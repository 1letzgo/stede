import SwiftUI

enum StedeTheme {
    /// Hintergrundblau des App-Icons (RGB 15, 70, 173).
    static let iconBlue = Color(red: 31 / 255, green: 111 / 255, blue: 128 / 255)

    /// Insel-Palette: Sandgrund, Kartenfläche, Hafen, Düne, Sonne, Meer.
    static let sand = Color("StedeSand")
    static let surface = Color("StedeSurface")
    static let harborRed = Color("StedeHarbor")
    static let duneGreen = Color("StedeDune")
    static let sunAmber = Color("StedeSun")
    static let seaTeal = Color("StedeSea")
    /// Tiefwasser-Blau für Akzente auf Sandgrund — ruhiger als das reine Markenblau.
    static let deep = Color("StedeDeep")
    /// Dunkles Petrol-Grün aus dem Stadtlogo (#284050) — nur für die Navigationsleiste,
    /// im Dunkelmodus etwas tiefer.
    static let bar = Color("StedeBar")
    /// Schrift und Symbole im Tiefwasserton: dunkelblau, im Dunkelmodus hellblau.
    /// `deep` selbst bleibt in beiden Modi dunkel (Leiste, gefüllte Chips).
    static let ink = Color("StedeInk")
    /// Heidekraut-Lila und Watt-Braun — für Kacheln, die sich von den übrigen
    /// Inselfarben abheben müssen (Restaurant, Sehenswürdigkeiten).
    static let heather = Color("StedeHeather")
    static let mudflat = Color("StedeMudflat")

    /// Lesebreite: auf iPad und Mac laufen Karten sonst über die volle
    /// Fensterbreite, mit zwei Wörtern an den Enden.
    static let readableWidth: CGFloat = 700

    /// Abstand zwischen Karten — auf allen Seiten derselbe.
    static let cardSpacing: CGFloat = 12

    static let cardShape = RoundedRectangle(cornerRadius: 20, style: .continuous)
    static let chipShape = RoundedRectangle(cornerRadius: 12, style: .continuous)

}

// MARK: - Karten

extension View {
    /// Standard-Kartenlook: Fläche auf Sandgrund, feine Kontur, weicher Schatten.
    /// Mit `fill` wird eine eigene Fläche gesetzt (z. B. Wetter-Verlauf) und auf
    /// Kontur und Schatten verzichtet. Hervorgehobene Karten sind Meerteal-Töne
    /// ohne Kontur — sie heben sich so von den weißen Karten ab.
    @ViewBuilder
    func stedeCard(highlighted: Bool = false, fill: AnyShapeStyle? = nil) -> some View {
        if let fill {
            background(fill, in: StedeTheme.cardShape)
                .clipShape(StedeTheme.cardShape)
        } else if highlighted {
            background {
                StedeTheme.cardShape.fill(AnyShapeStyle(StedeTheme.seaTeal.opacity(0.16)))
            }
            .clipShape(StedeTheme.cardShape)
            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        } else {
            background {
                StedeTheme.cardShape.fill(AnyShapeStyle(StedeTheme.surface))
            }
            .clipShape(StedeTheme.cardShape)
            .overlay {
                StedeTheme.cardShape.strokeBorder(
                    AnyShapeStyle(.primary.opacity(0.06)),
                    lineWidth: 1
                )
                // Die Kontur liegt über dem Inhalt und würde sonst Taps
                // schlucken — Buttons in der Karte wären tot.
                .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        }
    }
}

// MARK: - Auswahlzeilen

extension StedeTheme {
    /// Maße der Auswahlzeile unter der Navigationsleiste (Tag, Hafen, Kategorie).
    enum SelectionRow {
        static let height: CGFloat = 52
        static let horizontalInset: CGFloat = 16
        static let spacing: CGFloat = 8
    }
}

/// Waagerechte Auswahlzeile — eine Bauform für Tageswechsel, Hafenwahl und
/// Gastro-Filter. Ohne feste Höhe fällt eine horizontale ScrollView in einem
/// VStack auf null zusammen.
struct StedeSelectionRow<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: StedeTheme.SelectionRow.spacing) {
                content()
            }
            .padding(.horizontal, StedeTheme.SelectionRow.horizontalInset)
        }
        .frame(height: StedeTheme.SelectionRow.height)
        .scrollIndicators(.hidden)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

extension View {
    /// Kapsel einer Auswahlzeile: gefüllt, wenn gewählt.
    func stedeSelectionChip(isSelected: Bool) -> some View {
        font(.subheadline.weight(.semibold))
            .fontDesign(.rounded)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                isSelected ? AnyShapeStyle(StedeTheme.deep) : AnyShapeStyle(StedeTheme.surface),
                in: Capsule()
            )
            .foregroundStyle(isSelected ? Color.white : StedeTheme.ink)
    }
}

// MARK: - Bausteine

/// Druck-Rückmeldung für ganze Karten — dezenter als bei den Chips,
/// weil die Fläche deutlich größer ist.
struct StedeCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Farbiges Icon-Kachel für Kartenköpfe.
struct StedeIconChip: View {
    let symbol: String
    let color: Color
    /// Feste Kantenlänge, etwa passend zu Titel und Pille einer Ortskarte.
    var side: CGFloat?
    @ScaledMetric(relativeTo: .headline) private var size = 38.0

    var body: some View {
        Image(systemName: symbol)
            .font(.system(side == nil ? .headline : .title3, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: side ?? size, height: side ?? size)
            .background(color.opacity(0.16), in: StedeTheme.chipShape)
    }
}

/// Kapitel-Überschrift wie in den Apple-Apps: Systemschrift, keine Sperrung.
struct StedeSectionHeader: View {
    let title: String
    var symbol: String?

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
            }
            Text(title)
        }
        .font(.headline)
        .padding(.top, 4)
    }
}
