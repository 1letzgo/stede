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
    let departures = board.departures.compactMap { $0.asDeparture(reference: now) }
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
    #expect(items.count == 95)
    let first = try #require(items.first)
    #expect(first.kind == .residual)
    #expect(IslandTime.isoDate(first.date) == "2026-01-02")
    #expect(items.contains { $0.kind == .hazardous && IslandTime.isoDate($0.date) == "2026-01-31" })
    #expect(items.contains { $0.kind == .branches && IslandTime.isoDate($0.date) == "2026-01-21" })
    #expect(items.last.map { IslandTime.isoDate($0.date) } == "2026-12-24")
}
