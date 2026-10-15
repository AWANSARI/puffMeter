import SwiftUI

public struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var confirmSignOut = false

    public init() {}

    public var body: some View {
        @Bindable var model = model
        List {
            Section {
                accountRow
            } header: {
                ScreenSubtitle("Your routine, your privacy").textCase(nil).padding(.leading, -16)
            }

            Section("Photo storage") {
                NavigationLink(value: Route.driveSettings) {
                    HStack {
                        RowIcon("externaldrive", color: .pmLink)
                        Text("Google Drive folder")
                        Spacer()
                        Text(driveStatus).foregroundStyle(Color.pmLabelSecondary)
                    }
                }
                if let folder = model.settings.drive.folder {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(folder.path)
                        Text(lastSyncText)
                    }
                    .font(.footnote)
                    .foregroundStyle(Color.pmLabelSecondary)
                }
            }

            Section("Your daily routine") {
                Toggle(isOn: Binding(get: { model.settings.reminderEnabled },
                                     set: { value in model.updateSettings { $0.reminderEnabled = value } })) {
                    HStack { RowIcon("bell"); Text("Morning reminders") }
                }
                .tint(.pmSuccess)
                NavigationLink(value: Route.reminderTime) {
                    HStack {
                        RowIcon("clock")
                        Text("Reminder time")
                        Spacer()
                        Text(model.settings.reminderTime.formatted).foregroundStyle(Color.pmLabelSecondary)
                    }
                }
                .disabled(!model.settings.reminderEnabled)
                NavigationLink(value: Route.goals) {
                    HStack { RowIcon("target"); Text("Change daily goals") }
                }
                NavigationLink(value: Route.challenges) {
                    HStack { RowIcon("sunrise"); Text("Monthly challenges") }
                }
            }

            Section("Health & privacy") {
                Toggle(isOn: Binding(get: { model.settings.healthSyncEnabled },
                                     set: { value in model.updateSettings { $0.healthSyncEnabled = value } })) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack { RowIcon("heart"); Text("Apple Health sync") }
                        Text("Read sleep, water, and cycle data")
                            .font(.footnote).foregroundStyle(Color.pmLabelSecondary).padding(.leading, 36)
                    }
                }
                .tint(.pmSuccess)
                Toggle(isOn: Binding(get: { model.settings.faceIDLockEnabled }, set: { value in
                    Task {
                        // Authenticate before turning the lock on so users can't lock themselves out.
                        if value {
                            guard await model.services.appLock.authenticate(reason: "Turn on Face ID lock") else { return }
                        }
                        model.updateSettings { $0.faceIDLockEnabled = value }
                    }
                })) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack { RowIcon("faceid"); Text("\(model.services.appLock.biometryName) lock") }
                        Text("Require \(model.services.appLock.biometryName) when opening PuffyMeter")
                            .font(.footnote).foregroundStyle(Color.pmLabelSecondary).padding(.leading, 36)
                    }
                }
                .tint(.pmSuccess)
            }

            Section("Your data") {
                NavigationLink(value: Route.exportData) {
                    HStack { RowIcon("square.and.arrow.up", color: .pmLink); Text("Export my data") }
                }
                NavigationLink(value: Route.privacy) {
                    HStack { RowIcon("hand.raised", color: .pmLink); Text("Privacy & permissions") }
                }
                Button {
                    confirmSignOut = true
                } label: {
                    HStack { RowIcon("rectangle.portrait.and.arrow.right", color: .pmDestructive); Text("Sign out") }
                        .foregroundStyle(Color.pmDestructive)
                }
            }

            Section {
                EmptyView()
            } footer: {
                Text("PuffyMeter \(AppInfo.shortVersion) · Cosmetic wellness, not diagnosis.\nYour photos are never used for advertising.")
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
        }
        .pmInsetGroupedList()
        .scrollContentBackground(.hidden)
        .background(Color.pmBackground.ignoresSafeArea())
        .navigationTitle("Profile")
        .pmLargeTitleDisplay()
        .confirmationDialog("Sign out of PuffyMeter?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { await model.signOut(deleteLocalData: false) } }
            Button("Sign out & delete local data", role: .destructive) { Task { await model.signOut(deleteLocalData: true) } }
        } message: {
            Text("Your photos stay in Google Drive.")
        }
    }

    private var accountRow: some View {
        HStack(spacing: 14) {
            Text(model.settings.profile?.initials ?? "?")
                .font(.title2.bold())
                .foregroundStyle(Color.pmAccent)
                .frame(width: 56, height: 56)
                .background(Color.pmAccentFill, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(model.settings.profile?.displayName ?? "Guest").font(.title3.weight(.semibold))
                if let email = model.settings.profile?.email {
                    Text(email).font(.footnote).foregroundStyle(Color.pmLabelSecondary)
                }
                Text(providerText)
                    .font(.footnote).foregroundStyle(Color.pmLabelSecondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var providerText: String {
        switch model.settings.profile?.provider {
        case .apple: "Signed in with Apple"
        case .google: "Connected with Google"
        case .local, .none: "Using PuffyMeter on this iPhone"
        }
    }

    private var driveStatus: String {
        switch model.settings.drive {
        case .connected: "Connected"
        case .needsReconnect: "Reconnect"
        case .skipped, .notConnected: "Not connected"
        }
    }

    private var lastSyncText: String {
        guard let date = model.settings.lastSyncAt else { return "Not synced yet" }
        let day = DayKey(date, calendar: model.calendar) == model.today ? "Today" : Format.shortDay(DayKey(date, calendar: model.calendar))
        let pending = model.pendingUploadCount
        return "Last sync: \(day) at \(Format.time(date)) · " + (pending == 0 ? "All scans saved" : "\(Format.plural(pending, "scan")) waiting")
    }
}

// MARK: - Drive settings

public struct DriveSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var fileCount: Int?
    @State private var confirmDisconnect = false
    @State private var choosingFolder = false
    @State private var restoreMessage: String?
    @State private var isWorking = false

    public init() {}

    public var body: some View {
        @Bindable var model = model
        List {
            Section {
                if let folder = model.settings.drive.folder {
                    LabeledContent("Account", value: model.settings.profile?.email ?? "Google")
                    LabeledContent("Folder", value: folder.path)
                    LabeledContent("Files", value: fileCount.map(String.init) ?? "…")
                    LabeledContent("Last sync", value: model.settings.lastSyncAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never")
                } else {
                    Text("Scans are kept on this iPhone only. Connect Google Drive to back them up to a folder you choose.")
                        .font(.subheadline).foregroundStyle(Color.pmLabelSecondary)
                }
            }

            if model.needsDriveReconnect {
                Section {
                    Button("Reconnect Google Drive") { Task { await reconnect() } }
                        .foregroundStyle(Color.pmAccent)
                }
            }

            Section {
                if model.settings.drive.folder != nil {
                    Button("Sync now") { model.retryUploads(); Task { await model.processUploads() } }
                    Button(model.settings.drive.folder == nil ? "Connect Google Drive" : "Change folder") { choosingFolder = true }
                    Button(isWorking ? "Restoring…" : "Restore history from Drive") { Task { await restore() } }
                        .disabled(isWorking)
                } else {
                    Button("Connect Google Drive") { choosingFolder = true }
                }
            } footer: {
                if let restoreMessage { Text(restoreMessage) }
            }

            Section("Upload quality") {
                Picker("Upload quality", selection: Binding(get: { model.settings.uploadQuality },
                                                            set: { value in model.updateSettings { $0.uploadQuality = value } })) {
                    ForEach(UploadQuality.allCases) { quality in
                        Text(quality.title + (quality == .high ? " (default)" : "")).tag(quality)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            if model.settings.drive.folder != nil {
                Section {
                    Button("Disconnect Google Drive", role: .destructive) { confirmDisconnect = true }
                }
            }
        }
        .pmInsetGroupedList()
        .navigationTitle("Google Drive")
        .pmInlineTitleDisplay()
        .task {
            if let folder = model.settings.drive.folder {
                fileCount = try? await model.services.drive.fileCount(folderID: folder.id)
            }
        }
        .confirmationDialog("Disconnect Google Drive?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { model.disconnectDrive() }
        } message: {
            Text("Your photos stay in Google Drive. New scans will be kept on this iPhone until you reconnect.")
        }
        .sheet(isPresented: $choosingFolder) {
            NavigationStack {
                FolderPickerView { folder in
                    model.connectDrive(folder: folder, email: nil)
                    choosingFolder = false
                }
            }
        }
    }

    private func reconnect() async {
        do {
            _ = try await model.services.auth.requestDriveAccess()
            if let folder = model.settings.drive.folder {
                model.connectDrive(folder: folder, email: nil)
                model.retryUploads()
            }
        } catch {
            model.lastError = (error as? AuthError)?.message
        }
    }

    private func restore() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let count = try await model.restoreFromDrive()
            restoreMessage = count == 0 ? "Everything is already on this iPhone." : "Restored \(Format.plural(count, "scan"))."
        } catch {
            restoreMessage = "Couldn't restore right now. Try again later."
        }
    }
}

// MARK: - Reminder time

public struct ReminderTimeView: View {
    @Environment(AppModel.self) private var model
    @State private var time = Date()

    public init() {}

    public var body: some View {
        List {
            Section {
                DatePicker("Reminder time", selection: $time, displayedComponents: .hourAndMinute)
                    .pmWheelDatePicker()
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
            } footer: {
                Text("Scan right after waking for the most consistent comparisons.")
            }
            Section {
                Toggle("Streak saver", isOn: Binding(get: { model.settings.streakSaverEnabled },
                                                     set: { value in model.updateSettings { $0.streakSaverEnabled = value } }))
                    .tint(.pmSuccess)
            } footer: {
                Text("A gentle 11 AM nudge if you haven't scanned and have a streak of 3 days or more.")
            }
        }
        .pmInsetGroupedList()
        .navigationTitle("Reminder time")
        .pmInlineTitleDisplay()
        .onAppear { time = model.settings.reminderTime.date(on: model.today, calendar: model.calendar) }
        .onChange(of: time) {
            let comps = model.calendar.dateComponents([.hour, .minute], from: time)
            model.updateSettings { $0.reminderTime = ReminderTime(hour: comps.hour ?? 8, minute: comps.minute ?? 0) }
        }
    }
}

// MARK: - Export

public struct ExportDataView: View {
    @Environment(AppModel.self) private var model
    @State private var csvURL: URL?
    @State private var videoURL: URL?
    @State private var isExportingVideo = false

    public init() {}

    public var body: some View {
        List {
            Section {
                if let csvURL {
                    ShareLink(item: csvURL) { Label("Share scores (CSV)", systemImage: "tablecells") }
                } else {
                    Button { csvURL = writeCSV() } label: { Label("Export scores (CSV)", systemImage: "tablecells") }
                }
            } footer: {
                Text("Date, time, scores, face zones, habits, notes and tags for every scan.")
            }
            Section {
                if let videoURL {
                    ShareLink(item: videoURL) { Label("Share time-lapse", systemImage: "film") }
                } else {
                    Button {
                        Task {
                            isExportingVideo = true
                            videoURL = await TimeLapseExporter.export(scans: model.scans, photos: model.services.photos)
                            isExportingVideo = false
                        }
                    } label: {
                        Label(isExportingVideo ? "Preparing…" : "Export time-lapse (MP4)", systemImage: "film")
                    }
                    .disabled(isExportingVideo || model.scans.count < 2)
                }
            }
        }
        .pmInsetGroupedList()
        .navigationTitle("Export my data")
        .pmInlineTitleDisplay()
    }

    private func writeCSV() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PuffyMeter-scores.csv")
        do {
            try CSVExporter.csv(history: model.history).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}

// MARK: - Privacy & permissions

public struct PrivacyView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmDelete = false
    @State private var confirmDeleteFinal = false
    @State private var trashDrive = false

    public init() {}

    public var body: some View {
        List {
            Section("How PuffyMeter handles your face") {
                Label("Analysis runs on this iPhone", systemImage: "cpu")
                Label("Photos go only to your chosen Drive folder", systemImage: "folder")
                Label("No ads, no trackers, no PuffyMeter servers", systemImage: "hand.raised")
                Label("No face photo on your Lock Screen or widgets", systemImage: "lock")
            }
            .font(.subheadline)
            Section("Permissions") {
                Button("Open Settings") { openSettings() }
            }
            Section {
                Link("Privacy Policy", destination: URL(string: "https://puffymeter.app/privacy")!)
                Link("Terms of Service", destination: URL(string: "https://puffymeter.app/terms")!)
            }
            Section {
                Toggle("Also move PuffyMeter files in Drive to Trash", isOn: $trashDrive)
                Button("Delete all data", role: .destructive) { confirmDelete = true }
            } footer: {
                Text("Removes scans, photos, habits, awards and settings from this iPhone.")
            }
        }
        .pmInsetGroupedList()
        .navigationTitle("Privacy & permissions")
        .pmInlineTitleDisplay()
        .confirmationDialog("Delete all PuffyMeter data?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Continue", role: .destructive) { confirmDeleteFinal = true }
        } message: {
            Text(trashDrive ? "Local data will be erased and Drive files moved to Trash." : "Local data will be erased. Your Drive photos stay.")
        }
        .alert("This can't be undone", isPresented: $confirmDeleteFinal) {
            Button("Delete everything", role: .destructive) {
                Task { await model.deleteAllData(trashDriveFiles: trashDrive) }
            }
            Button("Cancel", role: .cancel) {}
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
