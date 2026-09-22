import SwiftUI

struct EventView: View {
    @Environment(SelectedDateStore.self) private var dateStore
    @State private var model = EventViewModel()

    var body: some View {
        TabScreen(title: "Kalender") {
            await model.load(day: dateStore.selectedDate, force: true)
        } content: {
            LoadStateView(state: model.state, emptyMessage: "Für diesen Tag sind keine Veranstaltungen eingetragen.") {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: StedeTheme.cardSpacing) {
                            // Nach Tageszeit gegliedert, jede mit eigener Farbe.
                            ForEach(sections, id: \.part) { section in
                                StedeSectionHeader(title: section.part.title, symbol: section.part.symbol)
                                ForEach(section.events) { event in
                                    EventCard(event: event, tint: section.part.tint)
                                        .id("event-\(event.id)")
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
    }

    private var sections: [(part: EventDaypart, events: [StedeEvent])] {
        EventDaypart.allCases.compactMap { part in
            let events = model.events.filter { EventDaypart(time: $0.time) == part }
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
