import SwiftUI
import PuffyKit
import Network

@main
struct PuffyMeterApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel
    @State private var router = AppRouter()
    private let cameraFactory: FaceCameraFactory
    private let connectivity = ConnectivityMonitor()

    init() {
        let mode = LaunchMode.current
        let services: Services
        let calendar: Calendar
        let clock: @Sendable () -> Date
        switch mode {
        case .demo:
            // Seeded with the mockup data and a fixed clock (Oct 8, 2026 8:02 AM) for screenshots.
            services = .mock(seeded: true, signedIn: true)
            calendar = SampleData.calendar
            let fixed = SampleData.now
            let launched = Date()
            clock = { fixed.addingTimeInterval(Date().timeIntervalSince(launched)) }
        case .uiTest:
            services = .mock(seeded: false, signedIn: false)
            calendar = .current
            clock = { Date() }
        case .live:
            services = LiveServices.make()
            calendar = .current
            clock = { Date() }
        }
        _model = State(initialValue: AppModel(services: services, calendar: calendar, clock: clock))
        #if targetEnvironment(simulator)
        cameraFactory = .simulated
        #else
        cameraFactory = mode == .live ? FaceCameraFactory { LiveFaceCamera.make() } : .simulated
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(router)
                .environment(\.faceCameraFactory, cameraFactory)
                .task {
                    if LaunchMode.current == .demo {
                        await SampleData.seedPhotos(into: model.services.photos)
                        model.photosRevision += 1
                    }
                }
                .onAppear {
                    appDelegate.router = router
                    connectivity.start { online in model.isOnline = online }
                }
                .onOpenURL { url in GoogleAuthService.handle(url: url) }
        }
    }
}

enum LaunchMode: Equatable {
    case live, demo, uiTest

    static var current: LaunchMode {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-UITestMode") { return .uiTest }
        if args.contains("-DemoMode") { return .demo }
        return .live
    }
}

/// Publishes online/offline changes so queued uploads resume automatically.
final class ConnectivityMonitor: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private var started = false

    func start(onChange: @escaping @MainActor (Bool) -> Void) {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor in onChange(online) }
        }
        monitor.start(queue: DispatchQueue(label: "PuffyMeter.connectivity"))
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    @MainActor var router: AppRouter?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        LocalNotificationService.registerCategories()
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let destination = response.notification.request.content.userInfo["route"] as? String ?? "summary"
        await MainActor.run {
            router?.handle(url: URL(string: "puffymeter://\(destination)")!)
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
