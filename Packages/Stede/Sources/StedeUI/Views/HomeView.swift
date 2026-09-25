import SwiftUI
import StedeCore

/// Von Start gepushte Detailseiten.
enum HomeDestination: Hashable {
    case weather
    case train
    case bus
    case waste
    case island(category: String)
}

struct HomeView: View {
    @Binding var direction: TrainDirection
    /// Gewählte Bushaltestelle — liegt in den UserDefaults, `BusView` liest denselben Schlüssel.
    @AppStorage("bus.stop") private var busStopID: String = BusStop.zob.id
    @Binding var path: [HomeDestination]
    @State private var weather = WeatherViewModel()
    @State private var air = AirQualityViewModel()
    @State private var trains = TrainViewModel()
    @State private var buses = BusViewModel()
    @State private var waste = WasteViewModel()
    @AppStorage("waste.street") private var wasteStreetID: Int = 0
    @AppStorage("waste.section") private var wasteSectionID: Int = 0
    @AppStorage("waste.branchSection") private var wasteBranchID: Int = 0
    @AppStorage(HomeLayout.orderKey) private var homeOrder = HomeLayout.defaultOrder
    @AppStorage(HomeLayout.hiddenKey) private var homeHidden = HomeLayout.defaultHidden
    @AppStorage(HomeLayout.tilesKey) private var homeTiles = ""

    @ScaledMetric(relativeTo: .caption) private var gastroRowHeight = 172.0


    var body: some View {
        TabScreen(title: "stede", showsDateNavigator: false) {
            await loadWeather(force: true)
        } content: {
                ScrollView {
                    VStack(alignment: .leading, spacing: StedeTheme.cardSpacing) {
                    NavigationLink(value: HomeDestination.weather) {
                        HomeHeader(
                            hour: currentHour,
                            detail: weatherDetail,
                            isLoading: currentHour == nil && !weatherFailed
                        )
                    }
                    .buttonStyle(StedeCardButtonStyle())
                    .foregroundStyle(.primary)

                    if !failedSections.isEmpty {
                        HomeLoadIssue(sections: failedSections) {
                            await loadWeather(force: true)
                        }
                    }

                    ForEach(sections) { section in
                        let tiles = HomeLayout.tiles(in: section, order: homeTiles).filter { !hiddenTiles.contains($0) }
                        if !tiles.isEmpty {
                            StedeSectionHeader(title: section.title, symbol: section.symbol)
                            sectionContent(section, tiles: tiles)
                        }
                    }

                    if hiddenTiles.count == HomeTileID.allCases.count {
                        InfoCard {
                            Text("Alle Kacheln sind ausgeblendet. Unter Einstellungen → Startseite kannst du sie wieder einblenden.")
                                .foregroundStyle(.secondary)
                        }
                    }

                    }
                    .padding()
                }
        }
        .task {
            await loadWeather(force: false)
        }
        .task(id: busStopID) {
            await buses.load(stop: busStop, day: IslandTime.startOfDay(Date()))
        }
        .task(id: wasteSelection?.cacheKey ?? "") {
            await waste.load(selection: wasteSelection)
        }
    }

    private var sections: [HomeSection] { HomeLayout.order(homeOrder) }
    private var hiddenTiles: Set<HomeTileID> { HomeLayout.hidden(homeHidden) }

