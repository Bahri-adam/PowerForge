import SwiftData
import Foundation

// ═══════════════════════════════════════════
// ENUMS
// ═══════════════════════════════════════════

enum MovementPattern: String, Codable, CaseIterable {
    case horizontalPush = "horizontal_push"
    case horizontalPull = "horizontal_pull"
    case verticalPush = "vertical_push"
    case verticalPull = "vertical_pull"
    case squat = "squat"
    case hinge = "hinge"
    case lunge = "lunge"
    case hipThrust = "hip_thrust"
    case isolation = "isolation"
    case carry = "carry"
    case core = "core"
}

enum EquipmentType: String, Codable, CaseIterable {
    case barbell = "barbell"
    case dumbbell = "dumbbell"
    case cable = "cable"
    case machine = "machine"
    case bodyweight = "bodyweight"
    case kettlebell = "kettlebell"
    case band = "band"
    case other = "other"
}

enum GoalType: String, Codable, CaseIterable {
    case hypertrophy    = "hypertrophy"
    case strength       = "strength"
    case powerbuilding  = "powerbuilding"
    case recomp         = "recomp"

    static func migrate(from legacy: String) -> GoalType {
        switch legacy.lowercased() {
        case "build muscle", "buildmuscle",
             "get stronger and more jacked":  return .hypertrophy
        case "get stronger", "getstronger":   return .strength
        case "both", "powerbuilding":         return .powerbuilding
        case "minimal time", "recomp",
             "stay athletic", "cut":          return .recomp
        default:                              return .hypertrophy
        }
    }

    var displayName: String {
        switch self {
        case .hypertrophy:   return "Build Muscle"
        case .strength:      return "Get Stronger"
        case .powerbuilding: return "Powerbuilding"
        case .recomp:        return "Body Recomposition"
        }
    }
}

enum ExperienceLevel: String, Codable, CaseIterable {
    case beginner = "Beginner"
    case intermediate = "Intermediate"
    case advanced = "Advanced"
    case elite = "Elite"
}

enum MissedWorkoutPolicy: String, Codable {
    case rotation = "rotation"
    case strictCalendar = "strictCalendar"
}

enum OverrideScope: String, Codable {
    case single = "single"
    case future = "future"
    case range = "range"
}

enum ExerciseRole: String, Codable {
    case mainLift = "mainLift"
    case supplemental = "supplemental"
    case accessory = "accessory"
    case finisher = "finisher"
}

enum ExerciseTier: String, Codable {
    case tier1  // anchor compound — never rotates mid-mesocycle
    case tier2  // primary accessory — rotates per mesocycle
    case tier3  // isolation finisher — rotates freely

    var sortValue: Int {
        switch self {
        case .tier1: return 1
        case .tier2: return 2
        case .tier3: return 3
        }
    }

    var backoffPercentage: Double {
        switch self {
        case .tier1: return 0.94
        case .tier2: return 0.90
        case .tier3: return 0.85
        }
    }
}

enum SessionType: String, Codable, CaseIterable {
    case heavyUpper = "Heavy Upper"
    case hypertrophyUpper = "Hypertrophy Upper"
    case heavyLower = "Heavy Lower"
    case hypertrophyLower = "Hypertrophy Lower"
    case push = "Push"
    case pull = "Pull"
    case legs = "Legs"
    case fullBody = "Full Body"
    case fullBodyA = "Full Body A"
    case fullBodyB = "Full Body B"
    case upperPower = "Upper Power"
    case lowerPower = "Lower Power"
    case strengthHypertrophy = "Strength Hypertrophy"
    case rest = "Rest"
    case legQuadFocus    = "Legs — Quad Focus"
    case legsPosterior   = "Legs — Posterior Chain"
    case chestBack       = "Chest & Back"
    case armsDelts       = "Arms & Delts"
    case chestArms       = "Chest & Arms"
    case legsVolume      = "Legs — Volume"
    case pushA           = "Push A"
    case pushB           = "Push B"
    case pullA           = "Pull A"
    case pullB           = "Pull B"
    case legsA           = "Legs A"
    case legsB           = "Legs B"
    case freeform        = "Freeform"
}

enum BlockType: String, Codable {
    case accumulation    = "accumulation"
    case intensification = "intensification"
    case reaccumulation  = "reaccumulation"
    case peak            = "peak"
    case deload          = "deload"
}

extension BlockType {
    static func next(
        current: BlockType,
        goal: GoalType,
        blockNumber: Int
    ) -> BlockType {
        switch (goal, current) {
        case (.hypertrophy, .accumulation):           return .deload
        case (.hypertrophy, .deload):
            // blockNumber at deload exit is always odd: 1, 3, 5, 7...
            // Cycle number = (blockNumber + 1) / 2 = 1, 2, 3, 4...
            // Odd cycles → reaccumulation, Even cycles → accumulation
            let cycle = (blockNumber + 1) / 2
            return cycle % 2 == 1 ? .reaccumulation : .accumulation
        case (_, .reaccumulation):                    return .deload
        case (.strength, .accumulation):              return .deload
        case (.strength, .intensification):           return .deload
        case (.strength, .peak):                      return .deload
        case (.strength, .deload):
            let phase = blockNumber % 6
            if phase < 2 { return .intensification }
            if phase < 4 { return .peak }
            return .accumulation
        case (.powerbuilding, .accumulation):         return .deload
        case (.powerbuilding, .intensification):      return .deload
        case (.powerbuilding, .deload) where blockNumber % 3 == 1:
            return .intensification
        case (.powerbuilding, .deload):               return .reaccumulation
        case (.recomp, .deload):                      return .accumulation
        case (.recomp, _):                            return .deload
        default:                                      return .accumulation
        }
    }
}

// ═══════════════════════════════════════════
// COMPUTED BLOCK INFO
// Derives block phase (type, number, week-in-block, display name) from a
// given week and program structure. Use this for ALL display sites so the UI
// reflects the week the user is browsing — not the stale `inst.blockType`
// stored state, which only advances when finalizeWorkout transitions.
// ═══════════════════════════════════════════

struct ComputedBlockInfo {
    let blockType: BlockType
    let blockNumber: Int           // 1-indexed
    let weekInBlock: Int           // 1-indexed, position within current block
    let blockTrainingWeeks: Int    // training weeks in this block (excludes the trailing deload)
    let isDeloadWeek: Bool
    let displayPhaseName: String   // goal-aware (e.g., "Training Block", "Growth Phase", "Recovery")

