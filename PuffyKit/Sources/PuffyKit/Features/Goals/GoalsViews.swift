import SwiftUI

public struct GoalsEditorView: View {
    var dismissOnSave: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var dePuff = 35
    @State private var scans = 1
    @State private var habits = 4
    @State private var saved = false

    public init(dismissOnSave: Bool = false) { self.dismissOnSave = dismissOnSave }

    public var body: some View {
        ScreenScaffold("Your daily goals", subtitle: "PuffyMeter") {
            Text("Make your rings work for you. Adjust your goals as your routine evolves.")
                .font(.body).foregroundStyle(Color.pmLabelSecondary).wrapping()
            GoalStepperCard(kind: .dePuff, value: $dePuff, range: GoalSet.dePuffRange, unitTitle: "Score or lower",
                            message: "Close this ring when your score meets your goal. Lower is better.")
            GoalStepperCard(kind: .scan, value: $scans, range: GoalSet.scansRange,
                            unitTitle: scans == 1 ? "Scan per day" : "Scans per day",
                            message: "One consistent morning scan is enough.")
            GoalStepperCard(kind: .habits, value: $habits, range: GoalSet.habitsRange, unitTitle: "Check-ins per day",
                            message: "Water, sleep, salt, and alcohol. Log honestly, not perfectly.")
            Button("Save goals") {
                var goals = model.currentGoals
                goals.dePuffMax = dePuff
                goals.scansPerDay = scans
                goals.habitsPerDay = habits
                model.updateGoals(goals)
                saved.toggle()
                dismiss()
            }
            .buttonStyle(.pmPrimary)
            .padding(.top, 4)
            Disclaimer("Goals support your routine. They are not medical targets.", alignment: .center)
        }
        .sensoryFeedback(.success, trigger: saved)
        .toolbar {
            if dismissOnSave {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            let goals = model.currentGoals
            dePuff = goals.dePuffMax
            scans = goals.scansPerDay
            habits = goals.habitsPerDay
        }
    }
}

public struct ChallengesView: View {
    @Environment(AppModel.self) private var model
    @State private var showPast = false

    public init() {}

    public var body: some View {
        let monthName = model.today.startDate(calendar: model.calendar).formatted(.dateTime.month(.wide))
        let statuses = model.challengeStatuses
        ScreenScaffold("\(monthName) challenges", subtitle: "PuffyMeter") {
            if statuses.isEmpty {
                InsightCard(symbol: "calendar", title: "No challenges this month",
                            message: "New challenges open on the first of each month.", footnote: nil)
            }
            ForEach(Array(statuses.enumerated()), id: \.element.id) { index, status in
                ChallengeCard(status: status, showsHeroIcon: index == 0) {
                    model.joinChallenge(status.id)
                }
            }
            if let next = model.nextMonthChallenges.first(where: \.requiresJoin) ?? model.nextMonthChallenges.first {
                let nextMonth = next.month.firstDay.startDate(calendar: model.calendar).formatted(.dateTime.month(.wide))
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Next month: \(next.title)").font(.headline)
                        Text("\(nextMonth)'s \(next.title.lowercased()) challenge opens on \(Format.shortDay(next.month.firstDay)).")
                            .font(.body).foregroundStyle(Color.pmLabelSecondary).wrapping()
                    }
                }
            }
            Button("View all challenges") { showPast = true }
                .buttonStyle(.pmSecondary)
        }
        .sheet(isPresented: $showPast) {
            NavigationStack { AllChallengesView() }
        }
    }
}

struct AllChallengesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let months = Array(Set(model.challengeDefinitions.map(\.month))).sorted(by: >)
        List {
            ForEach(months, id: \.self) { month in
                Section(Format.monthYear(month, calendar: model.calendar)) {
                    ForEach(ChallengeEngine.definitions(for: month, in: model.challengeDefinitions)) { challenge in
                        let status = ChallengeEngine.status(of: challenge, history: model.history,
                                                            progressRecords: model.challengeRecords,
                                                            today: model.today, calendar: model.calendar)
                        HStack {
                            Image(systemName: challenge.symbol).foregroundStyle(challenge.accent.ring.color).frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(challenge.title)
                                Text(month > model.today.monthKey ? "Opens \(Format.shortDay(month.firstDay))"
                                     : "\(status.progress) / \(challenge.target)\(status.isComplete ? " · Complete" : "")")
                                    .font(.footnote).foregroundStyle(Color.pmLabelSecondary)
                            }
                            Spacer()
                            if status.isComplete {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.pmScan)
                            }
                        }
                    }
                }
            }
        }
        .pmInsetGroupedList()
        .navigationTitle("All challenges")
        .pmInlineTitleDisplay()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
    }
}
