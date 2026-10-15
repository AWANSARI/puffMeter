import SwiftUI

// MARK: - Habit chip

public struct HabitChip: View {
    var kind: HabitKind
    var log: HabitLog?
    var waterGoal: Double
    var action: () -> Void

    public init(kind: HabitKind, log: HabitLog?, waterGoal: Double, action: @escaping () -> Void) {
        self.kind = kind
        self.log = log
        self.waterGoal = waterGoal
        self.action = action
    }

    private var isLogged: Bool { log?.isLogged(kind) ?? false }

    private var label: String {
        switch kind {
        case .water:
            let value = log?.waterLiters.map { Format.liters($0).replacingOccurrences(of: " L", with: "") } ?? "0"
            return "Water · \(value) / \(Format.liters(waterGoal))"
        case .sleep:
            return "Sleep · " + (log?.sleepHours.map(Format.hours) ?? "Log")
        case .salt:
            return "Salt · " + (log?.salt?.title ?? "Log")
        case .alcohol:
            return "Alcohol · " + (log?.alcohol?.title ?? "Log")
        }
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if !isLogged || kind == .water {
                    Text("+")
                }
                Text(label)
                if log?.sources[kind] == .health {
                    Image(systemName: "heart.fill").font(.caption2).accessibilityLabel("From Apple Health")
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.pmAccent.opacity(isLogged ? 1 : 0.75))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 36)
            .background(Color.pmAccentFill.opacity(isLogged ? 1 : 0.6), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Log \(kind.title.lowercased())")
    }
}

// MARK: - Tag chip

public struct TagChip: View {
    var title: String
    var isOn: Bool
    var action: () -> Void

    public init(_ title: String, isOn: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isOn = isOn
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isOn ? Color.pmAccent : Color.pmLabelSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isOn ? Color.pmAccentFill : Color.pmSecondaryFill, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Upload status

public enum UploadCardState: Hashable, Sendable {
    case uploading(progress: Double)
    case saved(fileName: String, path: String)
    case failed(UploadFailure)
    case queued(count: Int)
    case localOnly
}

public struct UploadStatusCard: View {
    var state: UploadCardState
    var onAction: (() -> Void)?

    public init(state: UploadCardState, onAction: (() -> Void)? = nil) {
        self.state = state
        self.onAction = onAction
    }

    public var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: symbol)
                        .font(.title3)
                        .foregroundStyle(tint)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(titleColor)
                        Text(subtitle).font(.footnote).foregroundStyle(Color.pmLabelSecondary).wrapping()
                    }
                    Spacer(minLength: 8)
                    if case .failed(let failure) = state, let onAction {
                        Button(failure.actionTitle, action: onAction)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.pmAccent)
                            .buttonStyle(.plain)
                    }
                }
                switch state {
                case .uploading(let progress):
                    ProgressBar(value: progress, tint: .pmHabits)
                case .saved(let fileName, _):
                    Text("\(fileName) · Synced just now").font(.footnote).foregroundStyle(Color.pmLabelSecondary)
                case .queued(let count):
                    Text("Saved locally · \(Format.plural(count, "item")) waiting to sync")
                        .font(.footnote).foregroundStyle(Color.pmLabelSecondary)
                case .failed, .localOnly:
                    EmptyView()
                }
            }
        }
        .accessibilityElement(children: .contain)
        .animation(.easeInOut(duration: 0.25), value: state)
    }

    private var symbol: String {
        switch state {
        case .uploading: "icloud.and.arrow.up"
        case .saved: "checkmark.icloud"
        case .failed: "exclamationmark.icloud"
        case .queued: "icloud.slash"
        case .localOnly: "iphone"
        }
    }

    private var tint: Color {
        switch state {
        case .uploading: .pmHabits
        case .saved: .pmScan
        case .failed: .pmAccent
        case .queued, .localOnly: .pmLabelSecondary
        }
    }

    private var titleColor: Color {
        switch state {
        case .uploading: .pmHabits
        case .saved: .pmScan
        case .failed: .pmAccent
        case .queued, .localOnly: .pmLabelSecondary
        }
    }

    private var title: String {
        switch state {
        case .uploading: "Uploading to Google Drive"
        case .saved: "Saved to Google Drive"
        case .failed: "Upload failed"
        case .queued: "Offline · Upload queued"
        case .localOnly: "Saved on this iPhone"
        }
    }

    private var subtitle: String {
        switch state {
        case .uploading(let progress): "Daily photo and notes · \(Int((progress * 100).rounded()))%"
        case .saved(_, let path): path
        case .failed(let failure): "Your scan is safe on this iPhone. \(failure.message)"
        case .queued: "Will sync when you're back online."
        case .localOnly: "Connect Google Drive in Profile to back up your scans."
        }
    }
}

