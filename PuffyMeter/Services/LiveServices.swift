import Foundation
import PuffyKit
import HealthKit
import UserNotifications
import LocalAuthentication
import AVFoundation
import UIKit

enum LiveServices {
    @MainActor
    static func make() -> Services {
        let auth = GoogleAuthService()
        return Services(
            auth: auth,
            drive: GoogleDriveClient { try await auth.driveAccessTokenFromAnyContext() },
            health: HealthKitService(),
            notifications: LocalNotificationService(),
            photos: FilePhotoStore(),
            appLock: BiometricAppLock(),
            camera: AVCameraPermission(),
            analyzer: VisionFaceAnalyzer(),
            store: FileStateStore()
        )
    }
}

// MARK: - HealthKit (read only)

final class HealthKitService: HealthService, @unchecked Sendable {
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        [HKCategoryType(.sleepAnalysis), HKQuantityType(.dietaryWater), HKCategoryType(.menstrualFlow)]
    }

    func requestAuthorization() async throws {
        guard isAvailable else { return }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    /// Asleep samples between 6 PM the previous day and 12 PM on `day`.
    func sleepHours(endingOn day: DayKey) async -> Double? {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .hour, value: -6, to: day.startDate(calendar: calendar))!
        let end = calendar.date(byAdding: .hour, value: 12, to: day.startDate(calendar: calendar))!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
                                                 sortDescriptors: [])
        guard let samples = try? await descriptor.result(for: store) else { return nil }
        let asleepValues: Set<Int> = [HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                                      HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                                      HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                                      HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue]
        let seconds = samples.filter { asleepValues.contains($0.value) }
            .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        return seconds > 0 ? seconds / 3600 : nil
    }

    func waterLiters(on day: DayKey) async -> Double? {
        let calendar = Calendar.current
        let start = day.startDate(calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKStatisticsQueryDescriptor(predicate: .quantitySample(type: HKQuantityType(.dietaryWater), predicate: predicate),
                                                     options: .cumulativeSum)
        guard let result = try? await descriptor.result(for: store),
              let sum = result.sumQuantity() else { return nil }
        return sum.doubleValue(for: .liter())
    }

    func cycleDays(from start: DayKey, through end: DayKey) async -> Set<DayKey>? {
        let calendar = Calendar.current
        let predicate = HKQuery.predicateForSamples(withStart: start.startDate(calendar: calendar),
                                                    end: end.adding(days: 1).startDate(calendar: calendar))
        let descriptor = HKSampleQueryDescriptor(predicates: [.categorySample(type: HKCategoryType(.menstrualFlow), predicate: predicate)],
                                                 sortDescriptors: [])
        guard let samples = try? await descriptor.result(for: store), !samples.isEmpty else { return nil }
        let flowDays = samples.filter { $0.value != HKCategoryValueVaginalBleeding.none.rawValue }
            .map { DayKey($0.startDate, calendar: calendar) }
        return Set(flowDays)
    }
}

// MARK: - Notifications

struct LocalNotificationService: NotificationService {
    static let dailyID = "puffymeter.daily"
    static let streakID = "puffymeter.streak"
    static let scanCategory = "SCAN"

    static func registerCategories() {
        let scan = UNNotificationAction(identifier: "SCAN_NOW", title: "Scan now", options: [.foreground])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: scanCategory, actions: [scan], intentIdentifiers: []),
        ])
    }

    func authorizationStatus() async -> NotificationAuthorization {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: .authorized
        case .denied: .denied
        default: .notDetermined
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func scheduleDailyReminder(at time: ReminderTime) async {
        let content = UNMutableNotificationContent()
        content.title = "Good morning"
        content.body = "Time for your PuffyMeter scan."
        content.sound = .default
        content.categoryIdentifier = Self.scanCategory
        content.userInfo = ["route": "scan"]
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: time.hour, minute: time.minute), repeats: true)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: Self.dailyID, content: content, trigger: trigger))
    }

    func cancelDailyReminder() async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.dailyID])
    }

    func scheduleStreakSaver(streak: Int, on day: DayKey) async {
        let calendar = Calendar.current
        guard let fireDate = calendar.date(bySettingHour: 11, minute: 0, second: 0, of: day.startDate(calendar: calendar)),
              fireDate > .now else { return }
        let content = UNMutableNotificationContent()
        content.title = "Keep your \(streak)-day streak going"
        content.body = "A quick scan takes 20 seconds."
        content.sound = .default
        content.categoryIdentifier = Self.scanCategory
        content.userInfo = ["route": "scan"]
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: Self.streakID, content: content, trigger: trigger))
    }

    func cancelStreakSaver() async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.streakID])
    }

    func notifyAward(title: String) async {
        let state = await MainActor.run { UIApplication.shared.applicationState }
        guard state != .active else { return }
        let content = UNMutableNotificationContent()
        content.title = "New award"
        content.body = "You earned \(title)."
        content.userInfo = ["route": "awards"]
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

// MARK: - Face ID

struct BiometricAppLock: AppLockService {
    var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Face ID"
        }
    }

    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        // Passcode fallback is allowed so users can't be locked out.
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

// MARK: - Camera permission

@MainActor
final class AVCameraPermission: CameraPermissionService {
    func status() -> CameraAuthorization {
        #if targetEnvironment(simulator)
        return .authorized
        #else
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .authorized
        case .denied, .restricted: return .denied
        default: return .notDetermined
        }
        #endif
    }

    func request() async -> Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return await AVCaptureDevice.requestAccess(for: .video)
        #endif
    }
}
