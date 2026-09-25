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
                        menuRow("Abschnitt", selection: $sectionID, options: street.sections ?? [])
                    }
                    if let street, street.needsBranchSection {
                        menuRow("Ast- und Strauchwerk", selection: $branchSectionID, options: street.branchSections ?? [])
                    }
                }
                SettingsFootnote("Für den Abfuhrkalender auf der Startseite.")

                StedeSectionHeader(title: "Unterwegs", symbol: "tram.fill")
                SettingsCard {
                    pickerRow("Bushaltestelle", value: BusStop.stop(id: busStopID).shortName, symbol: "bus.fill", tint: StedeTheme.seaTeal) {
                        showsStops = true
                    }
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
                    .frame(minHeight: 32)
            .stedeRowCard()
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
        .frame(minHeight: 32)
            .stedeRowCard()
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
            .frame(minHeight: 32)
            .stedeRowCard()
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

/// Reihenfolge der Bereiche und Kacheln (am Griff ≡ ziehen) und Kacheln ein- und ausblenden.
/// Eigene Karten statt `List`: nur so liegen die Griffe mit Abstand innerhalb der Karte.
private struct HomeLayoutSettings: View {
    @AppStorage(HomeLayout.orderKey) private var orderRaw = HomeLayout.defaultOrder
    @AppStorage(HomeLayout.hiddenKey) private var hiddenRaw = HomeLayout.defaultHidden
    @AppStorage(HomeLayout.tilesKey) private var tilesRaw = ""
    /// Während eine Zeile gezogen wird, scrollt die Seite nicht mit.
    @State private var isReordering = false

    private var order: [HomeSection] { HomeLayout.order(orderRaw) }
    private var hidden: Set<HomeTileID> { HomeLayout.hidden(hiddenRaw) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StedeTheme.cardSpacing) {
                StedeSectionHeader(title: "Reihenfolge", symbol: "arrow.up.arrow.down")
                ReorderableStack(items: order, isReordering: $isReordering) { from, to in
                    var sections = order
                    sections.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                    orderRaw = HomeLayout.encode(sections)
                } row: { section in
                    HStack(spacing: 12) {
                        SettingsIcon(symbol: section.symbol, tint: StedeTheme.ink)
                        Text(section.title)
                        Spacer(minLength: 8)
                        DragHandle()
                    }
                    .frame(minHeight: 32)
                }
                SettingsFootnote("Zum Verschieben eine Zeile kurz gedrückt halten und ziehen.")

                ForEach(order) { section in
                    let tiles = HomeLayout.tiles(in: section, order: tilesRaw)
                    StedeSectionHeader(title: section.title, symbol: section.symbol)
                    ReorderableStack(items: tiles, isReordering: $isReordering) { from, to in
                        tilesRaw = HomeLayout.moveTiles(in: section, order: tilesRaw, from: IndexSet(integer: from), to: to > from ? to + 1 : to)
                    } row: { tile in
                        HStack(spacing: 12) {
                            SettingsIcon(symbol: tile.symbol, tint: tile.tint)
                            Text(tile.title).lineLimit(1)
                            Spacer(minLength: 8)
                            Toggle(tile.title, isOn: binding(for: tile))
                                .labelsHidden()
                                .tint(StedeTheme.ink)
                            if tiles.count > 1 { DragHandle() }
                        }
                        .frame(minHeight: 32)
                    }
                    if section == .city { SettingsFootnote("Die ersten beiden sichtbaren Kacheln erscheinen groß.") }
                }

                Button {
                    withAnimation {
                        orderRaw = HomeLayout.defaultOrder
                        hiddenRaw = HomeLayout.defaultHidden
                        tilesRaw = ""
                    }
                } label: {
                    Text("Standard wiederherstellen")
                        .frame(maxWidth: .infinity)
                        .stedeSelectionChip(isSelected: false)
                }
                .buttonStyle(StedeCardButtonStyle())
                .disabled(orderRaw == HomeLayout.defaultOrder && hiddenRaw == HomeLayout.defaultHidden && tilesRaw.isEmpty)
                .padding(.top, 8)
            }
            .padding()
        }
        .scrollDisabled(isReordering)
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

/// Umsortierbare Kartenliste: Zeile kurz gedrückt halten, sie hebt sich an und folgt dem
/// Finger, die übrigen rücken live beiseite; beim Loslassen rastet sie am neuen Platz ein.
/// Eigene Geste statt Drag & Drop — die System-Variante springt und rastet unsauber ein.
private struct ReorderableStack<Item: Hashable, Row: View>: View {
    let items: [Item]
    @Binding var isReordering: Bool
    /// Von Index, nach Index (Endposition).
    let move: (Int, Int) -> Void
    @ViewBuilder let row: (Item) -> Row

    @State private var dragged: Item?
    @State private var translation: CGFloat = 0
    @State private var rowHeight: CGFloat = 56

    private var step: CGFloat { rowHeight + StedeTheme.cardSpacing }

    private var fromIndex: Int? { dragged.flatMap { items.firstIndex(of: $0) } }

    private var targetIndex: Int? {
        guard let from = fromIndex else { return nil }
        let shift = Int((translation / step).rounded())
        return min(max(from + shift, 0), items.count - 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StedeTheme.cardSpacing) {
            ForEach(Array(items.enumerated()), id: \.element) { index, item in
                let isDragged = item == dragged
                row(item)
                    .stedeRowCard()
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowHeight = $0 }
                    .scaleEffect(isDragged ? 1.03 : 1)
                    .shadow(color: .black.opacity(isDragged ? 0.18 : 0), radius: 12, y: 6)
                    .offset(y: offset(for: index, isDragged: isDragged))
                    .zIndex(isDragged ? 1 : 0)
                    .animation(isDragged ? nil : .snappy(duration: 0.22), value: targetIndex)
                    .gesture(reorderGesture(for: item), including: items.count > 1 ? .all : .subviews)
                    .sensoryFeedback(.selection, trigger: isDragged ? targetIndex : nil)
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: dragged != nil)
    }

    private func offset(for index: Int, isDragged: Bool) -> CGFloat {
        if isDragged { return translation }
        guard let from = fromIndex, let to = targetIndex else { return 0 }
        if from < to, index > from, index <= to { return -step }
        if to < from, index >= to, index < from { return step }
        return 0
    }

    private func reorderGesture(for item: Item) -> some Gesture {
        LongPressGesture(minimumDuration: 0.25)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if dragged == nil {
                    withAnimation(.snappy(duration: 0.18)) { dragged = item }
                    isReordering = true
                }
                translation = drag?.translation.height ?? 0
            }
            .onEnded { _ in
                guard let from = fromIndex, let to = targetIndex else { reset(); return }
                withAnimation(.snappy(duration: 0.25)) {
                    if from != to { move(from, to) }
                    dragged = nil
                    translation = 0
                }
                isReordering = false
            }
    }

    private func reset() {
        withAnimation(.snappy) { dragged = nil; translation = 0 }
        isReordering = false
    }
}

/// Griff ≡ rechts in der Zeile, mit Abstand zur Kartenkante (kommt vom Karten-Padding).
private struct DragHandle: View {
    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.body.weight(.medium))
            .foregroundStyle(.tertiary)
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)
    }
}

/// Gruppe von Einstellungszeilen — jede Zeile ist eine eigene Karte (`stedeRowCard`).
private struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: StedeTheme.cardSpacing) { content() }
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
