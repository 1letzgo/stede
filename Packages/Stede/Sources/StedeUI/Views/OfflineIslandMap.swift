import MapKit
import StedeCore
import SwiftUI

#if canImport(UIKit)
import UIKit

/// Offline-Karte mit den Pins der Rubrik „Insel". Gleiche Aufgaben wie die
/// frühere SwiftUI-`Map`: Pins zeigen, Tipp wählt aus, Auswahl zentriert.
struct OfflineIslandMap: UIViewRepresentable {
    let pins: [StedeMapPin]
    let selectedID: String?
    let select: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(select: select) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = false
        map.isPitchEnabled = false
        map.isRotateEnabled = false
        // Ganzes Stadtgebiet samt Hobbie und Park der Gärten; weiter hinaus gibt es keine Daten.
        map.cameraBoundary = MKMapView.CameraBoundary(
            coordinateRegion: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 53.26, longitude: 7.935),
                span: MKCoordinateSpan(latitudeDelta: 0.18, longitudeDelta: 0.27)
            )
        )
        map.cameraZoomRange = MKMapView.CameraZoomRange(minCenterCoordinateDistance: 150, maxCenterCoordinateDistance: 45000)
        context.coordinator.addBaseLayers(to: map)
        context.coordinator.update(map, pins: pins, selectedID: selectedID, animated: false)
        context.coordinator.updateDetail(map)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.select = select
        context.coordinator.update(map, pins: pins, selectedID: selectedID, animated: true)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var select: (String) -> Void
        private var pinIDs: [String] = []
        private var selectedID: String?
        private var styles: [ObjectIdentifier: LayerStyle] = [:]
        /// Feine Ebenen (Fußwege), die nur beim Hineinzoomen auf der Karte liegen.
        private var detail: [MKOverlay] = []
        private var showsDetail = false
        /// Ab dieser Ausschnittshöhe (Grad) werden Fußwege gezeigt.
        private static let detailSpan: CLLocationDegrees = 0.035

        init(select: @escaping (String) -> Void) {
            self.select = select
        }

        // MARK: Grundkarte

        func addBaseLayers(to map: MKMapView) {
            // Leere Kacheln ersetzen die Apple-Karte — nichts wird nachgeladen.
            // Deckend in der Grundfarbe: sonst zeigt MapKit dort, wo keine Daten liegen,
            // sein Karo-Raster für fehlende Kacheln.
            let blank = BlankTileOverlay(color: UIColor(StedeTheme.sand).resolvedColor(with: map.traitCollection))
            blank.canReplaceMapContent = true
            map.addOverlay(blank, level: .aboveLabels)

            guard let data = IslandMapData.shared else { return }
            // Deckender Grund, sonst scheint das leere Kachelraster durch;
            // außerhalb des Datenausschnitts bleibt die Fläche blass.
            let ground = MKPolygon(coordinates: [
                CLLocationCoordinate2D(latitude: 53.0, longitude: 7.5),
                CLLocationCoordinate2D(latitude: 53.5, longitude: 7.5),
                CLLocationCoordinate2D(latitude: 53.5, longitude: 8.4),
                CLLocationCoordinate2D(latitude: 53.0, longitude: 8.4),
            ], count: 4)
            add(ground, style: .fill(StedeTheme.mudflat, 0.12), to: map)
            add(multiPolygon(data.land), style: .fill(StedeTheme.sand, 1), to: map)
            add(multiPolygon(data.polygons["settlement"]), style: .fill(StedeTheme.mudflat, 0.16), to: map)
            add(multiPolygon(data.polygons["sand"]), style: .fill(StedeTheme.sunAmber, 0.20), to: map)
            add(multiPolygon(data.polygons["green"]), style: .fill(StedeTheme.duneGreen, 0.16), to: map)
            add(multiPolygon(data.polygons["dune"]), style: .fill(StedeTheme.duneGreen, 0.28), to: map)
            add(multiPolygon(data.polygons["saltmarsh"]), style: .fill(StedeTheme.seaTeal, 0.18), to: map)
            add(multiPolygon(data.polygons["wood"]), style: .fill(StedeTheme.duneGreen, 0.45), to: map)
            add(multiPolygon(data.polygons["water"]), style: .fill(StedeTheme.seaTeal, 0.45), to: map)
            add(multiPolyline(data.lines["stream"]), style: .line(StedeTheme.seaTeal, 0.55, width: 1.2, dashed: false), to: map)
            add(multiPolyline(data.lines["groyne"]), style: .line(StedeTheme.mudflat, 0.6, width: 2, dashed: false), to: map)
            // Keine Einzelgebäude: die Siedlungsfläche reicht, und die 11.000 Umrisse kosteten
            // beim Herauszoomen Sekunden. Fußwege nur nah heran (siehe `regionDidChangeAnimated`).
            if let paths = multiPolyline(data.lines["path"]) {
                styles[ObjectIdentifier(paths)] = .line(StedeTheme.ink, 0.28, width: 1, dashed: true); detail.append(paths)
            }
            add(multiPolyline(data.lines["road"]), style: .line(StedeTheme.ink, 0.38, width: 2.5, dashed: false), to: map)
            add(multiPolyline(data.lines["rail"]), style: .line(StedeTheme.harborRed, 0.6, width: 1.5, dashed: true), to: map)
        }

        private func add(_ overlay: MKOverlay?, style: LayerStyle, to map: MKMapView) {
            guard let overlay else { return }
            styles[ObjectIdentifier(overlay)] = style
            map.addOverlay(overlay, level: .aboveLabels)
        }

        private func coordinates(_ ring: [[Double]]) -> [CLLocationCoordinate2D] {
            ring.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
        }

        private func multiPolygon(_ rings: [[[Double]]]?) -> MKMultiPolygon? {
            guard let rings, !rings.isEmpty else { return nil }
            return MKMultiPolygon(rings.map { ring in
                let points = coordinates(ring)
                return MKPolygon(coordinates: points, count: points.count)
            })
        }

        private func multiPolyline(_ lines: [[[Double]]]?) -> MKMultiPolyline? {
            guard let lines, !lines.isEmpty else { return nil }
            return MKMultiPolyline(lines.map { line in
                let points = coordinates(line)
                return MKPolyline(coordinates: points, count: points.count)
            })
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tiles = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tiles)
            }
            let style = styles[ObjectIdentifier(overlay)] ?? .fill(StedeTheme.sand, 1)
            switch (overlay, style) {
            case let (polygon as MKMultiPolygon, .fill(color, alpha)):
                let renderer = MKMultiPolygonRenderer(multiPolygon: polygon)
                renderer.fillColor = UIColor(color).withAlphaComponent(alpha)
                return renderer
            case let (polygon as MKPolygon, .fill(color, alpha)):
                let renderer = MKPolygonRenderer(polygon: polygon)
                renderer.fillColor = UIColor(color).withAlphaComponent(alpha)
                return renderer
            case let (polygon as MKMultiPolygon, .building):
                let renderer = MKMultiPolygonRenderer(multiPolygon: polygon)
                renderer.fillColor = UIColor(StedeTheme.ink).withAlphaComponent(0.14)
                renderer.strokeColor = UIColor(StedeTheme.ink).withAlphaComponent(0.22)
                renderer.lineWidth = 0.5
                return renderer
            case let (line as MKMultiPolyline, .line(color, alpha, width, dashed)):
                let renderer = MKMultiPolylineRenderer(multiPolyline: line)
                renderer.strokeColor = UIColor(color).withAlphaComponent(alpha)
                renderer.lineWidth = width
                renderer.lineCap = .round
                if dashed { renderer.lineDashPattern = [3, 3] }
                return renderer
            default:
                return MKOverlayRenderer(overlay: overlay)
            }
        }

        // MARK: Pins und Auswahl

        func update(_ map: MKMapView, pins: [StedeMapPin], selectedID: String?, animated: Bool) {
            let ids = pins.map(\.id)
            if ids != pinIDs {
                map.removeAnnotations(map.annotations)
                map.addAnnotations(pins.map(PinAnnotation.init))
                pinIDs = ids
                map.setRegion(StedePlaceMap.region(for: pins), animated: animated)
            }
            if selectedID != self.selectedID {
                self.selectedID = selectedID
                if let pin = pins.first(where: { $0.placeID == selectedID }) {
                    map.setRegion(
                        MKCoordinateRegion(center: pin.coordinate,
                                           span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.006)),
                        animated: animated
                    )
                } else {
                    map.setRegion(StedePlaceMap.region(for: pins), animated: animated)
                }
            }
            for annotation in map.annotations {
                guard let pin = annotation as? PinAnnotation,
                      let view = map.view(for: pin) as? PinAnnotationView else { continue }
                view.setChosen(pin.pin.placeID == selectedID)
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            updateDetail(mapView)
        }

        /// Fußwege unter die Straßen legen, sobald nah genug gezoomt ist.
        func updateDetail(_ map: MKMapView) {
            let wanted = map.region.span.latitudeDelta < Self.detailSpan
            guard wanted != showsDetail, !detail.isEmpty else { return }
            showsDetail = wanted
            if wanted {
                // Unter die Straßen (letzte Grundebene vor den Straßen ist das Gewässernetz).
                let roads = map.overlays.first { styles[ObjectIdentifier($0)].map { if case .line(_, _, 2.5, _) = $0 { true } else { false } } ?? false }
                for overlay in detail {
                    if let roads { map.insertOverlay(overlay, below: roads) } else { map.addOverlay(overlay, level: .aboveLabels) }
                }
            } else {
                map.removeOverlays(detail)
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let pin = annotation as? PinAnnotation else { return nil }
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: PinAnnotationView.reuseID) as? PinAnnotationView)
                ?? PinAnnotationView(annotation: pin, reuseIdentifier: PinAnnotationView.reuseID)
            view.annotation = pin
            view.configure(pin.pin, chosen: pin.pin.placeID == selectedID)
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            guard let pin = annotation as? PinAnnotation else { return }
            // Sofort wieder abwählen, damit ein zweiter Tipp erneut auslöst.
            mapView.deselectAnnotation(annotation, animated: false)
            select(pin.pin.placeID)
        }
    }
}

