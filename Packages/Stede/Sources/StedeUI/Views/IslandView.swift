import SwiftUI
import StedeCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Ein Ort der Rubrik „Stadt": Gastronomie, Geschäfte, Fahrradläden und mehr.
enum IslandPlace: Identifiable {
    case gastro(GastroPlace)
    case bike(BikeRentalProvider)

    var id: String {
        switch self {
        case .gastro(let place): place.id
        case .bike(let provider): provider.id
        }
    }

    var category: String {
        switch self {
        case .gastro(let place): place.category
        case .bike: IslandCatalog.bikeCategory
        }
    }

    var name: String {
        switch self {
        case .gastro(let place): place.name
        case .bike(let provider): provider.name
        }
    }

    /// Liefert nach Hause — zählt zusätzlich zur eigenen Art für die Pille „Lieferdienst“.
    var delivers: Bool {
        if case .gastro(let place) = self { return place.delivers }
        return false
    }
}

/// Kategorien der Rubrik „Stadt" mit Symbol, Farbe und Einträgen —
/// gemeinsam genutzt von den Kacheln auf Start und der Kategorie-Ansicht.
enum IslandCatalog {
    static let bikeCategory = "Fahrrad"

    static let sightsCategory = "Sehenswürdigkeiten"
    /// Große Kachel unter „Stadt": Sehenswürdigkeiten und Ausflüge plus Bad, Sport,
    /// Spiel & Familie und Kultur in einer Ansicht.
    static let discoverCategory = "Entdecken"
    static let healthCategory = "Gesundheit"
    static let leisureCategory = "Freizeit & Sport"
    static let tripsCategory = "Ausflüge"
    /// Spielplätze plus alles zum Spielen aus „Freizeit & Sport“ (Arten in `playKinds`) — auch Kostenpflichtiges.
    static let playgroundsCategory = "Spiel & Spaß"
    /// Arten aus „Freizeit & Sport“, die unter „Spiel & Spaß“ statt unter „Entdecken“ stehen.
    static let playKinds: Set<String> = ["Spiel & Familie", "Kostenpflichtig", "Spielplatz", "Skaterplatz"]
    /// Vergünstigungen der Ehrenamtskarte in Westerstede (optionale Kachel auf Start).
    static let volunteerCategory = "Ehrenamtskarte"


    /// Versorgung in der Stadt — nicht unter „Gastro", sondern unter „Stadt".
    /// Fahrradläden stehen mit unter „Einkaufen".
    static let islandCategories = ["Einkaufen"]
    static let shoppingCategory = "Einkaufen"
    /// Bäckereien stehen in der Ansicht „Einkaufen", behalten aber Farbe und Pille.
    static let bakeryCategory = "Bäckerei"
    /// Der Drogeriemarkt steht ebenfalls unter „Einkaufen", in eigener Farbe.
    static let drugstoreCategory = "Drogerie"

    /// Große Kachel „Gastro": alle Arten zum Essen und Trinken in einer
    /// Ansicht (Restaurant, Café, Eiscafé, Imbiss, Bar), filterbar per Pille.
    static let gastroCategory = "Gastro"

    static var gastroKinds: [String] {
        GastroStore.directory.categories.filter {
            !islandCategories.contains($0) && $0 != bakeryCategory && $0 != drugstoreCategory
        }
    }

