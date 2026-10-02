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
    /// Alle Straßen der Gemeinde, von appfuhr.de übernommen (`tbl=str&ort=<Ort>`).
    public static var directory: WasteStreetDirectory { store.value }

    private static let store = TenantScoped { () -> WasteStreetDirectory in
        // Stand aus dem Backend (`content_files`), sonst das Bundle.
        if let data = ContentFiles.data("abfuhr-strassen"),
           let directory = try? JSONDecoder().decode(WasteStreetDirectory.self, from: data), !directory.streets.isEmpty {
            return directory
        }
        let tenant = Tenants.current
        guard
            Tenants.usesBundle,
            let url = Bundle.module.url(forResource: "abfuhr-strassen", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let directory = try? JSONDecoder().decode(WasteStreetDirectory.self, from: data)
        else {
            return WasteStreetDirectory(source: "", fetchedAt: "", townID: tenant.wasteTownID, town: tenant.municipality, streets: [])
        }
        return directory
    }
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
    /// Eigenkompostierer: keine Biotonne (appfuhr `komp=true`).
    public let noOrganic: Bool
    /// Restabfall nur alle 4 Wochen (appfuhr `vier=true`).
    public let fourWeekly: Bool

    public init(streetID: Int, sectionID: Int? = nil, branchSectionID: Int? = nil, noOrganic: Bool = false, fourWeekly: Bool = false) {
        self.streetID = streetID
        self.sectionID = sectionID
        self.branchSectionID = branchSectionID
        self.noOrganic = noOrganic
        self.fourWeekly = fourWeekly
    }

    enum CodingKeys: String, CodingKey { case streetID, sectionID, branchSectionID, noOrganic, fourWeekly }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        streetID = try c.decode(Int.self, forKey: .streetID)
        sectionID = try c.decodeIfPresent(Int.self, forKey: .sectionID)
        branchSectionID = try c.decodeIfPresent(Int.self, forKey: .branchSectionID)
        noOrganic = try c.decodeIfPresent(Bool.self, forKey: .noOrganic) ?? false
        fourWeekly = try c.decodeIfPresent(Bool.self, forKey: .fourWeekly) ?? false
    }

    /// Ohne Optionen wie bisher; jede Option bekommt einen eigenen Cache-Eintrag.
    public var cacheKey: String {
        "\(streetID)-\(sectionID ?? 0)-\(branchSectionID ?? 0)" + (noOrganic ? "-nobio" : "") + (fourWeekly ? "-4w" : "")
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
        // Zwei Abfuhren am selben Tag: Das PDF nennt das Datum nur einmal, die zweite Art
        // („Gelber Sack“, „Ast- und Strauchwerk“) steht allein in der Folgezeile — oft mit
        // Monatsnamen dazwischen. Sie gehört zum zuletzt genannten Datum.
        var lastDate: Date?
        func add(_ date: Date, _ label: String) {
            let collection = WasteCollection(date: date, kind: WasteKind(label: label), label: label)
            if seen.insert(collection.id).inserted {
                result.append(collection)
            }
        }
        for line in text.components(separatedBy: .newlines) {
            let ns = line as NSString
            guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else {
                let label = line.trimmingCharacters(in: .whitespaces)
                if let lastDate, WasteKind(label: label) != .other { add(lastDate, label) }
                continue
            }
            guard let day = Int(ns.substring(with: match.range(at: 1))),
                  let month = Int(ns.substring(with: match.range(at: 2)))
            else { continue }
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            guard let date = IslandTime.calendar.date(from: components) else { continue }
            let start = IslandTime.startOfDay(date)
            lastDate = start
            add(start, ns.substring(with: match.range(at: 3)))
        }
        return result.sorted { $0.date < $1.date }
    }
}
