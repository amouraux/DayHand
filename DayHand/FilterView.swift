import SwiftUI

/// Narrow the list to any mix of categories and projects. A card shows if it
/// matches any of them: "Teaching, and also STUDY2026".
///
/// Never a menu: a menu closes after every tap, and multi-select needs to stay
/// open while several are picked. Projects sit under their category — and,
/// within it, under their group when they have one — with their open-card
/// count, and can be searched.
///
/// This is also where projects are organised into groups: long-press a project
/// (right-click on the Mac) to move it, or a group heading to rename it. Tapping
/// keeps its one job, selecting, so the two never clash.
///
/// The list itself, without a container: the phone presents it as a sheet, and
/// a wide window keeps it in a sidebar, where choosing a project and seeing the
/// cards change are the same moment rather than two.
struct FilterList: View {
    @Binding var categorySelection: Set<UUID>
    @Binding var projectSelection: Set<UUID>

    @EnvironmentObject private var store: TodoStore
    @State private var search = ""
    /// Off by default, and on every opening: an archived project is one that is
    /// over, and the list is about what is still going on.
    @State private var showArchived = false

    /// A project waiting for the name of a new group to go into.
    @State private var newGroupFor: Project?
    /// A group waiting for its new name.
    @State private var renaming: GroupRef?
    @State private var nameField = ""
    /// The project whose full editor is open — renaming, category, archiving,
    /// merging and deleting all live there, reached from this list rather than
    /// from a second screen somewhere else.
    @State private var editingProject: Project?

    /// A group is identified by its category and its label.
    struct GroupRef: Identifiable {
        let categoryID: UUID?
        let name: String
        var id: String { (categoryID?.uuidString ?? "none") + "/" + name }
    }

    private var categories: [CardCategory] { store.categories }
    private var openCounts: [UUID: Int] { store.openCardCounts }
    private var categoryCounts: [UUID: Int] { store.openCategoryCounts }
    private var isEverything: Bool { categorySelection.isEmpty && projectSelection.isEmpty }

