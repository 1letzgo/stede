import StedeCore
import SwiftUI

/// Profilbild einer Person als Kreis — ohne Bild die Initialen in der Rollenfarbe.
/// Ersetzt das Personen-Symbol in Mitglieder-, Zusage- und Anfragelisten.
struct PersonAvatar: View {
    let url: URL?
    let name: String
    var color: Color = StedeTheme.ink
    var side: CGFloat?
    @ScaledMetric(relativeTo: .headline) private var size = 38.0

    var body: some View {
        let edge = side ?? size
        Group {
            if let url {
                RemoteImage(url: url) { initials }
            } else {
                initials
            }
        }
        .frame(width: edge, height: edge)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var initials: some View {
        Text(CommunityAvatar.initials(of: name))
            .font(.system((side ?? 38) > 50 ? .title2 : .subheadline, design: .rounded, weight: .bold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(color.opacity(0.16))
    }
}
