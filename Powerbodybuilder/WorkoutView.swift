import SwiftUI
import SwiftData
import Charts

// ═══════════════════════════════════════════
// HELPERS — shared across WorkoutView
// ═══════════════════════════════════════════

/// Single source of truth for deload weeks per program.
/// Matches what's actually seeded in the templates.
func deloadWeeks(for programId: Int, blockLength: Int) -> Set<Int> {
    switch programId {
    case 1: return [4, 12, 20]                              // Powerbuilding
    case 2: return [4, 12, 16]                              // PPL
    case 3: return [4, 8, 13]                               // Strength
    case 4: return [4, 8]                                   // Beginner
    case 5: return [4, 12]                                  // Athletic
    case 6: return [4, 8]                                   // Minimalist
    case 7: return [3, 6, 9, 12, 15, 18, 21, 24]            // Bahri Split
    default:
        // Custom/generated programs use blockLength-based math
        let bl = blockLength > 0 ? blockLength : 5
        let cycleLen = bl + 1
        var result: Set<Int> = []
        for w in 1...24 where ((w - 1) % cycleLen) + 1 > bl {
            result.insert(w)
        }
        return result
    }
}

/// Returns the session rotation for any program ID.
/// For custom programs (ID >= 100), looks up the ProgramTemplate from SwiftData.
func sessionRotation(for programId: Int, templates: [ProgramTemplate] = [],
                      instance: UserProgramInstance? = nil, profile: UserProfile? = nil) -> [SessionType] {
    if programId == 0 { return [.freeform] }
    if programId == 2 {
        return [.pushA, .pullA, .legsA, .pushB, .pullB, .legsB]
    }
    if programId == 3 {
        return [.heavyLower, .heavyUpper, .hypertrophyLower, .hypertrophyUpper]
    }
    if programId == 4 {
        return [.fullBodyA, .fullBodyB, .fullBodyA]
    }
    if programId == 5 {
        return [.upperPower, .lowerPower, .hypertrophyUpper, .hypertrophyLower]
    }
    if programId == 6 {
        return [.fullBodyA, .fullBodyB, .fullBody]
    }
    if programId == 7 {
        return [.legQuadFocus, .chestBack, .armsDelts, .legsPosterior, .chestArms, .legsVolume]
    }
    // Generated programs (ID > 10): derive rotation from profile settings
    if let inst = instance, inst.isGenerated, programId > 10, let p = profile {
        let split = ProgramGenerator.resolveSplitStructure(
            daysPerWeek: p.daysPerWeek, goal: p.goal, priorityMuscles: p.priorityMuscles)
        return split.filter { $0.sessionType != .rest }.map { $0.sessionType }
    }
    if programId >= 100 {
        if let tmpl = templates.first(where: { $0.programId == programId }) {
            return tmpl.sessionTypes
        }
    }
    return [.heavyUpper, .heavyLower, .hypertrophyUpper, .hypertrophyLower]
}

// ═══════════════════════════════════════════
// WORKOUT COMPLETION SUMMARY
// ═══════════════════════════════════════════

struct WorkoutCompletionSummary: Identifiable {
    let id = UUID()
    let totalSets: Int
    let exerciseCount: Int
    let totalVolume: Int
    let prExercises: [String]
    let duration: TimeInterval?
    let sessionType: String
}

struct WorkoutCompletionView: View {
    let summary: WorkoutCompletionSummary
    let onDismiss: () -> Void

    var body: some View {
        ScrollView {
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 3).fill(Color.appBorder).frame(width: 36, height: 4).padding(.top, 14)

            // Celebration
            Image(systemName: summary.prExercises.isEmpty ? "checkmark.circle.fill" : "star.circle.fill")
                .font(.system(size: 44))
                .foregroundColor(summary.prExercises.isEmpty ? .appGreen : .appGold)
                .padding(.top, 8)

            Text(summary.prExercises.isEmpty ? "WORKOUT COMPLETE" : "NEW PR!")
                .font(.system(size: 16, weight: .black)).foregroundColor(.appTextPrimary).kerning(2)

            // Stats
            HStack(spacing: 0) {
                statBox(value: "\(summary.totalSets)", label: "SETS")
                divider()
                statBox(value: "\(summary.exerciseCount)", label: "EXERCISES")
                divider()
                statBox(value: summary.totalVolume > 1000 ? "\(summary.totalVolume/1000)K" : "\(summary.totalVolume)", label: "VOLUME")
                if let dur = summary.duration, dur > 60 {
                    divider()
                    statBox(value: "\(Int(dur / 60))", label: "MIN")
                }
            }
            .padding(12).background(Color.appSurface).cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))

            // PRs
            if !summary.prExercises.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("PERSONAL RECORDS").font(.system(size: 10, weight: .bold)).foregroundColor(.appGold).kerning(1)
                    ForEach(summary.prExercises, id: \.self) { name in
                        HStack(spacing: 8) {
                            Image(systemName: "trophy.fill").font(.system(size: 12)).foregroundColor(.appGold)
                            Text(name).font(.system(size: 14, weight: .bold)).foregroundColor(.appTextPrimary)
                        }
                    }
                }
                .padding(14).background(Color.appGold.opacity(0.06)).cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appGold.opacity(0.2), lineWidth: 1))
            }

            Button(action: onDismiss) {
                Text("Done").font(.headline).fontWeight(.bold).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color.appRed).cornerRadius(12)
            }
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 24)
        }
        .background(Color.appBG)
    }

    private func statBox(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 22, weight: .black, design: .rounded)).foregroundColor(.appTextPrimary)
            Text(label).font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim).kerning(0.5)
        }.frame(maxWidth: .infinity)
    }

    private func divider() -> some View {
        Rectangle().fill(Color.appBorder).frame(width: 1, height: 36)
    }
}

enum WorkoutLayoutMode { case card, scroll }

// ═══════════════════════════════════════════
// WORKOUT VIEW — ROOT
// ═══════════════════════════════════════════