    /// Archived projects are left out until they are asked for — except one
    /// that is currently filtering the list, which must never vanish from
    /// under the selection that named it.
    private var visibleProjects: [Project] {
        store.projects
            .filter { !$0.isArchived || showArchived || projectSelection.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var hasArchived: Bool { store.projects.contains { $0.isArchived } }

    /// Projects whose category no longer exists are shown with the loose ones.
    private func scope(of project: Project) -> UUID? {
        guard let id = project.categoryID, categories.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    private func layout(for category: CardCategory?) -> ProjectGroups.Layout {
        ProjectGroups.layout(of: visibleProjects.filter { scope(of: $0) == category?.id })
    }

    var body: some View {
        List {
            Section {
                Button {
                    withAnimation { pick() }
                } label: {
                    row(symbol: "square.grid.2x2", tint: .secondary, text: Text("Everything"),
                        count: nil, selected: isEverything, bold: false)
                }
            } footer: {
                // Where the eye already is, rather than a tip at the bottom
                // that nobody scrolls to.
                Text("Choosing one replaces the last; touch and hold a row \u{2014} right-click on the Mac \u{2014} to add it instead. Tap \u{24D8} to rename a project, group it, or put it away.")
            }

            // Above the categories, not below them: on a phone the search field
            // is pinned to the bottom of the sheet, and a list short enough not
            // to scroll would leave this row stranded underneath it. Only worth
            // a row at all once there is something to include.
            if hasArchived {
                Section {
                    Toggle(isOn: $showArchived.animation(.easeInOut(duration: 0.2))) {
                        Label("Include archived projects", systemImage: "archivebox")
                    }
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
        .sheet(item: $editingProject) { project in
            NavigationStack {
                ProjectEditor(projectID: project.id)
                    .environmentObject(store)
                    // A sheet on the Mac cannot be swiped away, so it needs a
                    // way out that is not the keyboard.
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { editingProject = nil }
                        }
                    }
            }
        }
        .alert("New Group", isPresented: Binding(
            get: { newGroupFor != nil }, set: { if !$0 { newGroupFor = nil } }
        ), presenting: newGroupFor) { project in
            TextField("Holidays", text: $nameField)
            Button("Move") {
                withAnimation { store.setProjectGroup(project, to: nameField) }
            }
            Button("Cancel", role: .cancel) { }
        } message: { project in
            Text("A group for \(project.name) and others like it, such as Holidays or Clients.")
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
        if project.isArchived { return .secondary }
        return project.categoryID.flatMap { id in categories.first { $0.id == id } }?.color.prefixTint ?? .primary
    }

    private func categoryRow(_ category: CardCategory) -> some View {
        Button {
            withAnimation { pick(categories: [category.id]) }
        } label: {
            row(symbol: category.symbolName, tint: category.tint,
                text: Text("All \(category.label)"),
                count: categoryCounts[category.id] ?? 0,
                selected: categorySelection.contains(category.id), bold: false)
        }
        .contextMenu { addToSelection(categories: [category.id]) }
    }

    /// A group heading. Tapping selects the whole group — or clears it, when all
    /// of it is already selected. It selects the projects in the group now; one
    /// moved in later is not picked up by a selection already made.
    private func groupRow(_ name: String, projects: [Project], categoryID: UUID?) -> some View {
        let ids = Set(projects.map(\.id))
        let allSelected = !ids.isEmpty && ids.isSubset(of: projectSelection)
        let open = FilterCounts.total(of: projects, in: openCounts)

        return Button {
            withAnimation { pick(projects: ids) }
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
                // Cards, like every row under it. It used to be the number of
                // projects, in the same slot and the same grey, so a group
                // holding one finished project read as one card to be had.
                Text("\(open)")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                if allSelected {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                }
            }
        }
        .contextMenu {
            addToSelection(projects: ids)
            Button {
                nameField = name
                renaming = GroupRef(categoryID: categoryID, name: name)
            } label: {
                Label("Rename Group…", systemImage: "pencil")
            }
        }
        .accessibilityLabel("Group \(name), \(projects.count) projects")
        .accessibilityValue("\(open)")
        .accessibilityHint(allSelected ? "Shows every card again" : "Shows only this group")
    }

    private func projectRow(_ project: Project, tint: Color, indented: Bool) -> some View {
        HStack(spacing: 10) {
            Button {
                withAnimation { pick(projects: [project.id]) }
            } label: {
                row(symbol: "number", tint: project.isArchived ? .secondary : tint,
                    text: Text(project.name),
                    count: openCounts[project.id] ?? 0,
                    selected: projectSelection.contains(project.id), bold: true)
                    .padding(.leading, indented ? 20 : 0)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // The row filters by the project; this opens it — the way a Wi-Fi
            // network is joined by its row and configured by its ⓘ. Renaming
            // and grouping used to need a long press, which is no way to reach
            // the only place they live.
            Button {
                editingProject = project
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Edit \(project.name)")
        }
        .contextMenu {
            addToSelection(projects: [project.id])
            moveMenu(project)
        }
    }

    /// Move to Group: the category's existing groups, a new one, or none —
    /// listed straight in the long-press menu under a heading, not behind a
    /// submenu, since moving is the menu's only job.
    @ViewBuilder
    private func moveMenu(_ project: Project) -> some View {
        Button {
            editingProject = project
        } label: {
            Label("Edit Project…", systemImage: "square.and.pencil")
        }
        Section("Move \(project.name) to Group") {
            ProjectGroupMenu(project: project) {
                nameField = ""
                newGroupFor = project
            }
        }
    }

    private func row(symbol: String, tint: Color, text: Text, count: Int?, selected: Bool, bold: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 24)
            text
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

    /// One at a time. Choosing a row replaces whatever was chosen before, which
    /// is what browsing wants: click a project, look, click the next. Choosing
    /// what is already the whole selection clears it, so the row that narrowed
    /// the list is the row that puts it back.
    private func pick(categories: Set<UUID> = [], projects: Set<UUID> = []) {
        if categorySelection == categories && projectSelection == projects {
            categorySelection = []
            projectSelection = []
        } else {
            categorySelection = categories
            projectSelection = projects
        }
    }

    /// Several at once, from ⇧-click or the touch-and-hold menu. Already in the
    /// selection means take it out, so the same gesture undoes itself.
    private func add(categories: Set<UUID> = [], projects: Set<UUID> = []) {
        let held = categories.isSubset(of: categorySelection)
            && projects.isSubset(of: projectSelection)
        if held && !(categories.isEmpty && projects.isEmpty) {
            categorySelection.subtract(categories)
            projectSelection.subtract(projects)
        } else {
            categorySelection.formUnion(categories)
            projectSelection.formUnion(projects)
        }
    }

    private func isHeld(categories: Set<UUID> = [], projects: Set<UUID> = []) -> Bool {
        !(categories.isEmpty && projects.isEmpty)
            && categories.isSubset(of: categorySelection)
            && projects.isSubset(of: projectSelection)
    }

    /// Long-press on a phone, right-click on the Mac: the one route to a second
    /// selection, so every row carries it and it reads the same everywhere.
    /// Not ⇧-click — `Gesture.modifiers(_:)` is macOS-only and does not exist
    /// in a Catalyst app, and reading modifier flags would mean dropping to a
    /// UIKit recogniser under every row.
    @ViewBuilder
    private func addToSelection(categories: Set<UUID> = [], projects: Set<UUID> = []) -> some View {
        Button {
            withAnimation { add(categories: categories, projects: projects) }
        } label: {
            if isHeld(categories: categories, projects: projects) {
                Label("Remove from Selection", systemImage: "minus.circle")
            } else {
                Label("Add to Selection", systemImage: "plus.circle")
            }
        }
    }
}

/// The same list, presented modally — what a phone gets, where there is no room
/// to keep it beside the cards.
struct FilterSheet: View {
    @Binding var categorySelection: Set<UUID>
    @Binding var projectSelection: Set<UUID>

    @Environment(\.dismiss) private var dismiss
    /// Opens tall. The list is categories, groups and every project, and the
    /// search field floats at the bottom of the sheet — at the medium detent it
    /// sits on top of the last rows, which is where a project's ⓘ lives.
    @State private var detent: PresentationDetent = .large

    var body: some View {
        NavigationStack {
            FilterList(categorySelection: $categorySelection, projectSelection: $projectSelection)
                .navigationTitle("Filter")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large], selection: $detent)
    }
}
