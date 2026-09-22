import Foundation

public nonisolated struct WeatherResponse: Decodable, Sendable {
    public let weather: [WeatherHour]
    public let sources: [WeatherSource]
}

public nonisolated struct WeatherHour: Identifiable, Hashable, Sendable, Codable {
    public var id: Date { timestamp }
    public let timestamp: Date
    public let precipitation: Double?
    public let pressureMsl: Double?
    public let sunshine: Double?
    public let temperature: Double?
    public let windDirection: Double?
    public let windSpeed: Double?
    public let cloudCover: Double?
    public let relativeHumidity: Double?
    public let windGustSpeed: Double?
    public let condition: String?
    public let icon: String?

    public enum CodingKeys: String, CodingKey {
        case timestamp
        case precipitation
        case pressureMsl = "pressure_msl"
        case sunshine
        case temperature
        case windDirection = "wind_direction"
        case windSpeed = "wind_speed"
        case cloudCover = "cloud_cover"
        case relativeHumidity = "relative_humidity"
        case windGustSpeed = "wind_gust_speed"
        case condition
        case icon
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        precipitation = try container.decodeFlexibleDoubleIfPresent(forKey: .precipitation)
        pressureMsl = try container.decodeFlexibleDoubleIfPresent(forKey: .pressureMsl)
        sunshine = try container.decodeFlexibleDoubleIfPresent(forKey: .sunshine)
        temperature = try container.decodeFlexibleDoubleIfPresent(forKey: .temperature)
        windDirection = try container.decodeFlexibleDoubleIfPresent(forKey: .windDirection)
        windSpeed = try container.decodeFlexibleDoubleIfPresent(forKey: .windSpeed)
        cloudCover = try container.decodeFlexibleDoubleIfPresent(forKey: .cloudCover)
        relativeHumidity = try container.decodeFlexibleDoubleIfPresent(forKey: .relativeHumidity)
        windGustSpeed = try container.decodeFlexibleDoubleIfPresent(forKey: .windGustSpeed)
        condition = try container.decodeIfPresent(String.self, forKey: .condition)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
    }

    public var symbolName: String {
        switch icon {
        case "clear-day": "sun.max.fill"
        case "clear-night": "moon.stars.fill"
        case "partly-cloudy-day": "cloud.sun.fill"
        case "partly-cloudy-night": "cloud.moon.fill"
        case "cloudy": "cloud.fill"
        case "fog": "cloud.fog.fill"
        case "wind": "wind"
        case "rain": "cloud.rain.fill"
        case "sleet": "cloud.sleet.fill"
        case "snow": "cloud.snow.fill"
        case "hail": "cloud.hail.fill"
        case "thunderstorm": "cloud.bolt.fill"
        default: "cloud.sun.fill"
        }
    }

    public var conditionLabel: String {
        switch condition {
        case "dry": "Trocken"
        case "fog": "Nebel"
        case "rain": "Regen"
        case "sleet": "Schneeregen"
        case "snow": "Schnee"
        case "hail": "Hagel"
        case "thunderstorm": "Gewitter"
        default: iconLabel
        }
    }

    private var iconLabel: String {
        switch icon {
        case "clear-day", "clear-night": "Klar"
        case "partly-cloudy-day", "partly-cloudy-night": "Teils bewölkt"
        case "cloudy": "Bewölkt"
        default: "Wetter"
        }
    }

    public var usesNightPalette: Bool {
        switch icon {
        case "clear-night", "partly-cloudy-night":
            return true
        case "clear-day", "partly-cloudy-day":
            return false
        default:
            let hour = IslandTime.calendar.component(.hour, from: timestamp)
            return hour < 6 || hour >= 21
        }
    }

    /// Bright-Sky-Icon bzw. Niederschlags-Condition für Hero-Hintergründe.
    public var atmosphere: String {
        switch condition {
        case "fog", "rain", "sleet", "snow", "hail", "thunderstorm":
            condition ?? "cloudy"
        default:
            icon ?? "cloudy"
        }
    }
}

public nonisolated struct WeatherSource: Codable, Hashable, Sendable {
    public let id: Int
    public let stationName: String?
    public let distance: Double?

    public enum CodingKeys: String, CodingKey {
        case id
        case stationName = "station_name"
        case distance
    }
}

public nonisolated struct WeatherDaySummary: Codable, Sendable {
    public let hours: [WeatherHour]
    public let sourceName: String?

    public var minTemperature: Double? { hours.compactMap(\.temperature).min() }
    public var maxTemperature: Double? { hours.compactMap(\.temperature).max() }
    public var precipitationSum: Double { hours.compactMap(\.precipitation).reduce(0, +) }
    public var representative: WeatherHour? {
        hours.first { IslandTime.calendar.component(.hour, from: $0.timestamp) == 12 }
            ?? hours.dropFirst(hours.count / 2).first
            ?? hours.first
    }
}
