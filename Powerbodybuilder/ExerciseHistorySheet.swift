import SwiftUI
import SwiftData
import Charts

// ═══════════════════════════════════════════
// EXERCISE HISTORY SHEET
// ═══════════════════════════════════════════
// Tap any exercise name → see full session history, trend chart, PRs

struct ExerciseHistorySheet: View {
    let exerciseKey: String
    let displayName: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allLogs: [WorkoutLog]
    @Query private var allExercises: [Exercise]
    @Query(filter: #Predicate<UserProgramInstance> { $0.isActive == true })
    private var activeInstances: [UserProgramInstance]
    @State private var cueText: String = ""
    @State private var isEditingCue: Bool = false
    @State private var showStrengthGoal: Bool = false

    private var exercise: Exercise? {
        allExercises.first(where: { $0.exerciseKey == exerciseKey })
    }

    private var exerciseLogs: [WorkoutLog] {
        allLogs.filter { $0.exerciseKey == exerciseKey }
            .sorted { $0.workoutDate > $1.workoutDate }
    }

    private var sessionGroups: [(date: Date, logs: [WorkoutLog])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: exerciseLogs) { cal.startOfDay(for: $0.workoutDate) }
        return grouped.sorted { $0.key > $1.key }.map { (date: $0.key, logs: $0.value.sorted { $0.setIndex < $1.setIndex }) }
    }

    private var bestE1RM: Double {
        exerciseLogs.map { $0.e1rm }.max() ?? 0
    }

    private var bestWeight: Double {
        exerciseLogs.map { $0.weight }.max() ?? 0
    }

    private var totalSessions: Int { sessionGroups.count }

    // e1RM trend — best e1RM per session, chronological
    private var trendData: [(session: Int, e1rm: Double, date: Date)] {
        let chronological = sessionGroups.reversed()
        return chronological.enumerated().map { idx, group in
            let best = group.logs.map { $0.e1rm }.max() ?? 0
            return (idx + 1, best, group.date)
        }
    }

    var body: some View {
        ZStack {
            Color.appBG.ignoresSafeArea()
            VStack(spacing: 0) {
                // Drag handle
                RoundedRectangle(cornerRadius: 3).fill(Color.appBorder)
                    .frame(width: 36, height: 4).padding(.top, 12)

                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("EXERCISE HISTORY")
                            .font(.system(size: 11, weight: .bold)).foregroundColor(.appRed).kerning(2)
                        Text(displayName)
                            .font(.system(size: 20, weight: .black, design: .rounded)).foregroundColor(.appTextPrimary)
                    }
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold)).foregroundColor(.appTextSecondary)
                            .frame(width: 32, height: 32).background(Color.appSurface2).clipShape(Circle())
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(Color.appSurface)
                .overlay(Rectangle().frame(height: 1).foregroundColor(.appBorder), alignment: .bottom)

