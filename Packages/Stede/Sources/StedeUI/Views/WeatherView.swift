import Charts
import StedeCore
import SwiftUI

struct WeatherView: View {
    @Environment(SelectedDateStore.self) private var dateStore
    @State private var weather = WeatherViewModel()
    /// Vom Nutzer angetippte Stunde; `nil` heißt „jetzt" bzw. Mittag.
    @State private var selectedHourID: WeatherHour.ID?

    var body: some View {
        TabScreen(title: "Wetter") {
            await reload(force: true)
        } content: {
            LoadStateView(state: weather.state, emptyMessage: "Für diesen Tag liegt kein Wetter vor.") {
                if let summary = weather.summary, let selected {
                    ScrollView {
                        VStack(alignment: .leading, spacing: StedeTheme.cardSpacing) {
                            WeatherHero(
                                hour: selected,
                                badge: badge(for: selected),
                                overview: WeatherDayOverview(summary: summary)
                            )

                            StedeSectionHeader(title: "Stündlich", symbol: "clock")
                            WeatherHourStrip(
                                hours: summary.hours,
                                selectedID: selected.id,
                                currentID: dateStore.isToday ? weather.currentAnchor() : nil
                            ) { id in
                                withAnimation(.snappy) { selectedHourID = id }
                            }

                            StedeSectionHeader(title: "Tagesverlauf", symbol: "chart.xyaxis.line")
                            WeatherDayChart(hours: summary.hours, selectedID: selected.id) { id in
                                selectedHourID = id
                            }

                            StedeSectionHeader(title: "Details um \(WeatherFormat.hour(selected.timestamp))", symbol: "square.grid.2x2")
                            WeatherDetailGrid(
                                hour: selected,
                                summary: summary
                            )

                            SourceFooter(text: sourceLine)
                        }
                        .padding()
                    }
                    .id("weather-\(IslandTime.isoDate(dateStore.selectedDate))")
                }
            }
        }
        .task(id: dateStore.selectedDate) {
            selectedHourID = nil
            await reload(force: false)
        }
    }

    private var selected: WeatherHour? {
        guard let hours = weather.summary?.hours else { return nil }
        if let selectedHourID, let hour = hours.first(where: { $0.id == selectedHourID }) {
            return hour
        }
        return pinned
    }

    private var pinned: WeatherHour? {
        if dateStore.isToday {
            guard let id = weather.currentAnchor() else { return weather.summary?.representative }
            return weather.summary?.hours.first { $0.id == id }
        }
        return weather.summary?.representative
    }

    private func badge(for hour: WeatherHour) -> String {
        if dateStore.isToday, hour.id == weather.currentAnchor() {
            return "Jetzt"
        }
        return WeatherFormat.hour(hour.timestamp)
    }

    private var sourceLine: String {
        var parts = ["DWD über Bright Sky"]
        if let name = weather.summary?.sourceName {
            parts[0] += " · \(name)"
        }
        return parts.joined(separator: " · ")
    }

    private func reload(force: Bool) async {
        async let weatherLoad: Void = weather.load(day: dateStore.selectedDate, force: force)
        async let horizon = WeatherStore.latestAvailableDay()
        await weatherLoad
        dateStore.limit(to: await horizon)
    }
}

/// Zahlen und Uhrzeiten der Wetteransicht, immer in Inselzeit.
enum WeatherFormat {
    /// „17 Uhr" — das Format liefert die Einheit selbst mit.
    static func hour(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(locale: IslandTime.germanLocale, calendar: IslandTime.calendar, timeZone: IslandTime.timeZone)
                .hour(.twoDigits(amPM: .omitted))
        )
    }

    static func hourNumber(_ date: Date) -> String {
        String(IslandTime.calendar.component(.hour, from: date))
    }

    static func degrees(_ value: Double?) -> String {
        guard let value else { return "–" }
        return "\(value.formatted(.number.precision(.fractionLength(0))))°"
    }

    static func number(_ value: Double, digits: ClosedRange<Int> = 0 ... 0) -> String {
        value.formatted(.number.precision(.fractionLength(digits)).locale(IslandTime.germanLocale))
    }

    /// Himmelsrichtung, aus der der Wind kommt.
    static func compass(_ degrees: Double) -> String {
        let names = ["N", "NO", "O", "SO", "S", "SW", "W", "NW"]
        let index = Int((degrees.truncatingRemainder(dividingBy: 360) + 22.5) / 45) % 8
        return names[index]
    }
}

