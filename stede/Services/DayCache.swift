import Foundation

/// Ablage- und Aufräumregeln für alle tagesbezogenen Caches.
nonisolated enum CacheMaintenance: Sendable {
    static let retentionDays = 7
    static let dayCacheNames = ["events", "weather", "air"]

    static func directory(_ name: String) -> URL {
        let manager = FileManager.default
        let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? manager.temporaryDirectory
        return base.appendingPathComponent(name, isDirectory: true)
    }

    /// Entfernt alle Tagesdateien, deren Datum mehr als `retentionDays` zurückliegt.
    static func purgeExpired(reference: Date = Date()) {
        let manager = FileManager.default
        guard let limit = IslandTime.calendar.date(
            byAdding: .day,
            value: -retentionDays,
            to: IslandTime.startOfDay(reference)
        ) else { return }

        for name in dayCacheNames {
            let folder = directory(name)
            guard let files = try? manager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: nil
            ) else { continue }

            for file in files where file.pathExtension == "json" {
                guard let day = IslandTime.date(fromISO: file.deletingPathExtension().lastPathComponent),
                      day < limit
                else { continue }
                try? manager.removeItem(at: file)
            }
        }
    }
}

/// Tagesweiser Disk-Cache für API-Antworten.
actor DayCache<Value: Codable & Sendable> {
    private let name: String
    private let maxAge: TimeInterval
    private let fileManager = FileManager.default
    private var memory: [String: CachedDay<Value>] = [:]

    init(name: String, maxAge: TimeInterval) {
        self.name = name
        self.maxAge = maxAge
    }

    func peek(on day: Date) -> Value? {
        cached(for: IslandTime.isoDate(day))?.value
    }

    func value(
        on day: Date,
        force: Bool,
        fetch: @Sendable () async throws -> Value
    ) async throws -> Value {
        let key = IslandTime.isoDate(day)

        if !force, let cached = cached(for: key), !isStale(cached, day: day) {
            return cached.value
        }

        do {
            let fresh = try await fetch()
            let entry = CachedDay(fetchedAt: Date(), value: fresh)
            memory[key] = entry
            try? persist(entry, key: key)
            CacheMaintenance.purgeExpired()
            return fresh
        } catch {
            if let cached = cached(for: key) {
                return cached.value
            }
            throw error
        }
    }

    private func cached(for key: String) -> CachedDay<Value>? {
        if let entry = memory[key] {
            return entry
        }
        guard let data = try? Data(contentsOf: fileURL(for: key)),
              let entry = try? JSONDecoder().decode(CachedDay<Value>.self, from: data)
        else { return nil }
        memory[key] = entry
        return entry
    }

    private func isStale(_ entry: CachedDay<Value>, day: Date) -> Bool {
        // Vergangene Tage ändern sich nicht mehr, deren Cache bleibt bis zum Aufräumen gültig.
        if IslandTime.endOfDay(day) < entry.fetchedAt {
            return false
        }
        return Date().timeIntervalSince(entry.fetchedAt) >= maxAge
    }

    private func persist(_ entry: CachedDay<Value>, key: String) throws {
        let folder = CacheMaintenance.directory(name)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(entry)
        try data.write(to: fileURL(for: key), options: .atomic)
    }

    private func fileURL(for key: String) -> URL {
        CacheMaintenance.directory(name).appendingPathComponent("\(key).json")
    }
}

nonisolated struct CachedDay<Value: Codable & Sendable>: Codable, Sendable {
    let fetchedAt: Date
    let value: Value
}
