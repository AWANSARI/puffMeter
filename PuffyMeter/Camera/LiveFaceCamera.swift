import SwiftUI
import ARKit
import SceneKit
import AVFoundation
import Vision
import CoreImage
import PuffyKit

enum LiveFaceCamera {
    /// ARKit face tracking on TrueDepth devices; AVFoundation + Vision elsewhere.
    @MainActor
    static func make() -> any FaceCameraSession {
        ARFaceTrackingConfiguration.isSupported ? ARFaceCamera() : VisionFaceCamera()
    }
}

/// Region of the preview the oval occupies (normalized), shared by both cameras.
enum OvalGuide {
    static let center = CGPoint(x: 0.5, y: 0.44)
    static let tolerance = 0.08
}

// MARK: - ARKit

@MainActor
@Observable
final class ARFaceCamera: NSObject, FaceCameraSession {
    private(set) var checks = ScanChecks()
    private(set) var isRunning = false
    private(set) var meshPoints: [CGPoint] = []

    @ObservationIgnored let sceneView = ARSCNView()
    @ObservationIgnored private var lastEvaluation = Date.distantPast
    @ObservationIgnored private var latestAnchor: ARFaceAnchor?
    @ObservationIgnored private var latestQuality = ScanQuality.ideal

    override init() {
        super.init()
        sceneView.automaticallyUpdatesLighting = false
        sceneView.session.delegate = self
    }

    func start() {
        guard !isRunning else { return }
        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = true
        configuration.maximumNumberOfTrackedFaces = 2
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        isRunning = true
    }

    func stop() {
        sceneView.session.pause()
        isRunning = false
    }

    func makePreview() -> AnyView {
        AnyView(ARPreview(view: sceneView))
    }

    func capture(manual: Bool) async throws -> CapturedFace {
        let frame: ARFrame = try await withCheckedThrowingContinuation { continuation in
            sceneView.session.captureHighResolutionFrame { frame, error in
                if let frame { continuation.resume(returning: frame) } else { continuation.resume(throwing: error ?? CameraError.captureFailed) }
            }
        }
        // Saved photo uses the true (unmirrored) orientation. Verify on device: front-camera buffers
        // arrive in landscape sensor orientation.
        let image = CIImage(cvPixelBuffer: frame.capturedImage).oriented(.right)
        guard let jpeg = CIContext().jpegRepresentation(of: image, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                         options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.9]) else {
            throw CameraError.captureFailed
        }
        let anchor = latestAnchor
        var quality = latestQuality
        quality.manual = manual
        let raw = anchor.map(FaceGeometryMetrics.measure)
        let transform = anchor.map { anchor -> [Float] in
            let m = anchor.transform
            return [m.columns.0, m.columns.1, m.columns.2, m.columns.3].flatMap { [$0.x, $0.y, $0.z, $0.w] }
        }
        return CapturedFace(jpegData: jpeg, capturedAt: .now, quality: quality, raw: raw, faceTransform: transform)
    }

    fileprivate func evaluate(frame: ARFrame) {
        let faces = frame.anchors.compactMap { $0 as? ARFaceAnchor }.filter(\.isTracked)
        var next = ScanChecks(faceCount: faces.count)
        guard faces.count == 1, let face = faces.first else {
            checks = next
            latestAnchor = nil
            return
        }
        latestAnchor = face
        let camera = frame.camera
        let cameraPosition = simd_make_float3(camera.transform.columns.3)
        let facePosition = simd_make_float3(face.transform.columns.3)
        let distance = simd_distance(cameraPosition, facePosition)
        next.distance = distance < 0.28 ? .tooClose : (distance > 0.47 ? .tooFar : .ok)

        let viewport = sceneView.bounds.size
        if viewport.width > 0 {
            let projected = camera.projectPoint(facePosition, orientation: .portrait, viewportSize: viewport)
            let normalized = CGPoint(x: projected.x / viewport.width, y: projected.y / viewport.height)
            next.centered = abs(normalized.x - OvalGuide.center.x) < OvalGuide.tolerance
                && abs(normalized.y - OvalGuide.center.y) < OvalGuide.tolerance * 1.4
        }

        // Head pose relative to the camera.
        let relative = simd_mul(simd_inverse(camera.transform), face.transform)
        let pitch = asin(-Double(relative.columns.2.y)) * 180 / .pi
        let yaw = atan2(Double(relative.columns.2.x), Double(relative.columns.2.z)) * 180 / .pi
        let roll = atan2(Double(relative.columns.0.y), Double(relative.columns.1.y)) * 180 / .pi
        // Front camera faces the user, so a straight-on face has yaw near ±180°; normalize.
        let yawNormalized = abs(yaw) > 90 ? (yaw > 0 ? yaw - 180 : yaw + 180) : yaw
        next.level = abs(yawNormalized) < 8 && abs(roll) < 8 && abs(pitch) < 12

        let intensity = Double(frame.lightEstimate?.ambientIntensity ?? 1000)
        next.goodLighting = (550...2200).contains(intensity)

        let shapes = face.blendShapes
        func value(_ key: ARFaceAnchor.BlendShapeLocation) -> Double { shapes[key]?.doubleValue ?? 0 }
        let expression = max(value(.mouthSmileLeft), value(.mouthSmileRight), value(.jawOpen), value(.browInnerUp),
                             value(.eyeBlinkLeft), value(.eyeBlinkRight))
        next.neutralFace = expression < 0.3

        latestQuality = ScanQuality(lighting: min(1, max(0, 1 - abs(intensity - 1000) / 1500)), yawDeg: yawNormalized,
                                    rollDeg: roll, pitchDeg: pitch, neutrality: 1 - expression, method: .arkit)
        checks = next
    }
}

