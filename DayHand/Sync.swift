import Foundation

// MARK: - Dates on disk

/// Timestamps decide which device's edit wins, so they are written with
/// fractional seconds. Plain `.iso8601` rounds to whole seconds, which both
/// loses precision and means a save/load round-trip changes the data.
enum DocumentCoding {
    private static let precise: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let whole: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(precise.string(from: date))
        }
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            // Files written before this change have no fractional part.
            if let date = precise.date(from: text) ?? whole.date(from: text) {
                return date
            }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unreadable date: \(text)")
            )
        }
        return decoder
    }
}

// MARK: - The document

/// Everything the app persists, in one file.
///
/// Deletions are recorded as tombstones rather than simply vanishing. Without
/// them, deleting a card on the phone and then merging with a Mac that still
/// has it would silently resurrect the card.
struct StoreDocument: Codable, Equatable {
    var categories: [CardCategory] = []
    var cards: [TodoItem] = []
    /// Card id (as a string, so the JSON stays readable) -> when it was deleted.
    var deletedCards: [String: Date] = [:]
    var deletedCategories: [String: Date] = [:]
    var projects: [Project] = []
    var deletedProjects: [String: Date] = [:]
    /// The category new cards start with, or nil for none. Stored on the
    /// document rather than as a flag on each category, so two devices can never
    /// end up with two defaults.
    var defaultCategoryID: UUID?
    /// When that choice was last changed, so a merge can resolve it.
    var defaultCategoryChangedAt: Date = .distantPast

    static let empty = StoreDocument()

    /// What a merge actually did, so "Sync Now" can say so rather than looking
    /// identical whether it pulled in forty cards, found nothing, or failed.
    /// Counted here rather than in the view, so it can be tested.
    struct Change: Equatable {
        var arrived = 0
        var changed = 0
        var removed = 0

        var isNothing: Bool { arrived == 0 && changed == 0 && removed == 0 }
    }

    /// Cards only. Renaming a category is real, but "3 cards came in" is what
    /// someone pressing a sync button is asking about.
    func change(from previous: StoreDocument) -> Change {
        let before = Dictionary(previous.cards.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let after = Dictionary(cards.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var change = Change()
        for (id, card) in after {
            if let old = before[id] {
                if old != card { change.changed += 1 }
            } else {
                change.arrived += 1
            }
        }
        change.removed = before.keys.filter { after[$0] == nil }.count
        return change
    }

    init(
        categories: [CardCategory] = [],
        cards: [TodoItem] = [],
        deletedCards: [String: Date] = [:],
        deletedCategories: [String: Date] = [:],
        projects: [Project] = [],
        deletedProjects: [String: Date] = [:],
        defaultCategoryID: UUID? = nil,
        defaultCategoryChangedAt: Date = .distantPast
    ) {
        self.categories = categories
        self.cards = cards
        self.deletedCards = deletedCards
        self.deletedCategories = deletedCategories
        self.projects = projects
        self.deletedProjects = deletedProjects
        self.defaultCategoryID = defaultCategoryID
        self.defaultCategoryChangedAt = defaultCategoryChangedAt
    }

    /// Written by hand because the synthesised decoder demands every key even
    /// when the property has a default — so a document saved before tombstones
    /// existed would fail outright and take the user's cards with it.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        categories = try c.decodeIfPresent([CardCategory].self, forKey: .categories) ?? []
        cards = try c.decodeIfPresent([TodoItem].self, forKey: .cards) ?? []
        deletedCards = try c.decodeIfPresent([String: Date].self, forKey: .deletedCards) ?? [:]
        deletedCategories = try c.decodeIfPresent([String: Date].self, forKey: .deletedCategories) ?? [:]
        projects = try c.decodeIfPresent([Project].self, forKey: .projects) ?? []
        deletedProjects = try c.decodeIfPresent([String: Date].self, forKey: .deletedProjects) ?? [:]
        defaultCategoryID = try c.decodeIfPresent(UUID.self, forKey: .defaultCategoryID)
        defaultCategoryChangedAt =
            try c.decodeIfPresent(Date.self, forKey: .defaultCategoryChangedAt) ?? .distantPast
    }
}

// MARK: - Merging two copies

extension StoreDocument {
    /// Reconcile this copy with another, without needing to know which is
    /// "newer": every card and category is resolved independently by its own
    /// `modifiedAt`, and a deletion wins over an edit only if it happened after
    /// that edit.
    func merged(with other: StoreDocument) -> StoreDocument {
        var result = StoreDocument()

        result.deletedCards = StoreDocument.mergeTombstones(deletedCards, other.deletedCards)
        result.deletedCategories = StoreDocument.mergeTombstones(deletedCategories, other.deletedCategories)

        result.cards = StoreDocument.mergeItems(
            mine: cards, theirs: other.cards,
            id: { $0.id }, modified: { $0.modifiedAt },
            tombstones: result.deletedCards
        )
        result.categories = StoreDocument.mergeItems(
            mine: categories, theirs: other.categories,
            id: { $0.id }, modified: { $0.modifiedAt },
            tombstones: result.deletedCategories
        )

        result.deletedProjects = StoreDocument.mergeTombstones(deletedProjects, other.deletedProjects)
        result.projects = StoreDocument.mergeItems(
            mine: projects, theirs: other.projects,
            id: { $0.id }, modified: { $0.modifiedAt },
            tombstones: result.deletedProjects
        )

        // Whoever chose most recently wins, and a default pointing at a category
        // that no longer survives is dropped rather than left dangling.
        let newer = defaultCategoryChangedAt >= other.defaultCategoryChangedAt ? self : other
        result.defaultCategoryID = newer.defaultCategoryID
        result.defaultCategoryChangedAt = newer.defaultCategoryChangedAt
        if let id = result.defaultCategoryID, !result.categories.contains(where: { $0.id == id }) {
            result.defaultCategoryID = nil
        }

        return result
    }

