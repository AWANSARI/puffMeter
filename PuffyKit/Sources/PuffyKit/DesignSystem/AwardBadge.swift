import SwiftUI

/// A 3D-looking medal built from layered gradients: metallic rim, colored face,
/// center symbol and a specular highlight. Locked badges render dark and desaturated.
public struct AwardBadgeView: View {
    var style: BadgeStyle
    var locked: Bool
    var size: CGFloat

    public init(style: BadgeStyle, locked: Bool, size: CGFloat) {
        self.style = style
        self.locked = locked
        self.size = size
    }

    public var body: some View {
        ZStack {
            outline
                .fill(rimGradient)
                .shadow(color: .black.opacity(0.35), radius: size * 0.06, y: size * 0.04)
            outline
                .fill(faceGradient)
                .padding(size * 0.08)
            outline
                .stroke(.white.opacity(0.35), lineWidth: size * 0.012)
                .padding(size * 0.08)
            center
                .foregroundStyle(symbolGradient)
                .shadow(color: .black.opacity(0.25), radius: size * 0.02, y: size * 0.015)
            // Specular highlight sweeping across the top-left.
            outline
                .fill(LinearGradient(colors: [.white.opacity(0.45), .clear], startPoint: .topLeading, endPoint: .center))
                .padding(size * 0.08)
                .blendMode(.screen)
        }
        .frame(width: size, height: size * (style.shape == .shield ? 1.12 : 1))
        .saturation(locked ? 0.05 : 1)
        .brightness(locked ? -0.28 : 0)
        .opacity(locked ? 0.75 : 1)
        .accessibilityHidden(true)
    }

    private var outline: AnyShape {
        switch style.shape {
        case .coin: AnyShape(Circle())
        case .hexagon: AnyShape(PolygonShape(sides: 6, rotation: .degrees(30), cornerRadius: size * 0.08))
        case .shield: AnyShape(ShieldShape())
        case .star: AnyShape(StarShape(points: 5, innerRatio: 0.5))
        }
    }

    @ViewBuilder private var center: some View {
        if let label = style.label {
            Text(label)
                .font(.system(size: size * 0.3, weight: .heavy, design: .rounded))
        } else if let symbol = style.symbol {
            Image(systemName: symbol)
                .font(.system(size: size * (style.shape == .star ? 0.22 : 0.36), weight: .bold))
        }
    }

    private var tint: (Color, Color) {
        switch style.tint {
        case .pink: (Color(light: 0xFF8FB0, dark: 0xFF8FB0), Color(light: 0xE0104A, dark: 0xE0104A))
        case .lime: (Color(light: 0xD8FF6E, dark: 0xD8FF6E), Color(light: 0x7FBF1A, dark: 0x7FBF1A))
        case .cyan: (Color(light: 0x8FF8FF, dark: 0x8FF8FF), Color(light: 0x0FB5C9, dark: 0x0FB5C9))
        case .silver: (Color(light: 0xF2F2F5, dark: 0xF2F2F5), Color(light: 0x9A9AA3, dark: 0x9A9AA3))
        case .gold: (Color(light: 0xFFE59A, dark: 0xFFE59A), Color(light: 0xC8901C, dark: 0xC8901C))
        case .indigo: (Color(light: 0xB3B1FF, dark: 0xB3B1FF), Color(light: 0x4B48D8, dark: 0x4B48D8))
        }
    }

    private var rimGradient: AngularGradient {
        AngularGradient(colors: [.white, Color(white: 0.62), Color(white: 0.92), Color(white: 0.5), .white],
                        center: .center)
    }

    private var faceGradient: RadialGradient {
        RadialGradient(colors: [tint.0, tint.1], center: UnitPoint(x: 0.35, y: 0.3),
                       startRadius: 0, endRadius: size * 0.6)
    }

    private var symbolGradient: LinearGradient {
        LinearGradient(colors: [.white, tint.0.opacity(0.9)], startPoint: .top, endPoint: .bottom)
    }
}

struct PolygonShape: Shape {
    var sides: Int
    var rotation: Angle
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let points = (0..<sides).map { i -> CGPoint in
            let angle = rotation.radians + Double(i) * 2 * .pi / Double(sides)
            return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }
        var path = Path()
        for i in 0..<sides {
            let current = points[i]
            let next = points[(i + 1) % sides]
            let mid = CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2)
            if i == 0 {
                let previous = points[sides - 1]
                path.move(to: CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2))
            }
            path.addArc(tangent1End: current, tangent2End: mid, radius: cornerRadius)
            path.addLine(to: mid)
        }
        path.closeSubpath()
        return path
    }
}

struct ShieldShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + h * 0.14),
                          control: CGPoint(x: rect.minX + w * 0.8, y: rect.minY + h * 0.02))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + h * 0.5))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY),
                          control: CGPoint(x: rect.maxX, y: rect.minY + h * 0.85))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + h * 0.5),
                          control: CGPoint(x: rect.minX, y: rect.minY + h * 0.85))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + h * 0.14))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY),
                          control: CGPoint(x: rect.minX + w * 0.2, y: rect.minY + h * 0.02))
        path.closeSubpath()
        return path
    }
}

struct StarShape: Shape {
    var points: Int
    var innerRatio: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.04)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * innerRatio
        var path = Path()
        for i in 0..<(points * 2) {
            let radius = i.isMultiple(of: 2) ? outer : inner
            let angle = -Double.pi / 2 + Double(i) * .pi / Double(points)
            let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}
