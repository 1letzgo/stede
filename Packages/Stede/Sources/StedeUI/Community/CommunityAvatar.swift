import StedeCore
import SwiftUI

/// Logo der Community in der Größe der Icon-Kachel; ohne Logo das Gruppensymbol.
struct CommunityAvatar: View {
    let logoURL: URL?
    var side: CGFloat?
    @ScaledMetric(relativeTo: .headline) private var size = 38.0

    var body: some View {
        if let logoURL {
            AsyncImage(url: logoURL) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    StedeIconChip(symbol: "person.3.fill", color: StedeTheme.seaTeal, side: side)
                }
            }
            .frame(width: side ?? size, height: side ?? size)
            .clipShape(StedeTheme.chipShape)
            .accessibilityHidden(true)
        } else {
            StedeIconChip(symbol: "person.3.fill", color: StedeTheme.seaTeal, side: side)
        }
    }
}
