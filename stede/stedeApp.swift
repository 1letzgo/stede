import StedeCore
import StedeUI
import SwiftUI

@main
struct stedeApp: App {
    #if os(iOS)
    /// Push: Token von APNs, Banner im Vordergrund, Tipp auf eine Nachricht.
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, IslandTime.germanLocale)
                .tint(StedeTheme.iconBlue)
                .task {
                    CacheMaintenance.purgeExpired()
                    Task { await Tenants.refresh() }
                    // Vor der ersten Gemeindewahl gibt es nichts nachzuladen.
                    guard Tenants.hasChosen else { return }
                    Task { await ContentSync.shared.syncAll() }
                    Task { await ContentFiles.shared.sync() }
                    Task { await EventStore.prefetch(around: Date()) }
                    Task {
                        let today = IslandTime.startOfDay(Date())
                        _ = try? await WeatherStore.summary(on: today)
                    }
                }
        }
    }
}
