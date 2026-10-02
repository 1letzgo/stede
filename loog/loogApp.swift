import StedeCore
import StedeUI
import SwiftUI

/// Hülle der Langeoog-App: Marke `loog` (Info.plist `StedeBrand`), alles andere im Package.
@main
struct loogApp: App {
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
