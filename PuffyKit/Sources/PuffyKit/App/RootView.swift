import SwiftUI

/// Chooses onboarding vs. the main tabs, and hosts app-wide presentations
/// (award unlocks, all-rings celebration, Face ID lock).
public struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @State private var locked = false
    @State private var backgroundedAt: Date?

    public init() {}

    public var body: some View {
        @Bindable var model = model
        ZStack {
            if !model.isLoaded {
                LaunchView()
            } else if model.settings.onboardingStep != .complete {
                OnboardingFlow()
                    .transition(.opacity)
            } else {
                MainTabView()
                    .transition(.opacity)
            }
            if locked {
                AppLockView { Task { await unlock() } }
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: model.settings.onboardingStep)
        .animation(.easeInOut(duration: 0.2), value: locked)
        .tint(.pmAccent)
        .task {
            RouterBridge.shared = router
            await model.load()
            if model.settings.faceIDLockEnabled && model.settings.onboardingStep == .complete {
                locked = true
                await unlock()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                backgroundedAt = .now
                if model.settings.faceIDLockEnabled { locked = true }
            case .active:
                if locked {
                    if let backgroundedAt, Date.now.timeIntervalSince(backgroundedAt) < 30 {
                        locked = false
                    } else {
                        Task { await unlock() }
                    }
                }
                Task {
                    await model.refreshFromHealth()
                    await model.processUploads()
                }
            default:
                break
            }
        }
        .onOpenURL { router.handle(url: $0) }
    }

    private func unlock() async {
        if await model.services.appLock.authenticate(reason: "Unlock PuffyMeter") {
            locked = false
        }
    }
}

struct LaunchView: View {
    var body: some View {
        ActivityRings(RingProgress(dePuff: 1, scan: 1, habits: 0.75), size: .compact, animateOnAppear: false)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.pmBackground.ignoresSafeArea())
    }
}

struct AppLockView: View {
    var onUnlock: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 20) {
            ActivityRings(RingProgress(dePuff: 1, scan: 1, habits: 0.75), size: .compact, animateOnAppear: false)
            Text("PuffyMeter is locked").font(.title2.bold())
            Button {
                onUnlock()
            } label: {
                Label("Unlock PuffyMeter", systemImage: "faceid")
            }
            .buttonStyle(.pmPrimary)
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .background(Color.pmBackground.opacity(0.85))
        .ignoresSafeArea()
    }
}

// MARK: - Onboarding

struct OnboardingFlow: View {
    @Environment(AppModel.self) private var model
    @State private var path: [OnboardingStep] = []
    @State private var connectedFolder: DriveFolderRef?

    var body: some View {
        NavigationStack(path: $path) {
            root
                .navigationDestination(for: OnboardingStep.self) { destination($0) }
        }
        .onAppear(perform: restorePath)
    }

    @ViewBuilder private var root: some View {
        switch model.settings.onboardingStep {
        case .welcome:
            WelcomeView { model.setOnboardingStep(.signIn) }
        default:
            SignInView(onSignedIn: { profile in
                model.signedIn(profile)
                path = [.driveLimitedAccess]
            }, onUseLocally: {
                model.useLocally()
                path = [.permissions]
            })
        }
    }

    @ViewBuilder private func destination(_ step: OnboardingStep) -> some View {
        switch step {
        case .driveLimitedAccess:
            ConnectDriveView(onConnected: {
                model.setOnboardingStep(.driveFolderPicker)
                path.append(.driveFolderPicker)
            }, onSkip: {
                model.skipDrive()
                model.setOnboardingStep(.permissions)
                path.append(.permissions)
            })
        case .driveFolderPicker:
            FolderPickerView { folder in
                connectedFolder = folder
                model.connectDrive(folder: folder, email: nil)
                model.setOnboardingStep(.driveConnected)
                path.append(.driveConnected)
            }
        case .driveConnected:
            DriveConnectedView(folder: connectedFolder ?? model.settings.drive.folder ?? SampleData.folder,
                               onContinue: {
                                   model.setOnboardingStep(.permissions)
                                   path.append(.permissions)
                               }, onChangeFolder: {
                                   path.removeLast()
                               })
        case .permissions:
            PermissionsView {
                model.setOnboardingStep(.baselineScan)
                path.append(.baselineScan)
            }
        case .baselineScan:
            ScanFlowView(isBaseline: true) {
                model.setOnboardingStep(.complete)
            }
        case .welcome, .signIn, .complete:
            EmptyView()
        }
    }

