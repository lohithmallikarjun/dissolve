import Engine
import Foundation
import SwiftData

/// What the journal widgets show.
struct JournalSnapshot: Sendable {
    struct Memory: Sendable {
        let date: LocalDate
        let firstLine: String
        let photoID: UUID?
        let isOnThisDay: Bool
    }

    let today: LocalDate
    let writtenToday: Bool
    let prompt: String
    let streak: Int
    let memory: Memory?

    static let placeholder = JournalSnapshot(
        today: AppSettings.today(), writtenToday: false, prompt: String(localized: "What went well today?"),
        streak: 0, memory: nil)

    static func load(context: ModelContext, today: LocalDate = AppSettings.today()) -> JournalSnapshot {
        let entries = (try? context.fetch(FetchDescriptor<JournalEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        let dated = entries.compactMap { entry in entry.localDate.map { ($0, entry) } }
        let dates = Set(dated.map(\.0))
        let todays = dated.first { $0.0 == today }?.1
        let prompt = todays?.orderedBlocks.first { $0.kind == .prompt }?.promptText
            ?? defaultJournalPrompt
        let writtenToday = (todays?.wordCount ?? 0) > 0 || !(todays?.photoIDs.isEmpty ?? true)

        // "On this day" in an earlier year, else the latest older entry with a photo.
        var memory: Memory?
        let onThisDay = JournalStats.onThisDay(Array(dates), today: today)
        let pick = onThisDay.first.flatMap { d in dated.first { $0.0 == d } }
            ?? dated.first { $0.0 < today.adding(days: -6) && !$0.1.photoIDs.isEmpty }
        if case let (date, entry)? = pick {
            memory = Memory(date: date, firstLine: entry.firstLine,
                            photoID: entry.photoIDs.first.flatMap(UUID.init(uuidString:)),
                            isOnThisDay: !onThisDay.isEmpty)
        }
        return JournalSnapshot(today: today, writtenToday: writtenToday, prompt: prompt,
                               streak: JournalStats.streak(entryDates: dates, today: today), memory: memory)
    }

    static func load() -> JournalSnapshot {
        guard let container = try? SharedModelContainer.appGroup() else { return .placeholder }
        return load(context: ModelContext(container))
    }
}

private let defaultJournalPrompt = String(localized: "What went well today?")
