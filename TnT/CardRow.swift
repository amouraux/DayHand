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
        case .completed: return 0
        }
    }

    var tint: Color {
        switch self {
        case .inbox:     return .gray
        case .today:     return .blue
        case .tomorrow:  return .orange
        case .later:     return .green
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
    @State private var isHorizontal = false
    @State private var didCommit = false

    private var overdue: Bool { Scheduler.isOverdue(item) }
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
                // Simultaneous, not exclusive. A plain `.gesture` inside a
                // ScrollView claims the touch as soon as it passes
                // `minimumDistance`, and the direction check below runs only
                // once that has already happened — too late to give the touch
                // back. The result is a drag that neither swipes nor scrolls,
                // which is most of them, because a thumb arcs sideways as it
                // travels down. Recognising alongside the scroll view leaves
                // scrolling untouched and lets the latch below decide only
                // whether the *card* moves.
                .simultaneousGesture(swipe)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text("Move to \(moveDestination.title)"), onMove)
        .accessibilityAction(named: Text("Edit"), onEdit)
    }

    // MARK: - The card itself

    private var card: some View {
        HStack(alignment: .top, spacing: 12) {
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
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                categoryGlyph(category)
                    .frame(width: 20, alignment: .center)

                VStack(alignment: .leading, spacing: 6) {
                    titleText
                        .font(.body)
                        .foregroundStyle(item.isCompleted ? Color.secondary : Color.primary)
                        .strikethrough(item.isCompleted, color: .secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let due = item.dueDate {
                        Label(Scheduler.relativeLabel(for: due), systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(overdue ? Color.red : Color.secondary)
                    } else if item.isCompleted, let origin = item.bucketBeforeCompletion {
                        Label("from \(origin.title)", systemImage: origin.symbolName)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "ellipsis")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(stackBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(overdue ? Color.red.opacity(0.35) : Color.clear)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(perform: onTap)
        #if targetEnvironment(macCatalyst)
        // Dragging a card sideways is unnatural with a mouse, so the Mac gets
        // the editor on a right-click instead. The swipe still works.
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

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                // Let the ScrollView have any drag that is mostly vertical.
                if !isHorizontal {
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    isHorizontal = true
                }

                // Resist past the commit point, and cap the travel, in both
                // directions.
                let raw = value.translation.width
                let distance = abs(raw)
                let eased = distance <= Self.commitDistance
                    ? distance
                    : Self.commitDistance + (distance - Self.commitDistance) * 0.25

                let wasArmed = armed
                dragX = min(eased, Self.maxDrag) * (raw < 0 ? -1 : 1)
                if armed && !wasArmed { hapticTick() }
            }
            .onEnded { _ in
                let commit = isHorizontal && armed
                let goingLeft = dragX < 0
                isHorizontal = false

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
            // Drawn as a glyph rather than an Image so it sits on the title's
            // baseline; an Image aligns by its own box and rides high. Smaller
            // than the title, which is display-sized and would make the symbol
            // the loudest thing on screen.
            Text(Image(systemName: bucket.symbolName))
                .font(.title2.weight(.semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)

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

/// Says what the app did on its own: cards that were sitting in LATER whose
/// date came round have been filed into TODAY or TOMORROW.
///
/// It is a banner rather than an alert because the move is already done and
/// correct — there is nothing to decide, only something to notice. It clears
/// itself after a few seconds so it cannot sit on top of the Today button, and
/// a tap dismisses it at once.
struct AutoFileBanner: View {
    let notice: AutoFileNotice
    let onDismiss: () -> Void

    private static let lifetime: Duration = .seconds(6)

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.title3)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 3) {
                Text("Their date arrived")
                    .font(.subheadline.weight(.semibold))
                Text(notice.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)

            Image(systemName: "xmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture(perform: onDismiss)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Their date arrived. " + notice.message)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Dismiss")
        // Keyed on the notice, so a second one restarts the clock rather than
        // inheriting what is left of the first one's.
        .task(id: notice.id) {
            try? await Task.sleep(for: Self.lifetime)
            guard !Task.isCancelled else { return }
            onDismiss()
        }
    }
}