    static func compute(forWeek week: Int,
                        programId: Int,
                        blockLength: Int,
                        totalWeeks: Int,
                        goal: GoalType,
                        instance: UserProgramInstance? = nil) -> ComputedBlockInfo {
        // deloadWeeks(for:blockLength:instance:) lives in WorkoutView.swift —
        // it's the single source of truth, and when instance is provided it
        // honors user-defined overrides (customDeloadWeeks / skippedDeloadWeeks
        // set by BlockSequenceEditor).
        let deloads = deloadWeeks(for: programId, blockLength: blockLength, instance: instance)
        let isDeload = deloads.contains(week)
        let priorDeloads = deloads.filter { $0 < week }.sorted()
        let blockNumber = priorDeloads.count + 1
        let blockStart = (priorDeloads.last ?? 0) + 1
        // The deload week that ENDS this block. For the final block of a
        // program with no trailing deload, fall back to totalWeeks + 1.
        let nextDeload = deloads.filter { $0 >= week }.min() ?? (totalWeeks + 1)
        // Training weeks in the block = weeks between blockStart and the next
        // deload, exclusive of the deload itself. Bahri block 1: 1..2, week 3
        // = deload → 2 training weeks.
        let blockTrainingWeeks = max(1, nextDeload - blockStart)
        // weekInBlock counts only training weeks. During a deload, the value
        // matches the position in the block but UI should display "Recovery".
        let weekInBlock = isDeload
            ? blockTrainingWeeks + 1
            : max(1, week - blockStart + 1)

        // Block type derived from block number + goal. Direct mapping —
        // simpler than walking BlockType.next and matches the conventional
        // periodization patterns users expect.
        let bt: BlockType = {
            if isDeload { return .deload }
            switch goal {
            case .hypertrophy, .recomp:
                // Alternating accumulation / reaccumulation
                return blockNumber % 2 == 1 ? .accumulation : .reaccumulation
            case .strength:
                // 3-block cycles: accum → intens → peak
                let phase = (blockNumber - 1) % 3
                if phase == 0 { return .accumulation }
                if phase == 1 { return .intensification }
                return .peak
            case .powerbuilding:
                // Block 1 = accum, 2 = intens, 3+ alternates between reaccum and accum
                if blockNumber == 1 { return .accumulation }
                if blockNumber == 2 { return .intensification }
                return blockNumber % 2 == 1 ? .accumulation : .reaccumulation
            }
        }()

        let isHyp = goal == .hypertrophy || goal == .recomp
        let displayPhaseName: String = {
            if isDeload { return isHyp ? "Recovery" : "Deload" }
            if isHyp {
                return bt == .reaccumulation ? "Growth Phase" : "Training Block"
            }
            switch bt {
            case .accumulation:    return "Accumulation"
            case .intensification: return "Intensification"
            case .reaccumulation:  return goal == .powerbuilding ? "Volume Phase" : "Accumulation"
            case .peak:            return "Peaking"
            case .deload:          return "Deload"
            }
        }()

        return ComputedBlockInfo(
            blockType: bt,
            blockNumber: blockNumber,
            weekInBlock: weekInBlock,
            blockTrainingWeeks: blockTrainingWeeks,
            isDeloadWeek: isDeload,
            displayPhaseName: displayPhaseName
        )
    }
}

enum BlockPhase: String, Codable {
    case earlyAccumulation
    case lateAccumulation
    case intensification
    case deload
    case postDeloadReintro
}

enum StallReason: String, Codable {
    case none = "none"
    case e1rmFlat = "e1rm_flat"
    case e1rmDecline = "e1rm_decline"
    case rpeRising = "rpe_rising"
    case repsFlat = "reps_flat"
}

// ═══════════════════════════════════════════
// VOLUME LANDMARKS (MEV / MAV / MRV)
// ═══════════════════════════════════════════

struct VolumeLandmark {
    let mev: Int
    let mavLow: Int   // bottom of productive range
    let mavHigh: Int   // top of productive range (sweet spot target)
    let mrv: Int

    /// Convenience: midpoint of MAV range (used as the single "target" in UI)
    var mav: Int { (mavLow + mavHigh) / 2 }

    // Research-backed defaults (direct sets per week)
    // MEV lowered for muscles that get significant indirect volume from compounds
    static let defaults: [String: VolumeLandmark] = [
        "Chest":      VolumeLandmark(mev: 6,  mavLow: 10, mavHigh: 16, mrv: 22),
        "Back":       VolumeLandmark(mev: 8,  mavLow: 12, mavHigh: 18, mrv: 24),
        "Quads":      VolumeLandmark(mev: 6,  mavLow: 10, mavHigh: 16, mrv: 22),
        "Hamstrings": VolumeLandmark(mev: 4,  mavLow: 8,  mavHigh: 12, mrv: 18),
        "Glutes":     VolumeLandmark(mev: 2,  mavLow: 6,  mavHigh: 12, mrv: 18),
        "Calves":     VolumeLandmark(mev: 4,  mavLow: 6,  mavHigh: 10, mrv: 16),
        "Biceps":     VolumeLandmark(mev: 4,  mavLow: 8,  mavHigh: 12, mrv: 18),
        "Triceps":    VolumeLandmark(mev: 4,  mavLow: 6,  mavHigh: 10, mrv: 16),
        "Delts":      VolumeLandmark(mev: 6,  mavLow: 10, mavHigh: 14, mrv: 20),
    ]

    func scaled(by tier: MuscleTier) -> VolumeLandmark {
        let m = tier.multiplier
        return VolumeLandmark(
            mev: Int(round(Double(mev) * m)),
            mavLow: Int(round(Double(mavLow) * m)),
            mavHigh: Int(round(Double(mavHigh) * m)),
            mrv: Int(round(Double(mrv) * m))
        )
    }
}

extension VolumeLandmark {
    static func scaledMEV(muscle: String,
                           experience: ExperienceLevel) -> Int {
        let base = defaults[muscle]?.mev ?? 6
        let m: Double = switch experience {
        case .beginner:     1.0
        case .intermediate: 1.4
        case .advanced:     2.0
        case .elite:        2.3
        }
        return Int(Double(base) * m)
    }

    static func scaledMRV(muscle: String,
                           experience: ExperienceLevel) -> Int {
        let base = defaults[muscle]?.mrv ?? 20
        let m: Double = switch experience {
        case .beginner:     1.0
        case .intermediate: 1.2
        case .advanced:     1.35
        case .elite:        1.45
        }
        return Int(Double(base) * m)
    }

    static func effectiveMEV(muscle: String,
                              experience: ExperienceLevel,
                              tier: MuscleTier) -> Int {
        Int(Double(scaledMEV(muscle: muscle, experience: experience))
            * tier.multiplier)
    }

    static func effectiveMRV(muscle: String,
                              experience: ExperienceLevel,
                              tier: MuscleTier,
                              calorieContext: CalorieContext = .unknown
    ) -> Int {
        let scaled = scaledMRV(muscle: muscle, experience: experience)
        let tiered = Int(Double(scaled) * tier.multiplier)
        return Int(Double(tiered) * calorieContext.mrvModifier)
    }

    static func mv(muscle: String) -> Int {
        switch muscle {
        case "Chest", "Back", "Quads", "Calves": return 6
        case "Hamstrings", "Glutes",
             "Delts", "Triceps", "Biceps":       return 4
        default:                                  return 4
        }
    }
}

// ═══════════════════════════════════════════
// INDIRECT VOLUME MAP
// Compound exercises contribute partial volume to secondary muscles
// ═══════════════════════════════════════════

struct IndirectVolumeMap {
    /// Fallback weight for custom exercises not in ExerciseDictionary (0.5 = half a direct set)
    static let secondaryWeight: Double = 0.5

    /// Look up per-exercise secondary muscle weights from the dictionary.
    /// Returns normalized tracking-muscle → weight mapping.
    /// Falls back to empty dict for unknown/custom exercises (caller should use secondaryWeight).
    static func secondaryWeights(for exerciseKey: String) -> [String: Double] {
        guard let def = ExerciseDictionary.all[exerciseKey] else { return [:] }
        var result = [String: Double]()
        for sm in def.secondaryMuscles {
            if let normalized = ExerciseDictionary.normalizeMuscle(sm.muscle) {
                // Keep the higher weight if multiple secondaries normalize to same group
                result[normalized] = max(result[normalized] ?? 0, sm.weight)
            }
        }
        return result
    }
}

