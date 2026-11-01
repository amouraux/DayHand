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
    @State private var showsTrial = false

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
                    UnlockButton()
                    if store.purchases.canStartTrial {
                        Button("Start 30-day trial") { showsTrial = true }
                            .disabled(store.purchases.isWorking)
                    }
                    Button("Restore Purchases") { Task { await store.purchases.restore() } }
                        .disabled(store.purchases.isWorking)
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
            .sheet(isPresented: $showsTrial) { TrialView().environmentObject(store) }
            .purchaseNotice()
            .task { await store.purchases.loadProducts() }
            // Buying, or starting the trial, is the answer: nothing left to offer.
            .onChange(of: store.purchases.storeAccess) { _, access in
                if access != .free { dismiss() }
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
        // Over the limit, which a trial or an import can leave someone, the
        // count is stated: "up to 3" alone does not tell them why they cannot
        // add one, or how far they are from being able to.
        let active = Entitlement.liveProjectCount(in: store.projects)
        let limit = Entitlement.freeProjectLimit
        switch reason {
        case .project(let name?):
            if active > limit {
                return "You have \(active) active projects; the free version keeps up to \(limit). Your task was added without the project \(name). To add one, archive or merge projects until you have fewer than \(limit), or unlock DayHand."
            }
            return "The free version keeps up to \(limit) active projects. Your task was added without the project \(name). Archive a project you have finished to make room, or unlock DayHand."
        case .project(nil):
            if active > limit {
                return "You have \(active) active projects; the free version keeps up to \(limit). To add one, archive or merge projects until you have fewer than \(limit), or unlock DayHand."
            }
            return "The free version keeps up to \(limit) active projects. Archive a project you have finished to make room, or unlock DayHand."
        case .history:
            return "The free version shows the last \(Entitlement.freeHistoryDays) days of finished tasks. Earlier ones are safe, and appear here once you unlock."
        }
    }
}

/// The unlock button, with the price the App Store gives for this Apple ID's
/// storefront. Without a price yet it still works: pressing it asks again and
/// says why if the App Store cannot be reached, rather than sitting greyed out.
struct UnlockButton: View {
    @EnvironmentObject private var store: TodoStore

    var body: some View {
        Button {
            Task { await store.purchases.purchase() }
        } label: {
            if let price = store.purchases.unlockPrice {
                Text("Unlock DayHand for \(price)")
            } else {
                Text("Unlock DayHand")
            }
        }
        .disabled(store.purchases.isWorking)
    }
}

/// States what the trial is before it starts: how long, what stops when it
/// ends, and what the unlock costs. It starts only from here, by choice.
struct TrialView: View {
    @EnvironmentObject private var store: TodoStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("30-day trial").font(.title3.weight(.semibold))
                        Text("Try everything for \(Entitlement.trialDays) days: unlimited active projects and your whole history of finished tasks. When the trial ends, DayHand goes back to the free version, which keeps up to \(Entitlement.freeProjectLimit) active projects and shows the last \(Entitlement.freeHistoryDays) days of finished tasks. Nothing is deleted, and nothing is charged.")
                            .foregroundStyle(.secondary)
                        if let price = store.purchases.unlockPrice {
                            Text("The one-time unlock is \(price). No subscription.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Button("Start 30-day trial") {
                        Task {
                            await store.purchases.startTrial()
                            if store.purchases.storeAccess.hasStartedTrial { dismiss() }
                        }
                    }
                    .disabled(store.purchases.isWorking)
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
            .purchaseNotice()
        }
    }
}

/// Settings' own place for the purchase: the trial and the unlock while the
/// version is free, a quiet line with the days left during the trial, and
/// Restore Purchases always, as the App Store requires. Nothing here nags.
struct PurchasesSection: View {
    @EnvironmentObject private var store: TodoStore
    @State private var showsTrial = false

    var body: some View {
        let access = store.purchases.storeAccess
        let entitlement = store.entitlement
        Section {
            switch access {
            case .unlocked:
                Label("DayHand is unlocked. Thank you.", systemImage: "checkmark.seal")
                    .foregroundStyle(.secondary)
            case .trial:
                if let days = entitlement.trialDaysLeft(now: Date()) {
                    LabeledContent("Trial days left") { Text("\(days)").monospacedDigit() }
                    UnlockButton()
                } else {
                    Text("Your trial has ended. Everything you made is still here.")
                        .foregroundStyle(.secondary)
                    UnlockButton()
                }
            case .free:
                if store.purchases.canStartTrial {
                    Button("Start 30-day trial") { showsTrial = true }
                }
                UnlockButton()
            }
            Button("Restore Purchases") { Task { await store.purchases.restore() } }
                .disabled(store.purchases.isWorking)
        } header: {
            Text("Purchases")
        }
        .sheet(isPresented: $showsTrial) { TrialView().environmentObject(store) }
        .purchaseNotice()
        .task { await store.purchases.loadProducts() }
    }
}

private struct PurchaseNotice: ViewModifier {
    @EnvironmentObject private var store: TodoStore

    func body(content: Content) -> some View {
        content.alert(
            "DayHand",
            isPresented: Binding(
                get: { store.purchases.notice != nil },
                set: { if !$0 { store.purchases.notice = nil } }
            ),
            actions: { Button("OK") { } },
            message: { Text(store.purchases.notice ?? "") }
        )
    }
}

extension View {
    /// One alert for whatever the last purchase action has to say.
    func purchaseNotice() -> some View { modifier(PurchaseNotice()) }
}
