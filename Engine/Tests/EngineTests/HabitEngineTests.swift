import Foundation
import Testing
@testable import Engine

private func d(_ s: String) -> LocalDate { LocalDate(s)! }

/// Builds logs from "yyyy-MM-dd": value pairs; negative value = skipped.
private func logs(_ pairs: [(String, Double)]) -> [LocalDate: DayLog] {
    Dictionary(uniqueKeysWithValues: pairs.map { (d($0.0), $0.1 < 0 ? DayLog(isSkipped: true) : DayLog(value: $0.1)) })
}

private func engine(
    _ kind: HabitKind = .binary, target: Double = 1, start: String = "2026-10-01",
    end: String? = nil, schedules: [ScheduleVersion]? = nil, logs: [LocalDate: DayLog],
    today: String = "2026-10-15"
) -> HabitEngine {
    HabitEngine(
        habit: HabitDefinition(
            kind: kind, target: target, startDate: d(start), endDate: end.map(d),
            schedules: schedules ?? [ScheduleVersion(.daily, from: d(start))]),
        logs: logs, today: d(today), firstWeekday: 2)
}

/// Every day from `from` through `to` with value 1.
private func streakDays(_ from: String, _ to: String) -> [(String, Double)] {
    let a = d(from), b = d(to)
    return (0...a.days(to: b)).map { (a.adding(days: $0).description, 1) }
}

@Suite("Schedules")
struct ScheduleTests {
    @Test func weekdaysAndEveryN() {
        let weekdays = ScheduleVersion(.weekdays([2, 4, 6]), from: d("2026-10-01"))
        #expect(weekdays.isDue(on: d("2026-10-12")))   // Monday
        #expect(!weekdays.isDue(on: d("2026-10-13")))  // Tuesday
        let everyThree = ScheduleVersion(.everyNDays(3), from: d("2026-10-01"))
        #expect(everyThree.isDue(on: d("2026-10-01")))
        #expect(!everyThree.isDue(on: d("2026-10-02")))
        #expect(everyThree.isDue(on: d("2026-10-04")))
        #expect(everyThree.isDue(on: d("2026-09-28")))  // before anchor, still on the cadence
    }

    @Test func startOfWeek() {
        #expect(d("2026-10-15").startOfWeek(firstWeekday: 2) == d("2026-10-12"))  // Thu → Mon
        #expect(d("2026-10-15").startOfWeek(firstWeekday: 1) == d("2026-10-11"))  // Thu → Sun
        #expect(d("2026-10-12").startOfWeek(firstWeekday: 2) == d("2026-10-12"))
    }

    @Test func scheduleChangeDoesNotRewriteHistory() {
        // Daily until the 10th, then Mondays only. The 7th (Wed) stays a missed daily day.
        let e = engine(schedules: [
            ScheduleVersion(.daily, from: d("2026-10-01")),
            ScheduleVersion(.weekdays([2]), from: d("2026-10-10")),
        ], logs: logs([]))
        #expect(e.status(on: d("2026-10-07")) == .missed)
        #expect(e.status(on: d("2026-10-14")) == .notScheduled)  // Wed after the change
        #expect(e.status(on: d("2026-10-12")) == .missed)        // Monday
    }
}

@Suite("Day status")
struct StatusTests {
    @Test func binary() {
        let e = engine(logs: logs([("2026-10-13", 1), ("2026-10-14", -1)]))
        #expect(e.status(on: d("2026-10-13")) == .completed)
        #expect(e.status(on: d("2026-10-14")) == .skipped)
        #expect(e.status(on: d("2026-10-12")) == .missed)
        #expect(e.status(on: d("2026-10-15")) == .pending)
        #expect(e.status(on: d("2026-10-16")) == .notScheduled)  // future
        #expect(e.status(on: d("2026-09-30")) == .notScheduled)  // before start
    }

    @Test func quantityPartial() {
        let e = engine(.quantity, target: 8, logs: logs([("2026-10-14", 4), ("2026-10-13", 9)]))
        #expect(e.status(on: d("2026-10-14")) == .partial)
        #expect(e.progress(on: d("2026-10-14")) == 0.5)
        #expect(e.status(on: d("2026-10-13")) == .completed)
        #expect(e.progress(on: d("2026-10-13")) == 1)
    }

