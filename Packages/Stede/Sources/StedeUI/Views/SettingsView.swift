import StedeCore
import SwiftUI

/// Tab „Einstellungen“: Konto, Straße und Haltestelle, Aufbau der Startseite.
/// Alle Werte liegen unter denselben `@AppStorage`-Schlüsseln wie in Start, Bus und Abfuhr.
struct SettingsView: View {
    @Environment(AuthStore.self) private var auth
    @AppStorage("waste.street") private var streetID: Int = 0
    @AppStorage("waste.section") private var sectionID: Int = 0
    @AppStorage("waste.branchSection") private var branchSectionID: Int = 0
    @AppStorage("waste.noOrganic") private var noOrganic = false
    @AppStorage("waste.fourWeekly") private var fourWeekly = false
    @AppStorage("bus.stop") private var busStopID: String = ""
    @AppStorage("train.direction") private var direction: TrainDirection = .oldenburg
    @AppStorage("train.station") private var stationID = ""
    @State private var showsTenants = false
    @AppStorage(RegionEvents.key) private var regionEvents = false
    @AppStorage(Audience.key) private var audienceRaw = ""
    @State private var showsStreets = false
    @State private var showsStops = false

    private var street: WasteStreet? { WasteSettings.street(id: streetID) }

    private var station: TenantConfig.Station {
        Tenants.current.station(id: stationID) ?? Tenants.current.stations[0]
    }

