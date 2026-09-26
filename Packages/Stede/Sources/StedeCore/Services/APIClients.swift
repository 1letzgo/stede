import Foundation

/// Abfahrtstafel eines Ammerland-Bahnhofs vom Abfahrtsmonitor dbf.finalrewind.org
/// (DB IRIS). Die Tafel reicht etwa zwei Stunden voraus und kennt nur „jetzt" —
/// andere Tage gibt es hier nicht. bahn.de selbst blockt die App mit 403.
public nonisolated struct TrainClient: Sendable {
    private static func boardURL(_ station: TenantConfig.Station) -> URL {
        let name = station.dbf.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? station.dbf
        return URL(string: "https://dbf.finalrewind.org/\(name).json?version=3")!
    }

    public let http: HTTPClient

    public init(http: HTTPClient = HTTPClient()) {
        self.http = http
    }

    public func departures(at station: TenantConfig.Station, now: Date = Date()) async throws -> [TrainDeparture] {
        let response: TrainBoardResponse = try await http.get(Self.boardURL(station), decoder: JSONDecoder())
        let departures = response.departures.compactMap { $0.asDeparture(station: station.name, reference: now) }
        return Self.mergingDoubleListings(departures).sorted { $0.scheduled < $1.scheduled }
    }

    /// Ein IC mit Nahverkehrsfreigabe steht zweimal auf der Tafel — als „IC 2034"
    /// und als „RE IC56". Es ist derselbe Zug; die RE-Zeile bleibt, weil sie zum
    /// Nahverkehrsticket passt, die IC-Nummer wandert in die Linienangabe.
    private static func mergingDoubleListings(_ departures: [TrainDeparture]) -> [TrainDeparture] {
        var byRun: [String: [TrainDeparture]] = [:]
        for departure in departures {
            byRun["\(departure.scheduled.timeIntervalSince1970)|\(departure.destination)", default: []].append(departure)
        }
        return byRun.values.map { group in
            guard group.count > 1,
                  let regional = group.first(where: { $0.line.hasPrefix("RE") }),
                  let longDistance = group.first(where: { !$0.line.hasPrefix("RE") })
            else { return group[0] }
            return TrainDeparture(
                id: regional.id,
                scheduled: regional.scheduled,
                delayMinutes: max(regional.delayMinutes, longDistance.delayMinutes),
                platform: regional.platform ?? longDistance.platform,
                scheduledPlatform: regional.scheduledPlatform ?? longDistance.scheduledPlatform,
                line: "\(regional.line) · \(longDistance.line)",
                destination: regional.destination,
                via: regional.via,
                direction: regional.direction,
                isCancelled: regional.isCancelled && longDistance.isCancelled,
                notes: regional.notes.isEmpty ? longDistance.notes : regional.notes
            )
        }
    }
}

/// Abfahrtstafel des VBN-Fahrplaners (HAFAS `stboard.exe`) für eine Haltestelle.
/// Liefert höchstens 120 Fahrten je Aufruf; für einen ganzen Tag wird ab der
/// letzten Zeit nachgeladen.
public nonisolated struct BusClient: Sendable {
    private static let boardURL = "https://fahrplaner.vbn.de/bin/stboard.exe/dn"
    private static let pageSize = 120
    private static let maxPages = 4

    public let http: HTTPClient

    public init(http: HTTPClient = HTTPClient()) {
        self.http = http
    }

    public func departures(stop: BusStop, day: Date) async throws -> [BusDeparture] {
        var collected: [BusDeparture] = []
        var seen = Set<String>()
        var from = IslandTime.startOfDay(day)
        for _ in 0 ..< Self.maxPages {
            let xml = try await board(stop: stop, from: from)
            if let error = BusBoardParser.errorText(from: xml), collected.isEmpty {
                throw AppError.decoding(error)
            }
            let page = BusBoardParser.departures(from: xml)
            for departure in page where seen.insert(departure.id).inserted {
                collected.append(departure)
            }
            // Weniger als eine volle Seite oder schon der nächste Tag: fertig.
            guard page.count >= Self.pageSize, let last = page.last?.scheduled,
                  IslandTime.isSameDay(last, day), last > from
            else { break }
            from = last.addingTimeInterval(60)
        }
        return collected
            .filter { IslandTime.isSameDay($0.scheduled, day) }
            .sorted { $0.scheduled < $1.scheduled }
    }

    private func board(stop: BusStop, from: Date) async throws -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = IslandTime.timeZone
        formatter.dateFormat = "dd.MM.yy"
        let dateText = formatter.string(from: from)
        formatter.dateFormat = "HH:mm"
        let timeText = formatter.string(from: from)

        var components = URLComponents(string: Self.boardURL)
        components?.queryItems = [
            URLQueryItem(name: "input", value: stop.id),
            URLQueryItem(name: "boardType", value: "dep"),
            URLQueryItem(name: "date", value: dateText),
            URLQueryItem(name: "time", value: timeText),
            URLQueryItem(name: "maxJourneys", value: String(Self.pageSize)),
            URLQueryItem(name: "start", value: "yes"),
            URLQueryItem(name: "L", value: "vs_java3"),
        ]
        guard let url = components?.url else { throw AppError.invalidURL }
        let data = try await http.data(from: url)
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }
}

