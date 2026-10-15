import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Stores scan photos in Application Support/Scans with complete file protection and
/// excluded from iCloud backup (the user's own Drive is the backup).
public actor FilePhotoStore: PhotoStore {
    private let directory: URL

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.directory = base.appendingPathComponent("Scans", isDirectory: true)
        }
    }

    public func save(jpeg: Data, scanID: UUID) throws -> (photo: String, thumbnail: String) {
        try prepareDirectory()
        let photoName = "\(scanID.uuidString).jpg"
        let thumbName = "\(scanID.uuidString)-thumb.jpg"
        try jpeg.write(to: url(for: photoName), options: Self.writeOptions)
        if let thumb = ImageUtilities.downsampledJPEG(jpeg, maxPixelSize: 300, quality: 0.8) {
            try thumb.write(to: url(for: thumbName), options: Self.writeOptions)
        }
        return (photoName, thumbName)
    }

    public nonisolated func url(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    public func image(named fileName: String) -> PlatformImage? {
        guard let data = try? Data(contentsOf: url(for: fileName)) else { return nil }
        return PlatformImage(data: data)
    }

    public func data(named fileName: String) -> Data? {
        try? Data(contentsOf: url(for: fileName))
    }

    public func deleteAll() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    private func prepareDirectory() throws {
        guard !FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = directory
        try mutable.setResourceValues(values)
    }

    private static var writeOptions: Data.WritingOptions {
        #if os(iOS)
        [.atomic, .completeFileProtection]
        #else
        [.atomic]
        #endif
    }
}

public enum ImageUtilities {
    /// Re-encodes a JPEG with its longest side limited, stripping GPS metadata.
    public static func downsampledJPEG(_ data: Data, maxPixelSize: Int?, quality: Double) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let image: CGImage?
        if let maxPixelSize {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            ]
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        } else {
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        guard let image else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        // Only orientation-free pixels and quality are written: no GPS or other location metadata.
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
