import Foundation
import StedeCore

@Observable
final class SelectedDateStore {
    var selectedDate: Date
    /// Letzter Tag mit Daten; `nil` bedeutet keine Obergrenze.
    var latestDate: Date?
    /// Mit dem Baustein `plus` und ohne Kauf bleibt die App auf dem heutigen Tag stehen.
    var canChangeDay = true

    init(date: Date = Date()) {
        selectedDate = IslandTime.startOfDay(date)
    }

    var isToday: Bool {
        IslandTime.calendar.isDate(selectedDate, inSameDayAs: Date())
    }

    var canGoForward: Bool {
        guard canChangeDay else { return false }
        guard let latestDate else { return true }
        return IslandTime.startOfDay(selectedDate) < IslandTime.startOfDay(latestDate)
    }

    var canGoBack: Bool { canChangeDay }

    func goBack() {
        guard canChangeDay else { return }
        shift(by: -1)
    }

    func goForward() {
        guard canGoForward else { return }
        shift(by: 1)
    }

    /// Montag der Woche, in der der gewählte Tag liegt.
    var weekStart: Date {
        var calendar = IslandTime.calendar
        calendar.firstWeekday = 2
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)
        return calendar.date(from: components).map(IslandTime.startOfDay) ?? IslandTime.startOfDay(selectedDate)
    }

    var weekEnd: Date {
        IslandTime.calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
    }

    var canGoForwardWeek: Bool {
        guard let latestDate else { return true }
        return weekEnd <= IslandTime.startOfDay(latestDate).addingTimeInterval(86_400)
    }

    func goBackWeek() { shift(by: -7) }

    func goForwardWeek() {
        guard canGoForwardWeek else { return }
        shift(by: 7)
    }

    func goToToday() {
        selectedDate = IslandTime.startOfDay(Date())
    }

    func select(_ date: Date) {
        guard canChangeDay else { return }
        selectedDate = clamped(IslandTime.startOfDay(date))
    }

    /// Nach einem Widerruf oder abgelaufenen Abo zurück auf heute.
    func lockToToday() {
        canChangeDay = false
        selectedDate = IslandTime.startOfDay(Date())
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
