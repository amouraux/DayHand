import SwiftUI


/// Projects are organised in Organise — long-press one, or right-click it on
/// the Mac — so there is no second screen listing them. What is left here is
/// the editor that menu opens, and the one-time conversion of title prefixes
/// written before projects existed.

/// The group choices for one project: the groups already in its category, a
/// new one, or none.
///
/// Shown twice — from the filter's long-press menu and from the editor's Group
/// row — which is two copies of the same list of buttons, and they drifted
/// apart within an hour of the second one being written. Naming the new group
/// is the only difference, so it is the only thing passed in.
/// The group a project belongs to, as one row.
///
/// Offered wherever a project is being chosen — the New Task sheet and the card
/// editor — because a group is easiest to set at the moment the project is
/// first named, and hunting for Organise afterwards is how projects end up
/// ungrouped forever.
///
/// Shown only when there *is* a project. A group with nothing in it is not a
/// thing this app has: groups are labels the projects carry, so offering one
/// before there is a project to carry it would be offering nothing.
struct ProjectGroupRow: View {
    let names: [String]
    @Binding var selection: String?
    let tint: Color
    /// False where changing it would be a side effect the surrounding screen
    /// has promised not to have — see the New Task sheet.
    var editable: Bool = true
    /// A line under the label saying who else this change reaches. A group sits
    /// on the project, so setting it from a task is the one control on that
    /// screen that edits something other than the task in front of you — and
    /// the only place that is visible is here, on the control itself.
    var note: String?
    let onNewGroup: () -> Void

    var body: some View {
        LabeledContent {
            if !editable {
                Text(selection ?? "None")
                    .fontWeight(selection == nil ? .regular : .semibold)
                    .foregroundStyle(selection == nil ? Color.secondary : tint)
            } else {
            Menu {
                Button {
                    withAnimation { selection = nil }
                } label: {
                    if selection == nil { Label("None", systemImage: "checkmark") } else { Text("None") }
                }
                if !names.isEmpty { Divider() }
                ForEach(names, id: \.self) { name in
                    Button {
                        withAnimation { selection = name }
                    } label: {
                        if Project.groupKey(for: name) == selection.map(Project.groupKey) {
                            Label(name, systemImage: "checkmark")
                        } else {
                            Text(name)
                        }
                    }
                }
                Divider()
                Button(action: onNewGroup) {
                    Label("New Group…", systemImage: "folder.badge.plus")
                }
            } label: {
                Text(selection ?? "None")
                    .fontWeight(selection == nil ? .regular : .semibold)
                    .foregroundStyle(selection == nil ? Color.secondary : tint)
            }
            }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Group")
                    if let note {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: "folder")
            }
        }
    }
}

struct ProjectGroupMenu: View {
    let project: Project
    /// Called when the user wants a group that does not exist yet; each caller
    /// asks for the name in whatever way suits where it is presented.
    let onNewGroup: () -> Void

    @EnvironmentObject private var store: TodoStore

