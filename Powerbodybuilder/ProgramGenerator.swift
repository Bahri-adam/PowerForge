import Foundation
import SwiftData

// ═══════════════════════════════════════════
// PROGRAM GENERATOR
// Resolves split structure and weekly set targets
// for auto-periodized programs.
// ═══════════════════════════════════════════

struct GeneratedDayTemplate {
    let label: String
    let sessionType: SessionType
    let primaryMuscles: [String]
    let emphasis: String?
}

struct ExerciseSlot {
    let exerciseKey: String
    let exerciseTier: ExerciseTier
    let sets: Int
    let repsLow: Int
    let repsHigh: Int
    let restSeconds: Int
}

struct ProgramGenerator {

    // ═══════════════════════════════════════
    // SPLIT STRUCTURE
    // ═══════════════════════════════════════

    static func resolveSplitStructure(
        daysPerWeek: Int,
        goal: GoalType,
        priorityMuscles: [String]
    ) -> [GeneratedDayTemplate] {

        let allMuscles = ["Chest", "Back", "Quads", "Hamstrings", "Glutes", "Delts", "Triceps", "Biceps", "Calves"]
        let pushMuscles = ["Chest", "Delts", "Triceps"]
        let pullMuscles = ["Back", "Biceps"]
        let legMuscles = ["Quads", "Hamstrings", "Glutes", "Calves"]
        let upperMuscles = ["Chest", "Back", "Delts", "Triceps", "Biceps"]
        let lowerMuscles = ["Quads", "Hamstrings", "Glutes", "Calves"]

        switch min(daysPerWeek, 7) {

        case ...2:
            return [
                GeneratedDayTemplate(label: "Full Body A", sessionType: .fullBodyA,
                                     primaryMuscles: allMuscles, emphasis: nil),
                GeneratedDayTemplate(label: "Full Body B", sessionType: .fullBodyB,
                                     primaryMuscles: allMuscles, emphasis: nil),
            ]

        case 3:
            if goal == .strength {
                return [
                    GeneratedDayTemplate(label: "Full Body A", sessionType: .fullBodyA,
                                         primaryMuscles: allMuscles, emphasis: nil),
                    GeneratedDayTemplate(label: "Full Body B", sessionType: .fullBodyB,
                                         primaryMuscles: allMuscles, emphasis: nil),
                    GeneratedDayTemplate(label: "Full Body C", sessionType: .fullBodyA,
                                         primaryMuscles: allMuscles, emphasis: nil),
                ]
            }
            return [
                GeneratedDayTemplate(label: "Push", sessionType: .push,
                                     primaryMuscles: pushMuscles, emphasis: nil),
                GeneratedDayTemplate(label: "Pull", sessionType: .pull,
                                     primaryMuscles: pullMuscles, emphasis: nil),
                GeneratedDayTemplate(label: "Legs", sessionType: .legs,
                                     primaryMuscles: legMuscles, emphasis: nil),
            ]

        case 4:
            return [
                GeneratedDayTemplate(label: "Heavy Upper", sessionType: .heavyUpper,
                                     primaryMuscles: upperMuscles, emphasis: nil),
                GeneratedDayTemplate(label: "Heavy Lower", sessionType: .heavyLower,
                                     primaryMuscles: lowerMuscles, emphasis: nil),
                GeneratedDayTemplate(label: "Hypertrophy Upper", sessionType: .hypertrophyUpper,
                                     primaryMuscles: upperMuscles, emphasis: nil),
                GeneratedDayTemplate(label: "Hypertrophy Lower", sessionType: .hypertrophyLower,
                                     primaryMuscles: lowerMuscles, emphasis: nil),
            ]

        case 5:
            // Upper/Lower/Push/Pull/Legs — every muscle hits 2x/week naturally
            return [
                GeneratedDayTemplate(label: "Upper", sessionType: .heavyUpper,
                                     primaryMuscles: upperMuscles, emphasis: nil),
                GeneratedDayTemplate(label: "Lower", sessionType: .heavyLower,
                                     primaryMuscles: lowerMuscles, emphasis: nil),
                GeneratedDayTemplate(label: "Push", sessionType: .push,
                                     primaryMuscles: pushMuscles, emphasis: nil),
                GeneratedDayTemplate(label: "Pull", sessionType: .pull,
                                     primaryMuscles: pullMuscles, emphasis: nil),
                GeneratedDayTemplate(label: "Legs", sessionType: .legs,
                                     primaryMuscles: legMuscles, emphasis: nil),
            ]

        case 6:
            let legsADay: GeneratedDayTemplate
            if priorityMuscles.contains("Quads") {
                legsADay = GeneratedDayTemplate(label: "Legs — Quad Focus", sessionType: .legQuadFocus,
                                                primaryMuscles: ["Quads", "Calves"], emphasis: "quadFocus")
            } else {
                legsADay = GeneratedDayTemplate(label: "Legs A", sessionType: .legsA,
                                                primaryMuscles: legMuscles, emphasis: nil)
            }
            let legsBDay: GeneratedDayTemplate
            if priorityMuscles.contains("Hamstrings") || priorityMuscles.contains("Glutes") {
                legsBDay = GeneratedDayTemplate(label: "Legs — Posterior Chain", sessionType: .legsPosterior,
                                                primaryMuscles: ["Hamstrings", "Glutes", "Calves"], emphasis: "posteriorFocus")
            } else {
                legsBDay = GeneratedDayTemplate(label: "Legs B", sessionType: .legsB,
                                                primaryMuscles: legMuscles, emphasis: nil)
            }
            return [
                GeneratedDayTemplate(label: "Push A", sessionType: .pushA,
                                     primaryMuscles: pushMuscles, emphasis: nil),
                GeneratedDayTemplate(label: "Pull A", sessionType: .pullA,
                                     primaryMuscles: pullMuscles, emphasis: nil),
                legsADay,
                GeneratedDayTemplate(label: "Push B", sessionType: .pushB,
                                     primaryMuscles: pushMuscles, emphasis: nil),
                GeneratedDayTemplate(label: "Pull B", sessionType: .pullB,
                                     primaryMuscles: pullMuscles, emphasis: nil),
                legsBDay,
            ]

        default: // 7
            let sixDay = resolveSplitStructure(daysPerWeek: 6, goal: goal,
                                               priorityMuscles: priorityMuscles)
            return sixDay + [
                GeneratedDayTemplate(label: "Active Recovery", sessionType: .rest,
                                     primaryMuscles: [], emphasis: nil)
            ]
        }
    }

