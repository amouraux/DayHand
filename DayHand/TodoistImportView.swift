import SwiftUI
import UniformTypeIdentifiers
import CryptoKit

enum TodoistFileReader {
    static func load(_ urls: [URL]) async throws -> [TodoistCSV.File] {
        try await Task.detached(priority: .userInitiated) {
            var files: [TodoistCSV.File] = []
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                   size > 20_000_000 { throw TodoistCSV.Failure.size }
                let data = try Data(contentsOf: url)
                guard data.count <= 20_000_000 else { throw TodoistCSV.Failure.size }
                guard let text = String(data: data, encoding: .utf8) else { throw TodoistCSV.Failure.encoding }
                // Names distinguish two different projects with identical CSV
                // contents. Paths do not: moving an export must not reimport it.
                var identity = Data(url.lastPathComponent.utf8)
                identity.append(0)
                identity.append(data)
                let hash = SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
                if files.contains(where: { $0.id == hash }) { continue }
                files.append(try TodoistCSV.parse(text, fileID: hash, name: url.lastPathComponent))
            }
            return files
        }.value
    }
}

/// The same project/category choice in both importers, with the category
/// inherited from an existing project rather than editing that project.
struct TaskImportDestinationFields: View {
    @EnvironmentObject private var store: TodoStore
    let suggestedName: String
    @Binding var destination: TaskImportDestination
    @Binding var projectChoice: String

    var body: some View {
        Picker("Project", selection: Binding(get: { projectChoice }, set: { value in
            projectChoice = value
            destination.projectID = UUID(uuidString: value)
            destination.newProjectName = value == "new" ? Project.canonicalName(suggestedName) : ""
        })) {
            Text("None").tag("none")
            Text("New Project…").tag("new")
            ForEach(store.projects.filter { !$0.isArchived }) { project in
                Text(project.name).tag(project.id.uuidString)
            }
        }
        if projectChoice == "new" {
            TextField("Project name", text: Binding(
                get: { destination.newProjectName },
                set: { destination.newProjectName = Project.canonicalName($0) }
            ))
        }
        if let id = destination.projectID, let project = store.project(id: id) {
            LabeledContent("Category", value: store.categories.first { $0.id == project.categoryID }?.label ?? String(localized: "None"))
        } else {
            Picker("Category", selection: $destination.categoryID) {
                Text("None").tag(UUID?.none)
                ForEach(store.categories) { Text($0.label).tag(UUID?.some($0.id)) }
            }
        }
    }
}

struct TodoistImportView: View {
    @EnvironmentObject private var store: TodoStore
    @Environment(\.dismiss) private var dismiss
    @State private var isChoosing = false
    @State private var isLoading = false
    @State private var files: [TodoistCSV.File] = []
    @State private var options = TaskImport.Options()
    @State private var projectChoices: [String: String] = [:]
    @State private var includeUnparsedDates = false
    @State private var preview: TaskImport.Plan?
    @State private var report: String?
    @State private var didImport = false

    private let limits = String(localized: "Todoist project CSVs exclude completed tasks. Sections, parent tasks, comments, labels and other exported details are kept as text in Notes. Subtasks become separate tasks; attachments are not downloaded.")
    private let dates = String(localized: "Recognised task dates become reminders at 9 a.m.; recognised deadlines stay deadlines. Dates never move tasks. Original date text stays in Notes. Dates written in words, including recurring dates, need review.")