    var body: some View {
        let groups = store.groupNames(in: project.categoryID)
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
        Button(action: onNewGroup) {
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

/// One project: its name, its category, archived or not, and the ways to fold
/// it into another or remove it.
///
/// Reached by long-pressing a project in Organise — right-clicking it on the
/// Mac — which is the one place projects are organised.
struct ProjectEditor: View {
    let projectID: UUID

    @EnvironmentObject private var store: TodoStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    /// Set when a rename hits another project's name, which makes it a merge.
    @State private var collision: Project?
    @State private var mergeTarget: Project?
    @State private var isConfirmingDelete = false
    /// Set when Archive was asked for while cards are still open.
    @State private var isConfirmingArchive = false
    /// Set while a new group is being named.
    @State private var isNamingGroup = false
    @State private var groupField = ""
    /// Set when bringing an archived project back is declined at the free limit.
    @State private var paywall: PaywallReason?

    private var project: Project? { store.project(id: projectID) }

    var body: some View {
        Group {
            if let project {
                form(project)
            } else {
                // Merged away or deleted from here, or from another device.
                ContentUnavailableView("Project removed", systemImage: "paperclip")
            }
        }
        .navigationTitle(project?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $paywall) { PaywallView(reason: $0).environmentObject(store) }
        .alert("New Group", isPresented: $isNamingGroup) {
            TextField("Holidays", text: $groupField)
            Button("Move") {
                if let project { withAnimation { store.setProjectGroup(project, to: groupField) } }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("A group for \(project?.name ?? "") and others like it, such as Holidays or Clients.")
        }
        .confirmationDialog(
            "Archive \(project?.name ?? "")?",
            isPresented: $isConfirmingArchive,
            titleVisibility: .visible
        ) {
            if let project {
                Button("Complete and Archive") {
                    store.completeAllAndArchive(project)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            // Says what will happen to the cards, since that is the part the
            // user did not ask for.
            Text("\(project.map { store.openCards(in: $0).count } ?? 0) tasks are still to do. They are marked completed.")
        }
    }

    private func form(_ project: Project) -> some View {
        formBody(project)
            // Changing the category here moves every task in the project. The
            // bar is how that is taken back, and an overlay on the list behind
            // this sheet would not be visible from inside it.
            .overlay(alignment: .bottom) { UndoBanner().environmentObject(store) }
    }

    private func formBody(_ project: Project) -> some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { commitName(project) }
            } header: {
                Text("Name")
            } footer: {
                Text("Renaming changes it on every task at once.")
            }

            Section {
                Picker(selection: Binding(
                    get: { project.categoryID },
                    set: { store.setProjectCategory(project, to: $0) }
                )) {
                    Text("None").tag(UUID?.none)
                    ForEach(store.categories) { category in
                        Label(category.label, systemImage: category.symbolName)
                            .tag(UUID?.some(category.id))
                    }
                } label: {
                    Label("Category", systemImage: "tag")
                }

                groupPicker(project)

                Button {
                    groupField = ""
                    isNamingGroup = true
                } label: {
                    Label("New Group…", systemImage: "folder.badge.plus")
                }

            } footer: {
                Text("Every task in this project moves with it, and new ones start here too. Moving a project to another category also takes it out of its group.")
            }

            // An action, not a setting: archiving has something to finish
            // first, so it asks rather than flicking back.
            // Before archiving, which is what you do once you have looked.
            Section {
                let finished = store.items.filter { $0.projectID == project.id && $0.isCompleted }
                NavigationLink {
                    TimelineView(title: project.name, cards: finished)
                        .environmentObject(store)
                } label: {
                    LabeledContent {
                        Text("\(finished.count)").monospacedDigit()
                    } label: {
                        Label("History", systemImage: "calendar.day.timeline.left")
                    }
                }
                .disabled(finished.isEmpty)
            } footer: {
                Text("When the work on this project actually landed, month by month.")
            }

            Section {
                if project.isArchived {
                    Button {
                        // Bringing one back takes a slot, like making one.
                        if store.canAddProject {
                            store.setProjectArchived(project, false)
                        } else {
                            paywall = .project(name: nil)
                        }
                    } label: {
                        Label("Unarchive Project", systemImage: "tray.and.arrow.up")
                    }
                } else {
                    Button {
                        if store.openCards(in: project).isEmpty {
                            store.setProjectArchived(project, true)
                        } else {
                            isConfirmingArchive = true
                        }
                    } label: {
                        Label("Archive Project", systemImage: "archivebox")
                    }
                }
            } footer: {
                if project.isArchived {
                    Text("Archived. Its tasks are still there, and it is left out of the project list until the Show row in Organise asks for archived projects. Typing its name brings it back.")
                } else if store.openCards(in: project).isEmpty {
                    Text("Nothing left to do, so this project can be put away.")
                } else {
                    Text("A project is archived once it is over, so anything still to do is marked completed first.")
                }
            }

            Section {
                let others = store.projects
                    .filter { $0.id != project.id }
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                Menu {
                    ForEach(others) { other in
                        Button(other.name) { mergeTarget = other }
                    }
                } label: {
                    Label("Merge Into…", systemImage: "arrow.triangle.merge")
                }
                .disabled(others.isEmpty)

                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Label("Delete Project", systemImage: "trash")
                }
            } footer: {
                Text("\(store.cardCount(using: project)) tasks in this project.")
            }
        }
        .onAppear { name = project.name }
        .onDisappear { commitName(project) }
        .confirmationDialog(
            "\(collision?.name ?? "") already exists",
            isPresented: Binding(get: { collision != nil }, set: { if !$0 { collision = nil } }),
            titleVisibility: .visible,
            presenting: collision
        ) { other in
            Button("Merge \(project.name) into \(other.name)") {
                store.mergeProject(project, into: other)
                dismiss()
            }
            Button("Keep \(project.name)", role: .cancel) { name = project.name }
        } message: { other in
            Text("Its \(store.cardCount(using: project)) tasks will move to \(other.name).")
        }
        .confirmationDialog(
            "Merge into \(mergeTarget?.name ?? "")?",
            isPresented: Binding(get: { mergeTarget != nil }, set: { if !$0 { mergeTarget = nil } }),
            titleVisibility: .visible,
            presenting: mergeTarget
        ) { target in
            Button("Merge") {
                store.mergeProject(project, into: target)
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: { target in
            Text("\(project.name)\u{2019}s \(store.cardCount(using: project)) tasks move to \(target.name), and \(project.name) is removed.")
        }
        .confirmationDialog(
            "Delete \(project.name)?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Project", role: .destructive) {
                store.deleteProject(project)
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Its tasks are kept. They just no longer belong to a project.")
        }
    }

    /// A Picker, like Category beside it, rather than a Menu with a hand-drawn
    /// value: a Menu's label is the parent's to draw, and a pop-up button on
    /// the Mac does not draw it the same way. A Picker states its own
    /// selection on every platform. Lifted out of the Form because the section
    /// had grown past what the type-checker would take.
    private func groupPicker(_ project: Project) -> some View {
        let names = store.groupNames(in: project.categoryID)

        return Picker(selection: Binding<String?>(
            get: { project.group },
            set: { chosen in withAnimation { store.setProjectGroup(project, to: chosen) } }
        )) {
            Text("None").tag(String?.none)
            ForEach(names, id: \.self) { name in
                Text(name).tag(String?.some(name))
            }
        } label: {
            Label("Group", systemImage: "folder")
        }
    }

    private func commitName(_ project: Project) {
        guard store.project(id: project.id) != nil else { return }
        switch store.renameProject(project, to: name) {
        case .collides(let other):
            collision = other
        case .invalid:
            name = project.name
        case .renamed, .unchanged:
            break
        }
    }
}

/// The one-time conversion: first words that look like project codes, each
/// with the cards it would take. Code-like words start ticked; ordinary words
/// start unticked, because a verb at the start of a title is not a project.
struct ProjectConversionView: View {
    let candidates: [ProjectConversion.Candidate]

    @EnvironmentObject private var store: TodoStore
    @Environment(\.dismiss) private var dismiss

    @State private var chosen: Set<String> = []
    /// Candidate id -> the project name to convert it into, when it should be
    /// folded into a similar one (STUDY into STUDY2026).
    @State private var target: [String: String] = [:]
    @State private var didSeed = false

    private var cardTotal: Int {
        candidates.filter { chosen.contains($0.id) }.reduce(0) { $0 + $1.cardIDs.count }
    }

    var body: some View {
        List {
            Section {
                ForEach(candidates) { candidate in
                    row(candidate)
                }
            } footer: {
                Text("Each ticked word becomes a project and is removed from the start of those titles. A new project takes the category most of its tasks have.")
            }
        }
        .navigationTitle("Convert Prefixes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Convert \(cardTotal)") { convert() }
                    .disabled(cardTotal == 0)
            }
        }
        .onAppear {
            guard !didSeed else { return }
            didSeed = true
            chosen = Set(candidates.filter(\.looksLikeCode).map(\.id))
        }
    }

    private func row(_ candidate: ProjectConversion.Candidate) -> some View {
        let isOn = chosen.contains(candidate.id)
        let samples = store.items
            .filter { candidate.cardIDs.contains($0.id) }
            .prefix(2)
            .compactMap { ProjectConversion.split($0.title)?.rest }

        return VStack(alignment: .leading, spacing: 6) {
            Button {
                if isOn { chosen.remove(candidate.id) } else { chosen.insert(candidate.id) }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(candidate.name).fontWeight(.semibold)
                            if store.project(named: candidate.name) != nil {
                                Text("existing").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(candidate.cardIDs.count) tasks")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Text(samples.joined(separator: " · "))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(Color.primary)
            }
            .buttonStyle(.plain)

            if isOn && !candidate.similar.isEmpty {
                Picker("Convert as", selection: Binding(
                    get: { target[candidate.id] ?? candidate.name },
                    set: { target[candidate.id] = $0 }
                )) {
                    Text(candidate.name).tag(candidate.name)
                    ForEach(candidate.similar, id: \.self) { name in
                        Text("Merge into \(name)").tag(name)
                    }
                }
                .font(.subheadline)
                .padding(.leading, 32)
            }
        }
        .padding(.vertical, 2)
    }

    private func convert() {
        let assignments = candidates
            .filter { chosen.contains($0.id) }
            .map { TodoStore.ProjectAssignment(cardIDs: $0.cardIDs, projectName: target[$0.id] ?? $0.name) }
        // The count is discarded explicitly: as the closure's only expression
        // it would otherwise become withAnimation's return value, which nothing
        // reads — @discardableResult covers the function, not the wrapper.
        withAnimation { _ = store.convertTitlePrefixes(assignments) }
        dismiss()
    }
}

/// A project made from nothing, before there is a task to put in it.
///
/// Every other way to create one starts from a task — type a first word, take
/// the chip — which is right when capturing and wrong when setting up, where
/// the whole point is to lay out the categories and projects first and add
/// work to them afterwards.
///
/// Name, category and group in one sheet, because a project created with no
/// category lands in "Other projects" and has to be moved immediately, which
/// is the opposite of what someone setting up is trying to do.
struct NewProjectSheet: View {
    @EnvironmentObject private var store: TodoStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var categoryID: UUID?
    @State private var group: String?
    @State private var isNamingGroup = false
    /// Set when creating is declined at the free limit.
    @State private var paywall: PaywallReason?
    @State private var typedGroup = ""
    @FocusState private var nameFocused: Bool

    /// Blank, or already taken. A name that belongs to another project would
    /// quietly become that project rather than a new one.
    private var problem: String? {
        guard let cleaned = Project.clean(name).isEmpty ? nil : Project.clean(name) else { return nil }
        let key = Project.key(for: cleaned)
        guard store.projects.contains(where: { $0.key == key }) else { return nil }
        return String(localized: "A project called \(Project.canonicalName(cleaned)) already exists.")
    }

    private var canCreate: Bool {
        !Project.clean(name).isEmpty && problem == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .focused($nameFocused)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onSubmit { if canCreate { create() } }
                } footer: {
                    if let problem {
                        Text(problem).foregroundStyle(.red)
                    } else {
                        Text("Capitals are added for you, the way a project typed into a task gets them.")
                    }
                }

                Section {
                    Picker(selection: $categoryID) {
                        Text("None").tag(UUID?.none)
                        ForEach(store.categories) { category in
                            Label(category.label, systemImage: category.symbolName)
                                .tag(UUID?.some(category.id))
                        }
                    } label: {
                        Label("Category", systemImage: "tag")
                    }

                    ProjectGroupRow(
                        names: store.groupNames(in: categoryID),
                        selection: $group,
                        tint: store.categories.first { $0.id == categoryID }?.color.prefixTint
                              ?? Color.accentColor
                    ) {
                        typedGroup = ""
                        isNamingGroup = true
                    }
                } footer: {
                    Text("Tasks given this project take its category. A group gathers projects that belong together.")
                }
            }
            .navigationTitle("New Project")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $paywall) { PaywallView(reason: $0).environmentObject(store) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }.disabled(!canCreate)
                }
            }
            .alert("New Group", isPresented: $isNamingGroup) {
                TextField("Holidays", text: $typedGroup)
                Button("Add") { group = Project.cleanGroup(typedGroup) }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Groups gather projects that belong together, such as Grants or Courses.")
            }
            // A category moving means its groups change with it, and a label
            // from the old one would be carried into a category that has no
            // such group.
            .onChange(of: categoryID) { _, _ in group = nil }
            .onAppear {
                categoryID = store.defaultCategoryID
                nameFocused = true
            }
        }
    }

    private func create() {
        guard canCreate else { return }
        // At the free limit the sheet stays open, with its name still typed,
        // and says why instead of closing on nothing.
        guard store.projectAccess(named: name) != .needsUnlock else {
            paywall = .project(name: nil)
            return
        }
        _ = store.ensureProject(named: name, categoryID: categoryID, group: group)
        dismiss()
    }
}

