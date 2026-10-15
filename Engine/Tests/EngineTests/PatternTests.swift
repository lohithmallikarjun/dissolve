import Foundation
import Testing
@testable import Engine

@Suite("Patterns")
struct PatternTests {
    private let start = LocalDate("2026-08-01")!
    private let today = LocalDate("2026-10-15")!

    private func engine(doneOn done: (Int) -> Bool) -> HabitEngine {
        var logs: [LocalDate: DayLog] = [:]
        for i in 0..<start.days(to: today) where done(i) { logs[start.adding(days: i)] = DayLog(value: 1) }
        return HabitEngine(habit: HabitDefinition(kind: .binary, startDate: start, schedules: [ScheduleVersion(.daily, from: start)]),
                           logs: logs, today: today, firstWeekday: 2)
    }

    @Test func moodIsHigherOnHabitDays() {
        let e = engine { $0 % 2 == 0 }
        var moods: [LocalDate: Int] = [:]
        for i in 0..<60 { moods[start.adding(days: i)] = i % 2 == 0 ? 4 : 2 }
        let split = Patterns.moodSplit(e, moods: moods, from: start, to: today)!
        #expect(split.withHabit == 4 && split.withoutHabit == 2 && split.difference == 2)
        #expect(split.daysWith == 30 && split.daysWithout == 30)
    }

    @Test func moodSplitNeedsEnoughDaysOnBothSides() {
        let always = engine { _ in true }
        let moods = Dictionary(uniqueKeysWithValues: (0..<40).map { (start.adding(days: $0), 3) })
        #expect(Patterns.moodSplit(always, moods: moods, from: start, to: today) == nil)
    }

    @Test func habitsDoneTogetherHaveLift() {
        // a and b on the same days (every third day); c independent (odd days).
        let a = engine { $0 % 3 == 0 }, b = engine { $0 % 3 == 0 }, c = engine { $0 % 2 == 1 }
        let pairs = Patterns.coOccurrence([a, b, c], from: start, to: today.adding(days: -1))
        #expect(pairs.first?.first == 0 && pairs.first?.second == 1)
        #expect(pairs.first!.lift > 2.5)
        #expect(!pairs.contains { $0.first == 0 && $0.second == 2 })
    }

    @Test func daysOfData() {
        #expect(Patterns.daysOfData([engine { _ in true }]) == start.days(to: today) + 1)
        #expect(Patterns.daysOfData([]) == 0)
    }
}
