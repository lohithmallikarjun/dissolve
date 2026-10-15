import Engine
import Foundation

/// Connects the SwiftData models to the pure `Engine`.
extension Habit {
    var localStartDate: LocalDate { LocalDate(startDate) ?? LocalDate(createdAt) }
    var isArchived: Bool { archivedAt != nil }

    var scheduleVersions: [ScheduleVersion] {
        schedules.compactMap(\.version).sorted { $0.effectiveFrom < $1.effectiveFrom }
    }

    /// The schedule that applies on `date` (today by default).
    func rule(on date: LocalDate = AppSettings.today()) -> ScheduleRule {
        scheduleVersions.last { $0.effectiveFrom <= date }?.rule ?? scheduleVersions.first?.rule ?? .daily
    }

    var definition: HabitDefinition {
        HabitDefinition(
            kind: kind, target: target, startDate: localStartDate,
            endDate: archivedAt.map { LocalDate($0, dayEndsAtHour: AppSettings.dayEndsAtHour) },
            schedules: scheduleVersions)
    }

    var dayLogs: [LocalDate: DayLog] {
        var result: [LocalDate: DayLog] = [:]
        for log in logs {
            guard let date = LocalDate(log.date) else { continue }
            result[date] = DayLog(value: log.value, isSkipped: log.isSkipped)
        }
        return result
    }

    func engine(today: LocalDate = AppSettings.today()) -> HabitEngine {
        HabitEngine(habit: definition, logs: dayLogs, today: today, firstWeekday: AppSettings.firstWeekday)
    }

    func log(on date: LocalDate) -> HabitLog? {
        let key = date.description
        return logs.first { $0.date == key }
    }

    /// Step for "+1": one unit, or 5 minutes for timed habits.
    var step: Double { kind == .timed ? 5 : 1 }
}

extension ScheduleRule {
    var summary: String {
        switch self {
        case .daily:
            return String(localized: "Every day")
        case .weekdays(let days):
            if days.count == 7 { return String(localized: "Every day") }
            if days.isEmpty { return String(localized: "No days") }
            let symbols = Calendar.current.shortWeekdaySymbols
            let first = Calendar.current.firstWeekday
            return days.sorted { ($0 - first + 7) % 7 < ($1 - first + 7) % 7 }
                .map { symbols[$0 - 1] }.joined(separator: ", ")
        case .timesPerWeek(let n):
            return String(localized: "\(n)× a week")
        case .everyNDays(let n):
            return String(localized: "Every \(n) days")
        }
    }
}

extension LocalDate {
    func formatted(_ format: Date.FormatStyle = .dateTime.weekday(.wide).month(.wide).day()) -> String {
        startDate().formatted(format)
    }

    /// "Today", "Yesterday", or e.g. "Monday, 12 October".
    func relativeName(today: LocalDate) -> String {
        switch days(to: today) {
        case 0: String(localized: "Today")
        case 1: String(localized: "Yesterday")
        case -1: String(localized: "Tomorrow")
        default: formatted()
        }
    }
}

/// Number formatting for habit amounts: "8", "2.5".
extension Double {
    var amountText: String { formatted(.number.precision(.fractionLength(0...1))) }
}
