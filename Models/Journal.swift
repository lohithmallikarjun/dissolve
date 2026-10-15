import Engine
import Foundation
import SwiftData

/// The kinds of blocks a template (and an entry) is made of.
enum BlockKind: String, CaseIterable, Codable, Sendable {
    case heading, prompt, text, checklist, image, mood, rating, habitSummary
}

/// An ordered list of blocks. Creating a day's entry copies them, so editing a template
/// never changes past entries.
@Model
final class JournalTemplate {
    var id: UUID = UUID()
    var name: String = ""
    var isDefault: Bool = false
    /// Weekdays (`1 = Sunday … 7 = Saturday`) this template is used for; empty = only as the default.
    var weekdays: [Int] = []
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \TemplateBlock.template)
    var blocks: [TemplateBlock] = []

    init(name: String, isDefault: Bool) {
        self.name = name
        self.isDefault = isDefault
    }

    var orderedBlocks: [TemplateBlock] { blocks.sorted { $0.order < $1.order } }
}

@Model
final class TemplateBlock {
    var id: UUID = UUID()
    var kindRaw: String = BlockKind.text.rawValue
    var order: Int = 0
    var promptText: String = ""
    var placeholder: String = ""
    var imageID: String?
    var required: Bool = false
    /// Checklist blocks: the items each new entry starts with.
    var checklistItems: [String] = []
    var template: JournalTemplate?

    init(kind: BlockKind, order: Int, promptText: String = "", placeholder: String = "") {
        kindRaw = kind.rawValue
        self.order = order
        self.promptText = promptText
        self.placeholder = placeholder
    }

    var kind: BlockKind { BlockKind(rawValue: kindRaw) ?? .text }
}

/// One entry per calendar day (`date` is unique, and the ID is derived from it so every
/// device agrees).
@Model
final class JournalEntry {
    var id: UUID = UUID()
    /// `yyyy-MM-dd`
    @Attribute(.unique) var date: String = ""
    /// 1…5, 0 = not set.
    var mood: Int = 0
    var wordCount: Int = 0
    var templateID: UUID?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \EntryBlock.entry)
    var blocks: [EntryBlock] = []

    init(date: LocalDate, templateID: UUID?) {
        id = Self.id(for: date)
        self.date = date.description
        self.templateID = templateID
    }

    static func id(for date: LocalDate) -> UUID { DeterministicID.uuid(for: "journalEntry|\(date)") }

    var localDate: LocalDate? { LocalDate(date) }
    var orderedBlocks: [EntryBlock] { blocks.sorted { $0.order < $1.order } }

    /// The first written line, for list cards and widgets.
    var firstLine: String {
        orderedBlocks.lazy.map(\.text)
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?
            .split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    }

    var photoIDs: [String] { orderedBlocks.flatMap(\.photoIDs) }

    func recountWords() {
        wordCount = blocks.reduce(0) { $0 + JournalStats.wordCount($1.text) }
    }
}

@Model
final class EntryBlock {
    var id: UUID = UUID()
    var kindRaw: String = BlockKind.text.rawValue
    var order: Int = 0
    /// Copied from the template when the entry was created.
    var promptText: String = ""
    var placeholder: String = ""
    var text: String = ""
    /// Checklist items as "[x] text" / "[ ] text".
    var checklist: [String] = []
    var rating: Int = 0
    var photoIDs: [String] = []
    var entry: JournalEntry?

    init(kind: BlockKind, order: Int, promptText: String = "", placeholder: String = "") {
        kindRaw = kind.rawValue
        self.order = order
        self.promptText = promptText
        self.placeholder = placeholder
    }

    var kind: BlockKind { BlockKind(rawValue: kindRaw) ?? .text }
}

/// A photo's metadata. The image itself lives on disk (`Photos/<id>.heic` + `<id>_thumb.heic`),
/// never in the database.
@Model
final class Photo {
    var id: UUID = UUID()
    var fileName: String = ""
    var thumbFileName: String = ""
    var width: Int = 0
    var height: Int = 0
    var caption: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(id: UUID, width: Int, height: Int) {
        self.id = id
        fileName = "\(id.uuidString).heic"
        thumbFileName = "\(id.uuidString)_thumb.heic"
        self.width = width
        self.height = height
    }
}

/// A checklist line stored as "[x] text" or "[ ] text".
struct ChecklistItem: Hashable {
    var text: String
    var isDone: Bool

    init(text: String, isDone: Bool) {
        self.text = text
        self.isDone = isDone
    }

    init(stored: String) {
        if stored.hasPrefix("[x] ") {
            self.init(text: String(stored.dropFirst(4)), isDone: true)
        } else if stored.hasPrefix("[ ] ") {
            self.init(text: String(stored.dropFirst(4)), isDone: false)
        } else {
            self.init(text: stored, isDone: false)
        }
    }

    var stored: String { (isDone ? "[x] " : "[ ] ") + text }
}