    static func places(in category: String) -> [IslandPlace] {
        // Nach einem Abgleich neu zeichnen (die Verzeichnisse selbst lesen dann frisch ein).
        _ = ContentRevision.shared.value
        if category == bikeCategory {
            return BikeRentalStore.directory.providers.map(IslandPlace.bike)
        }
        if category == sightsCategory {
            return GastroStore.sights.places.map(IslandPlace.gastro)
        }
        if category == gastroCategory {
            let directory = GastroStore.directory
            return gastroKinds.flatMap { directory.places(in: $0) }.map(IslandPlace.gastro)
        }
        if category == discoverCategory {
            // Sehenswürdigkeiten, Freizeit & Sport und Ausflüge in einer Ansicht.
            // Orte, die auch als Ausflug geführt sind (Rhododendronpark Hobbie), nur einmal — mit dem Ausflugstext.
            let trips = GastroStore.trips.places
            let tripNames = Set(trips.map { $0.name.lowercased() })
            // Spiel & Familie und Kostenpflichtiges stehen unter „Spiel & Spaß“.
            let leisure = GastroStore.leisure.places.filter { !playKinds.contains($0.category) }
            let local = (GastroStore.sights.places + leisure).filter { !tripNames.contains($0.name.lowercased()) }
            return (local + trips).map(IslandPlace.gastro)
        }
        if category == shoppingCategory {
            let directory = GastroStore.directory
            return (directory.places(in: shoppingCategory)
                + directory.places(in: drugstoreCategory)
                + directory.places(in: bakeryCategory))
                .map(IslandPlace.gastro)
                + (AppBrand.current.bikesInShopping ? BikeRentalStore.directory.providers.map(IslandPlace.bike) : [])
        }
        if category == healthCategory {
            return GastroStore.health.places.map(IslandPlace.gastro)
        }
        if category == leisureCategory {
            return GastroStore.leisure.places.map(IslandPlace.gastro)
        }
        if category == tripsCategory {
            return GastroStore.trips.places.map(IslandPlace.gastro)
        }
        if category == playgroundsCategory {
            // Spielplätze plus Spiel & Familie und Kostenpflichtiges aus „Freizeit & Sport“, nach Namen einmal.
            let playgrounds = GastroStore.playgrounds.places
            let names = Set(playgrounds.map { $0.name.lowercased() })
            let extra = GastroStore.leisure.places.filter { playKinds.contains($0.category) && !names.contains($0.name.lowercased()) }
            return (playgrounds + extra).map(IslandPlace.gastro)
        }
        if category == volunteerCategory {
            return GastroStore.volunteer.places.map(IslandPlace.gastro)
        }
        return GastroStore.directory.places(in: category).map(IslandPlace.gastro)
    }

    /// „22 Restaurants", „8 Verleiher" — für die Kachel auf Start.
    static func countLabel(for category: String, count: Int) -> String {
        let plural: [String: String] = [
            "Restaurant": "Restaurants", "Café": "Cafés", "Bäckerei": "Bäckereien",
            "Eiscafé": "Eiscafés", "Imbiss": "Imbisse", "Bar": "Bars", "Einkaufen": "Geschäfte",
            sightsCategory: "Sehenswürdigkeiten", healthCategory: "Einträge", leisureCategory: "Angebote", discoverCategory: "Orte", gastroCategory: "Lokale", tripsCategory: "Ausflüge", playgroundsCategory: "Angebote", volunteerCategory: "Vergünstigungen",
            bikeCategory: "Fahrradläden",
        ]
        let singular = [bikeCategory: "Fahrradladen", sightsCategory: "Sehenswürdigkeit", "Einkaufen": "Geschäft", playgroundsCategory: "Angebot"]
        let noun = count == 1 ? (singular[category] ?? category) : (plural[category] ?? "Orte")
        return "\(count) \(noun)"
    }

    /// Kurzer Name für die schmalen Kacheln auf Start; die Ansicht selbst
    /// behält den vollen Namen.
    static func tileTitle(for category: String) -> String {
        category == bikeCategory ? "Fahrräder" : category
    }

    static func source(for category: String) -> String {
        switch category {
        case bikeCategory: BikeRentalStore.directory.source
        case sightsCategory: GastroStore.sights.source
        case discoverCategory: "\(GastroStore.sights.source) · Freizeit: \(GastroStore.leisure.source) · Ausflüge: \(GastroStore.trips.source)"
        case healthCategory: GastroStore.health.source
        case leisureCategory: GastroStore.leisure.source
        case tripsCategory: GastroStore.trips.source
        case playgroundsCategory: "\(GastroStore.playgrounds.source) · Freizeit: \(GastroStore.leisure.source)"
        case volunteerCategory: GastroStore.volunteer.source
        case shoppingCategory: "\(GastroStore.directory.source) · Fahrrad: \(BikeRentalStore.directory.source)"
        default: GastroStore.directory.source
        }
    }

