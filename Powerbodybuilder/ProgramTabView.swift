import SwiftUI
import SwiftData

// ═══════════════════════════════════════════
// PROGRAM TAB
// Central hub for viewing, editing, and
// configuring your training program.
// ═══════════════════════════════════════════

struct ProgramTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @Query(filter: #Predicate<UserProgramInstance> { $0.isActive == true })
    private var activeInstances: [UserProgramInstance]
    @Query private var allExercises: [Exercise]
    @Query private var programTemplates: [ProgramTemplate]
    @Query private var allSessionTemplates: [ProgramSessionTemplate]

    var profile: UserProfile? { profiles.first }
    var instance: UserProgramInstance? { activeInstances.first }

    @State private var selectedSection: ProgramSection = .overview
    @State private var showSwitchProgram = false
    @State private var showGenerateProgram = false
    @State private var showBuildProgram = false
    @State private var showBlockInfo = false
    @State private var showBlockSequenceEditor = false
    @State private var blockEditorFocusIndex: Int = 0
    @State private var showProgramConfigurator = false
    @State private var editingWeek: Int = 1
    @State private var showStrengthGoalSheet = false
    @State private var editingGoal: StrengthGoal? = nil
    @State private var editSessionItem: SessionEditorItem? = nil
    @State private var volumeAdjustMuscle: String? = nil

    enum ProgramSection: String, CaseIterable {
        case overview = "Overview"
        case weeks = "Weeks"
        case templates = "Templates"
        case exercises = "Exercises"
    }

    var body: some View {
        ZStack {
            Color.appBG.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // ── HEADER ──
                    programHeader
                    // ── SECTION PICKER ──
                    sectionPicker
                    // ── CONTENT ──
                    switch selectedSection {
                    case .overview:  overviewSection
                    case .weeks:     weeksSection
                    case .templates: templatesSection
                    case .exercises: exercisesSection
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $showSwitchProgram) {
            if let p = profile {
                ProgramSelectionView(recommendedId: recommendProgram(
                    goal: p.goal.rawValue, experience: p.experience.rawValue, daysPerWeek: p.daysPerWeek))
            }
        }
        .fullScreenCover(isPresented: $showGenerateProgram) {
            NavigationStack {
                GeneratedProgramPreviewView(
                    programId: 200 + (instance?.programId ?? 100),
                    programName: "Auto-Generated Program")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { showGenerateProgram = false }
                            .foregroundColor(.appTextSecondary)
                    }
                }
            }
        }
        .sheet(isPresented: $showBlockInfo) {
            BlockInfoSheet(instance: instance, profile: profile)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showBlockSequenceEditor) {
            if let inst = instance, let p = profile {
                BlockSequenceEditor(instance: inst, profile: p, focusBlockIndex: blockEditorFocusIndex)
                    .presentationDetents([.large])
            }
        }
        .sheet(isPresented: $showProgramConfigurator) {
            if let inst = instance {
                ProgramConfiguratorSheet(
                    instance: inst,
                    profile: profile,
                    onRequestSequenceEditor: {
                        // Configurator already dismissed itself; present the
                        // editor at the parent level so we avoid sheet-within-sheet.
                        blockEditorFocusIndex = 0
                        showBlockSequenceEditor = true
                    }
                )
                .presentationDetents([.large])
            }
        }
        .sheet(isPresented: $showStrengthGoalSheet) {
            StrengthGoalCreatorSheet(instance: instance, exercises: allExercises,
                                     allLogs: instance?.logs ?? [])
                .presentationDetents([.large])
        }
        .sheet(item: $volumeAdjustMuscle) { muscle in
            if let inst = instance {
                VolumeAdjusterSheet(muscle: muscle, instance: inst, profile: profile, week: inst.currentWeek)
            }
        }
        .sheet(item: $editingGoal) { goal in
            StrengthGoalEditorSheet(goal: goal)
                .presentationDetents([.medium])
        }
        .fullScreenCover(isPresented: $showBuildProgram) {
            ProgramBuilderV2View()
        }
        .sheet(item: $editSessionItem) { item in
            if let inst = instance {
                SessionDetailEditor(sessionType: item.sessionType, templates: item.templates,
                                    exercises: allExercises, overrides: inst.overrides,
                                    instance: inst, week: editingWeek,
                                    onDismiss: { editSessionItem = nil })
            }
        }
        .onAppear { editingWeek = instance?.currentWeek ?? 1 }
    }

    // ═══════════════════════════════════════
    // HEADER
    // ═══════════════════════════════════════

    private var programHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Program icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Color.appRed.opacity(0.1))
                        .frame(width: 48, height: 48)
                    Image(systemName: instance?.isGenerated == true ? "wand.and.stars" : "dumbbell.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(instance?.isGenerated == true ? .appGreen : .appRed)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(instance?.name.uppercased() ?? "NO PROGRAM")
                        .font(.system(size: 16, weight: .black)).foregroundColor(.appTextPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    if let p = profile {
                        HStack(spacing: 8) {
                            Text(p.goal.displayName).font(.system(size: 11, weight: .bold)).foregroundColor(.appTextSecondary)
                            Text("·").foregroundColor(.appTextDim)
                            Text("\(p.daysPerWeek) days").font(.system(size: 11)).foregroundColor(.appTextDim)
                            Text("·").foregroundColor(.appTextDim)
                            Text(p.experience.rawValue).font(.system(size: 11)).foregroundColor(.appTextDim)
                        }
                    }
                }
                Spacer()

                // Week badge
                if let inst = instance, inst.programId != 0 {
                    VStack(spacing: 1) {
                        Text("WK").font(.system(size: 8, weight: .bold)).foregroundColor(.appTextDim)
                        Text("\(inst.currentWeek)").font(.system(size: 20, weight: .black, design: .rounded)).foregroundColor(.appRed)
                    }
                }
            }

            // Action buttons
            HStack(spacing: 8) {
                programActionButton(title: "Switch", icon: "arrow.triangle.2.circlepath", color: .appTextSecondary) {
                    showSwitchProgram = true
                }
                programActionButton(title: "Generate", icon: "wand.and.stars", color: .appGreen) {
                    showGenerateProgram = true
                }
                programActionButton(title: "Build", icon: "hammer.fill", color: .appRed) {
                    showBuildProgram = true
                }
            }
            // Configure button (full width)
            if instance != nil && instance?.programId != 0 {
                Button { showProgramConfigurator = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape.2.fill").font(.system(size: 12, weight: .bold))
                        Text("Configure Program").font(.system(size: 12, weight: .bold))
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 10))
                    }
                    .foregroundColor(.appGold)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color.appGold.opacity(0.06)).cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appGold.opacity(0.2), lineWidth: 1))
                }.buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color.appSurface).cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.appBorder, lineWidth: 1))
        .padding(.top, 8)
    }

    /// Programmed sets for a given muscle in the current week (matches VolumeAdjusterSheet).
    /// Filters out templates whose session has been removed via Configure Program,
    /// and falls back to cross-program lookup for imported session types so they
    /// contribute their real exercise counts to the volume metrics.
    private func programmedSetsForMuscle(_ muscle: String) -> Int {
        guard let inst = instance else { return 0 }
        let week = inst.currentWeek
        var total = 0
        let activeSessions = activeSessionsForWeek(
            programId: inst.programId, instance: inst, profile: profile, week: week,
            templates: programTemplates)
        // Resolve templates per active session using cross-program lookup so
        // imported sessions (whose templates live under another program's pid)
        // still contribute volume.
        var templates: [ProgramSessionTemplate] = []
        for st in activeSessions {
            templates.append(contentsOf: lookupTemplates(
                programId: inst.programId, week: week,
                sessionType: st, allTemplates: allSessionTemplates))
        }
        for t in templates {
            let key = resolveExerciseKey(slotId: t.slotId, originalKey: t.exerciseKey,
                                         overrides: inst.overrides, week: week)
            let targets: Bool = {
                if let def = ExerciseDictionary.all[key] {
                    return def.primaryMuscles.contains { ExerciseDictionary.normalizeMuscle($0) == muscle }
                }
                if let ex = allExercises.first(where: { $0.exerciseKey == key }) {
                    return ex.musclesPrimary.contains { ExerciseDictionary.normalizeMuscle($0) == muscle }
                }
                return false
            }()
            guard targets else { continue }
            let delta = inst.overrides
                .filter { ov in
                    ov.targetSlotId == t.slotId && ov.sessionType == t.sessionType &&
                    ov.setCountDelta != 0 && !ov.isAddition && ov.appliesTo(week: week)
                }
                .reduce(0) { $0 + $1.setCountDelta }
            total += max(0, t.targetSets + delta)
        }
        for ov in inst.overrides where ov.isAddition && ov.appliesTo(week: week) {
            let key = ov.replacementExerciseKey
            if let def = ExerciseDictionary.all[key] {
                if def.primaryMuscles.contains(where: { ExerciseDictionary.normalizeMuscle($0) == muscle }) {
                    total += ov.addedSets
                }
            } else if let ex = allExercises.first(where: { $0.exerciseKey == key }) {
                if ex.musclesPrimary.contains(where: { ExerciseDictionary.normalizeMuscle($0) == muscle }) {
                    total += ov.addedSets
                }
            }
        }
        return total
    }

    private func programActionButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 11, weight: .bold))
                Text(title).font(.system(size: 11, weight: .bold)).kerning(0.3)
            }
            .foregroundColor(color)
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(color.opacity(0.06)).cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // ═══════════════════════════════════════
    // SECTION PICKER
    // ═══════════════════════════════════════

    private var sectionPicker: some View {
        HStack(spacing: 4) {
            ForEach(ProgramSection.allCases, id: \.self) { section in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selectedSection = section }
                } label: {
                    Text(section.rawValue)
                        .font(.system(size: 12, weight: selectedSection == section ? .black : .medium))
                        .foregroundColor(selectedSection == section ? .white : .appTextSecondary)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(selectedSection == section ? Color.appRed : Color.appSurface2)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4).background(Color.appSurface).cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))
    }

    // ═══════════════════════════════════════
    // OVERVIEW SECTION
    // ═══════════════════════════════════════

    private var overviewSection: some View {
        VStack(spacing: 14) {
            // Mesocycle summary
            if let inst = instance, inst.programId != 0 {
                let goal = profile?.goal ?? .hypertrophy
                let isHyp = goal == .hypertrophy || goal == .recomp

                VStack(alignment: .leading, spacing: 10) {
                    Text("MESOCYCLE").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(2)

                    HStack(spacing: 16) {
                        VStack(spacing: 2) {
                            Text(isHyp ? "Training Block" : inst.blockType.rawValue.capitalized)
                                .font(.system(size: 14, weight: .black)).foregroundColor(.appTextPrimary)
                            Text("Current Phase").font(.system(size: 10)).foregroundColor(.appTextDim)
                        }
                        Spacer()
                        VStack(spacing: 2) {
                            Text("\(inst.blockWeek)/\(inst.blockLength)")
                                .font(.system(size: 18, weight: .black, design: .rounded)).foregroundColor(.appRed)
                            Text("Block Week").font(.system(size: 10)).foregroundColor(.appTextDim)
                        }
                        VStack(spacing: 2) {
                            Text("#\(inst.totalBlocksCompleted + 1)")
                                .font(.system(size: 18, weight: .black, design: .rounded)).foregroundColor(.appBlue)
                            Text("Block").font(.system(size: 10)).foregroundColor(.appTextDim)
                        }
                    }
                }
                .padding(14).background(Color.appSurface).cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
            }

            // Block configurator
            if let inst = instance, inst.programId != 0 {
                BlockConfigCard(inst: inst, goal: profile?.goal ?? .hypertrophy,
                                onTapBlock: { idx in blockEditorFocusIndex = idx; showBlockSequenceEditor = true },
                                modelContext: modelContext)
            }

            // Strength goals
            if let inst = instance {
                strengthGoalsManagement(inst: inst)
            }

            // Volume — programmed vs target
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("WEEKLY VOLUME").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(2)
                    Spacer()
                    Text("Programmed / Target").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim).kerning(0.5)
                }

                ForEach(ExerciseDictionary.trackingMuscles, id: \.self) { muscle in
                    let tier = profile?.muscleTiers[muscle] ?? .neutral
                    let autoTarget = ProgramGenerator.resolveWeeklySetTarget(
                        muscle: muscle, week: instance?.currentWeek ?? 1, blockType: instance?.blockType ?? .accumulation,
                        muscleTier: tier, experience: profile?.experience ?? .intermediate,
                        calorieContext: profile?.calorieContext ?? .surplus, calibration: nil)
                    // Honor user's custom target override, fallback to auto-computed
                    let target = profile?.muscleTargetOverrides[muscle].flatMap { $0 > 0 ? $0 : nil } ?? autoTarget
                    let mrv = VolumeLandmark.effectiveMRV(
                        muscle: muscle, experience: profile?.experience ?? .intermediate,
                        tier: tier, calorieContext: profile?.calorieContext ?? .surplus)
                    let programmed = programmedSetsForMuscle(muscle)
                    let underTarget = programmed < target

                    Button { volumeAdjustMuscle = muscle } label: {
                        HStack(spacing: 8) {
                            Text(muscle).font(.system(size: 11, weight: .bold))
                                .foregroundColor(tier == .priority ? .appGold : (tier == .maintenance ? .appTextDim : .appTextPrimary))
                                .frame(width: 70, alignment: .leading)
                            if tier == .priority { Text("★").font(.system(size: 9)).foregroundColor(.appGold) }
                            GeometryReader { geo in
                                let progPct = mrv > 0 ? min(CGFloat(programmed) / CGFloat(mrv), 1.0) : 0
                                let targPct = mrv > 0 ? min(CGFloat(target) / CGFloat(mrv), 1.0) : 0
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3).fill(Color.appSurface2).frame(height: 8)
                                    // Programmed fill (solid)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(tier == .priority ? Color.appGold : (underTarget ? Color.appOrange : Color.appGreen))
                                        .frame(width: geo.size.width * progPct, height: 8)
                                    // Target marker (vertical line)
                                    Rectangle().fill(Color.appTextPrimary).frame(width: 1.5, height: 12)
                                        .offset(x: geo.size.width * targPct - 1, y: -2)
                                }
                            }.frame(height: 12)
                            Text("\(programmed)/\(target)").font(.system(size: 10, weight: .black, design: .rounded))
                                .foregroundColor(underTarget ? .appOrange : .appTextPrimary).frame(width: 42, alignment: .trailing)
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                // Legend
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 1).fill(Color.appGreen).frame(width: 8, height: 4)
                        Text("Programmed").font(.system(size: 9)).foregroundColor(.appTextDim)
                    }
                    HStack(spacing: 4) {
                        Rectangle().fill(Color.appTextPrimary).frame(width: 1.5, height: 8)
                        Text("Target").font(.system(size: 9)).foregroundColor(.appTextDim)
                    }
                    Spacer()
                }
                .padding(.top, 4)
            }
            .padding(14).background(Color.appSurface).cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))

            // Muscle priority configuration
            if profile != nil {
                muscleTierEditor
            }

            // Split structure
            if let inst = instance, inst.programId != 0 {
                let split = programSplit()
                VStack(alignment: .leading, spacing: 10) {
                    Text("SPLIT STRUCTURE").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(2)
                    ForEach(Array(split.enumerated()), id: \.offset) { idx, day in
                        HStack(spacing: 8) {
                            Text("D\(idx + 1)").font(.system(size: 10, weight: .black, design: .monospaced))
                                .foregroundColor(.appRed).frame(width: 22)
                            Text(day.0).font(.system(size: 13, weight: .bold)).foregroundColor(.appTextPrimary)
                            Spacer()
                            Text(day.1).font(.system(size: 11)).foregroundColor(.appTextDim).lineLimit(1)
                        }
                    }
                }
                .padding(14).background(Color.appSurface).cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
            }

            // Session duration estimate
            VStack(alignment: .leading, spacing: 8) {
                Text("SESSION ESTIMATES").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(2)
                let split = programSplit()
                ForEach(Array(split.enumerated()), id: \.offset) { idx, day in
                    let sets = estimateSessionSets(sessionMuscles: day.1)
                    let minutes = sets * 3  // ~3 min per set average
                    HStack {
                        Text(day.0).font(.system(size: 12, weight: .bold)).foregroundColor(.appTextSecondary)
                        Spacer()
                        Text("\(sets) sets").font(.system(size: 11, weight: .bold)).foregroundColor(.appTextPrimary)
                        Text("~\(minutes) min").font(.system(size: 11)).foregroundColor(.appTextDim)
                    }
                }
            }
            .padding(14).background(Color.appSurface).cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
        }
    }

    // ═══════════════════════════════════════
    // STRENGTH GOALS MANAGEMENT
    // ═══════════════════════════════════════

    private func strengthGoalsManagement(inst: UserProgramInstance) -> some View {
        let activeGoals = inst.strengthGoals.filter { $0.isActive }

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("STRENGTH GOALS").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(2)
                Spacer()
                if activeGoals.count < 3 {
                    Button { showStrengthGoalSheet = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                            Text("ADD").font(.system(size: 10, weight: .black))
                        }
                        .foregroundColor(.appRed).padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.appRed.opacity(0.08)).cornerRadius(6)
                    }.buttonStyle(.plain)
                } else {
                    Text("3/3").font(.system(size: 10, weight: .bold)).foregroundColor(.appTextDim)
                }
            }

            if activeGoals.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "target").font(.system(size: 16)).foregroundColor(.appTextDim)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No strength goals set").font(.system(size: 13, weight: .bold)).foregroundColor(.appTextSecondary)
                        Text("Pick a compound lift and set a target. The algorithm will build a peaking plan.")
                            .font(.system(size: 11)).foregroundColor(.appTextDim)
                    }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.appSurface).cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
            } else {
                ForEach(activeGoals, id: \.exerciseKey) { goal in
                    let bestE1rm = inst.logs.filter { $0.exerciseKey == goal.exerciseKey }
                        .map { $0.e1rm }.max() ?? goal.startE1RM
                    let progress = min(1.0, max(0, (bestE1rm - goal.startE1RM) / max(goal.targetWeight - goal.startE1RM, 1)))
                    let isHyp = profile?.goal == .hypertrophy || profile?.goal == .recomp

                    Button { editingGoal = goal } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: "target").font(.system(size: 13)).foregroundColor(.appRed)
                                Text(goal.displayName).font(.system(size: 14, weight: .black)).foregroundColor(.appTextPrimary)
                                Spacer()
                                Text("\(Int(goal.targetWeight)) lb")
                                    .font(.system(size: 16, weight: .black, design: .rounded)).foregroundColor(.appGold)
                                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundColor(.appTextDim)
                            }

                            // Progress bar
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4).fill(Color.appSurface2).frame(height: 8)
                                    RoundedRectangle(cornerRadius: 4).fill(Color.appRed)
                                        .frame(width: max(0, geo.size.width * progress), height: 8)
                                }
                            }.frame(height: 8)

                            HStack {
                                Text("e1RM \(Int(bestE1rm)) → \(Int(goal.targetWeight)) lb (\(Int(progress * 100))%)")
                                    .font(.system(size: 11, weight: .bold)).foregroundColor(.appTextSecondary)
                                Spacer()
                                // Phase badge
                                HStack(spacing: 4) {
                                    Circle().fill(goalPhaseColor(goal.phase)).frame(width: 6, height: 6)
                                    Text("\(goal.phase.displayName) Wk \(goal.phaseWeek)/\(goal.currentPhaseLength)")
                                        .font(.system(size: 10, weight: .bold)).foregroundColor(.appTextDim)
                                }
                            }

                            // Week-by-week impact preview
                            VStack(alignment: .leading, spacing: 4) {
                                Text("PROGRAM IMPACT").font(.system(size: 8, weight: .bold)).foregroundColor(.appTextDim).kerning(1)
                                let rr = goal.phase.repRange
                                HStack(spacing: 12) {
                                    Label("\(goal.phase.targetSets)×\(rr.low)-\(rr.high)", systemImage: "dumbbell.fill")
                                        .font(.system(size: 10, weight: .bold)).foregroundColor(.appTextSecondary)
                                    Label("RPE \(String(format: "%.0f", goal.phase.targetRPE))", systemImage: "flame")
                                        .font(.system(size: 10, weight: .bold)).foregroundColor(.appTextSecondary)
                                    Label("Rest 3:00+", systemImage: "timer")
                                        .font(.system(size: 10, weight: .bold)).foregroundColor(.appTextSecondary)
                                }

                                if isHyp {
                                    Text("Other exercises stay hypertrophy (8-12 reps)")
                                        .font(.system(size: 9)).foregroundColor(.appTextDim)
                                }
                            }
                            .padding(8).background(Color.appSurface2).cornerRadius(6)
                        }
                        .padding(14).background(Color.appSurface).cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appRed.opacity(0.2), lineWidth: 1))
                    }.buttonStyle(.plain)
                }

                if activeGoals.count >= 3 {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle").font(.system(size: 10)).foregroundColor(.appBlue)
                        Text("Max 3 active goals — each strength goal adds systemic fatigue and reduces accessory volume. The algorithm manages recovery, but more than 3 would leave too little room for hypertrophy work.")
                            .font(.system(size: 10)).foregroundColor(.appTextDim)
                    }
                    .padding(10).background(Color.appBlue.opacity(0.04)).cornerRadius(8)
                }
            }
        }
    }

    private func goalPhaseColor(_ phase: StrengthGoalPhase) -> Color {
        switch phase {
        case .building: return .appGreen
        case .intensifying: return .appOrange
        case .peaking: return .appRed
        case .testing: return .appGold
        }
    }

    // blockConfigurator is now BlockConfigCard (separate struct below)
    // ═══════════════════════════════════════
    // MUSCLE TIER EDITOR
    // ═══════════════════════════════════════

    private var muscleTierEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("MUSCLE PRIORITIES").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(2)
                Spacer()
                Text("Tap to cycle").font(.system(size: 10)).foregroundColor(.appTextDim)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 95), spacing: 8)], spacing: 8) {
                ForEach(ExerciseDictionary.trackingMuscles, id: \.self) { muscle in
                    let tier = profile?.muscleTiers[muscle] ?? .neutral

                    Button {
                        guard let p = profile else { return }
                        var tiers = p.muscleTiers
                        switch tier {
                        case .neutral:     tiers[muscle] = .priority
                        case .priority:    tiers[muscle] = .maintenance
                        case .maintenance: tiers[muscle] = .neutral
                        }
                        p.muscleTiers = tiers
                        try? modelContext.save()
                    } label: {
                        VStack(spacing: 3) {
                            Text(muscle)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(tier == .priority ? .appGold : (tier == .maintenance ? .appTextDim : .appTextPrimary))
                            HStack(spacing: 3) {
                                Circle().fill(tierColor(tier)).frame(width: 6, height: 6)
                                Text(tier.label)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(tier == .priority ? .appGold : (tier == .maintenance ? .appTextDim : .appTextSecondary))
                            }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(tier == .priority ? Color.appGold.opacity(0.08) : (tier == .maintenance ? Color.appSurface2.opacity(0.5) : Color.appSurface2))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(tier == .priority ? Color.appGold.opacity(0.3) : Color.appBorder, lineWidth: tier == .priority ? 1.5 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Legend
            HStack(spacing: 16) {
                legendItem(color: .appGold, label: "Priority", detail: "+4 sets, 1.5x MRV")
                legendItem(color: .appGreen, label: "Neutral", detail: "Standard volume")
                legendItem(color: .appTextDim, label: "Maintenance", detail: "0.7x MRV ceiling")
            }
            .padding(.top, 4)
        }
        .padding(14).background(Color.appSurface).cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
    }

    private func tierColor(_ tier: MuscleTier) -> Color {
        switch tier {
        case .priority: return .appGold
        case .neutral: return .appGreen
        case .maintenance: return .appTextDim
        }
    }

    private func legendItem(color: Color, label: String, detail: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label).font(.system(size: 9, weight: .bold)).foregroundColor(color)
            Text(detail).font(.system(size: 8)).foregroundColor(.appTextDim)
        }
    }

    // ═══════════════════════════════════════
    // WEEKS SECTION
    // ═══════════════════════════════════════

    private var weeksSection: some View {
        VStack(spacing: 14) {
            // Week picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    let total = totalWeeks
                    ForEach(1...max(total, 1), id: \.self) { w in
                        Button { editingWeek = w } label: {
                            Text("\(w)")
                                .font(.system(size: 12, weight: editingWeek == w ? .black : .medium))
                                .foregroundColor(editingWeek == w ? .white : (w == instance?.currentWeek ? .appRed : .appTextSecondary))
                                .frame(width: 32, height: 32)
                                .background(editingWeek == w ? Color.appRed : Color.appSurface2)
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8)
                                    .stroke(w == instance?.currentWeek ? Color.appRed.opacity(0.5) : Color.clear, lineWidth: 1.5))
                        }.buttonStyle(.plain)
                    }
                }
            }

            // Week info with context
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("WEEK \(editingWeek)").font(.system(size: 14, weight: .black)).foregroundColor(.appTextPrimary)
                        if editingWeek == instance?.currentWeek {
                            Text("CURRENT").font(.system(size: 9, weight: .black)).foregroundColor(.appRed).kerning(1)
                                .padding(.horizontal, 6).padding(.vertical, 2).background(Color.appRed.opacity(0.1)).cornerRadius(4)
                        }
                    }
                    // Show what kind of week this is
                    let weekType = weekTypeLabel(editingWeek)
                    Text(weekType)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(weekType.contains("Recovery") || weekType.contains("Deload") ? .appBlue : .appGreen)
                }
                Spacer()
            }

            // Recovery week notice
            let isRecovery = isRecoveryWeek(editingWeek)
            if isRecovery {
                HStack(spacing: 8) {
                    Image(systemName: "leaf.fill").foregroundColor(.appBlue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recovery Week").font(.system(size: 13, weight: .bold)).foregroundColor(.appBlue)
                        Text("Reduced volume and intensity. Focus on movement quality and recovery.")
                            .font(.system(size: 11)).foregroundColor(.appTextSecondary)
                    }
                }
                .padding(12).background(Color.appBlue.opacity(0.06)).cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBlue.opacity(0.15), lineWidth: 1))
            }

            // Sessions for this week — base program rotation, plus any sessions
            // imported via Configure Program for this specific week. Order: base
            // first (preserves the user's program order), extras appended.
            let rotation = displayRotation(forWeek: editingWeek)
            let templatesBySession = sessionsForWeek(editingWeek)

            if rotation.isEmpty {
                HStack {
                    Image(systemName: "tray").foregroundColor(.appTextDim)
                    Text("No sessions configured").font(.system(size: 13)).foregroundColor(.appTextDim)
                    Spacer()
                }
                .padding(14).background(Color.appSurface).cornerRadius(10)
            } else {
                // Only show sessions that actually have templates this week
                let activeSessions = rotation.filter { !(templatesBySession[$0] ?? []).isEmpty }
                if activeSessions.isEmpty && isRecovery {
                    HStack(spacing: 8) {
                        Image(systemName: "leaf.fill").foregroundColor(.appBlue)
                        Text("No scheduled sessions this week — recovery only")
                            .font(.system(size: 13)).foregroundColor(.appTextSecondary)
                    }
                    .padding(14).background(Color.appSurface).cornerRadius(10)
                } else if activeSessions.isEmpty {
                    ForEach(Array(rotation.enumerated()), id: \.offset) { idx, sessionType in
                        weekSessionCard(sessionType: sessionType, templates: [])
                    }
                } else {
                    ForEach(Array(activeSessions.enumerated()), id: \.offset) { idx, sessionType in
                        let templates = templatesBySession[sessionType] ?? []
                        weekSessionCard(sessionType: sessionType, templates: templates)
                    }
                    // Show skipped sessions
                    let skipped = rotation.filter { (templatesBySession[$0] ?? []).isEmpty }
                    if !skipped.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "moon.zzz.fill").font(.system(size: 11)).foregroundColor(.appTextDim)
                            Text("Resting: \(skipped.map { $0.shortLabel }.joined(separator: ", "))")
                                .font(.system(size: 11)).foregroundColor(.appTextDim)
                        }
                        .padding(10).background(Color.appSurface2).cornerRadius(8)
                    }
                }
            }

            // Copy week button
            Button {
                // TODO: Copy week functionality
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.doc").font(.system(size: 12))
                    Text("Copy This Week's Setup").font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(.appBlue).frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(Color.appBlue.opacity(0.06)).cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBlue.opacity(0.15), lineWidth: 1))
            }.buttonStyle(.plain)
        }
    }

    private func weekSessionCard(sessionType: SessionType, templates: [ProgramSessionTemplate]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(sessionType.shortLabel).font(.system(size: 13, weight: .black)).foregroundColor(.appTextPrimary)
                Spacer()
                Text("\(templates.count) exercises").font(.system(size: 11)).foregroundColor(.appTextDim)
                Button {
                    editSessionItem = SessionEditorItem(sessionType: sessionType, templates: templates)
                } label: {
                    Image(systemName: "pencil").font(.system(size: 12, weight: .bold)).foregroundColor(.appBlue)
                        .frame(width: 36, height: 36).contentShape(Rectangle()).background(Color.appBlue.opacity(0.1)).cornerRadius(8)
                }.buttonStyle(.plain)
            }

            ForEach(templates.sorted { $0.exerciseIndex < $1.exerciseIndex }) { t in
                let name = ExerciseDictionary.all[t.exerciseKey]?.displayName ?? t.exerciseKey
                let def = ExerciseDictionary.all[t.exerciseKey]
                let tierLabel = t.isMainLift ? "T1" : (def?.isCompound == false ? "T3" : "T2")
                let tierColor: Color = t.isMainLift ? .appRed : (def?.isCompound == false ? .appGreen : .appBlue)

                HStack(spacing: 8) {
                    Text(tierLabel).font(.system(size: 9, weight: .black)).foregroundColor(tierColor).frame(width: 20)
                    Text(name).font(.system(size: 12)).foregroundColor(.appTextSecondary).lineLimit(1)
                    Spacer()
                    Text("\(t.targetSets)×\(t.targetRepsLow)-\(t.targetRepsHigh)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.appTextDim)
                }
            }
        }
        .padding(12).background(Color.appSurface).cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))
    }

    // ═══════════════════════════════════════
    // TEMPLATES SECTION
    // ═══════════════════════════════════════

    private var templatesSection: some View {
        VStack(spacing: 14) {
            DayTemplateLibraryView()
        }
    }

    // ═══════════════════════════════════════
    // EXERCISES SECTION
    // ═══════════════════════════════════════

    private var exercisesSection: some View {
        ExerciseLibraryBrowser(exercises: allExercises)
    }

    // ═══════════════════════════════════════
    // HELPERS
    // ═══════════════════════════════════════

    private var totalWeeks: Int {
        if let inst = instance, inst.isGenerated {
            return (inst.blockLength + 1) * 4
        }
        if let tmpl = programTemplates.first(where: { $0.programId == instance?.programId ?? 1 }) {
            return tmpl.durationWeeks
        }
        return instance?.programId == 2 ? 16 : 24
    }

    private func programSplit() -> [(String, String)] {
        guard let p = profile, let inst = instance else { return [] }
        // Seeded programs (ID 1-10) — use hardcoded rotation
        if inst.programId <= 10 && inst.programId > 0 {
            let rotation: [SessionType]
            switch inst.programId {
            case 2: rotation = [.pushA, .pullA, .legsA, .pushB, .pullB, .legsB]
            case 7: rotation = [.legQuadFocus, .chestBack, .armsDelts, .legsPosterior, .chestArms, .legsVolume]
            default: rotation = [.heavyUpper, .heavyLower, .hypertrophyUpper, .hypertrophyLower]
            }
            return rotation.map { ($0.shortLabel, $0.muscleSubtitle) }
        }
        // Generated or custom programs — derive from profile
        let split = ProgramGenerator.resolveSplitStructure(
            daysPerWeek: p.daysPerWeek, goal: p.goal, priorityMuscles: p.priorityMuscles)
        return split.filter { $0.sessionType != .rest }.map { ($0.label, $0.primaryMuscles.joined(separator: ", ")) }
    }

    private func isRecoveryWeek(_ week: Int) -> Bool {
        guard let inst = instance else { return false }
        // ALL programs use blockLength as source of truth (synced everywhere)
        let bl = inst.blockLength > 0 ? inst.blockLength : 5
        return ((week - 1) % (bl + 1)) + 1 > bl
    }

    private func weekTypeLabel(_ week: Int) -> String {
        let goal = profile?.goal ?? .hypertrophy
        let isHyp = goal == .hypertrophy || goal == .recomp

        if isRecoveryWeek(week) { return isHyp ? "Recovery Week" : "Deload Week" }

        guard let inst = instance else { return "Training" }

        // Generated/custom
        if inst.isGenerated || inst.programId > 10 {
            let bl = inst.blockLength > 0 ? inst.blockLength : 5
            let blockNum = (week - 1) / (bl + 1)
            let posInBlock = ((week - 1) % (bl + 1)) + 1
            let phase = isHyp ? (blockNum % 2 == 0 ? "Training Block" : "Growth Phase") : inst.blockType.rawValue.capitalized
            return "\(phase) — Week \(posInBlock) of \(bl)"
        }

        // Seeded: Bahri (3-week cycles)
        if inst.programId == 7 {
            // Remove deload weeks from counting
            var trainingWeek = 0
            for w in 1...week {
                if ![3,6,9,12,15,18,21,24].contains(w) { trainingWeek += 1 }
            }
            let blockIdx = (trainingWeek - 1) / 2  // 2 training weeks per mini-block
            return "Block \(blockIdx / 3 + 1) — Training Week \(trainingWeek)"
        }

        // Seeded: PPL (8-week blocks)
        if inst.programId == 2 {
            let adjustedWeek: Int
            if week <= 3 { adjustedWeek = week }
            else if week <= 8 { adjustedWeek = week - 1 }  // subtract deload at 4
            else if week <= 11 { adjustedWeek = week - 5 }
            else if week <= 16 { adjustedWeek = week - 6 }
            else { adjustedWeek = week }
            let phase = week <= 8 ? (isHyp ? "Training Block" : "Accumulation") : (isHyp ? "Growth Phase" : "Intensification")
            return "\(phase) — Week \(adjustedWeek > 7 ? adjustedWeek - 7 : adjustedWeek)"
        }

        // Seeded: Powerbuilding (8-week blocks)
        if week <= 3 { return "\(isHyp ? "Training Block" : "Accumulation") — Week \(week)" }
        if week <= 8 { return "\(isHyp ? "Training Block" : "Accumulation") — Week \(week - 1)" }
        if week <= 11 { return "\(isHyp ? "Growth Phase" : "Intensification") — Week \(week - 8)" }
        if week <= 16 { return "\(isHyp ? "Growth Phase" : "Intensification") — Week \(week - 9)" }
        if week <= 19 { return "\(isHyp ? "Training Block" : "Peaking") — Week \(week - 16)" }
        return "\(isHyp ? "Training Block" : "Peaking") — Week \(week - 17)"
    }

    /// The program's actual session rotation — source of truth for what sessions exist
    /// Display order for the Weeks tab: base rotation first, then any sessions
    /// imported via Configure Program for this week. Skips sessions that have
    /// been removed via permanent or week-specific rest-day overrides.
    private func displayRotation(forWeek week: Int) -> [SessionType] {
        let base = programRotation()
        guard let inst = instance else { return base }
        let active = activeSessionsForWeek(
            programId: inst.programId, instance: inst, profile: profile,
            week: week, templates: programTemplates)
        var ordered: [SessionType] = []
        for st in base where active.contains(st) && !ordered.contains(st) {
            ordered.append(st)
        }
        for st in active where !ordered.contains(st) {
            ordered.append(st)
        }
        return ordered
    }

    private func programRotation() -> [SessionType] {
        guard let inst = instance else { return [] }
        // Seeded programs
        switch inst.programId {
        case 1: return [.heavyUpper, .heavyLower, .hypertrophyUpper, .hypertrophyLower]
        case 2: return [.pushA, .pullA, .legsA, .pushB, .pullB, .legsB]
        case 7: return [.legQuadFocus, .chestBack, .armsDelts, .legsPosterior, .chestArms, .legsVolume]
        default: break
        }
        // Generated programs
        if inst.isGenerated, let p = profile {
            let split = ProgramGenerator.resolveSplitStructure(
                daysPerWeek: p.daysPerWeek, goal: p.goal, priorityMuscles: p.priorityMuscles)
            return split.filter { $0.sessionType != .rest }.map { $0.sessionType }
        }
        // Custom programs
        if let tmpl = programTemplates.first(where: { $0.programId == inst.programId }) {
            return tmpl.sessionTypes
        }
        return [.heavyUpper, .heavyLower, .hypertrophyUpper, .hypertrophyLower]
    }

    private func sessionsForWeek(_ week: Int) -> [SessionType: [ProgramSessionTemplate]] {
        guard let inst = instance else { return [:] }

        // Try the exact week first
        var templates = allSessionTemplates.filter {
            $0.programId == inst.programId && $0.week == week
        }

        // If this should be a training week (per blockLength) but templates are empty or sparse,
        // fall back to the nearest non-deload week's templates
        let rotation = programRotation()
        let sessionTypesFound = Set(templates.map { $0.sessionType })
        let missingSessionTypes = rotation.filter { !sessionTypesFound.contains($0) }

        if !isRecoveryWeek(week) && !missingSessionTypes.isEmpty {
            let bl = inst.blockLength > 0 ? inst.blockLength : 5
            let totalWk = totalWeeks
            for offset in [1, -1, 2, -2, 3, -3, 4, -4] {
                let fallbackWeek = week + offset
                guard fallbackWeek >= 1 && fallbackWeek <= totalWk else { continue }
                guard !isRecoveryWeek(fallbackWeek) else { continue }
                let fallbackTemplates = allSessionTemplates.filter {
                    $0.programId == inst.programId && $0.week == fallbackWeek
                }
                let fallbackTypes = Set(fallbackTemplates.map { $0.sessionType })
                // Check if this fallback week has the missing session types
                if missingSessionTypes.allSatisfy({ fallbackTypes.contains($0) }) {
                    // Add the missing session templates from the fallback week
                    for missing in missingSessionTypes {
                        let fallbackForSession = fallbackTemplates.filter { $0.sessionType == missing }
                        templates.append(contentsOf: fallbackForSession)
                    }
                    break
                }
            }
        }

        // Cross-program fallback: any session type that's active for this week
        // (base rotation + imported sessions via schedule overrides) but still
        // missing from templates gets borrowed from another program that defines
        // it. Iterating active sessions instead of just base rotation ensures
        // imported sessions show their exercises in the Weeks tab.
        let active = activeSessionsForWeek(
            programId: inst.programId, instance: inst, profile: profile,
            week: week, templates: programTemplates)
        let typesAfterInProgram = Set(templates.map { $0.sessionType })
        for st in active where !typesAfterInProgram.contains(st) {
            let foreign = lookupTemplates(programId: inst.programId, week: week,
                                          sessionType: st, allTemplates: allSessionTemplates)
            templates.append(contentsOf: foreign)
        }

        // Deduplicate: keep latest version per slotId
        var best: [String: ProgramSessionTemplate] = [:]
        for t in templates {
            let key = "\(t.sessionTypeRaw)_\(t.slotId)"
            if let existing = best[key] {
                if t.programVersion >= existing.programVersion { best[key] = t }
            } else {
                best[key] = t
            }
        }
        return Dictionary(grouping: Array(best.values)) { $0.sessionType }
    }

    private func estimateSessionSets(sessionMuscles: String) -> Int {
        let muscles = sessionMuscles.components(separatedBy: ", ")
        guard let p = profile else { return 12 }
        var total = 0
        for m in muscles {
            let target = ProgramGenerator.resolveWeeklySetTarget(
                muscle: m, week: 1, blockType: .accumulation,
                muscleTier: p.muscleTiers[m] ?? .neutral,
                experience: p.experience, calorieContext: p.calorieContext, calibration: nil)
            let freq = max(1, programSplit().filter { $0.1.contains(m) }.count)
            total += target / freq
        }
        return min(total, 24)
    }
}

