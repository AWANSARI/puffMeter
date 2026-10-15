import Foundation

public struct Correlation: Hashable, Sendable, Identifiable {
    public enum Factor: String, CaseIterable, Sendable, Identifiable {
        case sleep, water, salt, cycle
        public var id: String { rawValue }
        public var title: String { rawValue.capitalized }
        public var symbol: String {
            switch self {
            case .sleep: "moon"
            case .water: "drop"
            case .salt: "fork.knife"
            case .cycle: "circle.dashed"
            }
        }
    }

    public enum Strength: String, Sendable {
        case insufficient, none, small, moderate, strong

        public var label: String {
            switch self {
            case .insufficient: "No conclusion yet"
            case .none: "No clear difference"
            case .small: "Small association"
            case .moderate: "Moderate association"
            case .strong: "Strong association"
            }
        }
    }

    public var factor: Factor
    /// Mean score difference (group of interest minus comparison). Negative = lower = better.
    public var delta: Double?
    public var pairedDays: Int
    public var strength: Strength
    public var explanation: String
    public var id: Factor { factor }

    public var hasEnoughData: Bool { strength != .insufficient }

    /// "−7 points" (uses a true minus sign like the mockup).
    public var deltaText: String? {
        guard let delta, hasEnoughData else { return nil }
        let rounded = Int(delta.rounded())
        if rounded == 0 { return "±0 points" }
        return rounded < 0 ? "−\(abs(rounded)) points" : "+\(rounded) points"
    }

    public var footnote: String {
        hasEnoughData ? "\(pairedDays) paired days · \(strength.label)" : "\(pairedDays) paired days · No conclusion yet"
    }
}

/// Personal associations between habits and scores. Never claims causation.
public enum InsightEngine {
    public static let minimumPerGroup = 5
    public static let minimumPaired = 14
    public static let windowDays = 30

    public struct Input: Sendable {
        public var score: Int
        public var sleepHours: Double?
        public var waterLiters: Double?
        public var salt: SaltLevel?
        /// Menstrual or late-luteal day from HealthKit, nil when unknown.
        public var cyclePhaseFlag: Bool?
        public var waterGoal: Double

        public init(score: Int, sleepHours: Double? = nil, waterLiters: Double? = nil,
                    salt: SaltLevel? = nil, cyclePhaseFlag: Bool? = nil, waterGoal: Double = 2) {
            self.score = score
            self.sleepHours = sleepHours
            self.waterLiters = waterLiters
            self.salt = salt
            self.cyclePhaseFlag = cyclePhaseFlag
            self.waterGoal = waterGoal
        }
    }

    public static func inputs(history: History, through today: DayKey, cycleDays: Set<DayKey> = [],
                              cycleDataAvailable: Bool = false) -> [Input] {
        let start = today.adding(days: -(windowDays - 1), calendar: history.calendar)
        return history.stats(from: start, through: today).compactMap { stats in
            guard let scan = stats.primaryScan, !scan.lowConfidence else { return nil }
            return Input(score: scan.score, sleepHours: stats.habits?.sleepHours,
                         waterLiters: stats.habits?.waterLiters, salt: stats.habits?.salt,
                         cyclePhaseFlag: cycleDataAvailable ? cycleDays.contains(stats.day) : nil,
                         waterGoal: stats.goals.waterGoalLiters)
        }
    }

    public static func correlations(_ inputs: [Input]) -> [Correlation] {
        Correlation.Factor.allCases.map { correlation(for: $0, inputs: inputs) }
    }

