import SwiftUI
import Charts

/// Score bars with value labels, a dashed goal rule, and today's bar highlighted.
public struct ScoreBarChart: View {
    var points: [TrendPoint]
    var goal: Int?
    var showValueLabels: Bool
    var height: CGFloat
    @Binding var selection: String?

    public init(points: [TrendPoint], goal: Int?, showValueLabels: Bool = true, height: CGFloat = 150,
                selection: Binding<String?> = .constant(nil)) {
        self.points = points
        self.goal = goal
        self.showValueLabels = showValueLabels
        self.height = height
        _selection = selection
    }

    public var body: some View {
        Chart {
            ForEach(points) { point in
                if let value = point.value {
                    BarMark(x: .value("Day", point.id), y: .value("Score", value), width: .ratio(0.62))
                        .foregroundStyle(isHighlighted(point) ? Color.pmAccent : Color.pmDePuffTrack)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        .annotation(position: .top, spacing: 4) {
                            if showValueLabels {
                                Text("\(Int(value.rounded()))")
                                    .font(.caption)
                                    .foregroundStyle(Color.pmLabelSecondary)
                            }
                        }
                } else {
                    // Keep the slot so missing days still show their label.
                    BarMark(x: .value("Day", point.id), y: .value("Score", 0))
                        .foregroundStyle(.clear)
                }
            }
            if let goal {
                RuleMark(y: .value("Goal", goal))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Color.pmLabelSecondary.opacity(0.7))
                    .accessibilityLabel("Goal \(goal)")
            }
        }
        .chartYScale(domain: 0...yMax)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: axisValues) { value in
                AxisValueLabel {
                    if let id = value.as(String.self), let point = points.first(where: { $0.id == id }) {
                        Text(point.label)
                            .font(.caption)
                            .fontWeight(isHighlighted(point) ? .semibold : .regular)
                            .foregroundStyle(isHighlighted(point) ? Color.pmLabel : Color.pmLabelSecondary)
                    }
                }
            }
        }
        .chartXSelection(value: $selection)
        .frame(height: height)
        .accessibilityChartDescriptor(ScoreChartDescriptor(points: points))
    }

    private var yMax: Double {
        let maxValue = points.compactMap(\.value).max() ?? 50
        return max(maxValue, Double(goal ?? 0)) * 1.18
    }

    private var axisValues: [String] {
        // Thin out labels for dense ranges.
        let stride = points.count > 14 ? max(1, points.count / 6) : 1
        return points.enumerated().filter { $0.offset % stride == 0 || $0.element.isCurrent }.map(\.element.id)
    }

    private func isHighlighted(_ point: TrendPoint) -> Bool {
        selection.map { $0 == point.id } ?? point.isCurrent
    }
}

struct ScoreChartDescriptor: AXChartDescriptorRepresentable {
    let points: [TrendPoint]

    func makeChartDescriptor() -> AXChartDescriptor {
        let xAxis = AXCategoricalDataAxisDescriptor(title: "Day", categoryOrder: points.map(\.label))
        let yAxis = AXNumericDataAxisDescriptor(title: "Puffiness Score", range: 0...100, gridlinePositions: []) {
            "\(Int($0)) points"
        }
        let series = AXDataSeriesDescriptor(name: "Puffiness Score", isContinuous: false,
                                            dataPoints: points.compactMap { point in
                                                point.value.map { AXDataPoint(x: point.label, y: $0) }
                                            })
        return AXChartDescriptor(title: "Puffiness Score", summary: "Lower is better", xAxis: xAxis,
                                 yAxis: yAxis, additionalAxes: [], series: [series])
    }
}

/// Seven mini rings with weekday initials (the Fitness weekly view).
public struct StreakRow: View {
    var days: [DayStats]

    public init(days: [DayStats]) { self.days = days }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(days) { stats in
                VStack(spacing: 6) {
                    ActivityRings(stats.rings, size: .mini, animateOnAppear: false)
                    Text(Format.weekdayInitial(stats.day))
                        .font(.caption)
                        .foregroundStyle(Color.pmLabelSecondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Format.longDay(stats.day))
                .accessibilityValue(stats.scanCount > 0 ? "Scanned" : "No scan")
            }
        }
    }
}

/// Month heatmap: scanned days tinted by score (brighter = lower = better).
public struct HeatmapCalendar: View {
    var month: MonthKey
    var history: History
    var today: DayKey
    @Binding var selected: DayKey?
    var onPrevious: () -> Void
    var onNext: () -> Void

    public init(month: MonthKey, history: History, today: DayKey, selected: Binding<DayKey?>,
                onPrevious: @escaping () -> Void, onNext: @escaping () -> Void) {
        self.month = month
        self.history = history
        self.today = today
        _selected = selected
        self.onPrevious = onPrevious
        self.onNext = onNext
    }

    private var calendar: Calendar { history.calendar }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(Format.monthYear(month, calendar: calendar)).font(.title2.bold())
                Spacer()
                Button(action: onPrevious) { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Previous month")
                Button(action: onNext) { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Next month")
                    .disabled(month >= today.monthKey)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.pmAccent)
            .font(.body.weight(.semibold))

            let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol).font(.caption).foregroundStyle(Color.pmLabelSecondary)
                }
                ForEach(0..<leadingBlanks, id: \.self) { _ in Color.clear.frame(height: 44) }
                ForEach(1...month.numberOfDays(calendar: calendar), id: \.self) { dayNumber in
                    dayCell(DayKey(year: month.year, month: month.month, day: dayNumber))
                }
            }

            HStack(spacing: 6) {
                Text("Lower score").font(.footnote).foregroundStyle(Color.pmLabelSecondary)
                ForEach(0..<4) { bucket in
                    RoundedRectangle(cornerRadius: 3).fill(heatColor(bucket)).frame(width: 18, height: 10)
                }
                Text("Higher").font(.footnote).foregroundStyle(Color.pmLabelSecondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func dayCell(_ day: DayKey) -> some View {
        let stats = history.stats(for: day)
        let isFuture = day > today
        let isSelected = selected == day
        let fill: Color = {
            guard let score = stats.score else { return isFuture ? Color.pmCardElevated.opacity(0.5) : Color.pmCardElevated }
            if day == today { return .pmAccent }
            return heatColor(TrendAggregator.heatBucket(score: score, goal: stats.goals.dePuffMax))
        }()
        return Button {
            selected = day
        } label: {
            Text("\(day.day)")
                .font(.subheadline.weight(stats.score != nil ? .semibold : .regular))
                .foregroundStyle(stats.score != nil ? Color.white : Color.pmLabelSecondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.pmLabel, lineWidth: 2)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .accessibilityLabel(Format.longDay(day, calendar: calendar))
        .accessibilityValue(stats.score.map { "Score \($0)" } ?? "No scan")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func heatColor(_ bucket: Int) -> Color {
        Color.pmAccent.opacity([0.95, 0.62, 0.42, 0.26][bucket.clamped(to: 0...3)])
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var leadingBlanks: Int {
        let weekday = calendar.component(.weekday, from: month.firstDay.startDate(calendar: calendar))
        return (weekday - calendar.firstWeekday + 7) % 7
    }
}
