import Foundation
import Testing
@testable import Engine

@Suite("LocalDate")
struct LocalDateTests {
    private var kolkata: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        kolkata.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    @Test func parsesAndFormats() throws {
        let d = try #require(LocalDate("2026-03-07"))
        #expect(d.year == 2026 && d.month == 3 && d.day == 7)
        #expect(d.description == "2026-03-07")
        #expect(d.monthKey == "2026-03")
    }

    @Test(arguments: ["2026-02-29", "2026-13-01", "2026-00-10", "2026-4-01", "26-04-01", "2026-04-31", "", "abcd-ef-gh"])
    func rejectsInvalid(_ string: String) {
        #expect(LocalDate(string) == nil)
    }

    @Test func leapDayIsValid() {
        #expect(LocalDate("2028-02-29") != nil)
        #expect(LocalDate("2000-02-29") != nil)
        #expect(LocalDate("1900-02-29") == nil)
    }

    @Test func epochIsDayZero() {
        #expect(LocalDate("1970-01-01")!.dayNumber == 0)
        #expect(LocalDate(dayNumber: 0).description == "1970-01-01")
        #expect(LocalDate(dayNumber: -1).description == "1969-12-31")
    }

    @Test func dayNumberRoundTripsOverCenturies() {
        for n in stride(from: -200_000, through: 200_000, by: 37) {
            #expect(LocalDate(dayNumber: n).dayNumber == n)
        }
    }

    @Test func dayNumberMatchesFoundation() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let start = utc.date(from: DateComponents(year: 1899, month: 12, day: 25))!
        for offset in stride(from: 0, to: 60_000, by: 11) {
            let day = utc.date(byAdding: .day, value: offset, to: start)!
            let c = utc.dateComponents([.year, .month, .day, .weekday], from: day)
            let local = LocalDate(year: c.year!, month: c.month!, day: c.day!)!
            #expect(local.dayNumber == Int((day.timeIntervalSince1970 / 86_400).rounded(.down)))
            #expect(local.weekday == c.weekday!)
        }
    }

    @Test func addingCrossesMonthsAndLeapYears() {
        let d = LocalDate("2028-02-28")!
        #expect(d.adding(days: 1).description == "2028-02-29")
        #expect(d.adding(days: 2).description == "2028-03-01")
        #expect(LocalDate("2026-12-31")!.adding(days: 1).description == "2027-01-01")
        #expect(LocalDate("2026-01-01")!.adding(days: -1).description == "2025-12-31")
        #expect(LocalDate("2026-01-01")!.days(to: LocalDate("2027-01-01")!) == 365)
    }

    @Test func weekdayOfKnownDates() {
        #expect(LocalDate("2026-10-15")!.weekday == 5) // Thursday
        #expect(LocalDate("2000-01-01")!.weekday == 7) // Saturday
        #expect(LocalDate("1969-12-28")!.weekday == 1) // Sunday
    }

    @Test func ordering() {
        let a = LocalDate("2026-01-31")!, b = LocalDate("2026-02-01")!
        #expect(a < b)
        #expect([b, a].sorted() == [a, b])
    }

    @Test func lateCheckOffCountsForPreviousDay() {
        let lateNight = date(2026, 10, 15, 2, 30)
        #expect(LocalDate(lateNight, calendar: kolkata, dayEndsAtHour: 4).description == "2026-10-14")
        #expect(LocalDate(lateNight, calendar: kolkata, dayEndsAtHour: 0).description == "2026-10-15")
        #expect(LocalDate(lateNight, calendar: kolkata, dayEndsAtHour: 3).description == "2026-10-14")
    }

    @Test func dayStartsAtCutoff() {
        #expect(LocalDate(date(2026, 10, 15, 4, 0), calendar: kolkata, dayEndsAtHour: 4).description == "2026-10-15")
        #expect(LocalDate(date(2026, 10, 15, 3, 59), calendar: kolkata, dayEndsAtHour: 4).description == "2026-10-14")
    }

    @Test func dayEndsHandlesNewYear() {
        let d = date(2027, 1, 1, 1, 0)
        #expect(LocalDate(d, calendar: kolkata, dayEndsAtHour: 4).description == "2026-12-31")
    }

    @Test func codableUsesPlainString() throws {
        let d = LocalDate("2026-10-15")!
        let json = try JSONEncoder().encode(["date": d])
        #expect(String(decoding: json, as: UTF8.self) == #"{"date":"2026-10-15"}"#)
        let back = try JSONDecoder().decode([String: LocalDate].self, from: json)
        #expect(back["date"] == d)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([String: LocalDate].self, from: Data(#"{"date":"2026-02-30"}"#.utf8))
        }
    }

    @Test func startDateIsLocalMidnight() {
        let start = LocalDate("2026-10-15")!.startDate(in: kolkata)
        let c = kolkata.dateComponents([.year, .month, .day, .hour, .minute], from: start)
        #expect(c.year == 2026 && c.month == 10 && c.day == 15 && c.hour == 0 && c.minute == 0)
    }
}
