import Foundation

/// A calendar day with no time or time zone, stored as `yyyy-MM-dd`.
///
/// Habit logs and journal entries are keyed by `LocalDate`, never by a timestamp,
/// so a log made at 23:50 in Pune still means the same day after flying to London.
public struct LocalDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init?(year: Int, month: Int, day: Int) {
        guard (1...12).contains(month),
              (1...Self.daysInMonth(year: year, month: month)).contains(day)
        else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses `yyyy-MM-dd`.
    public init?(_ string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2])
        else { return nil }
        self.init(year: y, month: m, day: d)
    }

    /// Days since 1970-01-01 (which is day 0).
    public init(dayNumber: Int) {
        let (y, m, d) = Self.civil(fromDays: dayNumber)
        year = y
        month = m
        day = d
    }

    /// The day a moment belongs to, given the "day ends at" setting.
    ///
    /// With `dayEndsAtHour = 3` (the default), 02:30 on the 15th still counts for the 14th.
    public init(_ date: Date, calendar: Calendar = .current, dayEndsAtHour: Int = 3) {
        let shifted = calendar.date(byAdding: .hour, value: -dayEndsAtHour, to: date) ?? date
        let c = calendar.dateComponents([.year, .month, .day], from: shifted)
        year = c.year!
        month = c.month!
        day = c.day!
    }

    public var description: String {
        "\(Self.pad(year, 4))-\(Self.pad(month, 2))-\(Self.pad(day, 2))"
    }

    /// `yyyy-MM`, used for monthly sync log files.
    public var monthKey: String { "\(Self.pad(year, 4))-\(Self.pad(month, 2))" }

    /// Days since 1970-01-01.
    public var dayNumber: Int { Self.days(fromCivil: year, month, day) }

    /// 1 = Sunday … 7 = Saturday, matching `Calendar.component(.weekday, …)`.
    public var weekday: Int { ((dayNumber % 7 + 7) % 7 + 4) % 7 + 1 }

    public func adding(days: Int) -> LocalDate { LocalDate(dayNumber: dayNumber + days) }

    public func days(to other: LocalDate) -> Int { other.dayNumber - dayNumber }

    /// Midnight at the start of this day in `calendar`'s time zone.
    public func startDate(in calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool { lhs.dayNumber < rhs.dayNumber }

    public static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    public static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: isLeapYear(year) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    // Howard Hinnant's days_from_civil / civil_from_days: exact, branch-light,
    // and independent of Calendar, so grids of 365+ cells stay cheap.
    private static func days(fromCivil year: Int, _ month: Int, _ day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    private static func civil(fromDays days: Int) -> (Int, Int, Int) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (m <= 2 ? y + 1 : y, m, d)
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let s = String(value)
        return s.count >= width ? s : String(repeating: "0", count: width - s.count) + s
    }
}

extension LocalDate: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let value = LocalDate(string) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Expected yyyy-MM-dd, got \(string)")
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
