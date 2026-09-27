import Foundation

extension Date {
    /// A timestamp at millisecond resolution — the resolution the document
    /// format stores — so a value written and read back is unchanged. A `Date()`
    /// carries more precision than that, which would make every save/load
    /// round-trip alter the data it just wrote.
    static func stamp() -> Date {
        Date(timeIntervalSince1970: (Date().timeIntervalSince1970 * 1000).rounded() / 1000)
    }
}

// MARK: - Buckets

/// The vertical sections the cards are grouped into, in display order.
///
/// A card's bucket is *stored*, not derived from a date: an undated card you
/// put in TOMORROW stays in TOMORROW until you move it yourself. Nothing rolls
/// over on its own.
///
/// A date is the one exception, and only once it arrives: a card dated for
/// today or tomorrow is filed into the matching stack, from wherever it was.
/// A date further out only decides where the card sits inside its own stack.
enum Bucket: String, Codable, CaseIterable, Identifiable {
    case inbox
    case today
    case tomorrow
    case later
    case completed

    var id: String { rawValue }

    /// Shown on the section headings, in the pickers and inside sentences such
    /// as "Move to Tomorrow", so it is translated like any other visible text.
    var title: String {
        switch self {
        case .inbox:     return String(localized: "Inbox", comment: "Stack name")
        case .today:     return String(localized: "Today", comment: "Stack name")
        case .tomorrow:  return String(localized: "Tomorrow", comment: "Stack name")
        case .later:     return String(localized: "Later", comment: "Stack name")
        case .completed: return String(localized: "Completed", comment: "Stack name")
        }
    }

    var symbolName: String {
        switch self {
        case .inbox:     return "tray"
        case .today:     return "sun.max"
        case .tomorrow:  return "sunrise"
        case .later:     return "hourglass"
        case .completed: return "checkmark.circle"
        }
    }

    /// The buckets a card can be sent to straight from the tap menu.
    /// COMPLETED is reached by completing.
    static let quickMoveTargets: [Bucket] = [.inbox, .today, .tomorrow, .later]

    /// Where the move gesture sends a card: forward into TODAY, or on to
    /// TOMORROW for a card that is already in TODAY.
    var forwardDestination: Bucket {
        self == .today ? .tomorrow : .today
    }

    /// Accepts bucket names written by earlier versions of the app.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "nextWeek":  self = .later     // renamed
        case "scheduled": self = .inbox     // category retired; the date is kept
        default:          self = Bucket(rawValue: raw) ?? .inbox
        }
    }
}

// MARK: - Categories

/// The colours a category may use. Deliberately disjoint from the stack
/// colours (gray / blue / orange / green) and from red, which means overdue —
/// a category has to stay legible sitting on top of a stack-coloured card.
enum CategoryColor: String, Codable, CaseIterable, Identifiable {
    case indigo
    case purple
    case teal
    case pink
    case brown
    case yellow

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .indigo: return "Indigo"
        case .purple: return "Purple"
        case .teal:   return "Teal"
        case .pink:   return "Pink"
        case .brown:  return "Brown"
        case .yellow: return "Yellow"
        }
    }
}

