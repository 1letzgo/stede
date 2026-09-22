import CoreLocation
import Foundation

/// Eine Bushaltestelle im VBN-Netz. Die IDs stammen aus der Haltestellensuche
/// des VBN-Fahrplaners (`ajax-getstop.exe`), Stand 09/2026.
nonisolated struct BusStop: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Kurzname ohne den Ortsteil davor („ZOB" statt „Westerstede ZOB").
    var shortName: String {
        name.replacingOccurrences(of: "Westerstede-", with: "")
            .replacingOccurrences(of: "Westerstede ", with: "")
    }

    static let zob = BusStop(id: "009098661", name: "Westerstede ZOB", latitude: 53.258354, longitude: 7.928171)

    /// Die Haltestellen im Stadtgebiet mit regelmäßigem Verkehr — ZOB zuerst,
    /// dann alphabetisch; der Bahnhof Ocholt als Umstieg zur Bahn am Ende.
    static let all: [BusStop] = [
        zob,
        BusStop(id: "009098621", name: "Westerstede Altenheim", latitude: 53.253698, longitude: 7.922877),
        BusStop(id: "009098630", name: "Westerstede Am Esch", latitude: 53.265411, longitude: 7.937394),
        BusStop(id: "009098623", name: "Westerstede Ammerland-Klinik", latitude: 53.259109, longitude: 7.91822),
        BusStop(id: "009098624", name: "Westerstede Amtsgericht", latitude: 53.252916, longitude: 7.929834),
        BusStop(id: "009060998", name: "Westerstede An der Norderbäke", latitude: 53.258992, longitude: 7.920099),
        BusStop(id: "009098628", name: "Westerstede Brakenhoffschule", latitude: 53.253814, longitude: 7.937628),
        BusStop(id: "009098631", name: "Westerstede Detershof", latitude: 53.246785, longitude: 7.925483),
        BusStop(id: "009098627", name: "Westerstede Eichendorffstraße", latitude: 53.263172, longitude: 7.933151),
        BusStop(id: "009098633", name: "Westerstede Famila", latitude: 53.260206, longitude: 7.932306),
        BusStop(id: "009098634", name: "Westerstede Finanzamt", latitude: 53.252871, longitude: 7.934158),
        BusStop(id: "009098637", name: "Westerstede Goethestraße", latitude: 53.251954, longitude: 7.939821),
        BusStop(id: "009098639", name: "Westerstede Gymnasium", latitude: 53.253266, longitude: 7.925699),
        BusStop(id: "009098641", name: "Westerstede Hössenbad", latitude: 53.253859, longitude: 7.912638),
        BusStop(id: "009098644", name: "Westerstede Kreishaus", latitude: 53.255406, longitude: 7.934859),
        BusStop(id: "009098645", name: "Westerstede Kuhlenstraße", latitude: 53.252664, longitude: 7.916539),
        BusStop(id: "009098647", name: "Westerstede Lüttje Moorpadd", latitude: 53.261779, longitude: 7.916063),
        BusStop(id: "009098651", name: "Westerstede Oberschule", latitude: 53.26239, longitude: 7.925178),
        BusStop(id: "009098655", name: "Westerstede Süderstraße/Virchowstraße", latitude: 53.253149, longitude: 7.94881),
        BusStop(id: "009098657", name: "Westerstede Telekom", latitude: 53.258992, longitude: 7.93699),
        BusStop(id: "009098666", name: "Westerstede-Lindern Rosenkrug", latitude: 53.221121, longitude: 7.884484),
        BusStop(id: "009098668", name: "Westerstede-Ocholt Bahnhof", latitude: 53.202288, longitude: 7.886533),
    ]

    static func stop(id: String) -> BusStop {
        all.first { $0.id == id } ?? zob
    }
}

