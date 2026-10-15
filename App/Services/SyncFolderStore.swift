import Engine
import Foundation
import Observation

/// One test file found in `m0/`, written by this or another device.
struct DiagnosticFile: Identifiable, Sendable {
    var id: String { fileName }
    let fileName: String
    let payload: DiagnosticPayload?
    let problem: String?
}

/// Remembers the iCloud Drive folder the user picked (as a security-scoped
/// bookmark) and runs the Milestone 0 write/read handshake in it.
@MainActor @Observable
final class SyncFolderStore {
    struct Message: Equatable {
        let text: String
        let isError: Bool
    }

    private(set) var folderURL: URL?
    private(set) var files: [DiagnosticFile] = []
    private(set) var message: Message?
    private(set) var isWorking = false

    private let bookmarkKey = "sync.folderBookmark"
    private let defaults: UserDefaults

    #if os(macOS)
    private static let bookmarkCreation: URL.BookmarkCreationOptions = [.withSecurityScope]
    private static let bookmarkResolution: URL.BookmarkResolutionOptions = [.withSecurityScope]
    #else
    private static let bookmarkCreation: URL.BookmarkCreationOptions = []
    private static let bookmarkResolution: URL.BookmarkResolutionOptions = []
    #endif

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        folderURL = resolveBookmark()
    }

    var folderName: String? { folderURL?.lastPathComponent }

    /// Handles the result of `.fileImporter(allowedContentTypes: [.folder])`.
    func select(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            message = Message(text: error.localizedDescription, isError: true)
        case .success(let url):
            do {
                let data = try FolderIO.withAccess(url) {
                    try url.bookmarkData(
                        options: Self.bookmarkCreation,
                        includingResourceValuesForKeys: nil, relativeTo: nil)
                }
                defaults.set(data, forKey: bookmarkKey)
                folderURL = url
                files = []
                message = Message(text: "Folder saved. It will be remembered after relaunch.", isError: false)
            } catch {
                message = Message(text: "Couldn't remember that folder: \(error.localizedDescription)", isError: true)
            }
        }
    }

    func forgetFolder() {
        defaults.removeObject(forKey: bookmarkKey)
        folderURL = nil
        files = []
        message = nil
    }

    /// Writes `m0/<deviceID>.json`, then re-reads the folder.
    func writeTestFile(appGroupValue: Int) async {
        guard let folder = folderURL else { return }
        isWorking = true
        defer { isWorking = false }
        let payload = DiagnosticPayload(
            deviceID: DeviceIdentity.id, deviceName: DeviceIdentity.name,
            platform: DeviceIdentity.platform, writtenAt: .now, appGroupValue: appGroupValue)
        do {
            try await Task.detached {
                try FolderIO.withAccess(folder) {
                    let data = try JSONEncoder.sync.encode(payload)
                    try FolderIO.ensureDirectory(folder.appending(path: SyncLayout.diagnosticsFolder))
                    try FolderIO.coordinatedWrite(
                        data, to: folder.appending(path: SyncLayout.diagnosticPath(deviceID: payload.deviceID)))
                }
            }.value
            message = Message(text: "Wrote test file for \(payload.deviceName).", isError: false)
            await readTestFiles()
        } catch {
            message = Message(text: "Write failed: \(error.localizedDescription)", isError: true)
        }
    }

    /// Reads every device's `m0/*.json`.
    func readTestFiles() async {
        guard let folder = folderURL else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let found = try await Task.detached {
                try FolderIO.withAccess(folder) {
                    try FolderIO.listFiles(in: folder.appending(path: SyncLayout.diagnosticsFolder))
                        .filter { $0.url.pathExtension == "json" }
                        .map { entry -> DiagnosticFile in
                            let name = entry.url.lastPathComponent
                            do {
                                let data = try FolderIO.coordinatedRead(entry.url)
                                let payload = try JSONDecoder.sync.decode(DiagnosticPayload.self, from: data)
                                return DiagnosticFile(fileName: name, payload: payload, problem: nil)
                            } catch {
                                let problem = entry.needsDownload
                                    ? "Downloading from iCloud… tap Read again in a moment."
                                    : error.localizedDescription
                                return DiagnosticFile(fileName: name, payload: nil, problem: problem)
                            }
                        }
                }
            }.value
            files = found.sorted { ($0.payload?.writtenAt ?? .distantPast) > ($1.payload?.writtenAt ?? .distantPast) }
            let others = found.filter { $0.payload != nil && $0.payload?.deviceID != DeviceIdentity.id }.count
            message = Message(
                text: others > 0
                    ? "Read \(found.count) file(s), \(others) from another device ✓"
                    : "Read \(found.count) file(s). None from another device yet.",
                isError: false)
        } catch {
            message = Message(text: "Read failed: \(error.localizedDescription)", isError: true)
        }
    }

    private func resolveBookmark() -> URL? {
        guard let data = defaults.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data, options: Self.bookmarkResolution,
                relativeTo: nil, bookmarkDataIsStale: &isStale)
            if isStale, let fresh = try? FolderIO.withAccess(url, {
                try url.bookmarkData(options: Self.bookmarkCreation, includingResourceValuesForKeys: nil, relativeTo: nil)
            }) {
                defaults.set(fresh, forKey: bookmarkKey)
            }
            return url
        } catch {
            message = Message(text: "Saved folder is no longer reachable. Choose it again.", isError: true)
            return nil
        }
    }
}
