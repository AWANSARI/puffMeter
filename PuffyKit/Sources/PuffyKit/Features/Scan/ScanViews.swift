import SwiftUI

/// Provides the camera session; the app injects the real one, previews use the simulated one.
public struct FaceCameraFactory: Sendable {
    public var make: @MainActor @Sendable () -> any FaceCameraSession
    public init(make: @escaping @MainActor @Sendable () -> any FaceCameraSession) { self.make = make }
    public static let simulated = FaceCameraFactory { SimulatedFaceCamera() }
}

private struct FaceCameraFactoryKey: EnvironmentKey {
    static let defaultValue = FaceCameraFactory.simulated
}

public extension EnvironmentValues {
    var faceCameraFactory: FaceCameraFactory {
        get { self[FaceCameraFactoryKey.self] }
        set { self[FaceCameraFactoryKey.self] = newValue }
    }
}

/// Camera → countdown → analyzing → result.
public struct ScanFlowView: View {
    var isBaseline: Bool
    var onFinished: () -> Void

    @Environment(AppModel.self) private var model
    @State private var stage: Stage = .camera

    enum Stage: Equatable {
        case camera
        case analyzing(PhotoBox)
        case result(UUID)
    }

    public init(isBaseline: Bool, onFinished: @escaping () -> Void) {
        self.isBaseline = isBaseline
        self.onFinished = onFinished
    }

    public var body: some View {
        Group {
            switch stage {
            case .camera:
                ScanCameraView(isBaseline: isBaseline) { capture in
                    stage = .analyzing(PhotoBox(capture: capture))
                }
            case .analyzing(let box):
                AnalyzingView(capture: box.capture, isBaseline: isBaseline) { scanID in
                    stage = scanID.map(Stage.result) ?? .camera
                }
            case .result(let id):
                ScanResultView(scanID: id, isBaseline: isBaseline, onDone: onFinished)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: stage)
    }
}

struct PhotoBox: Equatable {
    let id = UUID()
    let capture: CapturedFace
    static func == (lhs: PhotoBox, rhs: PhotoBox) -> Bool { lhs.id == rhs.id }
}

// MARK: - Camera

struct ScanCameraView: View {
    var isBaseline: Bool
    var onCapture: (CapturedFace) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.faceCameraFactory) private var factory
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var camera: (any FaceCameraSession)?
    @State private var countdown: Int?
    @State private var passStart: Date?
    @State private var capturing = false
    @State private var showGhost = true
    @State private var flash = false
    @State private var captureError: String?

    var body: some View {
        ScreenScaffold(isBaseline ? "Your first scan" : "Daily Scan", subtitle: "PuffyMeter") {
            cameraCard
            VStack(spacing: 14) {
                Text(headline)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .contentTransition(.opacity)
                    .accessibilityAddTraits(.updatesFrequently)
                HStack {
                    ChecklistItem("Centered", passed: checks.isCentered)
                    ChecklistItem("Good lighting", passed: checks.goodLighting)
                    ChecklistItem("Neutral face", passed: checks.neutralFace)
                }
                .sensoryFeedback(.selection, trigger: checks)
                Text(caption)
                    .font(.footnote).foregroundStyle(Color.pmLabelSecondary)
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                if let captureError {
                    Text(captureError).font(.footnote).foregroundStyle(Color.pmAccent)
                }
                if countdown != nil {
                    Button("Cancel countdown") { cancelCountdown() }.buttonStyle(.pmPrimary)
                } else {
                    Button(isBaseline ? "Capture baseline" : "Capture now") {
                        Task { await capture(manual: !checks.allPassed) }
                    }
                    .buttonStyle(.pmPrimary)
                    .disabled(capturing || checks.faceCount == 0)
                }
            }
        }
        .overlay { if flash { Color.white.ignoresSafeArea().transition(.opacity) } }
        .onAppear {
            showGhost = model.settings.ghostOverlayEnabled
            let session = factory.make()
            camera = session
            session.start()
        }
        .onDisappear { camera?.stop() }
        .onChange(of: checks) { evaluateAutoCapture() }
        .task(id: countdown) { await tickCountdown() }
        .sensoryFeedback(.impact(weight: .light), trigger: countdown)
    }

