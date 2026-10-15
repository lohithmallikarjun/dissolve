import Charts
import Engine
import SwiftData
import SwiftUI

/// The Stats half of Progress: insight cards, each leading with one plain sentence.
struct StatsView: View {
    @Environment(AppModel.self) private var model
    @Query(filter: #Predicate<Habit> { $0.archivedAt == nil }, sort: \Habit.sortOrder) private var habits: [Habit]
    @Query private var entries: [JournalEntry]

    var body: some View {
        StatsCards(stats: StatsSnapshot.compute(habits: habits, entries: entries, today: model.today))
    }
}

/// The cards themselves (also rendered for CI screenshots).
struct StatsCards: View {
    let stats: StatsSnapshot

    var body: some View {
        VStack(spacing: 16) {
            StrengthCard(stats: stats)
            CompletionCard(stats: stats)
            StreaksCard(stats: stats)
            WeekdayCard(stats: stats)
            JournalStatsCard(stats: stats)
            PatternsCard(stats: stats)
        }
    }
}

/// Title, the insight sentence, then the chart.
struct InsightCard<Content: View>: View {
    let title: LocalizedStringKey
    let symbol: String
    let tint: Color
    let insight: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            Text(insight)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: 1 · Strength

private struct StrengthCard: View {
    let stats: StatsSnapshot
    @State private var days = 30
    @State private var selected: Date?