struct WorkoutView: View {

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<UserProgramInstance> { $0.isActive == true })
    private var activeInstances: [UserProgramInstance]
    @Query private var profiles: [UserProfile]
    @Query private var exercises: [Exercise]
    @Query private var allTemplates: [ProgramSessionTemplate]
    @Query private var programTemplates: [ProgramTemplate]
    @Query private var dayTemplatesQuery: [DayTemplate]
    @Query private var allProgramInstances: [UserProgramInstance]

    var instance: UserProgramInstance? { activeInstances.first }

    private var careerLogs: [WorkoutLog] {
        allProgramInstances.flatMap { $0.logs }.filter { !$0.isManualPR }
    }
    var profile: UserProfile? { profiles.first }

    @State private var activeWorkout: ActiveWorkoutSession? = nil
    @State private var completionSummary: WorkoutCompletionSummary? = nil
    @State private var previewSession: ActiveWorkoutSession? = nil
    @State private var showCompleteConfirm = false
    @State private var showReadinessPrompt = false
    @State private var pendingSession: ActiveWorkoutSession? = nil

    var exerciseNames: [String: String] {
        Dictionary(exercises.map { ($0.exerciseKey, $0.displayName) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        ZStack {
            Color.appBG.ignoresSafeArea()
            if let workout = activeWorkout {
                if workout.isComplete {
                    WorkoutCompleteView(session: workout, exerciseNames: exerciseNames, useMetric: profile?.useMetric ?? false) {
                        finalizeWorkout(session: workout)
                    }
                } else {
                    ActiveWorkoutView(
                        session: workout,
                        exerciseNames: exerciseNames,
                        allExercises: exercises,
                        allLogs: instance?.logs ?? [],
                        progressionStates: instance?.progressionStates ?? [],
                        instance: instance,
                        useMetric: profile?.useMetric ?? false,
                        onFinish: { showCompleteConfirm = true }
                    )
                }
            } else if let preview = previewSession {
                PreWorkoutView(
                    session: preview,
                    instance: instance,
                    exerciseNames: exerciseNames,
                    useMetric: profile?.useMetric ?? false,
                    onStart: {
                        pendingSession = preview
                        previewSession = nil
                        showReadinessPrompt = true
                    },
                    onCancel: { previewSession = nil }
                )
            } else {
                ScheduleView(
                    instance: instance,
                    allTemplates: allTemplates,
                    exerciseNames: exerciseNames,
                    useMetric: profile?.useMetric ?? false,
                    onStartSession: { sessionType in
                        buildPreview(sessionType: sessionType)
                    },
                    onStartCustomSession: { sessionType in
                        buildCustomSession(sessionType: sessionType)
                    }
                )
            }
        }
        .confirmationDialog("Finish Workout?", isPresented: $showCompleteConfirm, titleVisibility: .visible) {
            Button("Finish & Save") {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                activeWorkout?.isComplete = true
            }
            Button("Keep Going") { }
            Button("Discard Workout", role: .destructive) { activeWorkout = nil }
        } message: {
            Text("Any sets you logged will be saved.")
        }
        .sheet(item: $completionSummary) { summary in
            WorkoutCompletionView(summary: summary, onDismiss: { completionSummary = nil })
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showReadinessPrompt) {
            ReadinessPromptView(
                onSelect: { score in
                    if let session = pendingSession {
                        session.readiness = score
                        applyReadinessToSession(session, readiness: score)
                        activeWorkout = session
                    }
                    pendingSession = nil
                    showReadinessPrompt = false
                },
                onSkip: {
                    if let session = pendingSession {
                        session.readiness = 3
                        activeWorkout = session
                    }
                    pendingSession = nil
                    showReadinessPrompt = false
                }
            )
            .presentationDetents([.medium])
        }
    }

    private func applyReadinessToSession(_ session: ActiveWorkoutSession, readiness: Int) {
        let (wFactor, repAdj) = ProgressionEngine.readinessModifier(readiness: readiness)
        guard wFactor != 1.0 || repAdj != 0 else { return }

        for i in session.exercises.indices {
            let ex = session.exercises[i]
            var newSets: [LiveSet] = []
            for s in ex.sets {
                let adjWeight = RPETable.roundToPlate(s.recommendedWeight * wFactor,
                                                      useMetric: profile?.useMetric ?? false)
                let adjReps = max(ex.targetRepsLow, min(ex.targetRepsHigh, s.recommendedReps + repAdj))
                newSets.append(LiveSet(setIndex: s.setIndex, recommendedWeight: adjWeight, recommendedReps: adjReps))
            }
            session.exercises[i].sets = newSets
        }
    }

    // ── Build custom (empty) session for a scheduled slot ──────────────────

    private func buildCustomSession(sessionType: SessionType) {
        guard let inst = instance else { return }
        previewSession = ActiveWorkoutSession(
            sessionType: sessionType,
            week: inst.currentWeek,
            exercises: [],
            isCustom: true
        )
    }

    // ── Build preview session ──────────────────────────────────────────────

    private func buildPreview(sessionType: SessionType) {
        guard let inst = instance else { return }
        let useMetric = profile?.useMetric ?? false
        let week = inst.currentWeek
        let pid = inst.programId

        // Freestyle: start an empty session — user adds exercises during workout
        if pid == 0 {
            previewSession = ActiveWorkoutSession(
                sessionType: .freeform,
                week: week,
                exercises: []
            )
            return
        }

        // Check if today's schedule has a day template assigned
        let cal = Calendar.current
        let todayWeekday = cal.component(.weekday, from: Date()) // 1=Sun, 7=Sat
        let todayDow = todayWeekday == 1 ? 0 : todayWeekday - 1  // 0=Sun, 1=Mon...6=Sat
        let matchingSchedule = inst.schedules.first(where: { sched in
            sched.dayOfWeek == todayDow && !sched.dayTemplateId.isEmpty &&
            (sched.isPermanent || sched.week == week)
        })

        if let templateId = matchingSchedule?.dayTemplateId, !templateId.isEmpty,
           let dayTemplate = dayTemplatesQuery.first(where: { $0.templateId.uuidString == templateId }) {
            let liveExercises: [LiveExercise] = dayTemplate.exercises.enumerated().map { idx, ex in
                let name = exerciseNames[ex.exerciseKey] ?? ex.displayName
                let recentLogs = careerLogs.filter { $0.exerciseKey == ex.exerciseKey }.sorted { $0.date > $1.date }
                let progState = inst.progressionStates.first(where: { $0.exerciseKey == ex.exerciseKey })
                let tier: ExerciseTier = {
                    let def = ExerciseDictionary.all[ex.exerciseKey]
                    if def?.isAnchorableAsTier1 == true { return .tier1 }
                    if def?.isCompound == true { return .tier2 }
                    return .tier3
                }()
                let rec = ProgressionEngine.recommend(
                    recentLogs: recentLogs,
                    targetRepsLow: ex.targetRepsLow,
                    targetRepsHigh: ex.targetRepsHigh,
                    targetRPE: ex.targetRPE,
                    exerciseTier: tier,
                    useMetric: useMetric,
                    progressionState: progState,
                    lastSessionIFI: progState?.lastIFI,
                    blockPhase: inst.blockPhase,
                    progressionRate: profile?.progressionRate ?? .normal
                )
                let algoMode2 = profile?.algorithmMode ?? .full
                let top = rec.recommendedWeight > 0 ? rec.recommendedWeight : 0
                let backoff = rec.backoffWeight > 0 ? rec.backoffWeight : top
                let isTier1 = tier == .tier1
                let sets = (0..<ex.targetSets).map { i in
                    let w = algoMode2 == .off ? 0.0 : ((isTier1 && i > 0) ? backoff : top)
                    let r = algoMode2 == .off ? ex.targetRepsHigh : rec.repsForSet(i)
                    return LiveSet(setIndex: i, recommendedWeight: w, recommendedReps: r)
                }
                let letter = idx < 26 ? String(UnicodeScalar(65 + idx)!) : "Z"
                return LiveExercise(
                    exerciseKey: ex.exerciseKey, displayName: name,
                    slotId: "\(letter)1", role: ex.role, exerciseTier: tier,
                    targetSets: ex.targetSets, targetRepsLow: ex.targetRepsLow,
                    targetRepsHigh: ex.targetRepsHigh, targetRPE: ex.targetRPE,
                    restSeconds: ex.restSeconds, notes: "", sets: sets
                )
            }
            previewSession = ActiveWorkoutSession(sessionType: sessionType, week: week, exercises: liveExercises)
            return
        }

        // If user opted out of deloads and this is a deload week, substitute
        // templates from the most recent non-deload week so they keep training.
        let skipDeloads = profile?.skipDeloads ?? false
        let dlWeeks = deloadWeeks(for: pid, blockLength: inst.blockLength)
        var effectiveWeek = week
        if skipDeloads && dlWeeks.contains(week) {
            for w in stride(from: week - 1, through: 1, by: -1) {
                if !dlWeeks.contains(w) {
                    effectiveWeek = w
                    break
                }
            }
        }
        var templates = allTemplates
            .filter { $0.programId == pid && $0.week == effectiveWeek && $0.sessionType == sessionType }
            .sorted { $0.exerciseIndex < $1.exerciseIndex }

        // Imported session fallback: if the current program has no templates for this
        // session type (e.g., user imported legsPosterior from Bahri into Powerbuilding),
        // borrow templates from whichever program defines this session type.
        if templates.isEmpty {
            let foreignAtCurrentWeek = allTemplates
                .filter { $0.sessionType == sessionType && $0.week == effectiveWeek }
            if !foreignAtCurrentWeek.isEmpty,
               let foreignPid = foreignAtCurrentWeek.first?.programId {
                templates = foreignAtCurrentWeek
                    .filter { $0.programId == foreignPid }
                    .sorted { $0.exerciseIndex < $1.exerciseIndex }
            } else {
                // Fall back to week 1 of any program with this session type
                let foreignWeek1 = allTemplates
                    .filter { $0.sessionType == sessionType && $0.week == 1 }
                if let foreignPid = foreignWeek1.first?.programId {
                    templates = foreignWeek1
                        .filter { $0.programId == foreignPid }
                        .sorted { $0.exerciseIndex < $1.exerciseIndex }
                }
            }
        }

        var priorExercisesForPML: [(key: String, sets: Int)] = []
        var liveExercises: [LiveExercise] = []
        var strengthGoalAppliedKeys: Set<String> = []  // only apply goal to first occurrence
        var compoundWarmupCount = 0
        for t in templates {
            // Resolve overrides — use swapped exercise if one applies to this week
            let effectiveKey = resolveExerciseKey(
                slotId: t.slotId, originalKey: t.exerciseKey,
                overrides: inst.overrides, week: week
            )
            let name = exerciseNames[effectiveKey] ?? effectiveKey
                .replacingOccurrences(of: "_", with: " ").capitalized
            let recentLogs = careerLogs
                .filter { $0.exerciseKey == effectiveKey }
                .sorted { $0.date > $1.date }
            let progState = inst.progressionStates.first(where: { $0.exerciseKey == effectiveKey })
            let tier: ExerciseTier = {
                let def = ExerciseDictionary.all[effectiveKey]
                if def?.isAnchorableAsTier1 == true { return .tier1 }
                if def?.isCompound == true { return .tier2 }
                return .tier3
            }()

            // Compute PML from prior exercises this session
            let pml = ProgressionEngine.computePML(
                targetExerciseKey: effectiveKey,
                priorExercises: priorExercisesForPML,
                personalSensitivity: progState?.personalFatigueSensitivity ?? 0.12
            )

            // ── Strength Goal override (only first occurrence per exercise) ──
            let activeGoal: StrengthGoal? = {
                guard !strengthGoalAppliedKeys.contains(effectiveKey) else { return nil }
                return inst.strengthGoals.first(where: { $0.exerciseKey == effectiveKey && $0.isActive })
            }()
            let effectiveRepsLow: Int
            let effectiveRepsHigh: Int
            let effectiveRPE: Double
            let effectiveSets: Int
            var goalNote = ""

            if let goal = activeGoal, tier == .tier1 {
                strengthGoalAppliedKeys.insert(effectiveKey)
                let phase = goal.phase
                effectiveRepsLow = phase.repRange.low
                effectiveRepsHigh = phase.repRange.high
                effectiveRPE = phase.targetRPE
                effectiveSets = phase.targetSets
                goalNote = "Strength Focus — \(phase.displayName) (Wk \(goal.phaseWeek)/\(goal.currentPhaseLength))"
            } else {
                effectiveRepsLow = t.targetRepsLow
                effectiveRepsHigh = t.targetRepsHigh
                effectiveRPE = t.targetRPE
                effectiveSets = t.targetSets
            }

            let rec = ProgressionEngine.recommend(
                recentLogs: recentLogs,
                targetRepsLow: effectiveRepsLow,
                targetRepsHigh: effectiveRepsHigh,
                targetRPE: effectiveRPE,
                exerciseTier: tier,
                useMetric: useMetric,
                progressionState: progState,
                lastSessionIFI: progState?.lastIFI,
                blockPhase: inst.blockPhase,
                progressionRate: profile?.progressionRate ?? .normal,
                pmlFactor: pml.factor
            )

            // For strength goals, override weight with phase-prescribed loading
            var top = rec.recommendedWeight > 0 ? rec.recommendedWeight : 0
            if let goal = activeGoal, tier == .tier1 {
                let prescribed = goal.prescribeWeight(
                    currentE1RM: progState?.bestE1RM ?? top,
                    useMetric: useMetric)
                if prescribed > 0 { top = prescribed }
            }

            let algoMode = profile?.algorithmMode ?? .full
            let backoff = rec.backoffWeight > 0 ? rec.backoffWeight : top
            let isTier1 = tier == .tier1
            let sets = (0..<effectiveSets).map { i -> LiveSet in
                // Prefer per-set prescription when available (weight-aware)
                let prescription = rec.prescriptionForSet(i)

                let weight: Double
                let reps: Int
                let repsHigh: Int?
                let role: ProgressionEngine.SetRole?

                switch algoMode {
                case .full:
                    if let p = prescription, p.weight > 0 {
                        weight = p.weight
                        reps = p.repsTarget
                        repsHigh = p.hasRange ? p.repsRangeHigh : nil
                        role = p.role
                    } else {
                        // Fallback: straight sets at top/backoff
                        weight = (isTier1 && i > 0) ? backoff : top
                        reps = rec.repsForSet(i)
                        repsHigh = nil
                        role = isTier1 ? (i > 0 ? .backoff : .primary) : .primary
                    }
                case .suggestions:
                    weight = 0  // not pre-filled in suggestions mode
                    if let p = prescription {
                        reps = p.repsTarget
                        repsHigh = p.hasRange ? p.repsRangeHigh : nil
                        role = p.role
                    } else {
                        reps = rec.repsForSet(i)
                        repsHigh = nil
                        role = nil
                    }
                case .off:
                    weight = 0
                    reps = effectiveRepsHigh
                    repsHigh = nil
                    role = nil
                }
                return LiveSet(
                    setIndex: i,
                    recommendedWeight: weight,
                    recommendedReps: reps,
                    recommendedRepsHigh: repsHigh,
                    role: role
                )
            }
            let warmupWeight = top > 0 ? top : (progState?.lastSessionWeight ?? 0)
            let showWarmups = profile?.showWarmups ?? true
            let warmups: [WarmupSet]
            if showWarmups && tier != .tier3 && compoundWarmupCount < 2 {
                warmups = ProgressionEngine.generateWarmupSets(
                    workingWeight: warmupWeight, exerciseTier: tier, useMetric: useMetric
                ).map { WarmupSet(weight: $0.weight, reps: $0.reps, label: $0.label) }
                if !warmups.isEmpty { compoundWarmupCount += 1 }
            } else {
                warmups = []
            }

            let pmlNote = pml.factor < 0.97 && !pml.fatigueSource.isEmpty
                ? "Adjusted for prior \(pml.fatigueSource) work" : ""

            // Build combined notes: goal note + PML note + original notes
            var allNotes: [String] = []
            if !goalNote.isEmpty { allNotes.append(goalNote) }
            if !pmlNote.isEmpty { allNotes.append(pmlNote) }
            if !t.notes.isEmpty { allNotes.append(t.notes) }

            liveExercises.append(LiveExercise(
                exerciseKey: effectiveKey,
                displayName: name,
                slotId: t.slotId,
                role: t.role,
                exerciseTier: tier,
                targetSets: effectiveSets,
                targetRepsLow: effectiveRepsLow,
                targetRepsHigh: effectiveRepsHigh,
                targetRPE: effectiveRPE,
                restSeconds: activeGoal?.restSeconds ?? t.restSeconds,
                notes: allNotes.joined(separator: " · "),
                sets: sets,
                warmupSets: warmups
            ))

            // Track for subsequent PML calculations
            priorExercisesForPML.append((key: effectiveKey, sets: t.targetSets))
        }

        // ── Inject volume additions (SessionOverride.isAddition=true) ─────────
        let additions = inst.overrides.filter { ov in
            ov.isAddition && ov.sessionType == sessionType && ov.appliesTo(week: week)
        }
        for (i, add) in additions.enumerated() {
            let exKey = add.replacementExerciseKey
            let name = exerciseNames[exKey] ?? exKey
                .replacingOccurrences(of: "_", with: " ").capitalized
            let progState = inst.progressionStates.first(where: { $0.exerciseKey == exKey })
            let recentLogs = careerLogs.filter { $0.exerciseKey == exKey }.sorted { $0.date > $1.date }
            let tier: ExerciseTier = {
                let def = ExerciseDictionary.all[exKey]
                if def?.isAnchorableAsTier1 == true { return .tier1 }
                if def?.isCompound == true { return .tier2 }
                return .tier3
            }()
            let pml = ProgressionEngine.computePML(
                targetExerciseKey: exKey,
                priorExercises: priorExercisesForPML,
                personalSensitivity: progState?.personalFatigueSensitivity ?? 0.12
            )
            let rec = ProgressionEngine.recommend(
                recentLogs: recentLogs,
                targetRepsLow: add.addedRepsLow,
                targetRepsHigh: add.addedRepsHigh,
                targetRPE: add.addedRPE,
                exerciseTier: tier,
                useMetric: useMetric,
                progressionState: progState,
                lastSessionIFI: progState?.lastIFI,
                blockPhase: inst.blockPhase,
                progressionRate: profile?.progressionRate ?? .normal,
                pmlFactor: pml.factor
            )
            let algoMode = profile?.algorithmMode ?? .full
            let top = rec.recommendedWeight > 0 ? rec.recommendedWeight : 0
            let setLetter = "Z\(i + 1)"
            let sets = (0..<add.addedSets).map { idx -> LiveSet in
                let weight = algoMode == .off ? 0 : top
                let reps = algoMode == .off ? add.addedRepsHigh : rec.repsForSet(idx)
                return LiveSet(setIndex: idx, recommendedWeight: weight, recommendedReps: reps)
            }
            liveExercises.append(LiveExercise(
                exerciseKey: exKey,
                displayName: name,
                slotId: setLetter,
                role: .accessory,
                exerciseTier: tier,
                targetSets: add.addedSets,
                targetRepsLow: add.addedRepsLow,
                targetRepsHigh: add.addedRepsHigh,
                targetRPE: add.addedRPE,
                restSeconds: add.addedRest,
                notes: "Added for volume",
                sets: sets
            ))
            priorExercisesForPML.append((key: exKey, sets: add.addedSets))
        }

        previewSession = ActiveWorkoutSession(
            sessionType: sessionType,
            week: week,
            exercises: liveExercises
        )
    }

    // ── Finalize & persist ─────────────────────────────────────────────────

    private func finalizeWorkout(session: ActiveWorkoutSession) {
        guard let inst = instance else { activeWorkout = nil; return }
        let sessionDate = session.startedAt  // Permanent workout date — never changes on later edits
        // Pre-compute top set index per exercise from actual logged weights
        var topSetIndexByExercise: [String: Int] = [:]
        for ex in session.exercises {
            var maxW: Double = 0; var maxIdx = 0
            for s in ex.sets where s.isLogged {
                if let w = s.loggedWeight, w > maxW { maxW = w; maxIdx = s.setIndex }
            }
            if maxW > 0 { topSetIndexByExercise[ex.exerciseKey] = maxIdx }
        }
        let completedLogs = session.exercises.flatMap { ex -> [WorkoutLog] in
            let progState = inst.progressionStates.first(where: { $0.exerciseKey == ex.exerciseKey })
            let topIdx = topSetIndexByExercise[ex.exerciseKey] ?? 0
            return ex.sets.compactMap { s -> WorkoutLog? in
                guard s.isLogged, let w = s.loggedWeight, let r = s.loggedReps else { return nil }
                let log = WorkoutLog(
                    date: s.completedAt ?? Date(),
                    workoutDate: sessionDate,
                    week: session.week,
                    sessionType: session.sessionType,
                    exerciseKey: ex.exerciseKey,
                    displayName: ex.displayName,
                    slotId: ex.slotId,
                    setIndex: s.setIndex,
                    weight: w,
                    reps: r,
                    rpe: s.loggedRPE ?? 0,
                    isMainLift: ex.isMainLift,
                    isTopSet: s.setIndex == topIdx,
                    hitTargetReps: r >= ex.targetRepsHigh,
                    suggestedWeight: s.recommendedWeight,
                    acceptedSuggestion: abs(w - s.recommendedWeight) < 2.6
                )
                log.targetRepsLow = ex.targetRepsLow
                log.previousWeight = progState?.lastCompletedWeight ?? 0
                log.readiness = session.readiness
                return log
            }
        }
        if !completedLogs.isEmpty {
            // Attach session notes to the first log of the session
            let trimmedNotes = session.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedNotes.isEmpty {
                completedLogs.first?.sessionNotes = trimmedNotes
            }
            completedLogs.forEach { inst.logs.append($0) }
            if inst.programId != 0 && !session.isCustom {
                inst.nextRotationIndex += 1
                let rotationSize = sessionRotation(for: inst.programId, templates: programTemplates, instance: inst, profile: profiles.first).count
                let newWeek = inst.nextRotationIndex / rotationSize
                let maxWeeks = programTemplates.first(where: { $0.programId == inst.programId })?.durationWeeks ?? (inst.programId == 2 ? 16 : 24)
                if newWeek > inst.microcycleIndex && newWeek < maxWeeks {
                    inst.microcycleIndex = newWeek
                }
            }
            let byExercise = Dictionary(grouping: completedLogs) { $0.exerciseKey }
            for (key, logs) in byExercise {
                // TODO: Scope ProgressionState by (exerciseKey + slotId) composite before building Progress tab.
                // Current single-key lookup can conflate progression across slots if same exercise appears twice.
                let state: ProgressionState
                if let existing = inst.progressionStates.first(where: { $0.exerciseKey == key }) {
                    state = existing
                } else {
                    state = ProgressionState(exerciseKey: key)
                    inst.progressionStates.append(state)
                }
                let tmpl = session.exercises.first(where: { $0.exerciseKey == key })
                ProgressionEngine.updateProgressionState(
                    state: state, completedSets: logs,
                    suggestedWeight: logs.first?.suggestedWeight ?? 0,
                    targetRepsLow: tmpl?.targetRepsLow ?? 5,
                    targetRepsHigh: tmpl?.targetRepsHigh ?? 10,
                    exerciseTier: tmpl?.exerciseTier ?? .tier2
                )

                // PML sensitivity learning — compare predicted vs actual e1RM
                let exIdx = session.exercises.firstIndex(where: { $0.exerciseKey == key }) ?? 0
                if exIdx > 0 {
                    let priorKeys = session.exercises.prefix(exIdx).map { (key: $0.exerciseKey, sets: $0.targetSets) }
                    let pml = ProgressionEngine.computePML(
                        targetExerciseKey: key, priorExercises: priorKeys,
                        personalSensitivity: state.personalFatigueSensitivity)
                    let topE1rm = logs.map { $0.e1rm }.max() ?? 0
                    ProgressionEngine.learnFatigueSensitivity(
                        state: state, pmlFactor: pml.factor,
                        predictedWeight: logs.first?.suggestedWeight ?? 0,
                        actualTopE1RM: topE1rm)
                }
            }

            // ── Advance Strength Goal phases ──────────────────────────────
            for goal in inst.strengthGoals where goal.isActive {
                let trained = session.exercises.contains(where: { $0.exerciseKey == goal.exerciseKey })
                guard trained else { continue }

                // Check if target was hit during testing phase
                if goal.phase == .testing {
                    let goalLogs = completedLogs.filter { $0.exerciseKey == goal.exerciseKey }
                    if let best = goalLogs.max(by: { $0.weight < $1.weight }), best.weight >= goal.targetWeight {
                        goal.isActive = false
                        goal.completedAt = Date()
                        continue
                    }
                }

                goal.advanceWeek()
            }

            // ── Update LandmarkCalibration ─────────────────────────────────
            let trainedMuscles = Set(
                session.exercises
                    .compactMap { ExerciseDictionary.all[$0.exerciseKey] }
                    .flatMap { $0.primaryMuscles }
                    .compactMap { ExerciseDictionary.normalizeMuscle($0) }
            )

            for muscle in trainedMuscles {
                if let existing = inst.landmarkCalibrations
                                       .first(where: { $0.muscleGroup == muscle }) {
                    let days = Calendar.current.dateComponents(
                        [.day], from: existing.lastRecalibrationDate ?? .distantPast,
                        to: Date()).day ?? 0
                    if days >= 14 {
                        let muscleLogs = inst.logs.filter { log in
                            guard let def = ExerciseDictionary.all[log.exerciseKey] else { return false }
                            return def.primaryMuscles.compactMap { ExerciseDictionary.normalizeMuscle($0) }.contains(muscle)
                        }
                        let sessions = ProgressionEngine.groupBySession(muscleLogs)
                        let e1rmChange: Double
                        if sessions.count >= 2 {
                            let latest = sessions[0].map { $0.e1rm }.max() ?? 0
                            let prior  = sessions[1].map { $0.e1rm }.max() ?? 0
                            e1rmChange = prior > 0 ? (latest - prior) / prior : 0
                        } else { e1rmChange = 0 }

                        let muscleStates = inst.progressionStates.filter {
                            guard let def = ExerciseDictionary.all[$0.exerciseKey] else { return false }
                            return def.primaryMuscles.compactMap { ExerciseDictionary.normalizeMuscle($0) }.contains(muscle)
                        }
                        let avgIFI = muscleStates.isEmpty ? 0.0 :
                            muscleStates.map { $0.lastIFI }.reduce(0, +) / Double(muscleStates.count)

                        let currentSets = inst.logs
                            .filter { isThisWeekLog($0) }
                            .filter { log in
                                guard let def = ExerciseDictionary.all[log.exerciseKey] else { return false }
                                return def.primaryMuscles.compactMap { ExerciseDictionary.normalizeMuscle($0) }.contains(muscle)
                            }
                            .count

                        existing.recalibrate(avgE1rmChange: e1rmChange,
                                               avgIFI: avgIFI,
                                               currentSets: currentSets)
                    }
                } else {
                    let newCal = LandmarkCalibration(muscleGroup: muscle)
                    modelContext.insert(newCal)
                    inst.landmarkCalibrations.append(newCal)
                }
            }
        }

        // ── Track hard sets per muscle this session ────────────────────
        for ex in session.exercises {
            let sessionMaxWeight = ex.sets
                .compactMap { $0.loggedWeight }.max() ?? 0
            let hardSets = ex.sets.filter { set in
                guard let w = set.loggedWeight, let r = set.loggedReps else {
                    return false
                }
                let isWorkingWeight = w >= sessionMaxWeight * 0.80
                let rpe = set.loggedRPE ?? 0
                let isHardEffort = rpe == 0 || rpe >= 6.0
                return isWorkingWeight && isHardEffort && r > 0
            }
            guard !hardSets.isEmpty,
                  let def = ExerciseDictionary.all[ex.exerciseKey] else { continue }
            for muscle in def.primaryMuscles.compactMap({
                ExerciseDictionary.normalizeMuscle($0) }) {
                inst.currentWeekSets[muscle, default: 0] += hardSets.count
            }
        }

        // ── Advance block week ─────────────────────────────────────────
        if let blockProfile = profiles.first {
            inst.blockWeek += 1

            if inst.blockWeek > inst.blockLength {
                inst.previousBlockExerciseKeys = Set(inst.logs.map { $0.exerciseKey })
                inst.blockType = BlockType.next(
                    current: inst.blockType,
                    goal: blockProfile.goal,
                    blockNumber: inst.totalBlocksCompleted
                )
                // Skip deload block entirely if user opted out
                if blockProfile.skipDeloads && inst.blockType == .deload {
                    inst.blockType = BlockType.next(
                        current: .deload,
                        goal: blockProfile.goal,
                        blockNumber: inst.totalBlocksCompleted + 1
                    )
                }
                if inst.blockType == .deload {
                    inst.blockLength = 1
                } else if !inst.isGenerated {
                    switch blockProfile.experience {
                    case .beginner, .intermediate: inst.blockLength = blockProfile.goal == .recomp ? 3 : 5
                    case .advanced, .elite: inst.blockLength = blockProfile.goal == .recomp ? 3 : 4
                    }
                }
                inst.blockWeek = 1
                inst.totalBlocksCompleted += 1
                inst.currentWeekSets = [:]
                inst.nextWeekSetAdjustments = [:]
                inst.mrvSignalScores = [:]

                // Generate next block's templates
                if blockProfile.useGeneratedPrograms, inst.isGenerated {
                    let peakSets: [String: Int] = VolumeLandmark.defaults.keys
                        .reduce(into: [:]) { result, muscle in
                            let finalWeek = inst.blockLength
                            result[muscle] = inst.logs
                                .filter { log in
                                    log.week == finalWeek &&
                                    exerciseTargetsMuscle(log.exerciseKey, muscle: muscle)
                                }
                                .count
                        }

                    do {
                        let newTemplates = try ProgramGenerator.generateBlock(
                            profile: blockProfile,
                            instance: inst,
                            blockNumber: inst.totalBlocksCompleted,
                            blockType: inst.blockType,
                            previousBlockPeakSets: peakSets,
                            allLogs: inst.logs,
                            progressionStates: inst.progressionStates,
                            modelContext: modelContext)
                        newTemplates.forEach { modelContext.insert($0) }
                    } catch {
                        print("Block transition generator failed: \(error)")
                        inst.isGenerated = false
                    }
                }
            }
        }

        // ── MRV signal scoring ─────────────────────────────────────────
        // Secondary muscles deliberately excluded — only direct training sessions
        // (primaryMuscles) drive MRV signal decisions. Indirect volume shows in display only.
        let scoredMuscles = Set(
            session.exercises
                .compactMap { ExerciseDictionary.all[$0.exerciseKey] }
                .flatMap { $0.primaryMuscles }
                .compactMap { ExerciseDictionary.normalizeMuscle($0) }
        )
        for muscle in scoredMuscles {
            let currentScore = inst.mrvSignalScores[muscle] ?? 0
            let relatedStates = inst.progressionStates.filter {
                exerciseTargetsMuscle($0.exerciseKey, muscle: muscle)
            }
            inst.mrvSignalScores[muscle] = MRVSignalEngine.computeScore(
                muscle: muscle,
                progressionStates: relatedStates,
                recentLogs: inst.logs,
                existingScore: currentScore,
                lastSignalDate: relatedStates.first?.lastSignalDate,
                isDeloadWeek: inst.blockType == .deload
            )
            for state in relatedStates {
                state.lastSignalDate = Date()
            }
        }

        // ── Volume decision per muscle ─────────────────────────────────
        // Secondary muscles deliberately excluded — only direct training sessions
        // (primaryMuscles) drive VDE decisions. Indirect volume shows in display only.
        let vdeMuscles = Set(
            session.exercises
                .compactMap { ExerciseDictionary.all[$0.exerciseKey] }
                .flatMap { $0.primaryMuscles }
                .compactMap { ExerciseDictionary.normalizeMuscle($0) }
        )
        for muscle in vdeMuscles {
            guard let prof = profiles.first else { break }
            let tier = prof.muscleTiers[muscle] ?? .neutral
            let exp = prof.experience

            let relatedStates = inst.progressionStates.filter {
                exerciseTargetsMuscle($0.exerciseKey, muscle: muscle)
            }
            let primaryState = relatedStates.first

            let overloadState = OverloadState(
                progressionRule: primaryState?.lastProgressionRule ?? .hold,
                ifiZone: IFIZone(ifi: primaryState?.lastIFI ?? 0),
                stallDiagnosis: primaryState?.lastStallDiagnosis ?? .noStall,
                e1rmTrend: ProgressionEngine.computeE1rmTrend(primaryState),
                weeksAtCurrentLoad: primaryState?.weeksAtSameLoad ?? 0,
                weeksAtCurrentVolume: 0,
                blockPhase: inst.blockPhase,
                respondsBetterTo: prof.respondsBetterTo
            )

            let currentSets = inst.currentWeekSets[muscle] ??
                VolumeLandmark.effectiveMEV(muscle: muscle, experience: exp, tier: tier)
            let mrv = VolumeLandmark.effectiveMRV(muscle: muscle, experience: exp,
                                                   tier: tier,
                                                   calorieContext: prof.calorieContext)
            let mev = VolumeLandmark.effectiveMEV(muscle: muscle, experience: exp,
                                                   tier: tier)

            let decision = VolumeDecisionEngine.decide(
                state: overloadState,
                currentSets: currentSets,
                mev: mev,
                mrv: mrv
            )

            switch decision {
            case .addSets(let n):
                inst.nextWeekSetAdjustments[muscle] = n
            case .reduceSets(let n):
                inst.nextWeekSetAdjustments[muscle] = -n
            case .holdVolume:
                inst.nextWeekSetAdjustments[muscle] = 0
            case .deload:
                inst.mrvSignalScores[muscle] = max(inst.mrvSignalScores[muscle] ?? 0, 8)
            }
        }

        // ── Progression rate assessment ────────────────────────────────
        if let prof = profiles.first {
            let weeksOfHistory = inst.totalBlocksCompleted * (inst.blockLength + 1)
                + inst.blockWeek
            if let rate = ProgressionEngine.assessProgressionRate(
                progressionStates: inst.progressionStates,
                experience: prof.experience,
                weeksOfHistory: weeksOfHistory
            ) {
                prof.progressionRate = rate
            }
        }

        // ── N=1 adaptation assessment ────────────────────────────────
        if let prof = profiles.first, inst.totalBlocksCompleted >= 2 {
            let volumeHistory = buildVolumeHistory(inst: inst)
            if let response = ProgressionEngine.assessRespondsBetterTo(
                volumeHistory: volumeHistory,
                totalBlocksCompleted: inst.totalBlocksCompleted) {
                prof.respondsBetterTo = response
            }
        }

        // Build completion summary before clearing
        let totalSets = completedLogs.count
        let exerciseNames = Array(Set(completedLogs.map { $0.displayName }))
        let totalVolume = Int(completedLogs.reduce(0.0) { $0 + $1.weight * Double($1.reps) })
        let prs = completedLogs.filter { log in
            guard let state = inst.progressionStates.first(where: { $0.exerciseKey == log.exerciseKey }) else { return false }
            return log.e1rm >= state.bestE1RM && log.e1rm > 0
        }.map { $0.displayName }
        let uniquePRs = Array(Set(prs))
        let duration: TimeInterval? = {
            let dates = completedLogs.map { $0.date }
            guard dates.count >= 2, let earliest = dates.min(), let latest = dates.max() else { return nil }
            return latest.timeIntervalSince(earliest)
        }()

        completionSummary = WorkoutCompletionSummary(
            totalSets: totalSets, exerciseCount: exerciseNames.count,
            totalVolume: totalVolume, prExercises: uniquePRs,
            duration: duration, sessionType: session.sessionType.rawValue)

        try? modelContext.save()
        activeWorkout = nil
    }

    private func buildVolumeHistory(
        inst: UserProgramInstance
    ) -> [(week: Int, sets: Int, e1rmChange: Double)] {
        var weeklyData: [Int: (sets: Int, e1rms: [Double])] = [:]
        for log in inst.logs {
            let week = log.week
            var data = weeklyData[week] ?? (sets: 0, e1rms: [])
            if log.rpe == 0 || log.rpe >= 6.0 { data.sets += 1 }
            if ProgressionEngine.isValidForE1RM(log.reps) {
                let e1rm = log.weight * (1.0 + Double(log.reps) / 30.0)
                data.e1rms.append(e1rm)
            }
            weeklyData[week] = data
        }
        let sorted = weeklyData.keys.sorted()
        var history: [(week: Int, sets: Int, e1rmChange: Double)] = []
        for (i, week) in sorted.enumerated() {
            guard let data = weeklyData[week] else { continue }
            let avgE1rm = data.e1rms.isEmpty ? 0 :
                data.e1rms.reduce(0, +) / Double(data.e1rms.count)
            let change: Double
            if i > 0, let prev = weeklyData[sorted[i-1]] {
                let prevAvg = prev.e1rms.isEmpty ? 0 :
                    prev.e1rms.reduce(0, +) / Double(prev.e1rms.count)
                change = prevAvg > 0 ? (avgE1rm - prevAvg) / prevAvg : 0
            } else { change = 0 }
            history.append((week: week, sets: data.sets, e1rmChange: change))
        }
        return history
    }

}

// ═══════════════════════════════════════════
// SCHEDULE VIEW — default Train tab state
// ═══════════════════════════════════════════

struct ScheduleView: View {
    @Query private var legacyPrograms: [UserProgram]
    @Query private var programTemplates: [ProgramTemplate]
    @Query private var dayTemplatesQuery: [DayTemplate]
    @Query private var profilesQuery: [UserProfile]
    let instance: UserProgramInstance?
    let allTemplates: [ProgramSessionTemplate]
    let exerciseNames: [String: String]
    let useMetric: Bool
    let onStartSession: (SessionType) -> Void
    var onStartCustomSession: ((SessionType) -> Void)? = nil

    private var legacyProgram: UserProgram? { legacyPrograms.first(where: { $0.isActive }) }

    /// Returns the DayTemplate assigned to today's schedule, if any
    private var todayDayTemplate: DayTemplate? {
        guard let inst = instance else { return nil }
        let cal = Calendar.current
        let todayWeekday = cal.component(.weekday, from: Date())
        let todayDow = todayWeekday == 1 ? 0 : todayWeekday - 1
        let week = currentWeek
        let matchingSchedule = inst.schedules.first(where: { sched in
            sched.dayOfWeek == todayDow && !sched.dayTemplateId.isEmpty &&
            (sched.isPermanent || sched.week == week)
        })
        guard let templateId = matchingSchedule?.dayTemplateId, !templateId.isEmpty else { return nil }
        return dayTemplatesQuery.first(where: { $0.templateId.uuidString == templateId })
    }

    /// Returns the session type for today's schedule (for rest days with templates)
    private var todayScheduledSession: SessionType? {
        guard let inst = instance else { return nil }
        let cal = Calendar.current
        let todayWeekday = cal.component(.weekday, from: Date())
        let todayDow = todayWeekday == 1 ? 0 : todayWeekday - 1
        let week = currentWeek
        if let sched = inst.schedules.first(where: { s in
            s.dayOfWeek == todayDow && (s.isPermanent || s.week == week)
        }) {
            return sched.isRestDay ? .rest : sched.sessionType
        }
        return nil
    }

    private var sessionOrder: [SessionType] {
        sessionRotation(for: instance?.programId ?? 1, templates: programTemplates,
                        instance: instance, profile: profilesQuery.first)
    }

    /// Session order with all schedule overrides applied for the current week
    private var displaySessionOrder: [SessionType] {
        guard let inst = instance else { return sessionOrder }
        let week = currentWeek

        let workDays: [Int] = sessionOrder.count >= 6 ? [1,2,3,4,6,7] :
            sessionOrder.count == 5 ? [1,2,3,5,6] :
            sessionOrder.count == 3 ? [1,3,5] : [1,2,4,5]

        var dayMap: [Int: SessionType] = [:]
        for (i, st) in sessionOrder.enumerated() {
            if i < workDays.count { dayMap[workDays[i]] = st }
        }

        for s in inst.schedules where s.isPermanent {
            let dow = s.dayOfWeek == 0 ? 7 : s.dayOfWeek
            if s.isRestDay { dayMap.removeValue(forKey: dow) }
            else { dayMap[dow] = s.sessionType }
        }

        for s in inst.schedules where !s.isPermanent && s.week == week {
            let dow = s.dayOfWeek == 0 ? 7 : s.dayOfWeek
            if s.isRestDay { dayMap.removeValue(forKey: dow) }
            else { dayMap[dow] = s.sessionType }
        }

        return [1,2,3,4,5,6,7].compactMap { dayMap[$0] }
    }

    private var nextSessionType: SessionType {
        guard let inst = instance else { return sessionOrder.first ?? .heavyUpper }
        return sessionOrder[inst.nextRotationIndex % sessionOrder.count]
    }

    private var currentWeek: Int { instance?.currentWeek ?? 1 }
    private var pid: Int { instance?.programId ?? 1 }
    private var totalWeeks: Int {
        if let tmpl = programTemplates.first(where: { $0.programId == pid }) {
            return tmpl.durationWeeks
        }
        return pid == 2 ? 16 : 24
    }

    private var completedSessionCount: [SessionType: Int] {
        guard let inst = instance else { return [:] }
        let validLogs = inst.logs.filter { $0.week == currentWeek && !$0.isManualPR }
        let grouped = Dictionary(grouping: validLogs) { Calendar.current.startOfDay(for: $0.workoutDate) }
        var counts: [SessionType: Int] = [:]
        for (_, logs) in grouped {
            if let st = logs.first.flatMap({ SessionType(rawValue: $0.sessionTypeRaw) }) {
                counts[st, default: 0] += 1
            }
        }
        return counts
    }

    @State private var mesocycleWeek: Int = 1
    @State private var showBlockInfoTrain = false
    @State private var expandedSession: SessionType? = nil
    @State private var showWeekPicker = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {

                // ── Header ──────────────────────────────────────────
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("TRAIN").font(.system(size: 11, weight: .bold)).foregroundColor(.appRed).kerning(2)
                            if pid == 0 {
                                Text("FREESTYLE")
                                    .font(.system(size: 22, weight: .black, design: .rounded)).foregroundColor(.appTextPrimary)
                            } else {
                                Button(action: { showWeekPicker = true }) {
                                    HStack(spacing: 6) {
                                        Text("WEEK \(currentWeek) OF \(totalWeeks)")
                                            .font(.system(size: 22, weight: .black, design: .rounded)).foregroundColor(.appTextPrimary)
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.system(size: 10, weight: .bold)).foregroundColor(.appTextDim)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Spacer()
                        if pid != 0 {
                            Text(blockLabel(week: currentWeek, pid: pid))
                                .font(.system(size: 10, weight: .black))
                                .foregroundColor(blockColor(week: currentWeek, pid: pid))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(blockColor(week: currentWeek, pid: pid).opacity(0.12))
                                .cornerRadius(6)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .background(LinearGradient.appHeader)
                    Rectangle().frame(height: 1.5).foregroundColor(.appRed.opacity(0.5))
                }

                if pid == 0 {
                    // ── FREESTYLE MODE ────────────────────────────────
                    VStack(spacing: 20) {
                        VStack(spacing: 14) {
                            Image(systemName: "figure.mixed.cardio")
                                .font(.system(size: 36))
                                .foregroundColor(.appTextSecondary)
                            Text("FREESTYLE MODE")
                                .font(.system(size: 18, weight: .black, design: .rounded))
                                .foregroundColor(.appTextPrimary)
                            Text("No fixed program. Start a workout and add any exercises you want from the full library.")
                                .font(.system(size: 13))
                                .foregroundColor(.appTextSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 20)

                        PrimaryButton(title: "START WORKOUT", icon: "play.fill") {
                            onStartSession(.freeform)
                        }

                        // Recent freestyle sessions
                        if let inst = instance, !inst.logs.isEmpty {
                            let recentDays = Array(Set(inst.logs.map { Calendar.current.startOfDay(for: $0.date) })).sorted(by: >).prefix(5)
                            VStack(spacing: 10) {
                                SectionHeader(title: "RECENT SESSIONS")
                                ForEach(recentDays, id: \.self) { day in
                                    let dayLogs = inst.logs.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
                                    let exercises = Set(dayLogs.map { $0.displayName }).sorted()
                                    let volume = Int(dayLogs.reduce(0.0) { $0 + ($1.weight * Double($1.reps)) })
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(day, style: .date)
                                                .font(.system(size: 13, weight: .bold)).foregroundColor(.appTextPrimary)
                                            Text(exercises.prefix(3).joined(separator: " · ") + (exercises.count > 3 ? " +\(exercises.count - 3)" : ""))
                                                .font(.system(size: 11)).foregroundColor(.appTextDim).lineLimit(1)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text("\(dayLogs.count) sets").font(.system(size: 11, weight: .bold)).foregroundColor(.appTextSecondary)
                                            Text("\(volume > 1000 ? "\(volume/1000)K" : "\(volume)") lbs").font(.system(size: 10)).foregroundColor(.appTextDim)
                                        }
                                    }
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .background(Color.appSurface).cornerRadius(10)
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))
                                }
                            }
                        }
                    }
                    .padding(16).padding(.bottom, 32)
                } else {
                VStack(spacing: 20) {

                    // ── TODAY'S SCHEDULED SESSION (from schedule override) ──
                    if todayDayTemplate == nil, let scheduled = todayScheduledSession, scheduled != .rest {
                        Button { onStartSession(scheduled) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 24)).foregroundColor(.appRed)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("TODAY").font(.system(size: 9, weight: .black)).foregroundColor(.appRed).kerning(1)
                                    Text(scheduled.shortLabel).font(.system(size: 14, weight: .black)).foregroundColor(.appTextPrimary)
                                }
                                Spacer()
                                Text(scheduled.muscleSubtitle).font(.system(size: 11)).foregroundColor(.appTextDim)
                                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundColor(.appRed)
                            }
                            .padding(12)
                            .background(Color.appRed.opacity(0.04)).cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appRed.opacity(0.15), lineWidth: 1))
                        }.buttonStyle(.plain)
                    }

                    // ── TODAY'S TEMPLATE SESSION ──
                    if let template = todayDayTemplate {
                        Button { onStartSession(todayScheduledSession ?? .rest) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 24)).foregroundColor(templateColor(template.colorHex))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("TODAY").font(.system(size: 9, weight: .black)).foregroundColor(.appRed).kerning(1)
                                    Text(template.name.uppercased())
                                        .font(.system(size: 14, weight: .black)).foregroundColor(.appTextPrimary)
                                }
                                Spacer()
                                Text("\(template.exercises.count) exercises")
                                    .font(.system(size: 11)).foregroundColor(.appTextDim)
                                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundColor(templateColor(template.colorHex))
                            }
                            .padding(12)
                            .background(templateColor(template.colorHex).opacity(0.04)).cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(templateColor(template.colorHex).opacity(0.2), lineWidth: 1))
                        }.buttonStyle(.plain)
                    }

                    // ── SESSION PICKER ────────────────────────────────
                    VStack(spacing: 10) {
                        SectionHeader(title: "WEEK \(currentWeek) SESSIONS")
                        ForEach(Array(displaySessionOrder.enumerated()), id: \.offset) { idx, sessionType in
                            let isSelected = expandedSession == nil ? sessionType == nextSessionType : expandedSession == sessionType
                            let completedCount = completedSessionCount[sessionType] ?? 0
                            let neededBefore = displaySessionOrder.prefix(idx).filter { $0 == sessionType }.count
                            let isDone = completedCount > neededBefore
                            let isExpanded = expandedSession == sessionType
                            let isRotationNext = sessionType == nextSessionType
                            SessionPickerCard(
                                sessionType: sessionType,
                                week: currentWeek,
                                templates: templatesFor(sessionType, week: currentWeek),
                                exerciseNames: exerciseNames,
                                isNext: isSelected,
                                isDone: isDone,
                                isExpanded: isExpanded,
                                isRotationNext: isRotationNext,
                                onTap: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        expandedSession = isExpanded ? nil : sessionType
                                    }
                                },
                                onStart: { onStartSession(sessionType) },
                                onStartCustom: onStartCustomSession != nil ? { onStartCustomSession?(sessionType) } : nil
                            )
                        }
                    }

                    // ── MESOCYCLE BROWSER ────────────────────────────
                    VStack(spacing: 10) {
                        Button(action: { showBlockInfoTrain = true }) {
                            HStack {
                                SectionHeader(title: "MESOCYCLE")
                                Spacer()
                                if let inst = instance {
                                    let goal = profilesQuery.first?.goal ?? .hypertrophy
                                    let label: String = {
                                        switch (goal, inst.blockType) {
                                        case (.hypertrophy, .accumulation), (.recomp, .accumulation): return "Training Block"
                                        case (.hypertrophy, .reaccumulation), (.recomp, .reaccumulation): return "Growth Phase"
                                        case (.hypertrophy, .deload), (.recomp, .deload): return "Recovery"
                                        default: return inst.blockType.rawValue.capitalized
                                        }
                                    }()
                                    Text("\(label) · Wk \(inst.blockWeek)/\(inst.blockLength)")
                                        .font(.system(size: 11, weight: .bold)).foregroundColor(.appBlue)
                                }
                                Image(systemName: "info.circle")
                                    .font(.system(size: 13)).foregroundColor(.appBlue)
                            }
                        }.buttonStyle(.plain)
                        MesocycleBrowser(
                            currentWeek: currentWeek,
                            programId: pid,
                            totalWeeks: totalWeeks,
                            selectedWeek: $mesocycleWeek,
                            sessionOrder: sessionOrder,
                            allTemplates: allTemplates,
                            exerciseNames: exerciseNames,
                            goal: profilesQuery.first?.goal ?? .hypertrophy,
                            blockLength: instance?.blockLength ?? 5,
                            skipDeloads: profilesQuery.first?.skipDeloads ?? false
                        )
                    }

                }
                .padding(16).padding(.bottom, 32)
                }
            }
        }
        .onAppear { mesocycleWeek = currentWeek }
        .sheet(isPresented: $showBlockInfoTrain) {
            BlockInfoSheet(instance: instance, profile: profilesQuery.first)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showWeekPicker) {
            WeekPickerSheet(
                instance: instance,
                legacyProgram: legacyProgram,
                maxWeek: totalWeeks
            )
            .presentationDetents([.medium])
        }
    }

    private func templatesFor(_ session: SessionType, week: Int) -> [ProgramSessionTemplate] {
        let direct = allTemplates
            .filter { $0.programId == pid && $0.week == week && $0.sessionType == session }
            .sorted { $0.exerciseIndex < $1.exerciseIndex }

        // If this week should be a training week (per blockLength) but has no templates
        // or has deload-level templates, fall back to the nearest training week
        if !isEffectiveDeloadWeek(week) && direct.isEmpty {
            // Search nearby weeks for this session's templates
            for offset in [1, -1, 2, -2, 3, -3] {
                let fallbackWeek = week + offset
                guard fallbackWeek >= 1 && fallbackWeek <= totalWeeks else { continue }
                guard !isEffectiveDeloadWeek(fallbackWeek) else { continue }
                let fallback = allTemplates
                    .filter { $0.programId == pid && $0.week == fallbackWeek && $0.sessionType == session }
                    .sorted { $0.exerciseIndex < $1.exerciseIndex }
                if !fallback.isEmpty { return fallback }
            }
        }

        return direct
    }

    private func slotCount(_ session: SessionType, week: Int) -> Int {
        allTemplates.filter { $0.programId == pid && $0.week == week && $0.sessionType == session }.count
    }

    private func sessionMusclePreview(_ type: SessionType) -> String {
        switch type {
        case .heavyUpper:       return "Bench · OHP · Rows · Pulldown · Arms"
        case .heavyLower:       return "Squat · Deadlift · Leg Curl · Leg Extension"
        case .hypertrophyUpper: return "Incline DB · Cable Fly · DB Row · Delts · Arms"
        case .hypertrophyLower: return "RDL · Hip Thrust · Leg Press · Leg Curl · Calves"
        case .legQuadFocus:     return "Squat · Leg Press · Hack Squat · Extensions"
        case .legsPosterior:    return "Romanian DL · Nordic Curl · Hip Thrust · Leg Curl"
        case .chestBack:        return "Bench · Rows · Incline · Pulldown"
        case .armsDelts:        return "Curls · Triceps · Lateral Raises · Face Pull"
        case .chestArms:        return "Incline · Cable Fly · Curls · Pushdown"
        case .legsVolume:       return "Leg Press · Extensions · Curls · Calves"
        case .pushA:            return "Bench · Incline DB · Cable Fly · OHP · Laterals · Triceps"
        case .pushB:            return "OHP · Incline DB · Cable Fly · Laterals · Triceps"
        case .pullA:            return "Barbell Row · Pulldown · Cable Row · Face Pull · Curls"
        case .pullB:            return "Deadlift · DB Row · Pulldown · Face Pull · Curls"
        case .legsA:            return "Squat · Leg Press · Extensions · Leg Curl · Calves"
        case .legsB:            return "RDL · Leg Press · Leg Curl · Extensions · Calves"
        default:                return ""
        }
    }

    /// Uses the per-program deload schedule. Matches the seeded templates exactly.
    /// Returns false if user has opted to skip deloads entirely.
    private func isEffectiveDeloadWeek(_ week: Int) -> Bool {
        guard let inst = instance else { return false }
        if profilesQuery.first?.skipDeloads == true { return false }
        return deloadWeeks(for: inst.programId, blockLength: inst.blockLength).contains(week)
    }

    private func blockLabel(week: Int, pid: Int) -> String {
        let goal = profilesQuery.first?.goal ?? .hypertrophy
        let isHyp = goal == .hypertrophy || goal == .recomp

        // Use blockLength-based deload for ALL programs (synced with Home tab)
        if isEffectiveDeloadWeek(week) { return isHyp ? "RECOVERY" : "DELOAD" }

        if let inst = instance {
            if inst.isGenerated || pid > 10 {
                let bl = inst.blockLength > 0 ? inst.blockLength : 5
                let blockNum = (week - 1) / (bl + 1)
                if isHyp { return blockNum % 2 == 0 ? "TRAINING BLOCK" : "GROWTH PHASE" }
                return inst.blockType.rawValue.uppercased()
            }
        }

        // Seeded programs — block labels (deload already handled above)
        if pid == 7 {
            if week <= 9 { return "BLOCK 1" }; if week <= 15 { return "BLOCK 2" }; return "BLOCK 3"
        }
        if pid == 2 {
            return week <= 8 ? (isHyp ? "TRAINING BLOCK" : "ACCUMULATION") : (isHyp ? "GROWTH PHASE" : "INTENSIFICATION")
        }
        if week <= 8 { return isHyp ? "TRAINING BLOCK" : "ACCUMULATION" }
        if week <= 16 { return isHyp ? "GROWTH PHASE" : "INTENSIFICATION" }
        return isHyp ? "TRAINING BLOCK" : "PEAKING"
    }

    private func blockColor(week: Int, pid: Int) -> Color {
        // Use blockLength-based deload detection (synced with Home)
        if isEffectiveDeloadWeek(week) { return .appBlue }

        if pid == 2 {
            if week <= 8 { return .appGreen }
            return .appGold
        }
        if pid == 7 {
            if week <= 9 { return .appGreen }
            if week <= 15 { return .appGold }
            return .appRed
        }
        if week <= 8 { return .appGreen }
        if week <= 16 { return .appGold }
        return .appRed
    }
}

