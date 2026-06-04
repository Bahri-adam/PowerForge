import Foundation
import SwiftData

// ═══════════════════════════════════════════
// PROGRESSION ENGINE v3
// e1RM EMA trend as primary signal.
// Double progression as secondary (< 6 sessions).
// RPE as optional brake.
// ═══════════════════════════════════════════

struct ProgressionEngine {

    // ─── e1RM TREND CONSTANTS ───

    /// Noise floor: below 2.5% is biological variability + Epley error
    internal static let e1rmNoiseFloor: Double = 0.025

    /// Minimum sessions before EMA trend is meaningful
    internal static let minSessionsForTrend: Int = 6

    // ─── MAIN ENTRY ───
    static func recommend(
        recentLogs: [WorkoutLog],
        targetRepsLow: Int,
        targetRepsHigh: Int,
        targetRPE: Double,
        exerciseTier: ExerciseTier,
        useMetric: Bool,
        progressionState: ProgressionState?,
        lastSessionIFI: Double? = nil,
        blockPhase: BlockPhase = .earlyAccumulation,
        progressionRate: ProgressionRate = .normal,
        pmlFactor: Double = 1.0
    ) -> ProgressionRecommendation {

        // No history — return zero, UI prompts manual entry
        guard !recentLogs.isEmpty else {
            return ProgressionRecommendation(
                recommendedWeight: 0,
                topSetWeight: 0,
                backoffWeight: 0,
                recommendedReps: targetRepsHigh,
                perSetReps: [],
                perSetPrescription: [],
                targetRPE: targetRPE,
                basis: .noHistory,
                confidence: .none,
                stallDetected: false,
                stallReason: .none,
                progressionRule: .hold,
                debugNote: "No history"
            )
        }

        // ─── GROUP LOGS BY SESSION ───
        let sessions = groupBySession(recentLogs)
        let lastSession = sessions.first
        let previousSessions = Array(sessions.dropFirst())

        // ─── DETERMINE DATA CONFIDENCE ───
        let confidence = dataConfidence(exposures: sessions.count)

        // ─── EXTRACT LAST TOP SET ───
        // For PRESCRIPTION purposes, the anchor is the HEAVIEST weight the
        // user actually loaded — not the set with the highest e1RM. A mid-
        // weight high-rep set (e.g. 225×11) can have a higher e1RM than a
        // heavy single (245×4), which would let the heavier work disappear
        // from future prescriptions. Use raw max weight here.
        let lastTopSet = lastSession?.max(by: { $0.weight < $1.weight })
        let lastWorkingWeight = lastTopSet?.weight ?? 0

        // ─── Compute per-set reps from last session (used in all return paths) ───
        // Even early-return paths (deload, G8) should show realistic per-set targets
        // based on the user's last actual performance, not flat targetRepsHigh.
        let fallbackSets = lastSession?.count ?? 0
        let fallbackPerSet: [Int] = fallbackSets > 0
            ? computePerSetReps(
                lastSession: lastSession,
                targetRepsLow: targetRepsLow,
                targetRepsHigh: targetRepsHigh,
                targetSets: fallbackSets,
                rule: .hold,
                weightIncreased: false,
                lastSessionIFI: lastSessionIFI
            )
            : []

        // ─── DELOAD: return early — hold weight, reduce rep targets ───
        if blockPhase == .deload {
            let rounded = RPETable.roundToPlate(lastWorkingWeight, useMetric: useMetric)
            let backoff = exerciseTier == .tier1
                ? RPETable.roundToPlate(rounded * 0.92, useMetric: useMetric)
                : rounded
            // Deload: cut rep targets by ~30% from last session to reduce volume
            let deloadPerSet = fallbackPerSet.map { max(targetRepsLow, Int(Double($0) * 0.70)) }
            // Deload: preserve per-set weights from last session but cut reps by 30%
            let deloadPrescription = computePerSetPrescription(
                lastSession: lastSession,
                targetRepsLow: targetRepsLow,
                targetRepsHigh: targetRepsHigh,
                targetSets: lastSession?.count ?? 3,
                tier: exerciseTier,
                useMetric: useMetric,
                lastSessionIFI: lastSessionIFI,
                ruleForStraight: .hold,
                weightIncreasedForStraight: false,
                topWeightForStraight: rounded,
                backoffWeightForStraight: backoff
            ).map { pres in
                PerSetPrescription(
                    weight: pres.weight,
                    repsTarget: max(targetRepsLow, Int(Double(pres.repsTarget) * 0.70)),
                    repsRangeLow: nil, repsRangeHigh: nil,
                    role: pres.role,
                    note: "deload — 70% reps"
                )
            }
            return ProgressionRecommendation(
                recommendedWeight: rounded,
                topSetWeight: rounded,
                backoffWeight: backoff,
                recommendedReps: targetRepsHigh,
                perSetReps: deloadPerSet,
                perSetPrescription: deloadPrescription,
                targetRPE: targetRPE,
                basis: .doublePrgresssion,
                confidence: confidence,
                stallDetected: false,
                stallReason: .none,
                progressionRule: .hold,
                debugNote: "→ Deload week — holding weight"
            )
        }

        // ─── G8: suppress signals before 3 sessions ───
        // Exception: if every working set in the last session blew past
        // targetRepsHigh by 5+ reps, the user has clearly outgrown the
        // prescribed range. Honor that demonstrated capacity rather than
        // holding weight forever — otherwise calf-raise-at-340-for-24-reps
        // never gets a weight bump.
        let demonstratedCapacityOverride: Bool = {
            guard let last = lastSession, !last.isEmpty else { return false }
            let sessionMax = last.map { $0.weight }.max() ?? 0
            let working = last.filter { $0.weight >= sessionMax * 0.80 }
            guard !working.isEmpty else { return false }
            return working.allSatisfy { $0.reps >= targetRepsHigh + 5 }
        }()

        guard GuardRails.allowProgressionSignal(
            totalExposures: progressionState?.totalExposures ?? 0) ||
              demonstratedCapacityOverride else {
            let rw = RPETable.roundToPlate(lastWorkingWeight > 0 ? lastWorkingWeight : 0, useMetric: useMetric)

            // Below-range correction applies even before 3 sessions: an
            // impossible rep target (loaded too heavy to reach the range) is a
            // sanity fix, not a progression decision, so lighten it early too.
            // This covers a freshly-added custom exercise the user overloaded.
            if let fitted = belowRangeFittedWeight(lastSession: lastSession,
                                                   targetRepsLow: targetRepsLow,
                                                   currentWeight: lastWorkingWeight) {
                let corrected = RPETable.roundToPlate(fitted, useMetric: useMetric)
                let setCount = lastSession?.count ?? 3
                let presc = (0..<setCount).map { i in
                    PerSetPrescription(
                        weight: corrected,
                        repsTarget: targetRepsLow,
                        repsRangeLow: targetRepsLow,
                        repsRangeHigh: targetRepsHigh,
                        role: i == 0 ? .topSet : .primary,
                        note: "lightened to fit \(targetRepsLow)–\(targetRepsHigh)"
                    )
                }
                return ProgressionRecommendation(
                    recommendedWeight: corrected,
                    topSetWeight: corrected,
                    backoffWeight: corrected,
                    recommendedReps: targetRepsHigh,
                    perSetReps: Array(repeating: targetRepsLow, count: setCount),
                    perSetPrescription: presc,
                    targetRPE: targetRPE,
                    basis: .lastSessionBased,
                    confidence: confidence,
                    stallDetected: false,
                    stallReason: .none,
                    progressionRule: .backoff,
                    debugNote: "Below \(targetRepsLow)-rep floor at \(Int(lastWorkingWeight)) → lightened to \(Int(corrected)) for \(targetRepsLow)–\(targetRepsHigh) (early)"
                )
            }

            // G8: hold weight, use last session's per-set pattern (weights + reps + roles)
            let g8Prescription = computePerSetPrescription(
                lastSession: lastSession,
                targetRepsLow: targetRepsLow,
                targetRepsHigh: targetRepsHigh,
                targetSets: lastSession?.count ?? 3,
                tier: exerciseTier,
                useMetric: useMetric,
                lastSessionIFI: lastSessionIFI,
                ruleForStraight: .hold,
                weightIncreasedForStraight: false,
                topWeightForStraight: rw,
                backoffWeightForStraight: rw
            )
            return ProgressionRecommendation(
                recommendedWeight: rw,
                topSetWeight: rw,
                backoffWeight: rw,
                recommendedReps: targetRepsHigh,
                perSetReps: fallbackPerSet,  // use last session's per-set pattern
                perSetPrescription: g8Prescription,
                targetRPE: targetRPE,
                basis: .noHistory,
                confidence: .none,
                stallDetected: false,
                stallReason: .none,
                progressionRule: .hold,
                debugNote: "G8: insufficient history"
            )
        }

        // ─── PROGRESSION RULES ───
        var rule = determineProgressionRule(
            lastSession: lastSession,
            previousSessions: previousSessions,
            targetRepsLow: targetRepsLow,
            targetRepsHigh: targetRepsHigh,
            exerciseTier: exerciseTier,
            progressionState: progressionState
        )

        // ─── G9: suppress post-deload progression ───
        rule = GuardRails.suppressPostDeload(blockPhase: blockPhase, rule: rule)

        // ─── G5: block progress after backoff ───
        if let ps = progressionState, ps.consecutiveFailures > 0 {
            rule = GuardRails.blockProgressAfterBackoff(
                lastRule: .backoff, currentRule: rule)
        }

        // ─── CALCULATE BASE WEIGHT ───
        var baseWeight = lastWorkingWeight
        var increment = progressionIncrement(
            exerciseTier: exerciseTier,
            useMetric: useMetric,
            currentWeight: lastWorkingWeight
        )

        switch rule {
        case .progress:
            // Intensification: 30% larger increment
            if blockPhase == .intensification {
                increment *= 1.3
            }
            baseWeight = lastWorkingWeight + increment

        case .hold:
            baseWeight = lastWorkingWeight

        case .backoff:
            baseWeight = lastWorkingWeight * exerciseTier.backoffPercentage
        }

        // ─── IFI MODIFIER (adjusts progression based on fatigue pattern) ───
        var effectiveRule = rule
        if let ifi = lastSessionIFI, ifi > 0 {
            let zone = IFIZone.classify(ifi)
            switch zone {
            case .fatigued where rule == .progress:
                baseWeight = lastWorkingWeight
                effectiveRule = .hold
            case .acuteOverreach:
                baseWeight = lastWorkingWeight * exerciseTier.backoffPercentage
                effectiveRule = .backoff
            default:
                break
            }
        }

        // ─── RPE BRAKE (optional — only applies if RPE was logged) ───
        let lastRPE = lastTopSet?.rpe ?? 0
        if lastRPE > 0 {
            baseWeight = applyRPEBrake(
                weight: baseWeight,
                lastWorkingWeight: lastWorkingWeight,
                lastRPE: lastRPE,
                targetRPE: targetRPE,
                rule: effectiveRule,
                exerciseTier: exerciseTier,
                useMetric: useMetric
            )
        }

        // ─── PROGRESSION RATE MODIFIER ───
        switch progressionRate {
        case .fast:
            if exerciseTier == .tier1 && rule == .progress {
                baseWeight += increment * 0.5
            }
        case .slow:
            let required = exerciseTier == .tier1 ? 2 : 1
            let actual = progressionState?.consecutiveSuccesses ?? 0
            if rule == .progress && actual < required {
                baseWeight = lastWorkingWeight
            }
        case .normal:
            break
        }

        // ─── PML ADJUSTMENT (prior exercise fatigue) ───
        if pmlFactor < 1.0 {
            baseWeight *= pmlFactor
        }

        // ─── BELOW-RANGE WEIGHT CORRECTION ───
        // Textbook double progression: if the user couldn't reach the bottom of
        // the rep range at the loaded weight, the weight is too heavy for this
        // slot. Recommend a lighter, e1RM-derived weight that lands them at
        // targetRepsLow, then normal progression climbs back up. Skip when e1RM
        // is genuinely rising (rule == .progress — that's improvement, not a
        // mismatch) and for intentional pyramids (reverse/ascending), where a
        // heavy low-rep top set is the whole point.
        var belowRangeCorrected = false
        if rule != .progress,
           let fitted = belowRangeFittedWeight(lastSession: lastSession,
                                               targetRepsLow: targetRepsLow,
                                               currentWeight: baseWeight) {
            baseWeight = fitted
            rule = .backoff
            belowRangeCorrected = true
        }

        // ─── ROUND TO PLATE ───
        let rounded = RPETable.roundToPlate(baseWeight, useMetric: useMetric)

        // ─── BACKOFF WEIGHT (tier1 only) ───
        // Below-range correction prescribes straight sets at the corrected
        // weight (every set targets the rep range), so skip the tier1 taper.
        let backoff = belowRangeCorrected
            ? rounded
            : (exerciseTier == .tier1
                ? RPETable.roundToPlate(rounded * 0.92, useMetric: useMetric)
                : rounded)

        // ─── STALL DETECTION ───
        let stall: (isStalled: Bool, reason: StallReason)
        if blockPhase == .postDeloadReintro {
            // Skip stall detection on post-deload reintro
            stall = (false, .none)
        } else if let cached = progressionState?.lastStallDiagnosis,
           cached != .noStall,
           (progressionState?.consecutiveStallDiagnoses ?? 0) >= 1 {
            stall = stallReasonFrom(diagnosis: cached)
        } else {
            // Late accumulation uses tighter threshold
            let stallThreshold: Double = blockPhase == .lateAccumulation ? 0.003 : 0.01
            stall = detectStall(
                sessions: sessions,
                exerciseTier: exerciseTier,
                targetRepsLow: targetRepsLow,
                threshold: stallThreshold
            )
        }

        let debugNote = belowRangeCorrected
            ? "Below \(targetRepsLow)-rep floor at \(Int(lastWorkingWeight)) → lightened to \(Int(rounded)) for \(targetRepsLow)–\(targetRepsHigh)"
            : buildDebugNote(
                rule: rule,
                lastWeight: lastWorkingWeight,
                suggested: rounded,
                confidence: confidence,
                sessions: sessions.count
            )

        // Compute per-set rep targets (legacy) and per-set prescription (new)
        let templateSets = lastSession?.count ?? 3
        let weightWentUp = rounded > lastWorkingWeight && rule == .progress

        let perSet: [Int]
        let prescription: [PerSetPrescription]
        if belowRangeCorrected {
            // Straight sets at the corrected weight; every set aims for the
            // bottom of the range, with the full range shown as the goal.
            perSet = Array(repeating: targetRepsLow, count: templateSets)
            prescription = (0..<templateSets).map { i in
                PerSetPrescription(
                    weight: rounded,
                    repsTarget: targetRepsLow,
                    repsRangeLow: targetRepsLow,
                    repsRangeHigh: targetRepsHigh,
                    role: i == 0 ? .topSet : .primary,
                    note: "lightened to fit \(targetRepsLow)–\(targetRepsHigh)"
                )
            }
        } else {
            perSet = computePerSetReps(
                lastSession: lastSession,
                targetRepsLow: targetRepsLow,
                targetRepsHigh: targetRepsHigh,
                targetSets: templateSets,
                rule: rule,
                weightIncreased: weightWentUp,
                lastSessionIFI: lastSessionIFI
            )
            prescription = computePerSetPrescription(
                lastSession: lastSession,
                targetRepsLow: targetRepsLow,
                targetRepsHigh: targetRepsHigh,
                targetSets: templateSets,
                tier: exerciseTier,
                useMetric: useMetric,
                lastSessionIFI: lastSessionIFI,
                ruleForStraight: rule,
                weightIncreasedForStraight: weightWentUp,
                topWeightForStraight: rounded,
                backoffWeightForStraight: backoff
            )
        }

        return ProgressionRecommendation(
            recommendedWeight: rounded,
            topSetWeight: rounded,
            backoffWeight: backoff,
            recommendedReps: targetRepsHigh,
            perSetReps: perSet,
            perSetPrescription: prescription,
            targetRPE: targetRPE,
            basis: .doublePrgresssion,
            confidence: confidence,
            stallDetected: stall.isStalled,
            stallReason: stall.reason,
            progressionRule: rule,
            debugNote: debugNote
        )
    }

