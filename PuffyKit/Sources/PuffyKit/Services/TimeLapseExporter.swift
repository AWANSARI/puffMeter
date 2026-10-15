import AVFoundation
import CoreGraphics
import CoreVideo
import ImageIO

/// Writes the scan photos into an MP4 (1080 × 1440). Photos are only cropped to fill the
/// frame, never retouched ("Original photos · No smoothing").
public enum TimeLapseExporter {
    public static func export(scans: [ScanRecord], photos: PhotoStore, framesPerSecond: Int32 = 4) async -> URL? {
        let size = CGSize(width: 1080, height: 1440)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PuffyMeter-time-lapse.mp4")
        try? FileManager.default.removeItem(at: url)

        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return nil }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: size.width,
            kCVPixelBufferHeightKey as String: size.height,
        ])
        guard writer.canAdd(input) else { return nil }
        writer.add(input)
        guard writer.startWriting() else { return nil }
        writer.startSession(atSourceTime: .zero)

        var frame: Int64 = 0
        for scan in scans {
            guard let name = scan.photoFileName,
                  let data = await photos.data(named: name),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  let buffer = pixelBuffer(from: image, size: size) else { continue }
            while !input.isReadyForMoreMediaData {
                try? await Task.sleep(for: .milliseconds(10))
            }
            adaptor.append(buffer, withPresentationTime: CMTime(value: frame, timescale: framesPerSecond))
            frame += 1
        }
        input.markAsFinished()
        await writer.finishWriting()
        return writer.status == .completed && frame > 0 ? url : nil
    }

    private static func pixelBuffer(from image: CGImage, size: CGSize) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height), kCVPixelFormatType_32ARGB,
                            [kCVPixelBufferCGImageCompatibilityKey: true,
                             kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary, &buffer)
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width),
                                      height: Int(size.height), bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { return nil }
        // Aspect-fill crop.
        let scale = max(size.width / CGFloat(image.width), size.height / CGFloat(image.height))
        let drawSize = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        let origin = CGPoint(x: (size.width - drawSize.width) / 2, y: (size.height - drawSize.height) / 2)
        context.draw(image, in: CGRect(origin: origin, size: drawSize))
        return buffer
    }
}
