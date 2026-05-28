import SwiftUI
import SwiftData
import Charts

struct ProgressView: View {

    @Query(filter: #Predicate<UserProgramInstance> { $0.isActive == true })
    private var activeInstances: [UserProgramInstance]
    @Query private var allInstances: [UserProgramInstance]
    @Query private var exercises: [Exercise]
    @Query private var profiles: [UserProfile]

    var instance: UserProgramInstance? { activeInstances.first }
    var profile: UserProfile? { profiles.first }

    /// User's UI density. Drives whether advanced analytics (Weak Points,
    /// Balance Ratios, Genetic Potential, Predictive 1RM) render.
    private var density: UIDensity { profile?.density ?? .advanced }

    @State private var selectedLiftKey: String? = nil
    @State private var selectedVolumeFilter: String = "All"
    @State private var historyExerciseKey: String? = nil
    @State private var historyExerciseName: String? = nil
    @State private var showExerciseHistory = false
    @State private var showWorkoutHistory = false
    @State private var activeSection: ProgressSection = .overview
    @State private var showPREntry = false

    enum ProgressSection: String, CaseIterable {
        case overview = "Overview"
        case strength = "Strength"
        case volume = "Volume"
        case history = "History"
    }

    // ── Derived data ────────────────────────────────────────────────────

    /// All logs across ALL program instances — career-wide stats
    private var allLogs: [WorkoutLog] {
        allInstances.flatMap { $0.logs }
    }

    private var exerciseNames: [String: String] {
        Dictionary(exercises.map { ($0.exerciseKey, $0.displayName) }, uniquingKeysWith: { first, _ in first })
    }

    private func displayName(for key: String) -> String {
        exerciseNames[key] ?? key.replacingOccurrences(of: "_", with: " ").capitalized
    }

    // ── Stats ────────────────────────────────────────────────────────────

    private var totalSessions: Int {
        Set(allLogs.map { Calendar.current.startOfDay(for: $0.workoutDate) }).count
    }

    private var totalSetsLogged: Int { allLogs.count }

    private var streak: Int {
        let cal = Calendar.current
        let days = Set(allLogs.map { cal.startOfDay(for: $0.date) }).sorted(by: >)
        guard !days.isEmpty else { return 0 }
        var count = 0
        var check = cal.startOfDay(for: Date())
        if !days.contains(check) { check = cal.date(byAdding: .day, value: -1, to: check)! }
        for day in days {
            if day == check { count += 1; check = cal.date(byAdding: .day, value: -1, to: check)! }
            else { break }
        }
        return count
    }

    private var totalTonnage: Double {
        allLogs.reduce(0) { $0 + $1.weight * Double($1.reps) }
    }

    private var tonnageLabel: String {
        if totalTonnage >= 1_000_000 { return String(format: "%.1fM", totalTonnage / 1_000_000) }
        if totalTonnage >= 1_000 { return String(format: "%.0fK", totalTonnage / 1_000) }
        return String(format: "%.0f", totalTonnage)
    }

    // ── PRs — heaviest set per exercise ─────────────────────────────────

    private struct PRRecord: Identifiable {
        let id: String
        let name: String
        let weight: Double
        let reps: Int
        let e1rm: Double
        let date: Date
    }

    private var exercisePRs: [PRRecord] {
        let grouped = Dictionary(grouping: allLogs) { $0.exerciseKey }
        return grouped.compactMap { key, logs in
            guard let best = logs.max(by: { $0.e1rm < $1.e1rm }), best.e1rm > 0 else { return nil }
            return PRRecord(id: key, name: displayName(for: key), weight: best.weight, reps: best.reps,
                            e1rm: best.e1rm, date: best.workoutDate)
        }
        .sorted { $0.e1rm > $1.e1rm }
    }

    /// PRs hit in the last 14 days
    private var recentPRs: [PRRecord] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        return exercisePRs.filter { $0.date >= cutoff }
    }

    /// Top 3 exercises by % e1RM improvement (need 2+ sessions)
    private var mostImproved: [(name: String, key: String, pctChange: Double)] {
        let grouped = Dictionary(grouping: allLogs) { $0.exerciseKey }
        var improvements: [(name: String, key: String, pctChange: Double)] = []
        for (key, logs) in grouped {
            let cal = Calendar.current
            let bySession = Dictionary(grouping: logs) { cal.startOfDay(for: $0.workoutDate) }
                .sorted { $0.key < $1.key }
            guard bySession.count >= 2 else { continue }
            let firstE1rm = bySession.first!.value.map { $0.e1rm }.max() ?? 0
            let lastE1rm = bySession.last!.value.map { $0.e1rm }.max() ?? 0
            guard firstE1rm > 0 else { continue }
            let pct = (lastE1rm - firstE1rm) / firstE1rm
            improvements.append((displayName(for: key), key, pct))
        }
        return improvements.sorted { $0.pctChange > $1.pctChange }
    }

    // ── e1RM Trend ──────────────────────────────────────────────────────

    private var mainLiftKeys: [String] {
        let keys = Set(allLogs.filter { $0.isMainLift }.map { $0.exerciseKey })
        return keys.sorted()
    }

    private var trendData: [(session: Int, e1rm: Double)] {
        guard let key = selectedLiftKey ?? mainLiftKeys.first else { return [] }
        let logs = allLogs.filter { $0.exerciseKey == key }
        let cal = Calendar.current
        var grouped: [Date: [WorkoutLog]] = [:]
        for log in logs { grouped[cal.startOfDay(for: log.workoutDate), default: []].append(log) }
        let sessions = grouped.sorted { $0.key < $1.key }.suffix(15)
        return sessions.enumerated().map { idx, pair in
            (idx + 1, pair.value.map { $0.e1rm }.max() ?? 0)
        }
    }

    // ── Volume Over Time (line chart data) ──────────────────────────────

    private struct VolumeDatum: Identifiable {
        let id = UUID()
        let week: Int
        let muscle: String
        let sets: Double
    }

    private var volumeHistory: [VolumeDatum] {
        guard let inst = instance else { return [] }
        let currentWk = inst.currentWeek
        let startWk = max(1, currentWk - 11)
        var result: [VolumeDatum] = []
        for wk in startWk...currentWk {
            let wkLogs = allLogs.filter { $0.week == wk }
            var muscleAcc: [String: Double] = [:]
            for log in wkLogs {
                if let def = ExerciseDictionary.all[log.exerciseKey] {
                    for n in def.directTrackingMuscles { muscleAcc[n, default: 0] += 1 }
                    for (n, w) in def.indirectTrackingMuscles { muscleAcc[n, default: 0] += w }
                } else if let ex = exercises.first(where: { $0.exerciseKey == log.exerciseKey }) {
                    for n in ex.directTrackingMuscles { muscleAcc[n, default: 0] += 1 }
                    for (n, w) in ex.indirectTrackingMuscles { muscleAcc[n, default: 0] += w }
                }
            }
            for (muscle, sets) in muscleAcc {
                result.append(VolumeDatum(week: wk, muscle: muscle, sets: sets))
            }
        }
        return result
    }

    /// Head-level volume history. Per-week, per-head set credits computed
    /// from each log's exercise headContributions. Stored with the head's
    /// rawValue in the `muscle` field so `filteredVolumeHistory` can return
    /// a `VolumeDatum` of the same shape regardless of filter granularity.
    private var headVolumeHistory: [VolumeDatum] {
        guard let inst = instance else { return [] }
        let currentWk = inst.currentWeek
        let startWk = max(1, currentWk - 11)
        var result: [VolumeDatum] = []
        for wk in startWk...currentWk {
            let wkLogs = allLogs.filter { $0.week == wk }
            var headAcc: [MuscleHead: Double] = [:]
            for log in wkLogs {
                let contributions = headContributionsFor(exerciseKey: log.exerciseKey)
                for (head, weight) in contributions {
                    headAcc[head, default: 0] += weight
                }
            }
            for (head, sets) in headAcc {
                result.append(VolumeDatum(week: wk, muscle: head.rawValue, sets: sets))
            }
        }
        return result
    }

    private func headContributionsFor(exerciseKey: String) -> [MuscleHead: Double] {
        if let def = ExerciseDictionary.all[exerciseKey] {
            return def.headContributions
        }
        if let ex = exercises.first(where: { $0.exerciseKey == exerciseKey }) {
            let stored = ex.headContributions
            return stored.isEmpty
                ? Exercise.inferHeadContributions(primary: ex.musclesPrimary,
                                                  secondary: ex.musclesSecondary)
                : stored
        }
        return [:]
    }