// ── SESSION PICKER CARD ─────────────────────────────────────────────────────

struct SessionPickerCard: View {
    let sessionType: SessionType
    let week: Int
    let templates: [ProgramSessionTemplate]
    let exerciseNames: [String: String]
    let isNext: Bool
    let isDone: Bool
    let isExpanded: Bool
    var isRotationNext: Bool = false
    let onTap: () -> Void
    let onStart: () -> Void
    var onStartCustom: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(isDone ? Color.appGreen : (isNext ? Color.appRed : Color.appBorder), lineWidth: 2)
                            .frame(width: 22, height: 22)
                        if isDone {
                            Image(systemName: "checkmark").font(.system(size: 10, weight: .black)).foregroundColor(.appGreen)
                        } else if isNext {
                            Circle().fill(Color.appRed).frame(width: 10, height: 10)
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(sessionType.shortLabel)
                                .font(.system(size: 14, weight: .black)).foregroundColor(.appTextPrimary)
                            if isRotationNext {
                                Text("NEXT").font(.system(size: 8, weight: .black)).foregroundColor(.appRed)
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(Color.appRed.opacity(0.12)).cornerRadius(3)
                            }
                            if isDone {
                                Text("DONE").font(.system(size: 8, weight: .black)).foregroundColor(.appGreen)
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(Color.appGreen.opacity(0.12)).cornerRadius(3)
                            }
                        }
                        Text("\(templates.count) exercises  ·  \(totalSets) sets")
                            .font(.system(size: 11)).foregroundColor(.appTextDim)
                    }
                    Spacer()

                    // Inline START button — always visible for non-done sessions
                    if !isDone {
                        HStack(spacing: 6) {
                            if let onCustom = onStartCustom {
                                Button(action: onCustom) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus.circle.fill").font(.system(size: 9))
                                        Text("CUSTOM").font(.system(size: 10, weight: .black))
                                    }
                                    .foregroundColor(.appTextSecondary)
                                    .padding(.horizontal, 8).padding(.vertical, 7)
                                    .background(Color.appSurface2).cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                            Button(action: onStart) {
                                HStack(spacing: 4) {
                                    Image(systemName: "play.fill").font(.system(size: 9))
                                    Text("START").font(.system(size: 10, weight: .black))
                                }
                                .foregroundColor(.appRed)
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .background(Color.appRed.opacity(0.1)).cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold)).foregroundColor(.appTextDim)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().background(Color.appBorder).padding(.horizontal, 14)
                VStack(spacing: 0) {
                    ForEach(templates, id: \.slotId) { t in
                        let name = exerciseNames[t.exerciseKey] ?? t.exerciseKey.replacingOccurrences(of: "_", with: " ").capitalized
                        HStack(spacing: 10) {
                            Text(t.slotId)
                                .font(.system(size: 9, weight: .black, design: .monospaced))
                                .foregroundColor(.appRed)
                                .frame(width: 26, height: 26)
                                .background(Color.appRed.opacity(0.08)).cornerRadius(6)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 5) {
                                    Text(name).font(.system(size: 13, weight: .bold)).foregroundColor(.appTextPrimary)
                                    if t.isMainLift {
                                        Text("MAIN").font(.system(size: 7, weight: .black)).foregroundColor(.appGold)
                                            .padding(.horizontal, 4).padding(.vertical, 2)
                                            .background(Color.appGold.opacity(0.15)).cornerRadius(3)
                                    }
                                }
                                Text("\(t.targetSets) × \(t.targetRepsLow)–\(t.targetRepsHigh)  ·  RPE \(String(format: "%.1f", t.targetRPE))")
                                    .font(.system(size: 11)).foregroundColor(.appTextDim)
                            }
                            Spacer()
                            Text(restLabel(t.restSeconds))
                                .font(.system(size: 10, weight: .bold)).foregroundColor(.appTextDim)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        if t.slotId != templates.last?.slotId {
                            Divider().background(Color.appBorder).padding(.leading, 50)
                        }
                    }
                }
            }
        }
        .background(Color.appSurface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isNext ? Color.appRed.opacity(0.4) : Color.appBorder, lineWidth: isNext ? 1.5 : 1)
        )
        .shadow(color: isNext ? Color.appRed.opacity(0.1) : Color.black.opacity(0.2), radius: isNext ? 10 : 6, x: 0, y: 3)
    }

    private var totalSets: Int { templates.reduce(0) { $0 + $1.targetSets } }
    private func restLabel(_ s: Int) -> String {
        s < 60 ? "\(s)s" : (s % 60 == 0 ? "\(s/60)m" : "\(s/60)m\(s%60)s")
    }
}

