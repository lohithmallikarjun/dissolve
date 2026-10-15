import Foundation

/// Patterns across habits and mood, after enough data. These are correlations, not causes.
public enum Patterns {
    public struct MoodSplit: Equatable, Sendable {
        /// Average mood (1–5) on days the habit was done.
        public let withHabit: Double
        /// Average mood on days it was due but not done.
        public let withoutHabit: Double
        public let daysWith: Int
        public let daysWithout: Int
        public var difference: Double { withHabit - withoutHabit }
    }

    /// Mood on days a habit was done vs days it was due and missed. nil without at least
    /// `minDays` journaled days on each side.
    public static func moodSplit(_ engine: HabitEngine, moods: [LocalDate: Int], from: LocalDate, to: LocalDate,
                                 minDays: Int = 5) -> MoodSplit? {
        var with: [Int] = [], without: [Int] = []
        var day = max(from, engine.habit.startDate)
        let last = min(to, engine.lastDay)
        while day <= last {
            if let mood = moods[day], mood > 0 {
                switch engine.status(on: day) {
                case .completed: with.append(mood)
                case .missed, .partial: without.append(mood)
                default: break
                }
            }
            day = day.adding(days: 1)
        }
        guard with.count >= minDays, without.count >= minDays else { return nil }
        func mean(_ a: [Int]) -> Double { Double(a.reduce(0, +)) / Double(a.count) }
        return MoodSplit(withHabit: mean(with), withoutHabit: mean(without), daysWith: with.count, daysWithout: without.count)
    }

    public struct Pair: Equatable, Sendable {
        public let first: Int
        public let second: Int
        /// Days both were done.
        public let together: Int
        /// Days both were due.
        public let sharedDays: Int
        /// P(both) ÷ (P(first) × P(second)); above 1 means they tend to happen together.
        public let lift: Double
    }

    /// Habit pairs that tend to be done on the same days (indices into `engines`), strongest first.
    public static func coOccurrence(_ engines: [HabitEngine], from: LocalDate, to: LocalDate,
                                    minSharedDays: Int = 14, minTogether: Int = 5, minLift: Double = 1.15) -> [Pair] {
        guard engines.count >= 2 else { return [] }
        // For each habit: which of the range's days it was due, and which it was done.
        let length = from.days(to: to) + 1
        guard length > 0 else { return [] }
        let table: [(due: [Bool], done: [Bool])] = engines.map { engine in
            var due = [Bool](repeating: false, count: length), done = [Bool](repeating: false, count: length)
            for i in 0..<length {
                let day = from.adding(days: i)
                switch engine.status(on: day) {
                case .completed: due[i] = true; done[i] = true
                case .missed, .partial: due[i] = true
                default: break
                }
            }
            return (due, done)
        }
        var pairs: [Pair] = []
        for a in 0..<engines.count {
            for b in (a + 1)..<engines.count {
                var shared = 0, doneA = 0, doneB = 0, both = 0
                for i in 0..<length where table[a].due[i] && table[b].due[i] {
                    shared += 1
                    if table[a].done[i] { doneA += 1 }
                    if table[b].done[i] { doneB += 1 }
                    if table[a].done[i] && table[b].done[i] { both += 1 }
                }
                guard shared >= minSharedDays, both >= minTogether, doneA > 0, doneB > 0 else { continue }
                let n = Double(shared)
                let lift = (Double(both) / n) / ((Double(doneA) / n) * (Double(doneB) / n))
                if lift >= minLift {
                    pairs.append(Pair(first: a, second: b, together: both, sharedDays: shared, lift: lift))
                }
            }
        }
        return pairs.sorted { $0.lift > $1.lift }
    }

    /// Days with any data: insights wait for ~30.
    public static func daysOfData(_ engines: [HabitEngine]) -> Int {
        guard let start = engines.map(\.habit.startDate).min(), let today = engines.first?.today else { return 0 }
        return max(0, start.days(to: today) + 1)
    }
}
