import Engine
import SwiftData
import SwiftUI

/// Grid | Stats. Grid: the overall year grid, then a mini grid per habit.
struct ProgressScreen: View {
    enum Mode: String, CaseIterable { case grid, stats }

    enum Range: Int, CaseIterable, Identifiable {
        case quarter = 13, half = 26, year = 53
        var id: Int { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .quarter: "3M"
            case .half: "6M"
            case .year: "1Y"
            }
        }
    }

    @Environment(AppModel.self) private var model
    @Query(filter: #Predicate<Habit> { $0.archivedAt == nil }, sort: \Habit.sortOrder) private var habits: [Habit]
    @State private var mode: Mode = .grid
    @State private var range: Range = .year
    @State private var selection: LocalDate?

    var body: some View {
        let today = model.today
        let engines = habits.map { $0.engine(today: today) }

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("View", selection: $mode.animation(.smooth)) {
                    Text("Grid").tag(Mode.grid)
                    Text("Stats").tag(Mode.stats)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch mode {
                case .grid:
                    overallCard(engines: engines, today: today)
                    ForEach(Array(zip(habits, engines)), id: \.0.id) { habit, engine in
                        NavigationLink(value: habit) {
                            HabitMiniCard(habit: habit, engine: engine)
                        }
                        .buttonStyle(.plain)
                        .scrollTransition(.animated(.smooth)) { content, phase in
                            content.opacity(phase.isIdentity ? 1 : 0.6).scaleEffect(phase.isIdentity ? 1 : 0.96)
                        }
                    }
                case .stats:
                    ComingSoonView(title: "Statistics", symbol: "chart.xyaxis.line", milestone: 5)
                        .frame(minHeight: 300)
                }
            }
            .padding(Metrics.margin)
        }
        .navigationTitle("Progress")
        .navigationDestination(for: Habit.self) { HabitDetailView(habit: $0) }
        #if os(macOS)
        .inspector(isPresented: Binding(get: { selection != nil }, set: { if !$0 { selection = nil } })) {
            if let selection {
                OverallDayDetail(date: selection, habits: habits, engines: engines)
                    .padding()
                    .inspectorColumnWidth(min: 220, ideal: 260)
            }
        }
        #endif
    }

    private func overallCard(engines: [HabitEngine], today: LocalDate) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("All habits").font(.headline)
                    let streak = Overall.perfectDayStreak(engines: engines, today: today)
                    Text(streak == 1 ? "1 perfect day in a row" : "\(streak) perfect days in a row")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .numberStyle()
                        .contentTransition(.numericText(value: Double(streak)))
                }
                Spacer()
                Picker("Range", selection: $range.animation(.smooth)) {
                    ForEach(Range.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            ContributionGrid(
                snapshot: .overall(engines: engines, today: today, weeks: range.rawValue),
                color: .green,
                selection: $selection,
                label: { overallLabel(for: $0, engines: engines) },
                onEdit: { model.showDay($0) }
            ) { date in
                OverallDayDetail(date: date, habits: habits, engines: engines)
                    .frame(width: 260)
            }
            .id(range)
        }
        .card()
    }

    private func overallLabel(for date: LocalDate, engines: [HabitEngine]) -> String {
        let due = engines.compactMap { $0.contribution(on: date) }
        let done = due.filter { $0 >= 1 }.count
        return "\(date.formatted(.dateTime.month(.wide).day())), \(done) of \(due.count) habits"
    }
}

/// What happened across all habits on one day; "Edit Day" opens it on Today.
struct OverallDayDetail: View {
    let date: LocalDate
    let habits: [Habit]
    let engines: [HabitEngine]
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(date.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                .font(.headline)
            ForEach(Array(zip(habits, engines)), id: \.0.id) { habit, engine in
                let status = engine.status(on: date)
                if status != .notScheduled || engine.value(on: date) > 0 {
                    HStack {
                        Image(systemName: icon(status))
                            .foregroundStyle(status == .completed ? habit.color : .secondary)
                        Text(habit.name)
                        Spacer()
                        if habit.kind != .binary {
                            Text(engine.value(on: date).amountText).numberStyle().foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)
                }
            }
            Button("Edit Day") { model.showDay(date) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Text("Tip: tap the cell again to edit.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func icon(_ status: DayStatus) -> String {
        switch status {
        case .completed: "checkmark.circle.fill"
        case .partial: "circle.lefthalf.filled"
        case .skipped: "moon.zzz"
        case .missed: "xmark.circle"
        case .pending, .notScheduled: "circle"
        }
    }
}

/// A habit's last 20 weeks; opens its detail.
struct HabitMiniCard: View {
    let habit: Habit
    let engine: HabitEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: habit.symbol)
                    .foregroundStyle(habit.color)
                Text(habit.name).font(.headline)
                Spacer()
                Label("\(engine.currentStreak.count)", systemImage: "flame.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .numberStyle()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            MiniGrid(snapshot: .habit(engine, weeks: 20), color: habit.color, spacing: 2)
                .frame(height: 64)
        }
        .card(padding: 16)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(habit.name), \(engine.currentStreak.count) streak")
    }
}

#Preview {
    NavigationStack { ProgressScreen() }
        .environment(AppModel())
        .modelContainer(PreviewData.container)
}
