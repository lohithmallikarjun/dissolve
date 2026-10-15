import Foundation

public enum HabitKind: String, Sendable, CaseIterable, Codable {
    /// Done / not done.
    case binary
    /// Target + unit, e.g. 8 glasses. Partial progress counts.
    case quantity
    /// Minutes.
    case timed
    /// Stay at or under the target, e.g. ≤ 2 coffees.
    case limit
}

public struct HabitDefinition: Sendable {
    public var kind: HabitKind
    public var target: Double
    /// The first day the habit counts.
    public var startDate: LocalDate
    /// The day it was archived; nothing after it counts.
    public var endDate: LocalDate?
    public var schedules: [ScheduleVersion]

    public init(kind: HabitKind, target: Double = 1, startDate: LocalDate,
                endDate: LocalDate? = nil, schedules: [ScheduleVersion]) {
        self.kind = kind
        self.target = target
        self.startDate = startDate
        self.endDate = endDate
        self.schedules = schedules.sorted { $0.effectiveFrom < $1.effectiveFrom }
    }
}

/// One day's record. At most one per habit per day.
public struct DayLog: Hashable, Sendable {
    public var value: Double
    public var isSkipped: Bool

    public init(value: Double = 0, isSkipped: Bool = false) {
        self.value = value
        self.isSkipped = isSkipped
    }
}

public enum DayStatus: Sendable, Equatable {
    case completed
    case partial
    /// Planned rest: neutral for streaks.
    case skipped
    case missed
    case notScheduled
    /// Today, not done yet.
    case pending
}

public struct Streak: Equatable, Sendable {
    public enum Unit: Sendable { case days, weeks }
    public var count: Int
    public var unit: Unit

    public init(_ count: Int, _ unit: Unit) {
        self.count = count
        self.unit = unit
    }
}

/// A grid cell's shading.
public struct GridCell: Equatable, Sendable {
    /// 0 (none) … 4 (100 %+).
    public var level: Int
    public var isSkipped: Bool

    public init(level: Int, isSkipped: Bool = false) {
        self.level = level
        self.isSkipped = isSkipped
    }

    public static let empty = GridCell(level: 0)

    /// Level for a completion fraction: 0 · 1–33 % · 34–66 % · 67–99 % · 100 %+.
    public static func level(for fraction: Double) -> Int {
        guard fraction > 0 else { return 0 }
        if fraction >= 1 { return 4 }
        let percent = Int((fraction * 100).rounded())
        switch percent {
        case ...33: return 1
        case 34...66: return 2
        default: return 3
        }
    }
}

/// Pure habit maths: day status, streaks, strength score, grid shading.
public struct HabitEngine: Sendable {
    public let habit: HabitDefinition
    public let logs: [LocalDate: DayLog]
    public let today: LocalDate
    public let firstWeekday: Int

    private var units: [Unit] = []

    public init(habit: HabitDefinition, logs: [LocalDate: DayLog], today: LocalDate, firstWeekday: Int = 2) {
        self.habit = habit
        self.logs = logs
        self.today = today
        self.firstWeekday = firstWeekday
        units = makeUnits()
    }

    /// The last day that counts: today, or the archive day.
    public var lastDay: LocalDate { min(today, habit.endDate ?? today) }

    public func schedule(on date: LocalDate) -> ScheduleVersion {
        habit.schedules.last { $0.effectiveFrom <= date }
            ?? habit.schedules.first
            ?? ScheduleVersion(.daily, from: habit.startDate)
    }

    public func isActive(on date: LocalDate) -> Bool {
        date >= habit.startDate && date <= lastDay
    }

    public func value(on date: LocalDate) -> Double { logs[date]?.value ?? 0 }

    /// 0…1. Limit habits: 1 while at or under the target, else 0.
    public func progress(on date: LocalDate) -> Double {
        let value = value(on: date)
        switch habit.kind {
        case .binary:
            return value >= 1 ? 1 : 0
        case .quantity, .timed:
            guard habit.target > 0 else { return value > 0 ? 1 : 0 }
            return min(value / habit.target, 1)
        case .limit:
            return value <= habit.target ? 1 : 0
        }
    }

    public func status(on date: LocalDate) -> DayStatus {
        guard isActive(on: date) else { return .notScheduled }
        if logs[date]?.isSkipped == true { return .skipped }
        let version = schedule(on: date)
        let p = progress(on: date)
        if habit.kind == .limit {
            guard version.isDue(on: date) else { return .notScheduled }
            return p >= 1 ? .completed : .missed
        }
        if version.rule.isWeekly {
            if p >= 1 { return .completed }
            if p > 0 { return .partial }
            return date == today ? .pending : .notScheduled
        }
        guard version.isDue(on: date) else { return p >= 1 ? .completed : .notScheduled }
        if p >= 1 { return .completed }
        if p > 0 { return .partial }
        return date == today ? .pending : .missed
    }

    public func cell(on date: LocalDate) -> GridCell {
        switch status(on: date) {
        case .skipped: GridCell(level: 0, isSkipped: true)
        case .notScheduled where progress(on: date) == 0 || habit.kind == .limit: .empty
        case .missed where habit.kind == .limit: .empty
        default: GridCell(level: GridCell.level(for: progress(on: date)))
        }
    }

    /// This day's share for the overall grid, or nil when the habit doesn't count that day.
    public func contribution(on date: LocalDate) -> Double? {
        guard isActive(on: date), logs[date]?.isSkipped != true else { return nil }
        let version = schedule(on: date)
        if version.rule.isWeekly {
            let p = progress(on: date)
            return p > 0 ? p : nil
        }
        return version.isDue(on: date) ? progress(on: date) : nil
    }