    /// Ohne Wahl gilt der Standardbahnhof der Gemeinde.
    private var stationBinding: Binding<String> {
        Binding(get: { station.id }, set: { stationID = $0 })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StedeTheme.cardSpacing) {
                // Reihenfolge: Konto · Plus · Ansicht · (Gemeinde) · Zuhause · Unterwegs · Kalender · Startseite · App.
                if Features.has(.groups) {
                    StedeSectionHeader(title: "Konto", symbol: "person.crop.circle")
                    SettingsCard {
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

                        #if os(iOS)
                        if auth.isSignedIn, AppBrand.current.hasPush {
                            NavigationLink {
                                NotificationSettingsView()
                            } label: {
                                HStack(spacing: 12) {
                                    SettingsIcon(symbol: "bell.fill", tint: StedeTheme.sunAmber)
                                    Text("Benachrichtigungen")
                                    Spacer(minLength: 0)
                                    SettingsChevron()
                                }
                                .frame(minHeight: 32)
                                .stedeRowCard()
                            }
                            .buttonStyle(StedeCardButtonStyle())
                            .foregroundStyle(.primary)
                        }
                        #endif
                    }
                }

                if Features.has(.plus) {
                    PlusSection()
                }

                StedeSectionHeader(title: "Ansicht", symbol: "person.2.fill")
                SettingsCard {
                    ForEach(Audience.allCases, id: \.self) { audience in
                        Button {
                            withAnimation(.snappy) { audienceRaw = audience.rawValue }
                        } label: {
                            HStack(spacing: 12) {
                                SettingsIcon(symbol: audience.symbol, tint: audience == .tourist ? StedeTheme.seaTeal : StedeTheme.duneGreen)
                                Text(audience.title)
                                Spacer(minLength: 8)
                                if audienceRaw == audience.rawValue {
                                    Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(StedeTheme.ink)
                                }
                            }
                            .frame(minHeight: 32)
                            .contentShape(Rectangle())
                            .stedeRowCard()
                        }
                        .buttonStyle(StedeCardButtonStyle())
                        .foregroundStyle(.primary)
                        .accessibilityAddTraits(audienceRaw == audience.rawValue ? .isSelected : [])
                    }
                }

                if AppBrand.current.choosesTenant {
                    StedeSectionHeader(title: "Gemeinde", symbol: "mappin.and.ellipse")
                    SettingsCard {
                        pickerRow("Gemeinde", value: Tenants.current.municipality, symbol: "mappin.and.ellipse", tint: StedeTheme.ink) {
                            showsTenants = true
                        }
                    }
                }

                if Features.has(.waste) {
                    StedeSectionHeader(title: "Zuhause", symbol: "house.fill")
                    SettingsCard {
                        pickerRow("Abfuhr", value: street?.name ?? "Nicht gewählt", symbol: "trash.fill", tint: StedeTheme.duneGreen) {
                            showsStreets = true
                        }
                        if let street, street.needsSection {
                            menuRow("Abschnitt", selection: $sectionID, options: street.sections ?? [])
                        }
                        if let street, street.needsBranchSection {
                            menuRow("Ast- und Strauchwerk", selection: $branchSectionID, options: street.branchSections ?? [])
                        }
                        // Wie auf der appfuhr-Website: Eigenkompostierer ohne Biotonne, Restabfall alle 4 Wochen.
                        if street != nil {
                            toggleRow("Keine Biotonne", symbol: "leaf.fill", tint: StedeTheme.duneGreen, isOn: $noOrganic)
                            toggleRow("Restabfall alle 4 Wochen", symbol: "trash.fill", tint: StedeTheme.ink, isOn: $fourWeekly)
                        }
                    }
                }

                if Features.has(.bus) || Features.has(.train) {
                    StedeSectionHeader(title: "Unterwegs", symbol: "tram.fill")
                    SettingsCard {
                        if Features.has(.bus) {
                            pickerRow("Bushaltestelle", value: BusStop.stop(id: busStopID).shortName, symbol: "bus.fill", tint: StedeTheme.seaTeal) {
                                showsStops = true
                            }
                        }
                        if Features.has(.train), !Tenants.current.stations.isEmpty {
                            HStack(spacing: 12) {
                                SettingsIcon(symbol: "tram.fill", tint: StedeTheme.harborRed)
                                Text("Bahnhof")
                                Spacer(minLength: 8)
                                SettingsMenu(title: "Bahnhof", selection: stationBinding, value: station.name,
                                             options: Tenants.current.stations.map { ($0.id, $0.name) })
                            }
                            .frame(minHeight: 32)
                            .stedeRowCard()
                            HStack(spacing: 12) {
                                SettingsIcon(symbol: "arrow.left.arrow.right", tint: StedeTheme.harborRed)
                                Text("Bahn-Richtung")
                                Spacer(minLength: 8)
                                SettingsMenu(title: "Bahn-Richtung", selection: $direction, value: direction.shortTitle(at: station),
                                             options: TrainDirection.allCases.map { ($0, $0.shortTitle(at: station)) })
                            }
                            .frame(minHeight: 32)
                            .stedeRowCard()
                        }
                    }
                }

                if AppBrand.current.offersRegionEvents, Features.has(.calendar) {
                    StedeSectionHeader(title: "Kalender", symbol: "calendar")
                    SettingsCard {
                        toggleRow("Termine der Region", symbol: "map.fill", tint: StedeTheme.seaTeal, isOn: $regionEvents)
                    }
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
        .sheet(isPresented: $showsTenants) {
            TenantPickerSheet()
        }
        .sheet(isPresented: $showsStops) {
            BusStopSheet(selection: $busStopID)
        }
    }

    private func menuRow(_ title: String, selection: Binding<Int>, options: [WasteSection]) -> some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 8)
            SettingsMenu(title: title, selection: selection,
                         value: options.first { $0.id == selection.wrappedValue }?.label ?? "Bitte wählen",
                         options: [(0, "Bitte wählen")] + options.map { ($0.id, $0.label) })
        }
        .frame(minHeight: 32)
        .stedeRowCard()
    }

    @ViewBuilder private var accountRow: some View {
        HStack(spacing: 12) {
            if auth.isSignedIn {
                PersonAvatar(url: auth.profile?.avatarURL, name: auth.profile?.displayName ?? "?", side: 44)
                Text(auth.profile?.displayName ?? "Konto").font(.headline)
            } else {
                StedeIconChip(symbol: "person.crop.circle", color: StedeTheme.ink, side: 44)
                Text("Anmelden").font(.headline)
            }
        }
        .padding(.vertical, 2)
    }

    private func toggleRow(_ title: String, symbol: String, tint: Color, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 12) {
                SettingsIcon(symbol: symbol, tint: tint)
                Text(title)
            }
        }
        .tint(StedeTheme.duneGreen)
        .frame(minHeight: 32)
        .stedeRowCard()
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
                    }
                    .frame(minHeight: 32)
                }

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
                        }
                        .frame(minHeight: 32)
                    }
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

