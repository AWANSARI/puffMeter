import Foundation

// Fake services for previews, unit tests and `-UITestMode`. They behave like the real ones
// (latency, errors) closely enough to exercise every UI state.

@MainActor
public final class MockAuthService: AuthService {
    public var profile = UserProfile(displayName: "Alex Morgan", email: "alex.morgan@gmail.com", provider: .google)
    public var signedIn: Bool
    public var failNextSignIn: AuthError?

    public init(signedIn: Bool = false) { self.signedIn = signedIn }

    public func restorePreviousSignIn() async -> UserProfile? { signedIn ? profile : nil }

    public func signInWithGoogle() async throws -> UserProfile {
        try await Task.sleep(for: .milliseconds(600))
        if let error = failNextSignIn {
            failNextSignIn = nil
            throw error
        }
        signedIn = true
        return profile
    }

    public func signInWithApple() async throws -> UserProfile {
        try await Task.sleep(for: .milliseconds(400))
        signedIn = true
        return UserProfile(displayName: profile.displayName, email: nil, provider: .apple)
    }

    public func requestDriveAccess() async throws -> String? {
        try await Task.sleep(for: .milliseconds(400))
        return profile.email
    }

    public func signOut() async { signedIn = false }

    public func driveAccessToken() async throws -> String { "mock-token" }
}

public actor MockDriveService: DriveService {
    public var folders: [String: [DriveFolder]]
    public var uploads: [String: Data] = [:]
    public var failure: UploadFailure?
    public var simulatedLatency: Duration

    public init(simulatedLatency: Duration = .milliseconds(500)) {
        self.simulatedLatency = simulatedLatency
        folders = ["root": [DriveFolder(id: "sample-folder", name: "PuffyMeter Daily"),
                            DriveFolder(id: "personal", name: "Personal"),
                            DriveFolder(id: "photos", name: "Photos"),
                            DriveFolder(id: "wellness", name: "Wellness")],
                   "personal": [DriveFolder(id: "journal", name: "Journal")]]
    }

    public func setFailure(_ failure: UploadFailure?) { self.failure = failure }

    public func listFolders(parentID: String?, query: String?) async throws -> [DriveFolder] {
        try await Task.sleep(for: simulatedLatency)
        let all = folders[parentID ?? "root"] ?? []
        guard let query, !query.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    public func createFolder(name: String, parentID: String?) async throws -> DriveFolder {
        try await Task.sleep(for: simulatedLatency)
        let folder = DriveFolder(id: UUID().uuidString, name: name)
        folders[parentID ?? "root", default: []].append(folder)
        folders[parentID ?? "root"]?.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        return folder
    }

    public func folderExists(id: String) async throws -> Bool { true }

    public func upload(data: Data, name: String, mimeType: String, parentID: String,
                       appProperties: [String: String], progress: @Sendable @escaping (Double) -> Void) async throws -> String {
        for step in 1...10 {
            try await Task.sleep(for: .milliseconds(120))
            progress(Double(step) / 10 * 0.99)
        }
        if let failure { throw DriveError.failure(failure) }
        let id = "mock-\(UUID().uuidString.prefix(8))"
        uploads[id] = data
        progress(1)
        return id
    }

    public func fileCount(folderID: String) async throws -> Int { uploads.count + 36 }

    public func listScoreFiles(folderID: String) async throws -> [DriveFolder] { [] }

    public func download(fileID: String) async throws -> Data {
        guard let data = uploads[fileID] else { throw DriveError.failure(.folderMissing) }
        return data
    }
}

public struct MockHealthService: HealthService {
    public init() {}
    public var isAvailable: Bool { true }
    public func requestAuthorization() async throws {}
    public func sleepHours(endingOn day: DayKey) async -> Double? { 8 }
    public func waterLiters(on day: DayKey) async -> Double? { nil }
    public func cycleDays(from start: DayKey, through end: DayKey) async -> Set<DayKey>? { nil }
}

public struct MockNotificationService: NotificationService {
    public init() {}
    public func authorizationStatus() async -> NotificationAuthorization { .authorized }
    public func requestAuthorization() async -> Bool { true }
    public func scheduleDailyReminder(at time: ReminderTime) async {}
    public func cancelDailyReminder() async {}
    public func scheduleStreakSaver(streak: Int, on day: DayKey) async {}
    public func cancelStreakSaver() async {}
    public func notifyAward(title: String) async {}
}

public struct MockAppLockService: AppLockService {
    public init() {}
    public var biometryName: String { "Face ID" }
    public func authenticate(reason: String) async -> Bool { true }
}

@MainActor
public final class MockCameraPermission: CameraPermissionService {
    public var current: CameraAuthorization
    public init(current: CameraAuthorization = .notDetermined) { self.current = current }
    public func status() -> CameraAuthorization { current }
    public func request() async -> Bool {
        current = .authorized
        return true
    }
}

/// Deterministic analyzer: derives metrics from the capture's bytes so retakes vary slightly
/// but the same image always gives the same result.
public struct FixtureFaceAnalyzer: FaceAnalyzing {
    public var base: RawFaceMetrics

    public init(base: RawFaceMetrics = RawFaceMetrics(underEyes: 0.338, cheeks: 0.929, jawline: 0.826)) {
        self.base = base
    }

    public func measure(_ capture: CapturedFace) async throws -> RawFaceMetrics {
        if let raw = capture.raw { return raw }
        try await Task.sleep(for: .milliseconds(300))
        let seed = capture.jpegData.prefix(4096).reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        func jitter(_ shift: UInt64) -> Double { Double((seed >> shift) & 0xFF) / 255.0 * 0.01 - 0.005 }
        return RawFaceMetrics(underEyes: base.underEyes + jitter(0), cheeks: base.cheeks + jitter(8),
                              jawline: base.jawline + jitter(16))
    }
}

public actor InMemoryPhotoStore: PhotoStore {
    private var images: [String: Data] = [:]
    public init() {}

    public func save(jpeg: Data, scanID: UUID) throws -> (photo: String, thumbnail: String) {
        let name = "\(scanID.uuidString).jpg"
        images[name] = jpeg
        return (name, name)
    }

    public nonisolated func url(for fileName: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    }

    public func image(named fileName: String) -> PlatformImage? {
        images[fileName].flatMap { PlatformImage(data: $0) }
    }

    public func data(named fileName: String) -> Data? { images[fileName] }

    public func deleteAll() { images = [:] }
}

public extension Services {
    /// Fully mocked services seeded with the mockup sample data.
    @MainActor
    static func mock(seeded: Bool = true, signedIn: Bool = true) -> Services {
        Services(auth: MockAuthService(signedIn: signedIn), drive: MockDriveService(), health: MockHealthService(),
                 notifications: MockNotificationService(), photos: InMemoryPhotoStore(),
                 appLock: MockAppLockService(), camera: MockCameraPermission(current: seeded ? .authorized : .notDetermined),
                 analyzer: FixtureFaceAnalyzer(), store: InMemoryStateStore(state: seeded ? SampleData.state : nil))
    }
}
