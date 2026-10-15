import Engine
import Foundation
import SwiftData
import SwiftUI

/// Countdowns and life numbers for widgets.
struct CountdownSummary: Identifiable, Sendable {
    let id: UUID
    let title: String
    let symbol: String
    let colorName: String
    let occurrence: Date
    let isAllDay: Bool
    let countUp: Bool
    let days: Int
    let progress: Double
    let hasArrived: Bool

    var color: Color { HabitColor.named(colorName).color }
    /// Within a day of a timed countdown: show a live timer.
    var isFinalHours: Bool { !isAllDay && !countUp && !hasArrived && occurrence.timeIntervalSinceNow < 86_400 }

    /// "D-41", "D-Day", "+44"
    var shortLabel: String {
        if countUp { return "+\(days)" }
        return hasArrived || days == 0 ? "D-Day" : "D-\(days)"
    }
}

struct TimeSnapshot: Sendable {
    let countdowns: [CountdownSummary]
    let life: Life?

    struct Life: Sendable {
        let fractionRemaining: Double
        let weeksLived: Int
        let weeksRemaining: Int
        let age: Int
        let years: Int
    }

    func countdown(_ id: UUID?) -> CountdownSummary? {
        id.flatMap { id in countdowns.first { $0.id == id } } ?? countdowns.first
    }

    static let empty = TimeSnapshot(countdowns: [], life: nil)

    static func load(context: ModelContext, now: Date = .now) -> TimeSnapshot {
        let descriptor = FetchDescriptor<Countdown>(predicate: #Predicate { $0.archivedAt == nil },
                                                    sortBy: [SortDescriptor(\.sortOrder)])
        let countdowns = ((try? context.fetch(descriptor)) ?? []).map { c -> CountdownSummary in
            let s = c.state(now: now)
            return CountdownSummary(id: c.id, title: c.title, symbol: c.symbol, colorName: c.colorName,
                                    occurrence: s.occurrence, isAllDay: c.isAllDay, countUp: c.countUp,
                                    days: s.days, progress: s.progress, hasArrived: s.hasArrived)
        }
        // Soonest first; count-ups after.
        .sorted { ($0.countUp ? 1 : 0, $0.occurrence) < ($1.countUp ? 1 : 0, $1.occurrence) }

        let profile = try? context.fetch(FetchDescriptor<LifeProfile>()).first
        let life = profile?.grid().map {
            Life(fractionRemaining: $0.fractionRemaining, weeksLived: $0.weeksLived,
                 weeksRemaining: $0.weeksRemaining, age: $0.age, years: $0.years)
        }
        return TimeSnapshot(countdowns: countdowns, life: life)
    }

    static func load() -> TimeSnapshot {
        guard let container = try? SharedModelContainer.appGroup() else { return .empty }
        return load(context: ModelContext(container))
    }
}