    @ViewBuilder
    private func sectionContent(_ section: HomeSection, tiles: [HomeTileID]) -> some View {
        switch section {
        case .transit:
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: StedeTheme.cardSpacing), count: tiles.count),
                      spacing: StedeTheme.cardSpacing) {
                ForEach(tiles) { tile in
                    NavigationLink(value: tile == .train ? HomeDestination.train : HomeDestination.bus) {
                        tile == .train ? trainTile : busTile
                    }
                    .buttonStyle(StedeCardButtonStyle())
                    .foregroundStyle(.primary)
                    .frame(maxHeight: .infinity)
                }
            }
        case .home:
            NavigationLink(value: HomeDestination.waste) {
                wasteTile
            }
            .buttonStyle(StedeCardButtonStyle())
            .foregroundStyle(.primary)
        case .city:
            // Die ersten beiden Kacheln groß nebeneinander, die übrigen klein darunter.
            let large = Array(tiles.prefix(2))
            let small = Array(tiles.dropFirst(2))
            if !large.isEmpty {
                HStack(spacing: StedeTheme.cardSpacing) {
                    ForEach(large) { tile in
                        if let category = tile.category { islandTile(category, prominent: true) }
                    }
                }
                .frame(height: gastroRowHeight)
            }
            if small.count > 4 {
                // Mehr als vier kleine Kacheln: Raster mit vier Spalten, gleich breit.
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: StedeTheme.cardSpacing), count: 4),
                          spacing: StedeTheme.cardSpacing) {
                    ForEach(small) { tile in
                        if let category = tile.category { islandTile(category) }
                    }
                }
            } else if !small.isEmpty {
                HStack(spacing: StedeTheme.cardSpacing) {
                    ForEach(small) { tile in
                        if let category = tile.category { islandTile(category) }
                    }
                }
            }
        }
    }

    /// Kachel je Kategorie der Rubrik „Stadt".
    private func islandTile(_ category: String, prominent: Bool = false, fillsHeight: Bool = false) -> some View {
        let places = IslandCatalog.places(in: category)
        return NavigationLink(value: HomeDestination.island(category: category)) {
            HomeCompactTile(
                title: IslandCatalog.tileTitle(for: category),
                symbol: IslandCatalog.symbol(for: category),
                tint: IslandCatalog.color(for: category),
                prominent: prominent,
                fillsHeight: fillsHeight
            )
        }
        .buttonStyle(StedeCardButtonStyle())
        .foregroundStyle(.primary)
        .accessibilityLabel("\(category), \(IslandCatalog.countLabel(for: category, count: places.count))")
    }

    private var weatherDetail: String {
        var parts: [String] = []
        if let condition = currentHour?.conditionLabel { parts.append(condition) }
        if let max = weather.summary?.maxTemperature { parts.append("Max \(temperature(max))") }
        return parts.joined(separator: " · ")
    }

    private var trainTile: HomeTile {
        let toOldenburg = nextDeparture(trains.departures(toward: .oldenburg))
        let toLeer = nextDeparture(trains.departures(toward: .leer))
        // Fährt heute gar nichts mehr, wäre eine Zeile mit Strich irreführend.
        if !trainsAreLoading, toOldenburg == nil, toLeer == nil {
            return HomeTile(
                title: "Bahn",
                symbol: "tram.fill",
                tint: StedeTheme.harborRed,
                headline: "Feierabend",
                detail: "Heute keine Abfahrt mehr"
            )
        }
        return HomeTile(
            title: "Bahn",
            symbol: "tram.fill",
            tint: StedeTheme.harborRed,
            headline: departure(toOldenburg, direction: .oldenburg),
            detail: departure(toLeer, direction: .leer),
            isLoading: trainsAreLoading
        )
    }

    private var busStop: BusStop { BusStop.stop(id: busStopID) }

    private var wasteStreet: WasteStreet? { WasteSettings.street(id: wasteStreetID) }
    private var wasteSelection: WasteSelection? {
        WasteSettings.selection(streetID: wasteStreetID, sectionID: wasteSectionID, branchSectionID: wasteBranchID)
    }

    /// Nächster Abfuhrtermin der gemerkten Straße; ohne Straße lädt die Kachel zur Wahl ein.
    private var wasteTile: HomeTile {
        guard let street = wasteStreet, wasteSelection != nil else {
            return HomeTile(
                title: "Abfuhr",
                symbol: "trash.fill",
                tint: StedeTheme.duneGreen,
                headline: "Straße wählen",
                detail: wasteStreet == nil ? "Abfuhrkalender für deine Straße" : "Abschnitt von \(wasteStreet?.name ?? "") wählen",
                compact: true
            )
        }
        let next = waste.collections.first
        let isLoading: Bool
        switch waste.state {
        case .idle, .loading: isLoading = next == nil
        default: isLoading = false
        }
        let format = Date.FormatStyle(locale: IslandTime.germanLocale, timeZone: IslandTime.timeZone)
            .weekday(.abbreviated).day().month(.abbreviated)
        return HomeTile(
            title: "Abfuhr",
            symbol: next?.kind.symbol ?? "trash.fill",
            tint: next?.kind.tint ?? StedeTheme.duneGreen,
            headline: next.map { "\($0.date.formatted(format)) · \($0.label)" } ?? (isLoading ? "–" : "Keine Termine"),
            detail: street.name,
            isLoading: isLoading,
            compact: true
        )
    }

    private var busTile: HomeTile {
        let next = buses.departures
            .filter { !$0.isCancelled && $0.departure > Date() }
            .min { $0.departure < $1.departure }
        if !busesAreLoading, next == nil {
            return HomeTile(
                title: "Bus",
                symbol: "bus.fill",
                tint: StedeTheme.seaTeal,
                headline: "Feierabend",
                detail: "Heute kein Bus mehr ab \(busStop.shortName)"
            )
        }
        var headline = "–"
        if let next {
            let delay = (next.delayMinutes ?? 0) > 0 ? " +\(next.delayMinutes ?? 0)" : ""
            headline = "\(next.scheduled.formatted(timeStyle))\(delay) · \(next.line)"
        }
        return HomeTile(
            title: "Bus",
            symbol: "bus.fill",
            tint: StedeTheme.seaTeal,
            headline: headline,
            detail: next.map { "\($0.destination) ab \(busStop.shortName)" } ?? busStop.shortName,
            isLoading: busesAreLoading
        )
    }

    private var busesAreLoading: Bool {
        switch buses.state {
        case .idle, .loading: true
        default: false
        }
    }

    /// Planzeit plus Verspätung („22:06 +8"), nicht die errechnete Ist-Zeit —
    /// so erkennt man auf einen Blick, ob der Zug pünktlich ist.
    private func departure(_ train: TrainDeparture?, direction: TrainDirection) -> String {
        guard let train else { return "kein Zug mehr · \(direction.shortTitle)" }
        let delay = train.delayMinutes > 0 ? " +\(train.delayMinutes)" : ""
        return "\(train.scheduled.formatted(timeStyle))\(delay) · \(direction.shortTitle)"
    }

    private func temperature(_ value: Double?) -> String {
        guard let value else { return "–" }
        return "\(value.formatted(.number.precision(.fractionLength(0))))°"
    }

    private var timeStyle: Date.FormatStyle {
        Date.FormatStyle(
            date: .omitted,
            time: .shortened,
            locale: IslandTime.germanLocale,
            timeZone: IslandTime.timeZone
        )
    }

    /// Bereiche, deren Ladevorgang fehlgeschlagen ist und für die auch nichts
    /// im Cache lag — nur dann steht der Nutzer wirklich ohne Daten da.
    private var failedSections: [String] {
        var names: [String] = []
        if case .failed = weather.state { names.append("Wetter") }
        if case .failed = trains.state { names.append("Bahn") }
        if case .failed = buses.state { names.append("Bus") }
        if case .failed = waste.state { names.append("Abfuhr") }
        if case .failed = air.state { names.append("Luftqualität") }
        return names
    }

    private var currentHour: WeatherHour? {
        guard let hours = weather.summary?.hours, !hours.isEmpty else { return nil }
        let now = Date()
        return hours.last { $0.timestamp <= now } ?? hours.first
    }

    private var weatherFailed: Bool {
        if case .failed = weather.state { return true }
        return false
    }

    private var trainsAreLoading: Bool {
        switch trains.state {
        case .idle, .loading: true
        default: false
        }
    }

    /// Nächste nicht ausgefallene Abfahrt der Richtung nach „jetzt“.
    private func nextDeparture(_ departures: [TrainDeparture]) -> TrainDeparture? {
        departures
            .filter { !$0.isCancelled && $0.departure > Date() }
            .min { $0.departure < $1.departure }
    }

    private func loadWeather(force: Bool) async {
        let today = IslandTime.startOfDay(Date())
        async let weatherLoad: Void = weather.load(day: today, force: force)
        async let airLoad: Void = air.load(day: today, force: force)
        async let trainLoad: Void = trains.load(day: today, force: force)
        async let busLoad: Void = buses.load(stop: busStop, day: today, force: force)
        _ = await (weatherLoad, airLoad, trainLoad, busLoad)
    }
}

