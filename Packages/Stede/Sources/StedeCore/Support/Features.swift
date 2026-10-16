import Foundation

/// Ein Baustein, den eine Gemeinde zeigen kann. Schlüssel wie in `tenants.config.features`.
public nonisolated enum Feature: String, Codable, Sendable, CaseIterable {
    case weather, calendar, train, bus, waste, ferry, tides, air, groups, plus
    /// Politik: Sitzungen und Vorlagen aus dem Ratsinformationssystem (`tenants.config.ris`).
    case politics
}

/// Was eine Gemeinde zeigt (`tenants.config.features`), etwa
/// `{"weather": true, "train": true, "places": ["gastro", "sights"]}`.
/// Fehlt ein Schlüssel, ist der Baustein aus. Fehlt `features` ganz (alter Cache,
/// Gemeinde ohne Eintrag), gelten die Standards der Marke.
public nonisolated struct FeatureSet: Codable, Sendable, Hashable {
    public var enabled: Set<Feature>
    /// `places.directory`-Schlüssel: gastro, health, leisure, sights, playgrounds, trips, bikes, volunteer.
    public var places: Set<String>

    public init(_ enabled: Set<Feature>, places: Set<String>) {
        self.enabled = enabled
        self.places = places
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        var enabled = Set<Feature>()
        for feature in Feature.allCases {
            if (try? container.decode(Bool.self, forKey: DynamicKey(feature.rawValue))) == true { enabled.insert(feature) }
        }
        self.enabled = enabled
        places = Set((try? container.decode([String].self, forKey: DynamicKey("places"))) ?? [])
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        for feature in enabled { try container.encode(true, forKey: DynamicKey(feature.rawValue)) }
        try container.encode(places.sorted(), forKey: DynamicKey("places"))
    }

    /// Nur, was beide erlauben — so kann eine Marke Bausteine sperren, die eine Gemeinde hätte.
    public func intersection(_ other: FeatureSet) -> FeatureSet {
        FeatureSet(enabled.intersection(other.enabled), places: places.intersection(other.places))
    }

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}

/// Die Bausteine der laufenden App: Gemeinde ∩ Marke.
public nonisolated enum Features {
    public static var current: FeatureSet {
        let brand = AppBrand.current
        return (Tenants.current.features ?? brand.defaultFeatures).intersection(brand.allowedFeatures)
    }

    public static func has(_ feature: Feature) -> Bool { current.enabled.contains(feature) }

    /// Mindestens eines der Verzeichnisse ist an.
    public static func hasPlaces(_ directories: Set<String>) -> Bool { !current.places.isDisjoint(with: directories) }
}
