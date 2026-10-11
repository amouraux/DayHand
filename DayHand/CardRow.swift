import SwiftUI

extension CategoryColor {
    var tint: Color {
        switch self {
        case .indigo: return .indigo
        case .purple: return .purple
        case .teal:   return .teal
        case .pink:   return .pink
        case .brown:  return .brown
        case .yellow: return .yellow
        }
    }
}

extension CategoryColor {
    /// The colour of this category as text or an icon on a card: the project
    /// prefix and the category glyph.
    ///
    /// Light mode keeps the tint, except yellow, which on a pale card is close
    /// to invisible and is darkened to an ochre. Dark mode lightens every tint
    /// 40% towards white: the system colours are tuned for a black background,
    /// and on a stack-washed card the darker ones — indigo, which is Research,
    /// above all — fell to a contrast of 2:1, below the 3:1 minimum even for
    /// bold text. Lightened, the worst pairing is above 5:1.
    var prefixTint: Color {
        let base: UIColor
        switch self {
        case .indigo: base = .systemIndigo
        case .purple: base = .systemPurple
        case .teal:   base = .systemTeal
        case .pink:   base = .systemPink
        case .brown:  base = .systemBrown
        case .yellow: base = .systemYellow
        }
        let isYellow = self == .yellow
        return Color(UIColor { traits in
            let resolved = base.resolvedColor(with: traits)
            if traits.userInterfaceStyle == .dark {
                return resolved.mixed(withWhite: 0.40)
            }
            return isYellow ? UIColor(red: 0.60, green: 0.45, blue: 0.0, alpha: 1) : resolved
        })
    }
}

private extension UIColor {
    /// This colour moved a fraction of the way towards white.
    func mixed(withWhite fraction: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return self }
        return UIColor(
            red: r + (1 - r) * fraction,
            green: g + (1 - g) * fraction,
            blue: b + (1 - b) * fraction,
            alpha: a
        )
    }
}

extension CardCategory {
    var tint: Color { color.tint }
}

extension Bucket {
    /// How strongly the stack's colour washes over the card in light mode.
    ///
    /// Not one value for all four: the same wash separates a card from the grey
    /// page by very different amounts depending on the hue. At 26% the blue of
    /// TODAY stood clear while the orange of TOMORROW and the green of LATER
    /// were nearly invisible against the page — they are light colours to begin
    /// with. These strengths bring all four to the same separation.
    var lightWash: Double {
        switch self {
        case .inbox:     return 0.35
        case .today:     return 0.27
        case .tomorrow:  return 0.44
        case .later:     return 0.44
        // Fainter than the rest. A waiting card is not your move, and should
        // not shout as loudly as one that is.
        case .waiting:   return 0.26
        case .completed: return 0
        }
    }

    var tint: Color {
        switch self {
        case .inbox:     return .gray
        case .today:     return .blue
        case .tomorrow:  return .orange
        case .later:     return .green
        // Slate: muted on purpose, and the one cool neutral left once grey
        // went to Inbox.
        case .waiting:   return Color(red: 0.42, green: 0.49, blue: 0.60)
        // Completed cards carry no wash at all: the strikethrough, the filled
        // checkmark and the dimming already say "done", and every remaining
        // colour is spoken for by a live stack.
        case .completed: return .clear
        }
    }
}

/// A thing a swipe can do, and how it looks while you are dragging.
private struct SwipeAction {
    let color: Color
    let symbol: String
    let label: String
}