/// A user-defined label on a card, orthogonal to its stack: the same category
/// can sit in TODAY, LATER or COMPLETED. Optional — a card may have none.
///
/// Cards show only the icon; the label identifies the category in Settings, in
/// the picker, and to VoiceOver.
struct CardCategory: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var label: String
    var symbolName: String
    var color: CategoryColor
    /// Last edit, used to reconcile two devices.
    var modifiedAt: Date = .stamp()

    /// The icons offered when creating or editing a category.
    static let iconChoices = [
        "flask", "graduationcap", "house", "briefcase", "book", "person.2",
        "heart", "cart", "airplane", "dumbbell", "leaf", "pawprint",
        "envelope", "phone", "camera", "music.note", "wrench.and.screwdriver",
        "creditcard", "gift", "cup.and.saucer", "hammer", "paintbrush",
        "chart.line.uptrend.xyaxis", "lightbulb"
    ]

    /// Seeded on first run, and used when an old data file has no categories.
    /// Three that suit most people, renameable like any other: the point is to
    /// arrive with something rather than an empty Settings page. The ids are
    /// fixed so a card written before categories were editable can still be
    /// matched to one.
    ///
    /// **Stamped `.distantPast`, and that is the whole point.** These ids are
    /// guaranteed to collide with every other install's, so a merge always has
    /// to choose between two versions of the same three categories. Stamped
    /// with the time of the install, a brand-new device would arrive claiming
    /// the freshest edit and rename "Research" back to "Home" on every other
    /// device — a default is not an edit, and must lose to one.
    static var defaults: [CardCategory] { [
        CardCategory(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000A001")!,
            label: String(localized: "Home", comment: "Seeded category"), symbolName: "house", color: .teal,
            modifiedAt: .distantPast
        ),
        CardCategory(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000A002")!,
            label: String(localized: "Work", comment: "Seeded category"), symbolName: "briefcase", color: .indigo,
            modifiedAt: .distantPast
        ),
        CardCategory(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000A003")!,
            label: String(localized: "Courses", comment: "Seeded category"), symbolName: "graduationcap", color: .purple,
            modifiedAt: .distantPast
        )
    ] }

    init(id: UUID = UUID(), label: String, symbolName: String, color: CategoryColor, modifiedAt: Date = .stamp()) {
        self.id = id
        self.label = label
        self.symbolName = symbolName
        self.color = color
        self.modifiedAt = modifiedAt
    }

    /// Same reason as `StoreDocument`: a category saved before `modifiedAt`
    /// existed must still load, not throw.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        label = try c.decode(String.self, forKey: .label)
        symbolName = try c.decode(String.self, forKey: .symbolName)
        color = try c.decodeIfPresent(CategoryColor.self, forKey: .color) ?? .indigo
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? .distantPast
    }

    /// Maps the fixed categories this app once shipped with onto a seeded one
    /// of the same name, so a card written back then keeps its category.
    ///
    /// Matched by label rather than by position: the seeded three have been
    /// renamed since, and matching by position would have filed a card marked
    /// "research" under whatever now sits first.
    static func legacyID(forRawValue raw: String) -> UUID? {
        defaults.first { $0.label.caseInsensitiveCompare(raw) == .orderedSame }?.id
    }
}

// MARK: - Projects

