import Foundation

/// Die Gemeinde als eigene Karte aus OpenStreetMap-Daten (`inselkarte.json`):
/// Siedlung, Wiesen, Wald, Wasser, Gebäude, Straßen, Wege und Bahn — offline, ohne
/// Apple-Kartenkacheln. Einmalig per Overpass geladen und vereinfacht.
public nonisolated struct IslandMapData: Decodable, Sendable {
    public let attribution: String
    public let land: [[[Double]]]
    public let polygons: [String: [[[Double]]]]
    public let buildings: [[[Double]]]
    public let lines: [String: [[[Double]]]]
    /// Karte mit Küstenlinie (Inseln): außerhalb von `land` ist Meer. Ältere Dateien ohne den Schlüssel
    /// erkennt `hasSea` daran, dass `land` mehr ist als das Rechteck des Kartenausschnitts.
    public let sea: Bool?

    public var hasSea: Bool { sea ?? (land.count > 1 || (land.first?.count ?? 0) > 5) }

    public static var shared: IslandMapData? { store.value }

    private static let store = TenantScoped { () -> IslandMapData? in
        // Stand aus dem Backend (`content_files`), sonst das Bundle.
        if let data = ContentFiles.data("inselkarte"), let map = try? JSONDecoder().decode(IslandMapData.self, from: data) {
            return map
        }
        guard
            Tenants.usesBundle,
            let url = Bundle.module.url(forResource: "inselkarte", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(IslandMapData.self, from: data)
    }
}

