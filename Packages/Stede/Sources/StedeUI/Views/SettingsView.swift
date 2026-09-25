import StedeCore
import SwiftUI

/// Tab „Einstellungen“: Konto, Straße und Haltestelle, Aufbau der Startseite.
/// Alle Werte liegen unter denselben `@AppStorage`-Schlüsseln wie in Start, Bus und Abfuhr.
struct SettingsView: View {
    @Environment(AuthStore.self) private var auth
    @AppStorage("waste.street") private var streetID: Int = 0
    @AppStorage("waste.section") private var sectionID: Int = 0
    @AppStorage("waste.branchSection") private var branchSectionID: Int = 0
    @AppStorage("bus.stop") private var busStopID: String = BusStop.zob.id
    @AppStorage("train.direction") private var direction: TrainDirection = .oldenburg
    @State private var showsStreets = false
    @State private var showsStops = false

    private var street: WasteStreet? { WasteSettings.street(id: streetID) }

    var body: some View {
        Form {
            Section("Konto") {
                NavigationLink {
                    AccountView(embedded: true)
                } label: {
                    accountRow
                }
            }

            Section {
                pickerRow("Straße", value: street?.name ?? "Nicht gewählt", symbol: "house.fill", tint: StedeTheme.duneGreen) {
                    showsStreets = true
                }
                if let street, street.needsSection {
                    Picker("Abschnitt", selection: $sectionID) {
                        Text("Bitte wählen").tag(0)
                        ForEach(street.sections ?? []) { Text($0.label).tag($0.id) }
                    }
                }
                if let street, street.needsBranchSection {
                    Picker("Ast- und Strauchwerk", selection: $branchSectionID) {
                        Text("Bitte wählen").tag(0)
                        ForEach(street.branchSections ?? []) { Text($0.label).tag($0.id) }
                    }
                }
            } header: {
                Text("Zuhause")
            } footer: {
                Text("Für den Abfuhrkalender auf der Startseite.")
            }

            Section("Unterwegs") {
                pickerRow("Bushaltestelle", value: BusStop.stop(id: busStopID).shortName, symbol: "bus.fill", tint: StedeTheme.seaTeal) {
                    showsStops = true
                }
                Picker(selection: $direction) {
                    ForEach(TrainDirection.allCases, id: \.self) { Text($0.shortTitle).tag($0) }
                } label: {
                    Label { Text("Bahn-Richtung") } icon: { SettingsIcon(symbol: "tram.fill", tint: StedeTheme.harborRed) }
                }
            }

            Section {
                NavigationLink {
                    HomeLayoutSettings()
                } label: {
                    Label { Text("Startseite anpassen") } icon: { SettingsIcon(symbol: "square.grid.2x2.fill", tint: StedeTheme.ink) }
                }
            } footer: {
                Text("Reihenfolge der Bereiche und welche Kacheln erscheinen.")
            }

            Section {
                LabeledContent("Version", value: Self.version)
            }
        }
        .navigationTitle("Einstellungen")
        .stedeSheetForm()
        .safeAreaPadding(.bottom, StedeTheme.SelectionRow.height)
        .sheet(isPresented: $showsStreets) {
            StreetSheet(selection: $streetID) {
                sectionID = 0
                branchSectionID = 0
            }
        }
        .sheet(isPresented: $showsStops) {
            BusStopSheet(selection: $busStopID)
        }
    }

    @ViewBuilder private var accountRow: some View {
        HStack(spacing: 12) {
            if auth.isSignedIn {
                PersonAvatar(url: auth.profile?.avatarURL, name: auth.profile?.displayName ?? "?", side: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(auth.profile?.displayName ?? "Konto").font(.headline)
                    Text("Profil, Kalender-Abo, Abmelden").font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                StedeIconChip(symbol: "person.crop.circle", color: StedeTheme.ink, side: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Anmelden").font(.headline)
                    Text("Für Gruppen und ihre Termine").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func pickerRow(_ title: String, value: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label { Text(title).foregroundStyle(.primary) } icon: { SettingsIcon(symbol: symbol, tint: tint) }
                Spacer()
                Text(value).foregroundStyle(.secondary).lineLimit(1)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .tint(.primary)
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }
}

/// Reihenfolge der Bereiche (ziehen) und Kacheln ein- und ausblenden.
private struct HomeLayoutSettings: View {
    @AppStorage(HomeLayout.orderKey) private var orderRaw = HomeLayout.defaultOrder
    @AppStorage(HomeLayout.hiddenKey) private var hiddenRaw = ""

    private var order: [HomeSection] { HomeLayout.order(orderRaw) }
    private var hidden: Set<HomeTileID> { HomeLayout.hidden(hiddenRaw) }

    var body: some View {
        List {
            Section {
                ForEach(order) { section in
                    Label { Text(section.title) } icon: { SettingsIcon(symbol: section.symbol, tint: StedeTheme.ink) }
                }
                .onMove { from, to in
                    var sections = order
                    sections.move(fromOffsets: from, toOffset: to)
                    orderRaw = HomeLayout.encode(sections)
                }
            } header: {
                Text("Reihenfolge")
            } footer: {
                Text("Zum Verschieben an den Griffen ziehen.")
            }

            ForEach(order) { section in
                Section(section.title) {
                    ForEach(section.tiles) { tile in
                        Toggle(isOn: binding(for: tile)) {
                            Label { Text(tile.title) } icon: { SettingsIcon(symbol: tile.symbol, tint: tile.tint) }
                        }
                    }
                }
            }

            Section {
                Button("Standard wiederherstellen") {
                    orderRaw = HomeLayout.defaultOrder
                    hiddenRaw = ""
                }
                .disabled(orderRaw == HomeLayout.defaultOrder && hiddenRaw.isEmpty)
            }
        }
        #if os(iOS)
        .environment(\.editMode, .constant(.active))
        #endif
        .navigationTitle("Startseite")
        .stedeSheetForm()
        .safeAreaPadding(.bottom, StedeTheme.SelectionRow.height)
    }

    private func binding(for tile: HomeTileID) -> Binding<Bool> {
        Binding {
            !hidden.contains(tile)
        } set: { visible in
            var set = hidden
            if visible { set.remove(tile) } else { set.insert(tile) }
            hiddenRaw = HomeLayout.encode(set)
        }
    }
}

/// Kleines Symbol-Kästchen vor Einstellungszeilen, wie in der System-App.
private struct SettingsIcon: View {
    let symbol: String
    let tint: Color
    @ScaledMetric(relativeTo: .body) private var side = 30.0

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: side * 0.5, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: side, height: side)
            .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: side * 0.26, style: .continuous))
    }
}
