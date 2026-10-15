import Foundation

/// File naming and serialized formats for what PuffyMeter writes to Google Drive.
public enum DriveNaming {
    /// "2026-10-08_0802" in the user's local time zone.
    public static func baseName(for date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04d-%02d-%02d_%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
    }

    public static func photoName(for date: Date, timeZone: TimeZone = .current) -> String {
        baseName(for: date, timeZone: timeZone) + ".jpg"
    }

    public static func scoresName(for date: Date, timeZone: TimeZone = .current) -> String {
        baseName(for: date, timeZone: timeZone) + ".json"
    }

    public static let defaultFolderName = "PuffyMeter Daily"
    /// `appProperties` marker used to find PuffyMeter files when restoring.
    public static let appPropertyKey = "puffymeter"
}

/// The JSON written next to each photo ("Scores and notes"). Schema version 1.
public struct ScanExport: Codable, Hashable, Sendable {
    public struct Zones: Codable, Hashable, Sendable {
        public var underEyes: Int
        public var cheeks: Int
        public var jawline: Int
    }

    public struct Delta: Codable, Hashable, Sendable {
        public var vsYesterday: Int?
        public var vsBaseline: Int?
    }

    public struct Quality: Codable, Hashable, Sendable {
        public var lighting: Double
        public var yawDeg: Double
        public var rollDeg: Double
        public var neutrality: Double
        public var method: String
        public var manual: Bool
    }

    public struct Habits: Codable, Hashable, Sendable {
        public var sleepHours: Double?
        public var waterLiters: Double?
        public var salt: String?
        public var alcohol: String?
    }

    public var schemaVersion: Int
    public var scanID: UUID
    public var capturedAt: String
    public var score: Int
    public var zones: Zones
    public var raw: RawFaceMetrics
    public var lowConfidence: Bool
    public var isBaseline: Bool
    public var baselineScanID: UUID?
    public var delta: Delta
    public var quality: Quality
    public var habits: Habits
    public var tags: [String]
    public var notes: String
    public var appVersion: String

    public init(scan: ScanRecord, baselineID: UUID?, deltaVsYesterday: Int?, deltaVsBaseline: Int?,
                habits: HabitLog?, appVersion: String, timeZone: TimeZone = .current) {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        schemaVersion = 1
        scanID = scan.id
        capturedAt = formatter.string(from: scan.capturedAt)
        score = scan.score
        zones = Zones(underEyes: scan.zones.underEyes, cheeks: scan.zones.cheeks, jawline: scan.zones.jawline)
        raw = scan.raw
        lowConfidence = scan.lowConfidence
        isBaseline = scan.isBaseline
        baselineScanID = baselineID
        delta = Delta(vsYesterday: deltaVsYesterday, vsBaseline: deltaVsBaseline)
        quality = Quality(lighting: scan.quality.lighting, yawDeg: scan.quality.yawDeg, rollDeg: scan.quality.rollDeg,
                          neutrality: scan.quality.neutrality, method: scan.quality.method.rawValue,
                          manual: scan.quality.manual)
        self.habits = Habits(sleepHours: habits?.sleepHours, waterLiters: habits?.waterLiters,
                             salt: habits?.salt?.rawValue, alcohol: habits?.alcohol?.rawValue)
        tags = scan.tags
        notes = scan.notes
        self.appVersion = appVersion
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> ScanExport {
        try JSONDecoder().decode(ScanExport.self, from: data)
    }

    /// Rebuilds a local record when restoring history from Drive.
    public func makeRecord(timeZone: TimeZone = .current) -> ScanRecord? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: capturedAt) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return ScanRecord(id: scanID, capturedAt: date, dayKey: DayKey(date, calendar: calendar), score: score,
                          zones: ZoneScores(underEyes: zones.underEyes, cheeks: zones.cheeks, jawline: zones.jawline),
                          raw: raw,
                          quality: ScanQuality(lighting: quality.lighting, yawDeg: quality.yawDeg, rollDeg: quality.rollDeg,
                                               neutrality: quality.neutrality,
                                               method: AnalysisMethod(rawValue: quality.method) ?? .vision,
                                               manual: quality.manual),
                          lowConfidence: lowConfidence, isBaseline: isBaseline, notes: notes, tags: tags,
                          syncState: .synced)
    }
}

public enum CSVExporter {
    public static let header = "date,time,score,under_eyes,cheeks,jawline,sleep_h,water_l,salt,alcohol,notes,tags,drive_file_id"

    public static func csv(history: History) -> String {
        var lines = [header]
        for scan in history.scans {
            let habits = history.habits[scan.dayKey]
            let fields: [String] = [
                scan.dayKey.description,
                timeString(scan.capturedAt, calendar: history.calendar),
                "\(scan.score)",
                "\(scan.zones.underEyes)",
                "\(scan.zones.cheeks)",
                "\(scan.zones.jawline)",
                habits?.sleepHours.map { String($0) } ?? "",
                habits?.waterLiters.map { String($0) } ?? "",
                habits?.salt?.rawValue ?? "",
                habits?.alcohol?.rawValue ?? "",
                scan.notes,
                scan.tags.joined(separator: ";"),
                scan.drivePhotoFileID ?? "",
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func timeString(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
