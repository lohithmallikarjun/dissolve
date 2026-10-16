import Foundation

/// SM-2 spaced repetition (the SuperMemo 2 algorithm Anki started from).
/// Pure and deterministic: the app stores `CardSchedule` and replays nothing.
public struct CardSchedule: Hashable, Sendable, Codable {
    /// Successful reviews in a row.
    public var repetitions: Int
    /// Days until the next review.
    public var intervalDays: Int
    /// Ease factor, never below 1.3.
    public var ease: Double
    public var due: LocalDate
    /// Times the card was forgotten after being learned.
    public var lapses: Int

    public init(repetitions: Int = 0, intervalDays: Int = 0, ease: Double = 2.5, due: LocalDate, lapses: Int = 0) {
        self.repetitions = repetitions
        self.intervalDays = intervalDays
        self.ease = ease
        self.due = due
        self.lapses = lapses
    }

    public static func new(on date: LocalDate) -> CardSchedule { CardSchedule(due: date) }

    public func isDue(on date: LocalDate) -> Bool { due <= date }
}

/// The four review buttons.
public enum ReviewGrade: Int, Sendable, CaseIterable, Codable {
    case again = 1, hard = 3, good = 4, easy = 5

    /// SM-2 quality, 0…5.
    var quality: Int { rawValue }
}

public enum SM2 {
    public static let minimumEase = 1.3

    public static func review(_ card: CardSchedule, grade: ReviewGrade, on date: LocalDate) -> CardSchedule {
        var next = card
        let q = Double(grade.quality)
        if grade == .again {
            if card.repetitions > 0 { next.lapses += 1 }
            next.repetitions = 0
            next.intervalDays = 1
        } else {
            next.repetitions += 1
            switch next.repetitions {
            case 1: next.intervalDays = grade == .easy ? 4 : 1
            case 2: next.intervalDays = grade == .easy ? 8 : 6
            default:
                var interval = Double(card.intervalDays) * card.ease
                if grade == .hard { interval = Double(card.intervalDays) * 1.2 }
                if grade == .easy { interval *= 1.3 }
                next.intervalDays = max(card.intervalDays + 1, Int(interval.rounded()))
            }
        }
        next.ease = max(minimumEase, card.ease + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02)))
        next.due = date.adding(days: next.intervalDays)
        return next
    }

    /// Cards due on `date`, oldest due first, capped at `limit` (new cards included).
    public static func dueQueue<ID: Hashable>(_ cards: [(id: ID, schedule: CardSchedule)], on date: LocalDate,
                                              limit: Int = .max) -> [ID] {
        cards.filter { $0.schedule.isDue(on: date) }
            .sorted { $0.schedule.due < $1.schedule.due }
            .prefix(limit)
            .map(\.id)
    }

    /// How many cards come due on each of the next `days` days (for a forecast chart).
    public static func forecast(_ schedules: [CardSchedule], from date: LocalDate, days: Int) -> [Int] {
        var counts = Array(repeating: 0, count: max(days, 0))
        for s in schedules {
            let offset = max(date.days(to: s.due), 0)
            if offset < counts.count { counts[offset] += 1 }
        }
        return counts
    }
}