    // ═══════════════════════════════════════
    // WEEKLY SET TARGET
    // ═══════════════════════════════════════

    static func resolveWeeklySetTarget(
        muscle: String,
        week: Int,
        blockType: BlockType,
        muscleTier: MuscleTier,
        experience: ExperienceLevel,
        calorieContext: CalorieContext,
        calibration: LandmarkCalibration?,
        nextWeekAdjustment: Int = 0,
        previousBlockPeakSets: Int? = nil
    ) -> Int {

        if blockType == .deload {
            return VolumeLandmark.mv(muscle: muscle)
        }

        let baseMEV: Int
        if let cal = calibration, cal.confidence != .seeded {
            let confidence = min(1.0, Double(cal.weeksTracked) / 12.0)
            baseMEV = Int(
                Double(VolumeLandmark.scaledMEV(muscle: muscle,
                                                 experience: experience)) * (1 - confidence)
                + Double(cal.adjustedMEV) * confidence
            )
        } else {
            baseMEV = VolumeLandmark.scaledMEV(muscle: muscle, experience: experience)
        }

        let priorityBonus: Int = muscleTier == .priority ? 4 : 0

        let blockMultiplier: Double = switch blockType {
        case .accumulation:    1.0
        case .intensification: 0.65
        case .reaccumulation:  1.15
        case .peak:            0.50
        case .deload:          1.0
        }

        let base = Int(Double(baseMEV + priorityBonus) * blockMultiplier)
        let weekAdjustment = week == 1 ? 0 : nextWeekAdjustment
        var result = base + weekAdjustment

        if week == 1, let peak = previousBlockPeakSets {
            result = min(result, peak - 2)
        }

        let mrv = VolumeLandmark.effectiveMRV(muscle: muscle, experience: experience,
                                               tier: muscleTier,
                                               calorieContext: calorieContext)
        let mv = VolumeLandmark.mv(muscle: muscle)
        let clamped = GuardRails.clampToMRV(min(result, mrv), mrv: mrv, muscle: muscle)
        return GuardRails.floorAtMV(clamped, mv: mv, muscle: muscle)
    }

