import Foundation

/// Abfahrtstafel für Westerstede-Ocholt vom Abfahrtsmonitor dbf.finalrewind.org
/// (DB IRIS). Die Tafel reicht etwa zwei Stunden voraus und kennt nur „jetzt" —
/// andere Tage gibt es hier nicht. bahn.de selbst blockt die App mit 403.
nonisolated struct TrainClient: Sendable {
    static let stationName = "Westerstede-Ocholt"
    private static let boardURL = URL(string: "https://dbf.finalrewind.org/Westerstede-Ocholt.json?version=3")!

    let http: HTTPClient

    init(http: HTTPClient = HTTPClient()) {
        self.http = http
    }

    func departures(now: Date = Date()) async throws -> [TrainDeparture] {
        let response: TrainBoardResponse = try await http.get(Self.boardURL, decoder: JSONDecoder())
        let departures = response.departures.compactMap { $0.asDeparture(reference: now) }
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
nonisolated struct BusClient: Sendable {
    private static let boardURL = "https://fahrplaner.vbn.de/bin/stboard.exe/dn"
    private static let pageSize = 120
    private static let maxPages = 4

    let http: HTTPClient

    init(http: HTTPClient = HTTPClient()) {
        self.http = http
    }

    func departures(stop: BusStop, day: Date) async throws -> [BusDeparture] {
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

nonisolated struct WeatherClient: Sendable {
    let http: HTTPClient

    init(http: HTTPClient = HTTPClient()) {
        self.http = http
    }

    func weather(on day: Date) async throws -> WeatherDaySummary {
        var components = URLComponents(string: "https://api.brightsky.dev/weather")
        components?.queryItems = [
            URLQueryItem(name: "lat", value: "53.256"),
            URLQueryItem(name: "lon", value: "7.927"),
            URLQueryItem(name: "date", value: IslandTime.isoDate(day)),
            URLQueryItem(name: "tz", value: "Europe/Berlin"),
        ]
        guard let url = components?.url else { throw AppError.invalidURL }
        let response: WeatherResponse = try await http.get(url)
        let hours = response.weather.filter { IslandTime.isSameDay($0.timestamp, day) }
        return WeatherDaySummary(hours: hours, sourceName: response.sources.first?.stationName)
    }

    func latestAvailableDay(from start: Date = Date(), spanDays: Int = 14) async throws -> Date? {
        let from = IslandTime.startOfDay(start)
        let to = IslandTime.calendar.date(byAdding: .day, value: spanDays, to: from) ?? from
        var components = URLComponents(string: "https://api.brightsky.dev/weather")
        components?.queryItems = [
            URLQueryItem(name: "lat", value: "53.256"),
            URLQueryItem(name: "lon", value: "7.927"),
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

nonisolated struct AirQualityClient: Sendable {
    static let stationCode = "DENI058"

    let http: HTTPClient

    init(http: HTTPClient = HTTPClient()) {
        self.http = http
    }

    func hours(on day: Date) async throws -> [AirHour] {
        let date = IslandTime.isoDate(day)
        var components = URLComponents(string: "https://luftdaten.umweltbundesamt.de/api-proxy/airquality/json")
        components?.queryItems = [
            URLQueryItem(name: "date_from", value: date),
            URLQueryItem(name: "date_to", value: date),
            URLQueryItem(name: "time_from", value: "1"),
            URLQueryItem(name: "time_to", value: "24"),
            URLQueryItem(name: "station", value: Self.stationCode),
            URLQueryItem(name: "lang", value: "de"),
        ]
        guard let url = components?.url else { throw AppError.invalidURL }
        let data = try await http.data(from: url)
        return try Self.parse(data)
    }

    static func parse(_ data: Data) throws -> [AirHour] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataNode = root["data"] as? [String: Any]
        else {
            throw AppError.decoding("Luftqualität ohne data-Knoten.")
        }

        var hours: [AirHour] = []
        for (_, stationValue) in dataNode {
            guard let byStart = stationValue as? [String: Any] else { continue }
            for (startRaw, rawHour) in byStart {
                guard let start = UBADateParser.date(from: startRaw),
                      let fields = rawHour as? [Any],
                      fields.count >= 3
                else { continue }

                let end = (fields[0] as? String).flatMap(UBADateParser.date) ?? start.addingTimeInterval(3600)
                let totalIndex = intValue(fields[1]) ?? 0
                let incomplete = intValue(fields[2]) == 1
                let pollutants: [AirPollutant] = fields.dropFirst(3).compactMap { item in
                    guard let row = item as? [Any], row.count >= 3,
                          let componentId = intValue(row[0]),
                          let value = doubleValue(row[1]),
                          let index = intValue(row[2])
                    else { return nil }
                    return AirPollutant(componentId: componentId, value: value, index: index)
                }
                hours.append(
                    AirHour(
                        start: start,
                        end: end,
                        totalIndex: totalIndex,
                        incomplete: incomplete,
                        pollutants: pollutants
                    )
                )
            }
        }
        return hours.sorted { $0.start < $1.start }
    }

    private static func intValue(_ value: Any) -> Int? {
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private static func doubleValue(_ value: Any) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let string = value as? String { return Double(string) }
        return nil
    }
}

/// Veranstaltungssuche der Stadt Westerstede — die Trefferliste als HTML,
/// 15 Treffer je Seite, weitere Seiten über `p0`.
nonisolated struct EventClient: Sendable {
    let http: HTTPClient

    init(http: HTTPClient = HTTPClient()) {
        self.http = http
    }

    func events(on day: Date) async throws -> [StedeEvent] {
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
