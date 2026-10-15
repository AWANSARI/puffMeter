import Foundation

/// Deterministic sample data that reproduces the design mockups (Alex Morgan, Oct 2–8 2026,
/// scores 48 44 41 39 36 40 32, zones 38/29/26). Used by previews, UI-test mode and tests.
public enum SampleData {
    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        calendar.firstWeekday = 2
        return calendar
    }

    public static let today = DayKey(year: 2026, month: 10, day: 8)

    public static var now: Date { date(today, hour: 8, minute: 2) }

    public static func date(_ day: DayKey, hour: Int, minute: Int) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day.startDate(calendar: calendar)) ?? .now
    }

    /// (day, score, zones, sleep, water, salt)
    private static let rows: [(DayKey, Int, ZoneScores, Double?, Double?, SaltLevel?)] = {
        func d(_ m: Int, _ day: Int) -> DayKey { DayKey(year: 2026, month: m, day: day) }
        func z(_ u: Int, _ c: Int, _ j: Int) -> ZoneScores { ZoneScores(underEyes: u, cheeks: c, jawline: j) }
        return [
            (d(9, 9), 50, z(56, 47, 45), 6.0, nil, nil),
            (d(9, 10), 47, z(53, 44, 42), 7.5, 1.5, .low),
            (d(9, 12), 52, z(58, 49, 47), 6.0, 1.0, .high),
            (d(9, 14), 45, z(51, 42, 40), 7.5, 2.0, .low),
            (d(9, 15), 49, z(55, 46, 44), 6.5, 1.5, .high),
            (d(9, 17), 43, z(49, 40, 38), 8.0, 2.0, .low),
            (d(9, 19), 50, z(56, 47, 45), 6.0, 1.0, .high),
            (d(9, 21), 44, z(50, 41, 39), 7.5, 2.0, .low),
            (d(9, 23), 47, z(53, 44, 42), 6.5, 1.5, .medium),
            (d(9, 26), 46, z(52, 43, 41), 8.0, 2.5, .low),
            (d(9, 29), 46, z(52, 43, 41), 6.0, 1.5, .high),
            (d(10, 2), 48, z(54, 45, 43), 6.0, 1.0, .high),
            (d(10, 3), 44, z(50, 41, 39), 7.0, 2.0, .low),
            (d(10, 4), 41, z(47, 38, 36), 7.5, nil, .low),
            (d(10, 5), 39, z(45, 36, 34), 8.0, 2.0, .medium),
            (d(10, 6), 36, z(42, 33, 31), 8.0, nil, .low),
            (d(10, 7), 40, z(48, 36, 31), 6.5, 1.5, .high),
            (d(10, 8), 32, z(38, 29, 26), 8.0, 1.5, .low),
        ]
    }()

    public static var scans: [ScanRecord] {
        rows.enumerated().map { index, row in
            let (day, score, zones, _, _, _) = row
            let minute = [2, 58, 5, 1, 9, 0, 3][index % 7]
            let hour = minute > 30 ? 7 : 8
            let raw = RawFaceMetrics(underEyes: 0.30 + Double(zones.underEyes) / 1000,
                                     cheeks: 0.90 + Double(zones.cheeks) / 1000,
                                     jawline: 0.80 + Double(zones.jawline) / 1000)
            let capturedAt = date(day, hour: hour, minute: day == today ? 2 : minute)
            let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1)) ?? UUID()
            return ScanRecord(id: id,
                              capturedAt: capturedAt, dayKey: day, score: score, zones: zones, raw: raw,
                              quality: .ideal, isBaseline: index == 0,
                              photoFileName: "\(id.uuidString).jpg", thumbnailFileName: "\(id.uuidString).jpg",
                              tags: day == today ? ["8h sleep", "Low salt", "No alcohol"] : [],
                              drivePhotoFileID: "drive-photo-\(index + 1)", driveJSONFileID: "drive-json-\(index + 1)",
                              syncState: .synced)
        }
    }

    public static var habitLogs: [HabitLog] {
        rows.map { row in
            let (day, _, _, sleep, water, salt) = row
            // Oct 8 leaves alcohol unlogged so Habits shows 3 / 4 like the Summary mockup.
            let alcohol: AlcoholLevel? = day == today ? nil : (salt == .high ? .one : AlcoholLevel.none)
            var sources: [HabitKind: HabitSource] = [:]
            if sleep != nil { sources[.sleep] = .health }
            return HabitLog(dayKey: day, waterLiters: water, sleepHours: sleep, salt: salt, alcohol: alcohol,
                            sources: sources)
        }
    }

    public static var goals: [GoalSet] { [GoalSet(effectiveFrom: DayKey(year: 2026, month: 9, day: 9))] }

    public static var earnedAwards: [EarnedAward] {
        [
            EarnedAward(awardID: "first-scan", earnedAt: date(DayKey(year: 2026, month: 9, day: 9), hour: 8, minute: 0), seen: true),
            EarnedAward(awardID: "habit-starter", earnedAt: date(DayKey(year: 2026, month: 9, day: 12), hour: 8, minute: 5), seen: true),
            EarnedAward(awardID: "streak-3", earnedAt: date(DayKey(year: 2026, month: 10, day: 4), hour: 8, minute: 1), seen: true),
            EarnedAward(awardID: "scans-10", earnedAt: date(DayKey(year: 2026, month: 10, day: 2), hour: 8, minute: 1), seen: true),
            EarnedAward(awardID: "streak-7", earnedAt: now, seen: true),
        ]
    }

    public static var challengeRecords: [ChallengeProgress] {
        [ChallengeProgress(challengeID: "2026-10-hydration", joinedAt: date(DayKey(year: 2026, month: 10, day: 1), hour: 9, minute: 0))]
    }

    public static let folder = DriveFolderRef(id: "sample-folder", name: "PuffyMeter Daily", path: "My Drive / PuffyMeter Daily")

    public static var settings: UserSettings {
        UserSettings(onboardingStep: .complete,
                     profile: UserProfile(displayName: "Alex Morgan", email: "alex.morgan@gmail.com", provider: .google),
                     drive: .connected(folder), reminderEnabled: true, reminderTime: .defaultMorning,
                     healthSyncEnabled: true, faceIDLockEnabled: true, lastSyncAt: now)
    }

    /// Renders an illustrated photo for every sample scan (puffier faces for higher scores).
    @MainActor
    public static func seedPhotos(into store: PhotoStore) async {
        for scan in scans {
            let puffiness = min(1, max(0, Double(scan.score - 28) / 26))
            if let jpeg = SampleFaceRenderer.jpeg(puffiness: puffiness, size: CGSize(width: 450, height: 600)) {
                _ = try? await store.save(jpeg: jpeg, scanID: scan.id)
            }
        }
    }

    public static var history: History {
        History(scans: scans, habits: habitLogs, goals: goals, calendar: calendar)
    }

    public static var state: PersistedState {
        PersistedState(scans: scans, habitLogs: habitLogs, goals: goals, earnedAwards: earnedAwards,
                       challengeRecords: challengeRecords, uploadJobs: [], settings: settings)
    }
}