    // ═══════════════════════════════════════
    // EXERCISE SELECTION PER MUSCLE (v5)
    // Mirrors Python pick_exercises() exactly.
    // ═══════════════════════════════════════

    enum SessionContext: String {
        case upper, lower, fullbody
    }

    static func selectExercisesForMuscle(
        muscle: String,
        setsNeeded: Int,
        muscleTier: MuscleTier,
        goal: GoalType,
        equipment: Set<EquipmentType>,
        usedKeys: Set<String>,
        blockNumber: Int,
        isSecondarySession: Bool = false,
        sessionsPerWeek: Int = 2,
        sessionContext: SessionContext = .fullbody
    ) -> [ExerciseSlot] {

        guard setsNeeded >= 2 else { return [] }

        // ── Filter candidates by muscle, equipment, session restriction ──
        let candidates = ExerciseDictionary.all.values.filter { def in
            guard def.primaryMuscles.contains(where: {
                ExerciseDictionary.normalizeMuscle($0) == muscle
            }) else { return false }
            // Hip adduction folds into Hamstrings for volume tracking, but it's
            // inner-thigh isolation — not a hamstring curl/hinge. Don't let the
            // generator auto-select it to fill Hamstrings volume (the user can
            // still add it manually).
            if muscle == "Hamstrings" && def.head == "adduction" { return false }
            guard equipment.contains(def.equipment) ||
                  def.equipment == .bodyweight else { return false }
            if sessionContext == .upper && def.sessionRestriction == .lowerOnly { return false }
            if sessionContext == .lower && def.sessionRestriction == .upperOnly { return false }
            return true
        }
        guard !candidates.isEmpty else { return [] }

        // ── T1 candidates ──
        var t1Candidates = candidates.filter { $0.isAnchorableAsTier1 && $0.isCompound }
        if goal == .strength {
            t1Candidates = t1Candidates.filter { $0.equipment == .barbell }
        }

        // ── T1 cap: 3 for 1x/week, 5 for 2x+/week ──
        // Reserve 2 for secondary head when muscle needs dual-head coverage at ≥5 sets
        let t1Cap: Int
        if sessionsPerWeek == 1 {
            let needsDualHead = ["Triceps", "Hamstrings", "Biceps", "Calves"].contains(muscle)
            if needsDualHead && setsNeeded >= 5 {
                t1Cap = min(3, setsNeeded - 2)
            } else {
                t1Cap = 3
            }
        } else {
            t1Cap = 5
        }

        // ── Sort key: rank ASC, stretch DESC, key ASC ──
        // Head-aware for Biceps (A=long, B=short) and Calves (A=gastro, B=soleus)
        func sortScore(_ def: ExerciseDefinition) -> (Int, Int, Int, String) {
            var headOrder = 0
            if muscle == "Biceps" {
                let headMap = isSecondarySession
                    ? ["short": 0, "both": 1, "long": 2, "brachio": 3]
                    : ["long": 0, "both": 1, "short": 2, "brachio": 3]
                headOrder = headMap[def.head] ?? 4
                return (headOrder, def.rank, -def.stretchPosition.sortValue, def.key)
            }
            if muscle == "Calves" {
                let headMap = isSecondarySession
                    ? ["soleus": 0, "gastro": 1]
                    : ["gastro": 0, "soleus": 1]
                headOrder = headMap[def.head] ?? 2
                return (headOrder, def.rank, -def.stretchPosition.sortValue, def.key)
            }
            return (0, def.rank, -def.stretchPosition.sortValue, def.key)
        }

        // ── Rep range helpers (strength compounds always use T1 range) ──
        func repsForSlot(tier: ExerciseTier, def: ExerciseDefinition) -> ClosedRange<Int> {
            if goal == .strength && def.isCompound {
                return tier1RepRange(goal: goal)
            }
            switch tier {
            case .tier1: return tier1RepRange(goal: goal)
            case .tier2: return tier2RepRange(goal: goal)
            case .tier3: return 12...20
            }
        }

        var slots: [ExerciseSlot] = []
        var used = usedKeys
        var patternsUsed: Set<String> = []

        // ── Reserve rear delt sets upfront for Delts ≥ 6 ──
        let rearReserve = (muscle == "Delts" && setsNeeded >= 6 && !isSecondarySession) ? 2 : 0
        var eff = setsNeeded - rearReserve

        func appendSlot(_ def: ExerciseDefinition, tier: ExerciseTier, sets: Int) {
            let range = repsForSlot(tier: tier, def: def)
            let rest = tier == .tier1 ? 210 : (tier == .tier2 ? 150 : 90)
            slots.append(ExerciseSlot(
                exerciseKey: def.key, exerciseTier: tier, sets: sets,
                repsLow: range.lowerBound, repsHigh: range.upperBound, restSeconds: rest))
            eff -= sets
            used.insert(def.key)
            if !def.generatorPattern.isEmpty { patternsUsed.insert(def.generatorPattern) }
        }

        // ═══ BACK DUAL T1 (vertical pull + horizontal row when ≥ 5 sets) ═══
        var dualT1Done = false
        if muscle == "Back" && !isSecondarySession && eff >= 5 && !t1Candidates.isEmpty {
            let verts = t1Candidates
                .filter { $0.generatorPattern == "vertical_pull" && !used.contains($0.key) }
                .sorted { sortScore($0) < sortScore($1) }
            let rows = t1Candidates
                .filter { $0.generatorPattern == "horizontal_row" && !used.contains($0.key) }
                .sorted { sortScore($0) < sortScore($1) }

            if let bestVert = verts.first, let bestRow = rows.first {
                var vSets = min(t1Cap, (eff / 2) + (eff % 2))
                var rSets = min(t1Cap, eff / 2)
                if vSets + rSets > eff { rSets = eff - vSets }
                if vSets >= 2 { appendSlot(bestVert, tier: .tier1, sets: vSets) }
                if rSets >= 2 { appendSlot(bestRow, tier: .tier1, sets: rSets) }
                dualT1Done = true
            }
        }

        // ═══ SINGLE T1 ═══
        if !dualT1Done && !t1Candidates.isEmpty && !isSecondarySession {
            let sorted = t1Candidates.sorted { sortScore($0) < sortScore($1) }
            let chosen = sorted.first { !used.contains($0.key) } ?? sorted[0]
            let s = min(t1Cap, eff)
            if s >= 2 { appendSlot(chosen, tier: .tier1, sets: s) }
        }

        if eff < 2 {
            if rearReserve > 0 { appendRearDelt(to: &slots, from: candidates, used: &used, sets: rearReserve, goal: goal) }
            return slots
        }

        // ═══ 1x/WEEK FORCED HEAD COVERAGE ═══
        if sessionsPerWeek == 1 && eff >= 2 {
            let headsSoFar = Set(slots.compactMap { slot -> String? in
                ExerciseDictionary.all[slot.exerciseKey]?.head
            })

            func forceHead(_ targetHead: String) {
                guard eff >= 2 else { return }
                let pool = candidates
                    .filter { $0.head == targetHead && !used.contains($0.key) }
                    .sorted { sortScore($0) < sortScore($1) }
                if let best = pool.first {
                    let s = min(3, eff)
                    if s >= 2 { appendSlot(best, tier: .tier2, sets: s) }
                }
            }

            if muscle == "Triceps" && !headsSoFar.contains("long") { forceHead("long") }
            if muscle == "Hamstrings" && !headsSoFar.contains("knee_flexion") { forceHead("knee_flexion") }
            if muscle == "Biceps" && headsSoFar.contains("long") && !headsSoFar.contains("short") { forceHead("short") }
            if muscle == "Calves" && headsSoFar.contains("gastro") && !headsSoFar.contains("soleus") { forceHead("soleus") }
        }

        if eff < 2 {
            if rearReserve > 0 { appendRearDelt(to: &slots, from: candidates, used: &used, sets: rearReserve, goal: goal) }
            return slots
        }

        // ═══ T2a ═══
        var t2Pool = candidates
            .filter { !used.contains($0.key) }
            .sorted { sortScore($0) < sortScore($1) }

        // Back B sessions: prefer pattern NOT used in A session
        if muscle == "Back" && isSecondarySession {
            let aPatterns = Set(used.compactMap { ExerciseDictionary.all[$0]?.generatorPattern })
            let diff = t2Pool.filter { !aPatterns.contains($0.generatorPattern) }
            if !diff.isEmpty { t2Pool = diff + t2Pool.filter { aPatterns.contains($0.generatorPattern) } }
        }

        if let best = t2Pool.first {
            let s = min(isSecondarySession ? 5 : 4, eff)
            if s >= 2 { appendSlot(best, tier: .tier2, sets: s) }
        }

        if eff < 2 {
            if rearReserve > 0 { appendRearDelt(to: &slots, from: candidates, used: &used, sets: rearReserve, goal: goal) }
            return slots
        }

        // ═══ T2b — different movement pattern for Back ═══
        var t2bPool = candidates
            .filter { !used.contains($0.key) }
            .sorted { sortScore($0) < sortScore($1) }

        if muscle == "Back" && !patternsUsed.isEmpty {
            let diff = t2bPool.filter { !patternsUsed.contains($0.generatorPattern) }
            if !diff.isEmpty { t2bPool = diff + t2bPool.filter { patternsUsed.contains($0.generatorPattern) } }
        }
        // Calves 1x/week: force soleus as second exercise
        if muscle == "Calves" && sessionsPerWeek == 1 {
            let sol = t2bPool.filter { $0.head == "soleus" }
            if !sol.isEmpty { t2bPool = sol + t2bPool.filter { $0.head != "soleus" } }
        }

        if let best = t2bPool.first {
            let s = min(3, eff)
            if s >= 2 { appendSlot(best, tier: .tier2, sets: s) }
        }

        if eff < 2 {
            if rearReserve > 0 { appendRearDelt(to: &slots, from: candidates, used: &used, sets: rearReserve, goal: goal) }
            return slots
        }

        // ═══ T3 ═══
        let t3Pool = candidates
            .filter { !$0.isCompound && !used.contains($0.key) }
            .sorted { sortScore($0) < sortScore($1) }

        if let best = t3Pool.first {
            let s = min(3, eff)
            if s >= 2 { appendSlot(best, tier: .tier3, sets: s) }
        }

        // ═══ Append rear delt reserve ═══
        if rearReserve > 0 {
            appendRearDelt(to: &slots, from: candidates, used: &used, sets: rearReserve, goal: goal)
        }

        return slots
    }

