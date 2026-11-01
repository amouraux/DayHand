import Foundation
import StoreKit

/// Where this device's `Entitlement` comes from: the App Store, through StoreKit 2.
///
/// Device-local on purpose: it is never written to the document, because a
/// synced file would hand one person's purchase to someone else.
///
/// Two products, both non-consumable. The unlock is the paid one. The trial is a
/// free one the user starts by choosing it: its purchase date is the start, so
/// it follows the Apple ID across devices, survives a reinstall and can be
/// taken only once. Apple's developer support names a free and a paid
/// non-consumable as the way to offer a trial on a one-time purchase.
///
/// There is no switch for trying the free and the paid app: a customer's copy
/// and a reviewer's copy behave the same, so the limits are what the reviewer
/// sees. In TestFlight and App Review purchases are sandbox purchases and cost
/// nothing, which is how a tester gets the unlock.
@MainActor
final class Purchases: ObservableObject {
    static let unlockID = "com.andremouraux.tnt.unlock"
    static let trialID = "com.andremouraux.tnt.trial"

    /// What the App Store says this Apple ID has: the last confirmed state, until
    /// StoreKit can be asked again.
    @Published private(set) var storeAccess: Entitlement.Access
    /// The unlock's price in the user's own currency, once the App Store has said.
    @Published private(set) var unlockPrice: String?
    /// True while the App Store is being asked, so a button cannot be pressed twice.
    @Published private(set) var isWorking = false
    /// One thing to tell the user, shown once: a failure, or what a restore found.
    @Published var notice: String?

    @Published private var unlock: Product?
    @Published private var trial: Product?
    private var updates: Task<Void, Never>?

    private static let cacheKey = "purchases.access.v1"
    private static let clockKey = "purchases.latestSeen.v1"

    /// Never goes back: see `TrialClock`.
    private var clock = TrialClock(
        latest: Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: Purchases.clockKey))
    )

    /// The date every entitlement check counts by. Saved when it has moved on
    /// by an hour, not on every read: views ask often.
    var now: Date {
        let before = clock.latest
        let reading = clock.reading(Date())
        if abs(clock.latest.timeIntervalSince(before)) > 3600 {
            UserDefaults.standard.set(clock.latest.timeIntervalSince1970, forKey: Self.clockKey)
        }
        return reading
    }

    init() {
        storeAccess = UserDefaults.standard.string(forKey: Self.cacheKey)
            .flatMap(Entitlement.Access.init(cacheValue:)) ?? .free
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }
        Task {
            await loadProducts()
            await refresh()
        }
    }

    var entitlement: Entitlement { Entitlement(access: storeAccess) }

    /// Whether the trial can still be started: it has not been, and the App
    /// Store offers it.
    var canStartTrial: Bool { !storeAccess.hasStartedTrial && storeAccess != .unlocked && trial != nil }

    // MARK: Asking the App Store

    func loadProducts() async {
        guard unlock == nil || trial == nil else { return }
        guard let products = try? await Product.products(for: [Self.unlockID, Self.trialID]) else { return }
        unlock = products.first { $0.id == Self.unlockID }
        trial = products.first { $0.id == Self.trialID }
        unlockPrice = unlock?.displayPrice
    }

    /// Read what the Apple ID owns. Nothing it reports can take a granted state
    /// away; see `Entitlement.Access.resolve`.
    func refresh(unlockRevoked: Bool = false) async {
        var unlocked = false
        var trialStart: Date?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.revocationDate == nil else { continue }
            if transaction.productID == Self.unlockID { unlocked = true }
            if transaction.productID == Self.trialID { trialStart = transaction.originalPurchaseDate }
        }
        let access = Entitlement.Access.resolve(
            cached: storeAccess, observedUnlocked: unlocked,
            observedTrialStart: trialStart, unlockRevoked: unlockRevoked
        )
        storeAccess = access
        UserDefaults.standard.set(access.cacheValue, forKey: Self.cacheKey)
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        await transaction.finish()
        let refunded = transaction.productID == Self.unlockID && transaction.revocationDate != nil
        await refresh(unlockRevoked: refunded)
    }

    // MARK: Buying

    func purchase() async { await buy(unlock) }

    func startTrial() async { await buy(trial) }

    private func buy(_ product: Product?) async {
        guard let product else {
            await loadProducts()
            notice = String(localized: "The App Store could not be reached. Try again later.")
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await refresh()
                } else {
                    notice = String(localized: "The App Store could not be reached. Try again later.")
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            notice = String(localized: "The App Store could not be reached. Try again later.")
        }
    }

    /// Required by the App Store: someone who bought on another device, or
    /// before a reinstall, can ask for it again.
    func restore() async {
        isWorking = true
        defer { isWorking = false }
        do { try await AppStore.sync() } catch {
            notice = String(localized: "The App Store could not be reached. Try again later.")
            return
        }
        await refresh()
        notice = storeAccess == .unlocked
            ? String(localized: "Purchases restored.")
            : String(localized: "No earlier purchase was found for this Apple Account.")
    }
}
