import StedeCore
import StedeUI
import SwiftUI

@main
struct stedeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, IslandTime.germanLocale)
                .tint(StedeTheme.iconBlue)
                .task {
                    CacheMaintenance.purgeExpired()
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
