import StedeCore
import SwiftUI

/// Logo der Community in der Größe der Icon-Kachel; ohne Logo die Initialen
/// des Namens („SW“ für „SPD Westerstede“) auf türkiser Kachel.
struct CommunityAvatar: View {
    let logoURL: URL?
    let name: String
    var side: CGFloat?
    @ScaledMetric(relativeTo: .headline) private var size = 38.0

    var body: some View {
        if let logoURL {
            RemoteImage(url: logoURL) { initialsTile }
            .frame(width: side ?? size, height: side ?? size)
            .clipShape(StedeTheme.chipShape)
            .accessibilityHidden(true)
        } else {
            initialsTile
        }
    }

    private var initialsTile: some View {
        Text(Self.initials(of: name))
            .font(.system(side.map { $0 > 50 ? .title2 : .subheadline } ?? .subheadline, design: .rounded, weight: .bold))
            .foregroundStyle(StedeTheme.seaTeal)
            .frame(width: side ?? size, height: side ?? size)
            .background(StedeTheme.seaTeal.opacity(0.16), in: StedeTheme.chipShape)
            .accessibilityHidden(true)
    }

    /// Erste Buchstaben der ersten beiden Wörter, sonst die ersten zwei Zeichen.
    static func initials(of name: String) -> String {
        let words = name.split(whereSeparator: { $0.isWhitespace || $0 == "-" }).filter { $0.first?.isLetter == true || $0.first?.isNumber == true }
        let letters = words.prefix(2).compactMap { $0.first }.map { String($0).uppercased() }
        if letters.count >= 2 { return letters.joined() }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return String(trimmed.prefix(2)).uppercased()
    }
}
