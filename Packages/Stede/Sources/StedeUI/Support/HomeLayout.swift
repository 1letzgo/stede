import StedeCore
import SwiftUI

/// Bereiche der Startseite, in der gewählten Reihenfolge.
enum HomeSection: String, CaseIterable, Identifiable {
    case sea
    case transit
    case home
    case city
    case politics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sea: "Meer & Fähre"
        case .transit: "Unterwegs"
        case .home: "Zuhause"
        case .city: AppBrand.current.placesTitle
        case .politics: "Politik"
        }
    }

    var symbol: String {
        switch self {
        case .sea: "water.waves"
        case .transit: "tram.fill"
        case .home: "house.fill"
        case .city: "map.fill"
        case .politics: "building.columns.fill"
        }
    }

    /// Kacheln in Standardreihenfolge; die gewählte liefert `HomeLayout.tiles(in:order:)`.
    var tiles: [HomeTileID] { HomeTileID.available.filter { $0.section == self } }
}

/// Einzelne Kachel der Startseite, ein- und ausblendbar.
enum HomeTileID: String, CaseIterable, Identifiable {
    case tides, ferry, train, bus, waste, discover, gastro, shopping, bikes, playgrounds, health, volunteer
    case sessions, papers

    var id: String { rawValue }

    var section: HomeSection {
        switch self {
        case .tides, .ferry: .sea
        case .train, .bus: .transit
        case .waste: .home
        case .sessions, .papers: .politics
        default: .city
        }
    }

    /// Kategorie der Rubrik „Stadt“, nil für Gezeiten, Fähre, Bahn, Bus und Abfuhr.
    var category: String? {
        switch self {
        case .discover: IslandCatalog.discoverCategory
        case .gastro: IslandCatalog.gastroCategory
        case .shopping: IslandCatalog.shoppingCategory
        case .bikes: IslandCatalog.bikeCategory
        case .playgrounds: IslandCatalog.playgroundsCategory
        case .health: IslandCatalog.healthCategory
        case .volunteer: IslandCatalog.volunteerCategory
        default: nil
        }
    }

    var title: String {
        switch self {
        case .tides: "Gezeiten"
        case .ferry: "Fähre"
        case .train: "Bahn"
        case .bus: "Bus"
        case .waste: "Abfuhr"
        case .sessions: "Sitzungen"
        case .papers: "Vorlagen"
        default: category.map(IslandCatalog.tileTitle(for:)) ?? rawValue
        }
    }

    var symbol: String {
        switch self {
        case .tides: "water.waves"
        case .ferry: "ferry.fill"
        case .train: "tram.fill"
        case .bus: "bus.fill"
        case .waste: "trash.fill"
        case .sessions: "person.3.fill"
        case .papers: "doc.text.fill"
        default: category.map(IslandCatalog.symbol(for:)) ?? "square"
        }
    }

    /// Hat die Gemeinde den Baustein? Sonst gibt es die Kachel nicht — auch nicht in den Einstellungen.
    var isAvailable: Bool {
        switch self {
        case .tides: Features.has(.tides)
        case .ferry: Features.has(.ferry)
        case .train: Features.has(.train)
        case .bus: Features.has(.bus)
        case .waste: Features.has(.waste)
        case .discover: Features.hasPlaces(["sights", "leisure", "trips"])
        case .gastro: Features.hasPlaces(["gastro"])
        case .shopping: Features.hasPlaces(["gastro", "bikes"])
        case .bikes: Features.hasPlaces(["bikes"]) && !AppBrand.current.bikesInShopping
        case .playgrounds: Features.hasPlaces(["playgrounds"])
        case .health: Features.hasPlaces(["health"])
        case .volunteer: Features.hasPlaces(["volunteer"])
        case .sessions, .papers: Features.has(.politics) && Tenants.current.ris != nil
        }
    }

    static var available: [HomeTileID] { allCases.filter(\.isAvailable) }

    var tint: Color {
        switch self {
        case .tides: StedeTheme.seaTeal
        case .ferry: StedeTheme.harborRed
        case .train: StedeTheme.harborRed
        case .bus: StedeTheme.seaTeal
        case .waste: StedeTheme.duneGreen
        case .sessions: StedeTheme.seaTeal
        case .papers: StedeTheme.sunAmber
        default: category.map(IslandCatalog.color(for:)) ?? StedeTheme.ink
        }
    }
}

/// Liest und schreibt die Startseiten-Einstellungen (UserDefaults `home.order`, `home.hidden`,
/// kommagetrennt). Die Views halten die `@AppStorage`-Strings selbst, damit Änderungen sofort greifen.
enum HomeLayout {
    static let orderKey = "home.order"
    static let hiddenKey = "home.hidden"
    static let tilesKey = "home.tiles"
    /// Optionale Kacheln (vorerst Ehrenamt) sind anfangs ausgeblendet.
    static let defaultHidden = HomeTileID.volunteer.rawValue
    static let defaultOrder = HomeSection.allCases.map(\.rawValue).joined(separator: ",")

    /// Unbekannte Einträge fallen weg, fehlende Bereiche kommen hinten dazu.
    static func order(_ raw: String) -> [HomeSection] {
        var sections = raw.split(separator: ",").compactMap { HomeSection(rawValue: String($0)) }
        for section in HomeSection.allCases where !sections.contains(section) { sections.append(section) }
        // Bereiche ohne Baustein (Bahn, Bus, Abfuhr fehlen der Gemeinde) gibt es nicht.
        return sections.filter { !$0.tiles.isEmpty }
    }

    static func encode(_ order: [HomeSection]) -> String {
        order.map(\.rawValue).joined(separator: ",")
    }

    /// Reihenfolge aller Kacheln; unbekannte fallen weg, fehlende kommen hinten dazu.
    static func tileOrder(_ raw: String) -> [HomeTileID] {
        var tiles = raw.split(separator: ",").compactMap { HomeTileID(rawValue: String($0)) }
        for tile in HomeTileID.allCases where !tiles.contains(tile) { tiles.append(tile) }
        return tiles
    }

    static func tiles(in section: HomeSection, order raw: String) -> [HomeTileID] {
        tileOrder(raw).filter { $0.section == section && $0.isAvailable }
    }

    /// Kacheln eines Bereichs verschieben, die anderen Bereiche bleiben unberührt.
    static func moveTiles(in section: HomeSection, order raw: String, from: IndexSet, to: Int) -> String {
        var sectionTiles = tiles(in: section, order: raw)
        sectionTiles.move(fromOffsets: from, toOffset: to)
        let others = tileOrder(raw).filter { $0.section != section }
        return (others + sectionTiles).map(\.rawValue).joined(separator: ",")
    }

    static func hidden(_ raw: String) -> Set<HomeTileID> {
        Set(raw.split(separator: ",").compactMap { HomeTileID(rawValue: String($0)) })
    }

    static func encode(_ hidden: Set<HomeTileID>) -> String {
        HomeTileID.allCases.filter(hidden.contains).map(\.rawValue).joined(separator: ",")
    }
}
