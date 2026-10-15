import Foundation

/// Progress of the three rings for one day. Values above 1 mean the ring overlapped.
public struct RingProgress: Hashable, Sendable {
    public var dePuff: Double
    public var scan: Double
    public var habits: Double

    public init(dePuff: Double, scan: Double, habits: Double) {
        self.dePuff = dePuff
        self.scan = scan
        self.habits = habits
    }

    public static let zero = RingProgress(dePuff: 0, scan: 0, habits: 0)

    public var allClosed: Bool { dePuff >= 1 && scan >= 1 && habits >= 1 }
    public var closedCount: Int { [dePuff, scan, habits].filter { $0 >= 1 }.count }
}

public enum RingMath {
    /// `(100 − score) / (100 − goal)`: score 32 with goal 35 → 1.046 (closed with overlap).
    public static func dePuff(score: Int?, goal: Int) -> Double {
        guard let score else { return 0 }
        let denominator = Double(100 - goal.clamped(to: 0...99))
        return max(0, Double(100 - score) / denominator)
    }

    public static func scan(count: Int, goal: Int) -> Double {
        Double(count) / Double(max(goal, 1))
    }

    public static func habits(count: Int, goal: Int) -> Double {
        Double(count) / Double(max(goal, 1))
    }

    public static func caption(for stats: DayStats) -> String {
        let p = stats.rings
        if p.allClosed { return "All three rings closed today." }
        if stats.scanCount == 0 && stats.habitCount == 0 { return "Start with today's scan." }
        if p.closedCount == 2 {
            if p.scan < 1 { return "Scan to close your Scan ring." }
            if p.habits < 1 {
                let remaining = stats.goals.habitsPerDay - stats.habitCount
                return remaining == 1
                    ? "One more habit check-in to close all three rings."
                    : "\(remaining) more habit check-ins to close all three rings."
            }
            return "Your De-Puff ring closes at \(stats.goals.dePuffMax) or lower."
        }
        if p.scan < 1 { return "Start with today's scan." }
        if p.habits < 1 { return "Log your habits to fill the Habits ring." }
        return "Your De-Puff ring closes at \(stats.goals.dePuffMax) or lower."
    }
}

/// Everything the UI needs to know about a single day.
public struct DayStats: Hashable, Sendable, Identifiable {
    public var day: DayKey
    public var goals: GoalSet
    /// The scan that counts for the day (first scan, or the retake that replaced it).
    public var primaryScan: ScanRecord?
    public var scanCount: Int
    public var habits: HabitLog?
    public var id: DayKey { day }

    public var score: Int? { primaryScan?.score }
    public var habitCount: Int { habits?.checkInCount ?? 0 }

    public var rings: RingProgress {
        RingProgress(
            dePuff: RingMath.dePuff(score: score, goal: goals.dePuffMax),
            scan: RingMath.scan(count: scanCount, goal: goals.scansPerDay),
            habits: RingMath.habits(count: habitCount, goal: goals.habitsPerDay)
        )
    }
}

/// Builds per-day stats from raw records. Pure and synchronous so it is easy to test.
public struct History: Sendable {
    public let scans: [ScanRecord]
    public let habits: [DayKey: HabitLog]
    public let goals: [GoalSet]
    public let calendar: Calendar

    private let scansByDay: [DayKey: [ScanRecord]]

    public init(scans: [ScanRecord], habits: [HabitLog], goals: [GoalSet], calendar: Calendar = .current) {
        self.scans = scans.sorted { $0.capturedAt < $1.capturedAt }
        self.habits = Dictionary(habits.map { ($0.dayKey, $0) }, uniquingKeysWith: { _, new in new })
        self.goals = goals
        self.calendar = calendar
        self.scansByDay = Dictionary(grouping: self.scans, by: \.dayKey)
    }

    public var scanDays: Set<DayKey> { Set(scansByDay.keys) }
    public var baseline: ScanRecord? { scans.first(where: \.isBaseline) ?? scans.first }

    public func scans(on day: DayKey) -> [ScanRecord] { scansByDay[day] ?? [] }

    public func stats(for day: DayKey) -> DayStats {
        let dayScans = scans(on: day)
        // Retakes replace the day's scan, so the latest scan of the day is the one that counts.
        return DayStats(day: day, goals: goals.goals(for: day), primaryScan: dayScans.last,
                        scanCount: dayScans.count, habits: habits[day])
    }

    public func stats(from start: DayKey, through end: DayKey) -> [DayStats] {
        var result: [DayStats] = []
        var day = start
        while day <= end {
            result.append(stats(for: day))
            day = day.adding(days: 1, calendar: calendar)
        }
        return result
    }

    public func previousScore(before day: DayKey) -> Int? {
        scans.last(where: { $0.dayKey < day })?.score
    }

    public func deltaVsPrevious(for day: DayKey) -> Int? {
        guard let today = stats(for: day).score, let previous = previousScore(before: day) else { return nil }
        return today - previous
    }

    public func zoneDeltaVsPrevious(for day: DayKey) -> ZoneScores? {
        guard let today = stats(for: day).primaryScan?.zones,
              let previous = scans.last(where: { $0.dayKey < day })?.zones else { return nil }
        return ZoneScores(underEyes: today.underEyes - previous.underEyes,
                          cheeks: today.cheeks - previous.cheeks,
                          jawline: today.jawline - previous.jawline)
    }

    public func average(from start: DayKey, through end: DayKey) -> Double? {
        let values = stats(from: start, through: end).compactMap(\.score)
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }

    public var lowestScore: Int? { scans.filter { !$0.isBaseline }.map(\.score).min() }
}