    public static func correlation(for factor: Correlation.Factor, inputs: [Input]) -> Correlation {
        // Each closure returns true for the group of interest, false for the comparison, nil if unknown.
        let classify: (Input) -> Bool?
        let explanation: String
        switch factor {
        case .sleep:
            classify = { $0.sleepHours.map { $0 >= 7 } }
            explanation = "Average score after 7+ hours vs less than 7 hours."
        case .water:
            classify = { input in input.waterLiters.map { $0 >= input.waterGoal } }
            explanation = "Average score on days with 2 L logged vs less."
        case .salt:
            classify = { input in
                switch input.salt {
                case .high: true
                case .low: false
                default: nil
                }
            }
            explanation = "Average score after \u{201C}high salt\u{201D} evenings vs \u{201C}low salt\u{201D}."
        case .cycle:
            classify = { $0.cyclePhaseFlag }
            explanation = "Log cycle days in Apple Health to explore your own pattern."
        }

        var interest: [Int] = []
        var comparison: [Int] = []
        for input in inputs {
            guard let isInterest = classify(input) else { continue }
            if isInterest { interest.append(input.score) } else { comparison.append(input.score) }
        }
        let paired = interest.count + comparison.count
        guard interest.count >= minimumPerGroup, comparison.count >= minimumPerGroup, paired >= minimumPaired else {
            return Correlation(factor: factor, delta: nil, pairedDays: paired, strength: .insufficient,
                               explanation: factor == .cycle ? explanation : "More data needed to compare. Keep logging.")
        }
        let delta = mean(interest) - mean(comparison)
        let cycleExplanation = "Average score on menstrual and late-luteal days vs others."
        return Correlation(factor: factor, delta: delta, pairedDays: paired,
                           strength: strength(delta: delta, paired: paired),
                           explanation: factor == .cycle ? cycleExplanation : explanation)
    }

    static func strength(delta: Double, paired: Int) -> Correlation.Strength {
        let magnitude = abs(delta)
        if magnitude < 2 { return .none }
        if magnitude < 4 { return .small }
        if magnitude <= 8 { return paired >= 20 ? .moderate : .small }
        return paired >= 20 ? .strong : .moderate
    }

    static func mean(_ values: [Int]) -> Double {
        Double(values.reduce(0, +)) / Double(max(values.count, 1))
    }

    // MARK: Summary insights

    public struct DailyInsight: Hashable, Sendable, Identifiable {
        public var id: String
        public var symbol: String?
        public var title: String
        public var body: String
        public var footnote: String?
    }

    /// Up to two insights for the Summary tab: the most significant correlation, then consistency.
    public static func dailyInsights(correlations: [Correlation], recentScanTimes: [Date],
                                     reminder: ReminderTime, calendar: Calendar = .current) -> [DailyInsight] {
        var result: [DailyInsight] = []
        let best = correlations
            .filter { $0.hasEnoughData && $0.strength != .none && ($0.delta ?? 0) < 0 }
            .min { ($0.delta ?? 0) < ($1.delta ?? 0) }
        if let best {
            result.append(insight(for: best))
        }
        if recentScanTimes.count >= 7 {
            let consistent = recentScanTimes.suffix(7).allSatisfy { date in
                let comps = calendar.dateComponents([.hour, .minute], from: date)
                let minutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
                return abs(minutes - (reminder.hour * 60 + reminder.minute)) <= 15
            }
            if consistent {
                result.append(DailyInsight(id: "consistency", symbol: nil, title: "Same light. Clearer comparisons.",
                                           body: "You've scanned within 15 minutes of \(reminder.formatted) all week. Keep your routine steady.",
                                           footnote: nil))
            } else {
                result.append(DailyInsight(id: "consistency", symbol: nil, title: "Same time, clearer trends.",
                                           body: "Try scanning at the same time each day for clearer comparisons.",
                                           footnote: nil))
            }
        }
        return Array(result.prefix(2))
    }

    static func insight(for correlation: Correlation) -> DailyInsight {
        let body: String
        let title: String
        switch correlation.factor {
        case .sleep:
            title = "A well-rested pattern"
            body = "Your scores tended to be lower after 7+ hours of sleep over the last \(windowDays / 7) weeks."
        case .water:
            title = "A hydration pattern"
            body = "Your scores tended to be lower on days you logged your water goal."
        case .salt:
            title = "A lighter-evening pattern"
            body = "Your scores tended to be lower after high-salt evenings."
        case .cycle:
            title = "A cycle pattern"
            body = "Your scores shifted around certain cycle days."
        }
        return DailyInsight(id: "correlation-\(correlation.factor.rawValue)", symbol: correlation.factor.symbol,
                            title: title, body: body, footnote: "Personal association · Not proof of cause")
    }
}