    private var checks: ScanChecks { camera?.checks ?? ScanChecks() }

    private var headline: String {
        if countdown != nil { return "Hold still. You're ready." }
        if let guidance = checks.guidance { return guidance }
        return isBaseline ? "Let's set your baseline" : "Hold still. You're ready."
    }

    private var caption: String {
        if countdown != nil {
            return "Auto-capture in \(countdown ?? 3) seconds" + (ghostAvailable && showGhost ? "\nYesterday's photo is faintly overlaid for alignment." : "")
        }
        if isBaseline {
            return "Face the camera at eye level in even light.\nYour first score is a starting point, not a verdict."
        }
        return "Capture starts automatically when all three checks pass."
    }

    private var ghostAvailable: Bool { !isBaseline && model.scans.last?.photoFileName != nil }

    private var cameraCard: some View {
        ZStack {
            if let camera {
                camera.makePreview()
            } else {
                Color.black
            }
            if ghostAvailable && showGhost {
                ScanPhotoView(fileName: model.scans.last?.photoFileName, cornerRadius: 0)
                    .opacity(0.18)
                    .allowsHitTesting(false)
            }
            GeometryReader { proxy in
                let ovalSize = CGSize(width: proxy.size.width * 0.64, height: proxy.size.height * 0.68)
                let ovalCenter = CGPoint(x: proxy.size.width / 2, y: proxy.size.height * 0.44)
                ZStack {
                    FaceMeshOverlay()
                        .stroke(Color.pmRingHabits.opacity(checks.faceCount == 1 ? 0.7 : 0), lineWidth: 1)
                        .frame(width: ovalSize.width * 0.92, height: ovalSize.height * 0.78)
                        .position(x: ovalCenter.x, y: ovalCenter.y - ovalSize.height * 0.02)
                    Ellipse()
                        .stroke(checks.allPassed ? Color.pmRingScan : Color.pmWarning, lineWidth: 3)
                        .frame(width: ovalSize.width, height: ovalSize.height)
                        .position(ovalCenter)
                        .animation(.easeInOut(duration: 0.2), value: checks.allPassed)
                    if let countdown {
                        Text("\(countdown)")
                            .font(.system(size: 48, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 96, height: 96)
                            .background(.black.opacity(0.55), in: Circle())
                            .position(x: ovalCenter.x, y: min(proxy.size.height - 56, ovalCenter.y + ovalSize.height / 2 + 4))
                            .transition(.scale.combined(with: .opacity))
                            .id(countdown)
                            .accessibilityLabel("Capturing in \(countdown)")
                    }
                }
            }
            VStack {
                HStack {
                    Text("FRONT CAMERA")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.45), in: Capsule())
                    Spacer()
                    if ghostAvailable {
                        Button {
                            showGhost.toggle()
                            model.updateSettings { $0.ghostOverlayEnabled = showGhost }
                        } label: {
                            Image(systemName: showGhost ? "square.on.square.fill" : "square.on.square")
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(.black.opacity(0.45), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(showGhost ? "Hide yesterday's photo overlay" : "Show yesterday's photo overlay")
                    }
                }
                Spacer()
            }
            .padding(12)
        }
        .aspectRatio(0.87, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.photoRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Camera preview")
    }

    private func evaluateAutoCapture() {
        guard !capturing else { return }
        if checks.allPassed {
            if passStart == nil { passStart = .now }
            if countdown == nil, let start = passStart {
                let elapsed = Date.now.timeIntervalSince(start)
                if elapsed >= 0.8 {
                    countdown = 3
                } else {
                    Task {
                        try? await Task.sleep(for: .seconds(0.8 - elapsed))
                        if checks.allPassed && countdown == nil && !capturing { countdown = 3 }
                    }
                }
            }
        } else {
            passStart = nil
            if countdown != nil { cancelCountdown() }
        }
    }

    private func cancelCountdown() {
        withAnimation { countdown = nil }
        passStart = nil
    }

    private func tickCountdown() async {
        guard let value = countdown else { return }
        try? await Task.sleep(for: .seconds(1))
        guard countdown == value, !Task.isCancelled else { return }
        if value > 1 {
            withAnimation(reduceMotion ? nil : .spring(response: 0.35)) { countdown = value - 1 }
        } else {
            countdown = nil
            await capture(manual: false)
        }
    }

    private func capture(manual: Bool) async {
        guard let camera, !capturing else { return }
        capturing = true
        captureError = nil
        withAnimation(.easeOut(duration: 0.08)) { flash = true }
        do {
            let capture = try await camera.capture(manual: manual)
            withAnimation(.easeIn(duration: 0.2)) { flash = false }
            camera.stop()
            onCapture(capture)
        } catch {
            flash = false
            captureError = "Couldn't capture. Please try again."
            capturing = false
        }
    }
}

/// Stylized face-mesh wireframe drawn inside the oval.
struct FaceMeshOverlay: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: rect.minX + w * x, y: rect.minY + h * y) }
        let outline = [p(0.5, 0.0), p(0.8, 0.08), p(0.95, 0.35), p(0.88, 0.62), p(0.7, 0.88), p(0.5, 1.0),
                       p(0.3, 0.88), p(0.12, 0.62), p(0.05, 0.35), p(0.2, 0.08)]
        path.addLines(outline + [outline[0]])
        let inner = [p(0.5, 0.25), p(0.72, 0.38), p(0.65, 0.62), p(0.5, 0.72), p(0.35, 0.62), p(0.28, 0.38)]
        path.addLines(inner + [inner[0]])
        for (a, b) in zip(outline, outline.indices.map { inner[$0 % inner.count] }) {
            path.move(to: a)
            path.addLine(to: b)
        }
        path.move(to: p(0.05, 0.35)); path.addLine(to: p(0.95, 0.35))
        path.move(to: p(0.12, 0.62)); path.addLine(to: p(0.88, 0.62))
        path.move(to: p(0.5, 0.0)); path.addLine(to: p(0.5, 1.0))
        return path
    }
}

