import Foundation

public nonisolated struct FerryTrip: Identifiable, Hashable, Sendable {
    public var id: Int { fahrtnummer }
    public let fahrtnummer: Int
    public let abfahrt: Date
    public let ankunft: Date
    public let ausgangshafen: String
    public let ausgangshafenBezeichnung: String
    public let zielhafen: String
    public let zielhafenBezeichnung: String
    public let ausflug: Bool
    /// Hafenkürzel des Festlands (`tenants.config.ferry.mainland`).
    public let mainland: String
    public let fahrzeugtyp: String
    public let fahrzeug: String
    public let ausgefallen: Bool
    public let auslastungPersonen: Int?
}

public nonisolated struct FerryTripDTO: Decodable, Sendable {
    public let fahrtnummer: Int
    public let abfahrt: Date
    public let ankunft: Date
    public let ausgangshafen: String
    public let ausgangshafenBezeichnung: String
    public let zielhafen: String
    public let zielhafenBezeichnung: String
    public let ausflug: Bool
    public let fahrzeugtyp: String
    public let fahrzeug: String?
    public let ausgefallen: Bool
    public let auslastungPersonen: Int?

    public enum CodingKeys: String, CodingKey {
        case fahrtnummer
        case abfahrt
        case ankunft
        case ausgangshafen
        case ausgangshafenBezeichnung = "ausgangshafen_bezeichnung"
        case zielhafen
        case zielhafenBezeichnung = "zielhafen_bezeichnung"
        case ausflug
        case fahrzeugtyp
        case fahrzeug
        case ausgefallen
        case auslastungPersonen = "auslastung_personen"
    }

    public func asTrip(mainland: String) -> FerryTrip {
        FerryTrip(
            fahrtnummer: fahrtnummer,
            abfahrt: abfahrt,
            ankunft: ankunft,
            ausgangshafen: ausgangshafen,
            ausgangshafenBezeichnung: ausgangshafenBezeichnung,
            zielhafen: zielhafen,
            zielhafenBezeichnung: zielhafenBezeichnung,
            ausflug: ausflug,
            mainland: mainland,
            fahrzeugtyp: fahrzeugtyp,
            fahrzeug: fahrzeug ?? fahrzeugtyp,
            ausgefallen: ausgefallen,
            auslastungPersonen: auslastungPersonen
        )
    }
}

extension FerryTrip {
    public var isToIsland: Bool {
        ausgangshafen == mainland
    }

    public var occupancyFraction: Double? {
        guard let auslastungPersonen else { return nil }
        return min(max(Double(auslastungPersonen) / 100, 0), 1)
    }
}
