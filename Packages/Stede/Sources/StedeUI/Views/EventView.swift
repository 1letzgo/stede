import SwiftUI
import StedeCore

struct EventView: View {
    @Environment(SelectedDateStore.self) private var dateStore
    @Environment(AuthStore.self) private var auth
    @State private var model = EventViewModel()
    @State private var community = CommunityCalendarModel()

    var body: some View {
        TabScreen(title: "Kalender") {
            await model.load(day: dateStore.selectedDate, force: true)
            await loadCommunity()
        } content: {
            LoadStateView(state: model.state, emptyMessage: "Für diesen Tag sind keine Veranstaltungen eingetragen.") {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: StedeTheme.cardSpacing) {
                            // Nach Tageszeit gegliedert, jede mit eigener Farbe.
                            ForEach(sections, id: \.part) { section in
                                StedeSectionHeader(title: section.part.title, symbol: section.part.symbol)
                                ForEach(section.events) { entry in
                                    switch entry {
                                    case .city(let event):
                                        EventCard(event: event, tint: section.part.tint)
                                            .id("event-\(event.id)")
                                    case .community(let event):
                                        CommunityEventCard(
                                            title: event.title, community: event.communityName, communityLogoURL: event.communityLogoURL, starts: event.startsAt, ends: event.endsAt,
                                            location: event.location, description: event.description, imageURL: event.imageURL,
                                            isPublic: event.isPublic, isCancelled: event.cancelledAt != nil,
                                            helpersNeeded: event.helpersNeeded, helperCount: community.helperCounts[event.id] ?? 0,
                                            participation: community.myParticipations[event.id], isSignedIn: auth.isSignedIn,
                                            onParticipate: { status, helping in
                                                Task { if let userID = auth.userID { await community.setParticipation(eventID: event.id, userID: userID, status: status, helping: helping) } }
                                            },
                                            signIn: { showsAccount = true }
                                        )
                                    case .publicEvent(let event):
                                        CommunityEventCard(
                                            title: event.title, community: event.communityName, communityLogoURL: event.communityLogoURL, starts: event.startsAt, ends: event.endsAt,
                                            location: event.location, description: event.description, imageURL: event.imageURL,
                                            isPublic: true, isCancelled: false,
                                            helpersNeeded: event.helpersNeeded, helperCount: community.helperCounts[event.id] ?? 0,
                                            participation: community.myParticipations[event.id], isSignedIn: auth.isSignedIn,
                                            onParticipate: { status, helping in
                                                Task { if let userID = auth.userID { await community.setParticipation(eventID: event.id, userID: userID, status: status, helping: helping) } }
                                            },
                                            signIn: { showsAccount = true }
                                        )
                                    }
                                }
                            }
                            SourceFooter(text: "Stadt Westerstede · westerstede.de/veranstaltungen")
                        }
                        .padding()
                    }
                    .id("events-\(IslandTime.isoDate(dateStore.selectedDate))")
                    .onAppear { scrollToEight(using: proxy) }
                    .onChange(of: model.events) { scrollToEight(using: proxy) }
                }
            }
        }
        .task(id: dateStore.selectedDate) {
            await model.load(day: dateStore.selectedDate)
        }
        .task(id: "\(IslandTime.isoDate(dateStore.selectedDate))|\(auth.tenant?.id.uuidString ?? "")|\(auth.userID?.uuidString ?? "")|\(memberCommunityIDs.map(\.uuidString).joined())") {
            await loadCommunity()
        }
        .onAppear { Task { await loadCommunity() } }
        .sheet(isPresented: $showsAccount) { AccountView() }
    }

    @State private var showsAccount = false

    private func loadCommunity() async {
        await community.load(day: dateStore.selectedDate, tenantID: auth.tenant?.id, memberCommunityIDs: memberCommunityIDs, userID: auth.userID)
    }

    private var memberCommunityIDs: [UUID] {
        auth.memberships.filter { $0.status == .active }.map(\.communityId)
    }

    /// Stadt-Termine, Termine der eigenen Communities und öffentliche Community-Termine
    /// in einer Liste; öffentliche Termine eigener Communities erscheinen nur einmal.
    private var entries: [CalendarEntry] {
        var result: [CalendarEntry] = model.events.map(CalendarEntry.city)
        let memberIDs = Set(community.memberEvents.map(\.id))
        result += community.memberEvents.filter { $0.cancelledAt == nil }.map(CalendarEntry.community)
        result += community.publicEvents.filter { !memberIDs.contains($0.id) }.map(CalendarEntry.publicEvent)
        return result.sorted { ($0.time ?? .distantPast) < ($1.time ?? .distantPast) }
    }

    private var sections: [(part: EventDaypart, events: [CalendarEntry])] {
        EventDaypart.allCases.compactMap { part in
            let events = entries.filter { EventDaypart(time: $0.time) == part }
            return events.isEmpty ? nil : (part, events)
        }
    }

    private func scrollToEight(using proxy: ScrollViewProxy) {
        guard !dateStore.isToday else { return }
        guard let first = model.events.first else { return }
        let eight = IslandTime.date(bySettingHour: 8, of: dateStore.selectedDate)
        let target = model.events.first { event in
            guard let time = event.time else { return false }
            return time >= eight
        } ?? model.events.last
        guard let target, target.id != first.id else { return }
        scrollToCurrent("event-\(target.id)", in: proxy)
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
}