    // ═══════════════════════════════════════
    // WEIGHT PATTERN DETECTION
    // ═══════════════════════════════════════

    /// Classify the last session's weight pattern.
    /// Returns the pattern type and the list of weights in set-index order.
    static func detectWeightPattern(_ lastSession: [WorkoutLog]?) -> (pattern: WeightPattern, weights: [Double]) {
        guard let sorted = lastSession?.sorted(by: { $0.setIndex < $1.setIndex }),
              !sorted.isEmpty else {
            return (.none, [])
        }
        let weights = sorted.map { $0.weight }
        guard let minW = weights.min(), let maxW = weights.max(), minW > 0 else {
            return (.none, weights)
        }

        // Within 5% → straight sets (absorbs minor logging noise)
        if maxW / minW <= 1.05 {
            return (.straight, weights)
        }

        let ascending = zip(weights, weights.dropFirst()).allSatisfy { $0 <= $1 }
        let descending = zip(weights, weights.dropFirst()).allSatisfy { $0 >= $1 }

        if ascending && !descending { return (.ascending, weights) }
        if descending && !ascending { return (.reverse, weights) }
        return (.mixed, weights)
    }

    /// Predict a rep range at `targetWeight` given the user's max e1RM.
    /// `positionFromFresh`: 0 = set 1 (fresh), applies ~5% rep decay per subsequent set.
    /// Returns a (low, high) tuple clamped into [targetRepsLow, targetRepsHigh].
    static func predictRepsRange(
        maxE1RM: Double,
        targetWeight: Double,
        targetRepsLow: Int,
        targetRepsHigh: Int,
        positionFromFresh: Int = 0
    ) -> (low: Int, high: Int) {
        guard maxE1RM > 0, targetWeight > 0 else {
            return (targetRepsLow, targetRepsHigh)
        }
        // Inverted Epley: reps = 30 × (e1RM/weight - 1)
        let baseRepsDouble = 30.0 * (maxE1RM / targetWeight - 1.0)
        let baseReps = max(1, Int(round(baseRepsDouble)))
        // Apply position decay (5% per set, capped at 30% total)
        let fatigueMult = max(0.70, 1.0 - Double(positionFromFresh) * 0.05)
        let adjusted = max(1, Int(round(Double(baseReps) * fatigueMult)))

        var low = max(targetRepsLow, adjusted - 1)
        var high = min(targetRepsHigh, adjusted + 1)
        if low > high {
            let mid = max(targetRepsLow, min(targetRepsHigh, adjusted))
            low = mid; high = mid
        }
        return (low, high)
    }

    // ═══════════════════════════════════════
    // WEIGHT PATTERN + SET ROLE TYPES
    // ═══════════════════════════════════════

    enum WeightPattern: String {
        case none               // no history
        case straight           // all sets at the same weight (±5%)
        case ascending          // weights monotonically increase across sets
        case reverse            // weights monotonically decrease across sets (RPT)
        case mixed              // non-monotonic; fallback to straight at top weight
    }

    enum SetRole: String, Codable {
        case topSet             // the working set that drives progression
        case feeder             // lighter ramp-up sets (ascending pyramid)
        case backoff            // lighter follow-up sets (reverse pyramid / straight T1)
        case primary            // straight-sets working set (no special role)
    }