private enum LayerStyle {
    case fill(Color, CGFloat)
    case line(Color, CGFloat, width: CGFloat, dashed: Bool)
    case building
}

/// Liefert leere Kacheln: Mit `canReplaceMapContent` zeichnet MapKit dann
/// nur noch unsere eigenen Flächen und Linien.
private final class BlankTileOverlay: MKTileOverlay {
    private let tile: Data

    init(color: UIColor) {
        tile = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256)).pngData { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
        }
        super.init(urlTemplate: nil)
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        result(tile, nil)
    }
}

private final class PinAnnotation: NSObject, MKAnnotation {
    let pin: StedeMapPin
    var coordinate: CLLocationCoordinate2D { pin.coordinate }
    var title: String? { pin.title }

    init(_ pin: StedeMapPin) {
        self.pin = pin
    }
}

/// Runder Pin mit Symbol wie bisher; gewählt invertiert und größer.
private final class PinAnnotationView: MKAnnotationView {
    static let reuseID = "stede-pin"
    private let circle = UIView()
    private let icon = UIImageView()
    private var color: UIColor = .systemTeal

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 30, height: 30)
        centerOffset = CGPoint(x: 0, y: -15)
        canShowCallout = false
        circle.frame = bounds
        circle.layer.cornerRadius = 15
        circle.layer.borderWidth = 2
        icon.frame = bounds.insetBy(dx: 7, dy: 7)
        icon.contentMode = .scaleAspectFit
        circle.addSubview(icon)
        addSubview(circle)
    }

    required init?(coder: NSCoder) { nil }

    func configure(_ pin: StedeMapPin, chosen: Bool) {
        color = UIColor(pin.color)
        icon.image = UIImage(systemName: pin.symbol, withConfiguration: UIImage.SymbolConfiguration(weight: .bold))
        accessibilityLabel = pin.title
        setChosen(chosen)
    }

    func setChosen(_ chosen: Bool) {
        UIView.animate(withDuration: 0.2) { [self] in
            circle.backgroundColor = chosen ? .white : color
            circle.layer.borderColor = (chosen ? color : .white).cgColor
            circle.layer.borderWidth = chosen ? 3 : 2
            icon.tintColor = chosen ? color : .white
            transform = chosen ? CGAffineTransform(scaleX: 1.35, y: 1.35) : .identity
            layer.shadowOpacity = chosen ? 0.3 : 0
            layer.shadowRadius = 4
            layer.shadowOffset = CGSize(width: 0, height: 2)
        }
        zPriority = chosen ? .max : .defaultUnselected
        accessibilityTraits = chosen ? [.button, .selected] : .button
    }
}
#endif
