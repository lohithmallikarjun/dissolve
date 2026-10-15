import AppIntents
import SwiftUI
import WidgetKit

struct TimeEntry: TimelineEntry {
    let date: Date
    let snapshot: TimeSnapshot
    var countdownID: UUID?
}

/// Refreshes at each day boundary (days left change), plus when a timed countdown arrives.
private func timeTimeline(countdownID: UUID? = nil) -> Timeline<TimeEntry> {
    let snapshot = TimeSnapshot.load()
    var refresh = AppSettings.nextDayBoundary()
    if let soonest = snapshot.countdowns.first(where: { !$0.isAllDay && !$0.hasArrived && !$0.countUp }),
       soonest.occurrence < refresh {
        refresh = soonest.occurrence.addingTimeInterval(1)
    }
    return Timeline(entries: [TimeEntry(date: .now, snapshot: snapshot, countdownID: countdownID)], policy: .after(refresh))
}

struct TimeProvider: TimelineProvider {
    func placeholder(in context: Context) -> TimeEntry { TimeEntry(date: .now, snapshot: .empty) }
    func getSnapshot(in context: Context, completion: @escaping (TimeEntry) -> Void) {
        completion(TimeEntry(date: .now, snapshot: TimeSnapshot.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TimeEntry>) -> Void) {
        completion(timeTimeline())
    }
}

struct CountdownProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TimeEntry { TimeEntry(date: .now, snapshot: .empty) }
    func snapshot(for configuration: SelectCountdownIntent, in context: Context) async -> TimeEntry {
        TimeEntry(date: .now, snapshot: TimeSnapshot.load(), countdownID: configuration.countdown?.id)
    }
    func timeline(for configuration: SelectCountdownIntent, in context: Context) async -> Timeline<TimeEntry> {
        timeTimeline(countdownID: configuration.countdown?.id)
    }
}

/// One countdown: small, Lock Screen inline and circular.
struct CountdownWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Countdown", intent: SelectCountdownIntent.self, provider: CountdownProvider()) { entry in
            CountdownEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Countdown")
        .description("Days to go, with a ring from when you started.")
        .supportedFamilies(Self.families)
    }

    private static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .accessoryInline, .accessoryCircular]
        #else
        [.systemSmall]
        #endif
    }
}

private struct CountdownEntryView: View {
    let entry: TimeEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let countdown = entry.snapshot.countdown(entry.countdownID)
        switch family {
        case .accessoryInline: CountdownInlineView(countdown: countdown)
        case .accessoryCircular: CountdownCircularView(countdown: countdown)
        default: CountdownSmallView(countdown: countdown)
        }
    }
}

/// The next three countdowns.
struct UpcomingCountdownsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UpcomingCountdowns", provider: TimeProvider()) { entry in
            CountdownListView(countdowns: entry.snapshot.countdowns)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Upcoming")
        .description("Your next three countdowns.")
        .supportedFamilies([.systemMedium])
    }
}

/// % of life remaining (small, Lock Screen) and one dot per year (large).
struct LifeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Life", provider: TimeProvider()) { entry in
            LifeEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Life")
        .description("How much of your life lies ahead.")
        .supportedFamilies(Self.families)
    }

    private static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemLarge, .accessoryCircular]
        #else
        [.systemSmall, .systemLarge]
        #endif
    }
}

private struct LifeEntryView: View {
    let entry: TimeEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemLarge: LifeYearsView(life: entry.snapshot.life)
        case .accessoryCircular: LifeCircularView(life: entry.snapshot.life)
        default: LifeSmallView(life: entry.snapshot.life)
        }
    }
}
