import Foundation

public enum AwardCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case streaks, habits, challenges, milestones
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .streaks: "Streaks"
        case .habits: "Habits"
        case .challenges: "Challenges"
        case .milestones: "Milestones"
        }
    }
}

/// Visual recipe for the 3D-looking badge drawn by `AwardBadgeView`.
public struct BadgeStyle: Hashable, Sendable {
    public enum Shape: String, Sendable { case coin, hexagon, shield, star }
    public enum Tint: String, Sendable { case pink, lime, cyan, silver, gold, indigo }

    public var shape: Shape
    public var tint: Tint
    /// SF Symbol drawn in the center, or nil when `label` is used.
    public var symbol: String?
    public var label: String?

    public init(shape: Shape, tint: Tint, symbol: String? = nil, label: String? = nil) {
        self.shape = shape
        self.tint = tint
        self.symbol = symbol
        self.label = label
    }
}

public struct AwardDefinition: Hashable, Sendable, Identifiable {
    public enum Metric: Hashable, Sendable {
        case totalScans
        case longestStreak
        case habitDays(HabitKind?)
        case restedDays(minHours: Double)
        case perfectWeekRun
        case personalBest(minScans: Int)
        case challenge(id: String)
    }

    public var id: String
    public var title: String
    public var category: AwardCategory
    public var requirement: String
    public var celebration: String
    public var tagline: String
    public var metric: Metric
    public var target: Int
    public var progressUnit: String
    public var style: BadgeStyle
}

public struct AwardProgress: Hashable, Sendable {
    public var current: Int
    public var target: Int
    public var fraction: Double { min(1, Double(current) / Double(max(target, 1))) }
}

public enum AwardCatalog {
    public static let standard: [AwardDefinition] = [
        AwardDefinition(id: "first-scan", title: "First scan", category: .milestones,
                        requirement: "Take your first scan", celebration: "Your first scan is in. Every routine starts somewhere.",
                        tagline: "Day one.", metric: .totalScans, target: 1, progressUnit: "scan",
                        style: BadgeStyle(shape: .hexagon, tint: .lime, symbol: "camera.fill")),
        streak(3, tint: .silver, tagline: "Three in a row."),
        streak(7, tint: .pink, tagline: "A week of showing up."),
        streak(30, tint: .gold, tagline: "A month of mornings."),
        streak(100, tint: .indigo, tagline: "One hundred mornings."),
        streak(365, tint: .gold, tagline: "A whole year."),
        scans(10, tint: .silver),
        scans(30, tint: .lime),
        scans(100, tint: .gold),
        AwardDefinition(id: "perfect-week", title: "Perfect week", category: .streaks,
                        requirement: "Close all rings for 7 days", celebration: "You closed all three rings seven days in a row.",
                        tagline: "Seven for seven.", metric: .perfectWeekRun, target: 7, progressUnit: "days",
                        style: BadgeStyle(shape: .coin, tint: .silver, symbol: "circle.circle")),
        AwardDefinition(id: "habit-starter", title: "Habit starter", category: .habits,
                        requirement: "Log your first habit", celebration: "You logged your first habit. Small check-ins add up.",
                        tagline: "It starts here.", metric: .habitDays(nil), target: 1, progressUnit: "day",
                        style: BadgeStyle(shape: .coin, tint: .cyan, symbol: "drop.fill")),
        AwardDefinition(id: "hydration-hero", title: "Hydration hero", category: .habits,
                        requirement: "Log water on 30 days", celebration: "Thirty days of water check-ins.",
                        tagline: "Well watered.", metric: .habitDays(.water), target: 30, progressUnit: "days",
                        style: BadgeStyle(shape: .shield, tint: .cyan, symbol: "drop.fill")),
        AwardDefinition(id: "rested", title: "Rested", category: .habits,
                        requirement: "Log 7+ hours of sleep on 14 days", celebration: "Fourteen well-rested nights logged.",
                        tagline: "Rest shows.", metric: .restedDays(minHours: 7), target: 14, progressUnit: "nights",
                        style: BadgeStyle(shape: .coin, tint: .indigo, symbol: "moon.fill")),
        AwardDefinition(id: "personal-best", title: "Personal best", category: .milestones,
                        requirement: "Reach your lowest score after 7+ scans", celebration: "Your lowest score yet.",
                        tagline: "New low, in the best way.", metric: .personalBest(minScans: 8), target: 1, progressUnit: "",
                        style: BadgeStyle(shape: .star, tint: .pink, symbol: "sparkles")),
    ]

    private static func streak(_ days: Int, tint: BadgeStyle.Tint, tagline: String) -> AwardDefinition {
        AwardDefinition(id: "streak-\(days)", title: "\(days)-day streak", category: .streaks,
                        requirement: "Scan \(days) days in a row",
                        celebration: "You scanned for \(days) days in a row. Here's to the routine you're building.",
                        tagline: tagline, metric: .longestStreak, target: days, progressUnit: "days",
                        style: BadgeStyle(shape: .coin, tint: tint, symbol: "flame.fill"))
    }

