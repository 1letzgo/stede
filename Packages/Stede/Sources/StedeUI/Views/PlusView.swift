import StedeCore
import StoreKit
import SwiftUI

struct PlusView: View {
    @Environment(PlusStore.self) private var store
    @State private var page: BrowserPage?
    @State private var isWorking = false

    var body: some View {
        TabScreen(title: AppBrand.current.plusName, showsDateNavigator: false) {
            ScrollView {
                VStack(alignment: .leading, spacing: StedeTheme.cardSpacing) {
                    header

                    if store.isUnlocked {
                        activeCard
                    } else {
                        ForEach(offers, id: \.id) { product in
                            OfferCard(product: product, isWorking: isWorking) {
                                await buy(product)
                            }
                        }
                        if store.products.isEmpty {
                            InfoCard {
                                Text(store.isLoadingProducts
                                     ? "Angebote werden geladen …"
                                     : "Die Angebote sind gerade nicht erreichbar.")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let error = store.purchaseError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(StedeTheme.harborRed)
                    }

                    comingSoon

                    if !store.isUnlocked {
                        Button("Käufe wiederherstellen") {
                            Task { await store.restore() }
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                    }

                    legal
                }
                .padding()
            }
        }
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

    private var header: some View {
        InfoCard(fill: AnyShapeStyle(
            LinearGradient(
                colors: [StedeTheme.seaTeal.opacity(0.28), StedeTheme.deep.opacity(0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    StedeIconChip(symbol: "sparkles", color: StedeTheme.seaTeal)
                    Text(AppBrand.current.plusName)
                        .font(.system(.title, design: .rounded, weight: .bold))
                }
                Text("Alle Tage statt nur heute")
                    .font(.headline)
                Text("Der heutige Tag bleibt immer kostenfrei. Mit \(AppBrand.current.plusName) blätterst du durch beliebige Tage — vor und zurück.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var activeCard: some View {
        InfoCard(isHighlighted: true) {
            VStack(alignment: .leading, spacing: 6) {
                Label("\(AppBrand.current.plusName) ist aktiv", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(StedeTheme.duneGreen)
                Text("Danke! Alle Tage sind freigeschaltet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var comingSoon: some View {
        InfoCard {
            VStack(alignment: .leading, spacing: 8) {
                StedeSectionHeader(title: "Bald in \(AppBrand.current.plusName)", symbol: "hammer")
                Text("Weitere Zusatzfunktionen sind in Arbeit. Sie kommen ohne Aufpreis dazu.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var legal: some View {
        VStack(spacing: 6) {
            HStack(spacing: 16) {
                Button("Nutzungsbedingungen") {
                    page = BrowserPage(url: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                }
                if let privacy = AppBrand.current.privacyURL {
                    Button("Datenschutz") {
                        page = BrowserPage(url: privacy)
                    }
                }
            }
            .font(.caption)

            Text("\(AppBrand.current.plusName) monatlich läuft einen Monat und verlängert sich automatisch um je einen Monat, bis du in den Einstellungen deines Apple-Accounts kündigst. \(AppBrand.current.plusName) einmalig ist ein einmaliger Kauf ohne Laufzeit.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }
}

private struct OfferCard: View {
    let product: Product
    let isWorking: Bool
    let buy: () async -> Void

    var body: some View {
        InfoCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(product.displayName)
                            .font(.headline)
                            .fontDesign(.rounded)
                        Text(product.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Text(priceLabel)
                        .font(.title3.weight(.bold))
                        .fontDesign(.rounded)
                        .monospacedDigit()
                }

                Button {
                    Task { await buy() }
                } label: {
                    Text(product.type == .autoRenewable ? "Abo starten" : "Kaufen")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(StedeTheme.deep, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(StedeCardButtonStyle())
                .disabled(isWorking)
            }
        }
    }

    private var priceLabel: String {
        guard let period = product.subscription?.subscriptionPeriod else {
            return product.displayPrice
        }
        return "\(product.displayPrice)/\(unit(period))"
    }

    private func unit(_ period: Product.SubscriptionPeriod) -> String {
        switch period.unit {
        case .day: "Tag"
        case .week: "Woche"
        case .month: "Monat"
        case .year: "Jahr"
        @unknown default: "Zeitraum"
        }
    }
}
