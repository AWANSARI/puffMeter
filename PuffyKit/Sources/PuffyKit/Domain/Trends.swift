import Foundation

public enum TrendRange: String, CaseIterable, Sendable, Identifiable {
    case day = "D", week = "W", month = "M", sixMonths = "6M", year = "Y"
    public var id: String { rawValue }

    public var averageLabel: String {
        switch self {
        case .day: "today"
        case .week: "weekly average"
        case .month: "monthly average"
        case .sixMonths: "6-month average"
        case .year: "yearly average"
        }
    }

    public var previousLabel: String {
        switch self {
        case .day: "yesterday"
        case .week: "previous week"
        case .month: "previous month"
        case .sixMonths: "previous 6 months"
        case .year: "previous year"
        }
    }
}

public struct TrendPoint: Hashable, Sendable, Identifiable {
    public var id: String
    /// Label under the bar ("F", "Oct", "W40").
    public var label: String
    public var start: DayKey
    public var end: DayKey
    public var value: Double?
    public var isCurrent: Bool
}

public struct TrendSeries: Hashable, Sendable {
    public var range: TrendRange
    public var points: [TrendPoint]
    public var start: DayKey
    public var end: DayKey
    public var average: Double?
    public var previousAverage: Double?

    public var deltaVsPrevious: Int? {
        guard let average, let previousAverage else { return nil }
        return Int((average - previousAverage).rounded())
    }
}

public enum TrendAggregator {
    /// - Parameter offset: 0 for the range ending `today`, -1 for the range before it, etc.
    public static func series(_ range: TrendRange, history: History, today: DayKey, offset: Int = 0) -> TrendSeries {
        let cal = history.calendar
        switch range {
        case .day, .week:
            // Day view still charts the week for context; the detail view shows the day itself.
            let end = today.adding(days: 7 * offset, calendar: cal)
            let start = end.adding(days: -6, calendar: cal)
            let points = history.stats(from: start, through: end).map { stats in
                TrendPoint(id: stats.day.description, label: Format.weekdayInitial(stats.day, calendar: cal),
                           start: stats.day, end: stats.day, value: stats.score.map(Double.init),
                           isCurrent: stats.day == end)
            }
            return finish(range: range, points: points, start: start, end: end, history: history,
                          previousStart: start.adding(days: -7, calendar: cal), previousEnd: start.adding(days: -1, calendar: cal))
        case .month:
            let end = today.adding(days: 30 * offset, calendar: cal)
            let start = end.adding(days: -29, calendar: cal)
            let points = history.stats(from: start, through: end).map { stats in
                TrendPoint(id: stats.day.description, label: "\(stats.day.day)", start: stats.day, end: stats.day,
                           value: stats.score.map(Double.init), isCurrent: stats.day == end)
            }
            return finish(range: range, points: points, start: start, end: end, history: history,
                          previousStart: start.adding(days: -30, calendar: cal), previousEnd: start.adding(days: -1, calendar: cal))
        case .sixMonths:
            let end = today.adding(days: 182 * offset, calendar: cal)
            let points = (0..<26).reversed().map { weeksAgo -> TrendPoint in
                let weekEnd = end.adding(days: -7 * weeksAgo, calendar: cal)
                let weekStart = weekEnd.adding(days: -6, calendar: cal)
                return TrendPoint(id: weekStart.description, label: Format.shortDay(weekStart, calendar: cal),
                                  start: weekStart, end: weekEnd,
                                  value: history.average(from: weekStart, through: weekEnd), isCurrent: weeksAgo == 0)
            }
            let start = points.first?.start ?? end
            return finish(range: range, points: points, start: start, end: end, history: history,
                          previousStart: start.adding(days: -182, calendar: cal), previousEnd: start.adding(days: -1, calendar: cal))
        case .year:
            let endMonth = today.monthKey.adding(months: 12 * offset, calendar: cal)
            let points = (0..<12).reversed().map { monthsAgo -> TrendPoint in
                let month = endMonth.adding(months: -monthsAgo, calendar: cal)
                let label = month.firstDay.startDate(calendar: cal).formatted(.dateTime.month(.narrow))
                return TrendPoint(id: month.description, label: label, start: month.firstDay, end: month.lastDay,
                                  value: history.average(from: month.firstDay, through: month.lastDay),
                                  isCurrent: monthsAgo == 0)
            }
            let start = points.first?.start ?? today
            let end = points.last?.end ?? today
            let prevStart = endMonth.adding(months: -23, calendar: cal).firstDay
            return finish(range: range, points: points, start: start, end: end, history: history,
                          previousStart: prevStart, previousEnd: start.adding(days: -1, calendar: cal))
        }
    }

    private static func finish(range: TrendRange, points: [TrendPoint], start: DayKey, end: DayKey,
                               history: History, previousStart: DayKey, previousEnd: DayKey) -> TrendSeries {
        TrendSeries(range: range, points: points, start: start, end: end,
                    average: history.average(from: start, through: end),
                    previousAverage: history.average(from: previousStart, through: previousEnd))
    }

    /// Heatmap intensity bucket 0 (best, brightest) ... 3 (highest score, dimmest).
    public static func heatBucket(score: Int, goal: Int) -> Int {
        switch score {
        case ...goal: 0
        case ...(goal + 7): 1
        case ...(goal + 15): 2
        default: 3
        }
    }
}
