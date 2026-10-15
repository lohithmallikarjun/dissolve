import SwiftUI
import WidgetKit

struct StatsEntry: TimelineEntry {
    let date: Date
    let stats: StatsSnapshot?
}

struct StatsProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatsEntry { StatsEntry(date: .now, stats: nil) }

    func getSnapshot(in context: Context, completion: @escaping (StatsEntry) -> Void) {
        completion(StatsEntry(date: .now, stats: StatsSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatsEntry>) -> Void) {
        completion(Timeline(entries: [StatsEntry(date: .now, stats: StatsSnapshot.load())],
                            policy: .after(AppSettings.nextDayBoundary())))
    }
}

/// Overall strength (small) and this week vs last week (medium).
struct StatsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Stats", provider: StatsProvider()) { entry in
            StatsEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Stats")
        .description("Your overall strength, or this week against last week.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct StatsEntryView: View {
    let entry: StatsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemMedium: StatsWeekMediumView(stats: entry.stats)
        default: StatsStrengthSmallView(stats: entry.stats)
        }
    }
}
