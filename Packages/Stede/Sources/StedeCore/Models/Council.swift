import Foundation

// Politik: Ratsinformationssystem ALLRIS net 3.9 (Westerstede: ris.westerstede.de/bi/).
// Eine OParl-Schnittstelle gibt es nicht, deshalb liest `CouncilParser` das HTML —
// übernommen aus dem Projekt „rischen“ (Kotlin, Ksoup), hier mit regulären Ausdrücken.

/// Eine Sitzung aus dem Sitzungskalender (`si010_e.asp`).
public nonisolated struct CouncilSession: Codable, Sendable, Hashable, Identifiable {
    /// SILFDNR.
    public let id: Int
    /// „Sitzung des Sozialausschusses“.
    public let title: String
    public let start: Date
    public let end: Date?
    /// false, wenn der Kalender keine Uhrzeit nennt.
    public let hasTime: Bool
    public let room: String?
    /// Ist die Tagesordnung schon veröffentlicht?
    public let hasAgenda: Bool

    public init(id: Int, title: String, start: Date, end: Date?, hasTime: Bool, room: String?, hasAgenda: Bool) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.hasTime = hasTime
        self.room = room
        self.hasAgenda = hasAgenda
    }

    /// Name des Gremiums ohne „Sitzung des …“ — für Kacheln und Karten.
    public var committee: String {
        for prefix in ["Sitzung des ", "Sitzung der ", "Sitzung "] where title.hasPrefix(prefix) {
            // „Rates der Stadt“ → „Rat der Stadt“, „Sozialausschusses“ → „Sozialausschuss“.
            let rest = String(title.dropFirst(prefix.count))
                .replacingOccurrences(of: #"^Rates\b"#, with: "Rat", options: .regularExpression)
                .replacingOccurrences(of: #"(\w)(ausschuss|rat|beirat)es\b"#, with: "$1$2", options: .regularExpression)
                .replacingOccurrences(of: #"\bAusschusses\b"#, with: "Ausschuss", options: .regularExpression)
            return rest.prefix(1).uppercased() + rest.dropFirst()
        }
        return title
    }
}

/// Tagesordnung einer Sitzung (`to010.asp`).
public nonisolated struct CouncilAgenda: Codable, Sendable, Hashable {
    public let sessionID: Int
    public let title: String
    public let committee: String
    public let date: String
    public let time: String
    public let room: String
    public let place: String
    public let documents: [CouncilDocument]
    public let items: [Item]

    public nonisolated struct Item: Codable, Sendable, Hashable, Identifiable {
        public var id: String { number + title }
        /// „Ö 4“ (öffentlich) oder „N 2“.
        public let number: String
        public let title: String
        /// „ungeändert beschlossen“; nil, solange offen.
        public let result: String?
        /// VOLFDNR der zugehörigen Vorlage.
        public let paperID: Int?
        /// „26/2174“.
        public let paperNumber: String?

        public var isPublic: Bool { !number.hasPrefix("N") }
    }
}

/// Zeile der Vorlagenliste (`vo040.asp`).
public nonisolated struct CouncilPaper: Codable, Sendable, Hashable, Identifiable {
    /// VOLFDNR.
    public let id: Int
    /// „26/2190“.
    public let number: String
    public let subject: String
    /// Federführendes Amt.
    public let office: String
    /// Freigabe, „08.10.2026“.
    public let date: String
    /// „Beschlussvorlage“, „Informationsvorlage“ …
    public let kind: String
    public let hasAttachments: Bool
    public let hasResolution: Bool
}

public nonisolated struct CouncilPaperPage: Sendable, Hashable {
    public let items: [CouncilPaper]
    /// ALLRIS nennt nur eine ungefähre Gesamtzahl („von ungefähr 1500“).
    public let approximateTotal: Int?
    public let hasNext: Bool
}

/// Schritt der Beratungsfolge: ein Gremium und, sobald geplant, seine Sitzung.
public nonisolated struct CouncilConsultation: Codable, Sendable, Hashable {
    public let committee: String
    /// „Vorberatung“, „Entscheidung“.
    public let role: String
    /// „Erledigt“, „Geplant“.
    public let status: String
    public let date: String?
    public let sessionID: Int?
    public let sessionName: String?
    public let result: String?
}

/// PDF einer Vorlage oder Sitzung. ALLRIS legt PDFs unter kurzlebigen `___tmp/`-Pfaden ab,
/// die echte Adresse holt `CouncilClient.documentURL` direkt vor dem Öffnen.
public nonisolated struct CouncilDocument: Codable, Sendable, Hashable, Identifiable {
    public var id: String { "\(dolfdnr ?? 0)-\(title)" }
    public let title: String
    /// Erzeugte Dokumente (`do027.asp?DOLFDNR=…`).
    public let dolfdnr: Int?
    /// Anlagen: Temp-Pfad beim Laden der Detailseite.
    public let path: String?
    public let size: String?
}

public nonisolated struct CouncilTextSection: Codable, Sendable, Hashable {
    /// „Beschlussvorschlag“, „Sachverhalt“ …
    public let title: String
    public let paragraphs: [String]
}

public nonisolated struct CouncilPaperDetail: Codable, Sendable, Hashable {
    public let id: Int
    public let number: String
    public let subject: String
    public let status: String
    public let kind: String
    public let office: String
    public let clerk: String
    public let consultations: [CouncilConsultation]
    public let sections: [CouncilTextSection]
    public let documents: [CouncilDocument]
    public let attachments: [CouncilDocument]
}

// MARK: - Parser

/// Liest ALLRIS-net-Seiten. Reine Funktionen ohne Netz, getestet gegen Fixtures.
public nonisolated enum CouncilParser {

    // MARK: Sitzungskalender

    /// Monatsansicht `si010_e.asp?MM=…&YY=…`. Tage ohne Sitzung haben keine SILFDNR;
    /// eine zweite Sitzung am selben Tag lässt die Tageszelle leer.
    public static func sessions(_ html: String, year: Int, month: Int) -> [CouncilSession] {
        var result: [CouncilSession] = []
        var day: Int?
        // Wochenenden haben eigene Zeilenklassen (zl16, zl17).
        for row in rows(html, classes: "1267") {
            let cells = cells(row)
            guard cells.count >= 4 else { continue }
            if let value = Int(text(cells[1])) { day = value }
            guard let id = firstInt(#"name="SILFDNR" value="(\d+)""#, in: row), let day,
                  let base = IslandTime.calendar.date(from: DateComponents(year: year, month: month, day: day)) else { continue }
            let times = matches(#"(\d{1,2}):(\d{2})"#, in: text(cells[2]), groups: 2)
            func at(_ index: Int) -> Date? {
                guard times.count > index, let h = Int(times[index][0]), let m = Int(times[index][1]) else { return nil }
                return IslandTime.calendar.date(bySettingHour: h, minute: m, second: 0, of: base)
            }
            // Spalten: Wochentag | Tag | Zeit | ICS | TO | Sitzung | … | Raum
            let titleCell = cells.count > 5 ? cells[5] : ""
            result.append(CouncilSession(
                id: id,
                title: text(titleCell),
                start: at(0) ?? base,
                end: at(1),
                hasTime: !times.isEmpty,
                room: cells.last.map(text).flatMap { $0.isEmpty ? nil : $0 },
                hasAgenda: titleCell.contains("to010.asp")
            ))
        }
        return result
    }

    // MARK: Tagesordnung

    public static func agenda(_ html: String, sessionID: Int) -> CouncilAgenda {
        let items = rows(html).compactMap { row -> CouncilAgenda.Item? in
            let cells = cells(row)
            // TOP-Nummer „Ö 4“ / „N 2“; Kopf- und Trennzeilen haben keine.
            guard cells.count >= 4, let number = cells.first.map(text),
                  number.range(of: #"^[ÖN]\s*\d"#, options: .regularExpression) != nil else { return nil }
            let title = firstMatch(#"<a href="to020\.asp[^"]*">(.*?)</a>"#, in: row).map(text) ?? text(cells[3])
            let result = firstMatch(#"class="il1_naz" value="NA" title="([^"]*)""#, in: row).map(text)
            return CouncilAgenda.Item(
                number: number,
                title: title,
                result: result == "(offen)" || result?.isEmpty == true ? nil : result,
                paperID: firstInt(#"vo020\.asp\?VOLFDNR=(\d+)""#, in: row),
                paperNumber: firstMatch(#"<a href="vo020\.asp\?VOLFDNR=\d+">(.*?)</a>"#, in: row).map(text)
            )
        }
        return CouncilAgenda(
            sessionID: sessionID,
            title: field("Bezeichnung:", in: html),
            committee: field("Gremium:", in: html),
            date: field("Datum:", in: html),
            time: field("Zeit:", in: html),
            room: field("Raum:", in: html),
            place: field("Ort:", in: html),
            documents: generatedDocuments(html),
            items: items
        )
    }

    // MARK: Vorlagen

    public static func papers(_ html: String) -> CouncilPaperPage {
        let items = rows(html).compactMap(paperRow)
        let range = matches(#"Ergebnisse\s+(\d+)-(\d+)(?:\s+von\s+\D*?(\d+))?"#, in: text(html), groups: 3).first
        return CouncilPaperPage(
            items: items,
            approximateTotal: range.flatMap { Int($0[2]) },
            hasNext: html.contains("shownext=true")
        )
    }

    private static func paperRow(_ row: String) -> CouncilPaper? {
        let cells = cells(row)
        guard cells.count >= 7, let id = firstInt(#"name="VOLFDNR" value="(\d+)""#, in: cells[0]) else { return nil }
        // „26/2190&nbsp;Stadtstrand 2026 …“: Nummer und Betreff teilen sich einen Link.
        let title = text(cells[1].replacingOccurrences(of: "&nbsp;", with: "\u{1F}"))
        let number = title.split(separator: "\u{1F}", maxSplits: 1).first.map(String.init) ?? ""
        return CouncilPaper(
            id: id,
            number: number.trimmingCharacters(in: .whitespaces),
            subject: String(title.dropFirst(number.count)).replacingOccurrences(of: "\u{1F}", with: " ").trimmingCharacters(in: .whitespaces),
            office: text(cells[3]),
            date: text(cells[5]),
            kind: text(cells[6]),
            hasAttachments: cells[0].contains("attmnt"),
            hasResolution: cells[2].contains("VOLFDNR")
        )
    }

    public static func paper(_ html: String, id: Int) -> CouncilPaperDetail {
        // <title>Vorlage - 26/2175 - Kommunale Wärmeplanung …</title>
        let pageTitle = firstMatch(#"<title>(.*?)</title>"#, in: html).map(text) ?? ""
        let parts = pageTitle.components(separatedBy: " - ")
        return CouncilPaperDetail(
            id: id,
            number: parts.count > 1 ? parts[1] : "",
            subject: field("Betreff:", in: html),
            status: field("Status:", in: html),
            kind: field("Vorlage-Art:", in: html),
            office: field("Federführend:", in: html),
            clerk: field("Bearbeiter/-in:", in: html),
            consultations: consultations(html),
            sections: sections(html),
            documents: generatedDocuments(html),
            attachments: attachments(html)
        )
    }

    private static func consultations(_ html: String) -> [CouncilConsultation] {
        guard let start = html.range(of: "Beratungsfolge:") else { return [] }
        let rest = html[start.upperBound...]
        let block = rest.range(of: "</table>").map { String(rest[..<$0.lowerBound]) } ?? String(rest)
        var result: [CouncilConsultation] = []
        var current: CouncilConsultation?
        for row in rows(block) {
            let cells = cells(row, keepingOpenTag: true)
            let status = firstMatch(#"title="([^"]*)""#, in: cells.first ?? "").map(text) ?? ""
            let contents = cells.map(stripOpenTag)
            if !row.contains("si010_e.asp") {
                // Gremium: Status | Gremium | Rolle
                if let current { result.append(current) }
                current = CouncilConsultation(
                    committee: contents.count > 1 ? text(contents[1]) : "",
                    role: contents.count > 2 ? text(contents[2]) : "",
                    status: status, date: nil, sessionID: nil, sessionName: nil, result: nil
                )
            } else if let base = current {
                // Sitzung: Status | Datum | TO | Sitzung | Ergebnis | … | NA
                let session = CouncilConsultation(
                    committee: base.committee, role: base.role,
                    status: status.isEmpty ? base.status : status,
                    date: firstMatch(#"<a href="si010_e\.asp[^"]*"[^>]*>(.*?)</a>"#, in: row).map(text),
                    sessionID: firstInt(#"name="SILFDNR" value="(\d+)""#, in: row),
                    sessionName: contents.count > 3 ? nonEmpty(text(contents[3])) : nil,
                    result: contents.count > 4 ? nonEmpty(text(contents[4])) : nil
                )
                // Ein Gremium kann mehrmals über dieselbe Vorlage beraten: jede Sitzung behalten.
                if base.date != nil { result.append(base) }
                current = session
            }
        }
        if let current { result.append(current) }
        return result
    }

    /// Jeder Textblock ist ein vollständiges HTML-Dokument (Aspose-Export) direkt nach
    /// `<a name="allrisXX"></a>`; die Menülinks (`#allrisXX`) tragen die Überschriften.
    private static func sections(_ html: String) -> [CouncilTextSection] {
        var titles: [String: String] = [:]
        for pair in matches(##"<a href="#allris([A-Z]+)">(.*?)</a>"##, in: html, groups: 2) {
            titles[pair[0]] = text(pair[1])
        }
        let anchors = matchRanges(#"<a name="allris([A-Z]+)"></a>"#, in: html)
        return anchors.compactMap { anchor in
            let rest = html[anchor.range.upperBound...]
            let end = ["<a name=\"allris", "<table class=\"tk1\"", "<div id=\"risfoot\""]
                .compactMap { rest.range(of: $0)?.lowerBound }.min() ?? rest.endIndex
            var fragment = String(rest[..<end])
            fragment = fragment.replacingOccurrences(of: #"(?is)<h[1-4][^>]*>.*?</h[1-4]>"#, with: "", options: .regularExpression)
            var paragraphs = matches(#"<(?:p|li)\b[^>]*>(.*?)</(?:p|li)>"#, in: fragment).map(text).filter { !$0.isEmpty }
            if paragraphs.isEmpty, let body = nonEmpty(text(fragment)) { paragraphs = [body] }
            guard !paragraphs.isEmpty else { return nil }
            return CouncilTextSection(title: titles[anchor.key] ?? anchor.key, paragraphs: paragraphs)
        }
    }

    /// Erzeugte PDFs: Formulare `do027.asp` mit DOLFDNR, Titel steht im Button.
    private static func generatedDocuments(_ html: String) -> [CouncilDocument] {
        matches(#"<form action="do027\.asp"[^>]*>(.*?)</form>"#, in: html).compactMap { form in
            guard let id = firstInt(#"name="DOLFDNR" value="(\d+)""#, in: form) else { return nil }
            let title = firstMatch(#"type="submit"[^>]*value="([^"]*)""#, in: form).map(text) ?? "Dokument"
            return CouncilDocument(title: title, dolfdnr: id, path: nil, size: nil)
        }
    }

    private static func attachments(_ html: String) -> [CouncilDocument] {
        matches(#"<a href="(___tmp[^"]*)"([^>]*)>(.*?)</a>"#, in: html, groups: 3).map { groups in
            let size = firstMatch(#"title="Größe:\s*([^\n"]*)"#, in: groups[1]).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            return CouncilDocument(title: text(groups[2]), dolfdnr: nil, path: decodeEntities(groups[0]), size: size.flatMap(nonEmpty))
        }
    }

    // MARK: Hilfen

    /// Wert neben einer Beschriftung `<td class="kb1">Label</td><td …>Wert</td>`.
    static func field(_ label: String, in html: String) -> String {
        let pattern = #"<td class="kb1"[^>]*>\s*"# + NSRegularExpression.escapedPattern(for: label) + #"\s*</td>\s*<td[^>]*>(.*?)</td>"#
        return firstMatch(pattern, in: html).map(text) ?? ""
    }

    static func rows(_ html: String, classes: String = "12") -> [String] {
        matches(#"<tr\b[^>]*class="zl1["# + classes + #"]"[^>]*>(.*?)</tr>"#, in: html)
    }

    static func cells(_ row: String, keepingOpenTag: Bool = false) -> [String] {
        matches(keepingOpenTag ? #"(<td\b[^>]*>.*?)</td>"# : #"<td\b[^>]*>(.*?)</td>"#, in: row)
    }

    private static func stripOpenTag(_ cell: String) -> String {
        cell.replacingOccurrences(of: #"^<td\b[^>]*>"#, with: "", options: .regularExpression)
    }

    private static func nonEmpty(_ value: String) -> String? { value.isEmpty ? nil : value }

    /// Klartext: Skripte und Tags weg, Entities aufgelöst, Leerraum zusammengefasst.
    static func text(_ html: String) -> String {
        var value = html.replacingOccurrences(of: #"(?is)<script\b.*?</script>"#, with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: #"(?s)<!--.*?-->"#, with: " ", options: .regularExpression)
        // Inline-Tags trennen keine Wörter („<span>k</span><span>ommunale“), Blöcke schon.
        value = value.replacingOccurrences(of: #"(?i)</?(?:span|a|b|i|u|em|strong|font|sub|sup)\b[^>]*>"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        return decodeEntities(value)
            .replacingOccurrences(of: "\u{A0}", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let entities: [String: String] = [
        "&nbsp;": " ", "&amp;": "&", "&quot;": "\"", "&apos;": "'", "&lt;": "<", "&gt;": ">",
        "&auml;": "ä", "&ouml;": "ö", "&uuml;": "ü", "&Auml;": "Ä", "&Ouml;": "Ö", "&Uuml;": "Ü", "&szlig;": "ß",
        "&euro;": "€", "&shy;": "", "&ndash;": "–", "&mdash;": "—", "&hellip;": "…",
        "&bdquo;": "„", "&ldquo;": "“", "&rdquo;": "”", "&sect;": "§",
    ]

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = text
        for (entity, replacement) in entities where result.contains(entity) {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        guard result.contains("&#") else { return result }
        for groups in matches(#"&#(x?)([0-9A-Fa-f]+);"#, in: result, groups: 2) {
            guard let code = UInt32(groups[1], radix: groups[0].lowercased() == "x" ? 16 : 10),
                  let scalar = Unicode.Scalar(code) else { continue }
            result = result.replacingOccurrences(of: "&#\(groups[0])\(groups[1]);", with: String(Character(scalar)))
        }
        return result
    }

    static func firstMatch(_ pattern: String, in text: String) -> String? {
        matches(pattern, in: text, limit: 1).first
    }

    private static func firstInt(_ pattern: String, in text: String) -> Int? {
        firstMatch(pattern, in: text).flatMap { Int($0) }
    }

    /// Erste Gruppe jedes Treffers.
    static func matches(_ pattern: String, in text: String, limit: Int = .max) -> [String] {
        matches(pattern, in: text, groups: 1, limit: limit).map { $0[0] }
    }

    /// Gruppen 1…n jedes Treffers; fehlende Gruppen sind leer.
    static func matches(_ pattern: String, in text: String, groups: Int, limit: Int = .max) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return [] }
        let ns = text as NSString
        var result: [[String]] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result.append((1...groups).map { index in
                guard index < match.numberOfRanges, match.range(at: index).location != NSNotFound else { return "" }
                return ns.substring(with: match.range(at: index))
            })
            if result.count >= limit { break }
        }
        return result
    }

    private static func matchRanges(_ pattern: String, in text: String) -> [(key: String, range: Range<String.Index>)] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text), let key = Range(match.range(at: 1), in: text) else { return nil }
            return (String(text[key]), range)
        }
    }
}