/// A project overview remains visible until the user accepts it. Task edits,
/// adding a next step and a nested review all return to this same overview.
struct ProjectReviewView: View {
    @EnvironmentObject private var store: TodoStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("projectReviewSession.v1") private var savedSession = ""
    @State private var session: ProjectReviewSession?
    @State private var editingTask: TodoItem?
    @State private var presentation: Presentation?

    private struct Presentation: Identifiable {
        enum Kind: String { case add, tasks, edit, history }
        let project: Project
        let kind: Kind
        var id: String { "\(project.id)-\(kind.rawValue)" }
    }

    private var project: Project? {
        session?.currentID.flatMap { id in store.projects.first { $0.id == id && !$0.isArchived } }
    }

    private func openTasks(_ id: UUID) -> [TodoItem] {
        store.items.filter { $0.projectID == id && !$0.isCompleted }
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            if let project {
                overview(project)
            } else if session != nil {
                VStack(spacing: 0) {
                    ContentUnavailableView {
                        Label("Project review finished", systemImage: "checkmark.circle")
                    } description: {
                        Text("Your projects are reviewed one at a time. New projects will be included in your next pass.")
                    } actions: {
                        Button("Start a new project review") { start() }
                            .buttonStyle(.borderedProminent)
                        if session?.canGoBack == true {
                            Button("Previous project") { goBack() }
                                .buttonStyle(.bordered)
                        }
                    }
                    UndoBanner(bottomPadding: 16).environmentObject(store)
                }
            }
        }
        .navigationTitle("Review projects")
        .navigationBarTitleDisplayMode(.inline)
        // The system's back chevron leaves the review, which reads as "go back
        // to the project I just left". So the chevron does that, and leaving is
        // a cross at the other end. Dimmed on the first project rather than
        // hidden, so the bar does not change shape between one project and
        // the next.
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { goBack() } label: {
                    Label("Previous project", systemImage: "chevron.backward")
                }
                .disabled(session?.canGoBack != true)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button { dismiss() } label: {
                    Label("Close", systemImage: "xmark")
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .onAppear {
            guard session == nil else { return }
            if let data = savedSession.data(using: .utf8),
               let restored = try? JSONDecoder().decode(ProjectReviewSession.self, from: data) {
                session = restored
                reconcile()
            } else { start() }
        }
        .onChange(of: session) { _, _ in persist() }
        .onChange(of: store.items) { _, _ in reconcile() }
        .onChange(of: store.projects) { _, _ in reconcile() }
        .sheet(item: $editingTask) { card in
            CardActionsSheet(itemID: card.id).environmentObject(store)
        }
        .sheet(item: $presentation) { selected in
            presented(selected)
        }
    }

