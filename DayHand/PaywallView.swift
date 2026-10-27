import SwiftUI

/// Why the unlock is being offered, so the screen can say what just happened.
enum PaywallReason: Identifiable, Equatable {
    /// A project was asked for at the limit. `name` is set when a task was
    /// being saved with it, in which case the task was kept without it.
    case project(name: String?)
    /// Finished tasks older than the free window are collapsed.
    case history(earlier: Int)

    var id: String {
        switch self {
        case .project(let name): return "project-\(name ?? "")"
        case .history: return "history"
        }
    }
}

/// What the free version limits, and the way past it. Plain about both: what
/// is free, what is not, and that nothing the user has is lost either way.
struct PaywallView: View {
    let reason: PaywallReason

    @EnvironmentObject private var store: TodoStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(headline).font(.title3.weight(.semibold))
                        Text(explanation).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Label("Unlimited active projects", systemImage: "paperclip")
                    Label("Your whole history of finished tasks", systemImage: "checkmark.circle")
                } header: {
                    Text("Unlock DayHand")
                } footer: {
                    Text("Everything you have stays yours either way: your tasks, backups and exports always hold all of it.")
                }

                Section {
                    Button("Unlock DayHand") {
                        Task { await store.purchases.purchase() }
                    }
                    .disabled(store.purchases.testingAvailable)
                }

                if store.purchases.testingAvailable {
                    PaywallTestingSection()
                }
            }
            .navigationTitle("DayHand")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
    }

    private var headline: LocalizedStringKey {
        switch reason {
        case .project: return "Unlock more projects"
        case .history: return "Unlock your full history"
        }
    }

    private var explanation: LocalizedStringKey {
        switch reason {
        case .project(let name?):
            return "The free version keeps up to \(Entitlement.freeProjectLimit) active projects. Your task was added without the project \(name). Archive a project you have finished to make room, or unlock DayHand."
        case .project(nil):
            return "The free version keeps up to \(Entitlement.freeProjectLimit) active projects. Archive a project you have finished to make room, or unlock DayHand."
        case .history:
            return "The free version shows the last \(Entitlement.freeHistoryDays) days of finished tasks. Earlier ones are safe, and appear here once you unlock."
        }
    }
}

/// Temporary, for trying the free and the paid app on one device. Only shown
/// where `Purchases.testingAvailable`, which a customer's copy never is.
struct PaywallTestingSection: View {
    @EnvironmentObject private var store: TodoStore

    var body: some View {
        Section {
            Picker("Version", selection: Binding(
                get: { store.purchases.testingOverride },
                set: { store.purchases.setTestingOverride($0) }
            )) {
                Text("Automatic").tag(Purchases.TestingOverride?.none)
                Text("Free").tag(Purchases.TestingOverride?.some(.free))
                Text("Paid").tag(Purchases.TestingOverride?.some(.paid))
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Testing")
        } footer: {
            Text("Only in test builds. Free applies the project and history limits on this device; Paid removes them.")
        }
    }
}
