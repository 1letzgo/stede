import Foundation

/// Fahrtrichtung ab Westerstede-Ocholt — die Strecke Oldenburg–Leer hat nur zwei Enden.
/// Rohwert als String, damit die Wahl per `@AppStorage` gespeichert werden kann.
public nonisolated enum TrainDirection: String, CaseIterable, Hashable, Sendable, Codable {
    case oldenburg
    case leer

    public var title: String {
        switch self {
        case .oldenburg: "Richtung Oldenburg"
        case .leer: "Richtung Leer"
        }
    }

    public var shortTitle: String {
        switch self {
        case .oldenburg: "Oldenburg"
        case .leer: "Leer"
        }
    }
}

/// Eine Abfahrt am Bahnhof Westerstede-Ocholt, wie sie der Abfahrtsmonitor
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
    public func asDeparture(reference now: Date) -> TrainDeparture? {
        guard let scheduledDeparture, let scheduled = Self.date(from: scheduledDeparture, reference: now) else {
            return nil
        }
        let stops = (route ?? []).map(\.name)
        // Halte nach dem eigenen Bahnhof; fehlt der Bahnhof in der Route, hilft `via`.
        let after: [String]
        if let index = stops.firstIndex(of: TrainClient.stationName) {
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

    private static func direction(stops: [String]) -> TrainDirection? {
        let joined = stops.joined(separator: " ").lowercased()
        if joined.contains("zwischenahn") || joined.contains("oldenburg") || joined.contains("bremen")
            || joined.contains("hannover") {
            return .oldenburg
        }
        if joined.contains("augustfehn") || joined.contains("leer") || joined.contains("emden")
            || joined.contains("norddeich") {
            return .leer
        }
        return nil
    }
}