/// A sideways pan that can refuse a touch *before* it begins.
///
/// SwiftUI cannot. A `DragGesture` has already begun by the time `onChanged`
/// can look at its direction, and the scroll view has lost the touch by then —
/// which is why a drag that started on a card often did not scroll the list at
/// all. UIKit asks `gestureRecognizerShouldBegin` first, and a recogniser that
/// answers no leaves the scroll entirely alone.
///
/// The view itself takes no touches. It sits in the card's background with
/// interaction off, there only to hand the recogniser to the view SwiftUI put
/// the card in — a recogniser fires for the view that was hit and its
/// ancestors, so it has to live above the card's content rather than beside
/// it. That ancestor may hold every card in the list, so each one also checks
/// the touch is inside its own card before agreeing to begin.
struct HorizontalSwipe: UIViewRepresentable {
    var onChanged: (CGFloat) -> Void
    var onEnded: (CGFloat) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        context.coordinator.anchor = view
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        // Here rather than in `makeUIView`: the view has no superview yet when
        // it is made, and a lazy stack may move it to another one later.
        context.coordinator.attach()
    }

    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onChanged: (CGFloat) -> Void = { _ in }
        var onEnded: (CGFloat) -> Void = { _ in }
        weak var anchor: UIView?
        private weak var host: UIView?

        private lazy var pan: UIPanGestureRecognizer = {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handle))
            pan.delegate = self
            return pan
        }()

        /// The scroll view, not the immediate superview.
        ///
        /// A recogniser only fires for the view that was hit and its
        /// ancestors, and the view SwiftUI gives a background representable is
        /// not an ancestor of the card's own content — the recogniser went on
        /// it and never saw a touch, which showed up as the swipe doing
        /// nothing at all. The scroll view is an ancestor of everything in the
        /// list, so it is where this has to hang; the frame check in
        /// `shouldBegin` is what keeps each card answering only for itself.
        private func enclosingScrollView() -> UIView? {
            var candidate = anchor?.superview
            while let current = candidate {
                if current is UIScrollView { return current }
                candidate = current.superview
            }
            return anchor?.superview
        }

        func attach() {
            guard let target = enclosingScrollView() else {
                // Not in the hierarchy yet. `updateUIView` may not run again,
                // so come back rather than wait to be asked.
                DispatchQueue.main.async { [weak self] in self?.attach() }
                return
            }
            guard target !== host else { return }
            detach()
            target.addGestureRecognizer(pan)
            host = target
        }

        func detach() {
            host?.removeGestureRecognizer(pan)
            host = nil
        }

        @objc private func handle(_ pan: UIPanGestureRecognizer) {
            switch pan.state {
            case .changed: onChanged(pan.translation(in: pan.view).x)
            case .ended, .cancelled, .failed: onEnded(pan.translation(in: pan.view).x)
            default: break
            }
        }

        /// The whole point of going to UIKit for this.
        func gestureRecognizerShouldBegin(_ recogniser: UIGestureRecognizer) -> Bool {
            guard let pan = recogniser as? UIPanGestureRecognizer,
                  let anchor, let host, anchor.window != nil else { return false }

            // Answer only for touches on this card: the recogniser hangs off a
            // view that may well hold all of them.
            let touch = pan.location(in: host)
            guard anchor.convert(anchor.bounds, to: host).contains(touch) else { return false }

            // Sideways, or not at all. Saying no leaves the touch where it
            // was, which is the thing SwiftUI had no way to express.
            let speed = pan.velocity(in: host)
            return abs(speed.x) > abs(speed.y)
        }

        /// The card's own tap and the context menu's long press are SwiftUI's,
        /// and the scroll is the scroll view's. None of them need to lose.
        func gestureRecognizer(_ recogniser: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}


/// One todo rendered as a card.
///
/// - tap anywhere but the checkbox picks a stack, in one further tap
/// - the checkbox toggles completion
/// - swipe LEFT moves the card to TODAY, or to TOMORROW if it is in TODAY
/// - swipe RIGHT opens the editor for everything else
struct CardRow: View {
    let item: TodoItem
    /// Resolved from `item.categoryID` by the caller, which owns the store.
    let category: CardCategory?
    /// Resolved from `item.projectID` the same way.
    var project: Project? = nil
    let onTap: () -> Void
    let onToggle: () -> Void
    /// Move the card forward a stack.
    let onMove: () -> Void
    /// Open the full editor.
    let onEdit: () -> Void
    /// Narrow the list to this card's project (the Mac's right-click menu).
    var onShowProject: (() -> Void)? = nil
    /// Set while the list is filtered, so the same menu can offer the way back.
    var onShowAll: (() -> Void)? = nil

    /// How far the card must travel to commit.
    private static let commitDistance: CGFloat = 96
    /// How far it is allowed to travel at all, so the gesture feels bounded.
    private static let maxDrag: CGFloat = 140

    @Environment(\.colorScheme) private var colorScheme
    @State private var dragX: CGFloat = 0
    /// Set once a drag is judged horizontal, so vertical scrolling wins otherwise.
    @State private var didCommit = false

