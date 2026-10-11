import SwiftUI

/// What to do about a Return typed into a title field.
///
/// The title fields wrap onto a second line as you type, which on iOS means
/// Return is delivered as a line break and `onSubmit` never fires at all. A
/// card's title is one line, so a typed Return is taken for the submit it was
/// meant to be.
///
/// Pasted text can carry newlines too, and that is not a submit — it is text
/// arriving. Those are folded into spaces and left alone for the user to
/// finish, which is why the two cases are told apart rather than every newline
/// being treated as Return.
private struct TitleReturn {
    let cleaned: String
    let isSubmit: Bool
}

private func titleReturn(in text: String) -> TitleReturn? {
    guard text.contains(where: \.isNewline) else { return nil }
    return TitleReturn(
        cleaned: text.split(whereSeparator: \.isNewline).joined(separator: " "),
        isSubmit: text.last?.isNewline == true && text.filter(\.isNewline).count == 1
    )
}

/// The project a new card will get: none, one that exists, or one to create
/// when the card is added — so cancelling the sheet never leaves a stray one.
enum ProjectChoice: Equatable {
    case none
    case existing(Project)
    case new(String)

    var name: String? {
        switch self {
        case .none:                return nil
        case .existing(let project): return project.name
        case .new(let name):       return name
        }
    }
}

/// Compose a new card. Category and date are both optional and start empty, so
/// the fast path stays: type a title, tap Add.
///
/// A project is chosen by typing `#` and a few letters — matching projects
/// appear as chips under the field — or, before typing anything, by tapping one
/// of the recent projects already shown there. A project fills in its category.
struct AddCardView: View {
    @EnvironmentObject private var store: TodoStore

    let categories: [CardCategory]
    let projects: [Project]
    /// When each project was last used, for ranking the chips.
    let projectLastUsed: [UUID: Date]
    /// The projects a card carries, so an emptied one is not offered here either.
    let projectsInUse: Set<UUID>
    /// `(title, stack, category, project, remindAt, deadline)`.
    /// `(title, stack, category, project, newProjectGroup, remindAt, deadline)`.
    let onAdd: (String, Bucket, UUID?, ProjectChoice, String?, Date?, Date?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var categoryID: UUID?
    @State private var project: ProjectChoice = .none
    /// The project taken from a `#word` that is still being typed, and the
    /// category the card carried before it was taken. Both are given back if
    /// the word stops naming that project, so a half-typed name cannot leave
    /// the card somewhere the user never chose.
    /// What the card's category was before a project set it, so that removing
    /// the project puts it back.
    @State private var categoryBeforeProject: UUID?
    init(
        categories: [CardCategory],
        projects: [Project] = [],
        projectLastUsed: [UUID: Date] = [:],
        projectsInUse: Set<UUID> = [],
        defaultCategoryID: UUID?,
        onAdd: @escaping (String, Bucket, UUID?, ProjectChoice, String?, Date?, Date?) -> Void
    ) {
        self.categories = categories
        self.projects = projects
        self.projectLastUsed = projectLastUsed
        self.projectsInUse = projectsInUse
        self.onAdd = onAdd
        // Pre-selected, not forced: it is an ordinary picker value the user can
        // change back to None before adding.
        _categoryID = State(initialValue: defaultCategoryID)
    }

    @State private var bucket: Bucket = .inbox
    /// The group a *new* project should be created in. Kept here rather than
    /// inside `ProjectChoice`, because the title field rebuilds that choice on
    /// every keystroke and would drop the group with it.
    @State private var newProjectGroup: String?
    @State private var isNamingGroup = false
    @State private var typedGroup = ""
    @State private var hasReminder = false
    @State private var remindAt = Scheduler.defaultReminderTime()
    @State private var hasDeadline = false
    @State private var deadline = Scheduler.startOfToday()
    @FocusState private var focused: Bool
    /// Set once the card has been filed, so it cannot be filed again.
    @State private var didAdd = false

    /// The title as it will be saved. A first word that was going to be a
    /// project has already been taken out of it, by the chip or the Tab that
    /// accepted it — nothing is pending here any more.
    private var savedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAdd: Bool { !savedTitle.isEmpty }



    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ProjectTitleField(
                        title: $title,
                        project: $project,
                        projects: projects,
                        lastUsed: projectLastUsed,
                        inUse: projectsInUse,
                        categories: categories,
                        categoryID: categoryID,
                        focused: $focused,
                        onSubmit: add,
                        onProjectChosen: projectChosen
                    )

                    // Only once there is a project to put somewhere.
                    if project != .none {
                        ProjectGroupRow(
                            names: groupNames,
                            selection: groupSelection,
                            tint: categories.first { $0.id == categoryID }?.color.prefixTint
                                  ?? Color.accentColor,
                            // Shown, not settable, for a project that already
                            // exists. Changing it would refile that project on
                            // every card carrying it, and this sheet promises
                            // that cancelling leaves nothing behind — a global
                            // edit that survives Cancel is the opposite of
                            // that. The card editor is where it is changed.
                            editable: !isExistingProject
                        ) {
                            typedGroup = ""
                            isNamingGroup = true
                        }
                    }
                }

