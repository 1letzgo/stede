import StedeCore
import SwiftUI

/// Kalender als fortlaufende Liste ab heute: Filter-Reiter oben, ein Abschnitt je Tag
/// mit Terminen, Stadt- und Gruppen-Termine gemischt. Nach unten lädt sie von selbst
/// weiter, frühere Termine auf Tipp; „Heute“ in der Leiste springt zurück.
struct EventView: View {
    private enum Filter: String, CaseIterable {
        case all, city, communities, mine

        var title: String {
            switch self {
            case .all: "Alle"
            case .city: "Öffentlich"
            case .communities: "Gruppen"
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

    @Environment(AuthStore.self) private var auth
    @AppStorage("calendar.filter") private var filterRaw = Filter.all.rawValue
    @State private var model = CalendarFeedModel()
    @State private var scrollTarget: String?
    @State private var didScrollToToday = false
    @State private var community = CommunityCalendarModel()
    @State private var showsAccount = false
    @State private var openedEvent: CommunityEventInfo?
    @State private var commentingEvent: CommunityEventInfo?
    @State private var editingEvent: CommunityEvent?

    private var filter: Filter { Filter(rawValue: filterRaw) ?? .all }
    /// Tag, der vor „Frühere Termine“ oben stand — danach bleibt die Liste dort stehen,
    /// die geladenen Tage stehen darüber (alt → neu), statt zum ältesten zu springen.
    @State private var earlierAnchor: String?

    var body: some View {
        TabScreen(title: "Kalender", showsDateNavigator: false) {
            await model.load(force: true)
            await loadCommunity()
        } content: {
            VStack(spacing: 0) {
                filterRow
                    .padding(.top)
                    .padding(.bottom, StedeTheme.cardSpacing)
                LoadStateView(state: listState, emptyMessage: "Keine Termine gefunden.") {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: StedeTheme.cardSpacing) {
                                earlierButton
                                ForEach(days, id: \.date) { day in
                                    StedeSectionHeader(title: day.title, symbol: day.isToday ? "sun.max.fill" : nil)
                                        .id(dayID(day.date))
                                    if day.entries.isEmpty {
                                        Text("Heute keine Termine").font(.subheadline).foregroundStyle(.tertiary).padding(.horizontal, 4)
                                    }
                                    ForEach(day.entries) { entry in
                                        switch entry {
                                        case .city(let event): CityEventRow(event: event)
                                        case .community(let event): communityCard(CommunityEventInfo(event))
                                        case .publicEvent(let event): communityCard(CommunityEventInfo(event))
                                        }
                                    }
                                }
                                laterFooter
                            }
                            .padding([.horizontal, .bottom])
                        }
                        .onChange(of: earlierAnchor) {
                            guard let id = earlierAnchor else { return }
                            Task {
                                try? await Task.sleep(for: .milliseconds(60))
                                proxy.scrollTo(id, anchor: .bottom)
                                earlierAnchor = nil
                            }
                        }
                        .onChange(of: scrollTarget) {
                            scrollToCurrent(scrollTarget, in: proxy)
                            scrollTarget = nil
                        }
                        .onChange(of: model.state, initial: true) {
                            guard !didScrollToToday, model.state == .loaded || model.state == .empty else { return }
                            didScrollToToday = true
                            scrollToCurrent(dayID(IslandTime.startOfDay(Date())), in: proxy)
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Heute") { scrollTarget = dayID(IslandTime.startOfDay(Date())) }
                    .tint(.white)
            }
        }
        .task { await model.load() }
        .task(id: "\(IslandTime.isoDate(model.start))|\(IslandTime.isoDate(model.end))|\(auth.tenant?.id.uuidString ?? "")|\(auth.userID?.uuidString ?? "")|\(memberCommunityIDs.map(\.uuidString).joined())") {
            await loadCommunity()
        }
        .onAppear { Task { await loadCommunity() } }
        .sheet(isPresented: $showsAccount) { AccountView() }
        .sheet(item: $commentingEvent, onDismiss: { Task { await community.loadCommentCounts() } }) { info in
            CommentsSheet(title: info.title, target: .event(info.id), canModerate: canEdit(info))
        }
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
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .stedeSelectionChip(isSelected: filter == item)
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
        await community.load(from: model.start, to: IslandTime.day(model.end, adding: 1), tenantID: auth.tenant?.id, memberCommunityIDs: memberCommunityIDs, userID: auth.userID)
    }

    private func dayID(_ date: Date) -> String { "day-\(IslandTime.isoDate(date))" }

    // MARK: Nachladen

    /// Oben: frühere Termine auf Tipp — automatisch würde die Liste beim Einfügen springen.
    private var earlierButton: some View {
        Button {
            let anchor = days.first.map { dayID($0.date) }
            Task {
                await model.loadEarlier()
                earlierAnchor = anchor
            }
        } label: {
            HStack(spacing: 6) {
                if model.isLoadingEarlier { ProgressView().controlSize(.small) } else { Image(systemName: "chevron.up") }
                Text("Frühere Termine")
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .stedeSelectionChip(isSelected: false)
        }
        .buttonStyle(StedeCardButtonStyle())
        .disabled(model.isLoadingEarlier)
    }

    /// Unten: sobald sichtbar, die nächsten drei Wochen laden.
    @ViewBuilder private var laterFooter: some View {
        if model.canLoadLater {
            HStack { Spacer(); ProgressView(); Spacer() }
                .padding(.vertical, 8)
                .onAppear { Task { await model.loadLater() } }
                .id("later-\(IslandTime.isoDate(model.end))")
        }
        SourceFooter(text: Tenants.usesBundle
            ? "Stadt Westerstede · westerstede.de/veranstaltungen · Gruppen-Termine aus der App"
            : "\(Tenants.current.officialName) · Ammerland-Touristik (destination.one) · Gruppen-Termine aus der App")
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

    /// Nur Tage mit Terminen — plus heute, damit „Heute“ immer ein Ziel hat.
    private var days: [DayGroup] {
        let thisYear = IslandTime.calendar.component(.year, from: Date())
        let short = Date.FormatStyle(locale: IslandTime.germanLocale, timeZone: IslandTime.timeZone).weekday(.wide).day().month(.abbreviated)
        let long = short.year()
        let today = IslandTime.startOfDay(Date())
        let byDay = Dictionary(grouping: entries.filter { $0.time != nil }) { IslandTime.startOfDay($0.time!) }
        var dates = Set(byDay.keys.filter { $0 >= model.start && $0 <= model.end })
        dates.insert(today)
        return dates.sorted().map { date in
            let isToday = date == today
            let format = IslandTime.calendar.component(.year, from: date) == thisYear ? short : long
            return DayGroup(date: date, title: (isToday ? "Heute, " : "") + date.formatted(format), isToday: isToday, entries: byDay[date] ?? [])
        }
    }

    private var listState: LoadState {
        if case .failed(let message) = model.state, entries.isEmpty { return .failed(message) }
        if model.state == .loading, entries.isEmpty { return .loading }
        return .loaded
    }

    private func communityCard(_ info: CommunityEventInfo) -> some View {
        CommunityEventCard(
            info: info, helperCount: community.helperCounts[info.id] ?? 0,
            participation: community.myParticipations[info.id], isSignedIn: auth.isSignedIn,
            onParticipate: { status, helping in participate(info, status, helping) },
            signIn: { showsAccount = true },
            onOpen: { openedEvent = info },
            showsDate: false,
            commentCount: community.commentCounts[info.id] ?? 0,
            onComments: { commentingEvent = info },
            actions: cardActions(info)
        )
    }

    /// Schnellmenü für eigene bzw. verwaltete Gruppen-Termine.
    private func cardActions(_ info: CommunityEventInfo) -> EventCardActions? {
        guard canEdit(info), let event = community.memberEvents.first(where: { $0.id == info.id }) else { return nil }
        let open = event.cancelledAt == nil && (event.endsAt ?? event.startsAt) > Date()
        return EventCardActions(
            edit: { editingEvent = event },
            toggleComments: event.visibility == .members ? {
                Task { try? await CommunityClient().setEventComments(id: event.id, enabled: !event.commentsEnabled); await loadCommunity() }
            } : nil,
            cancel: open ? { Task { try? await CommunityClient().cancelEvent(id: event.id); await loadCommunity() } } : nil
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
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    StedeIconChip(symbol: "building.columns.fill", color: StedeTheme.mudflat)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.title).font(.headline).fontDesign(.rounded).multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            StedeTagPill(text: event.timeLabel ?? "ganztägig", color: StedeTheme.mudflat)
                            if let category = event.category { StedeTagPill(text: category, color: StedeTheme.ink) }
                        }
                    }
                    Spacer(minLength: 0)
                }
                // Ort linksbündig unter der Kopfzeile — wie bei den Gruppen-Terminen.
                if let location = event.location {
                    Label(location, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
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
