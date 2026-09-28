import Foundation
import SwiftUI

/// Owns the cards and persists them, to iCloud Drive when it is available and
/// to Application Support otherwise, so a companion Mac app can share the same
/// data.
///
/// An undated card sits in exactly the bucket it was put in. A dated one is
/// ordered by its dates but never moved by them, and
/// until then the date only reorders it within its bucket.
@MainActor
final class TodoStore: ObservableObject {
    @Published private(set) var items: [TodoItem] = []
    /// The categories the user has defined, in the order they appear.
    @Published private(set) var categories: [CardCategory] = []
    /// Projects — a trip, a client, a paper — in the order they were created.
    @Published private(set) var projects: [Project] = []
    /// The category new cards start with, chosen in Settings.
    @Published private(set) var defaultCategoryID: UUID?
    private var defaultCategoryChangedAt: Date = .distantPast
    /// Set when the filing pass raised cards out of LATER, so the app can say
    /// so. Cleared by the view once it has been read.

    /// The result of the last sync anyone asked for, for the line under the
    /// button. Cleared when the sync file is given up.
    @Published private(set) var lastSync: SyncOutcome?

    struct SyncOutcome: Equatable {
        let at: Date
        let change: StoreDocument.Change
        let couldNotRead: Bool
    }
    private var pollTimer: Timer?
    private var lastSeenSyncDate: Date?
    /// The day the last filing pass ran for, so a window left open overnight can
    /// notice that the date underneath it has changed.
    private var lastFiledDay: Date = .distantPast
    private var dayTimer: Timer?
    private var dayObservers: [NSObjectProtocol] = []

    private let storage: DocumentStorage
    /// Tombstones, so a delete here is not undone by a device that still has it.
    private var deletedCards: [String: Date] = [:]
    private var deletedCategories: [String: Date] = [:]
    private var deletedProjects: [String: Date] = [:]

    init(storage: DocumentStorage = DocumentStorage()) {
        self.storage = storage
        load()
        // File dated cards before the first render. Doing this from onAppear
        // instead mutates the list mid-layout, and rows keep painting their old
        // stack colour even though they have already moved section.
        rescheduleNotifications()
        // Once a day, before anything can go wrong in this session.
        storage.rotateBackupsIfNeeded(current: document)
        startSyncing()
        beginDayWatch()
    }

    // MARK: - Grouping

    /// Cards for one section, in display order.
    ///
    /// In the four live buckets: anything dated today (or overdue) first, then
    /// anything dated tomorrow, then the rest — alphabetical within each tier,
    /// by the text as displayed. A project's name leads that text, so its cards
    /// sit together, exactly as they did when the code was typed into titles.
    /// COMPLETED is an archive instead: most recently completed on top.
    func items(in bucket: Bucket, now: Date = Date()) -> [TodoItem] {
        let matching = items.filter { $0.bucket == bucket }

        if bucket == .completed {
            return matching.sorted {
                ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt)
            }
        }

        let names = projectNames
        func sortText(_ card: TodoItem) -> String {
            guard let id = card.projectID, let name = names[id] else { return card.title }
            return name + " " + card.title
        }

