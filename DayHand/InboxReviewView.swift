import SwiftUI

/// The four review helpers: which stack each walks through, and the words that
/// differ between them. Next and Later share one pass, since they answer the
/// same question — when do I want to work on this.
enum ReviewStack: String, Identifiable {
    case inbox, now, waiting, nextLater, all
    var id: String { rawValue }
    static func forBucket(_ bucket: Bucket) -> ReviewStack? {
        switch bucket {
        case .inbox: return .inbox
        case .today: return .now
        case .waiting: return .waiting
        case .tomorrow, .later: return .nextLater
        case .completed: return nil
        }
    }
    var bucket: Bucket {
        switch self {
        case .inbox: return .inbox
        case .now: return .today
        case .waiting: return .waiting
        case .nextLater: return .tomorrow
        case .all: return .inbox
        }
    }
    var buckets: [Bucket] {
        if self == .all { return StackReviewSession.allOpenBuckets }
        return self == .nextLater ? [.tomorrow, .later] : [bucket]
    }
    var title: String {
        switch self {
        case .inbox: return String(localized: "Review Inbox")
        case .now: return String(localized: "Review Now")
        case .waiting: return String(localized: "Review Waiting")
        case .nextLater: return String(localized: "Review Next and Later")
        case .all: return String(localized: "Review all tasks")
        }
    }
    var question: LocalizedStringKey {
        switch self {
        case .inbox: return "Where does this task belong?"
        case .now: return "Am I still actively working on this?"
        case .waiting: return "Am I still waiting, or can this move forward?"
        case .nextLater: return "Is this still relevant, and when do I want to work on it?"
        case .all: return "Where does this task belong?"
        }
    }
    var scopeNote: LocalizedStringKey {
        switch self {
        case .inbox: return "All Inbox tasks, including those outside your current filters."
        case .now: return "All Now tasks, including those outside your current filters."
        case .waiting: return "All Waiting tasks, including those outside your current filters."
        case .nextLater: return "All Next and Later tasks, including those outside your current filters."
        case .all: return "All open tasks, including those outside your current filters."
        }
    }
    var emptyTitle: LocalizedStringKey {
        switch self {
        case .inbox: return "Inbox is clear"
        case .now: return "Nothing in Now"
        case .waiting: return "Nothing in Waiting"
        case .nextLater: return "Nothing in Next or Later"
        case .all: return "No open tasks"
        }
    }
    var restartTitle: LocalizedStringKey {
        switch self {
        case .inbox: return "Review remaining Inbox"
        case .now: return "Review Now again"
        case .waiting: return "Review Waiting again"
        case .nextLater: return "Review Next and Later again"
        case .all: return "Start a new full review"
        }
    }
}

struct InboxReviewView: View {
    var body: some View { StackReviewView(stack: .inbox) }
}

struct NowReviewView: View {
    var body: some View { StackReviewView(stack: .now) }
}

/// One task at a time from a stack, and where it should go.
///
/// The layout is the point. The task and its details take whatever room is left
/// at the top; **the decision is pinned to the bottom**, where a thumb already
/// is. A form-style list put the four moves below the task's details, so every
/// task meant scrolling to reach the only thing the screen is for — and the
/// scroll position then survived the decision, opening the next task with its
/// title out of sight above the buttons being pressed for it. With the actions
/// fixed in place there is nothing to scroll to and nothing to get lost: each
/// task is a glance and a tap.
///
/// The four stacks are always in the same places (Now, Next, Later, Waiting) so
/// a thumb learns them once; the one the task is already in becomes "keep".
struct StackReviewView: View {
    let stack: ReviewStack

    init(stack: ReviewStack) {
        self.stack = stack
        // Preserve the existing keys and keep each helper's progress independent.
        _savedSession = AppStorage(wrappedValue: "", "\(stack.rawValue)ReviewSession.v1")
    }

