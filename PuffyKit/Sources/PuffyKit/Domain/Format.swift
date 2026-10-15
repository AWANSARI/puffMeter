import Foundation

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

/// Shared display formatting so numbers read the same everywhere.
public enum Format {
    /// "8h", "7.5h"
    public static func hours(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value))h" : String(format: "%.1fh", value)
    }

    /// "1.5 L", "2 L"
    public static func liters(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded.rounded() == rounded { return "\(Int(rounded)) L" }
        var text = String(format: "%.2f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        return "\(text) L"
    }

    /// "↓ 8", "↑ 3"; nil delta renders as "No change".
    public static func delta(_ value: Int) -> String {
        if value == 0 { return "No change" }
        return value < 0 ? "↓ \(abs(value))" : "↑ \(value)"
    }

    public static func weekdayInitial(_ day: DayKey, calendar: Calendar = .current) -> String {
        let symbols = calendar.veryShortWeekdaySymbols
        let weekday = calendar.component(.weekday, from: day.startDate(calendar: calendar))
        return symbols[(weekday - 1) % symbols.count]
    }

    /// "Thursday, October 8"
    public static func longDay(_ day: DayKey, calendar: Calendar = .current) -> String {
        day.startDate(calendar: calendar).formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    /// "Oct 8"
    public static func shortDay(_ day: DayKey, calendar: Calendar = .current) -> String {
        day.startDate(calendar: calendar).formatted(.dateTime.month(.abbreviated).day())
    }

    /// "Oct 2–8" or "Sep 28 – Oct 4"
    public static func range(_ start: DayKey, _ end: DayKey, calendar: Calendar = .current) -> String {
        if start.year == end.year && start.month == end.month {
            return "\(shortDay(start, calendar: calendar))–\(end.day)"
        }
        return "\(shortDay(start, calendar: calendar)) – \(shortDay(end, calendar: calendar))"
    }

    /// "Thursday, Oct 8 · 8:02 AM"
    public static func scanTimestamp(_ date: Date) -> String {
        let day = date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        let time = date.formatted(date: .omitted, time: .shortened)
        return "\(day) · \(time)"
    }

    public static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    public static func monthYear(_ month: MonthKey, calendar: Calendar = .current) -> String {
        month.firstDay.startDate(calendar: calendar).formatted(.dateTime.month(.wide).year())
    }

    public static func plural(_ count: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(count) \(count == 1 ? singular : (plural ?? singular + "s"))"
    }
}
