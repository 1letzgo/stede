import Foundation
import Supabase

/// Fahrten der Gemeinde-Fähre (`tenants.config.ferry`) über api.langeoog.de — wie alle Live-Dienste
/// über die Edge Function `upstream`.
public nonisolated struct FerryClient: Sendable {
    let http: HTTPClient

    public init(http: HTTPClient = HTTPClient()) {
        self.http = http
    }

    public func trips(on day: Date) async throws -> [FerryTrip] {
        guard let ferry = Tenants.current.ferry else { return [] }
        if ferry.isTimetable { return try await timetable(ferry, on: day) }
        let date = IslandTime.isoDate(day)
        var byID: [Int: FerryTrip] = [:]
        for route in ferry.routes ?? [] {
            guard let url = URL(string: "https://api.langeoog.de/fahrten/\(route)/\(date)") else { throw AppError.invalidURL }
            let payload: [FerryTripDTO] = try await http.get(url)
            for dto in payload {
                byID[dto.fahrtnummer] = dto.asTrip(mainland: ferry.mainland ?? "")
            }
        }
        return byID.values.sorted { $0.abfahrt < $1.abfahrt }
    }

    /// Fester Fahrplan aus dem PDF der Reederei: der Server legt ihn als Datei ab (`sync-ferry-pdf`),
    /// `ContentFiles` hält die lokale Kopie; ohne sie einmal direkt aus dem Bucket.
    nonisolated struct Timetable: Decodable, Sendable {
        let trips: [Row]
        nonisolated struct Row: Decodable, Sendable {
            let day: String
            let time: String
            let toIsland: Bool
            let vessel: String
        }
    }

    private func timetable(_ ferry: TenantConfig.FerryConfig, on day: Date) async throws -> [FerryTrip] {
        let name = ferry.file ?? "ferry"
        var data = ContentFiles.data(name)
        if data == nil {
            let url = Backend.url.appendingPathComponent("storage/v1/object/public/content/\(Tenants.currentSlug)/\(name).json")
            data = try await http.data(from: url)
        }
        guard let data else { return [] }
        let table = try JSONDecoder().decode(Timetable.self, from: data)
        let date = IslandTime.isoDate(day)
        return table.trips.enumerated().compactMap { index, row -> FerryTrip? in
            guard row.day == date, let departure = IslandTime.date(day: row.day, time: row.time) else { return nil }
            let vessel = ferry.vessels?[row.vessel] ?? row.vessel
            return FerryTrip(
                fahrtnummer: index, abfahrt: departure, ankunft: nil,
                ausgangshafen: row.toIsland ? "mainland" : "island", ausgangshafenBezeichnung: row.toIsland ? ferry.mainlandName : ferry.islandName,
                zielhafen: row.toIsland ? "island" : "mainland", zielhafenBezeichnung: row.toIsland ? ferry.islandName : ferry.mainlandName,
                ausflug: false, mainland: "mainland", fahrzeugtyp: vessel, fahrzeug: vessel, ausgefallen: false, auslastungPersonen: nil
            )
        }
        .sorted { $0.abfahrt < $1.abfahrt }
    }
}

/// Gemessene Wasserstände aus der Tabelle `water_levels` — der Server zieht sie alle 10 Minuten
/// aus PEGELONLINE nach, schon als 10-Minuten-Mittel.
public nonisolated struct WaterLevelClient: Sendable {
    public static let maxHistoryDays = 31

    public init() {}

    public func measurements(on day: Date) async throws -> [WaterMeasurement] {
        guard let gauge = Tenants.current.tides?.gauge else { return [] }
        let start = IslandTime.startOfDay(day)
        let end = IslandTime.endOfDay(day)
        let earliest = IslandTime.calendar.date(byAdding: .day, value: -Self.maxHistoryDays, to: Date()) ?? Date()
        guard end > earliest else { return [] }
        let stamp = ISO8601DateFormatter()
        let rows: [WaterMeasurementDTO] = try await Backend.client.from("water_levels")
            .select("timestamp:ts,value")
            .eq("station", value: gauge)
            .gte("ts", value: stamp.string(from: max(start, earliest)))
            .lte("ts", value: stamp.string(from: end))
            .order("ts").limit(1000).execute().value
        return rows.map { $0.asMeasurement() }
    }
}

/// Stündliche Luftqualität einer UBA-Station (`tenants.config.air_station`).
public nonisolated struct AirQualityClient: Sendable {
    let http: HTTPClient

    public init(http: HTTPClient = HTTPClient()) {
        self.http = http
    }

    public func hours(on day: Date) async throws -> [AirHour] {
        guard let station = Tenants.current.airStation else { return [] }
        let date = IslandTime.isoDate(day)
        var components = URLComponents(string: "https://luftdaten.umweltbundesamt.de/api-proxy/airquality/json")
        components?.queryItems = [
            URLQueryItem(name: "date_from", value: date),
            URLQueryItem(name: "date_to", value: date),
            URLQueryItem(name: "time_from", value: "1"),
            URLQueryItem(name: "time_to", value: "24"),
            URLQueryItem(name: "station", value: station),
            URLQueryItem(name: "lang", value: "de"),
        ]
        guard let url = components?.url else { throw AppError.invalidURL }
        return try Self.parse(try await http.data(from: url))
    }

    public static func parse(_ data: Data) throws -> [AirHour] {
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
                hours.append(AirHour(start: start, end: end, totalIndex: totalIndex, incomplete: incomplete, pollutants: pollutants))
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

public nonisolated enum AirQualityStore: Sendable {
    private static let cache = DayCache<[AirHour]>(name: "air", maxAge: 60 * 60)
    private static let client = AirQualityClient()

    public static func cached(on day: Date) async -> [AirHour]? {
        await cache.peek(on: day)
    }

    public static func hours(on day: Date, force: Bool = false) async throws -> [AirHour] {
        try await cache.value(on: day, force: force) {
            try await client.hours(on: day)
        }
    }
}
