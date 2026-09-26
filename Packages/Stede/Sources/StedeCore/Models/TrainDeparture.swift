import Foundation

/// Fahrtrichtung ab einem Ammerland-Bahnhof — jede Strecke hat zwei Enden:
/// Oldenburg und die Gegenrichtung (Leer, ab Rastede Wilhelmshaven).
/// Rohwert als String, damit die Wahl per `@AppStorage` gespeichert werden kann;
/// „leer" bleibt der Rohwert der Gegenrichtung, damit alte Einstellungen gelten.
public nonisolated enum TrainDirection: String, CaseIterable, Hashable, Sendable, Codable {
    case oldenburg
    case leer

    /// „Oldenburg", „Leer" oder „Wilhelmshaven" — je nach Bahnhof.
    public func shortTitle(at station: TenantConfig.Station) -> String {
        let names = station.directions
        switch self {
        case .oldenburg: return names.first ?? "Oldenburg"
        case .leer: return names.count > 1 ? names[1] : "Leer"
        }
    }

    public func title(at station: TenantConfig.Station) -> String {
        "Richtung \(shortTitle(at: station))"
    }
}

/// Eine Abfahrt an einem Ammerland-Bahnhof, wie sie der Abfahrtsmonitor
/// dbf.finalrewind.org (DB IRIS) liefert.
public nonisolated struct TrainDeparture: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let scheduled: Date
    public let delayMinutes: Int
    public let platform: String?
    public let scheduledPlatform: String?
    /// Linie oder Zugname, etwa „RE1", „RE IC56" oder „IC 2432".
    public let line: String
    public let destination: String
    /// Nächste Halte ab hier, ohne den eigenen Bahnhof.
    public let via: [String]
    public let direction: TrainDirection
    public let isCancelled: Bool
    /// Meldungen zu Verspätung und Qualität („Verspätung eines vorausfahrenden Zuges“).
    public let notes: [String]

    /// Voraussichtliche Abfahrt mit Verspätung.
    public var departure: Date { scheduled.addingTimeInterval(TimeInterval(delayMinutes) * 60) }

    public var platformLabel: String? { platform ?? scheduledPlatform }

    public var platformChanged: Bool {
        guard let platform, let scheduledPlatform else { return false }
        return platform != scheduledPlatform
    }
}

public nonisolated struct TrainBoardResponse: Decodable, Sendable {
    public let departures: [TrainDepartureDTO]
}

public nonisolated struct TrainDepartureDTO: Decodable, Sendable {
    public let scheduledDeparture: String?
    public let delayDeparture: Int?
    public let platform: String?
    public let scheduledPlatform: String?
    public let destination: String
    public let train: String
    public let trainNumber: String?
    public let isCancelled: FlexibleBool?
    public let route: [Stop]?
    public let via: [String]?
    public let messages: Messages?

    public nonisolated struct Stop: Decodable, Sendable {
        let name: String
    }

    public nonisolated struct Message: Decodable, Sendable {
        let text: String?
    }

    public nonisolated struct Messages: Decodable, Sendable {
        let delay: [Message]?
        let qos: [Message]?
    }

    /// dbf liefert `isCancelled` mal als 0/1, mal als Bool.
    public nonisolated enum FlexibleBool: Decodable, Sendable {
        case value(Bool)

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let flag = try? container.decode(Bool.self) {
                self = .value(flag)
            } else if let number = try? container.decode(Int.self) {
                self = .value(number != 0)
            } else {
                self = .value(false)
            }
        }

        var bool: Bool {
            if case let .value(flag) = self { return flag }
            return false
        }
    }

    /// Nil, wenn die Fahrt nicht zur Strecke passt oder keine Abfahrtszeit hat
    /// (endende Züge stehen mit Ankunft, aber ohne Abfahrt auf der Tafel).
    public func asDeparture(station: String, reference now: Date) -> TrainDeparture? {
        guard let scheduledDeparture, let scheduled = Self.date(from: scheduledDeparture, reference: now) else {
            return nil
        }
        let stops = (route ?? []).map(\.name)
        // Halte nach dem eigenen Bahnhof; fehlt der Bahnhof in der Route, hilft `via`.
        let after: [String]
        if let index = stops.firstIndex(of: station) {
            after = Array(stops[(index + 1)...])
        } else {
            after = via ?? []
        }
        guard let direction = Self.direction(stops: after + [destination]) else { return nil }

        let notes = ((messages?.delay ?? []) + (messages?.qos ?? []))
            .compactMap { $0.text?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return TrainDeparture(
            id: "\(trainNumber ?? train)-\(scheduledDeparture)",
            scheduled: scheduled,
            delayMinutes: delayDeparture ?? 0,
            platform: platform,
            scheduledPlatform: scheduledPlatform,
            line: Self.lineLabel(train),
            destination: destination,
            via: Array(after.prefix(3)),
            direction: direction,
            isCancelled: isCancelled?.bool ?? false,
            notes: Array(notes.prefix(2))
        )
    }

    /// „RE RE1" → „RE1", „RE IC56" und „IC 2032" bleiben.
    private static func lineLabel(_ train: String) -> String {
        let parts = train.split(separator: " ").map(String.init)
        if parts.count == 2, parts[1].hasPrefix(parts[0]) {
            return parts[1]
        }
        return train
    }

    /// Die Tafel nennt nur „HH:mm" — der Tag ist heute, kurz nach Mitternacht auch morgen.
    private static func date(from text: String, reference now: Date) -> Date? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        guard let today = IslandTime.calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: IslandTime.startOfDay(now)
        ) else { return nil }
        // Liegt die Zeit mehr als sechs Stunden zurück, meint die Tafel den nächsten Tag.
        if today.timeIntervalSince(now) < -6 * 60 * 60 {
            return IslandTime.calendar.date(byAdding: .day, value: 1, to: today)
        }
        return today
    }

    /// Alles Richtung Oldenburg (und weiter nach Bremen, Hannover, Osnabrück) ist
    /// `.oldenburg`, die übrigen Züge fahren in die Gegenrichtung (Leer, Wilhelmshaven).
    private static func direction(stops: [String]) -> TrainDirection? {
        let joined = stops.joined(separator: " ").lowercased()
        if ["oldenburg", "bremen", "hannover", "osnabrück", "osnabrueck"].contains(where: joined.contains) {
            return .oldenburg
        }
        if ["leer", "emden", "norddeich", "augustfehn", "wilhelmshaven", "varel", "sande", "jever", "esens"].contains(where: joined.contains) {
            return .leer
        }
        return nil
    }
}
