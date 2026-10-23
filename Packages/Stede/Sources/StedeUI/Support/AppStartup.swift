import Foundation
import StedeCore

/// Hochgezählt, sobald ein Abgleich neue Orte, Karten oder Haltestellen gebracht hat —
/// Ansichten, die `IslandCatalog` lesen, zeichnen dann neu.
@Observable
public final class ContentRevision {
    public static let shared = ContentRevision()
    private(set) var value = 0

    func bump() {
        ContentGeneration.bump()
        value += 1
    }
}

/// Start aller App-Hüllen (stede, Loog …): Caches aufräumen, Inhalte abgleichen, vorladen.
public enum AppStartup {
    /// Im `init` der App — Hintergrundaufgaben müssen vor dem Ende des Starts registriert sein.
    /// Nur, was die Info.plist der Hülle unter `BGTaskSchedulerPermittedIdentifiers` erlaubt —
    /// eine fremde Kennung lässt `BGTaskScheduler` abstürzen.
    public static func registerBackgroundTasks() {
        let permitted = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] ?? []
        if permitted.contains(TideStore.taskIdentifier) {
            TideStore.registerBackgroundRefresh()
        }
    }

    public static func run() async {
        CacheMaintenance.purgeExpired()
        // Seit 10/2026 kennt stede nur noch Westerstede: wer eine andere Gemeinde gewählt hatte,
        // landet dort und verliert deren Straße, Haltestelle und Bahnhof.
        if !AppBrand.current.choosesTenant, let stored = UserDefaults.standard.string(forKey: Tenants.slugKey),
           stored != AppBrand.current.defaultTenant {
            Tenants.select(AppBrand.current.defaultTenant)
        }
        Task { await Tenants.refresh() }
        // Vor der ersten Gemeindewahl gibt es nichts nachzuladen.
        guard Tenants.hasChosen else { return }
        Task {
            async let places = ContentSync.shared.syncAll()
            async let files = ContentFiles.shared.sync()
            let (placesChanged, filesChanged) = await (places, files)
            if placesChanged || filesChanged { ContentRevision.shared.bump() }
        }
        if Features.has(.calendar) {
            Task { await EventStore.prefetch(around: Date()) }
        }
        let today = IslandTime.startOfDay(Date())
        if Features.has(.weather) {
            Task { _ = try? await WeatherStore.summary(on: today) }
        }
        if Features.has(.air) {
            Task { _ = try? await AirQualityStore.hours(on: today) }
        }
        if Features.has(.tides) {
            Task {
                _ = try? await TideStore.shared.loadIfNeeded()
                TideStore.scheduleBackgroundRefresh()
            }
        }
    }
}