// MARK: - Analyzing

struct AnalyzingView: View {
    var capture: CapturedFace
    var isBaseline: Bool
    var onComplete: (UUID?) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    @State private var sweep = false
    @State private var errorMessage: String?

    var body: some View {
        ScreenScaffold("Analyzing", subtitle: "PuffyMeter") {
            ZStack(alignment: .top) {
                photo
                    .aspectRatio(0.98, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.photoRadius, style: .continuous))
                GeometryReader { proxy in
                    Rectangle()
                        .fill(Color.pmRingHabits)
                        .frame(height: 2)
                        .shadow(color: .pmRingHabits, radius: 6)
                        .offset(y: reduceMotion ? proxy.size.height / 2 : (sweep ? proxy.size.height - 2 : 0))
                }
            }
            .aspectRatio(0.98, contentMode: .fit)
            .accessibilityHidden(true)
            Text(errorMessage == nil ? "A moment for you." : "Something went wrong")
                .font(.title.bold()).frame(maxWidth: .infinity)
            Text(errorMessage ?? "Comparing today's face zones with your recent scans.")
                .font(.body).foregroundStyle(Color.pmLabelSecondary).wrapping(.center).frame(maxWidth: .infinity)
            if errorMessage == nil {
                StepList(steps: [
                    .init(title: "Photo quality checked", state: state(for: 0)),
                    .init(title: "Estimating face zones", state: state(for: 1)),
                    .init(title: "Preparing your comparison", state: state(for: 2)),
                ])
            } else {
                Button("Try again") { onComplete(nil) }.buttonStyle(.pmPrimary)
            }
            Disclaimer("Your score is a cosmetic estimate, not a diagnosis.", alignment: .center)
        }
        .pmHideTabBar(true)
        .task { await run() }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { sweep = true }
        }
    }

    @ViewBuilder private var photo: some View {
        if let image = PlatformImage(data: capture.jpegData) {
            Image(platformImage: image).resizable().scaledToFill()
        } else {
            PhotoPlaceholder()
        }
    }

    private func state(for index: Int) -> StepList.StepState {
        index < step ? .done : (index == step ? .active : .pending)
    }

    private func run() async {
        let started = Date.now
        try? await Task.sleep(for: .milliseconds(500))
        withAnimation { step = 1 }
        do {
            let record = try await model.recordScan(capture, isBaseline: isBaseline)
            withAnimation { step = 2 }
            let remaining = 1.5 - Date.now.timeIntervalSince(started)
            try? await Task.sleep(for: .seconds(max(0.4, remaining)))
            withAnimation { step = 3 }
            try? await Task.sleep(for: .milliseconds(250))
            onComplete(record.id)
        } catch {
            errorMessage = "We couldn't analyze this photo. Try again in even light."
        }
    }
}

