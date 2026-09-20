import SwiftUI

/// Settings → Projects: every project, grouped under its category, with the
/// tools to keep them tidy — rename, merge, archive, delete — and the one-time
/// conversion of title prefixes written before projects existed.
struct ProjectsView: View {
    @EnvironmentObject private var store: TodoStore

    @State private var isAdding = false
    @State private var newName = ""

    private var candidates: [ProjectConversion.Candidate] {
        ProjectConversion.candidates(cards: store.items, existing: store.projects)
    }

    private func projects(in category: CardCategory?, archived: Bool) -> [Project] {
        store.projects
            .filter { $0.isArchived == archived }
            .filter { project in
                guard let id = project.categoryID,
                      store.categories.contains(where: { $0.id == id }) else { return category == nil }
                return id == category?.id
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            let found = candidates
            if !found.isEmpty {
                Section {
                    NavigationLink {
                        ProjectConversionView(candidates: found).environmentObject(store)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Convert Title Prefixes…")
                                Text("\(found.count) possible project\(found.count == 1 ? "" : "s") found in your titles")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "wand.and.stars")
                        }
                    }
                } footer: {
                    Text("Cards written as \u{201C}TRIP book flights\u{201D} can become \u{201C}book flights\u{201D} in project TRIP. You choose which words to convert.")
                }
            }

            ForEach(store.categories) { category in
                let items = projects(in: category, archived: false)
                if !items.isEmpty {
                    Section(category.label) {
                        groupedRows(items)
                    }
                }
            }

            let loose = projects(in: nil, archived: false)
            if !loose.isEmpty {
                Section("No category") {
                    groupedRows(loose)
                }
            }

            let archived = store.projects.filter(\.isArchived)
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            if !archived.isEmpty {
                Section {
                    ForEach(archived) { row($0) }
                } header: {
                    Text("Archived")
                } footer: {
                    Text("Archived projects keep their cards but are no longer suggested. Typing one\u{2019}s name brings it back.")
                }
            }

            if store.projects.isEmpty && found.isEmpty {
                Section {
                    Text("Type # in a new task to create a project, such as #TRIP.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Projects")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newName = ""
                    isAdding = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add project")
            }
        }
        .alert("New Project", isPresented: $isAdding) {
            TextField("TRIP", text: $newName)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button("Add") { store.ensureProject(named: newName, categoryID: nil) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("A short one-word name for something you are working on.")
        }
    }

    /// The same grouping as the Filter sheet, shown here but organised there.
    @ViewBuilder
    private func groupedRows(_ items: [Project]) -> some View {
        let layout = ProjectGroups.layout(of: items)
        ForEach(layout.groups, id: \.name) { group in
            Label(group.name, systemImage: "folder")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(group.projects) { row($0).padding(.leading, 20) }
        }
        ForEach(layout.ungrouped) { row($0) }
    }

    private func row(_ project: Project) -> some View {
        let open = store.openCardCounts[project.id] ?? 0
        let total = store.cardCount(using: project)
        let tint = project.categoryID
            .flatMap { id in store.categories.first { $0.id == id } }?
            .color.prefixTint ?? .primary

        return NavigationLink {
            ProjectEditor(projectID: project.id).environmentObject(store)
        } label: {
            HStack {
                Text(project.name)
                    .fontWeight(.semibold)
                    .foregroundStyle(project.isArchived ? Color.secondary : tint)
                Spacer()
                Text(total == 0 ? "No cards" : "\(open) open · \(total)")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// One project: its name, its category, archived or not, and the ways to fold
/// it into another or remove it.
private struct ProjectEditor: View {
    let projectID: UUID

    @EnvironmentObject private var store: TodoStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    /// Set when a rename hits another project's name, which makes it a merge.
    @State private var collision: Project?
    @State private var mergeTarget: Project?
    @State private var isConfirmingDelete = false

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

                Toggle(isOn: Binding(
                    get: { project.isArchived },
                    set: { store.setProjectArchived(project, $0) }
                )) {
                    Label("Archived", systemImage: "archivebox")
                }
            } footer: {
                Text("A card given this project takes this category. Cards already in the project keep theirs. Moving a project to another category takes it out of its group; groups are arranged in the Filter sheet.")
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
                Text("\(store.cardCount(using: project)) card\(store.cardCount(using: project) == 1 ? "" : "s") in this project.")
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
                            Text("\(candidate.cardIDs.count) card\(candidate.cardIDs.count == 1 ? "" : "s")")
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
        withAnimation { store.convertTitlePrefixes(assignments) }
        dismiss()
    }
}