    /// Relaunching mid-onboarding resumes at the saved step.
    private func restorePath() {
        let order: [OnboardingStep] = [.driveLimitedAccess, .driveFolderPicker, .driveConnected, .permissions, .baselineScan]
        guard let index = order.firstIndex(of: model.settings.onboardingStep) else { return }
        var steps = Array(order[...index])
        if case .skipped = model.settings.drive {
            steps.removeAll { $0 == .driveFolderPicker || $0 == .driveConnected }
        }
        path = steps
    }
}

// MARK: - Main tabs

struct MainTabView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        @Bindable var model = model
        TabView(selection: $router.selectedTab) {
            Tab(MainTab.summary.title, systemImage: MainTab.summary.symbol, value: MainTab.summary) {
                NavigationStack(path: $router.summaryPath) {
                    SummaryView().withRoutes()
                }
            }
            Tab(MainTab.trends.title, systemImage: MainTab.trends.symbol, value: MainTab.trends) {
                NavigationStack(path: $router.trendsPath) {
                    TrendsView().withRoutes()
                }
            }
            Tab(MainTab.scan.title, systemImage: MainTab.scan.symbol, value: MainTab.scan) {
                ScanTabView()
            }
            Tab(MainTab.awards.title, systemImage: MainTab.awards.symbol, value: MainTab.awards) {
                NavigationStack(path: $router.awardsPath) {
                    AwardsView().withRoutes()
                }
            }
            Tab(MainTab.profile.title, systemImage: MainTab.profile.symbol, value: MainTab.profile) {
                NavigationStack(path: $router.profilePath) {
                    ProfileView().withRoutes()
                }
            }
        }
        .tint(.pmAccent)
        .environment(\.symbolVariants, .none)
        .sheet(item: Binding(get: { model.showAllRingsClosed ? nil : model.awardQueue.first },
                             set: { if $0 == nil { model.dequeueAward() } })) { award in
            AwardUnlockSheet(award: award) { model.dequeueAward() }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .pmFullScreenCover(isPresented: $model.showAllRingsClosed) {
            AllRingsClosedView {
                model.dismissAllRingsClosed()
                router.selectedTab = .summary
            }
        }
    }
}

extension View {
    func withRoutes() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .scanDetail(let id): ScanDetailView(scanID: id)
            case .timeLapse: TimeLapseView()
            case .photoGrid: PhotoGridView()
            case .patterns: PatternsView()
            case .goals: GoalsEditorView()
            case .challenges: ChallengesView()
            case .awardDetail(let id): AwardDetailView(awardID: id)
            case .driveSettings: DriveSettingsView()
            case .reminderTime: ReminderTimeView()
            case .exportData: ExportDataView()
            case .privacy: PrivacyView()
            }
        }
    }
}

/// Scan tab: camera when today's scan is missing, otherwise today's result with a retake option.
struct ScanTabView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var scanning = false
    @State private var confirmRetake = false
    @State private var flowID = UUID()

    var body: some View {
        NavigationStack {
            if let today = model.todayStats.primaryScan, !scanning {
                ScreenScaffold("Daily Scan", subtitle: "Done for today") {
                    ScanSummaryCard(scan: today)
                    Button("View result") { router.showScanDetail(today.id) }
                        .buttonStyle(.pmPrimary)
                    Button("Retake today's scan") { confirmRetake = true }
                        .buttonStyle(.pmSecondary)
                    Disclaimer("A retake replaces today's photo and score.", alignment: .center)
                }
                .confirmationDialog("Retake today's scan?", isPresented: $confirmRetake, titleVisibility: .visible) {
                    Button("Retake") {
                        flowID = UUID()
                        scanning = true
                    }
                } message: {
                    Text("Your new photo and score will replace today's.")
                }
            } else {
                ScanFlowView(isBaseline: !model.hasBaseline) {
                    scanning = false
                    flowID = UUID()
                    if !model.showAllRingsClosed { router.selectedTab = .summary }
                }
                .id(flowID)
                .onAppear { scanning = true }
            }
        }
    }
}

