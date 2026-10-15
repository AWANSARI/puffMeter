import SwiftUI

public struct TrendsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var range: TrendRange = .week
    @State private var offset = 0
    @State private var selection: String?
    @State private var showGoals = false

    public init() {}

    public var body: some View {
        ScreenScaffold("Trends", subtitle: "Your progress, in perspective") {
            Picker("Range", selection: $range) {
                ForEach(TrendRange.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: range) { offset = 0; selection = nil }

            if range == .day {
                dayDetail
            } else {
                chartCard
            }

            SectionHeader("Photo timeline", large: true, actionTitle: "See all") { router.trendsPath.append(.photoGrid) }
            photoTimeline
            Button {
                router.trendsPath.append(.timeLapse)
            } label: {
                Label("Play time-lapse", systemImage: "play.fill").labelStyle(.titleOnly)
            }
            .buttonStyle(.pmSecondary)
            .disabled(model.scans.count < 2)

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your days, connected").font(.title3.bold())
                    Text("Explore your calendar and the habits that show up alongside changes in your score.")
                        .font(.body).foregroundStyle(Color.pmLabelSecondary).wrapping()
                    Button {
                        router.trendsPath.append(.patterns)
                    } label: {
                        HStack(spacing: 2) {
                            Text("Calendar & correlations")
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                        }
                        .foregroundStyle(Color.pmAccent)
                    }
                    .buttonStyle(.plain)
                }
            }

            Disclaimer("Compare trends, not single numbers. Facial appearance naturally varies day to day.")
        }
        .sheet(isPresented: $showGoals) {
            NavigationStack { GoalsEditorView(dismissOnSave: true) }
        }
    }

    private var chartCard: some View {
        let series = TrendAggregator.series(range, history: model.history, today: model.today, offset: offset)
        let goal = model.currentGoals.dePuffMax
        let selected = selection.flatMap { id in series.points.first { $0.id == id } }
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Puffiness Score").font(.headline)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(displayValue(selected?.value ?? series.average))
                        .font(.system(size: 56, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.pmAccent)
                        .contentTransition(.numericText())
                    Text(selected.map { selectedLabel($0) } ?? range.averageLabel)
                        .font(.title3).foregroundStyle(Color.pmLabelSecondary)
                }
                if selected == nil, let delta = series.deltaVsPrevious {
                    MetricDelta(delta, suffix: delta == 0 ? "vs \(range.previousLabel)" : "points vs \(range.previousLabel)",
                                font: .footnote)
                }
                ScoreBarChart(points: series.points, goal: goal, showValueLabels: series.points.count <= 7,
                              height: 160, selection: $selection)
                    .gesture(DragGesture(minimumDistance: 30).onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        withAnimation(.snappy) {
                            if value.translation.width > 0 { offset -= 1 } else if offset < 0 { offset += 1 }
                            selection = nil
                        }
                    })
                    .sensoryFeedback(.selection, trigger: selection)
                Text("\(Format.range(series.start, series.end, calendar: model.calendar)) · Lower is better · Goal ≤\(goal)")
                    .font(.footnote).foregroundStyle(Color.pmLabelSecondary)
                Button {
                    showGoals = true
                } label: {
                    Text("Goal: \(goal) or lower · Edit goal ›").font(.footnote).foregroundStyle(Color.pmAccent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func displayValue(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded()))" } ?? "--"
    }

    private func selectedLabel(_ point: TrendPoint) -> String {
        point.start == point.end ? Format.shortDay(point.start, calendar: model.calendar)
            : Format.range(point.start, point.end, calendar: model.calendar)
    }

    @ViewBuilder private var dayDetail: some View {
        if let scan = model.todayStats.primaryScan ?? model.scans.last {
            ScanSummaryCard(scan: scan)
        } else {
            InsightCard(symbol: "camera", title: "No scan yet", message: "Take a scan to see today's detail.", footnote: nil)
        }
    }

    private var photoTimeline: some View {
        let recent = Array(model.scans.suffix(10).reversed())
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(recent) { scan in
                    Button {
                        router.trendsPath.append(.scanDetail(scan.id))
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            ScanPhotoView(fileName: scan.thumbnailFileName ?? scan.photoFileName, cornerRadius: 12)
                                .frame(width: 118, height: 128)
                            Text("\(Format.shortDay(scan.dayKey, calendar: model.calendar)) · \(scan.score)")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.pmLabel)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(Format.longDay(scan.dayKey, calendar: model.calendar)), score \(scan.score)")
                }
            }
        }
        .scrollClipDisabled()
    }
}