public nonisolated struct WeatherClient: Sendable {
    public let http: HTTPClient

    public init(http: HTTPClient = HTTPClient()) {
        self.http = http
    }

    public func weather(on day: Date) async throws -> WeatherDaySummary {
        let tenant = Tenants.current
        var components = URLComponents(string: "https://api.brightsky.dev/weather")
        components?.queryItems = [
            URLQueryItem(name: "lat", value: String(format: "%.3f", tenant.latitude)),
            URLQueryItem(name: "lon", value: String(format: "%.3f", tenant.longitude)),
            URLQueryItem(name: "date", value: IslandTime.isoDate(day)),
            URLQueryItem(name: "tz", value: "Europe/Berlin"),
        ]
        guard let url = components?.url else { throw AppError.invalidURL }
        let response: WeatherResponse = try await http.get(url)
        let hours = response.weather.filter { IslandTime.isSameDay($0.timestamp, day) }
        return WeatherDaySummary(hours: hours, sourceName: response.sources.first?.stationName)
    }

    public func latestAvailableDay(from start: Date = Date(), spanDays: Int = 14) async throws -> Date? {
        let from = IslandTime.startOfDay(start)
        let to = IslandTime.calendar.date(byAdding: .day, value: spanDays, to: from) ?? from
        let tenant = Tenants.current
        var components = URLComponents(string: "https://api.brightsky.dev/weather")
        components?.queryItems = [
            URLQueryItem(name: "lat", value: String(format: "%.3f", tenant.latitude)),
            URLQueryItem(name: "lon", value: String(format: "%.3f", tenant.longitude)),
            URLQueryItem(name: "date", value: IslandTime.isoDate(from)),
            URLQueryItem(name: "last_date", value: IslandTime.isoDate(to)),
            URLQueryItem(name: "tz", value: "Europe/Berlin"),
        ]
        guard let url = components?.url else { throw AppError.invalidURL }
        let response: WeatherResponse = try await http.get(url)
        return response.weather
            .filter { $0.temperature != nil || $0.icon != nil }
            .map { IslandTime.startOfDay($0.timestamp) }
            .max()
    }
}

/// Veranstaltungssuche der Stadt Westerstede — die Trefferliste als HTML,
/// 15 Treffer je Seite, weitere Seiten über `p0`.
public nonisolated struct EventClient: Sendable {
    public let http: HTTPClient

    public init(http: HTTPClient = HTTPClient()) {
        self.http = http
    }

    public func events(on day: Date) async throws -> [StedeEvent] {
        let date = IslandTime.isoDate(day)
        let firstHTML = try await pageHTML(date: date, page: 1)
        let totalPages = min(EventHTMLParser.pageCount(from: firstHTML), 10)
        var collected = EventHTMLParser.events(from: firstHTML, on: day)
        if totalPages > 1 {
            for page in 2 ... totalPages {
                let html = try await pageHTML(date: date, page: page)
                collected.append(contentsOf: EventHTMLParser.events(from: html, on: day))
            }
        }
        var seen = Set<Int>()
        return collected
            .filter { seen.insert($0.id).inserted }
            .sorted {
                switch ($0.time, $1.time) {
                case let (lhs?, rhs?): lhs < rhs
                case (_?, nil): true
                case (nil, _?): false
                default: $0.title < $1.title
                }
            }
    }

    private func pageHTML(date: String, page: Int) async throws -> String {
        var components = URLComponents(string: "https://www.westerstede.de/regional/veranstaltungen/suche.html")
        components?.queryItems = [
            URLQueryItem(name: "p0", value: String(page)),
            URLQueryItem(name: "naviID", value: "0"),
            URLQueryItem(name: "titel", value: "Veranstaltungssuche"),
            URLQueryItem(name: "kultur", value: "0"),
            URLQueryItem(name: "destination", value: "0"),
            URLQueryItem(name: "dest_id", value: "0"),
            URLQueryItem(name: "buchbar", value: "0"),
            URLQueryItem(name: "intern", value: "0"),
            URLQueryItem(name: "zeitauswahl", value: "4"),
            URLQueryItem(name: "beginn_datum", value: date),
            URLQueryItem(name: "ende_datum", value: date),
            URLQueryItem(name: "selected_kommune", value: "0"),
            URLQueryItem(name: "rubrik", value: "0"),
            URLQueryItem(name: "suchwort", value: ""),
            URLQueryItem(name: "suche", value: "1"),
            URLQueryItem(name: "termine", value: "0"),
            URLQueryItem(name: "action0", value: "1"),
        ]
        guard let url = components?.url else { throw AppError.invalidURL }
        let data = try await http.data(from: url)
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }
}
