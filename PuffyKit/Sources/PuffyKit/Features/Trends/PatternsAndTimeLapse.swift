import SwiftUI

public struct PatternsView: View {
    @Environment(AppModel.self) private var model
    @State private var month: MonthKey?
    @State private var selected: DayKey?

    public init() {}

    public var body: some View {
        let shownMonth = month ?? model.today.monthKey
        ScreenScaffold("Your patterns", subtitle: "Your progress, in perspective") {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HeatmapCalendar(month: shownMonth, history: model.history, today: model.today,
                                    selected: $selected,
                                    onPrevious: { month = shownMonth.adding(months: -1, calendar: model.calendar) },
                                    onNext: { month = shownMonth.adding(months: 1, calendar: model.calendar) })
                    Text(selectedLine(selected ?? model.today))
                        .font(.footnote).foregroundStyle(Color.pmLabelSecondary)
                }
            }

            SectionHeader("Habit correlations", large: true)
            Text("Patterns in your last 30 days. Associations don't establish what caused a change.")
                .font(.body).foregroundStyle(Color.pmLabelSecondary).wrapping()
            ForEach(model.correlations) { CorrelationCard($0) }
            Disclaimer("These insights are for cosmetic wellness, not health assessment or medical advice.")
        }
        .sensoryFeedback(.selection, trigger: selected)
    }

    private func selectedLine(_ day: DayKey) -> String {
        let stats = model.history.stats(for: day)
        var parts = [Format.shortDay(day, calendar: model.calendar)]
        if let score = stats.score { parts.append("Score \(score)") } else { parts.append("No scan") }
        if let sleep = stats.habits?.sleepHours { parts.append("\(Format.hours(sleep)) sleep") }
        if let water = stats.habits?.waterLiters { parts.append("\(Format.liters(water)) water") }
        return parts.joined(separator: " · ")
    }
}

public struct TimeLapseView: View {
    @Environment(AppModel.self) private var model
    @State private var index = 0
    @State private var isPlaying = false
    @State private var speed: Double = 1
    @State private var exportURL: URL?
    @State private var isExporting = false

    public init() {}

    private var frames: [ScanRecord] { model.scans }

    public var body: some View {
        let frames = self.frames
        let current = frames.indices.contains(index) ? frames[index] : nil
        ScreenScaffold("Photo time-lapse", subtitle: "Your progress, in perspective") {
            ScanPhotoView(fileName: current?.photoFileName, cornerRadius: Spacing.photoRadius)
                .aspectRatio(3 / 4, contentMode: .fit)
                .animation(.easeInOut(duration: 0.15), value: index)
            if let current {
                HStack {
                    Text("\(Format.shortDay(current.dayKey, calendar: model.calendar)) · \(Format.time(current.capturedAt))")
                        .font(.title3)
                    Spacer()
                    Text("Score \(current.score)").font(.title3.bold()).foregroundStyle(Color.pmAccent)
                }
            }
            Slider(value: Binding(get: { Double(index) }, set: { index = Int($0.rounded()) }),
                   in: 0...Double(max(frames.count - 1, 1)), step: 1)
                .tint(.pmAccent)
                .disabled(frames.count < 2)
                .accessibilityLabel("Frame")
            HStack {
                Button {
                    speed = speed == 0.5 ? 1 : (speed == 1 ? 2 : 0.5)
                } label: {
                    Text(speed == 0.5 ? "0.5×" : speed == 1 ? "1×" : "2×")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.pmAccent)
                        .frame(width: 40, height: 40)
                        .background(Color.pmAccentFill, in: Circle())
                }
                .accessibilityLabel("Playback speed")
                Spacer()
                Button { step(-1) } label: { Image(systemName: "backward.end") }
                    .accessibilityLabel("Previous photo")
                Spacer()
                Button { isPlaying.toggle() } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill").font(.largeTitle)
                }
                .accessibilityLabel(isPlaying ? "Pause" : "Play")
                Spacer()
                Button { step(1) } label: { Image(systemName: "forward.end") }
                    .accessibilityLabel("Next photo")
                Spacer()
                Text("\(min(index + 1, frames.count)) / \(frames.count)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.pmAccent)
                    .padding(.horizontal, 10)
                    .frame(height: 40)
                    .background(Color.pmAccentFill, in: Capsule())
            }
            .font(.title2)
            .foregroundStyle(Color.pmLabel)
            .buttonStyle(.plain)
            Disclaimer("Same framing · Original photos · No smoothing", alignment: .center)
            if let exportURL {
                ShareLink(item: exportURL) { Text("Share time-lapse") }
                    .buttonStyle(.pmSecondary)
            } else {
                Button(isExporting ? "Preparing…" : "Export time-lapse") {
                    Task { await export() }
                }
                .buttonStyle(.pmSecondary)
                .disabled(isExporting || frames.count < 2)
            }
        }
        .onAppear { index = max(0, frames.count - 1) }
        .task(id: isPlaying) {
            guard isPlaying else { return }
            if index >= frames.count - 1 { index = 0 }
            while isPlaying && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(0.5 / speed))
                if index >= frames.count - 1 { isPlaying = false; break }
                index += 1
            }
        }
        .sensoryFeedback(.selection, trigger: index)
    }

    private func step(_ delta: Int) {
        isPlaying = false
        index = (index + delta).clamped(to: 0...max(frames.count - 1, 0))
    }

    private func export() async {
        isExporting = true
        defer { isExporting = false }
        exportURL = await TimeLapseExporter.export(scans: frames, photos: model.services.photos)
    }
}