    /// Completions so far and the target for the week containing `date` (weekly habits).
    public func week(containing date: LocalDate) -> (done: Int, target: Int)? {
        guard case .timesPerWeek(let n) = schedule(on: date).rule else { return nil }
        let start = date.startOfWeek(firstWeekday: firstWeekday)
        let done = (0..<7).map { start.adding(days: $0) }
            .filter { isActive(on: $0) && progress(on: $0) >= 1 }.count
        return (done, n)
    }

    // MARK: Streaks and strength

    public var streakUnit: Streak.Unit {
        schedule(on: lastDay).rule.isWeekly ? .weeks : .days
    }

    /// Consecutive completed units ending now. Skipped days, unscheduled days, today while
    /// still open, and a week whose target is still reachable neither break nor extend it.
    public var currentStreak: Streak {
        var count = 0
        for unit in units.reversed() {
            switch unit.outcome {
            case .hit: count += 1
            case .neutral: continue
            case .miss: return Streak(count, streakUnit)
            }
        }
        return Streak(count, streakUnit)
    }

    public var bestStreak: Streak {
        var best = 0, run = 0
        for unit in units {
            switch unit.outcome {
            case .hit:
                run += 1
                best = max(best, run)
            case .neutral: continue
            case .miss: run = 0
            }
        }
        return Streak(best, streakUnit)
    }

    /// Loop-style exponential smoothing, 0…1. With a daily habit, a day's weight halves
    /// every 13 days; less frequent habits decay more slowly (half-life 13/√frequency days).
    public var strength: Double {
        var score = 0.0
        for unit in units {
            guard let value = unit.value else { continue }
            score = score * unit.multiplier + value * (1 - unit.multiplier)
        }
        return score
    }

    // MARK: Units

    private enum Outcome { case hit, miss, neutral }

    private struct Unit {
        var outcome: Outcome
        /// Contribution to strength; nil = ignored.
        var value: Double?
        var multiplier: Double
        /// The day this unit is settled (its day, or the last day of its week span).
        var end: LocalDate = LocalDate(dayNumber: 0)
    }

    /// Strength as it stood at the end of each day from `from` through `to`.
    public func strengthSeries(from: LocalDate, to: LocalDate) -> [Double] {
        guard from <= to else { return [] }
        var score = 0.0
        var index = 0
        var result: [Double] = []
        result.reserveCapacity(from.days(to: to) + 1)
        var day = from
        while day <= to {
            while index < units.count, units[index].end <= day {
                if let value = units[index].value {
                    score = score * units[index].multiplier + value * (1 - units[index].multiplier)
                }
                index += 1
            }
            result.append(score)
            day = day.adding(days: 1)
        }
        return result
    }

    private static func multiplier(dailyFrequency f: Double, unitDays: Double) -> Double {
        // Half-life in days is 13/√f; a unit spans `unitDays` days of expected occurrences.
        pow(0.5, unitDays * f.squareRoot() / 13)
    }

    /// Days (fixed schedules) and weeks (weekly schedules) from the start to today.
    private func makeUnits() -> [Unit] {
        var result: [Unit] = []
        var day = habit.startDate
        let end = lastDay
        while day <= end {
            let version = schedule(on: day)
            if case .timesPerWeek(let perWeek) = version.rule {
                let weekEnd = day.startOfWeek(firstWeekday: firstWeekday).adding(days: 6)
                var done = 0, skipped = 0, possible = 0
                var cursor = day
                // Days of this week under this schedule version (the whole week, even future days).
                while cursor <= weekEnd, schedule(on: cursor) == version,
                      habit.endDate.map({ cursor <= $0 }) ?? true {
                    possible += 1
                    if cursor <= end {
                        if logs[cursor]?.isSkipped == true { skipped += 1 } else if progress(on: cursor) >= 1 { done += 1 }
                    }
                    cursor = cursor.adding(days: 1)
                }
                let required = min(perWeek, possible - skipped)
                let isCurrent = cursor > end && end == today
                let m = Self.multiplier(dailyFrequency: version.rule.dailyFrequency, unitDays: 7)
                let settled = min(cursor.adding(days: -1), end)
                let before = result.count
                if required <= 0 {
                    result.append(Unit(outcome: .neutral, value: nil, multiplier: m))
                } else if done >= required {
                    result.append(Unit(outcome: .hit, value: 1, multiplier: m))
                } else if isCurrent {
                    let remaining = today.days(to: min(weekEnd, cursor.adding(days: -1))) + 1
                    let todayDone = progress(on: today) >= 1 ? 1 : 0
                    let reachable = done + (remaining - todayDone) >= required
                    result.append(reachable
                        ? Unit(outcome: .neutral, value: nil, multiplier: m)
                        : Unit(outcome: .miss, value: Double(done) / Double(required), multiplier: m))
                } else {
                    result.append(Unit(outcome: .miss, value: Double(done) / Double(required), multiplier: m))
                }
                for i in before..<result.count { result[i].end = settled }
                day = cursor
                continue
            }

            let f = version.rule.dailyFrequency
            let m = Self.multiplier(dailyFrequency: f, unitDays: 1 / f)
            switch status(on: day) {
            case .completed where version.isDue(on: day):
                result.append(Unit(outcome: .hit, value: 1, multiplier: m, end: day))
            case .partial where day != today:
                result.append(Unit(outcome: .miss, value: progress(on: day), multiplier: m, end: day))
            case .missed:
                result.append(Unit(outcome: .miss, value: 0, multiplier: m, end: day))
            default:
                break
            }
            day = day.adding(days: 1)
        }
        return result
    }
}
