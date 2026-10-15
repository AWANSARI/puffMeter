import SwiftUI

/// Small sheet for logging one habit. Each logged habit counts as a check-in on the Habits ring.
public struct QuickLogSheet: View {
    var kind: HabitKind
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var water: Double = 0
    @State private var sleep: Double = 7.5
    @State private var salt: SaltLevel = .low
    @State private var alcohol: AlcoholLevel = .none

    public init(kind: HabitKind) { self.kind = kind }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                content
                Spacer(minLength: 0)
                Button("Save") { save() }
                    .buttonStyle(.pmPrimary)
            }
            .padding(Spacing.margin)
            .background(Color.pmBackground.ignoresSafeArea())
            .navigationTitle(kind.title)
            .pmInlineTitleDisplay()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if model.todayLog?.isLogged(kind) == true {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear", role: .destructive) {
                            model.clearHabit(kind)
                            dismiss()
                        }
                    }
                }
            }
        }
        .onAppear(perform: loadCurrent)
        .sensoryFeedback(.selection, trigger: water)
        .sensoryFeedback(.selection, trigger: sleep)
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .water:
            VStack(spacing: 16) {
                bigValue(Format.liters(water), caption: "of \(Format.liters(model.currentGoals.waterGoalLiters)) today")
                HStack(spacing: 12) {
                    stepButton("minus") { water = max(0, water - 0.25) }
                    Button("+250 ml") { water += 0.25 }.buttonStyle(.pmSecondary(tint: .pmAccent))
                    Button("+500 ml") { water += 0.5 }.buttonStyle(.pmSecondary(tint: .pmAccent))
                    stepButton("plus") { water += 0.25 }
                }
            }
        case .sleep:
            VStack(spacing: 16) {
                bigValue(Format.hours(sleep), caption: model.todayLog?.sources[.sleep] == .health ? "From Apple Health" : "Last night")
                HStack(spacing: 12) {
                    stepButton("minus") { sleep = max(0, sleep - 0.5) }
                    stepButton("plus") { sleep = min(14, sleep + 0.5) }
                }
            }
        case .salt:
            VStack(alignment: .leading, spacing: 12) {
                Text("How salty was last evening's meal?").font(.headline).wrapping()
                Picker("Salt", selection: $salt) {
                    ForEach(SaltLevel.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        case .alcohol:
            VStack(alignment: .leading, spacing: 12) {
                Text("Any drinks last evening?").font(.headline)
                Picker("Alcohol", selection: $alcohol) {
                    ForEach(AlcoholLevel.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private func bigValue(_ text: String, caption: String) -> some View {
        VStack(spacing: 4) {
            Text(text)
                .metricFont(.hero)
                .foregroundStyle(Color.pmAccent)
                .contentTransition(.numericText())
                .animation(.snappy, value: text)
            Text(caption).font(.subheadline).foregroundStyle(Color.pmLabelSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .frame(width: 52, height: 52)
                .background(Color.pmCardElevated, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "plus" ? "Increase" : "Decrease")
    }

    private func loadCurrent() {
        let log = model.todayLog
        water = log?.waterLiters ?? 0
        sleep = log?.sleepHours ?? 7.5
        salt = log?.salt ?? .low
        alcohol = log?.alcohol ?? .none
    }

    private func save() {
        let water = self.water, sleep = self.sleep, salt = self.salt, alcohol = self.alcohol
        model.logHabit({ log in
            switch kind {
            case .water: log.waterLiters = water
            case .sleep: log.sleepHours = sleep
            case .salt: log.salt = salt
            case .alcohol: log.alcohol = alcohol
            }
        }, kind: kind)
        dismiss()
    }
}