// ═══════════════════════════════════════════
// EXERCISE LIBRARY BROWSER (for Program tab)
// ═══════════════════════════════════════════

struct ExerciseLibraryBrowser: View {
    let exercises: [Exercise]
    @Environment(\.modelContext) private var modelContext
    @State private var selectedMuscle: String? = nil
    @State private var searchText = ""
    @State private var expandedKey: String? = nil
    @State private var showCreateCustom = false

    private let muscles = ExerciseDictionary.trackingMuscles

    private var filtered: [Exercise] {
        var result = exercises.sorted { $0.displayName < $1.displayName }
        if let m = selectedMuscle {
            result = result.filter { ex in
                let priNorm = ex.musclesPrimary.compactMap { ExerciseDictionary.normalizeMuscle($0) }
                let def = ExerciseDictionary.all[ex.exerciseKey]
                let addlNorm = (def?.additionalFilterMuscles ?? []).compactMap { ExerciseDictionary.normalizeMuscle($0) }
                return priNorm.contains(m) || addlNorm.contains(m)
            }
        }
        if !searchText.isEmpty {
            result = result.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 10) {
            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(.appTextDim)
                TextField("Search exercises...", text: $searchText)
                    .font(.system(size: 14)).foregroundColor(.appTextPrimary)
            }
            .padding(10).background(Color.appSurface2).cornerRadius(8)

            // Muscle chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chipButton("All", selected: selectedMuscle == nil) { selectedMuscle = nil }
                    ForEach(muscles, id: \.self) { m in
                        chipButton(m, selected: selectedMuscle == m) { selectedMuscle = selectedMuscle == m ? nil : m }
                    }
                }
            }

            // Create custom + count
            HStack {
                Text("\(filtered.count) exercises").font(.system(size: 11)).foregroundColor(.appTextDim)
                Spacer()
                Button(action: { showCreateCustom = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 12))
                        Text("Create Custom").font(.system(size: 11, weight: .bold))
                    }.foregroundColor(.appGreen)
                }.buttonStyle(.plain)
            }

            ForEach(filtered) { ex in
                let def = ExerciseDictionary.all[ex.exerciseKey]
                let isExpanded = expandedKey == ex.exerciseKey

                VStack(alignment: .leading, spacing: 0) {
                    Button { withAnimation(.easeInOut(duration: 0.15)) { expandedKey = isExpanded ? nil : ex.exerciseKey } } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(ex.displayName).font(.system(size: 13, weight: .bold)).foregroundColor(.appTextPrimary).lineLimit(1)
                                Text(ex.musclesPrimary.prefix(2).joined(separator: " · "))
                                    .font(.system(size: 11)).foregroundColor(.appTextDim)
                            }
                            Spacer()
                            if ex.isCompound {
                                Text("Compound").font(.system(size: 9, weight: .bold)).foregroundColor(.appBlue)
                                    .padding(.horizontal, 5).padding(.vertical, 2).background(Color.appBlue.opacity(0.1)).cornerRadius(3)
                            }
                            if ex.isCustom {
                                Text("Custom").font(.system(size: 9, weight: .bold)).foregroundColor(.appGold)
                                    .padding(.horizontal, 5).padding(.vertical, 2).background(Color.appGold.opacity(0.1)).cornerRadius(3)
                            }
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9)).foregroundColor(.appTextDim)
                        }
                        .padding(10)
                    }.buttonStyle(.plain)

                    if isExpanded, let d = def {
                        VStack(alignment: .leading, spacing: 6) {
                            Divider().background(Color.appBorder)
                            detailRow("Equipment", value: d.equipment.rawValue.capitalized)
                            detailRow("Stretch", value: d.stretchPosition.rawValue.capitalized)
                            if !d.head.isEmpty { detailRow("Targets", value: d.head.capitalized) }
                            if !d.generatorPattern.isEmpty { detailRow("Pattern", value: d.generatorPattern.replacingOccurrences(of: "_", with: " ").capitalized) }
                            if d.isAnchorableAsTier1 { detailRow("Tier", value: "T1 Anchor — strength tracker") }
                            if !d.secondaryMuscles.isEmpty {
                                detailRow("Secondary", value: d.secondaryMuscles.map { "\($0.muscle) (\(Int($0.weight * 100))%)" }.joined(separator: ", "))
                            }
                        }
                        .padding(.horizontal, 10).padding(.bottom, 10)
                    }
                }
                .background(Color.appSurface).cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorder, lineWidth: 1))
            }
        }
        .sheet(isPresented: $showCreateCustom) {
            AddExerciseView()
        }
    }

    private func chipButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: selected ? .black : .medium))
                .foregroundColor(selected ? .white : .appTextSecondary)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(selected ? Color.appRed : Color.appSurface2).cornerRadius(6)
        }.buttonStyle(.plain)
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 10, weight: .bold)).foregroundColor(.appTextDim).frame(width: 70, alignment: .leading)
            Text(value).font(.system(size: 11)).foregroundColor(.appTextSecondary)
            Spacer()
        }
    }
}

