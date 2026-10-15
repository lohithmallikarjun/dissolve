import Engine
import Foundation

/// Coordinated file access inside the user-chosen iCloud Drive folder.
/// Everything here is synchronous and may block on iCloud, so call it off the main actor.
enum FolderIO {
    /// Runs `body` with the folder's security scope open.
    static func withAccess<T>(_ folder: URL, _ body: () throws -> T) throws -> T {
        let granted = folder.startAccessingSecurityScopedResource()
        defer { if granted { folder.stopAccessingSecurityScopedResource() } }
        return try body()
    }

    static func coordinatedWrite(_ data: Data, to url: URL) throws {
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
            do { try data.write(to: target, options: .atomic) } catch { writeError = error }
        }
        if let error = coordinationError ?? writeError { throw error }
    }

    /// A coordinated read also asks iCloud to download the file if it was offloaded.
    static func coordinatedRead(_ url: URL) throws -> Data {
        var coordinationError: NSError?
        var result: Result<Data, Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { target in
            result = Result { try Data(contentsOf: target) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    static func ensureDirectory(_ url: URL) throws {
        var coordinationError: NSError?
        var createError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &coordinationError) { target in
            do {
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            } catch { createError = error }
        }
        if let error = coordinationError ?? createError { throw error }
    }

    /// Lists a directory. Offloaded iCloud files are returned under their real name
    /// with `needsDownload` set, and a download is started for them.
    static func listFiles(in directory: URL) throws -> [(url: URL, needsDownload: Bool)] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path(percentEncoded: false)) else { return [] }
        let keys: [URLResourceKey] = [.ubiquitousItemDownloadingStatusKey, .isUbiquitousItemKey]
        let entries = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)
        return entries.compactMap { entry in
            let name = entry.lastPathComponent
            if let real = SyncLayout.realName(forPlaceholder: name) {
                let realURL = directory.appending(path: real)
                try? fm.startDownloadingUbiquitousItem(at: realURL)
                return (realURL, true)
            }
            if name.hasPrefix(".") { return nil }
            let values = try? entry.resourceValues(forKeys: Set(keys))
            if values?.isUbiquitousItem == true,
               let status = values?.ubiquitousItemDownloadingStatus, status != .current {
                try? fm.startDownloadingUbiquitousItem(at: entry)
                return (entry, true)
            }
            return (entry, false)
        }
    }
}
