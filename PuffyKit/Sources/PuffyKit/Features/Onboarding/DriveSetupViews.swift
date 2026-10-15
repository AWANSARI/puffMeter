import SwiftUI

/// "Connect Google Drive": explains the one-folder access before asking for the scope.
public struct ConnectDriveView: View {
    var onConnected: () -> Void
    var onSkip: () -> Void
    @Environment(AppModel.self) private var model
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var confirmSkip = false

    public init(onConnected: @escaping () -> Void, onSkip: @escaping () -> Void) {
        self.onConnected = onConnected
        self.onSkip = onSkip
    }

    public var body: some View {
        ScreenScaffold("Connect Google Drive", subtitle: "PuffyMeter") {
            Image(systemName: "lock.rectangle.stack")
                .font(.system(size: 64, weight: .thin))
                .foregroundStyle(Color.pmLink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .accessibilityHidden(true)
            HeroHeadline("One folder.\nNothing else.")
            Text("PuffyMeter can create and save photos only in the folder you select. It can't browse the rest of your Drive.")
                .font(.body).foregroundStyle(Color.pmLabelSecondary).wrapping()
            Card(padding: 0) {
                VStack(spacing: 0) {
                    accessRow("photo", "Daily scan photos", "JPG")
                    accessRow("doc.text", "Scores and notes", "JSON")
                    accessRow("lock.fill", "Your other files", "No access", iconColor: .pmLabelSecondary)
                }
                .padding(.vertical, 6)
            }
            Disclaimer("You can disconnect or change folders anytime in Profile. Deleting the app won't delete your Drive photos.")
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(Color.pmAccent).wrapping()
            }
            Button(isWorking ? "Connecting…" : "Choose Drive folder") { Task { await connect() } }
                .buttonStyle(.pmPrimary)
                .disabled(isWorking)
            Button("Not now") { confirmSkip = true }
                .font(.subheadline)
                .foregroundStyle(Color.pmLabelSecondary)
                .frame(maxWidth: .infinity)
                .buttonStyle(.plain)
        }
        .confirmationDialog("Continue without Google Drive?", isPresented: $confirmSkip, titleVisibility: .visible) {
            Button("Keep scans on this iPhone") { onSkip() }
        } message: {
            Text("Without Drive, scans are stored only on this iPhone. You can connect later in Profile.")
        }
    }

    private func accessRow(_ symbol: String, _ title: String, _ value: String, iconColor: Color = .pmAccent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(iconColor).frame(width: 28)
            Text(title)
            Spacer()
            Text(value).foregroundStyle(Color.pmLabelSecondary)
        }
        .padding(.horizontal, Spacing.cardPadding)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private func connect() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            if let email = try await model.services.auth.requestDriveAccess(), model.settings.profile?.email == nil {
                model.updateSettings { $0.profile?.email = email }
            }
            onConnected()
        } catch let error as AuthError {
            errorMessage = error.message
        } catch {
            errorMessage = "Couldn't connect to Google Drive. Please try again."
        }
    }
}

/// Folder browser. With the `drive.file` scope it lists folders PuffyMeter created or that
/// the user opened via the Google Picker; "New Folder" is the primary path.
public struct FolderPickerView: View {
    var onChoose: (DriveFolderRef) -> Void
    @Environment(AppModel.self) private var model

    @State private var trail: [DriveFolder] = []
    @State private var folders: [DriveFolder] = []
    @State private var selected: DriveFolder?
    @State private var query = ""
    @State private var loadState: LoadState = .loading
    @State private var showNewFolder = false

    enum LoadState: Equatable { case loading, loaded, failed }

    public init(onChoose: @escaping (DriveFolderRef) -> Void) { self.onChoose = onChoose }

    private var parentID: String? { trail.last?.id }
    private var pathPrefix: String { (["My Drive"] + trail.map(\.name)).joined(separator: " / ") }