// ── MESOCYCLE BROWSER ────────────────────────────────────────────────────────

struct MesocycleBrowser: View {
    let currentWeek: Int
    let programId: Int
    let totalWeeks: Int
    @Binding var selectedWeek: Int
    let sessionOrder: [SessionType]
    let allTemplates: [ProgramSessionTemplate]
    let exerciseNames: [String: String]
    var goal: GoalType = .hypertrophy
    var blockLength: Int = 5
    var skipDeloads: Bool = false
    private var isHyp: Bool { goal == .hypertrophy || goal == .recomp }
    private var cycleLen: Int { blockLength + 1 }

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 8) {
                HStack {
                    Text("Week \(selectedWeek)").font(.system(size: 14, weight: .black)).foregroundColor(.appTextPrimary)
                    Spacer()
                    Text(blockLabel(selectedWeek))
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(blockColor(selectedWeek))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(blockColor(selectedWeek).opacity(0.12)).cornerRadius(5)
                }
                HStack(spacing: 2) {
                    ForEach(1...max(totalWeeks, 1), id: \.self) { w in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(w == currentWeek ? Color.appRed :
                                (w == selectedWeek ? blockColor(w).opacity(0.8) :
                                (w < currentWeek ? Color.appGreen.opacity(0.5) : blockColor(w).opacity(0.25))))
                            .frame(height: 8)
                            .onTapGesture { withAnimation { selectedWeek = w } }
                    }
                }
            }
            .padding(14).appCard()

            ForEach(sessionOrder, id: \.self) { sessionType in
                let templates = allTemplates
                    .filter { $0.programId == programId && $0.week == selectedWeek && $0.sessionType == sessionType }
                    .sorted { $0.exerciseIndex < $1.exerciseIndex }
                if !templates.isEmpty {
                    MesocycleSessionCard(
                        sessionType: sessionType,
                        week: selectedWeek,
                        templates: templates,
                        exerciseNames: exerciseNames,
                        isCurrentWeek: selectedWeek == currentWeek
                    )
                }
            }
        }
    }

    private func isDeloadWeek(_ w: Int) -> Bool {
        if skipDeloads { return false }
        return deloadWeeks(for: programId, blockLength: blockLength).contains(w)
    }

    private func blockLabel(_ w: Int) -> String {
        if isDeloadWeek(w) { return isHyp ? "RECOVERY" : "DELOAD" }
        switch programId {
        case 7:
            if w <= 9 { return "BLOCK 1" }; if w <= 15 { return "BLOCK 2" }; return "BLOCK 3"
        case 2:
            return w <= 8 ? (isHyp ? "TRAINING BLOCK" : "ACCUMULATION") : (isHyp ? "GROWTH PHASE" : "INTENSIFICATION")
        default:
            if programId > 10 {
                let blockNum = (w - 1) / cycleLen
                if isHyp { return blockNum % 2 == 0 ? "TRAINING BLOCK" : "GROWTH PHASE" }
            }
            if w <= 8 { return isHyp ? "TRAINING BLOCK" : "ACCUMULATION" }
            if w <= 16 { return isHyp ? "GROWTH PHASE" : "INTENSIFICATION" }
            return isHyp ? "TRAINING BLOCK" : "PEAKING"
        }
    }

    private func blockColor(_ w: Int) -> Color {
        if isDeloadWeek(w) { return .appBlue }
        switch programId {
        case 7:
            if w <= 9 { return .appGreen }; if w <= 15 { return .appGold }; return .appOrange
        case 2:
            return w <= 8 ? .appGreen : .appGold
        default:
            if programId > 10 {
                let blockNum = (w - 1) / cycleLen
                let colors: [Color] = [.appGreen, .appGold, .appOrange, .appRed]
                return colors[blockNum % colors.count]
            }
            if w <= 8 { return .appGreen }; if w <= 16 { return .appGold }; return .appRed
        }
    }
}

struct MesocycleSessionCard: View {
    let sessionType: SessionType
    let week: Int
    let templates: [ProgramSessionTemplate]
    let exerciseNames: [String: String]
    let isCurrentWeek: Bool
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 0) {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } }) {
                HStack(spacing: 12) {
                    Text(sessionType.shortLabel)
                        .font(.system(size: 13, weight: .black)).foregroundColor(isCurrentWeek ? .appRed : .appTextPrimary)
                    Spacer()
                    Text("\(templates.count) exercises")
                        .font(.system(size: 11)).foregroundColor(.appTextDim)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold)).foregroundColor(.appTextDim)
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
            }
            .buttonStyle(.plain)

            if expanded {
                Divider().background(Color.appBorder).padding(.horizontal, 14)
                VStack(spacing: 0) {
                    ForEach(templates, id: \.slotId) { t in
                        let name = exerciseNames[t.exerciseKey] ?? t.exerciseKey.replacingOccurrences(of: "_", with: " ").capitalized
                        HStack(spacing: 10) {
                            Text(t.slotId)
                                .font(.system(size: 8, weight: .black, design: .monospaced)).foregroundColor(.appRed)
                                .frame(width: 34, height: 34).contentShape(Rectangle()).background(Color.appRed.opacity(0.08)).cornerRadius(6)
                            Text(name).font(.system(size: 12, weight: .bold)).foregroundColor(.appTextPrimary)
                            Spacer()
                            Text("\(t.targetSets)×\(t.targetRepsLow)–\(t.targetRepsHigh)")
                                .font(.system(size: 11, weight: .bold)).foregroundColor(.appTextSecondary)
                            Text("@\(String(format: "%.1f", t.targetRPE))")
                                .font(.system(size: 10)).foregroundColor(.appTextDim)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        if t.slotId != templates.last?.slotId {
                            Divider().background(Color.appBorder).padding(.leading, 48)
                        }
                    }
                }
            }
        }
        .background(Color.appSurface).cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isCurrentWeek ? Color.appRed.opacity(0.25) : Color.appBorder, lineWidth: 1)
        )
    }
}

// ═══════════════════════════════════════════
// PRE-WORKOUT VIEW
// ═══════════════════════════════════════════

struct PreWorkoutView: View {
    let session: ActiveWorkoutSession
    let instance: UserProgramInstance?
    let exerciseNames: [String: String]
    let useMetric: Bool
    let onStart: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onCancel) {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                        .foregroundColor(.appTextSecondary).padding(10)
                        .background(Color.appSurface2).clipShape(Circle())
                }
                Spacer()
                VStack(spacing: 2) {
                    Text(session.sessionLabel).font(.system(size: 15, weight: .black)).foregroundColor(.appTextPrimary)
                    if session.sessionType != .freeform {
                        Text("WEEK \(session.week)").font(.system(size: 10, weight: .bold)).foregroundColor(.appRed).kerning(1.5)
                    }
                }
                Spacer()
                Color.clear.frame(width: 38, height: 38)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Color.appSurface)
            .overlay(Rectangle().frame(height: 1).foregroundColor(.appBorder), alignment: .bottom)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    if session.exercises.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: session.isCustom ? "dumbbell.fill" : "plus.circle.fill")
                                .font(.system(size: 36)).foregroundColor(.appTextDim)
                            Text(session.isCustom ? "CUSTOM SESSION" : "FREESTYLE WORKOUT")
                                .font(.system(size: 15, weight: .black)).foregroundColor(.appTextPrimary)
                            Text(session.isCustom
                                ? "Start the workout and pick any exercises you want for this \(session.sessionType.shortLabel) slot."
                                : "Start the workout, then add exercises from the library using the + button.")
                                .font(.system(size: 13)).foregroundColor(.appTextSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(30)
                    } else {
                        ForEach(session.exercises) { ex in
                            PreviewExerciseRow(
                                exercise: ex,
                                lastWeight: instance?.logs
                                    .filter { $0.exerciseKey == ex.exerciseKey }
                                    .sorted { $0.date > $1.date }.first?.weight,
                                useMetric: useMetric
                            )
                        }
                    }
                }
                .padding(16).padding(.bottom, 100)
            }

            VStack(spacing: 0) {
                Divider().background(Color.appBorder)
                PrimaryButton(title: "START WORKOUT", icon: "play.fill", action: onStart)
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .background(Color.appBG)
            }
        }
    }
}

struct PreviewExerciseRow: View {
    let exercise: LiveExercise
    let lastWeight: Double?
    let useMetric: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(exercise.slotId)
                .font(.system(size: 11, weight: .black, design: .monospaced)).foregroundColor(.appRed)
                .frame(width: 32, height: 32).background(Color.appRed.opacity(0.1)).cornerRadius(8)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(exercise.displayName).font(.system(size: 14, weight: .bold)).foregroundColor(.appTextPrimary)
                    // Tier badge: T1 red, T2 blue, T3 green
                    let tierInfo = exerciseTierInfo(exercise)
                    Text(tierInfo.label).font(.system(size: 8, weight: .black)).foregroundColor(tierInfo.color)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(tierInfo.color.opacity(0.12)).cornerRadius(3)
                }
                HStack(spacing: 4) {
                    Text("\(exercise.targetSets) × \(exercise.targetRepsLow)–\(exercise.targetRepsHigh)  ·  RPE \(String(format: "%.1f", exercise.targetRPE))")
                        .font(.system(size: 12)).foregroundColor(.appTextDim)
                }
                // Context subtitle
                Text(exerciseTierInfo(exercise).subtitle)
                    .font(.system(size: 10)).foregroundColor(.appTextDim.opacity(0.7))
            }
            Spacer()
            if exercise.recommendedWeight > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.0f", exercise.recommendedWeight))
                        .font(.system(size: 15, weight: .black, design: .rounded)).foregroundColor(.appTextSecondary)
                    Text(useMetric ? "kg" : "lbs").font(.system(size: 10)).foregroundColor(.appTextDim)
                }
            } else {
                Text("NEW").font(.system(size: 10, weight: .black)).foregroundColor(.appBlue)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.appBlue.opacity(0.12)).cornerRadius(4)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12).appCard()
    }

    private func exerciseTierInfo(_ ex: LiveExercise) -> (label: String, color: Color, subtitle: String) {
        if ex.isMainLift {
            return ("T1", .appRed, "Strength anchor — tracks your e1RM")
        }
        let def = ExerciseDictionary.all[ex.exerciseKey]
        if let d = def, !d.isCompound {
            return ("T3", .appGreen, "Isolation finisher — pump & stretch")
        }
        return ("T2", .appBlue, "Hypertrophy accessory — growth focus")
    }
}

// ═══════════════════════════════════════════
// ACTIVE WORKOUT VIEW
// Layout: .card (tab per exercise) or .scroll (all at once)
// ═══════════════════════════════════════════

struct ActiveWorkoutView: View {
    @ObservedObject var session: ActiveWorkoutSession
    let exerciseNames: [String: String]
    let allExercises: [Exercise]
    let allLogs: [WorkoutLog]
    let progressionStates: [ProgressionState]
    let instance: UserProgramInstance?
    let useMetric: Bool
    let onFinish: () -> Void
    @Query private var profilesForSettings: [UserProfile]
    private var showRPE: Bool { profilesForSettings.first?.showRPE ?? true }
    private var showRepRange: Bool { profilesForSettings.first?.showRepRange ?? true }
    private var showRestTimer: Bool { profilesForSettings.first?.showRestTimer ?? true }

    @State private var currentExerciseIndex: Int = 0
    @State private var layoutMode: WorkoutLayoutMode = .scroll
    @State private var elapsedSeconds: Int = 0
    @State private var elapsedTimer: Timer? = nil
    @State private var restSecondsRemaining: Int = 0
    @State private var restTotal: Int = 0
    @State private var showingRestTimer: Bool = false
    @State private var restTimer: Timer? = nil

    // Mid-workout swap
    @State private var swapExerciseIndex: Int? = nil
    @State private var showInWorkoutSwap = false

    // Exercise config edit
    @State private var editExerciseIndex: Int? = nil
    @State private var showExerciseConfig = false

    // Delete confirmation
    @State private var deleteExerciseIndex: Int? = nil
    @State private var showDeleteConfirm = false

    // Progressive overload card expansion
    @State private var expandedOverloadKey: String? = nil

    // Add exercise (freestyle)
    @State private var showAddExercise = false
    @State private var insertExerciseAtIndex: Int? = nil

    // Exercise history
    @State private var historyExerciseKey: String? = nil
    @State private var historyExerciseName: String? = nil
    @State private var showExerciseHistory = false

