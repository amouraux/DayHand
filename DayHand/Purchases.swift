import Foundation
import StoreKit

/// Where this device's `Entitlement` comes from.
///
/// Device-local on purpose: it is never written to the document, because a
/// synced file would hand one person's purchase to someone else.
///
/// **Not yet wired to the App Store.** `storeAccess` stays unlocked until the
/// purchase and the 30-day trial are built, so nothing is limited for anyone
/// but a build that has switched to the free version on purpose (see
/// `TestingOverride`).
@MainActor
final class Purchases: ObservableObject {
    /// What the App Store says this Apple ID has bought.
    @Published private(set) var storeAccess: Entitlement.Access = .unlocked

    /// A way to look at the free and the paid app from one device. It exists
    /// only where the app is not a customer's copy — see `detectEnvironment` —
    /// so it can never hand anyone the paid version for nothing.
    enum TestingOverride: String {
        case free, paid
    }

    @Published private(set) var testingAvailable = false
    @Published private(set) var testingOverride: TestingOverride?

    private static let overrideKey = "paywallTesting.v1"

    init() {
        testingOverride = UserDefaults.standard.string(forKey: Self.overrideKey)
            .flatMap(TestingOverride.init(rawValue:))
        Task { await detectEnvironment() }
    }

    var entitlement: Entitlement { Entitlement(access: effectiveAccess) }

    private var effectiveAccess: Entitlement.Access {
        guard testingAvailable, let testingOverride else { return storeAccess }
        switch testingOverride {
        case .free: return .free
        case .paid: return .unlocked
        }
    }

    /// `nil` goes back to whatever the store says.
    func setTestingOverride(_ value: TestingOverride?) {
        testingOverride = value
        if let value {
            UserDefaults.standard.set(value.rawValue, forKey: Self.overrideKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.overrideKey)
        }
    }

    /// The test switch is offered in a debug build, in TestFlight and in App
    /// Review's sandbox, and never in a copy installed from the App Store.
    /// Anything that cannot be confirmed counts as a customer's copy: an
    /// offline first launch must not switch the tool on.
    private func detectEnvironment() async {
        #if DEBUG
        testingAvailable = true
        #else
        do {
            switch try await AppTransaction.shared {
            case .verified(let transaction):
                testingAvailable = transaction.environment != .production
            case .unverified:
                testingAvailable = false
            }
        } catch {
            testingAvailable = false
        }
        #endif
    }

    /// The purchase itself arrives with StoreKit.
    func purchase() async { }
}
