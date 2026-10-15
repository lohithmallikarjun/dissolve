#if os(iOS)
import ActivityKit
import SwiftUI
import WidgetKit

/// Lock Screen banner + Dynamic Island for a countdown's final hours.
struct CountdownLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CountdownActivityAttributes.self) { context in
            let color = HabitColor.named(context.attributes.colorName).color
            HStack(spacing: 14) {
                Image(systemName: context.attributes.symbol)
                    .font(.title2)
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.title).font(.headline)
                    Text(context.state.target, style: .time).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Text(context.state.target, style: .timer)
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 140)
            }
            .padding(16)
            .activityBackgroundTint(color.opacity(0.18))
            .activitySystemActionForegroundColor(color)
            .widgetURL(URL(string: "dissolve://life"))
        } dynamicIsland: { context in
            let color = HabitColor.named(context.attributes.colorName).color
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.title, systemImage: context.attributes.symbol)
                        .font(.headline)
                        .foregroundStyle(color)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.target, style: .timer)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.target, format: .dateTime.weekday(.wide).hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: context.attributes.symbol).foregroundStyle(color)
            } compactTrailing: {
                Text(context.state.target, style: .timer)
                    .monospacedDigit()
                    .frame(maxWidth: 64)
                    .multilineTextAlignment(.trailing)
            } minimal: {
                Image(systemName: context.attributes.symbol).foregroundStyle(color)
            }
            .widgetURL(URL(string: "dissolve://life"))
            .keylineTint(color)
        }
    }
}
#endif
