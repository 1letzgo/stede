import Foundation

public nonisolated struct HTTPClient: Sendable {
    public let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Live-Dienste, die zuerst über den Server-Zwischenspeicher (Edge Function `upstream`)
    /// laufen; fällt der aus, geht die App wie früher direkt zum Dienst.
    static let proxiedHosts: Set<String> = ["api.brightsky.dev", "luftdaten.umweltbundesamt.de", "dbf.finalrewind.org", "fahrplaner.vbn.de"]

    public func data(from url: URL) async throws -> Data {
        if let host = url.host, Self.proxiedHosts.contains(host),
           var components = URLComponents(url: Backend.url.appendingPathComponent("functions/v1/upstream"), resolvingAgainstBaseURL: false) {
            components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
            if let proxy = components.url, let data = try? await direct(proxy, timeout: 12) {
                return data
            }
        }
        return try await direct(url)
    }

    private func direct(_ url: URL, timeout: TimeInterval = 30) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.invalidResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw AppError.status(http.statusCode)
        }
        return data
    }

    public func get<T: Decodable>(_ url: URL, decoder: JSONDecoder = .api) async throws -> T {
        let data = try await data(from: url)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw AppError.decoding(error.localizedDescription)
        }
    }
}

extension JSONDecoder {
    public nonisolated static var api: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = Self.parseAPIDate(raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unbekanntes Datum: \(raw)"
            )
        }
        return decoder
    }

    nonisolated private static func parseAPIDate(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        if let date = formatter.date(from: raw) {
            return date
        }
        return formatter.date(from: raw.replacingOccurrences(of: " ", with: "T"))
    }
}