    private var safeIndex: Int {
        guard !session.exercises.isEmpty else { return 0 }
        return min(currentExerciseIndex, session.exercises.count - 1)
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Top bar ──────────────────────────────────────────
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.sessionLabel).font(.system(size: 14, weight: .black)).foregroundColor(.appTextPrimary)
                    Text(elapsedFormatted).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.appTextDim)
                }
                Spacer()
                Text("\(session.totalSetsLogged)/\(session.totalSets) sets")
                    .font(.system(size: 12, weight: .bold)).foregroundColor(.appTextSecondary)

                // Layout toggle
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { layoutMode = layoutMode == .card ? .scroll : .card } }) {
                    Image(systemName: layoutMode == .card ? "list.bullet" : "square.stack")
                        .font(.system(size: 14, weight: .bold)).foregroundColor(.appTextSecondary)
                        .frame(width: 34, height: 34).background(Color.appSurface2).cornerRadius(8)
                }

                Button(action: onFinish) {
                    Text("FINISH").font(.system(size: 12, weight: .black)).foregroundColor(.appRed)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.appRed.opacity(0.1)).cornerRadius(8)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Color.appSurface)
            .overlay(Rectangle().frame(height: 1).foregroundColor(.appBorder), alignment: .bottom)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Color.appSurface2.frame(height: 3)
                    let pct = session.totalSets > 0 ? Double(session.totalSetsLogged) / Double(session.totalSets) : 0
                    Color.appRed.frame(width: geo.size.width * pct, height: 3)
                        .animation(.easeOut, value: session.totalSetsLogged)
                }
            }
            .frame(height: 3)

            // Rest timer
            if showingRestTimer {
                RestTimerBanner(secondsRemaining: restSecondsRemaining, total: restTotal, onSkip: cancelRest)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if layoutMode == .card {
                cardLayout
            } else {
                scrollLayout
            }
        }
        .onAppear {
            startElapsed()
            if session.isCustom && session.exercises.isEmpty {
                showAddExercise = true
            }
        }
        .onDisappear { elapsedTimer?.invalidate(); restTimer?.invalidate() }
        .sheet(isPresented: $showInWorkoutSwap) {
            if let idx = swapExerciseIndex {
                let ex = session.exercises[idx]
                let target = SwapTarget.from(
                    exerciseKey: ex.exerciseKey,
                    displayName: ex.displayName,
                    slotId: ex.slotId,
                    sessionType: session.sessionType,
                    exercises: allExercises
                )
                if let inst = instance {
                    ExerciseSwapSheet(
                        slot: target,
                        instance: inst,
                        week: session.week,
                        onDismiss: { showInWorkoutSwap = false; swapExerciseIndex = nil },
                        onSwapApplied: { newKey, _ in
                            applyMidWorkoutSwap(idx: idx, newKey: newKey)
                        }
                    )
                } else {
                    // Freestyle mode — no instance, use swap sheet without persistence
                    FreestyleSwapSheet(
                        slot: target,
                        allExercises: allExercises,
                        onDismiss: { showInWorkoutSwap = false; swapExerciseIndex = nil },
                        onSwap: { newKey in
                            applyMidWorkoutSwap(idx: idx, newKey: newKey)
                        }
                    )
                }
            }
        }
        .sheet(isPresented: $showAddExercise) {
            InWorkoutAddSheet(allExercises: allExercises) { exercise in
                let slotId = "F\(session.exercises.count + 1)"
                let sets = (0..<3).map { i in LiveSet(setIndex: i, recommendedWeight: 0, recommendedReps: 10) }
                let addTier: ExerciseTier = {
                    let def = ExerciseDictionary.all[exercise.exerciseKey]
                    if def?.isAnchorableAsTier1 == true { return .tier1 }
                    if def?.isCompound == true { return .tier2 }
                    return .tier3
                }()
                let live = LiveExercise(
                    exerciseKey: exercise.exerciseKey,
                    displayName: exercise.displayName,
                    slotId: slotId,
                    role: .accessory,
                    exerciseTier: addTier,
                    targetSets: 3,
                    targetRepsLow: 8,
                    targetRepsHigh: 12,
                    targetRPE: 8.0,
                    restSeconds: 90,
                    notes: "",
                    sets: sets
                )
                if let insertIdx = insertExerciseAtIndex {
                    session.exercises.insert(live, at: min(insertIdx, session.exercises.count))
                } else {
                    session.exercises.append(live)
                }
                insertExerciseAtIndex = nil
                showAddExercise = false
            }
        }
        .confirmationDialog("Remove Exercise?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let idx = deleteExerciseIndex { removeExercise(at: idx) }
                deleteExerciseIndex = nil
            }
            Button("Cancel", role: .cancel) { deleteExerciseIndex = nil }
        } message: {
            Text("Remove this exercise from the workout?")
        }
        .sheet(isPresented: $showExerciseConfig) {
            if let idx = editExerciseIndex, idx < session.exercises.count {
                ExerciseConfigSheet(
                    exercise: $session.exercises[idx],
                    showRPE: showRPE,
                    showRepRange: showRepRange,
                    showRestTimer: showRestTimer
                )
                .presentationDetents([.medium])
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.appRed)
            }
        }
        .sheet(isPresented: $showExerciseHistory) {
            if let key = historyExerciseKey, let name = historyExerciseName {
                ExerciseHistorySheet(exerciseKey: key, displayName: name)
            }
        }
    }

    // ── CARD LAYOUT ──────────────────────────────────────────────────────────

    private var cardLayout: some View {
        VStack(spacing: 0) {
            // Exercise tab bar
            if !session.exercises.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(Array(session.exercises.enumerated()), id: \.element.id) { idx, ex in
                            let allDone = ex.sets.filter { !$0.isSkipped }.allSatisfy { $0.isLogged }
                            let isCurrent = idx == safeIndex
                            Button(action: { currentExerciseIndex = idx }) {
                                VStack(spacing: 4) {
                                    Text(ex.slotId)
                                        .font(.system(size: 11, weight: .black, design: .monospaced))
                                        .foregroundColor(isCurrent ? .appRed : (allDone ? .appGreen : .appTextDim))
                                    Text(ex.displayName.components(separatedBy: " ").prefix(2).joined(separator: " "))
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(isCurrent ? .appTextPrimary : .appTextDim)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .background(isCurrent ? Color.appRed.opacity(0.1) : Color.clear)
                                .overlay(Rectangle().frame(height: 2).foregroundColor(isCurrent ? .appRed : .clear), alignment: .bottom)
                            }
                            .buttonStyle(.plain)
                        }
                        // Add exercise tab
                        Button(action: { showAddExercise = true }) {
                            VStack(spacing: 4) {
                                Image(systemName: "plus").font(.system(size: 13, weight: .bold)).foregroundColor(.appRed)
                                Text("ADD").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color.appSurface)
                .overlay(Rectangle().frame(height: 1).foregroundColor(.appBorder), alignment: .bottom)
            }

            if session.exercises.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "plus.circle.fill").font(.system(size: 40)).foregroundColor(.appTextDim)
                    Text("No exercises yet").font(.system(size: 16, weight: .bold)).foregroundColor(.appTextSecondary)
                    Text("Tap + in the tab bar above to add exercises").font(.system(size: 13)).foregroundColor(.appTextDim)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                let exIdx = safeIndex
                let ex = session.exercises[exIdx]
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        exerciseHeader(ex: ex, exIdx: exIdx)
                        ProgressiveOverloadCard(
                            exerciseKey: ex.exerciseKey,
                            displayName: ex.displayName,
                            exerciseTier: ex.exerciseTier,
                            targetRepsLow: ex.targetRepsLow,
                            targetRepsHigh: ex.targetRepsHigh,
                            targetRPE: ex.targetRPE,
                            allLogs: allLogs,
                            useMetric: useMetric,
                            isExpanded: expandedOverloadKey == ex.exerciseKey,
                            onToggle: {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    expandedOverloadKey = expandedOverloadKey == ex.exerciseKey ? nil : ex.exerciseKey
                                }
                            },
                            progressionState: progressionStates.first(where: { $0.exerciseKey == ex.exerciseKey })
                        )
                        .padding(.horizontal, 16)
                        setsSection(ex: ex, exIdx: exIdx)
                        navButtons(exIdx: exIdx)
                    }
                }
                .scrollDismissesKeyboard(.immediately)
                .onChange(of: session.exercises.count) { _, newCount in
                    if currentExerciseIndex >= newCount { currentExerciseIndex = max(0, newCount - 1) }
                }
            }
        }
    }

    // ── SCROLL LAYOUT ────────────────────────────────────────────────────────

    private var scrollLayout: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                ForEach(Array(session.exercises.enumerated()), id: \.element.id) { idx, ex in
                    VStack(spacing: 12) {
                        exerciseHeader(ex: ex, exIdx: idx)
                        ProgressiveOverloadCard(
                            exerciseKey: ex.exerciseKey,
                            displayName: ex.displayName,
                            exerciseTier: ex.exerciseTier,
                            targetRepsLow: ex.targetRepsLow,
                            targetRepsHigh: ex.targetRepsHigh,
                            targetRPE: ex.targetRPE,
                            allLogs: allLogs,
                            useMetric: useMetric,
                            isExpanded: expandedOverloadKey == ex.exerciseKey,
                            onToggle: {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    expandedOverloadKey = expandedOverloadKey == ex.exerciseKey ? nil : ex.exerciseKey
                                }
                            },
                            progressionState: progressionStates.first(where: { $0.exerciseKey == ex.exerciseKey })
                        )
                        setsSection(ex: ex, exIdx: idx)

                        // IFI Badge — shown when all sets are logged
                        if ex.allSetsLogged, let ifi = ex.intrasetFatigueIndex, ifi > 0 {
                            let zone = IFIZone.classify(ifi)
                            HStack(spacing: 6) {
                                Circle().fill(ifiDotColor(zone)).frame(width: 6, height: 6)
                                Text("IFI: \(String(format: "%.0f%%", ifi * 100))")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.appTextSecondary)
                                Text("—")
                                    .font(.system(size: 11))
                                    .foregroundColor(.appTextDim)
                                Text(zone.rawValue)
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundColor(ifiDotColor(zone))
                                    .kerning(0.5)
                                Spacer()
                            }
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(ifiDotColor(zone).opacity(0.06))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.bottom, 4)
                    if idx < session.exercises.count - 1 {
                        if let ssid = ex.supersetGroupId, !ssid.isEmpty,
                           session.exercises[idx + 1].supersetGroupId == ssid {
                            // Superset connector
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.triangle.swap")
                                    .font(.system(size: 10, weight: .bold)).foregroundColor(.appBlue)
                                Text("SUPERSET")
                                    .font(.system(size: 9, weight: .black)).foregroundColor(.appBlue).kerning(1)
                                Rectangle().fill(Color.appBlue.opacity(0.3)).frame(height: 1)
                            }
                            .padding(.vertical, 4)
                        } else {
                            HStack(spacing: 0) {
                                Rectangle().fill(Color.appBorder.opacity(0.4)).frame(height: 1)
                                Button {
                                    insertExerciseAtIndex = idx + 1
                                    showAddExercise = true
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(.appRed.opacity(0.5))
                                        .padding(.horizontal, 8)
                                }
                                .buttonStyle(.plain)
                                Rectangle().fill(Color.appBorder.opacity(0.4)).frame(height: 1)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                // Add Exercise button
                Button(action: { showAddExercise = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 18))
                        Text("ADD EXERCISE").font(.system(size: 13, weight: .black)).kerning(1)
                    }
                    .foregroundColor(.appRed)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color.appRed.opacity(0.08)).cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appRed.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)

                // Session notes
                VStack(alignment: .leading, spacing: 6) {
                    Text("SESSION NOTES")
                        .font(.system(size: 10, weight: .bold)).foregroundColor(.appTextDim).kerning(1.5)
                    TextField("How did this session feel?", text: $session.notes, axis: .vertical)
                        .font(.system(size: 14)).foregroundColor(.appTextPrimary)
                        .lineLimit(3...6)
                        .padding(12)
                        .background(Color.appSurface2).cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorder, lineWidth: 1))
                }
                .padding(14)
                .appCard()
            }
            .padding(.horizontal, 16).padding(.vertical, 16).padding(.bottom, 100)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    // ── SHARED EXERCISE COMPONENTS ────────────────────────────────────────────

    private func ifiDotColor(_ zone: IFIZone) -> Color {
        switch zone {
        case .fresh:       return .appBlue
        case .optimal:     return .appGreen
        case .fatigued:    return .appYellow
        case .acuteOverreach: return .appRed
        }
    }

    @ViewBuilder
    private func exerciseHeader(ex: LiveExercise, exIdx: Int) -> some View {
        let loggedCount = ex.sets.filter { $0.isLogged }.count
        let totalCount = ex.sets.count
        return HStack(spacing: 8) {
            // UI-2: Completed sets badge
            ZStack(alignment: .topTrailing) {
                Text(ex.slotId)
                    .font(.system(size: 10, weight: .black, design: .monospaced)).foregroundColor(.appRed)
                    .frame(width: 30, height: 30).background(Color.appRed.opacity(0.1)).cornerRadius(8)
                if loggedCount > 0 {
                    Text("\(loggedCount)/\(totalCount)")
                        .font(.system(size: 7, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 3).padding(.vertical, 1)
                        .background(loggedCount == totalCount ? Color.appGreen : Color.appRed)
                        .cornerRadius(4)
                        .offset(x: 6, y: -6)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(ex.displayName)
                        .font(.system(size: 16, weight: .black, design: .rounded)).foregroundColor(.appTextPrimary)
                        .onTapGesture {
                            historyExerciseKey = ex.exerciseKey
                            historyExerciseName = ex.displayName
                            showExerciseHistory = true
                        }
                    if ex.isMainLift {
                        Text("MAIN").font(.system(size: 8, weight: .black)).foregroundColor(.appGold)
                            .padding(.horizontal, 5).padding(.vertical, 3)
                            .background(Color.appGold.opacity(0.15)).cornerRadius(3)
                    }
                    if let ssid = ex.supersetGroupId, !ssid.isEmpty {
                        Text("SS").font(.system(size: 8, weight: .black)).foregroundColor(.appBlue)
                            .padding(.horizontal, 5).padding(.vertical, 3)
                            .background(Color.appBlue.opacity(0.15)).cornerRadius(3)
                    }
                }
                Button {
                    editExerciseIndex = exIdx
                    showExerciseConfig = true
                } label: {
                    HStack(spacing: 4) {
                        let parts: [String] = {
                            var p: [String] = []
                            if showRepRange { p.append("\(ex.targetRepsLow)–\(ex.targetRepsHigh) reps") }
                            if showRPE { p.append("RPE \(String(format: "%.0f", ex.targetRPE))") }
                            if showRestTimer { p.append("\(restLabel(ex.restSeconds)) rest") }
                            return p
                        }()
                        Text(parts.isEmpty ? "Tap to configure" : parts.joined(separator: "  ·  "))
                        Image(systemName: "pencil").font(.system(size: 8))
                    }
                    .font(.system(size: 11)).foregroundColor(.appTextDim)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            // Action icons
            HStack(spacing: 4) {
                if exIdx > 0 {
                    Button(action: { moveExercise(from: exIdx, direction: -1) }) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 11, weight: .bold)).foregroundColor(.appTextDim)
                            .frame(width: 30, height: 30).background(Color.appSurface2).cornerRadius(6)
                    }.buttonStyle(.plain)
                }
                if exIdx < session.exercises.count - 1 {
                    Button(action: { moveExercise(from: exIdx, direction: 1) }) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold)).foregroundColor(.appTextDim)
                            .frame(width: 30, height: 30).background(Color.appSurface2).cornerRadius(6)
                    }.buttonStyle(.plain)
                }
                Button(action: { swapExerciseIndex = exIdx; showInWorkoutSwap = true }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .bold)).foregroundColor(.appBlue)
                        .frame(width: 30, height: 30).background(Color.appBlue.opacity(0.1)).cornerRadius(6)
                }.buttonStyle(.plain)
                // Superset toggle — pair with next exercise
                if exIdx < session.exercises.count - 1 {
                    let isSupersetted = ex.supersetGroupId != nil && !ex.supersetGroupId!.isEmpty
                    Button(action: { toggleSuperset(at: exIdx) }) {
                        Image(systemName: "arrow.triangle.swap")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(isSupersetted ? .appBlue : .appTextDim)
                            .frame(width: 30, height: 30)
                            .background(isSupersetted ? Color.appBlue.opacity(0.15) : Color.appSurface2)
                            .cornerRadius(6)
                    }.buttonStyle(.plain)
                }
                if session.exercises.count > 1 {
                    Button(action: { deleteExerciseIndex = exIdx; showDeleteConfirm = true }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .bold)).foregroundColor(.appRed.opacity(0.7))
                            .frame(width: 30, height: 30).background(Color.appRed.opacity(0.08)).cornerRadius(6)
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, layoutMode == .card ? 16 : 0)
        .padding(.top, layoutMode == .card ? 16 : 0)

        if !ex.notes.isEmpty {
            Text(ex.notes).font(.system(size: 12, weight: .medium)).foregroundColor(.appBlue)
                .padding(10).background(Color.appBlue.opacity(0.08)).cornerRadius(8)
                .padding(.horizontal, layoutMode == .card ? 16 : 0)
        }

        // Exercise cue (persistent, from Exercise model)
        if let exerciseCue = allExercises.first(where: { $0.exerciseKey == ex.exerciseKey })?.cue, !exerciseCue.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 9, weight: .bold)).foregroundColor(.appGold)
                Text(exerciseCue)
                    .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(.appGold)
                Spacer()
            }
            .padding(10).background(Color.appGold.opacity(0.08)).cornerRadius(8)
            .padding(.horizontal, layoutMode == .card ? 16 : 0)
        }
    }

    private func setsSection(ex: LiveExercise, exIdx: Int) -> some View {
        let firstSetWeight = session.exercises[exIdx].sets.first?.recommendedWeight ?? 0
        let canRemoveSet = session.exercises[exIdx].sets.count > 1
        return VStack(spacing: 8) {
            // Warm-up sets (collapsible, T1/T2 only)
            if !session.exercises[exIdx].warmupSets.isEmpty {
                warmupSection(exIdx: exIdx)
            }

            ForEach(Array(session.exercises[exIdx].sets.enumerated()), id: \.element.id) { setIdx, liveSet in
                setRow(exIdx: exIdx, setIdx: setIdx, liveSet: liveSet, ex: ex,
                       firstSetWeight: firstSetWeight, canRemoveSet: canRemoveSet)
            }

            // Add Set button
            Button(action: {
                let nextIndex = session.exercises[exIdx].sets.count
                let refWeight = session.exercises[exIdx].sets.last?.recommendedWeight ?? 0
                session.exercises[exIdx].sets.append(
                    LiveSet(setIndex: nextIndex, recommendedWeight: refWeight, recommendedReps: ex.targetRepsHigh)
                )
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                    Text("ADD SET").font(.system(size: 12, weight: .black))
                }
                .foregroundColor(.appRed)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.appRed.opacity(0.06))
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appRed.opacity(0.15), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, layoutMode == .card ? 16 : 0)
    }

    @ViewBuilder
    private func navButtons(exIdx: Int) -> some View {
        HStack(spacing: 12) {
            if exIdx > 0 {
                Button(action: { withAnimation { currentExerciseIndex = exIdx - 1 } }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left").font(.system(size: 12, weight: .bold))
                        Text("PREV").font(.system(size: 12, weight: .black))
                    }
                    .foregroundColor(.appTextSecondary).frame(maxWidth: .infinity)
                    .padding(.vertical, 12).background(Color.appSurface2).cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
            if exIdx < session.exercises.count - 1 {
                Button(action: { withAnimation { currentExerciseIndex = exIdx + 1 } }) {
                    HStack(spacing: 6) {
                        Text("NEXT").font(.system(size: 12, weight: .black))
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(.appTextPrimary).frame(maxWidth: .infinity)
                    .padding(.vertical, 12).background(Color.appRed.opacity(0.15)).cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 32)
    }

    @State private var warmupExpanded: Set<Int> = []

    private func warmupSection(exIdx: Int) -> some View {
        let expanded = warmupExpanded.contains(exIdx)
        let warmups = session.exercises[exIdx].warmupSets
        let useMetric = false // inherited from parent

        return VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if expanded { warmupExpanded.remove(exIdx) }
                    else { warmupExpanded.insert(exIdx) }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "flame").font(.system(size: 10)).foregroundColor(.appOrange)
                    Text("WARM-UP").font(.system(size: 10, weight: .black)).foregroundColor(.appOrange).kerning(1)
                    Text("(\(warmups.count) sets)")
                        .font(.system(size: 10, weight: .medium)).foregroundColor(.appTextDim)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .contentShape(Rectangle())
            }.buttonStyle(.plain)

            if expanded {
                VStack(spacing: 4) {
                    ForEach(Array(warmups.enumerated()), id: \.element.id) { idx, wu in
                        HStack(spacing: 10) {
                            Button {
                                session.exercises[exIdx].warmupSets[idx].isComplete.toggle()
                            } label: {
                                Image(systemName: session.exercises[exIdx].warmupSets[idx].isComplete
                                      ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 14))
                                    .foregroundColor(session.exercises[exIdx].warmupSets[idx].isComplete
                                                     ? .appGreen : .appTextDim)
                            }.buttonStyle(.plain)

                            Text(wu.label).font(.system(size: 10, weight: .bold)).foregroundColor(.appTextDim)
                                .frame(width: 30, alignment: .leading)
                            Text("\(Int(wu.weight))").font(.system(size: 13, weight: .bold)).foregroundColor(.appTextSecondary)
                            Text("×").font(.system(size: 11)).foregroundColor(.appTextDim)
                            Text("\(wu.reps)").font(.system(size: 13, weight: .bold)).foregroundColor(.appTextSecondary)
                            Spacer()
                        }
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .opacity(session.exercises[exIdx].warmupSets[idx].isComplete ? 0.5 : 1.0)
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .background(Color.appOrange.opacity(0.04))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appOrange.opacity(0.15), lineWidth: 1))
    }

    private func setRow(exIdx: Int, setIdx: Int, liveSet: LiveSet, ex: LiveExercise,
                         firstSetWeight: Double, canRemoveSet: Bool) -> some View {
        let backoff = ex.isMainLift && setIdx > 0 && liveSet.recommendedWeight < firstSetWeight
        let removeBlock: (() -> Void)? = canRemoveSet ? removeSetAction(exIdx: exIdx, setIdx: setIdx) : nil
        let completeBlock = completeSetAction(ex: ex, exIdx: exIdx)
        // Compute live top set: heaviest logged weight among logged sets in this exercise
        let loggedWeights = ex.sets.compactMap { $0.isLogged ? $0.loggedWeight : nil }
        let maxLoggedWeight = loggedWeights.max() ?? 0
        let isLiveTopSet = liveSet.isLogged
            && (liveSet.loggedWeight ?? 0) == maxLoggedWeight
            && maxLoggedWeight > 0
        return SetLogRow(
            set: $session.exercises[exIdx].sets[setIdx],
            setNumber: setIdx + 1,
            isMainLift: ex.isMainLift,
            isBackoff: backoff,
            targetRepsLow: ex.targetRepsLow,
            targetRepsHigh: ex.targetRepsHigh,
            useMetric: useMetric,
            isLiveTopSet: isLiveTopSet,
            onRemove: removeBlock,
            onComplete: completeBlock
        )
    }

    private func removeSetAction(exIdx: Int, setIdx: Int) -> () -> Void {
        return {
            withAnimation { _ = session.exercises[exIdx].sets.remove(at: setIdx) }
        }
    }

    private func completeSetAction(ex: LiveExercise, exIdx: Int) -> () -> Void {
        return {
            startRest(seconds: ex.restSeconds)
            let allDone = session.exercises[exIdx].sets.allSatisfy { $0.isLogged || $0.isSkipped }
            if allDone && layoutMode == .card && exIdx < session.exercises.count - 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    withAnimation { currentExerciseIndex = exIdx + 1 }
                }
            }
        }
    }

    // ── Exercise reorder / remove ────────────────────────────────────────

    private func moveExercise(from index: Int, direction: Int) {
        let newIndex = index + direction
        guard newIndex >= 0, newIndex < session.exercises.count else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            session.exercises.swapAt(index, newIndex)
            if layoutMode == .card { currentExerciseIndex = newIndex }
        }
    }

    private func toggleSuperset(at index: Int) {
        guard index < session.exercises.count - 1 else { return }
        let current = session.exercises[index].supersetGroupId
        if let ssid = current, !ssid.isEmpty {
            // Remove superset pairing
            session.exercises[index].supersetGroupId = nil
            // Also remove from partner if it matches
            if session.exercises[index + 1].supersetGroupId == ssid {
                session.exercises[index + 1].supersetGroupId = nil
            }
        } else {
            // Create superset pair with next exercise
            let groupId = "ss_\(index)"
            session.exercises[index].supersetGroupId = groupId
            session.exercises[index + 1].supersetGroupId = groupId
        }
        session.objectWillChange.send()
    }

    private func removeExercise(at index: Int) {
        guard session.exercises.count > 1 else { return }
        withAnimation {
            _ = session.exercises.remove(at: index)
            if currentExerciseIndex >= session.exercises.count {
                currentExerciseIndex = max(0, session.exercises.count - 1)
            }
        }
    }

    // ── Timers ─────────────────────────────────────────────────────────────

    private var elapsedFormatted: String {
        String(format: "%d:%02d", elapsedSeconds / 60, elapsedSeconds % 60)
    }
    private func startElapsed() {
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in elapsedSeconds += 1 }
    }
    private func startRest(seconds: Int) {
        restTimer?.invalidate()
        restTotal = seconds
        restSecondsRemaining = seconds
        withAnimation { showingRestTimer = true }
        restTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
            if restSecondsRemaining > 0 { restSecondsRemaining -= 1 }
            else { t.invalidate(); withAnimation { showingRestTimer = false } }
        }
    }
    private func cancelRest() { restTimer?.invalidate(); withAnimation { showingRestTimer = false } }
    private func restLabel(_ s: Int) -> String {
        s < 60 ? "\(s)s" : (s % 60 == 0 ? "\(s/60)m" : "\(s/60)m\(s%60)s")
    }

    private func applyMidWorkoutSwap(idx: Int, newKey: String) {
        let old = session.exercises[idx]
        let newName = allExercises.first(where: { $0.exerciseKey == newKey })?.displayName ?? newKey
        let newSets = old.sets.map { s in
            LiveSet(setIndex: s.setIndex, recommendedWeight: s.recommendedWeight, recommendedReps: s.recommendedReps)
        }
        let swapTier: ExerciseTier = {
            let def = ExerciseDictionary.all[newKey]
            if def?.isAnchorableAsTier1 == true { return .tier1 }
            if def?.isCompound == true { return .tier2 }
            return .tier3
        }()
        session.exercises[idx] = LiveExercise(
            exerciseKey: newKey,
            displayName: newName,
            slotId: old.slotId,
            role: old.role,
            exerciseTier: swapTier,
            targetSets: old.targetSets,
            targetRepsLow: old.targetRepsLow,
            targetRepsHigh: old.targetRepsHigh,
            targetRPE: old.targetRPE,
            restSeconds: old.restSeconds,
            notes: "",
            sets: newSets
        )
        showInWorkoutSwap = false
        swapExerciseIndex = nil
    }
}

