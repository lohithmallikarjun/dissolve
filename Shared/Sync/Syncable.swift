import Engine
import Foundation
import SwiftData

/// A model that travels through the sync change logs.
protocol Syncable: AnyObject {
    static var syncEntity: String { get }
    var id: UUID { get }
    var updatedAt: Date { get set }
    func syncFields() throws -> JSONValue
}

extension Syncable {
    func changeRecord(device: String) throws -> ChangeRecord {
        ChangeRecord(entity: Self.syncEntity, id: id, updatedAt: updatedAt, device: device, fields: try syncFields())
    }

    func tombstone(device: String) -> ChangeRecord {
        ChangeRecord(entity: Self.syncEntity, id: id, updatedAt: SyncClock.stamp(previous: updatedAt),
                     deleted: true, device: device, fields: nil)
    }
}

enum SyncEntity {
    static let habit = "habit"
    static let habitSchedule = "habitSchedule"
    static let habitLog = "habitLog"
    static let journalTemplate = "journalTemplate"
    static let journalEntry = "journalEntry"
    static let photo = "photo"
    static let countdown = "countdown"
    static let lifeProfile = "lifeProfile"

    /// Parents before children, so a log never arrives before its habit.
    static func priority(_ entity: String) -> Int {
        switch entity {
        case habit, journalTemplate, photo, countdown, lifeProfile: 0
        default: 1
        }
    }
}

// MARK: Field DTOs (what goes in `fields`)

struct HabitFields: Codable {
    var name: String
    var symbol: String
    var colorName: String
    var kind: String
    var target: Double
    var unit: String
    var sortOrder: Int
    var startDate: String
    var archivedAt: Date?
    var createdAt: Date
}

struct HabitScheduleFields: Codable {
    var habitID: UUID?
    var kind: String
    var weekdays: [Int]
    var timesPerWeek: Int
    var everyNDays: Int
    var effectiveFrom: String
}

struct HabitLogFields: Codable {
    var habitID: UUID?
    var date: String
    var value: Double
    var isSkipped: Bool
    var note: String
}

struct BlockFields: Codable {
    var id: UUID
    var kind: String
    var order: Int
    var promptText: String
    var placeholder: String
    var text: String
    var checklist: [String]
    var rating: Int
    var photoIDs: [String]
    var imageID: String?
    var required: Bool
}

struct JournalEntryFields: Codable {
    var date: String
    var mood: Int
    var wordCount: Int
    var templateID: UUID?
    var createdAt: Date
    var blocks: [BlockFields]
}

struct JournalTemplateFields: Codable {
    var name: String
    var isDefault: Bool
    var createdAt: Date
    var blocks: [BlockFields]
}

struct PhotoFields: Codable {
    var fileName: String
    var thumbFileName: String
    var width: Int
    var height: Int
    var caption: String
    var createdAt: Date
}

// MARK: Conformances

extension Habit: Syncable {
    static var syncEntity: String { SyncEntity.habit }
    func syncFields() throws -> JSONValue {
        try JSONValue(encoding: HabitFields(
            name: name, symbol: symbol, colorName: colorName, kind: kindRaw, target: target, unit: unit,
            sortOrder: sortOrder, startDate: startDate, archivedAt: archivedAt, createdAt: createdAt))
    }
}

extension HabitSchedule: Syncable {
    static var syncEntity: String { SyncEntity.habitSchedule }
    func syncFields() throws -> JSONValue {
        try JSONValue(encoding: HabitScheduleFields(
            habitID: habit?.id, kind: kindRaw, weekdays: weekdays, timesPerWeek: timesPerWeek,
            everyNDays: everyNDays, effectiveFrom: effectiveFrom))
    }
}

extension HabitLog: Syncable {
    static var syncEntity: String { SyncEntity.habitLog }
    func syncFields() throws -> JSONValue {
        try JSONValue(encoding: HabitLogFields(
            habitID: habit?.id, date: date, value: value, isSkipped: isSkipped, note: note))
    }
}

extension EntryBlock {
    var fields: BlockFields {
        BlockFields(id: id, kind: kindRaw, order: order, promptText: promptText, placeholder: placeholder,
                    text: text, checklist: checklist, rating: rating, photoIDs: photoIDs, imageID: nil, required: false)
    }
}

extension TemplateBlock {
    var fields: BlockFields {
        BlockFields(id: id, kind: kindRaw, order: order, promptText: promptText, placeholder: placeholder,
                    text: "", checklist: [], rating: 0, photoIDs: [], imageID: imageID, required: required)
    }
}

extension JournalEntry: Syncable {
    static var syncEntity: String { SyncEntity.journalEntry }
    func syncFields() throws -> JSONValue {
        try JSONValue(encoding: JournalEntryFields(
            date: date, mood: mood, wordCount: wordCount, templateID: templateID, createdAt: createdAt,
            blocks: orderedBlocks.map(\.fields)))
    }
}

extension JournalTemplate: Syncable {
    static var syncEntity: String { SyncEntity.journalTemplate }
    func syncFields() throws -> JSONValue {
        try JSONValue(encoding: JournalTemplateFields(
            name: name, isDefault: isDefault, createdAt: createdAt, blocks: orderedBlocks.map(\.fields)))
    }
}

extension Photo: Syncable {
    static var syncEntity: String { SyncEntity.photo }
    func syncFields() throws -> JSONValue {
        try JSONValue(encoding: PhotoFields(
            fileName: fileName, thumbFileName: thumbFileName, width: width, height: height,
            caption: caption, createdAt: createdAt))
    }
}

struct CountdownFields: Codable {
    var title: String
    var symbol: String
    var colorName: String
    var targetDate: Date
    var isAllDay: Bool
    var createdAt: Date
    var repeatsYearly: Bool
    var countUp: Bool
    var photoID: String?
    var sortOrder: Int
    var archivedAt: Date?
}

struct LifeProfileFields: Codable {
    var birthDate: String
    var lifespanYears: Int
    var eras: [LifeEra]
}

extension Countdown: Syncable {
    static var syncEntity: String { SyncEntity.countdown }
    func syncFields() throws -> JSONValue {
        try JSONValue(encoding: CountdownFields(
            title: title, symbol: symbol, colorName: colorName, targetDate: targetDate, isAllDay: isAllDay,
            createdAt: createdAt, repeatsYearly: repeatsYearly, countUp: countUp, photoID: photoID,
            sortOrder: sortOrder, archivedAt: archivedAt))
    }
}

extension LifeProfile: Syncable {
    static var syncEntity: String { SyncEntity.lifeProfile }
    func syncFields() throws -> JSONValue {
        try JSONValue(encoding: LifeProfileFields(birthDate: birthDate, lifespanYears: lifespanYears, eras: eras))
    }
}
