import SwiftUI

public struct SummaryView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var logging: HabitKind?
    @State private var showGoals = false

    public init() {}

    public var body: some View {
        let stats = model.todayStats
        ScreenScaffold("Summary", subtitle: Format.longDay(model.today, calendar: model.calendar)) {
            if model.needsDriveReconnect {
                BannerView(symbol: "exclamationmark.icloud", message: "Google Drive needs to reconnect",
                           actionTitle: "Reconnect") { router.presentDriveSettings() }
            } else if case .notConnected = model.settings.drive, model.settings.onboardingStep == .complete {
                BannerView(symbol: "externaldrive", message: "Back up your scans to Google Drive",
                           actionTitle: "Connect", tint: .pmLink) { router.presentDriveSettings() }
            }

            ringsCard(stats)

            if let scan = stats.primaryScan {
                scoreCard(scan)
                SectionHeader("Face zones", large: true)
                faceZones(scan)
            } else {
                emptyScoreCard
            }

            SectionHeader("Last 7 days", large: true, actionTitle: "Trends") { router.selectedTab = .trends }
            weekCard

            streakCard

            if !model.dailyInsights.isEmpty {
                SectionHeader("Daily insights", large: true)
                ForEach(model.dailyInsights) { insight in
                    InsightCard(symbol: insight.symbol, title: insight.title, message: insight.body,
                                footnote: insight.footnote)
                }
            } else if model.history.scanDays.count < 7 {
                SectionHeader("Daily insights", large: true)
                InsightCard(symbol: "sparkles", title: "Insights are on the way",
                            message: "Insights appear after a week of scans.", footnote: nil)
            }

            SectionHeader("Quick log", large: true)
            FlowLayout(spacing: 8) {
                ForEach(HabitKind.allCases) { kind in
                    HabitChip(kind: kind, log: model.todayLog, waterGoal: stats.goals.waterGoalLiters) {
                        logging = kind
                    }
                }
            }

            Disclaimer("Cosmetic wellness only. Scores can vary with lighting, expression, and daily changes.")
                .padding(.top, 4)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showGoals = true }
                    .tint(.pmAccent)
                    .accessibilityHint("Change your daily goals")
            }
        }
        .sheet(item: $logging) { kind in
            QuickLogSheet(kind: kind)
                .presentationDetents([.height(360)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showGoals) {
            NavigationStack { GoalsEditorView(dismissOnSave: true) }
        }
    }

    // MARK: Cards

    private func ringsCard(_ stats: DayStats) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 20) {
                        ActivityRings(stats.rings, size: .card)
                        RingLegend(stats: stats)
                        Spacer(minLength: 0)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        ActivityRings(stats.rings, size: .card).frame(maxWidth: .infinity)
                        RingLegend(stats: stats)
                    }
                }
                Text(RingMath.caption(for: stats))
                    .font(.footnote)
                    .foregroundStyle(Color.pmLabelSecondary)
                    .wrapping()
            }
        }
    }

    private func scoreCard(_ scan: ScanRecord) -> some View {
        Card {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    scoreText(scan)
                    Spacer(minLength: 0)
                    ScanPhotoView(fileName: scan.thumbnailFileName ?? scan.photoFileName)
                        .frame(width: 126, height: 162)
                }
                VStack(alignment: .leading, spacing: 12) {
                    scoreText(scan)
                    ScanPhotoView(fileName: scan.photoFileName).aspectRatio(3 / 4, contentMode: .fit)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { router.showScanDetail(scan.id) }
        .accessibilityAddTraits(.isButton)
    }

    private func scoreText(_ scan: ScanRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Puffiness Score").font(.headline)
            Text("\(scan.score)")
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.pmAccent)
                .accessibilityLabel("Score \(scan.score)")
            MetricDelta(model.history.deltaVsPrevious(for: scan.dayKey), font: .footnote)
            Text("0–100 · Lower is better").font(.footnote).foregroundStyle(Color.pmLabelSecondary)
            Text("Scanned at \(Format.time(scan.capturedAt))").font(.footnote).foregroundStyle(Color.pmLabelSecondary)
            if scan.lowConfidence {
                Label("Lower confidence: lighting or angle differed", systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(Color.pmWarning)
            }
            syncLabel(scan).padding(.top, 4)
        }
    }

    @ViewBuilder private func syncLabel(_ scan: ScanRecord) -> some View {
        switch model.uploadCardState(for: scan.id) {
        case .saved:
            Label("Saved in \(model.settings.drive.folder?.name ?? "Google Drive")", systemImage: "checkmark.icloud")
                .font(.footnote).foregroundStyle(Color.pmLabelSecondary)
                .symbolRenderingMode(.multicolor)
        case .uploading:
            Label("Uploading to Google Drive", systemImage: "icloud.and.arrow.up")
                .font(.footnote).foregroundStyle(Color.pmHabits)
        case .failed:
            Label("Upload failed · Tap to retry", systemImage: "exclamationmark.icloud")
                .font(.footnote).foregroundStyle(Color.pmAccent)
        case .queued:
            Label("Waiting to sync", systemImage: "icloud.slash")
                .font(.footnote).foregroundStyle(Color.pmLabelSecondary)
        case .localOnly:
            Label("Saved on this iPhone", systemImage: "iphone")
                .font(.footnote).foregroundStyle(Color.pmLabelSecondary)
        }
    }

    private var emptyScoreCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text(model.hasBaseline ? "Today's scan" : "Set your baseline").font(.headline)
                Text(model.hasBaseline
                     ? "Take today's scan to see your Puffiness Score."
                     : "Take your baseline scan to start tracking.")
                    .font(.subheadline).foregroundStyle(Color.pmLabelSecondary).wrapping()
                if let previous = model.history.previousScore(before: model.today) {
                    Text("Last score: \(previous)").font(.footnote).foregroundStyle(Color.pmLabelSecondary)
                }
                Button("Scan now") { router.selectedTab = .scan }
                    .buttonStyle(.pmPrimary)
                    .padding(.top, 4)
            }
        }
    }

    private func faceZones(_ scan: ScanRecord) -> some View {
        let deltas = model.history.zoneDeltaVsPrevious(for: scan.dayKey)
        return Card(padding: 0) {
            VStack(spacing: 0) {
                ForEach(FaceZone.allCases) { zone in
                    HStack(alignment: .firstTextBaseline) {
                        Text(zone.title).font(.body)
                        Spacer()
                        Text("\(scan.zones.value(for: zone))")
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                        if let delta = deltas?.value(for: zone), delta != 0 {
                            HStack(spacing: 2) {
                                Image(systemName: delta < 0 ? "arrow.down" : "arrow.up")
                                Text("\(abs(delta))")
                            }
                            .font(.caption)
                            .foregroundStyle(delta < 0 ? Color.pmScan : Color.pmAccent)
                            .frame(minWidth: 34, alignment: .trailing)
                        } else {
                            Color.clear.frame(width: 34, height: 1)
                        }
                    }
                    .padding(.horizontal, Spacing.cardPadding)
                    .padding(.vertical, 9)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var weekCard: some View {
        let series = TrendAggregator.series(.week, history: model.history, today: model.today)
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(series.average.map { "\(Int($0.rounded()))" } ?? "--")
                        .metricFont(.large)
                        .foregroundStyle(Color.pmAccent)
                    if let delta = series.deltaVsPrevious {
                        Text("average · \(delta == 0 ? "same as" : (delta < 0 ? "↓ \(-delta) from" : "↑ \(delta) from")) last week")
                            .font(.body).foregroundStyle(Color.pmLabelSecondary)
                    } else {
                        Text("average").font(.body).foregroundStyle(Color.pmLabelSecondary)
                    }
                }
                ScoreBarChart(points: series.points, goal: nil, height: 140)
                Text("\(Format.range(series.start, series.end, calendar: model.calendar)) · Lower is better")
                    .font(.footnote).foregroundStyle(Color.pmLabelSecondary)
            }
        }
    }

    private var streakCard: some View {
        let streak = model.streak
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "flame").foregroundStyle(Color.pmAccent).font(.title3)
                    Text(streak > 0 ? "\(streak)-day scan streak" : "Start a streak").font(.title3.bold())
                }
                StreakRow(days: model.lastSevenDays)
                Text(streakMessage(streak)).font(.footnote).foregroundStyle(Color.pmLabelSecondary)
            }
        }
    }

    private func streakMessage(_ streak: Int) -> String {
        switch streak {
        case 0: "Scan tomorrow morning to begin."
        case 1...2: "A good start. Same time tomorrow?"
        case 3...6: "Your morning routine is building."
        default: "Your morning routine is taking shape."
        }
    }
}