    /// Returns the MuscleHead enum for a filter string when it matches a
    /// head rawValue. Used by the chart to detect head-level filtering.
    private var selectedHead: MuscleHead? {
        MuscleHead(rawValue: selectedVolumeFilter)
    }

    private var filteredVolumeHistory: [VolumeDatum] {
        // Head filter — show that specific head's per-week credits.
        if let head = selectedHead {
            return headVolumeHistory.filter { $0.muscle == head.rawValue }
                .sorted { $0.week < $1.week }
        }
        if selectedVolumeFilter == "All" {
            let byWeek = Dictionary(grouping: volumeHistory) { $0.week }
            return byWeek.map { wk, data in
                VolumeDatum(week: wk, muscle: "Total", sets: data.reduce(0) { $0 + $1.sets })
            }.sorted { $0.week < $1.week }
        }
        return volumeHistory.filter { $0.muscle == selectedVolumeFilter }.sorted { $0.week < $1.week }
    }

    // ── Weak Points ─────────────────────────────────────────────────────

    private var weakPoints: [(muscle: String, avgSets: Double, deviation: Double)] {
        guard let inst = instance, inst.currentWeek >= 3 else { return [] }
        let weeksWithData = max(1, min(inst.currentWeek, 8))
        var totalByMuscle: [String: Double] = [:]
        for datum in volumeHistory { totalByMuscle[datum.muscle, default: 0] += datum.sets }
        let avgPerMuscle = totalByMuscle.mapValues { $0 / Double(weeksWithData) }
        // Only consider muscles that actually have data
        let musclesWithData = avgPerMuscle.filter { $0.value > 0 }
        guard musclesWithData.count >= 3 else { return [] }
        let overallAvg = musclesWithData.values.reduce(0, +) / Double(musclesWithData.count)
        guard overallAvg > 0 else { return [] }
        return ExerciseDictionary.trackingMuscles.compactMap { muscle in
            let avg = avgPerMuscle[muscle] ?? 0
            guard avg > 0 else { return nil }  // Skip muscles with 0 logged sets
            let deviation = (avg - overallAvg) / overallAvg
            guard deviation < -0.2 else { return nil }
            return (muscle, avg, deviation)
        }.sorted { $0.deviation < $1.deviation }
    }

    // ── Relative Strength Standards ─────────────────────────────────────

    private func strengthStandard(key: String, multiple: Double) -> (label: String, color: Color)? {
        guard multiple > 0 else { return nil }
        let standards: (beginner: Double, intermediate: Double, advanced: Double, elite: Double)
        let lk = key.lowercased()
        if lk.contains("squat") || lk.contains("hack") {
            standards = (1.0, 1.5, 2.0, 2.5)
        } else if lk.contains("bench") {
            standards = (0.75, 1.25, 1.5, 2.0)
        } else if lk.contains("deadlift") || lk.contains("rdl") || lk.contains("romanian") {
            standards = (1.25, 1.75, 2.5, 3.0)
        } else if lk.contains("overhead") || lk.contains("ohp") || (lk.contains("press") && !lk.contains("leg")) {
            standards = (0.5, 0.75, 1.0, 1.35)
        } else if lk.contains("row") {
            standards = (0.65, 1.0, 1.5, 1.75)
        } else { return nil }
        if multiple >= standards.elite { return ("ELITE", .appGold) }
        if multiple >= standards.advanced { return ("ADVANCED", .appGreen) }
        if multiple >= standards.intermediate { return ("INTERMEDIATE", .appBlue) }
        if multiple >= standards.beginner { return ("BEGINNER", .appTextSecondary) }
        return ("NOVICE", .appTextDim)
    }

    // ── Workout History (all sessions) ──────────────────────────────────

    private var allWorkoutSessions: [(date: Date, exercises: [String], totalSets: Int, totalTonnage: Double)] {
        // Group by EXACT workoutDate (session.startedAt) so multiple sessions
        // on the same calendar day stay distinct. Grouping by startOfDay
        // collapsed three different morning/midday/evening workouts into a
        // single row.
        let bySession = Dictionary(grouping: allLogs) { $0.workoutDate }
        return bySession.sorted { $0.key > $1.key }.map { date, logs in
            let exKeys = Array(Set(logs.map { $0.exerciseKey }))
            let names = exKeys.map { displayName(for: $0) }
            let tonnage = logs.reduce(0.0) { $0 + $1.weight * Double($1.reps) }
            return (date, names, logs.count, tonnage)
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    // BODY
    // ══════════════════════════════════════════════════════════════════════

    var body: some View {
        ZStack {
            Color.appBG.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                    sectionPicker
                    VStack(spacing: 20) {
                        switch activeSection {
                        case .overview: overviewContent
                        case .strength: strengthContent
                        case .volume: volumeContent
                        case .history: historyContent
                        }
                    }
                    .padding(16).padding(.bottom, 100)
                }
            }
        }
        .onAppear {
            if selectedLiftKey == nil { selectedLiftKey = mainLiftKeys.first }
        }
        .sheet(isPresented: $showExerciseHistory) {
            if let key = historyExerciseKey, let name = historyExerciseName {
                ExerciseHistorySheet(exerciseKey: key, displayName: name)
            }
        }
        .sheet(isPresented: $showPREntry) {
            PREntrySheet(
                allExercises: exercises,
                instance: instance,
                useMetric: profile?.useMetric ?? false
            )
        }
    }

    // ── Header ───────────────────────────────────────────────────────────

