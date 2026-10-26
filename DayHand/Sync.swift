import Foundation

// MARK: - One-time task imports (no platform dependencies)

struct TaskImportRecord: Identifiable, Equatable {
    var id: String
    var listID: String
    var title: String
    var notes = ""
    var dueDate: Date?
    var deadlineDate: Date?
    var createdAt: Date?
    var isCompleted = false
    var completedAt: Date?
    var isRecurring = false
}

struct TaskImportDestination: Equatable {
    var categoryID: UUID?
    var projectID: UUID?
    var newProjectName = ""
}

enum TaskImportFailure: LocalizedError {
    case changedDestination, conflictingProject, backup, save

    var errorDescription: String? {
        switch self {
        case .changedDestination:
            return String(localized: "An import destination changed. Go back and choose it again.")
        case .conflictingProject:
            return String(localized: "A project with that name already exists. Choose it explicitly or use another name.")
        case .backup:
            return String(localized: "A backup could not be saved. Nothing was imported.")
        case .save:
            return String(localized: "The imported tasks could not be saved. Nothing was imported.")
        }
    }
}

enum TaskImport {
    enum Source {
        case appleReminders, todoist
        var prefix: String { self == .appleReminders ? "apple-reminders:" : "todoist-csv:" }
    }
    struct Options {
        var destinations: [String: TaskImportDestination] = [:]
        var bucket: Bucket = .inbox
        var includeCompleted = false
        var importDates = true
        var excludedIDs: Set<String> = []
    }

    struct Plan {
        var document: StoreDocument
        var added = 0
        var duplicates = 0
        var skipped = 0
        var projectsCreated = 0
    }

    /// Recomputed against the live document on confirmation. Nothing in a
    /// preview can overwrite an edit made while its sheet was open.
    static func plan(records: [TaskImportRecord], options: Options,
                     document: StoreDocument, now: Date = .stamp(),
                     calendar: Calendar = .current, source: Source = .appleReminders) throws -> Plan {
        var result = Plan(document: document)
        var history = source == .appleReminders ? document.importedReminderIDs : document.importedTodoistIDs
        var resolved: [String: (UUID?, UUID?)] = [:]
        for record in records {
            guard let destination = options.destinations[record.listID] else { continue }
            guard !options.excludedIDs.contains(record.id), !record.isRecurring,
                  options.includeCompleted || !record.isCompleted,
                  !record.id.isEmpty,
                  !record.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { result.skipped += 1; continue }
            let key = source.prefix + record.id
            guard !history.contains(key) else {
                result.duplicates += 1
                continue
            }
            if resolved[record.listID] == nil {
                var categoryID = destination.categoryID
                var projectID = destination.projectID
                if let id = projectID {
                    guard let project = result.document.projects.first(where: { $0.id == id }),
                          !project.isArchived else { throw TaskImportFailure.changedDestination }
                    categoryID = project.categoryID
                } else if !destination.newProjectName.isEmpty {
                    let name = Project.canonicalName(destination.newProjectName)
                    guard !name.isEmpty else { throw TaskImportFailure.changedDestination }
                    if let project = result.document.projects.first(where: { $0.key == Project.key(for: name) }) {
                        // Two selected lists may intentionally share a *new*
                        // project. Existing projects require an explicit choice.
                        guard !document.projects.contains(where: { $0.id == project.id }),
                              project.categoryID == categoryID else { throw TaskImportFailure.conflictingProject }
                        projectID = project.id
                    } else {
                        let project = Project(name: name, categoryID: categoryID, modifiedAt: now)
                        result.document.projects.append(project)
                        projectID = project.id
                        result.projectsCreated += 1
                    }
                }
                if let id = categoryID, !document.categories.contains(where: { $0.id == id }) {
                    throw TaskImportFailure.changedDestination
                }
                resolved[record.listID] = (categoryID, projectID)
            }
            let (categoryID, projectID) = resolved[record.listID]!
            let bucket = options.bucket == .completed ? Bucket.inbox : options.bucket
            var card = TodoItem(title: record.title, bucket: record.isCompleted ? .completed : bucket,
                                categoryID: categoryID, projectID: projectID)
            card.notes = record.notes
            card.createdAt = record.createdAt ?? now
            card.modifiedAt = now
            if options.importDates, let date = record.dueDate {
                let at = Scheduler.reminderTime(on: date, calendar: calendar)
                card.remindAt = at
                if at <= now || record.isCompleted { card.reminderAnsweredAt = at }
            }
            if options.importDates, let deadline = record.deadlineDate {
                card.deadline = calendar.startOfDay(for: deadline)
            }
            if record.isCompleted {
                card.bucketBeforeCompletion = bucket
                // An unknown completion date is not a completion today.
                card.completedAt = record.completedAt
            }
            // When it arrived in the stack it sits in. The field defaults to the
            // moment of import, which would have every task in a four-year-old
            // backlog report that it had just arrived — and the helpers this
            // field exists for would find nothing sitting still. The best bound
            // a source gives is when the task was made, or, for one already
            // done, when it was finished. Both are the same fallback the
            // decoder and the CSV use for a value they do not have.
            card.enteredStackAt = (record.isCompleted ? record.completedAt : nil) ?? card.createdAt
            result.document.cards.append(card)
            history.insert(key)
            result.added += 1
        }
        if source == .appleReminders { result.document.importedReminderIDs = history }
        else { result.document.importedTodoistIDs = history }
        return result
    }

    /// EventKit can give date-only or floating components. Interpreting a
    /// date-only value in UTC shifts it to the previous day in some regions.
    static func date(from components: DateComponents?, calendar: Calendar = .current) -> Date? {
        guard var components, components.year != nil, components.month != nil,
              components.day != nil else { return nil }
        var source = components.calendar ?? Calendar(identifier: .gregorian)
        source.timeZone = components.timeZone ?? calendar.timeZone
        components.calendar = source
        return source.date(from: components)
    }
}

// MARK: - Todoist project CSV