enum CalorieContext: String, Codable, CaseIterable {
    case unknown = "unknown"
    case surplus = "surplus"
    case maintenance = "maintenance"
    case mildDeficit = "mild_deficit"
    case moderateDeficit = "moderate_deficit"
    case aggressiveDeficit = "aggressive_deficit"

    var mrvModifier: Double {
        switch self {
        case .unknown, .surplus:   return 1.0
        case .maintenance:         return 1.0
        case .mildDeficit:         return 0.90
        case .moderateDeficit:     return 0.85
        case .aggressiveDeficit:   return 0.75
        }
    }
}

enum RespondsBetterTo: String, Codable {
    case highVolumeLowIntensity
    case lowVolumeHighIntensity
    case balanced
}

enum ProgressionRate: String, Codable {
    case fast   = "fast"
    case normal = "normal"
    case slow   = "slow"
}

enum AlgorithmMode: String, Codable, CaseIterable {
    case full        = "full"         // Auto-adjusts weight, reps, volume, deloads
    case suggestions = "suggestions"  // Shows recommendations but nothing pre-filled
    case off         = "off"          // Pure logger, algorithm tracks in background

    var displayName: String {
        switch self {
        case .full: return "Full"
        case .suggestions: return "Suggestions"
        case .off: return "Off"
        }
    }

    var subtitle: String {
        switch self {
        case .full: return "Auto-adjusts weight, reps, and volume"
        case .suggestions: return "Shows recommendations — you decide"
        case .off: return "Pure logger, no recommendations shown"
        }
    }
}

enum MuscleTier: String, Codable, CaseIterable {
    case priority = "priority"
    case neutral = "neutral"
    case maintenance = "maintenance"

    var multiplier: Double {
        switch self {
        case .priority: return 1.5
        case .neutral: return 1.0
        case .maintenance: return 0.7
        }
    }

    var label: String {
        switch self {
        case .priority: return "Priority"
        case .neutral: return "Neutral"
        case .maintenance: return "Maintenance"
        }
    }
}

enum VolumeZone: String {
    case underTraining = "UNDER-TRAINING"
    case building = "BUILDING"
    case optimal = "OPTIMAL"
    case overReaching = "OVER-REACHING"

    static func classify(sets: Int, landmark: VolumeLandmark) -> VolumeZone {
        if sets < landmark.mev { return .underTraining }
        if sets < landmark.mavLow { return .building }
        if sets <= landmark.mrv { return .optimal }
        return .overReaching
    }

    static func classify(
        directSets: Int,
        indirectSets: Double = 0,
        muscle: String,
        experience: ExperienceLevel,
        tier: MuscleTier
    ) -> VolumeZone {
        let effective = directSets + Int(indirectSets.rounded())
        let mev = VolumeLandmark.effectiveMEV(muscle: muscle,
                                               experience: experience, tier: tier)
        let mrv = VolumeLandmark.effectiveMRV(muscle: muscle,
                                               experience: experience, tier: tier)
        let mavLow = VolumeLandmark.scaledMEV(muscle: muscle,
                                               experience: experience)
        if effective < mev    { return .underTraining }
        if effective < mavLow { return .building }
        if effective <= mrv   { return .optimal }
        return .overReaching
    }
}

enum IFIZone: String, Codable {
    case fresh         = "FRESH"
    case optimal       = "OPTIMAL"
    case fatigued      = "FATIGUED"
    case acuteOverreach = "HIGH FATIGUE"

    static func classify(_ ifi: Double) -> IFIZone {
        if ifi < 0.10 { return .fresh }
        if ifi < 0.25 { return .optimal }
        if ifi < 0.40 { return .fatigued }
        return .acuteOverreach
    }
}

extension IFIZone {
    init(ifi: Double) {
        switch ifi {
        case ..<0.10:  self = .fresh
        case ..<0.25:  self = .optimal
        case ..<0.40:  self = .fatigued
        default:       self = .acuteOverreach
        }
    }
}

enum StallDiagnosis: String {
    case fatigueStall = "Fatigue Stall"
    case intensityStall = "Intensity Stall"
    case truePlateau = "True Plateau"
    case volumeStall = "Volume Stall"
    case noStall = "No Stall"
}

enum StallUrgency: String {
    case suggestion = "suggestion"     // 1st occurrence
    case warning = "warning"           // 2nd consecutive
    case actionRequired = "action_required"  // 3rd+ consecutive — hard prompt

    static func from(consecutiveCount: Int) -> StallUrgency {
        switch consecutiveCount {
        case ...1:  return .suggestion
        case 2:     return .warning
        default:    return .actionRequired
        }
    }
}

// ═══════════════════════════════════════════
// EXERCISE
// ═══════════════════════════════════════════

@Model
class Exercise {
    var exerciseKey: String
    var displayName: String
    var movementPatternRaw: String
    var musclesPrimary: [String]
    var musclesSecondary: [String]
    var equipmentRaw: String
    var isCompound: Bool
    var isCustom: Bool
    var jointStressTags: [String]
    var variationOfKey: String?
    var stretchPositionRaw: String = "mid"
    var cue: String = ""
    var exerciseTierRaw: String = "tier2"
    var createdAt: Date
    var updatedAt: Date

    var exerciseTier: ExerciseTier {
        get { ExerciseTier(rawValue: exerciseTierRaw) ?? .tier2 }
        set { exerciseTierRaw = newValue.rawValue }
    }

    var movementPattern: MovementPattern {
        get { MovementPattern(rawValue: movementPatternRaw) ?? .isolation }
        set { movementPatternRaw = newValue.rawValue }
    }

    var equipment: EquipmentType {
        get { EquipmentType(rawValue: equipmentRaw) ?? .other }
        set { equipmentRaw = newValue.rawValue }
    }

    var stretchPosition: StretchPosition {
        get { StretchPosition(rawValue: stretchPositionRaw) ?? .mid }
        set { stretchPositionRaw = newValue.rawValue }
    }

