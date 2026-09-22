import Foundation

nonisolated enum WeatherStore: Sendable {
    private static let cache = DayCache<WeatherDaySummary>(name: "weather", maxAge: 60 * 60)
    private static let client = WeatherClient()
    private static let horizon = WeatherHorizonCache()
    private static let fallbackForecastDays = 10

    static func cached(on day: Date) async -> WeatherDaySummary? {
        await cache.peek(on: day)
    }

    static func summary(on day: Date, force: Bool = false) async throws -> WeatherDaySummary {
        try await cache.value(on: day, force: force) {
            try await client.weather(on: day)
        }
    }

    static func latestAvailableDay() async -> Date {
        if let cached = await horizon.dayIfFresh() {
            return cached
        }
        let today = IslandTime.startOfDay(Date())
        let fallback = IslandTime.calendar.date(
            byAdding: .day,
            value: fallbackForecastDays,
            to: today
        ) ?? today
        do {
            let day = try await client.latestAvailableDay(from: today) ?? fallback
            await horizon.store(day)
            return day
        } catch {
            await horizon.store(fallback)
            return fallback
        }
    }
}

private actor WeatherHorizonCache {
    private var fetchedAt: Date?
    private var day: Date?

    func dayIfFresh(maxAge: TimeInterval = 60 * 60) -> Date? {
        guard let fetchedAt, let day, Date().timeIntervalSince(fetchedAt) < maxAge else {
            return nil
        }
        return day
    }

    func store(_ day: Date) {
        self.day = IslandTime.startOfDay(day)
        fetchedAt = Date()
    }
}

nonisolated enum AirQualityStore: Sendable {
    private static let cache = DayCache<[AirHour]>(name: "air", maxAge: 60 * 60)
    private static let client = AirQualityClient()

    static func cached(on day: Date) async -> [AirHour]? {
        await cache.peek(on: day)
    }

    static func hours(on day: Date, force: Bool = false) async throws -> [AirHour] {
        try await cache.value(on: day, force: force) {
            try await client.hours(on: day)
        }
    }
}
