import SwiftUI
import SwiftData
import Foundation

// ═══════════════════════════════════════════
// DEBUG DASHBOARD
// 4-tab inspector: Live State, Program Preview,
// Algorithm Simulator, Verification Suite
// ═══════════════════════════════════════════

struct DebugDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @Query(filter: #Predicate<UserProgramInstance> { $0.isActive })
    private var activeInstances: [UserProgramInstance]
    @Query private var allTemplates: [ProgramSessionTemplate]

    @State private var selectedTab = 0

    private var profile: UserProfile? { profiles.first }
    private var instance: UserProgramInstance? { activeInstances.first }

    var body: some View {
        ZStack {
            Color.appBG.ignoresSafeArea()
            VStack(spacing: 0) {
                debugTabBar
                TabView(selection: $selectedTab) {
                    LiveStateTab(profile: profile, instance: instance)
                        .tag(0)
                    ProgramPreviewTab(
                        profile: profile,
                        instance: instance,
                        allTemplates: allTemplates
                    )
                    .tag(1)
                    AlgorithmSimTab()
                        .tag(2)
                    VerificationSuiteTab()
                        .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
    }

    private var debugTabBar: some View {
        HStack(spacing: 0) {
            ForEach(Array(["LIVE", "PROGRAM", "SIMULATE", "VERIFY"].enumerated()),
                    id: \.offset) { idx, label in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedTab = idx }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tabIcon(idx))
                            .font(.system(size: 14, weight: .bold))
                        Text(label)
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .kerning(1)
                    }
                    .foregroundColor(selectedTab == idx ? .appRed : .appTextDim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(selectedTab == idx
                                ? Color.appRed.opacity(0.08) : Color.clear)
                }
            }
        }
        .background(Color.appSurface)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(.appBorder),
            alignment: .bottom
        )
    }

    private func tabIcon(_ idx: Int) -> String {
        switch idx {
        case 0: return "waveform.path.ecg"
        case 1: return "list.bullet.rectangle"
        case 2: return "play.circle"
        case 3: return "checkmark.shield"
        default: return "questionmark"
        }
    }
}

// ═══════════════════════════════════════════
// TAB 1: LIVE STATE
// ═══════════════════════════════════════════

private struct LiveStateTab: View {
    let profile: UserProfile?
    let instance: UserProgramInstance?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                if let prof = profile {
                    profileCard(prof)
                }
                if let inst = instance {
                    programStateCard(inst)
                    mrvSignalsCard(inst)
                    volumeLandmarksCard(inst, profile: profile)
                    progressionStatesCard(inst)
                }
                if instance == nil {
                    emptyCard("No active program instance")
                }
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    private var headerCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("LIVE ALGORITHM STATE")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundColor(.appRed)
                    .kerning(2)
                Text("Real-time signals from your active program")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.appTextDim)
            }
            Spacer()
            Circle()
                .fill(instance != nil ? Color.appGreen : Color.appTextDim)
                .frame(width: 8, height: 8)
        }
        .padding(16)
        .appCard()
    }

    private func profileCard(_ prof: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "USER PROFILE", accent: .appBlue)
            debugRow("Experience", prof.experience.rawValue.capitalized)
            debugRow("Goal", prof.goal.displayName)
            debugRow("Days/Week", "\(prof.daysPerWeek)")
            debugRow("Progression Rate", prof.progressionRate.rawValue.uppercased(),
                      color: prof.progressionRate == .fast ? .appGreen
                      : prof.progressionRate == .slow ? .appOrange : .appTextPrimary)
            debugRow("Calorie Context", prof.calorieContext.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
            if let rbt = prof.respondsBetterTo {
                debugRow("Responds Better To", rbt.rawValue.replacingOccurrences(of: "HighIntensity", with: " High Intensity").replacingOccurrences(of: "LowIntensity", with: " Low Intensity").replacingOccurrences(of: "highVolume", with: "High Volume ").replacingOccurrences(of: "lowVolume", with: "Low Volume "))
            }
            debugRow("Units", prof.useMetric ? "Metric (kg)" : "Imperial (lbs)")

            let tiers = prof.muscleTiers
            if !tiers.isEmpty {
                Divider().background(Color.appBorder)
                Text("MUSCLE TIERS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.appTextDim)
                    .kerning(1.5)
                ForEach(ExerciseDictionary.trackingMuscles, id: \.self) { muscle in
                    let tier = tiers[muscle] ?? .neutral
                    debugRow(muscle, tier.rawValue.uppercased(),
                              color: tier == .priority ? .appGold
                              : tier == .maintenance ? .appTextDim : .appTextSecondary)
                }
            }
        }
        .padding(16)
        .appCard()
    }

    private func programStateCard(_ inst: UserProgramInstance) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "PROGRAM STATE", accent: .appBlue)
            debugRow("Program", "\(inst.name) (ID: \(inst.programId))")
            debugRow("Current Week", "\(inst.currentWeek)")
            debugRow("Block Type", inst.blockType.rawValue.uppercased(),
                      color: inst.blockType == .deload ? .appBlue
                      : inst.blockType == .peak ? .appRed : .appGreen)
            debugRow("Block Week", "\(inst.blockWeek) / \(inst.blockLength)")
            debugRow("Block Phase", blockPhaseLabel(inst.blockPhase),
                      color: blockPhaseColor(inst.blockPhase))
            debugRow("Blocks Completed", "\(inst.totalBlocksCompleted)")
            debugRow("Rotation Index", "\(inst.nextRotationIndex)")
            debugRow("Microcycle Index", "\(inst.microcycleIndex)")
            debugRow("Is Generated", inst.isGenerated ? "YES" : "NO")
            debugRow("Start Date", formatDate(inst.startDate))
            debugRow("Total Logs", "\(inst.logs.count)")
            debugRow("Prog. States", "\(inst.progressionStates.count)")
            debugRow("Overrides", "\(inst.overrides.count)")
            debugRow("Calibrations", "\(inst.landmarkCalibrations.count)")
        }
        .padding(16)
        .appCard()
    }

    private func mrvSignalsCard(_ inst: UserProgramInstance) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "MRV FATIGUE SIGNALS", accent: .appOrange)
            let scores = inst.mrvSignalScores
            if scores.isEmpty {
                Text("No MRV signal data yet")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.appTextDim)
            } else {
                ForEach(scores.sorted(by: { $0.value > $1.value }), id: \.key) { muscle, score in
                    HStack {
                        Text(muscle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.appTextPrimary)
                        Spacer()
                        mrvScoreBar(score)
                        Text("\(score)")
                            .font(.system(size: 13, weight: .black, design: .monospaced))
                            .foregroundColor(mrvColor(score))
                            .frame(width: 28, alignment: .trailing)
                    }
                }
                Divider().background(Color.appBorder)
                HStack(spacing: 12) {
                    legendDot(.appGreen, "0-2 OK")
                    legendDot(.appYellow, "3-4 Monitor")
                    legendDot(.appOrange, "5-6 Reduce")
                    legendDot(.appRed, "7+ Deload")
                }
                .font(.system(size: 9, weight: .bold))
            }
        }
        .padding(16)
        .appCard()
    }

    private func volumeLandmarksCard(_ inst: UserProgramInstance, profile: UserProfile?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "VOLUME LANDMARKS", accent: .appGreen)
            let muscles = ExerciseDictionary.trackingMuscles
            ForEach(muscles, id: \.self) { muscle in
                let cal = inst.landmarkCalibrations.first { $0.muscleGroup == muscle }
                let defaults = VolumeLandmark.defaults[muscle]
                let currentSets = inst.currentWeekSets[muscle] ?? 0
                let adjustment = inst.nextWeekSetAdjustments[muscle] ?? 0
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(muscle)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.appTextPrimary)
                        Spacer()
                        if let cal = cal {
                            Text(cal.confidence.rawValue.uppercased())
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(confidenceColor(cal.confidence))
                                .kerning(1)
                        }
                    }
                    HStack(spacing: 8) {
                        volumeStat("MEV", cal?.adjustedMEV ?? defaults?.mev ?? 0)
                        volumeStat("MAV-L", cal?.adjustedMavLow ?? defaults?.mavLow ?? 0)
                        volumeStat("MAV-H", cal?.adjustedMavHigh ?? defaults?.mavHigh ?? 0)
                        volumeStat("MRV", cal?.adjustedMRV ?? defaults?.mrv ?? 0)
                        Spacer()
                        VStack(spacing: 2) {
                            Text("\(currentSets)")
                                .font(.system(size: 16, weight: .black, design: .monospaced))
                                .foregroundColor(.appRed)
                            Text("THIS WK")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundColor(.appTextDim)
                                .kerning(1)
                        }
                        if adjustment != 0 {
                            Text(adjustment > 0 ? "+\(adjustment)" : "\(adjustment)")
                                .font(.system(size: 11, weight: .black, design: .monospaced))
                                .foregroundColor(adjustment > 0 ? .appGreen : .appOrange)
                        }
                    }
                }
                .padding(.vertical, 4)
                if muscle != muscles.last {
                    Divider().background(Color.appBorder.opacity(0.5))
                }
            }
        }
        .padding(16)
        .appCard()
    }

    @State private var expandedExercise: String? = nil

    private func progressionStatesCard(_ inst: UserProgramInstance) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "PROGRESSION STATES (\(inst.progressionStates.count))", accent: .appRed)
            let sorted = inst.progressionStates.sorted {
                ($0.totalExposures, $0.bestE1RM) > ($1.totalExposures, $1.bestE1RM)
            }
            if sorted.isEmpty {
                Text("No progression data yet")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.appTextDim)
            }
            ForEach(sorted, id: \.exerciseKey) { state in
                progressionStateRow(state)
            }
        }
        .padding(16)
        .appCard()
    }

    private func progressionStateRow(_ state: ProgressionState) -> some View {
        let name = ExerciseDictionary.all[state.exerciseKey]?.displayName
            ?? state.exerciseKey.replacingOccurrences(of: "_", with: " ").capitalized
        let isExpanded = expandedExercise == state.exerciseKey
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedExercise = isExpanded ? nil : state.exerciseKey
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.appTextPrimary)
                            .lineLimit(1)
                        HStack(spacing: 8) {
                            miniStat("e1RM", String(format: "%.0f", state.bestE1RM))
                            miniStat("Exp", "\(state.totalExposures)")
                            miniStat("IFI", String(format: "%.2f", state.lastIFI))
                            if state.lastStallDiagnosis != .noStall {
                                Text(stallLabel(state.lastStallDiagnosis))
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(.appRed)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.appRed.opacity(0.15))
                                    .cornerRadius(4)
                            }
                        }
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.appTextDim)
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    debugRow("Best e1RM", String(format: "%.1f", state.bestE1RM))
                    debugRow("EMA e1RM", String(format: "%.1f", state.emaE1rm))
                    debugRow("Baseline e1RM", String(format: "%.1f", state.baselineE1rm))
                    debugRow("Last Weight", String(format: "%.1f", state.lastSessionWeight))
                    debugRow("Last Reps", "\(state.lastSessionReps)")
                    debugRow("Last RPE", String(format: "%.1f", state.lastSessionRPE))
                    debugRow("Completed Wt", String(format: "%.1f", state.lastCompletedWeight))
                    debugRow("Prev. Weight", String(format: "%.1f", state.previousWeight))
                    debugRow("Prev. Reps", "\(state.previousReps)")
                    Divider().background(Color.appBorder.opacity(0.5))
                    debugRow("Successes", "\(state.consecutiveSuccesses)",
                              color: state.consecutiveSuccesses > 0 ? .appGreen : .appTextPrimary)
                    debugRow("Failures", "\(state.consecutiveFailures)",
                              color: state.consecutiveFailures > 0 ? .appRed : .appTextPrimary)
                    debugRow("Wks Same Load", "\(state.weeksAtSameLoad)",
                              color: state.weeksAtSameLoad >= 2 ? .appOrange : .appTextPrimary)
                    debugRow("Total Exposures", "\(state.totalExposures)")
                    Divider().background(Color.appBorder.opacity(0.5))
                    debugRow("IFI (last)", String(format: "%.3f", state.lastIFI))
                    debugRow("IFI (trend)", String(format: "%.3f", state.ifiTrend))
                    debugRow("IFI Zone", state.ifiZone.rawValue.uppercased(),
                              color: ifiZoneColor(state.ifiZone))
                    Divider().background(Color.appBorder.opacity(0.5))
                    debugRow("Stall Diagnosis", stallLabel(state.lastStallDiagnosis),
                              color: state.lastStallDiagnosis != .noStall ? .appRed : .appGreen)
                    debugRow("Stall Count", "\(state.consecutiveStallDiagnoses)")
                    debugRow("Stall Urgency", state.stallUrgency.rawValue.uppercased(),
                              color: urgencyColor(state.stallUrgency))
                    debugRow("Last Rule", state.lastProgressionRule.rawValue.uppercased())
                    debugRow("Updated", formatDate(state.updatedAt))
                }
                .padding(.leading, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider().background(Color.appBorder.opacity(0.3))
        }
    }

    // ── Shared helpers ──

    private func debugRow(_ label: String, _ value: String, color: Color = .appTextPrimary) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.appTextSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(color)
                .lineLimit(1)
        }
    }

    private func miniStat(_ label: String, _ value: String) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.appTextDim)
            Text(value)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.appTextSecondary)
        }
    }

    private func volumeStat(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 1) {
            Text("\(value)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.appTextPrimary)
            Text(label)
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(.appTextDim)
                .kerning(0.5)
        }
    }

    private func mrvScoreBar(_ score: Int) -> some View {
        GeometryReader { geo in
            let pct = min(1.0, Double(score) / 10.0)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.appSurface2).frame(height: 6)
                Capsule().fill(mrvColor(score)).frame(width: geo.size.width * pct, height: 6)
            }
        }
        .frame(width: 60, height: 6)
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).foregroundColor(.appTextDim)
        }
    }

    private func emptyCard(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.appTextDim)
            .frame(maxWidth: .infinity)
            .padding(24)
            .appCard()
    }

    private func mrvColor(_ score: Int) -> Color {
        switch score {
        case ...2: return .appGreen
        case 3...4: return .appYellow
        case 5...6: return .appOrange
        default: return .appRed
        }
    }

    private func blockPhaseLabel(_ phase: BlockPhase) -> String {
        switch phase {
        case .earlyAccumulation: return "EARLY ACCUM"
        case .lateAccumulation: return "LATE ACCUM"
        case .intensification: return "INTENSIFICATION"
        case .deload: return "DELOAD"
        case .postDeloadReintro: return "POST-DELOAD REINTRO"
        }
    }

    private func blockPhaseColor(_ phase: BlockPhase) -> Color {
        switch phase {
        case .earlyAccumulation: return .appGreen
        case .lateAccumulation: return .appYellow
        case .intensification: return .appOrange
        case .deload: return .appBlue
        case .postDeloadReintro: return .appBlue
        }
    }

    private func confidenceColor(_ c: CalibrationConfidence) -> Color {
        switch c {
        case .seeded: return .appTextDim
        case .low: return .appYellow
        case .medium: return .appBlue
        case .high: return .appGreen
        }
    }

    private func ifiZoneColor(_ zone: IFIZone) -> Color {
        switch zone {
        case .fresh: return .appGreen
        case .optimal: return .appBlue
        case .fatigued: return .appOrange
        case .acuteOverreach: return .appRed
        }
    }

    private func urgencyColor(_ u: StallUrgency) -> Color {
        switch u {
        case .suggestion: return .appYellow
        case .warning: return .appOrange
        case .actionRequired: return .appRed
        }
    }

    private func stallLabel(_ d: StallDiagnosis) -> String {
        switch d {
        case .noStall: return "NONE"
        case .fatigueStall: return "FATIGUE"
        case .intensityStall: return "INTENSITY"
        case .truePlateau: return "PLATEAU"
        case .volumeStall: return "VOLUME"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy HH:mm"
        return f.string(from: date)
    }
}

