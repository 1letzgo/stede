import Foundation
#if os(iOS)
import BackgroundTasks
#endif

/// Gezeiten-Vorausberechnung der Gemeinde (`tenants.config.tides`). Der Server kürzt den
/// BSH-Feed täglich (Edge Function `sync-tides`) und legt ihn in den Bucket `content`; die App
/// fragt das BSH nicht selbst.
public actor TideStore {
    public static let shared = TideStore()
    /// In der Info.plist der App-Hülle unter `BGTaskSchedulerPermittedIdentifiers` eintragen.
    public static let taskIdentifier = (Bundle.main.bundleIdentifier ?? "de.letzgo.stede") + ".refresh-tides"
    public static let maxAge: TimeInterval = 30 * 24 * 60 * 60

    private static var serverURL: URL? {
        Tenants.current.tides.map { Backend.url.appendingPathComponent("storage/v1/object/public/content/\($0.path)") }
    }

    private let http = HTTPClient()
    /// Je Gemeinde, damit ein Wechsel keine fremden Gezeiten zeigt.
    private var cached: (slug: String, station: TideStation)?
    private var cachedStation: TideStation? {
        get { cached?.slug == Tenants.currentSlug ? cached?.station : nil }
        set { cached = newValue.map { (Tenants.currentSlug, $0) } }
    }
    private let fileManager = FileManager.default

    private var directory: URL { CacheMaintenance.directory("tides") }

    private var jsonURL: URL {
        directory.appendingPathComponent("\(Tenants.currentSlug).json")
    }

    /// Die Vorausberechnung reicht übers laufende und nächste Jahr. Nach dem ersten Laden
    /// wird nur neu geladen, wenn die Daten bald enden (oder beim Pull-to-Refresh).
    public static let refreshLeadTime: TimeInterval = 120 * 24 * 60 * 60

    private var didAttemptDownload = false

    public func loadIfNeeded(force: Bool = false) async throws -> TideStation {
        if force {
            do {
                return try await download()
            } catch {
                if let local = localStation() { return local }
                throw error
            }
        }

        let station: TideStation
        if let cachedStation {
            station = cachedStation
        } else if let local = localStation() {
            station = local
        } else {
            return try await download()
        }

        if needsRefresh(station, until: Date().addingTimeInterval(Self.refreshLeadTime)), !didAttemptDownload {
            didAttemptDownload = true
            Task { _ = try? await self.download() }
        }
        return station
    }

    /// Nur Speicher und Disk, ohne Netz — für die Startkarte.
    public func cachedEvents(on day: Date, paddingHours: Int = 16) -> [TideEvent] {
        guard let station = cachedStation ?? localStation() else { return [] }
        return events(from: station, on: day, paddingHours: paddingHours)
    }

    public func events(on day: Date, paddingHours: Int = 16) async throws -> [TideEvent] {
        var station = try await loadIfNeeded()
        // Tag liegt hinter den lokalen Daten: einmal direkt nachladen.
        if needsRefresh(station, until: IslandTime.endOfDay(day)), !didAttemptDownload {
            didAttemptDownload = true
            if let fresh = try? await download() {
                station = fresh
            }
        }
        return events(from: station, on: day, paddingHours: paddingHours)
    }

    private func needsRefresh(_ station: TideStation, until date: Date) -> Bool {
        guard let last = station.events.last?.timestamp else { return true }
        return last < date
    }

    private func events(from station: TideStation, on day: Date, paddingHours: Int) -> [TideEvent] {
        let start = IslandTime.startOfDay(day).addingTimeInterval(TimeInterval(-paddingHours * 3600))
        let end = IslandTime.endOfDay(day).addingTimeInterval(TimeInterval(paddingHours * 3600))
        return station.events.filter { $0.timestamp >= start && $0.timestamp <= end }
    }

    public func refresh(force: Bool) async -> Bool {
        do {
            let station = try await loadIfNeeded()
            if force || needsRefresh(station, until: Date().addingTimeInterval(Self.refreshLeadTime)) {
                _ = try await download()
            }
            return true
        } catch {
            return false
        }
    }

    public static func registerBackgroundRefresh() {
        #if os(iOS)
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            let refreshTask = task as? BGAppRefreshTask
            Task {
                let success = await TideStore.shared.refresh(force: false)
                refreshTask?.setTaskCompleted(success: success)
                scheduleBackgroundRefresh()
            }
        }
        #endif
    }

    public static func scheduleBackgroundRefresh() {
        #if os(iOS)
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: maxAge)
        try? BGTaskScheduler.shared.submit(request)
        #endif
    }

    private func download() async throws -> TideStation {
        guard let url = Self.serverURL else { throw AppError.missingCache }
        let data = try await http.data(from: url)
        let station = try JSONDecoder.api.decode(TideStationDTO.self, from: data).asStation()
        try persist(data: data)
        cachedStation = station
        return station
    }

    private func persist(data: Data) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: jsonURL, options: .atomic)
    }

    /// Der zuletzt geladene Stand von der Platte.
    private func localStation() -> TideStation? {
        guard let station = try? loadFromDisk() else { return nil }
        cachedStation = station
        return station
    }

    private func loadFromDisk() throws -> TideStation {
        guard fileManager.fileExists(atPath: jsonURL.path) else {
            throw AppError.missingCache
        }
        let data = try Data(contentsOf: jsonURL)
        return try JSONDecoder.api.decode(TideStationDTO.self, from: data).asStation()
    }
}
