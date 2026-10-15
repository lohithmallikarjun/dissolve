import Engine
import Foundation
import SwiftData

@Model
final class Habit {
    var id: UUID = UUID()
    var name: String = ""
    var symbol: String = "checkmark"
    var colorName: String = "green"
    var kindRaw: String = HabitKind.binary.rawValue
    /// Binary: 1. Quantity/limit: the amount. Timed: minutes.
    var target: Double = 1
    var unit: String = ""
    var sortOrder: Int = 0
    /// `yyyy-MM-dd`: the first day the habit counts.
    var startDate: String = ""
    var archivedAt: Date?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \HabitSchedule.habit)
    var schedules: [HabitSchedule] = []

    @Relationship(deleteRule: .cascade, inverse: \HabitLog.habit)
    var logs: [HabitLog] = []

    init(name: String, symbol: String, colorName: String, kind: HabitKind, target: Double,
         unit: String, sortOrder: Int, startDate: LocalDate) {
        self.name = name
        self.symbol = symbol
        self.colorName = colorName
        kindRaw = kind.rawValue
        self.target = target
        self.unit = unit
        self.sortOrder = sortOrder
        self.startDate = startDate.description
    }

    var kind: HabitKind {
        get { HabitKind(rawValue: kindRaw) ?? .binary }
        set { kindRaw = newValue.rawValue }
    }
}
