import Foundation
import PuffyKit

// A tiny assertion runner so the domain logic can be verified with only the Command Line
// Tools installed. The full suite lives in Tests/PuffyKitTests (Swift Testing, run in Xcode).

nonisolated(unsafe) var failures = 0
nonisolated(unsafe) var passes = 0

func check(_ condition: @autoclosure () -> Bool, _ message: String, file: String = #file, line: Int = #line) {
    if condition() {
        passes += 1
    } else {
        failures += 1
        print("FAIL \(URL(fileURLWithPath: file).lastPathComponent):\(line) \(message)")
    }
}

let cal = SampleData.calendar
let today = SampleData.today

// Scoring: mockup zones 38/29/26 → 32.
check(ScoringEngine.overall(ZoneScores(underEyes: 38, cheeks: 29, jawline: 26)) == 32, "overall 38/29/26 should be 32")
let ref = ScoringEngine.ZoneReference(center: 1.0, spread: 0.02)
check(ScoringEngine.zoneScore(raw: 1.0, reference: ref) == 30, "raw at center scores 30")
check(ScoringEngine.zoneScore(raw: 1.02, reference: ref) == 45, "one spread above scores 45")
check(ScoringEngine.zoneScore(raw: 0.0, reference: ref) == 0, "clamps at 0")
check(ScoringEngine.zoneScore(raw: 9.0, reference: ref) == 100, "clamps at 100")
let lowQuality = ScanQuality(lighting: 0.2, yawDeg: 15, rollDeg: 2, neutrality: 0.4, method: .vision)
let baselineRaw = RawFaceMetrics(underEyes: 0.3, cheeks: 0.9, jawline: 0.8)
let reference = ScoringEngine.reference(baseline: baselineRaw, history: [])
check(ScoringEngine.score(raw: baselineRaw, quality: lowQuality, reference: reference).lowConfidence, "low quality flagged")
check(!ScoringEngine.score(raw: baselineRaw, quality: .ideal, reference: reference).lowConfidence, "ideal not flagged")
check(ScoringEngine.score(raw: baselineRaw, quality: .ideal, reference: reference).overall == 30, "baseline scores 30")

// Rings.
check(abs(RingMath.dePuff(score: 32, goal: 35) - 68.0 / 65.0) < 0.0001, "De-Puff 32/35 = 1.046")
check(RingMath.dePuff(score: nil, goal: 35) == 0, "no scan = 0")
check(abs(RingMath.dePuff(score: 40, goal: 35) - 60.0 / 65.0) < 0.0001, "De-Puff 40/35")

let history = SampleData.history
let todayStats = history.stats(for: today)
check(todayStats.score == 32, "today score 32")
check(todayStats.habitCount == 3, "today habits 3/4")
check(todayStats.rings.dePuff > 1 && todayStats.rings.scan == 1 && todayStats.rings.habits == 0.75, "today rings")
check(RingMath.caption(for: todayStats) == "One more habit check-in to close all three rings.", "caption: \(RingMath.caption(for: todayStats))")
check(history.deltaVsPrevious(for: today) == -8, "delta vs yesterday -8")
check(history.zoneDeltaVsPrevious(for: today) == ZoneScores(underEyes: -10, cheeks: -7, jawline: -5), "zone deltas")

// Streaks.
check(StreakCalculator.current(scanDays: history.scanDays, today: today, calendar: cal) == 7, "7-day streak")
check(StreakCalculator.current(scanDays: history.scanDays, today: today.adding(days: 1, calendar: cal), calendar: cal) == 7,
      "streak survives until a full day passes")
check(StreakCalculator.current(scanDays: history.scanDays, today: today.adding(days: 2, calendar: cal), calendar: cal) == 0,
      "streak breaks after a missed day")
// DST: US fall-back 2026-11-01.
let dstDays: Set<DayKey> = [DayKey(year: 2026, month: 10, day: 31), DayKey(year: 2026, month: 11, day: 1),
                            DayKey(year: 2026, month: 11, day: 2)]
check(StreakCalculator.current(scanDays: dstDays, today: DayKey(year: 2026, month: 11, day: 2), calendar: cal) == 3,
      "streak across DST")
check(DayKey(year: 2026, month: 3, day: 7).adding(days: 1, calendar: cal) == DayKey(year: 2026, month: 3, day: 8), "DST spring add")
check(DayKey(year: 2026, month: 12, day: 31).adding(days: 1, calendar: cal) == DayKey(year: 2027, month: 1, day: 1), "year rollover")

// Weekly trend: 40 average, ↓ 6 vs previous week (mockup).
let week = TrendAggregator.series(.week, history: history, today: today)
check(week.points.map { $0.value.map { Int($0) } } == [48, 44, 41, 39, 36, 40, 32], "week values \(week.points.map(\.value))")
check(week.average.map { Int($0.rounded()) } == 40, "week average 40, got \(String(describing: week.average))")
check(week.points.map(\.label).joined() == "FSSMTWT", "weekday labels \(week.points.map(\.label))")