    private static func appendRearDelt(
        to slots: inout [ExerciseSlot],
        from candidates: [ExerciseDefinition],
        used: inout Set<String>,
        sets: Int,
        goal: GoalType
    ) {
        let posterior = candidates
            .filter { $0.head == "posterior" && !used.contains($0.key) }
            .sorted { ($0.rank, $0.key) < ($1.rank, $1.key) }
        if let best = posterior.first {
            let range = tier2RepRange(goal: goal)
            slots.append(ExerciseSlot(
                exerciseKey: best.key, exerciseTier: .tier2, sets: sets,
                repsLow: range.lowerBound, repsHigh: range.upperBound, restSeconds: 150))
            used.insert(best.key)
        }
    }

    // ── Rep range helpers ─────────────────────────────────────────

    private static func tier1RepRange(goal: GoalType) -> ClosedRange<Int> {
        switch goal {
        case .hypertrophy:   return 5...8
        case .strength:      return 2...5
        case .powerbuilding: return 3...6
        case .recomp:        return 6...10
        }
    }

    private static func tier2RepRange(goal: GoalType) -> ClosedRange<Int> {
        switch goal {
        case .hypertrophy:   return 8...12
        case .strength:      return 4...8
        case .powerbuilding: return 8...12
        case .recomp:        return 10...15
        }
    }