                Section {
                    Picker(selection: $bucket.animation(.easeInOut(duration: 0.2))) {
                        ForEach(Bucket.quickMoveTargets) { target in
                            Label(target.title, systemImage: target.symbolName)
                                .tag(target)
                        }
                    } label: {
                        Label("Stack", systemImage: "tray.full")
                    }

                    Picker(selection: $categoryID) {
                        Text("None").tag(UUID?.none)
                        ForEach(categories) { category in
                            Label(category.label, systemImage: category.symbolName)
                                .tag(UUID?.some(category.id))
                        }
                    } label: {
                        Label("Category", systemImage: "tag")
                    }
                    .disabled(categories.isEmpty)

                    // One date, then optionally its far end. The reminder is
                    // when to pick the card up; the deadline only means
                    // something once there is a day to start, so it is not
                    // offered until there is one. Neither moves the card.
                    Toggle(isOn: $hasReminder.animation(.easeInOut(duration: 0.2))) {
                        Label("Remind me", systemImage: "flag")
                    }
                    if hasReminder {
                        DatePicker("Date", selection: $remindAt,
                                   displayedComponents: [.date])
                            .datePickerStyle(.compact)

                        Toggle(isOn: $hasDeadline.animation(.easeInOut(duration: 0.2))) {
                            Label("Deadline", systemImage: "flag.checkered")
                        }
                        if hasDeadline {
                            DatePicker("Due", selection: $deadline, displayedComponents: [.date])
                                .datePickerStyle(.compact)
                        }
                    }
                } footer: {
                    Label(footerText, systemImage: bucket.symbolName)
                }
            }
            .alert("New Group", isPresented: $isNamingGroup) {
                TextField("Grants", text: $typedGroup)
                    .autocorrectionDisabled()
                Button("Add") {
                    guard let name = Project.cleanGroup(typedGroup) else { return }
                    groupSelection.wrappedValue = name
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Groups gather projects that belong together, such as Grants or Courses.")
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: add).disabled(!canAdd)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Projects while typing

    private func tint(for project: Project) -> Color {
        project.categoryID
            .flatMap { id in categories.first { $0.id == id } }?
            .color.prefixTint ?? .accentColor
    }

    /// A project brings its category with it; the picker can still change that
    /// for this one card, and giving the project back gives the category back.
    private func projectChosen(_ choice: ProjectChoice) {
        if choice == .none {
            categoryID = categoryBeforeProject ?? categoryID
            categoryBeforeProject = nil
            return
        }
        if categoryBeforeProject == nil { categoryBeforeProject = categoryID }
        if let category = category(for: choice) { categoryID = category }
    }

    private var isExistingProject: Bool {
        if case .existing = project { return true }
        return false
    }

    /// The groups already in use in the category the card is heading for.
    private var groupNames: [String] { store.groupNames(in: categoryID) }

    /// Reading and writing the group, whichever kind of project is chosen.
    ///
    /// An existing project is refiled for real, on the spot, because it is a
    /// property of the project rather than of this card — and changing it here
    /// changes it everywhere that project appears. A project that does not
    /// exist yet only records the choice; it is applied when the card is added
    /// and the project is actually created.
    private var groupSelection: Binding<String?> {
        Binding(
            get: {
                if case .existing(let chosen) = project { return chosen.group }
                return newProjectGroup
            },
            // Only ever the pending one: an existing project's group is read
            // here, never written.
            set: { newProjectGroup = $0 }
        )
    }

    /// The category a choice brings with it, if any.
    private func category(for choice: ProjectChoice) -> UUID? {
        guard case .existing(let chosen) = choice, let category = chosen.categoryID,
              categories.contains(where: { $0.id == category }) else { return nil }
        return category
    }

    private var footerText: String {
        switch bucket {
        // `Label` takes a plain String verbatim, so these have to be looked up
        // here or they ship in English however the app is set.
        case .inbox:    return String(localized: "This card goes to your inbox.",
                                      comment: "Footer under the New Task sheet")
        case .today:    return String(localized: "This card goes to Now.",
                                      comment: "Footer under the New Task sheet")
        case .tomorrow: return String(localized: "This card goes to Next.",
                                      comment: "Footer under the New Task sheet")
        case .later:    return String(localized: "This card goes to Later.",
                                      comment: "Footer under the New Task sheet")
        case .waiting:  return String(localized: "This card goes to Waiting.",
                                      comment: "Footer under the New Task sheet")
        case .completed: return ""
        }
    }

    /// Adding is guarded because Return can arrive by either route — as a
    /// submit, or as a line break the field below turns back into one — and on
    /// a platform that delivers both, an unguarded `add` would file the card
    /// twice.
    private func add() {
        guard canAdd, !didAdd else { return }
        didAdd = true
        onAdd(savedTitle, bucket, categoryID, project, newProjectGroup,
              hasReminder ? remindAt : nil,
              hasReminder && hasDeadline ? deadline : nil)
        dismiss()
    }
}

