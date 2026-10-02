import StedeCore
import StoreKit
import SwiftUI

/// Große Kachel „<App>+“ ganz oben in den Einstellungen (Baustein `plus`): Status, Kauf direkt in der
/// Kachel, Wiederherstellen und Rechtliches — keine eigene Ansicht. Das Schloss in Tagesleiste und
/// Kalender führt hierher (`AppNavigation.openPlus`).
struct PlusSection: View {
    @Environment(PlusStore.self) private var store
    @State private var page: BrowserPage?
    @State private var isWorking = false

    private var name: String { AppBrand.current.plusName }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                StedeIconChip(symbol: store.isUnlocked ? "checkmark.seal.fill" : "sparkles",
                              color: store.isUnlocked ? StedeTheme.duneGreen : StedeTheme.seaTeal)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(.title, design: .rounded, weight: .bold))
                    Text(store.isUnlocked ? "Aktiv — alle Tage freigeschaltet" : "Alle Tage statt nur heute")
                        .font(.headline)
                        .foregroundStyle(store.isUnlocked ? StedeTheme.duneGreen : .primary)
                }
            }

            if !store.isUnlocked {
                Text("Der heutige Tag bleibt immer kostenfrei. Mit \(name) blätterst du durch beliebige Tage — vor und zurück.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if offers.isEmpty {
                    Text(store.isLoadingProducts ? "Angebote werden geladen …" : "Die Angebote sind gerade nicht erreichbar.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(offers, id: \.id) { product in
                        Button {
                            Task { await buy(product) }
                        } label: {
                            HStack {
                                Text(product.displayName)
                                Spacer(minLength: 8)
                                Text(priceLabel(product)).monospacedDigit()
                            }
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(StedeTheme.deep, in: Capsule())
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(StedeCardButtonStyle())
                        .disabled(isWorking)
                    }
                }
            }

            if let error = store.purchaseError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(StedeTheme.harborRed)
            }

            HStack(spacing: 16) {
                if !store.isUnlocked {
                    Button("Käufe wiederherstellen") { Task { await store.restore() } }
                }
                Button("Nutzungsbedingungen") {
                    page = BrowserPage(url: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                }
                if let privacy = AppBrand.current.privacyURL {
                    Button("Datenschutz") { page = BrowserPage(url: privacy) }
                }
            }
            .font(.caption.weight(.semibold))
            .tint(StedeTheme.ink)

            if !store.isUnlocked {
                Text("\(name) monatlich läuft einen Monat und verlängert sich automatisch, bis du in den Einstellungen deines Apple-Accounts kündigst. \(name) einmalig ist ein einmaliger Kauf ohne Laufzeit.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(StedeTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .stedeCard(highlighted: true)
        .sheet(item: $page) { page in
            InAppBrowser(url: page.url)
        }
        .task { await store.load() }
    }

    /// Einmalkauf zuerst — er ist das Angebot, das die meisten wollen.
    private var offers: [Product] {
        [store.lifetime, store.monthly].compactMap { $0 }
    }

    private func buy(_ product: Product) async {
        isWorking = true
        await store.purchase(product)
        isWorking = false
    }

    private func priceLabel(_ product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else { return product.displayPrice }
        let unit = switch period.unit {
        case .day: "Tag"
        case .week: "Woche"
        case .month: "Monat"
        case .year: "Jahr"
        @unknown default: "Zeitraum"
        }
        return "\(product.displayPrice)/\(unit)"
    }
}
