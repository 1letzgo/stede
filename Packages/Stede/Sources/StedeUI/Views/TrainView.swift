import SwiftUI
import StedeCore

struct TrainView: View {
    @Binding var direction: TrainDirection
    @Environment(SelectedDateStore.self) private var dateStore
    @AppStorage("train.station") private var stationID = ""
    @State private var model = TrainViewModel()

    private var station: TenantConfig.Station? { Tenants.current.station(id: stationID) }

    var body: some View {
        TabScreen(title: "Bahn") {
            if let station { await model.load(station: station, day: dateStore.selectedDate, force: true) }
        } content: {
            VStack(spacing: 0) {
                if let station {
                    DirectionSwitcher(selection: $direction, station: station)
                        .padding(.top)
                        .padding(.bottom, StedeTheme.cardSpacing)
                }

                LoadStateView(state: model.state, emptyMessage: emptyMessage) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: StedeTheme.cardSpacing) {
                            if departures.isEmpty {
                                InfoCard {
                                    Text("Keine Züge \(station.map(direction.title(at:)) ?? "")")
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                ForEach(departures) { train in
                                    TrainCard(
                                        train: train,
                                        isNext: dateStore.isToday && train.id == nextID,
                                        isPast: dateStore.isToday && train.departure < Date()
                                    )
                                }
                            }
                            SourceFooter(text: "Bahnhof \(station?.name ?? "") · dbf.finalrewind.org (DB IRIS), nächste rund zwei Stunden")
                        }
                        .padding([.horizontal, .bottom])
                    }
                    .id("trains-\(IslandTime.isoDate(dateStore.selectedDate))-\(stationID)-\(direction.rawValue)")
                }
            }
        }
        .task(id: "\(IslandTime.isoDate(dateStore.selectedDate))-\(stationID)") {
            if let station { await model.load(station: station, day: dateStore.selectedDate) }
        }
    }

    private var departures: [TrainDeparture] {
        model.departures(toward: direction)
    }

    /// Die Tafel kennt nur „jetzt" — für andere Tage gibt es nichts zu zeigen.
    private var emptyMessage: String {
        dateStore.isToday
            ? "Gerade stehen keine Abfahrten auf der Tafel."
            : "Die Abfahrtstafel zeigt nur die nächsten Stunden ab jetzt — für andere Tage gibt es keine Zeiten."
    }

    private var nextID: TrainDeparture.ID? {
        departures.first { $0.departure > Date() && !$0.isCancelled }?.id
    }
}

private struct DirectionSwitcher: View {
    @Binding var selection: TrainDirection
    let station: TenantConfig.Station

    var body: some View {
        // Zwei Richtungen, zwei gleich breite Hälften — wie die Tageszeile nutzt
        // die Reihe die Maße von StedeTheme.SelectionRow, ordnet aber selbst an.
        HStack(spacing: StedeTheme.SelectionRow.spacing) {
            ForEach(TrainDirection.allCases, id: \.self) { direction in
                Button {
                    selection = direction
                } label: {
                    Text(direction.title(at: station))
                        .frame(maxWidth: .infinity)
                        .stedeSelectionChip(isSelected: selection == direction)
                }
                .buttonStyle(StedeCardButtonStyle())
                .accessibilityAddTraits(selection == direction ? .isSelected : [])
            }
        }
        .padding(.horizontal, StedeTheme.SelectionRow.horizontalInset)
        .fixedSize(horizontal: false, vertical: true)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

private struct TrainCard: View {
    let train: TrainDeparture
    let isNext: Bool
    var isPast = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(train.scheduled.formatted(Self.timeFormat))
                    .font(.title3.weight(.semibold))
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .strikethrough(train.isCancelled)
                if train.isCancelled {
                    Text("fällt aus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(StedeTheme.harborRed)
                } else if train.delayMinutes > 0 {
                    Text("+\(train.delayMinutes)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(StedeTheme.harborRed)
                }
                Spacer(minLength: 8)
                if isNext, !train.isCancelled {
                    Text("Nächster")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(StedeTheme.seaTeal.opacity(0.25), in: Capsule())
                }
                Text(train.line)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(StedeTheme.deep, in: Capsule())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let platform = train.platformLabel {
                    Text("Gl. \(platform)")
                        .font(.caption)
                        .foregroundStyle(train.platformChanged ? StedeTheme.harborRed : .secondary)
                        .monospacedDigit()
                }
            }

            Text(destinationLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if let note = train.notes.first, !train.isCancelled {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(StedeTheme.harborRed)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isPast ? 0.55 : 1)
        .stedeCard(highlighted: isNext && !train.isCancelled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isNext && !train.isCancelled ? .isSelected : [])
    }

    private static let timeFormat = Date.FormatStyle(locale: IslandTime.germanLocale, timeZone: IslandTime.timeZone)
        .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)

    private var destinationLine: String {
        // Nur die nächsten Halte, sonst wird die Zeile zur Streckenliste.
        let stops = train.via.prefix(3)
        guard !stops.isEmpty else { return "nach \(train.destination)" }
        return "nach \(train.destination) · über \(stops.joined(separator: ", "))"
    }

    /// VoiceOver liest sonst „plus fünf" und „Gl. 3" ohne Zusammenhang.
    private var accessibilityText: String {
        var parts = ["\(train.line) nach \(train.destination)", "Abfahrt \(train.scheduled.formatted(Self.timeFormat)) Uhr"]
        if train.isCancelled {
            parts.append("fällt aus")
        } else {
            if train.delayMinutes > 0 { parts.append("\(train.delayMinutes) Minuten Verspätung") }
            if isNext { parts.append("nächster Zug") }
            if isPast { parts.append("bereits abgefahren") }
        }
        if let platform = train.platformLabel { parts.append("Gleis \(platform)") }
        if let note = train.notes.first { parts.append(note) }
        return parts.joined(separator: ", ")
    }
}
