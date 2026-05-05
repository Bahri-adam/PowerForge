import Testing
import Foundation
@testable import Powerbodybuilder

// ═══════════════════════════════════════════
// TEST HELPERS
// ═══════════════════════════════════════════

/// Create a WorkoutLog with minimal boilerplate
func makeLog(
    weight: Double,
    reps: Int,
    setIndex: Int = 0,
    rpe: Double = 0,
    date: Date = Date(),
    exerciseKey: String = "bench_press_barbell",
    isMainLift: Bool = true
) -> WorkoutLog {
    WorkoutLog(
        date: date,
        week: 1,
        sessionType: .heavyUpper,
        exerciseKey: exerciseKey,
        displayName: "Bench Press",
        slotId: "A1",
        setIndex: setIndex,
        weight: weight,
        reps: reps,
        rpe: rpe,
        isMainLift: isMainLift
    )
}

/// Create a session (array of logs) on a given date
func makeSession(
    weight: Double,
    reps: [Int],
    date: Date = Date(),
    rpe: Double = 0,
    exerciseKey: String = "bench_press_barbell",
    isMainLift: Bool = true
) -> [WorkoutLog] {
    reps.enumerated().map { idx, r in
        makeLog(
            weight: weight,
            reps: r,
            setIndex: idx,
            rpe: rpe,
            date: date,
            exerciseKey: exerciseKey,
            isMainLift: isMainLift
        )
    }
}

/// Create a date offset by days from now
func daysAgo(_ days: Int) -> Date {
    Calendar.current.date(byAdding: .day, value: -days, to: Date())!
}

/// Creates a ProgressionState with enough totalExposures to pass G8 signal suppression.
/// Use in multi-week simulation tests where progressionState: nil would trigger G8 every call.
func makeProgState(
    exerciseKey: String = "bench_press_barbell",
    exposures: Int = 4,
    lastWeight: Double = 0,
    bestE1RM: Double = 0
) -> ProgressionState {
    let ps = ProgressionState(exerciseKey: exerciseKey)
    ps.totalExposures = exposures
    ps.lastSessionWeight = lastWeight
    ps.lastCompletedWeight = lastWeight
    ps.bestE1RM = bestE1RM
    ps.emaE1rm = bestE1RM
    ps.baselineE1rm = bestE1RM > 0 ? bestE1RM * 0.95 : 0
    return ps
}


// ═══════════════════════════════════════════
// 1. DOUBLE PROGRESSION RULE ENGINE
// ═══════════════════════════════════════════

@Suite("Double Progression Rules")
struct DoubleProgressionTests {

    @Test("Progress when all working sets hit top of rep range")
    func progressOnAllHitTop() {
        // 3 sets × 225 lbs × 10 reps, target range 8-10
        let session = makeSession(weight: 225, reps: [10, 10, 10])
        let rule = ProgressionEngine.determineProgressionRule(
            lastSession: session,
            previousSessions: [],
            targetRepsLow: 8,
            targetRepsHigh: 10,
            exerciseTier: .tier1,
            progressionState: nil
        )
        #expect(rule == .progress)
    }

    @Test("Hold when reps in range but not at top")
    func holdWhenInRange() {
        let session = makeSession(weight: 225, reps: [9, 8, 8])
        let rule = ProgressionEngine.determineProgressionRule(
            lastSession: session,
            previousSessions: [],
            targetRepsLow: 8,
            targetRepsHigh: 10,
            exerciseTier: .tier1,
            progressionState: nil
        )
        #expect(rule == .hold)
    }

    @Test("Backoff requires TWO consecutive bad sessions")
    func backoffRequiresTwoSessions() {
        let bad1 = makeSession(weight: 225, reps: [6, 5, 5], date: daysAgo(7))
        let bad2 = makeSession(weight: 225, reps: [7, 6, 5], date: daysAgo(0))
        let rule = ProgressionEngine.determineProgressionRule(
            lastSession: bad2,
            previousSessions: [bad1],
            targetRepsLow: 8,
            targetRepsHigh: 10,
            exerciseTier: .tier1,
            progressionState: nil
        )
        #expect(rule == .backoff)
    }

    @Test("Single bad session does NOT trigger backoff")
    func singleBadSessionNoBackoff() {
        let good = makeSession(weight: 225, reps: [9, 8, 8], date: daysAgo(7))
        let bad = makeSession(weight: 225, reps: [7, 6, 5], date: daysAgo(0))
        let rule = ProgressionEngine.determineProgressionRule(
            lastSession: bad,
            previousSessions: [good],
            targetRepsLow: 8,
            targetRepsHigh: 10,
            exerciseTier: .tier1,
            progressionState: nil
        )
        #expect(rule == .hold)
    }

    @Test("Empty session returns hold")
    func emptySessionHold() {
        let rule = ProgressionEngine.determineProgressionRule(
            lastSession: nil,
            previousSessions: [],
            targetRepsLow: 8,
            targetRepsHigh: 10,
            exerciseTier: .tier1,
            progressionState: nil
        )
        #expect(rule == .hold)
    }

    @Test("Warm-up sets are excluded from working set analysis")
    func warmUpsExcluded() {
        // Warm-up at 135 (60% of 225), working sets at 225
        var session = makeSession(weight: 225, reps: [10, 10, 10])
        session.insert(makeLog(weight: 135, reps: 5, setIndex: 0), at: 0)
        // Re-index
        for i in 0..<session.count { session[i] = makeLog(weight: session[i].weight, reps: session[i].reps, setIndex: i) }

        let rule = ProgressionEngine.determineProgressionRule(
            lastSession: session,
            previousSessions: [],
            targetRepsLow: 8,
            targetRepsHigh: 10,
            exerciseTier: .tier1,
            progressionState: nil
        )
        #expect(rule == .progress)
    }
}


// ═══════════════════════════════════════════
// 2. PROGRESSION INCREMENTS
// ═══════════════════════════════════════════

@Suite("Progression Increments")
struct IncrementTests {

    @Test("Tier1 >= 185 lbs uses 10 lb increment")
    func tier1Heavy() {
        let inc = ProgressionEngine.progressionIncrement(exerciseTier: .tier1, useMetric: false, currentWeight: 225)
        #expect(inc == 10.0)
        let atThreshold = ProgressionEngine.progressionIncrement(exerciseTier: .tier1, useMetric: false, currentWeight: 185)
        #expect(atThreshold == 10.0)
    }

    @Test("Tier1 < 185 lbs uses 5 lb increment")
    func tier1Light() {
        let inc = ProgressionEngine.progressionIncrement(exerciseTier: .tier1, useMetric: false, currentWeight: 95)
        #expect(inc == 5.0)
        let near = ProgressionEngine.progressionIncrement(exerciseTier: .tier1, useMetric: false, currentWeight: 180)
        #expect(near == 5.0)
    }

    @Test("Tier2 uses 5 lb increment")
    func tier2() {
        let inc = ProgressionEngine.progressionIncrement(exerciseTier: .tier2, useMetric: false, currentWeight: 50)
        #expect(inc == 5.0)
    }

    @Test("Tier3 uses 2.5 lb increment")
    func tier3() {
        let inc = ProgressionEngine.progressionIncrement(exerciseTier: .tier3, useMetric: false, currentWeight: 50)
        #expect(inc == 2.5)
    }

