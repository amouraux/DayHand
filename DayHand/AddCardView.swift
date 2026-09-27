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
    let categories: [CardCategory]
    let projects: [Project]
    /// When each project was last used, for ranking the chips.
    let projectLastUsed: [UUID: Date]
    let onAdd: (String, Bucket, UUID?, ProjectChoice, Date?) -> Void

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
        defaultCategoryID: UUID?,
        onAdd: @escaping (String, Bucket, UUID?, ProjectChoice, Date?) -> Void
    ) {
        self.categories = categories
        self.projects = projects
        self.projectLastUsed = projectLastUsed
        self.onAdd = onAdd
        // Pre-selected, not forced: it is an ordinary picker value the user can
        // change back to None before adding.
        _categoryID = State(initialValue: defaultCategoryID)
    }

    @State private var bucket: Bucket = .inbox
    @State private var hasDueDate = false
    @State private var dueDate = Scheduler.startOfToday()
    @FocusState private var focused: Bool
    /// Set once the card has been filed, so it cannot be filed again.
    @State private var didAdd = false

    /// The title as it will be saved: without a `#word` still being typed.
    private var titleWithoutToken: String {
        (ProjectToken.find(in: title)?.remainder ?? title)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAdd: Bool { !titleWithoutToken.isEmpty }

    /// A card in Later may not be dated today, tomorrow or earlier.
    private var dateFloor: Date? {
        bucket == .later ? Scheduler.earliestLaterDate() : nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ProjectTitleField(
                        title: $title,
                        project: $project,
                        projects: projects,
                        lastUsed: projectLastUsed,
                        categories: categories,
                        categoryID: categoryID,
                        focused: $focused,
                        onSubmit: add,
                        onProjectChosen: projectChosen
                    )
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

                    Toggle(isOn: $hasDueDate.animation(.easeInOut(duration: 0.2))) {
                        Label("Due date", systemImage: "calendar")
                    }

                    if hasDueDate {
                        Group {
                            if let dateFloor {
                                DatePicker("Date", selection: $dueDate, in: dateFloor...,
                                           displayedComponents: [.date])
                            } else {
                                DatePicker("Date", selection: $dueDate,
                                           displayedComponents: [.date])
                            }
                        }
                        .datePickerStyle(.compact)
                    }
                } footer: {
                    Label(footerText, systemImage: bucket.symbolName)
                }
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
            // Keep stack and date consistent, using the same rules as the rest
            // of the app, so the card can never be created in a state the next
            // launch would immediately correct.
            .onChange(of: dueDate) { _, newDate in reconcileDate(newDate) }
            .onChange(of: hasDueDate) { _, isOn in
                // Switching the date on defaults it to today. For a Later card
                // that would drag the stack to Today and quietly undo an
                // explicit choice, so push the date forward instead.
                guard isOn else { return }
                bucket == .later ? reconcileBucket(.later) : reconcileDate(dueDate)
            }
            .onChange(of: bucket) { _, newBucket in reconcileBucket(newBucket) }
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

    /// The category a choice brings with it, if any.
    private func category(for choice: ProjectChoice) -> UUID? {
        guard case .existing(let chosen) = choice, let category = chosen.categoryID,
              categories.contains(where: { $0.id == category }) else { return nil }
        return category
    }

    /// A date of today or tomorrow implies its stack, so move the picker to
    /// match rather than letting the two disagree.
    private func reconcileDate(_ date: Date) {
        // Later is excluded: its picker already refuses dates that would imply
        // another stack, and an explicit Later must not be overridden.
        guard hasDueDate, bucket != .later,
              let implied = Scheduler.autoStack(for: date), implied != bucket else { return }
        bucket = implied
    }

    /// Choosing a stack by hand wins, exactly as moving a card does: a date that
    /// contradicts it is dropped, and a Later card's date is pushed to the
    /// earliest day Later allows.
    private func reconcileBucket(_ newBucket: Bucket) {
        guard hasDueDate else { return }

        if newBucket == .later {
            let floor = Scheduler.earliestLaterDate()
            if dueDate < floor { dueDate = floor }
            return
        }
        if let implied = Scheduler.autoStack(for: dueDate), implied != newBucket {
            hasDueDate = false
        }
    }

    private var footerText: String {
        switch bucket {
        case .inbox:    return "This card goes to your inbox."
        case .today:    return "This card goes to Today."
        case .tomorrow: return "This card goes to Tomorrow."
        case .later:    return "This card goes to Later."
        case .completed: return ""
        }
    }

    /// Adding is guarded because Return can arrive by either route — as a
    /// submit, or as a line break the field below turns back into one — and on
    /// a platform that delivers both, an unguarded `add` would file the card
    /// twice.
    private func add() {
        guard canAdd, !didAdd else { return }
        // A `#word` typed but not yet finished with a space still counts.
        // Resolved into locals rather than written to state and read back.
        var choice = project
        var category = categoryID
        if let token = ProjectToken.find(in: title),
           let typed = ProjectTitleField.choice(for: token.query, in: projects) {
            choice = typed
            category = self.category(for: typed) ?? category
        }
        didAdd = true
        onAdd(titleWithoutToken, bucket, category, choice, hasDueDate ? dueDate : nil)
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
    let categories: [CardCategory]
    /// The category the card carries, for tinting the pill before a project
    /// has been chosen.
    let categoryID: UUID?
    var placeholder: LocalizedStringKey = "What needs doing?  #project"
    @FocusState.Binding var focused: Bool
    /// Return true to swallow the submit; New Task adds the card on Return.
    var onSubmit: () -> Void = {}
    /// The project changed — taken from a typed word, a chip, or given back.
    var onProjectChosen: (ProjectChoice) -> Void = { _ in }

    /// What follows a `#` while it is still being typed, or nil.
    @State private var query: String?
    /// The project taken from a word that is still being typed, so that typing
    /// on past a name that matched can give it back.
    @State private var adoptedID: UUID?

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

            // On the iPhone keyboard `#` is two layer-switches away — three on
            // a layout that puts £ there — which would undo the time a project
            // saves. One tap here starts one, and lists every project rather
            // than only the recent ones.
            if project == .none && query == nil {
                Button { insertHash() } label: {
                    Image(systemName: "number")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 32, height: 22)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Add a project")
            }
        }

        if !chips.isEmpty || createName != nil {
            chipRow
        }
    }

    // MARK: - Chips

    private var chips: [Project] {
        if let query {
            return ProjectSuggestions.rank(projects, query: query, lastUsed: lastUsed)
        }
        guard project == .none else { return [] }
        return ProjectSuggestions.rank(projects, query: "", lastUsed: lastUsed, limit: 5)
    }

    private var createName: String? {
        guard let query else { return nil }
        let name = Project.clean(query)
        guard !name.isEmpty else { return nil }
        return projects.contains { $0.key == Project.key(for: name) } ? nil : name
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { candidate in
                    Button { pick(.existing(candidate)) } label: {
                        chipLabel(candidate.name, tint: tint(for: candidate), filled: true)
                    }
                    .buttonStyle(.plain)
                }
                if let name = createName {
                    Button { pick(.new(name)) } label: {
                        chipLabel("Create #\(name)", tint: .secondary, filled: false)
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
        guard let token = ProjectToken.find(in: entered) else {
            query = nil
            release()
            return
        }
        if token.isFinished {
            // A space ends the word, which is taken exactly as typed: an
            // existing project if the name matches, otherwise a new one.
            adoptedID = nil
            if let choice = resolve(token.query) { choose(choice) }
            title = token.remainder.isEmpty ? "" : token.remainder + " "
            query = nil
        } else {
            query = token.query
            adopt(token.query)
        }
    }

    /// Taking the project the moment the letters name one, rather than waiting
    /// for a space: until then the sheet shows a category the card is not going
    /// to get, which reads as the tag having done nothing.
    private func adopt(_ typed: String) {
        let name = Project.clean(typed)
        let match = name.isEmpty ? nil : projects.first { $0.key == Project.key(for: name) }
        guard let match else { return release() }
        guard adoptedID != match.id else { return }
        adoptedID = match.id
        choose(.existing(match))
    }

    private func release() {
        guard adoptedID != nil else { return }
        adoptedID = nil
        withAnimation(.easeOut(duration: 0.15)) { choose(.none) }
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

    /// A tapped chip: take its project and drop the `#word` it completed.
    private func pick(_ choice: ProjectChoice) {
        if let token = ProjectToken.find(in: title) {
            title = token.remainder.isEmpty ? "" : token.remainder + " "
        }
        query = nil
        adoptedID = nil
        choose(choice)
        focused = true
    }

    private func choose(_ choice: ProjectChoice) {
        withAnimation(.easeOut(duration: 0.15)) { project = choice }
        onProjectChosen(choice)
    }

    private func insertHash() {
        if title.isEmpty || title.last?.isWhitespace == true {
            title += "#"
        } else {
            title += " #"
        }
    }
}

/// Pick a due date for a card.
///
/// A card in LATER may not be dated today, tomorrow or in the past, so for those
/// cards the picker simply starts at the day after tomorrow — the contradictory
/// dates are never offered rather than being rejected after the fact.
struct DatePickerSheet: View {
    let item: TodoItem
    let onPick: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var date: Date

    private let floor: Date?

    init(item: TodoItem, onPick: @escaping (Date) -> Void) {
        self.item = item
        self.onPick = onPick

        let earliest: Date? = item.bucket == .later ? Scheduler.earliestLaterDate() : nil
        self.floor = earliest

        let current = item.dueDate ?? Scheduler.startOfToday()
        _date = State(initialValue: max(current, earliest ?? current))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Group {
                    if let floor {
                        DatePicker(
                            "Due date",
                            selection: $date,
                            in: floor...,
                            displayedComponents: [.date]
                        )
                    } else {
                        DatePicker(
                            "Due date",
                            selection: $date,
                            displayedComponents: [.date]
                        )
                    }
                }
                .datePickerStyle(.graphical)
                .padding(.horizontal)

                if floor != nil {
                    Text("Cards in Later start from the day after tomorrow.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.top, 4)
                }

                Spacer(minLength: 0)
            }
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Set") {
                        onPick(date)
                        dismiss()
                    }
                }
            }
        }
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

    @State private var title = ""
    @FocusState private var titleFocused: Bool
    /// What the field shows as the card's project. Written straight through to
    /// the card, and read back from it when the sheet opens.
    @State private var editorProject: ProjectChoice = .none
    @State private var isNamingProject = false
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
                            title: $title,
                            project: $editorProject,
                            projects: store.projects,
                            lastUsed: store.projectLastUsed,
                            categories: store.categories,
                            categoryID: item.categoryID,
                            placeholder: "Title",
                            focused: $titleFocused,
                            onSubmit: {
                                commitTitle(item)
                                titleFocused = false
                            },
                            onProjectChosen: { choice in applyProject(choice, to: item) }
                        )
                        .onChange(of: title) { _, entered in
                            guard let typed = titleReturn(in: entered) else { return }
                            title = typed.cleaned
                            // Renaming saves as you go, so Return here only
                            // needs to commit and put the keyboard away.
                            if typed.isSubmit {
                                commitTitle(item)
                                titleFocused = false
                            }
                        }
                    }

                    Section {
                        projectRow(item)

                        if let split = firstWordProject(item) {
                            Button {
                                if let project = store.ensureProject(named: split.word,
                                                                     categoryID: item.categoryID) {
                                    title = split.rest
                                    store.rename(item, to: split.rest)
                                    withAnimation { store.setProject(item, to: project.id) }
                                }
                            } label: {
                                Label("Make \u{201C}\(split.word)\u{201D} a project",
                                      systemImage: "wand.and.stars")
                            }
                        }

                        Picker(selection: stackBinding(item)) {
                            ForEach(Bucket.quickMoveTargets) { target in
                                Label(target.title, systemImage: target.symbolName).tag(target)
                            }
                        } label: {
                            Label("Stack", systemImage: "tray.full")
                        }
                        .disabled(item.isCompleted)

                        Picker(selection: categoryBinding(item)) {
                            Text("None").tag(UUID?.none)
                            ForEach(store.categories) { category in
                                Label(category.label, systemImage: category.symbolName)
                                    .tag(UUID?.some(category.id))
                            }
                        } label: {
                            Label("Category", systemImage: "tag")
                        }
                        .disabled(store.categories.isEmpty)

                        Toggle(isOn: hasDateBinding(item).animation(.easeInOut(duration: 0.2))) {
                            Label("Due date", systemImage: "calendar")
                        }

                        if item.dueDate != nil {
                            Group {
                                if item.bucket == .later {
                                    DatePicker("Date", selection: dateBinding(item),
                                               in: Scheduler.earliestLaterDate()...,
                                               displayedComponents: [.date])
                                } else {
                                    DatePicker("Date", selection: dateBinding(item),
                                               displayedComponents: [.date])
                                }
                            }
                            .datePickerStyle(.compact)
                        }
                    }

                    Section {
                        Button {
                            commitTitle(item)
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
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            commitTitle(item)
                            dismiss()
                        }
                    }
                }
                .onAppear {
                    title = item.title
                    // The field shows what the card already carries, so the
                    // pill is there before anything is typed.
                    editorProject = store.project(for: item).map(ProjectChoice.existing) ?? .none
                }
                // Typing then dismissing by swipe must not lose the edit.
                .onDisappear { commitTitle(item) }
                .alert("New Project", isPresented: $isNamingProject) {
                    TextField("TRIP", text: $newProjectName)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button("Add") {
                        if let created = store.ensureProject(named: newProjectName, categoryID: item.categoryID) {
                            withAnimation { store.setProject(item, to: created.id) }
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

    /// A `#word` left unfinished when the sheet closes still counts, exactly as
    /// it does in New Task.
    private func takeTypedProject(_ item: TodoItem) -> Bool {
        guard let token = ProjectToken.find(in: title),
              let choice = ProjectTitleField.choice(for: token.query, in: store.projects)
        else { return false }

        title = token.remainder
        store.rename(item, to: token.remainder)
        editorProject = choice
        applyProject(choice, to: item)
        return true
    }

    /// The first word, when it reads like a code, is almost always the project
    /// the card belongs to — the same judgement the bulk conversion makes.
    private func firstWordProject(_ item: TodoItem) -> (word: String, rest: String)? {
        guard item.projectID == nil,
              let split = ProjectConversion.split(title),
              ProjectConversion.looksLikeCode(split.word) else { return nil }
        return split
    }

    /// A project chosen in the field goes straight onto the card, which also
    /// moves the card's category — the project is what says where the work
    /// belongs. A new name is created only once it is actually chosen.
    private func applyProject(_ choice: ProjectChoice, to item: TodoItem) {
        switch choice {
        case .none:
            withAnimation { store.setProject(item, to: nil) }
        case .existing(let project):
            withAnimation { store.setProject(item, to: project.id) }
        case .new(let name):
            if let created = store.ensureProject(named: name, categoryID: item.categoryID) {
                withAnimation { store.setProject(item, to: created.id) }
            }
        }
    }

    private func commitTitle(_ item: TodoItem) {
        if takeTypedProject(item) { return }
        store.rename(item, to: title)
    }

    // MARK: - Project

    /// A menu rather than a picker so it can also offer "New Project…". Setting
    /// a project brings its category, exactly as in the New Task sheet.
    private func projectRow(_ item: TodoItem) -> some View {
        let current = store.project(for: item)
        let offered = store.projects
            .filter { !$0.isArchived || $0.id == current?.id }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let tint = store.category(for: item)?.color.prefixTint ?? Color.accentColor

        return LabeledContent {
            Menu {
                Button {
                    withAnimation { store.setProject(item, to: nil) }
                } label: {
                    if current == nil { Label("None", systemImage: "checkmark") } else { Text("None") }
                }
                Divider()
                ForEach(offered) { project in
                    Button {
                        withAnimation { store.setProject(item, to: project.id) }
                    } label: {
                        if project.id == current?.id {
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
                Text(current?.name ?? "None")
                    .fontWeight(current == nil ? .regular : .semibold)
                    .foregroundStyle(current == nil ? Color.secondary : tint)
            }
        } label: {
            Label("Project", systemImage: "number")
        }
    }

    // MARK: - Bindings that write straight through to the store

    private func stackBinding(_ item: TodoItem) -> Binding<Bucket> {
        Binding(
            get: { item.bucket == .completed ? (item.bucketBeforeCompletion ?? .inbox) : item.bucket },
            set: { newBucket in withAnimation { store.move(item, to: newBucket) } }
        )
    }

    private func categoryBinding(_ item: TodoItem) -> Binding<UUID?> {
        Binding(
            get: { item.categoryID },
            set: { store.setCategory(item, to: $0) }
        )
    }

    private func hasDateBinding(_ item: TodoItem) -> Binding<Bool> {
        Binding(
            get: { item.dueDate != nil },
            set: { isOn in
                if isOn {
                    // Later refuses a date sooner than the day after tomorrow.
                    let start = item.bucket == .later
                        ? Scheduler.earliestLaterDate()
                        : Scheduler.startOfToday()
                    store.setDate(item, to: start)
                } else {
                    store.clearDate(item)
                }
            }
        )
    }

    private func dateBinding(_ item: TodoItem) -> Binding<Date> {
        Binding(
            get: { item.dueDate ?? Scheduler.startOfToday() },
            set: { store.setDate(item, to: $0) }
        )
    }
}
