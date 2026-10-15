import Engine
import Foundation
import SwiftData
import SwiftUI

/// Everything widgets need, computed once per timeline refresh.
struct HabitSummary: Identifiable, Sendable {
    let id: UUID
    let name: String
    let symbol: String
    let colorName: String
    let kind: HabitKind
    let value: Double
    let target: Double
    let progress: Double
    let status: DayStatus
    let streak: Streak
    let strength: Double
    let detail: String
    /// The last 53 weeks.
    let grid: GridSnapshot

    var color: Color { HabitColor.named(colorName).color }
    var isDone: Bool { status == .completed }
    var isDue: Bool { status != .notScheduled || value > 0 }
}

struct DashboardSnapshot: Sendable {
    let today: LocalDate
    let habits: [HabitSummary]
    /// The last 53 weeks across all habits.
    let overall: GridSnapshot
    let todayFraction: Double
    let perfectStreak: Int

    var dueToday: [HabitSummary] { habits.filter(\.isDue) }
    var doneCount: Int { dueToday.filter(\.isDone).count }
    var nextUndone: HabitSummary? { dueToday.first { !$0.isDone && $0.kind != .limit } }

    func habit(_ id: UUID?) -> HabitSummary? { id.flatMap { id in habits.first { $0.id == id } } }

    static let empty = DashboardSnapshot(
        today: AppSettings.today(), habits: [],
        overall: .overall(engines: [], today: AppSettings.today(), weeks: 53),
        todayFraction: 0, perfectStreak: 0)
}

enum DashboardLoader {
    static func load(context: ModelContext, today: LocalDate = AppSettings.today()) -> DashboardSnapshot {
        let descriptor = FetchDescriptor<Habit>(
            predicate: #Predicate { $0.archivedAt == nil }, sortBy: [SortDescriptor(\.sortOrder)])
        let habits = (try? context.fetch(descriptor)) ?? []
        let engines = habits.map { $0.engine(today: today) }
        let summaries = zip(habits, engines).map { habit, engine in
            HabitSummary(
                id: habit.id, name: habit.name, symbol: habit.symbol, colorName: habit.colorName,
                kind: habit.kind, value: engine.value(on: today), target: habit.target,
                progress: engine.progress(on: today), status: engine.status(on: today),
                streak: engine.currentStreak, strength: engine.strength,
                detail: habit.detailText(engine: engine, day: today),
                grid: .habit(engine, weeks: 53))
        }
        return DashboardSnapshot(
            today: today, habits: summaries,
            overall: .overall(engines: engines, today: today, weeks: 53),
            todayFraction: Overall.fraction(on: today, engines: engines) ?? 0,
            perfectStreak: Overall.perfectDayStreak(engines: engines, today: today))
    }

    /// Reads the shared App Group store (widgets).
    static func load() -> DashboardSnapshot {
        guard let container = try? SharedModelContainer.appGroup() else { return .empty }
        return load(context: ModelContext(container))
    }
}

extension GridSnapshot {
    /// The same grid cut to its last `weeks` columns.
    func suffix(weeks: Int) -> GridSnapshot {
        let n = min(weeks, layout.weeks)
        let source = self
        return GridSnapshot(layout: GridLayout(endingAt: layout.today, weeks: n, firstWeekday: layout.firstWeekday)) { date in
            let offset = source.layout.start.days(to: date)
            return source.cells[offset / 7][offset % 7] ?? .empty
        }
    }
}

extension Habit {
    /// "3 of 8 glasses", "1 of 3 this week", "Mon, Wed, Fri", …
    func detailText(engine: HabitEngine, day: LocalDate) -> String {
        if engine.status(on: day) == .skipped { return String(localized: "Skipped · rest day") }
        let value = engine.value(on: day)
        let unit = self.unit.isEmpty ? "" : " \(self.unit)"
        switch kind {
        case .binary:
            if let week = engine.week(containing: day) {
                return String(localized: "\(week.done) of \(week.target) this week")
            }
            return rule(on: day).summary
        case .quantity:
            return "\(value.amountText) of \(target.amountText)\(unit)"
        case .timed:
            return "\(value.amountText) of \(target.amountText) min"
        case .limit:
            return "\(value.amountText) of ≤ \(target.amountText)\(unit)"
        }
    }
}