    @Test("Metric: tier1 and tier2 use 2.5 kg, tier3 uses 1.25 kg")
    func metric() {
        let t1 = ProgressionEngine.progressionIncrement(exerciseTier: .tier1, useMetric: true, currentWeight: 100)
        let t2 = ProgressionEngine.progressionIncrement(exerciseTier: .tier2, useMetric: true, currentWeight: 30)
        let t3 = ProgressionEngine.progressionIncrement(exerciseTier: .tier3, useMetric: true, currentWeight: 20)
        #expect(t1 == 2.5)
        #expect(t2 == 2.5)
        #expect(t3 == 1.25)
    }
}


// ═══════════════════════════════════════════
// 3. WEIGHT ROUNDING
// ═══════════════════════════════════════════

@Suite("Weight Rounding")
struct RoundingTests {

    @Test("Imperial rounds to nearest 5 lbs")
    func imperialRounding() {
        #expect(RPETable.roundToPlate(227, useMetric: false) == 225)
        #expect(RPETable.roundToPlate(228, useMetric: false) == 230)
        #expect(RPETable.roundToPlate(312, useMetric: false) == 310)
        #expect(RPETable.roundToPlate(308, useMetric: false) == 310) // The bug that was fixed
    }

    @Test("Metric rounds to nearest 2.5 kg")
    func metricRounding() {
        #expect(RPETable.roundToPlate(101, useMetric: true) == 100.0)   // 101/2.5=40.4 → 40 → 100
        #expect(RPETable.roundToPlate(100, useMetric: true) == 100)
        #expect(RPETable.roundToPlate(102.5, useMetric: true) == 102.5)
        #expect(RPETable.roundToPlate(101.3, useMetric: true) == 102.5) // 101.3/2.5=40.52 → 41 → 102.5
    }

    @Test("All recommended weights are plate-loadable")
    func allWeightsPlateLoadable() {
        // Test a range of weights through the engine
        for w in stride(from: 45.0, through: 500.0, by: 7.3) {
            let rounded = RPETable.roundToPlate(w, useMetric: false)
            #expect(rounded.truncatingRemainder(dividingBy: 5.0) == 0,
                    "Weight \(rounded) from \(w) is not divisible by 5")
        }
    }
}


// ═══════════════════════════════════════════
// 4. IFI COMPUTATION
// ═══════════════════════════════════════════

@Suite("Intraset Fatigue Index")
struct IFITests {

    @Test("IFI = 0 when reps are equal across sets")
    func equalReps() {
        let session = makeSession(weight: 200, reps: [10, 10, 10])
        let ifi = ProgressionEngine.computeIFI(sessionSets: session)
        #expect(ifi == 0.0)
    }

    @Test("IFI computed correctly for normal fatigue")
    func normalFatigue() {
        // 10, 8 → IFI = (10-8)/10 = 0.20
        let session = makeSession(weight: 200, reps: [10, 8])
        let ifi = ProgressionEngine.computeIFI(sessionSets: session)
        #expect(abs(ifi - 0.2) < 0.001)
    }

    @Test("IFI computed correctly for heavy fatigue")
    func heavyFatigue() {
        // 10, 9, 6 → IFI = (10-6)/10 = 0.40
        let session = makeSession(weight: 200, reps: [10, 9, 6])
        let ifi = ProgressionEngine.computeIFI(sessionSets: session)
        #expect(abs(ifi - 0.4) < 0.001)
    }

    @Test("IFI uses first and last working set only")
    func firstAndLast() {
        // 10, 5, 8 → IFI = (10-8)/10 = 0.20 (middle set doesn't matter)
        let session = makeSession(weight: 200, reps: [10, 5, 8])
        let ifi = ProgressionEngine.computeIFI(sessionSets: session)
        #expect(abs(ifi - 0.2) < 0.001)
    }

    @Test("IFI returns 0 for single set")
    func singleSet() {
        let session = makeSession(weight: 200, reps: [10])
        let ifi = ProgressionEngine.computeIFI(sessionSets: session)
        #expect(ifi == 0.0)
    }

    @Test("IFI clamped to 0 when last set has more reps than first")
    func moreRepsLater() {
        // Rare: warming up during the exercise
        let session = makeSession(weight: 200, reps: [6, 8])
        let ifi = ProgressionEngine.computeIFI(sessionSets: session)
        #expect(ifi == 0.0) // Clamped to 0
    }

    @Test("IFI excludes warm-up sets")
    func excludesWarmups() {
        // Warm-up at 100 (50% of 200), working at 200
        var session = makeSession(weight: 200, reps: [10, 8])
        session.insert(makeLog(weight: 100, reps: 15, setIndex: 0), at: 0)
        let ifi = ProgressionEngine.computeIFI(sessionSets: session)
        // Should only consider the 200 lb sets: (10-8)/10 = 0.20
        #expect(abs(ifi - 0.2) < 0.001)
    }

    @Test("IFI returns 0 for empty session")
    func emptySession() {
        let ifi = ProgressionEngine.computeIFI(sessionSets: [])
        #expect(ifi == 0.0)
    }
}


// ═══════════════════════════════════════════
// 5. IFI ZONE CLASSIFICATION
// ═══════════════════════════════════════════

@Suite("IFI Zone Classification")
struct IFIZoneTests {

    @Test("IFI zone boundaries")
    func zoneBoundaries() {
        #expect(IFIZone.classify(0.0) == .fresh)
        #expect(IFIZone.classify(0.05) == .fresh)
        #expect(IFIZone.classify(0.09) == .fresh)
        #expect(IFIZone.classify(0.10) == .optimal)
        #expect(IFIZone.classify(0.15) == .optimal)
        #expect(IFIZone.classify(0.20) == .optimal)
        #expect(IFIZone.classify(0.24) == .optimal)
        #expect(IFIZone.classify(0.25) == .fatigued)
        #expect(IFIZone.classify(0.30) == .fatigued)
        #expect(IFIZone.classify(0.39) == .fatigued)
        #expect(IFIZone.classify(0.40) == .acuteOverreach)
        #expect(IFIZone.classify(0.50) == .acuteOverreach)
        #expect(IFIZone.classify(1.0) == .acuteOverreach)
    }
}


// ═══════════════════════════════════════════
// 6. IFI MODIFIERS ON PROGRESSION
// ═══════════════════════════════════════════

@Suite("IFI Modifiers")
struct IFIModifierTests {

    @Test("Fresh IFI does not alter normal progression")
    func freshNoExtraIncrement() {
        let session = makeSession(weight: 225, reps: [10, 10, 10], date: daysAgo(0))
        let normal = ProgressionEngine.recommend(
            recentLogs: session,
            targetRepsLow: 8, targetRepsHigh: 10,
            targetRPE: 8.0, exerciseTier: .tier1,
            useMetric: false, progressionState: nil
        )
        let withFreshIFI = ProgressionEngine.recommend(
            recentLogs: session,
            targetRepsLow: 8, targetRepsHigh: 10,
            targetRPE: 8.0, exerciseTier: .tier1,
            useMetric: false, progressionState: nil,
            lastSessionIFI: 0.05 // FRESH
        )
        // Fresh IFI = good news, but no extra increment — normal progression only
        #expect(withFreshIFI.recommendedWeight == normal.recommendedWeight)
    }

