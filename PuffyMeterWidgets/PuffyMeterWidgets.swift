import WidgetKit
import SwiftUI
import PuffyKit

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    /// The snapshot is from an earlier day: show the "Scan today" state.
    var isStale: Bool { snapshot.dayKey != DayKey(date) }
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? Self.sample : (AppGroup.readWidgetSnapshot() ?? .empty)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let snapshot = AppGroup.readWidgetSnapshot() ?? .empty
        let now = Date.now
        // Refresh at midnight so the day resets; the app reloads timelines after every change.
        let midnight = Calendar.current.startOfDay(for: now.addingTimeInterval(86_400))
        completion(Timeline(entries: [SnapshotEntry(date: now, snapshot: snapshot),
                                      SnapshotEntry(date: midnight, snapshot: snapshot)],
                            policy: .after(midnight)))
    }

    static let sample = WidgetSnapshot(dayKey: DayKey(.now), score: 32, deltaVsYesterday: -8, dePuffProgress: 1.05,
                                       scanProgress: 1, habitsProgress: 0.75, scansToday: 1, habitsLogged: 3,
                                       habitsGoal: 4, streakDays: 7, updatedAt: .now)
}

// MARK: - Home Screen

struct HomeWidgetView: View {
    var entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: WidgetSnapshot { entry.snapshot }
    private var rings: RingProgress {
        entry.isStale ? .zero : RingProgress(dePuff: snapshot.dePuffProgress, scan: snapshot.scanProgress,
                                             habits: snapshot.habitsProgress)
    }

    var body: some View {
        switch family {
        case .systemMedium: medium
        default: small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Puffiness Score").font(.caption.weight(.semibold))
            if let score = snapshot.score, !entry.isStale {
                Text("\(score)")
                    .font(.system(size: 48, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.pmAccent)
                    .minimumScaleFactor(0.6)
                if let delta = snapshot.deltaVsYesterday, delta != 0 {
                    Text("\(delta < 0 ? "↓" : "↑") \(abs(delta)) points")
                        .font(.caption).foregroundStyle(delta < 0 ? Color.pmScan : Color.pmAccent)
                }
            } else {
                Spacer(minLength: 4)
                Label("Scan today", systemImage: "faceid").font(.headline).foregroundStyle(Color.pmAccent)
                Spacer(minLength: 4)
            }
            if snapshot.streakDays > 0 {
                Text("\(snapshot.streakDays)-day streak").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(URL(string: snapshot.score == nil || entry.isStale ? "puffymeter://scan" : "puffymeter://summary"))
    }

    private var medium: some View {
        HStack(spacing: 16) {
            ActivityRings(rings, size: .compact, animateOnAppear: false)
                .frame(width: 110, height: 110)
                .scaleEffect(110 / 88)
            VStack(alignment: .leading, spacing: 2) {
                Text("PuffyMeter · Today").font(.caption.weight(.semibold))
                if let score = snapshot.score, !entry.isStale {
                    Text("\(score)")
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.pmAccent)
                    if let delta = snapshot.deltaVsYesterday, delta != 0 {
                        Text("\(delta < 0 ? "↓" : "↑") \(abs(delta)) vs yesterday")
                            .font(.caption).foregroundStyle(delta < 0 ? Color.pmScan : Color.pmAccent)
                    }
                    Text("\(Format.plural(snapshot.scansToday, "scan")) · \(snapshot.habitsLogged) / \(snapshot.habitsGoal) habits")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Label("Scan today", systemImage: "faceid").font(.title3.bold()).foregroundStyle(Color.pmAccent)
                    Text("Your rings reset at midnight.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .widgetURL(URL(string: snapshot.score == nil || entry.isStale ? "puffymeter://scan" : "puffymeter://summary"))
    }
}

struct PuffyMeterHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PuffyMeterHome", provider: SnapshotProvider()) { entry in
            HomeWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.pmCard }
        }
        .configurationDisplayName("PuffyMeter")
        .description("Today's rings and Puffiness Score.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Lock Screen (never shows a face photo)

struct LockWidgetView: View {
    var entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: WidgetSnapshot { entry.snapshot }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: entry.isStale ? 0 : min(snapshot.habitsProgress, 1)) {
                Image(systemName: "face.smiling")
            } currentValueLabel: {
                Text(entry.isStale ? "--" : snapshot.score.map(String.init) ?? "--")
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
        case .accessoryInline:
            Text(entry.isStale || snapshot.score == nil
                 ? "PuffyMeter · Scan today"
                 : "PuffyMeter \(snapshot.score ?? 0) · \(snapshot.streakDays)-day streak")
        default:
            VStack(alignment: .leading, spacing: 2) {
                if let score = snapshot.score, !entry.isStale {
                    Label("PUFFINESS · \(score)", systemImage: "camera").font(.headline).widgetAccentable()
                    if let delta = snapshot.deltaVsYesterday {
                        Text(delta == 0 ? "Same as yesterday" : "\(delta < 0 ? "↓" : "↑") \(abs(delta)) vs yesterday")
                    }
                    Gauge(value: min(snapshot.habitsProgress, 1)) { EmptyView() }
                        .gaugeStyle(.accessoryLinearCapacity)
                } else {
                    Label("PuffyMeter", systemImage: "camera").font(.headline).widgetAccentable()
                    Text("Scan today")
                    if snapshot.streakDays > 0 { Text("Keep your \(snapshot.streakDays)-day streak") }
                }
            }
        }
    }
}

struct PuffyMeterLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PuffyMeterLock", provider: SnapshotProvider()) { entry in
            LockWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(URL(string: "puffymeter://summary"))
        }
        .configurationDisplayName("PuffyMeter")
        .description("Score, streak and habits. No photos.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct PuffyMeterWidgetBundle: WidgetBundle {
    var body: some Widget {
        PuffyMeterHomeWidget()
        PuffyMeterLockWidget()
    }
}
