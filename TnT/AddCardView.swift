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
    /// What follows a `#` still being typed, or nil when none is.
    @State private var projectQuery: String?

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
                    // Top-aligned, not baseline-aligned: an empty vertical text
                    // field reports its placeholder's baseline lower than typed
                    // text, so baseline alignment made the pill jump as soon as
                    // typing began.
                    HStack(alignment: .top, spacing: 8) {
                        if let name = project.name {
                            projectPill(name)
                        }
                        TextField(
                            project.name == nil ? "What needs doing?  #project" : "What needs doing?",
                            text: $title, axis: .vertical
                        )
                        .lineLimit(1...5)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(add)
                        .onChange(of: title) { _, entered in titleChanged(entered) }

                        // On the iPhone keyboard `#` is two layer-switches away,
                        // which would undo the time a project saves. One tap here
                        // starts one — and lists every project, not just recent ones.
                        if project == .none && projectQuery == nil {
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

                    if !chips.isEmpty || createChipName != nil {
                        chipRow
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

    /// Matching projects while a `#word` is being typed; otherwise, until a
    /// project is chosen, the most recent ones, so the common case needs no
    /// typing at all.
    private var chips: [Project] {
        if let projectQuery {
            return ProjectSuggestions.rank(projects, query: projectQuery, lastUsed: projectLastUsed)
        }
        guard project == .none else { return [] }
        return ProjectSuggestions.rank(projects, query: "", lastUsed: projectLastUsed, limit: 5)
    }

    /// Offered when what is being typed is not a project yet.
    private var createChipName: String? {
        guard let projectQuery else { return nil }
        let name = Project.clean(projectQuery)
        guard !name.isEmpty else { return nil }
        let key = Project.key(for: name)
        return projects.contains { $0.key == key } ? nil : name
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
                if let name = createChipName {
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

    /// The chosen project, in front of the title. Tapping it takes it off again.
    private func projectPill(_ name: String) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { project = .none }
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
        if case .existing(let project) = project { return tint(for: project) }
        return categoryID.flatMap { id in categories.first { $0.id == id } }?.color.prefixTint ?? .accentColor
    }

    private func titleChanged(_ entered: String) {
        if let typed = titleReturn(in: entered) {
            title = typed.cleaned
            if typed.isSubmit { add() }
            return
        }

        guard let token = ProjectToken.find(in: entered) else {
            projectQuery = nil
            return
        }
        if token.isFinished {
            // A space ends the word, which is taken exactly as typed: an
            // existing project if the name matches, otherwise a new one.
            // Completing a partial name is what the chips are for.
            take(literal: token.query)
            title = token.remainder.isEmpty ? "" : token.remainder + " "
            projectQuery = nil
        } else {
            projectQuery = token.query
        }
    }

    /// A chip was tapped: take its project and drop the `#word` it completed.
    private func pick(_ choice: ProjectChoice) {
        if let token = ProjectToken.find(in: title) {
            title = token.remainder.isEmpty ? "" : token.remainder + " "
        }
        projectQuery = nil
        choose(choice)
        focused = true
    }

    /// A typed name as a choice: the project it names, or a new one.
    private func resolve(literal raw: String) -> ProjectChoice? {
        let name = Project.clean(raw)
        guard !name.isEmpty else { return nil }
        if let match = projects.first(where: { $0.key == Project.key(for: name) }) {
            return .existing(match)
        }
        return .new(name)
    }

    private func take(literal raw: String) {
        if let choice = resolve(literal: raw) { choose(choice) }
    }

    /// The category a choice brings with it, if any.
    private func category(for choice: ProjectChoice) -> UUID? {
        guard case .existing(let chosen) = choice, let category = chosen.categoryID,
              categories.contains(where: { $0.id == category }) else { return nil }
        return category
    }

    /// Choosing a project brings its category with it; the category picker can
    /// still change that for this one card.
    private func choose(_ choice: ProjectChoice) {
        withAnimation(.easeOut(duration: 0.15)) { project = choice }
        if let category = category(for: choice) { categoryID = category }
    }

    private func insertHash() {
        if title.isEmpty || title.last?.isWhitespace == true {
            title += "#"
        } else {
            title += " #"
        }
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
        if let token = ProjectToken.find(in: title), let typed = resolve(literal: token.query) {
            choice = typed
            category = self.category(for: typed) ?? category
        }
        didAdd = true
        onAdd(titleWithoutToken, bucket, category, choice, hasDueDate ? dueDate : nil)
        dismiss()
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
    @State private var isNamingProject = false
    @State private var newProjectName = ""

    private var item: TodoItem? { store.items.first { $0.id == itemID } }

    var body: some View {
        NavigationStack {
            if let item {
                Form {
                    Section {
                        TextField("Title", text: $title, axis: .vertical)
                            .lineLimit(1...4)
                            .focused($titleFocused)
                            .submitLabel(.done)
                            .onSubmit { commitTitle(item) }
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
                .onAppear { title = item.title }
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

    private func commitTitle(_ item: TodoItem) {
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

/// Narrow the list to any mix of categories and projects. A card shows if it
/// matches any of them: "Teaching, and also STUDY2026".
///
/// A sheet rather than a menu, because a menu closes after every tap and
/// multi-select needs to stay open while several are picked. Projects sit under
/// their category — and, within it, under their group when they have one —
/// with their open-card count, and can be searched.
///
/// This is also where projects are organised into groups: long-press a project
/// (right-click on the Mac) to move it, or a group heading to rename it. Tapping
/// keeps its one job, selecting, so the two never clash.
struct FilterSheet: View {
    @Binding var categorySelection: Set<UUID>
    @Binding var projectSelection: Set<UUID>

    @EnvironmentObject private var store: TodoStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    /// A project waiting for the name of a new group to go into.
    @State private var newGroupFor: Project?
    /// A group waiting for its new name.
    @State private var renaming: GroupRef?
    @State private var nameField = ""

    /// A group is identified by its category and its label.
    struct GroupRef: Identifiable {
        let categoryID: UUID?
        let name: String
        var id: String { (categoryID?.uuidString ?? "none") + "/" + name }
    }

    private var categories: [CardCategory] { store.categories }
    private var openCounts: [UUID: Int] { store.openCardCounts }
    private var isEverything: Bool { categorySelection.isEmpty && projectSelection.isEmpty }

    /// Archived projects only appear while something of theirs is still open.
    private var visibleProjects: [Project] {
        store.projects
            .filter { !$0.isArchived || (openCounts[$0.id] ?? 0) > 0 || projectSelection.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Projects whose category no longer exists are shown with the loose ones.
    private func scope(of project: Project) -> UUID? {
        guard let id = project.categoryID, categories.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    private func layout(for category: CardCategory?) -> ProjectGroups.Layout {
        ProjectGroups.layout(of: visibleProjects.filter { scope(of: $0) == category?.id })
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        categorySelection.removeAll()
                        projectSelection.removeAll()
                    } label: {
                        row(symbol: "square.grid.2x2", tint: .secondary, text: "Everything",
                            count: nil, selected: isEverything, bold: false)
                    }
                }

                if search.isEmpty {
                    ForEach(categories) { category in
                        Section(category.label) {
                            categoryRow(category)
                            projectRows(layout(for: category), categoryID: category.id,
                                        tint: category.color.prefixTint)
                        }
                    }
                    let loose = layout(for: nil)
                    if !loose.groups.isEmpty || !loose.ungrouped.isEmpty {
                        Section("Other projects") {
                            projectRows(loose, categoryID: nil, tint: .primary)
                        }
                    }
                } else {
                    let key = Project.key(for: search)
                    Section("Projects") {
                        ForEach(visibleProjects.filter { $0.key.contains(key) }) { project in
                            projectRow(project, tint: tint(for: project), indented: false)
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search projects")
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("New Group", isPresented: Binding(
                get: { newGroupFor != nil }, set: { if !$0 { newGroupFor = nil } }
            ), presenting: newGroupFor) { project in
                TextField("Active", text: $nameField)
                Button("Move") {
                    withAnimation { store.setProjectGroup(project, to: nameField) }
                }
                Button("Cancel", role: .cancel) { }
            } message: { project in
                Text("A group for \(project.name) and others like it, such as Active or On hold.")
            }
            .alert("Rename Group", isPresented: Binding(
                get: { renaming != nil }, set: { if !$0 { renaming = nil } }
            ), presenting: renaming) { group in
                TextField("Name", text: $nameField)
                Button("Rename") {
                    withAnimation { store.renameGroup(group.name, in: group.categoryID, to: nameField) }
                }
                Button("Cancel", role: .cancel) { }
            } message: { group in
                Text("Renames \u{201C}\(group.name)\u{201D} on every project in it. Using another group\u{2019}s name joins the two.")
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Groups first, each under its heading, then the projects in no group.
    @ViewBuilder
    private func projectRows(_ layout: ProjectGroups.Layout, categoryID: UUID?, tint: Color) -> some View {
        ForEach(layout.groups, id: \.name) { group in
            groupRow(group.name, projects: group.projects, categoryID: categoryID)
            ForEach(group.projects) { projectRow($0, tint: tint, indented: true) }
        }
        ForEach(layout.ungrouped) { projectRow($0, tint: tint, indented: false) }
    }

    private func tint(for project: Project) -> Color {
        project.categoryID.flatMap { id in categories.first { $0.id == id } }?.color.prefixTint ?? .primary
    }

    private func categoryRow(_ category: CardCategory) -> some View {
        Button {
            toggle(category.id, in: $categorySelection)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: category.symbolName)
                    .foregroundStyle(category.tint)
                    .frame(width: 24)
                Text("All \(category.label)").foregroundStyle(Color.primary)
                Spacer()
                if categorySelection.contains(category.id) {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    /// A group heading. Tapping selects the whole group — or clears it, when all
    /// of it is already selected. It selects the projects in the group now; one
    /// moved in later is not picked up by a selection already made.
    private func groupRow(_ name: String, projects: [Project], categoryID: UUID?) -> some View {
        let ids = Set(projects.map(\.id))
        let allSelected = !ids.isEmpty && ids.isSubset(of: projectSelection)

        return Button {
            if allSelected {
                projectSelection.subtract(ids)
            } else {
                projectSelection.formUnion(ids)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                // Primary, not secondary: a dimmed heading in a list reads as
                // disabled, especially in dark mode.
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                Spacer()
                Text("All \(projects.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if allSelected {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                }
            }
        }
        .contextMenu {
            Button {
                nameField = name
                renaming = GroupRef(categoryID: categoryID, name: name)
            } label: {
                Label("Rename Group…", systemImage: "pencil")
            }
        }
        .accessibilityLabel("Group \(name), \(projects.count) projects")
        .accessibilityHint(allSelected ? "Clears the group" : "Selects the whole group")
    }

    private func projectRow(_ project: Project, tint: Color, indented: Bool) -> some View {
        Button {
            toggle(project.id, in: $projectSelection)
        } label: {
            row(symbol: "number", tint: tint, text: project.name,
                count: openCounts[project.id] ?? 0,
                selected: projectSelection.contains(project.id), bold: true)
                .padding(.leading, indented ? 20 : 0)
        }
        .contextMenu { moveMenu(project) }
    }

    /// Move to Group: the category's existing groups, a new one, or none —
    /// listed straight in the long-press menu under a heading, not behind a
    /// submenu, since moving is the menu's only job.
    @ViewBuilder
    private func moveMenu(_ project: Project) -> some View {
        let groups = store.groupNames(in: project.categoryID)
        Section("Move \(project.name) to Group") {
            ForEach(groups, id: \.self) { name in
                Button {
                    withAnimation { store.setProjectGroup(project, to: name) }
                } label: {
                    if Project.groupKey(for: name) == project.group.map(Project.groupKey) {
                        Label(name, systemImage: "checkmark")
                    } else {
                        Text(name)
                    }
                }
            }
            if !groups.isEmpty { Divider() }
            Button {
                nameField = ""
                newGroupFor = project
            } label: {
                Label("New Group…", systemImage: "folder.badge.plus")
            }
            if project.group != nil {
                Button {
                    withAnimation { store.setProjectGroup(project, to: nil) }
                } label: {
                    Label("No Group", systemImage: "folder.badge.minus")
                }
            }
        }
    }

    private func row(symbol: String, tint: Color, text: String, count: Int?, selected: Bool, bold: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 24)
            Text(text)
                .fontWeight(bold ? .semibold : .regular)
                .foregroundStyle(bold ? tint : Color.primary)
            Spacer()
            if let count {
                Text("\(count)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if selected {
                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
            }
        }
    }

    private func toggle(_ id: UUID, in selection: Binding<Set<UUID>>) {
        if selection.wrappedValue.contains(id) {
            selection.wrappedValue.remove(id)
        } else {
            selection.wrappedValue.insert(id)
        }
    }
}
