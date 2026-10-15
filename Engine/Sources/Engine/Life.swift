import Foundation

/// A coloured band on the life grid ("University", "Career").
public struct LifeEra: Hashable, Sendable, Codable {
    public var name: String
    public var start: LocalDate
    /// nil = still going.
    public var end: LocalDate?
    public var colorName: String

    public init(name: String, start: LocalDate, end: LocalDate?, colorName: String) {
        self.name = name
        self.start = start
        self.end = end
        self.colorName = colorName
    }
}

/// "Life in Weeks": one row per year of age, 52 columns, each row starting on a birthday.
public struct LifeGrid: Sendable {
    public static let weeksPerYear = 52

    public let birth: LocalDate
    public let years: Int
    public let today: LocalDate

    public init(birth: LocalDate, years: Int, today: LocalDate) {
        self.birth = birth
        self.years = max(1, years)
        self.today = today
    }

    public struct Cell: Hashable, Sendable {
        public let row: Int
        public let column: Int

        public init(row: Int, column: Int) {
            self.row = row
            self.column = column
        }
    }

    /// The birthday that starts row `age`. 29 February → 28 February in other years.
    public func birthday(age: Int) -> LocalDate {
        let year = birth.year + age
        return LocalDate(year: year, month: birth.month, day: birth.day)
            ?? LocalDate(year: year, month: birth.month, day: 28)!
    }

    /// The cell containing `date`, or nil before birth / after the lifespan.
    public func cell(for date: LocalDate) -> Cell? {
        guard date >= birth else { return nil }
        var age = date.year - birth.year
        if birthday(age: age) > date { age -= 1 }
        guard age < years else { return nil }
        let column = min(birthday(age: age).days(to: date) / 7, Self.weeksPerYear - 1)
        return Cell(row: age, column: column)
    }

    /// The current week (pulses on the grid).
    public var current: Cell? { cell(for: today) }

    public var totalWeeks: Int { years * Self.weeksPerYear }

    /// Weeks fully lived before the current one.
    public var weeksLived: Int {
        guard today >= birth else { return 0 }
        guard let current else { return totalWeeks }
        return current.row * Self.weeksPerYear + current.column
    }

    public var weeksRemaining: Int { totalWeeks - weeksLived }
    public var fractionRemaining: Double { Double(weeksRemaining) / Double(totalWeeks) }

    /// First day of a cell's week.
    public func startDate(_ cell: Cell) -> LocalDate {
        birthday(age: cell.row).adding(days: cell.column * 7)
    }

    public enum State: Sendable { case past, current, future }

    public func state(_ cell: Cell) -> State {
        guard let current else { return today >= birth ? .past : .future }
        if cell == current { return .current }
        return (cell.row, cell.column) < (current.row, current.column) ? .past : .future
    }

    /// The era a week falls in (the latest-starting one if they overlap).
    public func era(for cell: Cell, in eras: [LifeEra]) -> LifeEra? {
        let date = startDate(cell)
        let weekEnd = date.adding(days: 6)
        return eras
            .filter { $0.start <= weekEnd && ($0.end.map { $0 >= date } ?? true) }
            .max { $0.start < $1.start }
    }

    /// Whole years of age today.
    public var age: Int { current?.row ?? (today >= birth ? years : 0) }
}
