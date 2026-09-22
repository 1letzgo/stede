import Foundation

nonisolated struct AirHour: Identifiable, Hashable, Sendable, Codable {
    var id: Date { start }
    let start: Date
    let end: Date
    let totalIndex: Int
    let incomplete: Bool
    let pollutants: [AirPollutant]

    var indexLevel: AirIndexLevel {
        AirIndexLevel(rawValue: totalIndex) ?? .unknown
    }

    func value(for component: Int) -> Double? {
        pollutants.first { $0.componentId == component }?.value
    }
}

nonisolated struct AirPollutant: Hashable, Sendable, Codable {
    let componentId: Int
    let value: Double
    let index: Int

    var name: String {
        switch componentId {
        case 1: "PM10"
        case 3: "O₃"
        case 4: "SO₂"
        case 5: "NO₂"
        case 9: "PM2,5"
        default: "Komponente \(componentId)"
        }
    }

    var unit: String { "µg/m³" }

    var indexLevel: AirIndexLevel {
        AirIndexLevel(rawValue: index) ?? .unknown
    }
}

nonisolated enum AirIndexLevel: Int, Sendable {
    case veryGood = 1
    case good = 2
    case moderate = 3
    case poor = 4
    case veryPoor = 5
    case unknown = 0

    var label: String {
        switch self {
        case .veryGood: "Sehr gut"
        case .good: "Gut"
        case .moderate: "Mäßig"
        case .poor: "Schlecht"
        case .veryPoor: "Sehr schlecht"
        case .unknown: "Unbekannt"
        }
    }
}

extension AirHour {
    var displayPollutants: [AirPollutant] {
        let order = [1, 9, 5, 3]
        return order.compactMap { id in pollutants.first { $0.componentId == id } }
    }
}

nonisolated enum UBADateParser: Sendable {
    static func date(from raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 3600)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = formatter.date(from: raw) {
            return date
        }
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: raw)
    }
}
