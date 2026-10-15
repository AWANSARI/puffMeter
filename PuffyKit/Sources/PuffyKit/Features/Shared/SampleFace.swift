import SwiftUI

/// A neutral illustrated portrait used on the Welcome screen and by the simulated camera
/// (the Simulator has no front camera). `puffiness` 0...1 subtly widens the cheeks and
/// under-eyes so fixture captures differ.
public struct SampleFaceIllustration: View {
    var puffiness: Double

    public init(puffiness: Double = 0.3) { self.puffiness = puffiness }

    public var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let faceW = w * (0.40 + 0.03 * puffiness)
            let faceH = h * 0.40
            let cx = w / 2
            let cy = h * 0.42
            ZStack {
                LinearGradient(colors: [Color(light: 0xD9D5CF, dark: 0xD9D5CF), Color(light: 0xC4BFB8, dark: 0xC4BFB8)],
                               startPoint: .top, endPoint: .bottom)
                // Shoulders / sweater
                Ellipse()
                    .fill(Color(light: 0x4A4A4C, dark: 0x4A4A4C))
                    .frame(width: w * 1.05, height: h * 0.5)
                    .position(x: cx, y: h * 1.02)
                // Neck
                RoundedRectangle(cornerRadius: w * 0.05)
                    .fill(Color(light: 0xD8A98A, dark: 0xD8A98A))
                    .frame(width: faceW * 0.42, height: h * 0.16)
                    .position(x: cx, y: cy + faceH * 0.58)
                // Hair back
                Ellipse()
                    .fill(Color(light: 0x3B2A21, dark: 0x3B2A21))
                    .frame(width: faceW * 1.12, height: faceH * 1.08)
                    .position(x: cx, y: cy - faceH * 0.08)
                // Face
                Ellipse()
                    .fill(RadialGradient(colors: [Color(light: 0xF0C3A4, dark: 0xF0C3A4), Color(light: 0xDDA585, dark: 0xDDA585)],
                                         center: .center, startRadius: 0, endRadius: faceW * 0.7))
                    .frame(width: faceW, height: faceH)
                    .position(x: cx, y: cy)
                // Hair top
                Capsule()
                    .fill(Color(light: 0x3B2A21, dark: 0x3B2A21))
                    .frame(width: faceW * 0.98, height: faceH * 0.26)
                    .position(x: cx, y: cy - faceH * 0.42)
                // Brows
                ForEach([-1.0, 1.0], id: \.self) { side in
                    Capsule()
                        .fill(Color(light: 0x4A3328, dark: 0x4A3328))
                        .frame(width: faceW * 0.2, height: faceH * 0.025)
                        .rotationEffect(.degrees(side * 5))
                        .position(x: cx + side * faceW * 0.2, y: cy - faceH * 0.12)
                    // Eyes
                    Ellipse()
                        .fill(Color.white)
                        .frame(width: faceW * 0.16, height: faceH * 0.06)
                        .overlay(Circle().fill(Color(light: 0x5A3E2B, dark: 0x5A3E2B)).frame(width: faceH * 0.05))
                        .position(x: cx + side * faceW * 0.2, y: cy - faceH * 0.04)
                    // Under-eye softness
                    Ellipse()
                        .fill(Color(light: 0xC98E70, dark: 0xC98E70).opacity(0.25 + 0.3 * puffiness))
                        .frame(width: faceW * 0.17, height: faceH * (0.03 + 0.02 * puffiness))
                        .position(x: cx + side * faceW * 0.2, y: cy + faceH * 0.02)
                }
                // Nose
                Capsule()
                    .fill(Color(light: 0xCF9878, dark: 0xCF9878).opacity(0.6))
                    .frame(width: faceW * 0.07, height: faceH * 0.16)
                    .position(x: cx, y: cy + faceH * 0.08)
                // Mouth: a gentle, relaxed curve
                Path { path in
                    path.move(to: CGPoint(x: cx - faceW * 0.12, y: cy + faceH * 0.25))
                    path.addQuadCurve(to: CGPoint(x: cx + faceW * 0.12, y: cy + faceH * 0.25),
                                      control: CGPoint(x: cx, y: cy + faceH * 0.29))
                }
                .stroke(Color(light: 0xB86B5E, dark: 0xB86B5E), style: StrokeStyle(lineWidth: faceH * 0.025, lineCap: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

public enum SampleFaceRenderer {
    /// Renders the illustration to JPEG data, used as the simulated camera capture.
    @MainActor
    public static func jpeg(puffiness: Double, size: CGSize = CGSize(width: 900, height: 1200)) -> Data? {
        let renderer = ImageRenderer(content: SampleFaceIllustration(puffiness: puffiness)
            .frame(width: size.width / 3, height: size.height / 3))
        renderer.scale = 3
        guard let cgImage = renderer.cgImage else { return nil }
        #if canImport(UIKit)
        return PlatformImage(cgImage: cgImage).jpegData(compressionQuality: 0.9)
        #else
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        #endif
    }
}

#if canImport(AppKit) && !canImport(UIKit)
import AppKit
#endif