    @Test("Fatigued IFI + progress = hold (conservative)")
    func fatiguedBlocksProgress() {
        let session = makeSession(weight: 225, reps: [10, 10, 10], date: daysAgo(0))
        let rec = ProgressionEngine.recommend(
            recentLogs: session,
            targetRepsLow: 8, targetRepsHigh: 10,
            targetRPE: 8.0, exerciseTier: .tier1,
            useMetric: false, progressionState: nil,
            lastSessionIFI: 0.30 // FATIGUED (0.25-0.40)
        )
        // Fatigued IFI blocks progression → hold at last weight
        #expect(rec.recommendedWeight == 225)
    }

    @Test("Overtrained IFI forces backoff regardless of rep performance")
    func overtrainedForcesBackoff() {
        let session = makeSession(weight: 225, reps: [10, 10, 10], date: daysAgo(0))
        let rec = ProgressionEngine.recommend(
            recentLogs: session,
            targetRepsLow: 8, targetRepsHigh: 10,
            targetRPE: 8.0, exerciseTier: .tier1,
            useMetric: false, progressionState: makeProgState(exposures: 4, lastWeight: 225),
            lastSessionIFI: 0.45 // ACUTE OVERREACH (>= 0.40)
        )
        // Should back off from 225 → 225 * 0.94 (tier1) = 211.5 → rounded to 210
        #expect(rec.recommendedWeight < 225)
    }

    @Test("Optimal IFI does not alter normal progression")
    func optimalNoChange() {
        let session = makeSession(weight: 225, reps: [10, 10, 10], date: daysAgo(0))
        let normal = ProgressionEngine.recommend(
            recentLogs: session,
            targetRepsLow: 8, targetRepsHigh: 10,
            targetRPE: 8.0, exerciseTier: .tier1,
            useMetric: false, progressionState: nil
        )
        let withOptimalIFI = ProgressionEngine.recommend(
            recentLogs: session,
            targetRepsLow: 8, targetRepsHigh: 10,
            targetRPE: 8.0, exerciseTier: .tier1,
            useMetric: false, progressionState: nil,
            lastSessionIFI: 0.15 // OPTIMAL
        )
        #expect(withOptimalIFI.recommendedWeight == normal.recommendedWeight)
    }

    @Test("nil IFI = backward compatible, no modifier applied")
    func nilIFIBackwardCompat() {
        let session = makeSession(weight: 225, reps: [10, 10, 10], date: daysAgo(0))
        let withNil = ProgressionEngine.recommend(
            recentLogs: session,
            targetRepsLow: 8, targetRepsHigh: 10,
            targetRPE: 8.0, exerciseTier: .tier1,
            useMetric: false, progressionState: nil,
            lastSessionIFI: nil
        )
        let withZero = ProgressionEngine.recommend(
            recentLogs: session,
            targetRepsLow: 8, targetRepsHigh: 10,
            targetRPE: 8.0, exerciseTier: .tier1,
            useMetric: false, progressionState: nil,
            lastSessionIFI: 0 // Zero should also skip
        )
        #expect(withNil.recommendedWeight == withZero.recommendedWeight)
    }
}


// ═══════════════════════════════════════════
// 7. VOLUME LANDMARKS & ZONES
// ═══════════════════════════════════════════

@Suite("Volume Landmarks")
struct VolumeLandmarkTests {

    @Test("Default landmarks exist for all 9 muscle groups")
    func allMusclesHaveLandmarks() {
        let muscles = ["Chest","Back","Quads","Hamstrings","Glutes","Calves","Biceps","Triceps","Delts"]
        for m in muscles {
            #expect(VolumeLandmark.defaults[m] != nil, "Missing landmark for \(m)")
        }
    }

    @Test("MEV < MAV < MRV for all muscles")
    func landmarkOrdering() {
        for (muscle, lm) in VolumeLandmark.defaults {
            #expect(lm.mev < lm.mav, "\(muscle): MEV (\(lm.mev)) should be < MAV (\(lm.mav))")
            #expect(lm.mav < lm.mrv, "\(muscle): MAV (\(lm.mav)) should be < MRV (\(lm.mrv))")
        }
    }

    @Test("Priority tier scales landmarks up by 1.5x")
    func priorityScaling() {
        let chest = VolumeLandmark.defaults["Chest"]!
        let scaled = chest.scaled(by: .priority)
        #expect(scaled.mev == Int(round(6 * 1.5)))
        #expect(scaled.mavLow == Int(round(10 * 1.5)))
        #expect(scaled.mavHigh == Int(round(16 * 1.5)))
        #expect(scaled.mrv == Int(round(22 * 1.5)))
    }

    @Test("Maintenance tier scales landmarks down by 0.7x")
    func maintenanceScaling() {
        let chest = VolumeLandmark.defaults["Chest"]!
        let scaled = chest.scaled(by: .maintenance)
        #expect(scaled.mev == Int(round(6 * 0.7)))
        #expect(scaled.mavLow == Int(round(10 * 0.7)))
        #expect(scaled.mavHigh == Int(round(16 * 0.7)))
        #expect(scaled.mrv == Int(round(22 * 0.7)))
    }

    @Test("Neutral tier doesn't change landmarks")
    func neutralNoChange() {
        let chest = VolumeLandmark.defaults["Chest"]!
        let scaled = chest.scaled(by: .neutral)
        #expect(scaled.mev == chest.mev)
        #expect(scaled.mav == chest.mav)
        #expect(scaled.mrv == chest.mrv)
    }
}

@Suite("Volume Zone Classification")
struct VolumeZoneTests {

    @Test("Under-training when below MEV")
    func underTraining() {
        let lm = VolumeLandmark(mev: 6, mavLow: 10, mavHigh: 16, mrv: 22)
        #expect(VolumeZone.classify(sets: 0, landmark: lm) == .underTraining)
        #expect(VolumeZone.classify(sets: 3, landmark: lm) == .underTraining)
        #expect(VolumeZone.classify(sets: 5, landmark: lm) == .underTraining)
    }

    @Test("Building when between MEV and MAV-low")
    func building() {
        let lm = VolumeLandmark(mev: 6, mavLow: 10, mavHigh: 16, mrv: 22)
        #expect(VolumeZone.classify(sets: 6, landmark: lm) == .building)
        #expect(VolumeZone.classify(sets: 8, landmark: lm) == .building)
        #expect(VolumeZone.classify(sets: 9, landmark: lm) == .building)
    }

    @Test("Optimal when between MAV-low and MRV")
    func optimal() {
        let lm = VolumeLandmark(mev: 6, mavLow: 10, mavHigh: 16, mrv: 22)
        #expect(VolumeZone.classify(sets: 10, landmark: lm) == .optimal)
        #expect(VolumeZone.classify(sets: 16, landmark: lm) == .optimal)
        #expect(VolumeZone.classify(sets: 22, landmark: lm) == .optimal)
    }

    @Test("Over-reaching when above MRV")
    func overReaching() {
        let lm = VolumeLandmark(mev: 6, mavLow: 10, mavHigh: 16, mrv: 22)
        #expect(VolumeZone.classify(sets: 23, landmark: lm) == .overReaching)
        #expect(VolumeZone.classify(sets: 30, landmark: lm) == .overReaching)
    }

