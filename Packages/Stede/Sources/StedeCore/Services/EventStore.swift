import Foundation

public nonisolated enum EventStore: Sendable {
    private static let cache = DayCache<[StedeEvent]>(name: "events", maxAge: 6 * 60 * 60)
    private static let client = EventClient()

    public static func cached(on day: Date) async -> [StedeEvent]? {
        await cache.peek(on: day)
    }

    /// Erst das Backend (`city_events`, stündlich vom Server gescrapt), bei Fehler
    /// der eigene Scraper — so bleibt der Kalender auch ohne Backend nutzbar.
    public static func events(on day: Date, force: Bool = false) async throws -> [StedeEvent] {
        try await cache.value(on: day, force: force) {
            do {
                return try await CityEventClient().events(on: day)
            } catch {
                return try await client.events(on: day)
            }
        }
    }

    /// Alle Tage von `start` bis einschließlich `end`: frische Caches direkt, sonst eine
    /// Bereichsabfrage ans Backend (füllt die Tagescaches); fällt das aus, Tag für Tag.
    public static func events(from start: Date, through end: Date, force: Bool = false) async throws -> [StedeEvent] {
        let days = IslandTime.days(from: start, through: end)
        if !force {
            var collected: [StedeEvent] = []
            var complete = true
            for day in days {
                if let hit = await cache.fresh(on: day) { collected += hit } else { complete = false; break }
            }
            if complete { return collected }
        }
        do {
            let grouped = try await CityEventClient().events(from: start, through: end)
            var collected: [StedeEvent] = []
            for day in days {
                let items = grouped[IslandTime.isoDate(day)] ?? []
                await cache.store(items, on: day)
                collected += items
            }
            return collected
        } catch {
            var collected: [StedeEvent] = []
            for day in days { collected += (try? await events(on: day, force: force)) ?? [] }
            return collected
        }
    }

    /// Lädt benachbarte Tage still in den Cache, damit das Umblättern sofort geht.
    public static func prefetch(around day: Date) async {
        let start = IslandTime.startOfDay(day)
        for offset in -1 ... 7 {
            guard let target = IslandTime.calendar.date(byAdding: .day, value: offset, to: start) else {
                continue
            }
            _ = try? await events(on: target)
        }
    }
}
