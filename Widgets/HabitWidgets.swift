import AppIntents
import Engine
import SwiftUI
import WidgetKit

struct DashboardEntry: TimelineEntry {
    let date: Date
    let snapshot: DashboardSnapshot
    /// The configured habit, if any.
    var habitID: UUID?
}

/// Refreshes when the app logs something and at each day boundary.
private func dashboardTimeline(habitID: UUID? = nil) -> Timeline<DashboardEntry> {
    Timeline(entries: [DashboardEntry(date: .now, snapshot: DashboardLoader.load(), habitID: habitID)],
             policy: .after(AppSettings.nextDayBoundary()))
}

// MARK: Providers

struct DashboardProvider: TimelineProvider {
    func placeholder(in context: Context) -> DashboardEntry {
        DashboardEntry(date: .now, snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (DashboardEntry) -> Void) {
        completion(DashboardEntry(date: .now, snapshot: DashboardLoader.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DashboardEntry>) -> Void) {
        completion(dashboardTimeline())
    }
}

struct SelectHabitProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DashboardEntry {
        DashboardEntry(date: .now, snapshot: .empty)
    }

    func snapshot(for configuration: SelectHabitIntent, in context: Context) async -> DashboardEntry {
        DashboardEntry(date: .now, snapshot: DashboardLoader.load(), habitID: configuration.habit?.id)
    }

    func timeline(for configuration: SelectHabitIntent, in context: Context) async -> Timeline<DashboardEntry> {
        dashboardTimeline(habitID: configuration.habit?.id)
    }
}

struct YearGridProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DashboardEntry {
        DashboardEntry(date: .now, snapshot: .empty)
    }

    func snapshot(for configuration: YearGridIntent, in context: Context) async -> DashboardEntry {
        DashboardEntry(date: .now, snapshot: DashboardLoader.load(), habitID: configuration.habit?.id)
    }

    func timeline(for configuration: YearGridIntent, in context: Context) async -> Timeline<DashboardEntry> {
        dashboardTimeline(habitID: configuration.habit?.id)
    }
}

// MARK: Widgets

/// One habit (or the next one to do) with a check / +1 button.
struct SingleHabitWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "SingleHabit", intent: SelectHabitIntent.self, provider: SelectHabitProvider()) { entry in
            SingleHabitEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Habit")
        .description("Check off one habit and see its streak.")
        .supportedFamilies(Self.families)
    }

    private static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .accessoryRectangular]
        #else
        [.systemSmall]
        #endif
    }
}

private struct SingleHabitEntryView: View {
    let entry: DashboardEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let habit = entry.snapshot.habit(entry.habitID) ?? entry.snapshot.nextUndone ?? entry.snapshot.habits.first
        switch family {
        case .accessoryRectangular:
            HabitRectangularView(habit: entry.snapshot.habit(entry.habitID) ?? entry.snapshot.nextUndone)
        default:
            SingleHabitSmallView(habit: habit)
        }
    }
}

/// Today's checklist (medium, large) and the % done ring (Lock Screen).
struct TodayHabitsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayHabits", provider: DashboardProvider()) { entry in
            TodayHabitsEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today's Habits")
        .description("Tap a habit to check it off.")
        .supportedFamilies(Self.families)
    }

    private static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemMedium, .systemLarge, .accessoryCircular]
        #else
        [.systemMedium, .systemLarge]
        #endif
    }
}

private struct TodayHabitsEntryView: View {
    let entry: DashboardEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular: PercentCircularView(fraction: entry.snapshot.todayFraction)
        case .systemLarge: ChecklistWidgetView(snapshot: entry.snapshot, maxItems: 7, showsStrip: true)
        default: ChecklistWidgetView(snapshot: entry.snapshot, maxItems: 4)
        }
    }
}

/// The overall consistency grid.
struct ConsistencyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Consistency", provider: DashboardProvider()) { entry in
            ConsistencyEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Consistency")
        .description("Your recent weeks across all habits.")
        .supportedFamilies(Self.families)
    }

    private static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemMedium, .accessoryRectangular]
        #else
        [.systemSmall, .systemMedium]
        #endif
    }
}

private struct ConsistencyEntryView: View {
    let entry: DashboardEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryRectangular: GridDotsRectangularView(snapshot: entry.snapshot)
        case .systemMedium: GridMediumView(snapshot: entry.snapshot)
        default: GridSmallView(snapshot: entry.snapshot)
        }
    }
}

/// A full year: all habits, or a chosen one.
struct YearGridWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "YearGrid", intent: YearGridIntent.self, provider: YearGridProvider()) { entry in
            YearGridEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Year Grid")
        .description("A full year for all habits or one habit.")
        .supportedFamilies([.systemLarge])
    }
}

private struct YearGridEntryView: View {
    let entry: DashboardEntry

    var body: some View {
        if let habit = entry.snapshot.habit(entry.habitID) {
            GridLargeView(title: habit.name, grid: habit.grid, color: habit.color,
                          streak: streakText(habit.streak))
        } else {
            GridLargeView(title: String(localized: "All habits"), grid: entry.snapshot.overall, color: .green,
                          streak: String(localized: "\(entry.snapshot.perfectStreak) perfect days"))
        }
    }

    private func streakText(_ streak: Streak) -> String {
        streak.unit == .weeks ? String(localized: "\(streak.count) weeks") : String(localized: "\(streak.count) days")
    }
}
