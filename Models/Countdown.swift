import Engine
import Foundation
import SwiftData

@Model
final class Countdown {
    var id: UUID = UUID()
    var title: String = ""
    var symbol: String = "calendar"
    var colorName: String = "orange"
    var targetDate: Date = Date.now
    var isAllDay: Bool = true
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    /// Birthdays, anniversaries.
    var repeatsYearly: Bool = false
    /// "Days since" instead of "days until".
    var countUp: Bool = false
    var photoID: String?
    var sortOrder: Int = 0
    var archivedAt: Date?

    init(title: String, symbol: String, colorName: String, targetDate: Date, isAllDay: Bool) {
        self.title = title
        self.symbol = symbol
        self.colorName = colorName
        self.targetDate = targetDate
        self.isAllDay = isAllDay
    }

    var spec: CountdownSpec {
        CountdownSpec(target: targetDate, isAllDay: isAllDay, createdAt: createdAt,
                      repeatsYearly: repeatsYearly, countUp: countUp)
    }

    func state(now: Date = .now) -> CountdownState { CountdownMath.state(spec, now: now) }
}

/// Birth date, lifespan and life eras. One per person (a fixed ID, so devices share it).
@Model
final class LifeProfile {
    static let sharedID = DeterministicID.uuid(for: "lifeProfile")

    var id: UUID = LifeProfile.sharedID
    /// `yyyy-MM-dd`
    var birthDate: String = ""
    var lifespanYears: Int = 80
    /// JSON-encoded `[LifeEra]`.
    var erasData: Data = Data()
    var updatedAt: Date = Date.now

    init(birthDate: LocalDate, lifespanYears: Int) {
        self.birthDate = birthDate.description
        self.lifespanYears = lifespanYears
    }

    var birth: LocalDate? { LocalDate(birthDate) }

    var eras: [LifeEra] {
        get { (try? JSONDecoder().decode([LifeEra].self, from: erasData)) ?? [] }
        set { erasData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    func grid(today: LocalDate = AppSettings.today()) -> LifeGrid? {
        birth.map { LifeGrid(birth: $0, years: lifespanYears, today: today) }
    }
}