    /// Fold several copies together. Order must not matter, because the copies
    /// arrive in whatever order the file system reports them.
    static func merging(_ documents: [StoreDocument]) -> StoreDocument {
        documents.reduce(StoreDocument.empty) { $0.merged(with: $1) }
    }

    private static func mergeTombstones(_ a: [String: Date], _ b: [String: Date]) -> [String: Date] {
        a.merging(b) { max($0, $1) }
    }

    /// Keeps whichever copy of each element was edited last, and drops anything
    /// whose tombstone is newer than its last edit. Local ordering is preserved,
    /// with elements only the other side knows about appended.
    private static func mergeItems<T>(
        mine: [T],
        theirs: [T],
        id: (T) -> UUID,
        modified: (T) -> Date,
        tombstones: [String: Date]
    ) -> [T] {
        var winners: [UUID: T] = [:]

        for element in mine + theirs {
            let key = id(element)
            if let existing = winners[key], modified(existing) >= modified(element) { continue }
            winners[key] = element
        }

        for (key, element) in winners {
            if let deletedAt = tombstones[key.uuidString], deletedAt >= modified(element) {
                winners.removeValue(forKey: key)
            }
        }

        var order = mine.map(id)
        order.append(contentsOf: theirs.map(id).filter { !order.contains($0) })

        return order.compactMap { winners[$0] }
    }
}

extension StoreDocument {
    /// What a brand-new install opens with: a few cards that explain the app by
    /// being it, rather than an empty screen and a manual.
    ///
    /// Every card is marked `isSample`. Editing one clears the mark, and the
    /// ones still untouched are swept away the first time real cards arrive
    /// from another device — so a second device set up months later does not
    /// push a handful of tutorial cards into the shared file.
    static func starter(now: Date = Date()) -> StoreDocument {
        let categories = CardCategory.defaults
        let home = categories[0].id, work = categories[1].id
        // Seeded, so `.distantPast` for the same reason as the categories: a
        // fresh install must never outrank a real edit made on another device.
        let trip = Project(name: String(localized: "TRIP", comment: "Seeded project on the sample card"),
                           categoryID: home, modifiedAt: .distantPast)

        func card(_ title: String, _ bucket: Bucket, category: UUID? = nil,
                  project: UUID? = nil, due: Date? = nil) -> TodoItem {
            var card = TodoItem(title: title, bucket: bucket, categoryID: category,
                                projectID: project, deadline: due)
            card.isSample = true
            return card
        }

        let calendar = Calendar.current
        let inAWeek = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now))

        var done = card(String(localized: "Read how this works", comment: "Starter card, already completed"), .completed, category: home)
        done.bucketBeforeCompletion = .today
        // Stamped, not `now`: the document stores milliseconds, and a raw Date
        // carries more, so saving and loading would alter what was just written.
        done.completedAt = .stamp()

        return StoreDocument(
            categories: categories,
            cards: [
                card(String(localized: "Tap a card to move it to another stack", comment: "Starter card"), .today, category: home),
                card(String(localized: "Swipe a card left to push it forward", comment: "Starter card"), .today, category: work),
                card(String(localized: "Swipe right to edit, or to set a date", comment: "Starter card"), .tomorrow, category: work),
                card(String(localized: "Nothing rolls over: cards stay where you put them", comment: "Starter card"), .tomorrow, category: home),
                card(String(localized: "book flights", comment: "Starter card, tagged TRIP"), .later, category: home, project: trip.id, due: inAWeek),
                card(String(localized: "Type # in a new task to tag it, as above", comment: "Starter card"), .inbox, category: home),
                done
            ],
            projects: [trip]
        )
    }

    var hasSampleCards: Bool { cards.contains { $0.isSample } }

    /// Drops the sample cards still untouched, and the starter project with
    /// them when nothing else uses it.
    func removingSampleCards() -> StoreDocument {
        guard hasSampleCards else { return self }
        var result = self
        result.cards.removeAll { $0.isSample }
        let used = Set(result.cards.compactMap(\.projectID))
        result.projects.removeAll { !used.contains($0.id) && $0.name == "TRIP" }
        return result
    }
}

