import AppIntents
import Engine
import SwiftUI
import WidgetKit

/// The round check / +1 control used in widgets. Interactive via `LogHabitIntent`.
struct HabitCheckButton: View {
    let habit: HabitSummary
    var size: CGFloat = 44

    var body: some View {
        Button(intent: LogHabitIntent(habitID: habit.id)) {
            ZStack {
                if habit.kind == .binary {
                    Circle().fill(habit.isDone ? habit.color : habit.color.opacity(0.18))
                } else {
                    Circle().stroke(habit.color.opacity(0.2), lineWidth: size * 0.1)
                    Circle()
                        .trim(from: 0, to: habit.kind == .limit ? 0 : habit.progress)
                        .stroke(habit.color, style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Image(systemName: icon)
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundStyle(habit.kind == .binary && habit.isDone ? .white : habit.color)
            }
            .frame(width: size, height: size)
            .widgetAccentable()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(habit.kind == .binary ? "Check off \(habit.name)" : "Add one to \(habit.name)")
    }

    private var icon: String {
        switch habit.kind {
        case .binary: habit.isDone ? "checkmark" : habit.symbol
        case .quantity, .timed: habit.progress >= 1 ? "checkmark" : "plus"
        case .limit: "plus"
        }
    }
}

/// Small: one habit with its button and streak.
struct SingleHabitSmallView: View {
    let habit: HabitSummary?

    var body: some View {
        if let habit {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Image(systemName: habit.symbol)
                        .font(.headline)
                        .foregroundStyle(habit.color)
                        .widgetAccentable()
                    Spacer()
                    HabitCheckButton(habit: habit, size: 46)
                }
                Spacer(minLength: 4)
                Text(habit.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(habit.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .numberStyle()
                Label("\(habit.streak.count)", systemImage: "flame.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .numberStyle()
                    .padding(.top, 2)
            }
        } else {
            NoHabitsView()
        }
    }
}

/// Lock Screen rectangular: the next habit with a check button.
struct HabitRectangularView: View {
    let habit: HabitSummary?

    var body: some View {
        if let habit {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(habit.name).font(.headline).lineLimit(1).widgetAccentable()
                    Text(habit.detail).font(.caption).lineLimit(1)
                    Label("\(habit.streak.count)", systemImage: "flame.fill").font(.caption2)
                }
                Spacer(minLength: 0)
                HabitCheckButton(habit: habit, size: 34)
            }
        } else {
            Label("All done", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .widgetAccentable()
        }
    }
}

/// Medium / Large: today's checklist; Large adds a 12-week strip.
struct ChecklistWidgetView: View {
    let snapshot: DashboardSnapshot
    let maxItems: Int
    var showsStrip = false

    var body: some View {
        let items = Array(snapshot.dueToday.prefix(maxItems))
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Today").font(.headline)
                Spacer()
                Text("\(snapshot.doneCount)/\(snapshot.dueToday.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                    .numberStyle()
                    .widgetAccentable()
            }
            if items.isEmpty {
                Spacer()
                NoHabitsView()
                Spacer()
            } else {
                ForEach(items) { habit in
                    HStack(spacing: 10) {
                        HabitCheckButton(habit: habit, size: 26)
                        Text(habit.name)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .strikethrough(habit.isDone && habit.kind != .limit, color: .secondary)
                        Spacer(minLength: 4)
                        Text(habit.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .numberStyle()
                    }
                }
                Spacer(minLength: 0)
            }
            if showsStrip {
                MiniGrid(snapshot: snapshot.overall.suffix(weeks: 12), color: .green, spacing: 3)
                    .frame(height: 70)
            }
        }
    }
}

/// Lock Screen circular: today's % done.
struct PercentCircularView: View {
    let fraction: Double

    var body: some View {
        Gauge(value: fraction) {
            Image(systemName: "checkmark")
        } currentValueLabel: {
            Text("\(Int((fraction * 100).rounded()))")
                .numberStyle()
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
        .accessibilityLabel("\(Int((fraction * 100).rounded())) percent of today's habits done")
    }
}

struct NoHabitsView: View {
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "plus.circle").font(.title2).foregroundStyle(.green)
            Text("Add a habit in Dissolve").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