enum TodoistCSV {
    enum Failure: LocalizedError {
        case format, encoding, size
        var errorDescription: String? {
            switch self {
            case .format: return String(localized: "This is not a valid Todoist project CSV. Export a project from Todoist and choose its CSV file.")
            case .encoding: return String(localized: "The CSV file must use UTF-8 text encoding.")
            case .size: return String(localized: "Choose CSV files smaller than 20 MB each.")
            }
        }
    }

    struct File: Identifiable {
        var id: String
        var name: String
        var records: [TaskImportRecord]
        var unparsedDateIDs: Set<String>
        var ignoredRows: Int
    }

    static func plan(files: [File], options: TaskImport.Options, includeUnparsedDates: Bool,
                     document: StoreDocument, now: Date = .stamp(),
                     calendar: Calendar = .current) throws -> TaskImport.Plan {
        var options = options
        if !includeUnparsedDates {
            for file in files { options.excludedIDs.formUnion(file.unparsedDateIDs) }
        }
        return try TaskImport.plan(records: files.flatMap(\.records), options: options,
                                   document: document, now: now, calendar: calendar, source: .todoist)
    }

    /// Only absolute, unambiguous dates are interpreted. Relative and recurring
    /// expressions cannot be safely anchored to the day the file was exported.
    static func date(_ raw: String, timeZone: String = "", calendar: Calendar = .current) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let zone: TimeZone
        if timeZone.isEmpty { zone = calendar.timeZone }
        else if let known = TimeZone(identifier: timeZone) { zone = known }
        else { return nil }
        let patterns = [
            ("^\\d{4}-\\d{2}-\\d{2}$", "yyyy-MM-dd"),
            ("^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}$", "yyyy-MM-dd HH:mm"),
            ("^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}$", "yyyy-MM-dd HH:mm:ss")
        ]
        for (pattern, format) in patterns where text.range(of: pattern, options: .regularExpression) != nil {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = zone
            formatter.dateFormat = format
            formatter.isLenient = false
            guard let date = formatter.date(from: text), formatter.string(from: date) == text else { return nil }
            return date
        }
        if text.range(of: "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(\\.\\d+)?(Z|[+-]\\d{2}:\\d{2})$",
                      options: .regularExpression) != nil {
            guard date(String(text.prefix(10)), calendar: calendar) != nil else { return nil }
            let f = ISO8601DateFormatter()
            f.formatOptions = text.contains(".") ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
            return f.date(from: text)
        }
        return nil
    }

    static func parse(_ text: String, fileID: String, name: String,
                      calendar: Calendar = .current) throws -> File {
        let rows = try csvRows(text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text)
        guard let header = rows.first else { throw Failure.format }
        let names = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
        guard Set(names).count == names.count, names.contains("TYPE"), names.contains("CONTENT") else { throw Failure.format }
        let columns = Dictionary(uniqueKeysWithValues: names.enumerated().map { ($1, $0) })
        var result = File(id: fileID, name: name, records: [], unparsedDateIDs: [], ignoredRows: 0)
        var section = ""
        var sectionDescription = ""
        var ancestors: [(level: Int, title: String)] = []
        var lastTask: Int?
        for (offset, row) in rows.dropFirst().enumerated() {
            if row.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { continue }
            guard row.count <= names.count else { throw Failure.format }
            func raw(_ key: String) -> String {
                guard let index = columns[key], index < row.count else { return "" }
                return row[index]
            }
            func field(_ key: String) -> String { raw(key).trimmingCharacters(in: .whitespacesAndNewlines) }
            func metadata(excluding excluded: Set<String>) -> String {
                names.filter { !excluded.contains($0) && !field($0).isEmpty }
                    .map { $0 + ": " + raw($0) }.joined(separator: "\n")
            }
            switch field("TYPE") {
            case "meta":
                lastTask = nil
            case "section":
                section = raw("CONTENT"); sectionDescription = raw("DESCRIPTION")
                ancestors = []; lastTask = nil
            case "note":
                guard let lastTask else { result.ignoredRows += 1; continue }
                let comment = [raw("CONTENT"), raw("DESCRIPTION"), metadata(excluding: ["TYPE", "CONTENT", "DESCRIPTION"])]
                    .filter { !$0.isEmpty }.joined(separator: "\n")
                if !comment.isEmpty {
                    result.records[lastTask].notes += "\n\n" + String(localized: "Comment") + ":\n" + comment
                }
            case "task":
                lastTask = nil
                let level = max(1, Int(field("INDENT")) ?? 1)
                while let last = ancestors.last, last.level >= level { ancestors.removeLast() }
                guard !field("CONTENT").isEmpty else { result.ignoredRows += 1; continue }
                var details = [raw("DESCRIPTION"), String(localized: "Source file") + ": " + name]
                if !section.isEmpty { details.append(String(localized: "Section") + ": " + section) }
                if !sectionDescription.isEmpty { details.append(sectionDescription) }
                if !ancestors.isEmpty { details.append(String(localized: "Parent task") + ": " + ancestors.map(\.title).joined(separator: " › ")) }
                details.append(metadata(excluding: ["TYPE", "CONTENT", "DESCRIPTION"]))
                let scheduled = date(field("DATE"), timeZone: field("TIMEZONE"), calendar: calendar)
                // Deadlines are civil days, not instants in the task's time zone.
                let deadline = date(field("DEADLINE"), calendar: calendar)
                let id = fileID + ":" + String(offset + 2)
                if (!field("DATE").isEmpty && scheduled == nil) || (!field("DEADLINE").isEmpty && deadline == nil) {
                    result.unparsedDateIDs.insert(id)
                }
                result.records.append(TaskImportRecord(id: id, listID: fileID, title: raw("CONTENT"),
                    notes: details.filter { !$0.isEmpty }.joined(separator: "\n\n"), dueDate: scheduled, deadlineDate: deadline))
                ancestors.append((level, raw("CONTENT")))
                lastTask = result.records.count - 1
            default:
                result.ignoredRows += 1
                lastTask = nil; ancestors = []
            }
        }
        return result
    }

    /// Strict quoting avoids silently rearranging a malformed export's tasks
    /// or attaching comments to the wrong parent. Fields may span lines.
    private static func csvRows(_ text: String) throws -> [[String]] {
        var result: [[String]] = [], row: [String] = []
        var field = "", quoted = false, closed = false
        var chars = text.makeIterator()
        var pending: Character?
        func endField() { row.append(field); field = ""; closed = false }
        func endRow() { endField(); result.append(row); row = [] }
        while let char = pending ?? chars.next() {
            pending = nil
            if quoted {
                if char == "\"" {
                    if let next = chars.next() {
                        if next == "\"" { field.append("\"") }
                        else { quoted = false; closed = true; pending = next }
                    } else { quoted = false; closed = true }
                } else { field.append(char) }
                continue
            }
            if closed && char != "," && char != "\n" && char != "\r" && char != "\r\n" { throw Failure.format }
            switch char {
            case "\"":
                guard field.isEmpty else { throw Failure.format }
                quoted = true
            case ",": endField()
            case "\n", "\r", "\r\n": endRow()
            default: field.append(char)
            }
        }
        guard !quoted else { throw Failure.format }
        if closed || !field.isEmpty || !row.isEmpty { endRow() }
        return result
    }
}

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

    /// Reads the one stamp shape this app writes, without a formatter.
    ///
    /// `ISO8601DateFormatter.date(from:)` costs about 70µs a call, and a task
    /// carries up to five dates, so at ten thousand tasks parsing them was
    /// around 1.75s of a 1.9s load — and that load is not only the launch: a
    /// write from another device decodes the whole file again, on the main
    /// thread. Reading the bytes at fixed offsets instead is some forty times
    /// faster and turns the whole question of file size back into a
    /// non-question for years.
    ///
    /// It is a fast path, never the only one. Anything that is not exactly
    /// `2026-09-26T09:15:00.123Z` or `2026-09-26T09:15:00Z` — an offset
    /// instead of Z, a different width, a month of 13 — returns nil and the
    /// formatters answer it as before.
    ///
    /// The day of the month is deliberately **not** checked. Foundation reads
    /// 30 February as 2 March rather than refusing it, and this has to agree
    /// with Foundation rather than be stricter than it: the arithmetic below
    /// rolls over the same way. `Tests/main.swift` compares the two across
    /// every month and every day from 1 to 31 for exactly this reason.
    static func stamp(from text: String) -> Date? {
        var u = [UInt8](); u.reserveCapacity(24)
        for b in text.utf8 { u.append(b); if u.count > 24 { return nil } }
        guard u.count == 20 || u.count == 24,
              u[4] == 45, u[7] == 45, u[10] == 84, u[13] == 58, u[16] == 58,
              u[u.count - 1] == 90
        else { return nil }
        if u.count == 24 && u[19] != 46 { return nil }

        func number(_ from: Int, _ to: Int) -> Int? {
            var value = 0
            for i in from..<to {
                let digit = Int(u[i]) &- 48
                guard digit >= 0, digit <= 9 else { return nil }
                value = value * 10 + digit
            }
            return value
        }
        guard let year = number(0, 4), let month = number(5, 7), let day = number(8, 10),
              let hour = number(11, 13), let minute = number(14, 16), let second = number(17, 19),
              // Only after the Gregorian reform. Foundation reads an older
              // date through the Julian cutover, so `0001-01-01` comes back
              // two days from where the arithmetic below would put it — and
              // that is not a curiosity, because `.distantPast` is what every
              // seeded row is stamped with and the encoder writes it as
              // exactly that. Before 1583 the formatter answers, as it always
              // did; nothing a user can enter lands there.
              year >= 1583,
              (1...12).contains(month), (1...31).contains(day),
              hour <= 23, minute <= 59, second <= 59
        else { return nil }
        var milli = 0
        if u.count == 24 {
            guard let value = number(20, 23) else { return nil }
            milli = value
        }

        // Days from civil (Howard Hinnant): no calendar, no table, and it
        // carries February and the leap rules by construction.
        let shifted = year - (month <= 2 ? 1 : 0)
        let era = (shifted >= 0 ? shifted : shifted - 399) / 400
        let yearOfEra = shifted - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        let days = era * 146_097 + dayOfEra - 719_468

        // Whole milliseconds, divided once — the same arithmetic as
        // `Date.stamp()`, which is what wrote the file. Adding
        // `milli / 1000` to a seconds-sized Double instead lands a bit away
        // from it often enough to break a save-and-load round trip, which is
        // how this was caught.
        let milliseconds = (days * 86_400 + hour * 3_600 + minute * 60 + second) * 1_000 + milli
        return Date(timeIntervalSince1970: Double(milliseconds) / 1000)
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = stamp(from: text) { return date }
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
/// What an undo puts back, exactly as it stood before the change.
///
/// Projects as well as tasks, because the changes worth undoing rarely touch
/// only one kind: moving a project to another category rewrites the project's
/// row *and* the category on every task carrying it, and the two have to come
/// back together or the undo leaves a project in one category with its tasks
/// in another.
struct Restoration: Equatable {
    var cards: [TodoItem] = []
    var projects: [Project] = []

    var isEmpty: Bool { cards.isEmpty && projects.isEmpty }
}

struct StoreDocument: Codable, Equatable {
    /// Local EventKit identifiers already imported. Survives deleting a task,
    /// so importing the same list again cannot resurrect it. These identifiers
    /// are device-local; importing on another device may produce duplicates.
    var importedReminderIDs: Set<String> = []
    /// Exact CSV file identity plus row, since Todoist project CSVs have no
    /// stable task ids. Edited or renamed exports may therefore duplicate tasks.
    var importedTodoistIDs: Set<String> = []
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

    /// Put a few tasks back exactly as they were.
    ///
    /// Every undoable change touches a handful of tasks and either edits them
    /// or removes them — nothing creates one — so the inverse is always the
    /// same shape: these tasks, as they used to be.
    ///
    /// Two things make it safe to sync, and both are easy to leave out:
    ///
    /// - The restored task is stamped **now**, not with the time it used to
    ///   carry. A deletion beats an edit only if it happened after it, so
    ///   putting a task back with its old timestamp would leave the tombstone
    ///   newer and the other device would delete it again.
    /// - Its **tombstone is dropped**. Keeping it would mean this device still
    ///   held a record saying the task was deleted, which the next merge would
    ///   hand to everyone else.
    func restoring(_ restoration: Restoration, now: Date = .stamp()) -> StoreDocument {
        var result = self
        for card in restoration.cards {
            var revived = card
            // Strictly after the tombstone, not merely at `now`. A merge gives
            // a tie to the deletion (`deletedAt >= modified`), so a task
            // deleted and put back inside the same millisecond would come back
            // here and stay dead everywhere else. Stamps carry milliseconds,
            // so one is the smallest step that settles it.
            let tombstone = result.deletedCards[card.id.uuidString]
            revived.modifiedAt = max(now, tombstone?.addingTimeInterval(0.001) ?? now)
            result.deletedCards.removeValue(forKey: card.id.uuidString)
            if let index = result.cards.firstIndex(where: { $0.id == card.id }) {
                result.cards[index] = revived
            } else {
                result.cards.append(revived)
            }
        }
        // The same three rules again, for the same reasons.
        for project in restoration.projects {
            var revived = project
            let tombstone = result.deletedProjects[project.id.uuidString]
            revived.modifiedAt = max(now, tombstone?.addingTimeInterval(0.001) ?? now)
            result.deletedProjects.removeValue(forKey: project.id.uuidString)
            if let index = result.projects.firstIndex(where: { $0.id == project.id }) {
                result.projects[index] = revived
            } else {
                result.projects.append(revived)
            }
        }
        return result
    }

    /// What a merge actually did, so "Sync Now" can say so rather than looking
    /// identical whether it pulled in forty cards, found nothing, or failed.
    /// Counted here rather than in the view, so it can be tested.
    struct Change: Equatable {
        var arrived = 0
        var changed = 0
        var removed = 0

        var isNothing: Bool { arrived == 0 && changed == 0 && removed == 0 }
    }

    /// Cards only. Renaming a category is real, but "3 tasks came in" is what
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
        importedReminderIDs = try c.decodeIfPresent(Set<String>.self, forKey: .importedReminderIDs) ?? []
        importedTodoistIDs = try c.decodeIfPresent(Set<String>.self, forKey: .importedTodoistIDs) ?? []
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
        result.importedReminderIDs = importedReminderIDs.union(other.importedReminderIDs)
        result.importedTodoistIDs = importedTodoistIDs.union(other.importedTodoistIDs)

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
        let trip = Project(name: String(localized: "TRIP", comment: "Seeded project on the sample task"),
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

        var done = card(String(localized: "Read how this works", comment: "Starter task, already completed"), .completed, category: home)
        done.bucketBeforeCompletion = .today
        // Stamped, not `now`: the document stores milliseconds, and a raw Date
        // carries more, so saving and loading would alter what was just written.
        done.completedAt = .stamp()

        return StoreDocument(
            categories: categories,
            cards: [
                card(String(localized: "Tap a task to move it to another stack", comment: "Starter task"), .today, category: home),
                card(String(localized: "Swipe a task left to push it forward", comment: "Starter task"), .today, category: work),
                card(String(localized: "Swipe right to edit, or to set a date", comment: "Starter task"), .tomorrow, category: work),
                card(String(localized: "Nothing rolls over: tasks stay where you put them", comment: "Starter task"), .tomorrow, category: home),
                card(String(localized: "book flights", comment: "Starter task, tagged TRIP"), .later, category: home, project: trip.id, due: inAWeek),
                card(String(localized: "Start a task with a code like BIO2140 to file it under one", comment: "Starter task"), .inbox, category: home),
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
    /// Only legacy cards need their lone date promoted. The version is marked
    /// even when no promotion is needed, so clearing a modern reminder or
    /// importing an explicit standalone deadline cannot trigger this again.
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
        guard cards.contains(where: { $0.dateSemanticsVersion == 0 }) else { return self }

        var result = self
        for index in result.cards.indices {
            guard result.cards[index].dateSemanticsVersion == 0 else { continue }
            result.cards[index].dateSemanticsVersion = 1
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

/// What an import did, in tasks. Categories and projects are created or changed
/// quietly: they are the structure the tasks arrive in, not what was asked for.
struct CSVImportSummary: Equatable {
    var added = 0
    var updated = 0
    var skipped = 0
    var removed = 0
}

extension StoreDocument {
    /// What a parsed CSV does to a document: categories, then projects, then
    /// tasks, each matched by id and then by name, so a file can be the whole of
    /// a document or a handful of rows typed into a spreadsheet.
    ///
    /// A pure function, on purpose. It is where the rules live — what is
    /// stamped, what is left alone, what a blank cell means — and the store is
    /// not something a test may construct, so it could not otherwise be tested.
    ///
    /// Nothing here deletes, except `replacing`, which replaces tasks and only
    /// tasks.
    ///
    /// **Only rows that actually changed are stamped.** Import is an edit, but a
    /// whole-file round trip is not an edit of every row in it. Stamping them
    /// all would let a stale file overwrite a newer change made on another
    /// device in the meantime, and would turn every sync after a restore into a
    /// rewrite of the whole document. A row identical to what is here is left
    /// exactly as it is, its `modifiedAt` included; a row that differs is
    /// stamped now, so a corrected file wins; a row that is new keeps the
    /// `modified` the file gives it, so a restore keeps its history.
    func importing(_ parsed: CardCSV.ImportResult, replacing: Bool = false,
                   now: Date = .stamp()) -> (document: StoreDocument, summary: CSVImportSummary) {
        var doc = self
        var summary = CSVImportSummary(skipped: parsed.skipped)

        // Replacing with a file that turned out to hold no cards would wipe
        // everything and put nothing back, so refuse rather than obey.
        if replacing && !parsed.cards.isEmpty {
            summary.removed = doc.cards.count
            for card in doc.cards { doc.deletedCards[card.id.uuidString] = now }
            doc.cards.removeAll()
        }

        // ---- categories
        for row in parsed.categories {
            if let index = doc.categories.firstIndex(where: { $0.id == row.id }) {
                var edited = doc.categories[index]
                // Not a rename when only the case differs: a hand-typed
                // "research" matched "Research" by label, and should not
                // rewrite it.
                if row.label.lowercased() != edited.label.lowercased() { edited.label = row.label }
                if let symbol = row.symbolName { edited.symbolName = symbol }
                if let color = row.color { edited.color = color }
                if edited != doc.categories[index] {
                    edited.modifiedAt = now
                    doc.categories[index] = edited
                }
            } else {
                doc.categories.append(CardCategory(
                    id: row.id,
                    label: row.label,
                    // Chosen here only when the file did not choose: a category
                    // made from a bare name still has to look like something.
                    symbolName: row.symbolName ?? "tag",
                    color: row.color ?? .indigo,
                    modifiedAt: row.modifiedAt ?? now
                ))
                doc.deletedCategories.removeValue(forKey: row.id.uuidString)
            }
        }
        if let id = parsed.categories.first(where: \.isDefault)?.id, id != doc.defaultCategoryID {
            doc.defaultCategoryID = id
            doc.defaultCategoryChangedAt = now
        }

        // ---- projects
        var declared = Set<String>()
        for row in parsed.projects {
            let key = Project.key(for: Project.clean(row.name))
            declared.insert(key)
            let group = row.group

            if let index = row.id.flatMap({ id in doc.projects.firstIndex { $0.id == id } })
                ?? doc.projects.firstIndex(where: { $0.key == key }) {
                var edited = doc.projects[index]
                let cleaned = Project.canonicalName(row.name)
                // A rename, but never onto a name another project already has —
                // that would be a merge, which is not something a spreadsheet
                // cell should be able to do.
                if !cleaned.isEmpty, cleaned != edited.name,
                   !doc.projects.contains(where: { $0.id != edited.id && $0.key == Project.key(for: cleaned) }) {
                    edited.name = cleaned
                }
                var refile = false
                if row.givesCategory, edited.categoryID != row.categoryID {
                    edited.categoryID = row.categoryID
                    edited.group = nil
                    refile = true
                }
                if let group {
                    edited.group = ProjectGroups.existingName(for: group, in: edited.categoryID,
                                                              projects: doc.projects) ?? group
                }
                if let archived = row.archived { edited.isArchived = archived }
                guard edited != doc.projects[index] else { continue }

                edited.modifiedAt = now
                doc.projects[index] = edited
                if refile {
                    // Moving a project takes its tasks, as everywhere else.
                    let ids = Set(ProjectCategory.cardsToRefile(edited, to: edited.categoryID, in: doc.cards).map(\.id))
                    for i in doc.cards.indices where ids.contains(doc.cards[i].id) {
                        doc.cards[i].categoryID = edited.categoryID
                        doc.cards[i].modifiedAt = now
                    }
                }
            } else {
                let name = Project.canonicalName(row.name)
                guard !name.isEmpty else { continue }
                doc.projects.append(Project(
                    id: row.id ?? UUID(),
                    name: name,
                    categoryID: row.categoryID,
                    isArchived: row.archived ?? false,
                    group: group.map { ProjectGroups.existingName(for: $0, in: row.categoryID, projects: doc.projects) ?? $0 },
                    modifiedAt: row.modifiedAt ?? now
                ))
                if let id = row.id { doc.deletedProjects.removeValue(forKey: id.uuidString) }
            }
        }

        // ---- tasks
        for var card in parsed.cards {
            let given = parsed.given[card.id] ?? []
            let index = doc.cards.firstIndex { $0.id == card.id }

            // Named projects are matched, or created, and bring their category
            // to a task that did not name one.
            if let name = parsed.projectNames[card.id] {
                let cleaned = Project.clean(name)
                let key = Project.key(for: cleaned)
                // A project the file describes keeps the state the file gives
                // it. Naming an archived project in a task brings it back, which
                // is right for typing a name and wrong for restoring a file.
                let stays = declared.contains(key) || parsed.projectArchived[key] != nil
                var project: Project?
                if let i = doc.projects.firstIndex(where: { $0.key == key }) {
                    if doc.projects[i].isArchived && !stays {
                        doc.projects[i].isArchived = false
                        doc.projects[i].modifiedAt = now
                    }
                    project = doc.projects[i]
                } else if !cleaned.isEmpty {
                    let made = Project(name: Project.canonicalName(cleaned), categoryID: card.categoryID, modifiedAt: now)
                    doc.projects.append(made)
                    project = made
                }
                card.projectID = project?.id
                if card.categoryID == nil, let category = project?.categoryID,
                   index == nil || given.contains("category") {
                    card.categoryID = category
                }
            }

            if let index {
                let existing = doc.cards[index]
                var merged = CardCSV.merged(existing, with: card, given: given)
                var compare = merged
                compare.modifiedAt = existing.modifiedAt
                if compare != existing {
                    merged.modifiedAt = now
                    // Touched by the user, so it is their task now.
                    merged.isSample = false
                    doc.cards[index] = merged
                    summary.updated += 1
                }
            } else {
                doc.cards.append(card)
                summary.added += 1
            }
            // An imported card must not be resurrected-then-deleted by a stale
            // tombstone from an earlier delete of the same id.
            doc.deletedCards.removeValue(forKey: card.id.uuidString)
        }

        // ---- older files
        // Files from before projects had rows of their own repeated these on
        // every task. They still apply — for any project the file does not
        // describe itself, which would otherwise be told twice.
        //
        // A group named in the file puts its project in that group. An empty
        // group column leaves the project where it is, so a file from before
        // groups never takes a project out of one.
        for (key, label) in parsed.projectGroups where !declared.contains(key) {
            guard let i = doc.projects.firstIndex(where: { $0.key == key }) else { continue }
            let group = ProjectGroups.existingName(for: label, in: doc.projects[i].categoryID,
                                                   projects: doc.projects) ?? label
            if doc.projects[i].group != group {
                doc.projects[i].group = group
                doc.projects[i].modifiedAt = now
            }
        }
        for (key, archived) in parsed.projectArchived where !declared.contains(key) {
            guard let i = doc.projects.firstIndex(where: { $0.key == key }),
                  doc.projects[i].isArchived != archived else { continue }
            doc.projects[i].isArchived = archived
            doc.projects[i].modifiedAt = now
        }
        return (doc, summary)
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

    @discardableResult
    func write(_ document: StoreDocument) -> Bool {
        guard let data = DocumentStorage.encode(document) else { return false }

        // Always keep the local copy current too, so the app still works if the
        // picked file goes away or the user signs out of iCloud later.
        do { try data.write(to: localURL, options: .atomic) }
        catch { return false }

        if let target = syncURL {
            withAccess(target) { url in
                var coordinationError: NSError?
                var didWrite = false
                NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { writeURL in
                    try? FileManager.default.createDirectory(
                        at: writeURL.deletingLastPathComponent(), withIntermediateDirectories: true
                    )
                    do {
                        try data.write(to: writeURL, options: .atomic)
                        didWrite = true
                    } catch { }
                }

                if didWrite, coordinationError == nil, pendingConflictURL == url {
                    DocumentStorage.markConflictsResolved(at: url)
                    pendingConflictURL = nil
                }
            }
        }
        return true
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
                         "project", "group", "remind", "notes", "entered",
                         "answered", "before", "archived",
                         "modified", "symbol", "color", "default", "type"]

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

    /// Everything in the document, one row per thing: categories, then projects,
    /// then tasks, each saying which it is in the `type` column.
    ///
    /// One wide table with empty cells where a column does not apply, rather
    /// than three files, because a CSV is one file and because a spreadsheet can
    /// filter on `type` to see any one kind alone. `title` carries a task's
    /// title, a project's name or a category's label — the column means "what it
    /// is called" in all three — and `category` is, for a task or a project, the
    /// category it belongs to.
    ///
    /// Categories and projects come first only because there are few of them
    /// and it makes the structure readable at the top of the sheet. Import does
    /// not depend on the order.
    static func export(cards: [TodoItem], categories: [CardCategory], projects: [Project] = [],
                       defaultCategoryID: UUID? = nil) -> String {
        let labels = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.label) })
        let names = Dictionary(projects.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })

        func line(_ values: [String: String]) -> String {
            header.map { escape(values[$0] ?? "") }.joined(separator: ",")
        }
        func stamp(_ date: Date?) -> String { date.map { stampFormatter.string(from: $0) } ?? "" }

        var rows = [header.joined(separator: ",")]

        for category in categories {
            rows.append(line([
                "type": "category",
                "id": category.id.uuidString,
                "title": category.label,
                "symbol": category.symbolName,
                "color": category.color.rawValue,
                // Written only for the one that is, so a blank stays silence.
                "default": category.id == defaultCategoryID ? "yes" : "",
                "modified": stamp(category.modifiedAt)
            ]))
        }
        for project in projects {
            rows.append(line([
                "type": "project",
                "id": project.id.uuidString,
                "title": project.name,
                "category": project.categoryID.flatMap { labels[$0] } ?? "",
                "group": project.group ?? "",
                // "yes" or "no" rather than blank, so that an empty cell can keep
                // meaning "the file says nothing" — which is what an export
                // from before this column reads as.
                "archived": project.isArchived ? "yes" : "no",
                "modified": stamp(project.modifiedAt)
            ]))
        }
        for card in cards {
            rows.append(line([
                "id": card.id.uuidString,
                "title": card.title,
                "stack": card.bucket.rawValue,
                "category": card.categoryID.flatMap { labels[$0] } ?? "",
                "deadline": card.deadline.map { dayFormatter.string(from: $0) } ?? "",
                "completed": stamp(card.completedAt),
                "created": stamp(card.createdAt),
                // Group and archived belong to the project, and are written on
                // its row. Repeating them here would give the same fact two
                // places to disagree.
                "project": card.projectID.flatMap { names[$0] } ?? "",
                "remind": stamp(card.remindAt),
                "notes": card.notes,
                "entered": stamp(card.enteredStackAt),
                "answered": stamp(card.reminderAnsweredAt),
                "before": card.bucketBeforeCompletion?.rawValue ?? "",
                "modified": stamp(card.modifiedAt)
            ]))
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

    /// A category row as the file describes it, with its identity already
    /// settled: the id of the category it matches here if there is one, otherwise
    /// the file's own, otherwise a fresh one.
    struct CategoryRow {
        var id: UUID
        var label: String
        var symbolName: String?
        var color: CategoryColor?
        var isDefault: Bool
        var modifiedAt: Date?
    }

    /// A project row. `givesCategory` is whether the file has a category column
    /// at all, since an empty cell there means "none" but no column means
    /// nothing was said.
    struct ProjectRow {
        var id: UUID?
        var name: String
        var categoryID: UUID?
        var givesCategory: Bool
        var group: String?
        var archived: Bool?
        var modifiedAt: Date?
    }

    struct ImportResult {
        var cards: [TodoItem] = []
        var categories: [CategoryRow] = []
        var projects: [ProjectRow] = []
        /// Task id -> the columns the file actually has something to say about
        /// for that row. An existing task is only changed in these, so a file
        /// with no `notes` column, or an unreadable date, leaves them alone
        /// rather than blanking them.
        var given: [UUID: Set<String>] = [:]
        var skipped = 0
        /// Card id -> the project name it was given, from a project column or a
        /// `#CODE` at the start of its title. Resolved to projects by the store,
        /// which can create the ones that do not exist yet.
        var projectNames: [UUID: String] = [:]
        /// Project key -> the group the file puts it in. The first row naming a
        /// group for a project wins; a hand-edited file could disagree with itself.
        var projectGroups: [String: String] = [:]
        /// Project key -> whether the file says it is archived. Absent when the
        /// column is missing or empty, which leaves the project as it is.
        var projectArchived: [String: Bool] = [:]
    }

    /// What a row in the file is. A blank type is a task, so every file written
    /// before there were kinds of row still reads as exactly what it was.
    enum RowKind { case task, project, category }

    private static func kind(of raw: String) -> RowKind? {
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "", "task", "card", "todo": return .task
        case "project": return .project
        case "category": return .category
        default: return nil
        }
    }

    private static func flag(_ raw: String) -> Bool? {
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "yes", "true", "1": return true
        case "no", "false", "0": return false
        default: return nil
        }
    }

    /// Columns where an empty cell means "clear this", as opposed to "the file
    /// says nothing". Everything else — the stack, the title, the timestamps —
    /// is left alone when blank, because a blank stack that moved a task to the
    /// inbox, or a blank `created` that made it brand new, would be a way for a
    /// half-filled spreadsheet to damage tasks it never meant to touch.
    private static let clearable: Set<String> = [
        "category", "deadline", "remind", "completed", "answered", "before", "notes", "project"
    ]

    /// Parses rows into categories, projects and tasks. Categories are matched to
    /// existing ones by id, then by label, case-insensitively; one the file
    /// declares and this device lacks is created by the store. A task naming a
    /// category nobody declared is left uncategorised rather than having one
    /// invented with an icon nobody chose.
    ///
    /// Columns are located by **header name**, not by position, so a file that
    /// has been reordered or trimmed in a spreadsheet still imports correctly.
    /// A file with no header falls back to this type's own column order.
    static func parse(_ text: String, categories: [CardCategory]) -> ImportResult {
        var rows = parseRows(text)
        guard !rows.isEmpty else { return ImportResult() }

        var columns = defaultColumns
        let legacyDate = !rows[0].contains { $0.trimmingCharacters(in: .whitespaces).lowercased() == "deadline" }
        if let mapped = headerColumns(rows[0]) {
            columns = mapped
            rows.removeFirst()
        }

        func field(_ row: [String], _ name: String) -> String {
            guard let index = columns[name], index < row.count else { return "" }
            // Notes can contain intentional indentation and spacing.
            if name == "notes" { return row[index] }
            return row[index].trimmingCharacters(in: .whitespaces)
        }
        /// Whether this row reaches the column at all. A short row in a file
        /// with no header simply does not have the later columns.
        func has(_ row: [String], _ name: String) -> Bool {
            guard let index = columns[name] else { return false }
            return index < row.count
        }
        func stamp(_ row: [String], _ name: String) -> Date? {
            stampFormatter.date(from: field(row, name))
        }

        var result = ImportResult()
        var byLabel = Dictionary(
            categories.map { ($0.label.lowercased(), $0.id) },
            uniquingKeysWith: { first, _ in first }
        )

        // Categories first, so that every project and task can name them.
        var seenLabels = Set<String>()
        for row in rows where kind(of: field(row, "type")) == .category {
            let label = field(row, "title")
            guard !label.isEmpty, seenLabels.insert(label.lowercased()).inserted else {
                if row.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                    result.skipped += 1
                }
                continue
            }
            let fileID = UUID(uuidString: field(row, "id"))
            let existing = fileID.flatMap { id in categories.first { $0.id == id } }
                ?? categories.first { $0.label.lowercased() == label.lowercased() }
            let id = existing?.id ?? fileID ?? UUID()
            byLabel[label.lowercased()] = id
            let symbol = field(row, "symbol")
            result.categories.append(CategoryRow(
                id: id,
                label: label,
                symbolName: symbol.isEmpty ? nil : symbol,
                color: CategoryColor(rawValue: field(row, "color").lowercased()),
                isDefault: flag(field(row, "default")) == true,
                modifiedAt: stamp(row, "modified")
            ))
        }

        for row in rows {
            guard let kind = kind(of: field(row, "type")) else {
                result.skipped += 1
                continue
            }
            if kind == .category { continue }

            let title = field(row, "title")
            guard !title.isEmpty else {
                if row.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                    result.skipped += 1
                }
                continue
            }

            if kind == .project {
                result.projects.append(ProjectRow(
                    id: UUID(uuidString: field(row, "id")),
                    name: title,
                    categoryID: byLabel[field(row, "category").lowercased()],
                    givesCategory: has(row, "category"),
                    // Blank is silence for a group and for archived alike, so
                    // a project is never taken out of one by a cell left empty.
                    group: Project.cleanGroup(field(row, "group")),
                    archived: flag(field(row, "archived")),
                    modifiedAt: stamp(row, "modified")
                ))
                continue
            }

            // A title written as "#ABC1234 slides" carries its project, which
            // is how a list pasted from elsewhere would say it.
            var cardTitle = title
            var projectName = Project.clean(field(row, "project"))
            if cardTitle.hasPrefix("#"), let (word, rest) = ProjectConversion.split(cardTitle) {
                if projectName.isEmpty { projectName = word }
                cardTitle = rest
            }

            var card = TodoItem(title: cardTitle)
            card.dateSemanticsVersion = legacyDate ? 0 : 1
            card.notes = field(row, "notes")
            if let id = UUID(uuidString: field(row, "id")) { card.id = id }
            if !projectName.isEmpty {
                result.projectNames[card.id] = projectName
                let key = Project.key(for: projectName)
                // Older files repeated these on every task row; they still read,
                // but a project row for the same project takes precedence.
                if result.projectGroups[key] == nil, let group = Project.cleanGroup(field(row, "group")) {
                    result.projectGroups[key] = group
                }
                if result.projectArchived[key] == nil, let archived = flag(field(row, "archived")) {
                    result.projectArchived[key] = archived
                }
            }

            var given: Set<String> = ["title"]
            func speak(_ name: String, valid: Bool = true) {
                guard has(row, name) else { return }
                let blank = field(row, name).isEmpty
                if blank ? clearable.contains(name) : valid { given.insert(name) }
            }

            let stack = Bucket(rawValue: field(row, "stack").lowercased())
            card.bucket = stack ?? .inbox
            speak("stack", valid: stack != nil)

            let label = field(row, "category").lowercased()
            card.categoryID = byLabel[label]
            speak("category", valid: byLabel[label] != nil)

            card.deadline = parseDay(field(row, "deadline"))
            speak("deadline", valid: card.deadline != nil)
            card.remindAt = stamp(row, "remind") ?? parseDay(field(row, "remind"))
            speak("remind", valid: card.remindAt != nil)
            card.completedAt = stamp(row, "completed")
            speak("completed", valid: card.completedAt != nil)
            card.reminderAnsweredAt = stamp(row, "answered")
            speak("answered", valid: card.reminderAnsweredAt != nil)

            let before = Bucket(rawValue: field(row, "before").lowercased())
            speak("before", valid: before != nil)

            if let created = stamp(row, "created") { card.createdAt = created; given.insert("created") }
            // Falls back to `createdAt` for the same reason the decoder does:
            // an export written before this column existed knows nothing about
            // when its tasks last moved, and re-importing one must not make
            // every task look as though it arrived today.
            if let entered = stamp(row, "entered") {
                card.enteredStackAt = entered
                given.insert("entered")
            } else {
                card.enteredStackAt = card.createdAt
            }

            speak("notes")
            if has(row, "project") || !projectName.isEmpty { given.insert("project") }

            // A completed timestamp and a non-completed stack contradict; the
            // stack column wins, since that is what the app reads.
            if card.bucket != .completed { card.completedAt = nil }
            // Only a completed task has somewhere to be reopened to; on any
            // other stack the column is a contradiction, and the stack wins.
            card.bucketBeforeCompletion = card.bucket == .completed ? before : nil
            // What the file says, or now: a row with no `modified` is new to
            // whoever wrote it, and an import is an edit.
            card.modifiedAt = stamp(row, "modified") ?? .stamp()

            result.cards.append(card)
            result.given[card.id] = given
        }
        return result
    }

    /// An existing task with what a file says about it laid over the top — and
    /// only what the file says. Anything the file does not speak to, because
    /// the column is absent, or empty where empty means silence, or unreadable,
    /// keeps the value the task already has.
    ///
    /// Timestamps compare to the second, which is all a CSV holds: a task whose
    /// stored millisecond differs from the file's whole second has not changed.
    /// Returning the old value when they agree is what lets the caller tell an
    /// untouched row from an edited one by simple equality.
    static func merged(_ existing: TodoItem, with parsed: TodoItem, given: Set<String>) -> TodoItem {
        func same(_ a: Date?, _ b: Date?) -> Bool {
            switch (a, b) {
            case (nil, nil): return true
            case let (x?, y?): return abs(x.timeIntervalSince(y)) < 1
            default: return false
            }
        }
        func take(_ old: Date?, _ new: Date?) -> Date? { same(old, new) ? old : new }
        /// A deadline is a day, and the CSV writes it as one. A task whose
        /// stored deadline happens to carry a time of day — an imported one can —
        /// reads back as midnight, and is not thereby a task that changed.
        func takeDay(_ old: Date?, _ new: Date?) -> Date? {
            switch (old, new) {
            case (nil, nil): return nil
            case let (x?, y?): return Calendar.current.isDate(x, inSameDayAs: y) ? x : y
            default: return new
            }
        }

        var card = existing
        if given.contains("title") { card.title = parsed.title }
        if given.contains("notes") { card.notes = parsed.notes }
        if given.contains("stack") { card.bucket = parsed.bucket }
        if given.contains("category") { card.categoryID = parsed.categoryID }
        if given.contains("project") { card.projectID = parsed.projectID }
        if given.contains("deadline") { card.deadline = takeDay(existing.deadline, parsed.deadline) }
        if given.contains("remind") { card.remindAt = take(existing.remindAt, parsed.remindAt) }
        if given.contains("completed") { card.completedAt = take(existing.completedAt, parsed.completedAt) }
        if given.contains("answered") {
            card.reminderAnsweredAt = take(existing.reminderAnsweredAt, parsed.reminderAnsweredAt)
        }
        if given.contains("before") { card.bucketBeforeCompletion = parsed.bucketBeforeCompletion }
        if given.contains("created") {
            card.createdAt = take(existing.createdAt, parsed.createdAt) ?? existing.createdAt
        }
        if given.contains("entered") {
            card.enteredStackAt = take(existing.enteredStackAt, parsed.enteredStackAt) ?? existing.enteredStackAt
        }

        // Changing the stack in the sheet is an arrival, and has to read as one
        // unless the sheet also said when.
        if card.bucket != existing.bucket {
            let saidWhen = given.contains("entered") && !same(parsed.enteredStackAt, existing.enteredStackAt)
            if !saidWhen { card.enteredStackAt = .stamp() }
            if card.bucket == .completed {
                if card.completedAt == nil { card.completedAt = .stamp() }
                if card.bucketBeforeCompletion == nil { card.bucketBeforeCompletion = existing.bucket }
            }
        }
        if card.bucket != .completed {
            card.completedAt = nil
            card.bucketBeforeCompletion = nil
        }
        return card
    }

    private static var defaultColumns: [String: Int] {
        Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1, $0) })
    }

    /// Names accepted for each column, so a file written by hand or by another
    /// tool still lands in the right places.
    private static let synonyms: [String: Set<String>] = [
        "notes":     ["notes", "note", "description"],
        "entered":   ["entered", "entered_stack", "stack_since"],
        "answered":  ["answered", "reminder_answered"],
        "before":    ["before", "before_completion", "was_in"],
        "archived":  ["archived", "is_archived"],
        "modified":  ["modified", "modified_at", "last_modified"],
        "symbol":    ["symbol", "icon"],
        "color":     ["color", "colour"],
        "default":   ["default", "is_default"],
        "type":      ["type", "kind", "record"],
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