// ═══════════════════════════════════════════
// BLOCK CONFIGURATION CARD
// Extracted as standalone struct to avoid
// type-checker issues with complex closures.
// ═══════════════════════════════════════════

struct BlockConfigCard: View {
    let inst: UserProgramInstance
    let goal: GoalType
    let onTapBlock: (Int) -> Void   // passes block index in timeline
    let modelContext: ModelContext

    private var isHyp: Bool { goal == .hypertrophy || goal == .recomp }
    private var isDeloadBlock: Bool { inst.blockType == .deload }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TRAINING BLOCK").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(2)

            // Current block status with adjustable controls
            HStack(spacing: 0) {
                blockWeekControl.frame(maxWidth: .infinity)
                Divider().frame(height: 40).padding(.horizontal, 4)
                blockLengthControl.frame(maxWidth: .infinity)
                Divider().frame(height: 40).padding(.horizontal, 4)
                blockNumberDisplay.frame(maxWidth: .infinity)
            }
            .padding(.vertical, 12).padding(.horizontal, 8)
            .background(Color.appSurface2).cornerRadius(8)

            // What's ahead timeline
            Text("WHAT'S AHEAD").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim).kerning(1)

            ForEach(0..<7, id: \.self) { i in
                let entry = timelineEntry(at: i)
                Button { onTapBlock(i) } label: {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(entry.color)
                            .frame(width: 4, height: entry.isCurrent ? 32 : 24)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(entry.name).font(.system(size: 12, weight: entry.isCurrent ? .black : .bold))
                                    .foregroundColor(entry.isCurrent ? .appTextPrimary : .appTextSecondary)
                                if entry.isCurrent {
                                    Text("NOW").font(.system(size: 8, weight: .black)).foregroundColor(.appRed).kerning(1)
                                        .padding(.horizontal, 4).padding(.vertical, 1).background(Color.appRed.opacity(0.1)).cornerRadius(3)
                                }
                                Text("\(entry.weeks) wk\(entry.weeks == 1 ? "" : "s")")
                                    .font(.system(size: 9, weight: .medium)).foregroundColor(.appTextDim)
                            }
                            Text(entry.detail).font(.system(size: 10)).foregroundColor(.appTextDim)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 9)).foregroundColor(.appTextDim)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14).background(Color.appSurface).cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
    }

    // ── Controls ──

    private var blockWeekControl: some View {
        VStack(spacing: 6) {
            Text("WEEK").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim)
            Text("\(inst.blockWeek) / \(inst.blockLength)")
                .font(.system(size: 18, weight: .black, design: .rounded)).foregroundColor(.appRed)
                .lineLimit(1).minimumScaleFactor(0.6)
            HStack(spacing: 10) {
                Button {
                    if inst.blockWeek > 1 { inst.blockWeek -= 1; save() }
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold)).foregroundColor(.appTextDim)
                        .frame(width: 36, height: 28).background(Color.appBG).cornerRadius(6)
                }.buttonStyle(.plain)
                Button {
                    if inst.blockWeek < inst.blockLength { inst.blockWeek += 1; save() }
                } label: {
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundColor(.appTextDim)
                        .frame(width: 36, height: 28).background(Color.appBG).cornerRadius(6)
                }.buttonStyle(.plain)
            }
        }
    }

    private var blockLengthControl: some View {
        VStack(spacing: 6) {
            Text("LENGTH").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim)
            Text("\(inst.blockLength) wk\(inst.blockLength == 1 ? "" : "s")")
                .font(.system(size: 18, weight: .black, design: .rounded)).foregroundColor(.appBlue)
                .lineLimit(1).minimumScaleFactor(0.6)
            HStack(spacing: 10) {
                Button {
                    if inst.blockLength > 1 { inst.blockLength -= 1
                        if inst.blockWeek > inst.blockLength { inst.blockWeek = inst.blockLength }
                        save()
                    }
                } label: {
                    Image(systemName: "minus").font(.system(size: 13, weight: .bold)).foregroundColor(.appBlue)
                        .frame(width: 36, height: 28).background(Color.appBlue.opacity(0.06)).cornerRadius(6)
                }.buttonStyle(.plain)
                Button {
                    if inst.blockLength < 12 { inst.blockLength += 1; save() }
                } label: {
                    Image(systemName: "plus").font(.system(size: 13, weight: .bold)).foregroundColor(.appBlue)
                        .frame(width: 36, height: 28).background(Color.appBlue.opacity(0.06)).cornerRadius(6)
                }.buttonStyle(.plain)
            }
        }
    }

    private var blockNumberDisplay: some View {
        VStack(spacing: 4) {
            Text("BLOCK #").font(.system(size: 8, weight: .bold)).foregroundColor(.appTextDim)
            Text("\(inst.totalBlocksCompleted + 1)")
                .font(.system(size: 16, weight: .black, design: .rounded)).foregroundColor(.appGreen)
        }
    }

    // ── Timeline ──

    private func timelineEntry(at index: Int) -> (name: String, detail: String, color: Color, isCurrent: Bool, weeks: Int) {
        if index == 0 {
            return (blockName(inst.blockType), "Wk \(inst.blockWeek)/\(inst.blockLength) · \(volumeDesc(inst.blockType))",
                    blockColor(inst.blockType), true, inst.blockLength)
        }
        var bt = inst.blockType
        for _ in 0..<index {
            bt = BlockType.next(current: bt, goal: goal, blockNumber: inst.totalBlocksCompleted + index - 1)
        }
        let weeks = bt == .deload ? 1 : inst.blockLength
        return (blockName(bt), volumeDesc(bt), blockColor(bt), false, weeks)
    }

    private func blockName(_ bt: BlockType) -> String {
        switch (isHyp, bt) {
        case (true, .accumulation):    return "Training Block"
        case (true, .reaccumulation):  return "Growth Phase"
        case (true, .deload):          return "Recovery"
        case (true, _):                return "Training Block"
        case (false, _):               return bt.rawValue.capitalized
        }
    }

    private func blockColor(_ bt: BlockType) -> Color {
        switch bt {
        case .accumulation:    return .appGreen
        case .reaccumulation:  return .appGold
        case .intensification: return .appOrange
        case .peak:            return .appRed
        case .deload:          return .appBlue
        }
    }

    private func volumeDesc(_ bt: BlockType) -> String {
        switch bt {
        case .accumulation:    return "Standard volume"
        case .reaccumulation:  return "+15% volume"
        case .intensification: return "Lower volume, heavier"
        case .peak:            return "Minimal volume, max weight"
        case .deload:          return "Light recovery"
        }
    }

    private func save() { try? modelContext.save() }
}

