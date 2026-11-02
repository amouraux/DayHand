import SwiftUI
import UniformTypeIdentifiers

/// Where the user defines their categories: a label, an icon and a colour each.
struct SettingsView: View {
    @EnvironmentObject private var store: TodoStore
    @Environment(\.dismiss) private var dismiss

    @State private var editing: CardCategory?
    /// Reordering and deleting categories, driven by the button in that
    /// section's own header rather than one in the navigation bar.
    @State private var categoryEdit: EditMode = .inactive
    @State private var isAdding = false
    @State private var pendingDeletion: CardCategory?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var isImportingReminders = false
    @State private var isImportingTodoist = false
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
    @AppStorage(Appearance.key) private var appearance = Appearance.automatic
    @State private var languageCode = SettingsView.storedLanguageCode()
    /// The trial screen is presented from here, with the other sheets, and not
    /// from the row that opens it: a row is rebuilt whenever the store
    /// publishes, and a sheet hanging off it would go with it.
    @State private var showsTrial = false
    @State private var showsIntro = false
    @State private var pendingRestore: BackupFile?
    @State private var isChoosingRestoreFile = false
    /// A file picked by hand, read and waiting for the user to confirm.
    @State private var pendingFileRestore: FileRestore?
    /// An automatic backup the user asked to delete, held for confirmation.
    @State private var pendingBackupDeletion: BackupFile?

    /// Unlocked, or in a trial that is still running. An ended trial is still
    /// recorded as a trial, so the stored state alone cannot say.
    private var hasFullAccess: Bool {
        store.entitlement.hasFullAccess(now: store.purchases.now)
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }

