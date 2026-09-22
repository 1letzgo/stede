import Foundation

/// Hält die zuletzt geladene Abfahrtstafel kurz im Speicher — die Tafel zeigt
/// nur die nächsten rund zwei Stunden, Verspätungen wechseln laufend.
actor TrainStore {
    static let shared = TrainStore()

    private let client = TrainClient()
    private let maxAge: TimeInterval = 60
    private var board: [TrainDeparture] = []
    private var fetchedAt: Date?

    /// Zuletzt geladene Tafel, auch wenn sie schon älter ist.
    func cached() -> [TrainDeparture]? {
        fetchedAt == nil ? nil : board
    }

    func departures(force: Bool = false) async throws -> [TrainDeparture] {
        if !force, let fetchedAt, Date().timeIntervalSince(fetchedAt) < maxAge {
            return board
        }
        let fresh = try await client.departures()
        board = fresh
        fetchedAt = Date()
        return fresh
    }
}
