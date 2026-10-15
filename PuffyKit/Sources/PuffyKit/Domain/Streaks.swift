import Foundation

public enum StreakCalculator {
    /// Consecutive days with at least one scan, ending today or yesterday. A streak isn't
    /// broken until a full day passes without a scan.
    public static func current(scanDays: Set<DayKey>, today: DayKey, calendar: Calendar = .current) -> Int {
        var cursor = scanDays.contains(today) ? today : today.adding(days: -1, calendar: calendar)
        var count = 0
        while scanDays.contains(cursor) {
            count += 1
            cursor = cursor.adding(days: -1, calendar: calendar)
        }
        return count
    }

    public static func longest(scanDays: Set<DayKey>, calendar: Calendar = .current) -> Int {
        longestRun(of: scanDays, calendar: calendar)
    }

    /// Longest run of consecutive days in an arbitrary set (used for "Perfect week").
    public static func longestRun(of days: Set<DayKey>, calendar: Calendar = .current) -> Int {
        var best = 0
        for day in days where !days.contains(day.adding(days: -1, calendar: calendar)) {
            var length = 1
            var next = day.adding(days: 1, calendar: calendar)
            while days.contains(next) {
                length += 1
                next = next.adding(days: 1, calendar: calendar)
            }
            best = max(best, length)
        }
        return best
    }

    /// Whether today's scan is still needed to keep a streak (for the streak-saver reminder).
    public static func isAtRisk(scanDays: Set<DayKey>, today: DayKey, calendar: Calendar = .current) -> Bool {
        !scanDays.contains(today) && current(scanDays: scanDays, today: today, calendar: calendar) > 0
    }
}