    private var header: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PROGRESS").font(.system(size: 11, weight: .bold)).foregroundColor(.appRed).kerning(2)
                    Text("YOUR STATS")
                        .font(.system(size: 22, weight: .black, design: .rounded)).foregroundColor(.appTextPrimary)
                }
                Spacer()
                TabHelpButton(chapter: .progress)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(LinearGradient.appHeader)
            Rectangle().frame(height: 1.5).foregroundColor(.appRed.opacity(0.5))
        }
    }

    // ── Section Picker ───────────────────────────────────────────────────

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ProgressSection.allCases, id: \.self) { section in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { activeSection = section }
                    } label: {
                        Text(section.rawValue.uppercased())
                            .font(.system(size: 11, weight: activeSection == section ? .black : .medium))
                            .foregroundColor(activeSection == section ? .white : .appTextSecondary)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(activeSection == section ? Color.appRed : Color.appSurface2)
                            .cornerRadius(8)
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 16).padding(.vertical, 12)
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    // OVERVIEW
    // ══════════════════════════════════════════════════════════════════════

    @ViewBuilder
    private var overviewContent: some View {
        statsStrip
        logPRButton
        if density.showsMostImproved, !mostImproved.isEmpty { mostImprovedSection }
        if !recentPRs.isEmpty { recentPRsSection }
        if density.showsWeakPoints, !weakPoints.isEmpty { weakPointsSection }
    }

    private var logPRButton: some View {
        Button { showPREntry = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "trophy.fill").font(.system(size: 16)).foregroundColor(.appGold)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Log a PR").font(.system(size: 15, weight: .bold)).foregroundColor(.appTextPrimary)
                    Text("Add a personal record or past best set")
                        .font(.system(size: 11)).foregroundColor(.appTextDim)
                }
                Spacer()
                Image(systemName: "plus.circle.fill").font(.system(size: 18)).foregroundColor(.appGold)
            }
            .padding(14)
            .background(Color.appGold.opacity(0.06)).cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appGold.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var statsStrip: some View {
        VStack(spacing: 8) {
            // First row — always shown.
            HStack(spacing: 0) {
                PremiumStatCell(value: "\(totalSessions)", label: "SESSIONS")
                statDivider
                PremiumStatCell(value: "\(totalSetsLogged)", label: "SETS")
                statDivider
                PremiumStatCell(value: "\(streak)", label: "STREAK", color: streak >= 3 ? .appGreen : .appRed)
            }
            .padding(.vertical, 4).appCard()

            // Second row — standard+advanced only. Minimal keeps the stat
            // strip to 3 core numbers to reduce visual load.
            if density.showsFullStatsStrip {
                HStack(spacing: 0) {
                    PremiumStatCell(value: instance != nil ? "W\(instance!.currentWeek)" : "—", label: "WEEK", color: .appGold)
                    statDivider
                    PremiumStatCell(value: tonnageLabel, label: "TONNAGE", color: .appBlue)
                    statDivider
                    PremiumStatCell(value: "\(exercisePRs.count)", label: "EXERCISES")
                }
                .padding(.vertical, 4).appCard()
            }
        }
    }

    private var statDivider: some View {
        Rectangle().fill(Color.appBorder).frame(width: 1, height: 36)
    }

    // ── Most Improved ────────────────────────────────────────────────────

    private var mostImprovedSection: some View {
        VStack(spacing: 8) {
            SectionHeader(title: "MOST IMPROVED")
            VStack(spacing: 0) {
                ForEach(Array(mostImproved.prefix(5).enumerated()), id: \.offset) { idx, item in
                    Button {
                        historyExerciseKey = item.key
                        historyExerciseName = item.name
                        showExerciseHistory = true
                    } label: {
                        HStack(spacing: 10) {
                            Text("\(idx + 1)").font(.system(size: 10, weight: .black, design: .monospaced))
                                .foregroundColor(.appTextDim).frame(width: 20)
                            Text(item.name).font(.system(size: 13, weight: .bold)).foregroundColor(.appTextPrimary)
                                .lineLimit(1)
                            Spacer()
                            HStack(spacing: 3) {
                                Image(systemName: item.pctChange >= 0 ? "arrow.up.right" : "arrow.down.right")
                                    .font(.system(size: 10, weight: .bold))
                                Text(String(format: "%+.1f%%", item.pctChange * 100))
                                    .font(.system(size: 13, weight: .black, design: .rounded))
                            }
                            .foregroundColor(item.pctChange >= 0 ? .appGreen : .appRed)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                    }.buttonStyle(.plain)

                    if idx < min(4, mostImproved.count - 1) {
                        Divider().background(Color.appBorder).padding(.leading, 44)
                    }
                }
            }.appCard()
        }
    }

    // ── Recent PRs ───────────────────────────────────────────────────────

    private var recentPRsSection: some View {
        let f = recentPRDateFormatter
        return VStack(spacing: 8) {
            SectionHeader(title: "RECENT PRs", accent: .appGold)
            VStack(spacing: 0) {
                ForEach(Array(recentPRs.prefix(5).enumerated()), id: \.offset) { idx, pr in
                    HStack(spacing: 10) {
                        Image(systemName: "trophy.fill").font(.system(size: 12)).foregroundColor(.appGold)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pr.name).font(.system(size: 13, weight: .bold)).foregroundColor(.appTextPrimary).lineLimit(1)
                            Text(f.string(from: pr.date)).font(.system(size: 10)).foregroundColor(.appTextDim)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(String(format: "%.0f", pr.e1rm))
                                .font(.system(size: 16, weight: .black, design: .rounded)).foregroundColor(.appGold)
                            Text("\(String(format: "%.0f", pr.weight))×\(pr.reps)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.appTextDim)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    if idx < min(4, recentPRs.count - 1) {
                        Divider().background(Color.appBorder).padding(.leading, 38)
                    }
                }
            }.appCard()
        }
    }

    // ── Weak Points ──────────────────────────────────────────────────────

    private var weakPointsSection: some View {
        VStack(spacing: 8) {
            SectionHeader(title: "WEAK POINTS")
            VStack(spacing: 0) {
                ForEach(Array(weakPoints.enumerated()), id: \.offset) { idx, wp in
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(weakPointColor(wp.deviation).opacity(0.15))
                                .frame(width: 36, height: 36)
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 14)).foregroundColor(weakPointColor(wp.deviation))
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(wp.muscle.uppercased())
                                .font(.system(size: 14, weight: .black)).foregroundColor(.appTextPrimary).kerning(0.5)
                            Text("\(String(format: "%.1f", wp.avgSets)) sets/week avg")
                                .font(.system(size: 11)).foregroundColor(.appTextDim)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(String(format: "%.0f", wp.deviation * 100))%")
                                .font(.system(size: 18, weight: .black, design: .rounded))
                                .foregroundColor(weakPointColor(wp.deviation))
                            Text("vs avg").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    if idx < weakPoints.count - 1 {
                        Divider().background(Color.appBorder).padding(.leading, 62)
                    }
                }
            }.appCard()
        }
    }

    private func weakPointColor(_ deviation: Double) -> Color {
        if deviation < -0.5 { return .appRed }
        if deviation < -0.35 { return .appOrange }
        return .appYellow
    }

    private var recentPRDateFormatter: DateFormatter {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }
    private var sessionDateFormatter: DateFormatter {
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f
    }
    /// Time-only formatter — used as a small subtitle to disambiguate
    /// multiple sessions on the same calendar day.
    private var sessionTimeFormatter: DateFormatter {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }

    // ══════════════════════════════════════════════════════════════════════
    // STRENGTH
    // ══════════════════════════════════════════════════════════════════════

    @ViewBuilder
    private var strengthContent: some View {
        if density.showsStrengthGoalsSection {
            strengthGoalsSection
        }
        prsSection
        e1rmTrendSection
        if density.showsBalanceRatios {
            balanceSection
        }
        if density.showsGeneticPotential {
            geneticPotentialSection
        }
    }

    // ── Strength Goals (display-only — management is in Program tab) ────

    private var strengthGoalsSection: some View {
        let goals = instance?.strengthGoals.filter({ $0.isActive }) ?? []
        let completed = instance?.strengthGoals.filter({ !$0.isActive && $0.completedAt != nil }) ?? []

        return Group {
            if !goals.isEmpty || !completed.isEmpty {
                VStack(spacing: 10) {
                    SectionHeader(title: "STRENGTH GOALS")

                    ForEach(goals, id: \.exerciseKey) { goal in
                        let currentE1RM = exercisePRs.first(where: { $0.id == goal.exerciseKey })?.e1rm ?? goal.startE1RM
                        let progress = min(1.0, max(0, (currentE1RM - goal.startE1RM) / max(goal.targetWeight - goal.startE1RM, 1)))

                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "target").font(.system(size: 13)).foregroundColor(.appRed)
                                Text(goal.displayName).font(.system(size: 13, weight: .black)).foregroundColor(.appTextPrimary)
                                Spacer()
                                Text("\(Int(goal.targetWeight)) lb")
                                    .font(.system(size: 16, weight: .black, design: .rounded)).foregroundColor(.appGold)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4).fill(Color.appSurface2).frame(height: 8)
                                    RoundedRectangle(cornerRadius: 4).fill(Color.appRed)
                                        .frame(width: max(0, geo.size.width * progress), height: 8)
                                }
                            }.frame(height: 8)
                            HStack {
                                Text("e1RM \(Int(currentE1RM)) → \(Int(goal.targetWeight)) (\(Int(progress * 100))%)")
                                    .font(.system(size: 10, weight: .bold)).foregroundColor(.appTextSecondary)
                                Spacer()
                                Text("\(goal.phase.displayName) Wk \(goal.phaseWeek)/\(goal.currentPhaseLength)")
                                    .font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim)
                            }
                        }
                        .padding(12).appCard()
                    }

                    if !completed.isEmpty {
                        VStack(spacing: 4) {
                            ForEach(completed, id: \.exerciseKey) { goal in
                                HStack(spacing: 8) {
                                    Image(systemName: "trophy.fill").font(.system(size: 11)).foregroundColor(.appGold)
                                    Text(goal.displayName).font(.system(size: 12, weight: .bold)).foregroundColor(.appTextPrimary)
                                    Spacer()
                                    Text("\(Int(goal.targetWeight))lb").font(.system(size: 13, weight: .black)).foregroundColor(.appGold)
                                }
                                .padding(.horizontal, 14).padding(.vertical, 6)
                            }
                        }.appCard()
                    }

                    Text("Manage goals in the Program tab")
                        .font(.system(size: 10)).foregroundColor(.appTextDim)
                }
            }
        }
    }

    // ── Strength Balance ──────────────────────────────────────────────────

    private var balanceSection: some View {
        let ratios = StrengthAnalytics.computeBalanceRatios(logs: allLogs)
        return Group {
            if !ratios.isEmpty {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        SectionHeader(title: "STRENGTH BALANCE")
                            .layoutPriority(1)
                        JargonHelp(termId: "balance_ratios", size: 10)
                        Spacer()
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(ratios.enumerated()), id: \.element.id) { idx, r in
                            HStack(spacing: 10) {
                                Text(r.label).font(.system(size: 12, weight: .bold)).foregroundColor(.appTextPrimary)
                                    .frame(width: 110, alignment: .leading)
                                // Ratio bar
                                GeometryReader { geo in
                                    let barW = geo.size.width
                                    let center = barW * 0.5
                                    let idealCenter = (r.idealLow + r.idealHigh) / 2
                                    let scale = barW / (idealCenter * 2.5)
                                    let markerX = min(barW, max(0, r.ratio * scale))
                                    ZStack(alignment: .leading) {
                                        // Background
                                        RoundedRectangle(cornerRadius: 3).fill(Color.appSurface2).frame(height: 8)
                                        // Ideal zone
                                        let idealStart = r.idealLow * scale
                                        let idealEnd = r.idealHigh * scale
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.appGreen.opacity(0.25))
                                            .frame(width: max(0, idealEnd - idealStart), height: 8)
                                            .offset(x: idealStart)
                                        // Marker
                                        Circle().fill(r.isBalanced ? Color.appGreen : Color.appOrange)
                                            .frame(width: 12, height: 12)
                                            .offset(x: markerX - 6)
                                    }
                                }.frame(height: 14)

                                Text(String(format: "%.2f", r.ratio))
                                    .font(.system(size: 12, weight: .black, design: .rounded))
                                    .foregroundColor(r.isBalanced ? .appGreen : .appOrange)
                                    .frame(width: 40, alignment: .trailing)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            if idx < ratios.count - 1 {
                                Divider().background(Color.appBorder).padding(.leading, 14)
                            }
                        }

                        // Imbalance advice
                        let imbalanced = ratios.filter { !$0.isBalanced }
                        if let worst = imbalanced.first {
                            Divider().background(Color.appBorder)
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 10)).foregroundColor(.appOrange)
                                let advice = worst.status == "low"
                                    ? "\(worst.label.components(separatedBy: " : ").first ?? "First") is weaker — consider adding volume"
                                    : "\(worst.label.components(separatedBy: " : ").last ?? "Second") is weaker — consider adding volume"
                                Text(advice)
                                    .font(.system(size: 11)).foregroundColor(.appTextSecondary)
                                Spacer()
                            }
                            .padding(.horizontal, 14).padding(.vertical, 8)
                        }
                    }.appCard()
                }
            }
        }
    }

    // ── Genetic Potential ─────────────────────────────────────────────────

    private var geneticPotentialSection: some View {
        let bw = profile?.bodyweight ?? 0
        let estimates = StrengthAnalytics.estimateGeneticPotential(bodyweight: bw, logs: allLogs)
        return Group {
            if !estimates.isEmpty {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        SectionHeader(title: "YOUR POTENTIAL")
                            .layoutPriority(1)
                        JargonHelp(termId: "genetic_potential", size: 10)
                        Spacer()
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(estimates.prefix(6).enumerated()), id: \.element.id) { idx, est in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(est.displayName).font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.appTextPrimary).lineLimit(1)
                                    Text("\(Int(est.currentE1RM)) / \(Int(est.estimatedCeiling)) lb")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(.appTextDim)
                                }
                                .frame(width: 130, alignment: .leading)

                                // Progress bar
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3).fill(Color.appSurface2).frame(height: 8)
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(potentialColor(est.percentOfPotential))
                                            .frame(width: max(0, geo.size.width * est.percentOfPotential / 100), height: 8)
                                    }
                                }.frame(height: 10)

                                Text("\(Int(est.percentOfPotential))%")
                                    .font(.system(size: 12, weight: .black, design: .rounded))
                                    .foregroundColor(potentialColor(est.percentOfPotential))
                                    .frame(width: 38, alignment: .trailing)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            if idx < min(5, estimates.count - 1) {
                                Divider().background(Color.appBorder).padding(.leading, 14)
                            }
                        }

                        Divider().background(Color.appBorder)
                        Text("Based on \(Int(bw))lb bodyweight. Individual genetics vary.")
                            .font(.system(size: 9)).foregroundColor(.appTextDim)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                    }.appCard()
                }
            }
        }
    }

    private func potentialColor(_ pct: Double) -> Color {
        if pct >= 80 { return .appGold }
        if pct >= 60 { return .appGreen }
        if pct >= 40 { return .appBlue }
        return .appTextSecondary
    }

    // ── Predictive 1RM (added to e1RM trend section) ─────────────────────

    private func predictionForSelectedLift() -> StrengthAnalytics.PredictedTimeline? {
        guard let key = selectedLiftKey ?? mainLiftKeys.first else { return nil }
        // Check if there's a strength goal target
        let goalTarget = instance?.strengthGoals.first(where: { $0.exerciseKey == key && $0.isActive })?.targetWeight
        // Use goal target or next milestone (nearest 25lb increment above current)
        let currentBest = exercisePRs.first(where: { $0.id == key })?.e1rm ?? 0
        let target = goalTarget ?? (ceil(currentBest / 25) * 25 + 25)
        guard target > 0 else { return nil }
        return StrengthAnalytics.predictTimeToTarget(logs: allLogs, exerciseKey: key, targetWeight: target)
    }

    private var prsSection: some View {
        VStack(spacing: 10) {
            SectionHeader(title: "PERSONAL RECORDS", accent: .appGold)

            if exercisePRs.isEmpty {
                Text("Complete some workouts to see PRs")
                    .font(.system(size: 13)).foregroundColor(.appTextDim)
                    .frame(maxWidth: .infinity).padding(.vertical, 20).appCard()
            } else {
                let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(exercisePRs.prefix(12)) { pr in
                        prTile(pr: pr)
                            .onTapGesture {
                                historyExerciseKey = pr.id
                                historyExerciseName = pr.name
                                showExerciseHistory = true
                            }
                    }
                }
            }
        }
    }

    private func prTile(pr: PRRecord) -> some View {
        let bw = profile?.bodyweight ?? 0
        let multiple = bw > 0 ? pr.e1rm / bw : 0
        let standard = strengthStandard(key: pr.id, multiple: multiple)
        let isRecent = pr.date >= (Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date())

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(pr.name).font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(.appTextPrimary).lineLimit(1)
                if isRecent {
                    Text("NEW").font(.system(size: 6, weight: .black)).foregroundColor(.appGreen)
                        .padding(.horizontal, 3).padding(.vertical, 1).background(Color.appGreen.opacity(0.15)).cornerRadius(2)
                }
            }
            Text(String(format: "%.0f", pr.e1rm))
                .font(.system(size: 28, weight: .black, design: .rounded)).foregroundColor(.appGold)
            Text("\(String(format: "%.0f", pr.weight)) × \(pr.reps)")
                .font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundColor(.appTextSecondary)
            HStack(spacing: 4) {
                if let std = standard {
                    Text(std.label).font(.system(size: 8, weight: .black)).foregroundColor(std.color)
                        .padding(.horizontal, 4).padding(.vertical, 2).background(std.color.opacity(0.12)).cornerRadius(3)
                }
                if multiple > 0 {
                    Text("\(String(format: "%.1f", multiple))× BW")
                        .font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14).background(Color.appSurface).cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
    }

    // ── e1RM Trend Chart ─────────────────────────────────────────────────

    private var e1rmTrendSection: some View {
        VStack(spacing: 10) {
            SectionHeader(title: "e1RM TREND")
            if mainLiftKeys.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(mainLiftKeys, id: \.self) { key in
                            let isSelected = (selectedLiftKey ?? mainLiftKeys.first) == key
                            Button { selectedLiftKey = key } label: {
                                Text(displayName(for: key))
                                    .font(.system(size: 11, weight: isSelected ? .black : .semibold))
                                    .foregroundColor(isSelected ? .white : .appTextSecondary)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(isSelected ? Color.appRed : Color.appSurface2).cornerRadius(6)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }

            if trendData.isEmpty {
                Text("Not enough data yet")
                    .font(.system(size: 13)).foregroundColor(.appTextDim)
                    .frame(maxWidth: .infinity).padding(.vertical, 30).appCard()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    // % change label
                    if trendData.count >= 2 {
                        let first = trendData.first!.e1rm
                        let last = trendData.last!.e1rm
                        let pct = first > 0 ? (last - first) / first * 100 : 0
                        HStack(spacing: 4) {
                            Image(systemName: pct >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 10, weight: .bold))
                            Text(String(format: "%+.1f%%", pct))
                                .font(.system(size: 13, weight: .black))
                            Text("over \(trendData.count) sessions")
                                .font(.system(size: 11)).foregroundColor(.appTextDim)
                        }
                        .foregroundColor(pct >= 0 ? .appGreen : .appRed)
                        .padding(.horizontal, 14).padding(.top, 10)
                    }

                    Chart(trendData, id: \.session) { point in
                        AreaMark(
                            x: .value("Session", point.session),
                            y: .value("e1RM", point.e1rm)
                        )
                        .foregroundStyle(LinearGradient(
                            colors: [Color.appRed.opacity(0.2), Color.appRed.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom))
                        LineMark(
                            x: .value("Session", point.session),
                            y: .value("e1RM", point.e1rm)
                        )
                        .foregroundStyle(Color.appRed)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        PointMark(
                            x: .value("Session", point.session),
                            y: .value("e1RM", point.e1rm)
                        )
                        .foregroundStyle(Color.appRed)
                        .symbolSize(20)
                    }
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
                    .frame(height: 200)
                    .padding(.horizontal, 14).padding(.bottom, 14)
                }
                .appCard()
            }

            // Predictive timeline — advanced only. Linear regression on
            // session-grouped e1RM data; needs interpretation casual users
            // wouldn't want to do.
            if density.showsPredictive1RM, let prediction = predictionForSelectedLift() {
                HStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 12)).foregroundColor(.appBlue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("At current rate: \(Int(prediction.targetWeight))lb in ~\(prediction.estimatedWeeks) weeks")
                            .font(.system(size: 12, weight: .bold)).foregroundColor(.appTextPrimary)
                        Text("+\(String(format: "%.1f", prediction.weeklyGainRate))lb/week · \(prediction.confidence) confidence")
                            .font(.system(size: 10)).foregroundColor(.appTextDim)
                    }
                    Spacer()
                    JargonHelp(termId: "predictive_1rm", size: 12)
                }
                .padding(12).background(Color.appBlue.opacity(0.06)).cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBlue.opacity(0.15), lineWidth: 1))
            }
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    // VOLUME
    // ══════════════════════════════════════════════════════════════════════

    @ViewBuilder
    private var volumeContent: some View {
        if density.showsVolumeChart {
            volumeLineSection
        }
        if density.showsFrequencyHeatmap {
            frequencyGrid
        }
        if !density.showsVolumeChart && !density.showsFrequencyHeatmap {
            // Minimal mode lands here with no content. Show a friendly nudge
            // so the tab isn't just empty.
            VStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 24)).foregroundColor(.appTextDim)
                Text("Volume tracking is available in Standard or Advanced mode")
                    .font(.system(size: 13)).foregroundColor(.appTextSecondary)
                    .multilineTextAlignment(.center)
                Text("Settings → Interface")
                    .font(.system(size: 11, weight: .bold)).foregroundColor(.appBlue)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 60)
        }
    }

    // ── Volume line chart ────────────────────────────────────────────────

    private var volumeLineSection: some View {
        // When Advanced + a specific parent muscle is selected, surface the
        // muscle's heads as a second filter row. Tapping a head filters the
        // chart to that head's per-week credits.
        let parentMuscleSelected: String? = {
            if selectedVolumeFilter == "All" { return nil }
            if MuscleHead(rawValue: selectedVolumeFilter) != nil {
                return MuscleHead(rawValue: selectedVolumeFilter)?.parentMuscle
            }
            if ExerciseDictionary.trackingMuscles.contains(selectedVolumeFilter) {
                return selectedVolumeFilter
            }
            return nil
        }()
        let showHeadChips = (density == .advanced) && (parentMuscleSelected != nil)

        return VStack(spacing: 10) {
            HStack {
                SectionHeader(title: "WEEKLY VOLUME")
                Spacer()
                if let head = selectedHead {
                    Text("\(head.parentMuscle.uppercased()) → \(head.displayName.uppercased())")
                        .font(.system(size: 9, weight: .black)).kerning(0.5)
                        .foregroundColor(.appBlue)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    volumeFilterChip("All")
                    ForEach(ExerciseDictionary.trackingMuscles, id: \.self) { muscle in
                        volumeFilterChip(muscle)
                    }
                }
            }

            // Head sub-chips — only when advanced + a parent muscle selected
            if showHeadChips, let parent = parentMuscleSelected {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(MuscleHead.heads(of: parent), id: \.self) { head in
                            volumeFilterChip(head.rawValue, displayName: head.displayName, isHead: true)
                        }
                    }
                }
                .transition(.opacity)
            }

            if filteredVolumeHistory.isEmpty {
                Text("No volume data yet")
                    .font(.system(size: 13)).foregroundColor(.appTextDim)
                    .frame(maxWidth: .infinity).padding(.vertical, 30).appCard()
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    // Volume trend summary
                    if filteredVolumeHistory.count >= 2 {
                        let first = filteredVolumeHistory.first!.sets
                        let last = filteredVolumeHistory.last!.sets
                        let delta = last - first
                        HStack(spacing: 4) {
                            Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 10, weight: .bold))
                            Text(String(format: "%+.0f sets", delta))
                                .font(.system(size: 12, weight: .bold))
                            Text("W\(filteredVolumeHistory.first!.week)→W\(filteredVolumeHistory.last!.week)")
                                .font(.system(size: 10)).foregroundColor(.appTextDim)
                        }
                        .foregroundColor(delta >= 0 ? .appGreen : .appOrange)
                        .padding(.horizontal, 14).padding(.top, 10)
                    }

                    Chart(filteredVolumeHistory) { datum in
                        AreaMark(
                            x: .value("Week", "W\(datum.week)"),
                            y: .value("Sets", datum.sets)
                        )
                        .foregroundStyle(LinearGradient(
                            colors: [muscleColor(for: selectedVolumeFilter).opacity(0.25),
                                     muscleColor(for: selectedVolumeFilter).opacity(0.02)],
                            startPoint: .top, endPoint: .bottom))
                        LineMark(
                            x: .value("Week", "W\(datum.week)"),
                            y: .value("Sets", datum.sets)
                        )
                        .foregroundStyle(muscleColor(for: selectedVolumeFilter))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        PointMark(
                            x: .value("Week", "W\(datum.week)"),
                            y: .value("Sets", datum.sets)
                        )
                        .foregroundStyle(muscleColor(for: selectedVolumeFilter))
                        .symbolSize(24)
                    }
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
                    .chartYAxisLabel("Sets", position: .leading)
                    .frame(height: 200)
                    .padding(.horizontal, 14).padding(.bottom, 14)
                }
                .appCard()
            }
        }
    }

    private func volumeFilterChip(_ filterKey: String, displayName: String? = nil, isHead: Bool = false) -> some View {
        let isSelected = selectedVolumeFilter == filterKey
        let label = (displayName ?? filterKey).uppercased()
        // Head chips use a smaller font + blue accent to distinguish them
        // visually from the parent muscle chips.
        let baseColor: Color = isHead ? .appBlue : muscleColor(for: filterKey)
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { selectedVolumeFilter = filterKey }
        } label: {
            Text(label)
                .font(.system(size: isHead ? 9 : 10, weight: isSelected ? .black : .semibold))
                .foregroundColor(isSelected ? .white : (isHead ? .appBlue : .appTextSecondary))
                .padding(.horizontal, isHead ? 8 : 10)
                .padding(.vertical, isHead ? 4 : 6)
                .background(isSelected ? baseColor : (isHead ? Color.appBlue.opacity(0.08) : Color.appSurface2))
                .cornerRadius(isHead ? 5 : 6)
                .overlay(RoundedRectangle(cornerRadius: isHead ? 5 : 6)
                    .stroke(isHead && !isSelected ? Color.appBlue.opacity(0.25) : Color.clear, lineWidth: 1))
        }.buttonStyle(.plain)
    }

    private func muscleColor(for muscle: String) -> Color {
        if muscle == "All" { return .appRed }
        // Head filter keys (e.g. "biceps_long") resolve to the parent
        // muscle's color so the chart stays visually consistent.
        if let head = MuscleHead(rawValue: muscle) {
            return muscleColor(for: head.parentMuscle)
        }
        let muscles = ExerciseDictionary.trackingMuscles
        let colors: [Color] = [.appRed, .appBlue, .appGreen, .appGold, .appOrange, .appYellow,
                                Color(red: 0.6, green: 0.4, blue: 0.8),
                                Color(red: 0.4, green: 0.7, blue: 0.9),
                                Color(red: 0.9, green: 0.5, blue: 0.6)]
        if let idx = muscles.firstIndex(of: muscle), idx < colors.count { return colors[idx] }
        return .appRed
    }

    // ── Frequency Heatmap ────────────────────────────────────────────────

    private var frequencyGrid: some View {
        let currentWk = instance?.currentWeek ?? 1
        let weeks = Array(max(1, currentWk - 3)...currentWk)
        let muscles = ExerciseDictionary.trackingMuscles

        return VStack(spacing: 8) {
            SectionHeader(title: "FREQUENCY HEATMAP")
            Text("Sessions per muscle per week").font(.system(size: 10)).foregroundColor(.appTextDim)

            VStack(spacing: 2) {
                // Week headers
                HStack(spacing: 2) {
                    Text("").frame(width: 52)
                    ForEach(weeks, id: \.self) { wk in
                        Text("W\(wk)").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim)
                            .frame(maxWidth: .infinity)
                    }
                }

                ForEach(muscles, id: \.self) { muscle in
                    HStack(spacing: 2) {
                        Text(muscle.prefix(5).uppercased())
                            .font(.system(size: 8, weight: .bold)).foregroundColor(.appTextDim)
                            .frame(width: 52, alignment: .leading)
                        ForEach(weeks, id: \.self) { wk in
                            let count = frequencyCount(muscle: muscle, week: wk)
                            Text("\(count)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(count > 0 ? .appTextPrimary : .appTextDim)
                                .frame(maxWidth: .infinity).frame(height: 28)
                                .background(heatColor(count))
                                .cornerRadius(4)
                        }
                    }
                }
            }
            .padding(12).appCard()
        }
    }

    private func frequencyCount(muscle: String, week: Int) -> Int {
        let wkLogs = allLogs.filter { $0.week == week }
        let cal = Calendar.current
        let sessionDays = Set(wkLogs.compactMap { log -> Date? in
            let def = ExerciseDictionary.all[log.exerciseKey]
            let priNorm = (def?.primaryMuscles ?? []).compactMap { ExerciseDictionary.normalizeMuscle($0) }
            if priNorm.contains(muscle) { return cal.startOfDay(for: log.workoutDate) }
            if let ex = exercises.first(where: { $0.exerciseKey == log.exerciseKey }) {
                let priNorm2 = ex.musclesPrimary.compactMap { ExerciseDictionary.normalizeMuscle($0) }
                if priNorm2.contains(muscle) { return cal.startOfDay(for: log.workoutDate) }
            }
            return nil
        })
        return sessionDays.count
    }

    private func heatColor(_ count: Int) -> Color {
        switch count {
        case 0: return Color.appSurface2
        case 1: return Color.appBlue.opacity(0.2)
        case 2: return Color.appGreen.opacity(0.3)
        default: return Color.appGreen.opacity(0.5)
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    // HISTORY — all workouts, browse any exercise
    // ══════════════════════════════════════════════════════════════════════

    @State private var historySearchText = ""
    @State private var historyMode: HistoryMode = .sessions

    enum HistoryMode: String, CaseIterable {
        case sessions = "Sessions"
        case exercises = "By Exercise"
    }

    @ViewBuilder
    private var historyContent: some View {
        // Mode toggle
        HStack(spacing: 6) {
            ForEach(HistoryMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { historyMode = mode }
                } label: {
                    Text(mode.rawValue.uppercased())
                        .font(.system(size: 11, weight: historyMode == mode ? .black : .medium))
                        .foregroundColor(historyMode == mode ? .white : .appTextSecondary)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(historyMode == mode ? Color.appRed : Color.appSurface2).cornerRadius(7)
                }.buttonStyle(.plain)
            }
            Spacer()
        }

        switch historyMode {
        case .sessions: sessionHistoryList
        case .exercises: exerciseBrowser
        }
    }

    // ── Session History ──────────────────────────────────────────────────

    private var sessionHistoryList: some View {
        let f = sessionDateFormatter
        return VStack(spacing: 8) {
            SectionHeader(title: "ALL WORKOUTS")

            if allWorkoutSessions.isEmpty {
                Text("No workouts logged yet")
                    .font(.system(size: 13)).foregroundColor(.appTextDim)
                    .frame(maxWidth: .infinity).padding(.vertical, 30).appCard()
            } else {
                // Detect days with multiple sessions so we can surface the
                // time-of-day as a disambiguating subtitle without polluting
                // the date label on single-session days.
                let tf = sessionTimeFormatter
                let cal = Calendar.current
                let dayCounts = Dictionary(grouping: allWorkoutSessions) {
                    cal.startOfDay(for: $0.date)
                }.mapValues { $0.count }

                ForEach(Array(allWorkoutSessions.enumerated()), id: \.offset) { _, session in
                    let dayKey = cal.startOfDay(for: session.date)
                    let multipleSameDay = (dayCounts[dayKey] ?? 1) > 1
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            HStack(spacing: 6) {
                                Text(f.string(from: session.date))
                                    .font(.system(size: 13, weight: .black)).foregroundColor(.appTextPrimary)
                                if multipleSameDay {
                                    Text(tf.string(from: session.date))
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.appBlue)
                                }
                            }
                            Spacer()
                            Text("\(session.totalSets) sets")
                                .font(.system(size: 11, weight: .bold)).foregroundColor(.appTextDim)
                        }
                        Text(session.exercises.prefix(4).joined(separator: " · "))
                            .font(.system(size: 11)).foregroundColor(.appTextSecondary).lineLimit(2)
                        if session.totalTonnage > 0 {
                            Text(String(format: "%.0f lbs tonnage", session.totalTonnage))
                                .font(.system(size: 10, weight: .bold)).foregroundColor(.appTextDim)
                        }
                    }
                    .padding(12).background(Color.appSurface).cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))
                }
            }
        }
    }

    // ── Exercise Browser ─────────────────────────────────────────────────

    private var exerciseBrowser: some View {
        VStack(spacing: 10) {
            SectionHeader(title: "EXERCISE HISTORY")

            // Search
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundColor(.appTextDim)
                TextField("Search exercises...", text: $historySearchText)
                    .font(.system(size: 14)).foregroundColor(.appTextPrimary)
                if !historySearchText.isEmpty {
                    Button { historySearchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.appTextDim)
                    }.buttonStyle(.plain)
                }
            }
            .padding(10).background(Color.appSurface2).cornerRadius(8)

            let allExerciseKeys = Set(allLogs.map { $0.exerciseKey })
            let filtered = allExerciseKeys.sorted { displayName(for: $0) < displayName(for: $1) }
                .filter { key in
                    if historySearchText.isEmpty { return true }
                    return displayName(for: key).lowercased().contains(historySearchText.lowercased())
                }

            if filtered.isEmpty {
                Text("No exercises found")
                    .font(.system(size: 13)).foregroundColor(.appTextDim)
                    .frame(maxWidth: .infinity).padding(.vertical, 20).appCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filtered.enumerated()), id: \.element) { idx, key in
                        let logs = allLogs.filter { $0.exerciseKey == key }
                        let sessionCount = Set(logs.map { Calendar.current.startOfDay(for: $0.workoutDate) }).count
                        let bestE1rm = logs.map { $0.e1rm }.max() ?? 0

                        Button {
                            historyExerciseKey = key
                            historyExerciseName = displayName(for: key)
                            showExerciseHistory = true
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(displayName(for: key))
                                        .font(.system(size: 13, weight: .bold)).foregroundColor(.appTextPrimary)
                                    Text("\(sessionCount) session\(sessionCount == 1 ? "" : "s")")
                                        .font(.system(size: 10)).foregroundColor(.appTextDim)
                                }
                                Spacer()
                                if bestE1rm > 0 {
                                    VStack(alignment: .trailing, spacing: 1) {
                                        Text(String(format: "%.0f", bestE1rm))
                                            .font(.system(size: 14, weight: .black, design: .rounded)).foregroundColor(.appGold)
                                        Text("e1RM").font(.system(size: 8, weight: .bold)).foregroundColor(.appTextDim)
                                    }
                                }
                                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundColor(.appTextDim)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                        }.buttonStyle(.plain)

                        if idx < filtered.count - 1 {
                            Divider().background(Color.appBorder).padding(.leading, 14)
                        }
                    }
                }.appCard()
            }
        }
    }
}

