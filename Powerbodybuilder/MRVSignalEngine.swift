import Foundation

// ═══════════════════════════════════════════
// MRV SIGNAL ENGINE
// Detects when a muscle is approaching or exceeding
// its maximum recoverable volume via 5 fatigue signals.
// ═══════════════════════════════════════════

func exerciseTargetsMuscle(_ exerciseKey: String,
                             muscle: String) -> Bool {
    guard let def = ExerciseDictionary.all[exerciseKey] else { return false }
    return def.primaryMuscles
        .compactMap { ExerciseDictionary.normalizeMuscle($0) }
        .contains(muscle)
}

func isThisWeekLog(_ log: WorkoutLog) -> Bool {
    Calendar.current.isDate(log.workoutDate,
                             equalTo: Date(), toGranularity: .weekOfYear)
}

func isLastWeekLog(_ log: WorkoutLog) -> Bool {
    guard let lastWeekDate = Calendar.current.date(
        byAdding: .weekOfYear, value: -1, to: Date()) else { return false }
    return Calendar.current.isDate(log.workoutDate,
                                    equalTo: lastWeekDate,
                                    toGranularity: .weekOfYear)
}

struct MRVSignalEngine {

    static func computeScore(
        muscle: String,
        progressionStates: [ProgressionState],
        recentLogs: [WorkoutLog],
        existingScore: Int,
        lastSignalDate: Date?,
        isDeloadWeek: Bool
    ) -> Int {
        if isDeloadWeek { return 0 }

        var score = existingScore
        if let last = lastSignalDate {
            let weeks = Calendar.current.dateComponents(
                [.weekOfYear], from: last, to: Date()).weekOfYear ?? 0
            score = max(0, score - weeks)
        }

        var newPoints = 0

        let muscleStates = progressionStates.filter {
            exerciseTargetsMuscle($0.exerciseKey, muscle: muscle)
        }

        // Global minimum-exposures guard. With only 1–5 logged sessions per
        // muscle group, signals fire on noise: a fresh session typically lifts
        // less than the career bestE1RM (which survives program resets), which
        // looks like a 10–20% e1RM decline. Hard workouts naturally have a
        // single high-IFI session that doesn't mean fatigue. Need enough data
        // for the EMA-based signals to be stable.
        let totalExposures = muscleStates.reduce(0) { $0 + $1.totalExposures }
        guard totalExposures >= 6 else { return score }

        // S1: e1RM declining >2.5% (noise floor) on any exercise (+3)
        // Per-exercise: 6+ exposures so we have a stable baseline and one
        // bad session doesn't trip the signal. Bench/squat/deadlift typically
        // need 4-6 sessions before e1RM trend stabilizes.
        for state in muscleStates where state.totalExposures >= 6 {
            if state.bestE1RM > 0 && state.lastCompletedWeight > 0 {
                let current = state.lastCompletedWeight *
                    (1.0 + Double(max(1, state.lastSessionReps)) / 30.0)
                let change = (current - state.bestE1RM) / max(state.bestE1RM, 1)
                if change < -0.025 { newPoints += 3 }
            }
        }

        // S2: IFI > 0.30 or IFI trend worsening (+2 each)
        // Per-exercise: 4+ exposures so a single hard session doesn't fire.
        // ifiTrend is an EMA and needs prior sessions to be meaningful.
        for state in muscleStates where state.totalExposures >= 4 {
            if state.lastIFI > 0.30 { newPoints += 2 }
            if state.ifiTrend > 0.25 { newPoints += 2 }
        }

        // S3: Stuck at same load 2+ weeks (+2)
        for state in muscleStates {
            if state.weeksAtSameLoad >= 2 { newPoints += 2 }
        }

        // S4: Volume-load declining despite same or more sets (+2)
        let thisVL = recentLogs
            .filter { isThisWeekLog($0) &&
                exerciseTargetsMuscle($0.exerciseKey, muscle: muscle) }
            .reduce(0.0) { $0 + $1.weight * Double($1.reps) }
        let lastVL = recentLogs
            .filter { isLastWeekLog($0) &&
                exerciseTargetsMuscle($0.exerciseKey, muscle: muscle) }
            .reduce(0.0) { $0 + $1.weight * Double($1.reps) }
        if lastVL > 0 && thisVL < lastVL * 0.97 { newPoints += 2 }

        // S5: Rep miss rate >30% in last 20 hard sets (+1)
        // A miss: reps < targetRepsLow AND user did not go heavier
        // rpe is non-optional Double — rpe == 0 means unlogged
        let hardLogs = recentLogs
            .filter { exerciseTargetsMuscle($0.exerciseKey, muscle: muscle)
                && ($0.rpe == 0 || $0.rpe >= 6.0) }
            .suffix(20)
        if hardLogs.count >= 10 {
            let missed = hardLogs.filter { log in
                let wentHeavier = log.weight > log.previousWeight
                return log.reps < log.targetRepsLow && !wentHeavier
            }.count
            if Double(missed) / Double(hardLogs.count) > 0.30 {
                newPoints += 1
            }
        }

        return newPoints > 0 ? score + newPoints : score
    }

    static func action(for score: Int) -> MRVAction {
        switch score {
        case 0...2:  return .none
        case 3...4:  return .monitor
        case 5...6:  return .reduceVolume
        default:     return .deload
        }
    }

    static func requiresFullDeload(
        scores: [String: Int],
        priorityMuscles: [String]
    ) -> Bool {
        if scores.values.contains(where: { $0 >= 8 }) { return true }
        let above5 = priorityMuscles.filter { (scores[$0] ?? 0) >= 5 }
        return above5.count >= 2
    }
}

enum MRVAction { case none, monitor, reduceVolume, deload }