// ═══════════════════════════════════════════
// FREESTYLE SWAP SHEET (no instance — no persistence)
// Used when swapping mid-workout in freestyle/no-program mode
// ═══════════════════════════════════════════

struct FreestyleSwapSheet: View {
    let slot: SwapTarget
    let allExercises: [Exercise]
    let onDismiss: () -> Void
    let onSwap: (String) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var selectedKey: String? = nil
    @State private var showCreateCustom = false
    @State private var cachedRanked: [RankedAlternative]? = nil

    private var ranked: [RankedAlternative] {
        cachedRanked ?? []
    }

    private func computeRanked() {
        cachedRanked = allExercises
            .filter { $0.exerciseKey != slot.exerciseKey }
            .compactMap { ex -> RankedAlternative? in
                let score = similarityScore(ex)
                guard score > 0 else { return nil }
                return RankedAlternative(exercise: ex, score: score)
            }
            .sorted { $0.score > $1.score }
    }

    private var filtered: [RankedAlternative] {
        // When searching, ignore muscle scoping and search the full library
        if !searchText.isEmpty {
            let tokens = searchText.lowercased()
                .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            return allExercises
                .filter { $0.exerciseKey != slot.exerciseKey }
                .filter { ex in
                    let haystack = ([ex.displayName] + ex.musclesPrimary + ex.musclesSecondary + [ex.equipmentRaw])
                        .joined(separator: " ").lowercased()
                    return tokens.allSatisfy { haystack.contains($0) }
                }
                .map { RankedAlternative(exercise: $0, score: 50) }
                .sorted { $0.exercise.displayName < $1.exercise.displayName }
        }
        return slot.musclesPrimary.isEmpty
            ? allExercises.filter { $0.exerciseKey != slot.exerciseKey }
                .map { RankedAlternative(exercise: $0, score: 50) }
                .sorted { $0.exercise.displayName < $1.exercise.displayName }
            : ranked
    }

    private var smartPicks: [RankedAlternative] {
        guard !slot.musclesPrimary.isEmpty && searchText.isEmpty else { return [] }
        return Array(filtered.prefix(4))
    }

    private var morePicks: [RankedAlternative] {
        guard !slot.musclesPrimary.isEmpty && searchText.isEmpty else { return filtered }
        return filtered.count > 4 ? Array(filtered.dropFirst(4)) : []
    }

    var body: some View {
        ZStack {
            Color.appBG.ignoresSafeArea()
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 3).fill(Color.appBorder)
                    .frame(width: 36, height: 4).padding(.top, 12)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SWAP EXERCISE")
                            .font(.system(size: 11, weight: .bold)).foregroundColor(.appRed).kerning(2)
                        Text(slot.displayName)
                            .font(.system(size: 20, weight: .black, design: .rounded)).foregroundColor(.appTextPrimary)
                        if !slot.muscleLabel.isEmpty {
                            Text(slot.muscleLabel)
                                .font(.system(size: 12)).foregroundColor(.appTextSecondary)
                        }
                    }
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold)).foregroundColor(.appTextSecondary)
                            .frame(width: 32, height: 32).background(Color.appSurface2).clipShape(Circle())
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(Color.appSurface)
                .overlay(Rectangle().frame(height: 1).foregroundColor(.appBorder), alignment: .bottom)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundColor(.appTextDim)
                    TextField("Search by name, muscle, or equipment...", text: $searchText)
                        .font(.system(size: 15)).foregroundColor(.appTextPrimary)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.appTextDim)
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(Color.appSurface2)
                .overlay(Rectangle().frame(height: 1).foregroundColor(.appBorder), alignment: .bottom)

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 16) {
                        Button(action: { showCreateCustom = true }) {
                            HStack(spacing: 10) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8).fill(Color.appRed.opacity(0.12)).frame(width: 36, height: 36)
                                    Image(systemName: "plus").font(.system(size: 16, weight: .bold)).foregroundColor(.appRed)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Create Custom Exercise")
                                        .font(.system(size: 14, weight: .bold)).foregroundColor(.appTextPrimary)
                                    Text("Not in the library? Add your own")
                                        .font(.system(size: 11)).foregroundColor(.appTextDim)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundColor(.appTextDim)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(Color.appSurface).cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appRed.opacity(0.25), lineWidth: 1))
                        }
                        .buttonStyle(.plain).padding(.horizontal, 16)

                        if !smartPicks.isEmpty {
                            VStack(spacing: 8) {
                                SectionHeader(title: "BEST MATCHES").padding(.horizontal, 16)
                                ForEach(smartPicks) { alt in
                                    AlternativeRow(alt: alt, isSelected: selectedKey == alt.exercise.exerciseKey,
                                        onSelect: { selectedKey = alt.exercise.exerciseKey }).padding(.horizontal, 16)
                                }
                            }
                        }
                        if !morePicks.isEmpty {
                            VStack(spacing: 8) {
                                SectionHeader(title: smartPicks.isEmpty ? "ALL EXERCISES" : "MORE OPTIONS").padding(.horizontal, 16)
                                let picks = smartPicks.isEmpty ? filtered : morePicks
                                ForEach(picks) { alt in
                                    AlternativeRow(alt: alt, isSelected: selectedKey == alt.exercise.exerciseKey,
                                        onSelect: { selectedKey = alt.exercise.exerciseKey }).padding(.horizontal, 16)
                                }
                            }
                        }
                        if filtered.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "magnifyingglass").font(.system(size: 28)).foregroundColor(.appTextDim)
                                Text(searchText.isEmpty ? "No exercises available" : "No matches for \"\(searchText)\"")
                                    .font(.system(size: 14)).foregroundColor(.appTextSecondary)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 40)
                        }
                    }
                    .padding(.vertical, 16).padding(.bottom, 100)
                }

                VStack(spacing: 0) {
                    Divider().background(Color.appBorder)
                    PrimaryButton(
                        title: selectedKey != nil ? "APPLY SWAP" : "SELECT AN EXERCISE",
                        icon: "arrow.triangle.2.circlepath"
                    ) {
                        guard let key = selectedKey else { return }
                        onSwap(key)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14).background(Color.appBG)
                    .disabled(selectedKey == nil).opacity(selectedKey != nil ? 1.0 : 0.5)
                }
            }
        }
        .sheet(isPresented: $showCreateCustom) {
            CreateCustomExerciseSheet(modelContext: modelContext) { newKey in
                selectedKey = newKey
                showCreateCustom = false
            }
        }
        .onAppear { if cachedRanked == nil { computeRanked() } }
    }

    private func similarityScore(_ ex: Exercise) -> Int {
        guard !slot.musclesPrimary.isEmpty else { return 50 }

        let slotDef = ExerciseDictionary.all[slot.exerciseKey]
        let candDef = ExerciseDictionary.all[ex.exerciseKey]

        // Dictionary swap list
        if let sDef = slotDef, let idx = sDef.swapKeys.firstIndex(of: ex.exerciseKey) {
            return max(100 - idx * 10, 30)
        }

        var score = 0
        let slotPriNorm = slot.musclesPrimary.compactMap { ExerciseDictionary.normalizeMuscle($0) }
        let exPriNorm = ex.musclesPrimary.compactMap { ExerciseDictionary.normalizeMuscle($0) }
        let normalizedMatch = !Set(slotPriNorm).intersection(Set(exPriNorm)).isEmpty
        let samePrimary = ex.musclesPrimary.contains(where: { slot.musclesPrimary.contains($0) })
        let anyMatch = samePrimary || ex.musclesSecondary.contains(where: { slot.musclesPrimary.contains($0) })

        guard anyMatch || normalizedMatch else { return 0 }
        score += (samePrimary || normalizedMatch) ? 50 : 20

        if let sDef = slotDef, let cDef = candDef, sDef.swapPattern == cDef.swapPattern { score += 30 }
        else if ex.movementPatternRaw == slot.movementPattern { score += 30 }
        if ex.equipmentRaw == slot.equipment { score += 10 }
        if ex.isCompound == slot.isCompound { score += 10 }
        if let sDef = slotDef, let cDef = candDef, sDef.stretchPosition == cDef.stretchPosition { score += 15 }

        return score
    }
}

// ═══════════════════════════════════════════
// EXERCISE ROW (used in add sheet)
// ═══════════════════════════════════════════

struct InWorkoutExerciseRow: View {
    let exercise: Exercise
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(isSelected ? Color.appRed : Color.appBorder, lineWidth: 2).frame(width: 22, height: 22)
                    if isSelected { Circle().fill(Color.appRed).frame(width: 12, height: 12) }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.displayName)
                        .font(.system(size: 14, weight: .bold)).foregroundColor(.appTextPrimary)
                    HStack(spacing: 6) {
                        Text(exercise.musclesPrimary.prefix(2).joined(separator: " · "))
                            .font(.system(size: 11)).foregroundColor(.appTextSecondary)
                        if exercise.isCompound {
                            Text("·").foregroundColor(.appTextDim)
                            Text("compound").font(.system(size: 11)).foregroundColor(.appTextDim)
                        }
                    }
                }
                Spacer()
                Text(exercise.equipmentRaw.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.system(size: 10)).foregroundColor(.appTextDim)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(isSelected ? Color.appRed.opacity(0.06) : Color.appSurface)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.appRed.opacity(0.4) : Color.appBorder, lineWidth: isSelected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }
}

// ═══════════════════════════════════════════
// ADD EXERCISE SHEET (used in freestyle + all workouts)
// ═══════════════════════════════════════════

struct InWorkoutAddSheet: View {
    let allExercises: [Exercise]
    let onAdd: (Exercise) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var selectedExercise: Exercise? = nil
    @State private var selectedMuscle: String? = nil
    @State private var showCreateCustom = false

    private let muscles = ExerciseDictionary.trackingMuscles

    private var filtered: [Exercise] {
        // When searching, search the full library and ignore muscle filter
        if !searchText.isEmpty {
            let tokens = searchText.lowercased()
                .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            return allExercises
                .filter { ex in
                    let haystack = ([ex.displayName] + ex.musclesPrimary + ex.musclesSecondary + [ex.equipmentRaw])
                        .joined(separator: " ").lowercased()
                    return tokens.allSatisfy { haystack.contains($0) }
                }
                .sorted { $0.displayName < $1.displayName }
        }
        var result = allExercises.sorted { $0.displayName < $1.displayName }
        if let muscle = selectedMuscle {
            result = result.filter { ex in
                let priNorm = ex.musclesPrimary.compactMap { ExerciseDictionary.normalizeMuscle($0) }
                let secNorm = ex.musclesSecondary.compactMap { ExerciseDictionary.normalizeMuscle($0) }
                let def = ExerciseDictionary.all[ex.exerciseKey]
                let addlNorm = (def?.additionalFilterMuscles ?? []).compactMap { ExerciseDictionary.normalizeMuscle($0) }
                return priNorm.contains(muscle) || secNorm.contains(muscle) || addlNorm.contains(muscle)
            }
        }
        return result
    }

    var body: some View {
        ZStack {
            Color.appBG.ignoresSafeArea()
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 3).fill(Color.appBorder)
                    .frame(width: 36, height: 4).padding(.top, 12)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ADD EXERCISE")
                            .font(.system(size: 11, weight: .bold)).foregroundColor(.appRed).kerning(2)
                        Text("Choose from library")
                            .font(.system(size: 18, weight: .black, design: .rounded)).foregroundColor(.appTextPrimary)
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

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundColor(.appTextDim)
                    TextField("Search exercises...", text: $searchText)
                        .font(.system(size: 15)).foregroundColor(.appTextPrimary)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.appTextDim)
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(Color.appSurface2)
                .overlay(Rectangle().frame(height: 1).foregroundColor(.appBorder), alignment: .bottom)

                // Muscle filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Button { selectedMuscle = nil } label: {
                            Text("All").font(.system(size: 11, weight: selectedMuscle == nil ? .black : .medium))
                                .foregroundColor(selectedMuscle == nil ? .white : .appTextSecondary)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(selectedMuscle == nil ? Color.appRed : Color.appSurface2).cornerRadius(6)
                        }.buttonStyle(.plain)
                        ForEach(muscles, id: \.self) { m in
                            Button { selectedMuscle = selectedMuscle == m ? nil : m } label: {
                                Text(m).font(.system(size: 11, weight: selectedMuscle == m ? .black : .medium))
                                    .foregroundColor(selectedMuscle == m ? .white : .appTextSecondary)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(selectedMuscle == m ? Color.appRed : Color.appSurface2).cornerRadius(6)
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                }
                .background(Color.appSurface)
                .overlay(Rectangle().frame(height: 1).foregroundColor(.appBorder), alignment: .bottom)

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        // Create custom exercise button
                        Button(action: { showCreateCustom = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill").font(.system(size: 16)).foregroundColor(.appGreen)
                                Text("Create Custom Exercise").font(.system(size: 14, weight: .bold)).foregroundColor(.appGreen)
                                Spacer()
                            }
                            .padding(12).background(Color.appGreen.opacity(0.06)).cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appGreen.opacity(0.15), lineWidth: 1))
                        }.buttonStyle(.plain)

                        ForEach(filtered) { ex in
                            InWorkoutExerciseRow(
                                exercise: ex,
                                isSelected: selectedExercise?.exerciseKey == ex.exerciseKey,
                                onSelect: { selectedExercise = ex }
                            ).padding(.horizontal, 16)
                        }
                        if filtered.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "magnifyingglass").font(.system(size: 28)).foregroundColor(.appTextDim)
                                Text("No matches for \"\(searchText)\"")
                                    .font(.system(size: 14)).foregroundColor(.appTextSecondary)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 40)
                        }
                    }
                    .padding(.vertical, 16).padding(.bottom, 100)
                }

                VStack(spacing: 0) {
                    Divider().background(Color.appBorder)
                    PrimaryButton(
                        title: selectedExercise != nil ? "ADD \(selectedExercise!.displayName.uppercased())" : "SELECT AN EXERCISE",
                        icon: "plus.circle.fill"
                    ) {
                        guard let ex = selectedExercise else { return }
                        onAdd(ex)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14).background(Color.appBG)
                    .disabled(selectedExercise == nil).opacity(selectedExercise != nil ? 1.0 : 0.5)
                }
            }
        }
        .sheet(isPresented: $showCreateCustom) {
            CreateCustomExerciseSheet(modelContext: modelContext) { newKey in
                if let ex = allExercises.first(where: { $0.exerciseKey == newKey }) {
                    selectedExercise = ex
                }
                showCreateCustom = false
            }
        }
    }
}

// ═══════════════════════════════════════════
// EXERCISE CONFIG SHEET (mid-workout edit)
// ═══════════════════════════════════════════