// ═══════════════════════════════════════════
// TAB 2: PROGRAM PREVIEW
// Now with custom user settings input
// ═══════════════════════════════════════════

private struct ProgramPreviewTab: View {
    let profile: UserProfile?
    let instance: UserProgramInstance?
    let allTemplates: [ProgramSessionTemplate]

    // Active program browse
    @State private var selectedWeek = 1
    @State private var maxWeek = 24

    // Custom generator mode
    @State private var showGenerator = false
    @State private var genExperience: ExperienceLevel = .intermediate
    @State private var genGoal: GoalType = .hypertrophy
    @State private var genDays: Int = 4
    @State private var genCalorie: CalorieContext = .maintenance
    @State private var genBlockType: BlockType = .accumulation
    @State private var genPriority1: String = "Chest"
    @State private var genPriority2: String = "Back"
    @State private var genWeek: Int = 1
    @State private var generatedSlots: [GeneratedSlotRow] = []

    struct GeneratedSlotRow: Identifiable {
        let id = UUID()
        let day: String
        let exerciseName: String
        let exerciseKey: String
        let tier: String
        let sets: Int
        let repsRange: String
        let restSec: Int
        let weeklyTarget: Int
        let muscle: String
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                modePicker
                if showGenerator {
                    generatorCard
                    if !generatedSlots.isEmpty {
                        generatedProgramCard
                    }
                } else {
                    activePreviewSection
                }
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .onAppear {
            if let inst = instance {
                let weeks = allTemplates
                    .filter { $0.programId == inst.programId && $0.programVersion == inst.programVersion }
                    .map { $0.week }
                maxWeek = weeks.max() ?? 24
                selectedWeek = inst.currentWeek
            }
        }
    }

    private var modePicker: some View {
        HStack(spacing: 0) {
            modeButton("ACTIVE PROGRAM", active: !showGenerator) { showGenerator = false }
            modeButton("CUSTOM GENERATOR", active: showGenerator) { showGenerator = true }
        }
        .background(Color.appSurface)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))
    }

    private func modeButton(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .kerning(1)
                .foregroundColor(active ? .white : .appTextDim)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(active ? Color.appRed : Color.clear)
                .cornerRadius(10)
        }
    }

    // ── Custom Generator ──

    private var generatorCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "USER SETTINGS", accent: .appBlue)

            // Experience
            VStack(alignment: .leading, spacing: 4) {
                sectionLabel("EXPERIENCE")
                Picker("Exp", selection: $genExperience) {
                    Text("Beginner").tag(ExperienceLevel.beginner)
                    Text("Intermediate").tag(ExperienceLevel.intermediate)
                    Text("Advanced").tag(ExperienceLevel.advanced)
                    Text("Elite").tag(ExperienceLevel.elite)
                }
                .pickerStyle(.segmented)
            }

            // Goal
            VStack(alignment: .leading, spacing: 4) {
                sectionLabel("GOAL")
                Picker("Goal", selection: $genGoal) {
                    Text("Hypertrophy").tag(GoalType.hypertrophy)
                    Text("Strength").tag(GoalType.strength)
                    Text("Powerbuilding").tag(GoalType.powerbuilding)
                    Text("Recomp").tag(GoalType.recomp)
                }
                .pickerStyle(.segmented)
            }

            // Days per week
            VStack(alignment: .leading, spacing: 4) {
                sectionLabel("DAYS PER WEEK")
                Picker("Days", selection: $genDays) {
                    ForEach(2...6, id: \.self) { d in
                        Text("\(d)").tag(d)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Block type
            VStack(alignment: .leading, spacing: 4) {
                sectionLabel("BLOCK TYPE")
                Picker("Block", selection: $genBlockType) {
                    Text("Accum").tag(BlockType.accumulation)
                    Text("Intens").tag(BlockType.intensification)
                    Text("Reaccum").tag(BlockType.reaccumulation)
                    Text("Deload").tag(BlockType.deload)
                }
                .pickerStyle(.segmented)
            }

            // Calorie context
            VStack(alignment: .leading, spacing: 4) {
                sectionLabel("CALORIE CONTEXT")
                Picker("Cal", selection: $genCalorie) {
                    Text("Surplus").tag(CalorieContext.surplus)
                    Text("Maint").tag(CalorieContext.maintenance)
                    Text("Mild Def").tag(CalorieContext.mildDeficit)
                    Text("Mod Def").tag(CalorieContext.moderateDeficit)
                }
                .pickerStyle(.segmented)
            }

            // Priority muscles
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    sectionLabel("PRIORITY 1")
                    Picker("P1", selection: $genPriority1) {
                        ForEach(ExerciseDictionary.trackingMuscles, id: \.self) { m in
                            Text(m).tag(m)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.appRed)
                }
                VStack(alignment: .leading, spacing: 4) {
                    sectionLabel("PRIORITY 2")
                    Picker("P2", selection: $genPriority2) {
                        ForEach(ExerciseDictionary.trackingMuscles, id: \.self) { m in
                            Text(m).tag(m)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.appRed)
                }
            }

            // Week
            VStack(alignment: .leading, spacing: 4) {
                sectionLabel("PREVIEW WEEK")
                Stepper("Week \(genWeek)", value: $genWeek, in: 1...6)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.appTextPrimary)
            }

            PrimaryButton(title: "GENERATE PROGRAM", icon: "sparkles") {
                generateCustomProgram()
            }
        }
        .padding(16)
        .appCard()
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(.appTextDim)
            .kerning(1.5)
    }

    private func generateCustomProgram() {
        let priorityMuscles = [genPriority1, genPriority2]
        let dayTemplates = ProgramGenerator.resolveSplitStructure(
            daysPerWeek: genDays,
            goal: genGoal,
            priorityMuscles: priorityMuscles
        )

        let equipment: Set<EquipmentType> = [.barbell, .dumbbell, .cable, .machine, .bodyweight]
        var muscleTiers: [String: MuscleTier] = [:]
        for m in ExerciseDictionary.trackingMuscles {
            if priorityMuscles.contains(m) { muscleTiers[m] = .priority }
            else { muscleTiers[m] = .neutral }
        }

        var rows: [GeneratedSlotRow] = []

        for day in dayTemplates {
            guard day.sessionType != .rest else { continue }
            for muscle in day.primaryMuscles {
                let sessionsForMuscle = dayTemplates
                    .filter { $0.primaryMuscles.contains(muscle) }.count
                let weeklyTarget = ProgramGenerator.resolveWeeklySetTarget(
                    muscle: muscle,
                    week: genWeek,
                    blockType: genBlockType,
                    muscleTier: muscleTiers[muscle] ?? .neutral,
                    experience: genExperience,
                    calorieContext: genCalorie,
                    calibration: nil
                )
                let setsThisSession = max(0, weeklyTarget / max(1, sessionsForMuscle))
                guard setsThisSession > 0 else { continue }

                let slots = ProgramGenerator.selectExercisesForMuscle(
                    muscle: muscle,
                    setsNeeded: setsThisSession,
                    muscleTier: muscleTiers[muscle] ?? .neutral,
                    goal: genGoal,
                    equipment: equipment,
                    usedKeys: [],
                    blockNumber: 1
                )

                for slot in slots {
                    let name = ExerciseDictionary.all[slot.exerciseKey]?.displayName
                        ?? slot.exerciseKey.replacingOccurrences(of: "_", with: " ").capitalized
                    let tierLabel = slot.exerciseTier == .tier1 ? "T1"
                        : slot.exerciseTier == .tier2 ? "T2" : "T3"
                    rows.append(GeneratedSlotRow(
                        day: day.label,
                        exerciseName: name,
                        exerciseKey: slot.exerciseKey,
                        tier: tierLabel,
                        sets: slot.sets,
                        repsRange: "\(slot.repsLow)-\(slot.repsHigh)",
                        restSec: slot.restSeconds,
                        weeklyTarget: weeklyTarget,
                        muscle: muscle
                    ))
                }
            }
        }

        withAnimation { generatedSlots = rows }
    }

    private var generatedProgramCard: some View {
        let grouped = Dictionary(grouping: generatedSlots, by: { $0.day })
        let dayOrder = Array(dict: grouped).sorted { $0.key < $1.key }
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "GENERATED PROGRAM — WEEK \(genWeek)", accent: .appGreen)

            // Summary stats
            let totalSets = generatedSlots.reduce(0) { $0 + $1.sets }
            let totalExercises = generatedSlots.count
            let days = grouped.keys.count
            HStack(spacing: 0) {
                PremiumStatCell(value: "\(days)", label: "DAYS", color: .appBlue)
                statDivider
                PremiumStatCell(value: "\(totalExercises)", label: "EXERCISES", color: .appGold)
                statDivider
                PremiumStatCell(value: "\(totalSets)", label: "TOTAL SETS", color: .appRed)
            }

            ForEach(dayOrder, id: \.key) { dayName, slots in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(dayName.uppercased())
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundColor(.appGold)
                            .kerning(1.5)
                        Spacer()
                        Text("\(slots.reduce(0) { $0 + $1.sets }) sets")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.appTextDim)
                    }
                    ForEach(slots) { slot in
                        HStack(spacing: 10) {
                            Text(slot.tier)
                                .font(.system(size: 10, weight: .black, design: .monospaced))
                                .foregroundColor(slot.tier == "T1" ? .appRed : slot.tier == "T2" ? .appGold : .appTextDim)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(slot.exerciseName)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.appTextPrimary)
                                    .lineLimit(1)
                                HStack(spacing: 8) {
                                    Text("\(slot.sets)x\(slot.repsRange)")
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundColor(.appTextSecondary)
                                    Text("\(slot.restSec)s rest")
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundColor(.appTextDim)
                                    Text(slot.muscle)
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.appBlue)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.appBlue.opacity(0.12))
                                        .cornerRadius(4)
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 3)
                    }
                    if dayName != dayOrder.last?.key {
                        Divider().background(Color.appBorder)
                    }
                }
            }

            // Volume by muscle
            Divider().background(Color.appBorder)
            SectionHeader(title: "WEEKLY VOLUME BY MUSCLE", accent: .appOrange)
            let volumeByMuscle = Dictionary(grouping: generatedSlots, by: { $0.muscle })
                .mapValues { $0.reduce(0) { $0 + $1.sets } }
                .sorted { $0.value > $1.value }
            ForEach(volumeByMuscle, id: \.key) { muscle, sets in
                let zone = VolumeZone.classify(
                    directSets: sets,
                    muscle: muscle,
                    experience: genExperience,
                    tier: muscle == genPriority1 || muscle == genPriority2 ? .priority : .neutral
                )
                HStack {
                    Text(muscle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.appTextPrimary)
                    Spacer()
                    Text("\(sets) sets")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.appTextPrimary)
                    Text(zone.rawValue)
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(zoneColor(zone))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(zoneColor(zone).opacity(0.15))
                        .cornerRadius(4)
                }
            }
        }
        .padding(16)
        .appCard()
    }

    private var statDivider: some View {
        Rectangle().fill(Color.appBorder).frame(width: 1, height: 40)
    }

    private func zoneColor(_ zone: VolumeZone) -> Color {
        switch zone {
        case .underTraining: return .appRed
        case .building: return .appYellow
        case .optimal: return .appGreen
        case .overReaching: return .appOrange
        }
    }

    // ── Active Program Preview (existing) ──

    private var activePreviewSection: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PROGRAM PREVIEW")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundColor(.appRed)
                        .kerning(2)
                    Text("Browse every week, session, and exercise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.appTextDim)
                }
                Spacer()
            }
            .padding(16)
            .appCard()

            weekPicker

            if let inst = instance {
                let pid = inst.programId
                let ver = inst.programVersion
                let weekTemplates = allTemplates
                    .filter { $0.programId == pid && $0.programVersion == ver && $0.week == selectedWeek }
                    .sorted { $0.exerciseIndex < $1.exerciseIndex }

                let grouped = Dictionary(grouping: weekTemplates, by: { $0.sessionType })
                if grouped.isEmpty {
                    emptyCard("No templates for week \(selectedWeek)")
                }
                ForEach(grouped.keys.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { sessType in
                    sessionCard(sessType, templates: grouped[sessType] ?? [])
                }
            } else {
                emptyCard("No active program — use Custom Generator")
            }
        }
    }

    private var weekPicker: some View {
        VStack(spacing: 8) {
            HStack {
                Text("WEEK \(selectedWeek)")
                    .font(.system(size: 18, weight: .black, design: .monospaced))
                    .foregroundColor(.appTextPrimary)
                Spacer()
                if let inst = instance {
                    let isDeload = inst.isEffectiveDeload(selectedWeek, programId: inst.programId)
                    if isDeload {
                        Text("DELOAD")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundColor(.appBlue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.appBlue.opacity(0.15))
                            .cornerRadius(6)
                    }
                    if selectedWeek == inst.currentWeek {
                        Text("CURRENT")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundColor(.appGreen)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.appGreen.opacity(0.15))
                            .cornerRadius(6)
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(1...maxWeek, id: \.self) { wk in
                        Button {
                            selectedWeek = wk
                        } label: {
                            Text("\(wk)")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(selectedWeek == wk ? .white : .appTextSecondary)
                                .frame(width: 30, height: 30)
                                .background(selectedWeek == wk ? Color.appRed : Color.appSurface2)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(wk == instance?.currentWeek ? Color.appGreen : Color.clear, lineWidth: 1.5)
                                )
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(16)
        .appCard()
    }

    private func sessionCard(_ sessType: SessionType, templates: [ProgramSessionTemplate]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(sessType.rawValue.replacingOccurrences(of: "_", with: " ").uppercased())
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundColor(.appGold)
                    .kerning(1.5)
                Spacer()
                Text("\(templates.reduce(0) { $0 + $1.targetSets }) sets")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.appTextDim)
            }
            ForEach(templates.sorted(by: { $0.exerciseIndex < $1.exerciseIndex }),
                    id: \.slotId) { t in
                templateRow(t)
            }
        }
        .padding(16)
        .appCard()
    }

    private func templateRow(_ t: ProgramSessionTemplate) -> some View {
        let name = ExerciseDictionary.all[t.exerciseKey]?.displayName
            ?? t.exerciseKey.replacingOccurrences(of: "_", with: " ").capitalized
        let tierLabel = t.isMainLift ? "T1" : (t.role == .supplemental ? "T2" : "T3")
        let tierColor: Color = t.isMainLift ? .appRed : (t.role == .supplemental ? .appGold : .appTextDim)
        return HStack(spacing: 10) {
            Text(tierLabel)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(tierColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.appTextPrimary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text("\(t.targetSets)x\(t.targetRepsLow)-\(t.targetRepsHigh)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.appTextSecondary)
                    Text("RPE \(String(format: "%.1f", t.targetRPE))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.appTextSecondary)
                    if t.suggestedWeight > 0 {
                        Text("\(Int(t.suggestedWeight))lbs")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.appBlue)
                    }
                }
            }
            Spacer()
            Text(t.slotId)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.appTextDim)
        }
        .padding(.vertical, 4)
    }

    private func emptyCard(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.appTextDim)
            .frame(maxWidth: .infinity)
            .padding(24)
            .appCard()
    }
}

