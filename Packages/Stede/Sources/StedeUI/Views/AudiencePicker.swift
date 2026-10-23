import StedeCore
import SwiftUI

/// „Zu Besuch“ oder „Ich wohne hier“ — beim ersten Start bildschirmfüllend, danach als
/// Auswahl unter Einstellungen. Touristen sehen alles Öffentliche, Einwohner zusätzlich
/// Abfuhr, Politik und Gruppen (soweit die Gemeinde sie hat).
struct AudiencePickerView: View {
    var onboarding = false
    @AppStorage(Audience.key) private var audienceRaw = ""
    /// Zählt Neuladungen der Gemeinde-Konfiguration — nach einem Update kann der Cache Bausteine noch nicht kennen.
    @State private var configVersion = 0

    var body: some View {
        if onboarding {
            ScrollView {
                VStack(alignment: .leading, spacing: StedeTheme.cardSpacing) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Willkommen bei \(AppBrand.current.displayName)")
                            .font(.largeTitle.weight(.bold))
                            .fontDesign(.rounded)
                        Text("Bist du in \(Tenants.current.municipality) zu Besuch oder wohnst du hier? Danach richtet sich, was die App zeigt. Du kannst es später in den Einstellungen ändern.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 32)
                    .padding(.bottom, 8)
                    options
                }
                .padding()
            }
            .background(StedeTheme.sand)
            .task {
                await Tenants.refresh()
                configVersion += 1
            }
        } else {
            options
        }
    }

    private var options: some View {
        VStack(spacing: StedeTheme.cardSpacing) {
            ForEach(Audience.allCases, id: \.self) { audience in
                Button {
                    withAnimation(.snappy) { audienceRaw = audience.rawValue }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        StedeIconChip(symbol: audience.symbol, color: color(audience))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(audience.title)
                                .font(.headline)
                                .fontDesign(.rounded)
                            Text(detail(audience, version: configVersion))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 8)
                        if !onboarding, audienceRaw == audience.rawValue {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundStyle(StedeTheme.ink)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .padding(StedeTheme.cardPadding)
                    .stedeCard(highlighted: !onboarding && audienceRaw == audience.rawValue)
                }
                .buttonStyle(StedeCardButtonStyle())
                .foregroundStyle(.primary)
                .accessibilityAddTraits(audienceRaw == audience.rawValue ? .isSelected : [])
            }
        }
    }

    private func color(_ audience: Audience) -> Color {
        audience == .tourist ? StedeTheme.seaTeal : StedeTheme.duneGreen
    }

    /// Beschreibt nur, was es in dieser Gemeinde wirklich gibt.
    private func detail(_ audience: Audience, version _: Int) -> String {
        switch audience {
        case .tourist:
            return "Termine, Ausflüge, Gastro, Wetter und alles für unterwegs."
        case .resident:
            let tenant = Tenants.current.features ?? AppBrand.current.defaultFeatures
            let allowed = tenant.intersection(AppBrand.current.allowedFeatures).enabled
            let extras = [(Feature.waste, "Abfuhr"), (.politics, "Politik"), (.groups, "Gruppen")]
                .filter { allowed.contains($0.0) }.map(\.1)
            return extras.isEmpty ? "Alles für den Alltag vor Ort."
                : "Alles für Gäste und zusätzlich \(extras.formatted(.list(type: .and)))."
        }
    }
}
