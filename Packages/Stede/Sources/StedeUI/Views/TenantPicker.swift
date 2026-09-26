import StedeCore
import SwiftUI

/// Gemeindewechsel: erst die Inhalte der neuen Gemeinde laden, dann umschalten —
/// so zeigt die App nach dem Wechsel sofort Orte, Karte, Haltestellen und Straßen.
enum TenantSwitch {
    static func activate(_ slug: String) async {
        await Tenants.refresh()
        async let files: Void = ContentFiles.shared.sync(slug: slug)
        async let places: Void = ContentSync.shared.syncAll(slug: slug)
        _ = await (files, places)
        Tenants.select(slug)
        #if canImport(UIKit)
        OfflineMapLayers.warmUp()
        #endif
    }
}

/// Liste der Ammerland-Gemeinden — beim ersten Start bildschirmfüllend, sonst als Sheet
/// aus den Einstellungen.
struct TenantPickerView: View {
    var onboarding = false
    @Environment(\.dismiss) private var dismiss
    @State private var tenants = Tenants.all
    @State private var loadingSlug: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StedeTheme.cardSpacing) {
                if onboarding {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Willkommen bei stede")
                            .font(.largeTitle.weight(.bold))
                            .fontDesign(.rounded)
                        Text("Wähle deine Gemeinde im Ammerland. Du kannst sie später in den Einstellungen wechseln.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 32)
                    .padding(.bottom, 8)
                }
                ForEach(tenants) { tenant in
                    Button {
                        choose(tenant.slug)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(StedeTheme.ink)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tenant.municipality).font(.headline)
                                Text(tenant.officialName).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            if loadingSlug == tenant.slug {
                                ProgressView()
                            } else if !onboarding, tenant.slug == Tenants.currentSlug {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(StedeTheme.ink)
                            }
                        }
                        .contentShape(Rectangle())
                        .stedeRowCard()
                    }
                    .buttonStyle(StedeCardButtonStyle())
                    .foregroundStyle(.primary)
                    .disabled(loadingSlug != nil)
                    .accessibilityAddTraits(!onboarding && tenant.slug == Tenants.currentSlug ? .isSelected : [])
                }
                if !onboarding {
                    Text("Straße, Haltestelle und Bahnhof wählst du nach einem Wechsel neu.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }
            .padding()
        }
        .background(StedeTheme.sand)
        .task {
            await Tenants.refresh()
            tenants = Tenants.all
        }
    }

    private func choose(_ slug: String) {
        guard onboarding || slug != Tenants.currentSlug else { dismiss(); return }
        loadingSlug = slug
        Task {
            await TenantSwitch.activate(slug)
            loadingSlug = nil
            if !onboarding { dismiss() }
        }
    }
}

/// Sheet-Hülle mit Leiste für die Einstellungen.
struct TenantPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TenantPickerView()
                .navigationTitle("Gemeinde")
                .stedeBar()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") { dismiss() }
                    }
                }
        }
    }
}