    static func symbol(for category: String) -> String {
        switch category {
        case "Café": "cup.and.saucer.fill"
        case "Bäckerei": "basket.fill"
        case "Allgemeinmedizin": "stethoscope"
        case "Zahnarzt": "mouth.fill"
        case "Apotheke": "pills.fill"
        case "Facharzt": "heart.text.clipboard.fill"
        case "Klinik": "building.2.fill"
        case "Tierarzt": "pawprint.fill"
        case "Therapie & Pflege": "hand.raised.fill"
        case "Eiscafé": "snowflake"
        case "Imbiss": "takeoutbag.and.cup.and.straw.fill"
        case GastroPlace.deliveryFeature: "scooter"
        case "Bar": "wineglass.fill"
        case "Einkaufen": "cart.fill"
        case "Drogerie": "bubbles.and.sparkles.fill"
        case bikeCategory: "bicycle"
        case sightsCategory, discoverCategory: "binoculars.fill"
        case healthCategory: "cross.case.fill"
        case leisureCategory: "figure.run"
        case "Bad": "figure.pool.swim"
        case "Sport": "figure.run"
        case "Spiel & Familie": "figure.and.child.holdinghands"
        case "Kultur": "theatermasks.fill"
        case tripsCategory, "Park": "leaf.fill"
        case playgroundsCategory, "Spielplatz": "figure.play"
        case "Skaterplatz": "skateboard.fill"
        case "Kostenpflichtig": "ticket.fill"
        case "Draisine": "figure.outdoor.cycle"
        case "Schifffahrt": "ferry.fill"
        case "Radtour": "bicycle"
        case volunteerCategory: "heart.fill"
        case "Verwaltung": "building.columns.fill"
        case "Bildung": "book.fill"
        case "Mobilität": "bus.fill"
        case "Handel": "bag.fill"
        case "Übernachtung": "tent.fill"
        case "Versicherung": "shield.fill"
        default: "fork.knife"
        }
    }

    /// Farben so verteilt, dass innerhalb jeder Rubrik auf Start keine zwei
    /// Kacheln gleich aussehen und die großen Kacheln (Gezeiten türkis,
    /// Restaurant lila, Sehenswürdigkeiten braun) sich unterscheiden — Gastro: Restaurant, Café, Eiscafé, Imbiss, Bar;
    /// Stadt: Sehenswürdigkeiten, Einkaufen, Bäckerei, Fahrrad, Gesundheit.
    static func color(for category: String) -> Color {
        switch category {
        case "Café": StedeTheme.sunAmber
        case "Eiscafé": StedeTheme.harborRed
        case "Imbiss": StedeTheme.duneGreen
        case GastroPlace.deliveryFeature: StedeTheme.seaTeal
        case "Bar": StedeTheme.ink
        case "Einkaufen": StedeTheme.ink
        case "Drogerie": StedeTheme.harborRed
        case "Bäckerei": StedeTheme.sunAmber
        case bikeCategory: StedeTheme.duneGreen
        case sightsCategory, discoverCategory: StedeTheme.mudflat
        case healthCategory, "Allgemeinmedizin": StedeTheme.seaTeal
        case "Zahnarzt": StedeTheme.ink
        case "Apotheke": StedeTheme.harborRed
        case "Facharzt": StedeTheme.heather
        case "Klinik": StedeTheme.mudflat
        case "Tierarzt": StedeTheme.duneGreen
        case "Therapie & Pflege": StedeTheme.sunAmber
        // Seiten mit mehreren Arten: jede Art in eigener Farbe.
        case leisureCategory, "Kultur": StedeTheme.heather
        case "Bad": StedeTheme.seaTeal
        case "Sport": StedeTheme.duneGreen
        case "Spiel & Familie": StedeTheme.sunAmber
        case tripsCategory, "Park": StedeTheme.harborRed
        case playgroundsCategory, "Spielplatz": StedeTheme.sunAmber
        case "Skaterplatz": StedeTheme.heather
        case "Kostenpflichtig": StedeTheme.seaTeal
        case "Draisine": StedeTheme.sunAmber
        case "Schifffahrt": StedeTheme.seaTeal
        case "Radtour": StedeTheme.duneGreen
        case volunteerCategory: StedeTheme.duneGreen
        case "Verwaltung": StedeTheme.ink
        case "Bildung": StedeTheme.heather
        case "Mobilität": StedeTheme.seaTeal
        case "Handel": StedeTheme.sunAmber
        case "Übernachtung": StedeTheme.harborRed
        case "Versicherung": StedeTheme.mudflat
        default: StedeTheme.heather
        }
    }

}

