import Foundation
import Testing
@testable import Engine

private var cal: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    return c
}

private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

@Suite("Countdowns")
struct CountdownTests {
    @Test func allDayCountsCalendarDays() {
        let spec = CountdownSpec(target: at(2026, 11, 25, 15), isAllDay: true, createdAt: at(2026, 10, 1))
        let s = CountdownMath.state(spec, now: at(2026, 10, 15, 23, 30), calendar: cal)
        #expect(s.days == 41)
        #expect(s.weeks == 5 && s.extraDays == 6)
        #expect(!s.hasArrived)
        #expect(s.occurrence == at(2026, 11, 25))
        #expect(s.progress > 0.25 && s.progress < 0.3)
    }

    @Test func allDayArrivesOnTheDay() {
        let spec = CountdownSpec(target: at(2026, 10, 15), isAllDay: true, createdAt: at(2026, 9, 1))
        let s = CountdownMath.state(spec, now: at(2026, 10, 15, 9), calendar: cal)
        #expect(s.days == 0 && s.hasArrived && s.progress == 1)
    }

    @Test func timedCountsWholeDaysAndArrivesAtTheMinute() {
        let spec = CountdownSpec(target: at(2026, 10, 17, 9, 30), isAllDay: false, createdAt: at(2026, 10, 1))
        #expect(CountdownMath.state(spec, now: at(2026, 10, 15, 10), calendar: cal).days == 1)  // 47.5 h
        #expect(!CountdownMath.state(spec, now: at(2026, 10, 17, 9, 29), calendar: cal).hasArrived)
        #expect(CountdownMath.state(spec, now: at(2026, 10, 17, 9, 31), calendar: cal).hasArrived)
    }

    @Test func yearlyRollsOverAndNeverArrives() {
        let birthday = CountdownSpec(target: at(1995, 6, 12), isAllDay: true, createdAt: at(2026, 1, 1), repeatsYearly: true)
        let before = CountdownMath.state(birthday, now: at(2026, 6, 11, 20), calendar: cal)
        #expect(before.days == 1 && before.occurrence == at(2026, 6, 12))
        let onTheDay = CountdownMath.state(birthday, now: at(2026, 6, 12, 20), calendar: cal)
        #expect(onTheDay.days == 0 && !onTheDay.hasArrived)
        let after = CountdownMath.state(birthday, now: at(2026, 6, 13, 1), calendar: cal)
        #expect(after.occurrence == at(2027, 6, 12) && after.days == 364)
        #expect(after.progress < 0.01)
    }

    @Test func leapDayBirthday() {
        let spec = CountdownSpec(target: at(2000, 2, 29), isAllDay: true, createdAt: at(2026, 1, 1), repeatsYearly: true)
        #expect(CountdownMath.state(spec, now: at(2026, 2, 1), calendar: cal).occurrence == at(2026, 2, 28))
        #expect(CountdownMath.state(spec, now: at(2028, 2, 1), calendar: cal).occurrence == at(2028, 2, 29))
    }

    @Test func countUpCountsDaysSince() {
        let spec = CountdownSpec(target: at(2026, 9, 1, 18), isAllDay: true, createdAt: at(2026, 9, 1), countUp: true)
        let s = CountdownMath.state(spec, now: at(2026, 10, 15, 8), calendar: cal)
        #expect(s.days == 44 && s.weeks == 6 && s.extraDays == 2)
    }
}

@Suite("Life grid")
struct LifeGridTests {
    private func d(_ s: String) -> LocalDate { LocalDate(s)! }

    @Test func rowsStartOnBirthdays() {
        let grid = LifeGrid(birth: d("1995-06-12"), years: 80, today: d("2026-10-15"))
        #expect(grid.current == LifeGrid.Cell(row: 31, column: 17))  // 125 days after the 31st birthday
        #expect(grid.weeksLived == 31 * 52 + 17)
        #expect(grid.totalWeeks == 4160)
        #expect(grid.weeksRemaining == 4160 - 1629)
        #expect(abs(grid.fractionRemaining - Double(4160 - 1629) / 4160) < 1e-9)
        #expect(grid.age == 31)
        #expect(grid.cell(for: d("2026-06-12")) == LifeGrid.Cell(row: 31, column: 0))
        #expect(grid.cell(for: d("2026-06-11")) == LifeGrid.Cell(row: 30, column: 51))  // day 364 is capped into week 52
    }

    @Test func statesAroundToday() {
        let grid = LifeGrid(birth: d("1995-06-12"), years: 80, today: d("2026-10-15"))
        #expect(grid.state(.init(row: 31, column: 16)) == .past)
        #expect(grid.state(.init(row: 31, column: 17)) == .current)
        #expect(grid.state(.init(row: 31, column: 18)) == .future)
        #expect(grid.state(.init(row: 0, column: 0)) == .past)
    }

    @Test func leapDayBirth() {
        let grid = LifeGrid(birth: d("2000-02-29"), years: 80, today: d("2026-03-01"))
        #expect(grid.birthday(age: 26) == d("2026-02-28"))
        #expect(grid.current == LifeGrid.Cell(row: 26, column: 0))
    }

    @Test func outsideTheLifespan() {
        let grid = LifeGrid(birth: d("1940-01-01"), years: 80, today: d("2026-10-15"))
        #expect(grid.current == nil)
        #expect(grid.weeksLived == grid.totalWeeks)
        #expect(grid.weeksRemaining == 0)
        #expect(grid.cell(for: d("1939-12-31")) == nil)
    }

    @Test func eras() {
        let grid = LifeGrid(birth: d("1995-06-12"), years: 80, today: d("2026-10-15"))
        let eras = [
            LifeEra(name: "School", start: d("2000-06-01"), end: d("2013-05-31"), colorName: "blue"),
            LifeEra(name: "University", start: d("2013-08-01"), end: d("2017-06-30"), colorName: "purple"),
            LifeEra(name: "Career", start: d("2017-07-15"), end: nil, colorName: "green"),
        ]
        #expect(grid.era(for: .init(row: 10, column: 0), in: eras)?.name == "School")
        #expect(grid.era(for: .init(row: 19, column: 20), in: eras)?.name == "University")
        #expect(grid.era(for: .init(row: 31, column: 17), in: eras)?.name == "Career")
        #expect(grid.era(for: .init(row: 2, column: 0), in: eras) == nil)
    }
}