    // ═══════════════════════════════════════
    // BLOCK GENERATOR
    // ═══════════════════════════════════════

    static func generateBlock(
        profile: UserProfile,
        instance: UserProgramInstance,
        blockNumber: Int,
        blockType: BlockType,
        previousBlockPeakSets: [String: Int]?,
        allLogs: [WorkoutLog],
        progressionStates: [ProgressionState],
        modelContext: ModelContext
    ) throws -> [ProgramSessionTemplate] {

        // Block length by experience and goal
        let blockLength: Int
        if profile.goal == .recomp {
            blockLength = 3
        } else {
            switch profile.experience {
            case .beginner, .intermediate: blockLength = 5
            case .advanced, .elite:        blockLength = 4
            }
        }
        instance.blockLength = blockLength

        let dayTemplates = resolveSplitStructure(
            daysPerWeek: profile.daysPerWeek,
            goal: profile.goal,
            priorityMuscles: profile.priorityMuscles)

        let equipment: Set<EquipmentType> =
            [.barbell, .dumbbell, .cable, .machine, .bodyweight]

        var allSlots: [ProgramSessionTemplate] = []

        let upperMuscles: Set<String> = ["Chest", "Back", "Delts", "Triceps", "Biceps"]
        let lowerMuscles: Set<String> = ["Quads", "Hamstrings", "Glutes", "Calves"]

        for week in 1...(blockLength + 1) {
            var musclesAllocatedThisWeek: Set<String> = []
            var categorySeenThisWeek: [String: Int] = [:]
            var allSeenKeys: [String: Set<String>] = [:]  // muscle → cumulative keys this week

            for day in dayTemplates {
                guard day.sessionType != .rest else { continue }

                // Category-based A/B detection (not label-based)
                let dayMuscleSet = Set(day.primaryMuscles)
                let category: String
                if dayMuscleSet.isSubset(of: Set(["Chest", "Delts", "Triceps"])) { category = "push" }
                else if dayMuscleSet.isSubset(of: Set(["Back", "Biceps"])) { category = "pull" }
                else if dayMuscleSet.isSubset(of: lowerMuscles) { category = "legs" }
                else if dayMuscleSet.isSubset(of: upperMuscles) { category = "upper" }
                else if dayMuscleSet.isSubset(of: lowerMuscles) { category = "lower" }
                else { category = "fullbody" }

                let categoryOccurrence = categorySeenThisWeek[category, default: 0]
                categorySeenThisWeek[category, default: 0] += 1
                let isSecondarySession = categoryOccurrence > 0

                // Session context for restriction filtering
                let sessionCtx: SessionContext
                if dayMuscleSet.isSubset(of: upperMuscles) { sessionCtx = .upper }
                else if dayMuscleSet.isSubset(of: lowerMuscles) { sessionCtx = .lower }
                else { sessionCtx = .fullbody }

                var sessionTotalSets = 0
                let maxSessionSets = 24
                var exerciseIndex = 0
                var sessionExerciseSlots: [ExerciseSlot] = []

                for muscle in day.primaryMuscles {
                    let sessionsForMuscle = dayTemplates
                        .filter { $0.primaryMuscles.contains(muscle) }.count

                    let weekBlockType: BlockType = week > blockLength ? .deload : blockType

                    let weeklyTarget = resolveWeeklySetTarget(
                        muscle: muscle,
                        week: week,
                        blockType: weekBlockType,
                        muscleTier: profile.muscleTiers[muscle] ?? .neutral,
                        experience: profile.experience,
                        calorieContext: profile.calorieContext,
                        calibration: instance.landmarkCalibrations
                            .first { $0.muscleGroup == muscle },
                        nextWeekAdjustment: instance.nextWeekSetAdjustments[muscle] ?? 0,
                        previousBlockPeakSets: previousBlockPeakSets?[muscle])

                    // Remainder goes to first session; consolidate if < 2 sets
                    let isFirstSessionForMuscle = !musclesAllocatedThisWeek.contains(muscle)
                    let basePerSession = weeklyTarget / max(1, sessionsForMuscle)
                    let remainder = weeklyTarget % max(1, sessionsForMuscle)

                    let setsThisSession: Int
                    if isFirstSessionForMuscle {
                        setsThisSession = basePerSession + remainder
                        musclesAllocatedThisWeek.insert(muscle)
                    } else {
                        if basePerSession < 2 { continue }  // consolidate to A session
                        setsThisSession = basePerSession
                    }

                    let cappedSets = min(setsThisSession, maxSessionSets - sessionTotalSets)
                    guard cappedSets >= 2 else { continue }

                    let usedKeysForMuscle = allSeenKeys[muscle] ?? Set<String>()

                    let slots = selectExercisesForMuscle(
                        muscle: muscle,
                        setsNeeded: cappedSets,
                        muscleTier: profile.muscleTiers[muscle] ?? .neutral,
                        goal: profile.goal,
                        equipment: equipment,
                        usedKeys: usedKeysForMuscle,
                        blockNumber: blockNumber,
                        isSecondarySession: isSecondarySession,
                        sessionsPerWeek: sessionsForMuscle,
                        sessionContext: sessionCtx)

                    // Track used keys cumulatively
                    for slot in slots {
                        allSeenKeys[muscle, default: []].insert(slot.exerciseKey)
                    }

                    for slot in slots {
                        // Duration budget
                        let estimatedMinutes = (sessionTotalSets + slot.sets)
                            * (45 + slot.restSeconds) / 60
                        if estimatedMinutes > profile.sessionDurationTarget + 20 {
                            if slot.exerciseTier == .tier3 { continue }
                            if slot.exerciseTier == .tier2 && sessionTotalSets > 16 { continue }
                        }

                        // Compute suggestedWeight from e1RM history
                        let progState = progressionStates.first {
                            $0.exerciseKey == slot.exerciseKey
                        }
                        let startWeight: Double
                        if let e1rm = progState?.bestE1RM, e1rm > 0 {
                            let mid = (slot.repsLow + slot.repsHigh) / 2
                            let pct: Double = switch mid {
                            case ...3:    0.92
                            case 4...5:   0.87
                            case 6...7:   0.82
                            case 8...9:   0.76
                            case 10...11: 0.72
                            case 12...14: 0.67
                            default:      0.60
                            }
                            let raw = e1rm * pct
                            let step = profile.useMetric ? 2.5 : 5.0
                            startWeight = (raw / step).rounded() * step
                        } else {
                            startWeight = 0
                        }

                        let weekBlockType: BlockType = week > blockLength ? .deload : blockType

                        // RPE from blockType × exerciseTier
                        let rpe: Double
                        switch (weekBlockType, slot.exerciseTier) {
                        case (.deload,          _):      rpe = 6.0
                        case (.accumulation,    .tier1): rpe = week <= 2 ? 7.0 : 7.5
                        case (.accumulation,    .tier2): rpe = week <= 2 ? 7.0 : 8.0
                        case (.accumulation,    .tier3): rpe = 7.5
                        case (.intensification, .tier1): rpe = 8.5
                        case (.intensification, .tier2): rpe = 8.0
                        case (.intensification, .tier3): rpe = 7.5
                        case (.reaccumulation,  .tier1): rpe = week <= 2 ? 7.5 : 8.0
                        case (.reaccumulation,  .tier2): rpe = 8.0
                        case (.reaccumulation,  .tier3): rpe = 7.5
                        case (.peak,            .tier1): rpe = 9.0
                        case (.peak,            .tier2): rpe = 8.5
                        case (.peak,            .tier3): rpe = 7.5
                        }

                        let slotId = "\(day.label.prefix(1).uppercased())\(exerciseIndex + 1)"

                        let template = ProgramSessionTemplate(
                            programId: instance.programId,
                            programVersion: instance.programVersion,
                            week: week,
                            sessionType: day.sessionType,
                            slotId: slotId,
                            exerciseIndex: exerciseIndex,
                            exerciseKey: slot.exerciseKey,
                            role: slot.exerciseTier == .tier1 ? .mainLift
                                : slot.exerciseTier == .tier2 ? .supplemental
                                : .accessory,
                            isMainLift: slot.exerciseTier == .tier1,
                            targetSets: slot.sets,
                            targetRepsLow: slot.repsLow,
                            targetRepsHigh: slot.repsHigh,
                            targetRPE: rpe,
                            restSeconds: slot.restSeconds,
                            notes: startWeight == 0
                                ? "Calibration — start light, log RPE" : ""
                        )
                        template.suggestedWeight = startWeight
                        allSlots.append(template)
                        sessionExerciseSlots.append(slot)
                        sessionTotalSets += slot.sets
                        exerciseIndex += 1
                    }
                }

                // Sort exercises by tier: T1 → T2 → T3
                sessionExerciseSlots.sort { $0.exerciseTier.sortValue < $1.exerciseTier.sortValue }

                let _ = GuardRails.validateSessionSetCount(sessionTotalSets)
                let _ = GuardRails.validateTierOrder(sessionExerciseSlots)
            }
        }

        return allSlots
    }
}