/// Wettersymbole zweifarbig: Wolke im Grundton, Sonne gelb, Tropfen blau.
/// `.multicolor` malt Wolken weiß — auf hellen Karten unsichtbar.
private struct WeatherSymbol: View {
    let name: String
    var base: Color = StedeTheme.ink.opacity(0.55)

    var body: some View {
        if name.hasPrefix("cloud") || name == "wind" {
            Image(systemName: name)
                .symbolRenderingMode(.palette)
                .foregroundStyle(base, accent)
        } else {
            Image(systemName: name)
                .symbolRenderingMode(.palette)
                .foregroundStyle(accent, base)
        }
    }

    private var accent: Color {
        switch name {
        case "sun.max.fill", "cloud.sun.fill", "cloud.bolt.fill": StedeTheme.sunAmber
        case "moon.stars.fill", "cloud.moon.fill": StedeTheme.sunAmber.opacity(0.8)
        case "cloud.rain.fill", "cloud.sleet.fill", "cloud.snow.fill", "cloud.hail.fill": StedeTheme.seaTeal
        default: base
        }
    }
}

// MARK: - Kopf

private struct WeatherHero: View {
    let hour: WeatherHour
    let badge: String
    let overview: WeatherDayOverview
    /// Feste Höhe: beim Wechsel der Stunde soll die Karte nicht springen.
    @ScaledMetric(relativeTo: .largeTitle) private var heroHeight = 112.0

    var body: some View {
        InfoCard(fill: AnyShapeStyle(WeatherAtmosphere.gradient(for: hour))) {
            // Kompakt: Temperatur links, Symbol, Zustand und Tageswerte rechts.
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(badge)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.22), in: Capsule())
                        .contentTransition(.numericText())
                    Text(WeatherFormat.degrees(hour.temperature))
                        .font(.system(size: 58, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(hour.conditionLabel)
                            .font(.headline)
                            .fontDesign(.rounded)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        // Feste Fläche: Sonne, Wolke und Regen sind unterschiedlich hoch.
                        WeatherSymbol(name: hour.symbolName, base: .white)
                            .font(.system(size: 34))
                            .frame(width: 44, height: 40)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    HStack(spacing: 10) {
                        Label(WeatherFormat.degrees(overview.maxTemperature), systemImage: "arrow.up")
                        Label(WeatherFormat.degrees(overview.minTemperature), systemImage: "arrow.down")
                        Label("\(WeatherFormat.number(overview.precipitationSum, digits: 0 ... 1)) mm", systemImage: "drop.fill")
                    }
                    .labelStyle(CompactLabelStyle())
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }
            }
            .frame(height: heroHeight)
        }
        .weatherHeroChrome(true)
        .accessibilityElement(children: .combine)
    }
}

/// Symbol dicht vor dem Wert — spart Breite in der kompakten Kopfkarte.
private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.font(.caption.weight(.bold))
            configuration.title
        }
    }
}

// MARK: - Stundenleiste