    var body: some View {
        NavigationStack {
            Form {
                if let preview {
                    previewSections(preview)
                } else {
                    setupSections
                }
            }
            .navigationTitle(preview == nil ? String(localized: "Import from Todoist") : String(localized: "Review import"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(preview == nil ? String(localized: "Cancel") : String(localized: "Back")) {
                        if preview == nil { dismiss() } else { preview = nil }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if let preview {
                        Button("Import") { importTasks() }.disabled(preview.added == 0)
                    } else if !files.isEmpty {
                        Button("Preview") { updatePreview() }
                            .disabled(isLoading || options.destinations.isEmpty || !validNames)
                    }
                }
            }
            .fileImporter(isPresented: $isChoosing, allowedContentTypes: [.commaSeparatedText, .plainText, .text],
                          allowsMultipleSelection: true) { result in
                switch result {
                case .failure(let error): report = error.localizedDescription
                case .success(let urls):
                    guard !urls.isEmpty else { return }
                    isLoading = true
                    Task { @MainActor in
                        defer { isLoading = false }
                        do {
                            let loaded = try await TodoistFileReader.load(urls)
                            files = loaded
                            options.destinations = Dictionary(uniqueKeysWithValues: loaded.map {
                                ($0.id, TaskImportDestination(categoryID: store.defaultCategoryID))
                            })
                            options.excludedIDs = []
                            projectChoices = [:]
                        } catch { report = error.localizedDescription }
                    }
                }
            }
            .alert(didImport ? String(localized: "Import complete") : String(localized: "Import"),
                   isPresented: Binding(get: { report != nil }, set: { if !$0 { report = nil } })) {
                Button("OK") { report = nil; if didImport { dismiss() } }
            } message: { Text(report ?? "") }
        }
    }

    @ViewBuilder private var setupSections: some View {
        Section {
            Text("In Todoist, open a project, choose Manage data, then Export as CSV. Select one or more exported CSV files here.")
            Button("Choose Todoist CSV files…") { isChoosing = true }.disabled(isLoading)
            if isLoading { ProgressView("Reading files…") }
        } footer: { Text(limits) }
        if !files.isEmpty {
            Section {
                Picker("Stack", selection: $options.bucket) {
                    ForEach(Bucket.quickMoveTargets) { Text($0.title).tag($0) }
                }
                Toggle("Import dates", isOn: $options.importDates)
                Toggle("Include tasks with unrecognised dates", isOn: $includeUnparsedDates)
            } footer: {
                Text(dates + "\n\n" + String(localized: "Including unrecognised dates imports those tasks once. Their unrecognised dates stay only in Notes; recurring schedules are not recreated."))
            }
            ForEach(files) { file in
                Section(file.name) {
                    Toggle("Import this file", isOn: Binding(get: { options.destinations[file.id] != nil }, set: { selected in
                        if selected { options.destinations[file.id] = TaskImportDestination(categoryID: store.defaultCategoryID) }
                        else { options.destinations.removeValue(forKey: file.id) }
                        projectChoices[file.id] = "none"
                    }))
                    LabeledContent("Tasks", value: "\(file.records.count)")
                    LabeledContent("Dates needing review", value: "\(file.unparsedDateIDs.count)")
                    if options.destinations[file.id] != nil {
                        TaskImportDestinationFields(
                            suggestedName: (file.name as NSString).deletingPathExtension,
                            destination: Binding(get: { options.destinations[file.id] ?? TaskImportDestination() },
                                                 set: { options.destinations[file.id] = $0 }),
                            projectChoice: Binding(get: { projectChoices[file.id] ?? "none" }, set: { projectChoices[file.id] = $0 })
                        )
                    }
                }
            }
        }
    }

    private var validNames: Bool {
        options.destinations.allSatisfy { id, destination in
            projectChoices[id] != "new" || !Project.canonicalName(destination.newProjectName).isEmpty
        }
    }

    @ViewBuilder private func previewSections(_ plan: TaskImport.Plan) -> some View {
        Section {
            LabeledContent("Stack", value: options.bucket.title)
            LabeledContent("Tasks to add", value: "\(plan.added)")
            LabeledContent("Already imported", value: "\(plan.duplicates)")
            LabeledContent("Skipped", value: "\(plan.skipped)")
            LabeledContent("New projects", value: "\(plan.projectsCreated)")
            LabeledContent("Ignored CSV rows", value: "\(files.filter { options.destinations[$0.id] != nil }.reduce(0) { $0 + $1.ignoredRows })")
        } footer: {
            Text("A backup is saved before import. Existing tasks are kept. Reimporting the same unchanged file with the same name skips previously imported rows, including deleted tasks. Edited or renamed exports can create duplicates.")
        }
        Section {
            Text(limits)
            Text(dates)
            Text("Todoist keeps its own alerts. Imported reminders may also notify you in DayHand.")
        }
        ForEach(files.filter { options.destinations[$0.id] != nil }) { file in
            Section(file.name) {
                if let destination = options.destinations[file.id] {
                    let project = destination.projectID.flatMap { store.project(id: $0) }
                    let categoryID = project != nil ? project?.categoryID : destination.categoryID
                    let name = project?.name ?? Project.canonicalName(destination.newProjectName)
                    LabeledContent("Project", value: name.isEmpty ? String(localized: "None") : name)
                    LabeledContent("Category", value: store.categories.first { $0.id == categoryID }?.label ?? String(localized: "None"))
                }
                ForEach(file.records) { record in
                    let dateExcluded = !includeUnparsedDates && file.unparsedDateIDs.contains(record.id)
                    Toggle(isOn: Binding(get: {
                        !dateExcluded && !options.excludedIDs.contains(record.id) && !store.hasImportedTodoistRow(record.id)
                    }, set: { included in
                        if included { options.excludedIDs.remove(record.id) } else { options.excludedIDs.insert(record.id) }
                        updatePreview()
                    })) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(record.title)
                            if file.unparsedDateIDs.contains(record.id) {
                                Text("Date needs review").font(.caption).foregroundStyle(.secondary)
                            }
                            if store.hasImportedTodoistRow(record.id) {
                                Text("Already imported").font(.caption).foregroundStyle(.secondary)
                            }
                            Text(record.notes).font(.caption).foregroundStyle(.secondary).lineLimit(4)
                        }
                    }.disabled(dateExcluded || store.hasImportedTodoistRow(record.id))
                }
            }
        }
    }

    private func updatePreview() {
        do { preview = try store.previewTodoist(files, options: options, includeUnparsedDates: includeUnparsedDates) }
        catch { report = error.localizedDescription }
    }

    private func importTasks() {
        do {
            let result = try store.importTodoist(files, options: options, includeUnparsedDates: includeUnparsedDates)
            didImport = true
            report = String(localized: "Added \(result.added) tasks. Skipped \(result.duplicates) already imported and \(result.skipped) other tasks. Todoist was left unchanged.")
        } catch { report = error.localizedDescription }
    }
}