    private static func scans(_ count: Int, tint: BadgeStyle.Tint) -> AwardDefinition {
        AwardDefinition(id: "scans-\(count)", title: "\(count) scans", category: .milestones,
                        requirement: "Complete \(count) scans", celebration: "\(count) scans and counting.",
                        tagline: "Consistency, counted.", metric: .totalScans, target: count, progressUnit: "scans",
                        style: BadgeStyle(shape: .shield, tint: tint, label: "\(count)"))
    }

    /// Challenge rewards are generated from challenge definitions.
    public static func challengeAward(for challenge: ChallengeDefinition, calendar: Calendar = .current) -> AwardDefinition? {
        guard let awardID = challenge.rewardAwardID else { return nil }
        let monthName = challenge.month.firstDay.startDate(calendar: calendar).formatted(.dateTime.month(.wide))
        let style: BadgeStyle
        let title: String
        switch challenge.kind {
        case .scanDays:
            title = "\(monthName) star"
            style = BadgeStyle(shape: .star, tint: .silver, symbol: nil)
        case .habitDays:
            title = "\(monthName) \(challenge.habit == .sleep ? "rest" : "water")"
            style = BadgeStyle(shape: .coin, tint: challenge.habit == .sleep ? .indigo : .cyan,
                               symbol: challenge.habit == .sleep ? "moon.fill" : "drop.fill")
        case .allRingsDays:
            title = "\(monthName) rings"
            style = BadgeStyle(shape: .coin, tint: .lime, symbol: "circle.circle")
        }
        let unit = challenge.kind == .scanDays ? "mornings" : "days"
        return AwardDefinition(id: awardID, title: title, category: .challenges,
                               requirement: challenge.description,
                               celebration: "You completed \(challenge.title) for \(monthName).",
                               tagline: "Challenge complete.", metric: .challenge(id: challenge.id),
                               target: challenge.target, progressUnit: unit, style: style)
    }

    public static func all(challenges: [ChallengeDefinition]) -> [AwardDefinition] {
        standard + challenges.compactMap { challengeAward(for: $0) }
    }
}

public enum AwardEngine {
    public struct Context: Sendable {
        public var history: History
        public var challenges: [ChallengeDefinition]
        public var challengeRecords: [ChallengeProgress]
        public var today: DayKey

        public init(history: History, challenges: [ChallengeDefinition],
                    challengeRecords: [ChallengeProgress], today: DayKey) {
            self.history = history
            self.challenges = challenges
            self.challengeRecords = challengeRecords
            self.today = today
        }
    }

    public static func progress(of award: AwardDefinition, in context: Context) -> AwardProgress {
        let history = context.history
        let current: Int
        switch award.metric {
        case .totalScans:
            current = history.scanDays.count
        case .longestStreak:
            current = StreakCalculator.longest(scanDays: history.scanDays, calendar: history.calendar)
        case .habitDays(let habit):
            current = history.habits.values.filter { log in
                habit.map(log.isLogged) ?? (log.checkInCount > 0)
            }.count
        case .restedDays(let minHours):
            current = history.habits.values.filter { ($0.sleepHours ?? 0) >= minHours }.count
        case .perfectWeekRun:
            let closedDays = Set(history.scanDays.filter { history.stats(for: $0).rings.allClosed })
            current = StreakCalculator.longestRun(of: closedDays, calendar: history.calendar)
        case .personalBest(let minScans):
            let scored = history.scans.filter { !$0.isBaseline }
            guard scored.count >= minScans, let latest = scored.last else { current = 0; break }
            let previousBest = scored.dropLast().map(\.score).min() ?? Int.max
            current = latest.score < previousBest ? 1 : 0
        case .challenge(let id):
            guard let challenge = context.challenges.first(where: { $0.id == id }) else { current = 0; break }
            let status = ChallengeEngine.status(of: challenge, history: history,
                                                progressRecords: context.challengeRecords, today: context.today,
                                                calendar: history.calendar)
            current = status.joined ? status.progress : 0
        }
        return AwardProgress(current: current, target: award.target)
    }

    /// Returns newly earned awards. Idempotent: awards already in `earned` are never returned again.
    public static func evaluate(_ awards: [AwardDefinition], context: Context,
                                earned: [EarnedAward], now: Date = .now) -> [EarnedAward] {
        let earnedIDs = Set(earned.map(\.awardID))
        return awards.compactMap { award in
            guard !earnedIDs.contains(award.id) else { return nil }
            let progress = progress(of: award, in: context)
            return progress.current >= award.target ? EarnedAward(awardID: award.id, earnedAt: now) : nil
        }
    }
}
