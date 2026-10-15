import SwiftUI

// MARK: - Card

public struct Card<Content: View>: View {
    var padding: CGFloat
    var content: Content

    public init(padding: CGFloat = Spacing.cardPadding, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(Color.pmCard, in: RoundedRectangle(cornerRadius: Spacing.cardRadius, style: .continuous))
    }
}

// MARK: - Buttons

public struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: Spacing.buttonHeight)
            .background(Color.pmAccent, in: RoundedRectangle(cornerRadius: Spacing.buttonRadius, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.35)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

public struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color
    @Environment(\.isEnabled) private var isEnabled

    public init(tint: Color = .pmLink) { self.tint = tint }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: Spacing.buttonHeight)
            .background(Color.pmSecondaryFill, in: RoundedRectangle(cornerRadius: Spacing.buttonRadius, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.35)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

public extension ButtonStyle where Self == PrimaryButtonStyle {
    static var pmPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

public extension ButtonStyle where Self == SecondaryButtonStyle {
    static var pmSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
    static func pmSecondary(tint: Color) -> SecondaryButtonStyle { SecondaryButtonStyle(tint: tint) }
}

// MARK: - Pill & chips

public struct Pill: View {
    var text: String
    var color: Color

    public init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        Text(text)
            .font(.footnote.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.pmCardElevated, in: Capsule())
    }
}

public struct FilterChip: View {
    var title: String
    var isSelected: Bool
    var action: () -> Void

    public init(_ title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : Color.pmAccent)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? Color.pmAccent : Color.pmAccentFill, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Section header

public struct SectionHeader: View {
    var title: String
    var large: Bool
    var actionTitle: String?
    var action: (() -> Void)?

    public init(_ title: String, large: Bool = false, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.large = large
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(large ? .title2.bold() : .subheadline.weight(.semibold))
                .foregroundStyle(large ? Color.pmLabel : Color.pmLabelSecondary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 2) {
                        Text(actionTitle)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                    }
                    .font(.body)
                    .foregroundStyle(Color.pmAccent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, large ? 8 : 4)
    }
}

/// Subtitle shown under a large navigation title ("Thursday, October 8").
public struct ScreenSubtitle: View {
    var text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Color.pmLabelSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, -8)
    }
}

/// Small print at the bottom of screens ("Cosmetic wellness only…").
public struct Disclaimer: View {
    var text: String
    var alignment: TextAlignment
    public init(_ text: String, alignment: TextAlignment = .leading) {
        self.text = text
        self.alignment = alignment
    }
    public var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Color.pmLabelSecondary)
            .wrapping(alignment)
            .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
    }
}

// MARK: - Metric delta

/// "↓ 8 vs yesterday": down (improvement) is green, up is pink.
public struct MetricDelta: View {
    var value: Int?
    var suffix: String
    var font: Font

    public init(_ value: Int?, suffix: String = "vs yesterday", font: Font = .subheadline) {
        self.value = value
        self.suffix = suffix
        self.font = font
    }

    public var body: some View {
        Group {
            if let value {
                if value == 0 {
                    Text("No change \(suffix)").foregroundStyle(Color.pmLabelSecondary)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: value < 0 ? "arrow.down" : "arrow.up")
                        Text("\(abs(value)) \(suffix)")
                    }
                    .foregroundStyle(value < 0 ? Color.pmScan : Color.pmAccent)
                }
            }
        }
        .font(font)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let value else { return "" }
        if value == 0 { return "No change \(suffix)" }
        return "\(value < 0 ? "Down" : "Up") \(abs(value)) \(suffix)"
    }
}

// MARK: - Insight card

public struct InsightCard: View {
    var symbol: String?
    var title: String
    var message: String
    var footnote: String?

    public init(symbol: String?, title: String, message: String, footnote: String?) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.footnote = footnote
    }

    public var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.title3)
                            .foregroundStyle(Color.pmHabits)
                    }
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.pmLabel)
                }
                Text(message).font(.subheadline).foregroundStyle(Color.pmLabelSecondary).wrapping()
                if let footnote {
                    Text(footnote).font(.footnote).foregroundStyle(Color.pmLabelTertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Checklist

public struct ChecklistItem: View {
    var title: String
    var passed: Bool

    public init(_ title: String, passed: Bool) {
        self.title = title
        self.passed = passed
    }

    public var body: some View {
        VStack(spacing: 6) {
            Image(systemName: passed ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(passed ? Color.pmScan : Color.pmLabelTertiary)
                .contentTransition(.symbolEffect(.replace))
            Text(title)
                .font(.footnote)
                .foregroundStyle(passed ? Color.pmLabel : Color.pmLabelSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.2), value: passed)
        .accessibilityElement(children: .combine)
        .accessibilityValue(passed ? "passed" : "not yet")
    }
}

// MARK: - Step list (Analyzing)

public struct StepList: View {
    public enum StepState: Sendable { case pending, active, done }
    public struct Step: Identifiable, Sendable {
        public var id: String { title }
        public var title: String
        public var state: StepState
        public init(title: String, state: StepState) {
            self.title = title
            self.state = state
        }
    }

    var steps: [Step]

    public init(steps: [Step]) { self.steps = steps }

    public var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(steps) { step in
                    HStack(spacing: 10) {
                        Group {
                            switch step.state {
                            case .done:
                                Image(systemName: "checkmark.circle").foregroundStyle(Color.pmScan)
                            case .active:
                                ProgressView().controlSize(.small).tint(Color.pmHabits)
                            case .pending:
                                Image(systemName: "circle").foregroundStyle(Color.pmLabelTertiary)
                            }
                        }
                        .frame(width: 22)
                        Text(step.state == .active ? step.title + "…" : step.title)
                            .font(.subheadline)
                            .foregroundStyle(color(for: step.state))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(step.state == .done ? "done" : step.state == .active ? "in progress" : "pending")
                }
            }
        }
        .animation(.easeInOut, value: steps.map(\.state.hashValue))
    }

    private func color(for state: StepState) -> Color {
        switch state {
        case .done: .pmScan
        case .active: .pmHabits
        case .pending: .pmLabelSecondary
        }
    }
}

// MARK: - Progress bar

public struct ProgressBar: View {
    var value: Double
    var tint: Color
    var track: Color

    public init(value: Double, tint: Color, track: Color? = nil) {
        self.value = value
        self.tint = tint
        self.track = track ?? tint.opacity(0.25)
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(tint).frame(width: max(6, proxy.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityValue("\(Int((min(max(value, 0), 1) * 100).rounded())) percent")
    }
}

// MARK: - Flow layout

/// Wraps chips onto new lines (Quick log, tags).
public struct FlowLayout: Layout {
    var spacing: CGFloat

    public init(spacing: CGFloat = 8) { self.spacing = spacing }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowHeight)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Icon chip used in list rows

public struct RowIcon: View {
    var symbol: String
    var color: Color
    public init(_ symbol: String, color: Color = .pmAccent) {
        self.symbol = symbol
        self.color = color
    }
    public var body: some View {
        Image(systemName: symbol)
            .font(.body)
            .foregroundStyle(color)
            .frame(width: 28)
    }
}