// Challenges.
check(ChallengeEngine.paceText(progress: 8, target: 20, dayOfMonth: 8, daysInMonth: 31) == "You're on pace", "on pace")
check(ChallengeEngine.paceText(progress: 2, target: 20, dayOfMonth: 15, daysInMonth: 30) == "8 more days to stay on pace",
      "behind pace: \(ChallengeEngine.paceText(progress: 2, target: 20, dayOfMonth: 15, daysInMonth: 30))")
let definitions = ChallengeEngine.bundledDefinitions()
check(definitions.count >= 3, "bundled challenges load (\(definitions.count))")
if let momentum = definitions.first(where: { $0.id == "2026-10-morning-momentum" }) {
    let status = ChallengeEngine.status(of: momentum, history: history, progressRecords: [], today: today, calendar: cal)
    check(status.progress == 7 && status.joined && status.daysLeft == 23, "momentum 7/20, 23 days left")
}
if let hydration = definitions.first(where: { $0.id == "2026-10-hydration" }) {
    let notJoined = ChallengeEngine.status(of: hydration, history: history, progressRecords: [], today: today, calendar: cal)
    check(!notJoined.joined, "hydration requires join")
    let joined = ChallengeEngine.status(of: hydration, history: history, progressRecords: SampleData.challengeRecords,
                                        today: today, calendar: cal)
    check(joined.joined && joined.progress == 5, "hydration joined, progress \(joined.progress)")
}

// Awards.
let awards = AwardCatalog.all(challenges: definitions)
let context = AwardEngine.Context(history: history, challenges: definitions,
                                  challengeRecords: SampleData.challengeRecords, today: today)
let fresh = AwardEngine.evaluate(awards, context: context, earned: [])
check(fresh.contains { $0.awardID == "first-scan" } && fresh.contains { $0.awardID == "streak-7" }, "earns first scan + 7-day")
check(!fresh.contains { $0.awardID == "scans-30" }, "30 scans not yet")
let again = AwardEngine.evaluate(awards, context: context, earned: fresh)
check(again.isEmpty, "award evaluation is idempotent")
if let thirty = awards.first(where: { $0.id == "scans-30" }) {
    let progress = AwardEngine.progress(of: thirty, in: context)
    check(progress.current == 18 && progress.target == 30, "30 scans progress 18/30 (got \(progress.current))")
}

// Insights.
let inputs = InsightEngine.inputs(history: history, through: today)
let correlations = InsightEngine.correlations(inputs)
let sleep = correlations.first { $0.factor == .sleep }
check(sleep?.hasEnoughData == true && (sleep?.delta ?? 0) < 0, "sleep correlation negative: \(String(describing: sleep))")
check(correlations.first { $0.factor == .cycle }?.hasEnoughData == false, "cycle needs more data")
check(InsightEngine.correlation(for: .sleep, inputs: Array(inputs.prefix(6))).strength == .insufficient, "few days insufficient")

// Drive naming and export.
check(DriveNaming.photoName(for: SampleData.now, timeZone: cal.timeZone) == "2026-10-08_0802.jpg", "photo name")
check(DriveNaming.scoresName(for: SampleData.now, timeZone: cal.timeZone) == "2026-10-08_0802.json", "json name")
if let scan = history.scans.last {
    let export = ScanExport(scan: scan, baselineID: history.baseline?.id, deltaVsYesterday: -8, deltaVsBaseline: -18,
                            habits: history.habits[today], appVersion: "1.0 (1)", timeZone: cal.timeZone)
    if let data = try? export.encoded(), let decoded = try? ScanExport.decode(data) {
        check(decoded == export, "export round-trips")
        check(decoded.capturedAt.hasPrefix("2026-10-08T08:02:00"), "capturedAt local time \(decoded.capturedAt)")
        check(decoded.makeRecord(timeZone: cal.timeZone)?.dayKey == today, "restore day key")
    } else {
        check(false, "export encodes")
    }
}
let csv = CSVExporter.csv(history: history)
check(csv.hasPrefix(CSVExporter.header), "csv header")
check(csv.split(separator: "\n").count == history.scans.count + 1, "csv rows")

// Persistence round-trip.
let state = SampleData.state
if let data = try? JSONEncoder.puffy.encode(state), let decoded = try? JSONDecoder.puffy.decode(PersistedState.self, from: data) {
    check(decoded == state, "persisted state round-trips")
} else {
    check(false, "persisted state encodes")
}

// Goals by effective date.
let goalHistory = [GoalSet(effectiveFrom: DayKey(year: 2026, month: 9, day: 1), dePuffMax: 40),
                   GoalSet(effectiveFrom: DayKey(year: 2026, month: 10, day: 5), dePuffMax: 35)]
check(goalHistory.goals(for: DayKey(year: 2026, month: 10, day: 4)).dePuffMax == 40, "past day keeps old goal")
check(goalHistory.goals(for: today).dePuffMax == 35, "new goal applies forward")

print("\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
