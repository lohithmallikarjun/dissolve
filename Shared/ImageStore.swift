import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
typealias PlatformImage = UIImage
#else
typealias PlatformImage = NSImage
#endif

extension Image {
    init(platformImage: PlatformImage) {
        #if os(iOS)
        self.init(uiImage: platformImage)
        #else
        self.init(nsImage: platformImage)
        #endif
    }
}

/// Journal photos on disk (App Group `Photos/`), never in the database:
/// `<id>.heic` resized to ~2048 px on the long edge, and `<id>_thumb.heic` at 400 px.
enum ImageStore {
    struct Saved: Sendable {
        let id: UUID
        let width: Int
        let height: Int
    }

    enum Failure: Error { case unreadable, encodingFailed }

    static let fullSize = 2048
    static let thumbSize = 400

    static var folder: URL {
        let folder = (AppGroup.containerURL ?? URL.applicationSupportDirectory).appending(path: "Photos")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func fileName(id: UUID) -> String { "\(id.uuidString).heic" }
    static func thumbFileName(id: UUID) -> String { "\(id.uuidString)_thumb.heic" }
    static func url(id: UUID) -> URL { folder.appending(path: fileName(id: id)) }
    static func thumbURL(id: UUID) -> URL { folder.appending(path: thumbFileName(id: id)) }

    static func hasFiles(id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: url(id: id).path(percentEncoded: false))
    }

    /// Resizes and stores an image. Call off the main thread.
    static func save(imageData: Data) throws -> Saved {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else { throw Failure.unreadable }
        let full = try downsample(source, maxPixels: fullSize)
        let thumb = try downsample(source, maxPixels: thumbSize)
        let id = UUID()
        try encode(full, quality: 0.8).write(to: url(id: id), options: .atomic)
        try encode(thumb, quality: 0.7).write(to: thumbURL(id: id), options: .atomic)
        return Saved(id: id, width: full.width, height: full.height)
    }

    static func deleteFiles(id: UUID) {
        try? FileManager.default.removeItem(at: url(id: id))
        try? FileManager.default.removeItem(at: thumbURL(id: id))
    }

    static func thumbnail(id: UUID) -> PlatformImage? { load(thumbURL(id: id)) }
    static func image(id: UUID) -> PlatformImage? { load(url(id: id)) }

    private static func load(_ url: URL) -> PlatformImage? {
        #if os(iOS)
        UIImage(contentsOfFile: url.path(percentEncoded: false))
        #else
        NSImage(contentsOf: url)
        #endif
    }

    private static func downsample(_ source: CGImageSource, maxPixels: Int) throws -> CGImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw Failure.unreadable
        }
        return image
    }

    /// HEIC, falling back to JPEG where HEIC encoding isn't available. (Image I/O reads either,
    /// whatever the file extension.)
    private static func encode(_ image: CGImage, quality: Double) throws -> Data {
        for type in [UTType.heic, .jpeg] {
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
                continue
            }
            CGImageDestinationAddImage(destination, image,
                                       [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            if CGImageDestinationFinalize(destination) { return data as Data }
        }
        throw Failure.encodingFailed
    }
}
