#if os(iOS)
import AppIntents
import SwiftData
import SwiftUI
import WidgetKit

/// Control Center / Lock Screen / Action button controls.
struct ControlsBundle: WidgetBundle {
    var body: some Widget {
        LogHabitControl()
        NewJournalEntryControl()
    }
}

/// Which habit a "Log <habit>" control logs.
struct SelectHabitControlIntent: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Habit"

    @Parameter(title: "Habit")
    var habit: HabitEntity?
}

struct HabitControlValue {
    var id: UUID?
    var name: String
    var symbol: String
    var isDone: Bool
}

struct HabitControlProvider: AppIntentControlValueProvider {
    func previewValue(configuration: SelectHabitControlIntent) -> HabitControlValue {
        HabitControlValue(id: configuration.habit?.id, name: configuration.habit?.name ?? String(localized: "Habit"),
                          symbol: "checkmark.circle", isDone: false)
    }

    func currentValue(configuration: SelectHabitControlIntent) async throws -> HabitControlValue {
        guard let id = configuration.habit?.id else { return previewValue(configuration: configuration) }
        let snapshot = DashboardLoader.load()
        guard let habit = snapshot.habit(id) else { return previewValue(configuration: configuration) }
        return HabitControlValue(id: id, name: habit.name, symbol: habit.symbol, isDone: habit.isDone)
    }
}

/// "Log <habit>" in Control Center: one tap checks it off (or adds one).
struct LogHabitControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "com.lohith.dissolve.logHabit", provider: HabitControlProvider()) { value in
            ControlWidgetButton(action: LogHabitIntent(habitID: value.id)) {
                Label(value.isDone ? "\(value.name) ✓" : value.name,
                      systemImage: value.isDone ? "checkmark.circle.fill" : value.symbol)
            } actionLabel: { isActive in
                Label(isActive ? "Logging…" : "Logged", systemImage: "checkmark.circle.fill")
            }
            .tint(.green)
        }
        .displayName("Log Habit")
        .description("Check off a habit from Control Center.")
        .promptsForUserConfiguration()
    }
}

/// Opens today's journal entry.
struct NewJournalEntryControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.lohith.dissolve.newJournalEntry") {
            ControlWidgetButton(action: OpenJournalIntent()) {
                Label("New Journal Entry", systemImage: "square.and.pencil")
            }
            .tint(.indigo)
        }
        .displayName("New Journal Entry")
        .description("Opens today's journal entry.")
    }
}
#endif
