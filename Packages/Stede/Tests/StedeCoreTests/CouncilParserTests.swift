import Foundation
import Testing
@testable import StedeCore

/// ALLRIS-Seiten sind ISO-8859-1.
private func risFixture(_ name: String) throws -> String {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "html", subdirectory: "Fixtures"))
    return try #require(String(data: Data(contentsOf: url), encoding: .isoLatin1))
}

@Test func councilSessionsFromCalendar() throws {
    let sessions = CouncilParser.sessions(try risFixture("ris-si010-2026-10"), year: 2026, month: 10)
    let first = try #require(sessions.first)
    #expect(first.id == 431)
    #expect(first.title == "Sitzung des Klima-, Umwelt- und Landwirtschaftsausschusses")
    #expect(first.committee == "Klima-, Umwelt- und Landwirtschaftsausschuss")
    #expect(first.room == "Sitzungssaal des Rathauses")
    #expect(first.hasAgenda)
    #expect(IslandTime.isoDate(first.start) == "2026-10-05")
    let parts = IslandTime.calendar.dateComponents([.hour, .minute], from: first.start)
    #expect(parts.hour == 17 && parts.minute == 0)
    #expect(first.end != nil)

    // Ratssitzung ohne veröffentlichte Tagesordnung und ohne Ende.
    let council = try #require(sessions.first { $0.id == 436 })
    #expect(council.committee == "Rat der Stadt Westerstede")
    #expect(!council.hasAgenda)
    #expect(council.end == nil)
    #expect(council.room == "Hotel Sonnenhof")
}

@Test func councilAgendaWithPapers() throws {
    let agenda = CouncilParser.agenda(try risFixture("ris-to010-431"), sessionID: 431)
    #expect(agenda.committee == "Klima-, Umwelt- und Landwirtschaftsausschuss")
    #expect(agenda.time == "17:00 - 19:53")
    #expect(agenda.place == "Am Markt 2, 26655 Westerstede")
    #expect(agenda.documents.first?.title == "Bekanntmachung")
    #expect(agenda.documents.first?.dolfdnr == 94105)
    let first = try #require(agenda.items.first)
    #expect(first.number == "Ö 1")
    #expect(first.result == nil)
    #expect(first.paperID == nil)
    let heat = try #require(agenda.items.first { $0.paperID == 2564 })
    #expect(heat.title == "Kommunale Wärmeplanung der Stadt Westerstede")
    #expect(heat.paperNumber == "26/2175")
    #expect(heat.result == "ungeändert beschlossen")
}

@Test func councilPaperList() throws {
    let page = CouncilParser.papers(try risFixture("ris-vo040"))
    #expect(page.items.count == 50)
    #expect(page.approximateTotal == 1500)
    #expect(page.hasNext)
    let first = try #require(page.items.first)
    #expect(first.id == 2582)
    #expect(first.number == "26/2190")
    #expect(first.subject == "Stadtstrand 2026 - erstes Resumé")
    #expect(first.office == "Amt für Immobilien, Wirtschaftsförderung und Marketing")
    #expect(first.date == "08.10.2026")
    #expect(first.kind == "Informationsvorlage")
    #expect(first.hasAttachments)
    let tablet = try #require(page.items.first { $0.id == 2446 })
    #expect(tablet.hasResolution)
    #expect(tablet.number == "26/2072")
}

@Test func councilPaperWithConsultations() throws {
    let paper = CouncilParser.paper(try risFixture("ris-vo020-2564"), id: 2564)
    #expect(paper.number == "26/2175")
    #expect(paper.subject == "Kommunale Wärmeplanung der Stadt Westerstede")
    #expect(paper.kind == "Beschlussvorlage")
    #expect(paper.office == "Klimaschutzmanagement")

    #expect(paper.consultations.count == 3)
    let climate = paper.consultations[0]
    #expect(climate.committee == "Klima-, Umwelt- und Landwirtschaftsausschuss")
    #expect(climate.role == "Vorberatung")
    #expect(climate.status == "Erledigt")
    #expect(climate.date == "05.10.2026")
    #expect(climate.sessionID == 431)
    #expect(climate.result == "ungeändert beschlossen")
    #expect(paper.consultations[1].committee == "Verwaltungsausschuss")
    #expect(paper.consultations[1].date == nil)
    let council = paper.consultations[2]
    #expect(council.role == "Entscheidung")
    #expect(council.date == "27.10.2026")
    #expect(council.sessionID == nil)
    #expect(council.sessionName == "Sitzung des Rates der Stadt Westerstede")

    #expect(paper.sections.map(\.title) == ["Beschlussvorschlag", "Sachverhalt", "Finanzielle Auswirkungen", "Anlage/n"])
    #expect(paper.sections[0].paragraphs.first?.hasPrefix("Die kommunale Wärmeplanung") == true)
}

@Test func councilPaperDocuments() throws {
    let paper = CouncilParser.paper(try risFixture("ris-vo020-2582"), id: 2582)
    #expect(paper.number == "26/2190")
    #expect(paper.clerk == "Nappe, Jörg")
    #expect(paper.documents.map(\.title) == ["Vorlage", "Vorlage-Sammeldokument"])
    #expect(paper.documents[0].dolfdnr == 94597)
    #expect(paper.attachments.count == 1)
    #expect(paper.attachments[0].title == "Präsentation-Rückschau Stadtstrand 2026 (2169 KB)")
    #expect(paper.attachments[0].size == "2,1 MB")
    #expect(paper.attachments[0].path?.hasPrefix("___tmp/") == true)
}

@Test func councilFormValuesAreLatin1() {
    #expect(CouncilClient.latin1Encode("Hössen bad") == "H%F6ssen+bad")
    #expect(CouncilClient.latin1Encode("(alle)") == "%28alle%29")
}

/// `ris` und der Baustein `politics` kommen aus `tenants.config`.
@Test func tenantDecodesCouncilConfig() throws {
    let json = """
    {"slug":"stede","municipality":"Westerstede","center":[53.25,7.92],"bbox":[53.15,7.78,53.36,8.1],
     "features":{"politics":true,"places":[]},"ris":{"url":"https://ris.westerstede.de/bi/"}}
    """
    let tenant = try JSONDecoder().decode(TenantConfig.self, from: Data(json.utf8))
    #expect(tenant.ris?.url == "https://ris.westerstede.de/bi/")
    #expect(tenant.features?.enabled == [.politics])
}

/// Gegen das echte RIS — nur mit RIS_LIVE=1 (`RIS_LIVE=1 swift test --filter councilLive`).
@Test(.enabled(if: ProcessInfo.processInfo.environment["RIS_LIVE"] == "1"))
func councilLiveSearchPagingAndDocuments() async throws {
    let client = CouncilClient(baseURL: URL(string: "https://ris.westerstede.de/bi/")!)
    let first = try await client.papers()
    #expect(first.items.count == 50 && first.hasNext)
    let second = try await client.nextPapers()
    #expect(second.items.first?.id != first.items.first?.id)

    let hits = try await client.papers(search: "Hössen")
    #expect(!hits.items.isEmpty)
    #expect(hits.items.allSatisfy { $0.subject.contains("Hössen") })

    let detail = try await client.paper(id: try #require(hits.items.first).id)
    let url = try await client.documentURL(try #require(detail.documents.first), paperID: detail.id)
    #expect(url.absoluteString.hasPrefix("https://ris.westerstede.de/bi/___tmp/"))
    #expect(url.pathExtension == "pdf")
}