/// The title field and everything about choosing a project from it: the `#`
/// button, the suggestion chips, the pill, and the reading of a half-typed
/// `#word`.
///
/// One view, used when adding a card and when editing one. The gesture people
/// learn while writing a card has to work when they come back to it, and two
/// copies of this would have drifted apart the first time either was touched.
/// The parent decides what a chosen project *means* — New Task moves its own
/// category picker, the editor writes it to the card — so all this reports is
/// which project is now on the card.
struct ProjectTitleField: View {
    @Binding var title: String
    @Binding var project: ProjectChoice
    let projects: [Project]
    let lastUsed: [UUID: Date]
    /// The projects a card actually carries. Only what is *offered* is drawn
    /// from this — a typed name is still matched against every project, so an
    /// emptied one is reused rather than made a second time.
    var inUse: Set<UUID>? = nil
    let categories: [CardCategory]
    /// The category the card carries, for tinting the pill before a project
    /// has been chosen.
    let categoryID: UUID?
    var placeholder: LocalizedStringKey = "What needs doing?"
    @FocusState.Binding var focused: Bool
    /// Return true to swallow the submit; New Task adds the card on Return.
    var onSubmit: () -> Void = {}
    /// The project changed — taken from a typed word, a chip, or given back.
    var onProjectChosen: (ProjectChoice) -> Void = { _ in }

    @State private var isNaming = false
    @State private var typedName = ""

    /// The first word of the title — the only word a project can be made
    /// from. A `#` typed out of old habit comes off in `clean`, so the reflex
    /// still finds the project it used to.
    ///
    /// Nil once the card has a project: the word in front is then the title's
    /// own, and offering to take it away would be wrong.
    private func firstWord(of text: String) -> String? {
        guard project == .none else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let word = Project.clean(String(trimmed.prefix { !$0.isWhitespace }))
        return word.isEmpty ? nil : word
    }

    private var firstWord: String? { firstWord(of: title) }

