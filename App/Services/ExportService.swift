import Engine
import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// "Export everything": data as JSON, one Markdown file per journal entry, and all photos, zipped.
@MainActor
enum ExportService {
    enum Failure: LocalizedError {
        case zipFailed
        var errorDescription: String? { String(localized: "Couldn't create the zip file.") }
    }

    static func makeArchive(context: ModelContext) async throws -> ZipDocument {
        let stamp = AppSettings.today().description
        let root = FileManager.default.temporaryDirectory.appending(path: "Dissolve-\(UUID().uuidString)")
        let folder = root.appending(path: "Dissolve Export \(stamp)")
        let journalFolder = folder.appending(path: "Journal")
        let photosFolder = folder.appending(path: "Photos")
        try FileManager.default.createDirectory(at: journalFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: photosFolder, withIntermediateDirectories: true)

        // 1. All data, grouped by kind, as readable JSON.
        let records = SyncExport.allRecords(in: context, device: DeviceIdentity.id)
        var grouped: [String: [JSONValue]] = [:]
        for record in records {
            var object: [String: JSONValue] = ["id": .string(record.id.uuidString),
                                               "updatedAt": .string(record.updatedAt.ISO8601Format())]
            if case .object(let fields)? = record.fields { object.merge(fields) { current, _ in current } }
            grouped[record.entity, default: []].append(.object(object))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(JSONValue.object(grouped.mapValues { .array($0) }))
            .write(to: folder.appending(path: "data.json"))

        // 2. Journal entries as Markdown.
        let entries = (try? context.fetch(FetchDescriptor<JournalEntry>(sortBy: [SortDescriptor(\.date)]))) ?? []
        for entry in entries {
            try markdown(for: entry).write(to: journalFolder.appending(path: "\(entry.date).md"), atomically: true, encoding: .utf8)
        }

        // 3. Photos (full size and thumbnails), off the main thread.
        let photoIDs = ((try? context.fetch(FetchDescriptor<Photo>())) ?? []).map(\.id)
        let zipData = try await Task.detached {
            for id in photoIDs {
                for source in [ImageStore.url(id: id), ImageStore.thumbURL(id: id)] {
                    let target = photosFolder.appending(path: source.lastPathComponent)
                    try? FileManager.default.copyItem(at: source, to: target)
                }
            }
            return try ExportService.zip(folder)
        }.value
        try? FileManager.default.removeItem(at: root)
        return ZipDocument(data: zipData)
    }

    static func markdown(for entry: JournalEntry) -> String {
        var lines: [String] = []
        let title = entry.localDate?.formatted(.dateTime.weekday(.wide).month(.wide).day().year()) ?? entry.date
        lines.append("# \(title)")
        if let mood = Mood(rawValue: entry.mood) { lines.append("Mood: \(String(localized: mood.name)) (\(mood.rawValue)/5)") }
        lines.append("")
        for block in entry.orderedBlocks {
            switch block.kind {
            case .heading:
                lines.append("## \(block.promptText)")
            case .prompt:
                lines.append("**\(block.promptText)**")
                if !block.text.isEmpty { lines.append(block.text) }
            case .text:
                if !block.text.isEmpty { lines.append(block.text) }
            case .checklist:
                if !block.promptText.isEmpty { lines.append("**\(block.promptText)**") }
                lines += block.checklist.map { ChecklistItem(stored: $0) }.map { "- [\($0.isDone ? "x" : " ")] \($0.text)" }
            case .image:
                lines += block.photoIDs.map { "![](../Photos/\($0).heic)" }
            case .rating:
                if block.rating > 0 { lines.append("\(block.promptText): " + String(repeating: "★", count: block.rating)) }
            case .mood, .habitSummary:
                continue
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// Zips a folder using the system: a coordinated read "for uploading" produces a zip.
    nonisolated static func zip(_ folder: URL) throws -> Data {
        var coordinationError: NSError?
        var result: Result<Data, Error> = .failure(Failure.zipFailed)
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinationError) { zipURL in
            result = Result { try Data(contentsOf: zipURL) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }
}

struct ZipDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip] }
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