    public var body: some View {
        ScreenScaffold("Choose a folder", subtitle: "PuffyMeter") {
            if let profile = model.settings.profile {
                Card {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.displayName).font(.headline)
                        if let email = profile.email {
                            Text(email).font(.footnote).foregroundStyle(Color.pmLabelSecondary)
                        }
                    }
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Button {
                    if !trail.isEmpty { trail.removeLast() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: trail.isEmpty ? "externaldrive" : "chevron.left").foregroundStyle(Color.pmLink)
                        Text(trail.last?.name ?? "My Drive").font(.headline).foregroundStyle(Color.pmLabel)
                    }
                }
                .buttonStyle(.plain)
                .disabled(trail.isEmpty)
                Spacer()
                Button("New Folder") { showNewFolder = true }
                    .foregroundStyle(Color.pmLink)
                    .buttonStyle(.plain)
            }
            .padding(.top, 4)

            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.pmLabelSecondary)
                TextField("Search folders", text: $query)
                    .submitLabel(.search)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(Color.pmCardElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            folderList

            if let selected {
                Disclaimer("Selected: \(pathPrefix) / \(selected.name)\nOnly this folder will be accessible to PuffyMeter.")
            }
            Button("Use this folder") {
                guard let selected else { return }
                onChoose(DriveFolderRef(id: selected.id, name: selected.name, path: "\(pathPrefix) / \(selected.name)"))
            }
            .buttonStyle(.pmPrimary)
            .disabled(selected == nil)
        }
        .task(id: "\(parentID ?? "root")|\(query)") { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showNewFolder) {
            NavigationStack {
                NewFolderView(parentID: parentID, pathPrefix: pathPrefix) { folder in
                    showNewFolder = false
                    folders.append(folder)
                    folders.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
                    selected = folder
                }
            }
        }
    }

    @ViewBuilder private var folderList: some View {
        switch loadState {
        case .loading:
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { _ in
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 4).fill(Color.pmCardElevated).frame(width: 24, height: 20)
                            RoundedRectangle(cornerRadius: 4).fill(Color.pmCardElevated).frame(width: 140, height: 14)
                            Spacer()
                        }
                        .padding(Spacing.cardPadding)
                    }
                }
            }
            .redacted(reason: .placeholder)
        case .failed:
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Couldn't load folders.").font(.headline)
                    Button("Retry") { Task { await load() } }.foregroundStyle(Color.pmAccent).buttonStyle(.plain)
                }
            }
        case .loaded:
            if folders.isEmpty {
                Card {
                    Text(query.isEmpty ? "No folders here. Create one with New Folder." : "No folders match \u{201C}\(query)\u{201D}.")
                        .font(.subheadline).foregroundStyle(Color.pmLabelSecondary).wrapping()
                }
            } else {
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(folders) { folder in
                            folderRow(folder)
                            if folder.id != folders.last?.id {
                                Divider().overlay(Color.pmSeparator).padding(.leading, 56)
                            }
                        }
                    }
                }
            }
        }
    }

    private func folderRow(_ folder: DriveFolder) -> some View {
        HStack(spacing: 12) {
            Button {
                selected = folder
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "folder").foregroundStyle(Color.pmAccent).frame(width: 28)
                    Text(folder.name).foregroundStyle(Color.pmLabel)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if selected?.id == folder.id {
                Image(systemName: "checkmark").foregroundStyle(Color.pmAccent).fontWeight(.semibold)
            } else {
                Button {
                    trail.append(folder)
                    selected = nil
                } label: {
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.pmLabelTertiary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(folder.name)")
            }
        }
        .padding(.leading, Spacing.cardPadding)
        .padding(.trailing, 6)
        .frame(minHeight: 52)
        .accessibilityAddTraits(selected?.id == folder.id ? .isSelected : [])
    }

    private func load() async {
        if folders.isEmpty { loadState = .loading }
        do {
            folders = try await model.services.drive.listFolders(parentID: parentID, query: query)
            if selected == nil, trail.isEmpty, model.settings.drive.folder == nil {
                selected = folders.first { $0.name == DriveNaming.defaultFolderName }
            }
            if let current = model.settings.drive.folder, selected == nil {
                selected = folders.first { $0.id == current.id }
            }
            loadState = .loaded
        } catch {
            loadState = .failed
        }
    }
}