    var body: some View {
        NavigationStack {
            List {
                // Without full access, which includes a trial that has ended, the
                // trial and the unlock come first. Otherwise the purchase stays
                // quietly at the bottom.
                if !hasFullAccess {
                    PurchasesSection(showsTrial: $showsTrial)
                }

                Section {
                    NavigationLink {
                        ProjectReviewView().environmentObject(store)
                    } label: {
                        Label("Review projects", systemImage: "paperclip")
                    }
                    NavigationLink {
                        StackReviewView(stack: .all).environmentObject(store)
                    } label: {
                        LabeledContent {
                            Text("\(store.items.filter { !$0.isCompleted }.count)").monospacedDigit()
                        } label: {
                            Label("Review all tasks", systemImage: "square.stack.3d.up")
                        }
                    }
                    NavigationLink {
                        InboxReviewView().environmentObject(store)
                    } label: {
                        LabeledContent {
                            Text("\(store.items.filter { $0.bucket == .inbox }.count)")
                                .monospacedDigit()
                        } label: {
                            Label("Review Inbox", systemImage: "tray")
                        }
                    }
                    NavigationLink {
                        NowReviewView().environmentObject(store)
                    } label: {
                        LabeledContent {
                            Text("\(store.items.filter { $0.bucket == .today }.count)").monospacedDigit()
                        } label: {
                            Label("Review Now", systemImage: "sun.max")
                        }
                    }
                    NavigationLink {
                        StackReviewView(stack: .waiting).environmentObject(store)
                    } label: {
                        LabeledContent {
                            Text("\(store.items.filter { $0.bucket == .waiting }.count)").monospacedDigit()
                        } label: {
                            Label("Review Waiting", systemImage: "pause.circle")
                        }
                    }
                    NavigationLink {
                        StackReviewView(stack: .nextLater).environmentObject(store)
                    } label: {
                        LabeledContent {
                            Text("\(store.items.filter { $0.bucket == .tomorrow || $0.bucket == .later }.count)").monospacedDigit()
                        } label: {
                            Label("Review Next and Later", systemImage: "sunrise")
                        }
                    }
                } header: {
                    Text("Review")
                } footer: {
                    Text("Review your tasks one at a time. You can stop and resume whenever you like.")
                }

                Section {
                    NavigationLink {
                        TimelineView(title: String(localized: "Completed"), cards: store.items)
                            .environmentObject(store)
                    } label: {
                        Label("Timeline", systemImage: "calendar.day.timeline.left")
                    }
                } header: {
                    Text("Completed")
                } footer: {
                    Text("What you have accomplished, grouped by the day you did it.")
                }

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
                    // Beside the thing it edits. In the navigation bar it read
                    // as editing More itself, which is sync, backups, CSV and
                    // language as well — none of which it touches.
                    HStack {
                        Text("Categories")
                        Spacer()
                        // Not an `EditButton`: that one reaches for an
                        // `editMode` binding the navigation stack provides,
                        // and whether it still finds it from inside a section
                        // header is exactly the kind of thing that works until
                        // it quietly does not. The state is held here and
                        // handed to the list below, so there is nothing to
                        // propagate.
                        Button(categoryEdit.isEditing ? "Done" : "Edit") {
                            withAnimation {
                                categoryEdit = categoryEdit.isEditing ? .inactive : .active
                            }
                        }
                        .disabled(store.categories.isEmpty)
                        .textCase(nil)
                    }
                } footer: {
                    Text("Tasks and projects are grouped by categories. Create your own \u{2014} tasks show the icon alone, so the label names it here and for VoiceOver.")
                }

                // Projects are organised in Organise, not here: one place to
                // rename, group, archive and merge them. What is left is the
                // one-time conversion, which is housekeeping rather than
                // organisation, and only appears while there is work for it.
                Section {
                    let found = ProjectConversion.candidates(cards: store.items, existing: store.projects)
                    if !found.isEmpty {
                        NavigationLink {
                            ProjectConversionView(candidates: found).environmentObject(store)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Convert Title Prefixes into Projects…")
                                    Text("\(found.count) possible projects found in your titles")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "wand.and.stars")
                            }
                        }
                    } else {
                        LabeledContent {
                            Text("\(store.projects.filter { !$0.isArchived }.count)")
                                .monospacedDigit()
                        } label: {
                            Label("Projects", systemImage: "paperclip")
                        }
                    }
                } footer: {
                    Text("A project groups tasks that belong to the same piece of work \u{2014} a trip, a paper, a course, an assignment. Start a task with its name and it is offered below the field. Rename, group and archive them in Organise: tap \u{24D8} beside a project.")
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
                    Text("New tasks")
                } footer: {
                    Text("New tasks start with this category. You can still change it on the task.")
                }

