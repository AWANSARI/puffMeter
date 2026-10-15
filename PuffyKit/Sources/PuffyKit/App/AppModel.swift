import Foundation
import Observation

/// The single source of truth for the UI. Holds persisted state, derives everything the
/// screens show, and coordinates services (Drive uploads, Health, notifications).
@MainActor
@Observable
public final class AppModel {
    // MARK: Persisted state
    public private(set) var scans: [ScanRecord] = []
    public private(set) var habitLogs: [HabitLog] = []
    public private(set) var goals: [GoalSet] = []
    public private(set) var earnedAwards: [EarnedAward] = []
    public private(set) var challengeRecords: [ChallengeProgress] = []
    public private(set) var uploadJobs: [UploadJob] = []
    public private(set) var settings = UserSettings()

    // MARK: Runtime state
    public private(set) var isLoaded = false
    public var isOnline = true {
        didSet { if isOnline && !oldValue { Task { await processUploads() } } }
    }
    /// Awards waiting to show their unlock sheet, one at a time.
    public private(set) var awardQueue: [AwardDefinition] = []
    public var showAllRingsClosed = false
    public private(set) var cycleDays: Set<DayKey>?
    public var lastError: String?
    /// Bumped when photos are written outside a scan (demo seeding, Drive restore) so images reload.
    public var photosRevision = 0

    public let services: Services
    public let challengeDefinitions: [ChallengeDefinition]
    public let calendar: Calendar
    private let clock: @Sendable () -> Date
    private var isProcessingUploads = false

    public init(services: Services, calendar: Calendar = .current, clock: @escaping @Sendable () -> Date = { Date() },
                challenges: [ChallengeDefinition] = ChallengeEngine.bundledDefinitions()) {
        self.services = services
        self.calendar = calendar
        self.clock = clock
        self.challengeDefinitions = challenges
    }

    // MARK: Derived

    public var now: Date { clock() }
    public var today: DayKey { DayKey(now, calendar: calendar) }

    public var history: History {
        History(scans: scans, habits: habitLogs, goals: goals, calendar: calendar)
    }

    public var currentGoals: GoalSet { goals.goals(for: today) }
    public var todayStats: DayStats { history.stats(for: today) }
    public var todayLog: HabitLog? { habitLogs.first { $0.dayKey == today } }
    public var hasBaseline: Bool { scans.contains(where: \.isBaseline) || !scans.isEmpty }
    public var streak: Int { StreakCalculator.current(scanDays: history.scanDays, today: today, calendar: calendar) }

    public var lastSevenDays: [DayStats] {
        history.stats(from: today.adding(days: -6, calendar: calendar), through: today)
    }

    public var challengeStatuses: [ChallengeStatus] {
        ChallengeEngine.definitions(for: today.monthKey, in: challengeDefinitions).map {
            ChallengeEngine.status(of: $0, history: history, progressRecords: challengeRecords, today: today,
                                   calendar: calendar)
        }
    }

    public var nextMonthChallenges: [ChallengeDefinition] {
        ChallengeEngine.definitions(for: today.monthKey.adding(months: 1, calendar: calendar), in: challengeDefinitions)
    }

    public var awardDefinitions: [AwardDefinition] { AwardCatalog.all(challenges: challengeDefinitions) }

    public var awardContext: AwardEngine.Context {
        AwardEngine.Context(history: history, challenges: challengeDefinitions, challengeRecords: challengeRecords,
                            today: today)
    }

    public func earned(_ award: AwardDefinition) -> EarnedAward? {
        earnedAwards.first { $0.awardID == award.id }
    }

    public var latestEarnedAward: (AwardDefinition, EarnedAward)? {
        guard let latest = earnedAwards.max(by: { $0.earnedAt < $1.earnedAt }),
              let definition = awardDefinitions.first(where: { $0.id == latest.awardID }) else { return nil }
        return (definition, latest)
    }

    public var correlations: [Correlation] {
        let inputs = InsightEngine.inputs(history: history, through: today, cycleDays: cycleDays ?? [],
                                          cycleDataAvailable: cycleDays != nil)
        return InsightEngine.correlations(inputs)
    }