    /// One set's prescription: weight, target reps (single or range), and role.
    struct PerSetPrescription {
        let weight: Double
        let repsTarget: Int             // single-point target
        let repsRangeLow: Int?          // if non-nil, display as range
        let repsRangeHigh: Int?
        let role: SetRole
        let note: String                // short explanation for debugging / UI tooltip

        var hasRange: Bool { repsRangeLow != nil && repsRangeHigh != nil }
    }

    // ═══════════════════════════════════════
    // PER-SET REP TARGETS
    // Legacy helper — kept for backward compatibility with callers that only
    // need rep numbers. New code should use computePerSetPrescription().
    // ═══════════════════════════════════════

    static func computePerSetReps(
        lastSession: [WorkoutLog]?,
        targetRepsLow: Int,
        targetRepsHigh: Int,
        targetSets: Int,
        rule: ProgressionRule,
        weightIncreased: Bool,
        lastSessionIFI: Double?
    ) -> [Int] {
        let ifi = lastSessionIFI ?? 0
        let zone = IFIZone.classify(ifi)

        guard let last = lastSession, !last.isEmpty else {
            return Array(repeating: targetRepsHigh, count: targetSets)
        }

        let sorted = last.sorted { $0.setIndex < $1.setIndex }

        return (0..<targetSets).map { i in
            let lastReps: Int
            if i < sorted.count {
                lastReps = sorted[i].reps
            } else if let final = sorted.last {
                lastReps = final.reps
            } else {
                lastReps = targetRepsLow
            }

            if weightIncreased {
                // Weight went up → expect rep drop, target near bottom of range
                return max(targetRepsLow, lastReps - 2)
            }

            if rule == .backoff {
                // Lighter weight → aim high but cap at lastReps + 3 (realistic jump)
                return max(targetRepsLow, min(targetRepsHigh, lastReps + 3))
            }

            // Front-loaded progression: top set (i=0) gets larger bump than secondary sets.
            // This prevents "flat ceiling" when IFI is artificially 0 (single set / all-equal
            // reps) and matches how real progression works — push the top set, others follow.
            let bumpTop: Int
            let bumpSecondary: Int
            switch zone {
            case .fresh:    bumpTop = 2; bumpSecondary = 1
            case .optimal:  bumpTop = 1; bumpSecondary = 1
            default:        bumpTop = 0; bumpSecondary = 0  // fatigued/overtrained: match
            }
            let bump = i == 0 ? bumpTop : bumpSecondary

            return max(targetRepsLow, min(targetRepsHigh, lastReps + bump))
        }
    }

    // ═══════════════════════════════════════
    // PER-SET WEIGHT-AWARE PRESCRIPTION
    // Preserves the user's weight pattern (straight / pyramid / reverse).
    // Returns per-set weights AND rep targets AND role labels.
    // ═══════════════════════════════════════

    static func computePerSetPrescription(
        lastSession: [WorkoutLog]?,
        targetRepsLow: Int,
        targetRepsHigh: Int,
        targetSets: Int,
        tier: ExerciseTier,
        useMetric: Bool,
        lastSessionIFI: Double?,
        ruleForStraight: ProgressionRule,
        weightIncreasedForStraight: Bool,
        topWeightForStraight: Double,
        backoffWeightForStraight: Double
    ) -> [PerSetPrescription] {
        let pattern = detectWeightPattern(lastSession)

        // No history → flat ceiling
        if pattern.pattern == .none {
            return (0..<targetSets).map { _ in
                PerSetPrescription(
                    weight: 0, repsTarget: targetRepsHigh,
                    repsRangeLow: nil, repsRangeHigh: nil,
                    role: .primary, note: "no history"
                )
            }
        }

        // Max e1RM across last session (for new-weight rep predictions)
        let lastSorted = lastSession?.sorted(by: { $0.setIndex < $1.setIndex }) ?? []
        let maxE1RM = lastSorted
            .filter { isValidForE1RM($0.reps) }
            .map { $0.e1rm }
            .max() ?? 0

        switch pattern.pattern {
        case .straight, .mixed, .none:
            // For mixed, collapse to straight at the top weight (the user's likely intent)
            return straightSetsPrescription(
                lastSorted: lastSorted,
                targetRepsLow: targetRepsLow,
                targetRepsHigh: targetRepsHigh,
                targetSets: targetSets,
                lastSessionIFI: lastSessionIFI,
                rule: ruleForStraight,
                weightIncreased: weightIncreasedForStraight,
                topWeight: topWeightForStraight,
                backoffWeight: backoffWeightForStraight,
                tier: tier
            )

        case .ascending:
            return ascendingPrescription(
                lastSorted: lastSorted,
                targetRepsLow: targetRepsLow,
                targetRepsHigh: targetRepsHigh,
                targetSets: targetSets,
                lastSessionIFI: lastSessionIFI,
                maxE1RM: maxE1RM,
                tier: tier,
                useMetric: useMetric
            )

        case .reverse:
            return reversePrescription(
                lastSorted: lastSorted,
                targetRepsLow: targetRepsLow,
                targetRepsHigh: targetRepsHigh,
                targetSets: targetSets,
                lastSessionIFI: lastSessionIFI,
                maxE1RM: maxE1RM,
                tier: tier,
                useMetric: useMetric
            )
        }
    }

    // ── Straight sets ──

    private static func straightSetsPrescription(
        lastSorted: [WorkoutLog],
        targetRepsLow: Int,
        targetRepsHigh: Int,
        targetSets: Int,
        lastSessionIFI: Double?,
        rule: ProgressionRule,
        weightIncreased: Bool,
        topWeight: Double,
        backoffWeight: Double,
        tier: ExerciseTier
    ) -> [PerSetPrescription] {
        let ifi = lastSessionIFI ?? 0
        let zone = IFIZone.classify(ifi)
        let bumpTop: Int
        let bumpSecondary: Int
        switch zone {
        case .fresh:   bumpTop = 2; bumpSecondary = 1
        case .optimal: bumpTop = 1; bumpSecondary = 1
        default:       bumpTop = 0; bumpSecondary = 0
        }

        let isTier1 = tier == .tier1

        return (0..<targetSets).map { i in
            // Weight: tier1 uses backoff for non-top sets; others flat
            let weight: Double = (isTier1 && i > 0) ? backoffWeight : topWeight

            // Rep target: based on last session's set[i] reps + IFI bump
            let lastReps: Int
            if i < lastSorted.count {
                lastReps = lastSorted[i].reps
            } else if let final = lastSorted.last {
                lastReps = final.reps
            } else {
                lastReps = targetRepsLow
            }

            let target: Int
            if weightIncreased {
                target = max(targetRepsLow, lastReps - 2)
            } else if rule == .backoff {
                target = max(targetRepsLow, min(targetRepsHigh, lastReps + 3))
            } else {
                let bump = i == 0 ? bumpTop : bumpSecondary
                // Don't cap at targetRepsHigh when the user has already shown
                // they can exceed the range. Otherwise calves-at-340-for-24-reps
                // get clamped to "do 15 next time" which makes no sense.
                let cap = lastReps >= targetRepsHigh ? lastReps + bump : targetRepsHigh
                target = max(targetRepsLow, min(cap, lastReps + bump))
            }

            // Top-set badge follows the heaviest weight, not the index.
            // For true straight sets all weights are equal → only i==0 gets
            // the badge (tiebreaker). For mixed-collapsed-to-top weights,
            // every set is at topWeight so still only i==0 — but if a future
            // pattern variant feeds non-uniform weights through this path,
            // weight equality is the correct rule.
            let isTopWeight = abs(weight - topWeight) < 0.5
            let role: SetRole = (isTopWeight && i == 0) ? .topSet
                                                       : (isTier1 ? .backoff : .primary)
            return PerSetPrescription(
                weight: weight, repsTarget: target,
                repsRangeLow: nil, repsRangeHigh: nil,
                role: role, note: "straight"
            )
        }
    }

    // ── Ascending pyramid ──

    private static func ascendingPrescription(
        lastSorted: [WorkoutLog],
        targetRepsLow: Int,
        targetRepsHigh: Int,
        targetSets: Int,
        lastSessionIFI: Double?,
        maxE1RM: Double,
        tier: ExerciseTier,
        useMetric: Bool
    ) -> [PerSetPrescription] {
        guard !lastSorted.isEmpty else { return [] }
        let weights = lastSorted.map { $0.weight }
        let topWeight = weights.max() ?? 0
        // First occurrence of the top weight is the top set index
        let topIdx = weights.firstIndex(of: topWeight) ?? (lastSorted.count - 1)

        let ifi = lastSessionIFI ?? 0
        let zone = IFIZone.classify(ifi)

        var result: [PerSetPrescription] = []
        for i in 0..<targetSets {
            if i >= lastSorted.count {
                // Extra set beyond what user logged — mirror the last logged set
                let lastW = lastSorted[lastSorted.count - 1].weight
                let lastR = lastSorted[lastSorted.count - 1].reps
                result.append(PerSetPrescription(
                    weight: lastW, repsTarget: max(targetRepsLow, min(targetRepsHigh, lastR)),
                    repsRangeLow: nil, repsRangeHigh: nil,
                    role: .feeder, note: "extra set — match last"
                ))
                continue
            }

            let lastW = lastSorted[i].weight
            let lastR = lastSorted[i].reps
            let isTop = i == topIdx

            if isTop {
                // Progress top set: if hit top of range → weight bump, else +1 rep
                if lastR >= targetRepsHigh {
                    let inc: Double = (tier == .tier3) ? (useMetric ? 1.25 : 2.5) : (useMetric ? 2.5 : 5.0)
                    let newWeight = RPETable.roundToPlate(lastW + inc, useMetric: useMetric)
                    let predicted = predictRepsRange(
                        maxE1RM: maxE1RM, targetWeight: newWeight,
                        targetRepsLow: targetRepsLow, targetRepsHigh: targetRepsHigh
                    )
                    result.append(PerSetPrescription(
                        weight: newWeight,
                        repsTarget: predicted.low,
                        repsRangeLow: predicted.low, repsRangeHigh: predicted.high,
                        role: .topSet,
                        note: "top set: weight +\(Int(inc))"
                    ))
                } else {
                    let bump = (zone == .fresh || zone == .optimal) ? 1 : 0
                    let target = max(targetRepsLow, min(targetRepsHigh, lastR + bump))
                    result.append(PerSetPrescription(
                        weight: lastW, repsTarget: target,
                        repsRangeLow: nil, repsRangeHigh: nil,
                        role: .topSet, note: "top set: +\(bump) rep"
                    ))
                }
            } else {
                // Feeder set — preserve weight, conservative rep target
                if lastR > targetRepsHigh {
                    // Unusual max-effort feeder — show range, don't force repeat
                    let high = min(lastR, targetRepsHigh + 5)
                    result.append(PerSetPrescription(
                        weight: lastW, repsTarget: targetRepsHigh,
                        repsRangeLow: targetRepsHigh, repsRangeHigh: high,
                        role: .feeder, note: "feeder (last was max-effort \(lastR))"
                    ))
                } else {
                    let bump = (zone == .fresh) ? 1 : 0
                    let target = max(targetRepsLow, min(targetRepsHigh, lastR + bump))
                    result.append(PerSetPrescription(
                        weight: lastW, repsTarget: target,
                        repsRangeLow: nil, repsRangeHigh: nil,
                        role: .feeder, note: "feeder — hold weight"
                    ))
                }
            }
        }
        return result
    }

