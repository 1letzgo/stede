import StedeCore
import SwiftUI

/// Kalender als Wochenliste: Filter-Reiter oben, ein Abschnitt je Tag,
/// Stadt-Termine und Community-Termine in einer Reihenfolge.
struct EventView: View {
    private enum Filter: String, CaseIterable {
        case all, city, communities, mine

        var title: String {
            switch self {
            case .all: "Alle"
            case .city: "Öffentlich"
            case .communities: "Communities"
            case .mine: "Meine"
            }
        }

        var symbol: String {
            switch self {
            case .all: "calendar"
            case .city: "building.columns"
            case .communities: "person.3.fill"
            case .mine: "checkmark.circle"
            }
        }
    }

    @Environment(SelectedDateStore.self) private var dateStore
    @Environment(AuthStore.self) private var auth
    @AppStorage("calendar.filter") private var filterRaw = Filter.all.rawValue
    @State private var model = WeekEventViewModel()
    @State private var community = CommunityCalendarModel()
    @State private var showsAccount = false
    @State private var openedEvent: CommunityEventInfo?
    @State private var editingEvent: CommunityEvent?

    private var filter: Filter { Filter(rawValue: filterRaw) ?? .all }

    var body: some View {
        TabScreen(title: "Kalender", weekNavigator: true) {
            await model.load(weekStart: dateStore.weekStart, force: true)
            await loadCommunity()
        } content: {
            VStack(spacing: 0) {
                filterRow
                    .padding(.top)
                    .padding(.bottom, StedeTheme.cardSpacing)
                LoadStateView(state: listState, emptyMessage: emptyMessage) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: StedeTheme.cardSpacing) {
                                ForEach(days, id: \.date) { day in
                                    StedeSectionHeader(title: day.title, symbol: day.isToday ? "sun.max.fill" : nil)
                                        .id("day-\(IslandTime.isoDate(day.date))")
                                    if day.entries.isEmpty {
                                        Text("Keine Termine").font(.subheadline).foregroundStyle(.tertiary).padding(.horizontal, 4)
                                    }
                                    ForEach(day.entries) { entry in
                                        switch entry {
                                        case .city(let event): CityEventRow(event: event)
                                        case .community(let event): communityCard(CommunityEventInfo(event))
                                        case .publicEvent(let event): communityCard(CommunityEventInfo(event))
                                        }
                                    }
                                }
                                SourceFooter(text: "Stadt Westerstede · westerstede.de/veranstaltungen · Community-Termine aus der App")
                            }
                            .padding([.horizontal, .bottom])
                        }
                        .onAppear { scrollToToday(proxy) }
                        .onChange(of: dateStore.weekStart) { scrollToToday(proxy) }
                    }
                }
            }
        }
        .task(id: dateStore.weekStart) {
            await model.load(weekStart: dateStore.weekStart)
        }
        .task(id: "\(IslandTime.isoDate(dateStore.weekStart))|\(auth.tenant?.id.uuidString ?? "")|\(auth.userID?.uuidString ?? "")|\(memberCommunityIDs.map(\.uuidString).joined())") {
            await loadCommunity()
        }
        .onAppear { Task { await loadCommunity() } }
        .sheet(isPresented: $showsAccount) { AccountView() }
        .sheet(item: $openedEvent) { info in
            CommunityEventDetailView(
                info: info, helperCount: community.helperCounts[info.id] ?? 0,
                participation: community.myParticipations[info.id], isSignedIn: auth.isSignedIn,
                onParticipate: { status, helping in participate(info, status, helping) },
                signIn: { showsAccount = true },
                onEdit: canEdit(info) ? { openedEvent = nil; editingEvent = community.memberEvents.first { $0.id == info.id } } : nil,
                showsParticipants: canEdit(info)
            )
        }
        .sheet(item: $editingEvent) { event in
            EventEditorView(communityID: event.communityId, existing: event) { draft in
                do {
                    try await CommunityClient().updateEvent(id: event.id, draft)
                    await loadCommunity()
                    return true
                } catch { return false }
            } onCancelEvent: {
                try? await CommunityClient().cancelEvent(id: event.id)
                await loadCommunity()
            }
        }
    }

    /// Ersteller, Admin oder Owner der Community — nur für Termine eigener Communities.
    private func canEdit(_ info: CommunityEventInfo) -> Bool {
        guard let userID = auth.userID, let communityID = info.communityId else { return false }
        if info.createdBy == userID { return true }
        guard let membership = auth.membership(for: communityID), membership.status == .active else { return false }
        return membership.role == .owner || membership.role == .admin
    }

    // MARK: Filter

    /// Vier gleich breite Chips wie der Richtungsumschalter der Bahn — nichts scrollt.
    private var filterRow: some View {
        HStack(spacing: StedeTheme.SelectionRow.spacing) {
            ForEach(Filter.allCases, id: \.self) { item in
                Button {
                    filterRaw = item.rawValue
                } label: {
                    Text(item.title)
                        .frame(maxWidth: .infinity)
                        .stedeSelectionChip(isSelected: filter == item)
                        .minimumScaleFactor(0.8)
                }
                .buttonStyle(StedeCardButtonStyle())
                .accessibilityAddTraits(filter == item ? .isSelected : [])
            }
        }
        .padding(.horizontal, StedeTheme.SelectionRow.horizontalInset)
        .fixedSize(horizontal: false, vertical: true)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    // MARK: Daten

    private var memberCommunityIDs: [UUID] {
        auth.memberships.filter { $0.status == .active }.map(\.communityId)
    }

    private func loadCommunity() async {
        await community.load(from: dateStore.weekStart, to: dateStore.weekEnd, tenantID: auth.tenant?.id, memberCommunityIDs: memberCommunityIDs, userID: auth.userID)
    }

    private func participate(_ info: CommunityEventInfo, _ status: ParticipationStatus?, _ helping: Bool) {
        Task { if let userID = auth.userID { await community.setParticipation(eventID: info.id, userID: userID, status: status, helping: helping) } }
    }

    /// Alle Einträge der Woche nach Filter.
    private var entries: [CalendarEntry] {
        var result: [CalendarEntry] = []
        if filter == .all || filter == .city {
            result += model.events.map(CalendarEntry.city)
        }
        if filter != .city {
            let memberIDs = Set(community.memberEvents.map(\.id))
            result += community.memberEvents.filter { $0.cancelledAt == nil }.map(CalendarEntry.community)
            result += community.publicEvents.filter { !memberIDs.contains($0.id) }.map(CalendarEntry.publicEvent)
        }
        if filter == .mine {
            result = result.filter { entry in
                guard let id = entry.communityEventID, let mine = community.myParticipations[id] else { return false }
                return mine.status != .declined
            }
        }
        return result.sorted { ($0.time ?? .distantPast) < ($1.time ?? .distantPast) }
    }

    private struct DayGroup {
        let date: Date
        let title: String
        let isToday: Bool
        let entries: [CalendarEntry]
    }

    private var days: [DayGroup] {
        let format = Date.FormatStyle(locale: IslandTime.germanLocale, timeZone: IslandTime.timeZone).weekday(.wide).day().month(.abbreviated)
        let today = IslandTime.startOfDay(Date())
        return (0 ..< 7).compactMap { offset in
            guard let date = IslandTime.calendar.date(byAdding: .day, value: offset, to: dateStore.weekStart) else { return nil }
            let items = entries.filter { entry in
                guard let time = entry.time else { return false }
                return IslandTime.isSameDay(time, date)
            }
            let isToday = date == today
            return DayGroup(date: date, title: (isToday ? "Heute, " : "") + date.formatted(format), isToday: isToday, entries: items)
        }
    }

    private var listState: LoadState {
        if case .failed(let message) = model.state, entries.isEmpty { return .failed(message) }
        if model.state == .loading, entries.isEmpty { return .loading }
        return .loaded
    }

    private var emptyMessage: String { "Für diese Woche sind keine Termine eingetragen." }

    private func scrollToToday(_ proxy: ScrollViewProxy) {
        let today = IslandTime.startOfDay(Date())
        guard today >= dateStore.weekStart, today < dateStore.weekEnd else { return }
        scrollToCurrent("day-\(IslandTime.isoDate(today))", in: proxy)
    }

    private func communityCard(_ info: CommunityEventInfo) -> some View {
        CommunityEventCard(
            info: info, helperCount: community.helperCounts[info.id] ?? 0,
            participation: community.myParticipations[info.id], isSignedIn: auth.isSignedIn,
            onParticipate: { status, helping in participate(info, status, helping) },
            signIn: { showsAccount = true },
            onOpen: { openedEvent = info },
            showsDate: false
        )
    }
}

