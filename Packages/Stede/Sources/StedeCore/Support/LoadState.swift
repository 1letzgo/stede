import Foundation

public nonisolated enum LoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case empty
    case failed(String)

    public static func == (lhs: LoadState, rhs: LoadState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.loaded, .loaded), (.empty, .empty):
            true
        case let (.failed(a), .failed(b)):
            a == b
        default:
            false
        }
    }
}

public nonisolated enum AppError: LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case status(Int)
    case decoding(String)
    case missingCache

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Ungültige Adresse."
        case .invalidResponse:
            "Ungültige Serverantwort."
        case .status(let code):
            "Serverfehler (\(code))."
        case .decoding(let detail):
            "Daten konnten nicht gelesen werden. \(detail)"
        case .missingCache:
            "Keine gespeicherten Daten."
        }
    }
}