    var body: some View {
        let points = Array(stats.strength.suffix(days))
        InsightCard(title: "Strength", symbol: "bolt.heart.fill", tint: .green,
                    insight: StatsInsights.strength(stats, days: days)) {
            Picker("Range", selection: $days.animation(.smooth)) {
                Text("30 days").tag(30)
                Text("90 days").tag(90)
                Text("1 year").tag(365)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Chart {
                ForEach(points) { p in
                    AreaMark(x: .value("Date", p.date), y: .value("Strength", p.value * 100))
                        .foregroundStyle(LinearGradient(colors: [.green.opacity(0.25), .green.opacity(0.02)],
                                                        startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Date", p.date), y: .value("Strength", p.value * 100))
                        .foregroundStyle(.green)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
                if let selected, let p = points.min(by: { abs($0.date.timeIntervalSince(selected)) < abs($1.date.timeIntervalSince(selected)) }) {
                    RuleMark(x: .value("Date", p.date))
                        .foregroundStyle(.secondary.opacity(0.4))
                    PointMark(x: .value("Date", p.date), y: .value("Strength", p.value * 100))
                        .foregroundStyle(.green)
                        .symbolSize(64)
                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                            ChartTooltip(title: p.day.formatted(.dateTime.month(.abbreviated).day()),
                                         value: StatsInsights.percent(p.value))
                        }
                }
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%") }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisValueLabel(format: days > 90 ? .dateTime.month(.abbreviated) : .dateTime.day().month(.abbreviated))
                }
            }
            .chartXSelection(value: $selected)
            .frame(height: 170)

            if !stats.habits.isEmpty {
                Text("By habit").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Chart(stats.habits) { habit in
                    BarMark(x: .value("Strength", habit.strength * 100), y: .value("Habit", habit.name), height: 14)
                        .foregroundStyle(habit.color)
                        .cornerRadius(4)
                        .annotation(position: .trailing) {
                            Text(StatsInsights.percent(habit.strength)).font(.caption).foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                }
                .chartXScale(domain: 0...115)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { AxisValueLabel().font(.caption) }
                }
                .frame(height: CGFloat(stats.habits.count) * 26 + 8)
            }
        }
    }
}

// MARK: 2 · Completion rate

private struct CompletionCard: View {
    let stats: StatsSnapshot
    @State private var monthly = false
    @State private var selected: String?

    var body: some View {
        let buckets = monthly ? stats.monthly : stats.weekly
        InsightCard(title: "Completion", symbol: "checkmark.circle.fill", tint: .green,
                    insight: StatsInsights.completion(stats, monthly: monthly)) {
            Picker("Period", selection: $monthly.animation(.smooth)) {
                Text("Weeks").tag(false)
                Text("Months").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Chart(buckets) { bucket in
                if let rate = bucket.tally.rate {
                    BarMark(x: .value("Period", bucket.label), y: .value("Completed", rate * 100), width: .ratio(0.6))
                        .foregroundStyle(.green.opacity(selected == nil || selected == bucket.label ? 1 : 0.4))
                        .cornerRadius(4)
                        .annotation(position: .top) {
                            if selected == bucket.label {
                                ChartTooltip(title: bucket.label,
                                             value: "\(StatsInsights.percent(rate)) · \(bucket.tally.done)/\(bucket.tally.due)")
                            }
                        }
                }
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%") }
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel(collisionResolution: .greedy) { Text(value.as(String.self) ?? "").font(.caption2) }
                }
            }
            .chartXSelection(value: $selected)
            .frame(height: 170)
            Text("Completed ÷ scheduled. Skipped days don't count.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: 3 · Streaks

private struct StreaksCard: View {
    let stats: StatsSnapshot

    var body: some View {
        InsightCard(title: "Streaks", symbol: "flame.fill", tint: .orange, insight: StatsInsights.streaks(stats)) {
            ForEach(stats.habits) { habit in
                let unit = habit.current.unit == .weeks ? String(localized: "wk") : String(localized: "d")
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Circle().fill(habit.color).frame(width: 8, height: 8)
                        Text(habit.name).font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(habit.current.count)\(unit)").font(.subheadline.weight(.semibold)).numberStyle()
                        Text("best \(habit.best.count)\(unit)").font(.caption).foregroundStyle(.secondary).numberStyle()
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(habit.color.opacity(0.18))
                            Capsule().fill(habit.color)
                                .frame(width: proxy.size.width * min(Double(habit.current.count) / Double(max(habit.best.count, 1)), 1))
                        }
                    }
                    .frame(height: 6)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: 4 · Weekdays

private struct WeekdayCard: View {
    let stats: StatsSnapshot
    @State private var selected: String?

    var body: some View {
        let best = stats.weekdays.max { ($0.tally.rate ?? -1) < ($1.tally.rate ?? -1) }?.weekday
        InsightCard(title: "By weekday", symbol: "calendar", tint: .green, insight: StatsInsights.weekdays(stats)) {
            Chart(stats.weekdays) { day in
                if let rate = day.tally.rate {
                    BarMark(x: .value("Day", day.symbol), y: .value("Completed", rate * 100), width: .ratio(0.6))
                        .foregroundStyle(.green.opacity(day.weekday == best ? 1 : 0.45))
                        .cornerRadius(4)
                        .annotation(position: .top) {
                            if day.weekday == best || selected == day.symbol {
                                Text(StatsInsights.percent(rate)).font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                }
            }
            .chartYScale(domain: 0...110)
            .chartYAxis(.hidden)
            .chartXSelection(value: $selected)
            .frame(height: 140)
            Text("Last 90 days, habits with fixed schedules.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: 5 · Journal

private struct JournalStatsCard: View {
    let stats: StatsSnapshot

    var body: some View {
        InsightCard(title: "Journal", symbol: "book.fill", tint: .indigo, insight: StatsInsights.journal(stats)) {
            HStack(spacing: 12) {
                MiniStat(value: "\(stats.journalStreak)", label: "day streak")
                MiniStat(value: "\(stats.journalDays30)", label: "of 30 days")
                MiniStat(value: stats.averageWords30.map { "\($0)" } ?? "—", label: "avg words")
            }
            Text("Entries per month").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Chart(stats.journalMonthly) { month in
                BarMark(x: .value("Month", month.label), y: .value("Entries", month.tally.done), width: .ratio(0.6))
                    .foregroundStyle(.indigo)
                    .cornerRadius(4)
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel()
                }
            }
            .frame(height: 120)
            if stats.mood.count >= 2 {
                Text("Mood, weekly average").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Chart(stats.mood) { point in
                    LineMark(x: .value("Week", point.date), y: .value("Mood", point.mood))
                        .foregroundStyle(.indigo)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Week", point.date), y: .value("Mood", point.mood))
                        .foregroundStyle(.indigo)
                        .symbolSize(30)
                }
                .chartYScale(domain: 1...5)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [1, 3, 5]) { value in
                        AxisGridLine().foregroundStyle(.quaternary)
                        AxisValueLabel {
                            if let v = value.as(Int.self), let mood = Mood(rawValue: v) {
                                Image(systemName: mood.symbol)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { AxisValueLabel(format: .dateTime.month(.abbreviated).day()) }
                }
                .frame(height: 110)
            }
        }
    }
}

// MARK: 6 · Patterns

private struct PatternsCard: View {
    let stats: StatsSnapshot

    var body: some View {
        InsightCard(title: "Patterns", symbol: "sparkle.magnifyingglass", tint: .purple,
                    insight: StatsInsights.patterns(stats)) {
            if stats.daysOfData >= 30 {
                ForEach(stats.patterns) { pattern in
                    Label {
                        Text(pattern.text).font(.subheadline)
                    } icon: {
                        Image(systemName: pattern.symbol).foregroundStyle(.purple)
                    }
                }
                Text("Patterns, not causes: things that happen together don't necessarily cause each other.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ProgressRing(progress: Double(stats.daysOfData) / 30, color: .purple, lineWidth: 5) {
                    Text("\(stats.daysOfData)").font(.caption.weight(.semibold)).numberStyle()
                }
                .frame(width: 48, height: 48)
            }
        }
    }
}

private struct MiniStat: View {
    let value: String
    let label: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.weight(.bold)).numberStyle()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ChartTooltip: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.weight(.semibold)).monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.background, in: .rect(cornerRadius: 8))
        .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
    }
}

#Preview {
    ScrollView {
        StatsView().padding()
    }
    .environment(AppModel())
    .modelContainer(PreviewData.container)
}
