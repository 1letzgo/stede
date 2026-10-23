import StedeCore
import SwiftUI

/// Wind und Seegang vor der Insel (`marine_forecasts`), nur mit `tenants.config.marine`.
@Observable
final class MarineViewModel {
    private(set) var hours: [MarineHour] = []
    private var loadedAt: Date?

    var isAvailable: Bool { Tenants.current.marine != nil }

    /// Die Vorhersage reicht rund drei Tage; geladen wird einmal je Viertelstunde.
    func load(force: Bool) async {
        guard isAvailable else { return }
        if !force, let loadedAt, Date().timeIntervalSince(loadedAt) < 900 { return }
        let start = Date().addingTimeInterval(-3 * 3600)
        if let fresh = try? await MarineClient().hours(from: start, to: start.addingTimeInterval(5 * 86400)), !fresh.isEmpty {
            hours = fresh
            loadedAt = Date()
        }
    }

    /// Stunde, die einer Wetterstunde am nächsten liegt (höchstens 90 Minuten daneben).
    func hour(near date: Date) -> MarineHour? {
        hours.min { abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date)) }
            .flatMap { abs($0.timestamp.timeIntervalSince(date)) <= 5400 ? $0 : nil }
    }

    /// Stunden eines Tages, für den Verlauf.
    func hours(on day: Date) -> [MarineHour] {
        let start = IslandTime.startOfDay(day)
        let end = IslandTime.day(start, adding: 1)
        return hours.filter { $0.timestamp >= start && $0.timestamp < end }
    }
}

enum MarineStyle {
    /// Bis 4 Bft ruhig, 5–6 kräftig, ab 7 stürmisch.
    static func color(_ beaufort: Int?) -> Color {
        switch beaufort ?? 0 {
        case ...4: StedeTheme.seaTeal
        case 5...6: StedeTheme.sunAmber
        default: StedeTheme.harborRed
        }
    }
}

/// Große Windkarte unter dem Wetterkopf: Beaufort, Richtung, Geschwindigkeit, Wellenhöhe und
/// der Tagesverlauf in Dreistundenschritten.
struct MarineWindCard: View {
    let hour: MarineHour
    let day: [MarineHour]
    let place: String?

    var body: some View {
        let color = MarineStyle.color(hour.beaufort)
        InfoCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 14) {
                    // Der Pfeil zeigt, wohin der Wind weht.
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(color)
                        .rotationEffect(.degrees((hour.windDirection ?? 0) + 180))
                        .frame(width: 58, height: 58)
                        .background(color.opacity(0.16), in: Circle())
                        .opacity(hour.windDirection == nil ? 0 : 1)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(hour.beaufort ?? 0)")
                                .font(.system(size: 44, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                            Text("Bft")
                                .font(.title3.weight(.semibold))
                                .fontDesign(.rounded)
                                .foregroundStyle(.secondary)
                        }
                        Text(([hour.compass.map { "aus \($0)" }, hour.beaufortName] as [String?]).compactMap { $0 }.joined(separator: " · "))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(color)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 4) {
                        if let kmh = hour.kmh {
                            Text("\(WeatherFormat.number(kmh)) km/h")
                                .font(.headline)
                                .fontDesign(.rounded)
                                .monospacedDigit()
                        }
                        if let knots = hour.knots {
                            Text("\(WeatherFormat.number(knots)) kn")
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        if let wave = hour.waveHeight {
                            Label("\(WeatherFormat.number(wave, digits: 1 ... 1)) m", systemImage: "water.waves")
                                .font(.subheadline.weight(.medium))
                                .monospacedDigit()
                                .foregroundStyle(StedeTheme.seaTeal)
                        }
                    }
                }

                if day.count > 1 {
                    Rectangle().fill(.separator).frame(height: 1)
                    HStack(spacing: 0) {
                        ForEach(threeHourly) { step in
                            VStack(spacing: 4) {
                                Text(WeatherFormat.hourNumber(step.timestamp))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "location.north.fill")
                                    .font(.caption)
                                    .foregroundStyle(MarineStyle.color(step.beaufort))
                                    .rotationEffect(.degrees((step.windDirection ?? 0) + 180))
                                Text("\(step.beaufort ?? 0)")
                                    .font(.subheadline.weight(.semibold))
                                    .fontDesign(.rounded)
                                    .monospacedDigit()
                                    .foregroundStyle(step.id == hour.id ? MarineStyle.color(step.beaufort) : .primary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Windstärke im Tagesverlauf in Beaufort")
                }

                Text("Wind 10 m und Wellen \(place.map { "· \($0)" } ?? "") · DWD-Seegangsmodell wie marineforecast.bsh.de")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Alle drei Stunden ein Wert, so passt der Tag in eine Zeile.
    private var threeHourly: [MarineHour] {
        day.filter { IslandTime.calendar.component(.hour, from: $0.timestamp) % 3 == 0 }
    }
}