extension StoreDocument {
    /// Two devices can each create the same project while apart — both typed
    /// #NEWCODE offline — and a merge then keeps both. Fold them into one,
    /// choosing the same survivor on every device so they agree without having
    /// to tell each other: the lowest id wins. Like filing, this is derived, so
    /// the cards moved across are not stamped as edited, and the loser's
    /// tombstone is dated at its own last edit so every device writes the same
    /// one.
    func canonicalizingProjects() -> StoreDocument {
        var survivors: [String: Project] = [:]
        for project in projects {
            if let current = survivors[project.key], current.id.uuidString <= project.id.uuidString { continue }
            survivors[project.key] = project
        }
        let losers = projects.filter { survivors[$0.key]?.id != $0.id }
        guard !losers.isEmpty else { return self }

        var result = self
        var remap: [UUID: UUID] = [:]
        for loser in losers { remap[loser.id] = survivors[loser.key]!.id }

        for index in result.cards.indices {
            if let id = result.cards[index].projectID, let target = remap[id] {
                result.cards[index].projectID = target
            }
        }
        for loser in losers {
            let key = loser.id.uuidString
            result.deletedProjects[key] = max(result.deletedProjects[key] ?? .distantPast, loser.modifiedAt)
        }
        result.projects.removeAll { remap[$0.id] != nil }
        return result
    }
}

extension StoreDocument {
    /// A card whose only date is a deadline had that date written by a version
    /// where a date meant one thing. It means the reminder now — the day to
    /// pick the card up — so move it there rather than leaving it as a finish
    /// line with no start, which is a date the app can do nothing with and the
    /// editor no longer offers.
    ///
    /// Nine in the morning, because the old date carried no time. Derived, so
    /// nothing is stamped as edited: every device computes the same thing from
    /// the same file.
    ///
    /// A reminder whose moment has already passed arrives answered. The card
    /// still shows red, which is the part worth seeing; what it must not do is
    /// drop a year of old dates into the review as a backlog of questions
    /// nobody asked.
    func promotingOrphanDeadlines(now: Date = Date(),
                                  calendar: Calendar = .current) -> StoreDocument {
        guard cards.contains(where: { $0.remindAt == nil && $0.deadline != nil }) else { return self }

        var result = self
        for index in result.cards.indices {
            guard result.cards[index].remindAt == nil,
                  let deadline = result.cards[index].deadline,
                  let at = calendar.date(bySettingHour: 9, minute: 0, second: 0,
                                         of: calendar.startOfDay(for: deadline))
            else { continue }
            result.cards[index].remindAt = at
            result.cards[index].deadline = nil
            if at <= now { result.cards[index].reminderAnsweredAt = at }
        }
        return result
    }
}

/// Watches the shared file and reports when something else writes to it —
/// the other device, or iCloud finishing a download.
private final class SyncFilePresenter: NSObject, NSFilePresenter {
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue.main
    private let onChange: () -> Void

    init(url: URL, onChange: @escaping () -> Void) {
        self.presentedItemURL = url
        self.onChange = onChange
        super.init()
    }

    func presentedItemDidChange() { onChange() }
    func presentedItemDidGain(_ version: NSFileVersion) { onChange() }
}

// MARK: - Where the file lives

/// Reads and writes the document: Application Support always, and the file the
/// user picked as well when there is one.
///
/// There is no iCloud *container* here, and no entitlement for one. Syncing is
/// a file the user chose, which the system happens to sync because they put it
/// in iCloud Drive — access granted by the choosing, not by the app claiming a
/// container. An earlier design did claim one, and the code for it survived
/// long after the entitlement was dropped: unreachable on both platforms,
/// quietly doing nothing, while looking from the outside like the thing that
/// noticed remote changes.
final class DocumentStorage {
    /// Called when the file changes underneath us: another device, or the Mac
    /// companion, has written to it.
    var onRemoteChange: (() -> Void)?

    private let localURL: URL

    /// A file the user picked themselves — typically inside iCloud Drive, so the
    /// system syncs it between devices. This needs no iCloud entitlement,
    /// because access is granted by the user choosing the file rather than by
    /// the app claiming a container.
    private var syncURL: URL?
    private var presenter: SyncFilePresenter?
    /// Set when a read folded in conflict copies, cleared once the merged
    /// result has been safely written back.
    private var pendingConflictURL: URL?
    private static let bookmarkKey = "syncFileBookmark"

    var syncFileName: String? { syncURL?.lastPathComponent }

    /// The picked file wins; without one, the local copy is all there is.
    private var activeURL: URL { syncURL ?? localURL }

    init() {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        localURL = directory.appendingPathComponent("cards.json")
        syncURL = DocumentStorage.resolveBookmark()
    }

    // MARK: - A file the user chose

    private static var bookmarkOptions: URL.BookmarkCreationOptions {
        #if targetEnvironment(macCatalyst)
        return [.withSecurityScope]
        #else
        return []
        #endif
    }

    private static var resolutionOptions: URL.BookmarkResolutionOptions {
        #if targetEnvironment(macCatalyst)
        return [.withSecurityScope]
        #else
        return []
        #endif
    }