/// Compact detail used by the D range and the scan detail screen.
struct ScanSummaryCard: View {
    var scan: ScanRecord
    @Environment(AppModel.self) private var model

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Format.scanTimestamp(scan.capturedAt)).font(.footnote).foregroundStyle(Color.pmLabelSecondary)
                        Text("\(scan.score)")
                            .font(.system(size: 56, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.pmAccent)
                        MetricDelta(model.history.deltaVsPrevious(for: scan.dayKey), font: .footnote)
                    }
                    Spacer()
                    ScanPhotoView(fileName: scan.thumbnailFileName ?? scan.photoFileName).frame(width: 96, height: 124)
                }
                HStack(spacing: 8) {
                    ForEach(FaceZone.allCases) { ZoneTile(zone: $0, value: scan.zones.value(for: $0)) }
                }
                if !scan.tags.isEmpty {
                    FlowLayout { ForEach(scan.tags, id: \.self) { TagChip($0, isOn: true) {} } }
                }
                if !scan.notes.isEmpty {
                    Text(scan.notes).font(.body).wrapping()
                }
            }
        }
    }
}

public struct ScanDetailView: View {
    var scanID: UUID
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    public init(scanID: UUID) { self.scanID = scanID }

    public var body: some View {
        if let scan = model.scan(id: scanID) {
            ScreenScaffold("Scan", subtitle: Format.scanTimestamp(scan.capturedAt)) {
                ScanPhotoView(fileName: scan.photoFileName, cornerRadius: Spacing.photoRadius)
                    .aspectRatio(3 / 4, contentMode: .fit)
                ScanSummaryCard(scan: scan)
                UploadStatusCard(state: model.uploadCardState(for: scan.id)) { model.retryUploads() }
                Button("Delete scan", role: .destructive) { confirmDelete = true }
                    .buttonStyle(.pmSecondary(tint: .pmDestructive))
            }
            .confirmationDialog("Delete this scan?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete scan", role: .destructive) {
                    model.deleteScan(id: scan.id)
                    dismiss()
                }
            } message: {
                Text("It's removed from PuffyMeter. Files already in Google Drive stay there.")
            }
        } else {
            ContentUnavailableView("Scan not found", systemImage: "photo")
        }
    }
}

public struct PhotoGridView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    public init() {}

    public var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)
        ScrollView {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(model.scans.reversed()) { scan in
                    Button {
                        router.trendsPath.append(.scanDetail(scan.id))
                    } label: {
                        ScanPhotoView(fileName: scan.thumbnailFileName ?? scan.photoFileName, cornerRadius: 6)
                            .aspectRatio(3 / 4, contentMode: .fill)
                            .overlay(alignment: .bottomLeading) {
                                Text("\(Format.shortDay(scan.dayKey, calendar: model.calendar)) · \(scan.score)")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(4)
                                    .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 4))
                                    .padding(4)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.margin)
        }
        .background(Color.pmBackground.ignoresSafeArea())
        .navigationTitle("All scans")
        .pmInlineTitleDisplay()
        .overlay {
            if model.scans.isEmpty {
                ContentUnavailableView("No scans yet", systemImage: "camera", description: Text("Your daily photos appear here."))
            }
        }
    }
}