    private func overview(_ project: Project) -> some View {
        let tasks = openTasks(project.id)
        let remaining = session?.remaining(projects: store.projects, cards: store.items) ?? []
        let count = remaining.filter { $0.id != project.id }.count + 1
        return VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    Text("\(count) projects left in this review")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(project.name).font(.title2.weight(.semibold))
                    if let category = store.categories.first(where: { $0.id == project.categoryID }) {
                        Label(category.label, systemImage: category.symbolName)
                            .foregroundStyle(category.color.prefixTint)
                    }
                    if let group = project.group { Label(group, systemImage: "folder") }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], alignment: .leading, spacing: 8) {
                        ForEach(StackReviewSession.allOpenBuckets) { bucket in
                            Label("\(bucket.title) \(tasks.filter { $0.bucket == bucket }.count)", systemImage: bucket.symbolName)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    observations(tasks)
                    if tasks.isEmpty {
                        Text("No unfinished tasks. If this project is over, archive it.")
                            .foregroundStyle(.secondary)
                        // Nothing is open, so there is nothing to confirm, as in
                        // the editor. Archiving ends the visit and moves on.
                        Button {
                            store.setProjectArchived(project, true)
                        } label: {
                            Label("Archive Project", systemImage: "archivebox")
                        }
                        .buttonStyle(.bordered)
                    }
                    ForEach(StackReviewSession.allOpenBuckets) { bucket in
                        let cards = store.items(in: bucket).filter { $0.projectID == project.id }
                        if !cards.isEmpty {
                            Text(bucket.title).font(.headline).accessibilityAddTraits(.isHeader)
                            ForEach(cards) { card in
                                CardRow(item: card, category: store.category(for: card),
                                    onTap: { editingTask = card },
                                    onToggle: { store.toggleCompleted(card) },
                                    onMove: { store.move(card, to: card.bucket.forwardDestination) },
                                    onEdit: { editingTask = card })
                                    .id("\(card.id)-\(card.bucket.rawValue)")
                            }
                        }
                    }
                    Button {
                        presentation = Presentation(project: project, kind: .history)
                    } label: {
                        Label("History", systemImage: "calendar.day.timeline.left")
                    }
                    .disabled(!store.items.contains { $0.projectID == project.id && $0.isCompleted })
                    Text("Projects with nothing left to do come last, so you can archive them. Tasks without a project stay in the task reviews.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: 600, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(20)
            }
            .id(project.id)
            UndoBanner(bottomPadding: 8).environmentObject(store)
            VStack(spacing: 10) {
                Text("Does this project have a clear way forward?")
                    .font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    Button {
                        session?.advance(projects: store.projects, cards: store.items)
                    } label: {
                        Label("Looks right — next project", systemImage: "checkmark")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    action("Add a task", symbol: "plus", project: project, kind: .add)
                    action("Review these tasks", symbol: "square.stack.3d.up", project: project, kind: .tasks)
                        .disabled(tasks.isEmpty)
                    action("Edit project", symbol: "pencil", project: project, kind: .edit)
                }
            }
            .padding(16)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
    }

    @ViewBuilder private func observations(_ tasks: [TodoItem]) -> some View {
        if !tasks.isEmpty && tasks.allSatisfy({ $0.bucket == .later }) {
            Text("All remaining tasks are in Later.").foregroundStyle(.secondary)
        }
        if tasks.contains(where: { $0.bucket == .waiting }) &&
            !tasks.contains(where: { $0.bucket == .today || $0.bucket == .tomorrow }) {
            Text("This project has tasks in Waiting, but none in Now or Next.").foregroundStyle(.secondary)
        }
        if tasks.contains(where: { $0.bucket == .inbox }) {
            Text("There are tasks in Inbox still to organise.").foregroundStyle(.secondary)
        }
    }

    private func action(_ title: LocalizedStringKey, symbol: String, project: Project,
                        kind: Presentation.Kind) -> some View {
        Button {
            presentation = Presentation(project: project, kind: kind)
        } label: {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder private func presented(_ selected: Presentation) -> some View {
        if selected.kind == .add {
            AddCardView(categories: store.categories, projects: store.projects,
                projectLastUsed: store.projectLastUsed, projectsInUse: store.projectsInUse,
                defaultCategoryID: selected.project.categoryID, defaultProject: selected.project,
                onAdd: addTask)
                .environmentObject(store)
        } else {
            NavigationStack {
                Group {
                    switch selected.kind {
                    case .tasks:
                        StackReviewView(stack: .all, projectID: selected.project.id, sharedSession: Binding(
                            get: { session?.tasks },
                            set: { if let tasks = $0 { session?.tasks = tasks } }
                        )).environmentObject(store)
                    case .edit:
                        ProjectEditor(projectID: selected.project.id).environmentObject(store)
                    case .history:
                        TimelineView(title: selected.project.name,
                            cards: store.items.filter { $0.projectID == selected.project.id && $0.isCompleted })
                            .environmentObject(store)
                    case .add: EmptyView()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Back to project") { presentation = nil }
                            .keyboardShortcut(.cancelAction)
                    }
                }
            }
        }
    }

    private func addTask(title: String, bucket: Bucket, categoryID: UUID?, projectChoice: ProjectChoice,
                         newProjectGroup: String?, remindAt: Date?, deadline: Date?) {
        let projectID: UUID?
        switch projectChoice {
        case .none: projectID = nil
        case .existing(let project): projectID = store.project(id: project.id)?.id
        case .new(let name):
            projectID = store.ensureProjectWithinLimit(named: name, categoryID: categoryID, group: newProjectGroup)?.id
        }
        let previousIDs = Set(store.items.map(\.id))
        store.add(title: title, bucket: bucket, categoryID: .some(categoryID), projectID: projectID,
                  remindAt: remindAt, deadline: deadline)
        let projectIDs = Set(session?.projectIDs ?? [])
        session?.tasks.includeAdded(store.items.filter {
            !previousIDs.contains($0.id) && $0.projectID.map(projectIDs.contains) == true
        })
    }

    private func goBack() {
        session?.goBack(projects: store.projects)
    }

    private func start() {
        let orderedCards = StackReviewSession.allOpenBuckets.flatMap { store.items(in: $0) }
        session = ProjectReviewSession(projects: store.projects, cards: orderedCards,
                                      categories: store.categories)
    }

    private func reconcile() {
        session?.reconcile(projects: store.projects, cards: store.items)
    }

    private func persist() {
        guard let session, let data = try? JSONEncoder().encode(session),
              let text = String(data: data, encoding: .utf8) else { return }
        savedSession = text
    }
}
