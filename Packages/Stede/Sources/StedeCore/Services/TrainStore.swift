import Foundation

/// Hält die zuletzt geladene Abfahrtstafel kurz im Speicher — die Tafel zeigt
/// nur die nächsten rund zwei Stunden, Verspätungen wechseln laufend.
public actor TrainStore {
    public static let shared = TrainStore()

    private let client = TrainClient()
    private let maxAge: TimeInterval = 60
    private var board: [TrainDeparture] = []
    private var fetchedAt: Date?
    private var stationID: String?

    /// Zuletzt geladene Tafel dieses Bahnhofs, auch wenn sie schon älter ist.
    public func cached(at station: TenantConfig.Station) -> [TrainDeparture]? {
        fetchedAt == nil || stationID != station.id ? nil : board
    }

    public func departures(at station: TenantConfig.Station, force: Bool = false) async throws -> [TrainDeparture] {
        if !force, stationID == station.id, let fetchedAt, Date().timeIntervalSince(fetchedAt) < maxAge {
            return board
        }
        let fresh = try await client.departures(at: station)
        board = fresh
        stationID = station.id
        fetchedAt = Date()
        return fresh
    }
}
