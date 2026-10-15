import Engine
import Foundation
import SwiftData

/// One record per habit per day, keyed by the local calendar date (not a timestamp).
@Model
final class HabitLog {
    /// `<habit id>|yyyy-MM-dd` — enforces one log per habit per day.
    @Attribute(.unique) var key: String = ""
    var id: UUID = UUID()
    /// `yyyy-MM-dd`
    var date: String = ""
    var value: Double = 0
    /// Planned rest: neutral for streaks.
    var isSkipped: Bool = false
    var note: String = ""
    var updatedAt: Date = Date.now
    var habit: Habit?

    /// Insert it, then set `habit` (see `HabitActions.log(for:on:in:)`).
    init(habit: Habit, date: LocalDate) {
        key = Self.key(habitID: habit.id, date: date)
        // Derived from habit + day, so two devices logging the same day edit the same record.
        id = DeterministicID.uuid(for: "habitLog|\(key)")
        self.date = date.description
    }

    static func key(habitID: UUID, date: LocalDate) -> String {
        "\(habitID.uuidString)|\(date.description)"
    }
}