/// Something a card belongs to: a trip, a client, a paper, a course. Typed as
/// `#TRIP` and shown as a coloured prefix on the card.
///
/// A project is its own record rather than text inside titles, so renaming or
/// merging one is a single change instead of a rewrite of every title, and it
/// syncs by the same rules as categories.
struct Project: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    /// Shown as first written; matched without regard to case or accents.
    var name: String
    /// The category a card picks up when it is given this project. A card can
    /// still be moved to another category afterwards.
    var categoryID: UUID?
    /// Finished — a course that has ended. Kept, with its cards, but no longer
    /// offered when typing.
    var isArchived: Bool = false
    /// An optional cluster within the category — "Grants", "Ongoing". A plain
    /// label rather than a record of its own: a category's groups are simply
    /// the labels its projects carry, so a group exists while something is in
    /// it and there is no second list to keep in step or to sync.
    var group: String?
    /// Last edit, used to reconcile two devices.
    var modifiedAt: Date = .stamp()

    init(
        id: UUID = UUID(),
        name: String,
        categoryID: UUID? = nil,
        isArchived: Bool = false,
        group: String? = nil,
        modifiedAt: Date = .stamp()
    ) {
        self.id = id
        self.name = name
        self.categoryID = categoryID
        self.isArchived = isArchived
        self.group = group
        self.modifiedAt = modifiedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        categoryID = try c.decodeIfPresent(UUID.self, forKey: .categoryID)
        isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        group = try c.decodeIfPresent(String.self, forKey: .group).flatMap(Project.cleanGroup)
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? .distantPast
    }

    /// What two names are compared by, so `sfrd2026`, `STUDY2026` and `#STUDY2026`
    /// are one project, not three.
    var key: String { Project.key(for: name) }

    static func key(for name: String) -> String {
        clean(name).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// A usable project name from whatever was typed: no leading `#`, no
    /// surrounding punctuation, and no spaces — a project is one word, which is
    /// what lets typing a space finish it.
    static func clean(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasPrefix("#") || text.hasPrefix("\u{FF03}") { text.removeFirst() }
        text = text.trimmingCharacters(in: Project.edgePunctuation)
        return text.filter { !$0.isWhitespace }
    }

    /// A usable group label, or nil for none. Unlike a project name a group may
    /// be several words ("Bachelor courses"); only the ends are trimmed and
    /// inner runs of spaces collapsed.
    static func cleanGroup(_ raw: String) -> String? {
        let words = raw.split(whereSeparator: { $0.isWhitespace })
        return words.isEmpty ? nil : words.joined(separator: " ")
    }

    /// Group labels compare like project names: without regard to case or
    /// accents, so "grants" joins "Grants" rather than starting a second one.
    static func groupKey(for label: String) -> String {
        (cleanGroup(label) ?? "").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Stripped from both ends of a name: "STUDY2026:" and "(ALPHA)" are the
    /// codes STUDY2026 and ALPHA.
    static let edgePunctuation = CharacterSet(charactersIn: ":;,.-–—()[]{}\"'/")
}

// MARK: - Groups of projects

/// Groups are read off the projects rather than stored: a category's groups are
/// the distinct labels its projects carry.
enum ProjectGroups {
    /// The groups in one category (nil for projects without a category), each
    /// with its projects, alphabetically, plus the projects in no group.
    struct Layout: Equatable {
        var groups: [(name: String, projects: [Project])]
        var ungrouped: [Project]

        static func == (a: Layout, b: Layout) -> Bool {
            a.ungrouped == b.ungrouped
                && a.groups.map(\.name) == b.groups.map(\.name)
                && a.groups.map(\.projects) == b.groups.map(\.projects)
        }
    }

    static func layout(of projects: [Project]) -> Layout {
        func byName(_ a: Project, _ b: Project) -> Bool {
            a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        var buckets: [String: (name: String, projects: [Project])] = [:]
        var loose: [Project] = []
        for project in projects {
            guard let label = project.group else { loose.append(project); continue }
            let key = Project.groupKey(for: label)
            // The first spelling met names the group; later variants join it.
            buckets[key, default: (label, [])].projects.append(project)
        }
        let groups = buckets.values
            .map { (name: $0.name, projects: $0.projects.sorted(by: byName)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return Layout(groups: groups, ungrouped: loose.sorted(by: byName))
    }

    /// The group names already used in a category, for the "Move to Group" menu.
    static func names(in categoryID: UUID?, projects: [Project]) -> [String] {
        layout(of: projects.filter { $0.categoryID == categoryID }).groups.map(\.name)
    }

    /// The existing spelling of a label in a category, if the label is already
    /// in use there — so choosing "grants" files a project under "Grants".
    static func existingName(for label: String, in categoryID: UUID?, projects: [Project]) -> String? {
        let key = Project.groupKey(for: label)
        return names(in: categoryID, projects: projects).first { Project.groupKey(for: $0) == key }
    }
}

/// Moving a project between categories.
///
/// The project is the thing that says where this work belongs, so changing its
/// category re-files every card in it. Cards already in the project used to
/// keep whatever category they had, which left a project's cards scattered
/// across categories with no way to see it or put it right.
enum ProjectCategory {
    /// The cards that would move, so the count can be reported and the work
    /// skipped when there is none.
    static func cardsToRefile(_ project: Project, to categoryID: UUID?, in cards: [TodoItem]) -> [TodoItem] {
        cards.filter { $0.projectID == project.id && $0.categoryID != categoryID }
    }
}

/// Putting a project away.
///
/// A project is archived when it is over — a course that has finished, a grant
/// that was decided — so it stops cluttering the list of what you might type
/// next. That only makes sense once nothing in it is still to do, which is why
/// archiving offers to tick off whatever is left rather than quietly hiding
/// work: cards that vanished while still open would be work lost.
enum Archiving {
    /// What archiving would have to finish first.
    static func openCards(of project: Project, in cards: [TodoItem]) -> [TodoItem] {
        cards.filter { $0.projectID == project.id && !$0.isCompleted }
    }

    static func isFinished(_ project: Project, in cards: [TodoItem]) -> Bool {
        openCards(of: project, in: cards).isEmpty
    }
}

/// Finding a card by what it shows.
///
/// The text searched is the text on the card: its title, with the project name
/// that is printed in front of it. Case and accents are ignored, so "creche"
/// finds "crèche" and a French keyboard is never required to find a card typed
/// on one. Several words all have to appear, in any order — "flight book"
/// finds "book the flights" — because a query is a memory of a card, not its
/// wording.
enum CardSearch {
    static func normalised(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    static func terms(in query: String) -> [String] {
        normalised(query).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// A blank query matches everything, so an empty search bar hides nothing.
    static func matches(title: String, project: String?, terms: [String]) -> Bool {
        guard !terms.isEmpty else { return true }
        let haystack = normalised([project, title].compactMap { $0 }.joined(separator: " "))
        return terms.allSatisfy { haystack.contains($0) }
    }
}

/// The tallies beside the rows of the filter sheet.
///
/// Every row counts the same thing — cards still to do, matched with the same
/// test the filter itself applies — so a row offering one card always has one
/// to show. A group heading used to count its projects instead, in the slot
/// where every row beneath it counted cards, and a group holding a single
/// finished project read "All 1" and then filtered to nothing.
enum FilterCounts {
    static func byProject(_ cards: [TodoItem]) -> [UUID: Int] {
        tally(cards) { $0.projectID }
    }

    static func byCategory(_ cards: [TodoItem]) -> [UUID: Int] {
        tally(cards) { $0.categoryID }
    }

    /// A group is worth the sum of its projects' cards.
    static func total(of projects: [Project], in counts: [UUID: Int]) -> Int {
        projects.reduce(0) { $0 + (counts[$1.id] ?? 0) }
    }

    private static func tally(_ cards: [TodoItem], by key: (TodoItem) -> UUID?) -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        for card in cards where !card.isCompleted {
            guard let id = key(card) else { continue }
            result[id, default: 0] += 1
        }
        return result
    }
}

// MARK: - Typing a project

/// The `#word` being typed in a title, found at the end of the text because
/// that is where the cursor is while typing.
struct ProjectToken: Equatable {
    /// What follows the `#`, possibly empty just after typing it.
    let query: String
    /// Whether a space has been typed after it — the signal to take it as is.
    let isFinished: Bool
    /// The title with the token removed.
    let remainder: String

    /// Finds the last `#word` in the text, if the text ends with it (or with it
    /// and one space). A `#` in the middle of finished words is left alone.
    static func find(in text: String) -> ProjectToken? {
        let finished = text.hasSuffix(" ")
        let body = finished ? String(text.dropLast()) : text
        // Two spaces means the word was finished some time ago.
        if finished && body.last?.isWhitespace == true { return nil }

        // The final word of what is left.
        let start = body.lastIndex(where: { $0.isWhitespace }).map { body.index(after: $0) } ?? body.startIndex
        let word = String(body[start...])
        guard let first = word.first, first == "#" || first == "\u{FF03}" else { return nil }

        let query = String(word.dropFirst())
        // "# " on its own is someone typing a hash and a space, not a project.
        if finished && query.isEmpty { return nil }

        let before = String(body[..<start])
        let remainder = before
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return ProjectToken(query: query, isFinished: finished, remainder: remainder)
    }
}

/// Ranks projects for the suggestion chips: names that start with what was
/// typed, then names that merely contain it; most recently used first within
/// each. Archived projects are never suggested.
enum ProjectSuggestions {
    static func rank(
        _ projects: [Project],
        query: String,
        lastUsed: [UUID: Date],
        limit: Int = 6
    ) -> [Project] {
        let wanted = Project.key(for: query)
        let live = projects.filter { !$0.isArchived }

        func recency(_ project: Project) -> Date { lastUsed[project.id] ?? .distantPast }
        func byRecency(_ a: Project, _ b: Project) -> Bool {
            let (ra, rb) = (recency(a), recency(b))
            if ra != rb { return ra > rb }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }

        guard !wanted.isEmpty else {
            return Array(live.sorted(by: byRecency).prefix(limit))
        }

        let prefix = live.filter { $0.key.hasPrefix(wanted) }.sorted(by: byRecency)
        let inside = live.filter { !$0.key.hasPrefix(wanted) && $0.key.contains(wanted) }.sorted(by: byRecency)
        return Array((prefix + inside).prefix(limit))
    }
}

// MARK: - Turning title prefixes into projects

/// Finds the first words of titles that look like project codes, for the
/// one-time conversion of cards written before projects existed.
///
/// Nothing is converted automatically. Code-like words (capitals, or letters
/// mixed with digits: ABC1234, NF, ALPHA) are offered ticked; ordinary words
/// used on several cards (Payer, Email) are offered unticked, because a verb at
/// the start of a title is not a project.
enum ProjectConversion {
    struct Candidate: Identifiable, Equatable {
        /// The word as it most often appears.
        let name: String
        let cardIDs: [UUID]
        let looksLikeCode: Bool
        /// Another candidate or existing project this one is probably the same
        /// as — STUDY beside STUDY2026.
        let similar: [String]

        var id: String { Project.key(for: name) }
    }

    /// The first word of a title as a project name, and the rest of the title.
    static func split(_ title: String) -> (word: String, rest: String)? {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard let space = trimmed.firstIndex(where: { $0.isWhitespace }) else { return nil }
        let word = Project.clean(String(trimmed[..<space]))
        var rest = String(trimmed[space...]).trimmingCharacters(in: .whitespaces)
        // "STUDY2026 - update program" should become "update program".
        while let first = rest.first, "-–—:".contains(first) {
            rest = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        guard !word.isEmpty, !rest.isEmpty else { return nil }
        return (word, rest)
    }

    static func looksLikeCode(_ word: String) -> Bool {
        let letters = word.filter(\.isLetter)
        guard word.count >= 2, !letters.isEmpty else { return false }
        let hasDigit = word.contains(where: \.isNumber)
        let noLowercase = !letters.contains(where: \.isLowercase)
        return noLowercase || hasDigit
    }

    static func candidates(cards: [TodoItem], existing: [Project]) -> [Candidate] {
        var groups: [String: (names: [String: Int], ids: [UUID])] = [:]
        for card in cards where card.projectID == nil {
            guard let (word, _) = split(card.title) else { continue }
            let key = Project.key(for: word)
            groups[key, default: ([:], [])].names[word, default: 0] += 1
            groups[key, default: ([:], [])].ids.append(card.id)
        }

        let existingKeys = Set(existing.map(\.key))
        let found = groups.compactMap { key, group -> (String, [UUID], Bool)? in
            let name = group.names.max { a, b in a.value < b.value || (a.value == b.value && a.key > b.key) }!.key
            let code = looksLikeCode(name)
            // A word already in use as a project always qualifies; otherwise it
            // must look like a code or recur.
            guard code || group.ids.count >= 2 || existingKeys.contains(key) else { return nil }
            return (name, group.ids, code || existingKeys.contains(key))
        }

        let allNames = found.map(\.0) + existing.map(\.name)
        return found
            .map { name, ids, code in
                let key = Project.key(for: name)
                let similar = allNames.filter { other in
                    let otherKey = Project.key(for: other)
                    guard otherKey != key, looksLikeCode(other), otherKey.count >= 2, key.count >= 2 else { return false }
                    return otherKey.hasPrefix(key) || key.hasPrefix(otherKey)
                }
                return Candidate(
                    name: name, cardIDs: ids, looksLikeCode: code,
                    similar: Array(Set(similar)).sorted()
                )
            }
            .sorted { a, b in
                if a.cardIDs.count != b.cardIDs.count { return a.cardIDs.count > b.cardIDs.count }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
    }
}

// MARK: - Item

struct TodoItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var bucket: Bucket = .inbox
    /// Optional category, independent of `bucket` and `dueDate`. Holds the id
    /// of a `CardCategory` the user has defined.
    var categoryID: UUID?
    /// Optional project — a trip, a client, a paper — one per card. Holds the
    /// id of a `Project`, so renaming the project renames it on every card.
    var projectID: UUID?
    /// When the work is due. Optional, and independent of `bucket` in every
    /// direction: it never moves the card, and moving the card never clears it.
    /// A job that takes four days has a deadline on the fourth and sits in
    /// Today for all four.
    var deadline: Date?
    /// When to be reminded, to the minute — a different question from when the
    /// work is due, and asked separately.
    var remindAt: Date?
    /// Whether that reminder actually fires. An editable field on the card, on
    /// by default, so a reminder can be silenced without losing the time it
    /// was set for.
    var remindsEnabled: Bool = true
    /// When the reminder was answered in the review. A notification that was
    /// merely swiped away is not an answer — only choosing what to do with the
    /// card is — so this is the one thing that takes a reminder off the list.
    var reminderAnsweredAt: Date?
    /// Where the card came from, so un-completing puts it back.
    var bucketBeforeCompletion: Bucket?
    var completedAt: Date?
    var createdAt: Date = .stamp()
    /// Last edit, used to reconcile two devices.
    var modifiedAt: Date = .stamp()
    /// One of the cards a new install arrives with, still untouched. Cleared
    /// the moment the user edits it, and what is left is swept away when real
    /// cards arrive from another device.
    var isSample: Bool = false

    var isCompleted: Bool { bucket == .completed }

    /// Only used to read files written before categories became user-defined,
    /// and before a date became a deadline rather than a filing instruction.
    private enum LegacyKeys: String, CodingKey { case category, dueDate }

    /// Tolerate files written by earlier versions / missing keys.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decode(String.self, forKey: .title)
        bucket = try c.decodeIfPresent(Bucket.self, forKey: .bucket) ?? .inbox
        // A date written by a version that filed cards is read as a deadline:
        // the day is what the user meant, the moving was the app's idea. The
        // old key is never written back, which is the only way to stop such a
        // version filing again — it would ignore any flag it did not know, but
        // it cannot file a date it cannot see.
        if let date = try c.decodeIfPresent(Date.self, forKey: .deadline) {
            deadline = date
        } else if let legacy = try? decoder.container(keyedBy: LegacyKeys.self) {
            deadline = try? legacy.decodeIfPresent(Date.self, forKey: .dueDate)
        } else {
            deadline = nil
        }
        remindAt = try c.decodeIfPresent(Date.self, forKey: .remindAt)
        remindsEnabled = try c.decodeIfPresent(Bool.self, forKey: .remindsEnabled) ?? true
        reminderAnsweredAt = try c.decodeIfPresent(Date.self, forKey: .reminderAnsweredAt)

        // `categoryID` is a UUID now. Files written when categories were a
        // fixed enum stored "research" / "teaching" / "personal" under a
        // "category" key instead, so fall back to matching those onto the
        // seeded categories. Read through a separate key type so the synthesised
        // encoder stays untouched.
        if let id = try? c.decodeIfPresent(UUID.self, forKey: .categoryID) {
            categoryID = id
        } else if let legacy = try? decoder.container(keyedBy: LegacyKeys.self),
                  let raw = try? legacy.decodeIfPresent(String.self, forKey: .category) {
            categoryID = CardCategory.legacyID(forRawValue: raw)
        } else {
            categoryID = nil
        }
        projectID = try c.decodeIfPresent(UUID.self, forKey: .projectID)
        bucketBeforeCompletion = try c.decodeIfPresent(Bucket.self, forKey: .bucketBeforeCompletion)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .stamp()
        // Files written before syncing existed have no timestamp; treat them as
        // old so a genuinely edited copy on another device wins.
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? .distantPast
        isSample = try c.decodeIfPresent(Bool.self, forKey: .isSample) ?? false
    }

    init(
        title: String,
        bucket: Bucket = .inbox,
        categoryID: UUID? = nil,
        projectID: UUID? = nil,
        deadline: Date? = nil,
        remindAt: Date? = nil
    ) {
        self.title = title
        self.bucket = bucket
        self.categoryID = categoryID
        self.projectID = projectID
        self.deadline = deadline
        self.remindAt = remindAt
    }
}

// MARK: - Deadlines and reminders

/// How close a deadline is, for the edge colour on the card.
///
/// A deadline states when work is due; it never moves the card, so the only
/// way it can say anything is by how the card looks. Yellow while it is
/// coming, red once it is here or past — and red is reserved for that, as it
/// always was.
enum DeadlineUrgency: Equatable {
    case none
    case approaching
    case due
    case overdue

    /// Three days: long enough to act on, short enough that a wall of yellow
    /// does not become the normal state of the list.
    static let approachingWithin = 3

    /// Red: here or past. Yellow is a warning, this is the thing itself, and
    /// it is what the attention filter gathers.
    var isRed: Bool { self == .due || self == .overdue }

    static func of(_ deadline: Date?, now: Date = Date(),
                   calendar: Calendar = .current) -> DeadlineUrgency {
        guard let deadline else { return .none }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: deadline)
        ).day ?? 0

        if days < 0 { return .overdue }
        if days == 0 { return .due }
        return days <= approachingWithin ? .approaching : .none
    }
}

/// The cards asking for attention: the red ones, and the ones a reminder is
/// waiting on.
///
/// Two different claims on the user — a deadline that has arrived, and a
/// question that has been asked and not answered — but from where they are
/// sitting both mean the same thing, so one button gathers both rather than
/// two competing for the same corner.
///
/// Yellow is deliberately left out. A card three days off is being shown, not
/// asked about, and a list of things to deal with now loses its meaning the
/// moment it also contains things to deal with later.
enum Attention {
    static func needed(_ card: TodoItem, now: Date = Date(),
                       calendar: Calendar = .current) -> Bool {
        guard !card.isCompleted else { return false }
        if Reminders.isOutstanding(card, now: now) { return true }
        return DeadlineUrgency.of(card.deadline, now: now, calendar: calendar).isRed
    }

    static func count(in cards: [TodoItem], now: Date = Date()) -> Int {
        cards.filter { needed($0, now: now) }.count
    }
}

/// Which reminders are waiting to be answered.
///
/// A reminder leaves this list for one reason only: the user said what to do
/// with the card. Swiping the notification away is not an answer — it is how
/// a notification is got rid of, not how a decision is made — so the review
/// goes on holding it until one of the three choices is made.
enum Reminders {
    static func isOutstanding(_ card: TodoItem, now: Date = Date()) -> Bool {
        guard card.remindsEnabled, !card.isCompleted, let at = card.remindAt else { return false }
        guard at <= now else { return false }
        // Answered before this reminder was due means it was a previous one:
        // re-arming for tomorrow must not arrive already answered.
        guard let answered = card.reminderAnsweredAt else { return true }
        return answered < at
    }

    static func outstanding(in cards: [TodoItem], now: Date = Date()) -> [TodoItem] {
        cards.filter { isOutstanding($0, now: now) }
            .sorted { ($0.remindAt ?? .distantPast) < ($1.remindAt ?? .distantPast) }
    }

    /// The reminders a notification should be pending for: armed, in the
    /// future, on a card still to do.
    static func scheduled(in cards: [TodoItem], now: Date = Date()) -> [TodoItem] {
        cards.filter { card in
            guard card.remindsEnabled, !card.isCompleted, let at = card.remindAt else { return false }
            return at > now
        }
    }

    /// "Snooze" — the same time on the next day, since a card has no
    /// recurrence of its own and what is being deferred is "not now".
    static func again(after at: Date, calendar: Calendar = .current) -> Date? {
        calendar.date(byAdding: .day, value: 1, to: at)
    }
}

/// What the user chose to do about a reminder that has come due.
///
/// Doing nothing is deliberately not in here. Leaving a reminder alone is the
/// absence of an answer, not one of them, which is exactly why it stays on the
/// list — the same reason dismissing a notification changes nothing.
enum ReminderAnswer: Equatable {
    case move(Bucket)
    /// Ask again at the same time tomorrow. The card does not move.
    case snooze
    /// Done with the reminder. The deadline is a separate field and is left
    /// exactly as it was.
    case clear

    /// Applied here rather than in the store so it can be tested.
    func apply(to card: inout TodoItem, now: Date, calendar: Calendar = .current) {
        switch self {
        case .move(let bucket):
            card.bucket = bucket
            card.bucketBeforeCompletion = nil
            card.completedAt = nil
            card.remindAt = nil
        case .snooze:
            card.remindAt = card.remindAt.flatMap { again(after: $0, calendar: calendar) }
        case .clear:
            card.remindAt = nil
        }
        card.reminderAnsweredAt = now
    }

    private func again(after at: Date, calendar: Calendar) -> Date? {
        Reminders.again(after: at, calendar: calendar)
    }
}

// MARK: - Looking back at what got done

/// A week to look back over. Only two, deliberately: the question worth asking
/// is "what did I get done", not "let me browse an archive" — the Completed
/// stack already holds everything.
enum ReviewWeek: String, CaseIterable, Identifiable {
    case thisWeek
    case lastWeek

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thisWeek: return String(localized: "This week", comment: "Review period")
        case .lastWeek: return String(localized: "Last week", comment: "Review period")
        }
    }

    /// The days the week covers, starting on whichever day the reader's
    /// calendar starts on — Monday in most of Europe, Sunday in the US.
    func interval(now: Date = Date(), calendar: Calendar = .current) -> DateInterval? {
        guard let current = calendar.dateInterval(of: .weekOfYear, for: now) else { return nil }
        switch self {
        case .thisWeek:
            return current
        case .lastWeek:
            guard let earlier = calendar.date(byAdding: .day, value: -7, to: current.start) else { return nil }
            return calendar.dateInterval(of: .weekOfYear, for: earlier)
        }
    }
}

/// Groups finished cards by the day they were finished.
enum Review {
    struct Day: Identifiable, Equatable {
        /// Midnight on the day these were completed.
        let date: Date
        /// Most recently completed first.
        let cards: [TodoItem]

        var id: Date { date }
    }

    /// The days of a week that have something on them, newest first. Days with
    /// nothing completed are left out rather than shown empty: a week of blank
    /// rows says nothing that one line of text cannot.
    static func days(
        completedIn interval: DateInterval,
        cards: [TodoItem],
        calendar: Calendar = .current
    ) -> [Day] {
        var byDay: [Date: [TodoItem]] = [:]
        for card in cards {
            // A card that was un-completed has no timestamp and did not happen.
            guard card.isCompleted, let done = card.completedAt else { continue }
            // `contains` is half-open, so a card finished at the very start of
            // next week belongs to next week, not this one.
            guard interval.contains(done) else { continue }
            byDay[calendar.startOfDay(for: done), default: []].append(card)
        }

        return byDay
            .map { day, cards in
                Day(date: day, cards: cards.sorted {
                    ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast)
                })
            }
            .sorted { $0.date > $1.date }
    }

    static func count(completedIn interval: DateInterval, cards: [TodoItem], calendar: Calendar = .current) -> Int {
        days(completedIn: interval, cards: cards, calendar: calendar)
            .reduce(0) { $0 + $1.cards.count }
    }
}

