import SwiftUI
import UniformTypeIdentifiers

/// Where the user defines their categories: a label, an icon and a colour each.
struct SettingsView: View {
    @EnvironmentObject private var store: TodoStore
    @Environment(\.dismiss) private var dismiss

    @State private var editing: CardCategory?
    @State private var isAdding = false
    @State private var pendingDeletion: CardCategory?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var importReport: String?
    /// The report alert serves both CSV import and restoring a backup.
    @State private var reportTitle = "Import"
    @State private var isChoosingSyncFile = false
    @State private var isCreatingSyncFile = false
    @State private var syncReport: String?
    @State private var isChoosingImportMode = false
    @State private var isChoosingSyncMode = false
    @State private var replaceOnImport = false
    @State private var replaceOnSync = false
    @State private var isConfirmingDeleteAll = false
    @State private var pendingRestore: BackupInfo?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.categories) { category in
                        Button {
                            editing = category
                        } label: {
                            row(category)
                        }
                    }
                    .onDelete { offsets in
                        // Confirm, because deleting also un-labels cards.
                        if let first = offsets.first {
                            pendingDeletion = store.categories[first]
                        }
                    }
                    .onMove { source, destination in
                        store.moveCategories(from: source, to: destination)
                    }

                    Button {
                        isAdding = true
                    } label: {
                        Label("Add Category", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Categories")
                } footer: {
                    Text("Cards show the icon only. The label names the category here and for VoiceOver.")
                }

                Section {
                    NavigationLink {
                        ProjectsView().environmentObject(store)
                    } label: {
                        LabeledContent {
                            Text("\(store.projects.filter { !$0.isArchived }.count)")
                                .monospacedDigit()
                        } label: {
                            Label("Projects", systemImage: "number")
                        }
                    }
                } footer: {
                    Text("A project groups cards that belong to the same piece of work \u{2014} a trip, a client, a paper, a course. Type # in a new task to use one.")
                }

                Section {
                    Picker(selection: Binding(
                        get: { store.defaultCategoryID },
                        set: { store.setDefaultCategory($0) }
                    )) {
                        Text("None").tag(UUID?.none)
                        ForEach(store.categories) { category in
                            Label(category.label, systemImage: category.symbolName)
                                .tag(UUID?.some(category.id))
                        }
                    } label: {
                        Label("Default category", systemImage: "tag")
                    }
                    .disabled(store.categories.isEmpty)
                } header: {
                    Text("New cards")
                } footer: {
                    Text("New cards start with this category. You can still change it on the card.")
                }

                Section {
                    Button {
                        openLanguageSettings()
                    } label: {
                        LabeledContent {
                            Text(currentLanguage)
                                .foregroundStyle(.secondary)
                        } label: {
                            Label("Language", systemImage: "globe")
                        }
                    }
                } header: {
                    Text("Language")
                } footer: {
                    Text("DayDeck follows your device's language. To read it in another one, pick a language for this app in the system settings.")
                }

                Section {
                    if let name = store.syncFileName {
                        LabeledContent {
                            Text(name).foregroundStyle(.secondary)
                        } label: {
                            Label("Sync file", systemImage: "arrow.triangle.2.circlepath")
                        }

                        Button {
                            withAnimation { store.refreshFromSyncFile() }
                        } label: {
                            Label("Sync Now", systemImage: "arrow.clockwise")
                        }

                        Button(role: .destructive) {
                            store.stopUsingSyncFile()
                        } label: {
                            Label("Stop Using This File", systemImage: "xmark.circle")
                        }
                    } else {
                        Button {
                            isCreatingSyncFile = true
                        } label: {
                            Label("Create Sync File…", systemImage: "plus.rectangle.on.folder")
                        }

                        Button {
                            isChoosingSyncMode = true
                        } label: {
                            Label("Use Existing Sync File…", systemImage: "folder")
                        }
                    }
                } header: {
                    Text("Sync")
                } footer: {
                    Text(store.syncFileName == nil
                         ? "Put one file in iCloud Drive and point every device at it. iCloud syncs the file, so no paid developer account is needed."
                         : "Both devices read and write this one file. Changes are merged, so edits made on either side while offline are kept.")
                }

                Section {
                    Button {
                        isExporting = true
                    } label: {
                        Label("Export Cards as CSV…", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        isChoosingImportMode = true
                    } label: {
                        Label("Import Cards from CSV…", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("Cards")
                } footer: {
                    Text("Importing can either add to what is here or replace it. Cards are matched by id; categories and projects by name.")
                }

                Section {
                    let backups = store.availableBackups()
                    if backups.isEmpty {
                        Text("No backups yet. One is taken automatically each day the app is opened.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(backups) { backup in
                            Button {
                                pendingRestore = backup
                            } label: {
                                LabeledContent {
                                    Text("\(backup.cardCount) cards")
                                        .foregroundStyle(.secondary)
                                } label: {
                                    Label(
                                        Scheduler.relativeLabel(for: backup.takenAt),
                                        systemImage: "clock.arrow.circlepath"
                                    )
                                }
                            }
                        }
                    }
                } header: {
                    Text("Backups")
                } footer: {
                    Text("Taken automatically once a day: the most recent, the day before, and one from about a week ago. Tap one to restore it.")
                }

                Section {
                    Button(role: .destructive) {
                        isConfirmingDeleteAll = true
                    } label: {
                        Label("Delete All Cards", systemImage: "trash")
                    }
                    .disabled(store.cardCount == 0)
                } footer: {
                    Text("Removes every card on this device. Categories are kept. If a sync file is in use, the deletion reaches your other devices too.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    EditButton().disabled(store.categories.isEmpty)
                }
            }
            .confirmationDialog(
                "Import from CSV",
                isPresented: $isChoosingImportMode,
                titleVisibility: .visible
            ) {
                Button("Add to Existing Cards") { beginImport(replacing: false) }
                Button("Replace All Cards", role: .destructive) { beginImport(replacing: true) }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Replacing removes the \(store.cardCount) cards here first.")
            }
            .confirmationDialog(
                "Use Existing Sync File",
                isPresented: $isChoosingSyncMode,
                titleVisibility: .visible
            ) {
                Button("Merge With This Device") { beginSyncFile(replacing: false) }
                Button("Replace Cards on This Device", role: .destructive) { beginSyncFile(replacing: true) }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Merging keeps both sides. Replacing discards the \(store.cardCount) cards here and takes the file's.")
            }
            .alert(
                "Restore this backup?",
                isPresented: Binding(
                    get: { pendingRestore != nil },
                    set: { if !$0 { pendingRestore = nil } }
                ),
                presenting: pendingRestore
            ) { backup in
                Button("Restore", role: .destructive) {
                    let count = withAnimation { store.restore(from: backup.slot) }
                    // "from today", but "from Sat, 12 Sep": only the relative
                    // words read naturally in lowercase mid-sentence.
                    let when = Scheduler.relativeLabel(for: backup.takenAt)
                    let phrase = ["Today", "Yesterday"].contains(when) ? when.lowercased() : when
                    reportTitle = "Restore"
                    importReport = String(localized: "Restored \(count) cards from \(phrase).")
                }
                Button("Cancel", role: .cancel) { }
            } message: { backup in
                Text("The \(store.cardCount) cards here will be replaced by the \(backup.cardCount) in this backup. Categories and projects come back too.")
            }
            .alert("Delete all cards?", isPresented: $isConfirmingDeleteAll) {
                Button("Delete All", role: .destructive) {
                    withAnimation { store.deleteAllCards() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("\(store.cardCount) cards will be removed. This cannot be undone.")
            }
            .fileExporter(
                isPresented: $isCreatingSyncFile,
                document: SyncFileDocument(data: store.documentData()),
                contentType: .json,
                defaultFilename: "DayDeck Cards"
            ) { result in
                adoptSyncFile(from: result, creating: true, replacing: false)
            }
            .fileImporter(
                isPresented: $isChoosingSyncFile,
                // Broad on purpose: a file copied or renamed between devices may
                // not be reported as JSON, and a greyed-out file is impossible
                // to pick at all.
                allowedContentTypes: [.json, .plainText, .text, .data]
            ) { result in
                adoptSyncFile(from: result, creating: false, replacing: replaceOnSync)
            }
            .alert(
                "Sync",
                isPresented: Binding(
                    get: { syncReport != nil },
                    set: { if !$0 { syncReport = nil } }
                ),
                presenting: syncReport
            ) { _ in
                Button("OK") { }
            } message: { report in
                Text(report)
            }
            .fileExporter(
                isPresented: $isExporting,
                document: CSVFile(text: store.exportCSV()),
                contentType: .commaSeparatedText,
                defaultFilename: "DayDeck Cards"
            ) { _ in }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.commaSeparatedText, .plainText, .text]
            ) { result in
                importCards(from: result)
            }
            .alert(
                reportTitle,
                isPresented: Binding(
                    get: { importReport != nil },
                    set: { if !$0 { importReport = nil } }
                ),
                presenting: importReport
            ) { _ in
                Button("OK") { }
            } message: { report in
                Text(report)
            }
            .sheet(isPresented: $isAdding) {
                CategoryEditor(category: nil) { label, symbol, color in
                    store.addCategory(label: label, symbolName: symbol, color: color)
                }
            }
            .sheet(item: $editing) { category in
                CategoryEditor(category: category) { label, symbol, color in
                    store.updateCategory(
                        CardCategory(id: category.id, label: label, symbolName: symbol, color: color)
                    )
                }
            }
            .alert(
                "Delete category?",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                presenting: pendingDeletion
            ) { category in
                Button("Delete", role: .destructive) {
                    withAnimation { store.deleteCategory(category) }
                }
                Button("Cancel", role: .cancel) { }
            } message: { category in
                let count = store.cardCount(using: category)
                Text(
                    count == 0
                        ? "“\(category.label)” isn’t used by any card."
                        : String(localized: "\(count) cards will lose this category. The cards themselves are kept.")
                )
            }
        }
    }

    /// A sheet presented straight from a dialog's button can be swallowed while
    /// the dialog is still dismissing, so let the run loop turn over first.
    /// The language the app is actually being read in, named in that language:
    /// "Français", not "French", which is what the system settings will show.
    private var currentLanguage: String {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        let locale = Locale(identifier: code)
        let name = locale.localizedString(forLanguageCode: code) ?? code
        return name.capitalized(with: locale)
    }

    /// iOS gives every app that ships more than one language its own Language
    /// screen, so there is nothing to reimplement here — just a way to reach
    /// it. macOS keeps the same choice in Language & Region instead.
    private func openLanguageSettings() {
        #if targetEnvironment(macCatalyst)
        let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension")
        #else
        let url = URL(string: UIApplication.openSettingsURLString)
        #endif
        guard let url else { return }
        UIApplication.shared.open(url)
    }

    private func present(_ show: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: show)
    }

    private func beginImport(replacing: Bool) {
        replaceOnImport = replacing
        present { isImporting = true }
    }

    private func beginSyncFile(replacing: Bool) {
        replaceOnSync = replacing
        present { isChoosingSyncFile = true }
    }

    private func adoptSyncFile(from result: Result<URL, Error>, creating: Bool, replacing: Bool) {
        switch result {
        case .failure(let error):
            syncReport = "Could not use that file.\n\n\(error.localizedDescription)"
        case .success(let url):
            // Replacing with a file that holds nothing would leave the device
            // empty for no reason, so fall back to merging and say so.
            let hasContent = store.syncFileHasContent(at: url)
            let reallyReplace = replacing && hasContent

            let ok = withAnimation { store.useSyncFile(at: url, replacingLocal: reallyReplace) }
            guard ok else {
                syncReport = "That file could not be opened for syncing."
                return
            }

            let name = url.lastPathComponent
            if creating {
                syncReport = "Now syncing through “\(name)”. Point your other device at the same file."
            } else if reallyReplace {
                syncReport = "Now syncing through “\(name)”. This device's cards were replaced by the file's."
            } else if replacing && !hasContent {
                syncReport = "“\(name)” holds no cards, so nothing was replaced. Your cards are intact and now sync through it."
            } else {
                syncReport = "Now syncing through “\(name)”. Anything it already held has been merged in."
            }
        }
    }

    /// The picked file lives outside the app, so its access has to be opened
    /// and closed explicitly.
    private func importCards(from result: Result<URL, Error>) {
        reportTitle = "Import"
        switch result {
        case .failure(let error):
            importReport = "Could not open that file.\n\n\(error.localizedDescription)"
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            guard let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8)
                          ?? String(data: data, encoding: .isoLatin1) else {
                importReport = "That file could not be read as text."
                return
            }

            let summary = withAnimation {
                store.importCSV(text, replacingExisting: replaceOnImport)
            }
            var lines: [String] = []
            if summary.removed > 0 { lines.append("Removed \(summary.removed) existing card(s).") }
            lines.append("Added \(summary.added), updated \(summary.updated).")
            if summary.skipped > 0 { lines.append("\(summary.skipped) row(s) skipped.") }
            if replaceOnImport && summary.removed == 0 && summary.added == 0 {
                lines = ["That file held no cards, so nothing was replaced."]
            }
            importReport = lines.joined(separator: "\n")
        }
    }

    private func row(_ category: CardCategory) -> some View {
        HStack(spacing: 14) {
            Image(systemName: category.symbolName)
                .font(.title3)
                .foregroundStyle(category.tint)
                .frame(width: 30)

            Text(category.label)
                .foregroundStyle(Color.primary)

            Spacer()

            if store.defaultCategoryID == category.id {
                Text("Default")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color(.tertiarySystemFill)))
            }

            Text("\(store.cardCount(using: category))")
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
    }
}