    // ── Reverse pyramid ──

    private static func reversePrescription(
        lastSorted: [WorkoutLog],
        targetRepsLow: Int,
        targetRepsHigh: Int,
        targetSets: Int,
        lastSessionIFI: Double?,
        maxE1RM: Double,
        tier: ExerciseTier,
        useMetric: Bool
    ) -> [PerSetPrescription] {
        guard !lastSorted.isEmpty else { return [] }
        let ifi = lastSessionIFI ?? 0
        let zone = IFIZone.classify(ifi)

        var result: [PerSetPrescription] = []
        for i in 0..<targetSets {
            if i >= lastSorted.count {
                let lastW = lastSorted[lastSorted.count - 1].weight
                let lastR = lastSorted[lastSorted.count - 1].reps
                result.append(PerSetPrescription(
                    weight: lastW, repsTarget: max(targetRepsLow, min(targetRepsHigh, lastR)),
                    repsRangeLow: nil, repsRangeHigh: nil,
                    role: .backoff, note: "extra set — match last"
                ))
                continue
            }

            let lastW = lastSorted[i].weight
            let lastR = lastSorted[i].reps
            let isTop = i == 0  // RPT: set 1 is heaviest

            if isTop {
                if lastR >= targetRepsHigh {
                    let inc: Double = (tier == .tier3) ? (useMetric ? 1.25 : 2.5) : (useMetric ? 2.5 : 5.0)
                    let newWeight = RPETable.roundToPlate(lastW + inc, useMetric: useMetric)
                    let predicted = predictRepsRange(
                        maxE1RM: maxE1RM, targetWeight: newWeight,
                        targetRepsLow: targetRepsLow, targetRepsHigh: targetRepsHigh
                    )
                    result.append(PerSetPrescription(
                        weight: newWeight,
                        repsTarget: predicted.low,
                        repsRangeLow: predicted.low, repsRangeHigh: predicted.high,
                        role: .topSet,
                        note: "top set: weight +\(Int(inc))"
                    ))
                } else {
                    let bump = (zone == .fresh || zone == .optimal) ? 1 : 0
                    let target = max(targetRepsLow, min(targetRepsHigh, lastR + bump))
                    result.append(PerSetPrescription(
                        weight: lastW, repsTarget: target,
                        repsRangeLow: nil, repsRangeHigh: nil,
                        role: .topSet, note: "top set: +\(bump) rep"
                    ))
                }
            } else {
                // Back-off set — preserve weight, small rep progression
                let bump = (zone == .fresh || zone == .optimal) ? 1 : 0
                let target = max(targetRepsLow, min(targetRepsHigh, lastR + bump))
                result.append(PerSetPrescription(
                    weight: lastW, repsTarget: target,
                    repsRangeLow: nil, repsRangeHigh: nil,
                    role: .backoff, note: "back-off: +\(bump) rep"
                ))
            }
        }
        return result
    }

    // ═══════════════════════════════════════
    // PML — PRIOR MUSCLE LOAD
    // Adjusts recommendations based on accumulated
    // fatigue from earlier exercises in the session.
    // ═══════════════════════════════════════

    struct PMLResult {
        let factor: Double          // 0.70-1.00, multiply against weight
        let totalPML: Double        // raw PML value
        let fatigueSource: String   // dominant contributing muscle, for UI note
    }

    /// Compute PML for a target exercise given prior exercises done this session.
    /// priorExercises = [(exerciseKey, sets)] completed earlier in session order.
    static func computePML(
        targetExerciseKey: String,
        priorExercises: [(key: String, sets: Int)],
        personalSensitivity: Double = 0.12
    ) -> PMLResult {
        guard !priorExercises.isEmpty else {
            return PMLResult(factor: 1.0, totalPML: 0, fatigueSource: "")
        }

        let targetDef = ExerciseDictionary.all[targetExerciseKey]
        let targetMuscles = Set((targetDef?.primaryMuscles ?? []).compactMap {
            ExerciseDictionary.normalizeMuscle($0)
        })

        guard !targetMuscles.isEmpty else {
            return PMLResult(factor: 1.0, totalPML: 0, fatigueSource: "")
        }

        // Overlap weights — how much does each muscle group fatigue our target?
        let overlapMap: [String: [String: Double]] = [
            "Chest":      ["Triceps": 0.40, "Delts": 0.30],
            "Back":       ["Biceps": 0.40, "Delts": 0.15],
            "Quads":      ["Glutes": 0.30, "Hamstrings": 0.15],
            "Hamstrings": ["Glutes": 0.30, "Back": 0.10],
            "Glutes":     ["Hamstrings": 0.20, "Quads": 0.10],
            "Delts":      ["Triceps": 0.20, "Chest": 0.10],
            "Triceps":    ["Chest": 0.10],
            "Biceps":     ["Back": 0.05],
        ]

        var totalPML: Double = 0
        var maxSource: (String, Double) = ("", 0)

        for (priorKey, priorSets) in priorExercises {
            let priorDef = ExerciseDictionary.all[priorKey]
            let priorMuscles = (priorDef?.primaryMuscles ?? []).compactMap {
                ExerciseDictionary.normalizeMuscle($0)
            }

            for priorMuscle in priorMuscles {
                let overlaps = overlapMap[priorMuscle] ?? [:]
                for targetMuscle in targetMuscles {
                    if let weight = overlaps[targetMuscle] {
                        let contribution = weight * Double(min(priorSets, 6)) / 6.0
                        totalPML += contribution
                        if contribution > maxSource.1 {
                            maxSource = (priorMuscle, contribution)
                        }
                    }
                }
            }
        }

        let factor = max(0.70, 1.0 - totalPML * personalSensitivity)
        let source = maxSource.0.isEmpty ? "" : maxSource.0.lowercased()
        return PMLResult(factor: factor, totalPML: totalPML, fatigueSource: source)
    }

    /// After a session, update the per-exercise fatigue sensitivity.
    /// If actual performance was better than PML-predicted → reduce sensitivity.
    /// If worse → increase sensitivity. Error threshold 0.12.
    static func learnFatigueSensitivity(
        state: ProgressionState,
        pmlFactor: Double,
        predictedWeight: Double,
        actualTopE1RM: Double
    ) {
        guard pmlFactor < 0.97,  // only learn when PML was meaningful
              predictedWeight > 0,
              state.totalExposures >= 3 else { return }

        // Compare what we predicted vs what happened
        let predictedE1RM = predictedWeight * (1.0 + 5.0 / 30.0) // rough e1RM at predicted weight
        guard predictedE1RM > 0 else { return }

        let error = (actualTopE1RM - predictedE1RM) / predictedE1RM

        let n = state.totalExposures
        let lr = max(0.04, 0.15 / (1.0 + Double(n) * 0.08))

        if error > 0.12 {
            // User did better than predicted → we overestimated fatigue
            state.personalFatigueSensitivity = max(0.03, state.personalFatigueSensitivity * (1.0 - lr))
        } else if error < -0.12 {
            // User did worse → we underestimated fatigue
            state.personalFatigueSensitivity = min(0.25, state.personalFatigueSensitivity * (1.0 + lr))
        }
    }

    // ═══════════════════════════════════════
    // READINESS MODIFIER
    // ═══════════════════════════════════════

    static func readinessModifier(readiness: Int) -> (weightFactor: Double, repAdjust: Int) {
        switch readiness {
        case 1:  return (0.90, -3)   // Very Low
        case 2:  return (0.95, -1)   // Below Average
        case 4:  return (1.00, +1)   // Good
        case 5:  return (1.02, +2)   // Excellent
        default: return (1.00,  0)   // Normal (3) or unset (0)
        }
    }

    // ═══════════════════════════════════════
    // WARM-UP SET GENERATION
    // ═══════════════════════════════════════

    struct WarmupPrescription {
        let weight: Double
        let reps: Int
        let label: String
    }

