import Foundation

// Protocols for everything that touches the outside world. Real implementations that need
// iOS-only frameworks (GoogleSignIn, HealthKit, ARKit) live in the app target; mocks live
// here for previews, tests and `-UITestMode`.

public enum AuthError: Error, Equatable, Sendable {
    case cancelled
    case network
    case notSignedIn
    case driveScopeDenied
    case other(String)

    public var message: String? {
        switch self {
        case .cancelled: nil
        case .network: "Couldn't reach Google. Check your connection and try again."
        case .notSignedIn: "Please sign in again."
        case .driveScopeDenied: "PuffyMeter needs permission to save to one Drive folder."
        case .other(let message): message
        }
    }
}

@MainActor
public protocol AuthService: AnyObject {
    func restorePreviousSignIn() async -> UserProfile?
    func signInWithGoogle() async throws -> UserProfile
    func signInWithApple() async throws -> UserProfile
    /// Incrementally adds the `drive.file` scope (and signs in with Google if the account is Apple-only).
    func requestDriveAccess() async throws -> String?
    func signOut() async
    /// A fresh OAuth access token for Drive, refreshed if needed.
    func driveAccessToken() async throws -> String
}

public struct DriveFolder: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public enum DriveError: Error, Equatable, Sendable {
    case failure(UploadFailure)
    case invalidResponse
}

public protocol DriveService: Sendable {
    /// Folders the app can see under `parentID` (nil = My Drive root). With the `drive.file`
    /// scope these are folders PuffyMeter created or the user opened via the Google Picker.
    func listFolders(parentID: String?, query: String?) async throws -> [DriveFolder]
    func createFolder(name: String, parentID: String?) async throws -> DriveFolder
    func folderExists(id: String) async throws -> Bool
    func upload(data: Data, name: String, mimeType: String, parentID: String,
                appProperties: [String: String], progress: @Sendable @escaping (Double) -> Void) async throws -> String
    func fileCount(folderID: String) async throws -> Int
    /// JSON score files in the folder, for "Restore history from Drive".
    func listScoreFiles(folderID: String) async throws -> [DriveFolder]
    func download(fileID: String) async throws -> Data
}

public protocol HealthService: Sendable {
    var isAvailable: Bool { get }
    func requestAuthorization() async throws
    func sleepHours(endingOn day: DayKey) async -> Double?
    func waterLiters(on day: DayKey) async -> Double?
    func cycleDays(from start: DayKey, through end: DayKey) async -> Set<DayKey>?
}

public enum NotificationAuthorization: Sendable {
    case notDetermined, denied, authorized
}

public protocol NotificationService: Sendable {
    func authorizationStatus() async -> NotificationAuthorization
    func requestAuthorization() async -> Bool
    func scheduleDailyReminder(at time: ReminderTime) async
    func cancelDailyReminder() async
    func scheduleStreakSaver(streak: Int, on day: DayKey) async
    func cancelStreakSaver() async
    func notifyAward(title: String) async
}

public protocol PhotoStore: Sendable {
    /// Saves a JPEG and a ~300 px thumbnail; returns their file names.
    func save(jpeg: Data, scanID: UUID) async throws -> (photo: String, thumbnail: String)
    func url(for fileName: String) -> URL
    func image(named fileName: String) async -> PlatformImage?
    func data(named fileName: String) async -> Data?
    func deleteAll() async throws
}

public protocol AppLockService: Sendable {
    var biometryName: String { get }
    func authenticate(reason: String) async -> Bool
}

public enum CameraAuthorization: Sendable {
    case notDetermined, denied, authorized
}

@MainActor
public protocol CameraPermissionService: AnyObject {
    func status() -> CameraAuthorization
    func request() async -> Bool
}

/// The output of a capture, handed to the analyzer.
public struct CapturedFace: @unchecked Sendable {
    public var jpegData: Data
    public var capturedAt: Date
    public var quality: ScanQuality
    /// Raw metrics measured live (ARKit) or nil if the analyzer must measure from the image.
    public var raw: RawFaceMetrics?
    public var faceTransform: [Float]?

    public init(jpegData: Data, capturedAt: Date, quality: ScanQuality, raw: RawFaceMetrics?, faceTransform: [Float]?) {
        self.jpegData = jpegData
        self.capturedAt = capturedAt
        self.quality = quality
        self.raw = raw
        self.faceTransform = faceTransform
    }
}

public protocol FaceAnalyzing: Sendable {
    func measure(_ capture: CapturedFace) async throws -> RawFaceMetrics
}

public struct Services {
    public var auth: AuthService
    public var drive: DriveService
    public var health: HealthService
    public var notifications: NotificationService
    public var photos: PhotoStore
    public var appLock: AppLockService
    public var camera: CameraPermissionService
    public var analyzer: FaceAnalyzing
    public var store: StateStore

    public init(auth: AuthService, drive: DriveService, health: HealthService, notifications: NotificationService,
                photos: PhotoStore, appLock: AppLockService, camera: CameraPermissionService,
                analyzer: FaceAnalyzing, store: StateStore) {
        self.auth = auth
        self.drive = drive
        self.health = health
        self.notifications = notifications
        self.photos = photos
        self.appLock = appLock
        self.camera = camera
        self.analyzer = analyzer
        self.store = store
    }
}