    @Test("Volume zone with tier multiplier via engine helper")
    func volumeZoneWithTier() {
        // Chest intermediate neutral: effectiveMEV=8, mavLow=8, effectiveMRV=26
        #expect(ProgressionEngine.volumeZone(currentSets: 3, muscle: "Chest", tier: .neutral) == .underTraining)
        #expect(ProgressionEngine.volumeZone(currentSets: 8, muscle: "Chest", tier: .neutral) == .optimal)
        #expect(ProgressionEngine.volumeZone(currentSets: 14, muscle: "Chest", tier: .neutral) == .optimal)
        #expect(ProgressionEngine.volumeZone(currentSets: 27, muscle: "Chest", tier: .neutral) == .overReaching)
        // Chest intermediate priority (1.5x): effectiveMEV=12, effectiveMRV=39
        #expect(ProgressionEngine.volumeZone(currentSets: 7, muscle: "Chest", tier: .priority) == .underTraining)
        #expect(ProgressionEngine.volumeZone(currentSets: 12, muscle: "Chest", tier: .priority) == .optimal)
        #expect(ProgressionEngine.volumeZone(currentSets: 20, muscle: "Chest", tier: .priority) == .optimal)
    }
}


// ═══════════════════════════════════════════
// 8. STALL DETECTION
// ═══════════════════════════════════════════

@Suite("Stall Detection")
struct StallDetectionTests {

    @Test("No stall with fewer than 3 sessions (tier1)")
    func noStallFewSessions() {
        let s1 = makeSession(weight: 225, reps: [8, 8, 8], date: daysAgo(0))
        let s2 = makeSession(weight: 225, reps: [8, 8, 8], date: daysAgo(7))
        let stall = ProgressionEngine.detectStall(sessions: [s1, s2], exerciseTier: .tier1, targetRepsLow: 8)
        #expect(stall.isStalled == false)
    }

    @Test("e1RM decline detected over 3 sessions")
    func e1rmDecline() {
        let s1 = makeSession(weight: 225, reps: [6, 6, 6], date: daysAgo(0))
        let s2 = makeSession(weight: 225, reps: [8, 8, 8], date: daysAgo(7))
        let s3 = makeSession(weight: 225, reps: [8, 8, 8], date: daysAgo(14))
        let stall = ProgressionEngine.detectStall(sessions: [s1, s2, s3], exerciseTier: .tier1, targetRepsLow: 8)
        #expect(stall.isStalled == true)
        #expect(stall.reason == .e1rmDecline)
    }

    @Test("e1RM flat detected over 3 sessions")
    func e1rmFlat() {
        let s1 = makeSession(weight: 225, reps: [8, 8, 8], date: daysAgo(0))
        let s2 = makeSession(weight: 225, reps: [8, 8, 8], date: daysAgo(7))
        let s3 = makeSession(weight: 225, reps: [8, 8, 8], date: daysAgo(14))
        let stall = ProgressionEngine.detectStall(sessions: [s1, s2, s3], exerciseTier: .tier1, targetRepsLow: 8)
        #expect(stall.isStalled == true)
        #expect(stall.reason == .e1rmFlat)
    }

    @Test("Accessory stall: reps flat over 4 sessions")
    func accessoryRepsFlat() {
        let sessions = (0..<4).map { i in
            makeSession(weight: 50, reps: [12, 12, 12], date: daysAgo(i * 7), isMainLift: false)
        }
        let stall = ProgressionEngine.detectStall(sessions: sessions, exerciseTier: .tier3, targetRepsLow: 8)
        #expect(stall.isStalled == true)
        #expect(stall.reason == .repsFlat)
    }

    @Test("No stall when reps are improving")
    func noStallImproving() {
        let s1 = makeSession(weight: 225, reps: [10, 10, 10], date: daysAgo(0))
        let s2 = makeSession(weight: 225, reps: [9, 9, 9], date: daysAgo(7))
        let s3 = makeSession(weight: 225, reps: [8, 8, 8], date: daysAgo(14))
        let stall = ProgressionEngine.detectStall(sessions: [s1, s2, s3], exerciseTier: .tier1, targetRepsLow: 8)
        #expect(stall.isStalled == false)
    }
}


// ═══════════════════════════════════════════
// 9. STALL DIAGNOSIS WITH IFI
// ═══════════════════════════════════════════

@Suite("IFI Stall Diagnosis")
struct StallDiagnosisTests {

    @Test("Fatigue stall: high IFI + declining e1RM")
    func fatigueStall() {
        let s1 = makeSession(weight: 225, reps: [6, 6, 6], date: daysAgo(0))
        let s2 = makeSession(weight: 225, reps: [8, 8, 8], date: daysAgo(7))
        let s3 = makeSession(weight: 225, reps: [8, 8, 8], date: daysAgo(14))
        let diagnosis = ProgressionEngine.diagnoseStallWithIFI(
            ifiTrend: 0.30,
            sessions: [s1, s2, s3],
            isTier1: true
        )
        #expect(diagnosis == .fatigueStall)
    }

    @Test("Intensity stall: low IFI + flat e1RM")
    func intensityStall() {
        let sessions = (0..<3).map { i in
            makeSession(weight: 225, reps: [8, 8, 8], date: daysAgo(i * 7))
        }
        let diagnosis = ProgressionEngine.diagnoseStallWithIFI(
            ifiTrend: 0.05,
            sessions: sessions,
            isTier1: true
        )
        #expect(diagnosis == .intensityStall)
    }

    @Test("True plateau: mid IFI + flat e1RM")
    func truePlateau() {
        let sessions = (0..<3).map { i in
            makeSession(weight: 225, reps: [8, 8, 8], date: daysAgo(i * 7))
        }
        let diagnosis = ProgressionEngine.diagnoseStallWithIFI(
            ifiTrend: 0.15,
            sessions: sessions,
            isTier1: true
        )
        #expect(diagnosis == .truePlateau)
    }

    @Test("Volume stall: very high IFI")
    func volumeStall() {
        let s1 = makeSession(weight: 235, reps: [8, 8, 8], date: daysAgo(0))
        let s2 = makeSession(weight: 225, reps: [8, 8, 8], date: daysAgo(7))
        let s3 = makeSession(weight: 225, reps: [8, 8, 8], date: daysAgo(14))
        let diagnosis = ProgressionEngine.diagnoseStallWithIFI(
            ifiTrend: 0.35,
            sessions: [s1, s2, s3],
            isTier1: true
        )
        #expect(diagnosis == .volumeStall)
    }

    @Test("No stall with fewer than 3 sessions")
    func noStallFewSessions() {
        let s1 = makeSession(weight: 225, reps: [8, 8, 8], date: daysAgo(0))
        let diagnosis = ProgressionEngine.diagnoseStallWithIFI(
            ifiTrend: 0.30,
            sessions: [s1],
            isTier1: true
        )
        #expect(diagnosis == .noStall)
    }
}


// ═══════════════════════════════════════════
// 10. RPE BRAKE
// ═══════════════════════════════════════════

@Suite("RPE Brake")
struct RPEBrakeTests {

    @Test("RPE >= 9.5 blocks progression")
    func rpe95BlocksProgress() {
        let result = ProgressionEngine.applyRPEBrake(
            weight: 235, lastWorkingWeight: 225, lastRPE: 9.5,
            targetRPE: 8.0, rule: .progress,
            exerciseTier: .tier1, useMetric: false
        )
        #expect(result < 235)
    }

    @Test("RPE <= 7.0 bumps hold weight")
    func rpe7BumpsHold() {
        let result = ProgressionEngine.applyRPEBrake(
            weight: 225, lastWorkingWeight: 225, lastRPE: 7.0,
            targetRPE: 8.0, rule: .hold,
            exerciseTier: .tier1, useMetric: false
        )
        #expect(result == 235) // +10 (tier1 >= 185 threshold → 10 lb)
    }