    @Test func limitSucceedsByStayingUnder() {
        let e = engine(.limit, target: 2, logs: logs([("2026-10-14", 3), ("2026-10-13", 2)]))
        #expect(e.status(on: d("2026-10-13")) == .completed)
        #expect(e.status(on: d("2026-10-14")) == .missed)
        #expect(e.status(on: d("2026-10-12")) == .completed)  // nothing logged = 0
        #expect(e.status(on: d("2026-10-15")) == .completed)  // still under today
        #expect(e.cell(on: d("2026-10-14")) == .empty)
        #expect(e.cell(on: d("2026-10-13")).level == 4)
    }

    @Test func archivedHabitStopsCounting() {
        let e = engine(end: "2026-10-10", logs: logs([]))
        #expect(e.status(on: d("2026-10-12")) == .notScheduled)
        #expect(e.status(on: d("2026-10-09")) == .missed)
        #expect(e.contribution(on: d("2026-10-12")) == nil)
    }
}

@Suite("Streaks")
struct StreakTests {
    @Test func countsConsecutiveDaysAndTodayStaysOpen() {
        let e = engine(logs: logs(streakDays("2026-10-10", "2026-10-14")))
        #expect(e.currentStreak == Streak(5, .days))  // today pending doesn't break it
        let done = engine(logs: logs(streakDays("2026-10-10", "2026-10-15")))
        #expect(done.currentStreak == Streak(6, .days))
    }

    @Test func missBreaksAndBestRemembers() {
        let e = engine(logs: logs(streakDays("2026-10-01", "2026-10-08") + streakDays("2026-10-12", "2026-10-15")))
        #expect(e.currentStreak.count == 4)
        #expect(e.bestStreak.count == 8)
    }

    @Test func skippedDaysAreNeutral() {
        let e = engine(logs: logs(streakDays("2026-10-10", "2026-10-11") + [("2026-10-12", -1)]
                                 + streakDays("2026-10-13", "2026-10-15")))
        #expect(e.currentStreak.count == 5)  // 10,11,13,14,15 — the skip neither breaks nor counts
    }

    @Test func pastPartialBreaks() {
        let e = engine(.quantity, target: 8, logs: logs([("2026-10-13", 8), ("2026-10-14", 3), ("2026-10-15", 8)]))
        #expect(e.currentStreak.count == 1)
    }

    @Test func unscheduledDaysDontBreak() {
        // Mon/Wed/Fri. Done on Fri 9, Mon 12, Wed 14; today Thu 15.
        let e = engine(schedules: [ScheduleVersion(.weekdays([2, 4, 6]), from: d("2026-10-01"))],
                       logs: logs([("2026-10-09", 1), ("2026-10-12", 1), ("2026-10-14", 1)]))
        #expect(e.currentStreak.count == 3)
    }

    @Test func weeklyHabitsCountWeeks() {
        // 3× per week, weeks start Monday. Weeks of Oct 5 and Sep 28 met; this week (Oct 12) has 1 so far.
        let e = engine(start: "2026-09-28", schedules: [ScheduleVersion(.timesPerWeek(3), from: d("2026-09-28"))],
                       logs: logs([("2026-09-28", 1), ("2026-09-30", 1), ("2026-10-02", 1),
                                   ("2026-10-05", 1), ("2026-10-06", 1), ("2026-10-09", 1),
                                   ("2026-10-13", 1)]))
        #expect(e.currentStreak == Streak(2, .weeks))  // current week still reachable → neutral
        #expect(e.week(containing: d("2026-10-15"))! == (1, 3))
    }

    @Test func weeklyBreaksWhenTargetUnreachable() {
        // 5× per week, only 1 done by Saturday: Sat + Sun can't make up 4.
        let e = engine(start: "2026-10-05", schedules: [ScheduleVersion(.timesPerWeek(5), from: d("2026-10-05"))],
                       logs: logs(streakDays("2026-10-05", "2026-10-09") + [("2026-10-12", 1)]),
                       today: "2026-10-17")
        #expect(e.currentStreak.count == 0)
        #expect(e.bestStreak.count == 1)
    }