    private static func resolveBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: resolutionOptions,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            // The file moved or was deleted; forget it rather than failing every
            // save from here on.
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            return nil
        }
        if stale, let refreshed = try? url.bookmarkData(options: bookmarkOptions) {
            UserDefaults.standard.set(refreshed, forKey: bookmarkKey)
        }
        return url
    }

    /// `URL` caches resource values on the instance, so re-reading a stored URL
    /// returns whatever it saw the first time. Anything that has to notice a
    /// file *changing* must ask for fresh values.
    private static func freshValues(_ url: URL, _ keys: Set<URLResourceKey>) -> URLResourceValues? {
        var probe = url
        probe.removeAllCachedResourceValues()
        return try? probe.resourceValues(forKeys: keys)
    }

    /// A file sitting in iCloud Drive may not be on this device yet — it can be
    /// a placeholder until something asks for it. Reading one without this
    /// returns nothing, which looks exactly like an empty file.
    private static func materialise(_ url: URL) {
        let values = freshValues(url, [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        guard values?.isUbiquitousItem == true else { return }
        if values?.ubiquitousItemDownloadingStatus == .current { return }

        try? FileManager.default.startDownloadingUbiquitousItem(at: url)

        // Give it a moment; if it is slow we still fall through and the next
        // read or foreground refresh picks it up.
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let status = freshValues(url, [.ubiquitousItemDownloadingStatusKey])?
                .ubiquitousItemDownloadingStatus
            if status == .current { return }
            Thread.sleep(forTimeInterval: 0.15)
        }
    }

    // MARK: Conflicting copies

    /// iCloud does not merge simultaneous writes. It keeps one copy as the
    /// current file and parks the others as *unresolved conflict versions*.
    /// Reading only the current file therefore throws away whatever the other
    /// device wrote — the exact case two people editing at once produce.
    private static func conflictDocuments(at url: URL) -> [StoreDocument] {
        guard let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) else { return [] }
        return versions.compactMap { version in
            guard let data = try? Data(contentsOf: version.url) else { return nil }
            return decode(data)
        }
    }

    /// Only ever called once the merged result has been written back, so a
    /// failed write cannot lose the copy it came from.
    private static func markConflictsResolved(at url: URL) {
        guard let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) else { return }
        for version in versions { version.isResolved = true }
        try? NSFileVersion.removeOtherVersionsOfItem(at: url)
    }

    /// Read a candidate file without adopting it, so the caller can tell the
    /// user what replacing would cost.
    func peekSyncFile(at url: URL) -> StoreDocument? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        DocumentStorage.materialise(url)

        var found: StoreDocument?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
            if let data = try? Data(contentsOf: readURL) { found = DocumentStorage.decode(data) }
        }
        let conflicts = DocumentStorage.conflictDocuments(at: url)
        guard !conflicts.isEmpty else { return found }
        return StoreDocument.merging(([found].compactMap { $0 }) + conflicts)
    }

    /// Point the app at `url` from now on, and hand back whatever it already
    /// holds so the caller can merge rather than overwrite.
    func adoptSyncFile(at url: URL) -> StoreDocument? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        DocumentStorage.materialise(url)

        guard let data = try? url.bookmarkData(options: DocumentStorage.bookmarkOptions) else {
            return nil
        }
        UserDefaults.standard.set(data, forKey: DocumentStorage.bookmarkKey)
        syncURL = url

        var existing: StoreDocument?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
            if let contents = try? Data(contentsOf: readURL) {
                existing = DocumentStorage.decode(contents)
            }
        }

        let conflicts = DocumentStorage.conflictDocuments(at: url)
        guard !conflicts.isEmpty else { return existing }
        pendingConflictURL = url
        return StoreDocument.merging(([existing].compactMap { $0 }) + conflicts)
    }

    func stopUsingSyncFile() {
        stopWatching()
        UserDefaults.standard.removeObject(forKey: DocumentStorage.bookmarkKey)
        syncURL = nil
    }

    // MARK: Noticing the other device

    /// When the shared file last changed, so a caller can poll cheaply without
    /// reading and decoding it every time.
    func syncFileModifiedAt() -> Date? {
        guard let syncURL else { return nil }
        return withAccess(syncURL) { url in
            DocumentStorage.freshValues(url, [.contentModificationDateKey])?.contentModificationDate
        }
    }

    /// Report writes made by anything other than us. Safe to call repeatedly.
    func startWatching(onChange: @escaping () -> Void) {
        guard let syncURL else { return }
        guard presenter?.presentedItemURL != syncURL else { return }

        stopWatching()
        let watcher = SyncFilePresenter(url: syncURL, onChange: onChange)
        NSFileCoordinator.addFilePresenter(watcher)
        presenter = watcher
    }

    func stopWatching() {
        if let presenter { NSFileCoordinator.removeFilePresenter(presenter) }
        presenter = nil
    }

    /// Runs `body` with the picked file's sandbox access open, if there is one.
    private func withAccess<T>(_ url: URL, _ body: (URL) -> T) -> T {
        guard url == syncURL else { return body(url) }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return body(url)
    }

    // MARK: Local, synchronous — used for the very first paint

    func readLocal() -> StoreDocument? {
        guard let data = try? Data(contentsOf: localURL) else { return nil }
        return DocumentStorage.decode(data)
    }

    // MARK: Coordinated read / write of whichever copy is active

    func read() -> StoreDocument? {
        withAccess(activeURL) { target in
            var result: StoreDocument?
            DocumentStorage.materialise(target)

            var coordinationError: NSError?
            NSFileCoordinator().coordinate(readingItemAt: target, options: [], error: &coordinationError) { url in
                guard let data = try? Data(contentsOf: url) else { return }
                result = DocumentStorage.decode(data)
            }
            return result
        }
    }

    func write(_ document: StoreDocument) {
        guard let data = DocumentStorage.encode(document) else { return }

        // Always keep the local copy current too, so the app still works if the
        // picked file goes away or the user signs out of iCloud later.
        try? data.write(to: localURL, options: .atomic)

        if let target = syncURL {
            withAccess(target) { url in
                var coordinationError: NSError?
                NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { writeURL in
                    try? FileManager.default.createDirectory(
                        at: writeURL.deletingLastPathComponent(), withIntermediateDirectories: true
                    )
                    try? data.write(to: writeURL, options: .atomic)
                }

                if coordinationError == nil, pendingConflictURL == url {
                    DocumentStorage.markConflictsResolved(at: url)
                    pendingConflictURL = nil
                }
            }
        }
    }


    // MARK: Coding

    static func encodeDocument(_ document: StoreDocument) -> Data? { encode(document) }

    fileprivate static func decode(_ data: Data) -> StoreDocument? {
        let decoder = DocumentCoding.makeDecoder()

        if let document = try? decoder.decode(StoreDocument.self, from: data) {
            return document
        }
        // A file from before syncing: a bare array of cards.
        if let cards = try? decoder.decode([TodoItem].self, from: data) {
            return StoreDocument(categories: CardCategory.defaults, cards: cards)
        }
        return nil
    }

    private static func encode(_ document: StoreDocument) -> Data? {
        try? DocumentCoding.makeEncoder().encode(document)
    }
}