                if exerciseLogs.isEmpty {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            cueSection
                            Spacer(minLength: 40)
                            VStack(spacing: 12) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 36)).foregroundColor(.appTextDim)
                                Text("No history yet")
                                    .font(.system(size: 16, weight: .bold)).foregroundColor(.appTextSecondary)
                                Text("Complete a workout with this exercise to see your history here.")
                                    .font(.system(size: 13)).foregroundColor(.appTextDim)
                                    .multilineTextAlignment(.center).padding(.horizontal, 40)
                            }
                            Spacer(minLength: 40)
                        }
                        .padding(16)
                    }
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            cueSection
                            statsRow
                            // Strength goal button (only for compounds)
                            if let def = ExerciseDictionary.all[exerciseKey], def.isCompound {
                                Button { showStrengthGoal = true } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "target").font(.system(size: 13))
                                        Text("Set Strength Goal").font(.system(size: 13, weight: .bold))
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.system(size: 10))
                                    }
                                    .foregroundColor(.appRed)
                                    .padding(12).background(Color.appRed.opacity(0.06)).cornerRadius(10)
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appRed.opacity(0.15), lineWidth: 1))
                                }.buttonStyle(.plain)
                            }
                            e1rmChart
                            sessionsSection
                        }
                        .padding(16).padding(.bottom, 40)
                    }
                }
            }
        }
        .onAppear {
            cueText = exercise?.cue ?? ""
        }
        .sheet(isPresented: $showStrengthGoal) {
            StrengthGoalCreatorSheet(
                instance: activeInstances.first,
                exercises: allExercises,
                allLogs: allLogs
            )
            .presentationDetents([.large])
        }
    }

    // ── Cue ────────────────────────────────────────────────────────────

    private var cueSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "quote.opening")
                    .font(.system(size: 11, weight: .bold)).foregroundColor(.appGold)
                Text("EXERCISE CUE")
                    .font(.system(size: 10, weight: .bold)).foregroundColor(.appTextDim).kerning(1.5)
                Spacer()
                if !isEditingCue {
                    Button(action: { isEditingCue = true }) {
                        Text(cueText.isEmpty ? "Add" : "Edit")
                            .font(.system(size: 12, weight: .bold)).foregroundColor(.appGold)
                    }
                }
            }

            if isEditingCue {
                HStack(spacing: 8) {
                    TextField("e.g. 3 second pause, squeeze at top...", text: $cueText)
                        .font(.system(size: 14)).foregroundColor(.appTextPrimary)
                        .padding(10)
                        .background(Color.appSurface2).cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorder, lineWidth: 1))
                    Button(action: saveCue) {
                        Text("Save")
                            .font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(Color.appGold).cornerRadius(8)
                    }
                }
            } else if !cueText.isEmpty {
                Text(cueText)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.appGold)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.appGold.opacity(0.08)).cornerRadius(8)
            }
        }
        .padding(14)
        .appCard()
    }

    private func saveCue() {
        let trimmed = cueText.trimmingCharacters(in: .whitespacesAndNewlines)
        exercise?.cue = trimmed
        cueText = trimmed
        isEditingCue = false
        try? modelContext.save()
    }

    // ── Stats ───────────────────────────────────────────────────────────

    private var statsRow: some View {
        HStack(spacing: 0) {
            PremiumStatCell(value: "\(totalSessions)", label: "SESSIONS")
            statDivider
            PremiumStatCell(value: String(format: "%.0f", bestE1RM), label: "BEST e1RM", color: .appGold)
            statDivider
            PremiumStatCell(value: String(format: "%.0f", bestWeight), label: "TOP WEIGHT", color: .appRed)
        }
        .padding(.vertical, 4).appCard()
    }

    private var statDivider: some View {
        Rectangle().fill(Color.appBorder).frame(width: 1, height: 36)
    }

    // ── e1RM Trend Chart ────────────────────────────────────────────────

    private var e1rmChart: some View {
        VStack(spacing: 10) {
            SectionHeader(title: "e1RM TREND")

            if trendData.count < 2 {
                Text("Need 2+ sessions for trend")
                    .font(.system(size: 13)).foregroundColor(.appTextDim)
                    .frame(maxWidth: .infinity).padding(.vertical, 30)
                    .appCard()
            } else {
                Chart(trendData.suffix(20), id: \.session) { point in
                    LineMark(
                        x: .value("Session", point.session),
                        y: .value("e1RM", point.e1rm)
                    )
                    .foregroundStyle(Color.appRed)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Session", point.session),
                        y: .value("e1RM", point.e1rm)
                    )
                    .foregroundStyle(Color.appRed)
                    .symbolSize(30)
                }
                .chartXAxisLabel("Session", position: .bottom, alignment: .center)
                .chartYAxisLabel("e1RM", position: .leading, alignment: .center)
                .chartXAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisGridLine().foregroundStyle(Color.appBorder)
                        AxisValueLabel().foregroundStyle(Color.appTextDim)
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisGridLine().foregroundStyle(Color.appBorder)
                        AxisValueLabel().foregroundStyle(Color.appTextDim)
                    }
                }
                .frame(height: 180)
                .padding(14)
                .appCard()
            }
        }
    }

    // ── Session History ─────────────────────────────────────────────────

    private var sessionsSection: some View {
        VStack(spacing: 10) {
            SectionHeader(title: "ALL SESSIONS")

            ForEach(sessionGroups, id: \.date) { group in
                sessionCard(group: group)
            }
        }
    }

    private func sessionCard(group: (date: Date, logs: [WorkoutLog])) -> some View {
        let bestSession = group.logs.map { $0.e1rm }.max() ?? 0
        let isPR = bestSession == bestE1RM && bestE1RM > 0
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d yyyy"

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(f.string(from: group.date))
                    .font(.system(size: 13, weight: .bold)).foregroundColor(.appTextPrimary)
                if isPR {
                    Text("PR")
                        .font(.system(size: 9, weight: .black)).foregroundColor(.appGold)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.appGold.opacity(0.15)).cornerRadius(3)
                }
                Spacer()
                Text("e1RM \(String(format: "%.0f", bestSession))")
                    .font(.system(size: 12, weight: .bold)).foregroundColor(.appTextSecondary)
            }

            ForEach(group.logs, id: \.setIndex) { log in
                HStack(spacing: 10) {
                    Text("Set \(log.setIndex + 1)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.appTextDim)
                        .frame(width: 38)
                    Text("\(String(format: "%.0f", log.weight)) × \(log.reps)")
                        .font(.system(size: 14, weight: .bold)).foregroundColor(.appTextPrimary)
                    if log.rpe > 0 {
                        Text("RPE \(String(format: "%.1f", log.rpe))")
                            .font(.system(size: 10, weight: .semibold)).foregroundColor(.appTextDim)
                    }
                    Spacer()
                    Text(String(format: "%.0f", log.e1rm))
                        .font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.appTextSecondary)
                }
            }
        }
        .padding(14)
        .background(Color.appSurface)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
    }
}
