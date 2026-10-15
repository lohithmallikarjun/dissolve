import Foundation

/// One local notification to schedule.
public struct PlannedReminder: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case habit(UUID)
        case journal
    }

    public let kind: Kind
    public let date: LocalDate
    /// Minutes after midnight, local time.
    public let minutes: Int

    public var identifier: String {
        switch kind {
        case .habit(let id): "habit-\(id.uuidString)-\(date)"
        case .journal: "journal-\(date)"
        }
    }
}

/// Plans the next few days of reminders. Local notifications only: no push, no paid account.
/// Rolling one-off notifications (instead of repeating ones) let us skip days that are
/// already done, rest days, and days a habit isn't scheduled.
public enum ReminderPlanner {
    public struct HabitInput: Sendable {
        public let id: UUID
        public let engine: HabitEngine
        public let minutes: Int

        public init(id: UUID, engine: HabitEngine, minutes: Int) {
            self.id = id
            self.engine = engine
            self.minutes = minutes
        }
    }

    public struct JournalInput: Sendable {
        public let minutes: Int
        public let writtenDates: Set<LocalDate>

        public init(minutes: Int, writtenDates: Set<LocalDate>) {
            self.minutes = minutes
            self.writtenDates = writtenDates
        }
    }

    /// iOS keeps at most 64 pending notifications per app.
    public static let systemLimit = 60

    public static func plan(habits: [HabitInput], journal: JournalInput?, today: LocalDate, nowMinutes: Int,
                            days: Int = 7, limit: Int = systemLimit) -> [PlannedReminder] {
        var result: [PlannedReminder] = []
        for offset in 0..<days {
            let date = today.adding(days: offset)
            let isToday = offset == 0
            if let journal, !(isToday && (journal.minutes <= nowMinutes || journal.writtenDates.contains(date))) {
                result.append(PlannedReminder(kind: .journal, date: date, minutes: journal.minutes))
            }
            for habit in habits {
                if isToday && habit.minutes <= nowMinutes { continue }
                if needsReminder(habit.engine, on: date, isToday: isToday) {
                    result.append(PlannedReminder(kind: .habit(habit.id), date: date, minutes: habit.minutes))
                }
            }
        }
        // Soonest first, so the cap drops the furthest days.
        return Array(result.sorted { ($0.date, $0.minutes) < ($1.date, $1.minutes) }.prefix(limit))
    }

    static func needsReminder(_ engine: HabitEngine, on date: LocalDate, isToday: Bool) -> Bool {
        let habit = engine.habit
        guard date >= habit.startDate, habit.endDate == nil else { return false }
        let version = engine.schedule(on: date)
        if habit.kind == .limit { return false }  // nothing to "do" for a limit
        if isToday {
            switch engine.status(on: date) {
            case .completed, .skipped, .notScheduled: return false
            default: break
            }
            if let week = engine.week(containing: date), week.done >= week.target { return false }
            return true
        }
        if engine.logs[date]?.isSkipped == true { return false }
        if case .timesPerWeek = version.rule {
            if let week = engine.week(containing: date), week.done >= week.target { return false }
            return true
        }
        return version.isDue(on: date)
    }
}