extension ARFaceCamera: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Throttle to ~10 Hz on the main actor.
        Task { @MainActor [weak self] in
            guard let self, Date.now.timeIntervalSince(self.lastEvaluation) > 0.1 else { return }
            self.lastEvaluation = .now
            self.evaluate(frame: frame)
        }
    }
}

private struct ARPreview: UIViewRepresentable {
    let view: ARSCNView
    func makeUIView(context: Context) -> ARSCNView { view }
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

/// IPD-normalized zone measurements from the ARKit face mesh. Regions are selected
/// geometrically (relative to the eye positions) rather than by undocumented vertex indices.
enum FaceGeometryMetrics {
    static func measure(_ anchor: ARFaceAnchor) -> RawFaceMetrics {
        let vertices = anchor.geometry.vertices
        let leftEye = simd_make_float3(anchor.leftEyeTransform.columns.3)
        let rightEye = simd_make_float3(anchor.rightEyeTransform.columns.3)
        let ipd = max(simd_distance(leftEye, rightEye), 0.04)
        let eyeY = (leftEye.y + rightEye.y) / 2

        func region(yRange: ClosedRange<Float>, absX: ClosedRange<Float>) -> [SIMD3<Float>] {
            vertices.filter { yRange.contains($0.y - eyeY) && absX.contains(abs($0.x)) }
        }
        func meanZ(_ points: [SIMD3<Float>]) -> Float {
            points.isEmpty ? 0 : points.reduce(0) { $0 + $1.z } / Float(points.count)
        }

        // Under-eyes: forward projection of the infraorbital band relative to the cheekbone.
        let underEye = region(yRange: -0.028 ... -0.010, absX: 0.012...0.045)
        let cheekbone = region(yRange: -0.045 ... -0.028, absX: 0.040...0.062)
        let underEyes = (meanZ(underEye) - meanZ(cheekbone)) / ipd

        // Cheeks: mid-face width plus forward fullness.
        let midCheek = region(yRange: -0.055 ... -0.030, absX: 0...1)
        let cheekWidth = (midCheek.map { abs($0.x) }.max() ?? 0) * 2
        let cheekFullness = meanZ(region(yRange: -0.06 ... -0.035, absX: 0.035...0.06))
        let cheeks = cheekWidth / ipd + cheekFullness / ipd * 0.5

        // Jawline: width at the jaw level (softer jaw = wider, less defined).
        let jaw = region(yRange: -0.105 ... -0.085, absX: 0...1)
        let jawWidth = (jaw.map { abs($0.x) }.max() ?? 0) * 2
        let jawline = jawWidth / ipd

        return RawFaceMetrics(underEyes: Double(underEyes), cheeks: Double(cheeks), jawline: Double(jawline))
    }
}

// MARK: - AVFoundation + Vision fallback

@MainActor
@Observable
final class VisionFaceCamera: NSObject, FaceCameraSession {
    private(set) var checks = ScanChecks()
    private(set) var isRunning = false
    var meshPoints: [CGPoint] { [] }

    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private let videoOutput = AVCaptureVideoDataOutput()
    @ObservationIgnored private let photoOutput = AVCapturePhotoOutput()
    @ObservationIgnored private let queue = DispatchQueue(label: "PuffyMeter.camera")
    @ObservationIgnored private var lastEvaluation = Date.distantPast
    @ObservationIgnored private var photoContinuation: CheckedContinuation<Data, Error>?
    @ObservationIgnored private var latestQuality = ScanQuality.ideal