// MARK: - CSV import / export

/// A plain-text interchange format for the cards, so they can be moved in and
/// out of a spreadsheet — and, in a pinch, carried between devices by hand.
enum CardCSV {
    /// `project` and `group` come last so that files written before they existed
    /// still read correctly by position when they have no header row.
    /// `deadline` kept the old `due` column's place so a header-less export
    /// still reads by position, and `remind` goes last, as every new column
    /// does. An older export's `reminds` column is simply ignored: what it
    /// recorded no longer exists, and a reminder is silenced by clearing it.
    static let header = ["id", "title", "stack", "category", "deadline", "completed", "created",
                         "project", "group", "remind"]

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    private static let stampFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// A due column is rarely still in the format we wrote it. Opening the file
    /// in a spreadsheet and saving it rewrites dates in the user's locale, and
    /// hand-written files use whatever the author felt like. Only the first
    /// pattern is what this type exports; the rest are what comes back.
    private static let dayPatterns = [
        "yyyy-MM-dd",       // what we write
        "yyyy/MM/dd",
        "dd/MM/yyyy",
        "dd-MM-yyyy",
        "dd.MM.yyyy",
        "d MMM yyyy",
        "d MMMM yyyy",
        "MMM d, yyyy"
    ]

    private static let dayParsers: [DateFormatter] = dayPatterns.map { pattern in
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = pattern
        f.timeZone = .current
        return f
    }

    /// Falls back to the device's own short and medium styles, which is what a
    /// spreadsheet writes when it reformats a column.
    private static let localeParsers: [DateFormatter] = [DateFormatter.Style.short, .medium].map { style in
        let f = DateFormatter()
        f.locale = .current
        f.dateStyle = style
        f.timeStyle = .none
        f.timeZone = .current
        return f
    }

    /// Reads a due date written in any of the shapes above, or as a full
    /// timestamp. Returns the start of that day, as the rest of the app expects.
    static func parseDay(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        for parser in dayParsers + localeParsers {
            if let date = parser.date(from: trimmed) {
                return Calendar.current.startOfDay(for: date)
            }
        }
        // Someone put a full timestamp in the due column.
        if let stamp = stampFormatter.date(from: trimmed) {
            return Calendar.current.startOfDay(for: stamp)
        }
        return nil
    }

    // MARK: Writing

