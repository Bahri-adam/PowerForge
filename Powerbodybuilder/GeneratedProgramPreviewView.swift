import SwiftUI
import SwiftData

// ═══════════════════════════════════════════
// PROGRAM SUGGESTION ENGINE
// ═══════════════════════════════════════════

struct ProgramSuggestionEngine {
    static func explain(
        goal: GoalType, experience: ExperienceLevel, daysPerWeek: Int,
        calorieContext: CalorieContext, muscleTiers: [String: MuscleTier],
        weeklyTargets: [String: Int]
    ) -> [String] {
        var b: [String] = []
        switch daysPerWeek {
        case ...2: b.append("With \(daysPerWeek) training days, we're using full body sessions to hit every muscle twice per week — the most efficient split for your schedule.")
        case 3:
            if goal == .strength { b.append("Three full body days lets you practice the main lifts frequently — ideal for building strength with compound movements.") }
            else { b.append("A Push/Pull/Legs split across 3 days gives each muscle group a dedicated session with enough volume to grow.") }
        case 4: b.append("Upper/Lower split across 4 days hits every muscle twice per week — the sweet spot for most intermediate lifters.")
        case 5: b.append("5-day split uses Push/Pull/Legs plus two priority sessions to give your focus muscles extra frequency.")
        case 6...: b.append("6-day PPL gives you two sessions per muscle group — heavy compounds on A days, hypertrophy accessories on B days.")
        default: break
        }
        let prios = muscleTiers.filter { $0.value == .priority }.map { $0.key }
        if !prios.isEmpty {
            let total = prios.compactMap { weeklyTargets[$0] }.reduce(0, +)
            b.append("\(prios.joined(separator: " and ")) set as priority — \(total) weekly sets with extra frequency.")
        }
        let maint = muscleTiers.filter { $0.value == .maintenance }.map { $0.key }
        if !maint.isEmpty { b.append("\(maint.joined(separator: ", ")) on maintenance — just enough to preserve size.") }
        switch calorieContext {
        case .aggressiveDeficit: b.append("Aggressive deficit — MRV ceiling lowered to match limited recovery.")
        case .moderateDeficit: b.append("Moderate deficit — slightly reduced max volume for recovery.")
        case .surplus: b.append("In a surplus — volume ceilings at maximum to take advantage of extra fuel.")
        default: break
        }
        switch goal {
        case .strength: b.append("Barbell-only T1 anchors at 2-5 reps — built for progressive overload.")
        case .hypertrophy: b.append("T1 at 5-8, T2 at 8-12, T3 at 12-20 — optimized for muscle growth.")
        case .powerbuilding: b.append("T1 at 3-6 for strength, T2/T3 for hypertrophy volume.")
        case .recomp: b.append("Short 3-week blocks, moderate 6-10 rep range for recomposition.")
        }
        return b
    }
}

// ═══════════════════════════════════════════
// GENERATED PROGRAM PREVIEW VIEW
// Live-configurable program generator preview.
// ═══════════════════════════════════════════

