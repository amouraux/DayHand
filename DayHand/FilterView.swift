import SwiftUI
import UIKit

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

    /// What is being renamed in place, if anything.
    enum Renaming: Equatable {
        case project(UUID)
        case group(UUID?, String)
    }
    @State private var renamingInline: Renaming?
    @State private var inlineText = ""
    @FocusState private var inlineFocused: Bool
    /// A rename that would really be a merge, which is not something to do by
    /// accident from a list row.
    @State private var collision: String?

    /// A drop that moves a project to another category, which takes every card
    /// in it along. Worth asking about; a change of group is not.
    struct PendingMove: Identifiable {
        let id = UUID()
        let project: Project
        let categoryID: UUID?
        let group: String?
        let cards: Int
    }
    @State private var pendingMove: PendingMove?

    /// Which heading a drag is over. A category and a group are different
    /// targets — dropping on a category means that category in *no* group — so
    /// this is not the same set of things that can be renamed.
    enum DropTarget: Equatable {
        case category(UUID)
        case group(UUID?, String)
    }

    /// Shown, because without it a drag that does nothing cannot be told from
    /// a drag that never started, and those want different fixes.
    @State private var aimedAt: DropTarget?

    private func dropHighlight(_ aimed: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Color.accentColor, lineWidth: aimed ? 2 : 0)
            .padding(.horizontal, 4)
            .opacity(aimed ? 1 : 0)
    }
    /// Whether this is the sidebar rather than the phone's sheet. Told, not
    /// worked out: each column of a NavigationSplitView carries its own size
    /// class, and the sidebar's is *compact* — so a view sitting in it that
    /// asks the environment decides it is the phone. It did, and the folding
    /// triangles and the tighter rows were missing from the sidebar, which is
    /// the one place they were for.
    var isSidebar = false

    /// Which headings are folded away, keyed so the state survives a relaunch:
    /// a sidebar that forgets what you folded is worse than one that does not
    /// fold at all. Stored as one string because AppStorage holds no sets.
    @AppStorage("filterCollapsed") private var collapsedRaw = ""
    private var collapsed: Set<String> {
        Set(collapsedRaw.split(separator: "\n").map(String.init))
    }
    /// Folding belongs to the sidebar. On a phone this same view is a sheet
    /// that is opened, picked from and closed, not a list anyone lives in, and
    /// a triangle there is only a second target crowding the checkbox.
    ///
    /// The state is ignored rather than merely hidden: it is remembered per
    /// device, so a category folded in an iPad's sidebar would otherwise come
    /// up collapsed in that same iPad's compact sheet, with nothing to expand
    /// it.
    private func isCollapsed(_ key: String) -> Bool {
        isSidebar && collapsed.contains(key)
    }
    private func toggleCollapsed(_ key: String) {
        var keys = collapsed
        if keys.contains(key) { keys.remove(key) } else { keys.insert(key) }
        collapsedRaw = keys.sorted().joined(separator: "\n")
    }
    private func categoryKey(_ id: UUID) -> String { "c:\(id.uuidString)" }
    private func groupFoldKey(_ name: String, in categoryID: UUID?) -> String {
        "g:\(categoryID?.uuidString ?? "-"):\(Project.groupKey(for: name))"
    }

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
                    HStack(spacing: 10) {
                        Color.clear.frame(width: 22, height: 1)
                        row(symbol: "square.grid.2x2", tint: .secondary, text: Text("Everything"),
                            count: nil, selected: isEverything, bold: false)
                    }
                }
            } footer: {
                // Where the eye already is, rather than a tip at the bottom
                // that nobody scrolls to.
                //
                // Stacked, not left loose: a section footer takes one view,
                // and two of them side by side in the builder meant only the
                // first was ever drawn — the drag line had never once been on
                // screen.
                VStack(alignment: .leading, spacing: 6) {
                    Text("Clicking a row picks that one; use the checkbox beside it to pick several. Tap \u{24D8} to rename a project or a group, or to put a project away.")
                    Text("Drag a project by its handle onto a group or an All category row to move it.")
                }
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
                    let inside = layout(for: category)
                    let folded = isCollapsed(categoryKey(category.id))
                    Section(category.label) {
                        categoryRow(category,
                                    canFold: !inside.groups.isEmpty || !inside.ungrouped.isEmpty,
                                    folded: folded)
                        if !folded {
                            projectRows(inside, categoryID: category.id,
                                        tint: category.color.prefixTint)
                        }
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
                        projectRow(project, tint: tint(for: project))
                    }
                }
            }

        }
        // Airy, but not as airy as a touch list has to be: on the Mac and the
        // iPad the sidebar is driven by a pointer, and the default 44pt row
        // turns a dozen projects into a scroll. The phone's sheet is this same
        // view and keeps the full target.
        .environment(\.defaultMinListRowHeight, isSidebar ? 30 : 44)
        // The rows fold in and out rather than appearing. AppStorage does not
        // take part in the `withAnimation` at the button, so the animation is
        // hung off the stored value itself.
        .animation(.snappy(duration: 0.28), value: collapsedRaw)
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
        // Moving a project to another category takes every card in it along,
        // so it says how many rather than doing it quietly. A group is only a
        // label, and changes without asking.
        .alert("Move Project?", isPresented: Binding(
            get: { pendingMove != nil }, set: { if !$0 { pendingMove = nil } }
        ), presenting: pendingMove) { move in
            Button("Move") { file(move.project, categoryID: move.categoryID, group: move.group) }
            Button("Cancel", role: .cancel) { }
        } message: { move in
            let into = categories.first { $0.id == move.categoryID }?.label ?? "Other projects"
            Text("\(move.project.name) and its \(move.cards) tasks move to \(into).")
        }
        .alert("Name Taken", isPresented: Binding(
            get: { collision != nil }, set: { if !$0 { collision = nil } }
        ), presenting: collision) { _ in
            Button("OK", role: .cancel) { }
        } message: { message in
            Text(message)
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
            let folded = isCollapsed(groupFoldKey(group.name, in: categoryID))
            groupRow(group.name, projects: group.projects,
                     categoryID: categoryID, folded: folded)
            if !folded {
                ForEach(group.projects) { projectRow($0, tint: tint) }
            }
        }
        ForEach(layout.ungrouped) { projectRow($0, tint: tint) }
    }

    private func tint(forCategory id: UUID?) -> Color {
        id.flatMap { wanted in categories.first { $0.id == wanted } }?.color.prefixTint ?? .primary
    }

    /// A heading's band. Faint on purpose, and built from the same tint the
    /// project names under it are written in, so a category reads as one block
    /// without competing with the only coloured text in the list. The tint is
    /// the dark-mode-aware one: the plain colour goes muddy behind a dark row.
    private func headingBand(_ tint: Color, strong: Bool) -> some View {
        tint.opacity(strong ? 0.13 : 0.07)
    }

    private func tint(for project: Project) -> Color {
        if project.isArchived { return .secondary }
        return project.categoryID.flatMap { id in categories.first { $0.id == id } }?.color.prefixTint ?? .primary
    }

    private func categoryRow(_ category: CardCategory,
                             canFold: Bool = false, folded: Bool = false) -> some View {
        HStack(spacing: 6) {
            selectionBox(isOn: categorySelection.contains(category.id)) {
                add(categories: [category.id])
            }
            foldControl(folded, enabled: canFold,
                        icon: category.symbolName, tint: category.tint) {
                toggleCollapsed(categoryKey(category.id))
            }
            Button {
                withAnimation { pick(categories: [category.id]) }
            } label: {
                row(symbol: nil, tint: category.tint,
                    text: Text("All \(category.label)"),
                    count: categoryCounts[category.id] ?? 0,
                    selected: false, bold: false)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .listRowBackground(
            headingBand(category.color.prefixTint, strong: true)
                .overlay(dropHighlight(aimedAt == .category(category.id)))
        )
        // A project dropped on a category belongs to it, in no group — which
        // is also the way one is taken out of a group, by dropping it on the
        // category it is already in.
        .background(projectDropTarget(.category(category.id), categoryID: category.id, group: nil))
        .contextMenu { addToSelection(categories: [category.id]) }
    }

    /// A group heading. Tapping selects the whole group — or clears it, when all
    /// of it is already selected. It selects the projects in the group now; one
    /// moved in later is not picked up by a selection already made.
    private func groupRow(_ name: String, projects: [Project],
                          categoryID: UUID?, folded: Bool = false) -> some View {
        let ids = Set(projects.map(\.id))
        let allSelected = !ids.isEmpty && ids.isSubset(of: projectSelection)
        let open = FilterCounts.total(of: projects, in: openCounts)

        return HStack(spacing: 6) {
            selectionBox(isOn: allSelected) { add(projects: ids) }
            foldControl(folded, enabled: !projects.isEmpty,
                        icon: "folder", tint: .secondary) {
                toggleCollapsed(groupFoldKey(name, in: categoryID))
            }
            if renamingInline == .group(categoryID, name) {
                renameField()
            } else {
            HStack(spacing: 8) {
                // Primary, not secondary: a dimmed heading in a list reads as
                // disabled, especially in dark mode.
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                // Cards, like every row under it. It used to be the number of
                // projects, in the same slot and the same grey, so a group
                // holding one finished project read as one card to be had.
                Text("\(open)")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { beginRename(.group(categoryID, name), text: name) }
            .onTapGesture { withAnimation { pick(projects: ids) } }
            .accessibilityAddTraits(.isButton)
            }

            // The same affordance the projects under it carry. Renaming is all
            // a group has — it owns no other settings — so this opens straight
            // into it rather than into a sheet with one row.
            Button {
                nameField = name
                renaming = GroupRef(categoryID: categoryID, name: name)
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Rename Group…")
        }
        .listRowBackground(
            headingBand(tint(forCategory: categoryID), strong: false)
                .overlay(dropHighlight(aimedAt == .group(categoryID, name)))
        )
        .background(projectDropTarget(.group(categoryID, name), categoryID: categoryID, group: name))
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
        .accessibilityHint(allSelected ? "Shows every task again" : "Shows only this group")
    }

    /// Every project row sits on the same column, the one a group's folder
    /// icon starts on: the heading above says whether it is in a group, so the
    /// row does not have to say it again with space it cannot spare.
    private func projectRow(_ project: Project, tint: Color) -> some View {
        HStack(spacing: 6) {
            selectionBox(isOn: projectSelection.contains(project.id)) {
                add(projects: [project.id])
            }
            ProjectDragHandle(projectID: project.id, name: project.name)
                .frame(width: 22, height: isSidebar ? 28 : 44)
                .allowsHitTesting(renamingInline == nil)
            if renamingInline == .project(project.id) {
                renameField()
            } else {
                row(symbol: nil, tint: project.isArchived ? .secondary : tint,
                    // No `#`. A card has never shown one — it writes the
                    // project as a coloured word in front of the title — and
                    // the sidebar was the only place that did. Colour says
                    // what it is, here as there.
                    text: Text(project.name),
                    count: openCounts[project.id] ?? 0,
                    selected: false, bold: true)
                    // None. The checkbox and the fold column already carry
                    // the name to where a group's folder icon sits, which is
                    // the column everything under a heading lines up on.
                    // Indenting past the group's *name* instead left a run of
                    // empty space between the checkbox and the tag.
                    .contentShape(Rectangle())
                    // Declared before the single tap, which gives it priority:
                    // a click now waits to see whether a second one follows.
                    // Only these rows pay that wait, not the cards.
                    .onTapGesture(count: 2) {
                        beginRename(.project(project.id), text: project.name)
                    }
                    .onTapGesture { withAnimation { pick(projects: [project.id]) } }
                    .accessibilityAddTraits(.isButton)
                    .contextMenu {
                        addToSelection(projects: [project.id])
                        moveMenu(project)
                    }
            }

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
        Section("Move \(project.name) to Category") {
            ForEach(categories) { category in
                Button {
                    refile(project, categoryID: category.id, group: nil)
                } label: {
                    if category.id == project.categoryID {
                        Label(category.label, systemImage: "checkmark")
                    } else {
                        Text(category.label)
                    }
                }
            }
        }
    }

    /// Clicking a row picks that one and drops the rest; clicking this takes a
    /// row in or out of what is already picked. Several at once therefore needs
    /// no modifier key — ⇧-click cannot be read in a Catalyst app without a
    /// UIKit recogniser under every row — and it works the same on a phone,
    /// where a modifier does not exist at all.
    // MARK: - Dragging a project somewhere else

    /// Exit callbacks can follow the next heading's entry callback, so only
    /// clear the highlight when it still belongs to the heading being left.
    private func aiming(at target: DropTarget) -> Binding<Bool> {
        Binding(
            get: { aimedAt == target },
            set: { over in
                if over { aimedAt = target }
                else if aimedAt == target { aimedAt = nil }
            }
        )
    }

    private func projectDropTarget(_ target: DropTarget, categoryID: UUID?,
                                   group: String?) -> some View {
        ProjectDropTarget(isTargeted: aiming(at: target), accepts: { id in
            guard let project = store.project(id: id) else { return false }
            return ProjectFiling.move(project, toCategory: categoryID,
                                      group: group, cards: store.items) != nil
        }, move: { id in
            guard let project = store.project(id: id) else { return }
            refile(project, categoryID: categoryID, group: group)
        })
    }

    /// Where a project is being sent, however it was asked for — dropped on a
    /// heading, or chosen from its menu. The menu also provides a route that
    /// does not require a drag gesture.
    @discardableResult
    private func refile(_ project: Project, categoryID: UUID?, group: String?) -> Bool {
        guard let project = store.project(id: project.id),
              categoryID == nil || categories.contains(where: { $0.id == categoryID }),
              let move = ProjectFiling.move(project, toCategory: categoryID,
                                            group: group, cards: store.items)
        else { return false }

        // Changing a project's category takes its cards with it, a real edit
        // to every one of them. A group is only a label, and goes quietly.
        if move.cards > 0 {
            pendingMove = PendingMove(project: project, categoryID: move.categoryID,
                                      group: move.group, cards: move.cards)
            return true
        }
        file(project, categoryID: move.categoryID, group: move.group)
        return true
    }

    private func file(_ project: Project, categoryID: UUID?, group: String?) {
        withAnimation(.snappy(duration: 0.28)) {
            store.moveProject(project.id, toCategory: categoryID, group: group)
        }
    }

    // MARK: - Renaming in place

    private func beginRename(_ what: Renaming, text: String) {
        inlineText = text
        renamingInline = what
        // A beat, or the field is not yet in the hierarchy to take the focus.
        DispatchQueue.main.async { inlineFocused = true }
    }

    private func commitRename() {
        guard let what = renamingInline else { return }
        renamingInline = nil
        switch what {
        case .project(let id):
            guard let project = store.projects.first(where: { $0.id == id }) else { return }
            if case .collides(let other) = store.renameProject(project, to: inlineText) {
                collision = "\(other.name) already exists. Open \(project.name) with \u{24D8} to merge them."
            }
        case .group(let categoryID, let name):
            guard let renamed = Project.cleanGroup(inlineText), renamed != name else { return }
            withAnimation { store.renameGroup(name, in: categoryID, to: renamed) }
        }
    }

    /// The field, shown in place of the name while it is being edited.
    private func renameField() -> some View {
        TextField("Name", text: $inlineText)
            .focused($inlineFocused)
            .autocorrectionDisabled()
            .onSubmit { commitRename() }
            // Clicking away keeps what was typed, the way a Finder rename
            // does. An untouched field writes nothing, so this cannot rename
            // anything by accident.
            .onChange(of: inlineFocused) { _, focused in if !focused { commitRename() } }
    }

    /// The triangle *and* the heading's own icon, as one control.
    ///
    /// The triangle alone was 18pt sitting 6pt from a 22pt checkbox — two
    /// targets inside the width of one fingertip, and on a phone the fold was
    /// nearly impossible to hit without toggling the filter instead. Taking
    /// the icon into the same button makes it 48pt wide at no cost in width,
    /// since the icon was already there. The name beside it still filters, the
    /// way a row's name does in any outline.
    @ViewBuilder
    private func foldControl(_ folded: Bool, enabled: Bool, icon: String, tint: Color,
                             toggle: @escaping () -> Void) -> some View {
        let glyphs = HStack(spacing: 8) {
            if isSidebar {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    // Kept in the layout when there is nothing to fold, so the
                    // icons below stay in one column.
                    .foregroundStyle(enabled ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(.clear))
                    .rotationEffect(.degrees(folded ? 0 : 90))
                    .frame(width: 18)
            }
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 22)
        }

        if enabled && isSidebar {
            Button {
                withAnimation(.snappy(duration: 0.28)) { toggle() }
            } label: {
                glyphs
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(folded ? "Expand" : "Collapse")
        } else {
            glyphs
        }
    }

    private func selectionBox(isOn: Bool, toggle: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { toggle() }
        } label: {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.body)
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary.opacity(0.45))
                .frame(width: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(isOn ? "Remove from Selection" : "Add to Selection")
    }

    /// - Parameter symbol: nil for a project, which carries its `#` inside its
    ///   name instead. A separate glyph cost a 24pt frame and the 12pt beside
    ///   it — 36pt of a sidebar that has none to spare, to say what one
    ///   character already says.
    private func row(symbol: String?, tint: Color, text: Text, count: Int?, selected: Bool, bold: Bool) -> some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                    .frame(width: 22)
            }
            text
                .fontWeight(bold ? .semibold : .regular)
                .foregroundStyle(bold ? tint : Color.primary)
                // A name that wraps turns one row into two and reads as two
                // projects. Shrink a little first, then tail-truncate.
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .truncationMode(.tail)
            Spacer(minLength: 4)
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

// MARK: - Native sidebar drag and drop

/// Local-only identity keeps text dragged from another app from moving data.
private struct DraggedProject {
    let id: UUID
}

/// A dedicated grip leaves selection, renaming and the info button independent
/// of the press that starts a drag, including on touch screens.
private struct ProjectDragHandle: UIViewRepresentable {
    let projectID: UUID
    let name: String

    func makeCoordinator() -> Coordinator { Coordinator(projectID: projectID, name: name) }

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView(image: UIImage(systemName: "line.3.horizontal"))
        view.contentMode = .center
        view.tintColor = .tertiaryLabel
        view.isUserInteractionEnabled = true
        view.isAccessibilityElement = true
        let interaction = UIDragInteraction(delegate: context.coordinator)
        interaction.isEnabled = true
        view.addInteraction(interaction)
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        context.coordinator.projectID = projectID
        context.coordinator.name = name
        view.accessibilityLabel = String(localized: "Move \(name)")
    }

    final class Coordinator: NSObject, UIDragInteractionDelegate {
        var projectID: UUID
        var name: String

        init(projectID: UUID, name: String) {
            self.projectID = projectID
            self.name = name
        }

        func dragInteraction(_ interaction: UIDragInteraction,
                             itemsForBeginning session: UIDragSession) -> [UIDragItem] {
            let item = UIDragItem(itemProvider: NSItemProvider(object: name as NSString))
            item.localObject = DraggedProject(id: projectID)
            return [item]
        }

        func dragInteraction(_ interaction: UIDragInteraction,
                             sessionIsRestrictedToDraggingApplication session: UIDragSession) -> Bool { true }
    }
}

/// SwiftUI's row drop modifiers are swallowed by List's collection view on
/// Catalyst. Attach to the cell's content view, an ancestor of its buttons,
/// instead of the background anchor (which never receives their hit tests).
private struct ProjectDropTarget: UIViewRepresentable {
    @Binding var isTargeted: Bool
    var accepts: (UUID) -> Bool
    var move: (UUID) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> Anchor {
        let anchor = Anchor()
        anchor.isUserInteractionEnabled = false
        anchor.coordinator = context.coordinator
        return anchor
    }

    func updateUIView(_ anchor: Anchor, context: Context) {
        context.coordinator.parent = self
        context.coordinator.attach(from: anchor)
    }

    static func dismantleUIView(_ anchor: Anchor, coordinator: Coordinator) {
        coordinator.detach()
        anchor.coordinator = nil
    }

    final class Anchor: UIView {
        weak var coordinator: Coordinator?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { coordinator?.detach() }
            else { coordinator?.attach(from: self) }
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            coordinator?.attach(from: self)
        }
    }

    final class Coordinator: NSObject, UIDropInteractionDelegate {
        var parent: ProjectDropTarget
        private weak var host: UIView?
        private lazy var interaction = UIDropInteraction(delegate: self)

        init(_ parent: ProjectDropTarget) { self.parent = parent }

        func attach(from anchor: UIView) {
            guard anchor.window != nil else { return }
            var candidate = anchor.superview
            while let view = candidate {
                let content: UIView?
                if let cell = view as? UICollectionViewCell { content = cell.contentView }
                else if let cell = view as? UITableViewCell { content = cell.contentView }
                else { content = nil }
                if let content {
                    guard content !== host else { return }
                    detach()
                    content.addInteraction(interaction)
                    host = content
                    return
                }
                candidate = view.superview
            }
        }

        func detach() {
            host?.removeInteraction(interaction)
            host = nil
        }

        private func projectID(in session: UIDropSession) -> UUID? {
            guard session.localDragSession != nil, session.items.count == 1,
                  let project = session.items.first?.localObject as? DraggedProject,
                  parent.accepts(project.id) else { return nil }
            return project.id
        }

        func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
            projectID(in: session) != nil
        }

        func dropInteraction(_ interaction: UIDropInteraction,
                             sessionDidUpdate session: UIDropSession) -> UIDropProposal {
            let accepted = session.allowsMoveOperation && projectID(in: session) != nil
            parent.isTargeted = accepted
            return UIDropProposal(operation: accepted ? .move : .forbidden)
        }

        func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
            parent.isTargeted = false
            guard let id = projectID(in: session) else { return }
            parent.move(id)
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: UIDropSession) {
            parent.isTargeted = false
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnd session: UIDropSession) {
            parent.isTargeted = false
        }
    }
}