    static func generateWarmupSets(
        workingWeight: Double,
        exerciseTier: ExerciseTier,
        useMetric: Bool
    ) -> [WarmupPrescription] {
        // Only for compounds (T1/T2)
        guard exerciseTier != .tier3 else { return [] }

        let bar: Double = useMetric ? 20.0 : 45.0
        guard workingWeight > bar * 1.5 else {
            // Light compound: just bar work
            return [WarmupPrescription(weight: bar, reps: 10, label: "Bar")]
        }

        let pcts: [(Double, Int, String)] = [
            (0.00, 10, "Bar"),
            (0.40,  8, "40%"),
            (0.60,  5, "60%"),
            (0.75,  3, "75%"),
            (0.90,  1, "90%"),
        ]

        var result: [WarmupPrescription] = []
        var lastWeight: Double = 0

        for (pct, reps, label) in pcts {
            let w = pct == 0 ? bar : RPETable.roundToPlate(workingWeight * pct, useMetric: useMetric)
            if w < bar { continue }
            if w == lastWeight { continue }  // skip duplicate plate loads
            if w >= workingWeight { continue }  // don't exceed working weight
            result.append(WarmupPrescription(weight: w, reps: reps, label: label))
            lastWeight = w
        }

        return result
    }

    // ═══════════════════════════════════════
    // e1RM CONFIDENCE & TREND
    // ═══════════════════════════════════════

    /// Whether a rep count is valid for e1RM estimation (Epley cutoff = 12)
    static func isValidForE1RM(_ reps: Int) -> Bool {
        reps >= 1 && reps <= 12
    }

    /// e1RM confidence by rep count (Reynolds et al.)
    /// Epley degrades above 9 reps; cutoff is 12
    internal static func e1rmConfidence(_ reps: Int) -> Double {
        switch reps {
        case 1...9:   return 1.00
        case 10...12: return 0.75
        default:      return 0.00  // excluded from e1RM tracking
        }
    }

    /// EMA-smoothed e1RM trend vs block baseline
    /// Returns 0.0 when data is insufficient or change is within noise
    internal static func computeE1rmTrend(
        _ state: ProgressionState?
    ) -> Double {
        guard let state = state,
              state.totalExposures >= minSessionsForTrend,
              state.baselineE1rm > 0,
              state.emaE1rm > 0 else { return 0.0 }
        let change = (state.emaE1rm - state.baselineE1rm)
                     / max(state.baselineE1rm, 1.0)
        if abs(change) < e1rmNoiseFloor { return 0.0 }
        return change
    }

    /// True if user intentionally went heavier for fewer reps
    /// This is a VALID stimulus choice — must NOT trigger backoff
    private static func didUserGoHeavier(
        _ state: ProgressionState?
    ) -> Bool {
        guard let state = state else { return false }
        return state.lastCompletedWeight > state.previousWeight
            && state.lastSessionReps < state.previousReps
    }

    // ═══════════════════════════════════════
    // PROGRESSION RULE ENGINE
    // Primary: e1RM EMA trend (6+ sessions)
    // Secondary: rep performance (< 6 sessions)
    // ═══════════════════════════════════════

    /// Below-range weight fit (textbook double progression). When the user's
    /// best working set last session fell short of `targetRepsLow` at a
    /// straight-ish load, the weight was too heavy for the slot. Returns an
    /// e1RM-derived weight that lands them at the rep floor — always lighter
    /// than `currentWeight`. Returns nil when they reached the range, when the
    /// load wasn't the limiter (reverse/ascending pyramids are intentional and
    /// a heavy low-rep top set is the point there), or when no lighter weight is
    /// warranted. Across-set fatigue (9/8/7) is NOT below-range — the BEST
    /// working set is what's judged, so only 7/6/5-style misses qualify.
    static func belowRangeFittedWeight(
        lastSession: [WorkoutLog]?,
        targetRepsLow: Int,
        currentWeight: Double
    ) -> Double? {
        guard let last = lastSession, !last.isEmpty else { return nil }
        let pattern = detectWeightPattern(last).pattern
        guard pattern == .straight || pattern == .mixed || pattern == .none else { return nil }
        let sessionMax = last.map { $0.weight }.max() ?? 0
        let working = last.filter { $0.weight >= sessionMax * 0.80 }
        let bestReps = working.map { $0.reps }.max() ?? 0
        guard bestReps < targetRepsLow else { return nil }
        let bestE1rm = working.map { $0.weight * (1.0 + Double($0.reps) / 30.0) }.max() ?? 0
        guard bestE1rm > 0 else { return nil }
        let fitted = bestE1rm / (1.0 + Double(targetRepsLow) / 30.0)
        return fitted < currentWeight ? fitted : nil
    }

    static func determineProgressionRule(
        lastSession: [WorkoutLog]?,
        previousSessions: [[WorkoutLog]],
        targetRepsLow: Int,
        targetRepsHigh: Int,
        exerciseTier: ExerciseTier,
        progressionState: ProgressionState?
    ) -> ProgressionRule {
        guard let last = lastSession, !last.isEmpty else { return .hold }

        let trend = computeE1rmTrend(progressionState)
        let exposures = progressionState?.totalExposures ?? 0

        // ── PRIMARY SIGNAL: e1RM EMA trend (requires 6+ sessions) ─────
        if exposures >= minSessionsForTrend {
            if trend > e1rmNoiseFloor {
                // e1RM genuinely rising — add weight
                return .progress
            }
            if trend < -e1rmNoiseFloor {
                // e1RM genuinely declining
                // Exception: user chose heavier × fewer reps intentionally
                if didUserGoHeavier(progressionState) { return .hold }
                return .backoff
            }
            // Within noise floor — no clear trend. Fall to secondary signal.
        }

        // ── SECONDARY SIGNAL: rep performance (used when < 6 sessions) ─
        // Also used when EMA trend is ambiguous (within noise floor)
        let sessionMaxWeight = last.map { $0.weight }.max() ?? 0
        let workingSets = last.filter { $0.weight >= sessionMaxWeight * 0.80 }
        guard !workingSets.isEmpty else { return .hold }

        // Progress: hit top of rep range on ALL working sets
        let allHitTop = workingSets.allSatisfy { $0.reps >= targetRepsHigh }
        if allHitTop { return .progress }

        // Backoff: missed bottom on 2+ sets, confirmed by previous session
        let missedLow = workingSets.filter { $0.reps < targetRepsLow }
        if missedLow.count >= 2, !previousSessions.isEmpty {
            let prevWorkingSets = previousSessions[0].filter {
                $0.weight >= (previousSessions[0].map { $0.weight }.max() ?? 0) * 0.80
            }
            let prevAlsoMissed = prevWorkingSets.filter {
                $0.reps < targetRepsLow
            }.count >= 2
            if prevAlsoMissed { return .backoff }
        }

        return .hold
    }

    // ═══════════════════════════════════════
    // PROGRESSION INCREMENT
    // ═══════════════════════════════════════

    static func progressionIncrement(
        exerciseTier: ExerciseTier,
        useMetric: Bool,
        currentWeight: Double
    ) -> Double {
        let heavyThreshold: Double = useMetric ? 84.0 : 185.0
        switch exerciseTier {
        case .tier1:
            if currentWeight >= heavyThreshold {
                return useMetric ? 2.5 : 10.0
            } else {
                return useMetric ? 2.5 : 5.0
            }
        case .tier2:
            return useMetric ? 2.5 : 5.0
        case .tier3:
            return useMetric ? 1.25 : 2.5
        }
    }

    // ═══════════════════════════════════════
    // RPE BRAKE (optional safety layer)
    // Only fires if user logged RPE last session
    // ═══════════════════════════════════════

    static func applyRPEBrake(
        weight: Double,
        lastWorkingWeight: Double,
        lastRPE: Double,
        targetRPE: Double,
        rule: ProgressionRule,
        exerciseTier: ExerciseTier,
        useMetric: Bool
    ) -> Double {

        // If last set felt near-maximal AND we're trying to progress
        if lastRPE >= 9.5 && rule == .progress {
            // Hold at last session's weight instead of progressing
            return lastWorkingWeight
        }

        // If last set felt very easy AND we're holding, allow a small bump
        if lastRPE <= 7.0 && rule == .hold {
            let bump = progressionIncrement(exerciseTier: exerciseTier, useMetric: useMetric, currentWeight: weight)
            return weight + bump
        }

        return weight
    }

    // ═══════════════════════════════════════
    // STALL REASON FROM CACHED DIAGNOSIS
    // ═══════════════════════════════════════

    static func stallReasonFrom(
        diagnosis: StallDiagnosis
    ) -> (isStalled: Bool, reason: StallReason) {
        switch diagnosis {
        case .fatigueStall:   return (true,  .e1rmDecline)
        case .volumeStall:    return (true,  .e1rmDecline)
        case .truePlateau:    return (true,  .e1rmFlat)
        case .intensityStall: return (false, .none)
        case .noStall:        return (false, .none)
        }
    }

    // ═══════════════════════════════════════
    // STALL DETECTION
    // Objective: numbers stopped moving
    // ═══════════════════════════════════════

    static func detectStall(
        sessions: [[WorkoutLog]],
        exerciseTier: ExerciseTier,
        targetRepsLow: Int,
        threshold: Double = 0.01
    ) -> (isStalled: Bool, reason: StallReason) {

        if exerciseTier == .tier1 {
            // Need 3+ sessions
            guard sessions.count >= 3 else { return (false, .none) }

            // ─── SUPPRESS after load jump ───
            // e1RM naturally dips on first session at a new weight — not a real stall
            let latestMaxWeight = sessions[0].map { $0.weight }.max() ?? 0
            let previousMaxWeight = sessions[1].map { $0.weight }.max() ?? 0
            if latestMaxWeight > previousMaxWeight + 1 {
                // First session after a weight increase — skip stall detection
                return (false, .none)
            }

            // Get best e1RM per session (e1RM-valid reps only)
            let e1rms = sessions.prefix(3).map { session in
                session.filter { isValidForE1RM($0.reps) }.map { $0.e1rm }.max() ?? 0
            }

            guard e1rms[0] > 0 && e1rms[2] > 0 else { return (false, .none) }

            // Decline: latest e1RM more than threshold below best of last 3
            let bestRecent = e1rms.max() ?? 0
            if e1rms[0] < bestRecent * (1.0 - threshold) {
                return (true, .e1rmDecline)
            }

            // Flat: less than threshold/2 improvement over 3 sessions
            let improvement = (e1rms[0] - e1rms[2]) / max(e1rms[2], 1)
            if improvement < (threshold / 2) {
                // Check if RPE is also rising (if available)
                let latestRPE = sessions[0].map { $0.rpe }.filter { $0 > 0 }.average()
                let oldestRPE = sessions[2].map { $0.rpe }.filter { $0 > 0 }.average()
                if latestRPE > 0 && oldestRPE > 0 && latestRPE > oldestRPE + 0.5 {
                    return (true, .rpeRising)
                }
                return (true, .e1rmFlat)
            }

        } else {
            // Accessories: reps at same load not improving over 4 exposures
            guard sessions.count >= 4 else { return (false, .none) }

            let repsPerSession = sessions.prefix(4).map { session -> Int in
                session.map { $0.reps }.max() ?? 0
            }

            let baseline = repsPerSession.last ?? 0  // oldest session (sessions are newest-first)
            let allFlat = repsPerSession.allSatisfy { $0 <= baseline + 1 }
            if allFlat && baseline > 0 {
                return (true, .repsFlat)
            }
        }

        return (false, .none)
    }