    /// How close the reminder is. The only thing a date does to a card is
    /// colour its edge and order it — it never moves it.
    private var urgency: Urgency {
        item.isCompleted ? .none : Urgency.of(item.remindAt)
    }
    private var progress: CGFloat { min(1, abs(dragX) / Self.commitDistance) }
    private var armed: Bool { abs(dragX) >= Self.commitDistance }

    /// A left swipe pulls a card forward into TODAY — or, for a card already in
    /// TODAY, pushes it on to TOMORROW. The panel wears the destination stack's
    /// own colour, so the gesture previews where the card is about to land.
    private var moveDestination: Bucket { item.bucket.forwardDestination }

    private var moveAction: SwipeAction {
        SwipeAction(
            color: moveDestination.tint,
            symbol: moveDestination.symbolName,
            label: moveDestination.title
        )
    }

    private var editAction: SwipeAction {
        SwipeAction(color: .indigo, symbol: "square.and.pencil", label: "Edit")
    }

    /// Which action the current drag direction is heading towards.
    /// Left = move the card on, right = open the editor.
    private var pendingAction: SwipeAction {
        dragX < 0 ? moveAction : editAction
    }

    var body: some View {
        ZStack {
            swipeBackdrop
            card
                .offset(x: dragX)
                // In the background, and taking no touches of its own: all
                // it does is give the pan recogniser to the view SwiftUI put
                // this card in. A SwiftUI DragGesture here claimed the touch
                // before its direction could be read, and a drag that began on
                // a card then did not scroll the list at all.
                .background(
                    HorizontalSwipe(onChanged: { dragTo($0) }, onEnded: { endDrag($0) })
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text("Move to \(moveDestination.title)"), onMove)
        .accessibilityAction(named: Text("Edit"), onEdit)
    }

    // MARK: - The card itself

    private var card: some View {
        // Centred, not top-aligned: on a card whose title runs to two lines the
        // checkbox and category icon belong beside the card, not beside its
        // first line. On a one-line card the two are the same.
        HStack(alignment: .center, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isCompleted ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isCompleted ? "Mark as not done" : "Mark as done")


            // Baseline-aligned so the icon sits on the title's line rather than
            // being centred against it. The slot is occupied even with no
            // category, or the titles of uncategorised cards would not line up.
            HStack(alignment: .center, spacing: 10) {
                categoryGlyph(category)
                    .frame(width: 20, alignment: .center)

                VStack(alignment: .leading, spacing: 6) {
                    titleText
                        .font(.body)
                        .foregroundStyle(item.isCompleted ? Color.secondary : Color.primary)
                        .strikethrough(item.isCompleted, color: .secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if item.remindAt != nil || item.deadline != nil {
                        // Start then finish, in that order and in that visual
                        // weight: a plain flag for the day to pick the card
                        // up, a chequered one for the day it has to be done.
                        // The second is the far end of a job and says so by
                        // staying grey while the first carries the colour.
                        HStack(spacing: 10) {
                            if let at = item.remindAt {
                                Label(Scheduler.relativeLabel(for: at), systemImage: "flag")
                                    .foregroundStyle(urgency.tint ?? Color.secondary)
                            }
                            if let deadline = item.deadline {
                                Label(Scheduler.relativeLabel(for: deadline),
                                      systemImage: "flag.checkered")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    } else if item.isCompleted, let origin = item.bucketBeforeCompletion {
                        // "was in", not "from": "from Today" read naturally and
                        // "from Now" does not.
                        Label("was in \(origin.title)", systemImage: origin.symbolName)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(stackBackground)
        // The reminder's whole voice before it fires: orange while it is
        // coming, red once it is here or past. Thicker than a hairline so it
        // reads as a state of the card rather than an edge that happens to be
        // coloured.
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(urgency.tint?.opacity(urgency == .approaching ? 0.55 : 0.8)
                              ?? Color.clear,
                              lineWidth: urgency == .none ? 0 : 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(perform: onTap)
        #if targetEnvironment(macCatalyst)
        // The Mac's right-click menu mirrors what a click already offers. Edit
        // is in both deliberately: this menu also filters, and a context menu
        // that will narrow the list by a card but not open it reads as broken.
        // Finder puts Open in both places for the same reason.
        .contextMenu {
            Button { onEdit() } label: { Label("Edit…", systemImage: "square.and.pencil") }
            // While any filter is on, the useful move is back out of it, so
            // "Show All" replaces "Show Only" — on every card, not only those
            // with a project, since a category filter shows cards without one.
            if let onShowAll {
                Button { onShowAll() } label: {
                    Label("Show All", systemImage: "line.3.horizontal.decrease.circle.fill")
                }
            } else if let project, let onShowProject {
                Button { onShowProject() } label: {
                    Label("Show Only \(project.name)", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
        #endif
        .opacity(item.isCompleted ? 0.65 : 1)
    }

    /// The title, led by the project in its category's colour: "TRIP book flights".
    /// One run of text rather than a badge beside it, so a long title wraps
    /// naturally and the card is no taller than before.
    private var titleText: Text {
        let title = Text(item.title)
        guard let project else { return title }
        let colour = category?.color.prefixTint ?? Color.primary
        return Text(project.name).fontWeight(.semibold).foregroundStyle(colour)
            + Text(" ")
            + title
    }

    /// One flat colour per card, taken from its stack. Kept low-opacity over the
    /// system card colour so the text stays readable in light and dark mode.
    /// Fainter in dark mode, where the same wash lifts the card towards the
    /// brightness of the coloured project prefixes and category icons on it.
    private var stackBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(item.bucket.tint.opacity(colorScheme == .dark ? 0.16 : item.bucket.lightWash))
            }
    }

    /// The category shows as its coloured icon alone. Its label is for
    /// Settings, the editor and VoiceOver — never for the card face.
    ///
    /// Drawn as `Text(Image:)` rather than a plain `Image` so the symbol is laid
    /// out as a glyph and shares the title's baseline exactly; an `Image` is
    /// aligned by its own box and sits visibly high.
    private func categoryChip(_ category: CardCategory) -> some View {
        Text(Image(systemName: category.symbolName))
            .font(.body)
            .foregroundStyle(category.color.prefixTint)
            .accessibilityLabel(category.label)
    }

    /// The leading slot used on the Mac: the glyph, or nothing but the space.
    @ViewBuilder
    private func categoryGlyph(_ category: CardCategory?) -> some View {
        if let category {
            categoryChip(category)
        } else {
            Text(" ").font(.body).accessibilityHidden(true)
        }
    }

    // MARK: - What the swipe reveals

    private var swipeBackdrop: some View {
        let action = pendingAction

        return RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(action.color.opacity(armed ? 1 : 0.35 + 0.5 * progress))
            .overlay(alignment: dragX < 0 ? .trailing : .leading) {
                Label(action.label, systemImage: action.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .scaleEffect(armed ? 1 : 0.85)
                    .opacity(Double(progress))
            }
            .opacity(dragX == 0 ? 0 : 1)
            .animation(.easeOut(duration: 0.15), value: armed)
    }

    // MARK: - Gesture

    /// The card follows the finger, resisting past the commit point and
    /// capped so it cannot be dragged off the screen.
    private func dragTo(_ raw: CGFloat) {
        let travel = abs(raw)
        let eased = travel <= Self.commitDistance
            ? travel
            : Self.commitDistance + (travel - Self.commitDistance) * 0.25

        let wasArmed = armed
        dragX = min(eased, Self.maxDrag) * (raw < 0 ? -1 : 1)
        if armed && !wasArmed { hapticTick() }
    }

    private func endDrag(_ raw: CGFloat) {
        let commit = armed
        let goingLeft = dragX < 0

        if commit, !didCommit {
            didCommit = true
            withAnimation(.easeOut(duration: 0.18)) { dragX = 0 }
            goingLeft ? onMove() : onEdit()
            // The card re-sorts or changes stack; allow the next swipe.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { didCommit = false }
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dragX = 0 }
        }
    }

    private func hapticTick() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}

struct SectionHeader: View {
    let bucket: Bucket
    let count: Int

    /// The stack's own colour, except COMPLETED, whose tint is clear — cards
    /// there carry no wash — and which would otherwise draw no icon at all.
    private var tint: Color {
        bucket == .completed ? Color.secondary : bucket.tint
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            // Centred on the title rather than sat on its baseline: the symbol
            // is much smaller than this display-sized text, and a shared
            // baseline left it looking dropped. Kept smaller so the name still
            // leads.
            Image(systemName: bucket.symbolName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
                .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 9 }

            Text(bucket.title)
                .font(.largeTitle.bold())
                .foregroundStyle(Color.primary)
            Text("\(count)")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.top, 18)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGroupedBackground))
    }
}
