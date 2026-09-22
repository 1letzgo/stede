import Foundation

/// Eine Veranstaltung aus dem Kalender der Stadt Westerstede (westerstede.de).
nonisolated struct StedeEvent: Identifiable, Hashable, Sendable, Codable {
    let id: Int
    let title: String
    let time: Date?
    let endTime: Date?
    let summary: String
    let location: String?
    let organizer: String?
    let category: String?
    /// Etwa „Jede Woche am Dienstag" bei Serienterminen.
    let seriesNote: String?
    let detailURL: URL?

    var timeLabel: String? {
        guard let time else { return nil }
        let style = Date.FormatStyle(date: .omitted, time: .shortened).locale(IslandTime.germanLocale)
        guard let endTime else { return time.formatted(style) }
        return "\(time.formatted(style))–\(endTime.formatted(style))"
    }
}

/// Liest die Trefferliste der Veranstaltungssuche auf westerstede.de (NOLIS-Manager).
/// Jeder Treffer beginnt mit einem Anker `terminanker_<id>`, darunter der Kopf
/// mit Detail- und iCal-Link und der Block `veranstaltung_grunddaten`.
nonisolated enum EventHTMLParser: Sendable {
    static func events(from html: String, on day: Date) -> [StedeEvent] {
        let blocks = html.components(separatedBy: "<a name=\"terminanker_")
        guard blocks.count > 1 else { return [] }

        var parsed: [StedeEvent] = []
        var seen = Set<Int>()
        for block in blocks.dropFirst() {
            guard let event = parseBlock(block, on: day), seen.insert(event.id).inserted else { continue }
            parsed.append(event)
        }
        return parsed
    }

    /// „Seite 1 von 3" — steht nur bei mehr als einer Seite.
    static func pageCount(from html: String) -> Int {
        guard let text = firstMatch(#"Seite \d+ von (\d+)"#, in: html), let count = Int(text) else { return 1 }
        return max(count, 1)
    }

    private static func parseBlock(_ raw: String, on day: Date) -> StedeEvent? {
        guard let idText = firstMatch(#"^(\d+)""#, in: raw), let id = Int(idText) else { return nil }
        guard let title = firstMatch(#"<span class="bezeichnung">(.*?)</span>"#, in: raw).map(stripTags),
              !title.isEmpty
        else { return nil }

        let detailURL = firstMatch(
            #"href="(https://www\.westerstede\.de/regional/veranstaltungen/[^"?]+\.html)[^"]*"\s+title="Detailseite""#,
            in: raw
        ).flatMap(URL.init(string:))

        // Der Datumsblock reicht bis zum nächsten Feld; darin stecken auch
        // Endzeit und der Serienhinweis als Bildtitel.
        let dateBlock = firstMatch(#"<span class="datum">(.*?)(?=<div class="|</div>)"#, in: raw) ?? ""
        let seriesNote = firstMatch(#"<img[^>]*title="([^"]*)""#, in: dateBlock).map(stripTags)
        let (time, endTime) = times(from: stripTags(dateBlock), on: day)

        let summary = firstMatch(#"<div class="kurzbeschreibung">(.*?)</div>"#, in: raw).map(stripTags) ?? ""
        let location = field("veranstaltungsort", in: raw)
        let organizer = field("veranstalter", in: raw)
        let category = firstMatch(#"<div class="rubriken">\s*Rubrik:\s*(.*?)(?:<br|</div>)"#, in: raw)
            .map(stripTags)
            .flatMap { $0.isEmpty ? nil : $0 }

        return StedeEvent(
            id: id,
            title: title,
            time: time,
            endTime: endTime,
            summary: summary,
            location: location,
            organizer: organizer,
            category: category,
            seriesNote: seriesNote,
            detailURL: detailURL
        )
    }

    /// Inhalt eines Feldes wie `veranstaltungsort`: Zeilenumbrüche werden zu Kommas,
    /// die Karten- und Mail-Links fallen weg.
    private static func field(_ name: String, in raw: String) -> String? {
        guard let inner = firstMatch(
            #"<div class="\#(name)">.*?<span class="feldinhalt">(.*?)</div>"#,
            in: raw
        ) else { return nil }
        let withBreaks = inner
            .replacingOccurrences(of: #"<br\s*/?>"#, with: ", ", options: .regularExpression)
            .replacingOccurrences(of: #"<a class="link_navigator.*?</a>"#, with: " ", options: .regularExpression)
        var text = stripTags(withBreaks)
        text = text.replacingOccurrences(of: #"(\s*,\s*)+"#, with: ", ", options: .regularExpression)
            .replacingOccurrences(of: ", Deutschland", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: ", "))
        return text.isEmpty ? nil : text
    }

    /// „Di., 22.09.2026, 17:00 - 17:45 Uhr" oder „Sa., 10.10.2026 - So., 11.10.2026, 19:00 Uhr".
    /// Läuft eine mehrtägige Veranstaltung schon, gilt sie am gefragten Tag als ganztägig.
    private static func times(from text: String, on day: Date) -> (Date?, Date?) {
        let dates = matches(#"(\d{2}\.\d{2}\.\d{4})"#, in: text)
        let clock = matches(#"(\d{1,2}:\d{2})"#, in: text)
        guard let startClock = clock.first else { return (nil, nil) }
        if dates.count > 1, let first = dates.first, first != germanDate(day) {
            return (nil, nil)
        }
        let start = combine(startClock, on: day)
        let end = clock.count > 1 ? combine(clock[1], on: day) : nil
        return (start, end)
    }

    private static func germanDate(_ day: Date) -> String {
        let components = IslandTime.calendar.dateComponents([.day, .month, .year], from: day)
        return String(format: "%02d.%02d.%04d", components.day ?? 0, components.month ?? 0, components.year ?? 0)
    }

    private static func combine(_ timeText: String, on day: Date) -> Date? {
        let parts = timeText.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1])
        else { return nil }
        return IslandTime.calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: IslandTime.startOfDay(day)
        )
    }

    private static let namedEntities: [String: String] = [
        "&nbsp;": " ", "&amp;": "&", "&euro;": "€", "&shy;": "",
        "&auml;": "ä", "&ouml;": "ö", "&uuml;": "ü",
        "&Auml;": "Ä", "&Ouml;": "Ö", "&Uuml;": "Ü", "&szlig;": "ß",
        "&quot;": "\"", "&apos;": "'", "&lt;": "<", "&gt;": ">",
        "&bdquo;": "„", "&ldquo;": "“", "&rdquo;": "”",
        "&laquo;": "«", "&raquo;": "»", "&sbquo;": "‚", "&lsquo;": "‘", "&rsquo;": "’",
        "&ndash;": "–", "&mdash;": "—", "&hellip;": "…", "&deg;": "°",
    ]

    private static func stripTags(_ html: String) -> String {
        var text = html.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        for (entity, replacement) in namedEntities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        text = decodeNumericEntities(text)
        return text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeNumericEntities(_ text: String) -> String {
        guard text.contains("&#"),
              let regex = try? NSRegularExpression(pattern: #"&#(x?)([0-9A-Fa-f]+);"#)
        else { return text }

        let ns = text as NSString
        var result = text
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for match in matches.reversed() {
            let isHex = ns.substring(with: match.range(at: 1)).lowercased() == "x"
            let digits = ns.substring(with: match.range(at: 2))
            guard let code = UInt32(digits, radix: isHex ? 16 : 10),
                  let scalar = Unicode.Scalar(code),
                  let range = Range(match.range, in: result)
            else { continue }
            result.replaceSubrange(range, with: String(Character(scalar)))
        }
        return result
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        matches(pattern, in: text).first
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            return ns.substring(with: match.range(at: 1))
        }
    }
}
