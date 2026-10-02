import Foundation

/// Wann ein Termin als vorbei gilt — für das Ausblenden in Kalender und Gruppenliste
/// und die Pille „vorbei“: mit Ende ab dem Ende, ganztägig ab Mitternacht danach,
/// ohne Ende zwei Stunden nach Beginn (sonst verschwände er schon in der ersten Minute).
public nonisolated enum EventTiming {
    public static let assumedDuration: TimeInterval = 2 * 3600

    public static func end(starts: Date, ends: Date?, allDay: Bool) -> Date {
        if let ends, ends > starts { return ends }
        if allDay { return IslandTime.day(IslandTime.startOfDay(starts), adding: 1) }
        return starts.addingTimeInterval(assumedDuration)
    }

    public static func isOver(starts: Date, ends: Date?, allDay: Bool, now: Date = Date()) -> Bool {
        end(starts: starts, ends: ends, allDay: allDay) <= now
    }
}

public extension CommunityEvent {
    var isOver: Bool { EventTiming.isOver(starts: startsAt, ends: endsAt, allDay: allDay) }
}

public extension PublicEvent {
    var isOver: Bool { EventTiming.isOver(starts: startsAt, ends: endsAt, allDay: allDay ?? false) }
}

public extension StedeEvent {
    /// Roh-Termine der Stadt: ohne Uhrzeit (00:00) ganztägig.
    var isOver: Bool {
        guard let time else { return false }
        return EventTiming.isOver(starts: time, ends: endTime, allDay: time == IslandTime.startOfDay(time))
    }
}
