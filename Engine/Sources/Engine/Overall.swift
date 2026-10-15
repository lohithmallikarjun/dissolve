import Foundation

/// Combines several habits into the overall grid.
public enum Overall {
    /// Share of the day's scheduled habits completed (skipped ones excluded), or nil if none were due.
    public static func fraction(on date: LocalDate, engines: [HabitEngine], journaled: Bool? = nil) -> Double? {
        var total = 0.0, count = 0
        for engine in engines {
            if let c = engine.contribution(on: date) {
                total += c
                count += 1
            }
        }
        if let journaled {
            total += journaled ? 1 : 0
            count += 1
        }
        return count == 0 ? nil : total / Double(count)
    }

    public static func cell(on date: LocalDate, engines: [HabitEngine]) -> GridCell {
        GridCell(level: GridCell.level(for: fraction(on: date, engines: engines) ?? 0))
    }

    /// Consecutive days at 100 %. Days with nothing due are neutral, and so is today until it's done.
    public static func perfectDayStreak(engines: [HabitEngine], today: LocalDate, limit: Int = 3660) -> Int {
        var count = 0
        for offset in 0..<limit {
            let day = today.adding(days: -offset)
            guard let f = fraction(on: day, engines: engines) else {
                if engines.allSatisfy({ day < $0.habit.startDate }) { break }
                continue
            }
            if f >= 1 { count += 1 } else if offset == 0 { continue } else { break }
        }
        return count
    }
}

/// A GitHub-style layout: columns are weeks, rows are weekdays, today in the last column.
public struct GridLayout: Sendable {
    public struct MonthLabel: Hashable, Sendable {
        public let column: Int
        public let month: Int
        public let year: Int
    }

    public let weeks: Int
    public let firstWeekday: Int
    public let start: LocalDate
    public let today: LocalDate

    public init(endingAt today: LocalDate, weeks: Int, firstWeekday: Int = 2) {
        self.weeks = weeks
        self.firstWeekday = firstWeekday
        self.today = today
        start = today.startOfWeek(firstWeekday: firstWeekday).adding(days: -7 * (weeks - 1))
    }

    /// nil for days after today.
    public func date(column: Int, row: Int) -> LocalDate? {
        let d = start.adding(days: column * 7 + row)
        return d <= today ? d : nil
    }

    /// `1 = Sunday … 7 = Saturday` for each row.
    public var rowWeekdays: [Int] { (0..<7).map { (firstWeekday - 1 + $0) % 7 + 1 } }

    /// A label at each column where a month begins.
    public var monthLabels: [MonthLabel] {
        (0..<weeks).compactMap { column in
            (0..<7).lazy.compactMap { self.date(column: column, row: $0) }
                .first { $0.day == 1 }
                .map { MonthLabel(column: column, month: $0.month, year: $0.year) }
        }
    }

    public var allDates: [LocalDate] {
        (0..<weeks).flatMap { c in (0..<7).compactMap { date(column: c, row: $0) } }
    }
}
