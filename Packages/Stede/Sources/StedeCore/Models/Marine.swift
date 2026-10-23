import Foundation
import Supabase

/// Wind und Seegang einer Stunde vor der Insel — aus den DWD-Seegangsmodellen, die auch
/// marineforecast.bsh.de zeigt; der Server legt sie stündlich in `marine_forecasts` ab.
public nonisolated struct MarineHour: Codable, Sendable, Hashable, Identifiable {
    public var id: Date { timestamp }
    public let timestamp: Date
    /// Meter pro Sekunde, 10 m über Grund.
    public let windSpeed: Double?
    /// Richtung, aus der der Wind kommt, in Grad.
    public let windDirection: Double?
    /// Signifikante Wellenhöhe in Metern.
    public let waveHeight: Double?

    enum CodingKeys: String, CodingKey {
        case timestamp = "ts"
        case windSpeed = "wind_speed"
        case windDirection = "wind_direction"
        case waveHeight = "wave_height"
    }

    public init(timestamp: Date, windSpeed: Double?, windDirection: Double?, waveHeight: Double?) {
        self.timestamp = timestamp
        self.windSpeed = windSpeed
        self.windDirection = windDirection
        self.waveHeight = waveHeight
    }

    public var kmh: Double? { windSpeed.map { $0 * 3.6 } }
    public var knots: Double? { windSpeed.map { $0 * 1.943_84 } }

    /// Windstärke nach Beaufort.
    public var beaufort: Int? {
        guard let windSpeed else { return nil }
        return Self.beaufortLimits.firstIndex { windSpeed < $0 } ?? 12
    }

    static let beaufortLimits = [0.3, 1.6, 3.4, 5.5, 8.0, 10.8, 13.9, 17.2, 20.8, 24.5, 28.5, 32.7]

    public var beaufortName: String {
        guard let beaufort else { return "–" }
        return ["Windstille", "leiser Zug", "leichte Brise", "schwache Brise", "mäßige Brise", "frische Brise",
                "starker Wind", "steifer Wind", "stürmischer Wind", "Sturm", "schwerer Sturm",
                "orkanartiger Sturm", "Orkan"][beaufort]
    }

    /// „SW“ — Himmelsrichtung, aus der der Wind kommt.
    public var compass: String? {
        guard let windDirection else { return nil }
        let names = ["N", "NO", "O", "SO", "S", "SW", "W", "NW"]
        return names[Int((windDirection.truncatingRemainder(dividingBy: 360) + 382.5) / 45) % 8]
    }
}

/// Liest `marine_forecasts` der gewählten Gemeinde — nie die DWD-Dienste direkt.
public nonisolated struct MarineClient: Sendable {
    public init() {}

    public func hours(from start: Date, to end: Date) async throws -> [MarineHour] {
        guard Tenants.current.marine != nil, let tenant = Tenants.current.tenantID else { return [] }
        let stamp = ISO8601DateFormatter()
        let data = try await Backend.client.from("marine_forecasts")
            .select("ts,wind_speed,wind_direction,wave_height")
            .eq("tenant_id", value: tenant.uuidString)
            .gte("ts", value: stamp.string(from: start))
            .lte("ts", value: stamp.string(from: end))
            .order("ts")
            .execute().data
        return try JSONDecoder.api.decode([MarineHour].self, from: data)
    }
}