    // ═══════════════════════════════════════
    // DATA CONFIDENCE
    // More sessions = more accurate suggestions
    // ═══════════════════════════════════════

    static func dataConfidence(exposures: Int) -> RecommendationConfidence {
        switch exposures {
        case 0:        return .none
        case 1:        return .low
        case 2...3:    return .medium
        default:       return .high
        }
    }

    // ═══════════════════════════════════════
    // GROUP LOGS BY SESSION DATE
    // Returns array of sessions, newest first
    // ═══════════════════════════════════════

    static func groupBySession(_ logs: [WorkoutLog]) -> [[WorkoutLog]] {
        let calendar = Calendar.current
        var grouped: [Date: [WorkoutLog]] = [:]

        for log in logs {
            let day = calendar.startOfDay(for: log.date)
            grouped[day, default: []].append(log)
        }

        return grouped
            .sorted { $0.key > $1.key }
            .map { $0.value }
    }

    // ═══════════════════════════════════════
    // DEBUG NOTE BUILDER
    // Surfaces algorithm reasoning in UI
    // ═══════════════════════════════════════

    static func buildDebugNote(
        rule: ProgressionRule,
        lastWeight: Double,
        suggested: Double,
        confidence: RecommendationConfidence,
        sessions: Int
    ) -> String {
        let ruleStr: String
        switch rule {
        case .progress: ruleStr = "↑ Progress (hit top reps last session)"
        case .hold:     ruleStr = "→ Hold (building reps)"
        case .backoff:  ruleStr = "↓ Back off (missed range)"
        }

        let diff = suggested - lastWeight
        let diffStr = diff == 0 ? "same weight" : (diff > 0 ? "+\(Int(diff))" : "\(Int(diff))")

        return "\(ruleStr) · \(diffStr) · \(sessions) session\(sessions == 1 ? "" : "s") · confidence: \(confidence.rawValue)"
    }

    // ═══════════════════════════════════════
    // UPDATE PROGRESSION STATE AFTER SESSION
    // ═══════════════════════════════════════

    static func updateProgressionState(
        state: ProgressionState,
        completedSets: [WorkoutLog],
        suggestedWeight: Double,
        targetRepsLow: Int,
        targetRepsHigh: Int,
        allRecentLogs: [WorkoutLog] = [],
        exerciseTier: ExerciseTier = .tier2,
        appliedRule: ProgressionRule = .hold
    ) {
        guard !completedSets.isEmpty else { return }

        // ─── Capture outgoing values BEFORE any writes ───
        state.previousWeight = state.lastCompletedWeight
        state.previousReps = state.lastSessionReps
        state.lastProgressionRule = appliedRule

        let sessionMaxWeight = completedSets.map { $0.weight }.max() ?? 0
        let workingSets = completedSets.filter { $0.weight >= sessionMaxWeight * 0.80 }
        let topSet = completedSets.filter { isValidForE1RM($0.reps) }.max(by: { $0.e1rm < $1.e1rm })

        // Track suggestion acceptance
        let _ = abs(sessionMaxWeight - suggestedWeight) < 2.6

        // Success/failure tracking
        let allHitTop = workingSets.allSatisfy { $0.reps >= targetRepsHigh }
        let missedLow = workingSets.filter { $0.reps < targetRepsLow }.count >= 2

        if allHitTop {
            state.consecutiveSuccesses += 1
            state.consecutiveFailures = 0
        } else if missedLow {
            state.consecutiveFailures += 1
            state.consecutiveSuccesses = 0
        }

        // Capture previous weight BEFORE mutating state
        let previousSessionWeight = state.lastSessionWeight

        // Update core fields
        state.bestE1RM = max(state.bestE1RM, topSet?.e1rm ?? 0)
        state.lastSuggestedWeight = suggestedWeight
        state.lastCompletedWeight = sessionMaxWeight
        state.lastSessionWeight = sessionMaxWeight
        state.lastSessionReps = topSet?.reps ?? 0
        state.lastSessionRPE = topSet?.rpe ?? 0

        // ─── e1RM EMA tracking ───
        let topE1rm = topSet?.e1rm ?? 0
        let topReps = topSet?.reps ?? 1
        let confidence = e1rmConfidence(topReps)
        let effectiveAlpha = 0.30 * confidence
        if state.emaE1rm == 0 {
            state.emaE1rm = topE1rm  // seed on first session
        } else if effectiveAlpha > 0 {
            state.emaE1rm = (state.emaE1rm * (1 - effectiveAlpha))
                          + (topE1rm * effectiveAlpha)
        }
        // Seed baseline at block start
        if state.totalExposures == 0 {
            state.baselineE1rm = topE1rm
        }

        state.totalExposures += 1

        // Re-anchor baseline every 6 exposures (~one training block of
        // high-frequency work). Without this, the baseline stayed locked at
        // the user's first-ever session forever — so after 30+ sessions the
        // trend reported a huge positive change against ancient baseline
        // and `.progress` fired even on plateaus or slight regressions.
        // Re-anchoring lets the engine detect real declines / stalls.
        if state.totalExposures % 6 == 0 && state.emaE1rm > 0 {
            state.baselineE1rm = state.emaE1rm
        }

        if state.lastCompletedWeight == state.previousWeight && state.previousWeight > 0 {
            state.weeksAtSameLoad += 1
        } else {
            state.weeksAtSameLoad = 0
        }

        state.updatedAt = Date()

        // ─── IFI tracking ───
        let ifi = computeIFI(sessionSets: completedSets)
        state.lastIFI = ifi
        // Exponential moving average over ~3 sessions
        state.ifiTrend = state.totalExposures <= 1 ? ifi : (state.ifiTrend * 2 + ifi) / 3

        // ─── Stall diagnosis tracking (with hysteresis) ───
        let isTier1 = exerciseTier == .tier1
        if !allRecentLogs.isEmpty {
            let sessions = groupBySession(allRecentLogs)
            let diagnosis = diagnoseStallWithIFI(
                ifiTrend: state.ifiTrend,
                sessions: sessions,
                isTier1: isTier1,
                previousDiagnosis: state.lastStallDiagnosis
            )
            if diagnosis == state.lastStallDiagnosis && diagnosis != .noStall {
                state.consecutiveStallDiagnoses += 1
            } else if diagnosis != .noStall {
                state.consecutiveStallDiagnoses = 1
            } else {
                state.consecutiveStallDiagnoses = 0
            }
            state.lastStallDiagnosis = diagnosis
        }
    }

    // ═══════════════════════════════════════
    // INTRASET FATIGUE INDEX (IFI)
    // Measures rep drop-off across working sets
    // ═══════════════════════════════════════

    static func computeIFI(sessionSets: [WorkoutLog]) -> Double {
        // Filter to working sets AND hard-effort sets only
        // rpe == 0 means not logged — include by default
        // rpe < 6 means confirmed warm-up — exclude
        let sessionMaxWeight = sessionSets.map { $0.weight }.max() ?? 0
        let workingSets = sessionSets
            .filter { $0.weight >= sessionMaxWeight * 0.80 }
            .filter { $0.rpe == 0 || $0.rpe >= 6.0 }
            .sorted { $0.setIndex < $1.setIndex }

        guard workingSets.count >= 2,
              let first = workingSets.first,
              let last = workingSets.last else { return 0.0 }

        let firstVolume = Double(first.reps) * first.weight
        let lastVolume  = Double(last.reps) * last.weight
        guard firstVolume > 0 else { return 0.0 }
        return max(0, (firstVolume - lastVolume) / firstVolume)
    }

    // ═══════════════════════════════════════
    // STALL DIAGNOSIS WITH IFI
    // Combines fatigue trend with performance trend
    // ═══════════════════════════════════════