// MARK: - Goal stepper card

public struct GoalStepperCard: View {
    var kind: RingKind
    @Binding var value: Int
    var range: ClosedRange<Int>
    var unitTitle: String
    var message: String

    public init(kind: RingKind, value: Binding<Int>, range: ClosedRange<Int>, unitTitle: String, message: String) {
        self.kind = kind
        _value = value
        self.range = range
        self.unitTitle = unitTitle
        self.message = message
    }

    public var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text(kind.title).font(.subheadline.weight(.semibold)).foregroundStyle(kind.color)
                HStack(alignment: .center) {
                    Text("\(value)")
                        .metricFont(.large)
                        .foregroundStyle(kind.color)
                        .contentTransition(.numericText(value: Double(value)))
                    Spacer()
                    stepper
                }
                Text(unitTitle).font(.subheadline.weight(.semibold)).foregroundStyle(Color.pmLabel)
                Text(message).font(.footnote).foregroundStyle(Color.pmLabelSecondary).wrapping()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.title) goal, \(unitTitle)")
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: change(+1)
            case .decrement: change(-1)
            @unknown default: break
            }
        }
    }

    private var stepper: some View {
        HStack(spacing: 0) {
            Button { change(-1) } label: {
                Image(systemName: "minus").frame(width: 48, height: 36)
            }
            .disabled(value <= range.lowerBound)
            Rectangle().fill(Color.pmSeparator).frame(width: 1, height: 20)
            Button { change(+1) } label: {
                Image(systemName: "plus").frame(width: 48, height: 36)
            }
            .disabled(value >= range.upperBound)
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(Color.pmLabel)
        .buttonStyle(.plain)
        .background(Color.pmCardElevated, in: Capsule())
        .sensoryFeedback(.selection, trigger: value)
    }

    private func change(_ delta: Int) {
        withAnimation(.snappy) { value = (value + delta).clamped(to: range) }
    }
}

// MARK: - Challenge card

public struct ChallengeCard: View {
    var status: ChallengeStatus
    var showsHeroIcon: Bool
    var onJoin: (() -> Void)?

    public init(status: ChallengeStatus, showsHeroIcon: Bool = false, onJoin: (() -> Void)? = nil) {
        self.status = status
        self.showsHeroIcon = showsHeroIcon
        self.onJoin = onJoin
    }