/// Eine Kategorie der Rubrik „Stadt": Karte oben, darunter die Einträge.
/// Die Favoriten-Pill schaltet zwischen allen Einträgen und den gemerkten um.
struct IslandView: View {
    let category: String
    /// Info „Wer darf das nutzen?“ über der Ehrenamt-Liste — einmal weggeklickt, bleibt sie weg.
    @AppStorage("volunteer.infoHidden") private var volunteerInfoHidden = false
    /// Favoriten-Filter und ausgeblendete Arten (etwa „Drogerie" unter
    /// „Einkaufen") — je Kategorie gemerkt, beim nächsten Öffnen wie verlassen.
    @State private var favoritesOnly: Bool
    /// Leer = alle Arten sichtbar; sonst nur die gewählten.
    @State private var selectedKinds: Set<String>
    @State private var favoritesWidth: CGFloat = 0

    init(category: String) {
        self.category = category
        let defaults = UserDefaults.standard
        _favoritesOnly = State(initialValue: defaults.bool(forKey: Self.favoritesKey(category)))
        _selectedKinds = State(initialValue: Set(defaults.stringArray(forKey: Self.kindsKey(category)) ?? []))
    }

    private static func favoritesKey(_ category: String) -> String { "island.favoritesOnly.\(category)" }
    private static func kindsKey(_ category: String) -> String { "island.selectedKinds.\(category)" }
    @Environment(PlaceFavorites.self) private var favorites
    @State private var page: BrowserPage?
    @State private var selectedID: String?
    @AppStorage("island.showsMap") private var showsMap = true

