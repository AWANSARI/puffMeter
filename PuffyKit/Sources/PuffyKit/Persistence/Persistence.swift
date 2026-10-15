import Foundation

/// Everything PuffyMeter stores locally. Data volume is small (one scan per day), so a single
/// Codable document written atomically is simpler and more portable than a database and can
/// be shared with the widget through the App Group container.
public struct PersistedState: Codable, Hashable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var scans: [ScanRecord]
    public var habitLogs: [HabitLog]
    public var goals: [GoalSet]
    public var earnedAwards: [EarnedAward]
    public var challengeRecords: [ChallengeProgress]
    public var uploadJobs: [UploadJob]
    public var settings: UserSettings

    public init(version: Int = PersistedState.currentVersion, scans: [ScanRecord] = [],
                habitLogs: [HabitLog] = [], goals: [GoalSet] = [], earnedAwards: [EarnedAward] = [],
                challengeRecords: [ChallengeProgress] = [], uploadJobs: [UploadJob] = [],
                settings: UserSettings = UserSettings()) {
        self.version = version
        self.scans = scans
        self.habitLogs = habitLogs
        self.goals = goals
        self.earnedAwards = earnedAwards
        self.challengeRecords = challengeRecords
        self.uploadJobs = uploadJobs
        self.settings = settings
    }
}

public protocol StateStore: Sendable {
    func load() async throws -> PersistedState?
    func save(_ state: PersistedState) async throws
    func writeWidgetSnapshot(_ snapshot: WidgetSnapshot) async
    func deleteAll() async throws
}

public enum AppGroup {
    /// Comes from the `PuffyAppGroup` Info.plist key (set per developer team in Local.xcconfig).
    public static let identifier = Bundle.main.object(forInfoDictionaryKey: "PuffyAppGroup") as? String
        ?? "group.com.puffymeter.shared"

    /// The shared container when the entitlement exists, otherwise Application Support
    /// (unit tests, previews, `swift run`).
    public static func containerURL() -> URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("PuffyMeter", isDirectory: true)
    }

    public static var widgetSnapshotURL: URL { containerURL().appendingPathComponent("widget-snapshot.json") }

    public static func readWidgetSnapshot() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: widgetSnapshotURL) else { return nil }
        return try? JSONDecoder.puffy.decode(WidgetSnapshot.self, from: data)
    }
}

public actor FileStateStore: StateStore {
    private let directory: URL
    private var stateURL: URL { directory.appendingPathComponent("state.json") }

    public init(directory: URL = AppGroup.containerURL()) {
        self.directory = directory
    }

    public func load() throws -> PersistedState? {
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return nil }
        let data = try Data(contentsOf: stateURL)
        return try JSONDecoder.puffy.decode(PersistedState.self, from: data)
    }

    public func save(_ state: PersistedState) throws {
        try ensureDirectory()
        let data = try JSONEncoder.puffy.encode(state)
        try data.write(to: stateURL, options: Self.writeOptions)
    }

    public func writeWidgetSnapshot(_ snapshot: WidgetSnapshot) {
        guard (try? ensureDirectory()) != nil, let data = try? JSONEncoder.puffy.encode(snapshot) else { return }
        // The widget must be able to read this while the device is locked, so no `.complete` protection.
        try? data.write(to: directory.appendingPathComponent("widget-snapshot.json"), options: .atomic)
    }

    public func deleteAll() throws {
        for name in ["state.json", "widget-snapshot.json"] {
            let url = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private static var writeOptions: Data.WritingOptions {
        #if os(iOS)
        [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        #else
        [.atomic]
        #endif
    }
}

/// In-memory store for previews and tests.
public actor InMemoryStateStore: StateStore {
    public private(set) var state: PersistedState?
    public private(set) var snapshot: WidgetSnapshot?

    public init(state: PersistedState? = nil) { self.state = state }

    public func load() -> PersistedState? { state }
    public func save(_ state: PersistedState) { self.state = state }
    public func writeWidgetSnapshot(_ snapshot: WidgetSnapshot) { self.snapshot = snapshot }
    public func deleteAll() { state = nil; snapshot = nil }
}

public extension JSONEncoder {
    static var puffy: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

public extension JSONDecoder {
    static var puffy: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
