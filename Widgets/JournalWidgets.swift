import SwiftUI
import WidgetKit

struct JournalEntryTimeline: TimelineEntry {
    let date: Date
    let snapshot: JournalSnapshot
}

struct JournalProvider: TimelineProvider {
    func placeholder(in context: Context) -> JournalEntryTimeline {
        JournalEntryTimeline(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (JournalEntryTimeline) -> Void) {
        completion(JournalEntryTimeline(date: .now, snapshot: JournalSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<JournalEntryTimeline>) -> Void) {
        completion(Timeline(entries: [JournalEntryTimeline(date: .now, snapshot: JournalSnapshot.load())],
                            policy: .after(AppSettings.nextDayBoundary())))
    }
}

/// Today's prompt (or a tick) and the Lock Screen streak.
struct JournalTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "JournalToday", provider: JournalProvider()) { entry in
            JournalTodayEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Journal")
        .description("Today's prompt. Tap to write.")
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

private struct JournalTodayEntryView: View {
    let entry: JournalEntryTimeline
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryRectangular: JournalStreakRectangularView(snapshot: entry.snapshot)
        default: JournalSmallView(snapshot: entry.snapshot)
        }
    }
}

/// "On this day": a photo and the first line of an older entry.
struct OnThisDayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OnThisDay", provider: JournalProvider()) { entry in
            JournalMemoryView(snapshot: entry.snapshot)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("On This Day")
        .description("A journal memory from an earlier year.")
        .supportedFamilies([.systemMedium])
    }
}
