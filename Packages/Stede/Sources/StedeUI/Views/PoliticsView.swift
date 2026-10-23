import StedeCore
import SwiftUI

// Politik: Sitzungen, Tagesordnungen und Vorlagen aus dem Ratsinformationssystem der Gemeinde.

private let dayFormat = Date.FormatStyle(locale: IslandTime.germanLocale, timeZone: IslandTime.timeZone)
    .weekday(.wide).day().month(.wide)
private let timeFormat = Date.FormatStyle(date: .omitted, time: .shortened, locale: IslandTime.germanLocale, timeZone: IslandTime.timeZone)

private var risHost: String { CouncilClient.current?.baseURL.host ?? "Ratsinformationssystem" }

// MARK: - Sitzungen

struct CouncilSessionsView: View {
    @State private var model = CouncilSessionsModel()

    var body: some View {
        TabScreen(title: "Sitzungen", showsDateNavigator: false) {
            await model.load(force: true)
        } content: {
            LoadStateView(state: model.state, emptyMessage: "Im Sitzungskalender stehen gerade keine Termine.") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: StedeTheme.cardSpacing) {
                        Button {
                            Task { await model.loadEarlier() }
                        } label: {
                            StedeColorChip(title: "Frühere Sitzungen", symbol: model.loadingEarlier ? nil : "clock.arrow.circlepath",
                                           color: StedeTheme.ink)
                                .overlay(alignment: .leading) {
                                    if model.loadingEarlier { ProgressView().controlSize(.small).padding(.leading, 12) }
                                }
                        }
                        .buttonStyle(StedeCardButtonStyle())

                        if model.visible.isEmpty {
                            InfoCard {
                                Text("In den nächsten Wochen sind keine Sitzungen angesetzt.")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ForEach(months, id: \.key) { group in
                            StedeSectionHeader(title: group.title, symbol: "calendar")
                            ForEach(group.sessions) { session in
                                NavigationLink(value: HomeDestination.councilSession(session)) {
                                    CouncilSessionCard(session: session, isNext: session.id == model.upcoming.first?.id)
                                }
                                .buttonStyle(StedeCardButtonStyle())
                                .foregroundStyle(.primary)
                            }
                        }
                        SourceFooter(text: "Sitzungskalender · \(risHost) · Angaben ohne Gewähr")
                    }
                    .padding()
                }
            }
        }
        .task { await model.load(force: false) }
    }

    private var months: [(key: Int, title: String, sessions: [CouncilSession])] {
        let format = Date.FormatStyle(locale: IslandTime.germanLocale, timeZone: IslandTime.timeZone).month(.wide).year()
        var order: [Int] = []
        var groups: [Int: [CouncilSession]] = [:]
        for session in model.visible {
            let key = CouncilSessionsModel.monthIndex(session.start)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(session)
        }
        return order.map { key in (key, groups[key]?.first?.start.formatted(format) ?? "", groups[key] ?? []) }
    }
}

struct CouncilSessionCard: View {
    let session: CouncilSession
    let isNext: Bool
    /// Im Kalender steht das Datum schon über dem Tag — dort ein Symbol statt der Datumskachel.
    var showsDate = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if showsDate {
                CouncilDateChip(date: session.start)
            } else {
                StedeIconChip(symbol: "building.columns.fill", color: StedeTheme.seaTeal)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(session.committee)
                    .font(.headline)
                    .fontDesign(.rounded)
                    .multilineTextAlignment(.leading)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                if !session.hasAgenda {
                    Text(isPast ? "ohne Tagesordnung" : "Tagesordnung folgt")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(StedeTheme.mudflat.opacity(0.18), in: Capsule())
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .stedeCard(highlighted: isNext)
        .opacity(isPast ? 0.6 : 1)
        .accessibilityElement(children: .combine)
    }

    private var isPast: Bool { (session.end ?? session.start.addingTimeInterval(3 * 3600)) < Date() }

    private var detail: String {
        var parts: [String] = []
        if session.hasTime {
            parts.append(session.end.map { "\(session.start.formatted(timeFormat))–\($0.formatted(timeFormat)) Uhr" }
                         ?? "\(session.start.formatted(timeFormat)) Uhr")
        }
        if let room = session.room { parts.append(room) }
        return parts.joined(separator: " · ")
    }
}

/// Wochentag und Tag in einer Kachel, Farbe der Sitzungen.
private struct CouncilDateChip: View {
    let date: Date
    @ScaledMetric(relativeTo: .headline) private var side = 44.0

