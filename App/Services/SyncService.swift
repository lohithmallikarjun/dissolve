import Engine
import Foundation
import Observation
import SwiftData
import WidgetKit

/// What this device remembers between syncs (App Group `Sync/state.json`).
struct SyncState: Codable, Sendable {
    var versions: [RecordKey: RecordVersion] = [:]
    /// Byte offsets read so far, per file: `changes/<device>/<yyyy-MM>.jsonl` → offset.
    var cursors: [String: Int] = [:]
    var didInitialUpload = false
    var snapshotMonth: String?
    /// Photos whose files haven't arrived from iCloud yet.
    var pendingPhotos: Set<UUID> = []

    static var url: URL { Outbox.url.deletingLastPathComponent().appending(path: "state.json") }

    static func load() -> SyncState {
        guard let data = try? Data(contentsOf: url) else { return SyncState() }
        return (try? JSONDecoder.syncFields.decode(SyncState.self, from: data)) ?? SyncState()
    }

    func save() {
        if let data = try? JSONEncoder.syncFields.encode(self) {
            try? data.write(to: Self.url, options: .atomic)
        }
    }
}

/// Syncs through the chosen iCloud Drive folder. Each device appends only to its own
/// `changes/<deviceID>/<yyyy-MM>.jsonl`, reads everyone else's from a saved offset, and
/// merges per record (newest `updatedAt` wins, deletes are tombstones).
@MainActor @Observable
final class SyncService {
    private(set) var isSyncing = false
    private(set) var lastSyncedAt: Date?
    private(set) var lastError: String?
    private(set) var lastSummary = ""

    private let folderStore: SyncFolderStore
    private var pendingTask: Task<Void, Never>?

    init(folderStore: SyncFolderStore) {
        self.folderStore = folderStore
    }

    var isConfigured: Bool { folderStore.folderURL != nil }

    /// Debounced sync after local edits.
    func syncSoon(container: ModelContainer) {
        pendingTask?.cancel()
        pendingTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            await sync(container: container)
        }
    }

    func sync(container: ModelContainer) async {
        guard !isSyncing, let folder = folderStore.folderURL else { return }
        isSyncing = true
        defer { isSyncing = false }

        let device = DeviceIdentity.id
        let context = container.mainContext
        var state = SyncState.load()
        let month = AppSettings.today()

        // 1. Outgoing: queued local changes (plus everything, the first time).
        let outbox = Outbox.read()
        var outgoing = outbox.records
        if !state.didInitialUpload {
            outgoing = SyncExport.allRecords(in: context, device: device) + outgoing
        }
        let uploadPhotos = outgoing.filter { $0.entity == SyncEntity.photo && !$0.deleted }.map(\.id)
        let cursors = state.cursors

        do {
            let result = try await Task.detached {
                try FolderIO.withAccess(folder) {
                    try SyncIO.append(outgoing, folder: folder, device: device, month: month)
                    SyncIO.uploadPhotos(uploadPhotos, folder: folder)
                    return try SyncIO.readOthers(folder: folder, device: device, cursors: cursors)
                }
            }.value

            Outbox.remove(firstBytes: outbox.bytes)
            state.didInitialUpload = true
            _ = SyncMerger.merge(outgoing, into: &state.versions)

            // 2. Incoming.
            let winners = SyncMerger.merge(result.records, into: &state.versions)
            let photos = SyncApplier.apply(winners, in: context)
            if context.hasChanges { try context.save() }
            state.cursors = result.cursors
            state.pendingPhotos.formUnion(photos.filter { !ImageStore.hasFiles(id: $0) })

            // 3. Photo files that haven't arrived yet.
            let pending = state.pendingPhotos
            state.pendingPhotos = await Task.detached {
                (try? FolderIO.withAccess(folder) { SyncIO.downloadPhotos(pending, folder: folder) }) ?? pending
            }.value

            // 4. Monthly snapshot + compaction of this device's old logs.
            if state.snapshotMonth != month.monthKey {
                let all = SyncExport.allRecords(in: context, device: device)
                try await Task.detached {
                    try FolderIO.withAccess(folder) {
                        try SyncIO.writeSnapshot(all, folder: folder, device: device, keepingFrom: month)
                    }
                }.value
                state.snapshotMonth = month.monthKey
            }

            state.save()
            lastSyncedAt = .now
            lastError = nil
            lastSummary = String(localized: "Sent \(outgoing.count), received \(winners.count)")
            if !winners.isEmpty { WidgetCenter.shared.reloadAllTimelines() }
        } catch {
            lastError = error.localizedDescription
        }
    }
}

/// File work inside the sync folder. Synchronous; runs off the main actor.
enum SyncIO {
    struct ReadResult: Sendable {
        var records: [ChangeRecord]
        var cursors: [String: Int]
    }

