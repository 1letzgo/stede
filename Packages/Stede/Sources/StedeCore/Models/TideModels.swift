import Foundation

public nonisolated struct TideStation: Sendable {
    public let stationName: String
    public let bshnr: String
    public let pegelonlineUuid: String
    public let events: [TideEvent]
}

/// Alle Wasserstände liegen nach dem Decoding in Metern über Seekartennull vor.
public nonisolated enum TideFormat: Sendable {
    /// Differenz Pegelnullpunkt minus Seekartennull, wie im Kalender auf langeoog.de.
    public static let pnpMinusChartDatum = 3.17
    public static let reference = "über SKN"

    public static func fromPegelCentimetres(_ centimetres: Double) -> Double {
        centimetres / 100 - pnpMinusChartDatum
    }

    public static func meters(_ value: Double, digits: Int = 2) -> String {
        let number = value.formatted(
            .number.precision(.fractionLength(digits)).locale(IslandTime.germanLocale)
        )
        return "\(number) m"
    }
}

public nonisolated struct TideEvent: Identifiable, Hashable, Sendable {
    public var id: Date { timestamp }
    public let timestamp: Date
    /// Meter über Seekartennull.
    public let height: Double
    public let kind: Kind
    public let phase: String?

    public enum Kind: String, Sendable {
        case high = "HW"
        case low = "NW"

        public var label: String {
            switch self {
            case .high: "Hochwasser"
            case .low: "Niedrigwasser"
            }
        }

        public var shortLabel: String {
            rawValue
        }
    }

    public var phaseLabel: String? {
        switch phase {
        case "SP": "Springzeit"
        case "NP": "Nippzeit"
        case "MT": "Mittzeit"
        default: nil
        }
    }
}

public nonisolated struct TideStationDTO: Decodable, Sendable {
    public let stationName: String
    public let bshnr: String
    public let pegelonlineUuid: String
    public let years: [TideYearBox]

    public enum CodingKeys: String, CodingKey {
        case stationName = "station_name"
        case bshnr
        case pegelonlineUuid = "pegelonline_uuid"
        case years
    }

    public func asStation() -> TideStation {
        let events = years
            .flatMap(\.year.prediction.data)
            .compactMap { $0.asEvent() }
            .sorted { $0.timestamp < $1.timestamp }
        return TideStation(
            stationName: stationName,
            bshnr: bshnr,
            pegelonlineUuid: pegelonlineUuid,
            events: events
        )
    }
}

public nonisolated struct TideYearBox: Decodable, Sendable {
    public let year: TideYearPayload

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let keyed = try container.decode([String: TideYearPayload].self)
        guard let payload = keyed.values.first else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Leeres Gezeitenjahr"
            )
        }
        year = payload
    }
}

public nonisolated struct TideYearPayload: Decodable, Sendable {
    public let prediction: TidePrediction

    public enum CodingKeys: String, CodingKey {
        case prediction = "hwnw_prediction"
    }
}

public nonisolated struct TidePrediction: Decodable, Sendable {
    public let data: [TideEventDTO]
}

public nonisolated struct TideEventDTO: Decodable, Sendable {
    public let timestamp: Date
    public let height: Double
    public let type: String
    public let phase: String?

    public enum CodingKeys: String, CodingKey {
        case timestamp, height, type, phase
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        height = try container.decodeFlexibleDouble(forKey: .height)
        type = try container.decode(String.self, forKey: .type)
        phase = try container.decodeIfPresent(String.self, forKey: .phase)
    }

    public func asEvent() -> TideEvent? {
        guard let kind = TideEvent.Kind(rawValue: type) else { return nil }
        return TideEvent(timestamp: timestamp, height: TideFormat.fromPegelCentimetres(height), kind: kind, phase: phase)
    }
}

public nonisolated struct WaterMeasurement: Identifiable, Hashable, Sendable {
    public var id: Date { timestamp }
    public let timestamp: Date
    /// Meter über Seekartennull.
    public let value: Double
}

public nonisolated struct WaterMeasurementDTO: Decodable, Sendable {
    public let timestamp: Date
    public let value: Double

    public enum CodingKeys: String, CodingKey {
        case timestamp, value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        value = try container.decodeFlexibleDouble(forKey: .value)
    }

    public func asMeasurement() -> WaterMeasurement {
        WaterMeasurement(timestamp: timestamp, value: TideFormat.fromPegelCentimetres(value))
    }
}

public nonisolated enum TideCurve: Sendable {
    public static func interpolated(
        events: [TideEvent],
        from start: Date,
        to end: Date,
        stepMinutes: Int = 10
    ) -> [WaterMeasurement] {
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        guard sorted.count >= 2 else { return [] }
        let step = TimeInterval(stepMinutes * 60)
        var points: [WaterMeasurement] = []
        var cursor = start
        while cursor <= end {
            if let value = height(at: cursor, events: sorted) {
                points.append(WaterMeasurement(timestamp: cursor, value: value))
            }
            cursor = cursor.addingTimeInterval(step)
        }
        return points
    }

    public static func height(at date: Date, events: [TideEvent]) -> Double? {
        guard let index = events.lastIndex(where: { $0.timestamp <= date }),
              index + 1 < events.count
        else { return nil }
        let left = events[index]
        let right = events[index + 1]
        let span = right.timestamp.timeIntervalSince(left.timestamp)
        guard span > 0 else { return left.height }
        let progress = date.timeIntervalSince(left.timestamp) / span
        let cosine = cos(Double.pi * progress)
        return (left.height + right.height) / 2 + (left.height - right.height) / 2 * cosine
    }

    public static func downsample(_ measurements: [WaterMeasurement], minutes: Int = 10) -> [WaterMeasurement] {
        guard !measurements.isEmpty else { return [] }
        let interval = TimeInterval(minutes * 60)
        var buckets: [TimeInterval: (sum: Double, count: Int)] = [:]
        for item in measurements {
            let key = (item.timestamp.timeIntervalSince1970 / interval).rounded(.down) * interval
            let existing = buckets[key] ?? (0, 0)
            buckets[key] = (existing.sum + item.value, existing.count + 1)
        }
        return buckets.keys.sorted().map { key in
            let bucket = buckets[key]!
            return WaterMeasurement(
                timestamp: Date(timeIntervalSince1970: key),
                value: bucket.sum / Double(bucket.count)
            )
        }
    }
}
