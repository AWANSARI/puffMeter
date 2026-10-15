import Testing
import Foundation
@testable import PuffyKit

@Suite struct ScoringTests {
    @Test func mockupZonesGiveMockupScore() {
        #expect(ScoringEngine.overall(ZoneScores(underEyes: 38, cheeks: 29, jawline: 26)) == 32)
    }

    @Test(arguments: [(1.0, 30), (1.02, 45), (0.0, 0), (9.0, 100)])
    func zoneScoreMapping(raw: Double, expected: Int) {
        let reference = ScoringEngine.ZoneReference(center: 1.0, spread: 0.02)
        #expect(ScoringEngine.zoneScore(raw: raw, reference: reference) == expected)
    }

    @Test func lowQualityIsFlagged() {
        let raw = RawFaceMetrics(underEyes: 0.3, cheeks: 0.9, jawline: 0.8)
        let reference = ScoringEngine.reference(baseline: raw, history: [])
        let low = ScanQuality(lighting: 0.2, yawDeg: 15, rollDeg: 2, neutrality: 0.4, method: .vision)
        #expect(ScoringEngine.score(raw: raw, quality: low, reference: reference).lowConfidence)
        #expect(ScoringEngine.score(raw: raw, quality: .ideal, reference: reference).overall == 30)
    }

    @Test func deterministic() {
        let raw = RawFaceMetrics(underEyes: 0.31, cheeks: 0.92, jawline: 0.81)
        let reference = ScoringEngine.reference(baseline: RawFaceMetrics(underEyes: 0.3, cheeks: 0.9, jawline: 0.8), history: [])
        #expect(ScoringEngine.score(raw: raw, quality: .ideal, reference: reference)
            == ScoringEngine.score(raw: raw, quality: .ideal, reference: reference))
    }
}

@Suite struct RingAndStreakTests {
    let calendar = SampleData.calendar
    let today = SampleData.today

    @Test func dePuffOverflow() {
        #expect(abs(RingMath.dePuff(score: 32, goal: 35) - 68.0 / 65.0) < 0.0001)
        #expect(RingMath.dePuff(score: nil, goal: 35) == 0)
    }

    @Test func todayMatchesMockup() {
        let stats = SampleData.history.stats(for: today)
        #expect(stats.score == 32)
        #expect(stats.habitCount == 3)
        #expect(RingMath.caption(for: stats) == "One more habit check-in to close all three rings.")
        #expect(SampleData.history.deltaVsPrevious(for: today) == -8)
    }

    @Test func streakRules() {
        let days = SampleData.history.scanDays
        #expect(StreakCalculator.current(scanDays: days, today: today, calendar: calendar) == 7)
        #expect(StreakCalculator.current(scanDays: days, today: today.adding(days: 1, calendar: calendar), calendar: calendar) == 7)
        #expect(StreakCalculator.current(scanDays: days, today: today.adding(days: 2, calendar: calendar), calendar: calendar) == 0)
    }

    @Test func streakAcrossDST() {
        let days: Set<DayKey> = [DayKey(year: 2026, month: 10, day: 31), DayKey(year: 2026, month: 11, day: 1),
                                 DayKey(year: 2026, month: 11, day: 2)]
        #expect(StreakCalculator.current(scanDays: days, today: DayKey(year: 2026, month: 11, day: 2), calendar: calendar) == 3)
    }

    @Test func weeklyTrendMatchesMockup() {
        let week = TrendAggregator.series(.week, history: SampleData.history, today: today)
        #expect(week.points.compactMap { $0.value.map(Int.init) } == [48, 44, 41, 39, 36, 40, 32])
        #expect(week.average.map { Int($0.rounded()) } == 40)
        #expect(week.deltaVsPrevious == -6)
    }
}

@Suite struct EngineTests {
    let today = SampleData.today

    @Test func paceText() {
        #expect(ChallengeEngine.paceText(progress: 8, target: 20, dayOfMonth: 8, daysInMonth: 31) == "You're on pace")
        #expect(ChallengeEngine.paceText(progress: 2, target: 20, dayOfMonth: 15, daysInMonth: 30) == "8 more days to stay on pace")
    }