    override init() {
        super.init()
        session.sessionPreset = .photo
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return }
        session.addInput(input)
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        videoOutput.connection(with: .video)?.videoRotationAngle = 90
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let session = self.session
        queue.async { session.startRunning() }
    }

    func stop() {
        isRunning = false
        let session = self.session
        queue.async { session.stopRunning() }
    }

    func makePreview() -> AnyView { AnyView(VideoPreview(session: session)) }

    func capture(manual: Bool) async throws -> CapturedFace {
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            photoContinuation = continuation
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            photoOutput.connection(with: .video)?.videoRotationAngle = 90
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
        var quality = latestQuality
        quality.manual = manual
        return CapturedFace(jpegData: data, capturedAt: .now, quality: quality, raw: nil, faceTransform: nil)
    }

    fileprivate func apply(_ checks: ScanChecks, quality: ScanQuality) {
        self.checks = checks
        latestQuality = quality
    }
}

extension VisionFaceCamera: AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let rectangles = VNDetectFaceRectanglesRequest()
        let quality = VNDetectFaceCaptureQualityRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .leftMirrored)
        try? handler.perform([rectangles, quality])
        let faces = rectangles.results ?? []
        var checks = ScanChecks(faceCount: faces.count)
        var scanQuality = ScanQuality(lighting: 0.5, yawDeg: 0, rollDeg: 0, neutrality: 0.5, method: .vision)
        if faces.count == 1, let face = faces.first {
            let box = face.boundingBox
            let center = CGPoint(x: box.midX, y: 1 - box.midY)
            checks.centered = abs(center.x - OvalGuide.center.x) < OvalGuide.tolerance
                && abs(center.y - OvalGuide.center.y) < OvalGuide.tolerance * 1.4
            checks.distance = box.height < 0.32 ? .tooFar : (box.height > 0.55 ? .tooClose : .ok)
            let yaw = (face.yaw?.doubleValue ?? 0) * 180 / .pi
            let roll = (face.roll?.doubleValue ?? 0) * 180 / .pi
            let pitch = (face.pitch?.doubleValue ?? 0) * 180 / .pi
            checks.level = abs(yaw) < 8 && abs(roll) < 8 && abs(pitch) < 12
            let luma = LumaSampler.mean(pixelBuffer, in: box)
            checks.goodLighting = (0.35...0.8).contains(luma)
            let captureQuality = Double((quality.results?.first?.faceCaptureQuality) ?? 0)
            checks.neutralFace = captureQuality >= 0.5
            scanQuality = ScanQuality(lighting: 1 - abs(luma - 0.55) * 2, yawDeg: yaw, rollDeg: roll, pitchDeg: pitch,
                                      neutrality: captureQuality, method: .vision)
        }
        Task { @MainActor [weak self] in
            guard let self, Date.now.timeIntervalSince(self.lastEvaluation) > 0.1 else { return }
            self.lastEvaluation = .now
            self.apply(checks, quality: scanQuality)
        }
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = photo.fileDataRepresentation()
        Task { @MainActor in
            if let data { photoContinuation?.resume(returning: data) } else { photoContinuation?.resume(throwing: error ?? CameraError.captureFailed) }
            photoContinuation = nil
        }
    }
}

private struct VideoPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

enum LumaSampler {
    /// Mean luma (0...1) of a normalized Vision rect in a bi-planar YUV buffer.
    static func mean(_ buffer: CVPixelBuffer, in rect: CGRect) -> Double {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard CVPixelBufferGetPlaneCount(buffer) > 0, let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return 0.5 }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        let x0 = Int(rect.minX * CGFloat(width)), x1 = Int(rect.maxX * CGFloat(width))
        let y0 = Int((1 - rect.maxY) * CGFloat(height)), y1 = Int((1 - rect.minY) * CGFloat(height))
        var total = 0, count = 0
        for y in Swift.stride(from: max(0, y0), to: min(height, y1), by: 4) {
            for x in Swift.stride(from: max(0, x0), to: min(width, x1), by: 4) {
                total += Int(pixels[y * stride + x])
                count += 1
            }
        }
        return count > 0 ? Double(total) / Double(count) / 255 : 0.5
    }
}
