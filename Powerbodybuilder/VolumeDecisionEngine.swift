import Foundation

// ═══════════════════════════════════════════
// VOLUME DECISION ENGINE
// Decides whether to add, hold, or reduce weekly sets
// per muscle based on fatigue and progression signals.
// ═══════════════════════════════════════════

enum VolumeDecision {
    case addSets(Int)
    case holdVolume
    case reduceSets(Int)
    case deload
}

struct OverloadState {
    let progressionRule: ProgressionRule
    let ifiZone: IFIZone
    let stallDiagnosis: StallDiagnosis
    let e1rmTrend: Double
    let weeksAtCurrentLoad: Int
    let weeksAtCurrentVolume: Int
    let blockPhase: BlockPhase
    let respondsBetterTo: RespondsBetterTo?
}

struct StimulusEvaluation {
    let needsMoreStimulus: Bool
    let confidence: Double
    let reasoning: String
}

struct VolumeDecisionEngine {

    static func decide(
        state: OverloadState,
        currentSets: Int,
        mev: Int,
        mrv: Int
    ) -> VolumeDecision {

        // Deload signals — highest priority
        if state.ifiZone == .acuteOverreach { return .deload }
        if state.stallDiagnosis == .fatigueStall { return .deload }

        // Load progressing — volume is not the lever right now
        if state.progressionRule == .progress || state.e1rmTrend > ProgressionEngine.e1rmNoiseFloor {
            return .holdVolume
        }

        // User responds better to intensity — don't add sets
        if state.respondsBetterTo == .lowVolumeHighIntensity {
            return .holdVolume
        }

        // Backoff state: weight was reduced, not a volume problem
        if state.progressionRule == .backoff {
            return .holdVolume
        }

        // Intensity stall: user isn't pushing close enough to failure
        if state.stallDiagnosis == .intensityStall {
            return .holdVolume
        }

        // High fatigue with stalling — reduce volume
        if state.ifiZone == .fatigued || state.stallDiagnosis == .volumeStall {
            let setsToRemove = min(2, currentSets - mev)
            return setsToRemove > 0 ? .reduceSets(setsToRemove) : .holdVolume
        }

        // Evaluate whether stimulus is genuinely insufficient
        let stimulus = evaluateStimulus(state: state, currentSets: currentSets)

        if stimulus.needsMoreStimulus && stimulus.confidence >= 0.5 {
            let setsToAdd = state.ifiZone == .fresh ? 2 : 1
            let capped = min(setsToAdd, mrv - currentSets)
            return capped > 0 ? .addSets(capped) : .holdVolume
        }

        return .holdVolume
    }

    static func evaluateStimulus(
        state: OverloadState,
        currentSets: Int
    ) -> StimulusEvaluation {

        if state.progressionRule == .progress {
            return StimulusEvaluation(needsMoreStimulus: false,
                                       confidence: 0.95,
                                       reasoning: "Load progressing")
        }

        if state.ifiZone == .fatigued || state.ifiZone == .acuteOverreach {
            return StimulusEvaluation(needsMoreStimulus: false,
                                       confidence: 0.90,
                                       reasoning: "Fatigue is the issue")
        }

        var stimScore = 0.0
        var confidenceFactors: [Double] = []
        var reasons: [String] = []

        // Signal 1: How long has load been stalled? (35% weight)
        // Continuous training uses a neutral threshold (2 weeks) — no block
        // phase context, so we lean toward the late-accumulation cadence.
        let requiredWeeks: Int = switch state.blockPhase {
        case .postDeloadReintro: 999
        case .earlyAccumulation: 3
        case .lateAccumulation:  2
        case .intensification:   1
        case .deload:            999
        case .continuous:        2
        }

        if state.weeksAtCurrentLoad >= requiredWeeks {
            let dur = min(1.0, Double(state.weeksAtCurrentLoad) /
                              Double(requiredWeeks + 1))
            stimScore += dur * 0.35
            confidenceFactors.append(dur)
            reasons.append("Load stalled \(state.weeksAtCurrentLoad) wks")
        } else {
            confidenceFactors.append(0.2)
            reasons.append("Too early — \(state.weeksAtCurrentLoad) wk(s)")
        }

        // Signal 2: e1RM trend (30% weight)
        let noiseFloor = ProgressionEngine.e1rmNoiseFloor
        if state.e1rmTrend <= -noiseFloor {
            stimScore += 0.0
            confidenceFactors.append(0.20)
            reasons.append("e1RM declining — not a stimulus issue")
        } else if abs(state.e1rmTrend) < noiseFloor {
            stimScore += 0.30
            confidenceFactors.append(0.85)
            reasons.append("e1RM flat")
        } else {
            stimScore += 0.0
            confidenceFactors.append(0.20)
            reasons.append("e1RM still improving")
        }

        // Signal 3: IFI zone (25% weight)
        if state.ifiZone == .fresh {
            stimScore += 0.25
            confidenceFactors.append(0.85)
            reasons.append("IFI fresh — capacity available")
        } else if state.ifiZone == .optimal {
            stimScore += 0.10
            confidenceFactors.append(0.50)
            reasons.append("IFI optimal")
        }

        // Signal 4: Block phase (10% weight)
        if state.blockPhase == .lateAccumulation && abs(state.e1rmTrend) < noiseFloor {
            stimScore += 0.10
            confidenceFactors.append(0.80)
            reasons.append("Late accumulation stall")
        }

        let avgConf = confidenceFactors.isEmpty ? 0 :
            confidenceFactors.reduce(0, +) / Double(confidenceFactors.count)

        return StimulusEvaluation(
            needsMoreStimulus: stimScore > 0.5,
            confidence: avgConf,
            reasoning: reasons.joined(separator: " · ")
        )
    }
}
