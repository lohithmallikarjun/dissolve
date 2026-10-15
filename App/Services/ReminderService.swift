import Engine
import Foundation
import SwiftData
import UserNotifications

/// Habit reminders and the evening journal nudge, as local notifications (no push needed).
/// Rescheduled whenever the app becomes active or data changes, for the next 7 days.
@MainActor
enum ReminderService {
    static let habitCategory = "HABIT"
    static let journalCategory = "JOURNAL"
    static let doneAction = "DONE"
    private static let prefixes = ["habit-", "journal-"]

    static func registerCategories() {
        let done = UNNotificationAction(identifier: doneAction, title: String(localized: "Done"), options: [])
        let habit = UNNotificationCategory(identifier: habitCategory, actions: [done], intentIdentifiers: [])
        let journal = UNNotificationCategory(identifier: journalCategory, actions: [], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([habit, journal])
    }

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    static func reschedule(container: ModelContainer) async {
        let center = UNUserNotificationCenter.current()
        guard await authorizationStatus() == .authorized else { return }

        let context = container.mainContext
        let today = AppSettings.today()
        let habits = (try? context.fetch(FetchDescriptor<Habit>(predicate: #Predicate { $0.archivedAt == nil }))) ?? []
        let inputs = habits.compactMap { habit in
            habit.reminderMinutes.map { ReminderPlanner.HabitInput(id: habit.id, engine: habit.engine(today: today), minutes: $0) }
        }
        let journal = AppSettings.journalNudgeMinutes.map { minutes in
            let entries = (try? context.fetch(FetchDescriptor<JournalEntry>())) ?? []
            let written = Set(entries.filter { $0.wordCount > 0 || !$0.photoIDs.isEmpty }.compactMap(\.localDate))
            return ReminderPlanner.JournalInput(minutes: minutes, writtenDates: written)
        }
        let now = Calendar.current.dateComponents([.hour, .minute], from: .now)
        let plan = ReminderPlanner.plan(habits: inputs, journal: journal, today: today,
                                        nowMinutes: (now.hour ?? 0) * 60 + (now.minute ?? 0))

        let pending = await center.pendingNotificationRequests().map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { id in prefixes.contains { id.hasPrefix($0) } })

        let byID = Dictionary(uniqueKeysWithValues: habits.map { ($0.id, $0) })
        for reminder in plan {
            let content = UNMutableNotificationContent()
            content.sound = .default
            switch reminder.kind {
            case .habit(let id):
                guard let habit = byID[id] else { continue }
                let streak = habit.engine(today: today).currentStreak.count
                content.title = habit.name
                content.body = streak > 0
                    ? String(localized: "Keep your \(streak)-day streak going.")
                    : String(localized: "Time for \(habit.name).")
                content.categoryIdentifier = habitCategory
                content.userInfo = ["habitID": id.uuidString, "date": reminder.date.description]
                content.threadIdentifier = "habits"
            case .journal:
                content.title = String(localized: "How was today?")
                content.body = String(localized: "A few lines in your journal before bed.")
                content.categoryIdentifier = journalCategory
                content.userInfo = ["url": "dissolve://journal/\(reminder.date)"]
                content.threadIdentifier = "journal"
            }
            var components = DateComponents(year: reminder.date.year, month: reminder.date.month, day: reminder.date.day)
            components.hour = reminder.minutes / 60
            components.minute = reminder.minutes % 60
            let request = UNNotificationRequest(
                identifier: reminder.identifier, content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
            try? await center.add(request)
        }
    }
}

/// Handles taps and the "Done" button on notifications.
final class NotificationHandler: NSObject, UNUserNotificationCenterDelegate, Sendable {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        let habitID = info["habitID"] as? String
        let date = (info["date"] as? String).flatMap(LocalDate.init)
        let url = (info["url"] as? String).flatMap(URL.init(string:))
        await MainActor.run {
            if action == ReminderService.doneAction, let habitID {
                try? HabitIntentStore.primaryAction(habitID: habitID, on: date)
            } else if let url {
                AppSettings.pendingURL = url
            } else if habitID != nil {
                AppSettings.pendingURL = URL(string: "dissolve://today")
            }
        }
    }
}
