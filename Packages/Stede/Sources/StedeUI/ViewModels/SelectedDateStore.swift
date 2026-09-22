import Foundation
import StedeCore

@Observable
final class SelectedDateStore {
    var selectedDate: Date
    /// Letzter Tag mit Daten; `nil` bedeutet keine Obergrenze.
    var latestDate: Date?

    init(date: Date = Date()) {
        selectedDate = IslandTime.startOfDay(date)
    }

    var isToday: Bool {
        IslandTime.calendar.isDate(selectedDate, inSameDayAs: Date())
    }

    var canGoForward: Bool {
        guard let latestDate else { return true }
        return IslandTime.startOfDay(selectedDate) < IslandTime.startOfDay(latestDate)
    }

    var canGoBack: Bool { true }

    func goBack() {
        shift(by: -1)
    }

    func goForward() {
        guard canGoForward else { return }
        shift(by: 1)
    }

    func goToToday() {
        selectedDate = IslandTime.startOfDay(Date())
    }

    func select(_ date: Date) {
        selectedDate = clamped(IslandTime.startOfDay(date))
    }

    func limit(to latest: Date?) {
        latestDate = latest.map(IslandTime.startOfDay)
        selectedDate = clamped(selectedDate)
    }

    private func shift(by days: Int) {
        if let next = IslandTime.calendar.date(byAdding: .day, value: days, to: selectedDate) {
            selectedDate = clamped(IslandTime.startOfDay(next))
        }
    }

    private func clamped(_ date: Date) -> Date {
        guard let latestDate else { return date }
        return min(date, latestDate)
    }
}
