import StedeCore
import StedeUI
import SwiftUI

/// Hülle der App „Spoog“: Marke `spoog` (Info.plist `StedeBrand`), alles andere im Package.
@main
struct spoogApp: App {
    #if os(iOS)
    /// Push: Token von APNs, Banner im Vordergrund, Tipp auf eine Nachricht — wie in stede.
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate
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
