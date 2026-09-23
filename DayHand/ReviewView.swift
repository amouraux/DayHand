import SwiftUI

/// What you finished in a week, grouped by the day you finished it.
///
/// The Completed stack already holds everything ever ticked off, newest first,
/// which answers "where did that card go" but not "what did I actually get
/// done". This answers the second question, which is the one worth asking on a
/// Friday afternoon.
struct ReviewView: View {
    let week: ReviewWeek

    @EnvironmentObject private var store: TodoStore

    private var days: [Review.Day] {
        guard let interval = week.interval() else { return [] }
        return Review.days(completedIn: interval, cards: store.items)
    }

    var body: some View {
        let days = days
        let total = days.reduce(0) { $0 + $1.cards.count }

        List {
            if !days.isEmpty {
                Section {
                    LabeledContent {
                        Text("\(total) cards")
                            .monospacedDigit()
                    } label: {
                        Label("Finished", systemImage: "checkmark.circle")
                    }
                }
            }

            ForEach(days) { day in
                Section(Scheduler.relativeLabel(for: day.date)) {
                    ForEach(day.cards) { card in
                        row(card)
                    }
                }
            }
        }
        .navigationTitle(week.title)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if days.isEmpty {
                ContentUnavailableView(
                    "Nothing finished",
                    systemImage: "checkmark.circle",
                    description: Text("Cards you tick off appear here, grouped by the day you finished them.")
                )
            }
        }
    }

    /// Deliberately not a `CardRow`: this is a record of what happened, so it
    /// carries no swipes, no checkbox to untick and no stack colour.
    private func row(_ card: TodoItem) -> some View {
        let category = store.category(for: card)
        let project = store.project(for: card)

        return HStack(alignment: .firstTextBaseline, spacing: 10) {
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
