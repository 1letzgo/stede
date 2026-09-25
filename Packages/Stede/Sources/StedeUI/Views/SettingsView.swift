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
        ScrollView {
            VStack(alignment: .leading, spacing: StedeTheme.cardSpacing) {
                StedeSectionHeader(title: "Konto", symbol: "person.crop.circle")
                NavigationLink {
                    AccountView(embedded: true)
                } label: {
                    HStack(spacing: 12) {
                        accountRow
                        Spacer(minLength: 0)
                        SettingsChevron()
                    }
                    .stedeRowCard()
                }
                .buttonStyle(StedeCardButtonStyle())
                .foregroundStyle(.primary)

                StedeSectionHeader(title: "Zuhause", symbol: "house.fill")
                SettingsCard {
                    pickerRow("Straße", value: street?.name ?? "Nicht gewählt", symbol: "house.fill", tint: StedeTheme.duneGreen) {
                        showsStreets = true
                    }
                    if let street, street.needsSection {
                        SettingsDivider()
                        menuRow("Abschnitt", selection: $sectionID, options: street.sections ?? [])
                    }
                    if let street, street.needsBranchSection {
                        SettingsDivider()
                        menuRow("Ast- und Strauchwerk", selection: $branchSectionID, options: street.branchSections ?? [])
                    }
                }
                SettingsFootnote("Für den Abfuhrkalender auf der Startseite.")

                StedeSectionHeader(title: "Unterwegs", symbol: "tram.fill")
                SettingsCard {
                    pickerRow("Bushaltestelle", value: BusStop.stop(id: busStopID).shortName, symbol: "bus.fill", tint: StedeTheme.seaTeal) {
                        showsStops = true
                    }
                    SettingsDivider()
                    HStack(spacing: 12) {
                        SettingsIcon(symbol: "tram.fill", tint: StedeTheme.harborRed)
                        Text("Bahn-Richtung")
                        Spacer(minLength: 8)
                        Picker("Bahn-Richtung", selection: $direction) {
                            ForEach(TrainDirection.allCases, id: \.self) { Text($0.shortTitle).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .tint(StedeTheme.ink)
                    }
                    .padding(.vertical, 6)
                }

                StedeSectionHeader(title: "Startseite", symbol: "square.grid.2x2.fill")
                NavigationLink {
                    HomeLayoutSettings()
                } label: {
                    HStack(spacing: 12) {
                        SettingsIcon(symbol: "square.grid.2x2.fill", tint: StedeTheme.ink)
                        Text("Startseite anpassen")
                        Spacer(minLength: 0)
                        SettingsChevron()
                    }
                    .stedeRowCard()
                }
                .buttonStyle(StedeCardButtonStyle())
                .foregroundStyle(.primary)
                SettingsFootnote("Reihenfolge der Bereiche und Kacheln, und welche Kacheln erscheinen.")

                StedeSectionHeader(title: "App", symbol: "info.circle.fill")
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Self.version).foregroundStyle(.secondary)
                }
                .stedeRowCard()
            }
            .padding()
        }
        .background(StedeTheme.sand)
        .navigationTitle("Einstellungen")
        .stedeBar()
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

    private func menuRow(_ title: String, selection: Binding<Int>, options: [WasteSection]) -> some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 8)
            Picker(title, selection: selection) {
                Text("Bitte wählen").tag(0)
                ForEach(options) { Text($0.label).tag($0.id) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(StedeTheme.ink)
        }
        .padding(.vertical, 6)
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
            HStack(spacing: 12) {
                SettingsIcon(symbol: symbol, tint: tint)
                Text(title)
                Spacer(minLength: 8)
                Text(value).foregroundStyle(.secondary).lineLimit(1)
                SettingsChevron()
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(StedeCardButtonStyle())
        .foregroundStyle(.primary)
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }
}

/// Reihenfolge der Bereiche und Kacheln (Pfeile) und Kacheln ein- und ausblenden.
private struct HomeLayoutSettings: View {
    @AppStorage(HomeLayout.orderKey) private var orderRaw = HomeLayout.defaultOrder
    @AppStorage(HomeLayout.hiddenKey) private var hiddenRaw = ""
    @AppStorage(HomeLayout.tilesKey) private var tilesRaw = ""