    var body: some View {
        VStack(spacing: 0) {
            Text(date.formatted(.dateTime.weekday(.abbreviated).locale(IslandTime.germanLocale)))
                .font(.caption2.weight(.semibold))
            Text(date.formatted(Date.FormatStyle(locale: IslandTime.germanLocale, timeZone: IslandTime.timeZone).day()))
                .font(.headline)
                .fontDesign(.rounded)
                .monospacedDigit()
        }
        .foregroundStyle(StedeTheme.seaTeal)
        .frame(width: side, height: side)
        .background(StedeTheme.seaTeal.opacity(0.16), in: StedeTheme.chipShape)
    }
}

// MARK: - Tagesordnung

struct CouncilSessionDetailView: View {
    let session: CouncilSession
    @State private var model = CouncilAgendaModel()
    @State private var documents = CouncilDocumentOpener()
    @State private var page: BrowserPage?

    var body: some View {
        TabScreen(title: session.committee, showsDateNavigator: false) {
            if session.hasAgenda { await model.load(sessionID: session.id, force: true) }
        } content: {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: StedeTheme.cardSpacing) {
                    header
                    if session.hasAgenda {
                        agenda
                    } else {
                        InfoCard {
                            Text(session.start < Date()
                                 ? "Zu dieser Sitzung ist keine Tagesordnung veröffentlicht."
                                 : "Die Tagesordnung ist noch nicht veröffentlicht. Sie erscheint in der Regel etwa eine Woche vor der Sitzung.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    SourceFooter(text: "Ratsinformationssystem · \(risHost)")
                }
                .padding()
            }
        }
        .navigationBarTitleDisplayModeInline()
        .task { if session.hasAgenda { await model.load(sessionID: session.id) } }
        .councilDocuments(documents)
        .sheet(item: $page) { InAppBrowser(url: $0.url) }
    }

    private var header: some View {
        InfoCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(session.title)
                    .font(.title3.weight(.semibold))
                    .fontDesign(.rounded)
                Label(session.start.formatted(dayFormat), systemImage: "calendar")
                if session.hasTime {
                    Label(model.agenda?.time.isEmpty == false ? "\(model.agenda?.time ?? "") Uhr" : "\(session.start.formatted(timeFormat)) Uhr",
                          systemImage: "clock")
                }
                if let room = session.room {
                    Label(room, systemImage: "mappin.and.ellipse")
                }
                if let place = model.agenda?.place, !place.isEmpty, place != session.room {
                    Label(place, systemImage: "building.2")
                }
                CouncilDocumentChips(documents: model.agenda?.documents ?? [], paperID: nil, opener: documents)
                if let url = CouncilClient.current?.agendaPage(sessionID: session.id), session.hasAgenda {
                    Button { page = BrowserPage(url: url) } label: {
                        StedeActionChip(title: "Im Ratsinfo öffnen", symbol: "safari")
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.subheadline)
        }
    }

    @ViewBuilder
    private var agenda: some View {
        if let items = model.agenda?.items {
            if items.isEmpty {
                InfoCard { Text("Die Tagesordnung enthält keine Punkte.").foregroundStyle(.secondary) }
            } else {
                StedeSectionHeader(title: "Tagesordnung", symbol: "list.number")
                ForEach(items) { item in
                    if let paperID = item.paperID {
                        NavigationLink(value: HomeDestination.councilPaper(id: paperID, number: item.paperNumber ?? "")) {
                            CouncilAgendaRow(item: item)
                        }
                        .buttonStyle(StedeCardButtonStyle())
                        .foregroundStyle(.primary)
                    } else {
                        CouncilAgendaRow(item: item)
                    }
                }
            }
        } else if case .failed(let message) = model.state {
            InfoCard { Text(message).foregroundStyle(.secondary) }
        } else {
            ProgressView("Laden …").frame(maxWidth: .infinity).padding()
        }
    }
}

private struct CouncilAgendaRow: View {
    let item: CouncilAgenda.Item

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(item.number.replacingOccurrences(of: "Ö ", with: ""))
                .font(.subheadline.weight(.semibold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(item.isPublic ? StedeTheme.ink : .secondary)
                .frame(minWidth: 26, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.subheadline)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    if let number = item.paperNumber {
                        CouncilPill(text: number, symbol: "doc.text", color: StedeTheme.sunAmber)
                    }
                    if let result = item.result {
                        CouncilPill(text: result, color: CouncilPill.color(forResult: result))
                    }
                    if !item.isPublic {
                        CouncilPill(text: "nicht öffentlich", color: StedeTheme.mudflat)
                    }
                }
            }
            Spacer(minLength: 0)
            if item.paperID != nil {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .stedeRowCard()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Vorlagen

struct CouncilPapersView: View {
    @State private var model = CouncilPapersModel()
    @State private var searchText = ""

    var body: some View {
        TabScreen(title: "Vorlagen", showsDateNavigator: false) {
            await model.search(searchText)
        } content: {
            LoadStateView(state: model.state, emptyMessage: model.query.isEmpty
                          ? "Keine Vorlagen gefunden." : "Keine Vorlage mit „\(model.query)“ im Betreff.") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: StedeTheme.cardSpacing) {
                        if let total = model.approximateTotal, model.query.isEmpty {
                            Text("Rund \(total) Vorlagen, die neuesten zuerst")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(model.items) { paper in
                            NavigationLink(value: HomeDestination.councilPaper(id: paper.id, number: paper.number)) {
                                CouncilPaperCard(paper: paper)
                            }
                            .buttonStyle(StedeCardButtonStyle())
                            .foregroundStyle(.primary)
                            .task { await model.loadMoreIfNeeded(current: paper) }
                        }
                        if model.loadingMore {
                            ProgressView().frame(maxWidth: .infinity).padding()
                        }
                        SourceFooter(text: "Ratsinformationssystem · \(risHost) · Angaben ohne Gewähr")
                    }
                    .padding()
                }
            }
        }
        .searchable(text: $searchText, prompt: "Betreff durchsuchen")
        .onSubmit(of: .search) { Task { await model.search(searchText) } }
        .onChange(of: searchText) { _, new in
            // Leeres Suchfeld zeigt wieder alle Vorlagen.
            if new.isEmpty, !model.query.isEmpty { Task { await model.search("") } }
        }
        .task { if model.items.isEmpty { await model.search("") } }
    }
}

private struct CouncilPaperCard: View {
    let paper: CouncilPaper

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                CouncilPill(text: paper.number, color: StedeTheme.sunAmber)
                Text(paper.kind)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if paper.hasAttachments {
                    Image(systemName: "paperclip")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("mit Anlagen")
                }
                Spacer(minLength: 4)
                Text(paper.date)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Text(paper.subject)
                .font(.headline)
                .fontDesign(.rounded)
                .multilineTextAlignment(.leading)
                .lineLimit(4)
            Text(paper.office)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .stedeRowCard()
        .accessibilityElement(children: .combine)
    }
}

struct CouncilPaperDetailView: View {
    let id: Int
    let number: String
    @State private var model = CouncilPaperModel()
    @State private var documents = CouncilDocumentOpener()