/// Ein Eintrag im Kalender-Tab, egal aus welcher Quelle.
private enum CalendarEntry: Identifiable {
    case city(StedeEvent)
    case community(CommunityEvent)
    case publicEvent(PublicEvent)

    var id: String {
        switch self {
        case .city(let e): "city-\(e.id)"
        case .community(let e): "community-\(e.id.uuidString)"
        case .publicEvent(let e): "public-\(e.id.uuidString)"
        }
    }

    var time: Date? {
        switch self {
        case .city(let e): e.time
        case .community(let e): e.startsAt
        case .publicEvent(let e): e.startsAt
        }
    }

    var communityEventID: UUID? {
        switch self {
        case .city: nil
        case .community(let e): e.id
        case .publicEvent(let e): e.id
        }
    }
}

/// Kompakte Karte für Stadt-Termine: Zeit-Pille, Titel, Ort; Tipp öffnet die Seite der Stadt.
private struct CityEventRow: View {
    let event: StedeEvent
    @State private var page: BrowserPage?

    var body: some View {
        Button {
            if let url = event.detailURL { page = BrowserPage(url: url) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                StedeIconChip(symbol: "building.columns.fill", color: StedeTheme.mudflat)
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title).font(.headline).fontDesign(.rounded).multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        StedeTagPill(text: event.timeLabel ?? "ganztägig", color: StedeTheme.mudflat)
                        if let category = event.category { StedeTagPill(text: category, color: StedeTheme.ink) }
                    }
                    if let location = event.location {
                        Label(location, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(StedeTheme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .stedeCard()
        }
        .buttonStyle(StedeCardButtonStyle())
        .foregroundStyle(.primary)
        .disabled(event.detailURL == nil)
        .accessibilityHint(event.detailURL == nil ? "" : "Öffnet die Veranstaltungsseite im Browser")
        .sheet(item: $page) { page in InAppBrowser(url: page.url) }
    }
}
