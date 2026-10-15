import Foundation

// MARK: - Habits

public enum HabitKind: String, Codable, CodingKeyRepresentable, CaseIterable, Sendable, Identifiable {
    case water, sleep, salt, alcohol
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .water: "Water"
        case .sleep: "Sleep"
        case .salt: "Salt"
        case .alcohol: "Alcohol"
        }
    }

    public var symbol: String {
        switch self {
        case .water: "drop"
        case .sleep: "moon"
        case .salt: "fork.knife"
        case .alcohol: "wineglass"
        }
    }
}

public enum SaltLevel: String, Codable, CaseIterable, Sendable, Identifiable {
    case low, medium, high
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public enum AlcoholLevel: String, Codable, CaseIterable, Sendable, Identifiable {
    case none, one, twoPlus
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .none: "None"
        case .one: "1 drink"
        case .twoPlus: "2+ drinks"
        }
    }
}

public enum HabitSource: String, Codable, Sendable {
    case manual, health
}

public struct HabitLog: Codable, Hashable, Sendable {
    public var dayKey: DayKey
    public var waterLiters: Double?
    public var sleepHours: Double?
    public var salt: SaltLevel?
    public var alcohol: AlcoholLevel?
    public var sources: [HabitKind: HabitSource]

    public init(dayKey: DayKey, waterLiters: Double? = nil, sleepHours: Double? = nil,
                salt: SaltLevel? = nil, alcohol: AlcoholLevel? = nil,
                sources: [HabitKind: HabitSource] = [:]) {
        self.dayKey = dayKey
        self.waterLiters = waterLiters
        self.sleepHours = sleepHours
        self.salt = salt
        self.alcohol = alcohol
        self.sources = sources
    }

    public func isLogged(_ habit: HabitKind) -> Bool {
        switch habit {
        case .water: waterLiters != nil
        case .sleep: sleepHours != nil
        case .salt: salt != nil
        case .alcohol: alcohol != nil
        }
    }

    /// Each logged habit counts as one check-in toward the Habits ring.
    public var checkInCount: Int { HabitKind.allCases.filter(isLogged).count }

    /// Tags auto-suggested for a scan from today's quick log (e.g. "8h sleep", "Low salt").
    public var suggestedTags: [String] {
        var tags: [String] = []
        if let sleepHours { tags.append("\(Format.hours(sleepHours)) sleep") }
        if let salt { tags.append("\(salt.title) salt") }
        if let alcohol { tags.append(alcohol == .none ? "No alcohol" : alcohol.title) }
        if let waterLiters { tags.append("\(Format.liters(waterLiters)) water") }
        return tags
    }
}

// MARK: - Scans

public enum AnalysisMethod: String, Codable, Sendable {
    case arkit, vision, fixture
}

public struct ZoneScores: Codable, Hashable, Sendable {
    public var underEyes: Int
    public var cheeks: Int
    public var jawline: Int

    public init(underEyes: Int, cheeks: Int, jawline: Int) {
        self.underEyes = underEyes
        self.cheeks = cheeks
        self.jawline = jawline
    }

    public func value(for zone: FaceZone) -> Int {
        switch zone {
        case .underEyes: underEyes
        case .cheeks: cheeks
        case .jawline: jawline
        }
    }
}

public enum FaceZone: String, CaseIterable, Codable, Sendable, Identifiable {
    case underEyes, cheeks, jawline
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .underEyes: "Under-eyes"
        case .cheeks: "Cheeks"
        case .jawline: "Jawline"
        }
    }
}

/// Size-invariant raw measurements produced by the face analyzer (normalized by IPD).
public struct RawFaceMetrics: Codable, Hashable, Sendable {
    public var underEyes: Double
    public var cheeks: Double
    public var jawline: Double

    public init(underEyes: Double, cheeks: Double, jawline: Double) {
        self.underEyes = underEyes
        self.cheeks = cheeks
        self.jawline = jawline
    }

