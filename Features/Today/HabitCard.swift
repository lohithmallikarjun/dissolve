import Engine
import SwiftData
import SwiftUI

/// A big tappable habit card: tap to check off (or +1), long-press for more.
struct HabitCard: View {
    enum Action { case edit, details, editDay }

    let habit: Habit
    let engine: HabitEngine
    let day: LocalDate
    let perform: (Action) -> Void

    @Environment(\.modelContext) private var context

    private var status: DayStatus { engine.status(on: day) }
    private var progress: Double { engine.progress(on: day) }
    private var value: Double { engine.value(on: day) }

    var body: some View {
        HStack(spacing: 16) {
            indicator
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(habit.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .numberStyle()
                    .contentTransition(.numericText(value: value))
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                let streak = engine.currentStreak
                Label {
                    Text(streak.count, format: .number)
                        .contentTransition(.numericText(value: Double(streak.count)))
                } icon: {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(streak.count > 0 ? .orange : .secondary)
                        .symbolEffect(.bounce, value: streak.count)
                }
                .font(.headline)
                .numberStyle()
                .accessibilityLabel(streak.unit == .weeks ? "\(streak.count) week streak" : "\(streak.count) day streak")

                Text("\(Int((engine.strength * 100).rounded()))% strong")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .numberStyle()
                    .contentTransition(.numericText(value: engine.strength))
            }
        }
        .card()
        .contentShape(.rect(cornerRadius: 22))
        .onTapGesture {
            withAnimation(.snappy) { HabitActions.primaryAction(habit, on: day, in: context) }
        }
        .sensoryFeedback(.success, trigger: status == .completed) { _, done in done && habit.kind != .limit }
        .sensoryFeedback(.increase, trigger: value) { old, new in new > old && habit.kind != .binary }
        .contextMenu { menu }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(habit.kind == .binary ? "Double-tap to check off" : "Double-tap to add \(habit.step.amountText)")
    }

    @ViewBuilder
    private var indicator: some View {
        let color = habit.color
        switch habit.kind {
        case .binary:
            let done = status == .completed
            ZStack {
                Circle().fill(done ? color : color.opacity(0.15))
                    .animation(.snappy, value: done)
                Image(systemName: habit.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(color)
                    .opacity(done ? 0 : 1)
                    .scaleEffect(done ? 0.4 : 1)
                    .animation(.snappy, value: done)
                // The checkmark draws itself on.
                Image(systemName: "checkmark")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .symbolEffect(.drawOn, isActive: !done)
            }
            .overlay { skippedOverlay }
        case .quantity, .timed:
            ProgressRing(progress: progress, color: color, lineWidth: 5) {
                // Symbols with variable layers fill up with progress.
                Image(systemName: progress >= 1 ? "checkmark" : habit.symbol, variableValue: progress)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(color)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: value)
            }
            .overlay { skippedOverlay }
        case .limit:
            let over = value > habit.target
            ZStack {
                Circle().fill((over ? Color.red : color).opacity(0.15))
                Image(systemName: over ? "exclamationmark" : habit.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(over ? .red : color)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
    }

    @ViewBuilder
    private var skippedOverlay: some View {
        if status == .skipped {
            Circle().strokeBorder(habit.color, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
        }
    }

    private var detail: String { habit.detailText(engine: engine, day: day) }

    @ViewBuilder
    private var menu: some View {
        if habit.kind != .binary {
            Button("Add \(habit.step.amountText)", systemImage: "plus") {
                HabitActions.increment(habit, by: habit.step, on: day, in: context)
            }
            Button("Remove \(habit.step.amountText)", systemImage: "minus") {
                HabitActions.increment(habit, by: -habit.step, on: day, in: context)
            }
            if habit.kind != .limit {
                Button("Mark Done", systemImage: "checkmark") { HabitActions.complete(habit, on: day, in: context) }
            }
        }
        if status == .skipped {
            Button("Unskip", systemImage: "arrow.uturn.backward") {
                HabitActions.setSkipped(false, for: habit, on: day, in: context)
            }
        } else {
            Button("Skip (Rest Day)", systemImage: "moon.zzz") {
                HabitActions.setSkipped(true, for: habit, on: day, in: context)
            }
        }
        Button("Edit Day…", systemImage: "square.and.pencil") { perform(.editDay) }
        Button("Clear Day", systemImage: "eraser", role: .destructive) {
            HabitActions.reset(habit, on: day, in: context)
        }
        Divider()
        Button("Details", systemImage: "chart.bar.xaxis") { perform(.details) }
        Button("Edit Habit…", systemImage: "pencil") { perform(.edit) }
    }
}
