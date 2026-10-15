import SwiftUI

public enum RingSize: Sendable {
    case hero, card, compact, mini

    public var diameter: CGFloat {
        switch self {
        case .hero: 240
        case .card: 168
        case .compact: 88
        case .mini: 32
        }
    }

    public var lineWidth: CGFloat {
        switch self {
        case .hero: 28
        case .card: 20
        case .compact: 11
        case .mini: 4.5
        }
    }

    var gap: CGFloat { lineWidth * 0.15 }
}

/// Apple Fitness–style triple rings: De-Puff (outer), Scan (middle), Habits (inner).
public struct ActivityRings: View {
    public var progress: RingProgress
    public var size: RingSize
    public var animateOnAppear: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    public init(_ progress: RingProgress, size: RingSize, animateOnAppear: Bool = true) {
        self.progress = progress
        self.size = size
        self.animateOnAppear = animateOnAppear
    }

    public var body: some View {
        let displayed = shown || !animateOnAppear ? progress : .zero
        ZStack {
            ring(.dePuff, value: displayed.dePuff, index: 0)
            ring(.scan, value: displayed.scan, index: 1)
            ring(.habits, value: displayed.habits, index: 2)
        }
        .frame(width: size.diameter, height: size.diameter)
        .onAppear {
            guard animateOnAppear, !shown else { return }
            if reduceMotion {
                shown = true
            } else {
                withAnimation(.spring(response: 0.9, dampingFraction: 0.8).delay(0.1)) { shown = true }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Activity rings")
        .accessibilityValue(accessibilityText)
    }

    private func ring(_ kind: RingKind, value: Double, index: Int) -> some View {
        let inset = CGFloat(index) * (size.lineWidth + size.gap)
        return SingleRing(kind: kind, progress: value, lineWidth: size.lineWidth)
            .padding(inset + size.lineWidth / 2)
    }

    private var accessibilityText: String {
        func state(_ v: Double) -> String { v >= 1 ? "closed" : "\(Int((min(v, 1) * 100).rounded())) percent" }
        return "De-Puff \(state(progress.dePuff)). Scan \(state(progress.scan)). Habits \(state(progress.habits))."
    }
}

/// One ring. The frame passed in is the ring's centerline circle.
struct SingleRing: View {
    var kind: RingKind
    var progress: Double
    var lineWidth: CGFloat

    var body: some View {
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        ZStack {
            Circle().stroke(kind.trackColor, lineWidth: lineWidth)

            RingArc(progress: min(progress, 1))
                .stroke(kind.ringColor, style: style)

            if progress > 1 {
                // Second lap in the end color plus a shadowed cap so the overlap reads, like Fitness.
                RingArc(progress: progress - 1)
                    .stroke(kind.ringColor, style: style)
                RingCap(progress: progress, lineWidth: lineWidth)
                    .fill(kind.ringColor)
                    .shadow(color: .black.opacity(0.45), radius: lineWidth * 0.18, x: 0, y: 0)
            } else if progress >= 1 {
                // Closed ring: a hairline marks the start like the Fitness rings.
                Rectangle()
                    .fill(.black.opacity(0.35))
                    .frame(width: 1.5, height: lineWidth)
                    .offset(y: -0.5)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .offset(y: -lineWidth / 2)
            } else if progress > 0 {
                RingCap(progress: progress, lineWidth: lineWidth)
                    .fill(kind.ringColor)
            }
        }
    }
}

/// Arc starting at 12 o'clock, clockwise; animatable so the ring fills smoothly.
struct RingArc: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard progress > 0 else { return path }
        let radius = min(rect.width, rect.height) / 2
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: radius,
                    startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * min(progress, 1)), clockwise: false)
        return path
    }
}

/// The rounded end cap drawn on top so it can carry the overlap shadow.
struct RingCap: Shape {
    var progress: Double
    var lineWidth: CGFloat

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        let angle = Angle.degrees(-90 + 360 * progress).radians
        let center = CGPoint(x: rect.midX + radius * cos(angle), y: rect.midY + radius * sin(angle))
        return Path(ellipseIn: CGRect(x: center.x - lineWidth / 2, y: center.y - lineWidth / 2,
                                      width: lineWidth, height: lineWidth))
    }
}

/// Legend beside the rings: "De-Puff / 32 / ≤35".
public struct RingLegend: View {
    public var stats: DayStats

    public init(stats: DayStats) { self.stats = stats }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row(.dePuff, value: "\(stats.score.map(String.init) ?? "--") / ≤\(stats.goals.dePuffMax)")
            row(.scan, value: "\(stats.scanCount) / \(stats.goals.scansPerDay)")
            row(.habits, value: "\(stats.habitCount) / \(stats.goals.habitsPerDay)")
        }
    }

    private func row(_ kind: RingKind, value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(kind.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(kind.color)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.pmLabel)
        }
        .accessibilityElement(children: .combine)
    }
}
