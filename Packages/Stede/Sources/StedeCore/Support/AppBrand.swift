import Foundation

/// Welche App gerade läuft: stede (Ammerland), Loog (Langeoog) … Alle Apps teilen
/// diesen Code; die App-Hülle wählt ihre Marke über den Info.plist-Key `StedeBrand`.
/// Was eine Gemeinde davon zeigt, steuert zusätzlich `tenants.config.features`.
public nonisolated struct AppBrand: Sendable, Hashable, Identifiable {
    /// Wert von `StedeBrand`, etwa „stede“.
    public let id: String
    /// Name der App, wie er in Leiste und Texten steht („stede“, „loog“).
    public let displayName: String
    /// `tenants.region` der Gemeinden, die diese App zeigt.
    public let region: String
    /// Anzeigename der Region („Ammerland“).
    public let regionName: String
    /// Gemeinde vor der ersten Wahl — und die einzige, wenn es keine Wahl gibt.
    /// Ihre Inhalte liegen in den alten Ordnern ohne Gemeinde-Unterordner.
    public let defaultTenant: String
    /// Fragt die App beim ersten Start nach der Gemeinde?
    public let choosesTenant: Bool
    /// URL-Schema für Magic Link und OAuth-Rückkehr.
    public let urlScheme: String
    /// Präfix der Colorsets in `StedeUI/Resources/Colors.xcassets` („Stede“ → `StedeSand`).
    public let palette: String
    /// Bausteine, die diese App überhaupt enthält — Obergrenze für jede Gemeinde.
    public let allowedFeatures: FeatureSet
    /// Bausteine einer Gemeinde ohne `features` im Backend.
    public let defaultFeatures: FeatureSet
    /// Überschrift der Orte auf Start („Stadt“, „Insel“).
    public let placesTitle: String
    /// Fahrradläden stehen unter „Einkaufen“ statt in einer eigenen Kachel „Fahrräder“.
    public let bikesInShopping: Bool
    /// Datenschutzerklärung (Plus-Seite).
    public let privacyURL: URL?

    /// „loog+“ — Name des Bausteins `plus`, immer klein wie der App-Name.
    public var plusName: String { "\(displayName)+" }

    /// Alle `places.directory`-Schlüssel.
    public static let allDirectories: Set<String> = ["gastro", "health", "leisure", "sights", "playgrounds", "trips", "bikes", "volunteer"]
    /// Verzeichnisse ohne Ehrenamtskarte (Inseln).
    public static let islandDirectories: Set<String> = ["gastro", "health", "leisure", "sights", "playgrounds", "trips", "bikes"]

    // Neue Marken fügt der Skill `new-region-app` zwischen den Markern ein.
    // brands: start
    public static let stede = AppBrand(
        id: "stede", displayName: "stede", region: "ammerland", regionName: "Ammerland",
        defaultTenant: "stede", choosesTenant: true, urlScheme: "stede", palette: "Stede",
        allowedFeatures: FeatureSet(Set(Feature.allCases), places: allDirectories),
        defaultFeatures: FeatureSet([.weather, .calendar, .train, .bus, .waste, .groups], places: allDirectories),
        placesTitle: "Stadt", bikesInShopping: true, privacyURL: nil
    )

    /// Langeoog: eine Gemeinde, keine Wahl, keine Gruppen; Fähre, Gezeiten, Luft und loog+.
    public static let loog = AppBrand(
        id: "loog", displayName: "loog", region: "langeoog", regionName: "Langeoog",
        defaultTenant: "loog", choosesTenant: false, urlScheme: "loog", palette: "Loog",
        allowedFeatures: FeatureSet([.weather, .calendar, .ferry, .tides, .air, .plus], places: islandDirectories),
        defaultFeatures: FeatureSet([.weather, .calendar, .ferry, .tides, .air, .plus], places: islandDirectories),
        placesTitle: "Insel", bikesInShopping: true,
        privacyURL: URL(string: "https://loog.shelf.am/datenschutz.html")
    )

    /// Spiekeroog (Skill new-region-app).
    public static let spoog = AppBrand(
        id: "spoog", displayName: "spoog", region: "spiekeroog", regionName: "Spiekeroog",
        defaultTenant: "spiekeroog", choosesTenant: false, urlScheme: "spoog", palette: "Spoog",
        allowedFeatures: FeatureSet([.weather, .calendar, .ferry, .tides, .air, .plus], places: ["gastro", "health", "leisure", "playgrounds", "sights"]),
        defaultFeatures: FeatureSet([.weather, .calendar, .ferry, .tides, .air, .plus], places: ["gastro", "health", "leisure", "playgrounds", "sights"]),
        placesTitle: "Insel", bikesInShopping: false, privacyURL: URL(string: "https://loog.shelf.am/datenschutz.html")
    )

    /// Wangerooge (Skill new-region-app).
    public static let wooge = AppBrand(
        id: "wooge", displayName: "wooge", region: "wangerooge", regionName: "Wangerooge",
        defaultTenant: "wangerooge", choosesTenant: false, urlScheme: "wooge", palette: "Wooge",
        allowedFeatures: FeatureSet([.weather, .calendar, .ferry, .tides, .air, .plus], places: ["gastro", "health", "leisure", "playgrounds", "sights"]),
        defaultFeatures: FeatureSet([.weather, .calendar, .ferry, .tides, .air, .plus], places: ["gastro", "health", "leisure", "playgrounds", "sights"]),
        placesTitle: "Insel", bikesInShopping: false, privacyURL: URL(string: "https://loog.shelf.am/datenschutz.html")
    )

    public static let all: [AppBrand] = [.stede, .loog, .spoog, .wooge]
    // brands: end

    /// Die Marke dieser App; ohne Eintrag in der Info.plist stede.
    public static let current: AppBrand = {
        let id = Bundle.main.object(forInfoDictionaryKey: "StedeBrand") as? String
        return all.first { $0.id == id } ?? .stede
    }()
}
