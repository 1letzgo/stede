import Foundation

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
