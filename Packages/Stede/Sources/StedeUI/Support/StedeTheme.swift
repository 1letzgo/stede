import SwiftUI
import StedeCore

public enum StedeTheme {
    /// Akzent: Petrol aus Logo und Website der Stadt (#294753), im Dark Mode helles Petrol
    /// (#9FC3D0) wie `StedeInk` — sonst sind Links, Knöpfe und der aktive Tab dort kaum lesbar.
    /// Name aus der Inselzeit behalten.
    public static let iconBlue = brand("Ink")

    /// Insel-Palette: Sandgrund, Kartenfläche, Hafen, Düne, Sonne, Meer.
    static let sand = brand("Sand")
    static let surface = brand("Surface")
    static let harborRed = brand("Harbor")
    static let duneGreen = brand("Dune")
    static let sunAmber = brand("Sun")
    static let seaTeal = brand("Sea")
    /// Tiefwasser-Blau für Akzente auf Sandgrund — ruhiger als das reine Markenblau.
    static let deep = brand("Deep")
    /// Einheitliche Höhe aller Kapsel-Buttons (Auswahl, Aktion, Zusage).
    static let chipHeight: CGFloat = 36
    /// Dunkles Petrol-Grün aus dem Stadtlogo (#284050) — nur für die Navigationsleiste,
    /// im Dunkelmodus etwas tiefer.
    static let bar = brand("Bar")
    /// Schrift und Symbole im Tiefwasserton: dunkelblau, im Dunkelmodus hellblau.
    /// `deep` selbst bleibt in beiden Modi dunkel (Leiste, gefüllte Chips).
    static let ink = brand("Ink")
    /// Heidekraut-Lila und Watt-Braun — für Kacheln, die sich von den übrigen
    /// Inselfarben abheben müssen (Restaurant, Sehenswürdigkeiten).
    static let heather = brand("Heather")
    static let mudflat = brand("Mudflat")

    /// Farbe aus der Palette der Marke (`StedeSand`, `LoogSand` …).
    private static func brand(_ name: String) -> Color {
        Color("\(AppBrand.current.palette)\(name)", bundle: .module)
    }

    /// Lesebreite: auf iPad und Mac laufen Karten sonst über die volle
    /// Fensterbreite, mit zwei Wörtern an den Enden.
    static let readableWidth: CGFloat = 700

    /// Abstand zwischen Karten — auf allen Seiten derselbe.
    static let cardSpacing: CGFloat = 12
    /// Innenabstand großer Karten (Orte, Termine, Communities).
    static let cardPadding: CGFloat = 16
    /// Innenabstand einzeiliger Listenkarten (Abfahrten, Mitglieder, Abfuhr).
    static let rowPadding = EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)

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

// MARK: - Leiste und Sheets

extension View {
    /// Petrol-Leiste aus dem Stadtlogo mit weißer Schrift — auf jeder Seite und in jedem Sheet.
    func stedeBar() -> some View {
        #if os(macOS)
        self
        #else
        self
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(StedeTheme.bar, for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        #endif
    }

    /// Formulare und Listen in Sheets: Sandgrund statt Systemgrau, dazu die Petrol-Leiste.
    func stedeSheetForm() -> some View {
        scrollContentBackground(.hidden)
            .background(StedeTheme.sand)
            .stedeBar()
    }

    /// Einzeilige Listenkarte (Mitglied, Zusage, Anfrage).
    func stedeRowCard() -> some View {
        padding(StedeTheme.rowPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .stedeCard()
    }
}

/// Eingabefeld in Karten: sandfarbene Kapsel statt System-Rahmen.
struct StedeTextField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .autocorrectionDisabled()
            #if !os(macOS)
            .textInputAutocapitalization(.never)
            #endif
            .padding(.horizontal, 14)
            .frame(minHeight: StedeTheme.chipHeight)
            .background(StedeTheme.sand, in: Capsule())
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
    /// Kapsel einer Auswahlzeile: gefüllt, wenn gewählt. Feste Höhe, damit
    /// Text- und Symbol-Chips in einer Reihe gleich hoch sind.
    func stedeSelectionChip(isSelected: Bool) -> some View {
        font(.subheadline.weight(.semibold))
            .fontDesign(.rounded)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(minHeight: StedeTheme.chipHeight)
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
/// `StedeSectionHeader` als Kopf einer `Form`-Section — gleiche Optik wie auf den Seiten
/// (Symbol + Headline, keine Großbuchstaben), bündig mit der Kartenkante.
struct StedeFormHeader: View {
    let title: String
    var symbol: String?

    var body: some View {
        StedeSectionHeader(title: title, symbol: symbol)
            .foregroundStyle(.primary)
            .textCase(nil)
            .listRowInsets(EdgeInsets(top: 12, leading: 4, bottom: 8, trailing: 0))
    }
}

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
