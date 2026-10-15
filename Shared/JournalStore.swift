import Engine
import Foundation
import SwiftData

/// Creating entries from the template, and the default template itself.
@MainActor
enum JournalStore {
    /// The MVP template: a prompt, free text, photos and mood.
    static func defaultTemplate(in context: ModelContext) -> JournalTemplate {
        var descriptor = FetchDescriptor<JournalTemplate>(predicate: #Predicate { $0.isDefault })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first { return existing }
        let template = JournalTemplate(name: String(localized: "Daily Journal"), isDefault: true)
        context.insert(template)
        let blocks: [(BlockKind, String, String)] = [
            (.prompt, String(localized: "What went well today?"), String(localized: "One good thing…")),
            (.text, "", String(localized: "Anything else on your mind…")),
            (.image, String(localized: "Photos"), ""),
            (.mood, String(localized: "How was today?"), ""),
        ]
        for (index, (kind, prompt, placeholder)) in blocks.enumerated() {
            let block = TemplateBlock(kind: kind, order: index, promptText: prompt, placeholder: placeholder)
            context.insert(block)
            block.template = template
        }
        return template
    }

    static func entry(on date: LocalDate, in context: ModelContext) -> JournalEntry? {
        let key = date.description
        var descriptor = FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.date == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// The day's entry, created from the template if there isn't one (one entry per day).
    /// The template's blocks are copied, so later template edits never change this entry.
    static func entryCreatingIfNeeded(on date: LocalDate, in context: ModelContext) -> JournalEntry {
        if let existing = entry(on: date, in: context) { return existing }
        let template = defaultTemplate(in: context)
        let entry = JournalEntry(date: date, templateID: template.id)
        context.insert(entry)
        for t in template.orderedBlocks {
            let block = EntryBlock(kind: t.kind, order: t.order, promptText: t.promptText, placeholder: t.placeholder)
            context.insert(block)
            block.entry = entry
        }
        Persistence.save(context)
        return entry
    }

    /// Adds a resized photo to an image block.
    static func addPhoto(_ saved: ImageStore.Saved, to block: EntryBlock, in context: ModelContext) {
        let photo = Photo(id: saved.id, width: saved.width, height: saved.height)
        context.insert(photo)
        block.photoIDs.append(saved.id.uuidString)
        Persistence.save(context)
    }

    static func removePhoto(_ id: String, from block: EntryBlock, in context: ModelContext) {
        block.photoIDs.removeAll { $0 == id }
        if let uuid = UUID(uuidString: id) {
            var descriptor = FetchDescriptor<Photo>(predicate: #Predicate { $0.id == uuid })
            descriptor.fetchLimit = 1
            if let photo = try? context.fetch(descriptor).first { context.delete(photo) }
            ImageStore.deleteFiles(id: uuid)
        }
        Persistence.save(context)
    }
}

/// The five moods.
enum Mood: Int, CaseIterable, Identifiable {
    case awful = 1, bad, okay, good, great
    var id: Int { rawValue }

    var symbol: String {
        switch self {
        case .awful: "cloud.heavyrain.fill"
        case .bad: "cloud.drizzle.fill"
        case .okay: "cloud.sun.fill"
        case .good: "sun.max.fill"
        case .great: "sparkles"
        }
    }

    var name: LocalizedStringResource {
        switch self {
        case .awful: "Awful"
        case .bad: "Bad"
        case .okay: "Okay"
        case .good: "Good"
        case .great: "Great"
        }
    }
}
