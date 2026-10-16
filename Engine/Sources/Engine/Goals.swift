import Foundation

/// What a goal's progress is made of. Each source reports 0…1; the goal is their weighted mean,
/// and a parent goal is the mean of its children plus its own sources.
public enum GoalSource: Hashable, Sendable {
    /// A linked habit's strength score.
    case habitStrength(Double)
    /// Linked tasks: completed of total.
    case tasks(done: Int, total: Int)
    /// A numeric key result, e.g. 42 of 100 km. `start` handles "down" goals like weight.
    case keyResult(start: Double, current: Double, target: Double)
    /// Progress set by hand.
    case manual(Double)

    public var progress: Double? {
        switch self {
        case .habitStrength(let s): return clamp(s)
        case .tasks(let done, let total): return total > 0 ? clamp(Double(done) / Double(total)) : nil
        case .keyResult(let start, let current, let target):
            guard target != start else { return current == target ? 1 : 0 }
            return clamp((current - start) / (target - start))
        case .manual(let p): return clamp(p)
        }
    }

    private func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
}

public struct GoalNode: Sendable {
    public var sources: [GoalSource]
    public var children: [GoalNode]
    public var weight: Double

    public init(sources: [GoalSource] = [], children: [GoalNode] = [], weight: Double = 1) {
        self.sources = sources
        self.children = children
        self.weight = weight
    }

    /// Nil when nothing measurable is linked yet.
    public var progress: Double? {
        var parts: [(Double, Double)] = sources.compactMap { $0.progress.map { ($0, 1) } }
        parts += children.compactMap { child in child.progress.map { ($0, child.weight) } }
        let total = parts.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return nil }
        return parts.reduce(0) { $0 + $1.0 * $1.1 } / total
    }

    /// "On track" compares progress with the share of the goal's period that has passed.
    public func isOnTrack(periodStart: LocalDate, periodEnd: LocalDate, today: LocalDate, slack: Double = 0.1) -> Bool? {
        guard let progress, periodStart < periodEnd else { return nil }
        let elapsed = min(max(Double(periodStart.days(to: today)) / Double(periodStart.days(to: periodEnd)), 0), 1)
        return progress + slack >= elapsed
    }
}
