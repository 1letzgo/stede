import Foundation
import Testing
@testable import StedeCore

private func fixture(_ name: String) throws -> String {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try String(contentsOf: url, encoding: .utf8)
}

@Test func eventsParseFromCityCalendar() throws {
    let html = try fixture("events-2026-09-26.html")
    let day = try #require(IslandTime.date(fromISO: "2026-09-26"))
    let events = EventHTMLParser.events(from: html, on: day)
    #expect(events.count == 5)
    #expect(EventHTMLParser.pageCount(from: html) == 1)
    let sewing = try #require(events.first { $0.title == "Spaß am Nähen" })
    #expect(sewing.location == "Apothekervilla, Gaststraße 4, 26655 Westerstede")
    #expect(sewing.category == "Sonstiges")
    #expect(sewing.timeLabel == "10:00–17:00")
    #expect(sewing.detailURL?.lastPathComponent == "spass-am-naehen-900871289-37280.html")
}

@Test func trainBoardDecodesAndMergesDirections() throws {
    let data = try Data(contentsOf: #require(Bundle.module.url(forResource: "dbf-westerstede-ocholt", withExtension: "json", subdirectory: "Fixtures")))
    let board = try JSONDecoder().decode(TrainBoardResponse.self, from: data)
    let now = try #require(IslandTime.calendar.date(bySettingHour: 21, minute: 45, second: 0, of: IslandTime.date(fromISO: "2026-09-21")!))
    let departures = board.departures.compactMap { $0.asDeparture(station: "Westerstede-Ocholt", reference: now) }
    #expect(departures.count == 6)
    let first = try #require(departures.first)
    #expect(first.line == "RE1")
    #expect(first.direction == .leer)
    #expect(first.delayMinutes == 5)
    #expect(departures.contains { $0.line == "RE IC56" && $0.direction == .leer })
    #expect(departures.contains { $0.direction == .oldenburg && $0.destination == "Hannover Hbf" })
}

@Test func busBoardParsesJourneys() throws {
    let xml = try fixture("vbn-zob.xml")
    let buses = BusBoardParser.departures(from: xml)
    #expect(buses.count == 20)
    let first = try #require(buses.first)
    #expect(first.line == "S35")
    #expect(first.destination == "Oldenburg ZOB")
    #expect(first.platform == "1")
    #expect(first.delayMinutes == 0)
    #expect(BusBoardParser.errorText(from: xml) == nil)
    #expect(BusBoardParser.errorText(from: "<Err code=\"H730\" text=\"Your input is not valid.\" level=\"E\"/>") == "Your input is not valid.")
}

@Test func wasteCalendarParsesPDFText() throws {
    let text = try fixture("abfuhr-albertskamp-2026.txt")
    let items = WastePDFParser.collections(from: text, year: 2026)
    // 95 datierte Zeilen plus zweimal Ast- und Strauchwerk am Restabfall-Tag (27.3., 6.11.).
    #expect(items.count == 97)
    #expect(items.contains { $0.kind == .branches && IslandTime.isoDate($0.date) == "2026-11-06" })
    let first = try #require(items.first)
    #expect(first.kind == .residual)
    #expect(IslandTime.isoDate(first.date) == "2026-01-02")
    #expect(items.contains { $0.kind == .hazardous && IslandTime.isoDate($0.date) == "2026-01-31" })
    #expect(items.contains { $0.kind == .branches && IslandTime.isoDate($0.date) == "2026-01-21" })
    #expect(items.last.map { IslandTime.isoDate($0.date) } == "2026-12-24")
}

/// Doppeltermine: Die zweite Art am selben Tag steht ohne Datum in der Folgezeile,
/// teils mit Monatsnamen dazwischen — sie gehört zum zuletzt genannten Datum.
@Test func wasteCalendarReadsSecondCollectionOnSameDay() throws {
    let text = try fixture("abfuhr-gross-neudorfer-weg-2026.txt")
    let items = WastePDFParser.collections(from: text, year: 2026)
    let yellow = items.filter { $0.kind == .yellowBag }
    #expect(yellow.count == 26)
    #expect(items.contains { $0.kind == .residual && IslandTime.isoDate($0.date) == "2026-01-08" })
    #expect(yellow.contains { IslandTime.isoDate($0.date) == "2026-01-08" })
    // „August“/„Februar“ zwischen Datum und Art ändern nichts an der Zuordnung.
    #expect(yellow.contains { IslandTime.isoDate($0.date) == "2026-02-05" })
    #expect(items.contains { $0.kind == .branches && IslandTime.isoDate($0.date) == "2026-03-26" })
    #expect(!items.contains { $0.kind == .other })
}

/// Die Abfuhr-Optionen bekommen eigene Cache-Einträge, ohne Optionen bleibt der Schlüssel wie bisher.
@Test func wasteSelectionCacheKeyKeepsDefaults() throws {
    #expect(WasteSelection(streetID: 12, sectionID: 3).cacheKey == "12-3-0")
    #expect(WasteSelection(streetID: 12, noOrganic: true, fourWeekly: true).cacheKey == "12-0-0-nobio-4w")
    let old = try JSONDecoder().decode(WasteSelection.self, from: Data(#"{"streetID":12}"#.utf8))
    #expect(!old.noOrganic && !old.fourWeekly)
}