    static func diagnoseStallWithIFI(
        ifiTrend: Double,
        sessions: [[WorkoutLog]],
        isTier1: Bool,
        previousDiagnosis: StallDiagnosis = .noStall
    ) -> StallDiagnosis {
        guard sessions.count >= 3 else { return .noStall }

        let e1rms = sessions.prefix(3).map { session in
            session.filter { isValidForE1RM($0.reps) }.map { $0.e1rm }.max() ?? 0
        }
        guard e1rms[0] > 0, e1rms[2] > 0 else { return .noStall }

        let e1rmChange = (e1rms[0] - e1rms[2]) / max(e1rms[2], 1)
        let e1rmDeclining = e1rmChange < -0.01
        let e1rmFlat = abs(e1rmChange) < 0.005

        // ─── Raw diagnosis ───
        let raw: StallDiagnosis
        if ifiTrend > 0.25 && e1rmDeclining {
            raw = .fatigueStall   // High fatigue + dropping strength → need deload
        } else if ifiTrend < 0.10 && e1rmFlat {
            raw = .intensityStall // Low fatigue + flat strength → not pushing hard enough
        } else if ifiTrend >= 0.10 && ifiTrend <= 0.25 && e1rmFlat {
            raw = .truePlateau    // Normal fatigue + flat strength → need exercise variation
        } else if ifiTrend > 0.30 {
            raw = .volumeStall    // Very high fatigue → too much volume
        } else {
            return .noStall
        }

        // ─── Hysteresis: stick with previous diagnosis unless IFI has moved 0.05+ away ───
        // Prevents flickering between diagnoses when IFI trend sits near a boundary
        if previousDiagnosis != .noStall && raw != previousDiagnosis {
            let boundariesForPrevious: ClosedRange<Double>
            switch previousDiagnosis {
            case .fatigueStall:   boundariesForPrevious = 0.20...1.0
            case .intensityStall: boundariesForPrevious = 0.0...0.15
            case .truePlateau:    boundariesForPrevious = 0.05...0.30
            case .volumeStall:    boundariesForPrevious = 0.25...1.0
            case .noStall:        boundariesForPrevious = 0.0...1.0
            }
            // If IFI trend is still within the hysteresis band of the previous diagnosis, keep it
            if boundariesForPrevious.contains(ifiTrend) {
                return previousDiagnosis
            }
        }

        return raw
    }

    // ═══════════════════════════════════════
    // VOLUME ZONE HELPER
    // ═══════════════════════════════════════

    static func volumeZone(currentSets: Int, muscle: String, tier: MuscleTier, experience: ExperienceLevel = .intermediate) -> VolumeZone {
        return VolumeZone.classify(
            directSets: currentSets,
            muscle: muscle,
            experience: experience,
            tier: tier
        )
    }

    // ═══════════════════════════════════════
    // DELOAD SUGGESTION
    // ═══════════════════════════════════════

    /// Suggests a deload if multiple progression states show fatigue indicators
    static func shouldSuggestDeload(progressionStates: [ProgressionState]) -> Bool {
        guard progressionStates.count >= 3 else { return false }
        let stalledCount = progressionStates.filter { $0.isStalled }.count
        let highIFICount = progressionStates.filter { $0.lastIFI > 0.25 }.count
        let threshold = max(2, progressionStates.count / 2)
        return stalledCount >= threshold || highIFICount >= threshold
    }

    // ═══════════════════════════════════════
    // TRAINING LOAD CONSISTENCY
    // Acute:Chronic ratio — measures how consistent
    // your recent training volume is vs your baseline.
    // ═══════════════════════════════════════

    /// Computes acute:chronic load ratio. Acute = last 7 days, Chronic = last 28 days weekly average.
    /// Used as a consistency metric — not an injury predictor. Returns nil if <14 days of data.
    static func computeACWR(logs: [WorkoutLog]) -> Double? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let fourWeeksAgo = cal.date(byAdding: .day, value: -28, to: today),
              let oneWeekAgo = cal.date(byAdding: .day, value: -7, to: today) else { return nil }

        let recentLogs = logs.filter { $0.workoutDate >= fourWeeksAgo }
        guard !recentLogs.isEmpty else { return nil }

        let dates = recentLogs.map { cal.startOfDay(for: $0.workoutDate) }
        guard let earliest = dates.min(), let latest = dates.max(),
              cal.dateComponents([.day], from: earliest, to: latest).day ?? 0 >= 14 else { return nil }

        let acuteLoad = Double(recentLogs.filter { $0.workoutDate >= oneWeekAgo }.count)
        let chronicLoad = Double(recentLogs.count) / 4.0

        guard chronicLoad > 0 else { return nil }
        return acuteLoad / chronicLoad
    }

    // ═══════════════════════════════════════
    // N=1 ADAPTATION: RESPONDS BETTER TO
    // ═══════════════════════════════════════

    // ═══════════════════════════════════════
    // N=1 ADAPTATION: PROGRESSION RATE
    // ═══════════════════════════════════════

    static func assessProgressionRate(
        progressionStates: [ProgressionState],
        experience: ExperienceLevel,
        weeksOfHistory: Int
    ) -> ProgressionRate? {
        guard weeksOfHistory >= 4 else { return nil }

        let expected: Double = switch experience {
        case .beginner:     0.025
        case .intermediate: 0.010
        case .advanced:     0.004
        case .elite:        0.002
        }

        let growthRates: [Double] = progressionStates.compactMap { state in
            guard state.bestE1RM > 0,
                  state.totalExposures >= 4,
                  state.lastCompletedWeight > 0 else { return nil }
            let current = state.lastCompletedWeight *
                (1.0 + Double(max(1, state.lastSessionReps)) / 30.0)
            return (current - state.bestE1RM) / max(state.bestE1RM, 1)
                / Double(state.totalExposures)
        }

        guard !growthRates.isEmpty else { return .normal }
        let avg = growthRates.reduce(0, +) / Double(growthRates.count)

        if avg > expected * 1.5 { return .fast }
        if avg < expected * 0.5 { return .slow }
        return .normal
    }

    static func assessRespondsBetterTo(
        volumeHistory: [(week: Int, sets: Int, e1rmChange: Double)],
        totalBlocksCompleted: Int
    ) -> RespondsBetterTo? {
        guard totalBlocksCompleted >= 2 else { return nil }
        guard volumeHistory.count >= 6 else { return nil }

        let sortedByVolume = volumeHistory.sorted { $0.sets < $1.sets }
        let medianSets = sortedByVolume[volumeHistory.count / 2].sets

        let highVolumeWeeks = volumeHistory.filter { $0.sets > medianSets }
        let lowVolumeWeeks  = volumeHistory.filter { $0.sets <= medianSets }

        guard !highVolumeWeeks.isEmpty && !lowVolumeWeeks.isEmpty else {
            return .balanced
        }

        let avgHigh = highVolumeWeeks.map { $0.e1rmChange }
            .reduce(0, +) / Double(highVolumeWeeks.count)
        let avgLow  = lowVolumeWeeks.map { $0.e1rmChange }
            .reduce(0, +) / Double(lowVolumeWeeks.count)

        let diff = avgHigh - avgLow
        if diff > ProgressionEngine.e1rmNoiseFloor  { return .highVolumeLowIntensity }
        if diff < -ProgressionEngine.e1rmNoiseFloor { return .lowVolumeHighIntensity }
        return .balanced
    }
}

// ═══════════════════════════════════════════
// RPE TABLE
// Used as optional brake, not primary engine
// ═══════════════════════════════════════════

struct RPETable {

    static func percent1RM(reps: Int, rpe: Double) -> Double {
        let clampedReps = max(1, min(reps, 12))
        let clampedRPE = max(6.0, min(rpe, 10.0))

        // Rows = reps 1-12, Cols = RPE 6.0-10.0 in 0.5 steps
        let table: [[Double]] = [
            [0.778, 0.800, 0.822, 0.844, 0.867, 0.889, 0.911, 0.956, 1.000],
            [0.758, 0.780, 0.801, 0.824, 0.846, 0.868, 0.890, 0.935, 0.978],
            [0.738, 0.759, 0.781, 0.803, 0.824, 0.846, 0.868, 0.913, 0.957],
            [0.717, 0.739, 0.760, 0.782, 0.803, 0.825, 0.846, 0.891, 0.935],
            [0.697, 0.718, 0.739, 0.761, 0.782, 0.803, 0.824, 0.869, 0.913],
            [0.677, 0.698, 0.719, 0.740, 0.761, 0.782, 0.803, 0.847, 0.892],
            [0.657, 0.678, 0.699, 0.719, 0.740, 0.761, 0.781, 0.826, 0.870],
            [0.636, 0.657, 0.678, 0.699, 0.719, 0.739, 0.760, 0.804, 0.848],
            [0.616, 0.637, 0.657, 0.678, 0.698, 0.718, 0.738, 0.782, 0.826],
            [0.596, 0.616, 0.637, 0.657, 0.677, 0.697, 0.717, 0.761, 0.804],
            [0.576, 0.596, 0.616, 0.636, 0.656, 0.676, 0.695, 0.739, 0.783],
            [0.556, 0.575, 0.595, 0.615, 0.635, 0.654, 0.674, 0.717, 0.761],
        ]

        let repIndex = clampedReps - 1
        let rpeIndex = max(0, min(Int((clampedRPE - 6.0) / 0.5), 8))
        return table[repIndex][rpeIndex]
    }

    static func recommendedWeight(e1rm: Double, targetReps: Int, targetRPE: Double) -> Double {
        let pct = percent1RM(reps: targetReps, rpe: targetRPE)
        return e1rm * pct
    }

    static func roundToPlate(_ weight: Double, useMetric: Bool) -> Double {
        let increment: Double = useMetric ? 2.5 : 5.0
        return (weight / increment).rounded() * increment
    }
}

// ═══════════════════════════════════════════
// RESULT TYPES
// ═══════════════════════════════════════════

struct ProgressionRecommendation {
    let recommendedWeight: Double
    let topSetWeight: Double
    let backoffWeight: Double
    let recommendedReps: Int
    let perSetReps: [Int]       // per-set targets based on last session + IFI
    let perSetPrescription: [ProgressionEngine.PerSetPrescription]  // weight-aware per-set
    let targetRPE: Double
    let basis: RecommendationBasis
    let confidence: RecommendationConfidence
    let stallDetected: Bool
    let stallReason: StallReason
    let progressionRule: ProgressionRule
    let debugNote: String

