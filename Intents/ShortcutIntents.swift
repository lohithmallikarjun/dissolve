import AppIntents
import Engine
import Foundation
import SwiftData
import WidgetKit

/// "Log Meditate in Dissolve": checks off a habit, or adds an amount.
struct CompleteHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Habit"
    static let description = IntentDescription("Checks off a habit for today, or adds an amount to it.")

    @Parameter(title: "Habit")
    var habit: HabitEntity

    @Parameter(title: "Amount", description: "For amount and minute habits. Leave empty to add one step.")
    var amount: Double?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$habit)") {
            \.$amount
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try await ShortcutStore.log(habitID: habit.id, amount: amount)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

/// "How am I doing in Dissolve?"
struct TodayProgressIntent: AppIntent {
    static let title: LocalizedStringResource = "Today's Habits"
    static let description = IntentDescription("Tells you how many of today's habits are done.")

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let (done, due, next) = try await ShortcutStore.progress()
        var message = String(localized: "\(done) of \(due) habits done today.")
        if let next { message += " " + String(localized: "Next up: \(next).") }
        return .result(value: done, dialog: IntentDialog(stringLiteral: message))
    }
}

/// "What's my Meditate streak in Dissolve?"
struct HabitStreakIntent: AppIntent {
    static let title: LocalizedStringResource = "Habit Streak"
    static let description = IntentDescription("Gets a habit's current streak and strength.")

    @Parameter(title: "Habit")
    var habit: HabitEntity

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let (streak, message) = try await ShortcutStore.streak(habitID: habit.id)
        return .result(value: streak, dialog: IntentDialog(stringLiteral: message))
    }
}

/// Adds text to today's journal entry without opening the app.
struct AddToJournalIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to Journal"
    static let description = IntentDescription("Adds a line to today's journal entry.")

    @Parameter(title: "Text", inputOptions: String.IntentInputOptions(multiline: true))
    var text: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await ShortcutStore.appendToJournal(text)
        return .result(dialog: "Added to today's journal.")
    }
}

/// Opens today's journal entry (also the Control Center "New journal entry" control).
struct OpenJournalIntent: AppIntent {
    static let title: LocalizedStringResource = "New Journal Entry"
    static let description = IntentDescription("Opens today's journal entry in Dissolve.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        AppSettings.pendingURL = URL(string: "dissolve://journal/today")
        return .result()
    }
}

/// "How long until Marathon in Dissolve?"
struct DaysUntilIntent: AppIntent {
    static let title: LocalizedStringResource = "Days Until"
    static let description = IntentDescription("Tells you how many days are left on a countdown.")

    @Parameter(title: "Countdown")
    var countdown: CountdownEntity

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let (days, message) = try await ShortcutStore.daysUntil(countdownID: countdown.id)
        return .result(value: days, dialog: IntentDialog(stringLiteral: message))
    }
}

@MainActor
enum ShortcutStore {
    enum Failure: Error, CustomLocalizedStringResourceConvertible {
        case notFound
        var localizedStringResource: LocalizedStringResource { "Couldn't find that in Dissolve." }
    }

    private static func context() throws -> ModelContext {
        ModelContext(try SharedModelContainer.appGroup())
    }

    static func log(habitID: UUID, amount: Double?) throws -> String {
        let context = try context()
        guard let habit = HabitIntentStore.habit(habitID, in: context) else { throw Failure.notFound }
        let today = AppSettings.today()
        if let amount, habit.kind != .binary {
            HabitActions.increment(habit, by: amount, on: today, in: context)
        } else if habit.kind == .binary, (habit.log(on: today)?.value ?? 0) >= 1 {
            // Already done: "log" shouldn't toggle it back off.
        } else {
            HabitActions.primaryAction(habit, on: today, in: context)
        }
        HabitIntentStore.markExternalChange()
        let engine = habit.engine(today: today)
        let streak = engine.currentStreak.count
        let detail = habit.detailText(engine: engine, day: today)
        return streak > 0
            ? String(localized: "Logged \(habit.name) — \(detail). \(streak)-day streak.")
            : String(localized: "Logged \(habit.name) — \(detail).")
    }

    static func progress() throws -> (Int, Int, String?) {
        let snapshot = DashboardLoader.load(context: try context())
        return (snapshot.doneCount, snapshot.dueToday.count, snapshot.nextUndone?.name)
    }

    static func streak(habitID: UUID) throws -> (Int, String) {
        let context = try context()
        guard let habit = HabitIntentStore.habit(habitID, in: context) else { throw Failure.notFound }
        let engine = habit.engine()
        let streak = engine.currentStreak
        let unit = streak.unit == .weeks ? String(localized: "weeks") : String(localized: "days")
        let strength = Int((engine.strength * 100).rounded())
        return (streak.count, String(localized: "\(habit.name): \(streak.count) \(unit) in a row, \(strength)% strong."))
    }

    static func appendToJournal(_ text: String) throws {
        let context = try context()
        let entry = JournalStore.entryCreatingIfNeeded(on: AppSettings.today(), in: context)
        let block = entry.orderedBlocks.first { $0.kind == .text } ?? entry.orderedBlocks.first { $0.kind == .prompt }
        if let block {
            block.text = block.text.isEmpty ? text : block.text + "\n" + text
        }
        entry.recountWords()
        Persistence.save(context)
        HabitIntentStore.markExternalChange()
    }

    static func daysUntil(countdownID: UUID) throws -> (Int, String) {
        let context = try context()
        var descriptor = FetchDescriptor<Countdown>(predicate: #Predicate { $0.id == countdownID })
        descriptor.fetchLimit = 1
        guard let countdown = try context.fetch(descriptor).first else { throw Failure.notFound }
        let state = countdown.state()
        let message: String
        if countdown.countUp {
            message = String(localized: "\(state.days) days since \(countdown.title).")
        } else if state.days == 0 {
            message = String(localized: "\(countdown.title) is today!")
        } else {
            message = String(localized: "\(state.days) days until \(countdown.title).")
        }
        return (state.days, message)
    }
}
