import SwiftUI

/// The short introduction: three pages, skippable at every step.
///
/// Shown once, on the first launch that finds no data (`TodoStore.isFirstRun`),
/// and again whenever the user asks, from More. On a first run the last page asks
/// what to start with; skipping, or dismissing it any other way, keeps the
/// examples, which is how the app opened before the introduction existed.
struct IntroView: View {
    /// On a first run the last page offers the choice. Replayed from More it
    /// only closes.
    var offersChoice: Bool
    /// `true` to keep the example tasks, `false` to start with an empty list.
    var onFinish: (_ keepExamples: Bool) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    private let lastPage = 2

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                // Present on every page so the layout does not jump, but only
                // offered while there is still something to skip.
                Button("Skip") { finish(keepExamples: true) }
                    .opacity(page < lastPage ? 1 : 0)
                    .disabled(page == lastPage)
            }
            .padding(.horizontal)
            .padding(.top, 12)

            TabView(selection: $page) {
                stacksPage.tag(0)
                movePage.tag(1)
                datesPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            actions
                .padding(.horizontal)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    // MARK: Pages

    private var stacksPage: some View {
        page(symbol: "square.stack.3d.up", title: "A place for every task") {
            VStack(alignment: .leading, spacing: 14) {
                stackRow(.inbox, "Capture first, decide later.")
                stackRow(.today, "What you are working on, for as long as it takes.")
                stackRow(.tomorrow, "What you will pick up next.")
                stackRow(.later, "Ideas and plans you are keeping.")
                stackRow(.waiting, "Needs a reply, a delivery or a decision first.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var movePage: some View {
        page(symbol: "arrow.left.arrow.right.circle", title: "You decide when a task moves") {
            Text("Nothing rolls over. A task stays where you put it until you move it, so an unfinished day is never a failure.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var datesPage: some View {
        page(symbol: "bell.badge", title: "Dates remind, they never move") {
            Text("A reminder brings a task back to you on the day you choose, with a coloured edge. A deadline is only a finish date. Neither moves the task.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func page<Content: View>(symbol: String, title: LocalizedStringKey,
                                     @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: symbol)
                    .font(.system(size: 54))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                content()
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 56)   // clear of the page dots
        }
    }

    private func stackRow(_ bucket: Bucket, _ line: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: bucket.symbolName)
                .font(.title2)
                .foregroundStyle(bucket.tint)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(bucket.title).font(.headline)
                Text(line).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Buttons

    @ViewBuilder private var actions: some View {
        if page < lastPage {
            Button {
                withAnimation { page += 1 }
            } label: {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        } else if offersChoice {
            VStack(spacing: 10) {
                Button {
                    finish(keepExamples: true)
                } label: {
                    Text("Look around with example tasks").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button {
                    finish(keepExamples: false)
                } label: {
                    Text("Start with an empty list").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
        } else {
            Button {
                finish(keepExamples: true)
            } label: {
                Text("Done").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private func finish(keepExamples: Bool) {
        onFinish(keepExamples)
        dismiss()
    }
}

/// Shown at the top of the list while any example task is untouched, so there
/// is always an obvious way to be rid of them. It goes by itself once they are.
struct ExamplesCard: View {
    @EnvironmentObject private var store: TodoStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("These are example tasks. Remove them whenever you like.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Remove examples") {
                withAnimation { store.removeExamples() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.08)))
        .accessibilityElement(children: .contain)
    }
}
