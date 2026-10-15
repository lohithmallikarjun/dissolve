import Engine
import Foundation
import SwiftData

/// One version of a habit's schedule. A change adds a new version with a later
/// `effectiveFrom`, so old days keep being judged by the schedule they had.
@Model
final class HabitSchedule {
    enum Kind: String, CaseIterable, Identifiable {
        case daily, weekdays, timesPerWeek, everyNDays
        var id: String { rawValue }
    }

    var id: UUID = UUID()
    var kindRaw: String = Kind.daily.rawValue
    /// `1 = Sunday … 7 = Saturday`.
    var weekdays: [Int] = []
    var timesPerWeek: Int = 3
    var everyNDays: Int = 2
    /// `yyyy-MM-dd`
    var effectiveFrom: String = ""
    var updatedAt: Date = Date.now
    var habit: Habit?

    init(rule: ScheduleRule, effectiveFrom: LocalDate) {
        self.effectiveFrom = effectiveFrom.description
        self.rule = rule
    }

    var rule: ScheduleRule {
        get {
            switch Kind(rawValue: kindRaw) ?? .daily {
            case .daily: .daily
            case .weekdays: .weekdays(Set(weekdays))
            case .timesPerWeek: .timesPerWeek(timesPerWeek)
            case .everyNDays: .everyNDays(everyNDays)
            }
        }
        set {
            switch newValue {
            case .daily:
                kindRaw = Kind.daily.rawValue
            case .weekdays(let days):
                kindRaw = Kind.weekdays.rawValue
                weekdays = days.sorted()
            case .timesPerWeek(let n):
                kindRaw = Kind.timesPerWeek.rawValue
                timesPerWeek = n
            case .everyNDays(let n):
                kindRaw = Kind.everyNDays.rawValue
                everyNDays = n
            }
            updatedAt = .now
        }
    }

    var version: ScheduleVersion? {
        LocalDate(effectiveFrom).map { ScheduleVersion(rule, from: $0) }
    }
}
