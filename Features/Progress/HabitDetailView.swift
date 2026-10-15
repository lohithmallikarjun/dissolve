import Engine
import SwiftData
import SwiftUI

/// One habit: streaks, strength, the year grid (tap a day → popover, tap again → edit), notes.
struct HabitDetailView: View {
    let habit: Habit

    @Environment(AppModel.self) private var model
    @State private var selection: LocalDate?
    @State private var editingDate: LocalDate?
    @State private var editingHabit = false

    var body: some View {
        let engine = habit.engine(today: model.today)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(engine)
                HStack(spacing: 12) {
                    StatTile(title: "Streak", value: engine.currentStreak.count,
                             unit: engine.currentStreak.unit == .weeks ? "weeks" : "days", symbol: "flame.fill", color: .orange)
                    StatTile(title: "Best", value: engine.bestStreak.count,
                             unit: engine.bestStreak.unit == .weeks ? "weeks" : "days", symbol: "trophy.fill", color: .yellow)
                    StatTile(title: "Strength", value: Int((engine.strength * 100).rounded()),
                             unit: "%", symbol: "bolt.heart.fill", color: habit.color)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Past year").font(.headline)
                    ContributionGrid(
                        snapshot: .habit(engine, weeks: 53),
                        color: habit.color,
                        selection: $selection,
                        label: { label(for: $0, engine: engine) },
                        onEdit: { editingDate = $0 }
                    ) { date in
                        HabitDayPopover(habit: habit, engine: engine, date: date)
                            .frame(width: 240)
                    }
                }
                .card()

                notes
            }
            .padding(Metrics.margin)
        }
        .navigationTitle(habit.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit", systemImage: "pencil") { editingHabit = true }
            }
        }
        .sheet(isPresented: $editingHabit) { HabitEditorView(habit: habit, nextSortOrder: 0) }
        .sheet(item: $editingDate) { DayEditorView(habit: habit, date: $0) }
        #if os(macOS)
        .inspector(isPresented: Binding(get: { selection != nil }, set: { if !$0 { selection = nil } })) {
            if let selection {
                DayEditorView(habit: habit, date: selection, showsDoneButton: false)
                    .inspectorColumnWidth(min: 260, ideal: 300)
            }
        }
        #endif
    }

    private func header(_ engine: HabitEngine) -> some View {
        HStack(spacing: 16) {
            Image(systemName: habit.symbol)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(habit.color, in: .circle)
            VStack(alignment: .leading, spacing: 4) {
                Text(habit.rule(on: engine.today).summary).font(.headline)
                Text(typeText).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .card()
    }

    private var typeText: String {
        let unit = habit.unit.isEmpty ? "" : " \(habit.unit)"
        return switch habit.kind {
        case .binary: String(localized: "Done or not done")
        case .quantity: String(localized: "Goal: \(habit.target.amountText)\(unit)")
        case .timed: String(localized: "Goal: \(habit.target.amountText) min")
        case .limit: String(localized: "At most \(habit.target.amountText)\(unit)")
        }
    }

    @ViewBuilder
    private var notes: some View {
        let withNotes = habit.logs.filter { !$0.note.isEmpty }.sorted { $0.date > $1.date }.prefix(10)
        if !withNotes.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Notes").font(.headline)
                ForEach(Array(withNotes)) { log in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LocalDate(log.date)?.formatted(.dateTime.month(.abbreviated).day().year()) ?? log.date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(log.note)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private func label(for date: LocalDate, engine: HabitEngine) -> String {
        let day = date.formatted(.dateTime.month(.wide).day())
        switch engine.status(on: date) {
        case .completed: return "\(day), done"
        case .partial: return "\(day), \(engine.value(on: date).amountText) of \(habit.target.amountText)"
        case .skipped: return "\(day), skipped"
        case .missed: return "\(day), missed"
        case .pending: return "\(day), not done yet"
        case .notScheduled: return "\(day), not scheduled"
        }
    }
}

struct HabitDayPopover: View {
    let habit: Habit
    let engine: HabitEngine
    let date: LocalDate

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.headline)
            if habit.kind != .binary {
                Text("\(engine.value(on: date).amountText) of \(habit.target.amountText) \(habit.unit)")
                    .numberStyle()
            }
            if let note = habit.log(on: date)?.note, !note.isEmpty {
                Text(note).font(.subheadline).foregroundStyle(.secondary)
            }
            Text("Tap again to edit.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct StatTile: View {
    let title: LocalizedStringKey
    let value: Int
    let unit: LocalizedStringKey
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value, format: .number)
                    .font(.title.weight(.bold))
                    .numberStyle()
                    .contentTransition(.numericText(value: Double(value)))
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
        .accessibilityElement(children: .combine)
    }
}