// ═══════════════════════════════════════════
// STRENGTH GOAL CREATOR
// ═══════════════════════════════════════════

struct StrengthGoalCreatorSheet: View {
    let instance: UserProgramInstance?
    let exercises: [Exercise]
    let allLogs: [WorkoutLog]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedKey: String = ""
    @State private var targetWeight: String = ""
    @State private var startingWeight: String = ""
    @State private var searchText: String = ""
    @State private var adjustProgram: Bool = true

    // Eligible: any compound, including hack squat
    private var eligibleExercises: [(key: String, name: String, currentE1RM: Double)] {
        let loggedKeys = Set(allLogs.map { $0.exerciseKey })
        let eligible = exercises.filter { ex in
            let def = ExerciseDictionary.all[ex.exerciseKey]
            guard def?.isCompound == true else { return false }
            return def?.isAnchorableAsTier1 == true || loggedKeys.contains(ex.exerciseKey)
                || ex.exerciseKey == "hack_squat"
        }
        return eligible.map { ex in
            let best = allLogs.filter { $0.exerciseKey == ex.exerciseKey }.map { $0.e1rm }.max() ?? 0
            return (key: ex.exerciseKey, name: ex.displayName, currentE1RM: best)
        }
        .filter { searchText.isEmpty || $0.name.lowercased().contains(searchText.lowercased()) }
        .sorted { $0.currentE1RM > $1.currentE1RM }
    }

