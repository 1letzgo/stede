import Foundation
import StedeCore

@Observable
final class TrainViewModel {
    var departures: [TrainDeparture] = []
    var state: LoadState = .idle

    private var loadedDay: Date?

    func departures(toward direction: TrainDirection) -> [TrainDeparture] {
        departures.filter { $0.direction == direction }
    }

    /// Die Tafel gibt es nur für heute — andere Tage bleiben leer.
    func load(day: Date, force: Bool = false) async {
        let start = IslandTime.startOfDay(day)
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
        if let cached = await TrainStore.shared.cached() {
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
            departures = try await TrainStore.shared.departures(force: force)
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

    private(set) var start = IslandTime.day(Date(), adding: -7)
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
