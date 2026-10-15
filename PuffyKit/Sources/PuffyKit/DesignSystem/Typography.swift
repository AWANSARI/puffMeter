import SwiftUI

/// Rounded metric numerals (the Fitness look). Sizes scale with Dynamic Type.
public enum MetricStyle: Sendable {
    /// 56 Heavy: result score, small widget.
    case hero
    /// 34 Bold: Summary score, goal values.
    case large
    /// 28 Bold: zone values.
    case medium
    /// 17 Semibold: ring legend values.
    case small

    var baseSize: CGFloat {
        switch self {
        case .hero: 56
        case .large: 34
        case .medium: 28
        case .small: 17
        }
    }

    var weight: Font.Weight {
        switch self {
        case .hero: .heavy
        case .large, .medium: .bold
        case .small: .semibold
        }
    }

    var textStyle: Font.TextStyle {
        switch self {
        case .hero, .large: .largeTitle
        case .medium: .title
        case .small: .body
        }
    }
}

struct MetricFontModifier: ViewModifier {
    let style: MetricStyle
    @ScaledMetric private var size: CGFloat

    init(style: MetricStyle) {
        self.style = style
        _size = ScaledMetric(wrappedValue: style.baseSize, relativeTo: style.textStyle)
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: style.weight, design: .rounded))
            .monospacedDigit()
    }
}

public extension View {
    /// Applies SF Pro Rounded metric styling with monospaced digits.
    func metricFont(_ style: MetricStyle) -> some View {
        modifier(MetricFontModifier(style: style))
    }

    /// Caps eyebrow text ("MEET PUFFYMETER", "JUST EARNED").
    func eyebrowStyle(_ color: Color = .pmAccent) -> some View {
        self.font(.caption.weight(.semibold))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }

    /// Body text that always wraps instead of running off the card.
    func wrapping(_ alignment: TextAlignment = .leading) -> some View {
        self.fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(alignment)
    }
}

public enum Spacing {
    public static let margin: CGFloat = 16
    public static let cardPadding: CGFloat = 16
    public static let cardGap: CGFloat = 12
    public static let sectionGap: CGFloat = 24
    public static let cardRadius: CGFloat = 16
    public static let photoRadius: CGFloat = 20
    public static let buttonRadius: CGFloat = 12
    public static let buttonHeight: CGFloat = 52
}
