import CoreLocation
import Foundation

/// Ein Fahrradladen oder -verleih in Westerstede. Wie die Gastronomie liegt die
/// Liste als `Resources/fahrradverleih.json` im Bundle — aus OpenStreetMap.
nonisolated struct BikeRentalProvider: Identifiable, Hashable, Sendable, Decodable {
    let id: String
    let name: String
    let teaser: String?
    let phone: String?
    let email: String?
    let website: String?
    let features: [String]
    let stations: [BikeRentalStation]

    var websiteURL: URL? {
        guard let url = website.flatMap(URL.init(string:)),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return nil }
        return url
    }

    /// Für `tel:` müssen Trennzeichen raus, sonst wählt iOS nicht.
    var callURL: URL? {
        guard let phone else { return nil }
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel:\(digits)")
    }
}

/// Eine Ausleihstation; manche Anbieter haben mehrere.
nonisolated struct BikeRentalStation: Hashable, Sendable, Decodable {
    let label: String
    let street: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

nonisolated struct BikeRentalDirectory: Sendable, Decodable {
    let source: String
    let fetchedAt: String
    let providers: [BikeRentalProvider]

    /// Filterkategorien: Ausstattung, die häufigste zuerst.
    var features: [String] {
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

nonisolated enum BikeRentalStore {
    static let directory: BikeRentalDirectory = {
        guard
            let url = Bundle.main.url(forResource: "fahrradverleih", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let directory = try? JSONDecoder().decode(BikeRentalDirectory.self, from: data)
        else {
            assertionFailure("fahrradverleih.json fehlt im Bundle oder ist ungültig")
            return BikeRentalDirectory(source: "", fetchedAt: "", providers: [])
        }
        return directory
    }()
}
