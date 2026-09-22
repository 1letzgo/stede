import Foundation

/// Straße aus dem Abfuhrkalender des Landkreises Ammerland (appfuhr.de).
/// Einige Straßen sind in Abschnitte geteilt — dann muss der Nutzer seinen wählen.
public nonisolated struct WasteStreet: Identifiable, Hashable, Sendable, Decodable {
    public let id: Int
    public let name: String
    /// Straßenabschnitte für die Regelabfuhr („Ocholt" / „Westerstede").
    public let sections: [WasteSection]?
    /// Abschnitte nur für die Ast- und Strauchwerk-Abfuhr.
    public let branchSections: [WasteSection]?

    public var needsSection: Bool { (sections?.count ?? 0) > 1 }
    public var needsBranchSection: Bool { (branchSections?.count ?? 0) > 1 }
}

public nonisolated struct WasteSection: Identifiable, Hashable, Sendable, Decodable {
    public let id: Int
    public let label: String
}

public nonisolated struct WasteStreetDirectory: Sendable, Decodable {
    public let source: String
    public let fetchedAt: String
    public let townID: Int
    public let town: String
    public let streets: [WasteStreet]

    public func street(id: Int) -> WasteStreet? {
        streets.first { $0.id == id }
    }
}

public nonisolated enum WasteStreetStore {
    /// Alle Straßen Westerstedes, einmalig von appfuhr.de übernommen (`tbl=str&ort=5`).
    public static let directory: WasteStreetDirectory = {
        guard
            let url = Bundle.module.url(forResource: "abfuhr-strassen", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let directory = try? JSONDecoder().decode(WasteStreetDirectory.self, from: data)
        else {
            assertionFailure("abfuhr-strassen.json fehlt im Bundle oder ist ungültig")
            return WasteStreetDirectory(source: "", fetchedAt: "", townID: 5, town: "Westerstede", streets: [])
        }
        return directory
    }()
}

/// Abfallart, wie sie im Kalender heißt.
public nonisolated enum WasteKind: String, Hashable, Sendable, Codable, CaseIterable {
    case residual = "Restabfall"
    case paper = "Papier"
    case yellowBag = "Gelber Sack"
    case organic = "Bioabfall"
    case branches = "Ast- und Strauchwerk"
    case hazardous = "Problemstoffe"
    case other = "Sonstiges"

    public init(label: String) {
        self = WasteKind.allCases.first { $0.rawValue == label } ?? .other
    }

    public var title: String { rawValue }

    /// SF Symbol je Art.
    public var symbol: String {
        switch self {
        case .residual: "trash.fill"
        case .paper: "newspaper.fill"
        case .yellowBag: "bag.fill"
        case .organic: "leaf.fill"
        case .branches: "tree.fill"
        case .hazardous: "exclamationmark.triangle.fill"
        case .other: "trash"
        }
    }
}

/// Ein Abfuhrtermin.
public nonisolated struct WasteCollection: Identifiable, Hashable, Sendable, Codable {
    public let date: Date
    public let kind: WasteKind
    public let label: String

    public var id: String { "\(IslandTime.isoDate(date))|\(label)" }
}

/// Gewählte Straße samt Abschnitten — der Schlüssel für Abruf und Cache.
public nonisolated struct WasteSelection: Hashable, Sendable, Codable {
    public let streetID: Int
    public let sectionID: Int?
    public let branchSectionID: Int?

    public init(streetID: Int, sectionID: Int? = nil, branchSectionID: Int? = nil) {
        self.streetID = streetID
        self.sectionID = sectionID
        self.branchSectionID = branchSectionID
    }

    public var cacheKey: String {
        "\(streetID)-\(sectionID ?? 0)-\(branchSectionID ?? 0)"
    }
}

/// Liest den Text des appfuhr.de-PDFs: Zeilen wie „Freitag, 2.1. Restabfall".
/// Monatsnamen und Fußzeilen stehen dazwischen und werden übersprungen.
public nonisolated enum WastePDFParser: Sendable {
    public static func collections(from text: String, year: Int) -> [WasteCollection] {
        guard let regex = try? NSRegularExpression(pattern: #"^\s*(?:Montag|Dienstag|Mittwoch|Donnerstag|Freitag|Samstag|Sonntag),\s*(\d{1,2})\.(\d{1,2})\.\s+(.+?)\s*$"#) else {
            return []
        }
        var seen = Set<String>()
        var result: [WasteCollection] = []
        for line in text.components(separatedBy: .newlines) {
            let ns = line as NSString
            guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
                  let day = Int(ns.substring(with: match.range(at: 1))),
                  let month = Int(ns.substring(with: match.range(at: 2)))
            else { continue }
            let label = ns.substring(with: match.range(at: 3))
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            guard let date = IslandTime.calendar.date(from: components) else { continue }
            let collection = WasteCollection(date: IslandTime.startOfDay(date), kind: WasteKind(label: label), label: label)
            if seen.insert(collection.id).inserted {
                result.append(collection)
            }
        }
        return result.sorted { $0.date < $1.date }
    }
}
