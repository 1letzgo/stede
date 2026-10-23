#if os(iOS)
import StedeCore
import SwiftUI
import UIKit
import UserNotifications

/// Ziel einer angetippten Benachrichtigung.
enum PushRoute: Equatable {
    /// Beitrittsanfrage oder beantragte Gruppe: Admin-Bereich öffnen.
    case admin
    /// Neuer Termin oder neue Umfrage: Gruppe im passenden Reiter öffnen.
    case community(UUID, polls: Bool)
}

/// Push über APNs: fragt nach der Erlaubnis, sobald jemand Mitglied einer Gruppe
/// (oder Gemeinde-Admin) ist, meldet das Gerät in `push_tokens` an und merkt sich,
/// wohin eine angetippte Nachricht führen soll. Versand: Edge Function `push-send`.
@Observable
final class PushCenter {
    static let shared = PushCenter()

    /// Von `ContentView`/`CommunityListView` abgeholt und dann geleert.
    var pendingRoute: PushRoute?

    private var userID: UUID?
    private var tenantID: UUID?
    private var token: String?
    private let client = PushClient()

    /// Nach der Anmeldung, wenn es etwas zu benachrichtigen gibt. Fragt nur beim ersten Mal.
    func enable(userID: UUID, tenantID: UUID?) async {
        self.userID = userID
        self.tenantID = tenantID
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }
        UIApplication.shared.registerForRemoteNotifications()
        await upload()
    }

    func didRegister(deviceToken: Data) {
        token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await upload() }
    }

    /// Vor dem Abmelden oder Löschen des Kontos.
    func unregister() async {
        if let token { try? await client.unregister(token: token) }
        userID = nil
    }

    private func upload() async {
        guard let token, let userID else { return }
        #if DEBUG
        let sandbox = true
        #else
        let sandbox = false
        #endif
        try? await client.register(token: token, userID: userID, sandbox: sandbox, tenantID: tenantID)
    }

    /// Angetippte Nachricht: `type` und IDs aus dem Payload von `push-send`.
    func open(type: String?, communityID: String?) {
        switch type {
        case "join_request", "community_pending":
            pendingRoute = .admin
        case "event", "poll":
            if let id = communityID.flatMap(UUID.init(uuidString:)) { pendingRoute = .community(id, polls: type == "poll") }
        default:
            break
        }
    }
}

/// App-Delegate für Push — von `stedeApp` per `@UIApplicationDelegateAdaptor` eingebunden.
public final class PushAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    public func application(_ application: UIApplication,
                            didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    public func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushCenter.shared.didRegister(deviceToken: deviceToken)
    }

    public func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Ohne Token eben keine Nachrichten — z. B. im Simulator ohne Push-Unterstützung.
    }

    // Bewusst die Varianten mit Completion-Handler, aufgerufen auf dem Main-Thread: bei den async-Varianten
    // ruft das System den Handler nach dem Return auf einem Hintergrund-Thread auf, und UIKit bricht beim
    // Start per Mitteilung mit einer Assertion ab (TestFlight-Absturz Build 18).

    /// Auch im Vordergrund als Banner zeigen.
    public nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                                   withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void) {
        DispatchQueue.main.async { completionHandler([.banner, .list, .sound]) }
    }

    public nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                                   withCompletionHandler completionHandler: @escaping @Sendable () -> Void) {
        let info = response.notification.request.content.userInfo
        let type = info["type"] as? String
        let communityID = info["community_id"] as? String
        DispatchQueue.main.async {
            MainActor.assumeIsolated { PushCenter.shared.open(type: type, communityID: communityID) }
            completionHandler()
        }
    }
}
#endif