    public var body: some View {
        let ring = status.definition.accent.ring
        Card {
            VStack(alignment: .leading, spacing: 10) {
                if showsHeroIcon {
                    Image(systemName: status.definition.symbol)
                        .font(.system(size: 52, weight: .light))
                        .foregroundStyle(ring.color)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .accessibilityHidden(true)
                }
                Text(status.definition.title)
                    .font(showsHeroIcon ? .title2.bold() : .title3.bold())
                    .foregroundStyle(showsHeroIcon ? Color.pmLabel : ring.color)
                Text(status.definition.description)
                    .font(.body).foregroundStyle(Color.pmLabelSecondary).wrapping()
                if status.joined {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(status.progress) / \(status.definition.target)")
                            .metricFont(.large).foregroundStyle(ring.color)
                        if !status.definition.requiresJoin {
                            Text(status.definition.kind == .scanDays ? "days scanned" : "days logged")
                                .font(.footnote).foregroundStyle(Color.pmLabelSecondary)
                        }
                    }
                    ProgressBar(value: status.fraction, tint: ring.color, track: ring.trackColor)
                    if status.definition.requiresJoin {
                        Pill("Joined · Ends \(Format.shortDay(status.definition.month.lastDay))", color: .pmAccent)
                    }
                    Text(status.definition.requiresJoin
                         ? (status.definition.rewardText ?? "")
                         : "\(Format.plural(status.daysLeft, "day")) left · \(status.paceText)")
                        .font(.footnote).foregroundStyle(Color.pmLabelSecondary)
                } else if let onJoin {
                    Button("Join Challenge", action: onJoin)
                        .buttonStyle(.pmPrimary)
                        .padding(.top, 4)
                    if let reward = status.definition.rewardText {
                        Text(reward).font(.footnote).foregroundStyle(Color.pmLabelSecondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Correlation card

public struct CorrelationCard: View {
    var correlation: Correlation

    public init(_ correlation: Correlation) { self.correlation = correlation }

    public var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: correlation.factor.symbol)
                        .font(.title3)
                        .foregroundStyle(iconColor)
                        .frame(width: 28)
                    Text(correlation.factor.title).font(.headline)
                }
                if let deltaText = correlation.deltaText {
                    Text(deltaText).metricFont(.medium).foregroundStyle(deltaColor)
                } else {
                    Text("More data needed").metricFont(.medium).foregroundStyle(Color.pmLabelSecondary)
                }
                Text(correlation.explanation).font(.body).foregroundStyle(Color.pmLabelSecondary).wrapping()
                Text(correlation.footnote).font(.footnote).foregroundStyle(Color.pmLabelTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var deltaColor: Color { (correlation.delta ?? 0) <= 0 ? .pmHabits : .pmAccent }

    private var iconColor: Color {
        guard correlation.hasEnoughData else { return .pmLabelSecondary }
        return correlation.factor == .salt ? .pmAccent : .pmHabits
    }
}

// MARK: - Zone tiles

public struct ZoneTile: View {
    var zone: FaceZone
    var value: Int

    public init(zone: FaceZone, value: Int) {
        self.zone = zone
        self.value = value
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(zone.title).font(.footnote).foregroundStyle(Color.pmLabelSecondary)
            Text("\(value)").metricFont(.medium).foregroundStyle(Color.pmAccent)
                .accessibilityLabel("\(value) points")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.pmCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Before / after comparison

public struct ComparisonSlider<Before: View, After: View>: View {
    var before: Before
    var after: After
    @Binding var position: Double
    @State private var lastHapticStop: Int = 1

    public init(position: Binding<Double>, @ViewBuilder before: () -> Before, @ViewBuilder after: () -> After) {
        _position = position
        self.before = before()
        self.after = after()
    }

    public var body: some View {
        GeometryReader { proxy in
            let x = proxy.size.width * position
            ZStack(alignment: .leading) {
                after
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                before
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .mask(alignment: .leading) { Rectangle().frame(width: x) }
                Rectangle().fill(.white).frame(width: 2).offset(x: x - 1)
                Circle()
                    .fill(.white)
                    .frame(width: 44, height: 44)
                    .overlay(Image(systemName: "arrow.left.and.right").font(.headline).foregroundStyle(.black))
                    .shadow(color: .black.opacity(0.25), radius: 6)
                    .offset(x: x - 22)
            }
            .clipShape(RoundedRectangle(cornerRadius: Spacing.photoRadius, style: .continuous))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                position = (value.location.x / proxy.size.width).clamped(to: 0...1)
                let stop = Int((position * 2).rounded())
                if stop != lastHapticStop { lastHapticStop = stop }
            })
        }
        .aspectRatio(3 / 2, contentMode: .fit)
        .sensoryFeedback(.selection, trigger: lastHapticStop)
        .accessibilityElement()
        .accessibilityLabel("Before and after comparison")
        .accessibilityValue("Showing \(Int(((1 - position) * 100).rounded())) percent today")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: position = max(0, position - 0.1)
            case .decrement: position = min(1, position + 0.1)
            @unknown default: break
            }
        }
    }
}