    public var dailyInsights: [InsightEngine.DailyInsight] {
        guard history.scanDays.count >= 7 else { return [] }
        let recent = scans.filter { !$0.isBaseline }.suffix(7).map(\.capturedAt)
        return InsightEngine.dailyInsights(correlations: correlations, recentScanTimes: Array(recent),
                                           reminder: settings.reminderTime, calendar: calendar)
    }

    public func scan(id: UUID) -> ScanRecord? { scans.first { $0.id == id } }

    public func uploadCardState(for scanID: UUID) -> UploadCardState {
        guard settings.drive.folder != nil else { return .localOnly }
        let jobs = uploadJobs.filter { $0.scanID == scanID }
        let scan = scan(id: scanID)
        if jobs.isEmpty {
            if scan?.syncState == .synced, let folder = settings.drive.folder, let scan {
                return .saved(fileName: DriveNaming.photoName(for: scan.capturedAt, timeZone: calendar.timeZone),
                              path: folder.path)
            }
            return .queued(count: 1)
        }
        if let failure = jobs.compactMap({ job -> UploadFailure? in
            if case .failed(let failure) = job.state { return failure }
            return nil
        }).first {
            return .failed(failure)
        }
        if jobs.allSatisfy(\.isDone), let folder = settings.drive.folder, let scan {
            return .saved(fileName: DriveNaming.photoName(for: scan.capturedAt, timeZone: calendar.timeZone),
                          path: folder.path)
        }
        if !isOnline { return .queued(count: pendingUploadCount) }
        let progress = jobs.reduce(0.0) { total, job in
            switch job.state {
            case .done: total + 1
            case .uploading(let p): total + p
            default: total
            }
        } / Double(jobs.count)
        return .uploading(progress: progress)
    }

    public var pendingUploadCount: Int {
        Set(uploadJobs.filter { !$0.isDone }.map(\.scanID)).count
    }

    public var needsDriveReconnect: Bool {
        if case .needsReconnect = settings.drive { return true }
        return false
    }

    // MARK: Lifecycle

    public func load() async {
        do {
            if let state = try await services.store.load() {
                apply(state)
            }
        } catch {
            lastError = "Couldn't load your data."
        }
        if goals.isEmpty { goals = [GoalSet(effectiveFrom: today)] }
        // A scan whose app was closed before "Done" still needs its scores file uploaded.
        for scan in scans where scan.driveJSONFileID == nil && !uploadJobs.contains(where: { $0.scanID == scan.id && $0.kind == .scores }) {
            if settings.drive.folder != nil && scan.syncState != .synced {
                uploadJobs.append(UploadJob(scanID: scan.id, kind: .scores,
                                            fileName: DriveNaming.scoresName(for: scan.capturedAt, timeZone: calendar.timeZone)))
            }
        }
        isLoaded = true
        await refreshFromHealth()
        await persist()
        Task { await processUploads() }
    }

    private func apply(_ state: PersistedState) {
        scans = state.scans.sorted { $0.capturedAt < $1.capturedAt }
        habitLogs = state.habitLogs
        goals = state.goals
        earnedAwards = state.earnedAwards
        challengeRecords = state.challengeRecords
        // Jobs interrupted mid-upload restart from pending.
        uploadJobs = state.uploadJobs.map { job in
            var job = job
            if case .uploading = job.state { job.state = .pending }
            return job
        }
        settings = state.settings
    }

    private var persistedState: PersistedState {
        PersistedState(scans: scans, habitLogs: habitLogs, goals: goals, earnedAwards: earnedAwards,
                       challengeRecords: challengeRecords, uploadJobs: uploadJobs, settings: settings)
    }

    public func persist() async {
        do {
            try await services.store.save(persistedState)
        } catch {
            lastError = "Couldn't save your data."
        }
        await services.store.writeWidgetSnapshot(widgetSnapshot)
        WidgetReloader.reload()
    }

    public var widgetSnapshot: WidgetSnapshot {
        let stats = todayStats
        let rings = stats.rings
        return WidgetSnapshot(dayKey: today, score: stats.score, deltaVsYesterday: history.deltaVsPrevious(for: today),
                              dePuffProgress: rings.dePuff, scanProgress: rings.scan, habitsProgress: rings.habits,
                              scansToday: stats.scanCount, habitsLogged: stats.habitCount,
                              habitsGoal: stats.goals.habitsPerDay, streakDays: streak, updatedAt: now)
    }

