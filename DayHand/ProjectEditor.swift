import SwiftUI


/// Projects are organised in the Filter — long-press one, or right-click it on
/// the Mac — so there is no second screen listing them. What is left here is
/// the editor that menu opens, and the one-time conversion of title prefixes
/// written before projects existed.

/// One project: its name, its category, archived or not, and the ways to fold
/// it into another or remove it.
///
/// Reached by long-pressing a project in the Filter — right-clicking it on the
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

    private var project: Project? { store.project(id: projectID) }

    var body: some View {
        Group {
            if let project {
                form(project)
            } else {
                // Merged away or deleted from here, or from another device.
                ContentUnavailableView("Project removed", systemImage: "number")
            }
        }
        .navigationTitle(project?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
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
            Text("\(project.map { store.openCards(in: $0).count } ?? 0) cards are still to do. They are marked completed.")
        }
    }

    private func form(_ project: Project) -> some View {
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
                Text("Renaming changes it on every card at once.")
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

                Menu {
                    ForEach(store.groupNames(in: project.categoryID), id: \.self) { name in
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
                    if !store.groupNames(in: project.categoryID).isEmpty { Divider() }
                    Button {
                        groupField = ""
                        isNamingGroup = true
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
                } label: {
                    LabeledContent {
                        HStack(spacing: 6) {
                            Text(project.group ?? String(localized: "None"))
                            // The Picker above draws its own; a Menu does not,
                            // and without it this row reads as a dead label.
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.footnote.weight(.semibold))
                        }
                        .foregroundStyle(.secondary)
                    } label: {
                        Label("Group", systemImage: "folder")
                    }
                }

            } footer: {
                Text("Every card in this project moves with it, and new ones start here too. Moving a project to another category also takes it out of its group.")
            }

            // An action, not a setting: archiving has something to finish
            // first, so it asks rather than flicking back.
            Section {
                if project.isArchived {
                    Button {
                        store.setProjectArchived(project, false)
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
                    Text("Archived. Its cards are still there, and it is left out of the project list until \u{201C}Include archived projects\u{201D} is on. Typing its name brings it back.")
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
                Text("\(store.cardCount(using: project)) cards in this project.")
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
            Text("Its \(store.cardCount(using: project)) cards will move to \(other.name).")
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
            Text("\(project.name)\u{2019}s \(store.cardCount(using: project)) cards move to \(target.name), and \(project.name) is removed.")
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
            Text("Its cards are kept. They just no longer belong to a project.")
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
                Text("Each ticked word becomes a project and is removed from the start of those titles. A new project takes the category most of its cards have.")
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
                            Text("\(candidate.cardIDs.count) cards")
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
