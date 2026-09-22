import Foundation

public nonisolated enum IslandTime: Sendable {
    public static let timeZone = TimeZone(identifier: "Europe/Berlin")!

    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "de_DE")
        return calendar
    }

    public static let germanLocale = Locale(identifier: "de_DE")

    public static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    public static func endOfDay(_ date: Date) -> Date {
        calendar.date(byAdding: .day, value: 1, to: startOfDay(date)) ?? date
    }

    public static func isoDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    public static func date(bySettingHour hour: Int, of day: Date) -> Date {
        calendar.date(
            bySettingHour: hour,
            minute: 0,
            second: 0,
            of: startOfDay(day)
        ) ?? startOfDay(day)
    }

    public static func date(fromISO text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }

    public static func isSameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        calendar.isDate(lhs, inSameDayAs: rhs)
    }

}
