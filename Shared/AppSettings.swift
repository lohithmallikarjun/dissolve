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

    private static let journalNudgeKey = "settings.journalNudgeMinutes"
    private static let pendingURLKey = "settings.pendingURL"

    /// Evening journal nudge, minutes after midnight; nil = off. Default 21:30.
    static var journalNudgeMinutes: Int? {
        get {
            let defaults = AppGroup.defaults
            guard let value = defaults.object(forKey: journalNudgeKey) as? Int else { return 21 * 60 + 30 }
            return value < 0 ? nil : value
        }
        set { AppGroup.defaults.set(newValue ?? -1, forKey: journalNudgeKey) }
    }

    /// A deep link left by an intent or control (which may run in the widget extension)
    /// for the app to open when it next comes to the foreground.
    static var pendingURL: URL? {
        get { AppGroup.defaults.string(forKey: pendingURLKey).flatMap(URL.init(string:)) }
        set { AppGroup.defaults.set(newValue?.absoluteString, forKey: pendingURLKey) }
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