    var body: some View {
        // Ohne refresh-Closure: alle Daten liegen im Bundle, es gibt nichts
        // nachzuladen — Karte und Favoriten-Pill bleiben beim Scrollen stehen.
        TabScreen(title: category, showsDateNavigator: false) {
            ScrollViewReader { proxy in
                // Die erste Zeile beginnt 16 pt unter der Leiste wie die erste Karte sonst.
                VStack(alignment: .leading, spacing: 0) {
                    if showsMap {
                        StedePlaceMap(pins: pins, selectedID: selectedID) { id in
                            selectedID = id
                            withAnimation {
                                proxy.scrollTo(id, anchor: .top)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, StedeTheme.cardSpacing)
                        .transition(.opacity)
                    }

                    filterRow
                        .padding(.bottom, StedeTheme.cardSpacing)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: StedeTheme.cardSpacing) {
                            if places.isEmpty {
                                InfoCard {
                                    Text(favoritesOnly ? "Noch keine Favoriten — tippe auf den Stern einer Karte." : "Keine Einträge.")
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if category == IslandCatalog.volunteerCategory, !volunteerInfoHidden {
                                VolunteerInfoCard { withAnimation { volunteerInfoHidden = true } }
                            }

                            ForEach(places) { place in
                                card(for: place)
                                    .id(place.id)
                            }

                            if category == IslandCatalog.tripsCategory || category == IslandCatalog.discoverCategory {
                                Label(Tenants.current.notes?["trips"] ?? "Stadtführungen, Konzerte und Feste stehen im Kalender – hier nur Ziele rund um \(Tenants.current.municipality).", systemImage: "calendar")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 4)
                            }

                            if category == IslandCatalog.volunteerCategory {
                                Label("Gilt nur mit der Ehrenamtskarte Niedersachsen/Bremen – beim Anbieter vorzeigen. Beantragung und alle Angebote im Land: freiwilligenserver.de/ehrenamtskarte.", systemImage: "heart.text.square")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 4)
                                if volunteerInfoHidden {
                                    Button("Wer darf das nutzen?") { withAnimation { volunteerInfoHidden = false } }
                                        .font(.caption.weight(.semibold))
                                        .tint(StedeTheme.ink)
                                        .padding(.horizontal, 4)
                                }
                            }

                            if category == IslandCatalog.healthCategory {
                                Label(Tenants.current.notes?["health"] ?? "Notruf 112 · Ärztlicher Bereitschaftsdienst 116117.", systemImage: "cross.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 4)
                            }

                            if category == IslandCatalog.playgroundsCategory, Tenants.usesBundle {
                                Label("Bewertung und Sauberkeit laut Kinderrat Westerstede, Stand der Stadtseite.", systemImage: "info.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 4)
                            }

                            if hasOpeningHours {
                                Label("Öffnungszeiten ohne Gewähr, saisonal abweichend – im Zweifel vorher anrufen.", systemImage: "info.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 4)
                            }

                            SourceFooter(text: IslandCatalog.source(for: category))
                        }
                        .padding([.horizontal, .bottom])
                    }
                    .id(favoritesOnly)
                }
                .padding(.top)
            }
            .sheet(item: $page) { page in
                InAppBrowser(url: page.url)
            }
        }
        .mapToggle(isOn: $showsMap)
    }

    /// Die Favoriten-Pille steht fest links; die Pillen der Arten (nur bei
    /// mehreren Arten) scrollen unter ihr hindurch — wie früher im Gastro-Filter.
    private var filterRow: some View {
        let inset = StedeTheme.SelectionRow.horizontalInset
        let spacing = StedeTheme.SelectionRow.spacing
        return ZStack(alignment: .leading) {
            if kinds.count > 1 {
                ScrollView(.horizontal) {
                    HStack(spacing: spacing) {
                        ForEach(kinds, id: \.self) { kind in
                            kindToggle(kind)
                        }
                    }
                    .padding(.leading, inset + favoritesWidth + spacing)
                    .padding(.trailing, inset)
                }
                .scrollIndicators(.hidden)
            }

            Button {
                withAnimation(.snappy) { favoritesOnly.toggle() }
            } label: {
                // Nur der Stern — der Platz gehört den Arten-Pillen.
                Image(systemName: favoritesOnly ? "star.fill" : "star")
                    .stedeSelectionChip(isSelected: favoritesOnly)
            }
            .buttonStyle(StedeCardButtonStyle())
            .accessibilityLabel("Favoriten, \(favoriteCount)")
            .accessibilityAddTraits(favoritesOnly ? .isSelected : [])
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { favoritesWidth = $0 }
            .padding(.leading, inset)
            .padding(.trailing, spacing)
            .background(alignment: .leading) {
                // Deckender Sand unter der Pille, dann ein kurzer Verlauf. Etwas
                // höher als die Pille, damit größere Pillen (Symbole) nicht oben
                // und unten hervorschauen.
                HStack(spacing: 0) {
                    StedeTheme.sand
                    LinearGradient(colors: [StedeTheme.sand, StedeTheme.sand.opacity(0)],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: spacing)
                }
                .padding(.vertical, -8)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: favoritesOnly) {
            UserDefaults.standard.set(favoritesOnly, forKey: Self.favoritesKey(category))
        }
        .onChange(of: selectedKinds) {
            UserDefaults.standard.set(Array(selectedKinds), forKey: Self.kindsKey(category))
        }
    }

    @ViewBuilder
    private func card(for place: IslandPlace) -> some View {
        switch place {
        case .gastro(let gastroPlace):
            GastroCard(
                place: gastroPlace,
                isSelected: gastroPlace.id == selectedID,
                showOnMap: { showOnMap(gastroPlace.id) },
                isFavorite: favorites.contains(gastroPlace.id),
                toggleFavorite: { favorites.toggle(gastroPlace.id) },
                openWebsite: { page = BrowserPage(url: $0) }
            )
        case .bike(let provider):
            BikeRentalCard(
                provider: provider,
                isSelected: provider.id == selectedID,
                showOnMap: { showOnMap(provider.id) },
                isFavorite: favorites.contains(provider.id),
                toggleFavorite: { favorites.toggle(provider.id) },
                openWebsite: { page = BrowserPage(url: $0) }
            )
        }
    }

    private var hasOpeningHours: Bool {
        allPlaces.contains { place in
            if case .gastro(let gastroPlace) = place { return gastroPlace.hours != nil }
            return false
        }
    }

    private var allPlaces: [IslandPlace] {
        IslandCatalog.places(in: category)
    }

    private var favoriteCount: Int {
        allPlaces.filter { favorites.contains($0.id) }.count
    }

    private var places: [IslandPlace] {
        let selected = activeKinds
        return allPlaces.filter { place in
            (!favoritesOnly || favorites.contains(place.id))
                && (selected.isEmpty || selected.contains(place.category)
                    || (place.delivers && selected.contains(GastroPlace.deliveryFeature)))
        }
    }

    /// Gewählte Arten, die es in dieser Ansicht noch gibt — eine gespeicherte Art, die verschwunden
    /// oder umgezogen ist (etwa „Spiel & Familie“ nach „Spiel & Spaß“), filtert sonst alles weg.
    private var activeKinds: Set<String> {
        selectedKinds.intersection(kinds)
    }

    /// Arten in der Reihenfolge ihres ersten Auftretens; „Lieferdienst“ zuletzt,
    /// wenn ein Ort liefert — die Pille zeigt alle, die liefern, gleich welcher Art.
    private var kinds: [String] {
        var seen = Set<String>()
        let kinds = allPlaces.map(\.category).filter { seen.insert($0).inserted }
        return allPlaces.contains(where: \.delivers) ? kinds + [GastroPlace.deliveryFeature] : kinds
    }

    /// Ohne Auswahl sind alle Arten aktiv. Ein Tipp filtert auf genau diese
    /// Art, ein Tipp auf eine andere springt um, ein zweiter Tipp auf dieselbe
    /// hebt den Filter wieder auf.
    private func kindToggle(_ kind: String) -> some View {
        let isActive = activeKinds.isEmpty || activeKinds.contains(kind)
        let color = IslandCatalog.color(for: kind)
        return Button {
            withAnimation(.snappy) {
                selectedKinds = selectedKinds.contains(kind) ? [] : [kind]
            }
        } label: {
            Label(kind, systemImage: IslandCatalog.symbol(for: kind))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isActive ? color.opacity(0.18) : StedeTheme.surface.opacity(0.6), in: Capsule())
                .overlay(Capsule().strokeBorder(color.opacity(isActive ? 0.35 : 0.15), lineWidth: 1))
                .foregroundStyle(isActive ? AnyShapeStyle(color) : AnyShapeStyle(.tertiary))
        }
        .buttonStyle(StedeCardButtonStyle())
        .accessibilityLabel(selectedKinds.contains(kind) ? "Filter \(kind) aufheben" : "Nur \(kind) zeigen")
        .accessibilityAddTraits(selectedKinds.contains(kind) ? .isSelected : [])
    }

    /// Karte einblenden, falls ausgeblendet, und den Ort hervorheben —
    /// ein zweiter Tipp auf dieselbe Karte hebt die Auswahl wieder auf.
    private func showOnMap(_ id: String) {
        withAnimation(.snappy) {
            if selectedID == id {
                selectedID = nil
            } else {
                showsMap = true
                selectedID = id
            }
        }
    }

    /// Jeder Pin in Symbol und Farbe seiner eigenen Art — so bleiben etwa
    /// Bäckereien unter „Einkaufen" gelb.
    private var pins: [StedeMapPin] {
        let symbol = IslandCatalog.symbol(for: category)
        let color = IslandCatalog.color(for: category)
        return places.flatMap { place -> [StedeMapPin] in
            switch place {
            case .gastro(let gastroPlace):
                guard let coordinate = gastroPlace.coordinate else { return [] }
                return [StedeMapPin(id: gastroPlace.id, placeID: gastroPlace.id, title: gastroPlace.name,
                                   coordinate: coordinate, symbol: gastroPlace.symbol, color: gastroPlace.color)]
            case .bike(let provider):
                return provider.stations.map { station in
                    StedeMapPin(id: "\(provider.id)-\(station.street)", placeID: provider.id, title: provider.name,
                               coordinate: station.coordinate, symbol: symbol, color: color)
                }
            }
        }
    }
}

private extension GastroPlace {
    var symbol: String { IslandCatalog.symbol(for: category) }
    var color: Color { IslandCatalog.color(for: category) }
}

private struct GastroCard: View {
    let place: GastroPlace
    /// Feste Größe: ein zweizeiliger Name soll das Symbol nicht größer machen.
    @ScaledMetric(relativeTo: .headline) private var chipSide = 52.0
    let isSelected: Bool
    let showOnMap: () -> Void
    let isFavorite: Bool
    let toggleFavorite: () -> Void
    let openWebsite: (URL) -> Void
    @ScaledMetric(relativeTo: .body) private var imageHeight = 170.0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let imageURL = place.imageURL {
                GastroImage(url: imageURL)
                    .frame(maxWidth: .infinity)
                    .frame(height: imageHeight)
                    .clipped()
                    // `clipped()` beschneidet nur die Darstellung: das
                    // formatfüllende Bild bliebe über der ganzen Karte
                    // treffbar und würde die Chips darunter blockieren.
                    .allowsHitTesting(false)
                    // Freie Lizenzen verlangen den Namen am Bild.
                    .overlay(alignment: .bottomTrailing) {
                        if let credit = place.imageCredit {
                            Text(credit)
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.45), in: Capsule())
                                .padding(6)
                        }
                    }
            }

