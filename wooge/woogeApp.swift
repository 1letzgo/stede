import StedeCore
import StedeUI
import SwiftUI

/// Hülle der App „Wooge“: Marke `wooge` (Info.plist `StedeBrand`), alles andere im Package.
@main
struct woogeApp: App {
    #if os(iOS)
    // Ohne Gruppen kein Push.
    #endif

    init() {
        AppStartup.registerBackgroundTasks()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, IslandTime.germanLocale)
                .tint(StedeTheme.iconBlue)
                .task { await AppStartup.run() }
        }
    }
}
