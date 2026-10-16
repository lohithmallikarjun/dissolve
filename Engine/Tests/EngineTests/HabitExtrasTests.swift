import Foundation
import Testing
@testable import Engine

@Suite("Rest days, never miss twice, awards, routines")
struct HabitExtrasTests {
    private func d(_ s: String) -> LocalDate { LocalDate(s)! }

    private func engine(_ rule: ScheduleRule = .daily, start: String = "2026-01-01", today: String,
                        done: [LocalDate] = [], skipped: [LocalDate] = []) -> HabitEngine {
        var logs: [LocalDate: DayLog] = [:]
        for day in done { logs[day] = DayLog(value: 1) }
        for day in skipped { logs[day] = DayLog(isSkipped: true) }
        return HabitEngine(habit: HabitDefinition(kind: .binary, startDate: d(start),
                                                  schedules: [ScheduleVersion(rule, from: d(start))]),
                           logs: logs, today: d(today), firstWeekday: 2)
    }

    private func days(_ from: String, _ count: Int) -> [LocalDate] {
        (0..<count).map { d(from).adding(days: $0) }
    }

    @Test func earnsOneRestDayPerFourteenCompletions() {
        let bank = RestDayBank.compute(completed: days("2026-01-01", 30), spends: [], policy: RestDayPolicy())
        #expect(bank.earned == 2 && bank.balance == 2 && bank.progressToNext == 2)
    }

    @Test func spendBeforeEarningIsRejected() {
        let bank = RestDayBank.compute(completed: days("2026-01-01", 14), spends: [d("2026-01-05"), d("2026-01-20")],
                                       policy: RestDayPolicy())
        #expect(bank.rejected == [d("2026-01-05")])
        #expect(bank.spent == [d("2026-01-20")])
        #expect(bank.balance == 0)
    }

    @Test func bankIsCapped() {
        let bank = RestDayBank.compute(completed: days("2026-01-01", 100), spends: [],
                                       policy: RestDayPolicy(earnEvery: 10, maxBalance: 3))
        #expect(bank.balance == 3 && bank.earned == 3)
    }

    @Test func bankFromEngineCountsCompletedDays() {
        let e = engine(today: "2026-01-20", done: days("2026-01-01", 15))
        let bank = RestDayBank.compute(engine: e, spends: [], policy: RestDayPolicy())
        #expect(bank.balance == 1)
    }

    @Test func neverMissTwiceAfterAMiss() {
        let missedYesterday = engine(today: "2026-01-05", done: days("2026-01-01", 3))
        #expect(missedYesterday.needsNeverMissTwice)
        let doneYesterday = engine(today: "2026-01-05", done: days("2026-01-01", 4))
        #expect(!doneYesterday.needsNeverMissTwice)
        let restYesterday = engine(today: "2026-01-05", done: days("2026-01-01", 3), skipped: [d("2026-01-04")])
        #expect(!restYesterday.needsNeverMissTwice)
        let doneToday = engine(today: "2026-01-05", done: days("2026-01-01", 3) + [d("2026-01-05")])
        #expect(!doneToday.needsNeverMissTwice)
    }

    @Test func neverMissTwiceLooksPastUnscheduledDays() {
        // Mon/Wed/Fri. Missed Wed Jan 7, today Fri Jan 9.
        let e = engine(.weekdays([2, 4, 6]), start: "2026-01-05", today: "2026-01-09", done: [d("2026-01-05")])
        #expect(e.lastDueDay(before: d("2026-01-09")) == d("2026-01-07"))
        #expect(e.needsNeverMissTwice)
    }

    @Test func streakAwardsEarnedOnce() {
        // 10 days, a miss, then 8 days: the 7-day award is earned on day 7 only.
        let done = days("2026-01-01", 10) + days("2026-01-12", 8)
        let awards = Awards.earned(by: engine(today: "2026-01-19", done: done))
        let streaks = awards.filter { if case .streak = $0.kind { true } else { false } }
        #expect(streaks == [Award(kind: .streak(7), earnedOn: d("2026-01-07"))])
        #expect(awards.first == Award(kind: .firstCompletion, earnedOn: d("2026-01-01")))
    }

    @Test func restDaysDontBreakAwardStreaks() {
        let done = days("2026-01-01", 3) + days("2026-01-05", 4)
        let awards = Awards.earned(by: engine(today: "2026-01-09", done: done, skipped: [d("2026-01-04")]))
        #expect(awards.contains(Award(kind: .streak(7), earnedOn: d("2026-01-08"))))
    }

    @Test func perfectWeeksAndMonths() {
        // Feb 2026: Feb 1 is a Sunday. All of February done.
        let e = engine(start: "2026-02-01", today: "2026-03-03", done: days("2026-02-01", 28))
        let awards = Awards.earned(by: e)
        #expect(awards.contains(Award(kind: .perfectMonth("2026-02"), earnedOn: d("2026-02-28"))))
        // Weeks start Monday; the first full week is Feb 2–8; four full weeks in February, none into March.
        let weeks = awards.compactMap { if case .perfectWeek(let s) = $0.kind { s } else { nil } }
        #expect(weeks == [d("2026-02-02"), d("2026-02-09"), d("2026-02-16")])
        #expect(awards.contains(Award(kind: .streak(7), earnedOn: d("2026-02-07"))))
    }

    @Test func weeklyHabitStreakAwardsCountWeeks() {
        // 3× a week for 8 weeks from Monday Jan 5.
        var done: [LocalDate] = []
        for w in 0..<8 { done += [0, 2, 4].map { d("2026-01-05").adding(days: w * 7 + $0) } }
        let e = engine(.timesPerWeek(3), start: "2026-01-05", today: "2026-03-02", done: done)
        let awards = Awards.earned(by: e)
        #expect(awards.contains(Award(kind: .streak(7), earnedOn: d("2026-02-22"))))
    }

    @Test func routinePlayerSkipsDoneHabits() {
        let a = UUID(), b = UUID(), c = UUID()
        var player = RoutinePlayer(steps: [a, b, c], alreadyDone: [b])
        #expect(player.current == a)
        player.complete()
        #expect(player.current == c && player.progress == 0.5)
        player.skip()
        #expect(player.isFinished && player.completed == [a] && player.skipped == [c])
    }
}
