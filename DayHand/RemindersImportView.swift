import SwiftUI
import EventKit

/// EventKit is confined to this adapter. The importer below only consumes a
/// snapshot and has no API that could edit the source reminders.
@MainActor
final class AppleRemindersReader: ObservableObject {
    struct ListInfo: Identifiable {
        let id: String
        let title: String
        let account: String
    }

    @Published private(set) var lists: [ListInfo] = []
    @Published private(set) var records: [TaskImportRecord] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoaded = false
    @Published private(set) var error: String?
    @Published private(set) var accessDenied = false
    private let eventStore = EKEventStore()

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        accessDenied = false
        defer { isLoading = false }
        do {
            guard try await eventStore.requestFullAccessToReminders() else {
                accessDenied = true
                error = String(localized: "Allow Reminders access in system settings, then try again.")
                return
            }
            let calendars = eventStore.calendars(for: .reminder)
            let fetched: [EKReminder]?
            if calendars.isEmpty {
                fetched = []
            } else {
                let predicate = eventStore.predicateForReminders(in: calendars)
                fetched = await withCheckedContinuation { continuation in
                    eventStore.fetchReminders(matching: predicate) { reminders in
                        continuation.resume(returning: reminders)
                    }
                }
            }
            guard let fetched else {
                error = String(localized: "Reminders could not be read. Please try again.")
                return
            }
            lists = calendars.map {
                ListInfo(id: $0.calendarIdentifier, title: $0.title, account: $0.source.title)
            }.sorted { ($0.account, $0.title) < ($1.account, $1.title) }
            records = fetched.map { reminder in
                var notes = [reminder.notes ?? ""]
                notes.append(String(localized: "Source list") + ": " + reminder.calendar.title)
                if let url = reminder.url { notes.append(url.absoluteString) }
                if let location = reminder.location, !location.isEmpty {
                    notes.append(String(localized: "Location") + ": " + location)
                }
                let due = TaskImport.date(from: reminder.dueDateComponents)
                if let due {
                    let hasTime = reminder.dueDateComponents?.hour != nil
                    notes.append(String(localized: "Original due date") + ": " +
                                 due.formatted(date: .abbreviated, time: hasTime ? .shortened : .omitted))
                }
                if let start = TaskImport.date(from: reminder.startDateComponents) {
                    notes.append(String(localized: "Original start date") + ": " + start.formatted())
                }
                if reminder.priority > 0 {
                    notes.append(String(localized: "Original priority") + ": \(reminder.priority)")
                }
                if reminder.hasAlarms {
                    notes.append(String(localized: "Original alerts are not transferred."))
                }
                return TaskImportRecord(
                    id: reminder.calendarItemIdentifier,
                    listID: reminder.calendar.calendarIdentifier,
                    title: reminder.title ?? "",
                    notes: notes.filter { !$0.isEmpty }.joined(separator: "\n\n"),
                    dueDate: due, createdAt: reminder.creationDate,
                    isCompleted: reminder.isCompleted, completedAt: reminder.completionDate,
                    isRecurring: reminder.hasRecurrenceRules
                )
            }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            isLoaded = true
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct RemindersImportView: View {
    @EnvironmentObject private var store: TodoStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var reader = AppleRemindersReader()
    @State private var options = TaskImport.Options()
    @State private var projectChoices: [String: String] = [:]
    @State private var preview: TaskImport.Plan?
    @State private var report: String?
    @State private var didImport = false

    private var previewRecords: [TaskImportRecord] {
        reader.records.filter {
            options.destinations[$0.listID] != nil && !$0.isRecurring &&
            (options.includeCompleted || !$0.isCompleted) &&
            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let preview {
                    previewSections(preview)
                } else if reader.isLoaded {
                    mappingSections
                } else {
                    connectionSection
                }
            }
            .navigationTitle(preview == nil ? String(localized: "Import from Apple Reminders") : String(localized: "Review import"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(preview == nil ? String(localized: "Cancel") : String(localized: "Back")) {
                        if preview != nil { preview = nil }
                        else { dismiss() }
                    }
                }
                if reader.isLoaded {
                    ToolbarItem(placement: .confirmationAction) {
                        if let preview {
                            Button("Import") { importTasks() }
                                .disabled(preview.added == 0)
                        } else {
                            Button("Preview") { updatePreview() }
                                .disabled(options.destinations.isEmpty || !validNames)
                        }
                    }
                }
            }
            .alert(didImport ? String(localized: "Import complete") : String(localized: "Import"), isPresented: Binding(
                get: { report != nil }, set: { if !$0 { report = nil } }
            )) {
                Button("OK") {
                    report = nil
                    if didImport { dismiss() }
                }
            } message: { Text(report ?? "") }
        }
    }

    private var connectionSection: some View {
        Section {
            Text("Choose which lists to copy into DayHand. Apple requires full Reminders access to read them. DayHand only reads your reminders and never changes them.")
            if reader.isLoading {
                ProgressView("Reading reminders…")
            } else {
                if let error = reader.error { Text(error).foregroundStyle(.secondary) }
                if reader.accessDenied {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
                Button(reader.error == nil ? String(localized: "Choose lists…") : String(localized: "Try again")) {
                    Task { await reader.load() }
                }
            }
        } footer: {
            Text("This is a one-time copy. Later changes in either app are independent.")
        }
    }

    @ViewBuilder private var mappingSections: some View {
        Section {
            Picker("Stack", selection: $options.bucket) {
                ForEach(Bucket.quickMoveTargets) { Text($0.title).tag($0) }
            }
            Toggle("Include completed tasks", isOn: $options.includeCompleted)
            Toggle("Use due dates as reminders", isOn: $options.importDates)
        } footer: {
            Text("Due dates become reminders at 9 a.m. on that day, not deadlines. Original dates and times stay in Notes even when this is off. Dates never move tasks between stacks.")
        }
        if reader.lists.isEmpty {
            Section { Text("No Reminders lists are available on this device.") }
        }
        ForEach(reader.lists) { list in
            Section {
                Toggle(isOn: selected(list.id)) {
                    VStack(alignment: .leading) {
                        Text(list.title)
                        Text(list.account).font(.caption).foregroundStyle(.secondary)
                        Text("\(reader.records.filter { $0.listID == list.id }.count) tasks")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if options.destinations[list.id] != nil {
                    destinationRows(list)
                }
            }
        }
        Section {
            Text("Recurring reminders are skipped. Subtasks, tags, attachments and smart-list rules are not preserved. Notes, links, dates, locations and priority values are kept as text in Notes.")
        }
    }

    private var validNames: Bool {
        options.destinations.allSatisfy { id, destination in
            projectChoices[id] != "new" || !Project.canonicalName(destination.newProjectName).isEmpty
        }
    }

    private func selected(_ id: String) -> Binding<Bool> {
        Binding(get: { options.destinations[id] != nil }, set: { selected in
            if selected {
                options.destinations[id] = TaskImportDestination(categoryID: store.defaultCategoryID)
                projectChoices[id] = "none"
            } else {
                options.destinations.removeValue(forKey: id)
                projectChoices.removeValue(forKey: id)
            }
        })
    }

    private func destinationRows(_ list: AppleRemindersReader.ListInfo) -> some View {
        TaskImportDestinationFields(
            suggestedName: list.title,
            destination: Binding(get: { options.destinations[list.id] ?? TaskImportDestination() },
                                 set: { options.destinations[list.id] = $0 }),
            projectChoice: Binding(get: { projectChoices[list.id] ?? "none" },
                                   set: { projectChoices[list.id] = $0 })
        )
    }

    @ViewBuilder private func previewSections(_ plan: TaskImport.Plan) -> some View {
        Section {
            LabeledContent("Stack", value: options.bucket.title)
            LabeledContent("Tasks to add", value: "\(plan.added)")
            LabeledContent("Already imported", value: "\(plan.duplicates)")
            LabeledContent("Skipped", value: "\(plan.skipped)")
            LabeledContent("New projects", value: "\(plan.projectsCreated)")
        } footer: {
            Text("A backup is saved before import. Existing DayHand tasks are kept. Repeat imports skip tasks already imported on this device, including ones you deleted. Importing again on another device or after an account reset can create duplicates.")
        }
        Section {
            Text("Apple Reminders keeps its own alerts. Imported future reminders can also notify you in DayHand. Past dates are marked as answered; their tasks can still appear in Attention.")
        }
        ForEach(reader.lists.filter { options.destinations[$0.id] != nil }) { list in
            Section(list.title) {
                if let destination = options.destinations[list.id] {
                    let project = destination.projectID.flatMap { store.project(id: $0) }
                    let name = project?.name ?? Project.canonicalName(destination.newProjectName)
                    let categoryID = project != nil ? project?.categoryID : destination.categoryID
                    LabeledContent("Project", value: name.isEmpty ? String(localized: "None") : name)
                    LabeledContent("Category", value: store.categories.first { $0.id == categoryID }?.label ?? String(localized: "None"))
                }
                ForEach(previewRecords.filter { $0.listID == list.id }) { record in
                    Toggle(isOn: Binding(get: { !options.excludedIDs.contains(record.id) && !store.hasImportedReminder(record.id) }, set: { included in
                        if included { options.excludedIDs.remove(record.id) }
                        else { options.excludedIDs.insert(record.id) }
                        updatePreview()
                    })) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(record.title)
                            if store.hasImportedReminder(record.id) {
                                Text("Already imported").font(.caption).foregroundStyle(.secondary)
                            }
                            if !record.notes.isEmpty {
                                Text(record.notes).font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                        }
                    }
                    .disabled(store.hasImportedReminder(record.id))
                }
            }
        }
    }

    private func updatePreview() {
        do { preview = try store.previewReminders(reader.records, options: options) }
        catch { report = error.localizedDescription }
    }

    private func importTasks() {
        do {
            let result = try store.importReminders(reader.records, options: options)
            didImport = true
            report = String(localized: "Added \(result.added) tasks. Skipped \(result.duplicates) already imported and \(result.skipped) other tasks. Your Apple Reminders were left unchanged.")
        } catch { report = error.localizedDescription }
    }
}