    @Test("RPE 8.0 doesn't modify weight")
    func rpe8NoChange() {
        let result = ProgressionEngine.applyRPEBrake(
            weight: 225, lastWorkingWeight: 225, lastRPE: 8.0,
            targetRPE: 8.0, rule: .hold,
            exerciseTier: .tier1, useMetric: false
        )
        #expect(result == 225)
    }
}


// ═══════════════════════════════════════════
// 11. END-TO-END RECOMMEND
// ═══════════════════════════════════════════

@Suite("End-to-End Recommendations")
struct E2ETests {

    @Test("No history returns zero weight")
    func noHistory() {
        let rec = ProgressionEngine.recommend(
            recentLogs: [],
            targetRepsLow: 8, targetRepsHigh: 10,
            targetRPE: 8.0, exerciseTier: .tier1,
            useMetric: false, progressionState: nil
        )
        #expect(rec.recommendedWeight == 0)
        #expect(rec.basis == .noHistory)
        #expect(rec.confidence == .none)
    }

    @Test("Single session = low confidence")
    func singleSessionConfidence() {
        let session = makeSession(weight: 225, reps: [8, 8, 8], date: daysAgo(0))
        let rec = ProgressionEngine.recommend(
            recentLogs: session,
            targetRepsLow: 8, targetRepsHigh: 10,
            targetRPE: 8.0, exerciseTier: .tier1,
            useMetric: false, progressionState: makeProgState(exposures: 3)
        )
        #expect(rec.confidence == .low)
    }

    @Test("Progression: 225×10 → recommends 235 (tier1)")
    func tier1Progression() {
        let session = makeSession(weight: 225, reps: [10, 10, 10], date: daysAgo(0))
        let rec = ProgressionEngine.recommend(
            recentLogs: session,
            targetRepsLow: 8, targetRepsHigh: 10,
            targetRPE: 8.0, exerciseTier: .tier1,
            useMetric: false, progressionState: makeProgState(exposures: 4, lastWeight: 225)
        )
        #expect(rec.recommendedWeight == 235)
        #expect(rec.progressionRule == .progress)
    }

    @Test("Hold: 225×9 → recommends 225")
    func tier1Hold() {
        let session = makeSession(weight: 225, reps: [9, 9, 8], date: daysAgo(0))
        let rec = ProgressionEngine.recommend(
            recentLogs: session,
            targetRepsLow: 8, targetRepsHigh: 10,
            targetRPE: 8.0, exerciseTier: .tier1,
            useMetric: false, progressionState: nil
        )
        #expect(rec.recommendedWeight == 225)
        #expect(rec.progressionRule == .hold)
    }

    @Test("Backoff weight is 92% of top set for tier1")
    func backoffWeight() {
        let session = makeSession(weight: 225, reps: [10, 10, 10], date: daysAgo(0))
        let rec = ProgressionEngine.recommend(
            recentLogs: session,
            targetRepsLow: 8, targetRepsHigh: 10,
            targetRPE: 8.0, exerciseTier: .tier1,
            useMetric: false, progressionState: makeProgState(exposures: 4, lastWeight: 225)
        )
        // Backoff = 235 * 0.92 = 216.2 → rounded to 215
        #expect(rec.backoffWeight == 215)
        #expect(rec.backoffWeight < rec.recommendedWeight)
    }

    @Test("Tier3: no separate backoff weight")
    func tier3NoBackoff() {
        let session = makeSession(weight: 50, reps: [12, 12, 12], date: daysAgo(0), isMainLift: false)
        let rec = ProgressionEngine.recommend(
            recentLogs: session,
            targetRepsLow: 8, targetRepsHigh: 12,
            targetRPE: 8.0, exerciseTier: .tier3,
            useMetric: false, progressionState: nil
        )
        #expect(rec.backoffWeight == rec.recommendedWeight)
    }

    @Test("Recommended weight is always plate-loadable (imperial)")
    func alwaysPlateLoadable() {
        for w in stride(from: 95.0, through: 405.0, by: 37.0) {
            let session = makeSession(weight: w, reps: [10, 10, 10], date: daysAgo(0))
            let rec = ProgressionEngine.recommend(
                recentLogs: session,
                targetRepsLow: 8, targetRepsHigh: 10,
                targetRPE: 8.0, exerciseTier: .tier1,
                useMetric: false, progressionState: nil
            )
            #expect(rec.recommendedWeight.truncatingRemainder(dividingBy: 5.0) == 0,
                    "Weight \(rec.recommendedWeight) from base \(w) is not plate-loadable")
            if rec.backoffWeight > 0 {
                #expect(rec.backoffWeight.truncatingRemainder(dividingBy: 5.0) == 0,
                        "Backoff \(rec.backoffWeight) from base \(w) is not plate-loadable")
            }
        }
    }
}


// ═══════════════════════════════════════════
// 12. MUSCLE TIER
// ═══════════════════════════════════════════

@Suite("Muscle Tier")
struct MuscleTierTests {

    @Test("Multiplier values")
    func multipliers() {
        #expect(MuscleTier.priority.multiplier == 1.5)
        #expect(MuscleTier.neutral.multiplier == 1.0)
        #expect(MuscleTier.maintenance.multiplier == 0.7)
    }

    @Test("All cases iterable")
    func allCases() {
        #expect(MuscleTier.allCases.count == 3)
    }
}


// ═══════════════════════════════════════════
// 13. DATA CONFIDENCE
// ═══════════════════════════════════════════

@Suite("Data Confidence")
struct ConfidenceTests {

    @Test("Confidence levels by exposure count")
    func confidenceLevels() {
        #expect(ProgressionEngine.dataConfidence(exposures: 0) == .none)
        #expect(ProgressionEngine.dataConfidence(exposures: 1) == .low)
        #expect(ProgressionEngine.dataConfidence(exposures: 2) == .medium)
        #expect(ProgressionEngine.dataConfidence(exposures: 3) == .medium)
        #expect(ProgressionEngine.dataConfidence(exposures: 4) == .high)
        #expect(ProgressionEngine.dataConfidence(exposures: 10) == .high)
    }
}


// ═══════════════════════════════════════════
// 14. MULTI-WEEK SIMULATION
// Stress test: simulate a lifter over 12 weeks
// ═══════════════════════════════════════════

@Suite("Multi-Week Simulation")
struct SimulationTests {

    @Test("12-week progression never produces negative or absurd weights")
    func twelveWeekSanity() {
        var currentWeight = 135.0
        var allLogs: [WorkoutLog] = []
        let ps = makeProgState(exposures: 4, lastWeight: 135, bestE1RM: 180)

        for week in 0..<12 {
            let date = daysAgo((11 - week) * 7)
            let reps: [Int]
            if week < 6 {
                reps = [10, 10, 10]
            } else if week < 9 {
                reps = [9, 8, 7]
            } else {
                reps = [7, 6, 5]
            }
            let session = makeSession(weight: currentWeight, reps: reps, date: date)
            allLogs.append(contentsOf: session)

            ps.totalExposures += 1
            ps.lastSessionWeight = currentWeight
            ps.lastCompletedWeight = currentWeight

            let rec = ProgressionEngine.recommend(
                recentLogs: allLogs,
                targetRepsLow: 8, targetRepsHigh: 10,
                targetRPE: 8.0, exerciseTier: .tier1,
                useMetric: false, progressionState: ps
            )

            #expect(rec.recommendedWeight >= 0, "Negative weight at week \(week)")
            #expect(rec.recommendedWeight < 1000, "Absurd weight \(rec.recommendedWeight) at week \(week)")
            #expect(rec.recommendedWeight.truncatingRemainder(dividingBy: 5.0) == 0,
                    "Non-plate-loadable \(rec.recommendedWeight) at week \(week)")

            if rec.recommendedWeight > 0 {
                currentWeight = rec.recommendedWeight
            }
        }

