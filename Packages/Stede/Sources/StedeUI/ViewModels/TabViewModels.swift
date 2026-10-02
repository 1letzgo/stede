import Foundation
import StedeCore

@Observable
final class TrainViewModel {
    var departures: [TrainDeparture] = []
    var state: LoadState = .idle

    private var loadedDay: Date?
    private var loadedStation: String?

    func departures(toward direction: TrainDirection) -> [TrainDeparture] {
        departures.filter { $0.direction == direction }
    }

    /// Die Tafel gibt es nur für heute — andere Tage bleiben leer.
    func load(station: TenantConfig.Station, day: Date, force: Bool = false) async {
        let start = IslandTime.startOfDay(day)
        if loadedStation != station.id {
            departures = []
            loadedDay = nil
            state = .idle
        }
        loadedStation = station.id
        guard IslandTime.isSameDay(day, Date()) else {
            departures = []
            loadedDay = start
            state = .empty
            return
        }
        if !force, loadedDay == start, state == .loaded || state == .empty {
            return
        }

        let hadCache: Bool
        if let cached = await TrainStore.shared.cached(at: station) {
            departures = cached
            loadedDay = start
            state = cached.isEmpty ? .empty : .loaded
            hadCache = true
        } else {
            hadCache = false
            if state != .loaded {
                state = .loading
            }
        }

        do {
            departures = try await TrainStore.shared.departures(at: station, force: force)
            loadedDay = start
            state = departures.isEmpty ? .empty : .loaded
        } catch {
            if !hadCache {
                state = .failed(error.localizedDescription)
            }
        }
    }
}

@Observable
final class BusViewModel {
    var departures: [BusDeparture] = []
    var state: LoadState = .idle

    private var loadedKey: String?

    func load(stop: BusStop, day: Date, force: Bool = false) async {
        let key = "\(stop.id)|\(IslandTime.isoDate(day))"
        if !force, loadedKey == key, state == .loaded || state == .empty {
            return
        }

        let hadCache: Bool
        if let cached = await BusStore.shared.cached(stop: stop, day: day) {
            departures = cached
            loadedKey = key
            state = cached.isEmpty ? .empty : .loaded
            hadCache = true
        } else {
            hadCache = false
            if loadedKey != key { departures = [] }
            state = .loading
        }

        do {
            departures = try await BusStore.shared.departures(stop: stop, day: day, force: force)
            loadedKey = key
            state = departures.isEmpty ? .empty : .loaded
        } catch {
            if !hadCache {
                state = .failed(error.localizedDescription)
            }
        }
    }
}

@Observable
final class WasteViewModel {
    var collections: [WasteCollection] = []
    var state: LoadState = .idle

    private var loadedKey: String?

    func load(selection: WasteSelection?, force: Bool = false) async {
        guard let selection else {
            collections = []
            state = .empty
            loadedKey = nil
            return
        }
        let key = selection.cacheKey
        if !force, loadedKey == key, state == .loaded {
            return
        }
        let year = IslandTime.calendar.component(.year, from: Date())
        let hadCache: Bool
        if let cached = await WasteStore.shared.cached(for: selection, year: year) {
            let today = IslandTime.startOfDay(Date())
            collections = cached.filter { $0.date >= today }
            loadedKey = key
            state = .loaded
            hadCache = true
        } else {
            hadCache = false
            if loadedKey != key { collections = [] }
            state = .loading
        }
        do {
            collections = try await WasteStore.shared.upcoming(for: selection, force: force)
            loadedKey = key
            state = collections.isEmpty ? .empty : .loaded
        } catch {
            if !hadCache {
                state = .failed(error.localizedDescription)
            }
        }
    }
}

@Observable
final class WeatherViewModel {
    var summary: WeatherDaySummary?
    var state: LoadState = .idle

    private var loadedDay: Date?

