import Engine
import Foundation
import SwiftData
import WidgetKit

extension Notification.Name {
    /// Posted after local edits are saved (the app syncs soon after).
    static let dissolveLocalChange = Notification.Name("dissolveLocalChange")
}

/// Every local save goes through here: it stamps and records the changes for sync,
/// saves, queues them in the outbox, and refreshes widgets.
enum Persistence {
    static func save(_ context: ModelContext) {
        let records = pendingRecords(in: context, device: DeviceIdentity.id)
        do {
            try context.save()
        } catch {
            print("Dissolve: save failed: \(error)")
            return
        }
        Outbox.append(records)
        WidgetCenter.shared.reloadAllTimelines()
        #if os(iOS)
        ControlCenter.shared.reloadAllControls()
        #endif
        NotificationCenter.default.post(name: .dissolveLocalChange, object: nil)
    }

    /// Change records for everything inserted, changed or deleted in `context` since the last save.
    /// Blocks are recorded as part of their entry or template.
    static func pendingRecords(in context: ModelContext, device: String) -> [ChangeRecord] {
        var touched: [ObjectIdentifier: any Syncable] = [:]
        var deleted: [ObjectIdentifier: any Syncable] = [:]

        func owner(of model: any PersistentModel) -> (any Syncable)? {
            if let block = model as? EntryBlock { return block.entry }
            if let block = model as? TemplateBlock { return block.template }
            return model as? any Syncable
        }

        for model in context.insertedModelsArray + context.changedModelsArray {
            if let s = owner(of: model) { touched[ObjectIdentifier(s)] = s }
        }
        for model in context.deletedModelsArray {
            if model is EntryBlock || model is TemplateBlock {
                if let s = owner(of: model) { touched[ObjectIdentifier(s)] = s }
            } else if let s = model as? any Syncable {
                deleted[ObjectIdentifier(s)] = s
            }
        }

        var records: [ChangeRecord] = []
        for (key, model) in touched where deleted[key] == nil {
            model.updatedAt = SyncClock.stamp(previous: model.updatedAt)
            if let record = try? model.changeRecord(device: device) { records.append(record) }
        }
        for model in deleted.values {
            records.append(model.tombstone(device: device))
        }
        return records
    }
}

/// Local changes waiting to be written to this device's change log in iCloud Drive.
/// Lives in the App Group, so widget buttons (another process) queue their changes too.
enum Outbox {
    static var url: URL {
        let folder = (AppGroup.containerURL ?? URL.applicationSupportDirectory).appending(path: "Sync")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "outbox.jsonl")
    }

    static func append(_ records: [ChangeRecord]) {
        guard !records.isEmpty, let data = try? ChangeLog.lines(for: records) else { return }
        let url = url
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { target in
            if let handle = try? FileHandle(forWritingTo: target) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: target, options: .atomic)
            }
        }
    }

    /// Everything queued, and how many bytes that was (to remove after a successful push).
    static func read() -> (records: [ChangeRecord], bytes: Int) {
        guard let data = try? Data(contentsOf: url) else { return ([], 0) }
        let parsed = ChangeLog.parse(data)
        return (parsed.records, parsed.nextOffset)
    }

    /// Removes the first `bytes` (already pushed), keeping anything appended since.
    static func remove(firstBytes bytes: Int) {
        guard bytes > 0 else { return }
        let url = url
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
            guard let data = try? Data(contentsOf: target) else { return }
            try? data.dropFirst(min(bytes, data.count)).write(to: target, options: .atomic)
        }
    }
}
