import Foundation

public nonisolated enum WeatherStore: Sendable {
    private static let cache = DayCache<WeatherDaySummary>(name: "weather", maxAge: 60 * 60)
    private static let client = WeatherClient()
    private static let horizon = WeatherHorizonCache()
    private static let fallbackForecastDays = 10

    public static func cached(on day: Date) async -> WeatherDaySummary? {
        await cache.peek(on: day)
    }

    public static func summary(on day: Date, force: Bool = false) async throws -> WeatherDaySummary {
        try await cache.value(on: day, force: force) {
            try await client.weather(on: day)
        }
    }

    public static func latestAvailableDay() async -> Date {
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

    public func dayIfFresh(maxAge: TimeInterval = 60 * 60) -> Date? {
        guard let fetchedAt, let day, Date().timeIntervalSince(fetchedAt) < maxAge else {
            return nil
        }
        return day
    }

    public func store(_ day: Date) {
        self.day = IslandTime.startOfDay(day)
        fetchedAt = Date()
    }
}
