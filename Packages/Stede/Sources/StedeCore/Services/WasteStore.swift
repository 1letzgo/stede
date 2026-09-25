import Foundation
#if canImport(PDFKit)
import PDFKit
#endif

/// Holt den Abfuhrkalender von appfuhr.de: Der Dienst kennt nur PDF-Export —
/// `makekal.php` bereitet die Termine unter einer zufälligen ID vor,
/// `makepdf.php` setzt das PDF, das dann unter `/pdf/tmp/<id>.pdf` liegt.
public nonisolated struct WasteClient: Sendable {
    private static let base = "https://www.appfuhr.de"

    let http: HTTPClient

    public init(http: HTTPClient = HTTPClient()) {
        self.http = http
    }

    public func collections(for selection: WasteSelection, year: Int) async throws -> [WasteCollection] {
        // Erst der Server (Edge Function `waste-calendar`, PDF 7 Tage zwischengespeichert),
        // dann wie früher direkt bei appfuhr.de.
        if let data = try? await serverPDF(for: selection, year: year),
           let text = try? Self.text(from: data) {
            let collections = WastePDFParser.collections(from: text, year: year)
            if !collections.isEmpty { return collections }
        }
        return try await directCollections(for: selection, year: year)
    }

    private func serverPDF(for selection: WasteSelection, year: Int) async throws -> Data {
        guard var components = URLComponents(url: Backend.url.appendingPathComponent("functions/v1/waste-calendar"), resolvingAgainstBaseURL: false)
        else { throw AppError.invalidURL }
        components.queryItems = [
            URLQueryItem(name: "street", value: String(selection.streetID)),
            URLQueryItem(name: "year", value: String(year)),
            URLQueryItem(name: "section", value: selection.sectionID.map(String.init) ?? ""),
            URLQueryItem(name: "branch", value: selection.branchSectionID.map(String.init) ?? ""),
        ]
        guard let url = components.url else { throw AppError.invalidURL }
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 25))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AppError.invalidResponse }
        return data
    }

    private func directCollections(for selection: WasteSelection, year: Int) async throws -> [WasteCollection] {
        let id = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        let shortYear = String(format: "%02d", year % 100)
        let section = selection.sectionID.map(String.init) ?? "null"
        let branch = selection.branchSectionID.map(String.init) ?? "null"
        guard
            let prepare = URL(string: "\(Self.base)/api/makekal.php?uid=\(id)&str=\(selection.streetID)&strgr=\(section)&astgr=\(branch)&komp=false&vier=false&jahr=\(shortYear)&max=999"),
            let render = URL(string: "\(Self.base)/pdf/makepdf.php?uuid=\(id)&str=\(selection.streetID)&jahr=\(shortYear)&sw=false"),
            let pdf = URL(string: "\(Self.base)/pdf/tmp/\(id).pdf")
        else { throw AppError.invalidURL }

        _ = try await http.data(from: prepare)
        _ = try await http.data(from: render)
        let data = try await http.data(from: pdf)
        let text = try Self.text(from: data)
        let collections = WastePDFParser.collections(from: text, year: year)
        guard !collections.isEmpty else {
            throw AppError.decoding("Der Abfuhrkalender enthält keine Termine.")
        }
        return collections
    }

    private static func text(from data: Data) throws -> String {
        #if canImport(PDFKit)
        guard let document = PDFDocument(data: data) else {
            throw AppError.decoding("Das PDF von appfuhr.de ließ sich nicht öffnen.")
        }
        return (0 ..< document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
        #else
        throw AppError.decoding("PDF-Lesen wird auf dieser Plattform nicht unterstützt.")
        #endif
    }
}

/// Termine je Straße und Jahr — der Kalender ändert sich nur jährlich, also
/// lange auf der Platte halten; am Jahreswechsel kommt das Folgejahr dazu.
public actor WasteStore {
    public static let shared = WasteStore()

    private let client = WasteClient()
    private let fileManager = FileManager.default
    private var memory: [String: [WasteCollection]] = [:]

    private func key(_ selection: WasteSelection, _ year: Int) -> String {
        "\(selection.cacheKey)-\(year)"
    }

    private func fileURL(_ key: String) -> URL {
        CacheMaintenance.directory("waste").appendingPathComponent("\(key).json")
    }

    public func cached(for selection: WasteSelection, year: Int) -> [WasteCollection]? {
        let key = key(selection, year)
        if let hit = memory[key] { return hit }
        guard let data = try? Data(contentsOf: fileURL(key)),
              let list = try? JSONDecoder().decode([WasteCollection].self, from: data)
        else { return nil }
        memory[key] = list
        return list
    }

    public func collections(for selection: WasteSelection, year: Int, force: Bool = false) async throws -> [WasteCollection] {
        let key = key(selection, year)
        if !force, let hit = cached(for: selection, year: year) {
            return hit
        }
        let fresh = try await client.collections(for: selection, year: year)
        memory[key] = fresh
        let folder = CacheMaintenance.directory("waste")
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(fresh) {
            try? data.write(to: fileURL(key), options: .atomic)
        }
        return fresh
    }

    /// Kommende Termine ab heute: dieses Jahr, ab Dezember auch das nächste.
    public func upcoming(for selection: WasteSelection, force: Bool = false, now: Date = Date()) async throws -> [WasteCollection] {
        let year = IslandTime.calendar.component(.year, from: now)
        var all = try await collections(for: selection, year: year, force: force)
        if IslandTime.calendar.component(.month, from: now) >= 12 {
            all += (try? await collections(for: selection, year: year + 1, force: force)) ?? []
        }
        let today = IslandTime.startOfDay(now)
        return all.filter { $0.date >= today }.sorted { $0.date < $1.date }
    }
}