    static func append(_ records: [ChangeRecord], folder: URL, device: String, month: LocalDate) throws {
        guard !records.isEmpty else { return }
        let path = SyncLayout.changeLogPath(deviceID: device, month: month)
        let url = folder.appending(path: path)
        try FolderIO.ensureDirectory(url.deletingLastPathComponent())
        let existing = (try? FolderIO.coordinatedRead(url)) ?? Data()
        try FolderIO.coordinatedWrite(existing + (try ChangeLog.lines(for: records)), to: url)
    }

    static func readOthers(folder: URL, device: String, cursors: [String: Int]) throws -> ReadResult {
        var result = ReadResult(records: [], cursors: cursors)
        let changes = folder.appending(path: SyncLayout.changesFolder)
        let devices = try FolderIO.listFiles(in: changes).map(\.url).filter { $0.lastPathComponent != device }
        for deviceFolder in devices {
            let other = deviceFolder.lastPathComponent
            let prefix = "\(SyncLayout.changesFolder)/\(other)/"
            // A device we've never heard from: start from its latest snapshot (older logs may be compacted away).
            if !cursors.keys.contains(where: { $0.hasPrefix(prefix) }) {
                let snapshot = folder.appending(path: "\(SyncLayout.snapshotsFolder)/\(other).jsonl")
                if let data = try? FolderIO.coordinatedRead(snapshot) {
                    result.records += ChangeLog.parse(data).records
                }
            }
            let files = try FolderIO.listFiles(in: deviceFolder)
                .filter { $0.url.pathExtension == "jsonl" }
                .sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
            for file in files {
                let key = prefix + file.url.lastPathComponent
                if file.needsDownload { continue }  // asked iCloud to fetch it; next sync reads it
                let data = try FolderIO.coordinatedRead(file.url)
                let offset = min(cursors[key] ?? 0, data.count)
                let parsed = ChangeLog.parse(data, from: offset)
                result.records += parsed.records
                result.cursors[key] = parsed.nextOffset
            }
        }
        return result
    }

    /// Photos are written once and never modified.
    static func uploadPhotos(_ ids: [UUID], folder: URL) {
        let photos = folder.appending(path: SyncLayout.photosFolder)
        try? FolderIO.ensureDirectory(photos)
        for id in ids {
            for (local, remotePath) in [(ImageStore.url(id: id), SyncLayout.photoPath(id: id)),
                                        (ImageStore.thumbURL(id: id), SyncLayout.thumbnailPath(id: id))] {
                let remote = folder.appending(path: remotePath)
                guard !FileManager.default.fileExists(atPath: remote.path(percentEncoded: false)),
                      let data = try? Data(contentsOf: local) else { continue }
                try? FolderIO.coordinatedWrite(data, to: remote)
            }
        }
    }

    /// Copies photo files from iCloud into the local store. Returns the ones still missing.
    static func downloadPhotos(_ ids: Set<UUID>, folder: URL) -> Set<UUID> {
        var missing: Set<UUID> = []
        for id in ids where !ImageStore.hasFiles(id: id) {
            var ok = true
            for (remotePath, local) in [(SyncLayout.photoPath(id: id), ImageStore.url(id: id)),
                                        (SyncLayout.thumbnailPath(id: id), ImageStore.thumbURL(id: id))] {
                let remote = folder.appending(path: remotePath)
                try? FileManager.default.startDownloadingUbiquitousItem(at: remote)
                if let data = try? FolderIO.coordinatedRead(remote) {
                    try? data.write(to: local, options: .atomic)
                } else {
                    ok = false
                }
            }
            if !ok { missing.insert(id) }
        }
        return missing
    }

    /// Writes `snapshots/<device>.jsonl` with the full current state, then deletes this
    /// device's logs older than last month (the snapshot covers them).
    static func writeSnapshot(_ records: [ChangeRecord], folder: URL, device: String, keepingFrom month: LocalDate) throws {
        let snapshots = folder.appending(path: SyncLayout.snapshotsFolder)
        try FolderIO.ensureDirectory(snapshots)
        try FolderIO.coordinatedWrite(try ChangeLog.lines(for: SyncMerger.compact(records)),
                                      to: snapshots.appending(path: "\(device).jsonl"))
        let lastMonth = LocalDate(year: month.year, month: month.month, day: 1)!.adding(days: -1).monthKey
        let mine = folder.appending(path: "\(SyncLayout.changesFolder)/\(device)")
        for file in (try? FolderIO.listFiles(in: mine)) ?? [] {
            let name = file.url.deletingPathExtension().lastPathComponent
            if name < lastMonth {
                var error: NSError?
                NSFileCoordinator().coordinate(writingItemAt: file.url, options: .forDeleting, error: &error) {
                    try? FileManager.default.removeItem(at: $0)
                }
            }
        }
    }
}
