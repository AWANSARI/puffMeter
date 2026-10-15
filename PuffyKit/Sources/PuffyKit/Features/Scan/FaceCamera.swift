import SwiftUI
import Observation

/// Live quality checks that drive the checklist and auto-capture.
public struct ScanChecks: Equatable, Sendable {
    public var faceCount: Int
    public var centered: Bool
    public var distance: Distance
    public var level: Bool
    public var goodLighting: Bool
    public var neutralFace: Bool

    public enum Distance: Sendable { case ok, tooFar, tooClose }

    public init(faceCount: Int = 0, centered: Bool = false, distance: Distance = .ok, level: Bool = false,
                goodLighting: Bool = false, neutralFace: Bool = false) {
        self.faceCount = faceCount
        self.centered = centered
        self.distance = distance
        self.level = level
        self.goodLighting = goodLighting
        self.neutralFace = neutralFace
    }

    public var isCentered: Bool { faceCount == 1 && centered && distance == .ok && level }
    public var allPassed: Bool { isCentered && goodLighting && neutralFace }

    /// The single most useful coaching message, or nil when everything passes.
    public var guidance: String? {
        if faceCount == 0 { return "Center your face in the oval" }
        if faceCount > 1 { return "Only one face, please" }
        switch distance {
        case .tooFar: return "Move a little closer"
        case .tooClose: return "Move back slightly"
        case .ok: break
        }
        if !level { return "Level your head" }
        if !centered { return "Center your face in the oval" }
        if !goodLighting { return "Find softer, even light" }
        if !neutralFace { return "Relax your face" }
        return nil
    }

    public static let passing = ScanChecks(faceCount: 1, centered: true, distance: .ok, level: true,
                                           goodLighting: true, neutralFace: true)
}

/// A front-camera session. The app provides an ARKit/AVFoundation implementation; the
/// package ships a simulated one for the Simulator, previews and UI tests.
@MainActor
public protocol FaceCameraSession: AnyObject, Observable {
    var checks: ScanChecks { get }
    var isRunning: Bool { get }
    /// Live (ARKit) mesh points in normalized preview coordinates, used for the overlay.
    var meshPoints: [CGPoint] { get }
    func start()
    func stop()
    func capture(manual: Bool) async throws -> CapturedFace
    func makePreview() -> AnyView
}

public enum CameraError: Error {
    case unavailable
    case captureFailed
}

/// Simulated camera: shows the illustrated face, passes checks progressively, and
/// captures a rendered JPEG.
@MainActor
@Observable
public final class SimulatedFaceCamera: FaceCameraSession {
    public private(set) var checks = ScanChecks()
    public private(set) var isRunning = false
    public var meshPoints: [CGPoint] { [] }
    private var task: Task<Void, Never>?
    private let puffiness: Double

    public init(puffiness: Double = Double.random(in: 0.15...0.55)) {
        self.puffiness = puffiness
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        checks = ScanChecks()
        task = Task { [weak self] in
            let steps: [(Duration, (inout ScanChecks) -> Void)] = [
                (.milliseconds(500), { $0.faceCount = 1; $0.distance = .tooFar }),
                (.milliseconds(500), { $0.distance = .ok; $0.level = true; $0.centered = true }),
                (.milliseconds(400), { $0.goodLighting = true }),
                (.milliseconds(400), { $0.neutralFace = true }),
            ]
            for (delay, change) in steps {
                try? await Task.sleep(for: delay)
                guard let self, !Task.isCancelled else { return }
                change(&self.checks)
            }
        }
    }

    public func stop() {
        task?.cancel()
        isRunning = false
    }

    public func capture(manual: Bool) async throws -> CapturedFace {
        guard let data = SampleFaceRenderer.jpeg(puffiness: puffiness) else { throw CameraError.captureFailed }
        let quality = ScanQuality(lighting: 0.85, yawDeg: 1.2, rollDeg: 0.4, neutrality: 0.94,
                                  method: .fixture, manual: manual)
        let base = FixtureFaceAnalyzer().base
        let raw = RawFaceMetrics(underEyes: base.underEyes + (puffiness - 0.3) * 0.03,
                                 cheeks: base.cheeks + (puffiness - 0.3) * 0.03,
                                 jawline: base.jawline + (puffiness - 0.3) * 0.025)
        return CapturedFace(jpegData: data, capturedAt: .now, quality: quality, raw: raw, faceTransform: nil)
    }

    public func makePreview() -> AnyView {
        AnyView(SampleFaceIllustration(puffiness: puffiness))
    }
}