private struct WeatherHourStrip: View {
    let hours: [WeatherHour]
    let selectedID: WeatherHour.ID
    let currentID: WeatherHour.ID?
    let select: (WeatherHour.ID) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(hours) { hour in
                        column(hour)
                            .id(hour.id)
                    }
                }
                .padding(8)
            }
            .scrollIndicators(.hidden)
            .stedeCard()
            .onAppear {
                proxy.scrollTo(selectedID, anchor: .center)
            }
            .onChange(of: selectedID) {
                withAnimation { proxy.scrollTo(selectedID, anchor: .center) }
            }
        }
    }

    private func column(_ hour: WeatherHour) -> some View {
        let isSelected = hour.id == selectedID
        return Button {
            select(hour.id)
        } label: {
            VStack(spacing: 8) {
                Text(hour.id == currentID ? "Jetzt" : WeatherFormat.hourNumber(hour.timestamp))
                    .font(.caption.weight(hour.id == currentID ? .bold : .medium))
                    .foregroundStyle(hour.id == currentID ? AnyShapeStyle(StedeTheme.harborRed) : AnyShapeStyle(.secondary))
                WeatherSymbol(name: hour.symbolName)
                    .font(.title3)
                    .frame(height: 26)
                Text(WeatherFormat.degrees(hour.temperature))
                    .font(.headline)
                    .fontDesign(.rounded)
                    .monospacedDigit()
                if showsRain {
                    Text(rain(hour))
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(StedeTheme.seaTeal)
                }
            }
            .frame(width: 52)
            .padding(.vertical, 10)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(StedeTheme.seaTeal.opacity(0.16))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(StedeCardButtonStyle())
        .foregroundStyle(.primary)
        .accessibilityLabel("\(WeatherFormat.hour(hour.timestamp)), \(WeatherFormat.degrees(hour.temperature).replacingOccurrences(of: "°", with: " Grad")), \(hour.conditionLabel)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Die Regenzeile nur, wenn es an diesem Tag überhaupt regnet — sonst ist sie leerer Platz.
    private var showsRain: Bool { hours.contains { ($0.precipitation ?? 0) >= 0.1 } }

    /// Nur nennenswerter Regen bekommt eine Zahl, sonst bleibt die Zeile leer.
    private func rain(_ hour: WeatherHour) -> String {
        guard let rain = hour.precipitation, rain >= 0.1 else { return " " }
        return "\(WeatherFormat.number(rain, digits: 0 ... 1))"
    }
}

// MARK: - Tagesverlauf

private struct WeatherDayChart: View {
    let hours: [WeatherHour]
    let selectedID: WeatherHour.ID
    let select: (WeatherHour.ID) -> Void
    @State private var scrub: Date?

    var body: some View {
        InfoCard {
            VStack(alignment: .leading, spacing: 8) {
                Chart {
                    ForEach(temperatures, id: \.date) { point in
                        AreaMark(
                            x: .value("Zeit", point.date),
                            yStart: .value("Basis", lowerBound),
                            yEnd: .value("Temperatur", point.value)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [StedeTheme.sunAmber.opacity(0.35), StedeTheme.sunAmber.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        LineMark(x: .value("Zeit", point.date), y: .value("Temperatur", point.value))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(StedeTheme.sunAmber)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                    }

                    RuleMark(x: .value("Auswahl", selectedID))
                        .foregroundStyle(StedeTheme.seaTeal.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))

                    if let point = temperatures.first(where: { $0.date == selectedID }) {
                        PointMark(x: .value("Zeit", point.date), y: .value("Temperatur", point.value))
                            .foregroundStyle(StedeTheme.sunAmber)
                            .symbolSize(90)
                            .annotation(position: .top, spacing: 6) {
                                Text(WeatherFormat.degrees(point.value))
                                    .font(.caption.weight(.bold))
                                    .fontDesign(.rounded)
                                    .monospacedDigit()
                            }
                    }
                }
                .chartYScale(domain: lowerBound ... upperBound)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(WeatherFormat.hourNumber(date))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let degrees = value.as(Double.self) {
                                Text(WeatherFormat.degrees(degrees))
                            }
                        }
                    }
                }
                .chartXSelection(value: $scrub)
                .frame(height: 140)

                if maxRain < 0.1 {
                    Label("Kein Regen erwartet", systemImage: "drop")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(StedeTheme.seaTeal)
                } else {
                    Label("Regen bis \(WeatherFormat.number(maxRain, digits: 0 ... 1)) mm pro Stunde", systemImage: "drop.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(StedeTheme.seaTeal)
                    Chart {
                        ForEach(hours) { hour in
                            BarMark(
                                x: .value("Zeit", hour.timestamp, unit: .hour),
                                y: .value("Regen", hour.precipitation ?? 0)
                            )
                            .foregroundStyle(StedeTheme.seaTeal.gradient)
                            .cornerRadius(3)
                        }
                    }
                    .chartYScale(domain: 0 ... max(maxRain, 1))
                    .chartYAxis(.hidden)
                    .chartXAxis(.hidden)
                    .chartXSelection(value: $scrub)
                    .frame(height: 44)
                }
            }
        }
        .onChange(of: scrub) {
            guard let scrub,
                  let nearest = hours.min(by: { abs($0.timestamp.timeIntervalSince(scrub)) < abs($1.timestamp.timeIntervalSince(scrub)) })
            else { return }
            if nearest.id != selectedID {
                select(nearest.id)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Temperatur- und Regenverlauf")
        .accessibilityValue(accessibilitySummary)
    }

    private var temperatures: [(date: Date, value: Double)] {
        hours.compactMap { hour in hour.temperature.map { (hour.timestamp, $0) } }
    }

    private var lowerBound: Double {
        (temperatures.map(\.value).min() ?? 0).rounded(.down) - 2
    }

    private var upperBound: Double {
        (temperatures.map(\.value).max() ?? 20).rounded(.up) + 3
    }

    private var maxRain: Double {
        hours.compactMap(\.precipitation).max() ?? 0
    }

    private var accessibilitySummary: String {
        let values = temperatures.map(\.value)
        guard let low = values.min(), let high = values.max() else { return "Keine Daten" }
        return "Zwischen \(WeatherFormat.degrees(low)) und \(WeatherFormat.degrees(high)), Regen höchstens \(WeatherFormat.number(maxRain, digits: 0 ... 1)) Millimeter pro Stunde"
    }
}

// MARK: - Details

private struct WeatherDetailGrid: View {
    let hour: WeatherHour
    let summary: WeatherDaySummary

    private let columns = [
        GridItem(.flexible(), spacing: StedeTheme.cardSpacing),
        GridItem(.flexible(), spacing: StedeTheme.cardSpacing),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: StedeTheme.cardSpacing) {
            if let wind = hour.windSpeed {
                WeatherDetailTile(title: "Wind", symbol: "wind", color: StedeTheme.seaTeal,
                                  value: "\(WeatherFormat.number(wind)) km/h",
                                  caption: windCaption) {
                    if let direction = hour.windDirection {
                        // Der Pfeil zeigt, wohin der Wind weht.
                        Image(systemName: "location.north.fill")
                            .font(.title3)
                            .foregroundStyle(StedeTheme.seaTeal)
                            .rotationEffect(.degrees(direction + 180))
                            .accessibilityHidden(true)
                    }
                }
            }

            WeatherDetailTile(title: "Regen", symbol: "drop.fill", color: StedeTheme.iconBlue,
                              value: "\(WeatherFormat.number(hour.precipitation ?? 0, digits: 0 ... 1)) mm",
                              caption: "Tag: \(WeatherFormat.number(summary.precipitationSum, digits: 0 ... 1)) mm")

            WeatherDetailTile(title: "Sonne", symbol: "sun.max.fill", color: StedeTheme.sunAmber,
                              value: "\(WeatherFormat.number(hour.sunshine ?? 0)) min",
                              caption: "Tag: \(WeatherFormat.number(sunshineHours, digits: 0 ... 1)) h")

            if let clouds = hour.cloudCover {
                WeatherDetailTile(title: "Wolken", symbol: "cloud.fill", color: StedeTheme.ink,
                                  value: "\(WeatherFormat.number(clouds)) %",
                                  caption: hour.conditionLabel)
            }

            if let humidity = hour.relativeHumidity {
                WeatherDetailTile(title: "Luftfeuchte", symbol: "humidity.fill", color: StedeTheme.duneGreen,
                                  value: "\(WeatherFormat.number(humidity)) %",
                                  caption: hour.pressureMsl.map { "\(WeatherFormat.number($0)) hPa" })
            }
        }
    }

    private var windCaption: String {
        var parts: [String] = []
        if let direction = hour.windDirection {
            parts.append("aus \(WeatherFormat.compass(direction))")
        }
        if let gust = hour.windGustSpeed {
            parts.append("Böen \(WeatherFormat.number(gust))")
        }
        return parts.joined(separator: " · ")
    }

    private var sunshineHours: Double {
        summary.hours.compactMap(\.sunshine).reduce(0, +) / 60
    }
}

private struct WeatherDetailTile<Accessory: View>: View {
    let title: String
    let symbol: String
    let color: Color
    let value: String
    var caption: String?
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                Spacer(minLength: 4)
                accessory()
            }
            Text(value)
                .font(.title2.weight(.semibold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .stedeCard()
        .accessibilityElement(children: .combine)
    }
}

extension WeatherDetailTile where Accessory == EmptyView {
    init(title: String, symbol: String, color: Color, value: String, caption: String? = nil) {
        self.init(title: title, symbol: symbol, color: color, value: value, caption: caption) { EmptyView() }
    }
}

nonisolated struct WeatherDayOverview: Sendable {
    let minTemperature: Double?
    let maxTemperature: Double?
    let precipitationSum: Double

    init(summary: WeatherDaySummary) {
        minTemperature = summary.minTemperature
        maxTemperature = summary.maxTemperature
        precipitationSum = summary.precipitationSum
    }
}

enum WeatherAtmosphere {
    static func gradient(for hour: WeatherHour) -> LinearGradient {
        LinearGradient(
            colors: colors(for: hour),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var placeholder: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.52, green: 0.70, blue: 0.88),
                Color(red: 0.28, green: 0.46, blue: 0.68),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func colors(for hour: WeatherHour) -> [Color] {
        let night = hour.usesNightPalette
        return switch hour.atmosphere {
        case "clear-day":
            [Color(red: 0.40, green: 0.74, blue: 0.98), Color(red: 0.10, green: 0.42, blue: 0.86)]
        case "clear-night":
            [Color(red: 0.18, green: 0.22, blue: 0.48), Color(red: 0.05, green: 0.07, blue: 0.20)]
        case "partly-cloudy-day":
            [Color(red: 0.52, green: 0.70, blue: 0.88), Color(red: 0.28, green: 0.46, blue: 0.68)]
        case "partly-cloudy-night":
            [Color(red: 0.22, green: 0.28, blue: 0.42), Color(red: 0.10, green: 0.12, blue: 0.22)]
        case "cloudy":
            night
                ? [Color(red: 0.28, green: 0.32, blue: 0.40), Color(red: 0.14, green: 0.16, blue: 0.22)]
                : [Color(red: 0.46, green: 0.54, blue: 0.64), Color(red: 0.30, green: 0.36, blue: 0.46)]
        case "fog":
            [Color(red: 0.48, green: 0.54, blue: 0.58), Color(red: 0.34, green: 0.38, blue: 0.44)]
        case "wind":
            [Color(red: 0.38, green: 0.62, blue: 0.72), Color(red: 0.18, green: 0.40, blue: 0.55)]
        case "rain":
            night
                ? [Color(red: 0.16, green: 0.24, blue: 0.40), Color(red: 0.08, green: 0.12, blue: 0.22)]
                : [Color(red: 0.28, green: 0.42, blue: 0.58), Color(red: 0.14, green: 0.26, blue: 0.42)]
        case "sleet":
            [Color(red: 0.42, green: 0.52, blue: 0.64), Color(red: 0.24, green: 0.32, blue: 0.44)]
        case "snow":
            [Color(red: 0.48, green: 0.60, blue: 0.76), Color(red: 0.28, green: 0.40, blue: 0.58)]
        case "hail":
            [Color(red: 0.40, green: 0.48, blue: 0.58), Color(red: 0.22, green: 0.28, blue: 0.38)]
        case "thunderstorm":
            [Color(red: 0.28, green: 0.20, blue: 0.48), Color(red: 0.10, green: 0.08, blue: 0.22)]
        default:
            night
                ? [Color(red: 0.18, green: 0.22, blue: 0.48), Color(red: 0.05, green: 0.07, blue: 0.20)]
                : [Color(red: 0.40, green: 0.74, blue: 0.98), Color(red: 0.10, green: 0.42, blue: 0.86)]
        }
    }
}

extension View {
    @ViewBuilder
    func weatherHeroChrome(_ enabled: Bool) -> some View {
        if enabled {
            foregroundStyle(.white)
                .environment(\.colorScheme, .dark)
        } else {
            self
        }
    }
}