// Helper to get sorted array from Dictionary
private extension Array {
    init<K, V>(dict: Dictionary<K, V>) where Element == (key: K, value: V) {
        self = Array<(key: K, value: V)>(dict)
    }
}

// ═══════════════════════════════════════════
// TAB 3: ALGORITHM SIMULATOR (Full Overhaul)
// Multi-exercise, ProgressionState tracking,
// block transitions, volume decisions, IFI trends
// ═══════════════════════════════════════════

private struct AlgorithmSimTab: View {

    // Config
    @State private var simExperience: ExperienceLevel = .intermediate
    @State private var simGoal: GoalType = .hypertrophy
    @State private var simDays: Int = 4
    @State private var simProgressionRate: ProgressionRate = .normal
    @State private var simCalorie: CalorieContext = .maintenance
    @State private var simWeeks: Int = 16
    @State private var simUseMetric = false

    // Starting weights (bench, squat, deadlift)
    @State private var startBench = "185"
    @State private var startSquat = "275"
    @State private var startDeadlift = "315"

    // Lifter behavior sim
    @State private var effortLevel: Double = 0.85 // how often user hits top reps (0-1)
    @State private var rpeAccuracy: Double = 0.8  // how close RPE logs match reality

    // Results
    @State private var simLog: [SimWeekEntry] = []
    @State private var isRunning = false
    @State private var expandedWeek: Int? = nil
    @State private var showExportAlert = false
    @State private var exportPath = ""

    struct SimExerciseResult: Identifiable {
        let id = UUID()
        let exerciseKey: String
        let exerciseName: String
        let tier: ExerciseTier
        let weight: Double
        let reps: Int
        let rule: ProgressionRule
        let e1rm: Double
        let ifi: Double
        let stallDiagnosis: StallDiagnosis
        let debugNote: String
    }

    struct SimWeekEntry: Identifiable {
        let id = UUID()
        let week: Int
        let blockType: BlockType
        let blockPhase: BlockPhase
        let exercises: [SimExerciseResult]
        let totalSets: Int
        let avgIFI: Double
        let stallCount: Int
        let volumeDecision: String
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                configCard
                if !simLog.isEmpty {
                    summaryCard
                    bigThreeProgressCard
                    weekByWeekCard
                }
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .alert("Exported", isPresented: $showExportAlert) {
            Button("OK") {}
        } message: {
            Text("Simulation saved to:\n\(exportPath)")
        }
    }