    public func value(for zone: FaceZone) -> Double {
        switch zone {
        case .underEyes: underEyes
        case .cheeks: cheeks
        case .jawline: jawline
        }
    }
}

public struct ScanQuality: Codable, Hashable, Sendable {
    /// 0...1, 1 = ideal even lighting.
    public var lighting: Double
    public var yawDeg: Double
    public var rollDeg: Double
    public var pitchDeg: Double
    /// 0...1, 1 = fully neutral expression.
    public var neutrality: Double
    public var method: AnalysisMethod
    public var manual: Bool

    public init(lighting: Double, yawDeg: Double, rollDeg: Double, pitchDeg: Double = 0,
                neutrality: Double, method: AnalysisMethod, manual: Bool = false) {
        self.lighting = lighting
        self.yawDeg = yawDeg
        self.rollDeg = rollDeg
        self.pitchDeg = pitchDeg
        self.neutrality = neutrality
        self.method = method
        self.manual = manual
    }

    /// Composite 0...1 used to flag low-confidence scores.
    public var composite: Double {
        let maxAngle = max(abs(yawDeg), abs(rollDeg), abs(pitchDeg))
        let pose = max(0, 1 - maxAngle / 20)
        return (lighting * 0.4 + neutrality * 0.3 + pose * 0.3).clamped(to: 0...1)
    }

    public static let ideal = ScanQuality(lighting: 0.9, yawDeg: 1, rollDeg: 0.5, neutrality: 0.95, method: .fixture)
}

public enum SyncState: String, Codable, Sendable {
    case local, queued, uploading, synced, failed
}

public struct ScanRecord: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var capturedAt: Date
    public var dayKey: DayKey
    public var score: Int
    public var zones: ZoneScores
    public var raw: RawFaceMetrics
    public var quality: ScanQuality
    public var lowConfidence: Bool
    public var isBaseline: Bool
    /// File name inside the app's scans directory (not an absolute path, which changes across installs).
    public var photoFileName: String?
    public var thumbnailFileName: String?
    /// Flattened 4x4 face-anchor transform used to align the ghost overlay and time-lapse.
    public var faceTransform: [Float]?
    public var notes: String
    public var tags: [String]
    public var drivePhotoFileID: String?
    public var driveJSONFileID: String?
    public var syncState: SyncState

    public init(id: UUID = UUID(), capturedAt: Date, dayKey: DayKey, score: Int, zones: ZoneScores,
                raw: RawFaceMetrics, quality: ScanQuality, lowConfidence: Bool = false,
                isBaseline: Bool = false, photoFileName: String? = nil, thumbnailFileName: String? = nil,
                faceTransform: [Float]? = nil, notes: String = "", tags: [String] = [],
                drivePhotoFileID: String? = nil, driveJSONFileID: String? = nil,
                syncState: SyncState = .local) {
        self.id = id
        self.capturedAt = capturedAt
        self.dayKey = dayKey
        self.score = score
        self.zones = zones
        self.raw = raw
        self.quality = quality
        self.lowConfidence = lowConfidence
        self.isBaseline = isBaseline
        self.photoFileName = photoFileName
        self.thumbnailFileName = thumbnailFileName
        self.faceTransform = faceTransform
        self.notes = notes
        self.tags = tags
        self.drivePhotoFileID = drivePhotoFileID
        self.driveJSONFileID = driveJSONFileID
        self.syncState = syncState
    }
}

// MARK: - Goals

public struct GoalSet: Codable, Hashable, Sendable {
    public var effectiveFrom: DayKey
    public var dePuffMax: Int
    public var scansPerDay: Int
    public var habitsPerDay: Int
    public var waterGoalLiters: Double

    public init(effectiveFrom: DayKey, dePuffMax: Int = 35, scansPerDay: Int = 1,
                habitsPerDay: Int = 4, waterGoalLiters: Double = 2) {
        self.effectiveFrom = effectiveFrom
        self.dePuffMax = dePuffMax
        self.scansPerDay = scansPerDay
        self.habitsPerDay = habitsPerDay
        self.waterGoalLiters = waterGoalLiters
    }

