import Foundation

/// Busabfahrten je Haltestelle und Tag — kurz im Speicher gehalten, weil
/// Echtzeitangaben laufend wechseln.
actor BusStore {
    static let shared = BusStore()

    private let client = BusClient()
    private let maxAge: TimeInterval = 60
    private var boards: [String: (fetchedAt: Date, departures: [BusDeparture])] = [:]

    private func key(_ stop: BusStop, _ day: Date) -> String {
        "\(stop.id)|\(IslandTime.isoDate(day))"
    }

    func cached(stop: BusStop, day: Date) -> [BusDeparture]? {
        boards[key(stop, day)]?.departures
    }

    func departures(stop: BusStop, day: Date, force: Bool = false) async throws -> [BusDeparture] {
        let key = key(stop, day)
        if !force, let entry = boards[key], Date().timeIntervalSince(entry.fetchedAt) < maxAge {
            return entry.departures
        }
        let fresh = try await client.departures(stop: stop, day: day)
        boards[key] = (Date(), fresh)
        return fresh
    }
}
