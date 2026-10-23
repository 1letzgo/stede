import Foundation
import Observation
import StedeCore

/// Sitzungskalender: zeigt den letzten Stand sofort, lädt den laufenden und die zwei folgenden
/// Monate nach; „Frühere Sitzungen“ holt Monat für Monat zurück.
@Observable
final class CouncilSessionsModel {
    private(set) var sessions: [CouncilSession] = []
    private(set) var state: LoadState = .idle
    /// Vergangene Sitzungen sichtbar (nach „Frühere Sitzungen“).
    private(set) var showsPast = false
    private(set) var loadingEarlier = false
    /// Frühester geladener Monat (Jahr * 12 + Monat - 1).
    private var firstMonth: Int?

    private nonisolated struct Snapshot: Codable {
        let fetchedAt: Date
        let sessions: [CouncilSession]
    }

    /// Sitzungen, die noch nicht vorbei sind (Ende, sonst Beginn plus drei Stunden).
    var upcoming: [CouncilSession] {
        let now = Date()
        return sessions.filter { ($0.end ?? $0.start.addingTimeInterval(3 * 3600)) >= now }
    }

    var visible: [CouncilSession] { showsPast ? sessions : upcoming }

    func load(force: Bool) async {
        guard let client = CouncilClient.current else { state = .empty; return }
        var hadCache = !sessions.isEmpty
        if sessions.isEmpty, let snapshot = CouncilCache.load("sessions", as: Snapshot.self) {
            sessions = snapshot.sessions
            hadCache = true
            state = .loaded
            // Start lädt höchstens alle 30 Minuten neu.
            if !force, Date().timeIntervalSince(snapshot.fetchedAt) < 1800 { return }
        }
        if !hadCache { state = .loading }
        let current = Self.monthIndex(Date())
        do {
            let fresh = try await withThrowingTaskGroup(of: [CouncilSession].self) { group in
                for offset in 0..<3 {
                    let (year, month) = Self.yearMonth(current + offset)
                    group.addTask { try await client.sessions(year: year, month: month) }
                }
                return try await group.reduce(into: []) { $0 += $1 }
            }
            // Früher geladene Monate behalten.
            let older = sessions.filter { Self.monthIndex($0.start) < current }
            sessions = Self.sorted(older + fresh)
            firstMonth = min(firstMonth ?? current, current)
            state = sessions.isEmpty ? .empty : .loaded
            CouncilCache.save(Snapshot(fetchedAt: Date(), sessions: fresh), as: "sessions")
        } catch {
            if !hadCache { state = .failed(error.localizedDescription) }
        }
    }

    /// Zeigt vergangene Sitzungen und lädt jeweils einen Monat weiter zurück.
    func loadEarlier() async {
        guard let client = CouncilClient.current, !loadingEarlier else { return }
        let month = (firstMonth ?? Self.monthIndex(Date())) - (showsPast ? 1 : 0)
        showsPast = true
        // Der laufende Monat ist schon da; vergangene Sitzungen darin reichen fürs erste Antippen.
        guard month < (firstMonth ?? .max) else { return }
        loadingEarlier = true
        defer { loadingEarlier = false }
        let (year, monthOfYear) = Self.yearMonth(month)
        if let earlier = try? await client.sessions(year: year, month: monthOfYear) {
            sessions = Self.sorted(sessions.filter { Self.monthIndex($0.start) != month } + earlier)
            firstMonth = month
        }
    }

    private static func sorted(_ sessions: [CouncilSession]) -> [CouncilSession] {
        var seen = Set<Int>()
        return sessions.sorted { $0.start < $1.start }.filter { seen.insert($0.id).inserted }
    }

    static func monthIndex(_ date: Date) -> Int {
        let parts = IslandTime.calendar.dateComponents([.year, .month], from: date)
        return (parts.year ?? 0) * 12 + (parts.month ?? 1) - 1
    }

    static func yearMonth(_ index: Int) -> (Int, Int) { (index / 12, index % 12 + 1) }
}

/// Vorlagenliste mit Suche im Betreff und Nachladen in 50er-Seiten.
@Observable
final class CouncilPapersModel {
    private(set) var items: [CouncilPaper] = []
    private(set) var state: LoadState = .idle
    private(set) var hasNext = false
    private(set) var approximateTotal: Int?
    private(set) var loadingMore = false
    /// Suchbegriff der angezeigten Liste.
    private(set) var query = ""

    private nonisolated struct Snapshot: Codable {
        let fetchedAt: Date
        let items: [CouncilPaper]
    }

    /// Für die Kachel auf Start: neueste Vorlagen aus dem Cache, höchstens alle 30 Minuten neu.
    func loadLatest() async {
        if items.isEmpty, let snapshot = CouncilCache.load("papers", as: Snapshot.self) {
            items = snapshot.items
            state = .loaded
            if Date().timeIntervalSince(snapshot.fetchedAt) < 1800 { return }
        }
        await search("")
    }

