import StedeCore
import SwiftUI

/// Bereiche der Startseite, in der gewählten Reihenfolge.
enum HomeSection: String, CaseIterable, Identifiable {
    case transit
    case home
    case city

    var id: String { rawValue }

    var title: String {
        switch self {
        case .transit: "Unterwegs"
        case .home: "Zuhause"
        case .city: "Stadt"
        }
    }

    var symbol: String {
        switch self {
        case .transit: "tram.fill"
        case .home: "house.fill"
        case .city: "map.fill"
        }
    }

    /// Kacheln in Standardreihenfolge; die gewählte liefert `HomeLayout.tiles(in:order:)`.
    var tiles: [HomeTileID] { HomeTileID.allCases.filter { $0.section == self } }
}

/// Einzelne Kachel der Startseite, ein- und ausblendbar.
enum HomeTileID: String, CaseIterable, Identifiable {
    case train, bus, waste, discover, gastro, shopping, playgrounds, trips, health

    var id: String { rawValue }

    var section: HomeSection {
        switch self {
        case .train, .bus: .transit
        case .waste: .home
        default: .city
        }
    }

    /// Kategorie der Rubrik „Stadt“, nil für Bahn, Bus und Abfuhr.
    var category: String? {
        switch self {
        case .discover: IslandCatalog.discoverCategory
        case .gastro: IslandCatalog.gastroCategory
        case .shopping: IslandCatalog.shoppingCategory
        case .playgrounds: IslandCatalog.playgroundsCategory
        case .trips: IslandCatalog.tripsCategory
        case .health: IslandCatalog.healthCategory
        default: nil
        }
    }

    var title: String {
        switch self {
        case .train: "Bahn"
        case .bus: "Bus"
        case .waste: "Abfuhr"
        default: category.map(IslandCatalog.tileTitle(for:)) ?? rawValue
        }
    }

    var symbol: String {
        switch self {
        case .train: "tram.fill"
        case .bus: "bus.fill"
        case .waste: "trash.fill"
        default: category.map(IslandCatalog.symbol(for:)) ?? "square"
        }
    }

    var tint: Color {
        switch self {
        case .train: StedeTheme.harborRed
        case .bus: StedeTheme.seaTeal
        case .waste: StedeTheme.duneGreen
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
    static let defaultOrder = HomeSection.allCases.map(\.rawValue).joined(separator: ",")

    /// Unbekannte Einträge fallen weg, fehlende Bereiche kommen hinten dazu.
    static func order(_ raw: String) -> [HomeSection] {
        var sections = raw.split(separator: ",").compactMap { HomeSection(rawValue: String($0)) }
        for section in HomeSection.allCases where !sections.contains(section) { sections.append(section) }
        return sections
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
        tileOrder(raw).filter { $0.section == section }
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
