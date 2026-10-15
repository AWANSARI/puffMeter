import Foundation
import Vision
import CoreGraphics
import ImageIO
import PuffyKit

/// Measures IPD-normalized zone metrics from a still photo with Vision landmarks. Used when
/// the capture didn't come with ARKit geometry (non-TrueDepth devices).
struct VisionFaceAnalyzer: FaceAnalyzing {
    enum AnalyzerError: Error { case noFace, unreadableImage }

    func measure(_ capture: CapturedFace) async throws -> RawFaceMetrics {
        if let raw = capture.raw { return raw }
        guard let source = CGImageSourceCreateWithData(capture.jpegData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw AnalyzerError.unreadableImage }
        let request = VNDetectFaceLandmarksRequest()
        try VNImageRequestHandler(cgImage: image).perform([request])
        guard let face = request.results?.first, let landmarks = face.landmarks,
              let contour = landmarks.faceContour, let leftPupil = landmarks.leftPupil,
              let rightPupil = landmarks.rightPupil else { throw AnalyzerError.noFace }

        let size = CGSize(width: image.width, height: image.height)
        func points(_ region: VNFaceLandmarkRegion2D) -> [CGPoint] { region.pointsInImage(imageSize: size) }
        let left = points(leftPupil).first ?? .zero
        let right = points(rightPupil).first ?? .zero
        let ipd = max(hypot(right.x - left.x, right.y - left.y), 1)
        let eyeY = (left.y + right.y) / 2

        // Vision image coordinates have the origin at the bottom-left; the contour runs ear to ear under the chin.
        let contourPoints = points(contour)
        let chinY = contourPoints.map(\.y).min() ?? eyeY - ipd * 2
        func width(atY y: CGFloat) -> CGFloat {
            let band = contourPoints.filter { abs($0.y - y) < ipd * 0.12 }
            guard let minX = band.map(\.x).min(), let maxX = band.map(\.x).max() else { return 0 }
            return maxX - minX
        }
        let cheekY = eyeY - (eyeY - chinY) * 0.40
        let jawY = eyeY - (eyeY - chinY) * 0.80
        let cheeks = width(atY: cheekY) / ipd
        let jawline = width(atY: jawY) / ipd

        // Under-eye shadow depth: luma of the band below each eye vs the cheek band.
        let gray = GrayImage(image)
        func band(center: CGPoint, dy: CGFloat) -> Double {
            gray.mean(in: CGRect(x: center.x - ipd * 0.18, y: center.y - dy - ipd * 0.05, width: ipd * 0.36, height: ipd * 0.1))
        }
        let underBand = (band(center: left, dy: ipd * 0.22) + band(center: right, dy: ipd * 0.22)) / 2
        let cheekBand = (band(center: left, dy: ipd * 0.5) + band(center: right, dy: ipd * 0.5)) / 2
        let underEyes = (cheekBand - underBand) * 0.1

        return RawFaceMetrics(underEyes: underEyes, cheeks: cheeks, jawline: jawline)
    }
}

/// Grayscale copy of an image for cheap luma sampling (Vision coordinates: origin bottom-left).
private struct GrayImage {
    let pixels: [UInt8]
    let width: Int
    let height: Int

    init(_ image: CGImage) {
        let scale = min(1, 600 / Double(max(image.width, image.height)))
        width = Int(Double(image.width) * scale)
        height = Int(Double(image.height) * scale)
        var buffer = [UInt8](repeating: 0, count: width * height)
        let drawWidth = width, drawHeight = height
        buffer.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: drawWidth, height: drawHeight, bitsPerComponent: 8,
                                    bytesPerRow: drawWidth, space: CGColorSpaceCreateDeviceGray(),
                                    bitmapInfo: CGImageAlphaInfo.none.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: drawWidth, height: drawHeight))
        }
        pixels = buffer
        self.scaleFactor = scale
    }

    private let scaleFactor: Double

    func mean(in rect: CGRect) -> Double {
        // Convert from full-size bottom-left coordinates to the scaled top-left bitmap rows.
        let r = CGRect(x: rect.minX * scaleFactor, y: rect.minY * scaleFactor,
                       width: rect.width * scaleFactor, height: rect.height * scaleFactor)
        var total = 0, count = 0
        for y in Int(r.minY)..<Int(r.maxY) {
            let row = height - 1 - y
            guard row >= 0 && row < height else { continue }
            for x in Int(r.minX)..<Int(r.maxX) where x >= 0 && x < width {
                total += Int(pixels[row * width + x])
                count += 1
            }
        }
        return count > 0 ? Double(total) / Double(count) / 255 : 0.5
    }
}