    private var selectedExercise: (key: String, name: String, currentE1RM: Double)? {
        eligibleExercises.first(where: { $0.key == selectedKey })
    }

    private var effectiveStart: Double {
        if let manual = Double(startingWeight), manual > 0 { return manual }
        return selectedExercise?.currentE1RM ?? 0
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 3).fill(Color.appBorder).frame(width: 36, height: 4).padding(.top, 12)

                Text("STRENGTH GOAL").font(.system(size: 12, weight: .black)).foregroundColor(.appRed).kerning(2)
                Text("Pick a compound lift and set a target weight. The algorithm will build a peaking plan to get you there.")
                    .font(.system(size: 12)).foregroundColor(.appTextDim).multilineTextAlignment(.center)

                // ── Exercise picker ──
                VStack(alignment: .leading, spacing: 8) {
                    Text("EXERCISE").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(1)
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundColor(.appTextDim)
                        TextField("Search compound lifts...", text: $searchText)
                            .font(.system(size: 14)).foregroundColor(.appTextPrimary)
                    }
                    .padding(10).background(Color.appSurface2).cornerRadius(8)

                    VStack(spacing: 2) {
                        ForEach(eligibleExercises.prefix(8), id: \.key) { ex in
                            Button {
                                selectedKey = ex.key
                                if ex.currentE1RM > 0 {
                                    startingWeight = "\(Int(ex.currentE1RM))"
                                    targetWeight = "\(Int(RPETable.roundToPlate(ex.currentE1RM * 1.12, useMetric: false)))"
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: selectedKey == ex.key ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 16))
                                        .foregroundColor(selectedKey == ex.key ? .appRed : .appTextDim)
                                    Text(ex.name).font(.system(size: 13, weight: .bold)).foregroundColor(.appTextPrimary)
                                    Spacer()
                                    if ex.currentE1RM > 0 {
                                        Text("e1RM \(Int(ex.currentE1RM))")
                                            .font(.system(size: 11, weight: .bold)).foregroundColor(.appTextDim)
                                    }
                                }
                                .padding(.horizontal, 12).padding(.vertical, 9)
                                .background(selectedKey == ex.key ? Color.appRed.opacity(0.06) : Color.clear)
                                .cornerRadius(8)
                            }.buttonStyle(.plain)
                        }
                    }
                    .background(Color.appSurface).cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))
                }

                if selectedExercise != nil {
                    // ── Overlap warning ──
                    overlapWarning

                    // ── Starting weight ──
                    VStack(alignment: .leading, spacing: 6) {
                        Text("YOUR CURRENT MAX (e1RM)").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(1)
                        HStack(spacing: 8) {
                            TextField("e.g. 225", text: $startingWeight)
                                .font(.system(size: 20, weight: .black, design: .rounded))
                                .foregroundColor(.appTextPrimary)
                                .keyboardType(.numberPad)
                                .padding(12).background(Color.appSurface2).cornerRadius(10)
                            Text("lbs").font(.system(size: 14, weight: .bold)).foregroundColor(.appTextDim)
                        }
                        Text("Edit if auto-detected value is wrong")
                            .font(.system(size: 10)).foregroundColor(.appTextDim)
                    }

                    // ── Target weight ──
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TARGET WEIGHT").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(1)
                        HStack(spacing: 8) {
                            TextField("e.g. 275", text: $targetWeight)
                                .font(.system(size: 24, weight: .black, design: .rounded))
                                .foregroundColor(.appGold)
                                .keyboardType(.numberPad)
                                .padding(12).background(Color.appSurface2).cornerRadius(10)
                            Text("lbs").font(.system(size: 14, weight: .bold)).foregroundColor(.appTextDim)
                        }
                    }

                    // ── Program adjustment toggle ──
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PROGRAM ADJUSTMENT").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(1)

                        Button { adjustProgram = true } label: {
                            HStack(spacing: 10) {
                                Image(systemName: adjustProgram ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(adjustProgram ? .appRed : .appTextDim)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Adjust my program").font(.system(size: 13, weight: .bold)).foregroundColor(.appTextPrimary)
                                    Text("Switches this lift to strength rep ranges (3-5 reps, heavier weight). Rest of your program stays hypertrophy.")
                                        .font(.system(size: 10)).foregroundColor(.appTextDim)
                                }
                                Spacer()
                            }
                            .padding(10).background(adjustProgram ? Color.appRed.opacity(0.04) : Color.clear).cornerRadius(8)
                        }.buttonStyle(.plain)

                        Button { adjustProgram = false } label: {
                            HStack(spacing: 10) {
                                Image(systemName: !adjustProgram ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(!adjustProgram ? .appRed : .appTextDim)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Track only").font(.system(size: 13, weight: .bold)).foregroundColor(.appTextPrimary)
                                    Text("Just track your progress toward this goal. No program changes — you manage your own training.")
                                        .font(.system(size: 10)).foregroundColor(.appTextDim)
                                }
                                Spacer()
                            }
                            .padding(10).background(!adjustProgram ? Color.appRed.opacity(0.04) : Color.clear).cornerRadius(8)
                        }.buttonStyle(.plain)
                    }
                    .padding(10).background(Color.appSurface).cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))

                    // ── Phase preview (only when adjusting program) ──
                    if adjustProgram, let tw = Double(targetWeight), tw > 0, effectiveStart > 0 {
                        let gap = (tw - effectiveStart) / effectiveStart * 100
                        if gap > 0 {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("YOUR PLAN").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(1)

                                ForEach(StrengthGoalPhase.allCases, id: \.self) { phase in
                                    let wks = phase.weeksInPhase(gapPercent: gap)
                                    if wks > 0 {
                                        HStack(spacing: 8) {
                                            Circle().fill(phaseColor(phase)).frame(width: 8, height: 8)
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(phase.displayName).font(.system(size: 12, weight: .bold)).foregroundColor(.appTextPrimary)
                                                Text("\(wks) weeks · \(phase.targetSets)×\(phase.repRange.low)-\(phase.repRange.high) · RPE \(String(format: "%.0f", phase.targetRPE))")
                                                    .font(.system(size: 10)).foregroundColor(.appTextDim)
                                            }
                                            Spacer()
                                        }
                                    }
                                }

                                let total = StrengthGoalPhase.allCases.reduce(0) { $0 + $1.weeksInPhase(gapPercent: gap) }
                                Text("Total: ~\(total) weeks").font(.system(size: 11, weight: .bold)).foregroundColor(.appRed)

                                Divider().background(Color.appBorder)
                                Text("Your program will switch this lift to strength-focused rep ranges. All other exercises stay unchanged.")
                                    .font(.system(size: 10)).foregroundColor(.appTextDim)
                            }
                            .padding(12).background(Color.appSurface).cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))
                        }
                    }

                    // ── Create button ──
                    Button { createGoal() } label: {
                        Text(adjustProgram ? "SET GOAL & ADJUST PROGRAM" : "SET GOAL (TRACK ONLY)")
                            .font(.system(size: 14, weight: .black)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(canCreate ? Color.appRed : Color.appRed.opacity(0.3)).cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canCreate)
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.appBG)
        .numberPadDoneButton()
    }

    private var canCreate: Bool {
        guard selectedExercise != nil,
              let tw = Double(targetWeight), tw > 0,
              effectiveStart > 0, tw > effectiveStart else { return false }
        return true
    }

    /// Check if the selected exercise overlaps muscles with any existing active goals
    @ViewBuilder
    private var overlapWarning: some View {
        let activeGoals = instance?.strengthGoals.filter({ $0.isActive }) ?? []
        if !activeGoals.isEmpty, let sel = selectedExercise {
            let selDef = ExerciseDictionary.all[sel.key]
            let selMuscles = Set((selDef?.primaryMuscles ?? []).compactMap { ExerciseDictionary.normalizeMuscle($0) })

            let overlapping = activeGoals.filter { goal in
                let goalDef = ExerciseDictionary.all[goal.exerciseKey]
                let goalMuscles = Set((goalDef?.primaryMuscles ?? []).compactMap { ExerciseDictionary.normalizeMuscle($0) })
                return !selMuscles.isDisjoint(with: goalMuscles)
            }

            if !overlapping.isEmpty {
                let names = overlapping.map { $0.displayName }.joined(separator: " & ")
                let shared = selMuscles.intersection(
                    Set(overlapping.flatMap { goal in
                        (ExerciseDictionary.all[goal.exerciseKey]?.primaryMuscles ?? [])
                            .compactMap { ExerciseDictionary.normalizeMuscle($0) }
                    })
                ).joined(separator: ", ")

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12)).foregroundColor(.appOrange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Muscle overlap with \(names)")
                            .font(.system(size: 12, weight: .bold)).foregroundColor(.appOrange)
                        Text("Both goals share \(shared). Peaking overlapping lifts simultaneously may slow progress on both. Consider lifts that target different muscle groups.")
                            .font(.system(size: 10)).foregroundColor(.appTextDim)
                    }
                }
                .padding(10).background(Color.appOrange.opacity(0.06)).cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appOrange.opacity(0.2), lineWidth: 1))
            }
        }
    }

    private func phaseColor(_ phase: StrengthGoalPhase) -> Color {
        switch phase {
        case .building: return .appGreen
        case .intensifying: return .appOrange
        case .peaking: return .appRed
        case .testing: return .appGold
        }
    }

    private func createGoal() {
        guard let inst = instance, let ex = selectedExercise,
              let tw = Double(targetWeight), tw > effectiveStart else { return }
        let activeCount = inst.strengthGoals.filter({ $0.isActive }).count
        guard activeCount < 3 else { return }

        let goal = StrengthGoal(
            exerciseKey: ex.key,
            displayName: ex.name,
            targetWeight: tw,
            startE1RM: effectiveStart
        )
        // If track-only, skip building phase (go straight to testing to just track)
        if !adjustProgram {
            goal.phaseRaw = "testing"
        }
        inst.strengthGoals.append(goal)
        try? modelContext.save()
        dismiss()
    }
}

