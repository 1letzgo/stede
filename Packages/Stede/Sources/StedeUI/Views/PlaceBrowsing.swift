import MapKit
import StedeCore
import SwiftUI

/// Merkliste der Favoriten. Nur IDs, damit die Liste jeden Datenstand übersteht.
@Observable
final class PlaceFavorites {
    private let key: String
    private let defaults: UserDefaults
    private(set) var ids: Set<String>

    /// `legacyKeys`: frühere Listen, die einmalig übernommen und dann gelöscht werden.
    init(key: String, legacyKeys: [String] = [], defaults: UserDefaults = .standard) {
        self.key = key
        self.defaults = defaults
        var ids = Set(defaults.stringArray(forKey: key) ?? [])
        for legacy in legacyKeys {
            guard let old = defaults.stringArray(forKey: legacy) else { continue }
            ids.formUnion(old)
            defaults.removeObject(forKey: legacy)
        }
        defaults.set(Array(ids), forKey: key)
        self.ids = ids
    }

    func contains(_ id: String) -> Bool {
        ids.contains(id)
    }

    func toggle(_ id: String) {
        if ids.contains(id) {
            ids.remove(id)
        } else {
            ids.insert(id)
        }
        defaults.set(Array(ids), forKey: key)
    }
}

/// Kleine farbige Pille unter dem Titel einer Ortskarte: Art des Ortes
/// (Restaurant, Café …) oder Angebot (E-Bikes, Kinderräder …).
struct StedeTagPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
    }
}

/// Stern zum Merken, 44 pt Trefferfläche.
struct FavoriteButton: View {
    let isFavorite: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.headline)
                .foregroundStyle(isFavorite ? AnyShapeStyle(StedeTheme.sunAmber) : AnyShapeStyle(.tertiary))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(StedeCardButtonStyle())
        .accessibilityLabel(isFavorite ? "Favorit entfernen" : "Als Favorit merken")
    }
}

/// Ein Ort auf der Übersichtskarte. `placeID` verweist auf die Karte in der
/// Liste; ein Anbieter mit mehreren Stationen hat mehrere Pins.
struct StedeMapPin: Identifiable {
    let id: String
    let placeID: String
    let title: String
    let coordinate: CLLocationCoordinate2D
    let symbol: String
    let color: Color
}

/// Übersichtskarte über der Liste; ein Tipp auf einen Pin wählt den Ort aus.
struct StedePlaceMap: View {
    let pins: [StedeMapPin]
    let selectedID: String?
    let select: (String) -> Void
    @State private var position: MapCameraPosition = .automatic
    @ScaledMetric(relativeTo: .body) private var height = 220.0

    var body: some View {
        #if canImport(UIKit)
        // Eigene Offline-Karte aus OpenStreetMap-Daten — unterwegs ist
        // der Empfang oft schlecht.
        OfflineIslandMap(pins: pins, selectedID: selectedID, select: select)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .clipShape(StedeTheme.cardShape)
            .overlay(alignment: .bottomTrailing) {
                Text("© OpenStreetMap")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.thinMaterial, in: Capsule())
                    .padding(8)
            }
        #else
        appleMap
        #endif
    }

    private var appleMap: some View {
        Map(position: $position) {
            ForEach(pins) { pin in
                Annotation(pin.title, coordinate: pin.coordinate, anchor: .bottom) {
                    let isSelected = pin.placeID == selectedID
                    Button {
                        select(pin.placeID)
                    } label: {
                        // Gewählt: invertiert und größer statt einer Signalfarbe —
                        // Rot ist schon Kategoriefarbe (Eiscafé, Ausflüge).
                        Image(systemName: pin.symbol)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(isSelected ? pin.color : .white)
                            .frame(width: 30, height: 30)
                            .background(isSelected ? Color.white : pin.color, in: Circle())
                            .overlay(Circle().stroke(isSelected ? pin.color : .white, lineWidth: isSelected ? 3 : 2))
                            .scaleEffect(isSelected ? 1.35 : 1)
                            .shadow(color: .black.opacity(isSelected ? 0.3 : 0), radius: 4, y: 2)
                            .animation(.snappy, value: isSelected)
                    }
                    .buttonStyle(StedeCardButtonStyle())
                    .accessibilityLabel(pin.title)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipShape(StedeTheme.cardShape)
        .onAppear { position = .region(Self.region(for: pins)) }
        .onChange(of: pins.map(\.id)) {
            withAnimation {
                position = .region(Self.region(for: pins))
            }
        }
        // Ein Tipp auf eine Karte in der Liste rückt den Ort in die Mitte.
        .onChange(of: selectedID) {
            // Ohne Auswahl wieder der ganze Ort.
            guard let pin = pins.first(where: { $0.placeID == selectedID }) else {
                withAnimation { position = .region(Self.region(for: pins)) }
                return
            }
            withAnimation {
                position = .region(
                    MKCoordinateRegion(
                        center: pin.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.006)
                    )
                )
            }
        }
    }

    /// Ausschnitt über alle Pins mit etwas Rand. Weit entfernte Orte (Meierei
    /// am Ostende, Lokale am Hafen) bleiben außen vor, sonst schrumpft der Ort;
    /// angetippt rückt die Karte trotzdem zu ihnen.
    static func region(for pins: [StedeMapPin]) -> MKCoordinateRegion {
        let village = CLLocationCoordinate2D(latitude: 53.2570, longitude: 7.9270)
        let nearby = pins.map(\.coordinate).filter {
            abs($0.latitude - village.latitude) < 0.01 && abs($0.longitude - village.longitude) < 0.02
        }
        let coordinates = nearby.isEmpty ? pins.map(\.coordinate) : nearby
        guard let first = coordinates.first else {
            return MKCoordinateRegion(center: village, span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.02))
        }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.6, 0.004),
                longitudeDelta: max((maxLon - minLon) * 1.4, 0.006)
            )
        )
    }
}

extension View {
    /// Karten-Symbol oben rechts in der Leiste, blendet die Übersichtskarte ein und aus.
    func mapToggle(isOn: Binding<Bool>) -> some View {
        toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation {
                        isOn.wrappedValue.toggle()
                    }
                } label: {
                    // Fest weiß: `.toolbarColorScheme(.dark)` greift beim ersten
                    // Aufbau erst verspätet, bis dahin stünde das Symbol blau auf Blau.
                    Image(systemName: isOn.wrappedValue ? "map.fill" : "map")
                        .foregroundStyle(.white)
                }
                .tint(.white)
                .accessibilityLabel(isOn.wrappedValue ? "Karte ausblenden" : "Karte einblenden")
            }
        }
    }
}