            details
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .stedeCard(highlighted: isSelected)
        // Tippen zeigt den Ort auf der Karte; Stern, Telefon und Website
        // bleiben eigene Ziele, deshalb kein Button um die ganze Karte.
        .contentShape(StedeTheme.cardShape)
        .onTapGesture(perform: showOnMap)
        .accessibilityAction(named: "Auf Karte zeigen", showOnMap)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                StedeIconChip(symbol: place.symbol, color: place.color, side: chipSide)
                VStack(alignment: .leading, spacing: 4) {
                    Text(place.name)
                        .font(.headline)
                        .fontDesign(.rounded)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        StedeTagPill(text: place.category, color: place.color)
                        if place.delivers {
                            StedeTagPill(text: GastroPlace.deliveryFeature, color: IslandCatalog.color(for: GastroPlace.deliveryFeature))
                        }
                    }
                }
                Spacer(minLength: 8)
                FavoriteButton(isFavorite: isFavorite, toggle: toggleFavorite)
            }

            if let teaser = place.teaser {
                Text(teaser)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }

            // Adresse, Öffnungszeiten, Ruhetag und Saison als ein Block mit
            // gleichem Zeilenabstand.
            if place.street != nil || place.hours != nil || place.restDay != nil || place.seasonNote != nil {
                VStack(alignment: .leading, spacing: 4) {
                    if let street = place.street {
                        Label(street, systemImage: "mappin.and.ellipse")
                    }
                    if let hours = place.hours {
                        Label(hours, systemImage: "clock")
                    }
                    if let restDay = place.restDay {
                        Label("Ruhetag: \(restDay)", systemImage: "moon.zzz")
                    }
                    if let note = place.seasonNote {
                        Label(note, systemImage: "calendar")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            if place.callURL != nil || place.websiteURL != nil || place.extraURL != nil {
                HStack(spacing: 8) {
                    if let call = place.callURL, let phone = place.phone {
                        // Link statt Button: iOS wählt selbst und blendet den
                        // Chip dort aus, wo `tel:` nicht geht (z. B. Simulator).
                        Link(destination: call) {
                            StedeActionChip(title: phone, symbol: "phone.fill")
                        }
                        .buttonStyle(StedeCardButtonStyle())
                    }
                    // Öffnet wie die Website im In-App-Browser (PDF inklusive).
                    if let extra = place.extraURL, let title = place.extraLinkTitle {
                        Button {
                            openWebsite(extra)
                        } label: {
                            StedeActionChip(title: title, symbol: "doc.text.fill")
                        }
                        .buttonStyle(StedeCardButtonStyle())
                    }
                    if let site = place.websiteURL {
                        Button {
                            openWebsite(site)
                        } label: {
                            StedeActionChip(title: "Website", symbol: "safari.fill")
                        }
                        .buttonStyle(StedeCardButtonStyle())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }
}

/// Lädt das Bundle-Bild direkt von der Datei — ein Asset-Katalog wäre für
/// 37 einmalig übernommene Fotos zu viel Ballast.
/// Foto aus dem Bucket (dauerhaft zwischengespeichert, bis dahin Sandfläche) oder aus dem Bundle.
private struct GastroImage: View {
    let url: URL

    var body: some View {
        if !url.isFileURL {
            RemoteImage(url: url) { StedeTheme.sand }
        } else if let image {
            image
                .resizable()
                .scaledToFill()
        } else {
            StedeTheme.sand
        }
    }

    private var image: Image? {
        #if canImport(UIKit)
        UIImage(contentsOfFile: url.path(percentEncoded: false)).map(Image.init(uiImage:))
        #elseif canImport(AppKit)
        NSImage(contentsOf: url).map(Image.init(nsImage:))
        #else
        nil
        #endif
    }
}

private struct BikeRentalCard: View {
    let provider: BikeRentalProvider
    /// Feste Größe: ein zweizeiliger Name soll das Symbol nicht größer machen.
    @ScaledMetric(relativeTo: .headline) private var chipSide = 52.0
    let isSelected: Bool
    let showOnMap: () -> Void
    let isFavorite: Bool
    let toggleFavorite: () -> Void
    let openWebsite: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                StedeIconChip(symbol: "bicycle", color: StedeTheme.duneGreen, side: chipSide)
                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.name)
                        .font(.headline)
                        .fontDesign(.rounded)
                        .multilineTextAlignment(.leading)
                    // Art und Angebot zusammen in einer Pillenreihe unter dem Titel.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            StedeTagPill(text: IslandCatalog.bikeCategory, color: StedeTheme.duneGreen)
                            ForEach(provider.features, id: \.self) { feature in
                                StedeTagPill(text: feature, color: StedeTheme.duneGreen)
                            }
                        }
                    }
                }
                Spacer(minLength: 8)
                FavoriteButton(isFavorite: isFavorite, toggle: toggleFavorite)
            }

            if let teaser = provider.teaser {
                Text(teaser)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }


            ForEach(provider.stations, id: \.self) { station in
                Label(station.street, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if provider.callURL != nil || provider.websiteURL != nil {
                HStack(spacing: 8) {
                    if let call = provider.callURL, let phone = provider.phone {
                        // Link statt Button: iOS blendet `tel:` aus, wo es nicht geht.
                        Link(destination: call) {
                            StedeActionChip(title: phone, symbol: "phone.fill")
                        }
                        .buttonStyle(StedeCardButtonStyle())
                    }
                    if let site = provider.websiteURL {
                        Button {
                            openWebsite(site)
                        } label: {
                            StedeActionChip(title: "Website", symbol: "safari.fill")
                        }
                        .buttonStyle(StedeCardButtonStyle())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .stedeCard(highlighted: isSelected)
        // Tippen zeigt die Stationen auf der Karte; Stern, Telefon und Website
        // bleiben eigene Ziele, deshalb kein Button um die ganze Karte.
        .contentShape(StedeTheme.cardShape)
        .onTapGesture(perform: showOnMap)
        .accessibilityAction(named: "Auf Karte zeigen", showOnMap)
    }
}

/// Hinweis über der Ehrenamt-Liste: wer die Ehrenamtskarte bekommt und damit die
/// Vergünstigungen nutzen darf (Stand freiwilligenserver.de, 09/2026). Ausblendbar.
private struct VolunteerInfoCard: View {
    let dismiss: () -> Void

    var body: some View {
        InfoCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Label("Wer darf das nutzen?", systemImage: "person.badge.shield.checkmark.fill")
                        .font(.headline)
                        .foregroundStyle(StedeTheme.duneGreen)
                    Spacer(minLength: 8)
                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(.secondary.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(StedeCardButtonStyle())
                    .accessibilityLabel("Hinweis ausblenden")
                }
                Text("Die Angebote gelten für alle mit der Ehrenamtskarte Niedersachsen/Bremen – einfach beim Anbieter vorzeigen.")
                    .font(.subheadline)
                Text("Die Karte bekommt, wer sich seit mindestens zwei Jahren mindestens fünf Stunden pro Woche (250 Stunden im Jahr) unbezahlt engagiert. Ebenso Inhaberinnen und Inhaber einer JULEICA sowie Aktive in Freiwilliger Feuerwehr, Katastrophenschutz, Rettungsdienst oder Notfallseelsorge mit Grundausbildung.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let url = URL(string: "https://www.freiwilligenserver.de/ehrenamtskarte/faq/voraussetzungen-fuer-den-erhalt") {
                    Link(destination: url) {
                        Label("Voraussetzungen und Antrag", systemImage: "arrow.up.right.square")
                            .font(.subheadline.weight(.semibold))
                    }
                    .tint(StedeTheme.ink)
                }
            }
        }
    }
}
