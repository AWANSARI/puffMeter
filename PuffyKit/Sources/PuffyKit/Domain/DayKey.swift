import Foundation

/// A local calendar day ("2026-10-08"). Days run from local midnight to midnight.
public struct DayKey: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    public init?(string: String) {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Start of this day in the given calendar's time zone.
    public func startDate(calendar: Calendar = .current) -> Date {
        let comps = DateComponents(year: year, month: month, day: day)
        return calendar.date(from: comps) ?? Date(timeIntervalSince1970: 0)
    }

    /// Noon is used for day arithmetic so DST transitions never skip or repeat a day.
    private func noon(calendar: Calendar) -> Date {
        let comps = DateComponents(year: year, month: month, day: day, hour: 12)
        return calendar.date(from: comps) ?? Date(timeIntervalSince1970: 0)
    }

    public func adding(days: Int, calendar: Calendar = .current) -> DayKey {
        let date = calendar.date(byAdding: .day, value: days, to: noon(calendar: calendar)) ?? noon(calendar: calendar)
        return DayKey(date, calendar: calendar)
    }

    public func days(until other: DayKey, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: noon(calendar: calendar), to: other.noon(calendar: calendar)).day ?? 0
    }

    public var monthKey: MonthKey { MonthKey(year: year, month: month) }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    // Encode as "YYYY-MM-DD" so exported JSON stays readable.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let key = DayKey(string: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid day key \(raw)")
        }
        self = key
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

public struct MonthKey: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int

    public init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    public init?(string: String) {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        self.init(year: parts[0], month: parts[1])
    }

    public var description: String { String(format: "%04d-%02d", year, month) }

    public var firstDay: DayKey { DayKey(year: year, month: month, day: 1) }

    public func numberOfDays(calendar: Calendar = .current) -> Int {
        let date = firstDay.startDate(calendar: calendar)
        return calendar.range(of: .day, in: .month, for: date)?.count ?? 30
    }

    public var lastDay: DayKey {
        DayKey(year: year, month: month, day: numberOfDays())
    }

    public func adding(months: Int, calendar: Calendar = .current) -> MonthKey {
        let date = calendar.date(byAdding: .month, value: months, to: firstDay.startDate(calendar: calendar)) ?? firstDay.startDate(calendar: calendar)
        return DayKey(date, calendar: calendar).monthKey
    }

    public func contains(_ day: DayKey) -> Bool { day.year == year && day.month == month }

    public static func < (lhs: MonthKey, rhs: MonthKey) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let key = MonthKey(string: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid month key \(raw)")
        }
        self = key
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