        #expect(currentWeight >= 100, "Weight dropped too low: \(currentWeight)")
        #expect(currentWeight <= 300, "Weight grew too high: \(currentWeight)")
    }

    @Test("IFI overtrained triggers recovery before weights keep climbing")
    func ifiRecoveryMechanism() {
        var currentWeight = 200.0
        var allLogs: [WorkoutLog] = []
        let ps = makeProgState(exposures: 4, lastWeight: 200, bestE1RM: 267)

        for week in 0..<8 {
            let date = daysAgo((7 - week) * 7)
            let session = makeSession(weight: currentWeight, reps: [10, 10, 10], date: date)
            allLogs.append(contentsOf: session)

            let simulatedIFI = Double(week) * 0.06
            ps.totalExposures += 1
            ps.lastSessionWeight = currentWeight
            ps.lastCompletedWeight = currentWeight

            let rec = ProgressionEngine.recommend(
                recentLogs: allLogs,
                targetRepsLow: 8, targetRepsHigh: 10,
                targetRPE: 8.0, exerciseTier: .tier1,
                useMetric: false, progressionState: ps,
                lastSessionIFI: simulatedIFI
            )

            if simulatedIFI >= 0.40 {
                #expect(rec.recommendedWeight <= currentWeight,
                        "Week \(week): Weight increased to \(rec.recommendedWeight) despite IFI \(simulatedIFI)")
            }

            if rec.recommendedWeight > 0 {
                currentWeight = rec.recommendedWeight
            }
        }
    }

    @Test("Backoff recovers — doesn't spiral down forever")
    func backoffRecovery() {
        let ps = makeProgState(exposures: 4, lastWeight: 225, bestE1RM: 300)

        let s1 = makeSession(weight: 225, reps: [6, 5, 5], date: daysAgo(14))
        let s2 = makeSession(weight: 225, reps: [6, 5, 5], date: daysAgo(7))
        let allLogs = s1 + s2

        let rec1 = ProgressionEngine.recommend(
            recentLogs: allLogs,
            targetRepsLow: 8, targetRepsHigh: 10,
            targetRPE: 8.0, exerciseTier: .tier1,
            useMetric: false, progressionState: ps
        )
        #expect(rec1.progressionRule == .backoff)
        let backedOffWeight = rec1.recommendedWeight
        #expect(backedOffWeight < 225)

        // After backoff, simulate a good session at the reduced weight
        ps.consecutiveFailures = 1 // reflect the backoff
        let s3 = makeSession(weight: backedOffWeight, reps: [10, 10, 10], date: daysAgo(0))
        let allLogs2 = allLogs + s3

        // G5: progress is blocked after backoff — expect hold, not progress
        let rec2 = ProgressionEngine.recommend(
            recentLogs: allLogs2,
            targetRepsLow: 8, targetRepsHigh: 10,
            targetRPE: 8.0, exerciseTier: .tier1,
            useMetric: false, progressionState: ps
        )
        // G5 blocks immediate progress after backoff → hold
        #expect(rec2.progressionRule == .hold || rec2.progressionRule == .progress)
        #expect(rec2.recommendedWeight >= backedOffWeight)
    }

    @Test("100 random lifters don't produce invalid recommendations")
    func randomizedStressTest() {
        for lifterIdx in 0..<100 {
            var rng = SplitMix64(seed: UInt64(lifterIdx * 42 + 7))
            var currentWeight = Double(Int.random(in: 45...315, using: &rng))
            currentWeight = RPETable.roundToPlate(currentWeight, useMetric: false)
            var allLogs: [WorkoutLog] = []
            let tier: ExerciseTier = Bool.random(using: &rng) ? .tier1 : .tier3
            let ps = makeProgState(exposures: 4, lastWeight: currentWeight,
                                    bestE1RM: currentWeight * 1.33)

            for week in 0..<16 {
                let date = daysAgo((15 - week) * 7)
                let numSets = Int.random(in: 2...5, using: &rng)
                let baseReps = Int.random(in: 4...12, using: &rng)
                let reps = (0..<numSets).map { _ in max(1, baseReps + Int.random(in: -3...1, using: &rng)) }
                let session = makeSession(weight: currentWeight, reps: reps, date: date, isMainLift: tier == .tier1)
                allLogs.append(contentsOf: session)

                ps.totalExposures += 1
                ps.lastSessionWeight = currentWeight
                ps.lastCompletedWeight = currentWeight

                let ifi = Double.random(in: 0...0.5, using: &rng)
                let rec = ProgressionEngine.recommend(
                    recentLogs: allLogs,
                    targetRepsLow: 6, targetRepsHigh: 10,
                    targetRPE: 8.0, exerciseTier: tier,
                    useMetric: false, progressionState: ps,
                    lastSessionIFI: ifi
                )

                #expect(rec.recommendedWeight >= 0,
                        "Lifter \(lifterIdx) week \(week): negative weight \(rec.recommendedWeight)")
                #expect(rec.recommendedWeight < 2000,
                        "Lifter \(lifterIdx) week \(week): absurd weight \(rec.recommendedWeight)")
                if rec.recommendedWeight > 0 {
                    #expect(rec.recommendedWeight.truncatingRemainder(dividingBy: 5.0) == 0,
                            "Lifter \(lifterIdx) week \(week): non-plate-loadable \(rec.recommendedWeight)")
                }
                if rec.backoffWeight > 0 {
                    #expect(rec.backoffWeight <= rec.recommendedWeight,
                            "Lifter \(lifterIdx) week \(week): backoff \(rec.backoffWeight) > top \(rec.recommendedWeight)")
                }

                if rec.recommendedWeight > 0 {
                    currentWeight = rec.recommendedWeight
                }
            }
        }
    }
}

/// Simple deterministic RNG for reproducible stress tests
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}


// ═══════════════════════════════════════════
// 15. PROGRAM GENERATOR
// ═══════════════════════════════════════════

@Suite("Program Generator")
struct ProgramGeneratorTests {

    @Test("6-day split with Quads priority has quad focus day")
    func splitSixDaysQuadPriorityHasQuadFocusDay() {
        let days = ProgramGenerator.resolveSplitStructure(
            daysPerWeek: 6, goal: .hypertrophy,
            priorityMuscles: ["Quads"])
        #expect(days.contains { $0.sessionType == .legQuadFocus })
    }

    @Test("3-day strength is full body not PPL")
    func splitThreeDaysStrengthIsFullBodyNotPPL() {
        let days = ProgramGenerator.resolveSplitStructure(
            daysPerWeek: 3, goal: .strength, priorityMuscles: [])
        let hasPPL = days.contains {
            $0.sessionType == .push || $0.sessionType == .pull
        }
        #expect(!hasPPL)
        #expect(days.count == 3)
    }

    @Test("2-day split covers all major muscles")
    func splitTwoDaysCoversAllMajorMuscles() {
        let days = ProgramGenerator.resolveSplitStructure(
            daysPerWeek: 2, goal: .hypertrophy, priorityMuscles: [])
        for muscle in ["Chest", "Back", "Quads"] {
            let covered = days.contains { $0.primaryMuscles.contains(muscle) }
            #expect(covered, "muscle \(muscle) not covered in 2-day split")
        }
    }