/// Eine Busabfahrt von der VBN-Abfahrtstafel (HAFAS `stboard.exe`, Format `vs_java3`).
nonisolated struct BusDeparture: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let scheduled: Date
    /// Nil, wenn der Fahrplaner keine Echtzeit kennt („-").
    let delayMinutes: Int?
    let line: String
    let destination: String
    let platform: String?
    let isCancelled: Bool

    var departure: Date { scheduled.addingTimeInterval(TimeInterval(delayMinutes ?? 0) * 60) }
}

/// Liest die XML-Zeilen `<Journey fpTime="22:45" fpDate="21.09.26" delay="-" platform="1"
/// targetLoc="Oldenburg(Oldb) ZOB" hafasname="Bus S35" prod="Bus S35#Bus" dir="Oldenburg ZOB" … />`.
nonisolated enum BusBoardParser: Sendable {
    static func departures(from xml: String) -> [BusDeparture] {
        guard let regex = try? NSRegularExpression(pattern: #"<Journey\s([^>]*?)/>"#, options: [.dotMatchesLineSeparators]) else {
            return []
        }
        let ns = xml as NSString
        return regex.matches(in: xml, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            departure(from: attributes(ns.substring(with: match.range(at: 1))))
        }
    }

    /// `<Err code="H730" text="…"/>` — die Tafel meldet Fehler im selben Dokument.
    static func errorText(from xml: String) -> String? {
        guard let text = firstMatch(#"<Err[^>]*text="([^"]*)""#, in: xml) else { return nil }
        return unescape(text)
    }

    private static func departure(from attributes: [String: String]) -> BusDeparture? {
        guard let time = attributes["fpTime"], let date = attributes["fpDate"],
              let scheduled = Self.date(date: date, time: time),
              let name = attributes["hafasname"]
        else { return nil }
        // Am Bahnhof Ocholt stehen auch Züge auf der Tafel — hier zählen nur Busse.
        if let prod = attributes["prod"], !prod.hasSuffix("#Bus"), !name.hasPrefix("Bus") {
            return nil
        }
        let delayText = attributes["delay"] ?? "-"
        let cancelled = delayText.lowercased().contains("cancel") || attributes["is_cancelled"] == "1"
        // Ziele in der Stadt ohne den Ortsnamen davor — Platz ist knapp.
        var destination = unescape(attributes["dir"] ?? attributes["targetLoc"] ?? "")
        if destination.hasPrefix("Westerstede ") { destination.removeFirst("Westerstede ".count) }
        let line = name.replacingOccurrences(of: "Bus ", with: "")
        return BusDeparture(
            id: "\(line)-\(date)-\(time)-\(destination)",
            scheduled: scheduled,
            delayMinutes: Int(delayText),
            line: line,
            destination: destination,
            platform: attributes["platform"].flatMap { $0.isEmpty ? nil : $0 },
            isCancelled: cancelled
        )
    }

    private static func attributes(_ text: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(pattern: #"(\w+)="([^"]*)""#) else { return [:] }
        let ns = text as NSString
        var result: [String: String] = [:]
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result[ns.substring(with: match.range(at: 1))] = ns.substring(with: match.range(at: 2))
        }
        return result
    }

    /// „21.09.26" + „22:45" in Ortszeit.
    private static func date(date: String, time: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = IslandTime.timeZone
        formatter.dateFormat = "dd.MM.yy HH:mm"
        return formatter.date(from: "\(date) \(time)")
    }

    private static func unescape(_ text: String) -> String {
        var result = text
        for (entity, replacement) in [("&amp;", "&"), ("&quot;", "\""), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">")] {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        guard result.contains("&#"), let regex = try? NSRegularExpression(pattern: #"&#(\d+);"#) else { return result }
        let ns = result as NSString
        for match in regex.matches(in: result, range: NSRange(location: 0, length: ns.length)).reversed() {
            guard let code = UInt32(ns.substring(with: match.range(at: 1))),
                  let scalar = Unicode.Scalar(code),
                  let range = Range(match.range, in: result)
            else { continue }
            result.replaceSubrange(range, with: String(Character(scalar)))
        }
        return result
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1
        else { return nil }
        return ns.substring(with: match.range(at: 1))
    }
}
