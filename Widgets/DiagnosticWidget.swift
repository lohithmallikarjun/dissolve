import AppIntents
import SwiftData
import SwiftUI
import WidgetKit

/// Milestone 0 test widget: shows the value the app last wrote to the App Group,
/// read both from shared UserDefaults and from the shared SwiftData store.
struct DiagnosticWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "DiagnosticWidget", intent: DiagnosticConfigIntent.self, provider: DiagnosticProvider()) { entry in
            DiagnosticWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Dissolve Test")
        .description("Milestone 0: shows the value the app wrote.")
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

struct DiagnosticEntry: TimelineEntry {
    let date: Date
    let groupAvailable: Bool
    let counter: Int
    let updatedAt: Date?
    /// nil when the shared SwiftData store couldn't be opened.
    let latestPing: Int?

    static let sample = DiagnosticEntry(date: .now, groupAvailable: true, counter: 7, updatedAt: .now, latestPing: 7)
}

/// No options yet; real widgets will let you pick a habit or countdown.
struct DiagnosticConfigIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Dissolve Test"
}

struct DiagnosticProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DiagnosticEntry { .sample }

    func snapshot(for configuration: DiagnosticConfigIntent, in context: Context) async -> DiagnosticEntry {
        context.isPreview ? .sample : Self.load()
    }

    func timeline(for configuration: DiagnosticConfigIntent, in context: Context) async -> Timeline<DiagnosticEntry> {
        // The app reloads timelines after every write, so no polling.
        Timeline(entries: [Self.load()], policy: .never)
    }

    static func load() -> DiagnosticEntry {
        let defaults = AppGroup.defaults
        var latestPing: Int?
        if AppGroup.containerURL != nil, let container = try? SharedModelContainer.appGroup() {
            var descriptor = FetchDescriptor<DiagnosticPing>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
            descriptor.fetchLimit = 1
            latestPing = (try? ModelContext(container).fetch(descriptor))?.first?.value ?? 0
        }
        return DiagnosticEntry(
            date: .now,
            groupAvailable: AppGroup.containerURL != nil,
            counter: defaults.integer(forKey: SharedKeys.diagnosticCounter),
            updatedAt: defaults.object(forKey: SharedKeys.diagnosticUpdatedAt) as? Date,
            latestPing: latestPing)
    }
}

struct DiagnosticWidgetView: View {
    let entry: DiagnosticEntry
    @Environment(\.widgetFamily) private var family

    private var allGood: Bool {
        entry.groupAvailable && entry.latestPing == entry.counter
    }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text("Dissolve test").font(.headline).widgetAccentable()
                Text("Value \(entry.counter)").monospacedDigit()
                Text(allGood ? "Shared ✓" : "Not shared ✗")
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                Label("Dissolve", systemImage: allGood ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(allGood ? .green : .red)
                    .widgetAccentable()
                Spacer(minLength: 0)
                Text(entry.counter, format: .number)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(entry.counter)))
                Text(entry.latestPing.map { "SwiftData: \($0)" } ?? "SwiftData: ✗")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let updatedAt = entry.updatedAt {
                    Text(updatedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview(as: .systemSmall) {
    DiagnosticWidget()
} timeline: {
    DiagnosticEntry.sample
    DiagnosticEntry(date: .now, groupAvailable: false, counter: 0, updatedAt: nil, latestPing: nil)
}
