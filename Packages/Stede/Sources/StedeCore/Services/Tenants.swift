import Foundation
import Supabase

/// Eine Gemeinde im Ammerland mit allem, was die App je Gemeinde anders macht
/// (`tenants.config` im Backend, Erststand in `Resources/tenants.json`).
public nonisolated struct TenantConfig: Codable, Sendable, Hashable, Identifiable {
    public var id: String { slug }
    public let slug: String
    /// `tenants.id` — für Termine, die nur in bestimmten Gemeinden erscheinen.
    public let tenantID: UUID?
    /// „Westerstede", „Bad Zwischenahn" …
    public let municipality: String
    /// [Breite, Länge] des Ortskerns — Wetter und Kartenmitte.
    public let center: [Double]
    /// [Süd, West, Nord, Ost] — Kartenausschnitt.
    public let bbox: [Double]
    public let stations: [Station]
    public let defaultStation: String
    public let wasteTownID: Int
    public let busDefaultStop: String

    public nonisolated struct Station: Codable, Sendable, Hashable, Identifiable {
        /// EVA-Nummer.
        public let id: String
        /// Name im Abfahrtsmonitor dbf.finalrewind.org.
        public let dbf: String
        public let name: String
        /// [Richtung Oldenburg, Gegenrichtung], etwa ["Oldenburg", "Leer"].
        public let directions: [String]
    }

    public var latitude: Double { center.first ?? 53.2575 }
    public var longitude: Double { center.count > 1 ? center[1] : 7.9273 }

    public func station(id: String?) -> Station? {
        stations.first { $0.id == id } ?? stations.first { $0.id == defaultStation } ?? stations.first
    }

    /// „Stadt Westerstede", sonst „Gemeinde …".
    public var officialName: String { slug == Tenants.defaultSlug ? "Stadt \(municipality)" : "Gemeinde \(municipality)" }
}

/// Welche Gemeinde die App gerade zeigt. Die Wahl liegt in `UserDefaults`
/// (`tenant.slug`); Stände je Gemeinde liegen in getrennten Ordnern.
public nonisolated enum Tenants {
    public static let defaultSlug = "stede"
    public static let slugKey = "tenant.slug"
    /// Wird die Gemeinde gewechselt, gelten diese Einstellungen nicht mehr.
    public static let perTenantKeys = ["bus.stop", "train.station", "train.direction", "waste.street", "waste.section", "waste.branchSection"]

    public static var currentSlug: String {
        UserDefaults.standard.string(forKey: slugKey) ?? defaultSlug
    }

    /// Hat der Nutzer schon eine Gemeinde gewählt? Sonst fragt die App beim Start.
    public static var hasChosen: Bool {
        UserDefaults.standard.string(forKey: slugKey) != nil
    }

    /// Westerstede hat die Daten im Bundle; alle anderen nur aus dem Backend.
    public static var usesBundle: Bool { currentSlug == defaultSlug }

    public static var all: [TenantConfig] {
        if let data = try? Data(contentsOf: cacheURL),
           let list = try? JSONDecoder().decode([TenantConfig].self, from: data), !list.isEmpty {
            return list
        }
        return bundled
    }

    public static var current: TenantConfig {
        let slug = currentSlug
        return all.first { $0.slug == slug } ?? bundled.first { $0.slug == slug } ?? bundled[0]
    }

    /// Ordner für Inhalte einer Gemeinde; Westerstede behält den alten Ort.
    public static func contentFolder(_ slug: String = currentSlug) -> URL {
        let base = CacheMaintenance.directory("content")
        return slug == defaultSlug ? base : base.appendingPathComponent("tenants/\(slug)", isDirectory: true)
    }

    /// Setzt die Gemeinde und verwirft, was nur zur alten passte.
    public static func select(_ slug: String) {
        let defaults = UserDefaults.standard
        let changed = defaults.string(forKey: slugKey) != slug
        defaults.set(slug, forKey: slugKey)
        guard changed else { return }
        perTenantKeys.forEach { defaults.removeObject(forKey: $0) }
    }

    // MARK: Backend

    private static var cacheURL: URL { CacheMaintenance.directory("content").appendingPathComponent("tenants.json") }

    private nonisolated struct Row: Decodable, Sendable {
        let id: UUID
        let slug: String
        let municipality: String
        let config: Config
        nonisolated struct Config: Decodable, Sendable {
            let center: [Double]?
            let bbox: [Double]?
            let stations: [TenantConfig.Station]?
            let defaultStation: String?
            let wasteTownId: Int?
            let busDefaultStop: String?
            enum CodingKeys: String, CodingKey {
                case center, bbox, stations
                case defaultStation = "default_station"
                case wasteTownId = "waste_town_id"
                case busDefaultStop = "bus_default_stop"
            }
        }
    }

    /// Lädt die Gemeinden der Region neu; ohne Netz bleibt der letzte Stand.
    public static func refresh() async {
        do {
            let rows: [Row] = try await Backend.client.from("tenants").select("id, slug, municipality, config")
                .eq("region", value: "ammerland").order("municipality").execute().value
            let list = rows.compactMap { row -> TenantConfig? in
                let c = row.config
                guard let center = c.center, let bbox = c.bbox, let stations = c.stations, let station = c.defaultStation,
                      let town = c.wasteTownId, let stop = c.busDefaultStop else { return nil }
                return TenantConfig(slug: row.slug, tenantID: row.id, municipality: row.municipality, center: center, bbox: bbox, stations: stations,
                                    defaultStation: station, wasteTownID: town, busDefaultStop: stop)
            }
            guard !list.isEmpty else { return }
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(list).write(to: cacheURL, options: .atomic)
        } catch {
            // Offline: Bundle oder letzter Stand.
        }
    }

    private static let bundled: [TenantConfig] = {
        guard let url = Bundle.module.url(forResource: "tenants", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([TenantConfig].self, from: data), !list.isEmpty
        else {
            assertionFailure("tenants.json fehlt im Bundle")
            return [TenantConfig(slug: defaultSlug, tenantID: nil, municipality: "Westerstede", center: [53.25752, 7.92734], bbox: [53.15, 7.78, 53.36, 8.10],
                                 stations: [.init(id: "8004610", dbf: "Westerstede-Ocholt", name: "Westerstede-Ocholt", directions: ["Oldenburg", "Leer"])],
                                 defaultStation: "8004610", wasteTownID: 5, busDefaultStop: "009098661")]
        }
        return list
    }()
}

/// Ein Wert, der je Gemeinde einmal geladen wird und beim Wechsel neu.
public nonisolated final class TenantScoped<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private let load: @Sendable () -> Value
    private var cached: (slug: String, value: Value)?

    public init(_ load: @escaping @Sendable () -> Value) {
        self.load = load
    }

    public var value: Value {
        let slug = Tenants.currentSlug
        lock.lock()
        defer { lock.unlock() }
        if let cached, cached.slug == slug { return cached.value }
        let value = load()
        cached = (slug, value)
        return value
    }
}
