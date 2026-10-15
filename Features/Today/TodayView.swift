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
    #if os(macOS)
    @State private var selectedIndex = 0
    @FocusState private var focused: Bool
    #endif

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
                        RecentStrip(engines: engines, today: today)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens Progress")

                    ForEach(Array(zip(habits, engines).enumerated()), id: \.element.0.id) { index, pair in
                        let (habit, engine) = pair
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
                        .accessibilitySortPriority(Double(-index))
                        #if os(macOS)
                        .overlay {
                            if focused && index == selectedIndex {
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .strokeBorder(Color.accentColor, lineWidth: 2)
                            }
                        }
                        #endif
                    }
                }
            }
            .padding(Metrics.margin)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        #if os(macOS)
        // Space toggles the selected habit; ↑ / ↓ move the selection.
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.space) {
            guard habits.indices.contains(selectedIndex) else { return .ignored }
            withAnimation(.snappy) { HabitActions.primaryAction(habits[selectedIndex], on: model.day, in: context) }
            return .handled
        }
        .onKeyPress(.downArrow) {
            selectedIndex = min(selectedIndex + 1, max(habits.count - 1, 0))
            return .handled
        }
        .onKeyPress(.upArrow) {
            selectedIndex = max(selectedIndex - 1, 0)
            return .handled
        }
        .onAppear { focused = true }
        #endif
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

/// The last 12 weeks across all habits, with the perfect-day streak. Taps through to Progress.
private struct RecentStrip: View {
    let engines: [HabitEngine]
    let today: LocalDate

    var body: some View {
        let streak = Overall.perfectDayStreak(engines: engines, today: today)
        let week = (0..<7).compactMap { Overall.fraction(on: today.adding(days: -$0), engines: engines) }
        let weekAverage = week.isEmpty ? 0 : week.reduce(0, +) / Double(week.count)
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Last 12 weeks")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Label {
                    Text(streak, format: .number)
                        .contentTransition(.numericText(value: Double(streak)))
                } icon: {
                    Image(systemName: "flame.fill").foregroundStyle(.orange)
                }
                .font(.title2.weight(.bold))
                .numberStyle()
                Text(streak == 1 ? "perfect day" : "perfect days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(Int((weekAverage * 100).rounded()))% this week")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .numberStyle()
            }
            .fixedSize()
            MiniGrid(snapshot: .overall(engines: engines, today: today, weeks: 12), color: .green, spacing: 3)
                .frame(maxWidth: .infinity, maxHeight: 120)
        }
        .card(padding: 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Last 12 weeks. \(streak) perfect days in a row. \(Int((weekAverage * 100).rounded())) percent this week.")
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