        return matching.sorted { lhs, rhs in
            // A deadline orders a card; it never moves one. Cards carrying
            // one come first, soonest at the top; the undated keep the order
            // they always had.
            switch (Scheduler.sortKey(for: lhs), Scheduler.sortKey(for: rhs)) {
            case let (l?, r?) where l != r: return l < r
            case (.some, .none): return true
            case (.none, .some): return false
            default: break
            }
            return sortText(lhs).localizedStandardCompare(sortText(rhs)) == .orderedAscending
        }
    }

    // MARK: - Mutations

    /// Both extras are optional. With no date the card lands in INBOX; with a
    /// date of today or tomorrow the usual filing rule applies and it goes
    /// straight to that stack.
    /// New cards start on the default category unless the caller says otherwise.
    /// Pass `.some(nil)` to deliberately create an uncategorised card.
    func add(
        title: String,
        bucket: Bucket = .inbox,
        categoryID: UUID?? = nil,
        projectID: UUID? = nil,
        remindAt: Date? = nil,
        deadline: Date? = nil
    ) {
        addCard(
            title: title,
            bucket: bucket,
            categoryID: categoryID ?? defaultCategoryID,
            projectID: projectID,
            remindAt: remindAt,
            deadline: deadline
        )
    }

    private func addCard(title: String, bucket: Bucket, categoryID: UUID?, projectID: UUID?,
                         remindAt: Date?, deadline: Date?) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var card = TodoItem(title: trimmed, bucket: bucket, categoryID: categoryID, projectID: projectID)
        // Kept exactly as chosen. Neither date decides which stack a card
        // belongs in, so there is nothing for them to contradict. A deadline
        // without a reminder is dropped: it is the far end of a job with no
        // start, which the editor does not offer and nothing would read.
        card.remindAt = remindAt
        card.deadline = remindAt == nil ? nil : deadline.map { Scheduler.calendar.startOfDay(for: $0) }

        items.append(card)
        save()
    }

    func rename(_ item: TodoItem, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != item.title else { return }
        update(item) { card in card.title = trimmed }
    }

    /// Move a card to INBOX / TODAY / TOMORROW / LATER.
    func move(_ item: TodoItem, to bucket: Bucket) {
        update(item) { card in
            card.bucket = bucket
            card.bucketBeforeCompletion = nil
            card.completedAt = nil
            // Both dates survive the move. Nothing files a card any more, so a
            // date and a stack cannot contradict each other — a four-day job
            // sits in Today for four days and is still due on the fourth.
            //
            // But deciding where a card goes *is* an answer to the reminder
            // that asked. Without this a card could be dealt with and go on
            // asking, and the only way to stop it would be a separate sheet
            // whose whole job was to say "yes, I did that".
            //
            // Answered, not cleared: the date stays, so the card keeps its
            // red edge for the rest of the day. It is still today's work —
            // it just is not a question any more.
            if Reminders.isOutstanding(card) { card.reminderAnsweredAt = .stamp() }
        }
    }

    /// When the work must be done, for a job of more than a day. It is shown
    /// on the card and nothing else: the reminder is what colours an edge.
    func setDeadline(_ item: TodoItem, to date: Date) {
        update(item) { $0.deadline = Scheduler.calendar.startOfDay(for: date) }
    }

    /// When to pick the card up. Setting a time re-arms the reminder: an
    /// answer given to the previous one does not carry over to this.
    ///
    /// Clearing it leaves the deadline where it is. The job may still have a
    /// day it must be finished by, and setting a reminder again brings the
    /// field back with its value intact.
    func setReminder(_ item: TodoItem, at date: Date?) {
        update(item) { card in
            card.remindAt = date
            card.reminderAnsweredAt = nil
        }
        rescheduleNotifications()
    }

    /// Answer an outstanding reminder — the only thing that takes one off the
    /// list. A notification swiped away is how a notification is got rid of,
    /// not how a decision is made, and doing nothing is not an answer either:
    /// the reminder simply stays.
    func answerReminder(_ item: TodoItem, _ answer: ReminderAnswer) {
        update(item) { card in answer.apply(to: &card, now: .stamp()) }
        rescheduleNotifications()
    }



    // MARK: - The day turning underneath an open window

    /// Keep filing correct in a session that outlives the day it started in.
    ///
    /// Coming back to the app is already covered by the scene phase, but a
    /// window left open overnight — the common case on the Mac, and an iPhone
    /// left on the desk — would otherwise still be showing yesterday's stacks
    /// in the morning. Three things guard against that: the system's own
    /// day-changed notification, the significant-time-change notification that
    /// also covers a timezone or DST shift, and a slow poll as the backstop for
    /// a machine that was asleep when the day actually turned. All three land
    /// on the same idempotent check, so firing together costs nothing.
    private func beginDayWatch() {
        lastFiledDay = Scheduler.startOfToday()

        var names: [Notification.Name] = [.NSCalendarDayChanged]
        #if canImport(UIKit)
        names.append(UIApplication.significantTimeChangeNotification)
        #endif

        dayObservers = names.map { name in
            NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.refreshIfDayChanged() }
            }
        }

        dayTimer?.invalidate()
        dayTimer = Timer.scheduledTimer(withTimeInterval: Self.dayCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshIfDayChanged() }
        }
    }

    /// A quarter of an hour is far finer than the thing being watched for, and
    /// the check itself is a date comparison.
    private static let dayCheckInterval: TimeInterval = 15 * 60

    /// The day turning changes what the labels say and what colour an edge is
    /// — "Tomorrow" becomes "Today", an approaching reminder becomes due — so
    /// the list is nudged to redraw. Nothing moves; that is the point.
    func refreshIfDayChanged(now: Date = Date()) {
        guard Scheduler.startOfToday(now) != lastFiledDay else { return }
        lastFiledDay = Scheduler.startOfToday(now)
        withAnimation { objectWillChange.send() }
    }

    func clearDeadline(_ item: TodoItem) {
        update(item) { $0.deadline = nil }
    }

    /// Label a card, or pass `nil` to clear it. Never changes its stack.
    func setCategory(_ item: TodoItem, to categoryID: UUID?) {
        update(item) { card in card.categoryID = categoryID }
    }

    // MARK: - Categories

    func category(for item: TodoItem) -> CardCategory? {
        guard let id = item.categoryID else { return nil }
        return categories.first { $0.id == id }
    }

    func addCategory(label: String, symbolName: String, color: CategoryColor) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        categories.append(
            CardCategory(label: trimmed, symbolName: symbolName, color: color)
        )
        save()
    }

    func updateCategory(_ category: CardCategory) {
        guard let index = categories.firstIndex(where: { $0.id == category.id }) else { return }
        let trimmed = category.label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        categories[index] = CardCategory(
            id: category.id,
            label: trimmed,
            symbolName: category.symbolName,
            color: category.color,
            modifiedAt: .stamp()
        )
        save()
    }

    /// Removing a category also strips it from every card that used it — the
    /// cards themselves are never deleted.
    func deleteCategory(_ category: CardCategory) {
        categories.removeAll { $0.id == category.id }
        deletedCategories[category.id.uuidString] = .stamp()
        if defaultCategoryID == category.id {
            defaultCategoryID = nil
            defaultCategoryChangedAt = .stamp()
        }
        for index in items.indices where items[index].categoryID == category.id {
            items[index].categoryID = nil
            items[index].modifiedAt = .stamp()
        }
        for index in projects.indices where projects[index].categoryID == category.id {
            projects[index].categoryID = nil
            projects[index].modifiedAt = .stamp()
        }
        save()
    }

    func moveCategories(from source: IndexSet, to destination: Int) {
        categories.move(fromOffsets: source, toOffset: destination)
        for index in categories.indices { categories[index].modifiedAt = .stamp() }
        save()
    }

    /// Choose which category new cards start with; `nil` means none.
    func setDefaultCategory(_ id: UUID?) {
        defaultCategoryID = id
        defaultCategoryChangedAt = .stamp()
        save()
    }

    /// How many cards currently carry a category, for the delete confirmation.
    func cardCount(using category: CardCategory) -> Int {
        items.filter { $0.categoryID == category.id }.count
    }

    // MARK: - Reminders

    /// Make the pending notifications match the cards: one per armed reminder
    /// in the future, none for anything completed, deleted, disabled or past.
    ///
    /// Called after every change that could affect them rather than trying to
    /// patch individual notifications — the set is small, and a schedule that
    /// has drifted from the cards is the kind of bug nobody notices until a
    /// reminder fires for a card that was finished last week.
    func rescheduleNotifications() {
        ReminderScheduler.shared.sync(to: Reminders.scheduled(in: items),
                                      waiting: Reminders.outstanding(in: items).count)
    }

    // MARK: - Projects

    func project(for item: TodoItem) -> Project? {
        guard let id = item.projectID else { return nil }
        return projects.first { $0.id == id }
    }

    func project(id: UUID) -> Project? { projects.first { $0.id == id } }

    /// An existing project with this name, ignoring case and a leading `#`.
    func project(named name: String) -> Project? {
        let key = Project.key(for: name)
        guard !key.isEmpty else { return nil }
        return projects.first { $0.key == key }
    }

    private var projectNames: [UUID: String] {
        Dictionary(projects.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    /// When a card was last created in each project — the best guess at which
    /// one is typed next. Creation rather than last edit, because edits that are
    /// not about the project (completing, converting, merging) would otherwise
    /// reshuffle the suggestions. Derived rather than stored, so ranking never
    /// has to be synced.
    var projectLastUsed: [UUID: Date] {
        var result: [UUID: Date] = [:]
        for card in items {
            guard let id = card.projectID else { continue }
            result[id] = max(result[id] ?? .distantPast, card.createdAt)
        }
        return result
    }

    /// Cards not yet done, per project.
    var openCardCounts: [UUID: Int] { FilterCounts.byProject(items) }

    /// The same, per category, so both kinds of filter row read alike.
    var openCategoryCounts: [UUID: Int] { FilterCounts.byCategory(items) }

    func cardCount(using project: Project) -> Int {
        items.filter { $0.projectID == project.id }.count
    }

    /// The project with this name, created if it does not exist yet. Typing an
    /// archived project's name brings it back — a course running again.
    @discardableResult
    func ensureProject(named raw: String, categoryID: UUID?) -> Project? {
        let name = Project.clean(raw)
        guard !name.isEmpty else { return nil }

        if let index = projects.firstIndex(where: { $0.key == Project.key(for: name) }) {
            if projects[index].isArchived {
                projects[index].isArchived = false
                projects[index].modifiedAt = .stamp()
                save()
            }
            return projects[index]
        }
        let project = Project(name: name, categoryID: categoryID)
        projects.append(project)
        save()
        return project
    }

    /// Give a card a project, or pass `nil` to take it away. The project's
    /// category comes with it; the card can be recategorised afterwards.
    func setProject(_ item: TodoItem, to projectID: UUID?) {
        let category = projectID.flatMap { id in projects.first { $0.id == id } }?.categoryID
        update(item) { card in
            card.projectID = projectID
            if let category { card.categoryID = category }
        }
    }

    enum ProjectRename: Equatable {
        case renamed
        case unchanged
        case invalid
        /// The new name belongs to another project: renaming would really be a
        /// merge, which the caller must confirm.
        case collides(Project)
    }

    func renameProject(_ project: Project, to raw: String) -> ProjectRename {
        let name = Project.clean(raw)
        guard !name.isEmpty else { return .invalid }
        if let other = projects.first(where: { $0.key == Project.key(for: name) && $0.id != project.id }) {
            return .collides(other)
        }
        guard name != project.name else { return .unchanged }
        updateProject(project.id) { $0.name = name }
        return .renamed
    }

    /// Moving a project to another category takes it out of its group: groups
    /// belong to a category, and a grant must not turn up as "Grants" under
    /// Teaching.
    /// Moving a project to another category takes its cards with it. A real
    /// edit on each one, so it is stamped and syncs — unlike a derived change,
    /// which must never bump `modifiedAt`.
    @discardableResult
    func setProjectCategory(_ project: Project, to categoryID: UUID?) -> Int {
        let moving = ProjectCategory.cardsToRefile(project, to: categoryID, in: items)
        if !moving.isEmpty {
            let stamp = Date.stamp()
            let ids = Set(moving.map(\.id))
            for index in items.indices where ids.contains(items[index].id) {
                items[index].categoryID = categoryID
                items[index].modifiedAt = stamp
            }
        }
        updateProject(project.id) { edited in
            if edited.categoryID != categoryID { edited.group = nil }
            edited.categoryID = categoryID
        }
        return moving.count
    }

    // MARK: Groups

    func groupNames(in categoryID: UUID?) -> [String] {
        ProjectGroups.names(in: categoryID, projects: projects)
    }

    /// Put a project in a group, or pass nil to take it out. A label already in
    /// use in that category keeps its existing spelling.
    func setProjectGroup(_ project: Project, to label: String?) {
        let group = label.flatMap(Project.cleanGroup).map { typed in
            ProjectGroups.existingName(for: typed, in: project.categoryID, projects: projects) ?? typed
        }
        guard group != project.group else { return }
        updateProject(project.id) { $0.group = group }
    }

    /// Rename a group: the new label is written on each of its projects. Renaming
    /// it to another group's name joins the two, which is what that means.
    func renameGroup(_ name: String, in categoryID: UUID?, to newName: String) {
        guard let cleaned = Project.cleanGroup(newName) else { return }
        let key = Project.groupKey(for: name)
        let target = ProjectGroups.existingName(for: cleaned, in: categoryID, projects: projects
            .filter { $0.group.map(Project.groupKey) != key }) ?? cleaned
        let stamp = Date.stamp()
        var changed = false
        for index in projects.indices
        where projects[index].categoryID == categoryID
            && projects[index].group.map(Project.groupKey) == key
            && projects[index].group != target {
            projects[index].group = target
            projects[index].modifiedAt = stamp
            changed = true
        }
        if changed { save() }
    }

    func setProjectArchived(_ project: Project, _ archived: Bool) {
        updateProject(project.id) { $0.isArchived = archived }
    }

    /// What archiving would have to finish first.
    func openCards(in project: Project) -> [TodoItem] {
        Archiving.openCards(of: project, in: items)
    }

    /// Tick off everything still open in a project, as one edit, and put the
    /// project away. A real edit on every card, so it is stamped and syncs.
    func completeAllAndArchive(_ project: Project) {
        let stamp = Date.stamp()
        for index in items.indices
        where items[index].projectID == project.id && !items[index].isCompleted {
            items[index].bucketBeforeCompletion = items[index].bucket
            items[index].bucket = .completed
            items[index].completedAt = stamp
            items[index].modifiedAt = stamp
        }
        setProjectArchived(project, true)
    }

    /// Fold one project into another: its cards move across, and it goes.
    func mergeProject(_ source: Project, into target: Project) {
        guard source.id != target.id else { return }
        let stamp = Date.stamp()
        for index in items.indices where items[index].projectID == source.id {
            items[index].projectID = target.id
            items[index].modifiedAt = stamp
        }
        projects.removeAll { $0.id == source.id }
        deletedProjects[source.id.uuidString] = stamp
        save()
    }

    /// Remove a project. Its cards stay, and simply no longer carry it.
    func deleteProject(_ project: Project) {
        let stamp = Date.stamp()
        for index in items.indices where items[index].projectID == project.id {
            items[index].projectID = nil
            items[index].modifiedAt = stamp
        }
        projects.removeAll { $0.id == project.id }
        deletedProjects[project.id.uuidString] = stamp
        save()
    }

    private func updateProject(_ id: UUID, _ change: (inout Project) -> Void) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        change(&projects[index])
        projects[index].modifiedAt = .stamp()
        save()
    }

    /// One conversion choice: these cards get this project, and lose the word
    /// from the start of their titles.
    struct ProjectAssignment {
        var cardIDs: [UUID]
        var projectName: String
    }

    /// Turn title prefixes into projects, for cards written before projects
    /// existed. Each new project takes the category most of its cards have.
    @discardableResult
    func convertTitlePrefixes(_ assignments: [ProjectAssignment]) -> Int {
        var converted = 0
        let stamp = Date.stamp()

        for assignment in assignments {
            let indices = items.indices.filter { assignment.cardIDs.contains(items[$0].id) }
            guard !indices.isEmpty else { continue }

            let categoryVotes = indices.compactMap { items[$0].categoryID }
            let likeliest = Dictionary(grouping: categoryVotes, by: { $0 })
                .max { $0.value.count < $1.value.count }?.key

            let existed = project(named: assignment.projectName) != nil
            guard let project = ensureProject(named: assignment.projectName, categoryID: likeliest) else { continue }
            if !existed, project.categoryID == nil, let likeliest {
                setProjectCategory(project, to: likeliest)
            }

            for index in indices {
                guard items[index].projectID == nil,
                      let (_, rest) = ProjectConversion.split(items[index].title) else { continue }
                items[index].projectID = project.id
                items[index].title = rest
                items[index].modifiedAt = stamp
                converted += 1
            }
        }

        if converted > 0 { save() }
        return converted
    }

    func complete(_ item: TodoItem) {
        update(item) { card in
            guard card.bucket != .completed else { return }
            card.bucketBeforeCompletion = card.bucket
            card.bucket = .completed
            card.completedAt = .stamp()
        }
        // Finishing the work cancels the reminder about it, and takes it off
        // the review if it was already waiting there.
        rescheduleNotifications()
    }

    /// Send a completed card back where it came from.
    func uncomplete(_ item: TodoItem) {
        update(item) { card in
            guard card.bucket == .completed else { return }
            let origin = card.bucketBeforeCompletion ?? .inbox
            card.bucket = origin
            card.bucketBeforeCompletion = nil
            card.completedAt = nil
        }
    }

    func toggleCompleted(_ item: TodoItem) {
        item.isCompleted ? uncomplete(item) : complete(item)
    }

    func delete(_ item: TodoItem) {
        items.removeAll { $0.id == item.id }
        deletedCards[item.id.uuidString] = .stamp()
        save()
        rescheduleNotifications()
    }

    private func update(_ item: TodoItem, _ change: (inout TodoItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        change(&items[index])
        items[index].modifiedAt = .stamp()
        // Touched by the user, so it is their card now and survives the sweep.
        items[index].isSample = false
        save()
    }

    // MARK: - The shared sync file

    var syncFileName: String? { storage.syncFileName }

    /// Adopt a file the user picked. Whatever it already holds is merged in
    /// rather than replaced, so pointing a second device at an existing file
    /// brings both sides together instead of one flattening the other.
    @discardableResult
    func useSyncFile(at url: URL, replacingLocal: Bool = false) -> Bool {
        let existing = storage.adoptSyncFile(at: url)

        if let existing {
            discardSamples(given: existing)
            if replacingLocal {
                // Take the file wholesale. No tombstones for what is dropped:
                // these cards are being *abandoned*, not deleted, and marking
                // them deleted would propagate straight back and remove them
                // from the very file we are adopting.
                items.removeAll()
                deletedCards.removeAll()
                apply(existing)
            } else {
                apply(document.merged(with: existing))
            }
            rescheduleNotifications()
        }
        // Nothing readable there — a brand new file. Whatever is here seeds it.

        save()
        beginLiveSync()
        return storage.syncFileName != nil
    }

    /// Whether adopting a file would actually bring anything with it, so the UI
    /// can warn before replacing local cards with an empty one.
    func syncFileHasContent(at url: URL) -> Bool {
        storage.peekSyncFile(at: url)?.cards.isEmpty == false
    }

    // MARK: - Backups

    func availableBackups() -> [BackupFile] { storage.availableBackups() }

    /// A copy the user asked for, kept under today's date. Returns where it
    /// went, so the sheet can say something more useful than "done".
    @discardableResult
    func backUpNow(now: Date = Date()) -> URL? {
        storage.writeBackup(document, kind: .manual(now), now: now)
    }

    func deleteBackup(_ backup: BackupFile) { storage.deleteBackup(backup) }

    /// The name this device signs its backups with, shown so the user knows
    /// which of several files came from where.
    var backupDeviceName: String { storage.deviceName }

    /// Put the cards from a backup back.
    ///
    /// Restored cards are stamped as edited now, so they win over a stale copy
    /// on another device — including over a tombstone from the very delete being
    /// undone. Cards added since the backup are dropped locally but *not*
    /// tombstoned: they are not what the user asked to remove, and if the other
    /// device still has them they simply come back on the next sync.
    @discardableResult
    func restore(from file: BackupFile) -> Int {
        guard let backup = storage.readBackup(at: file.url) else { return 0 }

        var restored = backup.cards
        let stamp = Date.stamp()
        for index in restored.indices {
            restored[index].modifiedAt = stamp
            deletedCards.removeValue(forKey: restored[index].id.uuidString)
        }

        items = restored
        if !backup.categories.isEmpty { categories = backup.categories }
        if !backup.projects.isEmpty {
            let stamp = Date.stamp()
            projects = backup.projects.map { project in
                var project = project
                project.modifiedAt = stamp
                deletedProjects.removeValue(forKey: project.id.uuidString)
                return project
            }
        }
        rescheduleNotifications()
        save()
        return restored.count
    }

    /// Delete every card. Tombstoned, so the deletion reaches the other device
    /// instead of being undone by it.
    func deleteAllCards() {
        for card in items { deletedCards[card.id.uuidString] = .stamp() }
        items.removeAll()
        save()
    }

    var cardCount: Int { items.count }

    func stopUsingSyncFile() {
        lastSync = nil
        storage.stopUsingSyncFile()
        save()
    }

    /// Pull anything the other device wrote. Safe to call often.
    /// Records what happened, so Settings can say it. A sync that finds nothing
    /// is a real answer and gets recorded too — silence is what made the button
    /// feel broken.
    func refreshFromSyncFile() {
        lastSync = pullRemoteChanges()
    }

    // MARK: Live updates

    private static let pollInterval: TimeInterval = 4

    /// Start noticing the other device's writes while the app is in front: a
    /// file presenter for the immediate signal, and a cheap modification-date
    /// poll as a backstop, since presenters do not fire for every way a file
    /// can be replaced — iCloud swapping in a downloaded version among them.
    func beginLiveSync() {
        guard syncFileName != nil else { return }

        storage.startWatching { [weak self] in
            Task { @MainActor in self?.pullRemoteChanges() }
        }

        lastSeenSyncDate = storage.syncFileModifiedAt()
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollSyncFile() }
        }
    }

    func endLiveSync() {
        pollTimer?.invalidate()
        pollTimer = nil
        storage.stopWatching()
    }

    private func pollSyncFile() {
        guard let stamp = storage.syncFileModifiedAt() else { return }
        guard stamp != lastSeenSyncDate else { return }
        lastSeenSyncDate = stamp
        pullRemoteChanges()
    }

    /// The current document as bytes, for creating a new sync file.
    func documentData() -> Data {
        DocumentStorage.encodeDocument(document) ?? Data()
    }

    // MARK: - CSV

    func exportCSV() -> String {
        CardCSV.export(cards: items, categories: categories, projects: projects)
    }

    struct ImportSummary { var added = 0; var updated = 0; var skipped = 0; var removed = 0 }

    /// Merges imported cards in by id: a card the app already has is updated,
    /// anything else is added. Nothing is deleted, so an import can only ever
    /// add to what is here.
    @discardableResult
    func importCSV(_ text: String, replacingExisting: Bool = false) -> ImportSummary {
        let parsed = CardCSV.parse(text, categories: categories)
        var summary = ImportSummary(skipped: parsed.skipped)

        // Replacing with a file that turned out to hold no cards would wipe
        // everything and put nothing back, so refuse rather than obey.
        if replacingExisting && !parsed.cards.isEmpty {
            summary.removed = items.count
            for card in items { deletedCards[card.id.uuidString] = .stamp() }
            items.removeAll()
        }

        for var card in parsed.cards {
            // Named projects are matched, or created, and bring their category
            // to a card that did not name one.
            if let name = parsed.projectNames[card.id],
               let project = ensureProject(named: name, categoryID: card.categoryID) {
                card.projectID = project.id
                if card.categoryID == nil { card.categoryID = project.categoryID }
            }
            if let index = items.firstIndex(where: { $0.id == card.id }) {
                items[index] = card
                summary.updated += 1
            } else {
                items.append(card)
                summary.added += 1
            }
            // An imported card must not be resurrected-then-deleted by a stale
            // tombstone from an earlier delete of the same id.
            deletedCards.removeValue(forKey: card.id.uuidString)
        }

        // A group named in the file puts its project in that group. An empty
        // group column leaves the project where it is, so a file from before
        // groups never takes a project out of one.
        var regrouped = false
        for (projectKey, label) in parsed.projectGroups {
            guard let project = projects.first(where: { $0.key == projectKey }) else { continue }
            let before = project.group
            setProjectGroup(project, to: label)
            if self.project(id: project.id)?.group != before { regrouped = true }
        }

        if summary.added + summary.updated + summary.removed > 0 || regrouped {
            rescheduleNotifications()
            save()
        }
        return summary
    }

    // MARK: - Persistence and sync

    private func load() {
        if let document = storage.readLocal() {
            apply(document)
        } else {
            // A first run: arrive with a few cards that show what the app does.
            apply(StoreDocument.starter())
            save()
        }
    }

    /// Real cards from another device mean the sample ones have done their job.
    /// Dropped without tombstones: they were never anywhere else, and a
    /// tombstone would be a deletion to propagate rather than a tidy-up.
    private func discardSamples(given remote: StoreDocument) {
        guard !remote.cards.isEmpty, items.contains(where: { $0.isSample }) else { return }
        items.removeAll { $0.isSample }
        let used = Set(items.compactMap(\.projectID))
        projects.removeAll { !used.contains($0.id) && $0.name == "TRIP" }
    }

    private func apply(_ incoming: StoreDocument) {
        let document = incoming.canonicalizingProjects().promotingOrphanDeadlines()
        categories = document.categories.isEmpty ? CardCategory.defaults : document.categories
        items = document.cards
        deletedCards = document.deletedCards
        deletedCategories = document.deletedCategories
        projects = document.projects
        deletedProjects = document.deletedProjects
        defaultCategoryID = document.defaultCategoryID
        defaultCategoryChangedAt = document.defaultCategoryChangedAt
        // Never point at a category that is no longer there.
        if let id = defaultCategoryID, !categories.contains(where: { $0.id == id }) {
            defaultCategoryID = nil
        }
    }

    private var document: StoreDocument {
        StoreDocument(
            categories: categories,
            cards: items,
            deletedCards: deletedCards,
            deletedCategories: deletedCategories,
            projects: projects,
            deletedProjects: deletedProjects,
            defaultCategoryID: defaultCategoryID,
            defaultCategoryChangedAt: defaultCategoryChangedAt
        )
    }

    private func save() {
        storage.write(document)
        lastSeenSyncDate = storage.syncFileModifiedAt()
    }

    /// Look for the iCloud copy, fold it into what we already have, and keep
    /// listening for writes from another device.
    private func startSyncing() {
        storage.onRemoteChange = { [weak self] in
            Task { @MainActor in self?.pullRemoteChanges() }
        }

        storage.adoptCloudStorage { [weak self] remote in
            guard let self else { return }
            if let remote {
                discardSamples(given: remote)
                apply(document.merged(with: remote))
                rescheduleNotifications()
            }
            // Push whatever we have, so a first run seeds the cloud copy.
            save()
        }
    }

    @discardableResult
    private func pullRemoteChanges() -> SyncOutcome {
        guard let remote = storage.read() else {
            return SyncOutcome(at: Date(), change: .init(), couldNotRead: true)
        }
        // Reading back our own write is the common case; bailing out when the
        // file already matches is what keeps this from looping.
        guard remote != document else {
            return SyncOutcome(at: Date(), change: .init(), couldNotRead: false)
        }
        let before = document
        discardSamples(given: remote)
        apply(document.merged(with: remote))
        rescheduleNotifications()
        save()
        return SyncOutcome(at: Date(), change: document.change(from: before), couldNotRead: false)
    }
}
