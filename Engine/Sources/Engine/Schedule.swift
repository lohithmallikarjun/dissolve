import Foundation

/// How often a habit is due.
public enum ScheduleRule: Hashable, Sendable {
    case daily
    /// Weekdays as `1 = Sunday … 7 = Saturday`.
    case weekdays(Set<Int>)
    /// Any days, as long as the weekly count is met. Streaks count in weeks.
    case timesPerWeek(Int)
    /// Every N days, counted from the schedule's `effectiveFrom`.
    case everyNDays(Int)

    public var isWeekly: Bool {
        if case .timesPerWeek = self { true } else { false }
    }

    /// Expected completions per day; drives how fast the strength score moves.
    public var dailyFrequency: Double {
        switch self {
        case .daily: 1
        case .weekdays(let days): Double(min(max(days.count, 1), 7)) / 7
        case .timesPerWeek(let n): Double(min(max(n, 1), 7)) / 7
        case .everyNDays(let n): 1 / Double(max(n, 1))
        }
    }
}

/// A schedule that applies from `effectiveFrom` until the next version starts,
/// so changing a schedule never recalculates old history.
public struct ScheduleVersion: Hashable, Sendable {
    public var rule: ScheduleRule
    public var effectiveFrom: LocalDate

    public init(_ rule: ScheduleRule, from effectiveFrom: LocalDate) {
        self.rule = rule
        self.effectiveFrom = effectiveFrom
    }

    /// Whether a fixed-schedule habit is due on `date`. Weekly habits are "due" every day
    /// (any day can count); their weekly target is judged per week.
    public func isDue(on date: LocalDate) -> Bool {
        switch rule {
        case .daily, .timesPerWeek: true
        case .weekdays(let days): days.contains(date.weekday)
        case .everyNDays(let n):
            n <= 1 || ((effectiveFrom.days(to: date) % n) + n) % n == 0
        }
    }
}

extension LocalDate {
    /// The first day of the week containing this date. `firstWeekday`: 1 = Sunday, 2 = Monday.
    public func startOfWeek(firstWeekday: Int) -> LocalDate {
        adding(days: -((weekday - firstWeekday + 7) % 7))
    }
}
