import Engine
import Foundation

/// User settings shared with the widgets through the App Group.
enum AppSettings {
    private static let dayEndsAtKey = "settings.dayEndsAtHour"

    /// A check-off before this hour counts for the previous day. Default 3 am.
    static var dayEndsAtHour: Int {
        get {
            let defaults = AppGroup.defaults
            return defaults.object(forKey: dayEndsAtKey) == nil ? 3 : defaults.integer(forKey: dayEndsAtKey)
        }
        set { AppGroup.defaults.set(newValue, forKey: dayEndsAtKey) }
    }

    /// 1 = Sunday, 2 = Monday, from the user's region settings.
    static var firstWeekday: Int { Calendar.current.firstWeekday }

    static func today(now: Date = .now) -> LocalDate {
        LocalDate(now, dayEndsAtHour: dayEndsAtHour)
    }

    /// When "today" next changes.
    static func nextDayBoundary(after now: Date = .now) -> Date {
        let calendar = Calendar.current
        let tomorrow = today(now: now).adding(days: 1).startDate(in: calendar)
        return calendar.date(byAdding: .hour, value: dayEndsAtHour, to: tomorrow) ?? tomorrow
    }
}
