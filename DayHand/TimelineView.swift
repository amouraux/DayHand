import SwiftUI

/// The whole record of finished work, newest first.
///
/// Months are sections, days are headings inside them, and each day carries
/// a bar scaled to the busiest day anywhere in the list.
///
/// It takes its cards rather than reaching for the store's, so the caller
/// decides the scope and there is no second idea of what "this project" means.
struct TimelineView: View {
    let title: String
    let cards: [TodoItem]

    @EnvironmentObject private var store: TodoStore
    @State private var paywall: PaywallReason?

    var body: some View {
        // The free version shows the last 30 days; what is held back is counted
        // and offered at the end, never silently left out.
        let split = store.entitlement.splitHistory(cards, now: Date())
        let months = Timeline.months(of: split.shown)
        let busiest = Timeline.busiestDay(in: months)
        let total = months.reduce(0) { $0 + $1.completedCount }

        List {
            if !months.isEmpty {
                Section {
                    LabeledContent {
                        Text("\(total) tasks").monospacedDigit()
                    } label: {
                        Label("Finished", systemImage: "checkmark.circle")
                    }
                }
            }

            ForEach(months) { month in
                Section {
                    ForEach(month.days) { day in
                        dayHeading(day, busiest: busiest)
                        ForEach(day.cards) { card in
                            FinishedCardRow(card: card).environmentObject(store)
                        }
                    }
                } header: {
                    LabeledContent {
                        Text("\(month.completedCount)").monospacedDigit()
                    } label: {
                        Text(month.start, format: .dateTime.month(.wide).year())
                    }
                }
            }

            if split.earlier > 0 {
                Section {
                    Button {
                        paywall = .history(earlier: split.earlier)
                    } label: {
                        Label(String(localized: "\(split.earlier) earlier tasks · Unlock"), systemImage: "lock")
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $paywall) { PaywallView(reason: $0).environmentObject(store) }
        .overlay {
            if months.isEmpty && split.earlier == 0 {
                ContentUnavailableView(
                    "Nothing finished yet",
                    systemImage: "calendar",
                    description: Text("Tasks you tick off appear here, newest first, under the month and day you finished them.")
                )
            }
        }
    }

    /// The day's own row: a bar, the date, and how many landed that day.
    ///
    /// The bar is scaled against the busiest day in the whole timeline rather
    /// than the busiest in its month, so a quiet month looks quiet instead of
    /// looking exactly like a frantic one.
    private func dayHeading(_ day: Review.Day, busiest: Int) -> some View {
        HStack(spacing: 10) {
            bar(day.cards.count, of: busiest)
            Text(Scheduler.relativeLabel(for: day.date))
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 4)
            Text("\(day.cards.count)")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .listRowBackground(Color.secondary.opacity(0.07))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(Scheduler.relativeLabel(for: day.date)))
        .accessibilityValue(Text("\(day.cards.count) tasks"))
    }

    private func bar(_ count: Int, of busiest: Int) -> some View {
        // A track rather than a bare bar, so the days line up against a common
        // edge and the eye can read the run down the margin.
        let fraction = busiest > 0 ? Double(count) / Double(busiest) : 0
        return ZStack(alignment: .leading) {
            Capsule().fill(Color.secondary.opacity(0.15))
            // Never narrower than the capsule is tall: a single task on a quiet
            // day must still read as a mark, not as an empty track.
            Capsule().fill(Color.accentColor.opacity(0.75))
                .frame(width: max(6, 36 * fraction))
        }
        .frame(width: 36, height: 6)
    }
}

/// One finished task, as a record of what happened.
///
/// Deliberately not a `CardRow`: no swipes, no checkbox to untick, no stack
/// colour. Shared by the weekly review and the timeline so the two cannot
/// drift into showing the same thing differently.
struct FinishedCardRow: View {
    let card: TodoItem

    @EnvironmentObject private var store: TodoStore

    var body: some View {
        let category = store.category(for: card)
        let project = store.project(for: card)

        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(Image(systemName: category?.symbolName ?? "circle.dotted"))
                .font(.footnote)
                .foregroundStyle(category?.color.prefixTint ?? Color.secondary)
                .frame(width: 18, alignment: .center)

            Group {
                if let project {
                    Text(project.name)
                        .fontWeight(.semibold)
                        .foregroundStyle(category?.color.prefixTint ?? Color.primary)
                        + Text(" ") + Text(card.title)
                } else {
                    Text(card.title)
                }
            }
            .font(.body)
            .foregroundStyle(Color.primary)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