    var body: some View {
        TabScreen(title: model.paper?.number ?? number, showsDateNavigator: false) {
            await model.load(id: id, force: true)
        } content: {
            LoadStateView(state: model.state, emptyMessage: "Die Vorlage ist nicht verfügbar.") {
                if let paper = model.paper {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: StedeTheme.cardSpacing) {
                            header(paper)
                            if !paper.consultations.isEmpty {
                                StedeSectionHeader(title: "Beratungsfolge", symbol: "arrow.triangle.branch")
                                ForEach(Array(paper.consultations.enumerated()), id: \.offset) { _, step in
                                    CouncilConsultationRow(step: step)
                                }
                            }
                            ForEach(Array(paper.sections.enumerated()), id: \.offset) { _, section in
                                StedeSectionHeader(title: section.title, symbol: "text.alignleft")
                                InfoCard {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                                            Text(paragraph)
                                        }
                                    }
                                    .font(.subheadline)
                                    .textSelection(.enabled)
                                }
                            }
                            SourceFooter(text: "Ratsinformationssystem · \(risHost)")
                        }
                        .padding()
                    }
                }
            }
        }
        .navigationBarTitleDisplayModeInline()
        .task { await model.load(id: id) }
        .councilDocuments(documents)
    }

    private func header(_ paper: CouncilPaperDetail) -> some View {
        InfoCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(paper.subject)
                    .font(.title3.weight(.semibold))
                    .fontDesign(.rounded)
                    .textSelection(.enabled)
                HStack(spacing: 6) {
                    if !paper.kind.isEmpty { CouncilPill(text: paper.kind, color: StedeTheme.sunAmber) }
                    if !paper.status.isEmpty { CouncilPill(text: paper.status, color: StedeTheme.ink) }
                }
                VStack(alignment: .leading, spacing: 4) {
                    if !paper.office.isEmpty { Label(paper.office, systemImage: "building.2") }
                    if !paper.clerk.isEmpty { Label(paper.clerk, systemImage: "person") }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                CouncilDocumentChips(documents: paper.documents + paper.attachments, paperID: paper.id, opener: documents)
            }
        }
    }
}