    /// The title with its first word taken off, for when that word has become
    /// the project: a card draws its project as a coloured prefix, so leaving
    /// the word in would write the name twice.
    private func titleWithoutFirstWord(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let space = trimmed.firstIndex(where: \.isWhitespace) else { return "" }
        var rest = String(trimmed[space...]).trimmingCharacters(in: .whitespaces)
        // "BIO2140 - mark the sets" leaves "mark the sets".
        while let first = rest.first, "-\u{2013}\u{2014}:".contains(first) {
            rest = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return rest
    }

    var body: some View {
        // Top-aligned, not baseline-aligned: an empty vertical text field
        // reports its placeholder's baseline lower than typed text, so baseline
        // alignment made the pill jump as soon as typing began.
        HStack(alignment: .top, spacing: 8) {
            if let name = project.name {
                pill(name)
            }
            TextField(project.name == nil ? placeholder : "What needs doing?",
                      text: $title, axis: .vertical)
                .lineLimit(1...5)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(onSubmit)
                .onChange(of: title) { _, entered in handle(entered) }

            // Not a character any more. A project is made from the first
            // word of the title, so there is nothing to insert; what is left
            // is the job the hash was standing in for — reaching a project
            // the first word will not offer, either because it reads like a
            // word rather than a code or because it is not what is being
            // typed. On a phone keyboard `#` was two layer-switches away,
            // three on a layout that puts £ there. This is one tap.
            if project == .none {
                Menu {
                    ForEach(offered) { candidate in
                        Button(candidate.name) { pick(.existing(candidate)) }
                    }
                    if !offered.isEmpty { Divider() }
                    Button {
                        typedName = firstWord ?? ""
                        isNaming = true
                    } label: {
                        Label("New Project\u{2026}", systemImage: "plus")
                    }
                } label: {
                    Image(systemName: "number")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 32, height: 22)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Choose a project")
            }
        }
        .alert("New Project", isPresented: $isNaming) {
            TextField("TRIP", text: $typedName)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button("Add") {
                let name = Project.canonicalName(typedName)
                guard !name.isEmpty else { return }
                pick(Self.choice(for: name, in: projects) ?? .new(name),
                     typedAs: firstWord)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("A short one-word name for something you are working on.")
        }

        if !chips.isEmpty || createName != nil {
            chipRow
        }
    }

    /// Tab takes the first thing offered, the way it does everywhere else.
    private func complete(from text: String) {
        let word = firstWord(of: text)
        if let top = suggestions(for: text).first {
            pick(.existing(top), typedAs: word)
        } else if let name = newProjectName(for: text) {
            pick(.new(name), typedAs: word)
        }
    }

    // MARK: - Chips

    /// Every project that may be offered, for the picker.
    private var offered: [Project] {
        ProjectSuggestions.rank(projects, query: "", lastUsed: lastUsed,
                                inUse: inUse, limit: .max)
    }

    /// What the first word brings up. With nothing typed — or a first word
    /// that names nothing — the recent projects, as before.
    private func suggestions(for text: String) -> [Project] {
        guard project == .none else { return [] }
        guard let word = firstWord(of: text) else {
            return ProjectSuggestions.rank(projects, query: "", lastUsed: lastUsed,
                                           inUse: inUse, limit: 5)
        }
        let matches = ProjectSuggestions.rank(projects, query: word,
                                              lastUsed: lastUsed, inUse: inUse)
        return matches.isEmpty
            ? ProjectSuggestions.rank(projects, query: "", lastUsed: lastUsed,
                                      inUse: inUse, limit: 5)
            : matches
    }

    private var chips: [Project] { suggestions(for: title) }

    /// A new project is offered for a first word that reads like a code —
    /// capitals, or a digit in it. Any other word would put a chip under
    /// every title anyone ever writes, and most first words are just words.
    /// A name that is not code-like is still reachable, through the picker.
    private func newProjectName(for text: String) -> String? {
        guard project == .none, let word = firstWord(of: text),
              ProjectConversion.looksLikeCode(word),
              !projects.contains(where: { $0.key == Project.key(for: word) })
        else { return nil }
        return Project.canonicalName(word)
    }

    private var createName: String? { newProjectName(for: title) }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { candidate in
                    Button { pick(.existing(candidate), typedAs: firstWord) } label: {
                        chipLabel(candidate.name, tint: tint(for: candidate), filled: true)
                    }
                    .buttonStyle(.plain)
                }
                if let name = createName {
                    Button { pick(.new(name), typedAs: firstWord) } label: {
                        chipLabel("New project \(name)", tint: .secondary, filled: false)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func chipLabel(_ text: String, tint: Color, filled: Bool) -> some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(filled ? tint : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(filled ? tint.opacity(0.14) : Color.clear))
            .overlay(Capsule().strokeBorder(filled ? tint.opacity(0.35) : Color.secondary.opacity(0.4)))
    }

    private func pill(_ name: String) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { choose(.none) }
        } label: {
            HStack(spacing: 4) {
                Text(name).font(.body.weight(.semibold))
                Image(systemName: "xmark").font(.caption2.weight(.bold)).opacity(0.6)
            }
            .foregroundStyle(pillTint)
            .padding(.horizontal, 8)
            .padding(.vertical, 1)
            .background(Capsule().fill(pillTint.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Project \(name). Remove")
    }

    private func tint(for project: Project) -> Color {
        project.categoryID
            .flatMap { id in categories.first { $0.id == id } }?
            .color.prefixTint ?? .accentColor
    }

    private var pillTint: Color {
        if case .existing(let chosen) = project { return tint(for: chosen) }
        return categoryID.flatMap { id in categories.first { $0.id == id } }?.color.prefixTint ?? .accentColor
    }

    // MARK: - Reading the word being typed

    private func handle(_ entered: String) {
        // A Return typed into a field that wraps arrives as a line break, and
        // `onSubmit` never fires at all. A card's title is one line, so take
        // it for the submit it was meant to be. This lives here rather than at
        // the call sites because the New Task sheet went without it for want
        // of someone remembering to add it there too.
        var entered = entered

        // Tab arrives as a *character*, not as a key the view can intercept:
        // `onKeyPress(.tab)` never fires through a focused field, which was
        // tried and does not work. Taken out of the text and read as the
        // accept it was meant to be.
        if entered.contains("\t") {
            entered = entered.replacingOccurrences(of: "\t", with: "")
            title = entered
            complete(from: entered)
            return
        }

        if let typed = titleReturn(in: entered) {
            title = typed.cleaned
            if typed.isSubmit { onSubmit() }
        }

        // And nothing else. A first word is *offered*, never taken: the chips
        // below say what it could be and one of them has to be chosen. Typing
        // a space used to commit a project, which was the one place in the app
        // where something was written without being asked for.
    }

    /// The choice a typed word names: the project it matches, or a new one.
    /// Static because a sheet also has to resolve a word that was never
    /// finished with a space, on the way out.
    static func choice(for raw: String, in projects: [Project]) -> ProjectChoice? {
        let name = Project.clean(raw)
        guard !name.isEmpty else { return nil }
        if let match = projects.first(where: { $0.key == Project.key(for: name) }) {
            return .existing(match)
        }
        return .new(name)
    }

    private func resolve(_ raw: String) -> ProjectChoice? {
        Self.choice(for: raw, in: projects)
    }

    /// Taking a project that was offered.
    ///
    /// - Parameter typedAs: the first word that put it on offer, when it did.
    ///   The word comes out of the title only then — a card draws its project
    ///   as a coloured prefix, so leaving it would write the name twice.
    ///   Choosing from the recents while typing "Buy milk" is not that, and
    ///   the title is left exactly as typed.
    private func pick(_ choice: ProjectChoice, typedAs word: String? = nil) {
        let cameFromTheTitle = {
            guard let word, let name = choice.name else { return false }
            return Project.key(for: name) == Project.key(for: word)
        }()
        if cameFromTheTitle { title = titleWithoutFirstWord(title) }
        choose(choice)
        focused = true
    }

    private func choose(_ choice: ProjectChoice) {
        withAnimation(.easeOut(duration: 0.15)) { project = choice }
        onProjectChosen(choice)
    }

}
/// What opens when a card is tapped: its name, editable in place, with the same
/// controls the compose sheet uses so both read the same way.
///
/// Reads the card back out of the store on every change rather than holding a
/// copy, so the pickers stay honest when one edit implies another — dating a
/// card today moves its stack, and the Stack row updates to match.
struct CardActionsSheet: View {
    let itemID: UUID

    @EnvironmentObject private var store: TodoStore
    @Environment(\.dismiss) private var dismiss

    /// Everything the sheet can change, held here rather than written to the
    /// card as it is touched. The sheet used to edit the card live, which left
    /// nothing for a Cancel to undo and made Escape a commit by another name.
    ///
    /// A project named but not yet created lives here as `.new`, so a
    /// cancelled sheet leaves no project behind either.
    struct Draft: Equatable {
        var title = ""
        var bucket: Bucket = .inbox
        var categoryID: UUID?
        var project: ProjectChoice = .none
        /// The group the chosen project should end up in. A group belongs to
        /// the project rather than the card, so this is written to the project
        /// on Done like everything else.
        var group: String?
        var remindAt: Date?
        var deadline: Date?
    }

    @State private var draft = Draft()
    /// What the sheet opened on. Done writes only what differs from this, so
    /// opening the editor and closing it again changes nothing at all — and
    /// Cancel has something to mean.
    @State private var original = Draft()
    @State private var loaded = false
    @State private var isDiscarding = false
    private var isDirty: Bool { draft != original }

    @FocusState private var titleFocused: Bool
    @State private var isNamingProject = false
    @State private var isNamingGroup = false
    @State private var typedGroup = ""
    @State private var newProjectName = ""

    private var item: TodoItem? { store.items.first { $0.id == itemID } }

    var body: some View {
        NavigationStack {
            if let item {
                Form {
                    Section {
                        // The same field New Task uses, so `#` works here too:
                        // the button, the chips, the pill and the reading of a
                        // half-typed word are one view, not a lookalike.
                        ProjectTitleField(
                            title: $draft.title,
                            project: projectBinding,
                            projects: store.projects,
                            lastUsed: store.projectLastUsed,
                            inUse: store.projectsInUse,
                            categories: store.categories,
                            categoryID: draft.categoryID,
                            placeholder: "Title",
                            focused: $titleFocused,
                            onSubmit: { titleFocused = false }
                        )
                    }

                    Section {
                        projectRow()

                        // Only when the card has a project: a group is a label
                        // projects carry, so there is nothing to put in one
                        // until there is a project to put. A project only
                        // named so far counts — it will exist on Done.
                        if draft.project != .none {
                            ProjectGroupRow(
                                names: store.groupNames(in: draft.categoryID),
                                selection: $draft.group,
                                tint: store.categories
                                    .first { $0.id == draft.categoryID }?.color.prefixTint
                                    ?? Color.accentColor
                            ) {
                                typedGroup = ""
                                isNamingGroup = true
                            }
                        }

                        Picker(selection: $draft.bucket) {
                            ForEach(Bucket.quickMoveTargets) { target in
                                Label(target.title, systemImage: target.symbolName).tag(target)
                            }
                        } label: {
                            Label("Stack", systemImage: "tray.full")
                        }
                        .disabled(item.isCompleted)

                        Picker(selection: $draft.categoryID) {
                            Text("None").tag(UUID?.none)
                            ForEach(store.categories) { category in
                                Label(category.label, systemImage: category.symbolName)
                                    .tag(UUID?.some(category.id))
                            }
                        } label: {
                            Label("Category", systemImage: "tag")
                        }
                        .disabled(store.categories.isEmpty)

                        Toggle(isOn: hasReminderBinding.animation(.easeInOut(duration: 0.2))) {
                            Label("Remind me", systemImage: "flag")
                        }
                        if item.remindAt != nil {
                            DatePicker("Date", selection: reminderBinding,
                                       displayedComponents: [.date])
                                .datePickerStyle(.compact)
                        }

                        // Shown once there is a day to start from — or when
                        // the card already carries one, so a deadline left
                        // behind by clearing a reminder is never stranded
                        // somewhere it can be seen but not changed.
                        if draft.remindAt != nil || draft.deadline != nil {
                            Toggle(isOn: hasDeadlineBinding.animation(.easeInOut(duration: 0.2))) {
                                Label("Deadline", systemImage: "flag.checkered")
                            }
                            if draft.deadline != nil {
                                DatePicker("Due", selection: deadlineBinding,
                                           displayedComponents: [.date])
                                    .datePickerStyle(.compact)
                            }
                        }
                    }

                    Section {
                        Button {
                            // An explicit action, so the edit goes with it
                            // rather than being quietly dropped.
                            commit(item)
                            withAnimation { store.toggleCompleted(item) }
                            dismiss()
                        } label: {
                            Label(
                                item.isCompleted ? "Mark as Not Done" : "Complete",
                                systemImage: item.isCompleted
                                    ? "arrow.uturn.backward.circle" : "checkmark.circle"
                            )
                        }

                        Button(role: .destructive) {
                            withAnimation { store.delete(item) }
                            dismiss()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .navigationTitle("Task")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // Escape picks the cancellation role, which is the whole
                    // point: leaving by the keyboard must not write anything.
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { close() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            commit(item)
                            dismiss()
                        }
                    }
                }
                // Only once: the sheet stays alive across edits, and reloading
                // on every appearance would throw away what was typed.
                .onAppear { if !loaded { load(item) } }
                // Swiping down is the phone's Cancel, so an edit in progress
                // is not thrown away without being asked about. Nothing
                // changed, nothing to ask.
                .interactiveDismissDisabled(isDirty)
                .confirmationDialog("Discard changes?", isPresented: $isDiscarding) {
                    Button("Discard Changes", role: .destructive) { dismiss() }
                    Button("Keep Editing", role: .cancel) { }
                }
                .alert("New Group", isPresented: $isNamingGroup) {
                    TextField("Grants", text: $typedGroup)
                        .autocorrectionDisabled()
                    Button("Add") {
                        guard let name = Project.cleanGroup(typedGroup) else { return }
                        withAnimation { draft.group = name }
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("Groups gather projects that belong together, such as Grants or Courses.")
                }
                .alert("New Project", isPresented: $isNamingProject) {
                    TextField("TRIP", text: $newProjectName)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button("Add") {
                        let name = Project.clean(newProjectName)
                        guard !name.isEmpty else { return }
                        withAnimation {
                            draft.project = ProjectTitleField
                                .choice(for: name, in: store.projects) ?? .new(name)
                        }
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("A short one-word name for something you are working on.")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Leaving without Done. Asks first when there is something to lose, so
    /// neither Escape nor a swipe can throw an edit away in silence.
    private func close() {
        if isDirty { isDiscarding = true } else { dismiss() }
    }

    /// The stack the picker shows: a completed card still belongs to the one
    /// it was completed from.
    private static func effectiveBucket(_ item: TodoItem) -> Bucket {
        item.bucket == .completed ? (item.bucketBeforeCompletion ?? .inbox) : item.bucket
    }

    /// Reads the card into the draft. Done compares against this copy, so a
    /// sheet opened and closed again writes nothing at all.
    private func load(_ item: TodoItem) {
        let project = store.project(for: item)
        let start = Draft(title: item.title,
                          bucket: Self.effectiveBucket(item),
                          categoryID: item.categoryID,
                          project: project.map(ProjectChoice.existing) ?? .none,
                          group: project?.group,
                          remindAt: item.remindAt,
                          deadline: item.deadline)
        draft = start
        original = start
        loaded = true
    }

    /// Writes the draft to the card, and only what actually differs: a card
    /// whose edit date moved because its editor was opened would outrank a
    /// real edit made on another device.
    private func commit(_ item: TodoItem) {
        guard loaded else { return }

        // Nothing is ever half-typed now: a project is taken by a chip or by
        // Tab, and until then the first word is only the title's first word.
        let title = draft.title
        if title != item.title { store.rename(item, to: title) }

        // The project first: setting one moves the card's category to the
        // project's, so the category has to be written after it to win.
        let projectID: UUID?
        switch draft.project {
        case .none:
            projectID = nil
        case .existing(let project):
            projectID = project.id
        case .new(let name):
            projectID = store.ensureProject(named: name, categoryID: draft.categoryID,
                                            group: draft.group)?.id
        }
        if projectID != item.projectID { store.setProject(item, to: projectID) }

        // A group belongs to the project, not to this card, so it is written
        // only when it actually changed — otherwise opening the editor on one
        // card would restamp a project every other card shares.
        if let projectID, let project = store.project(id: projectID),
           draft.group != project.group {
            store.setProjectGroup(project, to: draft.group)
        }

        if draft.categoryID != store.items.first(where: { $0.id == item.id })?.categoryID {
            store.setCategory(item, to: draft.categoryID)
        }
        if draft.remindAt != item.remindAt { store.setReminder(item, at: draft.remindAt) }
        if draft.deadline != item.deadline {
            if let deadline = draft.deadline { store.setDeadline(item, to: deadline) }
            else { store.clearDeadline(item) }
        }
        if draft.bucket != Self.effectiveBucket(item) {
            withAnimation { store.move(item, to: draft.bucket) }
        }
    }

    /// The field and the Project row are two views of one fact, so neither
    /// holds its own copy: both read the draft. Given a copy to show, the pill
    /// went on offering a project the card no longer carried the moment the
    /// row below was used.
    private var projectBinding: Binding<ProjectChoice> {
        Binding(
            get: { draft.project },
            set: { choice in
                withAnimation(.easeOut(duration: 0.15)) {
                    draft.project = choice
                    // A project says where the work belongs, so it brings its
                    // category with it — the same move the New Task sheet makes.
                    if case .existing(let project) = choice {
                        draft.categoryID = project.categoryID
                        draft.group = project.group
                    }
                    if choice == .none { draft.group = nil }
                }
            }
        )
    }

    // MARK: - Project

    /// A menu rather than a picker so it can also offer "New Project…". Setting
    /// a project brings its category, exactly as in the New Task sheet.
    private func projectRow() -> some View {
        // Whatever the draft holds, which is not always a project that exists
        // yet: one named in the field is created on Done.
        let chosenID: UUID? = {
            if case .existing(let project) = draft.project { return project.id }
            return nil
        }()
        // The one the card already carries is always listed, even if it is the
        // last card and the project would otherwise have dropped out.
        let inUse = store.projectsInUse
        let offered = store.projects
            .filter { (!$0.isArchived && inUse.contains($0.id)) || $0.id == chosenID }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let tint = store.categories
            .first { $0.id == draft.categoryID }?.color.prefixTint ?? Color.accentColor

        return LabeledContent {
            Menu {
                Button {
                    projectBinding.wrappedValue = .none
                } label: {
                    if draft.project == .none {
                        Label("None", systemImage: "checkmark")
                    } else {
                        Text("None")
                    }
                }
                Divider()
                ForEach(offered) { project in
                    Button {
                        projectBinding.wrappedValue = .existing(project)
                    } label: {
                        if project.id == chosenID {
                            Label(project.name, systemImage: "checkmark")
                        } else {
                            Text(project.name)
                        }
                    }
                }
                Divider()
                Button {
                    newProjectName = ""
                    isNamingProject = true
                } label: {
                    Label("New Project…", systemImage: "plus")
                }
            } label: {
                Text(draft.project.name ?? "None")
                    .fontWeight(draft.project == .none ? .regular : .semibold)
                    .foregroundStyle(draft.project == .none ? Color.secondary : tint)
            }
        } label: {
            Label("Project", systemImage: "number")
        }
    }

    // MARK: - Bindings that write straight through to the store

    /// Opens on the day the card is to be started, not today: a finish line
    /// before the start is the one date that cannot be meant.
    private var deadlineDefault: Date {
        draft.remindAt.map { Scheduler.calendar.startOfDay(for: $0) } ?? Scheduler.startOfToday()
    }

    private var hasDeadlineBinding: Binding<Bool> {
        Binding(
            get: { draft.deadline != nil },
            set: { draft.deadline = $0 ? deadlineDefault : nil }
        )
    }

    private var deadlineBinding: Binding<Date> {
        Binding(
            get: { draft.deadline ?? deadlineDefault },
            set: { draft.deadline = $0 }
        )
    }

    private var hasReminderBinding: Binding<Bool> {
        Binding(
            get: { draft.remindAt != nil },
            set: { draft.remindAt = $0 ? Scheduler.defaultReminderTime() : nil }
        )
    }

    private var reminderBinding: Binding<Date> {
        Binding(
            get: { draft.remindAt ?? Scheduler.defaultReminderTime() },
            set: { draft.remindAt = $0 }
        )
    }
}
