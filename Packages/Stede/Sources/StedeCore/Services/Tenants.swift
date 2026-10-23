import Foundation
import Synchronization
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
    /// `tenants.region` — welche App die Gemeinde zeigt (`AppBrand.region`).
    public let region: String?
    /// [Breite, Länge] des Ortskerns — Wetter und Kartenmitte.
    public let center: [Double]
    /// [Süd, West, Nord, Ost] — Kartenausschnitt.
    public let bbox: [Double]
    public let stations: [Station]
    public let defaultStation: String
    public let wasteTownID: Int
    public let busDefaultStop: String
    /// Bausteine dieser Gemeinde; nil = Standard der Marke (`Features.current`).
    public let features: FeatureSet?
    /// Fähre (Baustein `ferry`).
    public let ferry: FerryConfig?
    /// Gezeiten und Pegel (Baustein `tides`).
    public let tides: TideConfig?
    /// UBA-Messstation für die Luftqualität (Baustein `air`), etwa „DENI058“.
    public let airStation: String?
    /// Hinweise unter Ortslisten je Kategorie-Schlüssel (`health`, `trips`).
    public let notes: [String: String]?
    /// Kacheln „Externe Anbieter“ auf Start, öffnen eine Website im In-App-Browser.
    public let external: [ExternalLink]?
    /// Ratsinformationssystem (Baustein `politics`).
    public let ris: RisConfig?
    /// Seepunkt vor der Insel für Wind und Seegang (`marine_forecasts`, Cron `sync-marine`).
    public let marine: MarineConfig?

    /// `{"lat": 53.80, "lon": 7.48, "name": "Seegebiet vor Langeoog"}`.
    public nonisolated struct MarineConfig: Codable, Sendable, Hashable {
        public let lat: Double
        public let lon: Double
        public let name: String?

        public init(lat: Double, lon: Double, name: String?) { self.lat = lat; self.lon = lon; self.name = name }
    }

    /// ALLRIS-net-Bürgerinfo der Gemeinde, `{"url": "https://ris.westerstede.de/bi/"}`.
    public nonisolated struct RisConfig: Codable, Sendable, Hashable {
        public let url: String

        public init(url: String) { self.url = url }
    }

    public nonisolated struct ExternalLink: Codable, Sendable, Hashable, Identifiable {
        public var id: String { url }
        public let title: String
        /// SF Symbol.
        public let symbol: String
        public let url: String
        /// Farbrolle der Kachel: „sea“, „dune“, „sun“, „heather“, „mudflat“; ohne Angabe „harbor“ (rot).
        public let tint: String?
        /// „resident“ / „tourist“: Kachel nur für diese Ansicht; ohne Angabe für alle.
        public let audience: String?

        /// Sichtbar in der gewählten Ansicht (Tourist oder Einwohner)?
        public var isVisible: Bool {
            guard let audience else { return true }
            return audience == (Audience.current ?? .resident).rawValue
        }
    }

    /// Fährverbindung über api.langeoog.de: `routes` sind die Pfade „von/nach“ (beide Richtungen),
    /// `mainland` das Hafenkürzel des Festlands — Fahrten von dort gehen „zur Insel“.
    public nonisolated struct FerryConfig: Codable, Sendable, Hashable {
        /// „api“ (Standard): Live-Fahrten über api.langeoog.de; „pdf“: fester Fahrplan, den der Server
        /// (Edge Function `sync-ferry-pdf`) aus dem PDF der Reederei liest und als `content_files`-Datei `file` ablegt.
        public let type: String?
        public let routes: [String]?
        public let mainland: String?
        /// Datei des festen Fahrplans (`content_files`-Name, Standard „ferry“).
        public let file: String?
        /// Schiffskürzel → Name, etwa „SP1“ → „Spiekeroog I“.
        public let vessels: [String: String]?
        /// „Bensersiel“ / „Langeoog“ — Umschalter im Fährplan.
        public let mainlandName: String
        public let islandName: String
        /// Vorbestellung, öffnet sich beim Tipp auf eine Fahrt.
        public let bookingURL: String?
        /// Quellenzeile unter dem Fahrplan.
        public let source: String?

        public var isTimetable: Bool { type == "pdf" }

        enum CodingKeys: String, CodingKey {
            case type, routes, mainland, source, file, vessels
            case mainlandName = "mainland_name"
            case islandName = "island_name"
            case bookingURL = "booking_url"
        }
    }

    /// Vorausberechnung als Datei im Bucket `content` (`content_files`-Name `file`, Pfad `path`),
    /// gemessene Pegel aus `water_levels` für die PEGELONLINE-Station `gauge`.
    public nonisolated struct TideConfig: Codable, Sendable, Hashable {
        public let file: String
        public let path: String
        public let gauge: String?
        public let gaugeName: String

        enum CodingKeys: String, CodingKey {
            case file, path, gauge
            case gaugeName = "gauge_name"
        }
    }

    public init(slug: String, tenantID: UUID?, municipality: String, region: String? = nil, center: [Double], bbox: [Double], stations: [Station],
                defaultStation: String, wasteTownID: Int, busDefaultStop: String, features: FeatureSet? = nil,
                ferry: FerryConfig? = nil, tides: TideConfig? = nil, airStation: String? = nil,
                notes: [String: String]? = nil, external: [ExternalLink]? = nil, ris: RisConfig? = nil, marine: MarineConfig? = nil) {
        self.slug = slug
        self.tenantID = tenantID
        self.municipality = municipality
        self.region = region
        self.center = center
        self.bbox = bbox
        self.stations = stations
        self.defaultStation = defaultStation
        self.wasteTownID = wasteTownID
        self.busDefaultStop = busDefaultStop
        self.features = features
        self.ferry = ferry
        self.tides = tides
        self.airStation = airStation
        self.notes = notes
        self.external = external
        self.ris = ris
        self.marine = marine
    }

    /// Gemeinden ohne Bahn, Bus oder Abfuhr lassen deren Felder weg.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slug = try c.decode(String.self, forKey: .slug)
        tenantID = try c.decodeIfPresent(UUID.self, forKey: .tenantID)
        municipality = try c.decode(String.self, forKey: .municipality)
        region = try c.decodeIfPresent(String.self, forKey: .region)
        center = try c.decode([Double].self, forKey: .center)
        bbox = try c.decode([Double].self, forKey: .bbox)
        stations = try c.decodeIfPresent([Station].self, forKey: .stations) ?? []
        defaultStation = try c.decodeIfPresent(String.self, forKey: .defaultStation) ?? ""
        wasteTownID = try c.decodeIfPresent(Int.self, forKey: .wasteTownID) ?? 0
        busDefaultStop = try c.decodeIfPresent(String.self, forKey: .busDefaultStop) ?? ""
        features = try c.decodeIfPresent(FeatureSet.self, forKey: .features)
        ferry = try c.decodeIfPresent(FerryConfig.self, forKey: .ferry)
        tides = try c.decodeIfPresent(TideConfig.self, forKey: .tides)
        airStation = try c.decodeIfPresent(String.self, forKey: .airStation)
        notes = try c.decodeIfPresent([String: String].self, forKey: .notes)
        external = try c.decodeIfPresent([ExternalLink].self, forKey: .external)
        ris = try c.decodeIfPresent(RisConfig.self, forKey: .ris)
        marine = try c.decodeIfPresent(MarineConfig.self, forKey: .marine)
    }

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
    public var officialName: String { slug == Tenants.bundleSlug ? "Stadt \(municipality)" : "Gemeinde \(municipality)" }
}