    @Test func awardsAreIdempotent() {
        let challenges = ChallengeEngine.bundledDefinitions()
        let awards = AwardCatalog.all(challenges: challenges)
        let context = AwardEngine.Context(history: SampleData.history, challenges: challenges,
                                          challengeRecords: SampleData.challengeRecords, today: today)
        let first = AwardEngine.evaluate(awards, context: context, earned: [])
        #expect(first.contains { $0.awardID == "streak-7" })
        #expect(AwardEngine.evaluate(awards, context: context, earned: first).isEmpty)
    }

    @Test func insightsNeedEnoughData() {
        let inputs = InsightEngine.inputs(history: SampleData.history, through: today)
        #expect(InsightEngine.correlation(for: .sleep, inputs: Array(inputs.prefix(6))).strength == .insufficient)
        #expect(InsightEngine.correlation(for: .cycle, inputs: inputs).hasEnoughData == false)
    }

    @Test func driveNamesAndExport() throws {
        let tz = SampleData.calendar.timeZone
        #expect(DriveNaming.photoName(for: SampleData.now, timeZone: tz) == "2026-10-08_0802.jpg")
        let scan = try #require(SampleData.history.scans.last)
        let export = ScanExport(scan: scan, baselineID: nil, deltaVsYesterday: -8, deltaVsBaseline: nil,
                                habits: nil, appVersion: "1.0 (1)", timeZone: tz)
        #expect(try ScanExport.decode(export.encoded()) == export)
    }

    @Test func uploadErrorsMapToFailures() {
        func response(_ code: Int) -> HTTPURLResponse {
            HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: code, httpVersion: nil, headerFields: nil)!
        }
        #expect(throws: DriveError.failure(.authExpired)) { try GoogleDriveClient.validate(response: response(401), body: Data()) }
        #expect(throws: DriveError.failure(.folderMissing)) { try GoogleDriveClient.validate(response: response(404), body: Data()) }
        #expect(throws: DriveError.failure(.server)) { try GoogleDriveClient.validate(response: response(503), body: Data()) }
        #expect(throws: DriveError.failure(.quotaExceeded)) {
            try GoogleDriveClient.validate(response: response(403), body: Data("storageQuotaExceeded".utf8))
        }
    }
}

@MainActor
@Suite struct AppModelTests {
    @Test func authFailureAsksToReconnect() async throws {
        let services = Services.mock(seeded: true)
        let model = AppModel(services: services, calendar: SampleData.calendar, clock: { SampleData.now })
        await model.load()
        let drive = try #require(services.drive as? MockDriveService)
        await drive.setFailure(.authExpired)
        let capture = CapturedFace(jpegData: Data([0xFF, 0xD8, 0xFF]), capturedAt: SampleData.now, quality: .ideal,
                                   raw: RawFaceMetrics(underEyes: 0.33, cheeks: 0.93, jawline: 0.83), faceTransform: nil)
        let record = try await model.recordScan(capture, isBaseline: false)
        // recordScan kicks off uploads in the background; wait for them to settle.
        for _ in 0..<60 where model.uploadCardState(for: record.id) != .failed(.authExpired) {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(model.uploadCardState(for: record.id) == .failed(.authExpired))
        #expect(model.needsDriveReconnect)
    }
}

@MainActor
@Suite struct UploadSuccessTests {
    @Test func newScanUploadsPhotoToDrive() async throws {
        let services = Services.mock(seeded: true)
        let model = AppModel(services: services, calendar: SampleData.calendar, clock: { SampleData.now })
        await model.load()
        let capture = CapturedFace(jpegData: Data([0xFF, 0xD8, 0xFF]), capturedAt: SampleData.now, quality: .ideal,
                                   raw: RawFaceMetrics(underEyes: 0.33, cheeks: 0.93, jawline: 0.83), faceTransform: nil)
        let record = try await model.recordScan(capture, isBaseline: false)
        model.finalizeScan(id: record.id, notes: "Rested", tags: [])
        for _ in 0..<80 {
            if case .saved = model.uploadCardState(for: record.id) { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard case .saved(let name, _) = model.uploadCardState(for: record.id) else {
            Issue.record("Expected saved, got \(model.uploadCardState(for: record.id))")
            return
        }
        #expect(name == "2026-10-08_0802.jpg")
        #expect(model.scan(id: record.id)?.syncState == .synced)
    }
}
