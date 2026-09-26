import Foundation

/// Ablage- und Aufräumregeln für alle tagesbezogenen Caches.
public nonisolated enum CacheMaintenance: Sendable {
    public static let retentionDays = 7
    public static let dayCacheNames = ["events", "weather"]

    public static func directory(_ name: String) -> URL {
        let manager = FileManager.default
        let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? manager.temporaryDirectory
        return base.appendingPathComponent(name, isDirectory: true)
    }

    /// Ordner eines Tagescaches für eine Gemeinde; Westerstede behält den alten Ort.
    public static func directory(_ name: String, tenant slug: String) -> URL {
        slug == Tenants.defaultSlug ? directory(name) : directory(name).appendingPathComponent("tenants/\(slug)", isDirectory: true)
    }

    /// Entfernt alle Tagesdateien, deren Datum mehr als `retentionDays` zurückliegt.
    public static func purgeExpired(reference: Date = Date()) {
        let manager = FileManager.default
        guard let limit = IslandTime.calendar.date(
            byAdding: .day,
            value: -retentionDays,
            to: IslandTime.startOfDay(reference)
        ) else { return }

        let folders = dayCacheNames.flatMap { name in
            [directory(name)] + Tenants.all.filter { $0.slug != Tenants.defaultSlug }.map { directory(name, tenant: $0.slug) }
        }
        for folder in folders {
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
public actor DayCache<Value: Codable & Sendable> {
    private let name: String
    private let maxAge: TimeInterval
    private let fileManager = FileManager.default
    private var memory: [String: CachedDay<Value>] = [:]

    public init(name: String, maxAge: TimeInterval) {
        self.name = name
        self.maxAge = maxAge
    }

    /// Schlüssel je Gemeinde und Tag — ein Gemeindewechsel sieht keine fremden Tage.
    private func key(_ day: Date) -> String {
        "\(Tenants.currentSlug)/\(IslandTime.isoDate(day))"
    }

    public func peek(on day: Date) -> Value? {
        cached(for: key(day))?.value
    }

    /// Nur ein noch gültiger Eintrag — für Bereichsabfragen, die sonst neu laden.
    public func fresh(on day: Date) -> Value? {
        guard let entry = cached(for: key(day)), !isStale(entry, day: day) else { return nil }
        return entry.value
    }

    /// Von außen geholten Wert ablegen (eine Bereichsabfrage füllt viele Tage auf einmal).
    public func store(_ value: Value, on day: Date) {
        let key = key(day)
        let entry = CachedDay(fetchedAt: Date(), value: value)
        memory[key] = entry
        try? persist(entry, key: key)
    }

    public func value(
        on day: Date,
        force: Bool,
        fetch: @Sendable () async throws -> Value
    ) async throws -> Value {
        let key = key(day)

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
        let url = fileURL(for: key)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(entry)
        try data.write(to: url, options: .atomic)
    }

    /// `<slug>/<Tag>` → Datei im Ordner der Gemeinde.
    private func fileURL(for key: String) -> URL {
        let parts = key.split(separator: "/", maxSplits: 1).map(String.init)
        return CacheMaintenance.directory(name, tenant: parts[0]).appendingPathComponent("\(parts[1]).json")
    }
}

public nonisolated struct CachedDay<Value: Codable & Sendable>: Codable, Sendable {
    public let fetchedAt: Date
    public let value: Value
}