/// Welche Gemeinde die App gerade zeigt. Die Wahl liegt in `UserDefaults`
/// (`tenant.slug`); Stände je Gemeinde liegen in getrennten Ordnern.
public nonisolated enum Tenants {
    /// Gemeinde der Marke; ihre Inhalte liegen in den alten Ordnern ohne Unterordner.
    public static var defaultSlug: String { AppBrand.current.defaultTenant }
    /// Gemeinde, deren Daten im Bundle liegen (Westerstede).
    public static let bundleSlug = "stede"
    public static let slugKey = "tenant.slug"
    /// Wird die Gemeinde gewechselt, gelten diese Einstellungen nicht mehr.
    public static let perTenantKeys = ["bus.stop", "train.station", "train.direction", "waste.street", "waste.section", "waste.branchSection", "waste.noOrganic", "waste.fourWeekly"]

    public static var currentSlug: String {
        guard AppBrand.current.choosesTenant else { return defaultSlug }
        return UserDefaults.standard.string(forKey: slugKey) ?? defaultSlug
    }

    /// Hat der Nutzer schon eine Gemeinde gewählt? Sonst fragt die App beim Start.
    public static var hasChosen: Bool {
        !AppBrand.current.choosesTenant || UserDefaults.standard.string(forKey: slugKey) != nil
    }

    /// Westerstede hat die Daten im Bundle; alle anderen nur aus dem Backend.
    public static var usesBundle: Bool { currentSlug == bundleSlug }

    /// Views fragen `Features` bei jedem Rendern ab — die Liste wird daher nur einmal
    /// von der Platte gelesen und nach `refresh()` neu.
    public static var all: [TenantConfig] {
        loaded.withLock { list in
            if let list { return list }
            let fresh = readCache() ?? bundled
            list = fresh
            return fresh
        }
    }

    private static let loaded = Mutex<[TenantConfig]?>(nil)

    private static func readCache() -> [TenantConfig]? {
        guard let data = try? Data(contentsOf: cacheURL),
              let list = try? JSONDecoder().decode([TenantConfig].self, from: data), !list.isEmpty else { return nil }
        return list
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
            let features: FeatureSet?
            let ferry: TenantConfig.FerryConfig?
            let tides: TenantConfig.TideConfig?
            let airStation: String?
            let notes: [String: String]?
            let external: [TenantConfig.ExternalLink]?
            let ris: TenantConfig.RisConfig?
            let marine: TenantConfig.MarineConfig?
            enum CodingKeys: String, CodingKey {
                case center, bbox, stations, features, ferry, tides, notes, external, ris, marine
                case airStation = "air_station"
                case defaultStation = "default_station"
                case wasteTownId = "waste_town_id"
                case busDefaultStop = "bus_default_stop"
            }
        }
    }

    /// Lädt die Gemeinden der Region der Marke neu; ohne Netz bleibt der letzte Stand.
    public static func refresh() async {
        do {
            let rows: [Row] = try await Backend.client.from("tenants").select("id, slug, municipality, config")
                .eq("region", value: AppBrand.current.region).order("municipality").execute().value
            let list = rows.compactMap { row -> TenantConfig? in
                let c = row.config
                guard let center = c.center, let bbox = c.bbox else { return nil }
                return TenantConfig(slug: row.slug, tenantID: row.id, municipality: row.municipality, region: AppBrand.current.region, center: center, bbox: bbox,
                                    stations: c.stations ?? [], defaultStation: c.defaultStation ?? "", wasteTownID: c.wasteTownId ?? 0,
                                    busDefaultStop: c.busDefaultStop ?? "", features: c.features,
                                    ferry: c.ferry, tides: c.tides, airStation: c.airStation, notes: c.notes, external: c.external, ris: c.ris, marine: c.marine)
            }
            guard !list.isEmpty else { return }
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(list).write(to: cacheURL, options: .atomic)
            loaded.withLock { $0 = list }
        } catch {
            // Offline: Bundle oder letzter Stand.
        }
    }

    static let bundled: [TenantConfig] = {
        guard let url = Bundle.module.url(forResource: "tenants", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([TenantConfig].self, from: data).filter({ $0.region == AppBrand.current.region }), !list.isEmpty
        else {
            assertionFailure("tenants.json fehlt im Bundle")
            return [TenantConfig(slug: bundleSlug, tenantID: nil, municipality: "Westerstede", center: [53.25752, 7.92734], bbox: [53.15, 7.78, 53.36, 8.10],
                                 stations: [.init(id: "8004610", dbf: "Westerstede-Ocholt", name: "Westerstede-Ocholt", directions: ["Oldenburg", "Leer"])],
                                 defaultStation: "8004610", wasteTownID: 5, busDefaultStop: "009098661")]
        }
        return list
    }()
}

/// Zähler für frisch synchronisierte Inhalte: nach `bump()` lesen alle `TenantScoped`-Werte
/// beim nächsten Zugriff neu ein — so erscheinen Orte, Karte und Haltestellen ohne Neustart.
public nonisolated enum ContentGeneration {
    private static let counter = Mutex(0)
    public static var value: Int { counter.withLock { $0 } }
    public static func bump() { counter.withLock { $0 += 1 } }
}

/// Ein Wert, der je Gemeinde einmal geladen wird und beim Wechsel oder nach einem Abgleich neu.
public nonisolated final class TenantScoped<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private let load: @Sendable () -> Value
    private var cached: (slug: String, generation: Int, value: Value)?

    public init(_ load: @escaping @Sendable () -> Value) {
        self.load = load
    }

    public var value: Value {
        let slug = Tenants.currentSlug
        let generation = ContentGeneration.value
        lock.lock()
        defer { lock.unlock() }
        if let cached, cached.slug == slug, cached.generation == generation { return cached.value }
        let value = load()
        cached = (slug, generation, value)
        return value
    }
}