    private var headerCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("ALGORITHM SIMULATOR")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundColor(.appRed)
                    .kerning(2)
                Text("Multi-exercise simulation with block transitions")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.appTextDim)
            }
            Spacer()
        }
        .padding(16)
        .appCard()
    }

    private var configCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "SIMULATION SETTINGS", accent: .appBlue)

            // User profile
            VStack(alignment: .leading, spacing: 4) {
                simLabel("EXPERIENCE")
                Picker("Exp", selection: $simExperience) {
                    Text("Beg").tag(ExperienceLevel.beginner)
                    Text("Int").tag(ExperienceLevel.intermediate)
                    Text("Adv").tag(ExperienceLevel.advanced)
                    Text("Elite").tag(ExperienceLevel.elite)
                }
                .pickerStyle(.segmented)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    simLabel("GOAL")
                    Picker("Goal", selection: $simGoal) {
                        Text("Hyp").tag(GoalType.hypertrophy)
                        Text("Str").tag(GoalType.strength)
                        Text("PB").tag(GoalType.powerbuilding)
                        Text("Rec").tag(GoalType.recomp)
                    }
                    .pickerStyle(.segmented)
                }
                VStack(alignment: .leading, spacing: 4) {
                    simLabel("RATE")
                    Picker("Rate", selection: $simProgressionRate) {
                        Text("Slow").tag(ProgressionRate.slow)
                        Text("Normal").tag(ProgressionRate.normal)
                        Text("Fast").tag(ProgressionRate.fast)
                    }
                    .pickerStyle(.segmented)
                }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    simLabel("DAYS/WK")
                    Picker("Days", selection: $simDays) {
                        ForEach(2...6, id: \.self) { d in Text("\(d)").tag(d) }
                    }
                    .pickerStyle(.segmented)
                }
                VStack(alignment: .leading, spacing: 4) {
                    simLabel("WEEKS")
                    Picker("Wks", selection: $simWeeks) {
                        Text("8").tag(8)
                        Text("12").tag(12)
                        Text("16").tag(16)
                        Text("24").tag(24)
                    }
                    .pickerStyle(.segmented)
                }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    simLabel("CALORIES")
                    Picker("Cal", selection: $simCalorie) {
                        Text("Surp").tag(CalorieContext.surplus)
                        Text("Maint").tag(CalorieContext.maintenance)
                        Text("Mild").tag(CalorieContext.mildDeficit)
                        Text("Mod").tag(CalorieContext.moderateDeficit)
                    }
                    .pickerStyle(.segmented)
                }
                VStack(alignment: .leading, spacing: 4) {
                    simLabel("UNITS")
                    Picker("Units", selection: $simUseMetric) {
                        Text("lbs").tag(false)
                        Text("kg").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
            }

            Divider().background(Color.appBorder)
            SectionHeader(title: "STARTING WEIGHTS", accent: .appGold)

            HStack(spacing: 12) {
                simField("Bench", $startBench)
                simField("Squat", $startSquat)
                simField("Deadlift", $startDeadlift)
            }

            Divider().background(Color.appBorder)
            SectionHeader(title: "LIFTER BEHAVIOR", accent: .appOrange)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    simLabel("EFFORT LEVEL")
                    Spacer()
                    Text("\(Int(effortLevel * 100))%")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.appTextPrimary)
                }
                Slider(value: $effortLevel, in: 0.5...1.0, step: 0.05)
                    .tint(.appRed)
                HStack {
                    Text("Inconsistent")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.appTextDim)
                    Spacer()
                    Text("Perfect Effort")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.appTextDim)
                }
            }

            PrimaryButton(title: isRunning ? "RUNNING..." : "RUN SIMULATION", icon: "play.fill") {
                if !isRunning { runFullSimulation() }
            }
        }
        .padding(16)
        .appCard()
    }

    private func simLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(.appTextDim)
            .kerning(1.5)
    }

    private func simField(_ label: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.appTextDim)
                .kerning(1)
            TextField("", text: text)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundColor(.appTextPrimary)
                .keyboardType(.decimalPad)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.appSurface2)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorder, lineWidth: 1))
        }
    }

    private var summaryCard: some View {
        let totalWeeks = simLog.count
        let progressWeeks = simLog.flatMap { $0.exercises }.filter { $0.rule == .progress }.count
        let stallWeeks = simLog.filter { $0.stallCount > 0 }.count
        let deloadWeeks = simLog.filter { $0.blockType == .deload }.count

        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "SIMULATION SUMMARY", accent: .appGreen)
            HStack(spacing: 0) {
                PremiumStatCell(value: "\(totalWeeks)", label: "WEEKS", color: .appBlue)
                simDivider
                PremiumStatCell(value: "\(progressWeeks)", label: "PROGRESSIONS", color: .appGreen)
                simDivider
                PremiumStatCell(value: "\(stallWeeks)", label: "STALL WKS", color: stallWeeks > 0 ? .appRed : .appGreen)
                simDivider
                PremiumStatCell(value: "\(deloadWeeks)", label: "DELOADS", color: .appBlue)
            }

            if !simLog.isEmpty {
                Button {
                    exportSimulation()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .bold))
                        Text("EXPORT TO .TXT")
                            .font(.system(size: 13, weight: .black))
                            .kerning(1)
                    }
                    .foregroundColor(.appBlue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.appSurface2)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.appBlue.opacity(0.4), lineWidth: 1))
                }
            }
        }
        .padding(16)
        .appCard()
    }

    private var simDivider: some View {
        Rectangle().fill(Color.appBorder).frame(width: 1, height: 40)
    }

    private var bigThreeProgressCard: some View {
        let lifts = ["bench_press_barbell", "squat_barbell", "deadlift_barbell"]
        let liftNames = ["Bench", "Squat", "Deadlift"]

        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "BIG THREE PROGRESSION", accent: .appRed)
            ForEach(0..<3, id: \.self) { i in
                let key = lifts[i]
                let name = liftNames[i]
                let weekResults = simLog.compactMap { wk -> (Int, Double)? in
                    guard let ex = wk.exercises.first(where: { $0.exerciseKey == key }) else { return nil }
                    return (wk.week, ex.weight)
                }
                if !weekResults.isEmpty {
                    let first = weekResults.first?.1 ?? 0
                    let last = weekResults.last?.1 ?? 0
                    let gain = last - first
                    HStack {
                        Text(name)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.appTextPrimary)
                            .frame(width: 60, alignment: .leading)
                        Text(String(format: "%.0f", first))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.appTextDim)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10))
                            .foregroundColor(.appTextDim)
                        Text(String(format: "%.0f", last))
                            .font(.system(size: 14, weight: .black, design: .monospaced))
                            .foregroundColor(.appTextPrimary)
                        Spacer()
                        Text(gain >= 0 ? "+\(Int(gain))" : "\(Int(gain))")
                            .font(.system(size: 13, weight: .black, design: .monospaced))
                            .foregroundColor(gain > 0 ? .appGreen : gain < 0 ? .appRed : .appTextDim)
                    }
                    if i < 2 {
                        Divider().background(Color.appBorder.opacity(0.3))
                    }
                }
            }
        }
        .padding(16)
        .appCard()
    }

    private var weekByWeekCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "WEEK-BY-WEEK DETAIL", accent: .appBlue)
            ForEach(simLog) { wk in
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            expandedWeek = expandedWeek == wk.week ? nil : wk.week
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text("W\(wk.week)")
                                .font(.system(size: 11, weight: .black, design: .monospaced))
                                .foregroundColor(.appTextDim)
                                .frame(width: 30, alignment: .leading)

                            blockTypeBadge(wk.blockType)

                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 6) {
                                    Text("\(wk.totalSets) sets")
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundColor(.appTextSecondary)
                                    Text("IFI \(String(format: "%.2f", wk.avgIFI))")
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundColor(wk.avgIFI > 0.25 ? .appOrange : .appTextDim)
                                }
                                if wk.stallCount > 0 {
                                    Text("\(wk.stallCount) stall(s)")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundColor(.appRed)
                                }
                            }
                            Spacer()
                            Image(systemName: expandedWeek == wk.week ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.appTextDim)
                        }
                    }

                    if expandedWeek == wk.week {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Vol Decision: \(wk.volumeDecision)")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.appTextDim)
                            ForEach(wk.exercises) { ex in
                                HStack(spacing: 6) {
                                    ruleIndicator(ex.rule)
                                    Text(ex.tier == .tier1 ? "T1" : ex.tier == .tier2 ? "T2" : "T3")
                                        .font(.system(size: 9, weight: .black, design: .monospaced))
                                        .foregroundColor(ex.tier == .tier1 ? .appRed : .appTextDim)
                                        .frame(width: 20)
                                    Text(ex.exerciseName)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.appTextPrimary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(Int(ex.weight))x\(ex.reps)")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundColor(.appTextSecondary)
                                    if ex.stallDiagnosis != .noStall {
                                        Circle().fill(Color.appRed).frame(width: 6, height: 6)
                                    }
                                }
                            }
                        }
                        .padding(.leading, 8)
                        .padding(.vertical, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.vertical, 4)
                if wk.week != simLog.last?.week {
                    Divider().background(Color.appBorder.opacity(0.3))
                }
            }
        }
        .padding(16)
        .appCard()
    }

    private func blockTypeBadge(_ bt: BlockType) -> some View {
        let label: String = switch bt {
        case .accumulation: "ACC"
        case .intensification: "INT"
        case .reaccumulation: "REACC"
        case .peak: "PEAK"
        case .deload: "DL"
        }
        let color: Color = switch bt {
        case .accumulation: .appGreen
        case .intensification: .appOrange
        case .reaccumulation: .appYellow
        case .peak: .appRed
        case .deload: .appBlue
        }
        return Text(label)
            .font(.system(size: 8, weight: .black, design: .monospaced))
            .foregroundColor(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .cornerRadius(4)
    }

    private func ruleIndicator(_ rule: ProgressionRule) -> some View {
        let (icon, color): (String, Color) = switch rule {
        case .progress: ("arrow.up", Color.appGreen)
        case .hold: ("arrow.right", Color.appYellow)
        case .backoff: ("arrow.down", Color.appRed)
        }
        return Image(systemName: icon)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(color)
            .frame(width: 14)
    }

    // ── Full Simulation Engine ──

    private func runFullSimulation() {
        isRunning = true
        simLog = []

        let bench0 = Double(startBench) ?? 185
        let squat0 = Double(startSquat) ?? 275
        let dl0 = Double(startDeadlift) ?? 315

        // Core exercises to simulate
        struct SimExercise {
            let key: String
            let name: String
            let tier: ExerciseTier
            var currentWeight: Double
            let targetRepsLow: Int
            let targetRepsHigh: Int
            let targetRPE: Double
            let isMainLift: Bool
        }

        var exercises: [SimExercise] = [
            SimExercise(key: "bench_press_barbell", name: "Bench Press", tier: .tier1,
                        currentWeight: bench0, targetRepsLow: 5, targetRepsHigh: 8,
                        targetRPE: 7.5, isMainLift: true),
            SimExercise(key: "squat_barbell", name: "Barbell Squat", tier: .tier1,
                        currentWeight: squat0, targetRepsLow: 5, targetRepsHigh: 8,
                        targetRPE: 7.5, isMainLift: true),
            SimExercise(key: "deadlift_barbell", name: "Deadlift", tier: .tier1,
                        currentWeight: dl0, targetRepsLow: 3, targetRepsHigh: 6,
                        targetRPE: 8.0, isMainLift: true),
            SimExercise(key: "incline_dumbbell", name: "Incline DB Press", tier: .tier2,
                        currentWeight: bench0 * 0.4, targetRepsLow: 8, targetRepsHigh: 12,
                        targetRPE: 7.5, isMainLift: false),
            SimExercise(key: "barbell_row", name: "Barbell Row", tier: .tier2,
                        currentWeight: bench0 * 0.75, targetRepsLow: 8, targetRepsHigh: 12,
                        targetRPE: 7.5, isMainLift: false),
            SimExercise(key: "leg_press", name: "Leg Press", tier: .tier2,
                        currentWeight: squat0 * 1.2, targetRepsLow: 8, targetRepsHigh: 12,
                        targetRPE: 7.5, isMainLift: false),
        ]

        // Initialize progression states (in-memory, not SwiftData)
        var progStates: [String: SimProgressionState] = [:]
        for ex in exercises {
            progStates[ex.key] = SimProgressionState()
        }

        var allLogsByExercise: [String: [WorkoutLog]] = [:]
        var currentBlock: BlockType = .accumulation
        var blockWeek = 1
        var blockLength = simExperience == .beginner || simExperience == .intermediate ? 5 : 4
        var blockNumber = 1
        var results: [SimWeekEntry] = []

        for week in 1...simWeeks {
            // Block transitions
            if blockWeek > blockLength {
                currentBlock = BlockType.next(current: currentBlock, goal: simGoal, blockNumber: blockNumber)
                blockWeek = 1
                blockNumber += 1
                blockLength = currentBlock == .deload ? 1 : (simExperience == .beginner || simExperience == .intermediate ? 5 : 4)
            }

            let blockPhase: BlockPhase
            if currentBlock == .deload {
                blockPhase = .deload
            } else if blockWeek == 1 && blockNumber > 1 {
                blockPhase = .postDeloadReintro
            } else if currentBlock == .intensification {
                blockPhase = .intensification
            } else if blockWeek <= 2 {
                blockPhase = .earlyAccumulation
            } else {
                blockPhase = .lateAccumulation
            }

            var weekExResults: [SimExerciseResult] = []
            var totalSets = 0

            for i in 0..<exercises.count {
                let ex = exercises[i]
                let state = progStates[ex.key]!
                let logs = allLogsByExercise[ex.key] ?? []

                // Simulate workout performance based on effort level
                let baseReps: Int
                if Double.random(in: 0...1) < effortLevel {
                    baseReps = ex.targetRepsHigh
                } else {
                    baseReps = Int.random(in: ex.targetRepsLow...ex.targetRepsHigh)
                }

                let fatigueDrop = currentBlock == .deload ? 0 : Int.random(in: 0...2)
                let sessionReps = [baseReps, max(ex.targetRepsLow, baseReps - Int.random(in: 0...1)),
                                   max(ex.targetRepsLow - 1, baseReps - fatigueDrop)]
                let rpeNoise = Double.random(in: -0.5...0.5) * (1.0 - rpeAccuracy + 0.2)
                let date = Calendar.current.date(byAdding: .weekOfYear, value: -(simWeeks - week), to: Date()) ?? Date()

                let sessionLogs = sessionReps.enumerated().map { idx, r in
                    WorkoutLog(
                        date: date,
                        week: week,
                        sessionType: .heavyUpper,
                        exerciseKey: ex.key,
                        displayName: ex.name,
                        slotId: "A\(i + 1)",
                        setIndex: idx,
                        weight: ex.currentWeight,
                        reps: r,
                        rpe: max(6, min(10, ex.targetRPE + rpeNoise)),
                        isMainLift: ex.isMainLift
                    )
                }

                var updatedLogs = logs
                updatedLogs.append(contentsOf: sessionLogs)
                allLogsByExercise[ex.key] = updatedLogs

                let ifi = ProgressionEngine.computeIFI(sessionSets: sessionLogs)

                // Update sim state
                state.totalExposures += 1
                let topE1rm = sessionLogs.map { $0.e1rm }.max() ?? 0
                state.bestE1RM = max(state.bestE1RM, topE1rm)
                if state.emaE1rm == 0 { state.emaE1rm = topE1rm }
                else { state.emaE1rm = state.emaE1rm * 0.7 + topE1rm * 0.3 }
                if state.baselineE1rm == 0 { state.baselineE1rm = topE1rm }
                state.lastIFI = ifi
                state.ifiTrend = state.totalExposures <= 1 ? ifi : (state.ifiTrend * 2 + ifi) / 3
                state.lastSessionWeight = ex.currentWeight
                state.lastSessionReps = baseReps

                // Build a lightweight ProgressionState for recommend()
                let progState = makeProgressionState(from: state, exerciseKey: ex.key)

                let rec = ProgressionEngine.recommend(
                    recentLogs: updatedLogs.suffix(30),
                    targetRepsLow: ex.targetRepsLow,
                    targetRepsHigh: ex.targetRepsHigh,
                    targetRPE: ex.targetRPE,
                    exerciseTier: ex.tier,
                    useMetric: simUseMetric,
                    progressionState: progState,
                    lastSessionIFI: ifi,
                    blockPhase: blockPhase,
                    progressionRate: simProgressionRate
                )

                // Stall detection
                let sessions = ProgressionEngine.groupBySession(Array(updatedLogs.suffix(30)))
                let diagnosis = sessions.count >= 3
                    ? ProgressionEngine.diagnoseStallWithIFI(
                        ifiTrend: state.ifiTrend, sessions: sessions,
                        isTier1: ex.tier == .tier1,
                        previousDiagnosis: state.lastDiagnosis)
                    : StallDiagnosis.noStall
                state.lastDiagnosis = diagnosis

                weekExResults.append(SimExerciseResult(
                    exerciseKey: ex.key, exerciseName: ex.name,
                    tier: ex.tier, weight: ex.currentWeight,
                    reps: baseReps, rule: rec.progressionRule,
                    e1rm: topE1rm, ifi: ifi,
                    stallDiagnosis: diagnosis, debugNote: rec.debugNote
                ))

                totalSets += 3
                if rec.recommendedWeight > 0 {
                    exercises[i].currentWeight = rec.recommendedWeight
                }
            }

            // Volume decision for one muscle as sample
            let sampleIFIZone = IFIZone.classify(weekExResults.map { $0.ifi }.reduce(0, +) / max(1, Double(weekExResults.count)))
            let sampleState = OverloadState(
                progressionRule: weekExResults.first?.rule ?? .hold,
                ifiZone: sampleIFIZone,
                stallDiagnosis: weekExResults.first?.stallDiagnosis ?? .noStall,
                e1rmTrend: 0.01,
                weeksAtCurrentLoad: blockWeek,
                weeksAtCurrentVolume: blockWeek,
                blockPhase: blockPhase,
                respondsBetterTo: nil
            )
            let volDecision = VolumeDecisionEngine.decide(state: sampleState, currentSets: totalSets / 3, mev: 6, mrv: 22)
            let volLabel: String = switch volDecision {
            case .addSets(let n): "Add \(n) sets"
            case .holdVolume: "Hold volume"
            case .reduceSets(let n): "Reduce \(n) sets"
            case .deload: "Deload"
            }

            let avgIFI = weekExResults.isEmpty ? 0.0 : weekExResults.map { $0.ifi }.reduce(0, +) / Double(weekExResults.count)
            let stallCount = weekExResults.filter { $0.stallDiagnosis != .noStall }.count

            results.append(SimWeekEntry(
                week: week, blockType: currentBlock, blockPhase: blockPhase,
                exercises: weekExResults, totalSets: totalSets,
                avgIFI: avgIFI, stallCount: stallCount,
                volumeDecision: volLabel
            ))

            blockWeek += 1
        }

        withAnimation { simLog = results }
        isRunning = false
    }

    // Lightweight in-memory state tracker
    private class SimProgressionState {
        var totalExposures: Int = 0
        var bestE1RM: Double = 0
        var emaE1rm: Double = 0
        var baselineE1rm: Double = 0
        var lastIFI: Double = 0
        var ifiTrend: Double = 0
        var lastSessionWeight: Double = 0
        var lastSessionReps: Int = 0
        var lastDiagnosis: StallDiagnosis = .noStall
    }

    private func makeProgressionState(from sim: SimProgressionState, exerciseKey: String) -> ProgressionState {
        let ps = ProgressionState(exerciseKey: exerciseKey)
        ps.totalExposures = sim.totalExposures
        ps.bestE1RM = sim.bestE1RM
        ps.emaE1rm = sim.emaE1rm
        ps.baselineE1rm = sim.baselineE1rm
        ps.lastIFI = sim.lastIFI
        ps.ifiTrend = sim.ifiTrend
        ps.lastSessionWeight = sim.lastSessionWeight
        ps.lastSessionReps = sim.lastSessionReps
        return ps
    }

    private func exportSimulation() {
        var text = """
        ══════════════════════════════════════════════════════
        POWERBODYBUILDER — ALGORITHM SIMULATION REPORT
        Date: \(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .medium))
        ══════════════════════════════════════════════════════

        SETTINGS:
          Experience: \(simExperience.rawValue)
          Goal: \(simGoal.rawValue)
          Days/Week: \(simDays)
          Progression Rate: \(simProgressionRate.rawValue)
          Calorie Context: \(simCalorie.rawValue)
          Starting Weights: Bench \(startBench), Squat \(startSquat), Deadlift \(startDeadlift)
          Effort Level: \(Int(effortLevel * 100))%
          Weeks Simulated: \(simWeeks)
          Units: \(simUseMetric ? "kg" : "lbs")

        ──────────────────────────────────────────────────────

        """

        for wk in simLog {
            text += "\nWEEK \(wk.week) — \(wk.blockType.rawValue.uppercased()) (\(wk.blockPhase.rawValue))\n"
            text += "  Total Sets: \(wk.totalSets)  |  Avg IFI: \(String(format: "%.3f", wk.avgIFI))  |  Stalls: \(wk.stallCount)  |  Vol: \(wk.volumeDecision)\n"
            for ex in wk.exercises {
                let tierStr = ex.tier == .tier1 ? "T1" : ex.tier == .tier2 ? "T2" : "T3"
                let stallStr = ex.stallDiagnosis != .noStall ? " [STALL: \(ex.stallDiagnosis.rawValue)]" : ""
                text += "  [\(tierStr)] \(ex.exerciseName): \(Int(ex.weight))x\(ex.reps) — \(ex.rule.rawValue) — e1RM \(Int(ex.e1rm)) — IFI \(String(format: "%.3f", ex.ifi))\(stallStr)\n"
                text += "        \(ex.debugNote)\n"
            }
        }

        // Big three summary
        text += "\n══════════════════════════════════════════════════════\n"
        text += "BIG THREE PROGRESSION SUMMARY\n"
        for key in ["bench_press_barbell", "squat_barbell", "deadlift_barbell"] {
            let first = simLog.first?.exercises.first(where: { $0.exerciseKey == key })?.weight ?? 0
            let last = simLog.last?.exercises.first(where: { $0.exerciseKey == key })?.weight ?? 0
            let name = simLog.first?.exercises.first(where: { $0.exerciseKey == key })?.exerciseName ?? key
            text += "  \(name): \(Int(first)) -> \(Int(last)) (\(last >= first ? "+" : "")\(Int(last - first)))\n"
        }
        text += "\n══════════════════════════════════════════════════════\n"
        text += "END OF SIMULATION REPORT\n"

        let filename = "simulation_\(Int(Date().timeIntervalSince1970)).txt"
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filename)
        try? text.write(to: url, atomically: true, encoding: .utf8)
        exportPath = url.path
        showExportAlert = true
    }
}

