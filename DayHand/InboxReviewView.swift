import SwiftUI

struct InboxReviewView: View {
    @EnvironmentObject private var store: TodoStore
    // Device-local UI state: this must never compete with task edits in sync.
    @AppStorage("inboxReviewSession.v1") private var savedSession = ""
    @State private var session: InboxReviewSession?
    @State private var editing: TodoItem?
    @State private var deleting: TodoItem?

    private var remaining: [TodoItem] { session?.remaining(in: store.items) ?? [] }
    private var inboxCount: Int { store.items.filter { $0.bucket == .inbox }.count }

    var body: some View {
        List {
            if let card = remaining.first {
                Section {
                    Text("Where does this task belong?")
                        .font(.headline)
                    Text("\(remaining.count) left in this review")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("All Inbox tasks, including those outside your current filters.")
                }

                Section {
                    Text(card.title)
                        .font(.title3.weight(.semibold))
                        .textSelection(.enabled)
                    SwiftUI.TimelineView(.periodic(from: .now, by: 60)) { context in
                        if let days = InboxReviewSession.daysInStack(since: card.enteredStackAt, now: context.date) {
                            Group {
                                if days == 0 {
                                    Text("Entered Inbox today")
                                } else if days == 1 {
                                    Text("In Inbox for 1 day")
                                } else {
                                    Text("In Inbox for \(days) days")
                                }
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                    }
                    if let project = store.project(for: card) {
                        Label(project.name, systemImage: "folder")
                    }
                    if let category = store.category(for: card) {
                        Label(category.label, systemImage: category.symbolName)
                            .foregroundStyle(category.color.prefixTint)
                    }
                    if !card.notes.isEmpty {
                        DisclosureGroup("Notes") {
                            Text(card.notes).foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    if let date = card.remindAt {
                        LabeledContent("Remind me", value: date.formatted(date: .abbreviated, time: .omitted))
                    }
                    if let date = card.deadline {
                        LabeledContent("Deadline", value: date.formatted(date: .abbreviated, time: .omitted))
                    }
                    Button {
                        editing = card
                    } label: {
                        Label("Edit task", systemImage: "pencil")
                    }
                } footer: {
                    Text("Edit to change its category, project, Notes or dates.")
                }

                Section {
                    destination(.today, explanation: "I am working on this")
                    destination(.tomorrow, explanation: "I intend to work on this next")
                    destination(.later, explanation: "This is for another time")
                    destination(.waiting, explanation: "I am waiting for someone or something")
                } header: {
                    Text("Move to")
                } footer: {
                    Text("Moving a task keeps its reminder and deadline.")
                }

                Section {
                    Button {
                        session?.keepInInbox(card.id)
                        persist()
                    } label: {
                        Label("Keep in Inbox", systemImage: "tray")
                    }
                    Button {
                        if let live = liveInboxCard(card.id) { store.complete(live) }
                    } label: {
                        Label("Complete", systemImage: "checkmark.circle")
                    }
                    Button(role: .destructive) {
                        deleting = card
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } footer: {
                    Text("Keep in Inbox leaves this task unchanged and continues to the next one.")
                }
            } else if session != nil {
                Section {
                    ContentUnavailableView(
                        inboxCount == 0 ? "Inbox is clear" : "Review finished",
                        systemImage: inboxCount == 0 ? "tray" : "checkmark.circle",
                        description: Text(inboxCount == 0
                            ? "New tasks will be here when you need them."
                            : "Tasks you kept in Inbox and any new arrivals are still there. Nothing moves unless you choose.")
                    )
                    if inboxCount > 0 {
                        Button("Review remaining Inbox") { start() }
                    }
                }
            }
        }
        .navigationTitle("Review Inbox")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            UndoBanner(bottomPadding: 16).environmentObject(store)
        }
        .onAppear {
            guard session == nil else { return }
            if let data = savedSession.data(using: .utf8),
               let restored = try? JSONDecoder().decode(InboxReviewSession.self, from: data) {
                session = restored
            } else {
                start()
            }
        }
        .sheet(item: $editing) { card in
            CardActionsSheet(itemID: card.id).environmentObject(store)
        }
        .alert("Delete task?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), presenting: deleting) { card in
            Button("Delete", role: .destructive) {
                if let live = liveInboxCard(card.id) { store.delete(live) }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { card in
            Text(card.title)
        }
    }

    private func liveInboxCard(_ id: UUID) -> TodoItem? {
        store.items.first { $0.id == id && $0.bucket == .inbox }
    }

    private func destination(_ bucket: Bucket, explanation: LocalizedStringKey) -> some View {
        Button {
            guard let id = remaining.first?.id, let card = liveInboxCard(id) else { return }
            store.move(card, to: bucket)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: bucket.symbolName).frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(bucket.title).font(.headline)
                    Text(explanation).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
    }

    private func start() {
        session = InboxReviewSession(cards: store.items(in: .inbox))
        persist()
    }

    private func persist() {
        guard let session, let data = try? JSONEncoder().encode(session),
              let text = String(data: data, encoding: .utf8) else { return }
        savedSession = text
    }
}