// MARK: - Result

struct ScanResultView: View {
    var scanID: UUID
    var isBaseline: Bool
    var onDone: () -> Void

    @Environment(AppModel.self) private var model
    @State private var notes = ""
    @State private var tags: [String] = []
    @State private var selectedTags: Set<String> = []
    @State private var comparison = 0.5
    @State private var showFailureAlert = false
    @State private var addingTag = false
    @State private var newTag = ""
    @State private var appeared = false

    var body: some View {
        if let scan = model.scan(id: scanID) {
            content(scan)
        } else {
            ProgressView()
        }
    }

    private func content(_ scan: ScanRecord) -> some View {
        let previous = model.scans.last { $0.dayKey < scan.dayKey }
        let upload = model.uploadCardState(for: scan.id)
        return ScreenScaffold(isBaseline ? "Baseline set" : "Scan result",
                              subtitle: isBaseline ? "Future scans compare to this one"
                                : "\(scan.capturedAt.formatted(.dateTime.month(.wide).day())) · \(Format.time(scan.capturedAt))") {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Puffiness Score").font(.headline)
                    HStack(alignment: .lastTextBaseline, spacing: 10) {
                        Text("\(scan.score)")
                            .font(.system(size: 72, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.pmAccent)
                            .contentTransition(.numericText(value: Double(appeared ? scan.score : 0)))
                        Text("/ 100 · Lower is better").font(.body).foregroundStyle(Color.pmLabelSecondary)
                    }
                    if isBaseline {
                        Text("This is your starting point, not a verdict.").font(.subheadline).foregroundStyle(Color.pmLabelSecondary)
                    } else if let previous {
                        let delta = scan.score - previous.score
                        MetricDelta(delta, suffix: delta == 0 ? "from \(dayWord(previous))'s \(previous.score)"
                                    : "points from \(dayWord(previous))'s \(previous.score)", font: .subheadline)
                    }
                    if scan.lowConfidence {
                        Label("Lower confidence: lighting or angle differed", systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(Color.pmWarning)
                    }
                }
            }

            if let previous, !isBaseline {
                HStack {
                    Text("\(dayWord(previous).capitalized) · \(previous.score)").foregroundStyle(Color.pmLabelSecondary)
                    Spacer()
                    Text("Today · \(scan.score)").foregroundStyle(Color.pmLabel)
                }
                .font(.subheadline)
                ComparisonSlider(position: $comparison) {
                    ScanPhotoView(fileName: previous.photoFileName, cornerRadius: 0)
                } after: {
                    ScanPhotoView(fileName: scan.photoFileName, cornerRadius: 0)
                }
                Slider(value: $comparison, in: 0...1)
                    .tint(.pmLink)
                    .accessibilityLabel("Comparison position")
            } else {
                ScanPhotoView(fileName: scan.photoFileName, cornerRadius: Spacing.photoRadius)
                    .aspectRatio(3 / 4, contentMode: .fit)
            }

            HStack(spacing: 8) {
                ForEach(FaceZone.allCases) { ZoneTile(zone: $0, value: scan.zones.value(for: $0)) }
            }

            Text("Notes & tags").font(.headline).padding(.top, 4)
            TextField("Add a note", text: $notes, axis: .vertical)
                .lineLimit(1...3)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.pmCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            FlowLayout(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    TagChip(tag, isOn: selectedTags.contains(tag)) {
                        if selectedTags.contains(tag) { selectedTags.remove(tag) } else { selectedTags.insert(tag) }
                    }
                }
                TagChip("+ Tag", isOn: false) { addingTag = true }
            }

            UploadStatusCard(state: upload) { handleUploadAction(upload) }

            switch upload {
            case .failed:
                Button("Retry upload") { model.retryUploads() }.buttonStyle(.pmPrimary)
                Button("Done") { finish() }.buttonStyle(.pmSecondary)
            case .queued:
                Button("Done · Save locally") { finish() }.buttonStyle(.pmPrimary)
            default:
                Button("Done") { finish() }.buttonStyle(.pmPrimary)
            }
            Disclaimer("Lighting and expression can affect your score.", alignment: .center)
        }
        .pmHideTabBar(true)
        .sensoryFeedback(.success, trigger: appeared)
        .sensoryFeedback(.error, trigger: isFailed(upload))
        .onAppear {
            tags = scan.tags.isEmpty ? (model.todayLog?.suggestedTags ?? []) : scan.tags
            selectedTags = Set(tags)
            notes = scan.notes
            appeared = true
        }
        .onChange(of: isFailed(upload)) { _, failed in if failed { showFailureAlert = true } }
        .alert("Couldn't save to Drive", isPresented: $showFailureAlert) {
            Button("Later", role: .cancel) {}
            Button("Retry") { model.retryUploads() }
        } message: {
            if case .failed(let failure) = upload, failure == .authExpired {
                Text("Your scan is safe on this iPhone. Reconnect Google Drive in Profile to finish backing up.")
            } else {
                Text("Your scan is safe on this iPhone.\nCheck your connection and try again.")
            }
        }
        .alert("Add a tag", isPresented: $addingTag) {
            TextField("Tag", text: $newTag)
            Button("Add") {
                let tag = newTag.trimmingCharacters(in: .whitespaces)
                if !tag.isEmpty, !tags.contains(tag) {
                    tags.append(tag)
                    selectedTags.insert(tag)
                }
                newTag = ""
            }
            Button("Cancel", role: .cancel) { newTag = "" }
        }
    }

    private func isFailed(_ state: UploadCardState) -> Bool {
        if case .failed = state { return true }
        return false
    }

    private func dayWord(_ previous: ScanRecord) -> String {
        let gap = previous.dayKey.days(until: model.today, calendar: model.calendar)
        return gap == 1 ? "yesterday" : Format.shortDay(previous.dayKey, calendar: model.calendar)
    }

    private func handleUploadAction(_ state: UploadCardState) {
        if case .failed(let failure) = state {
            switch failure {
            case .authExpired, .folderMissing:
                finish()
                RouterBridge.shared?.presentDriveSettings()
            default:
                model.retryUploads()
            }
        }
    }

    private func finish() {
        model.finalizeScan(id: scanID, notes: notes, tags: tags.filter { selectedTags.contains($0) })
        onDone()
    }
}

/// Lets leaf views reach the router without threading it through every initializer.
@MainActor
public enum RouterBridge {
    public static weak var shared: AppRouter?
}
