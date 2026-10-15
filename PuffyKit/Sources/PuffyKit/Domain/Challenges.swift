import Foundation

public struct ChallengeDefinition: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case scanDays, habitDays, allRingsDays
    }

    public enum Accent: String, Codable, Sendable {
        case dePuff, scan, habits
    }

    public var id: String
    public var month: MonthKey
    public var title: String
    public var description: String
    public var kind: Kind
    public var habit: HabitKind?
    public var target: Int
    public var requiresJoin: Bool
    public var rewardAwardID: String?
    public var rewardText: String?
    public var symbol: String
    public var accent: Accent

    public init(id: String, month: MonthKey, title: String, description: String, kind: Kind,
                habit: HabitKind? = nil, target: Int, requiresJoin: Bool, rewardAwardID: String?,
                rewardText: String? = nil, symbol: String, accent: Accent) {
        self.id = id
        self.month = month
        self.title = title
        self.description = description
        self.kind = kind
        self.habit = habit
        self.target = target
        self.requiresJoin = requiresJoin
        self.rewardAwardID = rewardAwardID
        self.rewardText = rewardText
        self.symbol = symbol
        self.accent = accent
    }
}

public struct ChallengeStatus: Hashable, Sendable, Identifiable {
    public var definition: ChallengeDefinition
    public var progress: Int
    public var joined: Bool
    public var paceText: String
    public var daysLeft: Int
    public var id: String { definition.id }

    public var fraction: Double { min(1, Double(progress) / Double(max(definition.target, 1))) }
    public var isComplete: Bool { progress >= definition.target }
}

public enum ChallengeEngine {
    /// Bundled definitions in `Resources/challenges.json`, so new months ship without code changes.
    public static func bundledDefinitions() -> [ChallengeDefinition] {
        guard let url = Bundle.module.url(forResource: "challenges", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([ChallengeDefinition].self, from: data)) ?? []
    }

    public static func definitions(for month: MonthKey, in all: [ChallengeDefinition]) -> [ChallengeDefinition] {
        all.filter { $0.month == month }
    }

    public static func progress(of challenge: ChallengeDefinition, history: History) -> Int {
        let start = challenge.month.firstDay
        let end = challenge.month.lastDay
        return history.stats(from: start, through: end).filter { stats in
            switch challenge.kind {
            case .scanDays: stats.scanCount > 0
            case .habitDays: challenge.habit.map { stats.habits?.isLogged($0) ?? false } ?? false
            case .allRingsDays: stats.rings.allClosed
            }
        }.count
    }

    public static func status(of challenge: ChallengeDefinition, history: History,
                              progressRecords: [ChallengeProgress], today: DayKey,
                              calendar: Calendar = .current) -> ChallengeStatus {
        let progress = progress(of: challenge, history: history)
        let joined = !challenge.requiresJoin || progressRecords.contains { $0.challengeID == challenge.id && $0.joinedAt != nil }
        let daysInMonth = challenge.month.numberOfDays(calendar: calendar)
        let dayOfMonth = challenge.month.contains(today) ? today.day : (challenge.month < today.monthKey ? daysInMonth : 0)
        let daysLeft = max(0, daysInMonth - dayOfMonth)
        return ChallengeStatus(definition: challenge, progress: progress, joined: joined,
                               paceText: paceText(progress: progress, target: challenge.target,
                                                  dayOfMonth: dayOfMonth, daysInMonth: daysInMonth),
                               daysLeft: daysLeft)
    }

    /// "You're on pace" when progress/target ≥ dayOfMonth/daysInMonth.
    public static func paceText(progress: Int, target: Int, dayOfMonth: Int, daysInMonth: Int) -> String {
        if progress >= target { return "Complete" }
        let expected = Double(target) * Double(dayOfMonth) / Double(max(daysInMonth, 1))
        if Double(progress) >= expected.rounded(.down) { return "You're on pace" }
        let behind = Int(expected.rounded(.down)) - progress
        return "\(Format.plural(behind, "more day")) to stay on pace"
    }
}
