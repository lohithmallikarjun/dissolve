import Foundation

/// Done ÷ due over some period. Skipped days are excluded; today counts only once it's done.
public struct Tally: Equatable, Sendable {
    public var done: Int
    public var due: Int

    public init(done: Int = 0, due: Int = 0) {
        self.done = done
        self.due = due
    }

    public var rate: Double? { due == 0 ? nil : Double(done) / Double(due) }

    public static func + (a: Tally, b: Tally) -> Tally { Tally(done: a.done + b.done, due: a.due + b.due) }
}

/// Statistics over one or more habits. Pure, so it's tested here and shared with widgets.
public enum Stats {
    /// Completion for one habit between two dates (inclusive).
    public static func tally(_ engine: HabitEngine, from: LocalDate, to: LocalDate) -> Tally {
        var tally = Tally()
        let last = min(to, engine.lastDay)
        var day = max(from, engine.habit.startDate)
        while day <= last {
            let version = engine.schedule(on: day)
            if case .timesPerWeek = version.rule {
                // Judge whole weeks: min(done, target) of target; a week still in progress counts only if met.
                let weekStart = day.startOfWeek(firstWeekday: engine.firstWeekday)
                let weekEnd = weekStart.adding(days: 6)
                let span = (0..<7).map { weekStart.adding(days: $0) }
                    .filter { $0 >= engine.habit.startDate && engine.schedule(on: $0) == version }
                    .filter { date in engine.habit.endDate.map { date <= $0 } ?? true }
                if let week = engine.week(containing: day) {
                    let skipped = span.filter { engine.logs[$0]?.isSkipped == true }.count
                    let required = min(week.target, span.count - skipped)
                    let inProgress = weekEnd >= engine.today
                    if required > 0, !(inProgress && week.done < required) {
                        tally = tally + Tally(done: min(week.done, required), due: required)
                    }
                }
                day = min(weekEnd, last).adding(days: 1)
                continue
            }
            switch engine.status(on: day) {
            case .completed:
                if version.isDue(on: day) { tally = tally + Tally(done: 1, due: 1) }
            case .missed:
                tally = tally + Tally(done: 0, due: 1)
            case .partial where day != engine.today:
                tally = tally + Tally(done: 0, due: 1)
            default:
                break
            }
            day = day.adding(days: 1)
        }
        return tally
    }

    public static func tally(_ engines: [HabitEngine], from: LocalDate, to: LocalDate) -> Tally {
        engines.reduce(Tally()) { $0 + tally($1, from: from, to: to) }
    }

    /// Completion per weekday (`1 = Sunday … 7 = Saturday`) for fixed-schedule habits.
    public static func byWeekday(_ engines: [HabitEngine], from: LocalDate, to: LocalDate) -> [Int: Tally] {
        var result: [Int: Tally] = [:]
        for engine in engines {
            var day = max(from, engine.habit.startDate)
            let last = min(to, engine.lastDay)
            while day <= last {
                let version = engine.schedule(on: day)
                if !version.rule.isWeekly {
                    let d = day.weekday
                    switch engine.status(on: day) {
                    case .completed where version.isDue(on: day): result[d, default: Tally()] = result[d, default: Tally()] + Tally(done: 1, due: 1)
                    case .missed: result[d, default: Tally()] = result[d, default: Tally()] + Tally(done: 0, due: 1)
                    case .partial where day != engine.today: result[d, default: Tally()] = result[d, default: Tally()] + Tally(done: 0, due: 1)
                    default: break
                    }
                }
                day = day.adding(days: 1)
            }
        }
        return result
    }

    /// The last `count` weeks, oldest first.
    public static func weekly(_ engines: [HabitEngine], weeks count: Int, today: LocalDate,
                              firstWeekday: Int) -> [(start: LocalDate, tally: Tally)] {
        let thisWeek = today.startOfWeek(firstWeekday: firstWeekday)
        return (0..<count).reversed().map { back in
            let start = thisWeek.adding(days: -7 * back)
            return (start, tally(engines, from: start, to: start.adding(days: 6)))
        }
    }

    /// The last `count` calendar months, oldest first (keyed by the 1st of the month).
    public static func monthly(_ engines: [HabitEngine], months count: Int, today: LocalDate) -> [(month: LocalDate, tally: Tally)] {
        (0..<count).reversed().map { back in
            var year = today.year, month = today.month - back
            while month < 1 { month += 12; year -= 1 }
            let first = LocalDate(year: year, month: month, day: 1)!
            let last = LocalDate(year: year, month: month, day: LocalDate.daysInMonth(year: year, month: month))!
            return (first, tally(engines, from: first, to: last))
        }
    }

    /// Mean strength across habits that existed on each day.
    public static func overallStrength(_ engines: [HabitEngine], from: LocalDate, to: LocalDate) -> [Double] {
        guard from <= to else { return [] }
        let length = from.days(to: to) + 1
        var sums = [Double](repeating: 0, count: length)
        var counts = [Int](repeating: 0, count: length)
        for engine in engines {
            let series = engine.strengthSeries(from: from, to: to)
            for i in 0..<length where from.adding(days: i) >= engine.habit.startDate {
                sums[i] += series[i]
                counts[i] += 1
            }
        }
        return zip(sums, counts).map { $1 == 0 ? 0 : $0 / Double($1) }
    }

    // MARK: Journal

    /// Entries in each of the last `count` months, oldest first.
    public static func entriesPerMonth(_ dates: Set<LocalDate>, months count: Int, today: LocalDate) -> [(month: LocalDate, count: Int)] {
        (0..<count).reversed().map { back in
            var year = today.year, month = today.month - back
            while month < 1 { month += 12; year -= 1 }
            return (LocalDate(year: year, month: month, day: 1)!,
                    dates.filter { $0.year == year && $0.month == month }.count)
        }
    }

    /// Average mood per week (weeks with no mood are nil), oldest first.
    public static func moodByWeek(_ moods: [LocalDate: Int], weeks count: Int, today: LocalDate,
                                  firstWeekday: Int) -> [(start: LocalDate, mood: Double?)] {
        let thisWeek = today.startOfWeek(firstWeekday: firstWeekday)
        return (0..<count).reversed().map { back in
            let start = thisWeek.adding(days: -7 * back)
            let values = (0..<7).compactMap { moods[start.adding(days: $0)] }.filter { $0 > 0 }
            return (start, values.isEmpty ? nil : Double(values.reduce(0, +)) / Double(values.count))
        }
    }
}