                Section {
                    Picker("Appearance", selection: $appearance) {
                        Text("Automatic").tag(Appearance.automatic)
                        Text("Light").tag(Appearance.light)
                        Text("Dark").tag(Appearance.dark)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Automatic follows your device's setting.")
                }

                Section {
                    Picker(selection: $languageCode) {
                        Text("Automatic").tag("")
                        ForEach(AppLanguage.all) { language in
                            Text(verbatim: language.name).tag(language.code)
                        }
                    } label: {
                        Label("Language", systemImage: "globe")
                    }
                    .onChange(of: languageCode) { _, chosen in Self.storeLanguage(chosen) }
                } header: {
                    Text("Language")
                } footer: {
                    Text("Automatic follows your device's language. A change applies the next time DayHand opens.")
                }

                Section {
                    if let name = store.syncFileName {
                        LabeledContent {
                            Text(name).foregroundStyle(.secondary)
                        } label: {
                            Label("Sync file", systemImage: "arrow.triangle.2.circlepath")
                        }
                    } else {
                        // Said here and nowhere else. One device needs no sync
                        // file and should not be nagged about it — but a
                        // device that has lost one looks exactly like a device
                        // that never had one, and the only way to tell was to
                        // notice the other one had stopped agreeing with you.
                        LabeledContent {
                            Text("Not syncing").foregroundStyle(.secondary)
                        } label: {
                            Label("Sync file", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .foregroundStyle(.secondary)
                    }

                    if store.syncFileName != nil {

                        Button {
                            withAnimation { store.refreshFromSyncFile() }
                        } label: {
                            Label("Sync Now", systemImage: "arrow.clockwise")
                        }

                        // Pressing the button used to look the same whether it
                        // merged forty cards, found nothing, or could not read
                        // the file at all. It says which, now.
                        if let sync = store.lastSync {
                            LabeledContent {
                                Text(sync.at, style: .relative)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            } label: {
                                Label {
                                    Text(syncSummary(sync))
                                } icon: {
                                    Image(systemName: sync.couldNotRead
                                          ? "exclamationmark.triangle" : "checkmark.circle")
                                }
                                .foregroundStyle(sync.couldNotRead ? Color.orange : .secondary)
                            }
                            .font(.subheadline)
                            .transition(.opacity)
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
                         : "Every device reads and writes this one file. Changes are merged, so edits made on any of them while offline are kept.")
                }

                Section {
                    Button {
                        isExporting = true
                    } label: {
                        Label("Export as CSV…", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        isChoosingImportMode = true
                    } label: {
                        Label("Import from CSV…", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        isImportingReminders = true
                    } label: {
                        Label("Import from Apple Reminders…", systemImage: "checklist")
                    }
                    Button {
                        isImportingTodoist = true
                    } label: {
                        Label("Import from Todoist…", systemImage: "doc.text")
                    }
                } header: {
                    Text("Tasks")
                } footer: {
                    Text("DayHand CSV import can either add to what is here or replace the tasks. Rows are matched by id, then by name, and only what the file says is changed.")
                }

                Section {
                    Button {
                        if let url = store.backUpNow() {
                            reportTitle = String(localized: "Backup")
                            importReport = String(localized: "Saved as \(url.lastPathComponent).")
                        } else {
                            reportTitle = String(localized: "Backup")
                            importReport = String(localized: "Could not write the backup.")
                        }
                    } label: {
                        Label("Back Up Now", systemImage: "arrow.down.document")
                    }

                    Button {
                        present { isChoosingRestoreFile = true }
                    } label: {
                        Label("Restore From File…", systemImage: "doc.badge.arrow.up")
                    }

                    let backups = store.availableBackups()
                    let mine = store.backupDeviceName
                    if backups.isEmpty {
                        Text("No backups yet. One is taken automatically each day the app is opened.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(backups) { backup in
                            Button {
                                pendingRestore = backup
                            } label: {
                                LabeledContent {
                                    Text("\(backup.cardCount) tasks")
                                        .foregroundStyle(.secondary)
                                } label: {
                                    Label {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(Scheduler.relativeLabel(for: backup.takenAt))
                                            // Where it came from, if not here —
                                            // naming this device on every row
                                            // would be noise. Otherwise which
                                            // kind it is, because the automatic
                                            // copy and a manual one taken the
                                            // same day both read "Today", and
                                            // picking the wrong one replaces
                                            // every card.
                                            if backup.device != mine {
                                                caption(backup.device)
                                            } else if backup.kind.isManual {
                                                caption(String(localized: "Saved by hand"))
                                            }
                                        }
                                    } icon: {
                                        Image(systemName: backup.kind.isManual
                                              ? "arrow.down.document" : "clock.arrow.circlepath")
                                    }
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                ShareLink(item: backup.url) {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                }
                                .tint(.accentColor)
                            }
                            // Delete on the other edge rather than behind
                            // Share. Two actions on one edge mean a full swipe
                            // runs the first and the second is reachable only
                            // by stopping halfway, which is no way to find it.
                            //
                            // `allowsFullSwipe` is off because the file is
                            // removed, not trashed. A full swipe is too easy a
                            // way to lose the copy someone made on purpose,
                            // and the tap is the confirmation.
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    delete(backup)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            // A swipe needs a finger, and the Mac has a pointer:
                            // there, the same three actions were unreachable.
                            // On the phone it is a press and hold.
                            .contextMenu {
                                Button { pendingRestore = backup } label: {
                                    Label("Restore", systemImage: "arrow.uturn.backward")
                                }
                                ShareLink(item: backup.url) {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                }
                                Button(role: .destructive) { delete(backup) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    Text("Backups")
                } footer: {
                    #if targetEnvironment(macCatalyst)
                    Text("Three backups are kept automatically — from yesterday, the day before and about a week ago — plus every one you take by hand, under its date. Click a backup to restore it. Right-click it to share or delete it. Each file is named for this device (\(store.backupDeviceName)), so copies from two devices can sit side by side.")
                    #else
                    Text("Three backups are kept automatically — from yesterday, the day before and about a week ago — plus every one you take by hand, under its date. Tap a backup to restore it. Swipe it, or press and hold, to share or delete it. Each file is named for this device (\(store.backupDeviceName)), so copies from two devices can sit side by side.")
                    #endif
                }

                if store.hasExamples {
                    Section {
                        Button {
                            withAnimation { store.removeExamples() }
                        } label: {
                            Label("Remove examples", systemImage: "rectangle.stack.badge.minus")
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        isConfirmingDeleteAll = true
                    } label: {
                        Label("Delete All Tasks", systemImage: "trash")
                    }
                    .disabled(store.cardCount == 0)
                } footer: {
                    Text("Removes every task on this device. Categories are kept. If a sync file is in use, the deletion reaches your other devices too.")
                }

                if hasFullAccess {
                    PurchasesSection(showsTrial: $showsTrial)
                }

                Section {
                    Button {
                        showsIntro = true
                    } label: {
                        Label("How DayHand works", systemImage: "play.circle")
                    }
                    Link(destination: Self.helpURL) {
                        LabeledContent {
                            Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
                        } label: {
                            Label("Help and support", systemImage: "questionmark.circle")
                        }
                    }
                    Link(destination: Self.privacyURL) {
                        LabeledContent {
                            Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
                        } label: {
                            Label("Privacy policy", systemImage: "hand.raised")
                        }
                    }
                } header: {
                    Text("Help")
                } footer: {
                    // The support page asks for the version and build, and
                    // nothing else in the app says which this is.
                    Text(verbatim: Self.versionLine)
                }
            }
            .environment(\.editMode, $categoryEdit)
            .navigationTitle("More")
            .sheet(isPresented: $showsTrial) { TrialView().environmentObject(store) }
            .sheet(isPresented: $showsIntro) { IntroView(offersChoice: false) }
            .purchaseNotice()
            .sheet(isPresented: $isImportingReminders) {
                RemindersImportView().environmentObject(store)
            }
            .sheet(isPresented: $isImportingTodoist) {
                TodoistImportView().environmentObject(store)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Import from CSV",
                isPresented: $isChoosingImportMode,
                titleVisibility: .visible
            ) {
                Button("Add to Existing Tasks") { beginImport(replacing: false) }
                Button("Replace All Tasks", role: .destructive) { beginImport(replacing: true) }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Replacing removes the \(store.cardCount) tasks here first.")
            }
            .confirmationDialog(
                "Use Existing Sync File",
                isPresented: $isChoosingSyncMode,
                titleVisibility: .visible
            ) {
                Button("Merge With This Device") { beginSyncFile(replacing: false) }
                Button("Replace Tasks on This Device", role: .destructive) { beginSyncFile(replacing: true) }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Merging keeps both sides. Replacing discards the \(store.cardCount) tasks here and takes the file's.")
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
                    let count = withAnimation { store.restore(from: backup) }
                    // "from today", but "from Sat, 12 Sep": only the relative
                    // words read naturally in lowercase mid-sentence.
                    let when = Scheduler.relativeLabel(for: backup.takenAt)
                    let phrase = Scheduler.labelIsWord(for: backup.takenAt) ? when.lowercased() : when
                    reportTitle = "Restore"
                    importReport = String(localized: "Restored \(count) tasks from \(phrase).")
                }
                Button("Cancel", role: .cancel) { }
            } message: { backup in
                Text("The \(store.cardCount) tasks here will be replaced by the \(backup.cardCount) in this backup. Categories and projects come back too.")
            }
            .fileImporter(
                isPresented: $isChoosingRestoreFile,
                // Broad for the same reason as the sync file picker.
                allowedContentTypes: [.json, .plainText, .text, .data]
            ) { result in
                chooseRestoreFile(result)
            }
            .alert(
                "Restore this file?",
                isPresented: Binding(
                    get: { pendingFileRestore != nil },
                    set: { if !$0 { pendingFileRestore = nil } }
                ),
                presenting: pendingFileRestore
            ) { file in
                Button("Restore", role: .destructive) {
                    let count = withAnimation { store.restore(file.document) }
                    reportTitle = "Restore"
                    importReport = String(localized: "Restored \(count) tasks from “\(file.name)”.")
                }
                Button("Cancel", role: .cancel) { }
            } message: { file in
                Text("The \(store.cardCount) tasks here will be replaced by the \(file.document.cards.count) in this file. Categories and projects come back too.")
            }
            .confirmationDialog(
                "Delete this backup?",
                isPresented: Binding(
                    get: { pendingBackupDeletion != nil },
                    set: { if !$0 { pendingBackupDeletion = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingBackupDeletion
            ) { backup in
                Button("Delete", role: .destructive) {
                    withAnimation { store.deleteBackup(backup) }
                }
                Button("Cancel", role: .cancel) { }
            } message: { _ in
                Text("This is one of the automatic backups. They are replaced as the days pass, but until then there is no copy from that day.")
            }
            .alert("Delete all tasks?", isPresented: $isConfirmingDeleteAll) {
                Button("Delete All", role: .destructive) {
                    withAnimation { store.deleteAllCards() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("\(store.cardCount) tasks will be removed. This cannot be undone.")
            }
            .fileExporter(
                isPresented: $isCreatingSyncFile,
                document: SyncFileDocument(data: store.documentData()),
                contentType: .json,
                defaultFilename: "DayHand Tasks"
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
                defaultFilename: "DayHand Tasks"
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
                        ? "“\(category.label)” isn’t used by any task."
                        : String(localized: "\(count) tasks will lose this category. The tasks themselves are kept.")
                )
            }
        }
    }

    /// The choice stored for this app alone, "" when it follows the device.
    ///
    /// Only the app's own domain is read: the standard defaults also answer with
    /// the system's list, which would make every device look like a choice.
    private static func storedLanguageCode() -> String {
        let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
        guard let stored = (domain?["AppleLanguages"] as? [String])?.first else { return "" }
        return AppLanguage.matching(stored)?.code ?? ""
    }

    /// Writes the choice where the system looks for it at launch. It is the key
    /// the system's own per-app Language screen writes, so the two agree. A
    /// SwiftUI view cannot swap the bundle it reads its strings from while
    /// running, which is why the footer promises the next launch and no more.
    private static func storeLanguage(_ code: String) {
        guard code != storedLanguageCode() else { return }
        if code.isEmpty {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        }
    }

    /// Says what happened, not that it succeeded.
    private func syncSummary(_ sync: TodoStore.SyncOutcome) -> String {
        if sync.needsNewerVersion {
            return String(localized: "The sync file was saved by a newer version of DayHand. Update the app to keep syncing.")
        }
        if sync.couldNotRead { return String(localized: "Could not read the sync file") }
        let c = sync.change
        if c.isNothing { return String(localized: "Already up to date") }

        var parts: [String] = []
        if c.arrived > 0 { parts.append(String(localized: "\(c.arrived) tasks arrived")) }
        if c.changed > 0 { parts.append(String(localized: "\(c.changed) tasks updated")) }
        if c.removed > 0 { parts.append(String(localized: "\(c.removed) tasks removed")) }
        return parts.joined(separator: ", ")
    }

    /// The site's pages in the language the app is being read in, when the site
    /// has them; English otherwise. The folder names are the site's own, so they
    /// must match `docs/<folder>/`. App Store Connect asks for the same
    /// addresses; keep them in step.
    private static func siteURL(help: Bool) -> URL {
        let translated: Set<String> = ["de", "es", "fr", "it", "nl", "pt-pt", "pt-br",
                                       "ja", "ko", "sv", "da", "nb", "fi", "pl"]
        let language = (Bundle.main.preferredLocalizations.first ?? "en").lowercased()
        let base = "https://amouraux.github.io/DayHand/"
        if translated.contains(language) {
            return URL(string: base + language + (help ? "/help.html" : "/privacy.html"))!
        }
        return URL(string: base + (help ? "help/" : "privacy.html"))!
    }

    private static var helpURL: URL { siteURL(help: true) }
    private static var privacyURL: URL { siteURL(help: false) }

    private static var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "DayHand \(version) (\(build))"
    }

    private func present(_ show: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: show)
    }

    /// One you took by hand is removed at once, as the swipe always did. An
    /// automatic one is asked about first: it is the copy from that day, and
    /// nothing else holds it until the rotation catches up.
    private func delete(_ backup: BackupFile) {
        if backup.kind.isManual {
            withAnimation { store.deleteBackup(backup) }
        } else {
            pendingBackupDeletion = backup
        }
    }

    /// The picked file lives outside the app, so its access has to be opened
    /// and closed explicitly. It is read now and applied only on confirmation.
    private func chooseRestoreFile(_ result: Result<URL, Error>) {
        reportTitle = "Restore"
        switch result {
        case .failure(let error):
            importReport = "Could not open that file.\n\n\(error.localizedDescription)"
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            guard let data = try? Data(contentsOf: url),
                  let document = store.document(from: data) else {
                importReport = String(localized: "That file could not be read as DayHand tasks.")
                return
            }
            pendingFileRestore = FileRestore(document: document, name: url.lastPathComponent)
        }
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
            // Syncing writes into the file, so one that holds something else
            // would be overwritten. A new file we just made is ours already.
            if !creating {
                switch store.inspectSyncFile(at: url) {
                case .none:
                    syncReport = "That file could not be opened for syncing."
                    return
                case .some(.other):
                    syncReport = String(localized: "“\(url.lastPathComponent)” does not look like a DayHand file, so it was not used. Syncing would have overwritten what it holds. Nothing was changed.")
                    return
                case .some(.newerVersion):
                    syncReport = String(localized: "“\(url.lastPathComponent)” was saved by a newer version of DayHand, so it was not used. Update DayHand to use it. Nothing was changed.")
                    return
                case .some(.empty), .some(.dayHand):
                    break
                }
            }

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
                syncReport = "Now syncing through “\(name)”. This device's tasks were replaced by the file's."
            } else if replacing && !hasContent {
                syncReport = "“\(name)” holds no tasks, so nothing was replaced. Your tasks are intact and now sync through it."
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
            if summary.removed > 0 { lines.append("Removed \(summary.removed) existing task(s).") }
            lines.append("Added \(summary.added), updated \(summary.updated).")
            if summary.skipped > 0 { lines.append("\(summary.skipped) row(s) skipped.") }
            if replaceOnImport && summary.removed == 0 && summary.added == 0 {
                lines = ["That file held no tasks, so nothing was replaced."]
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
/// Naming, picking an icon for and colouring one category. Used from More,
/// where categories are added and reordered, and from Organise, where one is
/// looked at in place.
struct CategoryEditor: View {
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

/// A file chosen for restoring, decoded and held until the user agrees.
private struct FileRestore {
    let document: StoreDocument
    let name: String
}

/// Light, dark, or whatever the device is set to. Kept on this device alone: a
/// phone in the evening and a Mac in daylight are not a disagreement to sync.
enum Appearance: String {
    case automatic, light, dark

    static let key = "appearance"

    /// Nil hands the choice back to the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .automatic: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

