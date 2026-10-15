import Engine
import Foundation
import SwiftData

/// Applies merged remote changes to the local store, without re-recording them.
enum SyncApplier {
    /// Returns photo IDs whose image files need fetching.
    @discardableResult
    static func apply(_ records: [ChangeRecord], in context: ModelContext) -> [UUID] {
        var photosToFetch: [UUID] = []
        let ordered = records.sorted {
            (SyncEntity.priority($0.entity), $0.updatedAt) < (SyncEntity.priority($1.entity), $1.updatedAt)
        }
        for record in ordered {
            do {
                switch record.entity {
                case SyncEntity.habit: try applyHabit(record, context)
                case SyncEntity.habitSchedule: try applySchedule(record, context)
                case SyncEntity.habitLog: try applyLog(record, context)
                case SyncEntity.journalTemplate: try applyTemplate(record, context)
                case SyncEntity.journalEntry: try applyEntry(record, context)
                case SyncEntity.photo:
                    try applyPhoto(record, context)
                    if !record.deleted { photosToFetch.append(record.id) }
                case SyncEntity.countdown: try applyCountdown(record, context)
                case SyncEntity.lifeProfile: try applyLifeProfile(record, context)
                default: continue  // a newer app version's entity; ignore
                }
            } catch {
                print("Dissolve: couldn't apply \(record.entity) \(record.id): \(error)")
            }
        }
        return photosToFetch
    }

    // MARK: Lookups