private struct CouncilConsultationRow: View {
    let step: CouncilConsultation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle.dashed")
                .font(.title3)
                .foregroundStyle(done ? StedeTheme.duneGreen : StedeTheme.heather)
            VStack(alignment: .leading, spacing: 4) {
                Text(step.committee)
                    .font(.subheadline.weight(.semibold))
                Text([step.role, step.date, step.status].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let result = step.result {
                    CouncilPill(text: result, color: CouncilPill.color(forResult: result))
                }
            }
            Spacer(minLength: 0)
        }
        .stedeRowCard()
        .accessibilityElement(children: .combine)
    }

    private var done: Bool { step.status == "Erledigt" }
}

// MARK: - Bausteine

private struct CouncilPill: View {
    let text: String
    var symbol: String?
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol) }
            Text(text).lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.18), in: Capsule())
        .foregroundStyle(StedeTheme.ink)
    }

    /// Beschlossen grün, abgelehnt rot, sonst neutral.
    static func color(forResult result: String) -> Color {
        let lower = result.lowercased()
        if lower.contains("abgelehnt") { return StedeTheme.harborRed }
        if lower.contains("beschlossen") || lower.contains("zugestimmt") { return StedeTheme.duneGreen }
        return StedeTheme.mudflat
    }
}

/// PDFs als Kapseln; das Antippen holt die frische Adresse und öffnet sie im In-App-Browser.
private struct CouncilDocumentChips: View {
    let documents: [CouncilDocument]
    let paperID: Int?
    let opener: CouncilDocumentOpener

    var body: some View {
        if !documents.isEmpty {
            FlowLayout(spacing: 8) {
                ForEach(documents) { document in
                    Button {
                        Task { await opener.open(document, paperID: paperID) }
                    } label: {
                        HStack(spacing: 6) {
                            if opener.opening == document.id {
                                ProgressView().controlSize(.mini)
                            }
                            StedeActionChip(title: label(document), symbol: document.dolfdnr == nil ? "paperclip" : "doc.richtext")
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(opener.opening != nil)
                }
            }
        }
    }

    /// Anlagen heißen wie die Datei („Präsentation (2169 KB)“) — Größe hinten weg.
    private func label(_ document: CouncilDocument) -> String {
        document.title.replacingOccurrences(of: #"\s*\(\d+ KB\)$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.pdf$"#, with: "", options: [.regularExpression, .caseInsensitive])
    }
}

/// Zeilenumbruch für Kapseln.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private extension View {
    /// PDF-Sheet und Fehlermeldung des `CouncilDocumentOpener`.
    func councilDocuments(_ opener: CouncilDocumentOpener) -> some View {
        @Bindable var opener = opener
        return sheet(item: $opener.page) { InAppBrowser(url: $0.url) }
            .alert("Dokument nicht verfügbar", isPresented: Binding(
                get: { opener.error != nil },
                set: { if !$0 { opener.error = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(opener.error ?? "")
            }
    }

    @ViewBuilder
    func navigationBarTitleDisplayModeInline() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