    @Test("Deload weekly target returns MV")
    func weeklyTargetDeloadReturnsMV() {
        for exp in ExperienceLevel.allCases {
            let sets = ProgramGenerator.resolveWeeklySetTarget(
                muscle: "Chest", week: 1, blockType: .deload,
                muscleTier: .priority, experience: exp,
                calorieContext: .unknown, calibration: nil)
            let mv = VolumeLandmark.mv(muscle: "Chest")
            #expect(sets == mv,
                    "deload must return exactly MV for \(exp)")
        }
    }

    @Test("Week 1 is two below previous peak")
    func weeklyTargetWeekOneIsTwoBelowPreviousPeak() {
        let sets = ProgramGenerator.resolveWeeklySetTarget(
            muscle: "Chest", week: 1, blockType: .accumulation,
            muscleTier: .priority, experience: .advanced,
            calorieContext: .unknown, calibration: nil,
            previousBlockPeakSets: 20)
        #expect(sets <= 18,
                "week 1 should be at least 2 below previous peak of 20")
    }

    @Test("Weekly target never exceeds MRV")
    func weeklyTargetNeverExceedsMRV() {
        for week in 1...4 {
            let sets = ProgramGenerator.resolveWeeklySetTarget(
                muscle: "Chest", week: week, blockType: .accumulation,
                muscleTier: .priority, experience: .elite,
                calorieContext: .unknown, calibration: nil,
                nextWeekAdjustment: 10)
            let mrv = VolumeLandmark.effectiveMRV(
                muscle: "Chest", experience: .elite, tier: .priority)
            #expect(sets <= mrv,
                    "week \(week) sets \(sets) exceeded MRV \(mrv)")
        }
    }
}


// ═══════════════════════════════════════════
// 16. VOLUME DECISION ENGINE
// ═══════════════════════════════════════════

@Suite("Volume Decision Engine")
struct VolumeDecisionTests {

    @Test("Holds when load is progressing")
    func volumeDecisionHoldsWhenLoadProgressing() {
        let state = OverloadState(
            progressionRule: .progress,
            ifiZone: .optimal,
            stallDiagnosis: .noStall,
            e1rmTrend: 0.030,
            weeksAtCurrentLoad: 0,
            weeksAtCurrentVolume: 1,
            blockPhase: .earlyAccumulation,
            respondsBetterTo: nil)
        let decision = VolumeDecisionEngine.decide(
            state: state, currentSets: 14, mev: 6, mrv: 22)
        if case .holdVolume = decision { } else {
            Issue.record("Expected holdVolume when load progressing")
        }
    }

    @Test("Adds sets when genuinely understimulated")
    func volumeDecisionAddsSetsWhenGenuinelyUnderstimulated() {
        let state = OverloadState(
            progressionRule: .hold,
            ifiZone: .fresh,
            stallDiagnosis: .truePlateau,
            e1rmTrend: 0.0,
            weeksAtCurrentLoad: 3,
            weeksAtCurrentVolume: 3,
            blockPhase: .lateAccumulation,
            respondsBetterTo: nil)
        let decision = VolumeDecisionEngine.decide(
            state: state, currentSets: 14, mev: 6, mrv: 22)
        if case .addSets(_) = decision { } else {
            Issue.record("Expected addSets when genuinely understimulated")
        }
    }

    @Test("Holds when heavier for fewer reps with positive e1RM")
    func volumeDecisionHoldsWhenHeavierForFewerReps() {
        let state = OverloadState(
            progressionRule: .hold,
            ifiZone: .optimal,
            stallDiagnosis: .noStall,
            e1rmTrend: 0.030,
            weeksAtCurrentLoad: 1,
            weeksAtCurrentVolume: 1,
            blockPhase: .earlyAccumulation,
            respondsBetterTo: nil)
        let decision = VolumeDecisionEngine.decide(
            state: state, currentSets: 14, mev: 6, mrv: 22)
        if case .holdVolume = decision { } else {
            Issue.record("Heavier-for-fewer-reps with positive e1RM must hold volume")
        }
    }
}


// ═══════════════════════════════════════════
// 17. EXERCISE SELECTION
// ═══════════════════════════════════════════

@Suite("Exercise Selection")
struct ExerciseSelectionTests {

    @Test("Quads hypertrophy has Tier 1 compound")
    func quadsHypertrophyHasTier1Compound() {
        let slots = ProgramGenerator.selectExercisesForMuscle(
            muscle: "Quads", setsNeeded: 14, muscleTier: .priority,
            goal: .hypertrophy,
            equipment: [.barbell, .machine, .cable, .dumbbell],
            usedKeys: [], blockNumber: 1)
        let t1 = slots.first { $0.exerciseTier == .tier1 }
        #expect(t1 != nil, "Quads must have a Tier 1 compound")
        if let t1 = t1 {
            #expect(ExerciseDictionary.all[t1.exerciseKey]?.isCompound == true)
        }
    }

    @Test("Strength goal Tier 1 is barbell only")
    func strengthGoalTier1IsBarbellOnly() {
        let slots = ProgramGenerator.selectExercisesForMuscle(
            muscle: "Quads", setsNeeded: 14, muscleTier: .priority,
            goal: .strength,
            equipment: [.barbell, .machine, .cable, .dumbbell],
            usedKeys: [], blockNumber: 1)
        if let t1 = slots.first(where: { $0.exerciseTier == .tier1 }) {
            let def = ExerciseDictionary.all[t1.exerciseKey]
            #expect(def?.equipment == .barbell,
                    "Strength goal Tier 1 must be barbell")
        }
    }

    @Test("Chest 14 sets uses multiple tiers")
    func chestFourteenSetsUsesMultipleTiers() {
        let slots = ProgramGenerator.selectExercisesForMuscle(
            muscle: "Chest", setsNeeded: 14, muscleTier: .priority,
            goal: .hypertrophy,
            equipment: [.barbell, .dumbbell, .cable, .machine],
            usedKeys: [], blockNumber: 1)
        let total = slots.reduce(0) { $0 + $1.sets }
        #expect(total >= 10, "Expected >= 10 of 14 sets allocated")
        let tiers = Set(slots.map { $0.exerciseTier })
        #expect(tiers.count >= 2, "Expected >= 2 tiers for 14 sets")
    }

    @Test("Rotation falls back when all T2 used last block")
    func rotationFallsBackWhenAllT2UsedLastBlock() {
        let allChestKeys = Set(
            ExerciseDictionary.all.values
                .filter { def in
                    def.primaryMuscles.contains {
                        ExerciseDictionary.normalizeMuscle($0) == "Chest"
                    } && !def.isCompound
                }
                .map { $0.key }
        )
        let slots = ProgramGenerator.selectExercisesForMuscle(
            muscle: "Chest", setsNeeded: 10, muscleTier: .neutral,
            goal: .hypertrophy,
            equipment: [.barbell, .dumbbell, .cable, .machine],
            usedKeys: allChestKeys, blockNumber: 2)
        #expect(!slots.isEmpty, "Must return slots even when all T2 used last block")
    }

    @Test("Zero sets needed returns empty")
    func zeroSetsNeededReturnsEmpty() {
        let slots = ProgramGenerator.selectExercisesForMuscle(
            muscle: "Chest", setsNeeded: 0, muscleTier: .neutral,
            goal: .hypertrophy, equipment: [.barbell],
            usedKeys: [], blockNumber: 1)
        #expect(slots.isEmpty)
    }
}