    public static let dePuffRange = 10...90
    public static let scansRange = 1...3
    public static let habitsRange = 1...4
}

public extension Array where Element == GoalSet {
    /// Goals apply from their effective day forward; past days keep the goals they had.
    func goals(for day: DayKey) -> GoalSet {
        let sorted = self.sorted { $0.effectiveFrom < $1.effectiveFrom }
        return sorted.last { $0.effectiveFrom <= day } ?? sorted.first ?? GoalSet(effectiveFrom: day)
    }
}

// MARK: - Awards & challenges

public struct EarnedAward: Codable, Hashable, Sendable, Identifiable {
    public var awardID: String
    public var earnedAt: Date
    public var seen: Bool
    public var id: String { awardID }

    public init(awardID: String, earnedAt: Date, seen: Bool = false) {
        self.awardID = awardID
        self.earnedAt = earnedAt
        self.seen = seen
    }
}

public struct ChallengeProgress: Codable, Hashable, Sendable {
    public var challengeID: String
    public var joinedAt: Date?
    public var completedAt: Date?

    public init(challengeID: String, joinedAt: Date? = nil, completedAt: Date? = nil) {
        self.challengeID = challengeID
        self.joinedAt = joinedAt
        self.completedAt = completedAt
    }
}

// MARK: - Uploads

public enum UploadKind: String, Codable, Sendable {
    case photo, scores
}

public enum UploadFailure: String, Codable, Sendable, Error {
    case network, authExpired, folderMissing, quotaExceeded, server, unknown

    public var isTransient: Bool {
        switch self {
        case .network, .server: true
        case .authExpired, .folderMissing, .quotaExceeded, .unknown: false
        }
    }

    public var message: String {
        switch self {
        case .network: "Couldn't reach Google Drive."
        case .authExpired: "Google Drive session expired."
        case .folderMissing: "Folder not found."
        case .quotaExceeded: "Your Google Drive is full."
        case .server: "Google Drive is having trouble right now."
        case .unknown: "Something went wrong."
        }
    }

    public var actionTitle: String {
        switch self {
        case .authExpired: "Reconnect"
        case .folderMissing: "Choose Folder"
        default: "Retry"
        }
    }
}

public enum UploadState: Codable, Hashable, Sendable {
    case pending
    case uploading(progress: Double)
    case done(fileID: String)
    case failed(UploadFailure)
}

public struct UploadJob: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var scanID: UUID
    public var kind: UploadKind
    public var fileName: String
    public var state: UploadState
    public var retryCount: Int
    public var createdAt: Date
    public var nextAttemptAt: Date?

    public init(id: UUID = UUID(), scanID: UUID, kind: UploadKind, fileName: String,
                state: UploadState = .pending, retryCount: Int = 0, createdAt: Date = .now,
                nextAttemptAt: Date? = nil) {
        self.id = id
        self.scanID = scanID
        self.kind = kind
        self.fileName = fileName
        self.state = state
        self.retryCount = retryCount
        self.createdAt = createdAt
        self.nextAttemptAt = nextAttemptAt
    }

    public var isDone: Bool {
        if case .done = state { return true }
        return false
    }
}

// MARK: - Drive

public struct DriveFolderRef: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    /// Human-readable path, e.g. "My Drive / PuffyMeter Daily".
    public var path: String

    public init(id: String, name: String, path: String) {
        self.id = id
        self.name = name
        self.path = path
    }
}

public enum UploadQuality: String, Codable, CaseIterable, Sendable, Identifiable {
    case original, high, compact
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .original: "Original"
        case .high: "High"
        case .compact: "Compact"
        }
    }
    /// Longest side in pixels; nil keeps the original resolution.
    public var maxPixelSize: Int? {
        switch self {
        case .original: nil
        case .high: 2048
        case .compact: 1280
        }
    }
    public var jpegQuality: Double { self == .original ? 0.95 : 0.85 }
}