    static func export(cards: [TodoItem], categories: [CardCategory], projects: [Project] = []) -> String {
        let labels = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.label) })
        let names = Dictionary(projects.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let groups = Dictionary(projects.map { ($0.id, $0.group ?? "") }, uniquingKeysWith: { first, _ in first })

        var rows = [header.joined(separator: ",")]
        for card in cards {
            rows.append([
                card.id.uuidString,
                card.title,
                card.bucket.rawValue,
                card.categoryID.flatMap { labels[$0] } ?? "",
                card.deadline.map { dayFormatter.string(from: $0) } ?? "",
                card.completedAt.map { stampFormatter.string(from: $0) } ?? "",
                stampFormatter.string(from: card.createdAt),
                card.projectID.flatMap { names[$0] } ?? "",
                card.projectID.flatMap { groups[$0] } ?? "",
                card.remindAt.map { stampFormatter.string(from: $0) } ?? ""
            ].map(escape).joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    /// Quote anything containing a comma, quote or newline, doubling inner quotes.
    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: Reading

    struct ImportResult {
        var cards: [TodoItem] = []
        var skipped = 0
        /// Card id -> the project name it was given, from a project column or a
        /// `#CODE` at the start of its title. Resolved to projects by the store,
        /// which can create the ones that do not exist yet.
        var projectNames: [UUID: String] = [:]
        /// Project key -> the group the file puts it in. The first row naming a
        /// group for a project wins; a hand-edited file could disagree with itself.
        var projectGroups: [String: String] = [:]
    }

    /// Parses rows into cards. Categories are matched to existing ones by label,
    /// case-insensitively; an unknown one leaves the card uncategorised rather
    /// than inventing a category the user did not ask for.
    ///
    /// Columns are located by **header name**, not by position, so a file that
    /// has been reordered or trimmed in a spreadsheet still imports correctly.
    /// A file with no header falls back to this type's own column order.
    static func parse(_ text: String, categories: [CardCategory]) -> ImportResult {
        var rows = parseRows(text)
        guard !rows.isEmpty else { return ImportResult() }

        var columns = defaultColumns
        if let mapped = headerColumns(rows[0]) {
            columns = mapped
            rows.removeFirst()
        }

        let byLabel = Dictionary(
            categories.map { ($0.label.lowercased(), $0.id) },
            uniquingKeysWith: { first, _ in first }
        )

        var result = ImportResult()
        for row in rows {
            func field(_ name: String) -> String {
                guard let index = columns[name], index < row.count else { return "" }
                return row[index].trimmingCharacters(in: .whitespaces)
            }

            let title = field("title")
            guard !title.isEmpty else {
                if row.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                    result.skipped += 1
                }
                continue
            }

            // A title written as "#ABC1234 slides" carries its project, which
            // is how a list pasted from elsewhere would say it.
            var cardTitle = title
            var projectName = Project.clean(field("project"))
            if cardTitle.hasPrefix("#"), let (word, rest) = ProjectConversion.split(cardTitle) {
                if projectName.isEmpty { projectName = word }
                cardTitle = rest
            }

            var card = TodoItem(title: cardTitle)
            if let id = UUID(uuidString: field("id")) { card.id = id }
            if !projectName.isEmpty {
                result.projectNames[card.id] = projectName
                let key = Project.key(for: projectName)
                if result.projectGroups[key] == nil, let group = Project.cleanGroup(field("group")) {
                    result.projectGroups[key] = group
                }
            }
            card.bucket = Bucket(rawValue: field("stack").lowercased()) ?? .inbox
            card.categoryID = byLabel[field("category").lowercased()]
            card.deadline = parseDay(field("deadline"))
            card.remindAt = stampFormatter.date(from: field("remind")) ?? parseDay(field("remind"))
            card.completedAt = stampFormatter.date(from: field("completed"))
            if let created = stampFormatter.date(from: field("created")) { card.createdAt = created }

            // A completed timestamp and a non-completed stack contradict; the
            // stack column wins, since that is what the app reads.
            if card.bucket != .completed { card.completedAt = nil }
            card.modifiedAt = .stamp()

            result.cards.append(card)
        }
        return result
    }

    private static var defaultColumns: [String: Int] {
        Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1, $0) })
    }

    /// Names accepted for each column, so a file written by hand or by another
    /// tool still lands in the right places.
    private static let synonyms: [String: Set<String>] = [
        "id":        ["id", "uuid", "identifier"],
        "title":     ["title", "name", "task", "card", "todo"],
        "stack":     ["stack", "bucket", "list", "status", "column"],
        "project":   ["project", "hashtag", "subproject", "course"],
        "group":     ["group", "cluster", "project group", "tag group"],
        "category":  ["category", "label", "tag"],
        "deadline":  ["deadline", "due", "due date", "duedate", "date", "scheduled"],
        "remind":    ["remind", "reminder", "remind me", "remind at"],
        "completed": ["completed", "completed at", "completedat", "done", "done at"],
        "created":   ["created", "created at", "createdat", "added"]
    ]

    /// Returns a column map if this row looks like a header, else nil.
    private static func headerColumns(_ row: [String]) -> [String: Int]? {
        let cells = row.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        var columns: [String: Int] = [:]

        for (index, cell) in cells.enumerated() {
            for (key, names) in synonyms where names.contains(cell) {
                if columns[key] == nil { columns[key] = index }
            }
        }
        // Only treat it as a header if it names the one column we cannot do
        // without; otherwise it is data and the default order applies.
        return columns["title"] != nil ? columns : nil
    }

    /// Splits CSV text into rows of fields, honouring quoted fields that may
    /// themselves contain commas, quotes or line breaks.
    private static func parseRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character?

        func endField() { row.append(field); field = "" }
        func endRow() {
            endField()
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }

        while let character = pending ?? iterator.next() {
            pending = nil

            if inQuotes {
                if character == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
                continue
            }

            switch character {
            case "\"": inQuotes = true
            case ",":  endField()
            // Swift treats CRLF as a single Character, so it has to be matched
            // in its own right — it is neither "\n" nor "\r".
            case "\n", "\r\n", "\r": endRow()
            default:   field.append(character)
            }
        }

        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }
}

// MARK: - Backups

/// What a kept copy is.
///
/// Three rotating automatic ones — yesterday, the day before, and one from
/// about a week back — which covers "I broke it just now" and "I broke it a
/// while ago and only noticed today". Plus any number the user asked for.
enum BackupKind: Equatable, Hashable {
    case day
    case twoDays
    case week
    /// Asked for, on the day it was asked for. One per day: a second on the
    /// same day replaces the first, so pressing the button twice is not a way
    /// to fill the disk.
    case manual(Date)

    /// The three that rotate, oldest last.
    static let automatic: [BackupKind] = [.day, .twoDays, .week]

