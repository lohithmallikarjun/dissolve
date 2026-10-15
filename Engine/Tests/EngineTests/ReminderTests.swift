import Foundation
import Testing
@testable import Engine

@Suite("Reminders")
struct ReminderTests {
    private func d(_ s: String) -> LocalDate { LocalDate(s)! }
    private let today = LocalDate("2026-10-15")!  // Thursday

    private func engine(_ rule: ScheduleRule = .daily, kind: HabitKind = .binary,
                        logs: [String: DayLog] = [:]) -> HabitEngine {
        HabitEngine(habit: HabitDefinition(kind: kind, target: 1, startDate: d("2026-10-01"),
                                           schedules: [ScheduleVersion(rule, from: d("2026-10-01"))]),
                    logs: Dictionary(uniqueKeysWithValues: logs.map { (d($0.key), $0.value) }),
                    today: today, firstWeekday: 2)
    }

    @Test func dailyHabitGetsSevenDaysUntilDone() {
        let id = UUID()
        let plan = ReminderPlanner.plan(habits: [.init(id: id, engine: engine(), minutes: 8 * 60)],
                                        journal: nil, today: today, nowMinutes: 7 * 60)
        #expect(plan.count == 7)
        #expect(plan.first?.date == today)
        let done = ReminderPlanner.plan(habits: [.init(id: id, engine: engine(logs: ["2026-10-15": DayLog(value: 1)]), minutes: 480)],
                                        journal: nil, today: today, nowMinutes: 420)
        #expect(done.count == 6 && done.first?.date == today.adding(days: 1))
    }

    @Test func skipsPastTimesTodayAndRestDays() {
        let e = engine(logs: ["2026-10-17": DayLog(isSkipped: true)])
        let plan = ReminderPlanner.plan(habits: [.init(id: UUID(), engine: e, minutes: 8 * 60)],
                                        journal: nil, today: today, nowMinutes: 9 * 60)
        #expect(!plan.contains { $0.date == today })
        #expect(!plan.contains { $0.date == d("2026-10-17") })
        #expect(plan.count == 5)
    }

    @Test func weekdaysOnlyOnScheduledDays() {
        let plan = ReminderPlanner.plan(habits: [.init(id: UUID(), engine: engine(.weekdays([2, 4, 6])), minutes: 600)],
                                        journal: nil, today: today, nowMinutes: 0)
        // Thu 15 … Wed 21: Fri 16, Mon 19, Wed 21.
        #expect(plan.map(\.date) == [d("2026-10-16"), d("2026-10-19"), d("2026-10-21")])
    }

    @Test func weeklyTargetMetStopsRemindersThatWeek() {
        let e = engine(.timesPerWeek(2), logs: ["2026-10-12": DayLog(value: 1), "2026-10-14": DayLog(value: 1)])
        let plan = ReminderPlanner.plan(habits: [.init(id: UUID(), engine: e, minutes: 600)],
                                        journal: nil, today: today, nowMinutes: 0)
        #expect(plan.allSatisfy { $0.date >= d("2026-10-19") })  // next week only
    }

    @Test func journalNudgeSkipsWrittenDays() {
        let plan = ReminderPlanner.plan(habits: [], journal: .init(minutes: 21 * 60 + 30, writtenDates: [today]),
                                        today: today, nowMinutes: 12 * 60)
        #expect(plan.count == 6 && plan.first?.date == today.adding(days: 1))
        #expect(plan.first?.identifier == "journal-2026-10-16")
    }

    @Test func limitHabitsAndArchivedHabitsGetNone() {
        let limit = engine(kind: .limit)
        let plan = ReminderPlanner.plan(habits: [.init(id: UUID(), engine: limit, minutes: 600)],
                                        journal: nil, today: today, nowMinutes: 0)
        #expect(plan.isEmpty)
    }

    @Test func capsAtTheSystemLimitKeepingTheSoonest() {
        let habits = (0..<12).map { _ in ReminderPlanner.HabitInput(id: UUID(), engine: engine(), minutes: 600) }
        let plan = ReminderPlanner.plan(habits: habits, journal: nil, today: today, nowMinutes: 0)
        #expect(plan.count == 60)
        #expect(plan.last!.date == today.adding(days: 4))
    }
}