    // MARK: Onboarding & account

    public func setOnboardingStep(_ step: OnboardingStep) {
        settings.onboardingStep = step
        Task { await persist() }
    }

    public func signedIn(_ profile: UserProfile) {
        settings.profile = profile
        settings.onboardingStep = .driveLimitedAccess
        Task { await persist() }
    }

    /// "Use without an account": scans stay on this iPhone; Drive can be connected later in Profile.
    public func useLocally() {
        settings.profile = UserProfile(displayName: "You", email: nil, provider: .local)
        settings.drive = .skipped
        settings.onboardingStep = .permissions
        Task { await persist() }
    }

    public func connectDrive(folder: DriveFolderRef, email: String?) {
        settings.drive = .connected(folder)
        if let email, settings.profile?.email == nil { settings.profile?.email = email }
        // Anything captured while Drive was off gets queued now.
        for scan in scans where scan.syncState != .synced {
            enqueueUploads(for: scan, includeScores: true)
        }
        Task {
            await persist()
            await processUploads()
        }
    }

    public func skipDrive() {
        settings.drive = .skipped
        Task { await persist() }
    }

    public func disconnectDrive() {
        settings.drive = .notConnected
        uploadJobs.removeAll()
        Task { await persist() }
    }

    public func markDriveNeedsReconnect() {
        if let folder = settings.drive.folder { settings.drive = .needsReconnect(folder) }
    }

    public func signOut(deleteLocalData: Bool) async {
        await services.auth.signOut()
        if deleteLocalData {
            await deleteAllData(trashDriveFiles: false)
        } else {
            settings.profile = nil
            settings.onboardingStep = .signIn
            await persist()
        }
    }

    public func deleteAllData(trashDriveFiles: Bool) async {
        try? await services.photos.deleteAll()
        try? await services.store.deleteAll()
        await services.notifications.cancelDailyReminder()
        await services.notifications.cancelStreakSaver()
        scans = []
        habitLogs = []
        goals = [GoalSet(effectiveFrom: today)]
        earnedAwards = []
        challengeRecords = []
        uploadJobs = []
        awardQueue = []
        settings = UserSettings()
        await services.auth.signOut()
        await persist()
    }

    // MARK: Settings

    public func updateSettings(_ change: (inout UserSettings) -> Void) {
        let before = settings
        change(&settings)
        let after = settings
        Task {
            if before.reminderEnabled != after.reminderEnabled || before.reminderTime != after.reminderTime {
                if after.reminderEnabled {
                    await services.notifications.scheduleDailyReminder(at: after.reminderTime)
                } else {
                    await services.notifications.cancelDailyReminder()
                }
            }
            if after.healthSyncEnabled && !before.healthSyncEnabled {
                try? await services.health.requestAuthorization()
                await refreshFromHealth()
            }
            await persist()
        }
    }

    public func updateGoals(_ newGoals: GoalSet) {
        var goalSet = newGoals
        goalSet.effectiveFrom = today
        goals.removeAll { $0.effectiveFrom == today }
        goals.append(goalSet)
        afterActivityChange()
    }

    public func joinChallenge(_ id: String) {
        guard !challengeRecords.contains(where: { $0.challengeID == id }) else { return }
        challengeRecords.append(ChallengeProgress(challengeID: id, joinedAt: now))
        afterActivityChange()
    }

    // MARK: Habits

    public func logHabit(_ update: (inout HabitLog) -> Void, kind: HabitKind) {
        var log = todayLog ?? HabitLog(dayKey: today)
        update(&log)
        log.sources[kind] = .manual
        habitLogs.removeAll { $0.dayKey == today }
        habitLogs.append(log)
        afterActivityChange()
    }

    public func clearHabit(_ kind: HabitKind) {
        logHabit({ log in
            switch kind {
            case .water: log.waterLiters = nil
            case .sleep: log.sleepHours = nil
            case .salt: log.salt = nil
            case .alcohol: log.alcohol = nil
            }
            log.sources[kind] = nil
        }, kind: kind)
    }

