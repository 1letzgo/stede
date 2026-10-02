import StedeCore
import SwiftUI

struct FerryView: View {
    @State private var harbor: FerryHarbor = .mainland
    @Environment(SelectedDateStore.self) private var dateStore
    @State private var model = FerryViewModel()

    var body: some View {
        TabScreen(title: "Fähre") {
            await model.load(day: dateStore.selectedDate, force: true)
        } content: {
            VStack(spacing: 0) {
                HarborSwitcher(selection: $harbor)
                    .padding(.top)
                    .padding(.bottom, StedeTheme.cardSpacing)

                LoadStateView(state: model.state, emptyMessage: "Für diesen Tag sind keine Fährzeiten hinterlegt.") {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: StedeTheme.cardSpacing) {
                            if trips.isEmpty {
                                InfoCard {
                                    Text("Keine Fahrten ab \(harbor.title)")
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                ForEach(trips) { trip in
                                    FerryCard(
                                        trip: trip,
                                        isNext: dateStore.isToday && trip.id == nextTripID,
                                        isPast: dateStore.isToday && trip.abfahrt < Date()
                                    )
                                }
                            }
                            SourceFooter(text: Tenants.current.ferry?.source ?? "")
                        }
                        // Gleiche Abstände wie in Gastro und Fahrradverleih.
                        .padding([.horizontal, .bottom])
                    }
                    // Der Fahrplan bleibt oben stehen — er ist kurz genug,
                    // dass der ganze Tag auf einen Blick sichtbar ist.
                    .id("ferry-\(IslandTime.isoDate(dateStore.selectedDate))-\(harbor.title)")
                }
            }
        }
        .task(id: dateStore.selectedDate) {
            await model.load(day: dateStore.selectedDate)
        }
    }

    private var trips: [FerryTrip] {
        switch harbor {
        case .mainland: model.outbound
        case .island: model.inbound
        }
    }

    private var nextTripID: FerryTrip.ID? {
        trips.first { $0.abfahrt > Date() && !$0.ausgefallen }?.id
    }

}

/// Abfahrtshafen; die Namen kommen aus `tenants.config.ferry`.
enum FerryHarbor: CaseIterable, Hashable {
    case mainland
    case island

    var title: String {
        switch self {
        case .mainland: Tenants.current.ferry?.mainlandName ?? "Festland"
        case .island: Tenants.current.ferry?.islandName ?? "Insel"
        }
    }
}

private struct HarborSwitcher: View {
    @Binding var selection: FerryHarbor

    var body: some View {
        // Zwei Häfen, zwei gleich breite Hälften — wie die Tageszeile nutzt
        // die Reihe die Maße von StedeTheme.SelectionRow, ordnet aber selbst an.
        HStack(spacing: StedeTheme.SelectionRow.spacing) {
            ForEach(FerryHarbor.allCases, id: \.self) { harbor in
                Button {
                    selection = harbor
                } label: {
                    Text(harbor.title)
                        .frame(maxWidth: .infinity)
                        .stedeSelectionChip(isSelected: selection == harbor)
                }
                .buttonStyle(StedeCardButtonStyle())
                .accessibilityAddTraits(selection == harbor ? .isSelected : [])
            }
        }
        .padding(.horizontal, StedeTheme.SelectionRow.horizontalInset)
        .fixedSize(horizontal: false, vertical: true)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

private struct FerryCard: View {
    let trip: FerryTrip
    let isNext: Bool
    var isPast = false
    @State private var showBooking = false

    private var bookingURL: URL? { Tenants.current.ferry?.bookingURL.flatMap(URL.init(string:)) }

    var body: some View {
        Button {
            showBooking = true
        } label: {
            card
        }
        .buttonStyle(StedeCardButtonStyle())
        .foregroundStyle(.primary)
        .disabled(trip.ausgefallen || bookingURL == nil)
        .accessibilityHint(trip.ausgefallen || bookingURL == nil ? "" : "Öffnet die Vorbestellung im Browser")
        .sheet(isPresented: $showBooking) {
            if let bookingURL { InAppBrowser(url: bookingURL) }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(timeRange)
                    .font(.title3.weight(.semibold))
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .strikethrough(trip.ausgefallen)
                if trip.ausgefallen {
                    Text("fällt aus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(StedeTheme.harborRed)
                }
                if trip.ausflug {
                    Text("Ausflug")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if isNext, !trip.ausgefallen {
                    Text("Nächste")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(StedeTheme.seaTeal.opacity(0.25), in: Capsule())
                }
                Text(trip.fahrzeug)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !trip.ausgefallen {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, occupancyPercent == nil ? 14 : 8)

            if let percent = occupancyPercent {
                Text("Auslastung \(percent) %")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            if !trip.ausgefallen, let percent = trip.auslastungPersonen {
                OccupancyBar(percent: percent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isPast ? 0.55 : 1)
        .stedeCard(highlighted: isNext && !trip.ausgefallen)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isNext && !trip.ausgefallen ? .isSelected : [])
    }

    /// VoiceOver liest sonst „Pfeil nach rechts" und die Auslastung als lose Zahl.
    private var accessibilityText: String {
        let format = Date.FormatStyle(date: .omitted, time: .shortened).locale(IslandTime.germanLocale)
        var parts = [
            "Abfahrt \(trip.abfahrt.formatted(format)) Uhr" + (trip.ankunft.map { ", Ankunft \($0.formatted(format)) Uhr" } ?? ""),
        ]
        if trip.ausgefallen {
            parts.append("fällt aus")
        } else {
            if isNext { parts.append("nächste Fahrt") }
            if isPast { parts.append("bereits abgefahren") }
            if let percent = occupancyPercent { parts.append("Auslastung \(percent) Prozent") }
        }
        if trip.ausflug { parts.append("Ausflug") }
        parts.append(trip.fahrzeug)
        return parts.joined(separator: ", ")
    }

    private var occupancyPercent: Int? {
        trip.ausgefallen ? nil : trip.auslastungPersonen
    }

    private var timeRange: String {
        let format = Date.FormatStyle(date: .omitted, time: .shortened).locale(IslandTime.germanLocale)
        guard let ankunft = trip.ankunft else { return trip.abfahrt.formatted(format) }
        return "\(trip.abfahrt.formatted(format)) → \(ankunft.formatted(format))"
    }
}

private struct OccupancyBar: View {
    let percent: Int

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(color.opacity(0.18))
                Rectangle()
                    .fill(color)
                    .frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }

    private var fraction: CGFloat {
        min(max(CGFloat(percent) / 100, 0), 1)
    }

    private var color: Color {
        switch percent {
        case ..<50: StedeTheme.duneGreen
        case ..<80: StedeTheme.sunAmber
        default: StedeTheme.harborRed
        }
    }
}
