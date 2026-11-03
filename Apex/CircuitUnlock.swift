import Foundation
import Observation
import StoreKit

// Ghost Thread is free to try: Ardennes and Apex School. A one-time purchase opens every other circuit, and every
// circuit added after them, for good.

/// What's free, and what needs the unlock.
enum CircuitUnlock {
    /// A non-consumable. Product IDs are permanent once created in App Store Connect.
    static let productID = "com.kraigstrong.apex.allcircuits"

    /// Whether the game sells the unlock, in every build: Xcode builds sell it against Apex.storekit, TestFlight builds
    /// in the sandbox (free), and the App Store for real. Turned off, every circuit is open.
    static let isSelling = true

    /// Free without the unlock. Everything else needs it, so a circuit added later is part of it from the start.
    static let free: Set<String> = [TrackLayout.ardennes.id, TrackLayout.apexSchool.id]

    static func isLocked(_ id: String, unlocked: Bool, selling: Bool = isSelling) -> Bool {
        selling && !unlocked && !free.contains(id)
    }

    /// The circuits it opens, in track-list order: the ones its screen shows.
    static var circuitsItOpens: [TrackLayout] { TrackLayout.all.filter { !free.contains($0.id) } }
}

/// The one-time purchase that opens every circuit (a non-consumable, shared with Family Sharing). Modeled on Bigger
/// Fish's `ArcadePurchases`.
@MainActor @Observable
final class CircuitPurchases {
    enum Outcome { case unlocked, pending, cancelled, failed }

    static let shared = CircuitPurchases()

    /// Cached so the track list draws right at launch and offline; StoreKit confirms it.
    private(set) var isUnlocked: Bool
    private(set) var product: Product?

    static let unlockedKey = "apex.unlocked"
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var updates: Task<Void, Never>?
    /// `AppStore.sync()`, which can ask to sign in. Tests replace it, since it waits on that prompt.
    @ObservationIgnored private let syncWithAppStore: () async throws -> Void
    /// Xcode builds launched with `-ApexUnlocked` keep what it says rather than asking StoreKit.
    @ObservationIgnored private var isOverridden = false

    init(defaults: UserDefaults = .standard,
         syncWithAppStore: @escaping () async throws -> Void = { try await AppStore.sync() }) {
        self.defaults = defaults
        self.syncWithAppStore = syncWithAppStore
        isUnlocked = defaults.bool(forKey: Self.unlockedKey)
        #if DEBUG
        if UserDefaults.standard.object(forKey: "ApexUnlocked") != nil {
            isUnlocked = UserDefaults.standard.bool(forKey: "ApexUnlocked")
            isOverridden = true
        }
        #endif
    }

    func isLocked(_ id: String) -> Bool { CircuitUnlock.isLocked(id, unlocked: isUnlocked) }

    /// Starts listening for transactions and checks what's already owned. Call once at launch; does nothing while the
    /// unlock isn't on sale.
    func start() {
        guard CircuitUnlock.isSelling, !isOverridden, updates == nil else { return }
        // Bought on another device, approved by a parent (Ask to Buy), or refunded.
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result, transaction.productID == CircuitUnlock.productID {
                    await transaction.finish()
                    await self?.refresh()
                }
            }
        }
        Task { [weak self] in
            await self?.refresh()
            await self?.loadProduct()
        }
    }

    /// Re-reads current entitlements. Refunded and revoked purchases drop out of them.
    func refresh() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == CircuitUnlock.productID,
               transaction.revocationDate == nil {
                owned = true
            }
        }
        setUnlocked(owned)
    }

    func loadProduct() async {
        guard product == nil else { return }
        product = try? await Product.products(for: [CircuitUnlock.productID]).first
    }

    /// The localized price, such as "$1.99", once the product has loaded. Xcode builds launched with
    /// `-ApexUnlockPrice '$1.99'` show that instead, since only a Run from Xcode has the StoreKit configuration.
    var displayPrice: String? {
        #if DEBUG
        if let price = UserDefaults.standard.string(forKey: "ApexUnlockPrice") { return price }
        #endif
        return product?.displayPrice
    }

    func purchase() async -> Outcome {
        await loadProduct()
        guard let product else { return .failed }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                setUnlocked(true)
                return .unlocked
            case .success(.unverified):
                return .failed
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .failed
            }
        } catch {
            return .failed
        }
    }

    /// Syncs with the App Store (it may ask to sign in), then re-checks. True if unlocked.
    func restore() async -> Bool {
        try? await syncWithAppStore()
        await refresh()
        return isUnlocked
    }

    private func setUnlocked(_ unlocked: Bool) {
        guard unlocked != isUnlocked else { return }
        isUnlocked = unlocked
        defaults.set(unlocked, forKey: Self.unlockedKey)
    }
}
