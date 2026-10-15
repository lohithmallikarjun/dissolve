import Engine
import Foundation
import SwiftData

/// Plausible sample habits with months of history, for previews, widget placeholders and CI screenshots.
/// Deterministic, so screenshots are stable.
enum DemoData {
    /// Seeds the real store when launched with `-demoData` and the store has no habits yet.
    @MainActor
    static func seedIfRequested(in context: ModelContext) {
        guard ProcessInfo.processInfo.arguments.contains("-demoData") else { return }
        let count = (try? context.fetchCount(FetchDescriptor<Habit>())) ?? 0
        guard count == 0 else { return }
        seed(into: context, today: AppSettings.today())
        try? context.save()
    }

    static func seed(into context: ModelContext, today: LocalDate, days: Int = 300) {
        var rng = SplitMix64(seed: 42)
        let start = today.adding(days: -days)

        func make(_ name: String, _ symbol: String, _ color: HabitColor, _ kind: HabitKind, target: Double = 1,
                  unit: String = "", rule: ScheduleRule, order: Int) -> Habit {
            let habit = Habit(name: name, symbol: symbol, colorName: color.rawValue, kind: kind, target: target,
                              unit: unit, sortOrder: order, startDate: start)
            context.insert(habit)
            let schedule = HabitSchedule(rule: rule, effectiveFrom: start)
            context.insert(schedule)
            schedule.habit = habit
            return habit
        }

        func log(_ habit: Habit, _ date: LocalDate, value: Double = 0, skipped: Bool = false, note: String = "") {
            let log = HabitLog(habit: habit, date: date)
            log.value = value
            log.isSkipped = skipped
            log.note = note
            context.insert(log)
            log.habit = habit
        }

        let meditate = make("Meditate", "brain.head.profile", .mint, .binary, rule: .daily, order: 0)
        let water = make("Water", "drop.fill", .blue, .quantity, target: 8, unit: "glasses", rule: .daily, order: 1)
        let gym = make("Gym", "dumbbell.fill", .orange, .binary, rule: .timesPerWeek(3), order: 2)
        let read = make("Read", "book.fill", .indigo, .timed, target: 20, rule: .weekdays([2, 3, 4, 5, 6]), order: 3)
        let coffee = make("Coffee", "cup.and.saucer.fill", .brown, .limit, target: 2, unit: "cups", rule: .daily, order: 4)

        for offset in 0..<days {
            let date = start.adding(days: offset)
            // Consistency improves over time.
            let skill = 0.55 + 0.4 * Double(offset) / Double(days)
            if rng.chance(0.03) {
                log(meditate, date, skipped: true)
            } else if rng.chance(skill) {
                log(meditate, date, value: 1, note: offset % 37 == 0 ? "Felt calm afterwards." : "")
            }
            log(water, date, value: Double(Int(rng.next(in: 3...9) * skill + 2)))
            if [2, 4, 6].contains(date.weekday), rng.chance(skill + 0.1) { log(gym, date, value: 1) }
            if (2...6).contains(date.weekday), rng.chance(skill) { log(read, date, value: Double(Int(rng.next(in: 10...35)))) }
            log(coffee, date, value: Double(Int(rng.next(in: 0...3.4))))
        }

        // Today: partly done.
        for habit in [meditate, water, gym, read, coffee] {
            if let existing = habit.logs.first(where: { $0.date == today.description }) { context.delete(existing) }
        }
        log(meditate, today, value: 1)
        log(water, today, value: 5)
        log(coffee, today, value: 1)
    }
}

/// Small deterministic RNG.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next(in range: ClosedRange<Double>) -> Double { Double.random(in: range, using: &self) }
    mutating func chance(_ p: Double) -> Bool { Double.random(in: 0..<1, using: &self) < p }
}

/// In-memory seeded store for SwiftUI previews and widget placeholders.
@MainActor
enum PreviewData {
    static let container: ModelContainer = {
        let container = SharedModelContainer.inMemory()
        DemoData.seed(into: container.mainContext, today: AppSettings.today(), days: 200)
        try? container.mainContext.save()
        return container
    }()
}
