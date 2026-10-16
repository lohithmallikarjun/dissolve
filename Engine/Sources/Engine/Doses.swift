import Foundation

/// When a medicine or supplement is taken. Record keeping only — never medical advice.
public struct DoseRule: Hashable, Sendable {
    public enum Days: Hashable, Sendable {
        case everyDay
        /// 1 = Sunday … 7 = Saturday.
        case weekdays(Set<Int>)
        /// Every N days from `start`.
        case everyNDays(Int)
    }

    /// Times of day, minutes after midnight. Empty = as needed (no reminders).
    public var times: [Int]
    public var days: Days
    public var start: LocalDate
    public var end: LocalDate?
    /// Pills (or units) per dose, for the refill countdown.
    public var unitsPerDose: Double

    public init(times: [Int], days: Days = .everyDay, start: LocalDate, end: LocalDate? = nil, unitsPerDose: Double = 1) {
        self.times = times.sorted()
        self.days = days
        self.start = start
        self.end = end
        self.unitsPerDose = unitsPerDose
    }

    public var isAsNeeded: Bool { times.isEmpty }

    public func isDue(on date: LocalDate) -> Bool {
        guard !isAsNeeded, date >= start, end.map({ date <= $0 }) ?? true else { return false }
        switch days {
        case .everyDay: return true
        case .weekdays(let set): return set.contains(date.weekday)
        case .everyNDays(let n): return start.days(to: date) % max(n, 1) == 0
        }
    }

    public func slots(on date: LocalDate) -> [DoseSlot] {
        isDue(on: date) ? times.map { DoseSlot(date: date, minutes: $0) } : []
    }

    /// Average doses per day over a 4-week window, for refills.
    public var dosesPerDay: Double {
        guard !isAsNeeded else { return 0 }
        let perDueDay = Double(times.count)
        switch days {
        case .everyDay: return perDueDay
        case .weekdays(let set): return perDueDay * Double(set.count) / 7
        case .everyNDays(let n): return perDueDay / Double(max(n, 1))
        }
    }
}

public struct DoseSlot: Hashable, Comparable, Sendable, Codable {
    public let date: LocalDate
    public let minutes: Int

    public init(date: LocalDate, minutes: Int) {
        self.date = date
        self.minutes = minutes
    }

    /// Stable key for the dose log and notification identifiers.
    public var key: String { "\(date)T\(minutes)" }

    public static func < (a: DoseSlot, b: DoseSlot) -> Bool {
        a.date == b.date ? a.minutes < b.minutes : a.date < b.date
    }
}

public enum DoseOutcome: String, Sendable, Codable { case taken, skipped }

public enum DoseMath {
    /// Slots from `date` on, in order, that have no outcome logged yet, starting after `nowMinutes` today
    /// minus a grace window (an overdue dose stays "due" for `graceMinutes`).
    public static func upcoming(_ rule: DoseRule, logged: [String: DoseOutcome], from date: LocalDate,
                                nowMinutes: Int, graceMinutes: Int = 120, days: Int = 7) -> [DoseSlot] {
        var result: [DoseSlot] = []
        for offset in 0..<days {
            let day = date.adding(days: offset)
            for slot in rule.slots(on: day) where logged[slot.key] == nil {
                if offset == 0 && slot.minutes < nowMinutes - graceMinutes { continue }
                result.append(slot)
            }
        }
        return result
    }

    public static func next(_ rule: DoseRule, logged: [String: DoseOutcome], from date: LocalDate,
                            nowMinutes: Int) -> DoseSlot? {
        upcoming(rule, logged: logged, from: date, nowMinutes: nowMinutes, days: 60).first
    }

    /// Share of past due doses (up to yesterday, plus today's passed times) marked taken.
    public static func adherence(_ rule: DoseRule, logged: [String: DoseOutcome], from: LocalDate,
                                 today: LocalDate, nowMinutes: Int) -> Double? {
        var due = 0, taken = 0
        var day = max(from, rule.start)
        while day <= today {
            for slot in rule.slots(on: day) where day < today || slot.minutes <= nowMinutes {
                due += 1
                if logged[slot.key] == .taken { taken += 1 }
            }
            day = day.adding(days: 1)
        }
        return due == 0 ? nil : Double(taken) / Double(due)
    }

    public struct Refill: Equatable, Sendable {
        /// Whole days the current supply lasts.
        public let daysLeft: Int
        /// The day it runs out.
        public let runsOut: LocalDate
        /// Remind on this day (`leadDays` before running out, never before today).
        public let remindOn: LocalDate
    }

    public static func refill(_ rule: DoseRule, unitsLeft: Double, today: LocalDate, leadDays: Int = 7) -> Refill? {
        let perDay = rule.dosesPerDay * rule.unitsPerDose
        guard perDay > 0 else { return nil }
        let days = max(Int((unitsLeft / perDay).rounded(.down)), 0)
        let runsOut = today.adding(days: days)
        return Refill(daysLeft: days, runsOut: runsOut, remindOn: max(today, runsOut.adding(days: -leadDays)))
    }
}