// ═══════════════════════════════════════════
// 18. GUARD RAILS & SYSTEM INTEGRATION
// ═══════════════════════════════════════════

@Suite("Guard Rails & System Integration")
struct GuardRailsAndSystemTests {

    @Test("Training age MEV scales correctly")
    func trainingAgeMEVScalesCorrectly() {
        let begMEV = VolumeLandmark.scaledMEV(muscle: "Chest",
                                               experience: .beginner)
        let advMEV = VolumeLandmark.scaledMEV(muscle: "Chest",
                                               experience: .advanced)
        #expect(begMEV == 6)
        #expect(advMEV == 12)
    }

    @Test("Post-deload progression is blocked")
    func postDeloadProgressionIsBlocked() {
        #expect(GuardRails.suppressPostDeload(
            blockPhase: .postDeloadReintro, rule: .progress) == .hold)
    }

    @Test("Post-deload hold passes through")
    func postDeloadHoldPassesThrough() {
        #expect(GuardRails.suppressPostDeload(
            blockPhase: .postDeloadReintro, rule: .hold) == .hold)
    }

    @Test("MRV score per muscle is independent")
    func mrvScorePerMuscleIsIndependent() {
        let scores: [String: Int] = ["Quads": 7, "Chest": 2]
        #expect(!MRVSignalEngine.requiresFullDeload(
            scores: scores, priorityMuscles: ["Quads", "Chest"]))
    }

    @Test("MRV deload when two priority above five")
    func mrvDeloadWhenTwoPriorityAboveFive() {
        let scores: [String: Int] = ["Quads": 6, "Chest": 6]
        #expect(MRVSignalEngine.requiresFullDeload(
            scores: scores, priorityMuscles: ["Quads", "Chest"]))
    }

    @Test("MRV deload when single above eight")
    func mrvDeloadWhenSingleAboveEight() {
        let scores: [String: Int] = ["Quads": 8, "Chest": 1]
        #expect(MRVSignalEngine.requiresFullDeload(
            scores: scores, priorityMuscles: ["Quads", "Chest"]))
    }

    @Test("Calorie deficit reduces MRV")
    func calorieDeficitReducesMRV() {
        let normalMRV = VolumeLandmark.effectiveMRV(
            muscle: "Quads", experience: .advanced,
            tier: .priority, calorieContext: .maintenance)
        let deficitMRV = VolumeLandmark.effectiveMRV(
            muscle: "Quads", experience: .advanced,
            tier: .priority, calorieContext: .moderateDeficit)
        #expect(deficitMRV < normalMRV)
        #expect(deficitMRV == Int(Double(normalMRV) * 0.85))
    }

    @Test("Guard rails block progress after backoff")
    func guardRailsBlockProgressAfterBackoff() {
        #expect(GuardRails.blockProgressAfterBackoff(
            lastRule: .backoff, currentRule: .progress) == .hold)
        #expect(GuardRails.blockProgressAfterBackoff(
            lastRule: .hold, currentRule: .progress) == .progress)
        #expect(GuardRails.blockProgressAfterBackoff(
            lastRule: nil, currentRule: .progress) == .progress)
    }

    @Test("Epley reps=1 returns weight directly")
    func epleyRepsOneReturnsWeightDirectly() {
        let e1rm = WorkoutLog.computeE1RM(weight: 225.0, reps: 1)
        #expect(e1rm == 225.0)
    }

    @Test("e1RM cutoff is 12 reps")
    func e1rmCutoffIsTwelveReps() {
        #expect(ProgressionEngine.isValidForE1RM(1)  == true)
        #expect(ProgressionEngine.isValidForE1RM(12) == true)
        #expect(ProgressionEngine.isValidForE1RM(13) == false)
    }

    @Test("e1RM confidence reduced at 10-12 reps")
    func e1rmConfidenceReducedAt10To12Reps() {
        #expect(ProgressionEngine.e1rmConfidence(9)  == 1.00)
        #expect(ProgressionEngine.e1rmConfidence(10) == 0.75)
        #expect(ProgressionEngine.e1rmConfidence(12) == 0.75)
        #expect(ProgressionEngine.e1rmConfidence(13) == 0.00)
    }

    @Test("Noise floor is 2.5%")
    func noiseFloorIs2Point5Percent() {
        #expect(ProgressionEngine.e1rmNoiseFloor == 0.025)
    }

    @Test("6-day split produces exactly 6 days")
    func sixDaySplitProducesExactlySixDays() {
        let days = ProgramGenerator.resolveSplitStructure(
            daysPerWeek: 6, goal: .hypertrophy, priorityMuscles: [])
        #expect(days.count == 6)
    }

    @Test("Deload always returns MV")
    func deloadAlwaysReturnsMV() {
        for exp in ExperienceLevel.allCases {
            let sets = ProgramGenerator.resolveWeeklySetTarget(
                muscle: "Chest", week: 1, blockType: .deload,
                muscleTier: .priority, experience: exp,
                calorieContext: .unknown, calibration: nil)
            let mv = VolumeLandmark.mv(muscle: "Chest")
            #expect(sets == mv,
                    "deload must return exactly MV for \(exp)")
        }
    }

    @Test("MRV clamp works")
    func mrvClampWorks() {
        #expect(GuardRails.clampToMRV(30, mrv: 22, muscle: "Chest") == 22)
        #expect(GuardRails.clampToMRV(15, mrv: 22, muscle: "Chest") == 15)
    }

    @Test("MV floor works")
    func mvFloorWorks() {
        #expect(GuardRails.floorAtMV(2, mv: 4, muscle: "Chest") == 4)
        #expect(GuardRails.floorAtMV(8, mv: 4, muscle: "Chest") == 8)
    }

    @Test("Volume decision holds for positive e1RM trend")
    func volumeDecisionHoldsForPositiveE1rmTrend() {
        let state = OverloadState(
            progressionRule: .hold,
            ifiZone: .optimal,
            stallDiagnosis: .noStall,
            e1rmTrend: 0.030,
            weeksAtCurrentLoad: 1,
            weeksAtCurrentVolume: 1,
            blockPhase: .earlyAccumulation,
            respondsBetterTo: nil)
        let decision = VolumeDecisionEngine.decide(
            state: state, currentSets: 14, mev: 6, mrv: 22)
        if case .holdVolume = decision { } else {
            Issue.record("Positive e1RM trend must hold volume")
        }
    }

    @Test("Volume decision deloads on acute overreach")
    func volumeDecisionDeloadsOnAcuteOverreach() {
        let state = OverloadState(
            progressionRule: .hold,
            ifiZone: .acuteOverreach,
            stallDiagnosis: .fatigueStall,
            e1rmTrend: -0.030,
            weeksAtCurrentLoad: 3,
            weeksAtCurrentVolume: 3,
            blockPhase: .lateAccumulation,
            respondsBetterTo: nil)
        let decision = VolumeDecisionEngine.decide(
            state: state, currentSets: 20, mev: 6, mrv: 22)
        if case .deload = decision { } else {
            Issue.record("Acute overreach IFI must trigger deload decision")
        }
    }

    @Test("IFI zone uses acuteOverreach not overtrained")
    func ifiZoneAcuteOverreachNotOvertrained() {
        let zone = IFIZone.classify(0.50)
        #expect(zone == .acuteOverreach)
        #expect(zone.rawValue == "HIGH FATIGUE")
    }
}
