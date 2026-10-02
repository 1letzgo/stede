import StedeCore
import StedeUI
import SwiftUI

@main
struct stedeApp: App {
    #if os(iOS)
    /// Push: Token von APNs, Banner im Vordergrund, Tipp auf eine Nachricht.
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