    @EnvironmentObject private var store: TodoStore
    // Device-local UI state: this must never compete with task edits in sync.
    @AppStorage private var savedSession: String
    @State private var session: StackReviewSession?
    @State private var editing: TodoItem?
    @State private var deleting: TodoItem?

    private var remaining: [TodoItem] { session?.remaining(in: store.items, buckets: stack.buckets) ?? [] }
    private var stackCount: Int { store.items.filter { stack.buckets.contains($0.bucket) }.count }

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
        .navigationTitle(stack.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard session == nil else { return }
            if let data = savedSession.data(using: .utf8),
               let restored = try? JSONDecoder().decode(StackReviewSession.self, from: data) {
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
                if let live = liveCard(card.id) { store.delete(live) }
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
        let stage = stack == .all ? ReviewStack.forBucket(card.bucket) ?? .inbox : stack
        return VStack(alignment: .leading, spacing: 12) {
            Text("\(remaining.count) left in this review")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if stack == .all {
                Label(stageHeading(card.bucket), systemImage: card.bucket.symbolName)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
            } else if stack == .nextLater {
                Text(card.bucket == .tomorrow ? "Reviewing Next · then Later" : "Reviewing Later")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
            }

            Text(card.title)
                .font(.title2.weight(.semibold))
                .textSelection(.enabled)

            SwiftUI.TimelineView(.periodic(from: .now, by: 60)) { context in
                if let days = StackReviewSession.daysInStack(since: card.enteredStackAt, now: context.date) {
                    Group {
                        if stage == .nextLater {
                            if card.bucket == .tomorrow {
                                if days == 0 { Text("Entered Next today") }
                                else if days == 1 { Text("In Next for 1 day") }
                                else { Text("In Next for \(days) days") }
                            } else {
                                if days == 0 { Text("Entered Later today") }
                                else if days == 1 { Text("In Later for 1 day") }
                                else { Text("In Later for \(days) days") }
                            }
                        } else if stage == .waiting {
                            if days == 0 { Text("Waiting since today") }
                            else if days == 1 { Text("Waiting for 1 day") }
                            else { Text("Waiting for \(days) days") }
                        } else if days == 0 {
                            Text(stage == .inbox ? "Entered Inbox today" : "Entered Now today")
                        } else if days == 1 {
                            Text(stage == .inbox ? "In Inbox for 1 day" : "In Now for 1 day")
                        } else {
                            if stage == .inbox { Text("In Inbox for \(days) days") }
                            else { Text("In Now for \(days) days") }
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

            Text(stack.scopeNote)
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
    }

    private func stageHeading(_ bucket: Bucket) -> LocalizedStringKey {
        switch bucket {
        case .inbox: return "Reviewing Inbox · 1 of 5"
        case .today: return "Reviewing Now · 2 of 5"
        case .waiting: return "Reviewing Waiting · 3 of 5"
        case .tomorrow: return "Reviewing Next · 4 of 5"
        case .later: return "Reviewing Later · 5 of 5"
        case .completed: return "Review finished"
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
        let stage = stack == .all ? ReviewStack.forBucket(card.bucket) ?? .inbox : stack
        return VStack(spacing: 10) {
            Text(stage.question)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                if stage == .inbox {
                    destination(.today, explanation: "I am working on this")
                    destination(.tomorrow, explanation: "I intend to work on this next")
                    destination(.later, explanation: "This is for another time")
                    destination(.waiting, explanation: "I am waiting for someone or something")
                } else if stage == .nextLater {
                    destination(.today, explanation: "I am ready to work on this")
                    destination(.tomorrow, explanation: card.bucket == .tomorrow
                        ? "This is still next" : "I want to tackle this next")
                    destination(.later, explanation: card.bucket == .later
                        ? "This is still for another time" : "This can stay for another time")
                    destination(.waiting, explanation: "I am blocked or waiting")
                } else if stage == .waiting {
                    destination(.today, explanation: "I can work on this now")
                    destination(.tomorrow, explanation: "It is ready; I will tackle it next")
                    destination(.later, explanation: "I am putting this aside")
                    destination(.waiting, explanation: "I am waiting for someone or something")
                } else {
                    destination(.today, explanation: "Yes, still working on it")
                    destination(.tomorrow, explanation: "Not now, but it is next")
                    destination(.later, explanation: "I am putting this aside")
                    destination(.waiting, explanation: "I am blocked or waiting")
                }
            }

            HStack(spacing: 8) {
                secondary(stage == .waiting ? "Edit / set reminder" : "Edit task", symbol: "pencil") { editing = card }
                if stage == .inbox {
                    secondary("Keep in Inbox", symbol: "tray") { keep(card) }
                }
                secondary("Complete", symbol: "checkmark.circle") {
                    if let live = liveCard(card.id) { store.complete(live) }
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
            guard let id = remaining.first?.id, let card = liveCard(id) else { return }
            if bucket == card.bucket {
                // Keeping a task is a decision, not a move: no date or reminder changes.
                keep(card)
            } else {
                store.move(card, to: bucket)
            }
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: bucket.symbolName)
                    Text(destinationTitle(bucket)).font(.headline)
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

    private func destinationTitle(_ bucket: Bucket) -> String {
        guard bucket == remaining.first?.bucket else { return bucket.title }
        switch bucket {
        case .today: return String(localized: "Keep in Now")
        case .waiting: return String(localized: "Still waiting")
        case .tomorrow: return String(localized: "Keep in Next")
        case .later: return String(localized: "Keep in Later")
        default: return bucket.title
        }
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
                Label(stackCount == 0 ? stack.emptyTitle : "Review finished",
                      systemImage: stackCount == 0 ? stack.bucket.symbolName : "checkmark.circle")
            } description: {
                if stack == .all {
                    Text(stackCount == 0
                        ? "There are no open tasks to review."
                        : "Your full review is finished. Tasks you kept remain in their stacks. New arrivals can be reviewed in the next pass.")
                } else if stack == .inbox {
                    Text(stackCount == 0
                        ? "New tasks will be here when you need them."
                        : "Tasks you kept in Inbox and any new arrivals are still there. Nothing moves unless you choose.")
                } else if stack == .nextLater {
                    Text(stackCount == 0
                        ? "Tasks you plan for another time will appear here."
                        : "Your choices are saved. Kept tasks and new arrivals can be reviewed in a new pass.")
                } else if stack == .waiting {
                    Text(stackCount == 0
                        ? "Tasks waiting on someone or something will appear here."
                        : "Tasks you are still waiting on remain in Waiting. New arrivals will be included in your next review.")
                } else {
                    Text(stackCount == 0
                        ? "Tasks you choose to work on will appear here."
                        : "Tasks you are still working on remain in Now. New arrivals will be included in your next review.")
                }
            } actions: {
                if stackCount > 0 {
                    Button(stack.restartTitle) { start() }
                        .buttonStyle(.borderedProminent)
                }
            }
            UndoBanner(bottomPadding: 16).environmentObject(store)
        }
    }

    // MARK: - Session

    private func liveCard(_ id: UUID) -> TodoItem? {
        store.items.first { $0.id == id && stack.buckets.contains($0.bucket) }
    }

    private func keep(_ card: TodoItem) {
        session?.keepInStack(card.id)
        persist()
    }

    private func start() {
        if stack == .nextLater || stack == .all {
            session = StackReviewSession(cards: stack.buckets.flatMap { store.items(in: $0) }, buckets: stack.buckets)
        } else {
            session = StackReviewSession(cards: store.items(in: stack.bucket), bucket: stack.bucket)
        }
        persist()
    }

    private func persist() {
        guard let session, let data = try? JSONEncoder().encode(session),
              let text = String(data: data, encoding: .utf8) else { return }
        savedSession = text
    }
}
