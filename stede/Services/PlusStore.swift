import Foundation
import StoreKit

/// Die Produkt-IDs, wie sie in App Store Connect angelegt sind.
nonisolated enum PlusProduct: String, CaseIterable, Sendable {
    /// Einmalkauf, schaltet alle Tage dauerhaft frei.
    case lifetime = "de.letzgo.stede.plus.lifetime"
    /// Monatsabo, schaltet alle Tage für die Laufzeit frei.
    case monthly = "de.letzgo.stede.plus.monthly"

    static var allIDs: [String] { allCases.map(\.rawValue) }
}

/// Verwaltet stede+: lädt die Produkte, kauft und hält den Freischaltstatus.
///
/// Der heutige Tag ist immer frei — stede+ schaltet nur andere Tage frei.
/// Der Status kommt aus `Transaction.currentEntitlements`, also von StoreKit
/// selbst; die App speichert ihn nicht doppelt.
@Observable
final class PlusStore {
    private(set) var products: [Product] = []
    private(set) var isUnlocked = false
    private(set) var isLoadingProducts = false
    private(set) var purchaseError: String?

    private var updates: Task<Void, Never>?

    init() {
        updates = Task { [weak self] in
            // Käufe, die außerhalb der App passieren (Familienfreigabe,
            // Erstattung, Abo-Verlängerung), kommen über diesen Strom.
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refreshEntitlement()
            }
        }
    }

    deinit {
        updates?.cancel()
    }

    var lifetime: Product? { product(.lifetime) }
    var monthly: Product? { product(.monthly) }

    func product(_ id: PlusProduct) -> Product? {
        products.first { $0.id == id.rawValue }
    }

    func load() async {
        await refreshEntitlement()
        guard products.isEmpty, !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let loaded = try await Product.products(for: PlusProduct.allIDs)
            // Einmalkauf zuerst, dann das Abo.
            products = loaded.sorted { $0.id < $1.id }
        } catch {
            purchaseError = "Die Angebote konnten nicht geladen werden."
        }
    }

    func purchase(_ product: Product) async {
        purchaseError = nil
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                }
                await refreshEntitlement()
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = "Der Kauf konnte nicht abgeschlossen werden."
        }
    }

    func restore() async {
        purchaseError = nil
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            if !isUnlocked {
                purchaseError = "Es wurde kein früherer Kauf gefunden."
            }
        } catch {
            purchaseError = "Die Wiederherstellung ist fehlgeschlagen."
        }
    }

    func refreshEntitlement() async {
        var unlocked = false
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement,
                  PlusProduct(rawValue: transaction.productID) != nil,
                  transaction.revocationDate == nil
            else { continue }
            if let expiry = transaction.expirationDate, expiry <= Date() { continue }
            unlocked = true
        }
        isUnlocked = unlocked
    }
}