struct GeneratedProgramPreviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var profiles: [UserProfile]
    @Query private var allInstances: [UserProgramInstance]
    @Query private var allUserPrograms: [UserProgram]

    let programId: Int
    let programName: String

    private var generatedName: String {
        let goal = cfgGoal.displayName
        let days = cfgDays
        let splitName: String
        switch days {
        case ...2: splitName = "Full Body"
        case 3: splitName = cfgGoal == .strength ? "Full Body" : "PPL"
        case 4: splitName = "Upper/Lower"
        case 5: splitName = "ULPPL"
        case 6...: splitName = "PPL"
        default: splitName = ""
        }
        return "\(goal) \(splitName) \(days)x"
    }

    // ── Configurable state (seeded from profile, editable live) ──
    @State private var cfgGoal: GoalType = .hypertrophy
    @State private var cfgExperience: ExperienceLevel = .intermediate
    @State private var cfgDays: Int = 4
    @State private var cfgCalories: CalorieContext = .surplus
    @State private var cfgTiers: [String: MuscleTier] = [:]
    @State private var cfgPriorities: [String] = []
    @State private var didSeedFromProfile = false

    // ── Generated output ──
    @State private var previewSplit: [GeneratedDayTemplate] = []
    @State private var weeklyTargets: [String: Int] = [:]
    @State private var sessionExercises: [String: [ExerciseSlot]] = [:]
    @State private var explanations: [String] = []
    @State private var showConfig = true

    private var profile: UserProfile? { profiles.first }
    private let allMuscles = ExerciseDictionary.trackingMuscles

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerSection
                configSection
                if !previewSplit.isEmpty {
                    explanationSection
                    volumeSection
                    sessionsSection
                    ctaSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .background(Color.appBG)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { seedFromProfile(); regenerate() }
    }

    // ═══════════════════════════════════════
    // HEADER
    // ═══════════════════════════════════════

    private var headerSection: some View {
        VStack(spacing: 6) {
            Text("PROGRAM GENERATOR")
                .font(.caption).fontWeight(.bold).foregroundColor(.appRed).tracking(2)
            Text(generatedName)
                .font(.title3).fontWeight(.bold).foregroundColor(.appTextPrimary)
        }
        .padding(.top, 12)
    }

    // ═══════════════════════════════════════
    // LIVE CONFIGURATION PANEL
    // ═══════════════════════════════════════

    private var configSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showConfig.toggle() }
            } label: {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(.appRed)
                    Text("CONFIGURE")
                        .font(.caption).fontWeight(.bold).foregroundColor(.appTextSecondary).tracking(1)
                    Spacer()
                    Image(systemName: showConfig ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundColor(.appTextDim)
                }
            }
            .buttonStyle(.plain)

            if showConfig {
                // Goal
                VStack(alignment: .leading, spacing: 6) {
                    Text("Goal").font(.caption).foregroundColor(.appTextDim)
                    HStack(spacing: 8) {
                        ForEach(GoalType.allCases, id: \.self) { g in
                            chipButton(g.displayName, selected: cfgGoal == g) { cfgGoal = g; regenerate() }
                        }
                    }
                }

                // Experience
                VStack(alignment: .leading, spacing: 6) {
                    Text("Experience").font(.caption).foregroundColor(.appTextDim)
                    HStack(spacing: 8) {
                        ForEach(ExperienceLevel.allCases, id: \.self) { e in
                            chipButton(e.rawValue, selected: cfgExperience == e) { cfgExperience = e; regenerate() }
                        }
                    }
                }

                // Days per week
                VStack(alignment: .leading, spacing: 6) {
                    Text("Days / Week").font(.caption).foregroundColor(.appTextDim)
                    HStack(spacing: 8) {
                        ForEach(2...6, id: \.self) { d in
                            chipButton("\(d)", selected: cfgDays == d) { cfgDays = d; regenerate() }
                        }
                    }
                }

                // Calories
                VStack(alignment: .leading, spacing: 6) {
                    Text("Calories").font(.caption).foregroundColor(.appTextDim)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(CalorieContext.allCases, id: \.self) { c in
                                chipButton(c.rawValue.replacingOccurrences(of: "_", with: " ").capitalized,
                                           selected: cfgCalories == c) { cfgCalories = c; regenerate() }
                            }
                        }
                    }
                }

                // Muscle tiers
                VStack(alignment: .leading, spacing: 6) {
                    Text("Muscle Tiers (tap to cycle)").font(.caption).foregroundColor(.appTextDim)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                        ForEach(allMuscles, id: \.self) { muscle in
                            let tier = cfgTiers[muscle] ?? .neutral
                            Button {
                                cycleTier(muscle)
                                regenerate()
                            } label: {
                                VStack(spacing: 2) {
                                    Text(muscle)
                                        .font(.caption2).fontWeight(.semibold)
                                        .foregroundColor(tier == .priority ? .appGold : (tier == .maintenance ? .appTextDim : .appTextPrimary))
                                    Text(tier.label)
                                        .font(.system(size: 9))
                                        .foregroundColor(tier == .priority ? .appGold : (tier == .maintenance ? .appTextDim : .appTextSecondary))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(tier == .priority ? Color.appGold.opacity(0.1) : (tier == .maintenance ? Color.appSurface2.opacity(0.5) : Color.appSurface2))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(tier == .priority ? Color.appGold.opacity(0.3) : Color.appBorder, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(14)
        .modifier(AppCard())
    }

    private func chipButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .foregroundColor(selected ? .white : .appTextSecondary)
                .background(selected ? Color.appRed : Color.appSurface2)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private func cycleTier(_ muscle: String) {
        let current = cfgTiers[muscle] ?? .neutral
        switch current {
        case .neutral:     cfgTiers[muscle] = .priority
        case .priority:    cfgTiers[muscle] = .maintenance
        case .maintenance: cfgTiers[muscle] = .neutral
        }
        cfgPriorities = cfgTiers.filter { $0.value == .priority }.map { $0.key }
    }

    // ═══════════════════════════════════════
    // EXPLANATION BULLETS
    // ═══════════════════════════════════════

    private var explanationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHY THIS PROGRAM").font(.caption).fontWeight(.bold).foregroundColor(.appTextSecondary).tracking(1)
            ForEach(explanations, id: \.self) { bullet in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.appGreen).font(.caption).padding(.top, 2)
                    Text(bullet).font(.subheadline).foregroundColor(.appTextPrimary)
                }
            }
        }
        .padding(14).modifier(AppCard())
    }

    // ═══════════════════════════════════════
    // VOLUME BARS
    // ═══════════════════════════════════════

    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WEEKLY VOLUME").font(.caption).fontWeight(.bold).foregroundColor(.appTextSecondary).tracking(1)
            ForEach(allMuscles, id: \.self) { muscle in
                let target = weeklyTargets[muscle] ?? 0
                let tier = cfgTiers[muscle] ?? .neutral
                let mrv = VolumeLandmark.effectiveMRV(muscle: muscle, experience: cfgExperience, tier: tier, calorieContext: cfgCalories)
                HStack {
                    Text(muscle).font(.caption).foregroundColor(tier == .priority ? .appGold : (tier == .maintenance ? .appTextDim : .appTextPrimary))
                        .frame(width: 80, alignment: .leading)
                    GeometryReader { geo in
                        let pct = mrv > 0 ? min(CGFloat(target) / CGFloat(mrv), 1.0) : 0
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(Color.appSurface2)
                            RoundedRectangle(cornerRadius: 3).fill(tier == .priority ? Color.appGold : Color.appGreen)
                                .frame(width: geo.size.width * pct)
                        }
                    }.frame(height: 10)
                    Text("\(target)").font(.caption2).fontWeight(.bold).foregroundColor(.appTextPrimary).frame(width: 24, alignment: .trailing)
                }
            }
            let total = weeklyTargets.values.reduce(0, +)
            HStack { Spacer(); Text("Total: \(total) sets/week").font(.caption).foregroundColor(.appTextSecondary) }
        }
        .padding(14).modifier(AppCard())
    }

    // ═══════════════════════════════════════
    // SESSION CARDS
    // ═══════════════════════════════════════

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YOUR SESSIONS").font(.caption).fontWeight(.bold).foregroundColor(.appTextSecondary).tracking(1)
            ForEach(Array(previewSplit.enumerated()), id: \.offset) { idx, day in
                if day.sessionType != .rest { sessionCard(day: day, dayNum: idx + 1) }
            }
        }
    }

    private func sessionCard(day: GeneratedDayTemplate, dayNum: Int) -> some View {
        let slots = sessionExercises[day.label] ?? []
        let total = slots.reduce(0) { $0 + $1.sets }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("DAY \(dayNum)").font(.caption2).fontWeight(.bold).foregroundColor(.appRed)
                Text(day.label).font(.subheadline).fontWeight(.semibold).foregroundColor(.appTextPrimary)
                Spacer()
                Text("\(total) sets").font(.caption).foregroundColor(.appTextSecondary)
            }
            ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                let def = ExerciseDictionary.all[slot.exerciseKey]
                let name = def?.displayName ?? slot.exerciseKey
                let isT1 = slot.exerciseTier == .tier1
                let tc: Color = isT1 ? .appRed : (slot.exerciseTier == .tier2 ? .appBlue : .appGreen)
                HStack(spacing: 8) {
                    Text(isT1 ? "T1" : (slot.exerciseTier == .tier2 ? "T2" : "T3"))
                        .font(.caption2).fontWeight(.bold).foregroundColor(tc).frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name).font(.caption).foregroundColor(.appTextPrimary)
                        Text("\(slot.sets) x \(slot.repsLow)-\(slot.repsHigh)").font(.caption2).foregroundColor(.appTextSecondary)
                    }
                    Spacer()
                    if isT1 {
                        Image(systemName: "lock.fill").font(.caption2).foregroundColor(.appTextDim)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(12).modifier(AppCard())
    }

    // ═══════════════════════════════════════
    // CTA
    // ═══════════════════════════════════════

    private var ctaSection: some View {
        VStack(spacing: 12) {
            Button { applyToProfile(); startProgram() } label: {
                Text("START THIS PROGRAM")
                    .font(.headline).fontWeight(.bold).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(Color.appRed).cornerRadius(14)
            }
            Button { dismiss() } label: {
                Text("Go Back").font(.subheadline).foregroundColor(.appTextSecondary)
            }
        }
        .padding(.top, 8)
    }

    // ═══════════════════════════════════════
    // SEED FROM PROFILE
    // ═══════════════════════════════════════

    private func seedFromProfile() {
        guard !didSeedFromProfile, let p = profile else { return }
        cfgGoal = p.goal
        cfgExperience = p.experience
        cfgDays = p.daysPerWeek
        cfgCalories = p.calorieContext
        cfgTiers = p.muscleTiers
        cfgPriorities = p.priorityMuscles
        didSeedFromProfile = true
    }

    // ═══════════════════════════════════════
    // REGENERATE (called on every config change)
    // ═══════════════════════════════════════

    private func regenerate() {
        cfgPriorities = cfgTiers.filter { $0.value == .priority }.map { $0.key }

        previewSplit = ProgramGenerator.resolveSplitStructure(
            daysPerWeek: cfgDays, goal: cfgGoal, priorityMuscles: cfgPriorities)

        weeklyTargets = [:]
        for m in allMuscles {
            weeklyTargets[m] = ProgramGenerator.resolveWeeklySetTarget(
                muscle: m, week: 1, blockType: .accumulation,
                muscleTier: cfgTiers[m] ?? .neutral, experience: cfgExperience,
                calorieContext: cfgCalories, calibration: nil)
        }

        let equipment: Set<EquipmentType> = [.barbell, .dumbbell, .cable, .machine, .bodyweight]
        let upperSet: Set<String> = ["Chest","Back","Delts","Triceps","Biceps"]
        let lowerSet: Set<String> = ["Quads","Hamstrings","Glutes","Calves"]
        var allSeenKeys: [String: Set<String>] = [:]
        var catSeen: [String: Int] = [:]
        sessionExercises = [:]

        for day in previewSplit {
            guard day.sessionType != .rest else { continue }
            let ms = Set(day.primaryMuscles)
            let cat: String
            if ms.isSubset(of: Set(["Chest","Delts","Triceps"])) { cat = "push" }
            else if ms.isSubset(of: Set(["Back","Biceps"])) { cat = "pull" }
            else if ms.isSubset(of: lowerSet) { cat = "legs" }
            else if ms.isSubset(of: upperSet) { cat = "upper" }
            else { cat = "fullbody" }
            let occ = catSeen[cat, default: 0]; catSeen[cat, default: 0] += 1
            let isB = occ > 0
            let ctx: ProgramGenerator.SessionContext
            if ms.isSubset(of: upperSet) { ctx = .upper } else if ms.isSubset(of: lowerSet) { ctx = .lower } else { ctx = .fullbody }

            var daySlots: [ExerciseSlot] = []
            var allocated: Set<String> = []
            var sessionTotal = 0

            for muscle in day.primaryMuscles {
                let freq = previewSplit.filter { $0.primaryMuscles.contains(muscle) }.count
                let target = weeklyTargets[muscle] ?? 0
                let base = target / max(1, freq); let rem = target % max(1, freq)
                let isFirst = !allocated.contains(muscle)
                let sets: Int
                if isFirst { sets = base + rem; allocated.insert(muscle) }
                else { if base < 2 { continue }; sets = base }
                let capped = min(sets, 24 - sessionTotal)
                guard capped >= 2 else { continue }
                let used = allSeenKeys[muscle] ?? []
                let slots = ProgramGenerator.selectExercisesForMuscle(
                    muscle: muscle, setsNeeded: capped, muscleTier: cfgTiers[muscle] ?? .neutral,
                    goal: cfgGoal, equipment: equipment, usedKeys: used, blockNumber: 0,
                    isSecondarySession: isB, sessionsPerWeek: freq, sessionContext: ctx)
                for s in slots { allSeenKeys[muscle, default: []].insert(s.exerciseKey); sessionTotal += s.sets }
                daySlots.append(contentsOf: slots)
            }
            daySlots.sort { $0.exerciseTier.sortValue < $1.exerciseTier.sortValue }
            sessionExercises[day.label] = daySlots
        }

        explanations = ProgramSuggestionEngine.explain(
            goal: cfgGoal, experience: cfgExperience, daysPerWeek: cfgDays,
            calorieContext: cfgCalories, muscleTiers: cfgTiers, weeklyTargets: weeklyTargets)
    }

    // ═══════════════════════════════════════
    // APPLY CONFIG TO PROFILE & START
    // ═══════════════════════════════════════

    private func applyToProfile() {
        guard let p = profile else { return }
        p.goal = cfgGoal
        p.experience = cfgExperience
        p.daysPerWeek = cfgDays
        p.calorieContextRaw = cfgCalories.rawValue
        p.muscleTiers = cfgTiers
        p.useGeneratedPrograms = true
    }

    private func startProgram() {
        guard let p = profile else { return }

        // Deactivate all existing instances and legacy programs
        for inst in allInstances { inst.isActive = false }
        for up in allUserPrograms { up.isActive = false }

        // Create or reactivate UserProgramInstance
        let instance: UserProgramInstance
        if let existing = allInstances.first(where: { $0.programId == programId }) {
            existing.isActive = true; instance = existing
        } else {
            instance = UserProgramInstance(programId: programId, programVersion: 1, name: generatedName)
            modelContext.insert(instance)
        }

        // Create or reactivate legacy UserProgram (needed for ContentView gate)
        if let existingLegacy = allUserPrograms.first(where: { $0.programId == programId }) {
            existingLegacy.isActive = true
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let userProgram = UserProgram(
                programId: programId,
                name: generatedName,
                startDate: formatter.string(from: Date())
            )
            modelContext.insert(userProgram)
        }

        // Generate block templates
        instance.isGenerated = true
        do {
            let templates = try ProgramGenerator.generateBlock(
                profile: p, instance: instance, blockNumber: 0, blockType: .accumulation,
                previousBlockPeakSets: nil, allLogs: [], progressionStates: [], modelContext: modelContext)
            templates.forEach { modelContext.insert($0) }
        } catch {
            print("GeneratedProgramPreview: block generation failed — \(error)")
            instance.isGenerated = false
        }

        try? modelContext.save()
        dismiss()
    }
}