    func load(day: Date, force: Bool = false) async {
        let start = IslandTime.startOfDay(day)
        if !force, loadedDay == start, state == .loaded || state == .empty {
            return
        }

        if let cached = await WeatherStore.cached(on: day) {
            summary = cached
            loadedDay = start
            state = cached.hours.isEmpty ? .empty : .loaded
        } else if state != .loaded {
            state = .loading
        }

        do {
            let summary = try await WeatherStore.summary(on: day, force: force)
            self.summary = summary
            loadedDay = start
            state = summary.hours.isEmpty ? .empty : .loaded
        } catch {
            if summary == nil {
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Stunde, die die aktuelle Uhrzeit enthält - Ziel für den automatischen Sprung.
    func currentAnchor(now: Date = Date()) -> WeatherHour.ID? {
        guard let hours = summary?.hours, !hours.isEmpty else { return nil }
        return hours.last { $0.timestamp <= now }?.id ?? hours.first?.id
    }
}

/// Stadt-Termine einer ganzen Woche, tageweise aus dem Cache.
/// Kalender als fortlaufende Liste: startet eine Woche vor heute bis drei Wochen
/// danach und wächst in Seiten zu 21 Tagen nach unten (automatisch) und oben (auf Tipp).
@Observable
final class CalendarFeedModel {
    static let pageDays = 21
    /// Weiter als ein Jahr voraus gibt es keine Stadt-Termine mehr.
    static let horizonDays = 365

    /// Startet heute — Vergangenes nur über „Frühere Termine“.
    private(set) var start = IslandTime.startOfDay(Date())
    private(set) var end = IslandTime.day(Date(), adding: pageDays - 1)
    private(set) var events: [StedeEvent] = []
    private(set) var state: LoadState = .idle
    private(set) var isLoadingEarlier = false
    private(set) var isLoadingLater = false

    var canLoadLater: Bool { end < IslandTime.day(Date(), adding: Self.horizonDays) }

    /// Erster Aufruf und Pull-to-Refresh: den ganzen bisher geladenen Bereich.
    func load(force: Bool = false) async {
        if !force, state == .loaded || state == .empty { return }
        if events.isEmpty { state = .loading }
        do {
            let fresh = try await EventStore.events(from: start, through: end, force: force)
            events = Self.sorted(fresh)
            state = events.isEmpty ? .empty : .loaded
        } catch {
            if events.isEmpty { state = .failed(error.localizedDescription) }
        }
    }

    func loadLater() async {
        guard !isLoadingLater, canLoadLater, state != .loading else { return }
        isLoadingLater = true
        defer { isLoadingLater = false }
        let from = IslandTime.day(end, adding: 1)
        let to = IslandTime.day(end, adding: Self.pageDays)
        let more = (try? await EventStore.events(from: from, through: to)) ?? []
        end = to
        events = Self.sorted(events + more)
        if !events.isEmpty { state = .loaded }
    }

    func loadEarlier() async {
        guard !isLoadingEarlier else { return }
        isLoadingEarlier = true
        defer { isLoadingEarlier = false }
        let to = IslandTime.day(start, adding: -1)
        let from = IslandTime.day(start, adding: -Self.pageDays)
        let more = (try? await EventStore.events(from: from, through: to)) ?? []
        start = from
        events = Self.sorted(more + events)
        if !events.isEmpty { state = .loaded }
    }

    private static func sorted(_ events: [StedeEvent]) -> [StedeEvent] {
        events.sorted { ($0.time ?? .distantFuture) < ($1.time ?? .distantFuture) }
    }
}

@Observable
final class EventViewModel {
    var events: [StedeEvent] = []
    var state: LoadState = .idle

    private var loadedDay: Date?

    func load(day: Date, force: Bool = false) async {
        let start = IslandTime.startOfDay(day)
        if !force, loadedDay == start, state == .loaded || state == .empty {
            return
        }

        let hadCache: Bool
        if let cached = await EventStore.cached(on: day) {
            events = cached
            loadedDay = start
            state = cached.isEmpty ? .empty : .loaded
            hadCache = true
        } else {
            hadCache = false
            if state != .loaded {
                state = .loading
            }
        }

        do {
            events = try await EventStore.events(on: day, force: force)
            loadedDay = start
            state = events.isEmpty ? .empty : .loaded
            Task { await EventStore.prefetch(around: day) }
        } catch {
            if !hadCache {
                state = .failed(error.localizedDescription)
            }
        }
    }
}

@Observable
final class FerryViewModel {
    var outbound: [FerryTrip] = []
    var inbound: [FerryTrip] = []
    var state: LoadState = .idle

    private let client = FerryClient()
    private var loadedDay: Date?

    func load(day: Date, force: Bool = false) async {
        if !force, loadedDay == IslandTime.startOfDay(day), state == .loaded || state == .empty {
            return
        }
        state = .loading
        do {
            let trips = try await client.trips(on: day)
            outbound = trips.filter(\.isToIsland)
            inbound = trips.filter { !$0.isToIsland }
            loadedDay = IslandTime.startOfDay(day)
            state = trips.isEmpty ? .empty : .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

nonisolated struct CurrentTideLevel: Sendable {
    let value: Double
    let timestamp: Date
    let isMeasured: Bool
    let isRising: Bool?

    var trendLabel: String? {
        switch isRising {
        case true: "steigend"
        case false: "fallend"
        default: nil
        }
    }

    var trendSymbol: String {
        switch isRising {
        case true: "arrow.up.right"
        case false: "arrow.down.right"
        default: "minus"
        }
    }
}

@Observable
final class TideViewModel {
    var events: [TideEvent] = []
    var dayEvents: [TideEvent] = []
    var predicted: [WaterMeasurement] = []
    var measured: [WaterMeasurement] = []
    var waterUnavailableReason: String?
    var stationName = Tenants.current.tides?.gaugeName ?? ""
    var state: LoadState = .idle

    private let waterClient = WaterLevelClient()
    private var loadedDay: Date?

    var nextEvent: TideEvent? {
        let now = Date()
        return dayEvents.first { $0.timestamp > now } ?? events.first { $0.timestamp > now }
    }

    /// Gemessener Pegel, sonst der aus der Vorausberechnung interpolierte Stand.
    func currentLevel(now: Date = Date()) -> CurrentTideLevel? {
        if let latest = measured.last, now.timeIntervalSince(latest.timestamp) < 90 * 60 {
            return CurrentTideLevel(
                value: latest.value,
                timestamp: latest.timestamp,
                isMeasured: true,
                isRising: isRising(at: now)
            )
        }
        guard let predictedValue = TideCurve.height(at: now, events: events) else { return nil }
        return CurrentTideLevel(
            value: predictedValue,
            timestamp: now,
            isMeasured: false,
            isRising: isRising(at: now)
        )
    }

    private func isRising(at date: Date) -> Bool? {
        guard let next = events.first(where: { $0.timestamp > date }) else { return nil }
        return next.kind == .high
    }

    func load(day: Date, force: Bool = false) async {
        let start = IslandTime.startOfDay(day)
        if !force, loadedDay == start, state == .loaded || state == .empty {
            return
        }

        let cached = await TideStore.shared.cachedEvents(on: day)
        if !cached.isEmpty {
            applyTideEvents(cached, day: day)
            loadedDay = start
            state = .loaded
        } else if state != .loaded {
            state = .loading
        }

        waterUnavailableReason = nil
        do {
            async let tideTask = TideStore.shared.events(on: day)
            async let waterTask = fetchWater(on: day)
            let events = try await tideTask
            applyTideEvents(events, day: day)
            measured = await waterTask
            loadedDay = start
            if dayEvents.isEmpty && predicted.isEmpty {
                state = .empty
            } else {
                state = .loaded
            }
        } catch {
            if cached.isEmpty {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func applyTideEvents(_ events: [TideEvent], day: Date) {
        self.events = events
        dayEvents = events.filter { IslandTime.isSameDay($0.timestamp, day) }
        predicted = TideCurve.interpolated(
            events: events,
            from: IslandTime.startOfDay(day),
            to: IslandTime.endOfDay(day)
        )
    }

    private func fetchWater(on day: Date) async -> [WaterMeasurement] {
        let start = IslandTime.startOfDay(day)
        let earliest = IslandTime.calendar.date(byAdding: .day, value: -WaterLevelClient.maxHistoryDays, to: Date()) ?? Date()
        if IslandTime.endOfDay(day) <= earliest {
            waterUnavailableReason = "PEGELONLINE liefert Wasserstände nur für die letzten 31 Tage."
            return []
        }
        if start > Date(), !IslandTime.calendar.isDate(day, inSameDayAs: Date()) {
            waterUnavailableReason = "Gemessene Wasserstände gibt es erst, wenn der Tag begonnen hat."
            return []
        }
        do {
            return try await waterClient.measurements(on: day)
        } catch {
            waterUnavailableReason = error.localizedDescription
            return []
        }
    }
}

@Observable
final class AirQualityViewModel {
    var hours: [AirHour] = []
    var state: LoadState = .idle

    private var loadedDay: Date?

    var latest: AirHour? {
        hours.last { $0.totalIndex > 0 } ?? hours.last
    }

    func hour(matching date: Date) -> AirHour? {
        guard let match = hours.min(by: {
            abs($0.start.timeIntervalSince(date)) < abs($1.start.timeIntervalSince(date))
        }) else { return nil }
        return abs(match.start.timeIntervalSince(date)) <= 45 * 60 ? match : nil
    }

    func load(day: Date, force: Bool = false) async {
        let start = IslandTime.startOfDay(day)
        if !force, loadedDay == start, state == .loaded || state == .empty {
            return
        }

        if let cached = await AirQualityStore.cached(on: day) {
            hours = cached
            loadedDay = start
            state = cached.isEmpty ? .empty : .loaded
        } else if state != .loaded {
            state = .loading
        }

        do {
            hours = try await AirQualityStore.hours(on: day, force: force)
            loadedDay = start
            state = hours.isEmpty ? .empty : .loaded
        } catch {
            if hours.isEmpty {
                state = .failed(error.localizedDescription)
            }
        }
    }
}

