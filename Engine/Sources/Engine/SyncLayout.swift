import Foundation

/// File layout inside the user's chosen iCloud Drive folder.
///
/// Each device writes only its own files, so two devices never edit the same file.
public enum SyncLayout {
    public static let changesFolder = "changes"
    public static let photosFolder = "photos"
    public static let snapshotsFolder = "snapshots"
    /// Milestone 0 handshake files.
    public static let diagnosticsFolder = "m0"

    /// `changes/<deviceID>/<yyyy-MM>.jsonl`
    public static func changeLogPath(deviceID: String, month: LocalDate) -> String {
        "\(changesFolder)/\(deviceID)/\(month.monthKey).jsonl"
    }

    /// `photos/<uuid>.heic`
    public static func photoPath(id: UUID) -> String {
        "\(photosFolder)/\(id.uuidString).heic"
    }

    /// `photos/<uuid>_thumb.heic`
    public static func thumbnailPath(id: UUID) -> String {
        "\(photosFolder)/\(id.uuidString)_thumb.heic"
    }

    /// `m0/<deviceID>.json`
    public static func diagnosticPath(deviceID: String) -> String {
        "\(diagnosticsFolder)/\(deviceID).json"
    }

    /// iCloud may show an offloaded file as a hidden placeholder `.<name>.icloud`.
    /// Returns the real file name, or nil if `fileName` isn't a placeholder.
    public static func realName(forPlaceholder fileName: String) -> String? {
        guard fileName.hasPrefix("."), fileName.hasSuffix(".icloud"), fileName.count > 8 else {
            return nil
        }
        return String(fileName.dropFirst().dropLast(".icloud".count))
    }
}
