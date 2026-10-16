import Foundation
import Synchronization

/// Zugriff auf ein ALLRIS-net-Bürgerinfo (`tenants.config.ris.url`, etwa https://ris.westerstede.de/bi/).
///
/// ALLRIS hält Suchfilter und Blättern in der ASP-Session (Cookie): `POST vo040.asp` setzt den
/// Filter, `GET vo040.asp?shownext=true` liefert die nächsten 50. Deshalb hat jede Gemeinde genau
/// einen Client mit eigenem Cookie-Speicher, dessen Aufrufe strikt nacheinander laufen.
/// Seiten und Formularwerte sind ISO-8859-1.
public actor CouncilClient {
    public let baseURL: URL
    private let session: URLSession
    private var tail: Task<Void, Never>?
    /// ASP-Session-Cookies; eigene `HTTPCookieStorage`-Instanzen nimmt URLSession nicht an.
    private var cookies: [String: String] = [:]

    public init(baseURL: URL) {
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration)
    }

    private static let clients = Mutex<[URL: CouncilClient]>([:])

    /// Client der gewählten Gemeinde; nil, wenn sie kein Ratsinformationssystem hat.
    public nonisolated static var current: CouncilClient? {
        guard let raw = Tenants.current.ris?.url, let url = URL(string: raw.hasSuffix("/") ? raw : raw + "/") else { return nil }
        return clients.withLock { clients in
            if let client = clients[url] { return client }
            let client = CouncilClient(baseURL: url)
            clients[url] = client
            return client
        }
    }

    // MARK: Sitzungen

    /// Sitzungen eines Monats.
    public func sessions(year: Int, month: Int) async throws -> [CouncilSession] {
        let html = try await get("si010_e.asp?MM=\(month)&YY=\(year)")
        return CouncilParser.sessions(html, year: year, month: month)
    }

    public func agenda(sessionID: Int) async throws -> CouncilAgenda {
        CouncilParser.agenda(try await get("to010.asp?SILFDNR=\(sessionID)"), sessionID: sessionID)
    }

    /// Adresse der Tagesordnung im Browser.
    public nonisolated func agendaPage(sessionID: Int) -> URL? {
        URL(string: "to010.asp?SILFDNR=\(sessionID)", relativeTo: baseURL)?.absoluteURL
    }

    // MARK: Vorlagen

    /// Erste Seite der Vorlagen, optional nach Betreff gefiltert. Ersetzt den Filter der Session.
    public func papers(search: String? = nil) async throws -> CouncilPaperPage {
        try await serialized { [self] in
            // Der Amtsfilter ist eine eigene Session-Einstellung; 99999999 heißt „(alle)“.
            _ = try await get("vo040.asp?ATLFDNRM=99999999")
            let query = search?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let html = query.isEmpty
                ? try await post("vo040.asp", fields: [("filtreset", "(alle)")])
                : try await post("vo040.asp", fields: [("VO040FIL2", query), ("filtvobetr1", "filter")])
            return CouncilParser.papers(html)
        }
    }

    /// Nächste Seite der Ergebnisse des letzten `papers`-Aufrufs.
    public func nextPapers() async throws -> CouncilPaperPage {
        try await serialized { [self] in CouncilParser.papers(try await get("vo040.asp?shownext=true")) }
    }

    public func paper(id: Int) async throws -> CouncilPaperDetail {
        CouncilParser.paper(try await get("vo020.asp?VOLFDNR=\(id)"), id: id)
    }

    /// Frische, direkt ladbare Adresse eines PDFs — Temp-Pfade laufen ab, also direkt vor dem Öffnen.
    public func documentURL(_ document: CouncilDocument, paperID: Int?) async throws -> URL {
        if let dolfdnr = document.dolfdnr {
            // do027.asp antwortet mit einer Weiterleitung auf das Temp-PDF; gebraucht wird nur die Location.
            var request = request("do027.asp")
            request.httpMethod = "POST"
            request.httpBody = Self.form([("DOLFDNR", "\(dolfdnr)"), ("options", "64")])
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let (_, response) = try await session.data(for: withCookies(request), delegate: NoRedirects())
            remember(response)
            guard let http = response as? HTTPURLResponse,
                  let location = http.value(forHTTPHeaderField: "Location"),
                  let url = resolve(location) else { throw AppError.invalidResponse }
            return url
        }
        // Anlagen: Detailseite neu laden, um einen gültigen Temp-Link zu bekommen.
        var path = document.path
        if let paperID, let fresh = try? await paper(id: paperID).attachments.first(where: { $0.title == document.title })?.path {
            path = fresh
        }
        guard let path, let url = resolve(path) else { throw AppError.invalidURL }
        return url
    }

    // MARK: Netz

    /// Läuft erst, wenn alle vorherigen Session-Aufrufe fertig sind.
    private func serialized<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        let previous = tail
        let task = Task<T, Error> {
            _ = await previous?.value
            return try await operation()
        }
        tail = Task { _ = try? await task.value }
        return try await task.value
    }

    private func resolve(_ path: String) -> URL? {
        if path.hasPrefix("http") { return URL(string: path) }
        var relative = path
        if relative.hasPrefix("/") {
            // „/bi/___tmp/…“: relativ zum Host.
            return URL(string: relative, relativeTo: baseURL)?.absoluteURL
        }
        relative = relative.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? relative
        return URL(string: relative, relativeTo: baseURL)?.absoluteURL
    }

    private func request(_ path: String) -> URLRequest {
        var request = URLRequest(url: URL(string: path, relativeTo: baseURL)?.absoluteURL ?? baseURL)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        return request
    }

    private func withCookies(_ request: URLRequest) -> URLRequest {
        guard !cookies.isEmpty else { return request }
        var request = request
        request.setValue(cookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
        return request
    }

    private func remember(_ response: URLResponse) {
        guard let http = response as? HTTPURLResponse, let url = http.url,
              let headers = http.allHeaderFields as? [String: String] else { return }
        for cookie in HTTPCookie.cookies(withResponseHeaderFields: headers, for: url) {
            cookies[cookie.name] = cookie.value
        }
    }

    private func get(_ path: String) async throws -> String {
        try await load(request(path))
    }

    private func post(_ path: String, fields: [(String, String)]) async throws -> String {
        var request = request(path)
        request.httpMethod = "POST"
        request.httpBody = Self.form(fields)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        return try await load(request)
    }

    private func load(_ request: URLRequest) async throws -> String {
        let (data, response) = try await session.data(for: withCookies(request))
        remember(response)
        guard let http = response as? HTTPURLResponse else { throw AppError.invalidResponse }
        guard (200 ..< 300).contains(http.statusCode) else { throw AppError.status(http.statusCode) }
        return String(data: data, encoding: .isoLatin1) ?? ""
    }

    /// ALLRIS erwartet Formularwerte in ISO-8859-1.
    nonisolated static func form(_ fields: [(String, String)]) -> Data {
        Data(fields.map { latin1Encode($0.0) + "=" + latin1Encode($0.1) }.joined(separator: "&").utf8)
    }

    nonisolated static func latin1Encode(_ value: String) -> String {
        let hex = Array("0123456789ABCDEF")
        var result = ""
        for scalar in value.unicodeScalars {
            let code = scalar.value < 256 ? Int(scalar.value) : Int(("?" as Unicode.Scalar).value)
            switch scalar {
            case "a"..."z", "A"..."Z", "0"..."9", "-", "_", ".", "*": result.unicodeScalars.append(scalar)
            case " ": result += "+"
            default: result += "%" + String(hex[code >> 4]) + String(hex[code & 0xF])
            }
        }
        return result
    }
}

/// Bricht Weiterleitungen ab, damit `do027.asp` seine Location preisgibt statt des PDFs.
private nonisolated final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Letzter Stand von Sitzungen und Vorlagen je Gemeinde (`Application Support/politics/…`),
/// damit Politik offline und sofort etwas zeigt.
public nonisolated enum CouncilCache {
    public static func load<T: Decodable>(_ name: String, as type: T.Type = T.self) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    public static func save(_ value: some Encodable, as name: String) {
        let url = url(name)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(value).write(to: url, options: .atomic)
    }

    private static func url(_ name: String) -> URL {
        CacheMaintenance.directory("politics", tenant: Tenants.currentSlug).appendingPathComponent("\(name).json")
    }
}