    init(
        exerciseKey: String,
        displayName: String,
        movementPattern: MovementPattern,
        musclesPrimary: [String],
        musclesSecondary: [String] = [],
        equipment: EquipmentType,
        isCompound: Bool,
        isCustom: Bool = false,
        jointStressTags: [String] = [],
        variationOfKey: String? = nil,
        stretchPosition: StretchPosition = .mid
    ) {
        self.exerciseKey = exerciseKey
        self.displayName = displayName
        self.movementPatternRaw = movementPattern.rawValue
        self.musclesPrimary = musclesPrimary
        self.musclesSecondary = musclesSecondary
        self.equipmentRaw = equipment.rawValue
        self.isCompound = isCompound
        self.isCustom = isCustom
        self.jointStressTags = jointStressTags
        self.variationOfKey = variationOfKey
        self.stretchPositionRaw = stretchPosition.rawValue
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// ═══════════════════════════════════════════
// USER PROFILE
// ═══════════════════════════════════════════

@Model
class UserProfile {
    var name: String
    var bodyweight: Double
    var age: Int
    var useMetric: Bool
    var goalRaw: String
    var experienceRaw: String
    var daysPerWeek: Int
    var priorityMuscles: [String]
    var missedWorkoutPolicyRaw: String
    var muscleTiersData: Data
    var sessionDurationTarget: Int = 90
    var calorieContextRaw: String = "unknown"
    var progressionRateRaw: String = "normal"
    var respondsBetterToRaw: String? = nil
    var useGeneratedPrograms: Bool = true
    var algorithmModeRaw: String = "full"
    var showWarmups: Bool = true
    var showRPE: Bool = true
    var showRepRange: Bool = true
    var showRestTimer: Bool = true
    var skipDeloads: Bool = false
    /// JSON [String: Int] — custom per-muscle weekly target sets that override
    /// the tier-derived default. Empty/missing = use the tier-derived default.
    var muscleTargetOverridesData: Data = Data()

    var goal: GoalType {
        get { GoalType(rawValue: goalRaw) ?? GoalType.migrate(from: goalRaw) }
        set { goalRaw = newValue.rawValue }
    }

    var experience: ExperienceLevel {
        get { ExperienceLevel(rawValue: experienceRaw) ?? .beginner }
        set { experienceRaw = newValue.rawValue }
    }

    var missedWorkoutPolicy: MissedWorkoutPolicy {
        get { MissedWorkoutPolicy(rawValue: missedWorkoutPolicyRaw) ?? .rotation }
        set { missedWorkoutPolicyRaw = newValue.rawValue }
    }

    var respondsBetterTo: RespondsBetterTo? {
        get {
            guard let raw = respondsBetterToRaw else { return nil }
            return RespondsBetterTo(rawValue: raw)
        }
        set { respondsBetterToRaw = newValue?.rawValue }
    }

    var calorieContext: CalorieContext {
        CalorieContext(rawValue: calorieContextRaw) ?? .unknown
    }

    var progressionRate: ProgressionRate {
        get { ProgressionRate(rawValue: progressionRateRaw) ?? .normal }
        set { progressionRateRaw = newValue.rawValue }
    }

    var algorithmMode: AlgorithmMode {
        get { AlgorithmMode(rawValue: algorithmModeRaw) ?? .full }
        set { algorithmModeRaw = newValue.rawValue }
    }

    var muscleTiers: [String: MuscleTier] {
        get {
            guard !muscleTiersData.isEmpty,
                  let raw = try? JSONDecoder().decode([String: String].self, from: muscleTiersData) else {
                // Migrate legacy priorityMuscles
                var tiers: [String: MuscleTier] = [:]
                for m in priorityMuscles { tiers[m] = .priority }
                return tiers
            }
            return raw.compactMapValues { MuscleTier(rawValue: $0) }
        }
        set {
            let raw = newValue.mapValues { $0.rawValue }
            muscleTiersData = (try? JSONEncoder().encode(raw)) ?? Data()
            // Keep priorityMuscles in sync for backward compat
            priorityMuscles = newValue.filter { $0.value == .priority }.map { $0.key }
        }
    }

    func tier(for muscle: String) -> MuscleTier {
        muscleTiers[muscle] ?? .neutral
    }

    /// Custom per-muscle weekly set targets. Stored as JSON [muscle: sets].
    /// nil/missing entry means "use tier-derived default."
    var muscleTargetOverrides: [String: Int] {
        get {
            guard !muscleTargetOverridesData.isEmpty,
                  let raw = try? JSONDecoder().decode([String: Int].self,
                                                      from: muscleTargetOverridesData) else {
                return [:]
            }
            return raw
        }
        set {
            muscleTargetOverridesData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    /// The user's effective weekly target for a muscle: custom override if set,
    /// otherwise the tier-derived MAVHigh default. Used as the "target" line
    /// in volume bars and as the optimal-zone ceiling in zone classification.
    func effectiveTarget(for muscle: String) -> Int {
        if let custom = muscleTargetOverrides[muscle], custom > 0 { return custom }
        let t = tier(for: muscle)
        let base = VolumeLandmark.defaults[muscle] ?? VolumeLandmark(mev: 4, mavLow: 8, mavHigh: 12, mrv: 18)
        return Int(round(Double(base.mavHigh) * t.multiplier))
    }

    init(
        name: String,
        bodyweight: Double,
        age: Int,
        useMetric: Bool,
        goal: String = "Both",
        experience: String = "Beginner",
        daysPerWeek: Int = 4,
        priorityMuscles: [String] = [],
        missedWorkoutPolicy: String = "rotation"
    ) {
        self.name = name
        self.bodyweight = bodyweight
        self.age = age
        self.useMetric = useMetric
        self.goalRaw = goal
        self.experienceRaw = experience
        self.daysPerWeek = daysPerWeek
        self.priorityMuscles = priorityMuscles
        self.missedWorkoutPolicyRaw = missedWorkoutPolicy
        self.muscleTiersData = Data()
    }
}

// ═══════════════════════════════════════════
// PROGRAM TEMPLATE (static, versioned)
// ═══════════════════════════════════════════

@Model
class ProgramTemplate {
    var programId: Int
    var name: String
    var version: Int
    var durationWeeks: Int
    var sessionTypeRaws: [String]
    var scheduleOptions: [String]

    var sessionTypes: [SessionType] {
        sessionTypeRaws.compactMap { SessionType(rawValue: $0) }
    }

    init(
        programId: Int,
        name: String,
        version: Int = 1,
        durationWeeks: Int = 24,
        sessionTypes: [SessionType],
        scheduleOptions: [String]
    ) {
        self.programId = programId
        self.name = name
        self.version = version
        self.durationWeeks = durationWeeks
        self.sessionTypeRaws = sessionTypes.map { $0.rawValue }
        self.scheduleOptions = scheduleOptions
    }
}

// ═══════════════════════════════════════════
// PROGRAM SESSION TEMPLATE
// One record per (programId, version, week, sessionType, slotId)
// ═══════════════════════════════════════════

@Model
class ProgramSessionTemplate {
    var programId: Int
    var programVersion: Int
    var week: Int
    var sessionTypeRaw: String
    var slotId: String
    var exerciseIndex: Int
    var exerciseKey: String
    var roleRaw: String
    var isMainLift: Bool
    var targetSets: Int
    var targetRepsLow: Int
    var targetRepsHigh: Int
    var targetRPE: Double
    var restSeconds: Int
    var notes: String
    var suggestedWeight: Double = 0

    var sessionType: SessionType {
        get { SessionType(rawValue: sessionTypeRaw) ?? .heavyUpper }
        set { sessionTypeRaw = newValue.rawValue }
    }

    var role: ExerciseRole {
        get { ExerciseRole(rawValue: roleRaw) ?? .accessory }
        set { roleRaw = newValue.rawValue }
    }

    init(
        programId: Int,
        programVersion: Int = 1,
        week: Int,
        sessionType: SessionType,
        slotId: String,
        exerciseIndex: Int,
        exerciseKey: String,
        role: ExerciseRole = .accessory,
        isMainLift: Bool = false,
        targetSets: Int,
        targetRepsLow: Int,
        targetRepsHigh: Int,
        targetRPE: Double,
        restSeconds: Int,
        notes: String = ""
    ) {
        self.programId = programId
        self.programVersion = programVersion
        self.week = week
        self.sessionTypeRaw = sessionType.rawValue
        self.slotId = slotId
        self.exerciseIndex = exerciseIndex
        self.exerciseKey = exerciseKey
        self.roleRaw = role.rawValue
        self.isMainLift = isMainLift
        self.targetSets = targetSets
        self.targetRepsLow = targetRepsLow
        self.targetRepsHigh = targetRepsHigh
        self.targetRPE = targetRPE
        self.restSeconds = restSeconds
        self.notes = notes
    }
}

// ═══════════════════════════════════════════
// USER PROGRAM INSTANCE
// ═══════════════════════════════════════════

@Model
class UserProgramInstance {
    var programId: Int
    var programVersion: Int
    var name: String
    var startDate: Date
    var microcycleIndex: Int
    var nextRotationIndex: Int
    var isActive: Bool
    var missedWorkoutPolicyRaw: String
    var blockTypeRaw: String = "accumulation"
    var blockWeek: Int = 1
    var blockLength: Int = 4
    var totalBlocksCompleted: Int = 0
    var currentWeekSetsData: Data = Data()
    var nextWeekSetAdjustmentsData: Data = Data()
    var mrvSignalScoresData: Data = Data()
    var previousBlockExerciseKeysData: Data = Data()
    var isGenerated: Bool = false

    @Relationship(deleteRule: .cascade)
    var schedules: [ProgramSchedule] = []

    @Relationship(deleteRule: .cascade)
    var overrides: [SessionOverride] = []

    @Relationship(deleteRule: .cascade)
    var workouts: [ActiveWorkout] = []

    @Relationship(deleteRule: .cascade)
    var logs: [WorkoutLog] = []

    @Relationship(deleteRule: .cascade)
    var progressionStates: [ProgressionState] = []

    @Relationship(deleteRule: .cascade)
    var landmarkCalibrations: [LandmarkCalibration] = []

    @Relationship(deleteRule: .cascade)
    var strengthGoals: [StrengthGoal] = []

    /// JSON-encoded [Int] — user-added deload weeks beyond program defaults
    var customDeloadWeeksData: Data = Data()
    /// JSON-encoded [Int] — program-default deload weeks the user has skipped
    var skippedDeloadWeeksData: Data = Data()

    var customDeloadWeeks: Set<Int> {
        get { (try? JSONDecoder().decode(Set<Int>.self, from: customDeloadWeeksData)) ?? [] }
        set { customDeloadWeeksData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var skippedDeloadWeeks: Set<Int> {
        get { (try? JSONDecoder().decode(Set<Int>.self, from: skippedDeloadWeeksData)) ?? [] }
        set { skippedDeloadWeeksData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    /// Returns true if a given week is an effective deload (program default + custom - skipped)
    func isEffectiveDeload(_ week: Int, programId: Int) -> Bool {
        let programDeloads = UserProgramInstance.defaultDeloadWeeks(for: programId)
        let activeDefaults = programDeloads.subtracting(skippedDeloadWeeks)
        return activeDefaults.contains(week) || customDeloadWeeks.contains(week)
    }

    static func defaultDeloadWeeks(for programId: Int) -> Set<Int> {
        switch programId {
        case 2: return [4, 12, 16]
        case 7: return Set([3,6,9,12,15,18,21,24])
        default: return [4, 12, 20]
        }
    }

    var missedWorkoutPolicy: MissedWorkoutPolicy {
        get { MissedWorkoutPolicy(rawValue: missedWorkoutPolicyRaw) ?? .rotation }
        set { missedWorkoutPolicyRaw = newValue.rawValue }
    }

    var blockType: BlockType {
        get { BlockType(rawValue: blockTypeRaw) ?? .accumulation }
        set { blockTypeRaw = newValue.rawValue }
    }

    var blockPhase: BlockPhase {
        if blockType == .deload { return .deload }
        if blockWeek == 1 && totalBlocksCompleted > 0 { return .postDeloadReintro }
        let midpoint = max(1, blockLength / 2)
        return blockWeek <= midpoint ? .earlyAccumulation : .lateAccumulation
    }

    var currentWeekSets: [String: Int] {
        get { (try? JSONDecoder().decode([String: Int].self,
                                         from: currentWeekSetsData)) ?? [:] }
        set { currentWeekSetsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var nextWeekSetAdjustments: [String: Int] {
        get { (try? JSONDecoder().decode([String: Int].self,
                                         from: nextWeekSetAdjustmentsData)) ?? [:] }
        set { nextWeekSetAdjustmentsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var mrvSignalScores: [String: Int] {
        get { (try? JSONDecoder().decode([String: Int].self,
                                         from: mrvSignalScoresData)) ?? [:] }
        set { mrvSignalScoresData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var previousBlockExerciseKeys: Set<String> {
        get {
            (try? JSONDecoder().decode(Set<String>.self,
                                       from: previousBlockExerciseKeysData)) ?? []
        }
        set {
            previousBlockExerciseKeysData =
                (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    var currentWeek: Int {
        microcycleIndex + 1
    }

    /// Compute the start date for a given week number (1-based)
    func weekStartDate(for week: Int) -> Date {
        Calendar.current.date(byAdding: .weekOfYear, value: week - 1, to: Calendar.current.startOfDay(for: startDate)) ?? startDate
    }

    /// Format a week's date range for display
    func weekDateLabel(for week: Int) -> String {
        let start = weekStartDate(for: week)
        let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return "\(f.string(from: start)) – \(f.string(from: end))"
    }

    init(
        programId: Int,
        programVersion: Int = 1,
        name: String,
        startDate: Date = Date(),
        missedWorkoutPolicy: MissedWorkoutPolicy = .rotation
    ) {
        self.programId = programId
        self.programVersion = programVersion
        self.name = name
        self.startDate = startDate
        self.microcycleIndex = 0
        self.nextRotationIndex = 0
        self.isActive = true
        self.missedWorkoutPolicyRaw = missedWorkoutPolicy.rawValue
    }
}

// ═══════════════════════════════════════════
// PROGRAM SCHEDULE
// ═══════════════════════════════════════════

@Model
class ProgramSchedule {
    var dayOfWeek: Int
    var sessionTypeRaw: String
    var isRestDay: Bool
    var rotationIndex: Int
    var fallbackSessionTypeRaw: String?
    var week: Int
    var isPermanent: Bool
    var dayTemplateId: String = ""

    var programInstance: UserProgramInstance?

    var sessionType: SessionType {
        get { SessionType(rawValue: sessionTypeRaw) ?? .rest }
        set { sessionTypeRaw = newValue.rawValue }
    }

    var fallbackSessionType: SessionType? {
        get {
            guard let raw = fallbackSessionTypeRaw else { return nil }
            return SessionType(rawValue: raw)
        }
        set { fallbackSessionTypeRaw = newValue?.rawValue }
    }

    init(
        dayOfWeek: Int,
        sessionType: SessionType,
        isRestDay: Bool = false,
        rotationIndex: Int = 0,
        fallbackSessionType: SessionType? = nil,
        week: Int = 0,
        isPermanent: Bool = false,
        dayTemplateId: String = ""
    ) {
        self.dayOfWeek = dayOfWeek
        self.sessionTypeRaw = sessionType.rawValue
        self.isRestDay = isRestDay
        self.rotationIndex = rotationIndex
        self.fallbackSessionTypeRaw = fallbackSessionType?.rawValue
        self.week = week
        self.isPermanent = isPermanent
        self.dayTemplateId = dayTemplateId
    }
}

// ═══════════════════════════════════════════
// STRENGTH GOAL
// ═══════════════════════════════════════════

enum StrengthGoalPhase: String, Codable, CaseIterable {
    case building       = "building"
    case intensifying   = "intensifying"
    case peaking        = "peaking"
    case testing        = "testing"

    var displayName: String {
        rawValue.capitalized
    }

    var repRange: (low: Int, high: Int) {
        switch self {
        case .building:     return (3, 5)
        case .intensifying: return (2, 3)
        case .peaking:      return (1, 2)
        case .testing:      return (1, 1)
        }
    }

    var targetSets: Int {
        switch self {
        case .building:     return 4
        case .intensifying: return 3
        case .peaking:      return 2
        case .testing:      return 1
        }
    }

    var targetRPE: Double {
        switch self {
        case .building:     return 7.5
        case .intensifying: return 8.5
        case .peaking:      return 9.0
        case .testing:      return 10.0
        }
    }

    var percentE1RM: (low: Double, high: Double) {
        switch self {
        case .building:     return (0.78, 0.85)
        case .intensifying: return (0.85, 0.92)
        case .peaking:      return (0.92, 0.97)
        case .testing:      return (0.98, 1.00)
        }
    }

    var next: StrengthGoalPhase {
        switch self {
        case .building:     return .intensifying
        case .intensifying: return .peaking
        case .peaking:      return .testing
        case .testing:      return .testing
        }
    }

    func weeksInPhase(gapPercent: Double) -> Int {
        switch self {
        case .building:     return gapPercent > 15 ? 5 : (gapPercent > 10 ? 4 : (gapPercent > 5 ? 3 : 2))
        case .intensifying: return gapPercent > 10 ? 3 : 2
        case .peaking:      return gapPercent > 15 ? 2 : 1
        case .testing:      return 1
        }
    }
}

@Model
class StrengthGoal {
    var exerciseKey: String
    var displayName: String
    var targetWeight: Double
    var startE1RM: Double
    var phaseRaw: String = "building"
    var phaseWeek: Int = 1
    var isActive: Bool = true
    var createdAt: Date = Date()
    var completedAt: Date? = nil
    var restSeconds: Int = 180

    var programInstance: UserProgramInstance?

    var phase: StrengthGoalPhase {
        get { StrengthGoalPhase(rawValue: phaseRaw) ?? .building }
        set { phaseRaw = newValue.rawValue }
    }

    var gapPercent: Double {
        guard startE1RM > 0 else { return 0 }
        return (targetWeight - startE1RM) / startE1RM * 100
    }

    var currentPhaseLength: Int {
        phase.weeksInPhase(gapPercent: gapPercent)
    }

    var totalProgramWeeks: Int {
        StrengthGoalPhase.allCases.reduce(0) { $0 + $1.weeksInPhase(gapPercent: gapPercent) }
    }

    /// Prescribe weight for today based on current e1RM and phase progress.
    /// Uses current (growing) e1RM, not static startE1RM.
    /// Testing phase targets the actual goal weight.
    func prescribeWeight(currentE1RM: Double, useMetric: Bool) -> Double {
        if phase == .testing {
            // Testing phase: work up to target weight
            return RPETable.roundToPlate(targetWeight, useMetric: useMetric)
        }
        // Other phases: percentage of CURRENT e1RM (which grows as user trains)
        let pcts = phase.percentE1RM
        let progress = Double(phaseWeek - 1) / Double(max(currentPhaseLength - 1, 1))
        let pct = pcts.low + (pcts.high - pcts.low) * progress
        return RPETable.roundToPlate(currentE1RM * pct, useMetric: useMetric)
    }

    /// Project week-by-week weights assuming e1RM grows linearly toward target.
    /// Returns [(week, phase, weight, sets, repsRange)] for display.
    func weekByWeekProjection(useMetric: Bool) -> [(week: Int, phase: StrengthGoalPhase, weight: Double, sets: Int, repsLow: Int, repsHigh: Int)] {
        let gap = gapPercent
        var result: [(week: Int, phase: StrengthGoalPhase, weight: Double, sets: Int, repsLow: Int, repsHigh: Int)] = []
        var weekNum = 0
        let totalWks = totalProgramWeeks
        guard totalWks > 0 else { return [] }

        for phase in StrengthGoalPhase.allCases {
            let phaseLen = phase.weeksInPhase(gapPercent: gap)
            for wk in 1...max(1, phaseLen) {
                guard phaseLen > 0 else { continue }
                weekNum += 1
                // Estimate e1RM at this week (linear interpolation from start to target)
                let overallProgress = Double(weekNum) / Double(totalWks)
                let estimatedE1RM = startE1RM + (targetWeight - startE1RM) * overallProgress

                let weight: Double
                if phase == .testing {
                    weight = RPETable.roundToPlate(targetWeight, useMetric: useMetric)
                } else {
                    let pcts = phase.percentE1RM
                    let phaseProgress = Double(wk - 1) / Double(max(phaseLen - 1, 1))
                    let pct = pcts.low + (pcts.high - pcts.low) * phaseProgress
                    weight = RPETable.roundToPlate(estimatedE1RM * pct, useMetric: useMetric)
                }

                let rr = phase.repRange
                result.append((weekNum, phase, weight, phase.targetSets, rr.low, rr.high))
            }
        }
        return result
    }

    func advanceWeek() {
        phaseWeek += 1
        if phaseWeek > currentPhaseLength {
            if phase != .testing {
                phase = phase.next
                phaseWeek = 1
            }
        }
    }

    init(exerciseKey: String, displayName: String, targetWeight: Double, startE1RM: Double) {
        self.exerciseKey = exerciseKey
        self.displayName = displayName
        self.targetWeight = targetWeight
        self.startE1RM = startE1RM
    }
}

// ═══════════════════════════════════════════
// DAY TEMPLATE
// ═══════════════════════════════════════════

@Model
class DayTemplate {
    var templateId: UUID
    var name: String
    var iconName: String = "dumbbell.fill"
    var colorHex: String = "appRed"
    var exercisesData: Data = Data()
    var createdAt: Date

    init(name: String, iconName: String = "dumbbell.fill", colorHex: String = "appRed") {
        self.templateId = UUID()
        self.name = name
        self.iconName = iconName
        self.colorHex = colorHex
        self.exercisesData = Data()
        self.createdAt = Date()
    }

    var exercises: [BuilderExercise] {
        get { (try? JSONDecoder().decode([BuilderExercise].self, from: exercisesData)) ?? [] }
        set { exercisesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
}

// ═══════════════════════════════════════════
// SESSION OVERRIDE
// ═══════════════════════════════════════════

@Model
class SessionOverride {
    var sessionTypeRaw: String
    var targetExerciseKey: String
    var targetSlotId: String
    var replacementExerciseKey: String
    var appliesFromWeek: Int
    var scopeRaw: String
    var scopeEndWeek: Int?
    var reason: String
    var isAddition: Bool
    var createdAt: Date
    // Fields used when isAddition=true to prescribe the added exercise
    var addedSets: Int = 3
    var addedRepsLow: Int = 8
    var addedRepsHigh: Int = 12
    var addedRPE: Double = 8.0
    var addedRest: Int = 90

    /// Adjusts the targetSets of an existing template slot for the scoped weeks.
    /// Negative reduces, positive augments. Zero = no adjustment (default).
    /// Used by VolumeAdjusterSheet for per-slot decrease/increase without
    /// replacing the exercise.
    var setCountDelta: Int = 0

    var programInstance: UserProgramInstance?

    var sessionType: SessionType {
        get { SessionType(rawValue: sessionTypeRaw) ?? .heavyUpper }
        set { sessionTypeRaw = newValue.rawValue }
    }

    var scope: OverrideScope {
        get { OverrideScope(rawValue: scopeRaw) ?? .single }
        set { scopeRaw = newValue.rawValue }
    }

    init(
        sessionType: SessionType,
        targetExerciseKey: String,
        targetSlotId: String,
        replacementExerciseKey: String,
        appliesFromWeek: Int,
        scope: OverrideScope = .single,
        scopeEndWeek: Int? = nil,
        reason: String = "userSwap",
        isAddition: Bool = false
    ) {
        self.sessionTypeRaw = sessionType.rawValue
        self.targetExerciseKey = targetExerciseKey
        self.targetSlotId = targetSlotId
        self.replacementExerciseKey = replacementExerciseKey
        self.appliesFromWeek = appliesFromWeek
        self.scopeRaw = scope.rawValue
        self.scopeEndWeek = scopeEndWeek
        self.reason = reason
        self.isAddition = isAddition
        self.createdAt = Date()
    }

    /// Whether this override applies to a given week number
    func appliesTo(week: Int) -> Bool {
        switch scope {
        case .single:
            return appliesFromWeek == week
        case .future:
            return week >= appliesFromWeek
        case .range:
            let end = scopeEndWeek ?? appliesFromWeek
            return week >= appliesFromWeek && week <= end
        }
    }
}

/// Resolve the effective exercise key for a slot, considering overrides scoped to a specific week
func resolveExerciseKey(slotId: String, originalKey: String, overrides: [SessionOverride], week: Int) -> String {
    overrides
        .filter { $0.targetSlotId == slotId && !$0.isAddition && $0.appliesTo(week: week) }
        .sorted { $0.createdAt > $1.createdAt }
        .first?.replacementExerciseKey ?? originalKey
}

// ═══════════════════════════════════════════
// ACTIVE WORKOUT
// Materialized and locked at start time
// renderedExercisesData is JSON encoded
// ═══════════════════════════════════════════

@Model
class ActiveWorkout {
    var date: Date
    var week: Int
    var sessionTypeRaw: String
    var startedAt: Date?
    var completedAt: Date?
    var isComplete: Bool
    var renderedExercisesData: Data

    var programInstance: UserProgramInstance?

    var sessionType: SessionType {
        get { SessionType(rawValue: sessionTypeRaw) ?? .heavyUpper }
        set { sessionTypeRaw = newValue.rawValue }
    }

    var renderedExercises: [RenderedExercise] {
        get {
            (try? JSONDecoder().decode([RenderedExercise].self, from: renderedExercisesData)) ?? []
        }
        set {
            renderedExercisesData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    init(
        date: Date = Date(),
        week: Int,
        sessionType: SessionType
    ) {
        self.date = date
        self.week = week
        self.sessionTypeRaw = sessionType.rawValue
        self.startedAt = nil
        self.completedAt = nil
        self.isComplete = false
        self.renderedExercisesData = Data()
    }
}

// ═══════════════════════════════════════════
// RENDERED EXERCISE + SET (Codable snapshots)
// ═══════════════════════════════════════════

struct RenderedExercise: Codable {
    var exerciseKey: String
    var displayName: String
    var slotId: String
    var role: String
    var isMainLift: Bool
    var targetSets: Int
    var targetRepsLow: Int
    var targetRepsHigh: Int
    var targetRPE: Double
    var restSeconds: Int
    var notes: String
    var recommendedWeight: Double
    var substitutionApplied: Bool
    var sets: [RenderedSet]
}

struct RenderedSet: Codable {
    var setIndex: Int
    var recommendedWeight: Double
    var recommendedReps: Int
    var loggedWeight: Double?
    var loggedReps: Int?
    var loggedRPE: Double?
    var isComplete: Bool
    var e1rm: Double?

    var isLogged: Bool {
        loggedWeight != nil && loggedReps != nil
    }
}

// ═══════════════════════════════════════════
// WORKOUT LOG
// ═══════════════════════════════════════════

@Model
class WorkoutLog {
    var date: Date
    /// The original workout date — set once at finalization, never changed on edits
    var workoutDate: Date = Date()
    var week: Int
    var sessionTypeRaw: String
    var exerciseKey: String
    var displayName: String
    var slotId: String
    var setIndex: Int
    var weight: Double
    var reps: Int
    var rpe: Double
    var e1rm: Double
    var e1rmFormulaVersion: Int
    var isMainLift: Bool
    var isTopSet: Bool
    var hitTargetReps: Bool
    var suggestedWeight: Double
    var acceptedSuggestion: Bool
    var sessionNotes: String = ""
    var targetRepsLow: Int = 0
    var previousWeight: Double = 0
    var readiness: Int = 0
    var isManualPR: Bool = false

    var programInstance: UserProgramInstance?

    var sessionType: SessionType {
        get { SessionType(rawValue: sessionTypeRaw) ?? .heavyUpper }
        set { sessionTypeRaw = newValue.rawValue }
    }

    func recomputeE1RM() {
        self.e1rm = WorkoutLog.computeE1RM(
            weight: weight,
            reps: reps,
            formulaVersion: e1rmFormulaVersion
        )
    }

    static func computeE1RM(
        weight: Double,
        reps: Int,
        formulaVersion: Int = 1
    ) -> Double {
        guard reps > 1 else { return weight }
        switch formulaVersion {
        case 1: return weight * (1.0 + Double(reps) / 30.0)
        default: return weight * (1.0 + Double(reps) / 30.0)
        }
    }

    init(
        date: Date = Date(),
        workoutDate: Date? = nil,
        week: Int,
        sessionType: SessionType,
        exerciseKey: String,
        displayName: String,
        slotId: String,
        setIndex: Int,
        weight: Double,
        reps: Int,
        rpe: Double = 0,
        isMainLift: Bool = false,
        isTopSet: Bool = false,
        hitTargetReps: Bool = false,
        suggestedWeight: Double = 0,
        acceptedSuggestion: Bool = false
    ) {
        self.date = date
        self.workoutDate = workoutDate ?? date
        self.week = week
        self.sessionTypeRaw = sessionType.rawValue
        self.exerciseKey = exerciseKey
        self.displayName = displayName
        self.slotId = slotId
        self.setIndex = setIndex
        self.weight = weight
        self.reps = reps
        self.rpe = rpe
        self.e1rmFormulaVersion = 1
        self.isMainLift = isMainLift
        self.isTopSet = isTopSet
        self.hitTargetReps = hitTargetReps
        self.suggestedWeight = suggestedWeight
        self.acceptedSuggestion = acceptedSuggestion
        self.e1rm = WorkoutLog.computeE1RM(weight: weight, reps: reps)
    }
}

// ═══════════════════════════════════════════
// PROGRESSION STATE (cached per lift)
// ═══════════════════════════════════════════

@Model
class ProgressionState {
    var exerciseKey: String
    var bestE1RM: Double
    var lastSessionWeight: Double
    var lastSessionReps: Int
    var lastSessionRPE: Double
    var lastSuggestedWeight: Double
    var lastCompletedWeight: Double
    var consecutiveSuccesses: Int
    var consecutiveFailures: Int
    var totalExposures: Int
    var weeksAtSameLoad: Int
    var isStalled: Bool
    var stallReasonRaw: String
    var lastIFI: Double
    var ifiTrend: Double
    var lastStallDiagnosisRaw: String
    var consecutiveStallDiagnoses: Int
    var emaE1rm: Double = 0
    var baselineE1rm: Double = 0
    var previousWeight: Double = 0
    var previousReps: Int = 0
    var lastProgressionRuleRaw: String = "hold"
    var lastSignalDate: Date? = nil
    var personalFatigueSensitivity: Double = 0.12
    var updatedAt: Date

    var programInstance: UserProgramInstance?

    var lastProgressionRule: ProgressionRule {
        get { ProgressionRule(rawValue: lastProgressionRuleRaw) ?? .hold }
        set { lastProgressionRuleRaw = newValue.rawValue }
    }

    var stallReason: StallReason {
        get { StallReason(rawValue: stallReasonRaw) ?? .none }
        set { stallReasonRaw = newValue.rawValue }
    }

    var lastStallDiagnosis: StallDiagnosis {
        get { StallDiagnosis(rawValue: lastStallDiagnosisRaw) ?? .noStall }
        set { lastStallDiagnosisRaw = newValue.rawValue }
    }

    var stallUrgency: StallUrgency {
        StallUrgency.from(consecutiveCount: consecutiveStallDiagnoses)
    }

    var ifiZone: IFIZone {
        IFIZone.classify(lastIFI)
    }

    init(exerciseKey: String) {
        self.exerciseKey = exerciseKey
        self.bestE1RM = 0
        self.lastSessionWeight = 0
        self.lastSessionReps = 0
        self.lastSessionRPE = 0
        self.lastSuggestedWeight = 0
        self.lastCompletedWeight = 0
        self.consecutiveSuccesses = 0
        self.consecutiveFailures = 0
        self.totalExposures = 0
        self.weeksAtSameLoad = 0
        self.isStalled = false
        self.stallReasonRaw = StallReason.none.rawValue
        self.lastIFI = 0
        self.ifiTrend = 0
        self.lastStallDiagnosisRaw = StallDiagnosis.noStall.rawValue
        self.consecutiveStallDiagnoses = 0
        self.updatedAt = Date()
    }
}

// ═══════════════════════════════════════════
// LANDMARK CALIBRATION (per-muscle adaptive tracking)
// ═══════════════════════════════════════════

enum CalibrationConfidence: String, Codable, CaseIterable {
    case seeded = "seeded"       // Using defaults, no user data
    case low = "low"             // 1-3 weeks of data
    case medium = "medium"       // 4-8 weeks of data
    case high = "high"           // 9+ weeks of data

    static func from(weeksOfData: Int) -> CalibrationConfidence {
        switch weeksOfData {
        case 0:     return .seeded
        case 1...3: return .low
        case 4...8: return .medium
        default:    return .high
        }
    }
}

@Model
class LandmarkCalibration {
    var muscleGroup: String

    // Adjusted landmarks (start at defaults, shift based on performance)
    var adjustedMEV: Int
    var adjustedMavLow: Int
    var adjustedMavHigh: Int
    var adjustedMRV: Int

    // Tracking fields
    var weeksTracked: Int
    var confidenceRaw: String
    var lastRecalibrationDate: Date?

    // Rolling performance data (last 3 weeks) stored as JSON
    // Each entry: { "week": ISO date, "sets": Int, "avgE1rmChange": Double, "avgIFI": Double }
    var recentPerformanceData: Data

    var programInstance: UserProgramInstance?

    var confidence: CalibrationConfidence {
        get { CalibrationConfidence(rawValue: confidenceRaw) ?? .seeded }
        set { confidenceRaw = newValue.rawValue }
    }

    var calibratedLandmark: VolumeLandmark {
        VolumeLandmark(mev: adjustedMEV, mavLow: adjustedMavLow, mavHigh: adjustedMavHigh, mrv: adjustedMRV)
    }

    init(muscleGroup: String) {
        self.muscleGroup = muscleGroup
        let defaults = VolumeLandmark.defaults[muscleGroup] ?? VolumeLandmark(mev: 4, mavLow: 8, mavHigh: 12, mrv: 18)
        self.adjustedMEV = defaults.mev
        self.adjustedMavLow = defaults.mavLow
        self.adjustedMavHigh = defaults.mavHigh
        self.adjustedMRV = defaults.mrv
        self.weeksTracked = 0
        self.confidenceRaw = CalibrationConfidence.seeded.rawValue
        self.lastRecalibrationDate = nil
        self.recentPerformanceData = Data()
    }

    /// Recalibrate landmarks based on accumulated performance data.
    /// Shifts are capped at ±2 sets per recalibration to prevent overcorrection.
    func recalibrate(avgE1rmChange: Double, avgIFI: Double, currentSets: Int) {
        weeksTracked += 1
        confidence = CalibrationConfidence.from(weeksOfData: weeksTracked)

        // Only recalibrate with at least 2 weeks of data
        guard weeksTracked >= 2 else { return }

        // Only recalibrate every 2 weeks to use rolling averages
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        if let lastDate = lastRecalibrationDate, lastDate > twoWeeksAgo { return }

        lastRecalibrationDate = Date()

        // ── MEV calibration ──
        // If performance improves at low volume → MEV might be lower than default
        // If performance stagnates at current volume → MEV might be higher
        if currentSets <= adjustedMEV + 2 && avgE1rmChange > 0.005 {
            // Progressing near MEV → can lower MEV slightly
            adjustedMEV = max(adjustedMEV - 1, 2)
        } else if currentSets >= adjustedMEV && currentSets <= adjustedMavLow && avgE1rmChange < -0.01 {
            // Declining in building zone → MEV might be higher
            adjustedMEV = min(adjustedMEV + 1, adjustedMavLow - 1)
        }

        // ── MRV calibration ──
        // High IFI + declining e1RM at high volume → MRV is too high
        // Low IFI + progressing at high volume → MRV could be higher
        if currentSets >= adjustedMavHigh {
            if avgIFI > 0.30 && avgE1rmChange < -0.005 {
                // Fatigued and declining → lower MRV
                adjustedMRV = max(adjustedMRV - 2, adjustedMavHigh + 2)
            } else if avgIFI < 0.15 && avgE1rmChange > 0.005 {
                // Fresh and progressing → raise MRV
                adjustedMRV = min(adjustedMRV + 2, 30) // cap at 30 hard sets
            }
        }

        // ── MAV calibration ──
        // Shift mavHigh toward the volume where best progress happened
        if currentSets >= adjustedMavLow && currentSets <= adjustedMRV {
            if avgE1rmChange > 0.01 && avgIFI < 0.20 {
                // Great progress in optimal zone → widen mavHigh slightly
                adjustedMavHigh = min(adjustedMavHigh + 1, adjustedMRV - 1)
            } else if avgE1rmChange < -0.005 && avgIFI > 0.25 {
                // Declining in upper range → narrow mavHigh
                adjustedMavHigh = max(adjustedMavHigh - 1, adjustedMavLow + 1)
            }
        }

        // Enforce ordering invariant
        adjustedMavLow = max(adjustedMavLow, adjustedMEV + 1)
        adjustedMavHigh = max(adjustedMavHigh, adjustedMavLow + 1)
        adjustedMRV = max(adjustedMRV, adjustedMavHigh + 1)
    }
}

// ═══════════════════════════════════════════
// USER PROGRAM (legacy — keep for compat)
// ═══════════════════════════════════════════

@Model
class UserProgram {
    var programId: Int
    var name: String
    var startDate: String
    var currentWeek: Int
    var isActive: Bool

    init(
        programId: Int,
        name: String,
        startDate: String,
        currentWeek: Int = 1,
        isActive: Bool = true
    ) {
        self.programId = programId
        self.name = name
        self.startDate = startDate
        self.currentWeek = currentWeek
        self.isActive = isActive
    }
}