// ═══════════════════════════════════════════
// SWAP ENGINE
// Returns ranked replacement suggestions for an exercise.
// Same-head preferred (functional equivalence for swaps).
// ═══════════════════════════════════════════

struct SwapSuggestion {
    let exerciseKey: String
    let displayName: String
    let isSameTier: Bool
    let isSameHead: Bool
    let rank: Int
    let equipment: EquipmentType
    let head: String
}

struct SwapEngine {

    static func suggestions(
        for exerciseKey: String,
        goal: GoalType,
        equipment: Set<EquipmentType>,
        sessionContext: ProgramGenerator.SessionContext = .fullbody,
        alreadyInSession: Set<String> = [],
        maxResults: Int = 5
    ) -> [SwapSuggestion] {

        guard let ex = ExerciseDictionary.all[exerciseKey] else { return [] }

        let muscle = ex.primaryMuscles.compactMap {
            ExerciseDictionary.normalizeMuscle($0)
        }.first ?? ""

        let isT1 = ex.isAnchorableAsTier1

        // Build candidate pool
        let pool = ExerciseDictionary.all.values.filter { def in
            // Same muscle group
            guard def.primaryMuscles.contains(where: {
                ExerciseDictionary.normalizeMuscle($0) == muscle
            }) else { return false }
            // Available equipment
            guard equipment.contains(def.equipment) ||
                  def.equipment == .bodyweight else { return false }
            // Not the same exercise
            guard def.key != exerciseKey else { return false }
            // Not already in session
            guard !alreadyInSession.contains(def.key) else { return false }
            // Session restriction
            if sessionContext == .upper && def.sessionRestriction == .lowerOnly { return false }
            if sessionContext == .lower && def.sessionRestriction == .upperOnly { return false }
            return true
        }

        // Sort: same tier first, same head first, then rank, stretch, key
        let sorted = pool.sorted { a, b in
            let aTier = (a.isAnchorableAsTier1 == isT1) ? 0 : 1
            let bTier = (b.isAnchorableAsTier1 == isT1) ? 0 : 1
            if aTier != bTier { return aTier < bTier }

            let aHead = (a.head == ex.head) ? 0 : 1
            let bHead = (b.head == ex.head) ? 0 : 1
            if aHead != bHead { return aHead < bHead }

            if a.rank != b.rank { return a.rank < b.rank }
            if a.stretchPosition.sortValue != b.stretchPosition.sortValue {
                return a.stretchPosition.sortValue > b.stretchPosition.sortValue
            }
            return a.key < b.key
        }

        return Array(sorted.prefix(maxResults)).map { def in
            SwapSuggestion(
                exerciseKey: def.key,
                displayName: def.displayName,
                isSameTier: def.isAnchorableAsTier1 == isT1,
                isSameHead: def.head == ex.head,
                rank: def.rank,
                equipment: def.equipment,
                head: def.head
            )
        }
    }
}
