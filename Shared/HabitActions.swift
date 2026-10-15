import Engine
import Foundation
import SwiftData
import WidgetKit

/// Every change to habit logs goes through here, from the app and from widget buttons.
enum HabitActions {
    /// The day's log, created if needed (one per habit per day).
    static func log(for habit: Habit, on date: LocalDate, in context: ModelContext) -> HabitLog {
        if let existing = habit.log(on: date) { return existing }
        let log = HabitLog(habit: habit, date: date)
        context.insert(log)
        log.habit = habit
        return log
    }

    /// The card / widget tap: check off a yes-no habit, or add one step to an amount.
    static func primaryAction(_ habit: Habit, on date: LocalDate, in context: ModelContext) {
        switch habit.kind {
        case .binary:
            let done = (habit.log(on: date)?.value ?? 0) >= 1
            setValue(done ? 0 : 1, for: habit, on: date, in: context)
        case .quantity, .timed, .limit:
            increment(habit, by: habit.step, on: date, in: context)
        }
    }

    static func increment(_ habit: Habit, by step: Double, on date: LocalDate, in context: ModelContext) {
        let current = habit.log(on: date)?.value ?? 0
        setValue(max(0, current + step), for: habit, on: date, in: context)
    }

    /// Marks the day fully done (binary 1, or the target amount).
    static func complete(_ habit: Habit, on date: LocalDate, in context: ModelContext) {
        setValue(habit.kind == .binary ? 1 : max(habit.target, 1), for: habit, on: date, in: context)
    }

    static func setValue(_ value: Double, for habit: Habit, on date: LocalDate, in context: ModelContext) {
        let log = log(for: habit, on: date, in: context)
        log.value = value
        log.isSkipped = false
        log.updatedAt = .now
        removeIfEmpty(log, in: context)
        save(context)
    }

    static func setSkipped(_ skipped: Bool, for habit: Habit, on date: LocalDate, in context: ModelContext) {
        let log = log(for: habit, on: date, in: context)
        log.isSkipped = skipped
        if skipped { log.value = 0 }
        log.updatedAt = .now
        removeIfEmpty(log, in: context)
        save(context)
    }

    static func setNote(_ note: String, for habit: Habit, on date: LocalDate, in context: ModelContext) {
        let log = log(for: habit, on: date, in: context)
        log.note = note
        log.updatedAt = .now
        removeIfEmpty(log, in: context)
        save(context)
    }

    /// Clears the day: no value, not skipped, no note.
    static func reset(_ habit: Habit, on date: LocalDate, in context: ModelContext) {
        if let log = habit.log(on: date) {
            context.delete(log)
            save(context)
        }
    }

    static func save(_ context: ModelContext) {
        Persistence.save(context)
    }

    /// A log with nothing in it is deleted, so "untouched" days stay untouched.
    private static func removeIfEmpty(_ log: HabitLog, in context: ModelContext) {
        if log.value == 0, !log.isSkipped, log.note.isEmpty {
            context.delete(log)
        }
    }
}
