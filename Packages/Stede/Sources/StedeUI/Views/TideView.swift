import StedeCore
import Charts
import SwiftUI

struct TideView: View {
    @Environment(SelectedDateStore.self) private var dateStore
    @State private var model = TideViewModel()

    private let columns = [
        GridItem(.flexible(), spacing: StedeTheme.cardSpacing),
        GridItem(.flexible(), spacing: StedeTheme.cardSpacing),
    ]

    var body: some View {
        TabScreen(title: "Gezeiten") {
            await model.load(day: dateStore.selectedDate, force: true)
        } content: {
            LoadStateView(state: model.state, emptyMessage: "Für diesen Tag liegen keine Gezeiten vor.") {
                ScrollView {
                    VStack(alignment: .leading, spacing: StedeTheme.cardSpacing) {
                        // Kurve zuerst, ohne Überschrift; der Wasserstand steht darunter.
                        TideWaterChart(
                            predicted: model.predicted,
                            measured: model.measured,
                            extrema: model.dayEvents,
                            current: dateStore.isToday ? model.currentLevel() : nil
                        )
                        .frame(height: 240)
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .stedeCard(fill: AnyShapeStyle(StedeTheme.seaTeal.opacity(0.12)))
                        .overlay(StedeTheme.cardShape.strokeBorder(StedeTheme.seaTeal.opacity(0.30), lineWidth: 1))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Tidekurve")
                        .accessibilityValue(chartSummary)

                        StedeSectionHeader(
                            title: dateStore.isToday ? "Wasserstand" : "Tidenhub",
                            symbol: "chart.line.uptrend.xyaxis"
                        )
                        TideHero(
                            current: dateStore.isToday ? model.currentLevel() : nil,
                            next: dateStore.isToday ? model.nextEvent : nil,
                            dayEvents: model.dayEvents,
                            timeStyle: timeStyle
                        )

                        if let reason = model.waterUnavailableReason {
                            Label(reason, systemImage: "info.circle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        StedeSectionHeader(title: "Hoch- & Niedrigwasser", symbol: "water.waves")

                        LazyVGrid(columns: columns, spacing: StedeTheme.cardSpacing) {
                            ForEach(model.dayEvents) { event in
                                HomeTile(
                                    title: event.kind.label,
                                    symbol: event.kind == .high ? "arrow.up.to.line" : "arrow.down.to.line",
                                    tint: tint(for: event),
                                    headline: "\(event.timestamp.formatted(timeStyle)) · \(TideFormat.meters(event.height))",
                                    detail: detail(for: event),
                                    compact: true
                                )
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(label(for: event))
                            }
                        }

                        SourceFooter(text: "BSH Gezeiten · PEGELONLINE WSV")
                    }
                    .padding()
                }
                .id("tides-\(IslandTime.isoDate(dateStore.selectedDate))")
            }
        }
        .task(id: dateStore.selectedDate) {
            await model.load(day: dateStore.selectedDate)
        }
    }

    /// Der Chart selbst ist für VoiceOver leere Fläche — die Extrema als Satz.
    private var chartSummary: String {
        guard !model.dayEvents.isEmpty else { return "Keine Daten" }
        return model.dayEvents.map(label(for:)).joined(separator: ". ")
    }

    /// Das nächste Hoch- oder Niedrigwasser steht grün im Raster.
    private func isNext(_ event: TideEvent) -> Bool {
        dateStore.isToday && model.nextEvent?.id == event.id
    }

    /// Hochwasser dunkelblau, Niedrigwasser türkis, das nächste grün.
    private func tint(for event: TideEvent) -> Color {
        if isNext(event) { return StedeTheme.duneGreen }
        return event.kind == .high ? StedeTheme.ink : StedeTheme.seaTeal
    }

    private func detail(for event: TideEvent) -> String {
        var parts: [String] = []
        if isNext(event) { parts.append("Als Nächstes") }
        if let phase = event.phaseLabel { parts.append(phase) }
        return parts.joined(separator: " · ")
    }

    private func label(for event: TideEvent) -> String {
        var parts = [
            "\(event.kind.label) um \(event.timestamp.formatted(timeStyle)) Uhr",
            "\(TideFormat.meters(event.height)) \(TideFormat.reference)",
        ]
        if isNext(event) { parts.append("als Nächstes") }
        if let phase = event.phaseLabel { parts.append(phase) }
        return parts.joined(separator: ", ")
    }

    private var timeStyle: Date.FormatStyle {
        Date.FormatStyle(date: .omitted, time: .shortened, locale: IslandTime.germanLocale, timeZone: IslandTime.timeZone)
    }
}

/// Kopf der Gezeiten im Kachel-Stil: heute der aktuelle Wasserstand mit
/// Tendenz und nächstem Ereignis, an anderen Tagen Höchst- und Tiefstwert.
private struct TideHero: View {
    let current: CurrentTideLevel?
    let next: TideEvent?
    let dayEvents: [TideEvent]
    let timeStyle: Date.FormatStyle
    @ScaledMetric(relativeTo: .caption) private var compactHeight = HomeTileMetrics.compactHeight

    private let tint = StedeTheme.seaTeal

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if let current {
                Label(current.trendLabel ?? "", systemImage: current.trendSymbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .labelStyle(.titleAndIcon)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: compactHeight, alignment: .topLeading)
        .padding(12)
        .background(alignment: .bottomTrailing) {
            Image(systemName: "water.waves")
                .font(.system(size: 110))
                .foregroundStyle(tint.opacity(0.18))
                .offset(x: 18, y: 30)
                .accessibilityHidden(true)
        }
        .stedeCard(fill: AnyShapeStyle(tint.opacity(0.18)))
        .overlay(StedeTheme.cardShape.strokeBorder(tint.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var headline: String {
        if let current { return TideFormat.meters(current.value) }
        let heights = dayEvents.map(\.height)
        guard let high = heights.max(), let low = heights.min() else { return "–" }
        return TideFormat.meters(high - low)
    }

    private var detail: String {
        if let next {
            return "\(next.kind.label) um \(next.timestamp.formatted(timeStyle)) · \(TideFormat.meters(next.height))"
        }
        if current == nil, !dayEvents.isEmpty {
            return "\(TideFormat.reference) · \(dayEvents.count) Hoch- und Niedrigwasser"
        }
        return TideFormat.reference
    }
}

struct TideWaterChart: View {
    let predicted: [WaterMeasurement]
    let measured: [WaterMeasurement]
    let extrema: [TideEvent]
    var current: CurrentTideLevel?

    var body: some View {
        Chart {
            if let current {
                RuleMark(x: .value("Jetzt", current.timestamp))
                    .foregroundStyle(StedeTheme.harborRed.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                PointMark(
                    x: .value("Zeit", current.timestamp),
                    y: .value("m", current.value)
                )
                .foregroundStyle(StedeTheme.harborRed)
                .symbolSize(160)
                .annotation(position: .top, alignment: .trailing, spacing: 10) {
                    Text("Jetzt \(TideFormat.meters(current.value))")
                        .font(.subheadline.weight(.bold))
                        .fontDesign(.rounded)
                        .monospacedDigit()
                        .foregroundStyle(StedeTheme.harborRed)
                        .fixedSize()
                }
            }
            ForEach(predicted) { point in
                LineMark(
                    x: .value("Zeit", point.timestamp),
                    y: .value("m", point.value),
                    series: .value("Serie", "Gezeiten")
                )
                .foregroundStyle(by: .value("Serie", "Gezeiten"))
                .interpolationMethod(.catmullRom)
            }
            ForEach(measured) { point in
                LineMark(
                    x: .value("Zeit", point.timestamp),
                    y: .value("m", point.value),
                    series: .value("Serie", "Pegel")
                )
                .foregroundStyle(by: .value("Serie", "Pegel"))
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            ForEach(extrema) { event in
                PointMark(
                    x: .value("Zeit", event.timestamp),
                    y: .value("m", event.height)
                )
                .foregroundStyle(event.kind == .high ? StedeTheme.ink : StedeTheme.seaTeal)
                .symbolSize(60)
                .annotation(position: event.kind == .high ? .top : .bottom, spacing: 4) {
                    Text(event.kind.shortLabel)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .chartForegroundStyleScale([
            "Gezeiten": StedeTheme.ink,
            "Pegel": StedeTheme.sunAmber,
        ])
        .chartYScale(domain: verticalDomain)
        .chartLegend(position: .top, alignment: .leading, spacing: 8)
        .fontDesign(.rounded)
        .font(.caption2)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(IslandTime.germanLocale)))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let meters = value.as(Double.self) {
                        Text(meters.formatted(
                            .number.precision(.fractionLength(1)).locale(IslandTime.germanLocale)
                        ))
                    }
                }
            }
        }
        .chartYAxisLabel("m \(TideFormat.reference)")
    }

    /// Enger Wertebereich um die Tagesdaten, damit die Tidekurve nicht flach wirkt.
    private var verticalDomain: ClosedRange<Double> {
        let values = predicted.map(\.value) + measured.map(\.value) + [current?.value].compactMap { $0 }
        guard let low = values.min(), let high = values.max(), high > low else {
            return 0 ... 10
        }
        let padding = max((high - low) * 0.15, 0.2)
        return (low - padding) ... (high + padding)
    }
}