struct ExerciseConfigSheet: View {
    @Binding var exercise: LiveExercise
    let showRPE: Bool
    let showRepRange: Bool
    let showRestTimer: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 3).fill(Color.appBorder).frame(width: 36, height: 4).padding(.top, 12)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CONFIGURE").font(.system(size: 10, weight: .black)).foregroundColor(.appRed).kerning(2)
                    Text(exercise.displayName)
                        .font(.system(size: 18, weight: .black, design: .rounded)).foregroundColor(.appTextPrimary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .font(.system(size: 14, weight: .bold)).foregroundColor(.appRed)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)

            ScrollView {
                VStack(spacing: 20) {
                    // Rep Range
                    VStack(alignment: .leading, spacing: 10) {
                        Text("REP RANGE").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(1)
                        HStack(spacing: 16) {
                            VStack(spacing: 4) {
                                Text("LOW").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim)
                                HStack(spacing: 8) {
                                    Button { if exercise.targetRepsLow > 1 { exercise.targetRepsLow -= 1 } } label: {
                                        Image(systemName: "minus").font(.system(size: 12, weight: .bold)).foregroundColor(.appTextDim)
                                            .frame(width: 36, height: 36).contentShape(Rectangle()).background(Color.appSurface2).cornerRadius(8)
                                    }.buttonStyle(.plain)
                                    Text("\(exercise.targetRepsLow)")
                                        .font(.system(size: 22, weight: .black, design: .rounded)).foregroundColor(.appTextPrimary)
                                        .frame(width: 36)
                                    Button { if exercise.targetRepsLow < exercise.targetRepsHigh { exercise.targetRepsLow += 1 } } label: {
                                        Image(systemName: "plus").font(.system(size: 12, weight: .bold)).foregroundColor(.appTextDim)
                                            .frame(width: 36, height: 36).contentShape(Rectangle()).background(Color.appSurface2).cornerRadius(8)
                                    }.buttonStyle(.plain)
                                }
                            }
                            Text("–").font(.system(size: 20, weight: .bold)).foregroundColor(.appTextDim)
                            VStack(spacing: 4) {
                                Text("HIGH").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim)
                                HStack(spacing: 8) {
                                    Button { if exercise.targetRepsHigh > exercise.targetRepsLow { exercise.targetRepsHigh -= 1 } } label: {
                                        Image(systemName: "minus").font(.system(size: 12, weight: .bold)).foregroundColor(.appTextDim)
                                            .frame(width: 36, height: 36).contentShape(Rectangle()).background(Color.appSurface2).cornerRadius(8)
                                    }.buttonStyle(.plain)
                                    Text("\(exercise.targetRepsHigh)")
                                        .font(.system(size: 22, weight: .black, design: .rounded)).foregroundColor(.appTextPrimary)
                                        .frame(width: 36)
                                    Button { if exercise.targetRepsHigh < 30 { exercise.targetRepsHigh += 1 } } label: {
                                        Image(systemName: "plus").font(.system(size: 12, weight: .bold)).foregroundColor(.appTextDim)
                                            .frame(width: 36, height: 36).contentShape(Rectangle()).background(Color.appSurface2).cornerRadius(8)
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(16).background(Color.appSurface).cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))

                    // RPE
                    VStack(alignment: .leading, spacing: 10) {
                        Text("TARGET RPE").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(1)
                        HStack(spacing: 12) {
                            Button { if exercise.targetRPE > 5.0 { exercise.targetRPE -= 0.5 } } label: {
                                Image(systemName: "minus").font(.system(size: 12, weight: .bold)).foregroundColor(.appTextDim)
                                    .frame(width: 36, height: 36).contentShape(Rectangle()).background(Color.appSurface2).cornerRadius(8)
                            }.buttonStyle(.plain)
                            Text(String(format: "%.1f", exercise.targetRPE))
                                .font(.system(size: 28, weight: .black, design: .rounded)).foregroundColor(.appTextPrimary)
                                .frame(width: 60)
                            Button { if exercise.targetRPE < 10.0 { exercise.targetRPE += 0.5 } } label: {
                                Image(systemName: "plus").font(.system(size: 12, weight: .bold)).foregroundColor(.appTextDim)
                                    .frame(width: 36, height: 36).contentShape(Rectangle()).background(Color.appSurface2).cornerRadius(8)
                            }.buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity)
                        Text(rpeDescription(exercise.targetRPE))
                            .font(.system(size: 11)).foregroundColor(.appTextDim)
                    }
                    .padding(16).background(Color.appSurface).cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))

                    // Rest Time
                    VStack(alignment: .leading, spacing: 10) {
                        Text("REST TIME").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(1)
                        HStack(spacing: 12) {
                            Button { if exercise.restSeconds > 15 { exercise.restSeconds -= 15 } } label: {
                                Image(systemName: "minus").font(.system(size: 12, weight: .bold)).foregroundColor(.appTextDim)
                                    .frame(width: 36, height: 36).contentShape(Rectangle()).background(Color.appSurface2).cornerRadius(8)
                            }.buttonStyle(.plain)
                            Text(restFormatted(exercise.restSeconds))
                                .font(.system(size: 28, weight: .black, design: .rounded)).foregroundColor(.appTextPrimary)
                                .frame(width: 80)
                            Button { if exercise.restSeconds < 600 { exercise.restSeconds += 15 } } label: {
                                Image(systemName: "plus").font(.system(size: 12, weight: .bold)).foregroundColor(.appTextDim)
                                    .frame(width: 36, height: 36).contentShape(Rectangle()).background(Color.appSurface2).cornerRadius(8)
                            }.buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(16).background(Color.appSurface).cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
            }
        }
        .background(Color.appBG)
    }

    private func rpeDescription(_ rpe: Double) -> String {
        switch rpe {
        case ...6.0: return "Light effort — could do 4+ more reps"
        case 6.5...7.5: return "Moderate — 2-3 reps in reserve"
        case 8.0...8.5: return "Hard — 1-2 reps in reserve"
        case 9.0...9.5: return "Very hard — 0-1 reps in reserve"
        default: return "Maximum effort — nothing left"
        }
    }

    private func restFormatted(_ seconds: Int) -> String {
        if seconds >= 60 {
            let min = seconds / 60
            let sec = seconds % 60
            return sec > 0 ? "\(min):\(String(format: "%02d", sec))" : "\(min):00"
        }
        return "\(seconds)s"
    }
}

// ═══════════════════════════════════════════
// REST TIMER BANNER
// ═══════════════════════════════════════════

struct RestTimerBanner: View {
    let secondsRemaining: Int
    let total: Int
    let onSkip: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Color.appBorder, lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: total > 0 ? 1.0 - Double(secondsRemaining) / Double(total) : 0)
                    .stroke(Color.appRed, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: secondsRemaining)
                Text("\(secondsRemaining)").font(.system(size: 13, weight: .black, design: .monospaced)).foregroundColor(.appRed)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("REST").font(.system(size: 11, weight: .black)).foregroundColor(.appTextPrimary).kerning(1.5)
                Text(secondsRemaining > 0 ? "Next set in \(secondsRemaining)s" : "Rest complete — load the bar")
                    .font(.system(size: 12)).foregroundColor(.appTextSecondary)
            }
            Spacer()
            Button(action: onSkip) {
                Text("SKIP").font(.system(size: 11, weight: .black)).foregroundColor(.appTextDim)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.appSurface2).cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color.appSurface)
        .overlay(Rectangle().frame(height: 1).foregroundColor(.appRed.opacity(0.3)), alignment: .bottom)
    }
}

// ═══════════════════════════════════════════
// SET LOG ROW
// ═══════════════════════════════════════════

struct SetLogRow: View {
    @Binding var set: LiveSet
    let setNumber: Int
    let isMainLift: Bool
    let isBackoff: Bool
    let targetRepsLow: Int
    let targetRepsHigh: Int
    let useMetric: Bool
    var isLiveTopSet: Bool = false
    let onRemove: (() -> Void)?
    let onComplete: () -> Void

    @State private var weightInput: String = ""
    @State private var repsInput: String = ""
    @State private var rpeInput: String = ""
    @State private var showRPE: Bool = false
    @State private var showBackoffInfo: Bool = false
    private var hitTarget: Bool { (set.loggedReps ?? 0) >= targetRepsHigh }
    private var loggedE1RM: Double? {
        guard let w = set.loggedWeight, let r = set.loggedReps, r > 0 else { return nil }
        return w * (1.0 + Double(r) / 30.0)
    }

    /// Display "10" or "10-12" depending on whether a rep range is set
    private var recommendedRepsDisplay: String {
        if let high = set.recommendedRepsHigh, high > set.recommendedReps {
            return "\(set.recommendedReps)-\(high)"
        }
        return "\(set.recommendedReps)"
    }

    @ViewBuilder
    private var roleBadge: some View {
        if isLiveTopSet {
            // Live: show TOP SET only when this set IS the heaviest logged
            HStack(spacing: 3) {
                Image(systemName: "star.fill").font(.system(size: 7))
                Text("TOP SET").font(.system(size: 8, weight: .black))
            }
            .foregroundColor(.appGold).kerning(0.5)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Color.appGold.opacity(0.12)).cornerRadius(3)
        } else if let role = set.role {
            switch role {
            case .topSet:
                EmptyView()  // Suppress pre-assigned top set; computed live above
            case .feeder:
                Text("FEEDER").font(.system(size: 8, weight: .black)).foregroundColor(.appBlue).kerning(0.5)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.appBlue.opacity(0.12)).cornerRadius(3)
            case .backoff:
                Button(action: { showBackoffInfo = true }) {
                    HStack(spacing: 3) {
                        Text("BACKOFF").font(.system(size: 8, weight: .black)).foregroundColor(.appTextDim)
                        Image(systemName: "info.circle").font(.system(size: 8)).foregroundColor(.appTextDim)
                    }
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(Color.appSurface2).cornerRadius(3)
                }.buttonStyle(.plain)
            case .primary:
                EmptyView()  // no badge for plain straight sets
            }
        } else if isBackoff {
            // Legacy fallback (no role populated but detected as backoff via weight comparison)
            Button(action: { showBackoffInfo = true }) {
                HStack(spacing: 3) {
                    Text("BACKOFF").font(.system(size: 8, weight: .black)).foregroundColor(.appTextDim)
                    Image(systemName: "info.circle").font(.system(size: 8)).foregroundColor(.appTextDim)
                }
                .padding(.horizontal, 4).padding(.vertical, 2)
                .background(Color.appSurface2).cornerRadius(3)
            }.buttonStyle(.plain)
        }
    }

    @State private var swipeOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .trailing) {
            // Subtle delete hint on swipe
            if onRemove != nil && swipeOffset < -20 {
                HStack {
                    Spacer()
                    Image(systemName: "trash.fill")
                        .font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                        .frame(width: 60).frame(maxHeight: .infinity)
                }
                .background(Color.appRed.opacity(min(1, Double(abs(swipeOffset)) / 80.0)))
                .cornerRadius(12)
            }

            setContent
                .offset(x: swipeOffset)
                .gesture(
                    DragGesture(minimumDistance: onRemove != nil ? 30 : .infinity)
                        .onChanged { value in
                            if value.translation.width < 0 {
                                swipeOffset = max(value.translation.width, -80)
                            }
                        }
                        .onEnded { value in
                            withAnimation(.easeOut(duration: 0.2)) {
                                if value.translation.width < -60 {
                                    onRemove?()
                                }
                                swipeOffset = 0
                            }
                        }
                )
        }
        .clipped()
    }

    private var setContent: some View {
        VStack(spacing: 0) {
            // Set header
            HStack {
                HStack(spacing: 6) {
                    Text("SET \(setNumber)")
                        .font(.system(size: 10, weight: .black)).kerning(1)
                        .foregroundColor(set.isLogged ? .appGreen : .appTextDim)
                    roleBadge
                }
                Spacer()
                if !set.isLogged && set.recommendedWeight > 0 {
                    Button(action: {
                        weightInput = String(format: "%.0f", set.recommendedWeight)
                        repsInput = "\(set.recommendedReps)"
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.to.line").font(.system(size: 9, weight: .bold))
                            Text("\(String(format: "%.0f", set.recommendedWeight)) \(useMetric ? "kg" : "lbs") × \(recommendedRepsDisplay)")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(.appBlue)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.appBlue.opacity(0.08)).cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).padding(.top, 12)

            if set.isLogged {
                // Logged state — clean summary with e1RM
                VStack(spacing: 6) {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.appGreen)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(String(format: "%.0f", set.loggedWeight ?? 0)) \(useMetric ? "kg" : "lbs") × \(set.loggedReps ?? 0) reps")
                                .font(.system(size: 16, weight: .black, design: .rounded)).foregroundColor(.appTextPrimary)
                            HStack(spacing: 8) {
                                if let e1rm = loggedE1RM {
                                    Text("e1RM \(String(format: "%.0f", e1rm))")
                                        .font(.system(size: 11, weight: .bold)).foregroundColor(.appGold)
                                }
                                if let rpe = set.loggedRPE, rpe > 0 {
                                    Text("RPE \(String(format: "%.1f", rpe))")
                                        .font(.system(size: 11, weight: .bold)).foregroundColor(.appTextDim)
                                }
                                if let time = set.completedAt {
                                    Text(timeLabel(time))
                                        .font(.system(size: 10)).foregroundColor(.appTextDim)
                                }
                            }
                        }
                        Spacer()
                        Button(action: { set.loggedWeight = nil; set.loggedReps = nil; set.loggedRPE = nil; set.completedAt = nil }) {
                            Image(systemName: "pencil.circle")
                                .font(.system(size: 18)).foregroundColor(.appTextDim)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
            } else if set.isSkipped {
                HStack {
                    Text("Skipped").font(.system(size: 13, weight: .bold)).foregroundColor(.appTextDim)
                    Spacer()
                    Button(action: { set.isSkipped = false }) {
                        Text("Undo").font(.system(size: 11, weight: .bold)).foregroundColor(.appBlue)
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
            } else {
                // Input fields
                HStack(spacing: 8) {
                    VStack(spacing: 4) {
                        Text(useMetric ? "KG" : "LBS").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim).kerning(1)
                        TextField("0", text: $weightInput)
                            .font(.system(size: 20, weight: .black, design: .rounded)).foregroundColor(.appTextPrimary)
                            .keyboardType(.decimalPad).multilineTextAlignment(.center)
                            .frame(height: 48).background(Color.appSurface2).cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))
                    }
                    .frame(maxWidth: .infinity)

                    Text("×").font(.system(size: 22, weight: .black)).foregroundColor(.appTextDim)

                    VStack(spacing: 4) {
                        Text("REPS").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim).kerning(1)
                        TextField("0", text: $repsInput)
                            .font(.system(size: 20, weight: .black, design: .rounded)).foregroundColor(.appTextPrimary)
                            .keyboardType(.numberPad).multilineTextAlignment(.center)
                            .frame(height: 48).background(Color.appSurface2).cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))
                    }
                    .frame(maxWidth: .infinity)

                    if showRPE {
                        VStack(spacing: 4) {
                            Text("RPE").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim).kerning(1)
                            TextField("8", text: $rpeInput)
                                .font(.system(size: 20, weight: .black, design: .rounded)).foregroundColor(.appTextPrimary)
                                .keyboardType(.decimalPad).multilineTextAlignment(.center)
                                .frame(height: 48).background(Color.appSurface2).cornerRadius(10)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))
                        }
                        .frame(width: 68)
                    }

                    Button(action: logSet) {
                        Image(systemName: "checkmark").font(.system(size: 18, weight: .black)).foregroundColor(.white)
                            .frame(width: 48, height: 48)
                            .background(canLog ? Color.appRed : Color.appSurface2).cornerRadius(10)
                    }
                    .buttonStyle(.plain).disabled(!canLog)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)

                HStack {
                    Button(action: { withAnimation { showRPE.toggle() } }) {
                        HStack(spacing: 4) {
                            Image(systemName: showRPE ? "minus" : "plus").font(.system(size: 9, weight: .bold))
                            Text("RPE").font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(.appTextDim)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button(action: { set.isSkipped = true }) {
                        Text("Skip set").font(.system(size: 11, weight: .bold)).foregroundColor(.appTextDim)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14).padding(.bottom, 10)
            }
        }
        .background(set.isLogged ? Color.appGreen.opacity(0.06) :
                    (set.isSkipped ? Color.appSurface2.opacity(0.5) : Color.appSurface))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(
            set.isLogged ? Color.appGreen.opacity(0.3) : Color.appBorder, lineWidth: 1))
        .onAppear {
            if weightInput.isEmpty && set.recommendedWeight > 0 { weightInput = String(format: "%.0f", set.recommendedWeight) }
            if repsInput.isEmpty { repsInput = "\(set.recommendedReps)" }
        }
        .alert("Backoff Set", isPresented: $showBackoffInfo) {
            Button("Got it", role: .cancel) {}
        } message: {
            Text("This is a backoff set — the weight is reduced to ~92% of your top set. Backoff sets add volume at a manageable load to drive hypertrophy without excessive fatigue. Focus on controlled reps and a strong mind-muscle connection.")
        }
    }

    private var canLog: Bool { Double(weightInput) != nil && Int(repsInput) != nil }
    private func logSet() {
        guard let w = Double(weightInput), let r = Int(repsInput) else { return }
        set.loggedWeight = w; set.loggedReps = r; set.loggedRPE = Double(rpeInput)
        set.completedAt = Date()
        // UI-1: Haptic feedback on set completion
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onComplete()
    }
    private func timeLabel(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f.string(from: date)
    }
}

// ═══════════════════════════════════════════
// WORKOUT COMPLETE VIEW
// ═══════════════════════════════════════════

struct WorkoutCompleteView: View {
    let session: ActiveWorkoutSession
    let exerciseNames: [String: String]
    let useMetric: Bool
    let onFinish: () -> Void

    private var durationLabel: String {
        String(format: "%d:%02d", session.elapsedSeconds / 60, session.elapsedSeconds % 60)
    }

    private var successExercises: [LiveExercise] {
        session.exercises.filter { ex in
            let logged = ex.sets.filter { $0.isLogged }
            return !logged.isEmpty && logged.allSatisfy { ($0.loggedReps ?? 0) >= ex.targetRepsHigh }
        }
    }

    var body: some View {
        ZStack {
            Color.appBG.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle().fill(Color.appRed.opacity(0.12)).frame(width: 90, height: 90)
                            Image(systemName: "checkmark.seal.fill").font(.system(size: 42)).foregroundColor(.appRed)
                        }
                        Text("SESSION COMPLETE")
                            .font(.system(size: 22, weight: .black, design: .rounded)).foregroundColor(.appTextPrimary)
                        Text(session.sessionType == .freeform ? session.sessionLabel : "Week \(session.week) · \(session.sessionLabel)")
                            .font(.system(size: 13)).foregroundColor(.appTextSecondary)
                    }
                    .padding(.top, 40)

                    HStack(spacing: 0) {
                        SummaryStatCell(value: "\(session.totalSetsLogged)", label: "SETS")
                        Rectangle().frame(width: 1, height: 32).foregroundColor(.appBorder)
                        SummaryStatCell(value: durationLabel, label: "TIME")
                        Rectangle().frame(width: 1, height: 32).foregroundColor(.appBorder)
                        SummaryStatCell(value: "\(session.exercises.count)", label: "EXERCISES")
                    }
                    .appCard()

                    if !successExercises.isEmpty {
                        VStack(spacing: 10) {
                            SectionHeader(title: "HIT TARGET REPS ↑ WEIGHT NEXT SESSION")
                            ForEach(successExercises) { ex in
                                HStack(spacing: 10) {
                                    Image(systemName: "bolt.fill").foregroundColor(.appGold).font(.system(size: 14))
                                    Text(ex.displayName).font(.system(size: 14, weight: .bold)).foregroundColor(.appTextPrimary)
                                    Spacer()
                                    let inc = ProgressionEngine.progressionIncrement(
                                        exerciseTier: ex.exerciseTier,
                                        useMetric: useMetric,
                                        currentWeight: ex.sets.first?.recommendedWeight ?? 100)
                                    let unit = useMetric ? "kg" : "lbs"
                                    Text("+\(inc.formatted()) \(unit) next time")
                                        .font(.system(size: 11)).foregroundColor(.appGold)
                                }
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .background(Color.appGold.opacity(0.06)).cornerRadius(10)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appGold.opacity(0.2), lineWidth: 1))
                            }
                        }
                    }

                    VStack(spacing: 10) {
                        SectionHeader(title: "EXERCISE SUMMARY")
                        ForEach(session.exercises) { ex in
                            let logged = ex.sets.filter { $0.isLogged }
                            if !logged.isEmpty {
                                HStack(spacing: 12) {
                                    Text(ex.slotId)
                                        .font(.system(size: 10, weight: .black, design: .monospaced)).foregroundColor(.appRed)
                                        .frame(width: 30, height: 30).background(Color.appRed.opacity(0.1)).cornerRadius(6)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ex.displayName).font(.system(size: 13, weight: .bold)).foregroundColor(.appTextPrimary)
                                        let top = logged.max(by: { ($0.loggedWeight ?? 0) < ($1.loggedWeight ?? 0) })
                                        Text("\(logged.count) sets · top \(String(format: "%.0f", top?.loggedWeight ?? 0)) × \(top?.loggedReps ?? 0)")
                                            .font(.system(size: 11)).foregroundColor(.appTextDim)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 12).padding(.vertical, 10).appCard()
                            }
                        }
                    }

                    PrimaryButton(title: "SAVE & FINISH", icon: "checkmark.circle.fill", action: onFinish)
                        .padding(.bottom, 40)
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