    var isManual: Bool {
        if case .manual = self { return true }
        return false
    }

    /// What goes in the filename. Fixed width for a date, which is what makes
    /// the name parseable again even though the date contains dashes too.
    var tag: String {
        switch self {
        case .day:     return "1day"
        case .twoDays: return "2day"
        case .week:    return "1week"
        case .manual(let date): return BackupKind.dayTag.string(from: date)
        }
    }

    static func kind(forTag tag: String) -> BackupKind? {
        switch tag {
        case "1day":  return .day
        case "2day":  return .twoDays
        case "1week": return .week
        default:      return dayTag.date(from: tag).map { .manual($0) }
        }
    }

    static let dayTag: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

/// What a backup file is called.
///
/// `DayHand-1day-Fatima-MacBook-Pro-9c3f.json`. The name carries everything,
/// because the point of a backup is to still make sense to someone who has
/// lost the app and is looking at a folder full of JSON — which device wrote
/// it, and which of that device's copies it is.
enum BackupFilename {
    static let prefix = "DayHand"
    static let suffix = ".json"

    static func make(kind: BackupKind, device: String) -> String {
        "\(prefix)-\(kind.tag)-\(device)\(suffix)"
    }

    static func parse(_ filename: String) -> (kind: BackupKind, device: String)? {
        guard filename.hasSuffix(suffix) else { return nil }
        var body = String(filename.dropLast(suffix.count))
        guard body.hasPrefix(prefix + "-") else { return nil }
        body.removeFirst(prefix.count + 1)

        // A date tag is exactly ten characters and holds dashes of its own, so
        // it is read by width rather than by splitting.
        for tag in ["1day", "2day", "1week"] where body.hasPrefix(tag + "-") {
            let device = String(body.dropFirst(tag.count + 1))
            guard !device.isEmpty, let kind = BackupKind.kind(forTag: tag) else { return nil }
            return (kind, device)
        }
        guard body.count > 11 else { return nil }
        let tag = String(body.prefix(10))
        guard body[body.index(body.startIndex, offsetBy: 10)] == "-",
              let kind = BackupKind.kind(forTag: tag) else { return nil }
        return (kind, String(body.dropFirst(11)))
    }

    /// A device name a filesystem, a mail attachment and a person can all
    /// cope with. The trailing id is what stops two phones that both call
    /// themselves "iPhone" from overwriting each other's copies.
    static func device(from raw: String, id: String) -> String {
        // Host names arrive Bonjour-style. ".local" is true of every device
        // that has one and so says nothing about which device this is.
        var raw = raw
        if raw.hasSuffix(".local") { raw.removeLast(6) }

        var cleaned = ""
        var lastWasDash = true
        for character in raw.prefix(40) {
            if character.isLetter || character.isNumber {
                cleaned.append(character)
                lastWasDash = false
            } else if !lastWasDash {
                cleaned.append("-")
                lastWasDash = true
            }
        }
        while cleaned.hasSuffix("-") { cleaned.removeLast() }
        return cleaned.isEmpty ? id : "\(cleaned)-\(id)"
    }
}

/// Which files a rotation should produce, given what is already on disk.
///
/// Separated from the writing so it can be tested: the store's own directories
/// are the user's real ones, and nothing here may go near them.
enum BackupRotation {
    struct Plan: Equatable {
        var ageTwoDaysToWeek = false
        var ageDayToTwoDays = false
        var writeDay = false
    }

    static func plan(day: Date?, twoDays: Date?, week: Date?,
                     now: Date, calendar: Calendar = .current) -> Plan {
        // One a day. The most recent copy's own timestamp is the record of
        // when that happened, so losing preferences cannot cause a second.
        if let day, calendar.isDate(day, inSameDayAs: now) { return Plan() }

        var plan = Plan()
        plan.writeDay = true
        plan.ageDayToTwoDays = day != nil
        // The weekly slot only takes over when it is genuinely a week behind,
        // otherwise it would just track the daily ones a day later.
        let weekAge = week.map { calendar.dateComponents([.day], from: $0, to: now).day ?? 0 }
        plan.ageTwoDaysToWeek = twoDays != nil && (weekAge == nil || weekAge! >= 7)
        return plan
    }
}

/// One backup found on disk.
struct BackupFile: Identifiable {
    let url: URL
    let kind: BackupKind
    /// Which device wrote it. Worth showing only when it was not this one —
    /// a backup copied in from elsewhere is the whole reason the name says.
    let device: String
    let takenAt: Date
    let cardCount: Int

    var id: String { url.lastPathComponent }
}

extension DocumentStorage {
    private static let installIDKey = "backupInstallID"
    private static let legacyDatesKey = "backupSlotDates"
    private static let legacyRotationKey = "backupLastRotation"

    var backupsDirectory: URL {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let backups = directory.appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        return backups
    }

    /// Four hex characters, made once and kept. Short enough to live in a
    /// filename without making it unreadable, and enough that two devices with
    /// the same name do not collide.
    var installID: String {
        if let existing = UserDefaults.standard.string(forKey: DocumentStorage.installIDKey) {
            return existing
        }
        let made = String(format: "%04x", Int.random(in: 0..<0x10000))
        UserDefaults.standard.set(made, forKey: DocumentStorage.installIDKey)
        return made
    }

