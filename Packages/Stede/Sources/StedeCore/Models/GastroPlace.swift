import CoreLocation
import Foundation

/// Ein Betrieb in Westerstede. Die Daten kommen nicht live aus dem Netz,
/// sondern liegen als `Resources/gastronomie.json` im Bundle — aus
/// OpenStreetMap übernommen und von Hand nachbearbeitet.
public nonisolated struct GastroPlace: Identifiable, Hashable, Sendable, Decodable {
    public let id: String
    public let name: String
    public let category: String
    public let teaser: String?
    public let street: String?
    public let phone: String?
    public let email: String?
    public let website: String?
    /// Herkunftsnachweis; die App verlinkt die Seite nicht mehr.
    public let detailURL: String?
    /// Öffnungszeiten und Ruhetag, von Hand von den Websites der Betriebe
    /// übernommen — kurzer Anzeigetext, saisonal kann es abweichen.
    public let hours: String?
    public let restDay: String?
    public let seasonNote: String?
    /// Bildnachweis für Fotos unter freier Lizenz (Wikimedia Commons).
    public let imageCredit: String?
    /// Zusätzlicher Link neben der Website, z. B. das Kinoprogramm als PDF.
    public let extraLinkTitle: String?
    public let extraLinkURL: String?

    public var extraURL: URL? {
        extraLinkURL.flatMap(URL.init(string:))
    }
    /// Einmalig per OpenStreetMap aus der Adresse ermittelt.
    public let latitude: Double?
    public let longitude: Double?

    public init(id: String, name: String, category: String, teaser: String?, street: String?, phone: String?, email: String?, website: String?, detailURL: String?, hours: String?, restDay: String?, seasonNote: String?, imageCredit: String?, extraLinkTitle: String?, extraLinkURL: String?, latitude: Double?, longitude: Double?) {
        self.id = id; self.name = name; self.category = category; self.teaser = teaser; self.street = street
        self.phone = phone; self.email = email; self.website = website; self.detailURL = detailURL
        self.hours = hours; self.restDay = restDay; self.seasonNote = seasonNote; self.imageCredit = imageCredit
        self.extraLinkTitle = extraLinkTitle; self.extraLinkURL = extraLinkURL; self.latitude = latitude; self.longitude = longitude
    }

    public var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Nur echte Web-Adressen — im Datensatz stand vereinzelt „#".
    public var websiteURL: URL? {
        guard let url = website.flatMap(URL.init(string:)),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return nil }
        return url
    }

    /// Bild im Bundle: `gastro-<id>.jpg` oder `sight-<id>.jpg`, falls vorhanden —
    /// derzeit liegen keine Fotos bei.
    public var imageURL: URL? {
        Bundle.module.url(forResource: "gastro-\(id)", withExtension: "jpg")
            ?? Bundle.module.url(forResource: "sight-\(id)", withExtension: "jpg")
    }

    /// Für `tel:` müssen Trennzeichen raus, sonst wählt iOS nicht.
    public var callURL: URL? {
        guard let phone else { return nil }
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel:\(digits)")
    }
}

public nonisolated struct GastroDirectory: Sendable, Decodable {
    public let source: String
    public let fetchedAt: String
    public let places: [GastroPlace]

    public init(source: String, fetchedAt: String, places: [GastroPlace]) {
        self.source = source; self.fetchedAt = fetchedAt; self.places = places
    }

    /// Reihenfolge der Kategorien wie im JSON — Restaurants zuerst.
    public var categories: [String] {
        var seen = Set<String>()
        return places.compactMap { seen.insert($0.category).inserted ? $0.category : nil }
    }

    public func places(in category: String) -> [GastroPlace] {
        places.filter { $0.category == category }
    }
}

public nonisolated enum GastroStore {
    public static let directory = load("gastronomie", synced: "gastro")

    /// Sehenswürdigkeiten nutzen dasselbe Format — Name, Text, Adresse,
    /// Koordinate — und liegen in `sehenswuerdigkeiten.json`.
    public static let sights = load("sehenswuerdigkeiten", synced: "sights")

    /// Ärzte, Zahnärzte, Apotheken, Kliniken — Kategorie „Gesundheit" unter „Stadt".
    public static let health = load("gesundheit", synced: "health")

    /// Bad, Sport, Spiel & Familie, Kultur — Kategorie „Freizeit & Sport".
    public static let leisure = load("freizeit", synced: "leisure")

    /// Parks, Draisine, Zwischenahner Meer, Radrouten — „Ausflüge".
    public static let trips = load("ausfluege", synced: "trips")

    /// Vergünstigungen der Ehrenamtskarte Niedersachsen/Bremen in Westerstede — „Ehrenamt".
    public static let volunteer = load("ehrenamt", synced: "volunteer")

    /// Die 34 städtischen Spielplätze samt Kinderrat-Bewertung — „Spielplätze".
    public static let playgrounds = load("spielplaetze", synced: "playgrounds")

    /// Fällt auf ein leeres Verzeichnis zurück; ohne Netzabhängigkeit kann
    /// hier nur ein Fehler beim Bundling auftreten.
    /// Stand aus dem Backend-Sync, sonst das Bundle. Wird beim App-Start
    /// einmal gelesen; ein frischer Sync wirkt beim nächsten Start.
    private static func load(_ resource: String, synced: String) -> GastroDirectory {
        if let synced = ContentSync.directory(synced), !synced.places.isEmpty { return synced }
        guard
            let url = Bundle.module.url(forResource: resource, withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let directory = try? JSONDecoder().decode(GastroDirectory.self, from: data)
        else {
            assertionFailure("\(resource).json fehlt im Bundle oder ist ungültig")
            return GastroDirectory(source: "", fetchedAt: "", places: [])
        }
        return directory
    }
}