// ═══════════════════════════════════════════
// PR ENTRY SHEET
// ═══════════════════════════════════════════

struct PREntrySheet: View {
    let allExercises: [Exercise]
    let instance: UserProgramInstance?
    let useMetric: Bool

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var selectedExercise: Exercise? = nil
    @State private var entries: [PREntry] = [PREntry()]
    @State private var savedCount = 0

    struct PREntry: Identifiable {
        let id = UUID()
        var weightText = ""
        var repsText = ""
        var date = Date()
    }

    private var filtered: [Exercise] {
        let sorted = allExercises.sorted { $0.displayName < $1.displayName }
        if searchText.isEmpty { return sorted }
        return sorted.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.musclesPrimary.joined().localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBG.ignoresSafeArea()
                VStack(spacing: 0) {
                    if selectedExercise == nil {
                        exercisePicker
                    } else {
                        prForm
                    }
                }
            }
            .navigationTitle(selectedExercise == nil ? "Log a PR" : selectedExercise!.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if selectedExercise != nil {
                        Button("Back") { selectedExercise = nil; entries = [PREntry()] }
                            .foregroundColor(.appTextSecondary)
                    } else {
                        Button("Cancel") { dismiss() }.foregroundColor(.appTextSecondary)
                    }
                }
            }
        }
    }

    private var exercisePicker: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundColor(.appTextDim)
                TextField("Search exercises...", text: $searchText)
                    .font(.system(size: 15)).foregroundColor(.appTextPrimary)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.appTextDim)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(Color.appSurface2)

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(filtered) { ex in
                        Button {
                            selectedExercise = ex
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ex.displayName)
                                        .font(.system(size: 14, weight: .bold)).foregroundColor(.appTextPrimary)
                                    Text(ex.musclesPrimary.prefix(2).joined(separator: " · "))
                                        .font(.system(size: 11)).foregroundColor(.appTextDim)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundColor(.appTextDim)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var prForm: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    // Existing entries
                    ForEach(Array(entries.indices), id: \.self) { idx in
                        entryRow(idx: idx)
                    }

                    // Add another entry
                    Button {
                        entries.append(PREntry())
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill").font(.system(size: 14))
                            Text("Add Another Set").font(.system(size: 13, weight: .bold))
                        }
                        .foregroundColor(.appBlue)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Color.appBlue.opacity(0.06)).cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBlue.opacity(0.15), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    if savedCount > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundColor(.appGreen)
                            Text("\(savedCount) PR\(savedCount == 1 ? "" : "s") saved")
                                .font(.system(size: 13, weight: .bold)).foregroundColor(.appGreen)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Color.appGreen.opacity(0.06)).cornerRadius(8)
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)

            // Save button
            VStack(spacing: 0) {
                Divider().background(Color.appBorder)
                Button {
                    savePRs()
                } label: {
                    Text("SAVE \(validEntryCount) PR\(validEntryCount == 1 ? "" : "s")")
                        .font(.system(size: 15, weight: .black)).kerning(1)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(validEntryCount > 0 ? Color.appGold : Color.appSurface2)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .disabled(validEntryCount == 0)
                .padding(.horizontal, 16).padding(.vertical, 14)
            }
            .background(Color.appBG)
        }
    }

    private func entryRow(idx: Int) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 4) {
                Text("SET \(idx + 1)").font(.system(size: 10, weight: .black)).foregroundColor(.appGold).kerning(1)
                Spacer()
                if entries.count > 1 {
                    Button {
                        entries.remove(at: idx)
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundColor(.appTextDim)
                            .frame(width: 28, height: 28).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WEIGHT").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim)
                    HStack(spacing: 6) {
                        TextField("0", text: $entries[idx].weightText)
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(.appTextPrimary)
                            .keyboardType(.decimalPad)
                            .frame(maxWidth: .infinity)
                        Text(useMetric ? "kg" : "lbs")
                            .font(.system(size: 12, weight: .bold)).foregroundColor(.appTextDim)
                    }
                    .padding(10).background(Color.appSurface2).cornerRadius(8)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("REPS").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim)
                    TextField("0", text: $entries[idx].repsText)
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(.appTextPrimary)
                        .keyboardType(.numberPad)
                        .frame(maxWidth: .infinity)
                        .padding(10).background(Color.appSurface2).cornerRadius(8)
                }
            }
            DatePicker("Date", selection: $entries[idx].date, in: ...Date(), displayedComponents: .date)
                .font(.system(size: 13)).foregroundColor(.appTextSecondary)

            // e1RM preview
            if let w = Double(entries[idx].weightText), w > 0, let r = Int(entries[idx].repsText), r > 0 {
                let e1rm = WorkoutLog.computeE1RM(weight: w, reps: r)
                Text("Est. 1RM: \(Int(e1rm)) \(useMetric ? "kg" : "lbs")")
                    .font(.system(size: 12, weight: .bold)).foregroundColor(.appGold)
            }
        }
        .padding(14)
        .background(Color.appSurface).cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
    }

    private var validEntryCount: Int {
        entries.filter { Double($0.weightText) ?? 0 > 0 && Int($0.repsText) ?? 0 > 0 }.count
    }

    private func savePRs() {
        guard let ex = selectedExercise else { return }
        let def = ExerciseDictionary.all[ex.exerciseKey]
        let isMain = def?.isAnchorableAsTier1 ?? false

        var count = 0
        for entry in entries {
            guard let weight = Double(entry.weightText), weight > 0,
                  let reps = Int(entry.repsText), reps > 0 else { continue }

            let log = WorkoutLog(
                date: entry.date,
                workoutDate: entry.date,
                week: instance?.currentWeek ?? 1,
                sessionType: .freeform,
                exerciseKey: ex.exerciseKey,
                displayName: ex.displayName,
                slotId: "PR",
                setIndex: 0,
                weight: weight,
                reps: reps,
                rpe: 0,
                isMainLift: isMain,
                isTopSet: true,
                hitTargetReps: true
            )
            log.isManualPR = true
            log.e1rm = WorkoutLog.computeE1RM(weight: weight, reps: reps)

            if let inst = instance {
                inst.logs.append(log)

                // Update ProgressionState so the algorithm uses this immediately
                if let state = inst.progressionStates.first(where: { $0.exerciseKey == ex.exerciseKey }) {
                    if log.e1rm > state.bestE1RM { state.bestE1RM = log.e1rm }
                    if weight > state.lastSessionWeight {
                        state.lastSessionWeight = weight
                        state.lastSessionReps = reps
                        state.lastCompletedWeight = weight
                    }
                    state.totalExposures += 1
                } else {
                    let newState = ProgressionState(exerciseKey: ex.exerciseKey)
                    newState.bestE1RM = log.e1rm
                    newState.lastSessionWeight = weight
                    newState.lastSessionReps = reps
                    newState.lastCompletedWeight = weight
                    newState.totalExposures = 1
                    inst.progressionStates.append(newState)
                }
            } else {
                modelContext.insert(log)
            }
            count += 1
        }

        try? modelContext.save()
        savedCount += count
        entries = [PREntry()]
    }
}
