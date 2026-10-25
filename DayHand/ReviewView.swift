import SwiftUI

/// What you finished in a week, grouped by the day you finished it.
///
/// The Completed stack already holds everything ever ticked off, newest first,
/// which answers "where did that task go" but not "what did I actually get
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
                        Text("\(total) tasks")
                            .monospacedDigit()
                    } label: {
                        Label("Finished", systemImage: "checkmark.circle")
                    }
                }
            }

            ForEach(days) { day in
                Section(Scheduler.relativeLabel(for: day.date)) {
                    ForEach(day.cards) { card in
                        FinishedCardRow(card: card).environmentObject(store)
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
                    description: Text("Tasks you tick off appear here, grouped by the day you finished them.")
                )
            }
        }
    }
}
