import Foundation
import Testing
@testable import Engine

@Suite("Statistics")
struct StatsTests {
    private func d(_ s: String) -> LocalDate { LocalDate(s)! }
    private let today = LocalDate("2026-10-15")!  // Thursday

    private func engine(_ rule: ScheduleRule = .daily, start: String = "2026-10-01", logs: [String: DayLog]) -> HabitEngine {
        HabitEngine(habit: HabitDefinition(kind: .binary, startDate: d(start), schedules: [ScheduleVersion(rule, from: d(start))]),
                    logs: Dictionary(uniqueKeysWithValues: logs.map { (d($0.key), $0.value) }), today: today, firstWeekday: 2)
    }

    private func done(_ days: [String]) -> [String: DayLog] {
        Dictionary(uniqueKeysWithValues: days.map { ($0, DayLog(value: 1)) })
    }

    @Test func dailyTallyExcludesSkipsAndOpenToday() {
        var logs = done(["2026-10-10", "2026-10-11", "2026-10-13"])
        logs["2026-10-12"] = DayLog(isSkipped: true)
        let t = Stats.tally(engine(logs: logs), from: d("2026-10-10"), to: today)
        // 10 ✓, 11 ✓, 12 skipped, 13 ✓, 14 missed, 15 open → 3 of 4.
        #expect(t == Tally(done: 3, due: 4))
        #expect(t.rate == 0.75)
    }

    @Test func todayCountsOnceDone() {
        let t = Stats.tally(engine(logs: done(["2026-10-15"])), from: today, to: today)
        #expect(t == Tally(done: 1, due: 1))
    }

    @Test func weeklyHabitsAreJudgedByWeek() {
        // 3×/week. Week of Oct 5: 2 done (of 3). Week of Oct 12 (in progress): 1 done → not counted yet.
        let e = engine(.timesPerWeek(3), start: "2026-10-05", logs: done(["2026-10-05", "2026-10-07", "2026-10-13"]))
        #expect(Stats.tally(e, from: d("2026-10-05"), to: today) == Tally(done: 2, due: 3))
    }

    @Test func weekdayBreakdown() {
        let e = engine(logs: done(["2026-10-05", "2026-10-12", "2026-10-06"]))  // Mondays + one Tuesday
        let w = Stats.byWeekday([e], from: d("2026-10-05"), to: d("2026-10-14"))
        #expect(w[2] == Tally(done: 2, due: 2))  // Monday
        #expect(w[3] == Tally(done: 1, due: 2))  // Tuesday
        #expect(w[4] == Tally(done: 0, due: 2))  // Wednesday
    }

    @Test func weeklyAndMonthlyBuckets() {
        let e = engine(start: "2026-08-01", logs: done((1...30).map { String(format: "2026-09-%02d", $0) }))
        let weeks = Stats.weekly([e], weeks: 3, today: today, firstWeekday: 2)
        #expect(weeks.map(\.start) == [d("2026-09-28"), d("2026-10-05"), d("2026-10-12")])
        #expect(weeks[0].tally == Tally(done: 3, due: 7))  // Sep 28–30 done, Oct 1–4 missed
        let months = Stats.monthly([e], months: 3, today: today)
        #expect(months.map(\.month) == [d("2026-08-01"), d("2026-09-01"), d("2026-10-01")])
        #expect(months[0].tally == Tally(done: 0, due: 31))
        #expect(months[1].tally.rate == 1)
        #expect(months[2].tally == Tally(done: 0, due: 14))
    }

    @Test func monthlyCrossesYears() {
        let months = Stats.monthly([], months: 12, today: d("2026-02-10"))
        #expect(months.first?.month == d("2025-03-01"))
        #expect(months.last?.month == d("2026-02-01"))
    }

    @Test func strengthSeriesEndsAtCurrentStrength() {
        let e = engine(start: "2026-01-01", logs: done((0..<200).map { d("2026-01-01").adding(days: $0).description }))
        let series = e.strengthSeries(from: d("2026-01-01"), to: today)
        #expect(series.count == d("2026-01-01").days(to: today) + 1)
        #expect(abs(series.last! - e.strength) < 1e-9)
        #expect(series[100] > series[10])  // grew while consistent
        #expect(series.last! < series[199])  // decayed after stopping
    }

    @Test func overallStrengthAveragesActiveHabits() {
        let a = engine(logs: done((1...15).map { String(format: "2026-10-%02d", $0) }))
        let b = engine(start: "2026-10-10", logs: [:])
        let overall = Stats.overallStrength([a, b], from: d("2026-10-05"), to: today)
        let aSeries = a.strengthSeries(from: d("2026-10-05"), to: today)
        #expect(overall[0] == aSeries[0])                  // only a existed
        #expect(abs(overall.last! - aSeries.last! / 2) < 1e-9)  // b is 0
    }

    @Test func journalStats() {
        let dates: Set<LocalDate> = [d("2026-10-01"), d("2026-10-02"), d("2026-09-15")]
        let months = Stats.entriesPerMonth(dates, months: 2, today: today)
        #expect(months.map(\.count) == [1, 2])
        let moods = Stats.moodByWeek([d("2026-10-12"): 4, d("2026-10-13"): 2, d("2026-10-06"): 0],
                                     weeks: 2, today: today, firstWeekday: 2)
        #expect(moods[0].mood == nil)
        #expect(moods[1].mood == 3)
    }
}
