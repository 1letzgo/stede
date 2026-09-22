import Foundation

nonisolated struct WeatherResponse: Decodable, Sendable {
    let weather: [WeatherHour]
    let sources: [WeatherSource]
}

nonisolated struct WeatherHour: Identifiable, Hashable, Sendable, Codable {
    var id: Date { timestamp }
    let timestamp: Date
    let precipitation: Double?
    let pressureMsl: Double?
    let sunshine: Double?
    let temperature: Double?
    let windDirection: Double?
    let windSpeed: Double?
    let cloudCover: Double?
    let relativeHumidity: Double?
    let windGustSpeed: Double?
    let condition: String?
    let icon: String?

    enum CodingKeys: String, CodingKey {
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

    init(from decoder: Decoder) throws {
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

    var symbolName: String {
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

    var conditionLabel: String {
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

    var usesNightPalette: Bool {
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
    var atmosphere: String {
        switch condition {
        case "fog", "rain", "sleet", "snow", "hail", "thunderstorm":
            condition ?? "cloudy"
        default:
            icon ?? "cloudy"
        }
    }
}

nonisolated struct WeatherSource: Codable, Hashable, Sendable {
    let id: Int
    let stationName: String?
    let distance: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case stationName = "station_name"
        case distance
    }
}

nonisolated struct WeatherDaySummary: Codable, Sendable {
    let hours: [WeatherHour]
    let sourceName: String?

    var minTemperature: Double? { hours.compactMap(\.temperature).min() }
    var maxTemperature: Double? { hours.compactMap(\.temperature).max() }
    var precipitationSum: Double { hours.compactMap(\.precipitation).reduce(0, +) }
    var representative: WeatherHour? {
        hours.first { IslandTime.calendar.component(.hour, from: $0.timestamp) == 12 }
            ?? hours.dropFirst(hours.count / 2).first
            ?? hours.first
    }
}
