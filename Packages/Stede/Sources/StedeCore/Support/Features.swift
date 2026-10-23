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
/// Wer die App nutzt: Touristen sehen alles Öffentliche, aber keine Abfuhr, keine Politik
/// und keine Gruppen; Einwohner alles, was die Gemeinde hat. Gewählt im Onboarding,
/// änderbar unter Einstellungen (`UserDefaults` `audience`).
public nonisolated enum Audience: String, CaseIterable, Sendable {
    case tourist, resident

    public static let key = "audience"

    /// nil, solange der Nutzer noch nicht gewählt hat — dann erscheint der Wizard.
    public static var current: Audience? {
        UserDefaults.standard.string(forKey: key).flatMap(Audience.init(rawValue:))
    }

    public static func select(_ audience: Audience) {
        UserDefaults.standard.set(audience.rawValue, forKey: key)
    }

    public var title: String {
        switch self {
        case .tourist: "Zu Besuch"
        case .resident: "Ich wohne hier"
        }
    }

    public var symbol: String {
        switch self {
        case .tourist: "suitcase.rolling.fill"
        case .resident: "house.fill"
        }
    }

    /// Bausteine, die diese Ansicht nie zeigt.
    public var hiddenFeatures: Set<Feature> {
        switch self {
        case .tourist: [.waste, .politics, .groups]
        case .resident: []
        }
    }
}

public nonisolated enum Features {
    public static var current: FeatureSet {
        let brand = AppBrand.current
        var set = (Tenants.current.features ?? brand.defaultFeatures).intersection(brand.allowedFeatures)
        // Ohne Wahl gilt Einwohner — der Wizard fragt ohnehin, bevor jemand etwas sieht.
        set.enabled.subtract((Audience.current ?? .resident).hiddenFeatures)
        return set
    }

    public static func has(_ feature: Feature) -> Bool { current.enabled.contains(feature) }

    /// Mindestens eines der Verzeichnisse ist an.
    public static func hasPlaces(_ directories: Set<String>) -> Bool { !current.places.isDisjoint(with: directories) }
}

/// Einstellung „Termine der Region“ (`UserDefaults` `events.region`), nur wo die Marke sie anbietet.
public nonisolated enum RegionEvents {
    public static let key = "events.region"

    public static var isOn: Bool {
        AppBrand.current.offersRegionEvents && UserDefaults.standard.bool(forKey: key)
    }
}
