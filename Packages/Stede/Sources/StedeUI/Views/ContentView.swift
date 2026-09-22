import SwiftUI
import StedeCore

enum AppTab: Hashable, CaseIterable {
    case start
    case events

    var title: String {
        switch self {
        case .start: "Start"
        case .events: "Kalender"
        }
    }

    var symbol: String {
        switch self {
        case .start: "house.fill"
        case .events: "calendar"
        }
    }
}

/// Der ausgewählte Tab, für Deep-Links und Startoptionen.
@Observable
final class AppNavigation {
    var tab: AppTab

    init(tab: AppTab) { self.tab = tab }
}

public struct ContentView: View {
    public init() {}

    @State private var navigation = AppNavigation(tab: LaunchOptions.tab)
    @State private var homePath = LaunchOptions.homePath
    /// Gewählter Tag gehört der App, nicht dem einzelnen Screen — sonst fällt er
    /// bei jedem Tabwechsel auf heute zurück.
    @State private var dateStore = SelectedDateStore()
    /// Die Fahrtrichtung bleibt über App-Starts erhalten — meist interessiert nur eine.
    @AppStorage("train.direction") private var direction: TrainDirection = .oldenburg
    /// Favoriten der Rubrik „Insel" — Kacheln auf Start und Kategorie-Ansichten
    /// müssen denselben Stand sehen. Übernimmt die früheren getrennten Listen.
    @State private var favorites = PlaceFavorites(
        key: "island.favorites",
        legacyKeys: ["gastro.favorites", "bikes.favorites"]
    )

    public var body: some View {
        TabView(selection: $navigation.tab) {
            Tab(AppTab.start.title, systemImage: AppTab.start.symbol, value: AppTab.start) {
                NavigationStack(path: $homePath) {
                    HomeView(direction: $direction, path: $homePath)
                        .navigationDestination(for: HomeDestination.self) { destination in
                            switch destination {
                            case .weather: WeatherView()
                            case .train: TrainView(direction: $direction)
                            case .bus: BusView()
                            case let .island(category):
                                IslandView(category: category)
                            }
                        }
                }
            }
            Tab(AppTab.events.title, systemImage: AppTab.events.symbol, value: AppTab.events) {
                screen { EventView() }
            }
        }
        .environment(dateStore)
        .environment(favorites)
        .environment(navigation)
        .task {
            // Ohne diesen Startwert hat der Vorwärtspfeil keine Obergrenze,
            // solange Wetter noch nicht geöffnet war.
            dateStore.limit(to: await WeatherStore.latestAvailableDay())
        }
    }

    private func screen(@ViewBuilder _ content: () -> some View) -> some View {
        NavigationStack {
            content()
        }
    }
}

/// Startet die App auf einem bestimmten Screen — für Store-Screenshots:
/// `xcrun simctl launch <udid> de.letzgo.stede -startScreen gastro`.
enum LaunchOptions {
    static var tab: AppTab {
        switch UserDefaults.standard.string(forKey: "startScreen") {
        case "events": .events
        default: .start
        }
    }

    static var homePath: [HomeDestination] {
        switch UserDefaults.standard.string(forKey: "startScreen") {
        case "weather": [.weather]
        case "train": [.train]
        case "bus": [.bus]
        case "island", "gastro": [.island(category: IslandCatalog.gastroCategory)]
        case "bikes": [.island(category: IslandCatalog.bikeCategory)]
        case "sights", "discover": [.island(category: IslandCatalog.discoverCategory)]
        case "shopping": [.island(category: IslandCatalog.shoppingCategory)]
        case "trips": [.island(category: IslandCatalog.tripsCategory)]
        case "playgrounds": [.island(category: IslandCatalog.playgroundsCategory)]
        default: []
        }
    }
}

#Preview {
    ContentView()
        .environment(\.locale, Locale(identifier: "de_DE"))
}