public struct NewFolderView: View {
    var parentID: String?
    var pathPrefix: String
    var onCreated: (DriveFolder) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = DriveNaming.defaultFolderName
    @State private var isWorking = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    public init(parentID: String?, pathPrefix: String, onCreated: @escaping (DriveFolder) -> Void) {
        self.parentID = parentID
        self.pathPrefix = pathPrefix
        self.onCreated = onCreated
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var body: some View {
        ScreenScaffold("New Folder", subtitle: "PuffyMeter") {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color.pmLink)
                .accessibilityHidden(true)
            Text("Create a dedicated home for your daily photos and scan notes.")
                .font(.body).foregroundStyle(Color.pmLabelSecondary).wrapping()
            Text("Folder name").font(.footnote).textCase(.uppercase).foregroundStyle(Color.pmLabelSecondary)
            TextField("Folder name", text: $name)
                .font(.body)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit { Task { await create() } }
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(Color.pmCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "folder").foregroundStyle(Color.pmAccent)
                        Text("Location")
                        Spacer()
                        Text(pathPrefix.components(separatedBy: " / ").last ?? "My Drive").foregroundStyle(Color.pmLabelSecondary)
                    }
                    Text("\(pathPrefix) / \(trimmed.isEmpty ? "…" : trimmed)").font(.footnote).foregroundStyle(Color.pmLabelSecondary)
                    Text("Limited to files saved by PuffyMeter").font(.footnote).foregroundStyle(Color.pmScan)
                }
            }
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(Color.pmAccent)
            }
            Button(isWorking ? "Creating…" : "Create folder") { Task { await create() } }
                .buttonStyle(.pmPrimary)
                .disabled(trimmed.isEmpty || isWorking)
            Button("Cancel") { dismiss() }
                .buttonStyle(.pmSecondary)
        }
        .onAppear { focused = true }
    }

    private func create() async {
        guard !trimmed.isEmpty else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let folder = try await model.services.drive.createFolder(name: trimmed, parentID: parentID)
            onCreated(folder)
        } catch {
            errorMessage = "Couldn't create the folder. Check your connection and try again."
        }
    }
}

public struct DriveConnectedView: View {
    var folder: DriveFolderRef
    var onContinue: () -> Void
    var onChangeFolder: () -> Void
    @Environment(AppModel.self) private var model
    @State private var drawn = false

    public init(folder: DriveFolderRef, onContinue: @escaping () -> Void, onChangeFolder: @escaping () -> Void) {
        self.folder = folder
        self.onContinue = onContinue
        self.onChangeFolder = onChangeFolder
    }

    public var body: some View {
        ScreenScaffold("Drive connected", subtitle: "PuffyMeter") {
            ZStack {
                Circle().stroke(Color.pmScan, lineWidth: 2.5).frame(width: 78, height: 78)
                CheckmarkShape()
                    .trim(from: 0, to: drawn ? 1 : 0)
                    .stroke(Color.pmScan, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .frame(width: 30, height: 22)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .accessibilityHidden(true)
            HeroHeadline("Your daily photos\nhave a home.", alignment: .center)
            Text("New scans will be backed up automatically when you're online.")
                .font(.body).foregroundStyle(Color.pmLabelSecondary).wrapping(.center)
                .frame(maxWidth: .infinity)
            DriveFolderCard(name: folder.name, path: folder.path, email: model.settings.profile?.email,
                            status: "Connected · Access to this folder only", symbol: "folder.badge.checkmark")
            Button("Continue", action: onContinue).buttonStyle(.pmPrimary)
            Button("Change folder", action: onChangeFolder).buttonStyle(.pmSecondary)
        }
        .sensoryFeedback(.success, trigger: drawn)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.2)) { drawn = true }
        }
    }
}

struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

// MARK: - Permissions

public struct PermissionsView: View {
    var onContinue: () -> Void
    @Environment(AppModel.self) private var model
    @State private var cameraStatus: CameraAuthorization = .notDetermined
    @State private var healthConnected = false
    @State private var showTimePicker = false

    public init(onContinue: @escaping () -> Void) { self.onContinue = onContinue }

