import Foundation
import Supabase

/// Zugang zum gemeinsamen Supabase-Projekt „lokalz“ — ein Backend für alle
/// Gemeinde-Apps. Welche Gemeinde die App zeigt, wählt der Nutzer (`Tenants`).
public nonisolated enum Backend {
    public static let url = URL(string: "https://fkzjlecsetbnumtqrnem.supabase.co")!
    /// Publishable Key: darf in der App liegen, RLS schützt die Daten.
    public static let publishableKey = "sb_publishable_5ptJm36r8qnhKrGoGOWd0A_5uOpaBmH"
    public static var tenantSlug: String { Tenants.currentSlug }
    /// Deep-Link für Magic-Link und OAuth-Rückkehr; in der Supabase-Konsole freigeben.
    public static let redirectURL = URL(string: "\(AppBrand.current.urlScheme)://auth-callback")!

    public static let client = SupabaseClient(
        supabaseURL: url,
        supabaseKey: publishableKey,
        options: SupabaseClientOptions(
            auth: SupabaseClientOptions.AuthOptions(redirectToURL: redirectURL)
        )
    )

    public static func communityLogoURL(path: String) -> URL {
        url.appending(path: "storage/v1/object/public/community-logos/\(path)")
    }

    /// Öffentlicher Bucket `avatars`; Pfad `<user_id>/<uuid>.jpg`.
    public static func avatarURL(path: String) -> URL {
        url.appending(path: "storage/v1/object/public/avatars/\(path)")
    }

    /// Öffentlicher Bucket `event-photos`; Pfad `<community_id>/<uuid>.jpg`.
    public static func eventPhotoURL(path: String) -> URL {
        url.appending(path: "storage/v1/object/public/event-photos/\(path)")
    }

    public static func feedURL(token: String, scope: String = "mine") -> URL {
        URL(string: "\(url.absoluteString)/functions/v1/calendar-feed/\(token).ics?scope=\(scope)")!
    }

    /// `webcal://` öffnet direkt den Abo-Dialog des Systemkalenders.
    public static func webcalURL(token: String, scope: String = "mine") -> URL {
        URL(string: "webcal://\(url.host ?? "")/functions/v1/calendar-feed/\(token).ics?scope=\(scope)")!
    }
}
