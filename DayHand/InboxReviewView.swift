import SwiftUI

/// One Inbox task at a time, and where it should go.
///
/// The layout is the point. The task and its details take whatever room is left
/// at the top; **the decision is pinned to the bottom**, where a thumb already
/// is. A form-style list put the four moves below the task's details, so every
/// task meant scrolling to reach the only thing the screen is for — and the
/// scroll position then survived the decision, opening the next task with its
/// title out of sight above the buttons being pressed for it. With the actions
/// fixed in place there is nothing to scroll to and nothing to get lost: each
/// task is a glance and a tap.
struct InboxReviewView: View {
    @EnvironmentObject private var store: TodoStore
    // Device-local UI state: this must never compete with task edits in sync.
    @AppStorage("inboxReviewSession.v1") private var savedSession = ""
    @State private var session: InboxReviewSession?
    @State private var editing: TodoItem?
    @State private var deleting: TodoItem?

    private var remaining: [TodoItem] { session?.remaining(in: store.items) ?? [] }
    private var inboxCount: Int { store.items.filter { $0.bucket == .inbox }.count }

    /// Wide enough to read, not so wide that a Mac window stretches a handful
    /// of buttons across the whole screen.
    private static let readableWidth: CGFloat = 600

    var body: some View {
        // A real background under everything, and not only as a colour: until
        // the saved pass is read the content below is empty, and `onAppear` on
        // an empty view never fires — so with nothing here to appear, the pass
        // would never start and the screen would stay blank for good.
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            if let card = remaining.first {
                review(card)
            } else if session != nil {
                finished
            }
        }
        .navigationTitle("Review Inbox")
        .navigationBarTitleDisplayMode(.inline)
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

    // MARK: - The task, and what to do with it

    private func review(_ card: TodoItem) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                details(card)
                    .frame(maxWidth: Self.readableWidth, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
            }
            // Only the details scroll, and only when Notes run long. They start
            // again from the top for each task.
            .id(card.id)

            // Above the actions rather than over them: it appears and goes, and
            // a control that jumps under a thumb is worse than a list that
            // gives up a few lines while the banner is up.
            UndoBanner(bottomPadding: 8).environmentObject(store)

            actions(card)
        }
    }

    private func details(_ card: TodoItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(remaining.count) left in this review")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(card.title)
                .font(.title2.weight(.semibold))
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

            let project = store.project(for: card)
            let category = store.category(for: card)
            if project != nil || category != nil {
                HStack(spacing: 16) {
                    if let project {
                        // The paperclip is what means a project everywhere
                        // else in the app; the folder means a group.
                        Label(project.name, systemImage: "paperclip")
                    }
                    if let category {
                        Label(category.label, systemImage: category.symbolName)
                            .foregroundStyle(category.color.prefixTint)
                    }
                }
                .font(.subheadline)
            }

            if card.remindAt != nil || card.deadline != nil {
                HStack(spacing: 16) {
                    if let date = card.remindAt { dated("Remind me", date) }
                    if let date = card.deadline { dated("Deadline", date) }
                }
                .font(.subheadline)
            }

            // Shown, not folded away: Notes are often what decides it, and the
            // decision is the whole purpose of being here.
            if !card.notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(card.notes)
                        .textSelection(.enabled)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Text("All Inbox tasks, including those outside your current filters.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
    }

    private func dated(_ label: LocalizedStringKey, _ date: Date) -> some View {
        HStack(spacing: 6) {
            Text(label).foregroundStyle(.secondary)
            Text(date.formatted(date: .abbreviated, time: .omitted))
        }
    }

    // MARK: - Pinned to the bottom

    private func actions(_ card: TodoItem) -> some View {
        VStack(spacing: 10) {
            Text("Where does this task belong?")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                destination(.today, explanation: "I am working on this")
                destination(.tomorrow, explanation: "I intend to work on this next")
                destination(.later, explanation: "This is for another time")
                destination(.waiting, explanation: "I am waiting for someone or something")
            }

            HStack(spacing: 8) {
                secondary("Edit task", symbol: "pencil") { editing = card }
                secondary("Keep in Inbox", symbol: "tray") {
                    session?.keepInInbox(card.id)
                    persist()
                }
                secondary("Complete", symbol: "checkmark.circle") {
                    if let live = liveInboxCard(card.id) { store.complete(live) }
                }
                secondary("Delete", symbol: "trash", role: .destructive) { deleting = card }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: Self.readableWidth)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    /// One of the four stacks, as a button big enough to hit without looking.
    /// "Moving" is the normal move: dates stay, and an outstanding reminder is
    /// answered.
    private func destination(_ bucket: Bucket, explanation: LocalizedStringKey) -> some View {
        Button {
            guard let id = remaining.first?.id, let card = liveInboxCard(id) else { return }
            store.move(card, to: bucket)
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: bucket.symbolName)
                    Text(bucket.title).font(.headline)
                }
                Text(explanation)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
        }
        .buttonStyle(.bordered)
        .tint(bucket.tint)
    }

    private func secondary(_ title: LocalizedStringKey, symbol: String, role: ButtonRole? = nil,
                           action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            VStack(spacing: 3) {
                // A fixed height, because the symbols differ and would
                // otherwise put each label at a slightly different level.
                Image(systemName: symbol).frame(height: 20)
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    // MARK: - Nothing left to decide

    private var finished: some View {
        VStack(spacing: 0) {
            // The button belongs to the message, so it is the message's own
            // action. Beside it in a stack, the message takes all the room there
            // is and leaves the button stranded at the bottom edge.
            ContentUnavailableView {
                Label(inboxCount == 0 ? "Inbox is clear" : "Review finished",
                      systemImage: inboxCount == 0 ? "tray" : "checkmark.circle")
            } description: {
                Text(inboxCount == 0
                    ? "New tasks will be here when you need them."
                    : "Tasks you kept in Inbox and any new arrivals are still there. Nothing moves unless you choose.")
            } actions: {
                if inboxCount > 0 {
                    Button("Review remaining Inbox") { start() }
                        .buttonStyle(.borderedProminent)
                }
            }
            UndoBanner(bottomPadding: 16).environmentObject(store)
        }
    }

    // MARK: - Session

    private func liveInboxCard(_ id: UUID) -> TodoItem? {
        store.items.first { $0.id == id && $0.bucket == .inbox }
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
