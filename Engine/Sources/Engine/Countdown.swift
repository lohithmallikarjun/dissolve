import Foundation

/// What a countdown is counting to (or from).
public struct CountdownSpec: Sendable, Equatable {
    /// For all-day countdowns, any time on the target day.
    public var target: Date
    public var isAllDay: Bool
    public var createdAt: Date
    public var repeatsYearly: Bool
    /// "Days since" instead of "days until".
    public var countUp: Bool

    public init(target: Date, isAllDay: Bool, createdAt: Date, repeatsYearly: Bool = false, countUp: Bool = false) {
        self.target = target
        self.isAllDay = isAllDay
        self.createdAt = createdAt
        self.repeatsYearly = repeatsYearly
        self.countUp = countUp
    }
}

public struct CountdownState: Sendable, Equatable {
    /// The moment counted to (next yearly occurrence; for all-day, midnight starting that day).
    public let occurrence: Date
    /// A one-off countdown whose day/time has passed.
    public let hasArrived: Bool
    /// Whole days left (calendar days for all-day), or days since for count-up.
    public let days: Int
    public let weeks: Int
    public let extraDays: Int
    /// 0…1 from the start (creation, or the previous yearly occurrence) to the occurrence.
    public let progress: Double
}

public enum CountdownMath {
    public static func state(_ spec: CountdownSpec, now: Date, calendar: Calendar = .current) -> CountdownState {
        let today = LocalDate(now, calendar: calendar, dayEndsAtHour: 0)

        if spec.countUp {
            let origin = spec.isAllDay ? LocalDate(spec.target, calendar: calendar, dayEndsAtHour: 0).startDate(in: calendar) : spec.target
            let days = max(0, LocalDate(origin, calendar: calendar, dayEndsAtHour: 0).days(to: today))
            return CountdownState(occurrence: origin, hasArrived: true, days: days,
                                  weeks: days / 7, extraDays: days % 7, progress: 0)
        }

        var occurrence = normalized(spec.target, allDay: spec.isAllDay, calendar: calendar)
        var start = spec.createdAt
        if spec.repeatsYearly {
            occurrence = nextOccurrence(of: spec.target, allDay: spec.isAllDay, onOrAfter: now, calendar: calendar)
            let previous = shift(occurrence, years: -1, allDay: spec.isAllDay, calendar: calendar)
            start = max(previous, min(spec.createdAt, occurrence))
        }

        let arrived: Bool
        let days: Int
        if spec.isAllDay {
            let targetDay = LocalDate(occurrence, calendar: calendar, dayEndsAtHour: 0)
            days = max(0, today.days(to: targetDay))
            arrived = today >= targetDay
        } else {
            let seconds = occurrence.timeIntervalSince(now)
            days = max(0, Int((seconds / 86_400).rounded(.down)))
            arrived = seconds <= 0
        }

        let total = occurrence.timeIntervalSince(start)
        let progress = total <= 0 ? 1 : min(max(now.timeIntervalSince(start) / total, 0), 1)
        return CountdownState(occurrence: occurrence, hasArrived: arrived && !spec.repeatsYearly,
                              days: days, weeks: days / 7, extraDays: days % 7,
                              progress: arrived ? 1 : progress)
    }

    /// The next anniversary of `target` that hasn't passed. All-day: today counts as not passed.
    /// A 29 February date falls on 28 February in other years.
    public static func nextOccurrence(of target: Date, allDay: Bool, onOrAfter now: Date, calendar: Calendar = .current) -> Date {
        let year = calendar.component(.year, from: now)
        for y in [year - 1, year, year + 1, year + 2] {
            let candidate = anniversary(of: target, inYear: y, allDay: allDay, calendar: calendar)
            let passed = allDay
                ? LocalDate(candidate, calendar: calendar, dayEndsAtHour: 0) < LocalDate(now, calendar: calendar, dayEndsAtHour: 0)
                : candidate < now
            if !passed { return candidate }
        }
        return anniversary(of: target, inYear: year + 1, allDay: allDay, calendar: calendar)
    }

    static func anniversary(of target: Date, inYear year: Int, allDay: Bool, calendar: Calendar) -> Date {
        var c = calendar.dateComponents([.month, .day, .hour, .minute, .second], from: target)
        c.year = year
        if c.month == 2, c.day == 29, !LocalDate.isLeapYear(year) { c.day = 28 }
        if allDay { c.hour = 0; c.minute = 0; c.second = 0 }
        return calendar.date(from: c) ?? target
    }

    private static func shift(_ date: Date, years: Int, allDay: Bool, calendar: Calendar) -> Date {
        anniversary(of: date, inYear: calendar.component(.year, from: date) + years, allDay: allDay, calendar: calendar)
    }

    private static func normalized(_ date: Date, allDay: Bool, calendar: Calendar) -> Date {
        allDay ? LocalDate(date, calendar: calendar, dayEndsAtHour: 0).startDate(in: calendar) : date
    }
}