/// Tageszeit einer Veranstaltung — gliedert den Kalender und färbt die Karten.
private enum EventDaypart: CaseIterable, Hashable {
    case allDay, morning, afternoon, evening

    init(time: Date?) {
        guard let time else { self = .allDay; return }
        switch IslandTime.calendar.component(.hour, from: time) {
        case ..<12: self = .morning
        case 12 ..< 17: self = .afternoon
        default: self = .evening
        }
    }

    var title: String {
        switch self {
        case .allDay: "Ganztägig"
        case .morning: "Vormittags"
        case .afternoon: "Nachmittags"
        case .evening: "Abends"
        }
    }

    var symbol: String {
        switch self {
        case .allDay: "calendar"
        case .morning: "sunrise.fill"
        case .afternoon: "sun.max.fill"
        case .evening: "moon.stars.fill"
        }
    }

    var tint: Color {
        switch self {
        case .allDay: StedeTheme.duneGreen
        case .morning: StedeTheme.sunAmber
        case .afternoon: StedeTheme.seaTeal
        case .evening: StedeTheme.ink
        }
    }
}

private struct EventCard: View {
    let event: StedeEvent
    let tint: Color
    @State private var page: BrowserPage?

    var body: some View {
        Button {
            if let url = event.detailURL {
                page = BrowserPage(url: url)
            }
        } label: {
            cardBody
        }
        .buttonStyle(StedeCardButtonStyle())
        .foregroundStyle(.primary)
        .disabled(event.detailURL == nil)
        .accessibilityHint(event.detailURL == nil ? "" : "Öffnet die Veranstaltungsseite im Browser")
        .sheet(item: $page) { page in
            InAppBrowser(url: page.url)
        }
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    if let time = event.timeLabel {
                        Label(time, systemImage: "clock")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(tint.opacity(0.18), in: Capsule())
                            .foregroundStyle(tint)
                    }
                    if let category = event.category {
                        Text(category)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(tint.opacity(0.12), in: Capsule())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }

                Text(event.title)
                    .font(.headline)

                if !event.summary.isEmpty {
                    Text(event.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }

                if event.location != nil || event.organizer != nil || event.seriesNote != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        if let location = event.location {
                            labeled("mappin.and.ellipse", location)
                        }
                        if let organizer = event.organizer {
                            labeled("person.2", organizer)
                        }
                        if let series = event.seriesNote {
                            labeled("repeat", series)
                        }
                    }
                    .font(.caption)
                    .padding(.top, 2)
                }
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Weiße Karte wie die Orte in Gastro und Stadt; die Tageszeit zeigt
        // sich nur in Uhrzeit-Pille und Symbolen.
        .stedeCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if let time = event.timeLabel { parts.append("\(time) Uhr") }
        parts.append(event.title)
        if let category = event.category { parts.append(category) }
        if !event.summary.isEmpty { parts.append(event.summary) }
        if let location = event.location { parts.append("Ort \(location)") }
        if let organizer = event.organizer { parts.append("Veranstalter \(organizer)") }
        if let series = event.seriesNote { parts.append(series) }
        return parts.joined(separator: ", ")
    }

    private func labeled(_ symbol: String, _ value: String) -> some View {
        Label {
            Text(value)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(tint)
        }
    }
}
