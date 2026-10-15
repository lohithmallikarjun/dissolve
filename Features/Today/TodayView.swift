import Engine
import SwiftData
import SwiftUI

/// The day's habits: a 12-week strip, then one card per habit. Any past day can be shown and edited.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Habit> { $0.archivedAt == nil }, sort: \Habit.sortOrder) private var habits: [Habit]

    @State private var editingHabit: Habit?
    @State private var addingHabit = false
    @State private var detailHabit: Habit?
    @State private var dayEditorHabit: Habit?

    var body: some View {
        let today = model.today
        let day = model.day
        let engines = habits.map { $0.engine(today: today) }
        let fraction = Overall.fraction(on: day, engines: engines) ?? 0

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DaySwitcher(day: day, today: today, fraction: fraction)

                if habits.isEmpty {
                    emptyState
                } else {
                    Button {
                        withAnimation(.snappy) { model.section = .progress }
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Last 12 weeks").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                            MiniGrid(snapshot: .overall(engines: engines, today: today, weeks: 12), color: .green, spacing: 3)
                                .frame(height: 96)
                        }
                        .card(padding: 16)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Last 12 weeks. Opens Progress.")

                    ForEach(Array(zip(habits, engines)), id: \.0.id) { habit, engine in
                        HabitCard(habit: habit, engine: engine, day: day) { action in
                            switch action {
                            case .edit: editingHabit = habit
                            case .details: detailHabit = habit
                            case .editDay: dayEditorHabit = habit
                            }
                        }
                        .scrollTransition(.animated(.smooth)) { content, phase in
                            content.opacity(phase.isIdentity ? 1 : 0.6).scaleEffect(phase.isIdentity ? 1 : 0.96)
                        }
                    }
                }
            }
            .padding(Metrics.margin)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(day == today ? String(localized: "Today") : day.relativeName(today: today))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Habit", systemImage: "plus") { addingHabit = true }
            }
        }
        .sheet(isPresented: $addingHabit) {
            HabitEditorView(habit: nil, nextSortOrder: (habits.map(\.sortOrder).max() ?? -1) + 1)
        }
        .sheet(item: $editingHabit) { habit in
            HabitEditorView(habit: habit, nextSortOrder: 0)
        }
        .sheet(item: $dayEditorHabit) { habit in
            DayEditorView(habit: habit, date: day)
        }
        .navigationDestination(item: $detailHabit) { habit in
            HabitDetailView(habit: habit)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No habits yet", systemImage: "checkmark.circle")
        } description: {
            Text("Add the first thing you want to do every day.")
        } actions: {
            Button("New Habit") { addingHabit = true }
                .buttonStyle(.borderedProminent)
        }
        .padding(.top, 40)
    }
}

/// "‹ Today ›" with the day's overall progress ring.
private struct DaySwitcher: View {
    let day: LocalDate
    let today: LocalDate
    let fraction: Double
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            Button("Previous Day", systemImage: "chevron.left") {
                withAnimation(.snappy) { model.moveDay(by: -1) }
            }
            .labelStyle(.iconOnly)

            VStack(alignment: .leading, spacing: 2) {
                Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.headline)
                    .contentTransition(.numericText())
                if day != today {
                    Button("Back to Today") { withAnimation(.snappy) { model.showDay(today) } }
                        .font(.caption)
                }
            }

            Button("Next Day", systemImage: "chevron.right") {
                withAnimation(.snappy) { model.moveDay(by: 1) }
            }
            .labelStyle(.iconOnly)
            .disabled(day >= today)

            Spacer()

            ProgressRing(progress: fraction, color: .green, lineWidth: 6) {
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.caption.weight(.semibold))
                    .numberStyle()
                    .contentTransition(.numericText(value: fraction))
            }
            .frame(width: 52, height: 52)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Int((fraction * 100).rounded())) percent done")
        }
        .buttonStyle(.borderless)
        .font(.title3)
    }
}

/// A ring that fills with `.snappy` motion.
struct ProgressRing<Label: View>: View {
    let progress: Double
    let color: Color
    var lineWidth: CGFloat = 5
    @ViewBuilder var label: Label

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(progress, 1)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.snappy, value: progress)
            label
        }
    }
}

#Preview {
    NavigationStack { TodayView() }
        .environment(AppModel())
        .modelContainer(PreviewData.container)
}