/// Create or edit one category.
private struct CategoryEditor: View {
    let category: CardCategory?
    let onSave: (String, String, CategoryColor) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var label: String
    @State private var symbolName: String
    @State private var color: CategoryColor
    @FocusState private var labelFocused: Bool

    init(category: CardCategory?, onSave: @escaping (String, String, CategoryColor) -> Void) {
        self.category = category
        self.onSave = onSave
        _label = State(initialValue: category?.label ?? "")
        _symbolName = State(initialValue: category?.symbolName ?? CardCategory.iconChoices[0])
        _color = State(initialValue: category?.color ?? .indigo)
    }

    private var canSave: Bool {
        !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private let iconColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)

    var body: some View {
        NavigationStack {
            Form {
                Section("Label") {
                    TextField("e.g. Research", text: $label)
                        .focused($labelFocused)
                        .submitLabel(.done)
                }

                Section("Colour") {
                    HStack(spacing: 14) {
                        ForEach(CategoryColor.allCases) { option in
                            Button {
                                color = option
                            } label: {
                                Circle()
                                    .fill(option.tint)
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        if option == color {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(option.displayName)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                }

                Section("Icon") {
                    LazyVGrid(columns: iconColumns, spacing: 10) {
                        ForEach(CardCategory.iconChoices, id: \.self) { name in
                            Button {
                                symbolName = name
                            } label: {
                                Image(systemName: name)
                                    .font(.body)
                                    .frame(width: 40, height: 40)
                                    .foregroundStyle(name == symbolName ? color.tint : Color.secondary)
                                    .background {
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .fill(name == symbolName
                                                  ? color.tint.opacity(0.18)
                                                  : Color(.tertiarySystemFill))
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(name)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(category == nil ? "New Category" : "Edit Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(label, symbolName, color)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear { if category == nil { labelFocused = true } }
        }
    }
}

/// Wraps the exported text so the system save panel can write it out.
struct CSVFile: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        text = String(data: data, encoding: .utf8) ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// Writes the current store out so the user can place the shared sync file
/// wherever they like — normally somewhere in iCloud Drive.
struct SyncFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