    /// Pre-fills today's quick log from Apple Health without overwriting manual values.
    public func refreshFromHealth() async {
        guard settings.healthSyncEnabled, services.health.isAvailable else { return }
        let day = today
        let sleep = await services.health.sleepHours(endingOn: day)
        let water = await services.health.waterLiters(on: day)
        cycleDays = await services.health.cycleDays(from: day.adding(days: -30, calendar: calendar), through: day)
        var log = todayLog ?? HabitLog(dayKey: day)
        var changed = false
        if let sleep, log.sources[.sleep] != .manual {
            log.sleepHours = (sleep * 2).rounded() / 2
            log.sources[.sleep] = .health
            changed = true
        }
        if let water, water > 0, log.sources[.water] != .manual {
            log.waterLiters = water
            log.sources[.water] = .health
            changed = true
        }
        if changed {
            habitLogs.removeAll { $0.dayKey == day }
            habitLogs.append(log)
        }
    }

    // MARK: Scans

    /// Measures, scores and stores a capture. Retakes on the same day replace the day's scan.
    public func recordScan(_ capture: CapturedFace, isBaseline: Bool) async throws -> ScanRecord {
        let raw = try await services.analyzer.measure(capture)
        let history = self.history
        let baselineRaw = isBaseline ? raw : (history.baseline?.raw ?? raw)
        let reference = ScoringEngine.reference(baseline: baselineRaw,
                                                history: history.scans.filter { !$0.lowConfidence }.map(\.raw))
        let result = ScoringEngine.score(raw: raw, quality: capture.quality, reference: reference)
        let id = UUID()
        let names = try await services.photos.save(jpeg: capture.jpegData, scanID: id)
        let day = DayKey(capture.capturedAt, calendar: calendar)
        let replaced = scans.filter { $0.dayKey == day && !isBaseline }
        var record = ScanRecord(id: id, capturedAt: capture.capturedAt, dayKey: day, score: result.overall,
                                zones: result.zones, raw: raw, quality: capture.quality,
                                lowConfidence: result.lowConfidence, isBaseline: isBaseline || scans.isEmpty,
                                photoFileName: names.photo, thumbnailFileName: names.thumbnail,
                                faceTransform: capture.faceTransform, tags: todayLog?.suggestedTags ?? [],
                                syncState: settings.drive.folder == nil ? .local : .queued)
        // Retakes keep a single scan per day.
        if !replaced.isEmpty {
            let replacedIDs = Set(replaced.map(\.id))
            scans.removeAll { replacedIDs.contains($0.id) }
            uploadJobs.removeAll { replacedIDs.contains($0.scanID) && !$0.isDone }
        }
        if record.isBaseline { record.lowConfidence = false }
        scans.append(record)
        scans.sort { $0.capturedAt < $1.capturedAt }
        if settings.drive.folder != nil {
            enqueueUploads(for: record, includeScores: false)
        }
        // Onboarding completes when the user taps Done on the baseline result (see OnboardingFlow),
        // so the result screen isn't torn down mid-flow.
        afterActivityChange()
        Task { await processUploads() }
        return record
    }

    /// Called when the user taps Done on the result: saves notes/tags and uploads the scores file.
    public func finalizeScan(id: UUID, notes: String, tags: [String]) {
        guard let index = scans.firstIndex(where: { $0.id == id }) else { return }
        scans[index].notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        scans[index].tags = tags
        if settings.drive.folder != nil,
           !uploadJobs.contains(where: { $0.scanID == id && $0.kind == .scores }) {
            uploadJobs.append(UploadJob(scanID: id, kind: .scores,
                                        fileName: DriveNaming.scoresName(for: scans[index].capturedAt, timeZone: calendar.timeZone)))
        }
        Task {
            await persist()
            await processUploads()
        }
    }

    public func deleteScan(id: UUID) {
        scans.removeAll { $0.id == id }
        uploadJobs.removeAll { $0.scanID == id }
        afterActivityChange()
    }

    private func enqueueUploads(for scan: ScanRecord, includeScores: Bool) {
        if scan.drivePhotoFileID == nil, !uploadJobs.contains(where: { $0.scanID == scan.id && $0.kind == .photo }) {
            uploadJobs.append(UploadJob(scanID: scan.id, kind: .photo,
                                        fileName: DriveNaming.photoName(for: scan.capturedAt, timeZone: calendar.timeZone)))
        }
        if includeScores, scan.driveJSONFileID == nil,
           !uploadJobs.contains(where: { $0.scanID == scan.id && $0.kind == .scores }) {
            uploadJobs.append(UploadJob(scanID: scan.id, kind: .scores,
                                        fileName: DriveNaming.scoresName(for: scan.capturedAt, timeZone: calendar.timeZone)))
        }
    }