    func search(_ text: String) async {
        guard let client = CouncilClient.current else { state = .empty; return }
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let showsCache = query.isEmpty && self.query.isEmpty && !items.isEmpty
        if !showsCache {
            if items.isEmpty, query.isEmpty, let snapshot = CouncilCache.load("papers", as: Snapshot.self) {
                items = snapshot.items
                state = .loaded
            } else {
                items = []
                state = .loading
            }
        }
        self.query = query
        do {
            let page = try await client.papers(search: query)
            guard self.query == query else { return }
            items = page.items
            hasNext = page.hasNext
            approximateTotal = page.approximateTotal
            state = items.isEmpty ? .empty : .loaded
            if query.isEmpty { CouncilCache.save(Snapshot(fetchedAt: Date(), items: page.items), as: "papers") }
        } catch {
            guard self.query == query else { return }
            if items.isEmpty { state = .failed(error.localizedDescription) }
        }
    }

    /// Lädt die nächste Seite, sobald eine der letzten Zeilen erscheint.
    func loadMoreIfNeeded(current: CouncilPaper) async {
        guard hasNext, !loadingMore, let client = CouncilClient.current,
              let index = items.firstIndex(where: { $0.id == current.id }), index >= items.count - 5 else { return }
        loadingMore = true
        defer { loadingMore = false }
        let query = self.query
        guard let page = try? await client.nextPapers(), self.query == query else { return }
        let known = Set(items.map(\.id))
        items += page.items.filter { !known.contains($0.id) }
        hasNext = page.hasNext
    }
}

/// Tagesordnung einer Sitzung.
@Observable
final class CouncilAgendaModel {
    private(set) var agenda: CouncilAgenda?
    private(set) var state: LoadState = .idle

    func load(sessionID: Int, force: Bool = false) async {
        guard let client = CouncilClient.current else { state = .empty; return }
        if agenda != nil, !force { return }
        if agenda == nil, let cached = CouncilCache.load("agenda-\(sessionID)", as: CouncilAgenda.self) {
            agenda = cached
            state = .loaded
        }
        if agenda == nil { state = .loading }
        do {
            let fresh = try await client.agenda(sessionID: sessionID)
            agenda = fresh
            state = .loaded
            CouncilCache.save(fresh, as: "agenda-\(sessionID)")
        } catch {
            if agenda == nil { state = .failed(error.localizedDescription) }
        }
    }
}

/// Eine Vorlage mit Beratungsfolge, Texten und PDFs.
@Observable
final class CouncilPaperModel {
    private(set) var paper: CouncilPaperDetail?
    private(set) var state: LoadState = .idle

    func load(id: Int, force: Bool = false) async {
        guard let client = CouncilClient.current else { state = .empty; return }
        if paper != nil, !force { return }
        if paper == nil { state = .loading }
        do {
            paper = try await client.paper(id: id)
            state = .loaded
        } catch {
            if paper == nil { state = .failed(error.localizedDescription) }
        }
    }
}

/// Öffnet PDFs aus dem Ratsinfo: die Temp-Adresse wird erst beim Antippen geholt.
@Observable
final class CouncilDocumentOpener {
    var page: BrowserPage?
    var error: String?
    private(set) var opening: String?

    func open(_ document: CouncilDocument, paperID: Int?) async {
        guard let client = CouncilClient.current else { return }
        opening = document.id
        defer { opening = nil }
        do {
            page = BrowserPage(url: try await client.documentURL(document, paperID: paperID))
        } catch {
            self.error = "„\(document.title)“ ist gerade nicht abrufbar. \(error.localizedDescription)"
        }
    }
}

/// Ratssitzungen für den Kalender: lädt die Monate des sichtbaren Bereichs aus dem Ratsinfo
/// (nur mit dem Baustein `politics`) und merkt sie sich für die Sitzung.
@Observable
final class CouncilCalendarModel {
    private(set) var sessions: [CouncilSession] = []
    private var loadedMonths: Set<Int> = []

    func load(from start: Date, to end: Date) async {
        guard Features.has(.politics), let client = CouncilClient.current else { sessions = []; return }
        let current = CouncilSessionsModel.monthIndex(Date())
        let months = CouncilSessionsModel.monthIndex(start)...CouncilSessionsModel.monthIndex(end)
        // Vergangene Monate ändern sich nicht mehr; laufende und künftige je Aufruf frisch.
        let needed = months.filter { !loadedMonths.contains($0) || $0 >= current }
        guard !needed.isEmpty else { return }
        var fresh: [Int: [CouncilSession]] = [:]
        await withTaskGroup(of: (Int, [CouncilSession]?).self) { group in
            for month in needed {
                let (year, monthOfYear) = CouncilSessionsModel.yearMonth(month)
                group.addTask { (month, try? await client.sessions(year: year, month: monthOfYear)) }
            }
            for await (month, list) in group { if let list { fresh[month] = list } }
        }
        let kept = sessions.filter { fresh[CouncilSessionsModel.monthIndex($0.start)] == nil }
        sessions = (kept + fresh.values.flatMap { $0 }).sorted { $0.start < $1.start }
        loadedMonths.formUnion(fresh.keys)
    }

    /// Ist ein importierter Termin (westerstede.de) dieselbe Sitzung? Gleicher Tag und gleicher Titel
    /// bzw. Gremium im Titel — dann zeigt der Kalender nur die Sitzung aus dem Ratsinfo.
    func matches(title: String, at date: Date) -> Bool {
        let day = IslandTime.startOfDay(date)
        return sessions.contains { session in
            IslandTime.startOfDay(session.start) == day
                && (title.localizedCaseInsensitiveCompare(session.title) == .orderedSame
                    || title.localizedCaseInsensitiveContains(session.committee))
        }
    }
}
