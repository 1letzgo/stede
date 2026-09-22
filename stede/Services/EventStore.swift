import Foundation

nonisolated enum EventStore: Sendable {
    private static let cache = DayCache<[StedeEvent]>(name: "events", maxAge: 6 * 60 * 60)
    private static let client = EventClient()

    static func cached(on day: Date) async -> [StedeEvent]? {
        await cache.peek(on: day)
    }

    static func events(on day: Date, force: Bool = false) async throws -> [StedeEvent] {
        try await cache.value(on: day, force: force) {
            try await client.events(on: day)
        }
    }

    /// Lädt benachbarte Tage still in den Cache, damit das Umblättern sofort geht.
    static func prefetch(around day: Date) async {
        let start = IslandTime.startOfDay(day)
        for offset in -1 ... 7 {
            guard let target = IslandTime.calendar.date(byAdding: .day, value: offset, to: start) else {
                continue
            }
            _ = try? await events(on: target)
        }
    }
}