    // MARK: Uploads

    public static let backoff: [TimeInterval] = [2, 8, 30, 120]

    /// Retries failed jobs immediately (user tapped Retry).
    public func retryUploads() {
        for index in uploadJobs.indices {
            if case .failed = uploadJobs[index].state {
                uploadJobs[index].state = .pending
                uploadJobs[index].nextAttemptAt = nil
            }
        }
        Task { await processUploads() }
    }

    /// Uploads pending jobs one at a time. Transient failures back off; auth and folder
    /// problems stop and surface a Reconnect / Choose Folder action.
    public func processUploads() async {
        guard !isProcessingUploads, isOnline, let folder = settings.drive.folder, !needsDriveReconnect else { return }
        isProcessingUploads = true
        defer { isProcessingUploads = false }

        while let index = uploadJobs.firstIndex(where: { job in
            if case .pending = job.state { return (job.nextAttemptAt ?? .distantPast) <= now }
            return false
        }) {
            let job = uploadJobs[index]
            guard let scan = scan(id: job.scanID) else {
                uploadJobs.remove(at: index)
                continue
            }
            setJobState(job.id, .uploading(progress: 0))
            do {
                let (data, mime) = try await payload(for: job, scan: scan)
                let jobID = job.id
                let fileID = try await services.drive.upload(
                    data: data, name: job.fileName, mimeType: mime, parentID: folder.id,
                    appProperties: ["scanID": scan.id.uuidString, "kind": job.kind.rawValue]
                ) { [weak self] progress in
                    Task { @MainActor in self?.setJobProgress(jobID, progress) }
                }
                setJobState(job.id, .done(fileID: fileID))
                markUploaded(scanID: scan.id, kind: job.kind, fileID: fileID)
                settings.lastSyncAt = now
            } catch let DriveError.failure(failure) {
                handleUploadFailure(jobID: job.id, failure: failure)
                if !failure.isTransient { break }
            } catch {
                handleUploadFailure(jobID: job.id, failure: .unknown)
                break
            }
            await persist()
        }
        // Completed jobs are no longer needed once both files for a scan are up.
        let completedScans = Set(uploadJobs.map(\.scanID)).filter { id in
            let jobs = uploadJobs.filter { $0.scanID == id }
            return jobs.count >= 2 && jobs.allSatisfy(\.isDone)
        }
        if !completedScans.isEmpty {
            // Keep them briefly so the result screen can show "Saved"; prune on next launch.
            uploadJobs.removeAll { completedScans.contains($0.scanID) && $0.createdAt < now.addingTimeInterval(-600) }
        }
        await persist()
        scheduleBackoffRetry()
    }

    private func payload(for job: UploadJob, scan: ScanRecord) async throws -> (Data, String) {
        switch job.kind {
        case .photo:
            guard let name = scan.photoFileName,
                  let original = await services.photos.data(named: name) else {
                throw DriveError.failure(.unknown)
            }
            let quality = settings.uploadQuality
            let data = quality == .original ? original
                : (ImageUtilities.downsampledJPEG(original, maxPixelSize: quality.maxPixelSize, quality: quality.jpegQuality) ?? original)
            return (data, "image/jpeg")
        case .scores:
            let history = self.history
            let baseline = history.baseline
            let export = ScanExport(scan: scan, baselineID: baseline?.id,
                                    deltaVsYesterday: history.deltaVsPrevious(for: scan.dayKey),
                                    deltaVsBaseline: baseline.map { scan.score - $0.score },
                                    habits: history.habits[scan.dayKey], appVersion: AppInfo.versionString,
                                    timeZone: calendar.timeZone)
            return (try export.encoded(), "application/json")
        }
    }

