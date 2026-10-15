import AppIntents

/// Siri phrases and the Shortcuts app's ready-made actions. (The Action button can run any of these.)
struct DissolveShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CompleteHabitIntent(),
            phrases: [
                "Log \(\.$habit) in \(.applicationName)",
                "Check off \(\.$habit) in \(.applicationName)",
                "Log a habit in \(.applicationName)",
            ],
            shortTitle: "Log Habit",
            systemImageName: "checkmark.circle")
        AppShortcut(
            intent: TodayProgressIntent(),
            phrases: [
                "How am I doing in \(.applicationName)",
                "Today's habits in \(.applicationName)",
            ],
            shortTitle: "Today's Habits",
            systemImageName: "chart.bar.fill")
        AppShortcut(
            intent: HabitStreakIntent(),
            phrases: ["What's my \(\.$habit) streak in \(.applicationName)"],
            shortTitle: "Habit Streak",
            systemImageName: "flame.fill")
        AppShortcut(
            intent: OpenJournalIntent(),
            phrases: [
                "New journal entry in \(.applicationName)",
                "Open my journal in \(.applicationName)",
            ],
            shortTitle: "New Journal Entry",
            systemImageName: "square.and.pencil")
        AppShortcut(
            intent: AddToJournalIntent(),
            phrases: ["Add to my journal in \(.applicationName)"],
            shortTitle: "Add to Journal",
            systemImageName: "text.append")
        AppShortcut(
            intent: DaysUntilIntent(),
            phrases: ["How long until \(\.$countdown) in \(.applicationName)"],
            shortTitle: "Days Until",
            systemImageName: "timer")
    }
}
