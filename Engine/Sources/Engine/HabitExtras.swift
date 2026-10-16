import Foundation

// MARK: Earned rest days

/// "1 rest day for every N completed days." A rest day turns a would-be miss into a skip,
/// so the streak survives. Earning and spending are replayed in date order, so a rest day
/// can only be spent once it has been earned.
public struct RestDayPolicy: Hashable, Sendable, Codable {
    public var earnEvery: Int
    /// Cap on the bank; nil = unlimited.
    public var maxBalance: Int?

    public init(earnEvery: Int = 14, maxBalance: Int? = 3) {
        self.earnEvery = max(earnEvery, 1)
        self.maxBalance = maxBalance
    }
}

public struct RestDayBank: Equatable, Sendable {
    public var earned: Int
    public var spent: [LocalDate]
    /// Spends that had nothing in the bank at the time; the caller should show them as misses.
    public var rejected: [LocalDate]
    public var balance: Int
    /// Completed days still counting toward the next rest day.
    public var progressToNext: Int

    public static func compute(completed: [LocalDate], spends: [LocalDate], policy: RestDayPolicy) -> RestDayBank {
        // On the same day, earning comes before spending.
        enum Event: Int { case done = 0, spend = 1 }
        var events: [(date: LocalDate, event: Event)] = completed.map { ($0, .done) }
        events += spends.map { ($0, .spend) }
        events.sort { ($0.date.dayNumber, $0.event.rawValue) < ($1.date.dayNumber, $1.event.rawValue) }
        var bank = RestDayBank(earned: 0, spent: [], rejected: [], balance: 0, progressToNext: 0)
        for (date, event) in events {
            switch event {
            case .done:
                bank.progressToNext += 1
                if bank.progressToNext >= policy.earnEvery {
                    bank.progressToNext = 0
                    if policy.maxBalance.map({ bank.balance < $0 }) ?? true {
                        bank.balance += 1
                        bank.earned += 1
                    }
                }
            case .spend:
                if bank.balance > 0 {
                    bank.balance -= 1
                    bank.spent.append(date)
                } else {
                    bank.rejected.append(date)
                }
            }
        }
        return bank
    }

    public static func compute(engine: HabitEngine, spends: [LocalDate], policy: RestDayPolicy) -> RestDayBank {
        var completed: [LocalDate] = []
        var day = engine.habit.startDate
        while day <= engine.lastDay {
            if engine.status(on: day) == .completed { completed.append(day) }
            day = day.adding(days: 1)
        }
        return compute(completed: completed, spends: spends, policy: policy)
    }
}

// MARK: Never miss twice

public extension HabitEngine {
    /// The most recent day before `date` the habit was due (and not a rest day).
    func lastDueDay(before date: LocalDate, lookback: Int = 60) -> LocalDate? {
        var day = date.adding(days: -1)
        let floor = max(habit.startDate, date.adding(days: -lookback))
        while day >= floor {
            if isActive(on: day), logs[day]?.isSkipped != true,
               !schedule(on: day).rule.isWeekly, schedule(on: day).isDue(on: day) {
                return day
            }
            day = day.adding(days: -1)
        }
        return nil
    }

    /// "Never miss twice": the last due day was missed and today is due and still open,
    /// so today's reminder should be a gentle priority one.
    var needsNeverMissTwice: Bool {
        guard habit.kind != .limit, status(on: today) == .pending,
              let last = lastDueDay(before: today) else { return false }
        return status(on: last) == .missed || status(on: last) == .partial
    }
}

// MARK: Awards

public enum AwardKind: Hashable, Sendable, Codable {
    /// Streak reached `count` units (days, or weeks for weekly habits).
    case streak(Int)
    /// Every due day of the week starting on this date was completed.
    case perfectWeek(LocalDate)
    /// Every due day of the month (`yyyy-MM`) was completed.
    case perfectMonth(String)
    case firstCompletion

    public static let streakMilestones = [7, 30, 100, 365]

    /// Stable key for storing "already shown".
    public var key: String {
        switch self {
        case .streak(let n): "streak-\(n)"
        case .perfectWeek(let start): "week-\(start)"
        case .perfectMonth(let month): "month-\(month)"
        case .firstCompletion: "first"
        }
    }
}

public struct Award: Hashable, Sendable {
    public let kind: AwardKind
    public let earnedOn: LocalDate
}