    private func handleUploadFailure(jobID: UUID, failure: UploadFailure) {
        guard let index = uploadJobs.firstIndex(where: { $0.id == jobID }) else { return }
        if failure.isTransient && uploadJobs[index].retryCount < Self.backoff.count {
            let delay = Self.backoff[uploadJobs[index].retryCount]
            uploadJobs[index].retryCount += 1
            uploadJobs[index].nextAttemptAt = now.addingTimeInterval(delay)
            uploadJobs[index].state = .pending
            if failure == .network { isOnline = false }
        } else {
            uploadJobs[index].state = .failed(failure)
            if failure == .authExpired { markDriveNeedsReconnect() }
        }
        if let scanIndex = scans.firstIndex(where: { $0.id == uploadJobs[index].scanID }) {
            scans[scanIndex].syncState = failure.isTransient ? .queued : .failed
        }
    }

    private func scheduleBackoffRetry() {
        guard let next = uploadJobs.compactMap({ job -> Date? in
            if case .pending = job.state { return job.nextAttemptAt }
            return nil
        }).min() else { return }
        let delay = max(0.5, next.timeIntervalSince(now))
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            await self?.processUploads()
        }
    }

    private func setJobState(_ id: UUID, _ state: UploadState) {
        guard let index = uploadJobs.firstIndex(where: { $0.id == id }) else { return }
        uploadJobs[index].state = state
        if case .uploading = state,
           let scanIndex = scans.firstIndex(where: { $0.id == uploadJobs[index].scanID }) {
            scans[scanIndex].syncState = .uploading
        }
    }

    private func setJobProgress(_ id: UUID, _ progress: Double) {
        guard let index = uploadJobs.firstIndex(where: { $0.id == id }),
              case .uploading = uploadJobs[index].state else { return }
        uploadJobs[index].state = .uploading(progress: progress)
    }

    private func markUploaded(scanID: UUID, kind: UploadKind, fileID: String) {
        guard let index = scans.firstIndex(where: { $0.id == scanID }) else { return }
        switch kind {
        case .photo: scans[index].drivePhotoFileID = fileID
        case .scores: scans[index].driveJSONFileID = fileID
        }
        if scans[index].drivePhotoFileID != nil && scans[index].driveJSONFileID != nil {
            scans[index].syncState = .synced
        }
    }

    /// Rebuilds history from the JSON files in the connected Drive folder (new device).
    public func restoreFromDrive() async throws -> Int {
        guard let folder = settings.drive.folder else { return 0 }
        let files = try await services.drive.listScoreFiles(folderID: folder.id)
        var restored = 0
        for file in files {
            let data = try await services.drive.download(fileID: file.id)
            guard let export = try? ScanExport.decode(data), var record = export.makeRecord(timeZone: calendar.timeZone),
                  !scans.contains(where: { $0.id == record.id }) else { continue }
            record.driveJSONFileID = file.id
            scans.append(record)
            restored += 1
        }
        scans.sort { $0.capturedAt < $1.capturedAt }
        afterActivityChange()
        return restored
    }

    // MARK: Awards & celebrations

    public func dequeueAward() {
        guard !awardQueue.isEmpty else { return }
        let award = awardQueue.removeFirst()
        if let index = earnedAwards.firstIndex(where: { $0.awardID == award.id }) {
            earnedAwards[index].seen = true
        }
        Task { await persist() }
    }

    public func dismissAllRingsClosed() {
        showAllRingsClosed = false
    }

    /// Re-evaluates awards and celebrations after any change that can move a ring.
    private func afterActivityChange() {
        let ringsBefore = settings.lastCelebrationDay == today
        let newAwards = AwardEngine.evaluate(awardDefinitions, context: awardContext, earned: earnedAwards, now: now)
        if !newAwards.isEmpty {
            earnedAwards += newAwards
            let definitions = newAwards.compactMap { earned in awardDefinitions.first { $0.id == earned.awardID } }
            awardQueue += definitions
            Task {
                for definition in definitions { await services.notifications.notifyAward(title: definition.title) }
            }
        }
        if todayStats.rings.allClosed && !ringsBefore {
            settings.lastCelebrationDay = today
            showAllRingsClosed = true
        }
        Task {
            await updateStreakSaver()
            await persist()
        }
    }

    private func updateStreakSaver() async {
        guard settings.streakSaverEnabled else { return }
        if history.scanDays.contains(today) {
            await services.notifications.cancelStreakSaver()
        } else if streak >= 3 {
            await services.notifications.scheduleStreakSaver(streak: streak, on: today)
        }
    }
}

public enum AppInfo {
    public static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    public static var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}
