import StedeCore
import StedeUI
import SwiftUI

/// Hülle der App „__APP_NAME__“: Marke `__ID__` (Info.plist `StedeBrand`), alles andere im Package.
@main
struct __STRUCT__: App {
    #if os(iOS)
    __PUSH_DELEGATE__
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