    private var order: [HomeSection] { HomeLayout.order(orderRaw) }
    private var hidden: Set<HomeTileID> { HomeLayout.hidden(hiddenRaw) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StedeTheme.cardSpacing) {
                StedeSectionHeader(title: "Reihenfolge", symbol: "arrow.up.arrow.down")
                SettingsCard {
                    ForEach(Array(order.enumerated()), id: \.element) { index, section in
                        if index > 0 { SettingsDivider() }
                        HStack(spacing: 12) {
                            SettingsIcon(symbol: section.symbol, tint: StedeTheme.ink)
                            Text(section.title)
                            Spacer(minLength: 8)
                            MoveButtons(canMoveUp: index > 0, canMoveDown: index < order.count - 1) { delta in
                                var sections = order
                                sections.swapAt(index, index + delta)
                                withAnimation { orderRaw = HomeLayout.encode(sections) }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                ForEach(order) { section in
                    let tiles = HomeLayout.tiles(in: section, order: tilesRaw)
                    StedeSectionHeader(title: section.title, symbol: section.symbol)
                    SettingsCard {
                        ForEach(Array(tiles.enumerated()), id: \.element) { index, tile in
                            if index > 0 { SettingsDivider() }
                            HStack(spacing: 12) {
                                SettingsIcon(symbol: tile.symbol, tint: tile.tint)
                                Text(tile.title).lineLimit(1)
                                Spacer(minLength: 8)
                                if tiles.count > 1 {
                                    MoveButtons(canMoveUp: index > 0, canMoveDown: index < tiles.count - 1) { delta in
                                        withAnimation {
                                            tilesRaw = HomeLayout.moveTiles(in: section, order: tilesRaw, from: IndexSet(integer: index),
                                                                           to: delta > 0 ? index + 2 : index - 1)
                                        }
                                    }
                                }
                                Toggle(tile.title, isOn: binding(for: tile))
                                    .labelsHidden()
                                    .tint(StedeTheme.ink)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    if section == .city { SettingsFootnote("Die ersten beiden sichtbaren Kacheln erscheinen groß.") }
                }

                Button {
                    withAnimation {
                        orderRaw = HomeLayout.defaultOrder
                        hiddenRaw = ""
                        tilesRaw = ""
                    }
                } label: {
                    Text("Standard wiederherstellen")
                        .frame(maxWidth: .infinity)
                        .stedeSelectionChip(isSelected: false)
                }
                .buttonStyle(StedeCardButtonStyle())
                .disabled(orderRaw == HomeLayout.defaultOrder && hiddenRaw.isEmpty && tilesRaw.isEmpty)
                .padding(.top, 8)
            }
            .padding()
        }
        .background(StedeTheme.sand)
        .navigationTitle("Startseite")
        .stedeBar()
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

/// Pfeile hoch/runter zum Verschieben einer Zeile.
private struct MoveButtons: View {
    let canMoveUp: Bool
    let canMoveDown: Bool
    let move: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            arrow("chevron.up", enabled: canMoveUp, label: "Nach oben") { move(-1) }
            arrow("chevron.down", enabled: canMoveDown, label: "Nach unten") { move(1) }
        }
    }

    private func arrow(_ symbol: String, enabled: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.footnote.weight(.bold))
                .frame(width: 32, height: 32)
                .background(StedeTheme.ink.opacity(enabled ? 0.1 : 0.04), in: Circle())
                .foregroundStyle(enabled ? StedeTheme.ink : Color.secondary.opacity(0.4))
        }
        .buttonStyle(StedeCardButtonStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

/// Karte mit mehreren Einstellungszeilen — gleiche Form wie alle Karten der App.
private struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.horizontal, StedeTheme.cardPadding)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .stedeCard()
    }
}

/// Trennlinie zwischen Zeilen, eingerückt bis hinter das Symbol.
private struct SettingsDivider: View {
    var body: some View {
        Rectangle().fill(.separator).frame(height: 0.5).padding(.leading, 42)
    }
}

private struct SettingsChevron: View {
    var body: some View {
        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
    }
}

/// Kleiner Hinweis unter einer Karte.
private struct SettingsFootnote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4).padding(.top, -4)
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
