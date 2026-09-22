import CoreLocation
import Foundation

/// Ein Fahrradladen oder -verleih in Westerstede. Wie die Gastronomie liegt die
/// Liste als `Resources/fahrradverleih.json` im Bundle — aus OpenStreetMap.
public nonisolated struct BikeRentalProvider: Identifiable, Hashable, Sendable, Decodable {
    public let id: String
    public let name: String
    public let teaser: String?
    public let phone: String?
    public let email: String?
    public let website: String?
    public let features: [String]
    public let stations: [BikeRentalStation]

    public var websiteURL: URL? {
        guard let url = website.flatMap(URL.init(string:)),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return nil }
        return url
    }

    /// Für `tel:` müssen Trennzeichen raus, sonst wählt iOS nicht.
    public var callURL: URL? {
        guard let phone else { return nil }
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel:\(digits)")
    }
}

/// Eine Ausleihstation; manche Anbieter haben mehrere.
public nonisolated struct BikeRentalStation: Hashable, Sendable, Decodable {
    public let label: String
    public let street: String
    public let latitude: Double
    public let longitude: Double

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

public nonisolated struct BikeRentalDirectory: Sendable, Decodable {
    public let source: String
    public let fetchedAt: String
    public let providers: [BikeRentalProvider]

    /// Filterkategorien: Ausstattung, die häufigste zuerst.
    public var features: [String] {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for feature in providers.flatMap(\.features) {
            if counts[feature] == nil { order.append(feature) }
            counts[feature, default: 0] += 1
        }
        return order.enumerated()
            .sorted { (counts[$0.element]!, -$0.offset) > (counts[$1.element]!, -$1.offset) }
            .map(\.element)
    }
}

public nonisolated enum BikeRentalStore {
    public static let directory: BikeRentalDirectory = {
        guard
            let url = Bundle.module.url(forResource: "fahrradverleih", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let directory = try? JSONDecoder().decode(BikeRentalDirectory.self, from: data)
        else {
            assertionFailure("fahrradverleih.json fehlt im Bundle oder ist ungültig")
            return BikeRentalDirectory(source: "", fetchedAt: "", providers: [])
        }
        return directory
    }()
}