/// Umsortierbare Kartenliste: am Griff ≡ ziehen — die Zeile hebt sich an und folgt dem Finger,
/// die übrigen rücken live beiseite, beim Loslassen rastet sie am neuen Platz ein. Nur der Griff
/// trägt die Geste, damit die Seite überall sonst normal scrollt. `@GestureState` setzt sich bei
/// einem Abbruch durch das System selbst zurück — nichts bleibt „hängen“.
private struct ReorderableStack<Item: Hashable, Row: View>: View {
    let items: [Item]
    @Binding var isReordering: Bool
    /// Von Index, nach Index (Endposition).
    let move: (Int, Int) -> Void
    @ViewBuilder let row: (Item) -> Row

    private struct Drag: Equatable { let item: Item; var dy: CGFloat }
    @GestureState private var drag: Drag?
    @State private var rowHeight: CGFloat = 56

    private var step: CGFloat { rowHeight + StedeTheme.cardSpacing }

    private func target(from: Int, dy: CGFloat) -> Int {
        min(max(from + Int((dy / step).rounded()), 0), items.count - 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StedeTheme.cardSpacing) {
            ForEach(Array(items.enumerated()), id: \.element) { index, item in
                let isDragged = drag?.item == item
                HStack(spacing: 12) {
                    row(item)
                    if items.count > 1 {
                        DragHandle()
                            .contentShape(Rectangle())
                            .highPriorityGesture(dragGesture(for: item))
                            .accessibilityHidden(true)
                    }
                }
                .stedeRowCard()
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowHeight = $0 }
                .scaleEffect(isDragged ? 1.03 : 1)
                .shadow(color: .black.opacity(isDragged ? 0.18 : 0), radius: 12, y: 6)
                .offset(y: offset(for: index, isDragged: isDragged))
                .zIndex(isDragged ? 1 : 0)
                .animation(isDragged ? nil : .snappy(duration: 0.22), value: drag.map { target(from: items.firstIndex(of: $0.item) ?? 0, dy: $0.dy) })
            }
        }
        .onChange(of: drag != nil) { isReordering = drag != nil }
        .sensoryFeedback(.impact(weight: .medium), trigger: drag != nil)
    }

    private func offset(for index: Int, isDragged: Bool) -> CGFloat {
        guard let drag, let from = items.firstIndex(of: drag.item) else { return 0 }
        if isDragged { return drag.dy }
        let to = target(from: from, dy: drag.dy)
        if from < to, index > from, index <= to { return -step }
        if to < from, index >= to, index < from { return step }
        return 0
    }

    private func dragGesture(for item: Item) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .updating($drag) { value, state, _ in
                state = Drag(item: item, dy: value.translation.height)
            }
            .onEnded { value in
                guard let from = items.firstIndex(of: item) else { return }
                let to = target(from: from, dy: value.translation.height)
                if from != to {
                    withAnimation(.snappy(duration: 0.25)) { move(from, to) }
                }
            }
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

/// Auswahlmenü mit grauem Wert wie die übrigen Zeilen („Straße“, „Bushaltestelle“) —
/// der System-Picker färbt seinen Wert in der Akzentfarbe und bricht lange Namen um.
private struct SettingsMenu<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let value: String
    let options: [(Value, String)]

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
            }
        } label: {
            HStack(spacing: 6) {
                Text(value)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        // Sonst färbt das Menü sein Label in der Akzentfarbe ein.
        .tint(.primary)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

private struct SettingsChevron: View {
    var body: some View {
        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
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
