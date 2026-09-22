import SwiftUI

private struct DatePickerSheet: View {
    @Environment(SelectedDateStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DatePicker(
                "Datum",
                selection: Binding(
                    get: { store.selectedDate },
                    set: { store.select($0) }
                ),
                in: Date.distantPast...(store.latestDate ?? Date.distantFuture),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .padding()
            .navigationTitle("Tag wählen")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            // Tiefwasserblaue Leiste; Schrift und Symbole darin weiß.
            .toolbarBackground(StedeTheme.bar, for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Heute") {
                        store.goToToday()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .environment(\.locale, IslandTime.germanLocale)
    }
}

/// Gemeinsame Hülle: Tageszeile plus Inhalt unter der nativen Leiste.
struct TabScreen<Content: View>: View {
    var title: String = ""
    var showsDateNavigator = true
    /// Ohne Closure bekommt der Screen kein Pull-to-Refresh — sinnvoll für
    /// Inhalte aus dem Bundle, die sich nicht neu laden lassen.
    var refresh: (() async -> Void)?
    @ViewBuilder var content: () -> Content
    @Environment(\.colorScheme) private var colorScheme
    @State private var showPicker = false

    var body: some View {
        // Der Tageswechsel schwebt unten über dem Inhalt, dicht über der
        // Tab-Leiste; `safeAreaPadding` hält die letzte Zeile frei.
        Group {
            if let refresh {
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .refreshable { await refresh() }
            } else {
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Auch ohne Tageswechsel derselbe Abstand nach unten, damit Start und
        // die Tagesansichten gleich weit über der Tab-Leiste enden.
        .safeAreaPadding(.bottom, StedeTheme.SelectionRow.height)
        .overlay(alignment: .bottom) {
            if showsDateNavigator {
                DayNavigator(showPicker: $showPicker)
            }
        }
        // Auf großen Displays bleibt der Inhalt lesbar schmal und zentriert.
        .frame(maxWidth: StedeTheme.readableWidth)
        .frame(maxWidth: .infinity)
        .background {
            StedeTheme.sand.ignoresSafeArea()
        }
        .navigationTitle(title)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        // Tiefwasserblaue Leiste; Schrift und Symbole darin weiß.
        .toolbarBackground(StedeTheme.bar, for: .navigationBar)
        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        #endif
        // Nur anhängen, wenn es den Tageswechsel gibt: zwei `.sheet` an
        // derselben View schließen einander aus, und Gastro bringt ein eigenes mit.
        .modifier(DatePickerSheetModifier(isPresented: $showPicker, isEnabled: showsDateNavigator, colorScheme: colorScheme))
    }
}

private struct DatePickerSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    let isEnabled: Bool
    let colorScheme: ColorScheme

    func body(content: Content) -> some View {
        if isEnabled {
            content.sheet(isPresented: $isPresented) {
                DatePickerSheet()
                    .environment(\.colorScheme, colorScheme)
            }
        } else {
            content
        }
    }
}

/// Tageswechsel im Inhalt statt in der Leiste — gleiche Auswahlzeile wie
/// Hafenwahl und Gastro-Filter.
struct DayNavigator: View {
    @Binding var showPicker: Bool
    @Environment(SelectedDateStore.self) private var store
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        // Schwebende Glasleiste über dem Inhalt statt einer festen Zeile.
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 4) {
                stepButton(systemImage: "chevron.left", enabled: store.canGoBack, label: "Vorheriger Tag") {
                    store.goBack()
                }

                Button {
                    // Ohne stede+ führt der Tipp dorthin, statt einen Picker zu
                    // öffnen, der ohnehin nichts ändern könnte.
                    if store.canChangeDay {
                        showPicker = true
                    } else {
                        navigation.tab = .plus
                    }
                } label: {
                    Label(dayLabel, systemImage: store.canChangeDay ? "calendar" : "lock")
                        .font(.subheadline.weight(.semibold))
                        .fontDesign(.rounded)
                        .monospacedDigit()
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .contentShape(Capsule())
                }
                .buttonStyle(StedeCardButtonStyle())
                .accessibilityLabel(store.canChangeDay ? "Tag wählen, \(dayLabel)" : "Andere Tage mit stede+ freischalten")
                .contextMenu {
                    Button("Heute", systemImage: "sun.max") {
                        store.goToToday()
                    }
                }

                stepButton(systemImage: "chevron.right", enabled: store.canGoForward, label: "Nächster Tag") {
                    store.goForward()
                }
            }
            .foregroundStyle(StedeTheme.ink)
            .padding(.horizontal, 4)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .padding(.bottom, 6)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private func stepButton(
        systemImage: String,
        enabled: Bool,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
                .frame(width: 38, height: 38)
                .contentShape(Circle())
        }
        .buttonStyle(StedeCardButtonStyle())
        .opacity(enabled ? 1 : 0.35)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    /// Kurzform — der volle Wochentag sprengt die Kapsel.
    private var dayLabel: String {
        if store.isToday { return "Heute" }
        return store.selectedDate.formatted(
            Date.FormatStyle(date: .abbreviated, time: .omitted)
                .locale(IslandTime.germanLocale)
        )
    }
}

struct InfoCard<Content: View>: View {
    var isHighlighted = false
    var fill: AnyShapeStyle? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .stedeCard(highlighted: isHighlighted, fill: fill)
    }
}

/// Springt zum Eintrag der aktuellen Uhrzeit. Der zweite Durchlauf korrigiert
/// die Position, sobald der LazyVStack die Zeilen darüber tatsächlich gebaut hat.
@MainActor
func scrollToCurrent(_ id: (some Hashable)?, in proxy: ScrollViewProxy) {
    guard let id else { return }
    proxy.scrollTo(id, anchor: .top)
    Task {
        try? await Task.sleep(for: .milliseconds(250))
        withAnimation(.easeInOut) {
            proxy.scrollTo(id, anchor: .top)
        }
    }
}

/// Kapsel für Aktionen in Karten: Telefon, Website, Karte.
struct StedeActionChip: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(StedeTheme.seaTeal.opacity(0.16), in: Capsule())
            .foregroundStyle(StedeTheme.ink)
    }
}

struct SourceFooter: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)
            .padding(.bottom, 8)
    }
}

struct LoadStateView<Content: View>: View {
    let state: LoadState
    var emptyMessage: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        switch state {
        case .idle, .loading:
            ProgressView("Laden …")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Nicht verfügbar", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            }
        case .empty:
            ContentUnavailableView {
                Label("Keine Daten", systemImage: "calendar.badge.exclamationmark")
            } description: {
                Text(emptyMessage)
            }
        case .loaded:
            content()
        }
    }
}