// MARK: - Dates

/// Date helpers. Buckets are stored on the card, so dates never decide where a
/// card lives — only where it sits inside its bucket.
enum Scheduler {
    static var calendar: Calendar { Calendar.current }

    static func startOfToday(_ now: Date = Date()) -> Date {
        calendar.startOfDay(for: now)
    }

    /// Whole days from today to `date`: 0 = today, 1 = tomorrow, negative = past.
    static func dayOffset(for date: Date, now: Date = Date()) -> Int {
        calendar.dateComponents(
            [.day],
            from: startOfToday(now),
            to: calendar.startOfDay(for: date)
        ).day ?? 0
    }

    /// A reminder's opening suggestion: 9am tomorrow. Not "now", which is a
    /// reminder that has already gone off before the sheet is closed.
    static func defaultReminderTime(_ now: Date = Date()) -> Date {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday(now)) ?? now
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    /// Where a card sits inside its stack. A deadline orders a card; it never
    /// moves one. Cards carrying one come first, soonest at the top, and the
    /// undated follow in the order they always had.
    static func sortKey(for item: TodoItem) -> Date? { item.deadline }

    static func relativeLabel(for date: Date, now: Date = Date()) -> String {
        let days = calendar.dateComponents(
            [.day],
            from: startOfToday(now),
            to: calendar.startOfDay(for: date)
        ).day ?? 0

        switch days {
        case 0:  return "Today"
        case 1:  return "Tomorrow"
        case -1: return "Yesterday"
        default:
            let formatter = DateFormatter()
            formatter.locale = .current
            formatter.setLocalizedDateFormatFromTemplate(abs(days) < 300 ? "EEEdMMM" : "dMMMyyyy")
            return formatter.string(from: date)
        }
    }
}