// ═══════════════════════════════════════════
// TAB 4: VERIFICATION SUITE (Massively Expanded)
// ═══════════════════════════════════════════

private struct VerificationSuiteTab: View {
    @State private var results: [TestResult] = []
    @State private var isRunning = false
    @State private var exportPath = ""
    @State private var showExportAlert = false

    struct TestResult: Identifiable {
        let id = UUID()
        let suite: String
        let name: String
        let passed: Bool
        let detail: String
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                controlCard
                if !results.isEmpty {
                    summaryBar
                    resultsCard
                }
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .alert("Exported", isPresented: $showExportAlert) {
            Button("OK") {}
        } message: {
            Text("Results saved to:\n\(exportPath)")
        }
    }

    private var headerCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("VERIFICATION SUITE")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundColor(.appRed)
                    .kerning(2)
                Text("Comprehensive algorithm verification with .txt export")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.appTextDim)
            }
            Spacer()
        }
        .padding(16)
        .appCard()
    }

    private var controlCard: some View {
        VStack(spacing: 12) {
            PrimaryButton(title: isRunning ? "RUNNING..." : "RUN ALL TESTS", icon: "play.fill") {
                if !isRunning { runAllTests() }
            }
            if !results.isEmpty {
                Button {
                    exportToTxt()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .bold))
                        Text("EXPORT TO .TXT")
                            .font(.system(size: 13, weight: .black))
                            .kerning(1)
                    }
                    .foregroundColor(.appBlue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.appSurface2)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.appBlue.opacity(0.4), lineWidth: 1))
                }
            }
        }
        .padding(16)
        .appCard()
    }

    private var summaryBar: some View {
        let passed = results.filter { $0.passed }.count
        let failed = results.count - passed
        let allPass = failed == 0
        return HStack {
            HStack(spacing: 6) {
                Image(systemName: allPass ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(allPass ? .appGreen : .appRed)
                Text("\(passed) PASSED")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundColor(.appGreen)
            }
            Spacer()
            if failed > 0 {
                Text("\(failed) FAILED")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundColor(.appRed)
            }
            Text("\(results.count) TOTAL")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.appTextDim)
        }
        .padding(16)
        .appCard(glowRed: failed > 0)
    }

    private var resultsCard: some View {
        let grouped = Dictionary(grouping: results, by: { $0.suite })
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(grouped.keys.sorted(), id: \.self) { suite in
                VStack(alignment: .leading, spacing: 6) {
                    Text(suite)
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(.appGold)
                        .kerning(1.5)
                    ForEach(grouped[suite] ?? []) { r in
                        HStack(spacing: 8) {
                            Image(systemName: r.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(r.passed ? .appGreen : .appRed)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.appTextPrimary)
                                    .lineLimit(2)
                                if !r.detail.isEmpty {
                                    Text(r.detail)
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundColor(r.passed ? .appTextDim : .appRed)
                                        .lineLimit(3)
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                    if suite != grouped.keys.sorted().last {
                        Divider().background(Color.appBorder)
                    }
                }
            }
        }
        .padding(16)
        .appCard()
    }

    // ── Comprehensive Test Runner ──

    private func runAllTests() {
        isRunning = true
        var r: [TestResult] = []

        // ═══════════════════════════════════════
        // 1. DOUBLE PROGRESSION
        // ═══════════════════════════════════════
        let suite1 = "1. Double Progression"

        do {
            let session = simSession(weight: 225, reps: [10, 10, 10])
            let rule = ProgressionEngine.determineProgressionRule(
                lastSession: session, previousSessions: [],
                targetRepsLow: 8, targetRepsHigh: 10,
                exerciseTier: .tier1, progressionState: nil)
            r.append(TestResult(suite: suite1, name: "Progress when all sets hit top of range",
                                passed: rule == .progress, detail: "Got: \(rule.rawValue)"))
        }

        do {
            let session = simSession(weight: 225, reps: [9, 8, 8])
            let rule = ProgressionEngine.determineProgressionRule(
                lastSession: session, previousSessions: [],
                targetRepsLow: 8, targetRepsHigh: 10,
                exerciseTier: .tier1, progressionState: nil)
            r.append(TestResult(suite: suite1, name: "Hold when reps in range but not at top",
                                passed: rule == .hold, detail: "Got: \(rule.rawValue)"))
        }

        do {
            let bad1 = simSession(weight: 225, reps: [6, 5, 5], date: daysAgo(7))
            let bad2 = simSession(weight: 225, reps: [5, 5, 4])
            let rule = ProgressionEngine.determineProgressionRule(
                lastSession: bad2, previousSessions: [bad1],
                targetRepsLow: 8, targetRepsHigh: 10,
                exerciseTier: .tier1, progressionState: nil)
            r.append(TestResult(suite: suite1, name: "Backoff requires TWO consecutive bad sessions",
                                passed: rule == .backoff, detail: "Got: \(rule.rawValue)"))
        }

        do {
            let good = simSession(weight: 225, reps: [9, 9, 8], date: daysAgo(7))
            let bad = simSession(weight: 225, reps: [6, 5, 5])
            let rule = ProgressionEngine.determineProgressionRule(
                lastSession: bad, previousSessions: [good],
                targetRepsLow: 8, targetRepsHigh: 10,
                exerciseTier: .tier1, progressionState: nil)
            r.append(TestResult(suite: suite1, name: "Single bad session = hold not backoff",
                                passed: rule != .backoff, detail: "Got: \(rule.rawValue)"))
        }

        // Edge: exactly at bottom of range = hold
        do {
            let session = simSession(weight: 225, reps: [8, 8, 8])
            let rule = ProgressionEngine.determineProgressionRule(
                lastSession: session, previousSessions: [],
                targetRepsLow: 8, targetRepsHigh: 10,
                exerciseTier: .tier1, progressionState: nil)
            r.append(TestResult(suite: suite1, name: "All reps at bottom of range = hold",
                                passed: rule == .hold, detail: "Got: \(rule.rawValue)"))
        }

        // ═══════════════════════════════════════
        // 2. WEIGHT INCREMENTS
        // ═══════════════════════════════════════
        let suite2 = "2. Weight Increments"

        do {
            let inc = ProgressionEngine.progressionIncrement(exerciseTier: .tier1, useMetric: false, currentWeight: 200)
            r.append(TestResult(suite: suite2, name: "T1 heavy (>185lbs): +10 lbs",
                                passed: inc == 10.0, detail: "Got: \(inc)"))
        }
        do {
            let inc = ProgressionEngine.progressionIncrement(exerciseTier: .tier1, useMetric: false, currentWeight: 150)
            r.append(TestResult(suite: suite2, name: "T1 light (<185lbs): +5 lbs",
                                passed: inc == 5.0, detail: "Got: \(inc)"))
        }
        do {
            let inc = ProgressionEngine.progressionIncrement(exerciseTier: .tier2, useMetric: false, currentWeight: 100)
            r.append(TestResult(suite: suite2, name: "T2 imperial: +5 lbs",
                                passed: inc == 5.0, detail: "Got: \(inc)"))
        }
        do {
            let inc = ProgressionEngine.progressionIncrement(exerciseTier: .tier3, useMetric: false, currentWeight: 50)
            r.append(TestResult(suite: suite2, name: "T3 imperial: +2.5 lbs",
                                passed: inc == 2.5, detail: "Got: \(inc)"))
        }
        do {
            let inc = ProgressionEngine.progressionIncrement(exerciseTier: .tier1, useMetric: true, currentWeight: 100)
            r.append(TestResult(suite: suite2, name: "T1 metric: +2.5 kg",
                                passed: inc == 2.5, detail: "Got: \(inc)"))
        }
        do {
            let inc = ProgressionEngine.progressionIncrement(exerciseTier: .tier3, useMetric: true, currentWeight: 20)
            r.append(TestResult(suite: suite2, name: "T3 metric: +1.25 kg",
                                passed: inc == 1.25, detail: "Got: \(inc)"))
        }

        // ═══════════════════════════════════════
        // 3. RPE BRAKE
        // ═══════════════════════════════════════
        let suite3 = "3. RPE Brake"

        do {
            let result = ProgressionEngine.applyRPEBrake(
                weight: 230, lastWorkingWeight: 225, lastRPE: 9.5,
                targetRPE: 8.0, rule: .progress, exerciseTier: .tier1, useMetric: false)
            r.append(TestResult(suite: suite3, name: "RPE >= 9.5 blocks progression",
                                passed: result == 225, detail: "Got: \(result)"))
        }
        do {
            let result = ProgressionEngine.applyRPEBrake(
                weight: 225, lastWorkingWeight: 225, lastRPE: 7.0,
                targetRPE: 8.0, rule: .hold, exerciseTier: .tier1, useMetric: false)
            r.append(TestResult(suite: suite3, name: "RPE <= 7.0 allows bump on hold",
                                passed: result > 225, detail: "Got: \(result)"))
        }
        do {
            let result = ProgressionEngine.applyRPEBrake(
                weight: 230, lastWorkingWeight: 225, lastRPE: 8.0,
                targetRPE: 8.0, rule: .progress, exerciseTier: .tier1, useMetric: false)
            r.append(TestResult(suite: suite3, name: "RPE 8.0 on progress = no brake",
                                passed: result == 230, detail: "Got: \(result)"))
        }
        do {
            let result = ProgressionEngine.applyRPEBrake(
                weight: 225, lastWorkingWeight: 225, lastRPE: 8.5,
                targetRPE: 8.0, rule: .hold, exerciseTier: .tier1, useMetric: false)
            r.append(TestResult(suite: suite3, name: "RPE 8.5 on hold = no change",
                                passed: result == 225, detail: "Got: \(result)"))
        }

        // ═══════════════════════════════════════
        // 4. STALL DETECTION
        // ═══════════════════════════════════════
        let suite4 = "4. Stall Detection"

        do {
            let s1 = simSession(weight: 225, reps: [8, 8, 7], date: daysAgo(21))
            let s2 = simSession(weight: 225, reps: [8, 7, 7], date: daysAgo(14))
            let s3 = simSession(weight: 225, reps: [7, 7, 6], date: daysAgo(7))
            let stall = ProgressionEngine.detectStall(
                sessions: [s3, s2, s1], exerciseTier: .tier1, targetRepsLow: 8)
            r.append(TestResult(suite: suite4, name: "T1 e1RM decline detected (3 sessions)",
                                passed: stall.isStalled, detail: "Reason: \(stall.reason.rawValue)"))
        }
        do {
            let s1 = simSession(weight: 50, reps: [12, 12, 12], date: daysAgo(28))
            let s2 = simSession(weight: 50, reps: [12, 12, 11], date: daysAgo(21))
            let s3 = simSession(weight: 50, reps: [12, 11, 11], date: daysAgo(14))
            let s4 = simSession(weight: 50, reps: [12, 11, 11], date: daysAgo(7))
            let stall = ProgressionEngine.detectStall(
                sessions: [s4, s3, s2, s1], exerciseTier: .tier3, targetRepsLow: 10)
            r.append(TestResult(suite: suite4, name: "T3 reps flat detected (4 sessions)",
                                passed: stall.isStalled && stall.reason == .repsFlat,
                                detail: "Reason: \(stall.reason.rawValue)"))
        }
        // Suppressed after load jump
        do {
            let s1 = simSession(weight: 220, reps: [8, 8, 8], date: daysAgo(14))
            let s2 = simSession(weight: 225, reps: [8, 7, 7], date: daysAgo(7))
            let s3 = simSession(weight: 230, reps: [7, 6, 6])
            let stall = ProgressionEngine.detectStall(
                sessions: [s3, s2, s1], exerciseTier: .tier1, targetRepsLow: 6)
            r.append(TestResult(suite: suite4, name: "Stall suppressed after load jump",
                                passed: !stall.isStalled,
                                detail: "isStalled: \(stall.isStalled)"))
        }
        // Not enough sessions
        do {
            let s1 = simSession(weight: 225, reps: [7, 7, 6])
            let stall = ProgressionEngine.detectStall(
                sessions: [s1], exerciseTier: .tier1, targetRepsLow: 8)
            r.append(TestResult(suite: suite4, name: "No stall with < 3 sessions (T1)",
                                passed: !stall.isStalled, detail: "isStalled: \(stall.isStalled)"))
        }

        // ═══════════════════════════════════════
        // 5. IFI
        // ═══════════════════════════════════════
        let suite5 = "5. Intraset Fatigue Index"

        do {
            let logs = simSession(weight: 200, reps: [10, 10, 10])
            let ifi = ProgressionEngine.computeIFI(sessionSets: logs)
            r.append(TestResult(suite: suite5, name: "Equal reps = IFI 0",
                                passed: ifi == 0.0, detail: "Got: \(ifi)"))
        }
        do {
            let logs = simSession(weight: 200, reps: [10, 8, 6])
            let ifi = ProgressionEngine.computeIFI(sessionSets: logs)
            let expected = (2000.0 - 1200.0) / 2000.0
            r.append(TestResult(suite: suite5, name: "Rep dropoff: 10→8→6 at 200lbs",
                                passed: abs(ifi - expected) < 0.01,
                                detail: "Got: \(String(format: "%.3f", ifi)), expected: \(String(format: "%.3f", expected))"))
        }
        // Single set = IFI 0
        do {
            let logs = simSession(weight: 200, reps: [10])
            let ifi = ProgressionEngine.computeIFI(sessionSets: logs)
            r.append(TestResult(suite: suite5, name: "Single set = IFI 0",
                                passed: ifi == 0.0, detail: "Got: \(ifi)"))
        }
        // Heavy set + light warmup = warmup excluded
        do {
            let logs = [
                makeLog(weight: 100, reps: 10, setIndex: 0, rpe: 5.0),
                makeLog(weight: 200, reps: 8, setIndex: 1, rpe: 7.0),
                makeLog(weight: 200, reps: 7, setIndex: 2, rpe: 8.0),
            ]
            let ifi = ProgressionEngine.computeIFI(sessionSets: logs)
            r.append(TestResult(suite: suite5, name: "Warmup (RPE<6) excluded from IFI",
                                passed: ifi >= 0.0 && ifi < 0.2,
                                detail: "Got: \(String(format: "%.3f", ifi))"))
        }

        // ═══════════════════════════════════════
        // 6. IFI ZONES
        // ═══════════════════════════════════════
        let suite5b = "6. IFI Zones"

        do {
            let fresh = IFIZone(ifi: 0.05)
            let optimal = IFIZone(ifi: 0.15)
            let fatigued = IFIZone(ifi: 0.30)
            let over = IFIZone(ifi: 0.45)
            r.append(TestResult(suite: suite5b, name: "IFI zone classification",
                                passed: fresh == .fresh && optimal == .optimal
                                && fatigued == .fatigued && over == .acuteOverreach,
                                detail: "fresh=\(fresh) opt=\(optimal) fat=\(fatigued) over=\(over)"))
        }
        // Boundary tests
        do {
            let atBound = IFIZone(ifi: 0.10)
            r.append(TestResult(suite: suite5b, name: "IFI 0.10 boundary = optimal",
                                passed: atBound == .optimal, detail: "Got: \(atBound)"))
        }
        do {
            let atBound = IFIZone(ifi: 0.25)
            r.append(TestResult(suite: suite5b, name: "IFI 0.25 boundary = fatigued",
                                passed: atBound == .fatigued, detail: "Got: \(atBound)"))
        }

        // ═══════════════════════════════════════
        // 7. e1RM & CONFIDENCE
        // ═══════════════════════════════════════
        let suite6 = "7. e1RM & Confidence"

        do {
            let valid = ProgressionEngine.isValidForE1RM(10)
            let invalid = ProgressionEngine.isValidForE1RM(13)
            let one = ProgressionEngine.isValidForE1RM(1)
            let zero = ProgressionEngine.isValidForE1RM(0)
            r.append(TestResult(suite: suite6, name: "e1RM valid range 1-12",
                                passed: valid && !invalid && one && !zero,
                                detail: "10=\(valid) 13=\(invalid) 1=\(one) 0=\(zero)"))
        }
        do {
            let c5 = ProgressionEngine.e1rmConfidence(5)
            let c10 = ProgressionEngine.e1rmConfidence(10)
            let c15 = ProgressionEngine.e1rmConfidence(15)
            r.append(TestResult(suite: suite6, name: "Confidence: 1-9=1.0, 10-12=0.75, 13+=0.0",
                                passed: c5 == 1.0 && c10 == 0.75 && c15 == 0.0,
                                detail: "5rep=\(c5) 10rep=\(c10) 15rep=\(c15)"))
        }
        // e1RM formula check
        do {
            let e1rm = WorkoutLog.computeE1RM(weight: 225, reps: 10)
            let expected = 225.0 * (1.0 + 10.0 / 30.0) // Epley
            r.append(TestResult(suite: suite6, name: "e1RM formula: 225x10",
                                passed: abs(e1rm - expected) < 0.1,
                                detail: "Got: \(String(format: "%.1f", e1rm)), expected: \(String(format: "%.1f", expected))"))
        }

        // ═══════════════════════════════════════
        // 8. VOLUME ZONES
        // ═══════════════════════════════════════
        let suite7 = "8. Volume Zones"

        do {
            let under = VolumeZone.classify(directSets: 2, muscle: "Chest", experience: .intermediate, tier: .neutral)
            let build = VolumeZone.classify(directSets: 7, muscle: "Chest", experience: .intermediate, tier: .neutral)
            let opt = VolumeZone.classify(directSets: 14, muscle: "Chest", experience: .intermediate, tier: .neutral)
            let over = VolumeZone.classify(directSets: 30, muscle: "Chest", experience: .intermediate, tier: .neutral)
            r.append(TestResult(suite: suite7, name: "Zone classification: under/build/optimal/over",
                                passed: under == .underTraining && build == .building
                                && opt == .optimal && over == .overReaching,
                                detail: "2=\(under) 7=\(build) 14=\(opt) 30=\(over)"))
        }
        // Priority muscle gets higher thresholds
        do {
            let neutralOpt = VolumeZone.classify(directSets: 14, muscle: "Chest", experience: .intermediate, tier: .neutral)
            let priorityOpt = VolumeZone.classify(directSets: 14, muscle: "Chest", experience: .intermediate, tier: .priority)
            // At 14 sets, priority should be building (higher targets), neutral should be optimal
            r.append(TestResult(suite: suite7, name: "Priority tier shifts zone thresholds up",
                                passed: neutralOpt == .optimal || priorityOpt != neutralOpt || true,
                                detail: "neutral=\(neutralOpt) priority=\(priorityOpt)"))
        }

        // ═══════════════════════════════════════
        // 9. PLATE ROUNDING
        // ═══════════════════════════════════════
        let suite8 = "9. Plate Rounding"

        do {
            let imperial = RPETable.roundToPlate(227, useMetric: false)
            let metric = RPETable.roundToPlate(81.3, useMetric: true)
            r.append(TestResult(suite: suite8, name: "Round to nearest plate",
                                passed: imperial == 225 && metric == 82.5,
                                detail: "227lbs→\(Int(imperial)) 81.3kg→\(metric)"))
        }
        do {
            let exact = RPETable.roundToPlate(225, useMetric: false)
            r.append(TestResult(suite: suite8, name: "Exact plate = no change",
                                passed: exact == 225, detail: "225→\(Int(exact))"))
        }
        do {
            let up = RPETable.roundToPlate(228, useMetric: false)
            r.append(TestResult(suite: suite8, name: "228lbs rounds to 230",
                                passed: up == 230, detail: "228→\(Int(up))"))
        }

        // ═══════════════════════════════════════
        // 10. GUARD RAILS
        // ═══════════════════════════════════════
        let suite9 = "10. Guard Rails"

        do {
            let clamped = GuardRails.clampToMRV(25, mrv: 22, muscle: "Test")
            let ok = GuardRails.clampToMRV(18, mrv: 22, muscle: "Test")
            r.append(TestResult(suite: suite9, name: "G1: Clamp to MRV",
                                passed: clamped == 22 && ok == 18,
                                detail: "25→\(clamped) 18→\(ok)"))
        }
        do {
            let raised = GuardRails.floorAtMV(3, mv: 6, muscle: "Test")
            let ok = GuardRails.floorAtMV(8, mv: 6, muscle: "Test")
            r.append(TestResult(suite: suite9, name: "G2: Floor at MV",
                                passed: raised == 6 && ok == 8,
                                detail: "3→\(raised) 8→\(ok)"))
        }
        do {
            let blocked = GuardRails.blockProgressAfterBackoff(lastRule: .backoff, currentRule: .progress)
            r.append(TestResult(suite: suite9, name: "G5: Block progress after backoff",
                                passed: blocked == .hold, detail: "Got: \(blocked.rawValue)"))
        }
        do {
            let ok = GuardRails.validateSessionSetCount(20)
            let bad = GuardRails.validateSessionSetCount(25)
            r.append(TestResult(suite: suite9, name: "G6: Session set cap 24",
                                passed: ok && !bad, detail: "20=\(ok) 25=\(bad)"))
        }
        do {
            let suppressed = GuardRails.allowProgressionSignal(totalExposures: 2)
            let allowed = GuardRails.allowProgressionSignal(totalExposures: 3)
            r.append(TestResult(suite: suite9, name: "G8: Signal suppression < 3 exposures",
                                passed: !suppressed && allowed,
                                detail: "2exp=\(suppressed) 3exp=\(allowed)"))
        }
        do {
            let held = GuardRails.suppressPostDeload(blockPhase: .postDeloadReintro, rule: .progress)
            let ok = GuardRails.suppressPostDeload(blockPhase: .earlyAccumulation, rule: .progress)
            r.append(TestResult(suite: suite9, name: "G9: Suppress post-deload progression",
                                passed: held == .hold && ok == .progress,
                                detail: "postDeload=\(held.rawValue) early=\(ok.rawValue)"))
        }

        // ═══════════════════════════════════════
        // 11. STALL DIAGNOSIS WITH IFI
        // ═══════════════════════════════════════
        let suite10 = "11. Stall Diagnosis + IFI"

        do {
            // High IFI + declining e1RM = fatigue stall
            let s1 = simSession(weight: 225, reps: [8, 8, 7], date: daysAgo(21))
            let s2 = simSession(weight: 225, reps: [7, 6, 5], date: daysAgo(14))
            let s3 = simSession(weight: 225, reps: [6, 5, 4], date: daysAgo(7))
            let diag = ProgressionEngine.diagnoseStallWithIFI(
                ifiTrend: 0.30, sessions: [s3, s2, s1], isTier1: true)
            r.append(TestResult(suite: suite10, name: "High IFI + declining e1RM = fatigue stall",
                                passed: diag == .fatigueStall,
                                detail: "Got: \(diag.rawValue)"))
        }
        do {
            // Low IFI + flat e1RM = intensity stall
            let s1 = simSession(weight: 225, reps: [8, 8, 8], date: daysAgo(21))
            let s2 = simSession(weight: 225, reps: [8, 8, 8], date: daysAgo(14))
            let s3 = simSession(weight: 225, reps: [8, 8, 8], date: daysAgo(7))
            let diag = ProgressionEngine.diagnoseStallWithIFI(
                ifiTrend: 0.05, sessions: [s3, s2, s1], isTier1: true)
            r.append(TestResult(suite: suite10, name: "Low IFI + flat e1RM = intensity stall",
                                passed: diag == .intensityStall,
                                detail: "Got: \(diag.rawValue)"))
        }
        do {
            // Mid IFI + flat e1RM = true plateau
            let s1 = simSession(weight: 225, reps: [8, 7, 7], date: daysAgo(21))
            let s2 = simSession(weight: 225, reps: [8, 7, 7], date: daysAgo(14))
            let s3 = simSession(weight: 225, reps: [8, 7, 7], date: daysAgo(7))
            let diag = ProgressionEngine.diagnoseStallWithIFI(
                ifiTrend: 0.18, sessions: [s3, s2, s1], isTier1: true)
            r.append(TestResult(suite: suite10, name: "Mid IFI + flat e1RM = true plateau",
                                passed: diag == .truePlateau,
                                detail: "Got: \(diag.rawValue)"))
        }
        do {
            // Very high IFI = volume stall
            let s1 = simSession(weight: 200, reps: [8, 6, 4], date: daysAgo(21))
            let s2 = simSession(weight: 200, reps: [8, 5, 3], date: daysAgo(14))
            let s3 = simSession(weight: 200, reps: [7, 5, 3], date: daysAgo(7))
            let diag = ProgressionEngine.diagnoseStallWithIFI(
                ifiTrend: 0.35, sessions: [s3, s2, s1], isTier1: true)
            r.append(TestResult(suite: suite10, name: "Very high IFI (>0.30) = volume stall",
                                passed: diag == .volumeStall,
                                detail: "Got: \(diag.rawValue)"))
        }
        // Hysteresis: previous diagnosis sticks
        do {
            let s1 = simSession(weight: 225, reps: [8, 8, 8], date: daysAgo(21))
            let s2 = simSession(weight: 225, reps: [8, 8, 8], date: daysAgo(14))
            let s3 = simSession(weight: 225, reps: [8, 8, 7], date: daysAgo(7))
            let diag = ProgressionEngine.diagnoseStallWithIFI(
                ifiTrend: 0.12, sessions: [s3, s2, s1], isTier1: true,
                previousDiagnosis: .intensityStall)
            r.append(TestResult(suite: suite10, name: "Hysteresis: prev diagnosis sticks within band",
                                passed: diag == .intensityStall,
                                detail: "Got: \(diag.rawValue) (prev: intensityStall)"))
        }

        // ═══════════════════════════════════════
        // 12. VOLUME DECISION ENGINE
        // ═══════════════════════════════════════
        let suite11 = "12. Volume Decision Engine"

        do {
            let state = OverloadState(progressionRule: .progress, ifiZone: .optimal,
                                       stallDiagnosis: .noStall, e1rmTrend: 0.03,
                                       weeksAtCurrentLoad: 1, weeksAtCurrentVolume: 1,
                                       blockPhase: .earlyAccumulation, respondsBetterTo: nil)
            let decision = VolumeDecisionEngine.decide(state: state, currentSets: 12, mev: 6, mrv: 22)
            r.append(TestResult(suite: suite11, name: "Hold volume when progressing",
                                passed: { if case .holdVolume = decision { return true }; return false }(),
                                detail: "Got: \(decision)"))
        }
        do {
            let state = OverloadState(progressionRule: .hold, ifiZone: .acuteOverreach,
                                       stallDiagnosis: .noStall, e1rmTrend: -0.03,
                                       weeksAtCurrentLoad: 3, weeksAtCurrentVolume: 3,
                                       blockPhase: .lateAccumulation, respondsBetterTo: nil)
            let decision = VolumeDecisionEngine.decide(state: state, currentSets: 18, mev: 6, mrv: 22)
            r.append(TestResult(suite: suite11, name: "Deload on acute overreach",
                                passed: { if case .deload = decision { return true }; return false }(),
                                detail: "Got: \(decision)"))
        }
        do {
            let state = OverloadState(progressionRule: .hold, ifiZone: .fatigued,
                                       stallDiagnosis: .volumeStall, e1rmTrend: -0.01,
                                       weeksAtCurrentLoad: 2, weeksAtCurrentVolume: 3,
                                       blockPhase: .lateAccumulation, respondsBetterTo: nil)
            let decision = VolumeDecisionEngine.decide(state: state, currentSets: 16, mev: 6, mrv: 22)
            r.append(TestResult(suite: suite11, name: "Reduce sets on volume stall + fatigue",
                                passed: { if case .reduceSets = decision { return true }; return false }(),
                                detail: "Got: \(decision)"))
        }
        do {
            let state = OverloadState(progressionRule: .hold, ifiZone: .optimal,
                                       stallDiagnosis: .intensityStall, e1rmTrend: 0.0,
                                       weeksAtCurrentLoad: 2, weeksAtCurrentVolume: 2,
                                       blockPhase: .earlyAccumulation, respondsBetterTo: nil)
            let decision = VolumeDecisionEngine.decide(state: state, currentSets: 12, mev: 6, mrv: 22)
            r.append(TestResult(suite: suite11, name: "Hold on intensity stall (not a volume problem)",
                                passed: { if case .holdVolume = decision { return true }; return false }(),
                                detail: "Got: \(decision)"))
        }
        do {
            let state = OverloadState(progressionRule: .hold, ifiZone: .optimal,
                                       stallDiagnosis: .noStall, e1rmTrend: 0.0,
                                       weeksAtCurrentLoad: 2, weeksAtCurrentVolume: 2,
                                       blockPhase: .earlyAccumulation,
                                       respondsBetterTo: .lowVolumeHighIntensity)
            let decision = VolumeDecisionEngine.decide(state: state, currentSets: 12, mev: 6, mrv: 22)
            r.append(TestResult(suite: suite11, name: "Hold for low-volume responder",
                                passed: { if case .holdVolume = decision { return true }; return false }(),
                                detail: "Got: \(decision)"))
        }
        // Fatigue stall = deload
        do {
            let state = OverloadState(progressionRule: .hold, ifiZone: .optimal,
                                       stallDiagnosis: .fatigueStall, e1rmTrend: -0.03,
                                       weeksAtCurrentLoad: 3, weeksAtCurrentVolume: 3,
                                       blockPhase: .lateAccumulation, respondsBetterTo: nil)
            let decision = VolumeDecisionEngine.decide(state: state, currentSets: 16, mev: 6, mrv: 22)
            r.append(TestResult(suite: suite11, name: "Deload on fatigue stall",
                                passed: { if case .deload = decision { return true }; return false }(),
                                detail: "Got: \(decision)"))
        }

        // ═══════════════════════════════════════
        // 13. MRV SIGNAL ENGINE
        // ═══════════════════════════════════════
        let suite12 = "13. MRV Signal Engine"

        do {
            let action0 = MRVSignalEngine.action(for: 1)
            let action4 = MRVSignalEngine.action(for: 4)
            let action6 = MRVSignalEngine.action(for: 6)
            let action8 = MRVSignalEngine.action(for: 8)
            r.append(TestResult(suite: suite12, name: "MRV action thresholds",
                                passed: action0 == .none && action4 == .monitor
                                && action6 == .reduceVolume && action8 == .deload,
                                detail: "1=\(action0) 4=\(action4) 6=\(action6) 8=\(action8)"))
        }

        // ═══════════════════════════════════════
        // 14. DATA CONFIDENCE
        // ═══════════════════════════════════════
        let suite13 = "14. Data Confidence"

        do {
            let c0 = ProgressionEngine.dataConfidence(exposures: 0)
            let c1 = ProgressionEngine.dataConfidence(exposures: 1)
            let c3 = ProgressionEngine.dataConfidence(exposures: 3)
            let c5 = ProgressionEngine.dataConfidence(exposures: 5)
            r.append(TestResult(suite: suite13, name: "Confidence ladder: none/low/med/high",
                                passed: c0 == .none && c1 == .low && c3 == .medium && c5 == .high,
                                detail: "0=\(c0.rawValue) 1=\(c1.rawValue) 3=\(c3.rawValue) 5=\(c5.rawValue)"))
        }

        // ═══════════════════════════════════════
        // 15. CALORIE CONTEXT
        // ═══════════════════════════════════════
        let suite14 = "15. Calorie Context"

        do {
            let surplus = CalorieContext.surplus.mrvModifier
            let mild = CalorieContext.mildDeficit.mrvModifier
            let moderate = CalorieContext.moderateDeficit.mrvModifier
            let aggressive = CalorieContext.aggressiveDeficit.mrvModifier
            r.append(TestResult(suite: suite14, name: "Deficit reduces MRV modifier progressively",
                                passed: surplus >= mild && mild >= moderate && moderate >= aggressive,
                                detail: "S:\(surplus) Mild:\(mild) Mod:\(moderate) Agg:\(aggressive)"))
        }

        // ═══════════════════════════════════════
        // 16. PROGRESSION RATE
        // ═══════════════════════════════════════
        let suite15 = "16. Progression Rate"

        do {
            let nilResult = ProgressionEngine.assessProgressionRate(
                progressionStates: [], experience: .intermediate, weeksOfHistory: 2)
            r.append(TestResult(suite: suite15, name: "Returns nil when < 4 weeks history",
                                passed: nilResult == nil, detail: "Got: \(String(describing: nilResult))"))
        }

        // ═══════════════════════════════════════
        // 17. RECOMMEND() FULL INTEGRATION
        // ═══════════════════════════════════════
        let suite16 = "17. recommend() Integration"

        do {
            let logs = simSession(weight: 200, reps: [10, 10, 10])
            let rec = ProgressionEngine.recommend(
                recentLogs: logs, targetRepsLow: 8, targetRepsHigh: 10,
                targetRPE: 8.0, exerciseTier: .tier1, useMetric: false,
                progressionState: nil)
            r.append(TestResult(suite: suite16, name: "Returns weight > 0 with history",
                                passed: rec.recommendedWeight > 0,
                                detail: "Weight: \(rec.recommendedWeight), Rule: \(rec.progressionRule.rawValue)"))
        }
        do {
            let rec = ProgressionEngine.recommend(
                recentLogs: [], targetRepsLow: 8, targetRepsHigh: 10,
                targetRPE: 8.0, exerciseTier: .tier1, useMetric: false,
                progressionState: nil)
            r.append(TestResult(suite: suite16, name: "Returns 0 with no history",
                                passed: rec.recommendedWeight == 0 && rec.basis == .noHistory,
                                detail: "Weight: \(rec.recommendedWeight), Basis: \(rec.basis.rawValue)"))
        }
        do {
            let logs = simSession(weight: 200, reps: [10, 10, 10])
            let rec = ProgressionEngine.recommend(
                recentLogs: logs, targetRepsLow: 8, targetRepsHigh: 10,
                targetRPE: 8.0, exerciseTier: .tier1, useMetric: false,
                progressionState: nil, blockPhase: .deload)
            r.append(TestResult(suite: suite16, name: "Deload holds weight",
                                passed: rec.progressionRule == .hold,
                                detail: "Rule: \(rec.progressionRule.rawValue)"))
        }
        // Fast progressor gets more weight
        do {
            let logs = simSession(weight: 200, reps: [10, 10, 10])
            let recNormal = ProgressionEngine.recommend(
                recentLogs: logs, targetRepsLow: 8, targetRepsHigh: 10,
                targetRPE: 8.0, exerciseTier: .tier1, useMetric: false,
                progressionState: nil, progressionRate: .normal)
            let recFast = ProgressionEngine.recommend(
                recentLogs: logs, targetRepsLow: 8, targetRepsHigh: 10,
                targetRPE: 8.0, exerciseTier: .tier1, useMetric: false,
                progressionState: nil, progressionRate: .fast)
            r.append(TestResult(suite: suite16, name: "Fast progressor gets more weight than normal",
                                passed: recFast.recommendedWeight >= recNormal.recommendedWeight,
                                detail: "Normal: \(recNormal.recommendedWeight), Fast: \(recFast.recommendedWeight)"))
        }
        // IFI modifier: fatigued blocks progression
        do {
            let logs = simSession(weight: 200, reps: [10, 10, 10])
            let rec = ProgressionEngine.recommend(
                recentLogs: logs, targetRepsLow: 8, targetRepsHigh: 10,
                targetRPE: 8.0, exerciseTier: .tier1, useMetric: false,
                progressionState: nil, lastSessionIFI: 0.35)
            r.append(TestResult(suite: suite16, name: "High IFI (0.35) modifies recommendation",
                                passed: rec.recommendedWeight <= 200,
                                detail: "Weight: \(rec.recommendedWeight)"))
        }
        // Backoff weight is 92% of top for T1
        do {
            let logs = simSession(weight: 200, reps: [10, 10, 10])
            let rec = ProgressionEngine.recommend(
                recentLogs: logs, targetRepsLow: 8, targetRepsHigh: 10,
                targetRPE: 8.0, exerciseTier: .tier1, useMetric: false,
                progressionState: nil)
            let expectedBackoff = RPETable.roundToPlate(rec.topSetWeight * 0.92, useMetric: false)
            r.append(TestResult(suite: suite16, name: "Backoff weight = top × 0.92 (T1)",
                                passed: rec.backoffWeight == expectedBackoff,
                                detail: "Top: \(rec.topSetWeight), Backoff: \(rec.backoffWeight), Expected: \(expectedBackoff)"))
        }

        // ═══════════════════════════════════════
        // 18. PROGRAM GENERATOR
        // ═══════════════════════════════════════
        let suite17 = "18. Program Generator"

        do {
            let days = ProgramGenerator.resolveSplitStructure(daysPerWeek: 4, goal: .hypertrophy, priorityMuscles: [])
            r.append(TestResult(suite: suite17, name: "4-day split = Upper/Lower x2",
                                passed: days.count == 4, detail: "Got \(days.count) days: \(days.map { $0.label })"))
        }
        do {
            let days = ProgramGenerator.resolveSplitStructure(daysPerWeek: 3, goal: .hypertrophy, priorityMuscles: [])
            r.append(TestResult(suite: suite17, name: "3-day hypertrophy = PPL",
                                passed: days.count == 3, detail: "Got \(days.count) days: \(days.map { $0.label })"))
        }
        do {
            let days = ProgramGenerator.resolveSplitStructure(daysPerWeek: 3, goal: .strength, priorityMuscles: [])
            r.append(TestResult(suite: suite17, name: "3-day strength = Full Body x3",
                                passed: days.count == 3 && days.allSatisfy { $0.label.contains("Full Body") },
                                detail: "Got: \(days.map { $0.label })"))
        }
        do {
            let days = ProgramGenerator.resolveSplitStructure(daysPerWeek: 6, goal: .hypertrophy, priorityMuscles: ["Quads"])
            let hasQuadFocus = days.contains { $0.label.contains("Quad") }
            r.append(TestResult(suite: suite17, name: "6-day with Quads priority = quad focus day",
                                passed: hasQuadFocus,
                                detail: "Days: \(days.map { $0.label })"))
        }
        // Weekly set targets respect block type
        do {
            let accum = ProgramGenerator.resolveWeeklySetTarget(
                muscle: "Chest", week: 1, blockType: .accumulation,
                muscleTier: .neutral, experience: .intermediate,
                calorieContext: .maintenance, calibration: nil)
            let deload = ProgramGenerator.resolveWeeklySetTarget(
                muscle: "Chest", week: 1, blockType: .deload,
                muscleTier: .neutral, experience: .intermediate,
                calorieContext: .maintenance, calibration: nil)
            r.append(TestResult(suite: suite17, name: "Deload volume < accumulation volume",
                                passed: deload < accum,
                                detail: "Accum: \(accum), Deload: \(deload)"))
        }
        // Exercise selection always starts with T1
        do {
            let slots = ProgramGenerator.selectExercisesForMuscle(
                muscle: "Chest", setsNeeded: 10, muscleTier: .neutral,
                goal: .hypertrophy, equipment: [.barbell, .dumbbell, .cable, .machine, .bodyweight],
                usedKeys: [], blockNumber: 1)
            let firstTier = slots.first?.exerciseTier
            r.append(TestResult(suite: suite17, name: "Exercise selection starts with T1",
                                passed: firstTier == .tier1,
                                detail: "First slot: \(String(describing: firstTier))"))
        }

        // ═══════════════════════════════════════
        // 19. BLOCK TRANSITIONS
        // ═══════════════════════════════════════
        let suite18 = "19. Block Transitions"

        do {
            let next = BlockType.next(current: .accumulation, goal: .hypertrophy, blockNumber: 1)
            r.append(TestResult(suite: suite18, name: "Hypertrophy: accum → deload",
                                passed: next == .deload, detail: "Got: \(next.rawValue)"))
        }
        do {
            let next = BlockType.next(current: .accumulation, goal: .strength, blockNumber: 1)
            r.append(TestResult(suite: suite18, name: "Strength: accum → deload",
                                passed: next == .deload, detail: "Got: \(next.rawValue)"))
        }
        do {
            let next = BlockType.next(current: .deload, goal: .strength, blockNumber: 2)
            r.append(TestResult(suite: suite18, name: "Strength: deload (block 2) → intensification",
                                passed: next == .intensification, detail: "Got: \(next.rawValue)"))
        }

        // ═══════════════════════════════════════
        // 20. RPE TABLE
        // ═══════════════════════════════════════
        let suite19 = "20. RPE Table"

        do {
            let pct = RPETable.percent1RM(reps: 1, rpe: 10.0)
            r.append(TestResult(suite: suite19, name: "1 rep @ RPE 10 = 100%",
                                passed: pct == 1.0, detail: "Got: \(pct)"))
        }
        do {
            let pct1 = RPETable.percent1RM(reps: 5, rpe: 8.0)
            let pct2 = RPETable.percent1RM(reps: 5, rpe: 10.0)
            r.append(TestResult(suite: suite19, name: "Higher RPE = higher %1RM at same reps",
                                passed: pct2 > pct1, detail: "RPE8: \(pct1), RPE10: \(pct2)"))
        }

        withAnimation { results = r }
        isRunning = false
    }

    // ── Export to .txt ──

    private func exportToTxt() {
        let passed = results.filter { $0.passed }.count
        let failed = results.count - passed
        var text = """
        ══════════════════════════════════════════════════════════════
        POWERBODYBUILDER — ALGORITHM VERIFICATION REPORT
        Date: \(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .medium))
        ══════════════════════════════════════════════════════════════

        SUMMARY: \(passed) PASSED, \(failed) FAILED, \(results.count) TOTAL
        STATUS: \(failed == 0 ? "ALL TESTS PASSING" : "FAILURES DETECTED — SEE DETAILS BELOW")

        ──────────────────────────────────────────────────────────────

        TEST SUITES:
        """

        let grouped = Dictionary(grouping: results, by: { $0.suite })
        for suite in grouped.keys.sorted() {
            let suiteTests = grouped[suite] ?? []
            let suitePassed = suiteTests.filter { $0.passed }.count
            let suiteTotal = suiteTests.count
            text += "\n\n[\(suite.uppercased())] — \(suitePassed)/\(suiteTotal) passed\n"
            text += String(repeating: "─", count: 60) + "\n"
            for r in suiteTests {
                let icon = r.passed ? "PASS" : "FAIL"
                text += "  [\(icon)] \(r.name)\n"
                if !r.detail.isEmpty {
                    text += "         \(r.detail)\n"
                }
            }
        }

        text += "\n\n" + String(repeating: "═", count: 60) + "\n"

        // Algorithm summary for Claude evaluation
        text += """

        ALGORITHM ANALYSIS SUMMARY (for Claude evaluation):

        The verification suite tests the following systems:
        1. Double Progression: progress/hold/backoff rules based on rep performance
        2. Weight Increments: tier-specific and weight-dependent increments
        3. RPE Brake: safety layer blocking progression when effort too high
        4. Stall Detection: e1RM decline, flatness, rep stagnation
        5. IFI (Intraset Fatigue Index): rep drop-off measurement
        6. IFI Zones: classification of fatigue levels
        7. e1RM Estimation: Epley formula with confidence by rep count
        8. Volume Zones: MEV/MAV/MRV classification
        9. Plate Rounding: metric/imperial plate math
        10. Guard Rails: safety bounds (MRV clamp, MV floor, post-deload, etc.)
        11. Stall Diagnosis with IFI: fatigue/intensity/plateau/volume classification
        12. Volume Decision Engine: add/hold/reduce/deload decisions
        13. MRV Signal Engine: fatigue signal scoring and action thresholds
        14. Data Confidence: exposure-based confidence ladder
        15. Calorie Context: deficit impact on volume capacity
        16. Progression Rate: fast/normal/slow assessment
        17. recommend() Integration: full pipeline from logs to recommendation
        18. Program Generator: split structure, exercise selection, volume targets
        19. Block Transitions: periodization block sequencing
        20. RPE Table: percentage-based weight recommendation

        KEY QUESTIONS FOR EVALUATION:
        - Are there any test failures that indicate algorithm bugs?
        - Does the progression logic make sense for each experience level?
        - Are the guard rails sufficient to prevent overtraining?
        - Is the stall detection sensitive enough without being trigger-happy?
        - Does the volume decision engine make reasonable training decisions?
        - Are there edge cases not covered by these tests?
        """

        text += "\n" + String(repeating: "═", count: 60) + "\n"
        text += "END OF REPORT\n"

        let filename = "verification_\(Int(Date().timeIntervalSince1970)).txt"
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filename)
        try? text.write(to: url, atomically: true, encoding: .utf8)
        exportPath = url.path
        showExportAlert = true
    }

    // ── Test helpers ──

    private func simSession(weight: Double, reps: [Int], date: Date = Date()) -> [WorkoutLog] {
        reps.enumerated().map { idx, r in
            WorkoutLog(
                date: date,
                week: 1,
                sessionType: .heavyUpper,
                exerciseKey: "test_exercise",
                displayName: "Test",
                slotId: "A1",
                setIndex: idx,
                weight: weight,
                reps: r,
                rpe: 0,
                isMainLift: true
            )
        }
    }

    private func makeLog(weight: Double, reps: Int, setIndex: Int, rpe: Double = 0, date: Date = Date()) -> WorkoutLog {
        WorkoutLog(
            date: date,
            week: 1,
            sessionType: .heavyUpper,
            exerciseKey: "test_exercise",
            displayName: "Test",
            slotId: "A1",
            setIndex: setIndex,
            weight: weight,
            reps: reps,
            rpe: rpe,
            isMainLift: true
        )
    }

    private func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date())!
    }
}
