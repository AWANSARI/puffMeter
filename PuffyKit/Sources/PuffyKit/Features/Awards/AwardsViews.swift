import SwiftUI

public struct AwardsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var filter: AwardCategory?

    public init() {}

    public var body: some View {
        let context = model.awardContext
        let awards = visibleAwards
        ScreenScaffold("Awards", subtitle: "Small wins. Lasting routines.") {
            if let (definition, earned) = model.latestEarnedAward {
                justEarned(definition, earned)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip("All awards", isSelected: filter == nil) { withAnimation(.snappy) { filter = nil } }
                    ForEach([AwardCategory.streaks, .habits, .challenges]) { category in
                        FilterChip(category.title, isSelected: filter == category) {
                            withAnimation(.snappy) { filter = category }
                        }
                    }
                }
            }
            .scrollClipDisabled()

            SectionHeader("Your collection", large: true)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(awards) { award in
                    Button {
                        router.awardsPath.append(.awardDetail(award.id))
                    } label: {
                        AwardTile(award: award, earned: model.earned(award),
                                  progress: AwardEngine.progress(of: award, in: context))
                    }
                    .buttonStyle(.plain)
                }
            }
            Disclaimer("Earned through consistency, not a perfect score.", alignment: .center)
        }
    }

    /// Earned first (newest first), then locked by closeness to completion.
    private var visibleAwards: [AwardDefinition] {
        let context = model.awardContext
        let currentMonth = model.today.monthKey
        let all = model.awardDefinitions.filter { award in
            guard filter == nil || award.category == filter else { return false }
            // Only show this month's challenge badges unless already earned.
            if case .challenge(let id) = award.metric,
               let challenge = model.challengeDefinitions.first(where: { $0.id == id }),
               challenge.month != currentMonth, model.earned(award) == nil {
                return false
            }
            return true
        }
        return all.sorted { a, b in
            let ea = model.earned(a), eb = model.earned(b)
            switch (ea, eb) {
            case let (x?, y?): return x.earnedAt < y.earnedAt
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil):
                return AwardEngine.progress(of: a, in: context).fraction > AwardEngine.progress(of: b, in: context).fraction
            }
        }
    }

    private func justEarned(_ award: AwardDefinition, _ earned: EarnedAward) -> some View {
        Card {
            HStack(spacing: 16) {
                AwardBadgeView(style: award.style, locked: false, size: 92)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Just earned").eyebrowStyle()
                    Text(award.title).font(.title2.bold())
                    Text(award.id.hasPrefix("streak") ? "You showed up every morning. That's worth celebrating." : award.celebration)
                        .font(.body).foregroundStyle(Color.pmLabelSecondary).wrapping()
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct AwardTile: View {
    var award: AwardDefinition
    var earned: EarnedAward?
    var progress: AwardProgress
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 10) {
            AwardBadgeView(style: award.style, locked: earned == nil, size: 84)
                .frame(height: 96)
            Text(award.title).font(.headline).foregroundStyle(Color.pmLabel).multilineTextAlignment(.center)
            Text(subtitle).font(.footnote).foregroundStyle(Color.pmLabelSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 192)
        .padding(.horizontal, 8)
        .background(Color.pmCard, in: RoundedRectangle(cornerRadius: Spacing.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityValue(earned == nil ? "Locked" : "Earned")
    }

    private var subtitle: String {
        if let earned {
            if DayKey(earned.earnedAt, calendar: model.calendar) == model.today { return "Earned today" }
            return earned.earnedAt.formatted(.dateTime.month(.abbreviated).day().year())
        }
        if progress.current == 0 || award.metric == .perfectWeekRun {
            return award.requirement
        }
        return "\(progress.current) / \(progress.target) \(award.progressUnit)"
    }
}

public struct AwardDetailView: View {
    var awardID: String
    @Environment(AppModel.self) private var model
    @State private var drag: CGSize = .zero

    public init(awardID: String) { self.awardID = awardID }

    public var body: some View {
        if let award = model.awardDefinitions.first(where: { $0.id == awardID }) {
            let earned = model.earned(award)
            let progress = AwardEngine.progress(of: award, in: model.awardContext)
            ScrollView {
                VStack(spacing: 16) {
                    AwardBadgeView(style: award.style, locked: earned == nil, size: 200)
                        .rotation3DEffect(.degrees(Double(drag.width) / 3), axis: (x: 0, y: 1, z: 0))
                        .rotation3DEffect(.degrees(Double(-drag.height) / 6), axis: (x: 1, y: 0, z: 0))
                        .gesture(DragGesture()
                            .onChanged { drag = $0.translation }
                            .onEnded { _ in withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) { drag = .zero } })
                        .padding(.top, 24)
                    Text(award.title).font(.largeTitle.bold())
                    if let earned {
                        Text("Earned \(earned.earnedAt.formatted(date: .long, time: .omitted))")
                            .font(.subheadline).foregroundStyle(Color.pmLabelSecondary)
                        Text(award.celebration).font(.body).multilineTextAlignment(.center).wrapping(.center)
                    } else {
                        Text(award.requirement).font(.body).foregroundStyle(Color.pmLabelSecondary).wrapping(.center)
                        if award.target > 1 {
                            VStack(spacing: 6) {
                                ProgressBar(value: progress.fraction, tint: .pmAccent)
                                Text("\(progress.current) / \(progress.target) \(award.progressUnit)")
                                    .font(.footnote).foregroundStyle(Color.pmLabelSecondary)
                            }
                            .padding(.horizontal, 40)
                        }
                    }
                    if earned != nil {
                        ShareLink(item: "I earned the \(award.title) award in PuffyMeter.") {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.pmSecondary)
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal, Spacing.margin)
            }
            .background(Color.pmBackground.ignoresSafeArea())
            .navigationTitle("")
            .pmInlineTitleDisplay()
        }
    }
}

/// "NEW AWARD" sheet; queued awards show one after another.
public struct AwardUnlockSheet: View {
    var award: AwardDefinition
    var onDone: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flipped = false
    @State private var shine = false

    public init(award: AwardDefinition, onDone: @escaping () -> Void) {
        self.award = award
        self.onDone = onDone
    }

    public var body: some View {
        VStack(spacing: 14) {
            Text("New award").eyebrowStyle().padding(.top, 28)
            AwardBadgeView(style: award.style, locked: false, size: 128)
                .overlay {
                    LinearGradient(colors: [.clear, .white.opacity(0.6), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 40)
                        .offset(x: shine ? 90 : -90)
                        .blendMode(.screen)
                        .mask(AwardBadgeView(style: award.style, locked: false, size: 128))
                }
                .rotation3DEffect(.degrees(flipped ? 0 : 180), axis: (x: 0, y: 1, z: 0))
                .opacity(flipped ? 1 : 0)
            Text(award.tagline).font(.title.bold()).multilineTextAlignment(.center).wrapping(.center)
            Text(award.celebration).font(.body).foregroundStyle(Color.pmLabelSecondary).wrapping(.center)
            if let earned = model.earned(award) {
                Text("\(award.title) · \(earned.earnedAt.formatted(date: .long, time: .omitted))")
                    .font(.footnote).foregroundStyle(Color.pmLabelSecondary)
            }
            Spacer(minLength: 8)
            Button("Keep it going", action: onDone).buttonStyle(.pmPrimary)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .background(Color.pmCard.ignoresSafeArea())
        .sensoryFeedback(.success, trigger: flipped)
        .onAppear {
            if reduceMotion {
                flipped = true
            } else {
                withAnimation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.15)) { flipped = true }
                withAnimation(.easeInOut(duration: 1.1).delay(0.8)) { shine = true }
            }
        }
    }
}

/// Full-screen celebration when all three rings close for the first time in a day.
public struct AllRingsClosedView: View {
    var onDone: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress = RingProgress.zero
    @State private var celebrate = false

    public init(onDone: @escaping () -> Void) { self.onDone = onDone }

    public var body: some View {
        let target = model.todayStats.rings
        VStack(spacing: 20) {
            Spacer(minLength: 12)
            Text(model.today.startDate(calendar: model.calendar).formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .eyebrowStyle(.pmScan)
            ActivityRings(progress, size: .hero, animateOnAppear: false)
                .overlay { if celebrate && !reduceMotion { ConfettiView() } }
            HeroHeadline("All rings.\nAll you.", alignment: .center)
            Text("You reached your De-Puff goal, scanned, and checked in with all four habits.")
                .font(.body).foregroundStyle(Color.pmLabelSecondary).wrapping(.center)
            Card {
                HStack(spacing: 14) {
                    Image(systemName: "flame").font(.largeTitle).foregroundStyle(Color.pmAccent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(model.streak) days of showing up").font(.headline)
                        Text("A little consistency goes a long way.").font(.footnote).foregroundStyle(Color.pmLabelSecondary)
                    }
                }
            }
            Spacer(minLength: 8)
            Button("Back to Summary", action: onDone).buttonStyle(.pmPrimary)
            ShareLink(item: ShareCardRenderer.render(stats: model.todayStats, streak: model.streak, calendar: model.calendar),
                      preview: SharePreview("PuffyMeter rings", image: ShareCardRenderer.render(stats: model.todayStats,
                                                                                             streak: model.streak,
                                                                                             calendar: model.calendar))) {
                Text("Share")
            }
            .buttonStyle(.pmSecondary)
        }
        .padding(.horizontal, Spacing.margin)
        .padding(.bottom, 12)
        .background(Color.pmBackground.ignoresSafeArea())
        .sensoryFeedback(.success, trigger: celebrate)
        .task {
            if reduceMotion {
                progress = target
                celebrate = true
                return
            }
            for step in 0..<3 {
                try? await Task.sleep(for: .milliseconds(step == 0 ? 250 : 450))
                withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                    switch step {
                    case 0: progress.dePuff = target.dePuff
                    case 1: progress.scan = target.scan
                    default: progress.habits = target.habits
                    }
                }
            }
            try? await Task.sleep(for: .milliseconds(450))
            celebrate = true
        }
    }
}

/// Lightweight Canvas particle burst.
struct ConfettiView: View {
    @State private var start = Date()
    private let pieces: [(x: Double, speed: Double, spin: Double, color: Color, size: Double)] = (0..<70).map { i in
        let colors: [Color] = [.pmRingDePuff, .pmRingScan, .pmRingHabits, .white]
        let seed = Double(i)
        return (x: (sin(seed * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1),
                speed: 180 + abs(sin(seed * 3.3)) * 260,
                spin: seed * 0.7,
                color: colors[i % colors.count],
                size: 5 + abs(cos(seed)) * 6)
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            Canvas { context, size in
                for piece in pieces {
                    let y = -20 + piece.speed * t
                    guard y < size.height + 40 else { continue }
                    let x = size.width / 2 + piece.x * size.width * 0.9 + sin(t * 3 + piece.spin) * 18
                    var copy = context
                    copy.translateBy(x: x, y: y)
                    copy.rotate(by: .radians(t * 4 + piece.spin))
                    copy.fill(Path(CGRect(x: -piece.size / 2, y: -piece.size / 4, width: piece.size, height: piece.size / 2)),
                              with: .color(piece.color))
                }
            }
        }
        .frame(width: 420, height: 700)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