// ═══════════════════════════════════════════
// STRENGTH GOAL EDITOR (tap to edit/remove)
// ═══════════════════════════════════════════

struct StrengthGoalEditorSheet: View {
    let goal: StrengthGoal
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var targetWeight: String = ""
    @State private var showRemoveConfirm = false

    private func editorPhaseColor(_ phase: StrengthGoalPhase) -> Color {
        switch phase {
        case .building: return .appGreen
        case .intensifying: return .appOrange
        case .peaking: return .appRed
        case .testing: return .appGold
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 3).fill(Color.appBorder).frame(width: 36, height: 4).padding(.top, 12)

                // Header
                HStack(spacing: 10) {
                    Image(systemName: "target").font(.system(size: 18)).foregroundColor(.appRed)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(goal.displayName).font(.system(size: 18, weight: .black)).foregroundColor(.appTextPrimary)
                        Text("Strength Goal").font(.system(size: 11)).foregroundColor(.appTextDim)
                    }
                    Spacer()
                    Text("\(Int(goal.targetWeight)) lb")
                        .font(.system(size: 22, weight: .black, design: .rounded)).foregroundColor(.appGold)
                }

                // ── Current Phase ──
                VStack(alignment: .leading, spacing: 8) {
                    Text("CURRENT PHASE").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim).kerning(1)
                    HStack(spacing: 10) {
                        Circle().fill(editorPhaseColor(goal.phase)).frame(width: 12, height: 12)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(goal.phase.displayName).font(.system(size: 16, weight: .black)).foregroundColor(.appTextPrimary)
                            Text("Week \(goal.phaseWeek) of \(goal.currentPhaseLength)")
                                .font(.system(size: 12)).foregroundColor(.appTextDim)
                        }
                        Spacer()
                        let rr = goal.phase.repRange
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(goal.phase.targetSets)×\(rr.low)-\(rr.high)")
                                .font(.system(size: 14, weight: .black, design: .monospaced)).foregroundColor(.appTextPrimary)
                            Text("RPE \(String(format: "%.0f", goal.phase.targetRPE))")
                                .font(.system(size: 10, weight: .bold)).foregroundColor(.appTextDim)
                        }
                    }
                }
                .padding(12).background(Color.appSurface).cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))

                // ── Week-by-Week Projection ──
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("WEEK-BY-WEEK PLAN").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim).kerning(1)
                        Spacer()
                        Text("\(Int(goal.startE1RM))lb → \(Int(goal.targetWeight))lb")
                            .font(.system(size: 10, weight: .bold)).foregroundColor(.appGold)
                    }

                    let projection = goal.weekByWeekProjection(useMetric: false)
                    ForEach(Array(projection.enumerated()), id: \.offset) { _, entry in
                        let isCurrent = entry.phase == goal.phase &&
                            (projection.prefix(while: { $0.phase != goal.phase }).count + goal.phaseWeek) == entry.week
                        let isPast = entry.week < (projection.prefix(while: { $0.phase != goal.phase }).count + goal.phaseWeek)

                        HStack(spacing: 8) {
                            Text("W\(entry.week)").font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(isCurrent ? .appRed : .appTextDim)
                                .frame(width: 22)
                            RoundedRectangle(cornerRadius: 2).fill(editorPhaseColor(entry.phase))
                                .frame(width: 3, height: 20)
                            Text("\(Int(entry.weight))lb").font(.system(size: 12, weight: .bold))
                                .foregroundColor(isPast ? .appTextDim : .appTextPrimary)
                                .frame(width: 50, alignment: .leading)
                            Text("\(entry.sets)×\(entry.repsLow)-\(entry.repsHigh)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.appTextSecondary)
                            Spacer()
                            if isCurrent {
                                Text("NOW").font(.system(size: 7, weight: .black)).foregroundColor(.appRed)
                                    .padding(.horizontal, 4).padding(.vertical, 2)
                                    .background(Color.appRed.opacity(0.1)).cornerRadius(3)
                            }
                        }
                        .padding(.vertical, 2)
                        .opacity(isPast ? 0.5 : 1.0)
                    }

                    Text("Weights increase as your e1RM grows. Testing phase targets your \(Int(goal.targetWeight))lb goal directly.")
                        .font(.system(size: 9)).foregroundColor(.appTextDim).padding(.top, 4)
                }
                .padding(12).background(Color.appSurface).cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))

                // ── How This Affects Your Program ──
                VStack(alignment: .leading, spacing: 6) {
                    Text("HOW THIS AFFECTS YOUR PROGRAM").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim).kerning(1)
                    VStack(alignment: .leading, spacing: 8) {
                        effectRow(icon: "dumbbell.fill", text: "\(goal.displayName) switches to \(goal.phase.targetSets)×\(goal.phase.repRange.low)-\(goal.phase.repRange.high) reps at RPE \(String(format: "%.0f", goal.phase.targetRPE))")
                        effectRow(icon: "arrow.triangle.2.circlepath", text: "Rep ranges and intensity change automatically as phases advance")
                        effectRow(icon: "figure.strengthtraining.traditional", text: "All other exercises remain at their normal hypertrophy rep ranges")
                        effectRow(icon: "timer", text: "Rest periods extended to 3+ minutes for strength sets")
                    }
                }
                .padding(12).background(Color.appSurface).cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))

                // ── Edit Target Weight ──
                VStack(alignment: .leading, spacing: 6) {
                    Text("TARGET WEIGHT").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim).kerning(1)
                    HStack(spacing: 8) {
                        TextField("Target", text: $targetWeight)
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(.appGold)
                            .keyboardType(.numberPad)
                            .padding(12).background(Color.appSurface2).cornerRadius(10)
                        Text("lbs").font(.system(size: 14, weight: .bold)).foregroundColor(.appTextDim)
                    }
                }

                // Save
                Button {
                    if let tw = Double(targetWeight), tw > goal.startE1RM {
                        goal.targetWeight = tw
                        try? modelContext.save()
                    }
                    dismiss()
                } label: {
                    Text("SAVE CHANGES")
                        .font(.system(size: 14, weight: .black)).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Color.appRed).cornerRadius(12)
                }.buttonStyle(.plain)

                // Remove
                Button { showRemoveConfirm = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash").font(.system(size: 12))
                        Text("Remove Goal").font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(.appRed)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Color.appRed.opacity(0.06)).cornerRadius(10)
                }.buttonStyle(.plain)
            }
            .padding(20).padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.appBG)
        .numberPadDoneButton()
        .onAppear { targetWeight = "\(Int(goal.targetWeight))" }
        .confirmationDialog("Remove Strength Goal?", isPresented: $showRemoveConfirm) {
            Button("Remove", role: .destructive) {
                goal.isActive = false
                try? modelContext.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will stop the strength-focused programming for \(goal.displayName).")
        }
    }

    private func effectRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).font(.system(size: 10)).foregroundColor(.appBlue)
                .frame(width: 16, alignment: .center).padding(.top, 2)
            Text(text).font(.system(size: 11)).foregroundColor(.appTextSecondary)
        }
    }
}

extension StrengthGoal: Identifiable {
    var id: String { exerciseKey }
}
