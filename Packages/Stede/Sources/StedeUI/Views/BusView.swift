import SwiftUI
import StedeCore

/// Busabfahrten einer Haltestelle; die Haltestelle wählt ein Menü oben und
/// bleibt über `@AppStorage` gemerkt.
struct BusView: View {
    /// Bleibt über App-Starts gemerkt; die Startseite liest denselben Schlüssel.
    @AppStorage("bus.stop") private var stopID: String = BusStop.zob.id
    @Environment(SelectedDateStore.self) private var dateStore
    @State private var model = BusViewModel()

    private var stop: BusStop { BusStop.stop(id: stopID) }

    var body: some View {
        TabScreen(title: "Bus") {
            await model.load(stop: stop, day: dateStore.selectedDate, force: true)
        } content: {
            VStack(spacing: 0) {
                BusStopMenu(selection: $stopID)
                    .padding(.top)
                    .padding(.bottom, StedeTheme.cardSpacing)

                LoadStateView(state: model.state, emptyMessage: emptyMessage) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: StedeTheme.cardSpacing) {
                            if visibleDepartures.isEmpty {
                                InfoCard {
                                    Text(emptyMessage)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            ForEach(visibleDepartures) { bus in
                                BusCard(
                                    bus: bus,
                                    isNext: dateStore.isToday && bus.id == nextID,
                                    isPast: dateStore.isToday && bus.departure < Date()
                                )
                            }
                            SourceFooter(text: "\(stop.name) · VBN-Fahrplaner, fahrplaner.vbn.de")
                        }
                        .padding([.horizontal, .bottom])
                    }
                }
            }
        }
        .task(id: "\(stopID)|\(IslandTime.isoDate(dateStore.selectedDate))") {
            await model.load(stop: stop, day: dateStore.selectedDate)
        }
    }

    private var emptyMessage: String {
        dateStore.isToday ? "Heute fährt hier kein Bus mehr." : "Für diesen Tag stehen hier keine Abfahrten im Fahrplan."
    }

    private var nextID: BusDeparture.ID? {
        model.departures.first { $0.departure > Date() && !$0.isCancelled }?.id
    }

    /// Heute nur, was noch kommt — abgefahrene Busse interessieren nicht mehr.
    private var visibleDepartures: [BusDeparture] {
        guard dateStore.isToday else { return model.departures }
        let now = Date()
        return model.departures.filter { $0.departure >= now }
    }
}

/// Chip wie der Richtungsumschalter der Bahn; ein Tipp öffnet die Haltestellenliste
/// als Sheet. Kein `Menu`/`Picker` — deren Label zeichnet sich spürbar verzögert.
private struct BusStopMenu: View {
    @Binding var selection: String
    @State private var showsList = false

    var body: some View {
        Button {
            showsList = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "bus.fill")
                Text(BusStop.stop(id: selection).shortName)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .stedeSelectionChip(isSelected: true)
        }
        .buttonStyle(StedeCardButtonStyle())
        .accessibilityLabel("Haltestelle wählen, \(BusStop.stop(id: selection).name)")
        .padding(.horizontal, StedeTheme.SelectionRow.horizontalInset)
        .fixedSize(horizontal: false, vertical: true)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .sheet(isPresented: $showsList) {
            BusStopSheet(selection: $selection)
        }
    }
}

private struct BusStopSheet: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(BusStop.all) { stop in
                Button {
                    selection = stop.id
                    dismiss()
                } label: {
                    HStack {
                        Text(stop.shortName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if stop.id == selection {
                            Image(systemName: "checkmark")
                                .foregroundStyle(StedeTheme.ink)
                                .fontWeight(.semibold)
                        }
                    }
                }
                .accessibilityAddTraits(stop.id == selection ? .isSelected : [])
            }
            .navigationTitle("Haltestelle")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct BusCard: View {
    let bus: BusDeparture
    let isNext: Bool
    var isPast = false

    private static let timeFormat = Date.FormatStyle(locale: IslandTime.germanLocale, timeZone: IslandTime.timeZone)
        .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(bus.scheduled.formatted(Self.timeFormat))
                    .font(.title3.weight(.semibold))
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .strikethrough(bus.isCancelled)
                if bus.isCancelled {
                    Text("fällt aus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(StedeTheme.harborRed)
                } else if let delay = bus.delayMinutes, delay > 0 {
                    Text("+\(delay)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(StedeTheme.harborRed)
                }
                Spacer(minLength: 8)
                if isNext, !bus.isCancelled {
                    Text("Nächster")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(StedeTheme.seaTeal.opacity(0.25), in: Capsule())
                        .fixedSize()
                }
                Text(bus.line)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(StedeTheme.deep, in: Capsule())
                    .foregroundStyle(.white)
                    .fixedSize()
                if let platform = bus.platform {
                    Text("Steig \(platform)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .fixedSize()
                }
            }
            Text("nach \(bus.destination)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isPast ? 0.55 : 1)
        .stedeCard(highlighted: isNext && !bus.isCancelled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = ["Linie \(bus.line) nach \(bus.destination)", "Abfahrt \(bus.scheduled.formatted(Self.timeFormat)) Uhr"]
        if bus.isCancelled { parts.append("fällt aus") }
        else if let delay = bus.delayMinutes, delay > 0 { parts.append("\(delay) Minuten Verspätung") }
        if isNext { parts.append("nächster Bus") }
        if isPast { parts.append("bereits abgefahren") }
        if let platform = bus.platform { parts.append("Steig \(platform)") }
        return parts.joined(separator: ", ")
    }
}