    var displayWeight: String {
        if recommendedWeight <= 0 { return "—" }
        return recommendedWeight.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(recommendedWeight))"
            : String(format: "%.1f", recommendedWeight)
    }

    var hasHistory: Bool { basis != .noHistory }

    /// Get the rep target for a specific set index. Falls back to MIRRORING
    /// the last available prescription rather than jumping to recommendedReps
    /// (= targetRepsHigh) — otherwise a template asking for 4 sets when the
    /// user logged 3 last time would show set 4 at the range upper bound,
    /// disconnected from the user's actual capacity.
    func repsForSet(_ index: Int) -> Int {
        if index < perSetPrescription.count {
            return perSetPrescription[index].repsTarget
        }
        if let last = perSetPrescription.last {
            return last.repsTarget
        }
        if index < perSetReps.count { return perSetReps[index] }
        if let lastFallback = perSetReps.last { return lastFallback }
        return recommendedReps
    }

    /// Get the full prescription for a specific set index. Mirrors the last
    /// available prescription for indices past the user's logged set count,
    /// so an extra-set scenario doesn't lose its weight/reps/role context.
    func prescriptionForSet(_ index: Int) -> ProgressionEngine.PerSetPrescription? {
        if index < perSetPrescription.count { return perSetPrescription[index] }
        return perSetPrescription.last
    }
}

enum RecommendationBasis: String {
    case noHistory = "no_history"
    case doublePrgresssion = "double_progression"
    case lastSessionBased = "last_session"
}

enum RecommendationConfidence: String {
    case none = "none"
    case low = "low"
    case medium = "medium"
    case high = "high"
}

enum ProgressionRule: String, Codable {
    case progress = "progress"
    case hold = "hold"
    case backoff = "backoff"
}

// ═══════════════════════════════════════════
// ARRAY EXTENSIONS
// ═══════════════════════════════════════════

extension Array where Element == Double {
    func average() -> Double {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Double(count)
    }
}

extension Array where Element == Int {
    func average() -> Double {
        guard !isEmpty else { return 0 }
        return Double(reduce(0, +)) / Double(count)
    }
}

// ═══════════════════════════════════════════
// STRENGTH BALANCE RATIOS
// ═══════════════════════════════════════════

struct BalanceRatio: Identifiable {
    let id: String
    let label: String
    let ratio: Double
    let idealLow: Double
    let idealHigh: Double

    var status: String {
        if ratio < idealLow { return "low" }
        if ratio > idealHigh { return "high" }
        return "balanced"
    }

    var isBalanced: Bool { status == "balanced" }
}

enum StrengthAnalytics {

    /// Compute push:pull, posterior:anterior, etc from best e1RMs per exercise.
    static func computeBalanceRatios(logs: [WorkoutLog]) -> [BalanceRatio] {
        // Best e1RM per exercise
        let grouped = Dictionary(grouping: logs) { $0.exerciseKey }
        let bestE1RM: [String: Double] = grouped.compactMapValues { logs in
            logs.map { $0.e1rm }.max()
        }

        // Classify by movement pattern from ExerciseDictionary
        var pushBest: Double = 0
        var pullBest: Double = 0
        var squatBest: Double = 0
        var hingeBest: Double = 0
        var ohpBest: Double = 0
        var benchBest: Double = 0

        for (key, e1) in bestE1RM {
            guard let def = ExerciseDictionary.all[key] else { continue }
            switch def.movementPattern {
            case .horizontalPush:
                pushBest = max(pushBest, e1)
                if key.contains("bench") && !key.contains("incline") && !key.contains("close") {
                    benchBest = max(benchBest, e1)
                }
            case .verticalPush:
                pushBest = max(pushBest, e1)
                ohpBest = max(ohpBest, e1)
            case .horizontalPull, .verticalPull:
                pullBest = max(pullBest, e1)
            case .squat, .lunge:
                squatBest = max(squatBest, e1)
            case .hinge, .hipThrust:
                hingeBest = max(hingeBest, e1)
            default: break
            }
        }

        var results: [BalanceRatio] = []

        if pushBest > 0 && pullBest > 0 {
            results.append(BalanceRatio(id: "push_pull", label: "Push : Pull",
                                        ratio: pushBest / pullBest, idealLow: 0.85, idealHigh: 1.15))
        }
        if hingeBest > 0 && squatBest > 0 {
            results.append(BalanceRatio(id: "post_ant", label: "Posterior : Anterior",
                                        ratio: hingeBest / squatBest, idealLow: 0.70, idealHigh: 1.10))
        }
        if ohpBest > 0 && benchBest > 0 {
            results.append(BalanceRatio(id: "ohp_bench", label: "OHP : Bench",
                                        ratio: ohpBest / benchBest, idealLow: 0.55, idealHigh: 0.75))
        }
        if squatBest > 0 && hingeBest > 0 {
            // Use deadlift specifically if available
            let dlBest = bestE1RM.filter { $0.key.contains("deadlift") && !$0.key.contains("romanian") }.values.max() ?? hingeBest
            if dlBest > 0 {
                results.append(BalanceRatio(id: "squat_dl", label: "Squat : Deadlift",
                                            ratio: squatBest / dlBest, idealLow: 0.75, idealHigh: 0.90))
            }
        }

        return results
    }

    // ═══════════════════════════════════════════
    // GENETIC POTENTIAL ESTIMATION
    // ═══════════════════════════════════════════

    struct PotentialEstimate: Identifiable {
        let id: String  // exercise key
        let displayName: String
        let currentE1RM: Double
        let estimatedCeiling: Double
        let percentOfPotential: Double  // 0-100

        var tier: String {
            if percentOfPotential >= 80 { return "Elite" }
            if percentOfPotential >= 60 { return "Advanced" }
            if percentOfPotential >= 40 { return "Intermediate" }
            return "Beginner"
        }

        var tierColor: String {
            if percentOfPotential >= 80 { return "gold" }
            if percentOfPotential >= 60 { return "green" }
            if percentOfPotential >= 40 { return "blue" }
            return "dim"
        }
    }

    /// Bodyweight-relative strength ceilings for natural male lifters.
    /// Female multipliers are ~60-65% of male values.
    private static let maleCeilings: [String: Double] = [
        "bench_press_barbell": 1.75,
        "incline_bench_barbell": 1.50,
        "squat_barbell": 2.25,
        "front_squat_barbell": 1.80,
        "hack_squat": 2.00,
        "deadlift_barbell": 2.75,
        "rdl_barbell": 2.20,
        "overhead_press_barbell": 1.15,
        "barbell_row": 1.40,
        "pendlay_row": 1.40,
        "close_grip_bench": 1.50,
    ]

    static func estimateGeneticPotential(
        bodyweight: Double,
        logs: [WorkoutLog]
    ) -> [PotentialEstimate] {
        guard bodyweight > 0 else { return [] }

        let grouped = Dictionary(grouping: logs) { $0.exerciseKey }
        var results: [PotentialEstimate] = []

        for (key, exerciseLogs) in grouped {
            guard let multiplier = maleCeilings[key] else { continue }
            guard let bestE1RM = exerciseLogs.map({ $0.e1rm }).max(), bestE1RM > 0 else { continue }

            let ceiling = bodyweight * multiplier
            let pct = min(100, (bestE1RM / ceiling) * 100)
            let name = ExerciseDictionary.all[key]?.displayName
                ?? key.replacingOccurrences(of: "_", with: " ").capitalized

            results.append(PotentialEstimate(
                id: key, displayName: name,
                currentE1RM: bestE1RM, estimatedCeiling: ceiling,
                percentOfPotential: pct
            ))
        }

        return results.sorted { $0.percentOfPotential > $1.percentOfPotential }
    }

    // ═══════════════════════════════════════════
    // PREDICTIVE 1RM TIMELINE
    // ═══════════════════════════════════════════

    struct PredictedTimeline {
        let exerciseKey: String
        let currentE1RM: Double
        let targetWeight: Double
        let weeklyGainRate: Double
        let estimatedWeeks: Int
        let confidence: String  // "low" / "medium" / "high"
    }

    /// Predict weeks to reach a target weight based on e1RM trend.
    static func predictTimeToTarget(
        logs: [WorkoutLog],
        exerciseKey: String,
        targetWeight: Double
    ) -> PredictedTimeline? {
        let exLogs = logs.filter { $0.exerciseKey == exerciseKey }
        let cal = Calendar.current
        let bySession = Dictionary(grouping: exLogs) { cal.startOfDay(for: $0.workoutDate) }
            .sorted { $0.key < $1.key }

        guard bySession.count >= 4 else { return nil }

        // Best e1RM per session with date
        let points: [(date: Date, e1rm: Double)] = bySession.map { ($0.key, $0.value.map { $0.e1rm }.max() ?? 0) }
            .filter { $0.1 > 0 }
        guard points.count >= 4 else { return nil }

        let currentE1RM = points.last!.e1rm
        guard targetWeight > currentE1RM else { return nil }

        // Linear regression: slope = Σ((x-x̄)(y-ȳ)) / Σ((x-x̄)²)
        let firstDate = points.first!.date
        let xs = points.map { cal.dateComponents([.day], from: firstDate, to: $0.date).day ?? 0 }
        let ys = points.map { $0.e1rm }
        let n = Double(points.count)
        let xMean = Double(xs.reduce(0, +)) / n
        let yMean = ys.reduce(0, +) / n

        var num: Double = 0
        var den: Double = 0
        for i in 0..<points.count {
            let dx = Double(xs[i]) - xMean
            let dy = ys[i] - yMean
            num += dx * dy
            den += dx * dx
        }

        guard den > 0 else { return nil }
        let dailySlope = num / den
        guard dailySlope > 0 else { return nil }  // not progressing

        let weeklyRate = dailySlope * 7
        let daysToTarget = (targetWeight - currentE1RM) / dailySlope
        let weeksToTarget = Int(ceil(daysToTarget / 7))

        let confidence: String
        if points.count >= 12 { confidence = "high" }
        else if points.count >= 6 { confidence = "medium" }
        else { confidence = "low" }

        return PredictedTimeline(
            exerciseKey: exerciseKey,
            currentE1RM: currentE1RM,
            targetWeight: targetWeight,
            weeklyGainRate: weeklyRate,
            estimatedWeeks: weeksToTarget,
            confidence: confidence
        )
    }
}