    public var body: some View {
        ScreenScaffold("Make it yours", subtitle: "PuffyMeter") {
            Text("A few permissions make your morning routine effortless. You can change them anytime.")
                .font(.body).foregroundStyle(Color.pmLabelSecondary).wrapping()

            permissionCard(symbol: "camera", title: "Camera", pill: Pill("Required", color: .pmAccent),
                           message: "Capture your face for a cosmetic puffiness estimate. Photos aren't added to your photo library.") {
                switch cameraStatus {
                case .authorized:
                    Label("Allowed", systemImage: "checkmark.circle.fill")
                        .font(.headline).foregroundStyle(Color.pmScan)
                        .frame(maxWidth: .infinity, minHeight: 44)
                case .denied:
                    VStack(spacing: 6) {
                        Text("Camera access is off. Turn it on in Settings to scan.")
                            .font(.footnote).foregroundStyle(Color.pmLabelSecondary).wrapping()
                        Button("Open Settings") { openSettings() }.buttonStyle(.pmPrimary)
                    }
                case .notDetermined:
                    Button("Allow camera") {
                        Task {
                            _ = await model.services.camera.request()
                            cameraStatus = model.services.camera.status()
                        }
                    }
                    .buttonStyle(.pmPrimary)
                }
            }

            permissionCard(symbol: "bell", title: "Notifications",
                           toggle: Binding(get: { model.settings.reminderEnabled }, set: { value in
                               Task {
                                   if value { _ = await model.services.notifications.requestAuthorization() }
                                   model.updateSettings { $0.reminderEnabled = value }
                               }
                           }),
                           message: "A gentle nudge to scan at the same time each day.") {
                Button { showTimePicker.toggle() } label: {
                    HStack {
                        Text("Morning reminder").foregroundStyle(Color.pmLabel)
                        Spacer()
                        Text(model.settings.reminderTime.formatted).foregroundStyle(Color.pmLabelSecondary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!model.settings.reminderEnabled)
                if showTimePicker {
                    DatePicker("Reminder time", selection: Binding(
                        get: { model.settings.reminderTime.date(on: model.today, calendar: model.calendar) },
                        set: { date in
                            let c = model.calendar.dateComponents([.hour, .minute], from: date)
                            model.updateSettings { $0.reminderTime = ReminderTime(hour: c.hour ?? 8, minute: c.minute ?? 0) }
                        }), displayedComponents: .hourAndMinute)
                        .pmWheelDatePicker()
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                }
            }

            permissionCard(symbol: "heart", title: "Apple Health", pill: Pill("Optional", color: .pmAccent),
                           message: "Read sleep and water to show personal patterns. PuffyMeter doesn't write facial scores to Health.") {
                if healthConnected {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .font(.headline).foregroundStyle(Color.pmScan)
                        .frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    Button("Connect Apple Health") {
                        Task {
                            try? await model.services.health.requestAuthorization()
                            healthConnected = true
                            model.updateSettings { $0.healthSyncEnabled = true }
                        }
                    }
                    .foregroundStyle(Color.pmLink)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.plain)
                    .disabled(!model.services.health.isAvailable)
                }
            }

            Button("Start my first scan", action: onContinue)
                .buttonStyle(.pmPrimary)
                .disabled(cameraStatus != .authorized)
            Disclaimer("You can continue without notifications or Health.", alignment: .center)
        }
        .onAppear {
            cameraStatus = model.services.camera.status()
            healthConnected = model.settings.healthSyncEnabled
        }
    }

    private func permissionCard<Footer: View>(symbol: String, title: String, pill: Pill? = nil, toggle: Binding<Bool>? = nil,
                                              message: String, @ViewBuilder footer: () -> Footer) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: symbol).foregroundStyle(Color.pmAccent).font(.title3).frame(width: 28)
                    Text(title).font(.headline)
                    Spacer()
                    if let pill { pill }
                    if let toggle { Toggle(title, isOn: toggle).labelsHidden().tint(.pmSuccess) }
                }
                Text(message).font(.body).foregroundStyle(Color.pmLabelSecondary).wrapping()
                footer()
            }
        }
    }

    private func openSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        #endif
    }
}

#if os(iOS)
import UIKit
#endif
