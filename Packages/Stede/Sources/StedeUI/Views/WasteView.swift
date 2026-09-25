import StedeCore
import SwiftUI

/// Abfuhrkalender für die Straße aus den Einstellungen: die kommenden Termine nach Monaten.
struct WasteView: View {
    @AppStorage("waste.street") private var streetID: Int = 0
    @AppStorage("waste.section") private var sectionID: Int = 0
    @AppStorage("waste.branchSection") private var branchSectionID: Int = 0
    @State private var model = WasteViewModel()
    @Environment(AppNavigation.self) private var navigation

    private var street: WasteStreet? { WasteSettings.street(id: streetID) }
    private var selection: WasteSelection? {
        WasteSettings.selection(streetID: streetID, sectionID: sectionID, branchSectionID: branchSectionID)
    }

    var body: some View {
        TabScreen(title: "Abfuhr", showsDateNavigator: false) {
            await model.load(selection: selection, force: true)
        } content: {
            VStack(spacing: 0) {
                if selection == nil {
                    ScrollView {
                        InfoCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(street == nil
                                     ? "Wähle deine Straße in den Einstellungen, dann erscheinen hier die Abfuhrtermine."
                                     : "Wähle in den Einstellungen den Abschnitt deiner Straße.")
                                    .foregroundStyle(.secondary)
                                Button { navigation.tab = .settings } label: {
                                    StedeColorChip(title: "Zu den Einstellungen", symbol: "gearshape.fill", color: StedeTheme.ink, prominent: true)
                                }
                                .buttonStyle(StedeCardButtonStyle())
                            }
                        }
                        .padding()
                    }
                } else {
                    LoadStateView(state: model.state, emptyMessage: "Für dieses Jahr stehen keine weiteren Termine im Kalender.") {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: StedeTheme.cardSpacing) {
                                ForEach(months, id: \.month) { group in
                                    StedeSectionHeader(title: group.title, symbol: "calendar")
                                    ForEach(group.items) { item in
                                        WasteCard(collection: item, isNext: item.id == model.collections.first?.id)
                                    }
                                }
                                SourceFooter(text: "\(WasteStreetStore.directory.source) · appfuhr.de · Angaben ohne Gewähr")
                            }
                            .padding()
                        }
                    }
                }
            }
        }
        .task(id: selection?.cacheKey ?? "") {
            await model.load(selection: selection)
        }
    }

    private var months: [(month: Int, title: String, items: [WasteCollection])] {
        var order: [Int] = []
        var groups: [Int: [WasteCollection]] = [:]
        let formatter = Date.FormatStyle(locale: IslandTime.germanLocale, timeZone: IslandTime.timeZone).month(.wide).year()
        for item in model.collections {
            let components = IslandTime.calendar.dateComponents([.year, .month], from: item.date)
            let key = (components.year ?? 0) * 100 + (components.month ?? 0)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(item)
        }
        return order.map { key in
            let first = groups[key]?.first?.date ?? Date()
            return (key, first.formatted(formatter), groups[key] ?? [])
        }
    }
}

/// Suchbare Liste aller 548 Straßen.
struct StreetSheet: View {
    @Binding var selection: Int
    let onChange: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var streets: [WasteStreet] {
        let all = WasteStreetStore.directory.streets
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        NavigationStack {
            List(streets) { street in
                Button {
                    if street.id != selection {
                        selection = street.id
                        onChange()
                    }
                    dismiss()
                } label: {
                    HStack {
                        Text(street.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        if street.id == selection {
                            Image(systemName: "checkmark")
                                .foregroundStyle(StedeTheme.ink)
                                .fontWeight(.semibold)
                        }
                    }
                }
                .accessibilityAddTraits(street.id == selection ? .isSelected : [])
            }
            .searchable(text: $query, prompt: "Straße in Westerstede")
            .navigationTitle("Straße")
            .stedeSheetForm()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}

private struct WasteCard: View {
    let collection: WasteCollection
    let isNext: Bool

    private static let dayFormat = Date.FormatStyle(locale: IslandTime.germanLocale, timeZone: IslandTime.timeZone)
        .weekday(.abbreviated).day().month(.abbreviated)

    var body: some View {
        HStack(spacing: 12) {
            StedeIconChip(symbol: collection.kind.symbol, color: collection.kind.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(collection.label)
                    .font(.headline)
                    .fontDesign(.rounded)
                Text(collection.date.formatted(Self.dayFormat))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if isNext {
                Text(relativeLabel)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(collection.kind.tint.opacity(0.22), in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .stedeCard(highlighted: isNext)
        .accessibilityElement(children: .combine)
    }

    private var relativeLabel: String {
        let days = IslandTime.calendar.dateComponents([.day], from: IslandTime.startOfDay(Date()), to: collection.date).day ?? 0
        switch days {
        case 0: return "Heute"
        case 1: return "Morgen"
        default: return "in \(days) Tagen"
        }
    }
}
