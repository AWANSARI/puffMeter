import Foundation

public enum OnboardingStep: String, Codable, Sendable, CaseIterable {
    case welcome
    case signIn
    case driveLimitedAccess
    case driveFolderPicker
    case driveConnected
    case permissions
    case baselineScan
    case complete
}

public enum DriveConnection: Codable, Hashable, Sendable {
    case notConnected
    case connected(DriveFolderRef)
    /// The user explicitly chose to keep scans on this iPhone only.
    case skipped
    /// Token refresh failed; the user is still signed in but Drive needs to reconnect.
    case needsReconnect(DriveFolderRef)

    public var folder: DriveFolderRef? {
        switch self {
        case .connected(let folder), .needsReconnect(let folder): folder
        case .notConnected, .skipped: nil
        }
    }
}

public struct ReminderTime: Codable, Hashable, Sendable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    public static let defaultMorning = ReminderTime(hour: 8, minute: 0)

    public func date(on day: DayKey, calendar: Calendar = .current) -> Date {
        let start = day.startDate(calendar: calendar)
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: start) ?? start
    }

    public var formatted: String {
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let date = Calendar.current.date(from: comps) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}

public struct UserProfile: Codable, Hashable, Sendable {
    public var displayName: String
    public var email: String?
    public var provider: AuthProvider

    public init(displayName: String, email: String?, provider: AuthProvider) {
        self.displayName = displayName
        self.email = email
        self.provider = provider
    }

    public var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}

public enum AuthProvider: String, Codable, Sendable {
    case google, apple
    /// No account: scans stay on this iPhone (used when Google isn't configured in the build).
    case local
}

/// Build-time switches read from Info.plist.
public enum AppConfiguration {
    public static var appleSignInEnabled: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "PuffyAppleSignIn") as? String)?.uppercased() != "NO"
    }

    /// False until a real Google iOS client ID is placed in Config/Secrets.xcconfig.
    public static var googleConfigured: Bool {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String else { return false }
        return !id.isEmpty && !id.contains("REPLACE_ME") && id.hasSuffix(".apps.googleusercontent.com")
    }
}

public struct UserSettings: Codable, Hashable, Sendable {
    public var onboardingStep: OnboardingStep
    public var profile: UserProfile?
    public var drive: DriveConnection
    public var reminderEnabled: Bool
    public var reminderTime: ReminderTime
    public var streakSaverEnabled: Bool
    public var healthSyncEnabled: Bool
    public var faceIDLockEnabled: Bool
    public var uploadQuality: UploadQuality
    public var ghostOverlayEnabled: Bool
    /// Last day the all-rings-closed celebration was shown (shown once per day).
    public var lastCelebrationDay: DayKey?
    public var lastSyncAt: Date?

    public init(onboardingStep: OnboardingStep = .welcome, profile: UserProfile? = nil,
                drive: DriveConnection = .notConnected, reminderEnabled: Bool = true,
                reminderTime: ReminderTime = .defaultMorning, streakSaverEnabled: Bool = true,
                healthSyncEnabled: Bool = false, faceIDLockEnabled: Bool = false,
                uploadQuality: UploadQuality = .high, ghostOverlayEnabled: Bool = true,
                lastCelebrationDay: DayKey? = nil, lastSyncAt: Date? = nil) {
        self.onboardingStep = onboardingStep
        self.profile = profile
        self.drive = drive
        self.reminderEnabled = reminderEnabled
        self.reminderTime = reminderTime
        self.streakSaverEnabled = streakSaverEnabled
        self.healthSyncEnabled = healthSyncEnabled
        self.faceIDLockEnabled = faceIDLockEnabled
        self.uploadQuality = uploadQuality
        self.ghostOverlayEnabled = ghostOverlayEnabled
        self.lastCelebrationDay = lastCelebrationDay
        self.lastSyncAt = lastSyncAt
    }
}

/// Lightweight snapshot written to the App Group for the widget extension.
public struct WidgetSnapshot: Codable, Hashable, Sendable {
    public var dayKey: DayKey
    public var score: Int?
    public var deltaVsYesterday: Int?
    public var dePuffProgress: Double
    public var scanProgress: Double
    public var habitsProgress: Double
    public var scansToday: Int
    public var habitsLogged: Int
    public var habitsGoal: Int
    public var streakDays: Int
    public var updatedAt: Date

    public init(dayKey: DayKey, score: Int?, deltaVsYesterday: Int?, dePuffProgress: Double,
                scanProgress: Double, habitsProgress: Double, scansToday: Int, habitsLogged: Int,
                habitsGoal: Int, streakDays: Int, updatedAt: Date) {
        self.dayKey = dayKey
        self.score = score
        self.deltaVsYesterday = deltaVsYesterday
        self.dePuffProgress = dePuffProgress
        self.scanProgress = scanProgress
        self.habitsProgress = habitsProgress
        self.scansToday = scansToday
        self.habitsLogged = habitsLogged
        self.habitsGoal = habitsGoal
        self.streakDays = streakDays
        self.updatedAt = updatedAt
    }

    public static let empty = WidgetSnapshot(dayKey: DayKey(.now), score: nil, deltaVsYesterday: nil,
                                             dePuffProgress: 0, scanProgress: 0, habitsProgress: 0,
                                             scansToday: 0, habitsLogged: 0, habitsGoal: 4,
                                             streakDays: 0, updatedAt: .now)
}
