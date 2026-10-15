import AppIntents
import Engine
import Foundation
import SwiftData
import WidgetKit

/// A habit, as Shortcuts and widget configuration see it.
struct HabitEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Habit"
    static let defaultQuery = HabitEntityQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct HabitEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [HabitEntity] {
        try await HabitIntentStore.entities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [HabitEntity] {
        try await HabitIntentStore.entities()
    }
}

/// The widget check / +1 button: same as tapping the habit card.
struct LogHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Habit"
    static let description = IntentDescription("Checks off a habit, or adds one step to an amount, for today.")

    @Parameter(title: "Habit ID")
    var habitID: String

    init() {}

    init(habitID: UUID?) {
        self.habitID = habitID?.uuidString ?? ""
    }

    /// Raw IDs aren't useful in Shortcuts; "Log Habit" (with a habit picker) is the public one.
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        try await HabitIntentStore.primaryAction(habitID: habitID)
        return .result()
    }
}

/// Widget configuration: which habit to show.
struct SelectHabitIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Habit"
    static let description = IntentDescription("Shows one habit. Leave empty to show the next one to do.")

    @Parameter(title: "Habit")
    var habit: HabitEntity?
}

/// Widget configuration: one habit's year, or all habits.
struct YearGridIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Grid"
    static let description = IntentDescription("Leave empty for all habits.")

    @Parameter(title: "Habit")
    var habit: HabitEntity?
}

/// Store access for intents (they may run in the widget extension's process).
@MainActor
enum HabitIntentStore {
    static func entities() throws -> [HabitEntity] {
        let context = ModelContext(try SharedModelContainer.appGroup())
        let descriptor = FetchDescriptor<Habit>(
            predicate: #Predicate { $0.archivedAt == nil }, sortBy: [SortDescriptor(\.sortOrder)])
        return try context.fetch(descriptor).map { HabitEntity(id: $0.id, name: $0.name) }
    }

    static func primaryAction(habitID: String, on date: LocalDate? = nil) throws {
        guard let id = UUID(uuidString: habitID) else { return }
        let context = ModelContext(try SharedModelContainer.appGroup())
        guard let habit = habit(id, in: context) else { return }
        HabitActions.primaryAction(habit, on: date ?? AppSettings.today(), in: context)
        markExternalChange()
    }

    static func habit(_ id: UUID, in context: ModelContext) -> Habit? {
        var descriptor = FetchDescriptor<Habit>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Tells the app (if running) to reload: this change came from another context or process.
    static func markExternalChange() {
        AppGroup.defaults.set(Date.now.timeIntervalSince1970, forKey: SharedKeys.externalChangeAt)
    }
}

/// A countdown, for widget configuration.
struct CountdownEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Countdown"
    static let defaultQuery = CountdownEntityQuery()

    let id: UUID
    let title: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct CountdownEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [CountdownEntity] {
        try await CountdownIntentStore.entities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [CountdownEntity] {
        try await CountdownIntentStore.entities()
    }
}

struct SelectCountdownIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Countdown"
    static let description = IntentDescription("Leave empty to show the soonest one.")

    @Parameter(title: "Countdown")
    var countdown: CountdownEntity?
}

@MainActor
enum CountdownIntentStore {
    static func entities() throws -> [CountdownEntity] {
        let context = ModelContext(try SharedModelContainer.appGroup())
        let descriptor = FetchDescriptor<Countdown>(predicate: #Predicate { $0.archivedAt == nil },
                                                    sortBy: [SortDescriptor(\.sortOrder)])
        return try context.fetch(descriptor).map { CountdownEntity(id: $0.id, title: $0.title) }
    }
}
