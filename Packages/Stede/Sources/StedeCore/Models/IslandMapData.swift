import Foundation

/// Westerstede als eigene Karte aus OpenStreetMap-Daten (`inselkarte.json`):
/// Siedlung, Wiesen, Wald, Wasser, Gebäude, Straßen, Wege und Bahn — offline, ohne
/// Apple-Kartenkacheln. Einmalig per Overpass geladen und vereinfacht.
public nonisolated struct IslandMapData: Decodable, Sendable {
    public let attribution: String
    public let land: [[[Double]]]
    public let polygons: [String: [[[Double]]]]
    public let buildings: [[[Double]]]
    public let lines: [String: [[[Double]]]]

    public static let shared: IslandMapData? = {
        guard
            let url = Bundle.module.url(forResource: "inselkarte", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(IslandMapData.self, from: data)
    }()
}