/// Der Gruß steckt in einer Karte, damit die erste Karte auf Start auf
/// derselben Höhe beginnt wie auf den Tagesansichten. Die Tageszeit gibt
/// Symbol und Farbe vor — sonst stünde der Gruß allein auf weißer Fläche.
/// Gruß und aktuelles Wetter in einem: die Karte führt zur Wetteransicht.
private struct HomeHeader: View {
    let hour: WeatherHour?
    let detail: String
    var isLoading = false
    /// So hoch wie die kleinen Kacheln unter Gastro und Stadt.
    @ScaledMetric(relativeTo: .caption) private var tileHeight = HomeTileMetrics.compactHeight

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Moin!")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(daypart.color)
                Text(daypart.subtitle)
                    .font(.headline.weight(.regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(temperature)
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .redacted(reason: isLoading ? .placeholder : [])
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                    .redacted(reason: isLoading ? .placeholder : [])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: tileHeight, alignment: .topLeading)
        .padding(12)
        // Das Wettersymbol blass und angeschnitten wie bei den Kacheln.
        .background(alignment: .bottomLeading) {
            Image(systemName: hour?.symbolName ?? daypart.symbol)
                .font(.system(size: 96))
                .foregroundStyle(daypart.color.opacity(0.18))
                .offset(x: -18, y: 26)
                .accessibilityHidden(true)
        }
        .stedeCard(fill: AnyShapeStyle(daypart.gradient))
        .overlay(StedeTheme.cardShape.strokeBorder(daypart.color.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Wetter, \(temperature.replacingOccurrences(of: "°", with: " Grad")), \(detail)")
    }

    private var temperature: String {
        guard let value = hour?.temperature else { return "–" }
        return "\(value.formatted(.number.precision(.fractionLength(0))))°"
    }

    private var daypart: Daypart {
        Daypart(hour: IslandTime.calendar.component(.hour, from: Date()))
    }
}

/// Tagesabschnitte in der Stadt — Gruß, Symbol und Farben wandern mit der Uhr.
/// Die Flächen bleiben lasiert, damit die Karte neben dem kräftigen Wetter-Hero
/// darunter nicht um Aufmerksamkeit kämpft und die Schrift dunkel bleiben kann.
private struct Daypart {
    let subtitle: String
    let symbol: String
    let color: Color
    private let secondColor: Color

    init(hour: Int) {
        switch hour {
        case 5 ..< 10:
            subtitle = "Guten Morgen in Westerstede"
            symbol = "sunrise.fill"
            color = StedeTheme.sunAmber
            secondColor = StedeTheme.harborRed
        case 10 ..< 17:
            subtitle = "Schönen Tag in Westerstede"
            symbol = "sun.max.fill"
            color = StedeTheme.sunAmber
            secondColor = StedeTheme.duneGreen
        case 17 ..< 22:
            subtitle = "Schönen Abend in Westerstede"
            symbol = "sunset.fill"
            color = StedeTheme.harborRed
            secondColor = StedeTheme.deep
        default:
            subtitle = "Gute Nacht in Westerstede"
            symbol = "moon.stars.fill"
            color = StedeTheme.seaTeal
            secondColor = StedeTheme.deep
        }
    }

    var gradient: LinearGradient {
        LinearGradient(
            colors: [color.opacity(0.28), secondColor.opacity(0.14)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// Kachel auf dem Start: getönte Fläche, Titel und Symbol oben, darunter
/// die Kernaussage, eine Zusatzzeile und die Aktionszeile am Fuß.
/// Gemeinsame Kachelhöhe — Gruß und Bereichskacheln bleiben gleich hoch.
enum HomeTileMetrics {
    static let height = 138.0
    /// Kleine Kacheln (Gastro, Stadt) und die Moin-Karte.
    static let compactHeight = 92.0
}

struct HomeTile: View {
    let title: String
    let symbol: String
    let tint: Color
    let headline: String
    var detail: String?
    var isLoading = false
    /// Flach: Höhe der kleinen Kacheln, etwa für Hoch- und Niedrigwasser.
    var compact = false
    /// Feste Höhe: alle Kacheln bleiben gleich groß, auch in verschiedenen Rastern.
    @ScaledMetric(relativeTo: .headline) private var tileHeight = HomeTileMetrics.height
    @ScaledMetric(relativeTo: .caption) private var compactHeight = HomeTileMetrics.compactHeight

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.headline)
                .foregroundStyle(tint)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(headline)
                .font(.headline)
                .fontDesign(.rounded)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .redacted(reason: isLoading ? .placeholder : [])

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .redacted(reason: isLoading ? .placeholder : [])
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: compact ? compactHeight : tileHeight)
        .padding(12)
        // Großes, blasses Symbol in der Ecke; `stedeCard` schneidet den
        // Überstand an der Kartenkante ab.
        .background(alignment: .bottomTrailing) {
            Image(systemName: symbol)
                .font(.system(size: 96))
                .foregroundStyle(tint.opacity(0.18))
                .offset(x: 22, y: 18)
                .accessibilityHidden(true)
        }
        .stedeCard(fill: AnyShapeStyle(tint.opacity(0.18)))
        // Kontur in der Bereichsfarbe: die getönte Fläche allein hebt sich
        // zu wenig vom sandfarbenen Hintergrund ab.
        .overlay(StedeTheme.cardShape.strokeBorder(tint.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Kachel für die Rubriken „Gastro" und „Stadt" im Stil der großen Kacheln:
/// Name oben links, großes blasses Symbol angeschnitten unten rechts.
private struct HomeCompactTile: View {
    let title: String
    let symbol: String
    let tint: Color
    /// Groß: Restaurant-Kachel über die halbe Zeile, mit größerem Namen und Symbol.
    var prominent = false
    /// Füllt die Höhe des Rasters, statt fest 92 pt zu sein.
    var fillsHeight = false
    @ScaledMetric(relativeTo: .caption) private var tileHeight = HomeTileMetrics.compactHeight

    var body: some View {
        Text(title)
            .font(prominent ? .headline : .caption.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(prominent ? 12 : 10)
            .frame(height: prominent || fillsHeight ? nil : tileHeight)
            .background(alignment: .bottomTrailing) {
                Image(systemName: symbol)
                    .font(.system(size: prominent ? 110 : 54))
                    .foregroundStyle(tint.opacity(0.22))
                    .offset(x: prominent ? 22 : 12, y: prominent ? 22 : 12)
                    .accessibilityHidden(true)
            }
            .stedeCard(fill: AnyShapeStyle(tint.opacity(0.18)))
            .overlay(StedeTheme.cardShape.strokeBorder(tint.opacity(0.35), lineWidth: 1))
    }
}

/// Sammelmeldung für die Bereiche, die auf dem Start nicht laden konnten.
private struct HomeLoadIssue: View {
    let sections: [String]
    let retry: () async -> Void
    @State private var isRetrying = false

    var body: some View {
        InfoCard {
            VStack(alignment: .leading, spacing: 10) {
                Label {
                    Text("\(sections.formatted(.list(type: .and))) konnte nicht geladen werden")
                        .font(.subheadline.weight(.semibold))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(StedeTheme.sunAmber)
                }
                Button {
                    Task {
                        isRetrying = true
                        await retry()
                        isRetrying = false
                    }
                } label: {
                    Label("Erneut versuchen", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .disabled(isRetrying)
            }
        }
    }
}

private struct HomeWeatherPlaceholder: View {
    var hasFailed = false

    var body: some View {
        InfoCard(fill: AnyShapeStyle(WeatherAtmosphere.placeholder)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    Text("Jetzt")
                        .font(.title3.weight(.semibold))
                        .fontDesign(.rounded)
                    Text("Jetzt")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.22), in: Capsule())
                    Image(systemName: "cloud.sun.fill")
                        .symbolRenderingMode(.multicolor)
                    Spacer(minLength: 8)
                    Text("–°")
                        .font(.title.weight(.semibold))
                        .fontDesign(.rounded)
                        .monospacedDigit()
                        .redacted(reason: hasFailed ? [] : .placeholder)
                }
                Text("Wetter")
                    .foregroundStyle(.white.opacity(0.82))
                HStack(spacing: 16) {
                    placeholderMetric("Wind")
                    placeholderMetric("Böen")
                    placeholderMetric("Regen")
                    placeholderMetric("Wolken")
                }
                .font(.caption)
            }
        }
        .weatherHeroChrome(true)
    }

    @ViewBuilder
    private func placeholderMetric(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.82))
            Text("–")
                .monospacedDigit()
                .redacted(reason: hasFailed ? [] : .placeholder)
        }
    }
}
