import Foundation

struct GuardRails {

    static func clampToMRV(_ sets: Int, mrv: Int, muscle: String) -> Int {
        guard sets > mrv else { return sets }
        log("G1: \(muscle) prescribed \(sets) sets, MRV \(mrv). Clamped.")
        return mrv
    }

    static func floorAtMV(_ sets: Int, mv: Int, muscle: String) -> Int {
        guard sets < mv else { return sets }
        log("G2: \(muscle) prescribed \(sets) sets, MV floor \(mv). Raised.")
        return mv
    }

    static func deloadSetFloor(_ sets: Int) -> Int {
        let result = max(sets, 2)
        if result != sets { log("G3: deload sets raised from \(sets) to 2") }
        return result
    }

    static func clampRPE(_ rpe: Double, isMaxTestSession: Bool) -> Double {
        guard !isMaxTestSession && rpe > 9.5 else { return rpe }
        log("G4: RPE \(rpe) > 9.5 outside max test. Clamped to 9.5.")
        return 9.5
    }

    static func blockProgressAfterBackoff(
        lastRule: ProgressionRule?,
        currentRule: ProgressionRule
    ) -> ProgressionRule {
        guard lastRule == .backoff && currentRule == .progress else {
            return currentRule
        }
        log("G5: Progress blocked after backoff — returning .hold")
        return .hold
    }

    static func validateSessionSetCount(_ count: Int) -> Bool {
        guard count > 24 else { return true }
        log("G6: Session has \(count) sets, cap is 24")
        return false
    }

    static func validateTierOrder(_ slots: [ExerciseSlot]) -> Bool {
        var lastTierPerMuscle: [String: ExerciseTier] = [:]
        var valid = true
        for slot in slots {
            guard let def = ExerciseDictionary.all[slot.exerciseKey] else { continue }
            let primary = def.primaryMuscles
                .compactMap { ExerciseDictionary.normalizeMuscle($0) }
                .first ?? ""
            if let last = lastTierPerMuscle[primary],
               slot.exerciseTier.sortValue < last.sortValue {
                log("G7: \(slot.exerciseKey) T\(slot.exerciseTier.sortValue) "
                    + "follows T\(last.sortValue) for \(primary)")
                valid = false
            }
            lastTierPerMuscle[primary] = slot.exerciseTier
        }
        return valid
    }

    static func allowProgressionSignal(totalExposures: Int) -> Bool {
        guard totalExposures >= 3 else {
            log("G8: Signal suppressed — \(totalExposures) session(s) of history")
            return false
        }
        return true
    }

    static func suppressPostDeload(
        blockPhase: BlockPhase,
        rule: ProgressionRule
    ) -> ProgressionRule {
        guard blockPhase == .postDeloadReintro && rule == .progress else {
            return rule
        }
        log("G9: Post-deload progression suppressed → .hold")
        return .hold
    }

    static func assertSameUnit(_ unit1: String, _ unit2: String,
                                context: String) {
        guard unit1 != unit2 else { return }
        let msg = "G10: unit mismatch \(unit1) vs \(unit2) in \(context)"
        #if DEBUG
        assertionFailure(msg)
        #else
        log(msg)
        #endif
    }

    private static func log(_ message: String) {
        #if DEBUG
        print("[GuardRails] \(message)")
        #endif
    }
}