public enum Awards {
    /// Every award this habit has earned, in date order. Each streak milestone is earned once,
    /// the first time the running streak reaches it.
    public static func earned(by engine: HabitEngine) -> [Award] {
        var awards: [Award] = []
        let start = engine.habit.startDate
        let end = engine.lastDay
        guard start <= end else { return [] }

        var day = start
        var firstDone = false
        var run = 0
        var reached = Set<Int>()
        let weekly = engine.schedule(on: end).rule.isWeekly
        var lastWeekStart: LocalDate?

        while day <= end {
            let status = engine.status(on: day)
            if !firstDone, status == .completed {
                firstDone = true
                awards.append(Award(kind: .firstCompletion, earnedOn: day))
            }
            if weekly {
                let weekStart = day.startOfWeek(firstWeekday: engine.firstWeekday)
                let weekEnd = weekStart.adding(days: 6)
                if day == min(weekEnd, end), weekStart != lastWeekStart, let week = engine.week(containing: day) {
                    lastWeekStart = weekStart
                    if week.done >= week.target { run += 1 } else if day == weekEnd { run = 0 }
                }
            } else {
                switch status {
                case .completed: run += 1
                case .missed, .partial: run = 0
                default: break
                }
            }
            for milestone in AwardKind.streakMilestones where run >= milestone && !reached.contains(milestone) {
                reached.insert(milestone)
                awards.append(Award(kind: .streak(milestone), earnedOn: day))
            }
            day = day.adding(days: 1)
        }
        if !weekly {
            awards += perfectPeriods(engine)
        }
        return awards.sorted { $0.earnedOn == $1.earnedOn ? $0.kind.key < $1.kind.key : $0.earnedOn < $1.earnedOn }
    }

    /// Weeks and months that are over, had at least one due day, and every due day completed
    /// (rest days don't count against them).
    private static func perfectPeriods(_ engine: HabitEngine) -> [Award] {
        var awards: [Award] = []
        func isPerfect(_ days: [LocalDate]) -> Bool {
            var due = 0
            for day in days {
                switch engine.status(on: day) {
                case .completed:
                    if engine.schedule(on: day).isDue(on: day) { due += 1 }
                case .missed, .partial, .pending: return false
                default: break
                }
            }
            return due > 0
        }
        let start = engine.habit.startDate
        let end = engine.lastDay
        // Weeks fully inside the habit's life that have ended.
        var weekStart = start.startOfWeek(firstWeekday: engine.firstWeekday)
        if weekStart < start { weekStart = weekStart.adding(days: 7) }
        while weekStart.adding(days: 6) < engine.today, weekStart.adding(days: 6) <= end {
            let days = (0..<7).map { weekStart.adding(days: $0) }
            if isPerfect(days) { awards.append(Award(kind: .perfectWeek(weekStart), earnedOn: days[6])) }
            weekStart = weekStart.adding(days: 7)
        }
        // Calendar months fully inside the habit's life that have ended.
        var year = start.year, month = start.month
        if start.day != 1 { (year, month) = month == 12 ? (year + 1, 1) : (year, month + 1) }
        while true {
            let first = LocalDate(year: year, month: month, day: 1)!
            let last = LocalDate(year: year, month: month, day: LocalDate.daysInMonth(year: year, month: month))!
            guard last < engine.today, last <= end else { break }
            let days = (0...first.days(to: last)).map { first.adding(days: $0) }
            if isPerfect(days) { awards.append(Award(kind: .perfectMonth(first.monthKey), earnedOn: last)) }
            (year, month) = month == 12 ? (year + 1, 1) : (year, month + 1)
        }
        return awards
    }
}

// MARK: Routines

/// A "Start routine" player: steps through the routine's habits, skipping ones already done.
public struct RoutinePlayer: Equatable, Sendable {
    public let steps: [UUID]
    public private(set) var index: Int
    public private(set) var completed: [UUID] = []
    public private(set) var skipped: [UUID] = []

    public init(steps: [UUID], alreadyDone: Set<UUID> = []) {
        self.steps = steps.filter { !alreadyDone.contains($0) }
        self.index = 0
    }

    public var current: UUID? { index < steps.count ? steps[index] : nil }
    public var isFinished: Bool { current == nil }
    public var progress: Double { steps.isEmpty ? 1 : Double(index) / Double(steps.count) }

    public mutating func complete() {
        guard let current else { return }
        completed.append(current)
        index += 1
    }

    public mutating func skip() {
        guard let current else { return }
        skipped.append(current)
        index += 1
    }
}
