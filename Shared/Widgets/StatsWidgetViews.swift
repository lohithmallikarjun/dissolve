import Engine
import SwiftUI
import WidgetKit

/// Small: overall strength, and how it moved in 30 days.
struct StatsStrengthSmallView: View {
    let stats: StatsSnapshot?

    var body: some View {
        if let stats, stats.hasHabits {
            let now = stats.currentStrength
            let delta = Int(((now - stats.strength(daysAgo: 30)) * 100).rounded())
            VStack(alignment: .leading, spacing: 4) {
                Label("Strength", systemImage: "bolt.heart.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .widgetAccentable()
                Spacer(minLength: 0)
                Text(now, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Label("\(abs(delta)) pts in 30 days",
                      systemImage: delta > 0 ? "arrow.up.right" : delta < 0 ? "arrow.down.right" : "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .numberStyle()
                Spacer(minLength: 0)
                // A thin sparkline of the last 30 days.
                Sparkline(values: stats.strength.suffix(30).map(\.value))
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .frame(height: 22)
                    .widgetAccentable()
            }
            .widgetURL(URL(string: "dissolve://progress"))
        } else {
            VStack(spacing: 6) {
                Image(systemName: "bolt.heart").font(.title2).foregroundStyle(.green)
                Text("Add a habit in Dissolve").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Medium: this week vs last week, with a bar per day.
struct StatsWeekMediumView: View {
    let stats: StatsSnapshot?

    var body: some View {
        if let stats, stats.hasHabits {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("This week").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(stats.thisWeek.rate ?? 0, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("Last week \((stats.lastWeek.rate ?? 0).formatted(.percent.precision(.fractionLength(0))))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .numberStyle()
                    Text("\(stats.thisWeek.done) of \(stats.thisWeek.due) done")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .numberStyle()
                }
                VStack(spacing: 6) {
                    WeekBars(values: stats.thisWeekDays, color: .green)
                    WeekBars(values: stats.lastWeekDays, color: .secondary)
                    HStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { i in
                            Text(Calendar.current.veryShortWeekdaySymbols[(AppSettings.firstWeekday - 1 + i) % 7])
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .widgetURL(URL(string: "dissolve://progress"))
        } else {
            Text("Add a habit in Dissolve").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct WeekBars: View {
    let values: [Double?]
    let color: Color

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(values.indices, id: \.self) { i in
                GeometryReader { proxy in
                    VStack {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(values[i] == nil ? Color.primary.opacity(0.08) : color)
                            .frame(height: max(3, proxy.size.height * (values[i] ?? 0)))
                    }
                }
                .widgetAccentable(values[i] != nil)
            }
        }
        .frame(height: 34)
    }
}

/// A line through evenly spaced values in 0…1.
struct Sparkline: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }
        let low = values.min() ?? 0, high = values.max() ?? 1
        let span = max(high - low, 0.05)
        for (i, v) in values.enumerated() {
            let point = CGPoint(x: rect.minX + rect.width * CGFloat(i) / CGFloat(values.count - 1),
                                y: rect.maxY - rect.height * CGFloat((v - low) / span))
            i == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        return path
    }
}