    static func habit(_ id: UUID?, _ context: ModelContext) -> Habit? {
        guard let id else { return nil }
        var d = FetchDescriptor<Habit>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    private static func schedule(_ id: UUID, _ context: ModelContext) -> HabitSchedule? {
        var d = FetchDescriptor<HabitSchedule>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    private static func log(_ id: UUID, _ context: ModelContext) -> HabitLog? {
        var d = FetchDescriptor<HabitLog>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    private static func template(_ id: UUID, _ context: ModelContext) -> JournalTemplate? {
        var d = FetchDescriptor<JournalTemplate>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    private static func entry(_ id: UUID, date: String?, _ context: ModelContext) -> JournalEntry? {
        var d = FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        if let found = try? context.fetch(d).first { return found }
        guard let date else { return nil }
        var byDate = FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.date == date })
        byDate.fetchLimit = 1
        return try? context.fetch(byDate).first
    }

    private static func photo(_ id: UUID, _ context: ModelContext) -> Photo? {
        var d = FetchDescriptor<Photo>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    // MARK: Entities

    private static func applyHabit(_ r: ChangeRecord, _ context: ModelContext) throws {
        let existing = habit(r.id, context)
        if r.deleted {
            if let existing { context.delete(existing) }
            return
        }
        guard let f = try r.fields?.decode(HabitFields.self) else { return }
        let h = existing ?? {
            let new = Habit(name: f.name, symbol: f.symbol, colorName: f.colorName, kind: .binary, target: f.target,
                            unit: f.unit, sortOrder: f.sortOrder, startDate: LocalDate(f.startDate) ?? AppSettings.today())
            new.id = r.id
            context.insert(new)
            return new
        }()
        h.name = f.name
        h.symbol = f.symbol
        h.colorName = f.colorName
        h.kindRaw = f.kind
        h.target = f.target
        h.unit = f.unit
        h.sortOrder = f.sortOrder
        h.startDate = f.startDate
        h.archivedAt = f.archivedAt
        h.createdAt = f.createdAt
        h.updatedAt = r.updatedAt
    }

    private static func applySchedule(_ r: ChangeRecord, _ context: ModelContext) throws {
        let existing = schedule(r.id, context)
        if r.deleted {
            if let existing { context.delete(existing) }
            return
        }
        guard let f = try r.fields?.decode(HabitScheduleFields.self) else { return }
        let s = existing ?? {
            let new = HabitSchedule(rule: .daily, effectiveFrom: LocalDate(f.effectiveFrom) ?? AppSettings.today())
            new.id = r.id
            context.insert(new)
            return new
        }()
        s.kindRaw = f.kind
        s.weekdays = f.weekdays
        s.timesPerWeek = f.timesPerWeek
        s.everyNDays = f.everyNDays
        s.effectiveFrom = f.effectiveFrom
        s.updatedAt = r.updatedAt
        if let owner = habit(f.habitID, context), s.habit !== owner { s.habit = owner }
    }

    private static func applyLog(_ r: ChangeRecord, _ context: ModelContext) throws {
        let existing = log(r.id, context)
        if r.deleted {
            if let existing { context.delete(existing) }
            return
        }
        guard let f = try r.fields?.decode(HabitLogFields.self),
              let owner = habit(f.habitID, context), let date = LocalDate(f.date) else { return }
        let l = existing ?? {
            let new = HabitLog(habit: owner, date: date)
            new.id = r.id
            context.insert(new)
            new.habit = owner
            return new
        }()
        l.value = f.value
        l.isSkipped = f.isSkipped
        l.note = f.note
        l.updatedAt = r.updatedAt
    }

    private static func applyTemplate(_ r: ChangeRecord, _ context: ModelContext) throws {
        let existing = template(r.id, context)
        if r.deleted {
            if let existing { context.delete(existing) }
            return
        }
        guard let f = try r.fields?.decode(JournalTemplateFields.self) else { return }
        let t = existing ?? {
            let new = JournalTemplate(name: f.name, isDefault: f.isDefault)
            new.id = r.id
            context.insert(new)
            return new
        }()
        t.name = f.name
        t.isDefault = f.isDefault
        t.createdAt = f.createdAt
        for block in t.blocks { context.delete(block) }
        for b in f.blocks {
            let block = TemplateBlock(kind: BlockKind(rawValue: b.kind) ?? .text, order: b.order,
                                      promptText: b.promptText, placeholder: b.placeholder)
            block.id = b.id
            block.imageID = b.imageID
            block.required = b.required
            context.insert(block)
            block.template = t
        }
        t.updatedAt = r.updatedAt
    }

    private static func applyEntry(_ r: ChangeRecord, _ context: ModelContext) throws {
        let f = try r.fields?.decode(JournalEntryFields.self)
        let existing = entry(r.id, date: f?.date, context)
        if r.deleted {
            if let existing { context.delete(existing) }
            return
        }
        guard let f, let date = LocalDate(f.date) else { return }
        let e = existing ?? {
            let new = JournalEntry(date: date, templateID: f.templateID)
            new.id = r.id
            context.insert(new)
            return new
        }()
        e.mood = f.mood
        e.wordCount = f.wordCount
        e.templateID = f.templateID
        e.createdAt = f.createdAt
        for block in e.blocks { context.delete(block) }
        for b in f.blocks {
            let block = EntryBlock(kind: BlockKind(rawValue: b.kind) ?? .text, order: b.order,
                                   promptText: b.promptText, placeholder: b.placeholder)
            block.id = b.id
            block.text = b.text
            block.checklist = b.checklist
            block.rating = b.rating
            block.photoIDs = b.photoIDs
            context.insert(block)
            block.entry = e
        }
        e.updatedAt = r.updatedAt
    }

    private static func applyPhoto(_ r: ChangeRecord, _ context: ModelContext) throws {
        let existing = photo(r.id, context)
        if r.deleted {
            if let existing { context.delete(existing) }
            ImageStore.deleteFiles(id: r.id)
            return
        }
        guard let f = try r.fields?.decode(PhotoFields.self) else { return }
        let p = existing ?? {
            let new = Photo(id: r.id, width: f.width, height: f.height)
            context.insert(new)
            return new
        }()
        p.fileName = f.fileName
        p.thumbFileName = f.thumbFileName
        p.width = f.width
        p.height = f.height
        p.caption = f.caption
        p.createdAt = f.createdAt
        p.updatedAt = r.updatedAt
    }
}

extension SyncApplier {
    fileprivate static func applyCountdown(_ r: ChangeRecord, _ context: ModelContext) throws {
        let id = r.id
        var d = FetchDescriptor<Countdown>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        let existing = try? context.fetch(d).first
        if r.deleted {
            if let existing { context.delete(existing) }
            return
        }
        guard let f = try r.fields?.decode(CountdownFields.self) else { return }
        let c = existing ?? {
            let new = Countdown(title: f.title, symbol: f.symbol, colorName: f.colorName,
                                targetDate: f.targetDate, isAllDay: f.isAllDay)
            new.id = r.id
            context.insert(new)
            return new
        }()
        c.title = f.title
        c.symbol = f.symbol
        c.colorName = f.colorName
        c.targetDate = f.targetDate
        c.isAllDay = f.isAllDay
        c.createdAt = f.createdAt
        c.repeatsYearly = f.repeatsYearly
        c.countUp = f.countUp
        c.photoID = f.photoID
        c.sortOrder = f.sortOrder
        c.archivedAt = f.archivedAt
        c.updatedAt = r.updatedAt
    }

    fileprivate static func applyLifeProfile(_ r: ChangeRecord, _ context: ModelContext) throws {
        let id = r.id
        var d = FetchDescriptor<LifeProfile>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        let existing = try? context.fetch(d).first
        if r.deleted {
            if let existing { context.delete(existing) }
            return
        }
        guard let f = try r.fields?.decode(LifeProfileFields.self), let birth = LocalDate(f.birthDate) else { return }
        let p = existing ?? {
            let new = LifeProfile(birthDate: birth, lifespanYears: f.lifespanYears)
            new.id = r.id
            context.insert(new)
            return new
        }()
        p.birthDate = f.birthDate
        p.lifespanYears = f.lifespanYears
        p.eras = f.eras
        p.updatedAt = r.updatedAt
    }
}

/// Every record in the local store, for the first upload and the monthly snapshot.
enum SyncExport {
    static func allRecords(in context: ModelContext, device: String) -> [ChangeRecord] {
        func records<T: PersistentModel & Syncable>(_ type: T.Type) -> [ChangeRecord] {
            ((try? context.fetch(FetchDescriptor<T>())) ?? []).compactMap { try? $0.changeRecord(device: device) }
        }
        return records(Habit.self) + records(HabitSchedule.self) + records(HabitLog.self)
            + records(JournalTemplate.self) + records(Photo.self) + records(JournalEntry.self)
            + records(Countdown.self) + records(LifeProfile.self)
    }
}