struct SummaryStatCell: View {
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 22, weight: .black, design: .rounded)).foregroundColor(.appRed)
            Text(label).font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim).kerning(1.5)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16)
    }
}

// ═══════════════════════════════════════════
// READINESS PROMPT
// ═══════════════════════════════════════════

struct ReadinessPromptView: View {
    let onSelect: (Int) -> Void
    let onSkip: () -> Void
    @State private var selectedLevel: Int = 0

    private let levels: [(score: Int, label: String, description: String, effect: String, color: Color)] = [
        (1, "Very Low", "Barely slept, sick, injured, extreme stress",
         "Weight -10% · Reps -3 · Volume cut", .appRed),
        (2, "Below Avg", "Poor sleep, high stress, sore",
         "Weight -5% · Reps -1", .appOrange),
        (3, "Normal", "Typical day, nothing unusual",
         "No adjustments", .appTextSecondary),
        (4, "Good", "Well rested, good nutrition",
         "Rep targets +1", .appGreen),
        (5, "Excellent", "Peak recovery, fully fueled",
         "Weight +2% · Rep targets +2", .appGreen),
    ]

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 3).fill(Color.appBorder).frame(width: 36, height: 4).padding(.top, 12)

            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Text("HOW ARE YOU FEELING?").font(.system(size: 12, weight: .black)).foregroundColor(.appRed).kerning(2)
                    Text("This adjusts today's recommendations")
                        .font(.system(size: 12)).foregroundColor(.appTextDim)
                }

                // 5 level buttons
                HStack(spacing: 8) {
                    ForEach(levels, id: \.score) { level in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { selectedLevel = level.score }
                        } label: {
                            VStack(spacing: 4) {
                                Text("\(level.score)")
                                    .font(.system(size: 20, weight: .black, design: .rounded))
                                    .foregroundColor(selectedLevel == level.score ? .white : level.color)
                                Text(level.label)
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(selectedLevel == level.score ? .white.opacity(0.8) : .appTextDim)
                            }
                            .frame(maxWidth: .infinity).frame(height: 60)
                            .background(selectedLevel == level.score ? level.color : Color.appSurface2)
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(
                                selectedLevel == level.score ? level.color : Color.appBorder, lineWidth: 1))
                        }.buttonStyle(.plain)
                    }
                }

                // Description panel (only when selected)
                if selectedLevel > 0, let level = levels.first(where: { $0.score == selectedLevel }) {
                    VStack(spacing: 8) {
                        Text(level.description)
                            .font(.system(size: 13)).foregroundColor(.appTextSecondary)
                        Divider().background(Color.appBorder)
                        HStack(spacing: 4) {
                            Image(systemName: "gearshape.fill").font(.system(size: 10)).foregroundColor(.appTextDim)
                            Text(level.effect)
                                .font(.system(size: 12, weight: .bold)).foregroundColor(.appTextPrimary)
                        }
                    }
                    .padding(14).background(Color.appSurface).cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))
                }

                // Action buttons
                VStack(spacing: 10) {
                    if selectedLevel > 0 {
                        Button {
                            onSelect(selectedLevel)
                        } label: {
                            Text("START WORKOUT")
                                .font(.system(size: 14, weight: .black)).foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(Color.appRed).cornerRadius(12)
                        }.buttonStyle(.plain)
                    }

                    Button {
                        onSkip()
                    } label: {
                        Text("SKIP (defaults to Normal)")
                            .font(.system(size: 12, weight: .bold)).foregroundColor(.appTextDim)
                    }.buttonStyle(.plain)
                }
            }
            .padding(20)

            Spacer()
        }
        .background(Color.appBG)
    }
}

// ═══════════════════════════════════════════
// SESSION DATA MODELS (in-memory)
// ═══════════════════════════════════════════

class ActiveWorkoutSession: ObservableObject, Identifiable {
    let id = UUID()
    let sessionType: SessionType
    let week: Int
    let startedAt: Date
    let isCustom: Bool
    @Published var exercises: [LiveExercise]
    @Published var isComplete: Bool = false
    @Published var notes: String = ""
    @Published var readiness: Int = 0  // 0=not rated, 1-5

    init(sessionType: SessionType, week: Int, exercises: [LiveExercise], isCustom: Bool = false) {
        self.sessionType = sessionType
        self.week = week
        self.startedAt = Date()
        self.isCustom = isCustom
        self.exercises = exercises
    }

    var sessionLabel: String {
        isCustom ? "Custom \(sessionType.shortLabel)" : sessionType.shortLabel
    }
    var totalSetsLogged: Int { exercises.flatMap { $0.sets }.filter { $0.isLogged }.count }
    var totalSets: Int { exercises.flatMap { $0.sets }.count }
    var elapsedSeconds: Int { Int(Date().timeIntervalSince(startedAt)) }
}

struct WarmupSet: Identifiable {
    let id = UUID()
    let weight: Double
    let reps: Int
    let label: String
    var isComplete: Bool = false
}

struct LiveExercise: Identifiable {
    let id = UUID()
    let exerciseKey: String
    let displayName: String
    let slotId: String
    let role: ExerciseRole
    let exerciseTier: ExerciseTier
    let targetSets: Int
    var targetRepsLow: Int
    var targetRepsHigh: Int
    var targetRPE: Double
    var restSeconds: Int
    let notes: String
    var sets: [LiveSet]
    var warmupSets: [WarmupSet] = []
    var supersetGroupId: String? = nil
    var recommendedWeight: Double { sets.first?.recommendedWeight ?? 0 }

    var isMainLift: Bool { exerciseTier == .tier1 }

    var intrasetFatigueIndex: Double? {
        let logged = sets.filter { $0.isLogged }
        guard logged.count >= 2,
              let firstReps = logged.first?.loggedReps, firstReps > 0,
              let lastReps = logged.last?.loggedReps else { return nil }
        return max(0, Double(firstReps - lastReps) / Double(firstReps))
    }

    var allSetsLogged: Bool {
        sets.allSatisfy { $0.isLogged || $0.isSkipped }
    }
}

struct LiveSet: Identifiable {
    let id = UUID()
    let setIndex: Int
    let recommendedWeight: Double
    let recommendedReps: Int
    var recommendedRepsHigh: Int? = nil          // non-nil when displaying a range (e.g., "10-12")
    var role: ProgressionEngine.SetRole? = nil    // top/feeder/backoff/primary (nil = no badge)
    var loggedWeight: Double? = nil
    var loggedReps: Int? = nil
    var loggedRPE: Double? = nil
    var isSkipped: Bool = false
    var completedAt: Date? = nil
    var isLogged: Bool { loggedWeight != nil && loggedReps != nil }
}

// ═══════════════════════════════════════════
// PROGRESSIVE OVERLOAD CARD
// ═══════════════════════════════════════════

struct ProgressiveOverloadCard: View {
    let exerciseKey: String
    let displayName: String
    let exerciseTier: ExerciseTier
    let targetRepsLow: Int
    let targetRepsHigh: Int
    let targetRPE: Double
    let allLogs: [WorkoutLog]
    let useMetric: Bool
    let isExpanded: Bool
    let onToggle: () -> Void
    var progressionState: ProgressionState? = nil

    var isMainLift: Bool { exerciseTier == .tier1 }

    private var historyEnabled: Bool {
        UserDefaults.standard.object(forKey: "historyEnabled_\(exerciseKey)") as? Bool ?? true
    }

    private var exerciseLogs: [WorkoutLog] {
        allLogs.filter { $0.exerciseKey == exerciseKey }.sorted { $0.date > $1.date }
    }

    private var sessions: [[WorkoutLog]] {
        ProgressionEngine.groupBySession(exerciseLogs)
    }

    private var lastSessionWeight: Double? {
        sessions.first?.map({ $0.weight }).max()
    }

    private var recommendation: ProgressionRecommendation {
        ProgressionEngine.recommend(
            recentLogs: exerciseLogs,
            targetRepsLow: targetRepsLow,
            targetRepsHigh: targetRepsHigh,
            targetRPE: targetRPE,
            exerciseTier: exerciseTier,
            useMetric: useMetric,
            progressionState: progressionState
        )
    }

    private var deltaLabel: String {
        // Use the actual top-set weight from the prescription if available
        let topWeight = recommendation.perSetPrescription
            .first(where: { $0.role == .topSet })?.weight
            ?? recommendation.recommendedWeight
        guard let last = lastSessionWeight, topWeight > 0 else { return "" }
        let diff = topWeight - last
        if abs(diff) < 0.1 { return "Same weight as last session" }
        let sign = diff > 0 ? "+" : ""
        return "\(sign)\(Int(diff)) \(useMetric ? "kg" : "lbs") from last session (\(Int(last)))"
    }

    // Top set per session (newest first) — actual weight × reps
    private var sessionTopSets: [(date: Date, weight: Double, reps: Int)] {
        sessions.compactMap { session in
            guard let top = session.max(by: { $0.weight < $1.weight }),
                  let date = session.first?.date else { return nil }
            return (date: date, weight: top.weight, reps: top.reps)
        }
    }

    // e1RM per session for chart
    private var sessionE1RMs: [(date: Date, e1rm: Double)] {
        sessions.compactMap { session in
            guard let best = session.max(by: { $0.e1rm < $1.e1rm }),
                  let date = session.first?.date else { return nil }
            return (date: date, e1rm: best.e1rm)
        }
    }

    private var bestTopSet: (weight: Double, reps: Int) {
        guard let best = sessionTopSets.max(by: { $0.weight < $1.weight }) else { return (0, 0) }
        return (best.weight, best.reps)
    }
    private var lastTopSet: (weight: Double, reps: Int) {
        guard let last = sessionTopSets.first else { return (0, 0) }
        return (last.weight, last.reps)
    }
    private var worstTopSet: (weight: Double, reps: Int) {
        guard let worst = sessionTopSets.min(by: { $0.weight < $1.weight }) else { return (0, 0) }
        return (worst.weight, worst.reps)
    }

    var body: some View {
        if !historyEnabled {
            templateOnlyCard
        } else if exerciseLogs.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 0) {
                summaryRow
                if isExpanded {
                    Divider().background(Color.appBorder)
                    detailPanel
                }
            }
            .background(Color.appSurface)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
        }
    }

    // ── Summary row (always visible) ──
    private var summaryRow: some View {
        // Pull the actual top set from the per-set prescription if available,
        // otherwise fall back to the scalar recommendation.
        let topSetPrescription = recommendation.perSetPrescription
            .first(where: { $0.role == .topSet })
        let displayWeight = topSetPrescription?.weight ?? recommendation.recommendedWeight
        let displayReps: String = {
            if let p = topSetPrescription {
                if p.hasRange, let lo = p.repsRangeLow, let hi = p.repsRangeHigh, hi > lo {
                    return "\(lo)-\(hi)"
                }
                return "\(p.repsTarget)"
            }
            return "\(recommendation.recommendedReps)"
        }()

        return Button(action: onToggle) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("RECOMMENDED TOP SET")
                        .font(.system(size: 9, weight: .black)).foregroundColor(.appTextDim).kerning(1)
                    if displayWeight > 0 {
                        HStack(spacing: 6) {
                            Text("\(String(format: "%.0f", displayWeight))")
                                .font(.system(size: 20, weight: .black, design: .rounded)).foregroundColor(.appRed)
                            Text("\(useMetric ? "kg" : "lbs") × \(displayReps)")
                                .font(.system(size: 12, weight: .bold)).foregroundColor(.appTextDim)
                        }
                    }
                    if !deltaLabel.isEmpty {
                        Text(deltaLabel)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(recommendation.progressionRule == .progress ? .appGreen :
                                            (recommendation.progressionRule == .backoff ? .appRed.opacity(0.8) : .appTextSecondary))
                    }
                }
                Spacer()
                HStack(spacing: 4) {
                    Text("History").font(.system(size: 11, weight: .bold)).foregroundColor(.appTextDim)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold)).foregroundColor(.appTextDim)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    // ── Detail panel (expanded) ──
    private var detailPanel: some View {
        VStack(spacing: 14) {
            // e1RM chart
            if sessionE1RMs.count >= 4 {
                e1rmChart
            } else {
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis").foregroundColor(.appTextDim)
                    Text("Not enough data yet (\(sessionE1RMs.count)/4 sessions)")
                        .font(.system(size: 12)).foregroundColor(.appTextDim)
                }
                .padding(.vertical, 8)
            }

            // Stat pills — actual top sets
            HStack(spacing: 8) {
                topSetPill(label: "BEST", weight: bestTopSet.weight, reps: bestTopSet.reps, color: .appGold)
                topSetPill(label: "LAST", weight: lastTopSet.weight, reps: lastTopSet.reps, color: .appRed)
                topSetPill(label: "WORST", weight: worstTopSet.weight, reps: worstTopSet.reps, color: .appTextDim)
            }

            // Fatigue analysis
            if let lastSession = sessions.first, lastSession.count >= 2 {
                fatigueSection(lastSession: lastSession.sorted { $0.setIndex < $1.setIndex })
            }

            // Stall diagnosis (IFI-enhanced with hysteresis and escalation)
            if recommendation.stallDetected {
                let lastIFI = sessions.first.map { ProgressionEngine.computeIFI(sessionSets: $0) } ?? 0
                let prevDiag = progressionState?.lastStallDiagnosis ?? .noStall
                let diagnosis = ProgressionEngine.diagnoseStallWithIFI(
                    ifiTrend: lastIFI,
                    sessions: sessions,
                    isTier1: exerciseTier == .tier1,
                    previousDiagnosis: prevDiag
                )
                if diagnosis != .noStall {
                    let consecutiveCount = (diagnosis == prevDiag)
                        ? (progressionState?.consecutiveStallDiagnoses ?? 0) + 1
                        : 1
                    let urgency = StallUrgency.from(consecutiveCount: consecutiveCount)
                    let urgencyColor: Color = urgency == .actionRequired ? .appRed : .appOrange

                    HStack(spacing: 8) {
                        Image(systemName: diagnosisIcon(diagnosis))
                            .font(.system(size: 14))
                            .foregroundColor(urgencyColor)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(diagnosis.rawValue.uppercased())
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundColor(urgencyColor)
                                    .kerning(0.5)
                                if urgency == .actionRequired {
                                    Text("ACTION REQUIRED")
                                        .font(.system(size: 8, weight: .black))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.appRed)
                                        .cornerRadius(3)
                                }
                            }
                            Text(diagnosisAdvice(diagnosis, urgency: urgency))
                                .font(.system(size: 11))
                                .foregroundColor(.appTextSecondary)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(urgencyColor.opacity(0.08))
                    .cornerRadius(8)
                }
            }

            // History toggle
            historyToggle
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    // ── e1RM Chart ──
    @ViewBuilder
    private var e1rmChart: some View {
        let data = Array(sessionE1RMs.reversed())
        VStack(alignment: .leading, spacing: 6) {
            Text("e1RM TREND").font(.system(size: 9, weight: .black)).foregroundColor(.appTextDim).kerning(1.5)
            Chart {
                ForEach(Array(data.enumerated()), id: \.offset) { idx, point in
                    LineMark(x: .value("Session", idx + 1), y: .value("e1RM", point.e1rm))
                        .foregroundStyle(Color.appRed)
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Session", idx + 1), y: .value("e1RM", point.e1rm))
                        .foregroundStyle(Color.appRed)
                        .symbolSize(30)
                }
            }
            .chartYScale(domain: (data.map { $0.e1rm }.min() ?? 0) * 0.95 ... (data.map { $0.e1rm }.max() ?? 100) * 1.02)
            .chartXAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisGridLine().foregroundStyle(Color.appBorder)
                    AxisValueLabel().foregroundStyle(Color.appTextDim)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Color.appBorder)
                    AxisValueLabel().foregroundStyle(Color.appTextDim)
                }
            }
            .frame(height: 140)
        }
    }

    // ── Top set pill ──
    private func topSetPill(label: String, weight: Double, reps: Int, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(label).font(.system(size: 8, weight: .black)).foregroundColor(color).kerning(1)
            Text(String(format: "%.0f", weight))
                .font(.system(size: 16, weight: .black, design: .rounded)).foregroundColor(.appTextPrimary)
            Text("× \(reps) reps").font(.system(size: 9)).foregroundColor(.appTextDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.06))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.2), lineWidth: 1))
    }

    // ── Fatigue section ──
    @ViewBuilder
    private func fatigueSection(lastSession: [WorkoutLog]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LAST SESSION").font(.system(size: 9, weight: .black)).foregroundColor(.appTextDim).kerning(1.5)
            ForEach(lastSession, id: \.setIndex) { log in
                HStack(spacing: 8) {
                    Text("Set \(log.setIndex + 1)")
                        .font(.system(size: 11, weight: .bold)).foregroundColor(.appTextSecondary)
                        .frame(width: 40, alignment: .leading)
                    Text("\(String(format: "%.0f", log.weight)) \(useMetric ? "kg" : "lbs") x \(log.reps)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.appTextPrimary)
                    Spacer()
                    let dateStr = shortDate(log.date)
                    Text(dateStr).font(.system(size: 10)).foregroundColor(.appTextDim)
                }
            }
            // Trend analysis
            let weights = lastSession.map { $0.weight }
            if weights.count >= 2 {
                let dropped = weights.last! < weights.first!
                let climbed = zip(weights, weights.dropFirst()).allSatisfy { $0 <= $1 } && weights.last! > weights.first!
                if dropped {
                    Text("Weight dropped on later sets — consider opening heavier or adjusting load")
                        .font(.system(size: 11, weight: .medium)).foregroundColor(.appGold)
                        .padding(8).background(Color.appGold.opacity(0.08)).cornerRadius(6)
                } else if climbed {
                    Text("You're consistently climbing — try opening 5 lbs heavier so you hit failure before the last set")
                        .font(.system(size: 11, weight: .medium)).foregroundColor(.appBlue)
                        .padding(8).background(Color.appBlue.opacity(0.08)).cornerRadius(6)
                }
            }
        }
    }

    private func shortDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f.string(from: date)
    }

    // ── History toggle ──
    private var historyToggle: some View {
        HStack {
            Text("Base on history")
                .font(.system(size: 12, weight: .bold)).foregroundColor(.appTextSecondary)
            Spacer()
            Toggle("", isOn: Binding(
                get: { historyEnabled },
                set: { UserDefaults.standard.set($0, forKey: "historyEnabled_\(exerciseKey)") }
            ))
            .tint(.appRed)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.appSurface2).cornerRadius(8)
    }

    // ── Template-only card (when history is OFF) ──
    private var templateOnlyCard: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("TEMPLATE TARGETS")
                        .font(.system(size: 9, weight: .black)).foregroundColor(.appTextDim).kerning(1.5)
                    Text("\(targetRepsLow)–\(targetRepsHigh) reps · RPE \(String(format: "%.1f", targetRPE))")
                        .font(.system(size: 13, weight: .bold)).foregroundColor(.appTextSecondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { historyEnabled },
                    set: { UserDefaults.standard.set($0, forKey: "historyEnabled_\(exerciseKey)") }
                ))
                .tint(.appRed).labelsHidden()
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color.appSurface).cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
    }

    private func diagnosisIcon(_ d: StallDiagnosis) -> String {
        switch d {
        case .fatigueStall:   return "battery.25percent"
        case .intensityStall: return "arrow.up.circle"
        case .truePlateau:    return "arrow.triangle.swap"
        case .volumeStall:    return "chart.bar.xaxis"
        case .noStall:        return "checkmark.circle"
        }
    }

    private func diagnosisAdvice(_ d: StallDiagnosis, urgency: StallUrgency = .suggestion) -> String {
        if urgency == .actionRequired {
            switch d {
            case .fatigueStall:   return "Stall persisted 3+ sessions — take a deload week before continuing"
            case .intensityStall: return "Stall persisted 3+ sessions — increase effort or add intensity techniques"
            case .truePlateau:    return "Stall persisted 3+ sessions — swap this exercise before next session"
            case .volumeStall:    return "Stall persisted 3+ sessions — drop 2+ sets immediately"
            case .noStall:        return ""
            }
        }
        switch d {
        case .fatigueStall:   return "Consider a deload — fatigue is accumulating"
        case .intensityStall: return "Push harder — you have room for more intensity"
        case .truePlateau:    return "Try a different exercise variation"
        case .volumeStall:    return "Reduce volume — too many sets are draining recovery"
        case .noStall:        return ""
        }
    }
}