    @Test func weeklyCurrentWeekCountsOnceMet() {
        let e = engine(start: "2026-10-12", schedules: [ScheduleVersion(.timesPerWeek(2), from: d("2026-10-12"))],
                       logs: logs([("2026-10-12", 1), ("2026-10-14", 1)]))
        #expect(e.currentStreak == Streak(1, .weeks))
    }
}

@Suite("Strength score")
struct StrengthTests {
    @Test func growsWithConsistencyAndStaysBounded() {
        let short = engine(start: "2026-10-01", logs: logs(streakDays("2026-10-01", "2026-10-15")))
        let long = engine(start: "2026-01-01", logs: logs(streakDays("2026-01-01", "2026-10-15")))
        #expect(short.strength > 0.4 && short.strength < 0.6)
        #expect(long.strength > 0.99 && long.strength <= 1)
    }

    @Test func oneMissDoesNotEraseALongRun() {
        let run = streakDays("2026-01-01", "2026-10-13")
        let e = engine(start: "2026-01-01", logs: logs(run + [("2026-10-15", 1)]))  // missed the 14th
        #expect(e.strength > 0.9)
        #expect(e.currentStreak.count == 1)
    }

    @Test func recentDaysWeighMore() {
        let oldGood = engine(start: "2026-08-01", logs: logs(streakDays("2026-08-01", "2026-09-15")))
        let recentGood = engine(start: "2026-08-01", logs: logs(streakDays("2026-09-01", "2026-10-15")))
        #expect(recentGood.strength > oldGood.strength)
    }

    @Test func skippedDaysDontLowerIt() {
        let base = streakDays("2026-09-01", "2026-10-10")
        let skipping = engine(start: "2026-09-01", logs: logs(base + [("2026-10-11", -1), ("2026-10-12", -1)]))
        let missing = engine(start: "2026-09-01", logs: logs(base))
        #expect(skipping.strength > missing.strength)
    }

    @Test func emptyHabitIsZero() {
        #expect(engine(start: "2026-10-15", logs: logs([])).strength == 0)
    }
}

@Suite("Grid")
struct GridTests {
    @Test(arguments: [(0.0, 0), (0.01, 1), (0.33, 1), (0.34, 2), (0.5, 2), (0.66, 2), (0.67, 3), (0.99, 3), (1.0, 4), (1.5, 4)])
    func levels(_ fraction: Double, _ level: Int) {
        #expect(GridCell.level(for: fraction) == level)
    }

    @Test func skippedCellIsOutlined() {
        let e = engine(logs: logs([("2026-10-14", -1)]))
        #expect(e.cell(on: d("2026-10-14")) == GridCell(level: 0, isSkipped: true))
    }

    @Test func yearLayoutPutsTodayInLastColumn() {
        let layout = WeekGrid(endingAt: d("2026-10-15"), weeks: 53, firstWeekday: 2)
        #expect(layout.start == d("2025-10-13"))  // a Monday, 52 weeks before this week's Monday
        #expect(layout.date(column: 52, row: 3) == d("2026-10-15"))
        #expect(layout.date(column: 52, row: 4) == nil)  // tomorrow
        #expect(layout.rowWeekdays == [2, 3, 4, 5, 6, 7, 1])
        #expect(layout.allDates.count == 52 * 7 + 4)
        let labels = layout.monthLabels
        #expect(labels.first == WeekGrid.MonthLabel(column: 2, month: 11, year: 2025))
        #expect(labels.count == 12)
        #expect(labels.last?.month == 10)
    }

    @Test func overallFractionAndPerfectStreak() {
        let a = engine(logs: logs(streakDays("2026-10-01", "2026-10-15")))
        let b = engine(.quantity, target: 4, logs: logs([("2026-10-13", 4), ("2026-10-14", 4), ("2026-10-15", 2)]))
        #expect(Overall.fraction(on: d("2026-10-15"), engines: [a, b]) == 0.75)
        #expect(Overall.fraction(on: d("2026-10-12"), engines: [a, b]) == 0.5)
        #expect(Overall.fraction(on: d("2026-10-14"), engines: [a, b], journaled: false) == 2.0 / 3)
        #expect(Overall.perfectDayStreak(engines: [a, b], today: d("2026-10-15")) == 2)
        #expect(Overall.fraction(on: d("2026-09-01"), engines: [a, b]) == nil)
    }
}