    var deviceName: String {
        BackupFilename.device(from: ProcessInfo.processInfo.hostName, id: installID)
    }

    private func url(for kind: BackupKind) -> URL {
        backupsDirectory.appendingPathComponent(
            BackupFilename.make(kind: kind, device: deviceName))
    }

    private func takenAt(_ url: URL) -> Date? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]) else {
            return nil
        }
        return values.contentModificationDate
    }

    /// Copy, keeping the timestamp: when a copy was *taken* is the thing being
    /// aged down the chain, and a fresh mtime would restart its clock.
    private func age(_ from: BackupKind, to: BackupKind) {
        let manager = FileManager.default
        let source = url(for: from), target = url(for: to)
        guard manager.fileExists(atPath: source.path) else { return }
        let stamp = takenAt(source)
        try? manager.removeItem(at: target)
        try? manager.copyItem(at: source, to: target)
        if let stamp {
            try? manager.setAttributes([.modificationDate: stamp], ofItemAtPath: target.path)
        }
    }

    /// Take today's backup if one has not been taken yet, ageing the older
    /// ones down the chain first. Called once at launch; doing nothing is the
    /// normal outcome.
    func rotateBackupsIfNeeded(current: StoreDocument, now: Date = Date()) {
        adoptLegacyBackups()

        let plan = BackupRotation.plan(
            day: takenAt(url(for: .day)),
            twoDays: takenAt(url(for: .twoDays)),
            week: takenAt(url(for: .week)),
            now: now
        )
        guard plan.writeDay else { return }

        if plan.ageTwoDaysToWeek { age(.twoDays, to: .week) }
        if plan.ageDayToTwoDays { age(.day, to: .twoDays) }
        writeBackup(current, kind: .day, now: now)
    }

    /// A copy the user asked for, named for the day. Returns where it went.
    @discardableResult
    func writeBackup(_ document: StoreDocument, kind: BackupKind, now: Date = Date()) -> URL? {
        guard let data = DocumentStorage.encodeDocument(document) else { return nil }
        let target = url(for: kind)
        do {
            try data.write(to: target, options: .atomic)
            try? FileManager.default.setAttributes([.modificationDate: now],
                                                   ofItemAtPath: target.path)
            return target
        } catch {
            return nil
        }
    }

    /// Everything in the folder that parses as a backup — including one
    /// copied in from another device, which is the point of the name.
    func availableBackups() -> [BackupFile] {
        let manager = FileManager.default
        let names = (try? manager.contentsOfDirectory(atPath: backupsDirectory.path)) ?? []
        return names.compactMap { name -> BackupFile? in
            guard let (kind, device) = BackupFilename.parse(name) else { return nil }
            let url = backupsDirectory.appendingPathComponent(name)
            guard let document = readBackup(at: url) else { return nil }
            // A manual copy carries its day in its name; a rotating one is
            // dated by the file, which is the only record either way.
            let when: Date? = {
                if case .manual(let date) = kind { return date }
                return takenAt(url)
            }()
            guard let when else { return nil }
            return BackupFile(url: url, kind: kind, device: device,
                              takenAt: when, cardCount: document.cards.count)
        }
        .sorted { $0.takenAt > $1.takenAt }
    }

    func readBackup(at url: URL) -> StoreDocument? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return DocumentStorage.decode(data)
    }

    func deleteBackup(_ backup: BackupFile) {
        try? FileManager.default.removeItem(at: backup.url)
    }

    /// Rename the three fixed-name files an earlier version wrote, so nobody
    /// loses a copy by updating. Their dates lived in preferences; they live
    /// in the files now, which is one fewer thing that can go missing.
    private func adoptLegacyBackups() {
        let manager = FileManager.default
        let dates = (UserDefaults.standard.dictionary(forKey: DocumentStorage.legacyDatesKey)
                     as? [String: Date]) ?? [:]
        let old: [(String, BackupKind)] = [
            ("backup-previousDay.json", .day),
            ("backup-dayBefore.json", .twoDays),
            ("backup-lastWeek.json", .week)
        ]
        var found = false
        for (name, kind) in old {
            let source = backupsDirectory.appendingPathComponent(name)
            guard manager.fileExists(atPath: source.path) else { continue }
            found = true
            let target = url(for: kind)
            let key = ["backup-previousDay.json": "previousDay",
                       "backup-dayBefore.json": "dayBefore",
                       "backup-lastWeek.json": "lastWeek"][name] ?? ""
            // The file's own timestamp first. The old version tracked these
            // in preferences and copied files with their dates intact, so the
            // two agree on any real upgrade — but a file restored from a
            // device backup while preferences were not is exactly the case
            // this whole change is meant to survive, and then only the file
            // is telling the truth.
            let stamp = takenAt(source) ?? dates[key]
            try? manager.removeItem(at: target)
            try? manager.moveItem(at: source, to: target)
            if let stamp {
                try? manager.setAttributes([.modificationDate: stamp],
                                           ofItemAtPath: target.path)
            }
        }
        if found {
            UserDefaults.standard.removeObject(forKey: DocumentStorage.legacyDatesKey)
            UserDefaults.standard.removeObject(forKey: DocumentStorage.legacyRotationKey)
        }
    }
}
