import Foundation

// ═══════════════════════════════════════════
// STRETCH POSITION
// ═══════════════════════════════════════════

enum StretchPosition: String, Codable, CaseIterable {
    case lengthened
    case mid
    case shortened

    var sortValue: Int {
        switch self {
        case .lengthened: return 2
        case .mid:        return 1
        case .shortened:  return 0
        }
    }
}

// ═══════════════════════════════════════════
// SECONDARY MUSCLE (with variable weight)
// ═══════════════════════════════════════════

struct SecondaryMuscle {
    let muscle: String
    let weight: Double  // 0.2–0.7
}

// ═══════════════════════════════════════════
// EXERCISE DEFINITION
// ═══════════════════════════════════════════

// ═══════════════════════════════════════════
// GENERATOR ENUMS (used by ProgramGenerator)
// ═══════════════════════════════════════════

enum SessionRestriction: String {
    case lowerOnly = "lower_only"   // squats, deadlifts, leg curls, calf raises
    case upperOnly = "upper_only"   // (reserved for future use)
}

struct ExerciseDefinition {
    let key: String
    let displayName: String
    let movementPattern: MovementPattern
    let swapPattern: String           // granular pattern for swap matching
    let primaryMuscles: [String]
    let secondaryMuscles: [SecondaryMuscle]
    let equipment: EquipmentType
    let isCompound: Bool
    let stretchPosition: StretchPosition
    let jointStressTags: [String]
    let swapKeys: [String]            // ordered best→worst
    let swapWarning: String?
    let variationOfKey: String?
    let isAnchorableAsTier1: Bool

    // ── Generator fields (used by ProgramGenerator.selectExercisesForMuscle) ──
    let rank: Int                     // 1=primary choice, 2=good alt, 3=fallback, 4=last resort
    let head: String                  // muscle head/region: "mid","upper","anterior","long","gastro", etc.
    let generatorPattern: String      // movement pattern for dedup: "horizontal_press","vertical_pull", etc.
    let sessionRestriction: SessionRestriction?  // nil=anywhere, .lowerOnly=lower/fullbody only
    let additionalFilterMuscles: [String]       // extra muscles to show this exercise under in filter UI

    /// Head-level volume contribution per set. When populated, this is the
    /// authoritative source for volume math (used by Advanced density to
    /// surface per-head bars, and aggregated up to canonical 9 for the
    /// other densities). When empty, volume math falls back to
    /// primaryMuscles (1.0) + secondaryMuscles (weight).
    ///
    /// Values are per-set contribution. Sum across heads of one parent
    /// muscle does NOT need to equal 1.0 — when reducing to canonical
    /// muscle credit we take MAX over heads (you do one set, that
    /// muscle works once at its peak head contribution).
    let headContributions: [MuscleHead: Double]

    init(
        key: String,
        displayName: String,
        movementPattern: MovementPattern,
        swapPattern: String,
        primaryMuscles: [String],
        secondaryMuscles: [SecondaryMuscle],
        equipment: EquipmentType,
        isCompound: Bool,
        stretchPosition: StretchPosition,
        jointStressTags: [String],
        swapKeys: [String],
        swapWarning: String?,
        variationOfKey: String?,
        isAnchorableAsTier1: Bool = false,
        rank: Int = 2,
        head: String = "",
        generatorPattern: String = "",
        sessionRestriction: SessionRestriction? = nil,
        additionalFilterMuscles: [String] = [],
        headContributions: [MuscleHead: Double] = [:]
    ) {
        self.key = key
        self.displayName = displayName
        self.movementPattern = movementPattern
        self.swapPattern = swapPattern
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.equipment = equipment
        self.isCompound = isCompound
        self.stretchPosition = stretchPosition
        self.jointStressTags = jointStressTags
        self.swapKeys = swapKeys
        self.swapWarning = swapWarning
        self.variationOfKey = variationOfKey
        self.isAnchorableAsTier1 = isAnchorableAsTier1
        self.additionalFilterMuscles = additionalFilterMuscles
        self.rank = rank
        self.head = head
        self.generatorPattern = generatorPattern
        self.sessionRestriction = sessionRestriction
        self.headContributions = headContributions
    }
}

// ═══════════════════════════════════════════
// VOLUME CREDIT HELPERS
// Single entry point for "how much does this exercise contribute to
// each tracking muscle per set?" Used by HomeView.setsByMuscle,
// MuscleCoverageCard.effectiveSetsByMuscle, IndirectVolumeMap, etc.
// ═══════════════════════════════════════════

extension ExerciseDefinition {

    /// Per-set credit per canonical tracking muscle.
    ///
    /// When headContributions is populated: takes MAX weight over heads
    /// belonging to each parent muscle (one set = one stimulus at peak
    /// head contribution).
    ///
    /// When headContributions is empty: falls back to primaryMuscles
    /// (1.0 each, normalized) + secondaryMuscles (their weight, normalized).
    ///
    /// Used everywhere that asks "how many sets does this give to Chest/Back/etc"
    /// so the math is consistent across HomeView, ProgramTab, VolumeAdjuster.
    func musclesCredit() -> [String: Double] {
        var result: [String: Double] = [:]

        // Head-level path (preferred when populated)
        if !headContributions.isEmpty {
            for (head, weight) in headContributions {
                let parent = head.parentMuscle
                result[parent] = max(result[parent] ?? 0, weight)
            }
            return result
        }

        // Legacy fallback: primary (1.0) + secondary (weight)
        for pm in primaryMuscles {
            if let n = ExerciseDictionary.normalizeMuscle(pm) {
                result[n] = max(result[n] ?? 0, 1.0)
            }
        }
        for sm in secondaryMuscles {
            if let n = ExerciseDictionary.normalizeMuscle(sm.muscle) {
                result[n] = max(result[n] ?? 0, sm.weight)
            }
        }
        return result
    }

    /// Per-set credit per individual head. Empty when no headContributions
    /// is set. Used by the Advanced-density expanded muscle bars.
    func headCredits() -> [MuscleHead: Double] {
        return headContributions
    }

    /// Unique tracking muscles where this exercise is a direct (primary) target.
    /// Multiple raw primary entries that collapse to the same tracking muscle
    /// (e.g. ["Lats", "Mid Back"] → "Back") count ONCE. Without this, a single
    /// set of dumbbell row would count as 2 sets of Back.
    var directTrackingMuscles: Set<String> {
        Set(primaryMuscles.compactMap { ExerciseDictionary.normalizeMuscle($0) })
    }

    /// Weighted secondary contributions per tracking muscle, deduped.
    /// If multiple secondaries normalize to the same tracking muscle, takes
    /// MAX (one set fires the muscle once, not multiple times). Excludes
    /// muscles already counted as direct.
    var indirectTrackingMuscles: [String: Double] {
        let direct = directTrackingMuscles
        var result: [String: Double] = [:]
        for sm in secondaryMuscles {
            guard let n = ExerciseDictionary.normalizeMuscle(sm.muscle),
                  !direct.contains(n) else { continue }
            result[n] = max(result[n] ?? 0, sm.weight)
        }
        return result
    }
}

/// Same helpers for SwiftData `Exercise` records (custom exercises).
extension Exercise {
    /// Unique tracking muscles where this exercise is a direct (primary) target.
    var directTrackingMuscles: Set<String> {
        Set(musclesPrimary.compactMap { ExerciseDictionary.normalizeMuscle($0) })
    }

    /// Weighted secondary contributions per tracking muscle, deduped (max).
    /// Excludes muscles already in primaries. Uses the flat
    /// `IndirectVolumeMap.secondaryWeight` since custom exercises don't carry
    /// per-secondary weights.
    var indirectTrackingMuscles: [String: Double] {
        let direct = directTrackingMuscles
        var result: [String: Double] = [:]
        for raw in musclesSecondary {
            guard let n = ExerciseDictionary.normalizeMuscle(raw),
                  !direct.contains(n) else { continue }
            result[n] = max(result[n] ?? 0, IndirectVolumeMap.secondaryWeight)
        }
        return result
    }
}

// ═══════════════════════════════════════════
// EXERCISE DICTIONARY — single source of truth
// ═══════════════════════════════════════════

struct ExerciseDictionary {

    // ── Canonical muscle groups for volume tracking ──
    static let trackingMuscles = [
        "Chest", "Back", "Quads", "Hamstrings", "Glutes",
        "Calves", "Biceps", "Triceps", "Delts"
    ]

    // ── Filters for exercise library UI ──
    static let exerciseFilters = [
        "All", "Chest", "Back", "Quads", "Hamstrings", "Glutes",
        "Calves", "Biceps", "Triceps", "Delts", "Core"
    ]

    // ── Normalize detailed muscle names to tracking groups ──
    static func normalizeMuscle(_ raw: String) -> String? {
        let l = raw.lowercased()
        if l.contains("chest") || l.contains("pec") { return "Chest" }
        if l.contains("lat") || l.contains("mid back") || l.contains("lower back")
            || l.contains("trap") || l == "back" { return "Back" }
        if l.contains("quad") || l.contains("rectus femoris") { return "Quads" }
        if l.contains("hamstring") { return "Hamstrings" }
        // Hip abduction (glute medius/minimus) → Glutes; hip adduction
        // (adductor magnus is a hip extensor) → Hamstrings. Checked before the
        // broad "ab" → Core rule below, since "abduct"/"adduct" contain "ab".
        if l.contains("abduct") { return "Glutes" }
        if l.contains("adduct") { return "Hamstrings" }
        if l.contains("glute") { return "Glutes" }
        if l.contains("calf") || l.contains("calves") || l.contains("gastrocnemius")
            || l.contains("soleus") { return "Calves" }
        if l.contains("bicep") || l.contains("brachialis") || l.contains("brachioradialis") { return "Biceps" }
        if l.contains("tricep") { return "Triceps" }
        if l.contains("delt") || l.contains("shoulder") { return "Delts" }
        if l.contains("ab") || l.contains("oblique") || l.contains("core")
            || l.contains("transverse") || l.contains("hip flexor") { return "Core" }
        if l.contains("rotator") || l.contains("external rotator") { return "Delts" }
        return nil
    }

    // ── All exercises ──

    static let all: [String: ExerciseDefinition] = {
        var dict = [String: ExerciseDefinition]()
        for def in allDefinitions {
            dict[def.key] = def
        }
        return dict
    }()

    // MARK: - Full exercise list

    private static let allDefinitions: [ExerciseDefinition] = [

        // ═══════════════════════════════════════
        // CHEST
        // ═══════════════════════════════════════

        ExerciseDefinition(
            key: "bench_press_barbell", displayName: "Barbell Bench Press",
            movementPattern: .horizontalPush, swapPattern: "horizontal_push",
            primaryMuscles: ["Chest"],
            secondaryMuscles: [.init(muscle: "Triceps", weight: 0.6), .init(muscle: "Front Delts", weight: 0.5)],
            equipment: .barbell, isCompound: true, stretchPosition: .mid,
            jointStressTags: ["shoulder"],
            swapKeys: ["bench_press_dumbbell", "bench_press_smith", "machine_chest_press"],
            swapWarning: nil, variationOfKey: nil, isAnchorableAsTier1: true,
            rank: 1, head: "mid", generatorPattern: "horizontal_press",
            headContributions: [
                .chestMid: 1.0, .chestLower: 0.4,
                .tricepsLateral: 0.6, .tricepsMedial: 0.5, .tricepsLong: 0.4,
                .deltsFront: 0.5
            ]),

        ExerciseDefinition(
            key: "bench_press_incline_barbell", displayName: "Incline Barbell Bench Press",
            movementPattern: .horizontalPush, swapPattern: "horizontal_push_incline",
            primaryMuscles: ["Upper Chest"],
            secondaryMuscles: [.init(muscle: "Triceps", weight: 0.5), .init(muscle: "Front Delts", weight: 0.7)],
            equipment: .barbell, isCompound: true, stretchPosition: .mid,
            jointStressTags: ["shoulder"],
            swapKeys: ["bench_press_incline_dumbbell", "bench_press_incline_smith", "incline_machine_press", "cable_fly_low_to_high"],
            swapWarning: nil, variationOfKey: "bench_press_barbell",
            rank: 1, head: "upper", generatorPattern: "incline_press",
            headContributions: [
                .chestUpper: 1.0, .chestMid: 0.5,
                .deltsFront: 0.7,
                .tricepsLateral: 0.5, .tricepsMedial: 0.5, .tricepsLong: 0.4
            ]),

        ExerciseDefinition(
            key: "bench_press_decline_barbell", displayName: "Decline Barbell Bench Press",
            movementPattern: .horizontalPush, swapPattern: "horizontal_push_decline",
            primaryMuscles: ["Lower Chest"],
            secondaryMuscles: [.init(muscle: "Triceps", weight: 0.6), .init(muscle: "Front Delts", weight: 0.3)],
            equipment: .barbell, isCompound: true, stretchPosition: .shortened,
            jointStressTags: ["shoulder"],
            swapKeys: ["bench_press_decline_dumbbell", "bench_press_decline_smith", "cable_fly_high_to_low"],
            swapWarning: nil, variationOfKey: "bench_press_barbell",
            head: "lower", generatorPattern: "decline_press",
            headContributions: [
                .chestLower: 1.0, .chestMid: 0.4,
                .tricepsLateral: 0.6, .tricepsMedial: 0.5, .tricepsLong: 0.5,
                .deltsFront: 0.3
            ]),

        ExerciseDefinition(
            key: "bench_press_dumbbell", displayName: "Dumbbell Bench Press",
            movementPattern: .horizontalPush, swapPattern: "horizontal_push",
            primaryMuscles: ["Chest"],
            secondaryMuscles: [.init(muscle: "Triceps", weight: 0.5), .init(muscle: "Front Delts", weight: 0.5)],
            equipment: .dumbbell, isCompound: true, stretchPosition: .mid,
            jointStressTags: ["shoulder"],
            swapKeys: ["bench_press_barbell", "bench_press_smith", "machine_chest_press"],
            swapWarning: nil, variationOfKey: "bench_press_barbell",
            head: "mid", generatorPattern: "horizontal_press",
            headContributions: [
                .chestMid: 1.0, .chestLower: 0.4,
                .tricepsLateral: 0.5, .tricepsMedial: 0.4, .tricepsLong: 0.4,
                .deltsFront: 0.5
            ]),

        ExerciseDefinition(
            key: "bench_press_incline_dumbbell", displayName: "Incline Dumbbell Press",
            movementPattern: .horizontalPush, swapPattern: "horizontal_push_incline",
            primaryMuscles: ["Upper Chest"],
            secondaryMuscles: [.init(muscle: "Triceps", weight: 0.4), .init(muscle: "Front Delts", weight: 0.7)],
            equipment: .dumbbell, isCompound: true, stretchPosition: .mid,
            jointStressTags: ["shoulder"],
            swapKeys: ["bench_press_incline_barbell", "bench_press_incline_smith", "cable_fly_low_to_high"],
            swapWarning: nil, variationOfKey: "bench_press_barbell",
            rank: 1, head: "upper", generatorPattern: "incline_press",
            headContributions: [
                .chestUpper: 1.0, .chestMid: 0.5,
                .deltsFront: 0.7,
                .tricepsLateral: 0.4, .tricepsMedial: 0.4, .tricepsLong: 0.4
            ]),

        ExerciseDefinition(
            key: "bench_press_decline_dumbbell", displayName: "Decline Dumbbell Press",
            movementPattern: .horizontalPush, swapPattern: "horizontal_push_decline",
            primaryMuscles: ["Lower Chest"],
            secondaryMuscles: [.init(muscle: "Triceps", weight: 0.5), .init(muscle: "Front Delts", weight: 0.3)],
            equipment: .dumbbell, isCompound: true, stretchPosition: .shortened,
            jointStressTags: ["shoulder"],
            swapKeys: ["bench_press_decline_barbell", "bench_press_decline_smith", "cable_fly_high_to_low"],
            swapWarning: nil, variationOfKey: "bench_press_barbell",
            rank: 3, head: "lower", generatorPattern: "decline_press",
            headContributions: [
                .chestLower: 1.0, .chestMid: 0.4,
                .tricepsLateral: 0.5, .tricepsMedial: 0.4, .tricepsLong: 0.4,
                .deltsFront: 0.3
            ]),

        ExerciseDefinition(
            key: "fly_dumbbell", displayName: "Dumbbell Fly",
            movementPattern: .horizontalPush, swapPattern: "horizontal_push",
            primaryMuscles: ["Chest"],
            secondaryMuscles: [.init(muscle: "Front Delts", weight: 0.3)],
            equipment: .dumbbell, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: ["shoulder"],
            swapKeys: ["cable_fly_neutral", "pec_deck", "fly_incline_dumbbell"],
            swapWarning: nil, variationOfKey: nil,
            rank: 3, head: "mid", generatorPattern: "fly",
            headContributions: [
                .chestMid: 1.0, .chestLower: 0.4,
                .deltsFront: 0.3
            ]),

        ExerciseDefinition(
            key: "fly_incline_dumbbell", displayName: "Incline Dumbbell Fly",
            movementPattern: .horizontalPush, swapPattern: "horizontal_push_incline",
            primaryMuscles: ["Upper Chest"],
            secondaryMuscles: [.init(muscle: "Front Delts", weight: 0.3)],
            equipment: .dumbbell, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: ["shoulder"],
            swapKeys: ["cable_fly_low_to_high", "pec_deck"],
            swapWarning: nil, variationOfKey: "fly_dumbbell",
            rank: 3, head: "upper", generatorPattern: "fly",
            headContributions: [
                .chestUpper: 1.0, .chestMid: 0.4,
                .deltsFront: 0.4
            ]),

        ExerciseDefinition(
            key: "cable_fly_low_to_high", displayName: "Cable Fly (Low to High)",
            movementPattern: .horizontalPush, swapPattern: "horizontal_push_incline",
            primaryMuscles: ["Upper Chest"],
            secondaryMuscles: [.init(muscle: "Front Delts", weight: 0.3)],
            equipment: .cable, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["fly_incline_dumbbell", "pec_deck"],
            swapWarning: nil, variationOfKey: nil,
            head: "upper", generatorPattern: "fly",
            headContributions: [
                .chestUpper: 1.0, .chestMid: 0.4,
                .deltsFront: 0.4
            ]),

        ExerciseDefinition(
            key: "cable_fly_high_to_low", displayName: "Cable Fly (High to Low)",
            movementPattern: .horizontalPush, swapPattern: "horizontal_push_decline",
            primaryMuscles: ["Lower Chest"],
            secondaryMuscles: [.init(muscle: "Front Delts", weight: 0.3)],
            equipment: .cable, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["pec_deck"],
            swapWarning: nil, variationOfKey: nil,
            head: "lower", generatorPattern: "fly",
            headContributions: [
                .chestLower: 1.0, .chestMid: 0.4,
                .deltsFront: 0.3
            ]),

        ExerciseDefinition(
            key: "cable_fly_neutral", displayName: "Cable Fly (Neutral)",
            movementPattern: .horizontalPush, swapPattern: "horizontal_push",
            primaryMuscles: ["Chest"],
            secondaryMuscles: [.init(muscle: "Front Delts", weight: 0.3)],
            equipment: .cable, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["fly_dumbbell", "pec_deck"],
            swapWarning: nil, variationOfKey: nil,
            head: "mid", generatorPattern: "fly",
            headContributions: [
                .chestMid: 1.0, .chestLower: 0.4,
                .deltsFront: 0.3
            ]),

        ExerciseDefinition(
            key: "pec_deck", displayName: "Pec Deck / Machine Fly",
            movementPattern: .horizontalPush, swapPattern: "horizontal_push",
            primaryMuscles: ["Chest"],
            secondaryMuscles: [.init(muscle: "Front Delts", weight: 0.2)],
            equipment: .machine, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["cable_fly_neutral", "fly_dumbbell"],
            swapWarning: nil, variationOfKey: nil,
            rank: 3, head: "mid", generatorPattern: "fly",
            headContributions: [
                .chestMid: 1.0, .chestLower: 0.3,
                .deltsFront: 0.3
            ]),

        ExerciseDefinition(
            key: "pushup", displayName: "Push-Up",
            movementPattern: .horizontalPush, swapPattern: "horizontal_push",
            primaryMuscles: ["Chest"],
            secondaryMuscles: [.init(muscle: "Triceps", weight: 0.5), .init(muscle: "Front Delts", weight: 0.4)],
            equipment: .bodyweight, isCompound: true, stretchPosition: .mid,
            jointStressTags: [],
            swapKeys: ["bench_press_dumbbell", "bench_press_barbell"],
            swapWarning: nil, variationOfKey: nil,
            head: "mid", generatorPattern: "horizontal_press",
            headContributions: [
                .chestMid: 0.7, .chestLower: 0.4,
                .tricepsLateral: 0.5, .tricepsMedial: 0.5, .tricepsLong: 0.3,
                .deltsFront: 0.4
            ]),

        ExerciseDefinition(
            key: "dips_chest", displayName: "Dips (Chest-Focused)",
            movementPattern: .horizontalPush, swapPattern: "horizontal_push_decline",
            primaryMuscles: ["Lower Chest"],
            secondaryMuscles: [.init(muscle: "Triceps", weight: 0.5), .init(muscle: "Front Delts", weight: 0.3)],
            equipment: .bodyweight, isCompound: true, stretchPosition: .mid,
            jointStressTags: ["shoulder"],
            swapKeys: ["bench_press_decline_dumbbell", "bench_press_decline_barbell"],
            swapWarning: nil, variationOfKey: nil,
            head: "lower", generatorPattern: "decline_press",
            headContributions: [
                .chestLower: 0.9, .chestMid: 0.5,
                .tricepsLateral: 0.6, .tricepsMedial: 0.5, .tricepsLong: 0.4,
                .deltsFront: 0.5
            ]),

        ExerciseDefinition(
            key: "landmine_press", displayName: "Landmine Press",
            movementPattern: .horizontalPush, swapPattern: "horizontal_push_incline",
            primaryMuscles: ["Upper Chest"],
            secondaryMuscles: [.init(muscle: "Front Delts", weight: 0.5), .init(muscle: "Triceps", weight: 0.3)],
            equipment: .barbell, isCompound: true, stretchPosition: .mid,
            jointStressTags: [],
            swapKeys: ["bench_press_incline_dumbbell", "bench_press_incline_barbell"],
            swapWarning: nil, variationOfKey: nil,
            head: "upper", generatorPattern: "incline_press",
            headContributions: [
                .chestUpper: 1.0, .chestMid: 0.4,
                .deltsFront: 0.6,
                .tricepsLateral: 0.3, .tricepsMedial: 0.3, .tricepsLong: 0.3
            ]),

        ExerciseDefinition(
            key: "bench_press_smith", displayName: "Smith Machine Bench Press",
            movementPattern: .horizontalPush, swapPattern: "horizontal_push",
            primaryMuscles: ["Chest"],
            secondaryMuscles: [.init(muscle: "Triceps", weight: 0.5), .init(muscle: "Front Delts", weight: 0.5)],
            equipment: .machine, isCompound: true, stretchPosition: .mid,
            jointStressTags: ["shoulder"],
            swapKeys: ["bench_press_barbell", "bench_press_dumbbell", "machine_chest_press"],
            swapWarning: nil, variationOfKey: "bench_press_barbell",
            head: "mid", generatorPattern: "horizontal_press",
            headContributions: [
                .chestMid: 1.0, .chestLower: 0.4,
                .tricepsLateral: 0.5, .tricepsMedial: 0.4, .tricepsLong: 0.4,
                .deltsFront: 0.5
            ]),

        // ═══════════════════════════════════════
        // BACK
        // ═══════════════════════════════════════

        ExerciseDefinition(
            key: "row_barbell", displayName: "Barbell Row (Overhand)",
            movementPattern: .horizontalPull, swapPattern: "horizontal_pull",
            primaryMuscles: ["Lats", "Mid Back"],
            secondaryMuscles: [.init(muscle: "Biceps", weight: 0.5), .init(muscle: "Rear Delts", weight: 0.6), .init(muscle: "Traps", weight: 0.4), .init(muscle: "Lower Back", weight: 0.4)],
            equipment: .barbell, isCompound: true, stretchPosition: .lengthened,
            jointStressTags: ["low_back"],
            swapKeys: ["row_dumbbell", "row_tbar", "row_cable_wide", "row_chest_supported"],
            swapWarning: nil, variationOfKey: nil, isAnchorableAsTier1: true,
            rank: 1, head: "thickness", generatorPattern: "horizontal_row",
            headContributions: [
                .midBack: 1.0, .lats: 0.8, .traps: 0.4, .rearDelts: 0.6, .lowerBack: 0.4,
                .bicepsLong: 0.5, .bicepsShort: 0.3, .brachialis: 0.5
            ]),

        ExerciseDefinition(
            key: "row_barbell_underhand", displayName: "Barbell Row (Underhand)",
            movementPattern: .horizontalPull, swapPattern: "horizontal_pull",
            primaryMuscles: ["Lats", "Mid Back"],
            secondaryMuscles: [.init(muscle: "Biceps", weight: 0.7), .init(muscle: "Rear Delts", weight: 0.3)],
            equipment: .barbell, isCompound: true, stretchPosition: .lengthened,
            jointStressTags: ["low_back"],
            swapKeys: ["row_cable_narrow", "row_dumbbell", "row_machine"],
            swapWarning: nil, variationOfKey: "row_barbell",
            head: "thickness", generatorPattern: "horizontal_row",
            headContributions: [
                .lats: 1.0, .midBack: 0.8, .rearDelts: 0.3, .lowerBack: 0.4,
                .bicepsShort: 0.7, .bicepsLong: 0.5, .brachialis: 0.4
            ]),

        ExerciseDefinition(
            key: "row_dumbbell", displayName: "Dumbbell Row",
            movementPattern: .horizontalPull, swapPattern: "horizontal_pull",
            primaryMuscles: ["Lats", "Mid Back"],
            secondaryMuscles: [.init(muscle: "Biceps", weight: 0.5), .init(muscle: "Rear Delts", weight: 0.3)],
            equipment: .dumbbell, isCompound: true, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["row_barbell", "row_cable_narrow", "row_meadows", "row_chest_supported"],
            swapWarning: nil, variationOfKey: nil,
            head: "thickness", generatorPattern: "horizontal_row",
            headContributions: [
                .lats: 1.0, .midBack: 0.8, .rearDelts: 0.4,
                .bicepsLong: 0.5, .bicepsShort: 0.4, .brachialis: 0.5
            ]),

        ExerciseDefinition(
            key: "row_cable_narrow", displayName: "Cable Row (Narrow Grip)",
            movementPattern: .horizontalPull, swapPattern: "horizontal_pull",
            primaryMuscles: ["Lats", "Mid Back"],
            secondaryMuscles: [.init(muscle: "Biceps", weight: 0.5), .init(muscle: "Rear Delts", weight: 0.3)],
            equipment: .cable, isCompound: true, stretchPosition: .mid,
            jointStressTags: [],
            swapKeys: ["row_machine", "row_barbell_underhand", "row_dumbbell"],
            swapWarning: nil, variationOfKey: nil, isAnchorableAsTier1: true,
            rank: 1, head: "thickness", generatorPattern: "horizontal_row",
            headContributions: [
                .midBack: 1.0, .lats: 0.7, .rearDelts: 0.4,
                .bicepsShort: 0.5, .bicepsLong: 0.4, .brachialis: 0.4
            ]),

        ExerciseDefinition(
            key: "row_cable_wide", displayName: "Cable Row (Wide Grip)",
            movementPattern: .horizontalPull, swapPattern: "horizontal_pull",
            primaryMuscles: ["Mid Back", "Rear Delts"],
            secondaryMuscles: [.init(muscle: "Biceps", weight: 0.3), .init(muscle: "Lats", weight: 0.5)],
            equipment: .cable, isCompound: true, stretchPosition: .mid,
            jointStressTags: [],
            swapKeys: ["row_chest_supported", "row_tbar", "row_barbell"],
            swapWarning: nil, variationOfKey: nil, isAnchorableAsTier1: true,
            rank: 1, head: "thickness", generatorPattern: "horizontal_row",
            headContributions: [
                .midBack: 1.0, .rearDelts: 0.8, .lats: 0.5,
                .bicepsShort: 0.3, .bicepsLong: 0.3, .brachialis: 0.3
            ]),

        ExerciseDefinition(
            key: "pulldown_wide", displayName: "Lat Pulldown (Wide Overhand)",
            movementPattern: .verticalPull, swapPattern: "vertical_pull",
            primaryMuscles: ["Lats"],
            secondaryMuscles: [.init(muscle: "Mid Back", weight: 0.4), .init(muscle: "Biceps", weight: 0.5), .init(muscle: "Rear Delts", weight: 0.4)],
            equipment: .cable, isCompound: true, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["pullup", "pulldown_close", "pullover_cable"],
            swapWarning: nil, variationOfKey: nil, isAnchorableAsTier1: true,
            rank: 1, head: "width", generatorPattern: "vertical_pull",
            headContributions: [
                .lats: 1.0, .midBack: 0.4, .rearDelts: 0.4,
                .bicepsShort: 0.5, .bicepsLong: 0.3, .brachialis: 0.4
            ]),

        ExerciseDefinition(
            key: "pulldown_close", displayName: "Lat Pulldown (Close Neutral)",
            movementPattern: .verticalPull, swapPattern: "vertical_pull",
            primaryMuscles: ["Lats"],
            secondaryMuscles: [.init(muscle: "Biceps", weight: 0.6), .init(muscle: "Mid Back", weight: 0.3)],
            equipment: .cable, isCompound: true, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["chinup", "pullup_neutral", "pulldown_wide"],
            swapWarning: nil, variationOfKey: "pulldown_wide", isAnchorableAsTier1: true,
            rank: 1, head: "width", generatorPattern: "vertical_pull",
            headContributions: [
                .lats: 1.0, .midBack: 0.5,
                .bicepsShort: 0.6, .bicepsLong: 0.4, .brachialis: 0.5
            ]),

        ExerciseDefinition(
            key: "pullup", displayName: "Pull-Up (Overhand)",
            movementPattern: .verticalPull, swapPattern: "vertical_pull",
            primaryMuscles: ["Lats"],
            secondaryMuscles: [.init(muscle: "Mid Back", weight: 0.6), .init(muscle: "Biceps", weight: 0.5), .init(muscle: "Rear Delts", weight: 0.4)],
            equipment: .bodyweight, isCompound: true, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["pulldown_wide", "pullup_neutral"],
            swapWarning: nil, variationOfKey: nil,
            rank: 1, head: "width", generatorPattern: "vertical_pull",
            headContributions: [
                .lats: 1.0, .midBack: 0.6, .rearDelts: 0.4,
                .bicepsShort: 0.5, .bicepsLong: 0.4, .brachialis: 0.5
            ]),

        ExerciseDefinition(
            key: "chinup", displayName: "Chin-Up (Underhand)",
            movementPattern: .verticalPull, swapPattern: "vertical_pull",
            primaryMuscles: ["Lats", "Biceps"],
            secondaryMuscles: [.init(muscle: "Mid Back", weight: 0.5)],
            equipment: .bodyweight, isCompound: true, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["pulldown_close", "pullup_neutral"],
            swapWarning: nil, variationOfKey: "pullup",
            rank: 1, head: "width", generatorPattern: "vertical_pull",
            headContributions: [
                .lats: 1.0, .midBack: 0.5,
                .bicepsShort: 0.9, .bicepsLong: 0.7, .brachialis: 0.4
            ]),

        ExerciseDefinition(
            key: "pullup_neutral", displayName: "Neutral Grip Pull-Up",
            movementPattern: .verticalPull, swapPattern: "vertical_pull",
            primaryMuscles: ["Lats"],
            secondaryMuscles: [.init(muscle: "Biceps", weight: 0.6)],
            equipment: .bodyweight, isCompound: true, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["chinup", "pulldown_close"],
            swapWarning: nil, variationOfKey: "pullup",
            rank: 1, head: "width", generatorPattern: "vertical_pull",
            headContributions: [
                .lats: 1.0, .midBack: 0.5,
                .bicepsShort: 0.6, .bicepsLong: 0.5, .brachialis: 0.5
            ]),

        ExerciseDefinition(
            key: "row_meadows", displayName: "Meadows Row",
            movementPattern: .horizontalPull, swapPattern: "horizontal_pull",
            primaryMuscles: ["Lats", "Mid Back"],
            secondaryMuscles: [.init(muscle: "Biceps", weight: 0.4), .init(muscle: "Rear Delts", weight: 0.3)],
            equipment: .barbell, isCompound: true, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["row_dumbbell", "row_cable_narrow"],
            swapWarning: nil, variationOfKey: "row_barbell",
            head: "thickness", generatorPattern: "horizontal_row",
            headContributions: [
                .lats: 1.0, .midBack: 0.7, .rearDelts: 0.4,
                .bicepsLong: 0.5, .bicepsShort: 0.3, .brachialis: 0.4
            ]),

        ExerciseDefinition(
            key: "row_tbar", displayName: "T-Bar Row",
            movementPattern: .horizontalPull, swapPattern: "horizontal_pull",
            primaryMuscles: ["Lats", "Mid Back"],
            secondaryMuscles: [.init(muscle: "Biceps", weight: 0.5), .init(muscle: "Rear Delts", weight: 0.4)],
            equipment: .barbell, isCompound: true, stretchPosition: .lengthened,
            jointStressTags: ["low_back"],
            swapKeys: ["row_barbell", "row_chest_supported", "row_dumbbell"],
            swapWarning: nil, variationOfKey: "row_barbell",
            rank: 1, head: "thickness", generatorPattern: "horizontal_row",
            headContributions: [
                .midBack: 1.0, .lats: 0.8, .traps: 0.4, .rearDelts: 0.5, .lowerBack: 0.4,
                .bicepsLong: 0.5, .bicepsShort: 0.3, .brachialis: 0.5
            ]),

        ExerciseDefinition(
            key: "row_machine", displayName: "Machine Row",
            movementPattern: .horizontalPull, swapPattern: "horizontal_pull",
            primaryMuscles: ["Lats", "Mid Back"],
            secondaryMuscles: [.init(muscle: "Biceps", weight: 0.4)],
            equipment: .machine, isCompound: true, stretchPosition: .mid,
            jointStressTags: [],
            swapKeys: ["row_cable_narrow", "row_dumbbell", "row_chest_supported"],
            swapWarning: nil, variationOfKey: nil,
            head: "thickness", generatorPattern: "horizontal_row",
            headContributions: [
                .midBack: 1.0, .lats: 0.7, .rearDelts: 0.3,
                .bicepsLong: 0.4, .bicepsShort: 0.3, .brachialis: 0.4
            ]),

        ExerciseDefinition(
            key: "row_chest_supported", displayName: "Chest-Supported Row",
            movementPattern: .horizontalPull, swapPattern: "horizontal_pull",
            primaryMuscles: ["Mid Back", "Lats"],
            secondaryMuscles: [.init(muscle: "Biceps", weight: 0.4), .init(muscle: "Rear Delts", weight: 0.4)],
            equipment: .machine, isCompound: true, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["row_cable_wide", "row_tbar", "row_dumbbell"],
            swapWarning: nil, variationOfKey: nil,
            head: "thickness", generatorPattern: "horizontal_row",
            headContributions: [
                .midBack: 1.0, .lats: 0.8, .rearDelts: 0.5,
                .bicepsLong: 0.4, .bicepsShort: 0.3, .brachialis: 0.4
            ]),

        ExerciseDefinition(
            key: "pulldown_straight_arm", displayName: "Straight-Arm Pulldown",
            movementPattern: .verticalPull, swapPattern: "vertical_pull",
            primaryMuscles: ["Lats"],
            secondaryMuscles: [.init(muscle: "Triceps", weight: 0.2)],
            equipment: .cable, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["pullover_cable"],
            swapWarning: nil, variationOfKey: nil,
            rank: 3, head: "width", generatorPattern: "vertical_pull",
            headContributions: [
                .lats: 1.0, .chestUpper: 0.3,
                .tricepsLong: 0.3
            ]),

        ExerciseDefinition(
            key: "rack_pull", displayName: "Rack Pull",
            movementPattern: .hinge, swapPattern: "hip_hinge",
            primaryMuscles: ["Traps", "Mid Back", "Lats"],
            secondaryMuscles: [.init(muscle: "Glutes", weight: 0.3), .init(muscle: "Hamstrings", weight: 0.3)],
            equipment: .barbell, isCompound: true, stretchPosition: .mid,
            jointStressTags: ["low_back"],
            swapKeys: ["deadlift_barbell", "deadlift_trap_bar"],
            swapWarning: nil, variationOfKey: "deadlift_barbell",
            head: "thickness", generatorPattern: "hinge", sessionRestriction: .lowerOnly,
            headContributions: [
                .traps: 1.0, .midBack: 0.8, .lats: 0.6, .lowerBack: 0.7,
                .glutesMax: 0.4,
                .hamstringsHipExtension: 0.4
            ]),

        ExerciseDefinition(
            key: "deadlift_barbell", displayName: "Barbell Deadlift",
            movementPattern: .hinge, swapPattern: "hip_hinge",
            // Promote Glutes + Hamstrings to PRIMARY. Conventional deadlift
            // is a posterior-chain compound — these aren't secondary movers,
            // they're the prime force generators along with the back's
            // isometric/contraction work.
            primaryMuscles: ["Lats", "Mid Back", "Traps", "Glutes", "Hamstrings"],
            secondaryMuscles: [.init(muscle: "Quads", weight: 0.4), .init(muscle: "Lower Back", weight: 1.0)],
            equipment: .barbell, isCompound: true, stretchPosition: .lengthened,
            jointStressTags: ["low_back"],
            swapKeys: ["deadlift_trap_bar", "rack_pull"],
            swapWarning: nil, variationOfKey: nil, isAnchorableAsTier1: true,
            rank: 1, head: "thickness", generatorPattern: "hinge", sessionRestriction: .lowerOnly,
            headContributions: [
                .lats: 0.6, .midBack: 0.8, .traps: 0.6, .lowerBack: 1.0,
                .glutesMax: 1.0,
                .hamstringsHipExtension: 1.0,
                .rectusFemoris: 0.3
            ]),

        ExerciseDefinition(
            key: "deadlift_trap_bar", displayName: "Trap Bar Deadlift",
            movementPattern: .hinge, swapPattern: "hip_hinge",
            // Trap bar shifts a bit more onto quads vs conventional, but
            // glutes + hams are still primary movers.
            primaryMuscles: ["Mid Back", "Quads", "Glutes", "Hamstrings"],
            secondaryMuscles: [.init(muscle: "Lats", weight: 0.5), .init(muscle: "Lower Back", weight: 0.8)],
            equipment: .barbell, isCompound: true, stretchPosition: .lengthened,
            jointStressTags: ["low_back"],
            swapKeys: ["deadlift_barbell", "rack_pull"],
            swapWarning: nil, variationOfKey: "deadlift_barbell",
            rank: 1, head: "thickness", generatorPattern: "hinge", sessionRestriction: .lowerOnly,
            headContributions: [
                .midBack: 0.7, .traps: 0.5, .lowerBack: 0.8,
                .glutesMax: 0.9,
                .hamstringsHipExtension: 0.7,
                .vastusLateralis: 0.7, .vastusMedialis: 0.7, .rectusFemoris: 0.5
            ]),

        ExerciseDefinition(
            key: "good_morning", displayName: "Good Morning",
            movementPattern: .hinge, swapPattern: "hip_hinge",
            // Good Morning is a posterior-chain hinge (hamstrings + erectors),
            // not a lat exercise — was mislabeled "Mid Back, Lats". Head credit
            // already routes correctly (hamstrings 0.9); this fixes the metadata
            // so it filters/selects as a hamstring movement.
            primaryMuscles: ["Hamstrings", "Lower Back"],
            secondaryMuscles: [.init(muscle: "Hamstrings", weight: 0.7), .init(muscle: "Glutes", weight: 0.5)],
            equipment: .barbell, isCompound: true, stretchPosition: .lengthened,
            jointStressTags: ["low_back"],
            swapKeys: ["rdl_barbell", "hyperextension"],
            swapWarning: nil, variationOfKey: nil,
            rank: 3, head: "thickness", generatorPattern: "hinge", sessionRestriction: .lowerOnly,
            headContributions: [
                .lowerBack: 0.6, .midBack: 0.4,
                .hamstringsHipExtension: 0.9,
                .glutesMax: 0.7
            ]),

        ExerciseDefinition(
            key: "hyperextension", displayName: "Hyperextension",
            movementPattern: .hinge, swapPattern: "hip_hinge",
            primaryMuscles: ["Lower Back"],
            secondaryMuscles: [.init(muscle: "Glutes", weight: 0.5), .init(muscle: "Hamstrings", weight: 0.4)],
            equipment: .bodyweight, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["reverse_hyperextension", "good_morning"],
            swapWarning: nil, variationOfKey: nil,
            head: "thickness", generatorPattern: "hinge",
            headContributions: [
                .lowerBack: 1.0,
                .glutesMax: 0.7,
                .hamstringsHipExtension: 0.7
            ]),

        ExerciseDefinition(
            key: "reverse_hyperextension", displayName: "Reverse Hyperextension",
            movementPattern: .hinge, swapPattern: "hip_hinge",
            primaryMuscles: ["Lower Back", "Glutes"],
            secondaryMuscles: [.init(muscle: "Hamstrings", weight: 0.4)],
            equipment: .machine, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["hyperextension", "good_morning"],
            swapWarning: nil, variationOfKey: "hyperextension",
            head: "thickness", generatorPattern: "hinge",
            headContributions: [
                .glutesMax: 1.0,
                .hamstringsHipExtension: 0.6,
                .lowerBack: 0.6
            ]),

        // Keep old key as alias
        ExerciseDefinition(
            key: "pulldown_cable", displayName: "Cable Lat Pulldown",
            movementPattern: .verticalPull, swapPattern: "vertical_pull",
            primaryMuscles: ["Lats"],
            secondaryMuscles: [.init(muscle: "Biceps", weight: 0.5), .init(muscle: "Rear Delts", weight: 0.3)],
            equipment: .cable, isCompound: true, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["pulldown_wide", "pullup", "pulldown_close"],
            swapWarning: nil, variationOfKey: "pulldown_wide", isAnchorableAsTier1: true,
            rank: 1, head: "width", generatorPattern: "vertical_pull",
            headContributions: [
                .lats: 1.0, .midBack: 0.4, .rearDelts: 0.3,
                .bicepsShort: 0.5, .bicepsLong: 0.3, .brachialis: 0.4
            ]),

        ExerciseDefinition(
            key: "pullover_cable", displayName: "Cable Pullover",
            movementPattern: .verticalPull, swapPattern: "vertical_pull",
            primaryMuscles: ["Lats"],
            secondaryMuscles: [],
            equipment: .cable, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["pulldown_straight_arm"],
            swapWarning: nil, variationOfKey: nil,
            rank: 3, head: "width", generatorPattern: "vertical_pull",
            headContributions: [
                .lats: 1.0, .chestLower: 0.3
            ]),

        ExerciseDefinition(
            key: "row_cable_neutral", displayName: "Cable Row (Neutral Grip)",
            movementPattern: .horizontalPull, swapPattern: "horizontal_pull",
            primaryMuscles: ["Lats", "Mid Back"],
            secondaryMuscles: [.init(muscle: "Biceps", weight: 0.5), .init(muscle: "Rear Delts", weight: 0.4)],
            equipment: .cable, isCompound: true, stretchPosition: .mid,
            jointStressTags: [],
            swapKeys: ["row_cable_narrow", "row_machine", "row_dumbbell"],
            swapWarning: nil, variationOfKey: "row_cable_narrow",
            head: "thickness", generatorPattern: "horizontal_row",
            headContributions: [
                .midBack: 1.0, .lats: 0.8, .rearDelts: 0.4,
                .bicepsLong: 0.4, .bicepsShort: 0.4, .brachialis: 0.4
            ]),

        // ═══════════════════════════════════════
        // SHOULDERS
        // ═══════════════════════════════════════

        ExerciseDefinition(
            key: "ohp_barbell", displayName: "Overhead Press (Barbell)",
            movementPattern: .verticalPush, swapPattern: "vertical_push",
            primaryMuscles: ["Front Delts", "Mid Delts"],
            secondaryMuscles: [.init(muscle: "Triceps", weight: 0.6), .init(muscle: "Upper Traps", weight: 0.4), .init(muscle: "Upper Chest", weight: 0.3)],
            equipment: .barbell, isCompound: true, stretchPosition: .mid,
            jointStressTags: ["shoulder"],
            swapKeys: ["ohp_dumbbell", "arnold_press", "shoulder_press_machine", "ohp_smith"],
            swapWarning: nil, variationOfKey: nil, isAnchorableAsTier1: true,
            rank: 1, head: "anterior", generatorPattern: "vertical_press",
            headContributions: [
                .deltsFront: 1.0, .deltsLateral: 0.5,
                .tricepsLateral: 0.6, .tricepsMedial: 0.5, .tricepsLong: 0.5,
                .traps: 0.4,
                .chestUpper: 0.3
            ]),

        ExerciseDefinition(
            key: "ohp_dumbbell", displayName: "Dumbbell Shoulder Press",
            movementPattern: .verticalPush, swapPattern: "vertical_push",
            primaryMuscles: ["Front Delts", "Mid Delts"],
            secondaryMuscles: [.init(muscle: "Triceps", weight: 0.5), .init(muscle: "Upper Traps", weight: 0.3)],
            equipment: .dumbbell, isCompound: true, stretchPosition: .mid,
            jointStressTags: ["shoulder"],
            swapKeys: ["ohp_barbell", "arnold_press", "shoulder_press_machine"],
            swapWarning: nil, variationOfKey: "ohp_barbell",
            rank: 1, head: "anterior", generatorPattern: "vertical_press",
            headContributions: [
                .deltsFront: 1.0, .deltsLateral: 0.5,
                .tricepsLateral: 0.5, .tricepsMedial: 0.4, .tricepsLong: 0.4,
                .traps: 0.3
            ]),

        ExerciseDefinition(
            key: "arnold_press", displayName: "Arnold Press",
            movementPattern: .verticalPush, swapPattern: "vertical_push",
            primaryMuscles: ["Front Delts", "Mid Delts"],
            secondaryMuscles: [.init(muscle: "Triceps", weight: 0.4), .init(muscle: "Upper Traps", weight: 0.3)],
            equipment: .dumbbell, isCompound: true, stretchPosition: .mid,
            jointStressTags: ["shoulder"],
            swapKeys: ["ohp_dumbbell", "ohp_barbell"],
            swapWarning: nil, variationOfKey: "ohp_barbell",
            head: "anterior", generatorPattern: "vertical_press",
            headContributions: [
                .deltsFront: 1.0, .deltsLateral: 0.6,
                .tricepsLateral: 0.5, .tricepsMedial: 0.4, .tricepsLong: 0.4,
                .traps: 0.3
            ]),

        ExerciseDefinition(
            key: "shoulder_press_seated_dumbbell", displayName: "Seated DB Shoulder Press",
            movementPattern: .verticalPush, swapPattern: "vertical_push",
            primaryMuscles: ["Front Delts", "Mid Delts"],
            secondaryMuscles: [.init(muscle: "Triceps", weight: 0.5)],
            equipment: .dumbbell, isCompound: true, stretchPosition: .mid,
            jointStressTags: ["shoulder"],
            swapKeys: ["ohp_dumbbell", "ohp_barbell", "shoulder_press_machine"],
            swapWarning: nil, variationOfKey: "ohp_dumbbell",
            head: "anterior", generatorPattern: "vertical_press",
            headContributions: [
                .deltsFront: 1.0, .deltsLateral: 0.5,
                .tricepsLateral: 0.5, .tricepsMedial: 0.4, .tricepsLong: 0.4
            ]),

        ExerciseDefinition(
            key: "shoulder_press_machine", displayName: "Machine Shoulder Press",
            movementPattern: .verticalPush, swapPattern: "vertical_push",
            primaryMuscles: ["Front Delts", "Mid Delts"],
            secondaryMuscles: [.init(muscle: "Triceps", weight: 0.4)],
            equipment: .machine, isCompound: true, stretchPosition: .mid,
            jointStressTags: [],
            swapKeys: ["ohp_dumbbell", "ohp_barbell"],
            swapWarning: nil, variationOfKey: nil,
            head: "anterior", generatorPattern: "vertical_press",
            headContributions: [
                .deltsFront: 1.0, .deltsLateral: 0.5,
                .tricepsLateral: 0.5, .tricepsMedial: 0.4, .tricepsLong: 0.4
            ]),

        ExerciseDefinition(
            key: "lateral_raise_dumbbell", displayName: "Dumbbell Lateral Raise",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Mid Delts"],
            secondaryMuscles: [.init(muscle: "Upper Traps", weight: 0.3)],
            equipment: .dumbbell, isCompound: false, stretchPosition: .mid,
            jointStressTags: [],
            swapKeys: ["lateral_raise_cable", "lateral_raise_machine"],
            swapWarning: nil, variationOfKey: nil,
            head: "medial", generatorPattern: "lateral_raise",
            headContributions: [
                .deltsLateral: 1.0, .deltsFront: 0.2,
                .traps: 0.3
            ]),

        ExerciseDefinition(
            key: "lateral_raise_cable", displayName: "Cable Lateral Raise",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Mid Delts"],
            secondaryMuscles: [.init(muscle: "Upper Traps", weight: 0.3)],
            equipment: .cable, isCompound: false, stretchPosition: .mid,
            jointStressTags: [],
            swapKeys: ["lateral_raise_dumbbell", "lateral_raise_machine"],
            swapWarning: nil, variationOfKey: "lateral_raise_dumbbell",
            rank: 1, head: "medial", generatorPattern: "lateral_raise",
            headContributions: [
                .deltsLateral: 1.0, .deltsFront: 0.2,
                .traps: 0.3
            ]),

        ExerciseDefinition(
            key: "lateral_raise_machine", displayName: "Machine Lateral Raise",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Mid Delts"],
            secondaryMuscles: [.init(muscle: "Upper Traps", weight: 0.2)],
            equipment: .machine, isCompound: false, stretchPosition: .mid,
            jointStressTags: [],
            swapKeys: ["lateral_raise_cable", "lateral_raise_dumbbell"],
            swapWarning: nil, variationOfKey: "lateral_raise_dumbbell",
            head: "medial", generatorPattern: "lateral_raise",
            headContributions: [
                .deltsLateral: 1.0, .deltsFront: 0.2,
                .traps: 0.2
            ]),

        ExerciseDefinition(
            key: "front_raise_dumbbell", displayName: "Dumbbell Front Raise",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Front Delts"],
            secondaryMuscles: [.init(muscle: "Mid Delts", weight: 0.3)],
            equipment: .dumbbell, isCompound: false, stretchPosition: .mid,
            jointStressTags: [],
            swapKeys: ["front_raise_cable"],
            swapWarning: nil, variationOfKey: nil,
            head: "anterior", generatorPattern: "lateral_raise",
            headContributions: [
                .deltsFront: 1.0, .deltsLateral: 0.3
            ]),

        ExerciseDefinition(
            key: "front_raise_cable", displayName: "Cable Front Raise",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Front Delts"],
            secondaryMuscles: [.init(muscle: "Mid Delts", weight: 0.3)],
            equipment: .cable, isCompound: false, stretchPosition: .mid,
            jointStressTags: [],
            swapKeys: ["front_raise_dumbbell"],
            swapWarning: nil, variationOfKey: "front_raise_dumbbell",
            head: "anterior", generatorPattern: "lateral_raise",
            headContributions: [
                .deltsFront: 1.0, .deltsLateral: 0.3
            ]),

        ExerciseDefinition(
            key: "rear_delt_fly_dumbbell", displayName: "Rear Delt Fly (Dumbbell)",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Rear Delts"],
            secondaryMuscles: [.init(muscle: "Mid Delts", weight: 0.3), .init(muscle: "Traps", weight: 0.3)],
            equipment: .dumbbell, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["rear_delt_fly_cable", "rear_delt_machine", "face_pull_cable"],
            swapWarning: nil, variationOfKey: nil,
            head: "posterior", generatorPattern: "rear_fly",
            headContributions: [
                .rearDelts: 1.0, .midBack: 0.5, .traps: 0.3
            ]),

        ExerciseDefinition(
            key: "rear_delt_fly_cable", displayName: "Rear Delt Fly (Cable)",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Rear Delts"],
            secondaryMuscles: [.init(muscle: "Mid Delts", weight: 0.3), .init(muscle: "Traps", weight: 0.3)],
            equipment: .cable, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["rear_delt_fly_dumbbell", "face_pull_cable", "rear_delt_machine"],
            swapWarning: nil, variationOfKey: "rear_delt_fly_dumbbell",
            head: "posterior", generatorPattern: "rear_fly",
            headContributions: [
                .rearDelts: 1.0, .midBack: 0.5, .traps: 0.3
            ]),

        ExerciseDefinition(
            key: "rear_delt_machine", displayName: "Rear Delt Machine Fly",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Rear Delts"],
            secondaryMuscles: [.init(muscle: "Mid Delts", weight: 0.2), .init(muscle: "Traps", weight: 0.2)],
            equipment: .machine, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["rear_delt_fly_cable", "rear_delt_fly_dumbbell", "face_pull_cable"],
            swapWarning: nil, variationOfKey: nil,
            rank: 1, head: "posterior", generatorPattern: "rear_fly",
            headContributions: [
                .rearDelts: 1.0, .midBack: 0.5, .traps: 0.3
            ]),

        ExerciseDefinition(
            key: "face_pull_cable", displayName: "Face Pull",
            movementPattern: .horizontalPull, swapPattern: "isolation",
            primaryMuscles: ["Rear Delts", "Traps"],
            secondaryMuscles: [.init(muscle: "Mid Delts", weight: 0.3), .init(muscle: "External Rotators", weight: 0.3)],
            equipment: .cable, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["rear_delt_fly_cable", "rear_delt_fly_dumbbell"],
            swapWarning: nil, variationOfKey: nil,
            rank: 1, head: "posterior", generatorPattern: "rear_fly",
            headContributions: [
                .rearDelts: 0.9, .midBack: 0.6, .traps: 0.5
            ]),

        ExerciseDefinition(
            key: "upright_row", displayName: "Upright Row",
            movementPattern: .verticalPull, swapPattern: "vertical_pull_partial",
            primaryMuscles: ["Upper Traps", "Mid Delts"],
            secondaryMuscles: [.init(muscle: "Front Delts", weight: 0.3)],
            equipment: .barbell, isCompound: true, stretchPosition: .mid,
            jointStressTags: ["shoulder"],
            swapKeys: ["face_pull_cable", "lateral_raise_cable", "shrug_barbell"],
            swapWarning: nil, variationOfKey: nil,
            rank: 3, head: "medial", generatorPattern: "lateral_raise",
            headContributions: [
                .deltsLateral: 0.8, .deltsFront: 0.6, .traps: 0.7
            ]),

        ExerciseDefinition(
            key: "shrug_barbell", displayName: "Barbell Shrug",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Upper Traps"],
            secondaryMuscles: [],
            equipment: .barbell, isCompound: false, stretchPosition: .shortened,
            jointStressTags: [],
            swapKeys: ["shrug_dumbbell", "shrug_cable"],
            swapWarning: nil, variationOfKey: nil,
            generatorPattern: "shrug",
            headContributions: [
                .traps: 1.0, .deltsLateral: 0.2
            ]),

        ExerciseDefinition(
            key: "shrug_dumbbell", displayName: "Dumbbell Shrug",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Upper Traps"],
            secondaryMuscles: [],
            equipment: .dumbbell, isCompound: false, stretchPosition: .shortened,
            jointStressTags: [],
            swapKeys: ["shrug_barbell", "shrug_cable"],
            swapWarning: nil, variationOfKey: "shrug_barbell",
            generatorPattern: "shrug",
            headContributions: [
                .traps: 1.0, .deltsLateral: 0.2
            ]),

        ExerciseDefinition(
            key: "shrug_cable", displayName: "Cable Shrug",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Upper Traps"],
            secondaryMuscles: [],
            equipment: .cable, isCompound: false, stretchPosition: .shortened,
            jointStressTags: [],
            swapKeys: ["shrug_barbell", "shrug_dumbbell"],
            swapWarning: nil, variationOfKey: "shrug_barbell",
            generatorPattern: "shrug",
            headContributions: [
                .traps: 1.0, .deltsLateral: 0.2
            ]),

        // ═══════════════════════════════════════
        // TRICEPS
        // ═══════════════════════════════════════

        ExerciseDefinition(
            key: "close_grip_bench", displayName: "Close-Grip Bench Press",
            movementPattern: .horizontalPush, swapPattern: "horizontal_push",
            primaryMuscles: ["Triceps"],
            secondaryMuscles: [.init(muscle: "Chest", weight: 0.5), .init(muscle: "Front Delts", weight: 0.3)],
            equipment: .barbell, isCompound: true, stretchPosition: .mid,
            jointStressTags: ["shoulder"],
            swapKeys: ["dips_tricep", "machine_dip"],
            swapWarning: nil, variationOfKey: nil, isAnchorableAsTier1: true,
            rank: 1, head: "lateral", generatorPattern: "press",
            additionalFilterMuscles: ["Chest"],
            headContributions: [
                .tricepsLateral: 0.8, .tricepsMedial: 0.7, .tricepsLong: 0.6,
                .chestMid: 0.7, .chestLower: 0.4,
                .deltsFront: 0.5
            ]),

        ExerciseDefinition(
            key: "tricep_pushdown_cable", displayName: "Triceps Pushdown (Bar)",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Triceps"],
            secondaryMuscles: [],
            equipment: .cable, isCompound: false, stretchPosition: .shortened,
            jointStressTags: [],
            swapKeys: ["tricep_pushdown_rope", "tricep_pushdown_machine"],
            swapWarning: nil, variationOfKey: nil,
            rank: 3, head: "lateral", generatorPattern: "pushdown",
            headContributions: [
                .tricepsLateral: 1.0, .tricepsMedial: 0.9, .tricepsLong: 0.4
            ]),

        ExerciseDefinition(
            key: "tricep_pushdown_rope", displayName: "Triceps Pushdown (Rope)",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Triceps"],
            secondaryMuscles: [],
            equipment: .cable, isCompound: false, stretchPosition: .shortened,
            jointStressTags: [],
            swapKeys: ["tricep_pushdown_cable", "tricep_pushdown_machine"],
            swapWarning: nil, variationOfKey: "tricep_pushdown_cable",
            rank: 3, head: "lateral", generatorPattern: "pushdown",
            headContributions: [
                .tricepsLateral: 1.0, .tricepsMedial: 0.9, .tricepsLong: 0.4
            ]),

        ExerciseDefinition(
            key: "tricep_overhead_cable", displayName: "Overhead Triceps Extension (Cable, High Anchor)",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Triceps"],
            secondaryMuscles: [],
            equipment: .cable, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["tricep_overhead_cable_low", "tricep_overhead_dumbbell", "skullcrusher_barbell"],
            swapWarning: "Long head stretch movement — avoid swapping to shortened-position exercises.", variationOfKey: nil,
            rank: 1, head: "long", generatorPattern: "extension",
            headContributions: [
                .tricepsLong: 1.0, .tricepsLateral: 0.5, .tricepsMedial: 0.5
            ]),

        // Low-pulley variant: cable anchored at the floor, you face away and
        // extend forward/up. Peak resistance occurs in the deepest stretch
        // (cable behind head), which research suggests is more hypertrophic
        // for the long head than the high-anchor variant.
        ExerciseDefinition(
            key: "tricep_overhead_cable_low", displayName: "Overhead Triceps Extension (Cable, Low Anchor)",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Triceps"],
            secondaryMuscles: [],
            equipment: .cable, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["tricep_overhead_cable", "tricep_overhead_dumbbell", "skullcrusher_barbell"],
            swapWarning: "Stretch-biased long-head movement — peak load is in the lengthened position. Avoid swapping to shortened-position exercises.",
            variationOfKey: "tricep_overhead_cable",
            rank: 1, head: "long", generatorPattern: "extension",
            // Higher long-head weighting reflects greater stretch-position
            // loading. Lateral/medial slightly lower than high-anchor variant.
            headContributions: [
                .tricepsLong: 1.0, .tricepsLateral: 0.45, .tricepsMedial: 0.45
            ]),

        // Single-arm overhead extension. Allows greater ROM and stretch on
        // each side independently. Commonly programmed as a finisher.
        ExerciseDefinition(
            key: "tricep_overhead_single_arm_dumbbell", displayName: "Single-Arm Overhead Triceps Extension (Dumbbell)",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Triceps"],
            secondaryMuscles: [],
            equipment: .dumbbell, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["tricep_overhead_dumbbell", "tricep_overhead_cable_low", "tricep_overhead_cable"],
            swapWarning: "Long head stretch movement — avoid swapping to shortened-position exercises.",
            variationOfKey: "tricep_overhead_dumbbell",
            rank: 2, head: "long", generatorPattern: "extension",
            headContributions: [
                .tricepsLong: 1.0, .tricepsLateral: 0.5, .tricepsMedial: 0.5
            ]),

        // Single-arm pushdown — unilateral lateral/medial head emphasis.
        ExerciseDefinition(
            key: "tricep_pushdown_single_arm", displayName: "Single-Arm Triceps Pushdown",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Triceps"],
            secondaryMuscles: [],
            equipment: .cable, isCompound: false, stretchPosition: .shortened,
            jointStressTags: [],
            swapKeys: ["tricep_pushdown_rope", "tricep_pushdown_cable"],
            swapWarning: nil, variationOfKey: "tricep_pushdown_cable",
            rank: 2, head: "lateral", generatorPattern: "pushdown",
            headContributions: [
                .tricepsLateral: 1.0, .tricepsMedial: 0.9, .tricepsLong: 0.4
            ]),

        ExerciseDefinition(
            key: "tricep_overhead_dumbbell", displayName: "Overhead Triceps Extension (Dumbbell)",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Triceps"],
            secondaryMuscles: [],
            equipment: .dumbbell, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["tricep_overhead_cable", "skullcrusher_barbell"],
            swapWarning: "Long head stretch movement — avoid swapping to shortened-position exercises.", variationOfKey: "tricep_overhead_cable",
            rank: 1, head: "long", generatorPattern: "extension",
            headContributions: [
                .tricepsLong: 1.0, .tricepsLateral: 0.5, .tricepsMedial: 0.5
            ]),

        ExerciseDefinition(
            key: "skullcrusher_barbell", displayName: "Skull Crusher (Barbell)",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Triceps"],
            secondaryMuscles: [],
            equipment: .barbell, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: ["elbow"],
            swapKeys: ["skullcrusher_dumbbell", "tricep_overhead_cable"],
            swapWarning: nil, variationOfKey: nil,
            rank: 1, head: "long", generatorPattern: "extension",
            headContributions: [
                .tricepsLong: 1.0, .tricepsLateral: 0.7, .tricepsMedial: 0.6
            ]),

        ExerciseDefinition(
            key: "skullcrusher_dumbbell", displayName: "Skull Crusher (Dumbbell)",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Triceps"],
            secondaryMuscles: [],
            equipment: .dumbbell, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: ["elbow"],
            swapKeys: ["skullcrusher_barbell", "tricep_overhead_cable"],
            swapWarning: nil, variationOfKey: "skullcrusher_barbell",
            head: "long", generatorPattern: "extension",
            headContributions: [
                .tricepsLong: 1.0, .tricepsLateral: 0.7, .tricepsMedial: 0.6
            ]),

        ExerciseDefinition(
            key: "dips_tricep", displayName: "Dips (Triceps-Focused)",
            movementPattern: .horizontalPush, swapPattern: "horizontal_push",
            primaryMuscles: ["Triceps"],
            secondaryMuscles: [.init(muscle: "Chest", weight: 0.4), .init(muscle: "Front Delts", weight: 0.3)],
            equipment: .bodyweight, isCompound: true, stretchPosition: .mid,
            jointStressTags: ["shoulder", "elbow"],
            swapKeys: ["close_grip_bench", "machine_dip"],
            swapWarning: nil, variationOfKey: nil,
            head: "lateral", generatorPattern: "press",
            additionalFilterMuscles: ["Chest"],
            headContributions: [
                .tricepsLateral: 0.9, .tricepsMedial: 0.8, .tricepsLong: 0.5,
                .chestLower: 0.6, .chestMid: 0.4,
                .deltsFront: 0.4
            ]),

        ExerciseDefinition(
            key: "diamond_pushup", displayName: "Diamond Push-Up",
            movementPattern: .horizontalPush, swapPattern: "horizontal_push",
            primaryMuscles: ["Triceps"],
            secondaryMuscles: [.init(muscle: "Chest", weight: 0.4)],
            equipment: .bodyweight, isCompound: true, stretchPosition: .mid,
            jointStressTags: [],
            swapKeys: ["close_grip_bench", "tricep_pushdown_cable"],
            swapWarning: nil, variationOfKey: nil,
            head: "lateral", generatorPattern: "press",
            additionalFilterMuscles: ["Chest"],
            headContributions: [
                .tricepsLateral: 0.8, .tricepsMedial: 0.7, .tricepsLong: 0.5,
                .chestMid: 0.5, .chestLower: 0.3,
                .deltsFront: 0.3
            ]),

        ExerciseDefinition(
            key: "kickback_dumbbell", displayName: "Dumbbell Kickback",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Triceps"],
            secondaryMuscles: [],
            equipment: .dumbbell, isCompound: false, stretchPosition: .shortened,
            jointStressTags: [],
            swapKeys: ["tricep_pushdown_cable"],
            swapWarning: nil, variationOfKey: nil,
            rank: 3, head: "lateral", generatorPattern: "kickback",
            headContributions: [
                .tricepsLong: 0.9, .tricepsLateral: 0.5, .tricepsMedial: 0.5
            ]),

        ExerciseDefinition(
            key: "jm_press", displayName: "JM Press",
            movementPattern: .horizontalPush, swapPattern: "horizontal_push",
            primaryMuscles: ["Triceps"],
            secondaryMuscles: [.init(muscle: "Chest", weight: 0.3)],
            equipment: .barbell, isCompound: true, stretchPosition: .mid,
            jointStressTags: ["elbow"],
            swapKeys: ["close_grip_bench", "skullcrusher_barbell"],
            swapWarning: nil, variationOfKey: nil,
            head: "lateral", generatorPattern: "press",
            headContributions: [
                .tricepsLong: 0.9, .tricepsLateral: 0.8, .tricepsMedial: 0.7,
                .chestMid: 0.4,
                .deltsFront: 0.3
            ]),

        // ═══════════════════════════════════════
        // BICEPS
        // ═══════════════════════════════════════

        ExerciseDefinition(
            key: "curl_barbell", displayName: "Barbell Curl",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Biceps"],
            secondaryMuscles: [.init(muscle: "Brachialis", weight: 0.5), .init(muscle: "Brachioradialis", weight: 0.3)],
            equipment: .barbell, isCompound: false, stretchPosition: .mid,
            jointStressTags: [],
            swapKeys: ["curl_dumbbell", "curl_cable", "curl_machine"],
            swapWarning: nil, variationOfKey: nil,
            head: "both", generatorPattern: "curl",
            headContributions: [
                .bicepsShort: 0.9, .bicepsLong: 0.7, .brachialis: 0.4
            ]),

        ExerciseDefinition(
            key: "curl_dumbbell", displayName: "Dumbbell Curl",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Biceps"],
            secondaryMuscles: [.init(muscle: "Brachialis", weight: 0.5)],
            equipment: .dumbbell, isCompound: false, stretchPosition: .mid,
            jointStressTags: [],
            swapKeys: ["curl_barbell", "curl_cable"],
            swapWarning: nil, variationOfKey: "curl_barbell",
            head: "both", generatorPattern: "curl",
            headContributions: [
                .bicepsShort: 0.9, .bicepsLong: 0.7, .brachialis: 0.4
            ]),

        ExerciseDefinition(
            key: "curl_incline_dumbbell", displayName: "Incline Dumbbell Curl",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Biceps"],
            secondaryMuscles: [.init(muscle: "Brachialis", weight: 0.4)],
            equipment: .dumbbell, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["curl_high_cable"],
            swapWarning: "Long head stretch movement — do not swap to preacher curl (opposite stretch profile).", variationOfKey: "curl_barbell",
            rank: 1, head: "long", generatorPattern: "curl",
            headContributions: [
                .bicepsLong: 1.0, .bicepsShort: 0.5, .brachialis: 0.3
            ]),

        ExerciseDefinition(
            key: "curl_preacher_barbell", displayName: "Preacher Curl (Barbell)",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Biceps"],
            secondaryMuscles: [.init(muscle: "Brachialis", weight: 0.5)],
            equipment: .barbell, isCompound: false, stretchPosition: .mid,
            jointStressTags: [],
            swapKeys: ["curl_preacher_dumbbell", "curl_machine", "curl_spider"],
            swapWarning: "Short head emphasis — not equivalent to incline curl.", variationOfKey: nil,
            head: "short", generatorPattern: "curl",
            headContributions: [
                .bicepsShort: 1.0, .bicepsLong: 0.5, .brachialis: 0.4
            ]),

        ExerciseDefinition(
            key: "curl_preacher_dumbbell", displayName: "Preacher Curl (Dumbbell)",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Biceps"],
            secondaryMuscles: [.init(muscle: "Brachialis", weight: 0.5)],
            equipment: .dumbbell, isCompound: false, stretchPosition: .mid,
            jointStressTags: [],
            swapKeys: ["curl_preacher_barbell", "curl_machine"],
            swapWarning: "Short head emphasis — not equivalent to incline curl.", variationOfKey: "curl_preacher_barbell",
            head: "short", generatorPattern: "curl",
            headContributions: [
                .bicepsShort: 1.0, .bicepsLong: 0.5, .brachialis: 0.4
            ]),

        ExerciseDefinition(
            key: "curl_cable", displayName: "Cable Curl",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Biceps"],
            secondaryMuscles: [.init(muscle: "Brachialis", weight: 0.4)],
            equipment: .cable, isCompound: false, stretchPosition: .mid,
            jointStressTags: [],
            swapKeys: ["curl_barbell", "curl_dumbbell"],
            swapWarning: nil, variationOfKey: "curl_barbell",
            rank: 1, head: "short", generatorPattern: "curl",
            headContributions: [
                .bicepsShort: 0.9, .bicepsLong: 0.7, .brachialis: 0.4
            ]),

        ExerciseDefinition(
            key: "curl_high_cable", displayName: "High Cable Curl",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Biceps"],
            secondaryMuscles: [.init(muscle: "Brachialis", weight: 0.3)],
            equipment: .cable, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["curl_incline_dumbbell"],
            swapWarning: "Long head stretch movement — do not swap to preacher curl.", variationOfKey: nil,
            head: "long", generatorPattern: "curl",
            headContributions: [
                .bicepsLong: 1.0, .bicepsShort: 0.5, .brachialis: 0.3
            ]),

        ExerciseDefinition(
            key: "curl_hammer", displayName: "Hammer Curl",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Brachialis", "Brachioradialis"],
            secondaryMuscles: [.init(muscle: "Biceps", weight: 0.5)],
            equipment: .dumbbell, isCompound: false, stretchPosition: .mid,
            jointStressTags: [],
            swapKeys: ["curl_reverse"],
            swapWarning: "Brachialis primary — not a true bicep swap.", variationOfKey: nil,
            rank: 3, head: "brachio", generatorPattern: "curl",
            headContributions: [
                .brachialis: 1.0, .bicepsLong: 0.6, .bicepsShort: 0.3
            ]),

        ExerciseDefinition(
            key: "curl_reverse", displayName: "Reverse Curl",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Brachioradialis", "Brachialis"],
            secondaryMuscles: [.init(muscle: "Biceps", weight: 0.3)],
            equipment: .barbell, isCompound: false, stretchPosition: .mid,
            jointStressTags: [],
            swapKeys: ["curl_hammer"],
            swapWarning: nil, variationOfKey: nil,
            rank: 3, head: "brachio", generatorPattern: "curl",
            headContributions: [
                .brachialis: 1.0, .bicepsShort: 0.3, .bicepsLong: 0.2
            ]),

        ExerciseDefinition(
            key: "curl_concentration", displayName: "Concentration Curl",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Biceps"],
            secondaryMuscles: [.init(muscle: "Brachialis", weight: 0.3)],
            equipment: .dumbbell, isCompound: false, stretchPosition: .mid,
            jointStressTags: [],
            swapKeys: ["curl_preacher_dumbbell", "curl_machine"],
            swapWarning: nil, variationOfKey: nil,
            rank: 3, head: "short", generatorPattern: "curl",
            headContributions: [
                .bicepsShort: 1.0, .bicepsLong: 0.6, .brachialis: 0.3
            ]),

        ExerciseDefinition(
            key: "curl_spider", displayName: "Spider Curl",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Biceps"],
            secondaryMuscles: [.init(muscle: "Brachialis", weight: 0.4)],
            equipment: .dumbbell, isCompound: false, stretchPosition: .mid,
            jointStressTags: [],
            swapKeys: ["curl_preacher_barbell", "curl_machine"],
            swapWarning: nil, variationOfKey: nil,
            rank: 3, head: "short", generatorPattern: "curl",
            headContributions: [
                .bicepsShort: 1.0, .bicepsLong: 0.5, .brachialis: 0.4
            ]),

        ExerciseDefinition(
            key: "curl_machine", displayName: "Machine Curl",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Biceps"],
            secondaryMuscles: [.init(muscle: "Brachialis", weight: 0.3)],
            equipment: .machine, isCompound: false, stretchPosition: .mid,
            jointStressTags: [],
            swapKeys: ["curl_barbell", "curl_cable"],
            swapWarning: nil, variationOfKey: nil,
            head: "both", generatorPattern: "curl",
            headContributions: [
                .bicepsShort: 0.9, .bicepsLong: 0.7, .brachialis: 0.3
            ]),

        // ═══════════════════════════════════════
        // QUADS
        // ═══════════════════════════════════════

        ExerciseDefinition(
            key: "squat_barbell", displayName: "Barbell Back Squat",
            movementPattern: .squat, swapPattern: "knee_dominant",
            primaryMuscles: ["Quads"],
            // Bumped Hams 0.3→0.4 (deeper squats engage hams more in the
            // hole). Lower back gets significant isometric stabilizer work.
            secondaryMuscles: [.init(muscle: "Glutes", weight: 0.7), .init(muscle: "Hamstrings", weight: 0.4), .init(muscle: "Adductors", weight: 0.3), .init(muscle: "Lower Back", weight: 0.5)],
            equipment: .barbell, isCompound: true, stretchPosition: .lengthened,
            jointStressTags: ["knee", "low_back"],
            swapKeys: ["squat_front", "hack_squat", "squat_smith", "leg_press"],
            swapWarning: nil, variationOfKey: nil, isAnchorableAsTier1: true,
            rank: 1, head: "compound", generatorPattern: "squat", sessionRestriction: .lowerOnly,
            headContributions: [
                .vastusLateralis: 1.0, .vastusMedialis: 1.0, .rectusFemoris: 0.7,
                .glutesMax: 0.7,
                .hamstringsHipExtension: 0.4,
                .adductors: 0.3,
                .lowerBack: 0.5
            ]),

        ExerciseDefinition(
            key: "squat_front", displayName: "Barbell Front Squat",
            movementPattern: .squat, swapPattern: "knee_dominant",
            primaryMuscles: ["Quads"],
            secondaryMuscles: [.init(muscle: "Glutes", weight: 0.5), .init(muscle: "Hamstrings", weight: 0.2)],
            equipment: .barbell, isCompound: true, stretchPosition: .lengthened,
            jointStressTags: ["knee"],
            swapKeys: ["squat_barbell", "hack_squat", "squat_goblet"],
            swapWarning: nil, variationOfKey: "squat_barbell",
            head: "compound", generatorPattern: "squat", sessionRestriction: .lowerOnly,
            headContributions: [
                .rectusFemoris: 1.0, .vastusLateralis: 0.9, .vastusMedialis: 0.9,
                .glutesMax: 0.5,
                .hamstringsHipExtension: 0.2,
                .lowerBack: 0.4
            ]),

        ExerciseDefinition(
            key: "squat_goblet", displayName: "Goblet Squat",
            movementPattern: .squat, swapPattern: "knee_dominant",
            primaryMuscles: ["Quads"],
            secondaryMuscles: [.init(muscle: "Glutes", weight: 0.5)],
            equipment: .dumbbell, isCompound: true, stretchPosition: .lengthened,
            jointStressTags: ["knee"],
            swapKeys: ["squat_front", "hack_squat"],
            swapWarning: nil, variationOfKey: "squat_barbell",
            head: "compound", generatorPattern: "squat", sessionRestriction: .lowerOnly,
            headContributions: [
                .rectusFemoris: 1.0, .vastusLateralis: 0.9, .vastusMedialis: 0.9,
                .glutesMax: 0.5
            ]),

        ExerciseDefinition(
            key: "hack_squat", displayName: "Hack Squat (Machine)",
            movementPattern: .squat, swapPattern: "knee_dominant",
            primaryMuscles: ["Quads"],
            // Bumped Glutes 0.4→0.5 (deep hack squat with sit-back gets
            // meaningful glute work). Adductor stabilizer credit added.
            secondaryMuscles: [.init(muscle: "Glutes", weight: 0.5), .init(muscle: "Adductors", weight: 0.3)],
            equipment: .machine, isCompound: true, stretchPosition: .lengthened,
            jointStressTags: ["knee"],
            swapKeys: ["leg_press", "pendulum_squat", "squat_smith"],
            swapWarning: nil, variationOfKey: nil, isAnchorableAsTier1: true,
            rank: 1, head: "compound", generatorPattern: "squat", sessionRestriction: .lowerOnly,
            headContributions: [
                .vastusLateralis: 1.0, .vastusMedialis: 1.0, .rectusFemoris: 0.6,
                .glutesMax: 0.7, .adductors: 0.3
            ]),

        ExerciseDefinition(
            key: "leg_press", displayName: "Leg Press",
            movementPattern: .squat, swapPattern: "knee_dominant",
            primaryMuscles: ["Quads"],
            // Bumped Hams 0.3→0.4 — deep leg press with feet high engages
            // hams more than a shallow press.
            secondaryMuscles: [.init(muscle: "Glutes", weight: 0.6), .init(muscle: "Hamstrings", weight: 0.4)],
            equipment: .machine, isCompound: true, stretchPosition: .lengthened,
            jointStressTags: ["knee"],
            swapKeys: ["hack_squat", "squat_smith"],
            swapWarning: nil, variationOfKey: nil, isAnchorableAsTier1: true,
            rank: 1, head: "compound", generatorPattern: "press", sessionRestriction: .lowerOnly,
            headContributions: [
                .vastusLateralis: 1.0, .vastusMedialis: 1.0, .rectusFemoris: 0.7,
                .glutesMax: 0.6,
                .hamstringsHipExtension: 0.4
            ]),

        ExerciseDefinition(
            key: "belt_squat", displayName: "Belt Squat",
            movementPattern: .squat, swapPattern: "knee_dominant",
            primaryMuscles: ["Quads"],
            secondaryMuscles: [.init(muscle: "Glutes", weight: 0.5), .init(muscle: "Adductors", weight: 0.3)],
            equipment: .machine, isCompound: true, stretchPosition: .lengthened,
            jointStressTags: ["knee"],
            swapKeys: ["hack_squat", "leg_press", "squat_barbell", "pendulum_squat"],
            swapWarning: nil, variationOfKey: nil, isAnchorableAsTier1: true,
            head: "compound", generatorPattern: "squat", sessionRestriction: .lowerOnly,
            headContributions: [
                .vastusLateralis: 1.0, .vastusMedialis: 1.0, .rectusFemoris: 0.7,
                .glutesMax: 0.6, .adductors: 0.3
            ]),

        ExerciseDefinition(
            key: "leg_extension", displayName: "Leg Extension",
            movementPattern: .isolation, swapPattern: "quad_isolation",
            primaryMuscles: ["Quads"],
            secondaryMuscles: [],
            equipment: .machine, isCompound: false, stretchPosition: .shortened,
            jointStressTags: ["knee"],
            swapKeys: ["leg_extension_single", "spanish_squat", "sissy_squat"],
            swapWarning: nil, variationOfKey: nil,
            rank: 3, head: "isolation", generatorPattern: "extension", sessionRestriction: .lowerOnly,
            headContributions: [
                .rectusFemoris: 1.0, .vastusLateralis: 0.8, .vastusMedialis: 0.8
            ]),

        ExerciseDefinition(
            key: "bulgarian_split_squat", displayName: "Bulgarian Split Squat",
            movementPattern: .lunge, swapPattern: "knee_dominant",
            primaryMuscles: ["Quads"],
            secondaryMuscles: [.init(muscle: "Glutes", weight: 0.7), .init(muscle: "Hamstrings", weight: 0.3)],
            equipment: .dumbbell, isCompound: true, stretchPosition: .lengthened,
            jointStressTags: ["knee"],
            swapKeys: ["lunge_barbell", "step_up", "single_leg_leg_press"],
            swapWarning: nil, variationOfKey: nil,
            head: "compound", generatorPattern: "lunge", sessionRestriction: .lowerOnly,
            headContributions: [
                .vastusLateralis: 1.0, .vastusMedialis: 0.9, .rectusFemoris: 0.6,
                .glutesMax: 0.7, .glutesMedius: 0.4,
                .hamstringsHipExtension: 0.3
            ]),

        ExerciseDefinition(
            key: "lunge_barbell", displayName: "Barbell Lunge",
            movementPattern: .lunge, swapPattern: "knee_dominant",
            primaryMuscles: ["Quads"],
            secondaryMuscles: [.init(muscle: "Glutes", weight: 0.6), .init(muscle: "Hamstrings", weight: 0.3)],
            equipment: .barbell, isCompound: true, stretchPosition: .lengthened,
            jointStressTags: ["knee"],
            swapKeys: ["bulgarian_split_squat", "step_up"],
            swapWarning: nil, variationOfKey: nil,
            head: "compound", generatorPattern: "lunge", sessionRestriction: .lowerOnly,
            headContributions: [
                .vastusLateralis: 1.0, .vastusMedialis: 0.9, .rectusFemoris: 0.6,
                .glutesMax: 0.6, .glutesMedius: 0.3,
                .hamstringsHipExtension: 0.3
            ]),

        ExerciseDefinition(
            key: "lunge_dumbbell", displayName: "Dumbbell Lunge",
            movementPattern: .lunge, swapPattern: "knee_dominant",
            primaryMuscles: ["Quads"],
            secondaryMuscles: [.init(muscle: "Glutes", weight: 0.6), .init(muscle: "Hamstrings", weight: 0.3)],
            equipment: .dumbbell, isCompound: true, stretchPosition: .lengthened,
            jointStressTags: ["knee"],
            swapKeys: ["bulgarian_split_squat", "step_up", "lunge_barbell"],
            swapWarning: nil, variationOfKey: "lunge_barbell",
            head: "compound", generatorPattern: "lunge", sessionRestriction: .lowerOnly,
            headContributions: [
                .vastusLateralis: 1.0, .vastusMedialis: 0.9, .rectusFemoris: 0.6,
                .glutesMax: 0.6, .glutesMedius: 0.3,
                .hamstringsHipExtension: 0.3
            ]),

        ExerciseDefinition(
            key: "step_up", displayName: "Step-Up",
            movementPattern: .lunge, swapPattern: "knee_dominant",
            primaryMuscles: ["Quads"],
            secondaryMuscles: [.init(muscle: "Glutes", weight: 0.6)],
            equipment: .dumbbell, isCompound: true, stretchPosition: .lengthened,
            jointStressTags: ["knee"],
            swapKeys: ["bulgarian_split_squat", "lunge_dumbbell"],
            swapWarning: nil, variationOfKey: nil,
            rank: 3, head: "compound", generatorPattern: "lunge", sessionRestriction: .lowerOnly,
            headContributions: [
                .vastusLateralis: 0.9, .vastusMedialis: 0.8, .rectusFemoris: 0.5,
                .glutesMax: 0.7, .glutesMedius: 0.4,
                .hamstringsHipExtension: 0.3
            ]),

        ExerciseDefinition(
            key: "sissy_squat", displayName: "Sissy Squat",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Quads"],
            secondaryMuscles: [],
            equipment: .bodyweight, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: ["knee"],
            swapKeys: ["leg_extension"],
            swapWarning: nil, variationOfKey: nil,
            rank: 4, head: "isolation", generatorPattern: "extension", sessionRestriction: .lowerOnly,
            headContributions: [
                .rectusFemoris: 1.0, .vastusLateralis: 0.7, .vastusMedialis: 0.7
            ]),

        ExerciseDefinition(
            key: "spanish_squat", displayName: "Spanish Squat",
            movementPattern: .squat, swapPattern: "knee_dominant",
            primaryMuscles: ["Quads"],
            secondaryMuscles: [.init(muscle: "Glutes", weight: 0.3)],
            equipment: .band, isCompound: false, stretchPosition: .mid,
            jointStressTags: [],
            swapKeys: ["leg_extension"],
            swapWarning: nil, variationOfKey: nil,
            head: "isolation", generatorPattern: "extension", sessionRestriction: .lowerOnly,
            headContributions: [
                .vastusLateralis: 0.8, .vastusMedialis: 0.9, .rectusFemoris: 0.6,
                .glutesMax: 0.3
            ]),

        ExerciseDefinition(
            key: "pendulum_squat", displayName: "Pendulum Squat",
            movementPattern: .squat, swapPattern: "knee_dominant",
            primaryMuscles: ["Quads"],
            secondaryMuscles: [.init(muscle: "Glutes", weight: 0.4)],
            equipment: .machine, isCompound: true, stretchPosition: .lengthened,
            jointStressTags: ["knee"],
            swapKeys: ["hack_squat", "leg_press"],
            swapWarning: nil, variationOfKey: "hack_squat",
            rank: 1, head: "compound", generatorPattern: "squat", sessionRestriction: .lowerOnly,
            headContributions: [
                .vastusLateralis: 1.0, .vastusMedialis: 1.0, .rectusFemoris: 0.6,
                .glutesMax: 0.7
            ]),

        ExerciseDefinition(
            key: "squat_smith", displayName: "Smith Machine Squat",
            movementPattern: .squat, swapPattern: "knee_dominant",
            primaryMuscles: ["Quads"],
            secondaryMuscles: [.init(muscle: "Glutes", weight: 0.5), .init(muscle: "Hamstrings", weight: 0.3)],
            equipment: .machine, isCompound: true, stretchPosition: .lengthened,
            jointStressTags: ["knee"],
            swapKeys: ["squat_barbell", "hack_squat", "leg_press"],
            swapWarning: nil, variationOfKey: "squat_barbell",
            head: "compound", generatorPattern: "squat", sessionRestriction: .lowerOnly,
            headContributions: [
                .vastusLateralis: 1.0, .vastusMedialis: 1.0, .rectusFemoris: 0.6,
                .glutesMax: 0.6,
                .hamstringsHipExtension: 0.3
            ]),

        // ═══════════════════════════════════════
        // HAMSTRINGS
        // ═══════════════════════════════════════

        ExerciseDefinition(
            key: "rdl_barbell", displayName: "Romanian Deadlift (Barbell)",
            movementPattern: .hinge, swapPattern: "hip_hinge",
            // Glutes are co-primary on RDL — full hip extension at the top
            // is heavy glute work. Was previously secondary at 0.7 which
            // chronically under-counted glute volume for posterior-focused
            // training.
            primaryMuscles: ["Hamstrings", "Glutes"],
            secondaryMuscles: [.init(muscle: "Lower Back", weight: 0.5), .init(muscle: "Lats", weight: 0.3)],
            equipment: .barbell, isCompound: true, stretchPosition: .lengthened,
            jointStressTags: ["low_back"],
            swapKeys: ["rdl_dumbbell", "rdl_single_leg", "stiff_leg_deadlift"],
            swapWarning: nil, variationOfKey: nil, isAnchorableAsTier1: true,
            rank: 1, head: "hip_hinge", generatorPattern: "hinge", sessionRestriction: .lowerOnly,
            headContributions: [
                .hamstringsHipExtension: 1.0,
                .glutesMax: 0.9,
                .lowerBack: 0.5,
                .lats: 0.3
            ]),

        ExerciseDefinition(
            key: "rdl_dumbbell", displayName: "Romanian Deadlift (Dumbbell)",
            movementPattern: .hinge, swapPattern: "hip_hinge",
            primaryMuscles: ["Hamstrings", "Glutes"],
            secondaryMuscles: [.init(muscle: "Lower Back", weight: 0.4)],
            equipment: .dumbbell, isCompound: true, stretchPosition: .lengthened,
            jointStressTags: ["low_back"],
            swapKeys: ["rdl_barbell", "rdl_single_leg"],
            swapWarning: nil, variationOfKey: "rdl_barbell",
            rank: 1, head: "hip_hinge", generatorPattern: "hinge", sessionRestriction: .lowerOnly,
            headContributions: [
                .hamstringsHipExtension: 1.0,
                .glutesMax: 0.9,
                .lowerBack: 0.4
            ]),

        ExerciseDefinition(
            key: "rdl_single_leg", displayName: "Single-Leg RDL",
            movementPattern: .hinge, swapPattern: "hip_hinge",
            primaryMuscles: ["Hamstrings", "Glutes"],
            secondaryMuscles: [],
            equipment: .dumbbell, isCompound: true, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["rdl_barbell", "rdl_dumbbell"],
            swapWarning: nil, variationOfKey: "rdl_barbell",
            head: "hip_hinge", generatorPattern: "hinge", sessionRestriction: .lowerOnly,
            headContributions: [
                .hamstringsHipExtension: 1.0,
                .glutesMax: 0.9, .glutesMedius: 0.4,
                .lowerBack: 0.3
            ]),

        ExerciseDefinition(
            key: "leg_curl_lying", displayName: "Lying Leg Curl",
            movementPattern: .isolation, swapPattern: "hamstring_curl",
            primaryMuscles: ["Hamstrings"],
            secondaryMuscles: [],
            equipment: .machine, isCompound: false, stretchPosition: .mid,
            jointStressTags: [],
            swapKeys: ["leg_curl_seated", "leg_curl_standing", "nordic_hamstring_curl"],
            swapWarning: "Seated leg curl loads the long head in a more lengthened position — stretch profile differs.", variationOfKey: nil,
            head: "knee_flexion", generatorPattern: "curl", sessionRestriction: .lowerOnly,
            headContributions: [
                .hamstringsKneeFlexion: 1.0
            ]),

        ExerciseDefinition(
            key: "leg_curl_seated", displayName: "Seated Leg Curl",
            movementPattern: .isolation, swapPattern: "hamstring_curl",
            primaryMuscles: ["Hamstrings"],
            secondaryMuscles: [],
            equipment: .machine, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["leg_curl_lying", "leg_curl_standing", "leg_curl_seated_single"],
            swapWarning: "Lying leg curl has a different stretch profile — seated is preferred for long head hypertrophy.", variationOfKey: nil,
            rank: 1, head: "knee_flexion", generatorPattern: "curl", sessionRestriction: .lowerOnly,
            headContributions: [
                .hamstringsKneeFlexion: 1.0, .hamstringsHipExtension: 0.3
            ]),

        ExerciseDefinition(
            key: "nordic_hamstring_curl", displayName: "Nordic Hamstring Curl",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Hamstrings"],
            secondaryMuscles: [.init(muscle: "Glutes", weight: 0.3)],
            equipment: .bodyweight, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["glute_ham_raise"],
            swapWarning: nil, variationOfKey: nil,
            head: "knee_flexion", generatorPattern: "curl", sessionRestriction: .lowerOnly,
            headContributions: [
                .hamstringsKneeFlexion: 1.0, .hamstringsHipExtension: 0.3,
                .glutesMax: 0.3
            ]),

        ExerciseDefinition(
            key: "stiff_leg_deadlift", displayName: "Stiff-Leg Deadlift",
            movementPattern: .hinge, swapPattern: "hip_hinge",
            primaryMuscles: ["Hamstrings", "Glutes"],
            secondaryMuscles: [.init(muscle: "Lower Back", weight: 0.5)],
            equipment: .barbell, isCompound: true, stretchPosition: .lengthened,
            jointStressTags: ["low_back"],
            swapKeys: ["rdl_barbell", "good_morning"],
            swapWarning: nil, variationOfKey: "rdl_barbell",
            head: "hip_hinge", generatorPattern: "hinge", sessionRestriction: .lowerOnly,
            headContributions: [
                .hamstringsHipExtension: 1.0,
                .glutesMax: 0.8,
                .lowerBack: 0.6,
                .lats: 0.3
            ]),

        ExerciseDefinition(
            key: "glute_ham_raise", displayName: "Glute-Ham Raise",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Hamstrings", "Glutes"],
            secondaryMuscles: [.init(muscle: "Lower Back", weight: 0.3)],
            equipment: .machine, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["nordic_hamstring_curl"],
            swapWarning: nil, variationOfKey: nil,
            rank: 3, head: "knee_flexion", generatorPattern: "curl", sessionRestriction: .lowerOnly,
            headContributions: [
                .hamstringsKneeFlexion: 0.9, .hamstringsHipExtension: 0.6,
                .glutesMax: 0.5,
                .lowerBack: 0.3
            ]),

        ExerciseDefinition(
            key: "cable_pull_through", displayName: "Cable Pull-Through",
            movementPattern: .hinge, swapPattern: "hip_hinge",
            primaryMuscles: ["Hamstrings", "Glutes"],
            secondaryMuscles: [.init(muscle: "Lower Back", weight: 0.3)],
            equipment: .cable, isCompound: true, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["rdl_barbell", "rdl_dumbbell"],
            swapWarning: nil, variationOfKey: nil,
            rank: 3, head: "hip_hinge", generatorPattern: "hinge", sessionRestriction: .lowerOnly,
            headContributions: [
                .hamstringsHipExtension: 1.0,
                .glutesMax: 1.0,
                .lowerBack: 0.4
            ]),

        // ═══════════════════════════════════════
        // GLUTES
        // ═══════════════════════════════════════

        ExerciseDefinition(
            key: "hip_thrust_barbell", displayName: "Hip Thrust (Barbell)",
            movementPattern: .hipThrust, swapPattern: "isolation",
            primaryMuscles: ["Glutes"],
            // Heels-driven hip thrust gives hamstrings serious work — bumped
            // from 0.4 to 0.6. Some quad contribution too on the knee-extension
            // portion of the lockout.
            secondaryMuscles: [.init(muscle: "Hamstrings", weight: 0.6), .init(muscle: "Quads", weight: 0.3)],
            equipment: .barbell, isCompound: true, stretchPosition: .shortened,
            jointStressTags: [],
            swapKeys: ["hip_thrust_machine", "glute_bridge"],
            swapWarning: nil, variationOfKey: nil, isAnchorableAsTier1: true,
            rank: 1, head: "extension", generatorPattern: "hip_thrust", sessionRestriction: .lowerOnly,
            headContributions: [
                .glutesMax: 1.0,
                .hamstringsHipExtension: 0.6,
                .vastusLateralis: 0.3
            ]),

        ExerciseDefinition(
            key: "hip_thrust_machine", displayName: "Hip Thrust (Machine)",
            movementPattern: .hipThrust, swapPattern: "isolation",
            primaryMuscles: ["Glutes"],
            secondaryMuscles: [.init(muscle: "Hamstrings", weight: 0.5)],
            equipment: .machine, isCompound: true, stretchPosition: .shortened,
            jointStressTags: [],
            swapKeys: ["hip_thrust_barbell", "glute_bridge"],
            swapWarning: nil, variationOfKey: "hip_thrust_barbell",
            rank: 1, head: "extension", generatorPattern: "hip_thrust", sessionRestriction: .lowerOnly,
            headContributions: [
                .glutesMax: 1.0,
                .hamstringsHipExtension: 0.5,
                .vastusLateralis: 0.3
            ]),

        ExerciseDefinition(
            key: "glute_bridge", displayName: "Glute Bridge",
            movementPattern: .hipThrust, swapPattern: "isolation",
            primaryMuscles: ["Glutes"],
            secondaryMuscles: [.init(muscle: "Hamstrings", weight: 0.3)],
            equipment: .bodyweight, isCompound: false, stretchPosition: .shortened,
            jointStressTags: [],
            swapKeys: ["hip_thrust_barbell", "hip_thrust_machine"],
            swapWarning: nil, variationOfKey: "hip_thrust_barbell",
            rank: 4, head: "extension", generatorPattern: "hip_thrust", sessionRestriction: .lowerOnly,
            headContributions: [
                .glutesMax: 1.0,
                .hamstringsHipExtension: 0.5
            ]),

        ExerciseDefinition(
            key: "cable_kickback", displayName: "Cable Kickback",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Glutes"],
            secondaryMuscles: [.init(muscle: "Hamstrings", weight: 0.3)],
            equipment: .cable, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["machine_kickback"],
            swapWarning: nil, variationOfKey: nil,
            rank: 4, head: "extension", generatorPattern: "kickback", sessionRestriction: .lowerOnly,
            headContributions: [
                .glutesMax: 1.0,
                .hamstringsHipExtension: 0.3
            ]),

        ExerciseDefinition(
            key: "machine_kickback", displayName: "Machine Kickback",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Glutes"],
            secondaryMuscles: [.init(muscle: "Hamstrings", weight: 0.3)],
            equipment: .machine, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["cable_kickback"],
            swapWarning: nil, variationOfKey: "cable_kickback",
            rank: 4, head: "extension", generatorPattern: "kickback", sessionRestriction: .lowerOnly,
            headContributions: [
                .glutesMax: 1.0,
                .hamstringsHipExtension: 0.3
            ]),

        ExerciseDefinition(
            key: "abduction_machine", displayName: "Hip Abduction Machine",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Glutes"],
            secondaryMuscles: [],
            equipment: .machine, isCompound: false, stretchPosition: .mid,
            jointStressTags: [],
            swapKeys: ["cable_hip_abduction"],
            swapWarning: nil, variationOfKey: nil,
            rank: 3, head: "abduction", generatorPattern: "abduction", sessionRestriction: .lowerOnly,
            headContributions: [
                .glutesMedius: 1.0, .glutesMax: 0.3
            ]),

        ExerciseDefinition(
            key: "cable_hip_abduction", displayName: "Cable Hip Abduction",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Glutes"],
            secondaryMuscles: [],
            equipment: .cable, isCompound: false, stretchPosition: .mid,
            jointStressTags: [],
            swapKeys: ["abduction_machine"],
            swapWarning: nil, variationOfKey: "abduction_machine",
            rank: 3, head: "abduction", generatorPattern: "abduction", sessionRestriction: .lowerOnly,
            headContributions: [
                .glutesMedius: 1.0, .glutesMax: 0.3
            ]),

        ExerciseDefinition(
            key: "deadlift_sumo", displayName: "Sumo Deadlift",
            movementPattern: .hinge, swapPattern: "hip_hinge",
            primaryMuscles: ["Glutes", "Adductors"],
            secondaryMuscles: [.init(muscle: "Hamstrings", weight: 0.5), .init(muscle: "Quads", weight: 0.4)],
            equipment: .barbell, isCompound: true, stretchPosition: .lengthened,
            jointStressTags: ["low_back"],
            swapKeys: ["leg_press_wide", "rdl_barbell"],
            swapWarning: nil, variationOfKey: "deadlift_barbell",
            head: "extension", generatorPattern: "hinge", sessionRestriction: .lowerOnly,
            headContributions: [
                .glutesMax: 1.0,
                .hamstringsHipExtension: 0.6, .adductors: 0.6,
                .vastusLateralis: 0.5, .vastusMedialis: 0.5, .rectusFemoris: 0.3,
                .lowerBack: 0.7, .midBack: 0.5, .traps: 0.4, .lats: 0.4
            ]),

        ExerciseDefinition(
            key: "leg_press_wide", displayName: "Wide-Stance Leg Press",
            movementPattern: .squat, swapPattern: "knee_dominant",
            primaryMuscles: ["Glutes", "Adductors"],
            secondaryMuscles: [.init(muscle: "Quads", weight: 0.5), .init(muscle: "Hamstrings", weight: 0.3)],
            equipment: .machine, isCompound: true, stretchPosition: .lengthened,
            jointStressTags: ["knee"],
            swapKeys: ["deadlift_sumo"],
            swapWarning: nil, variationOfKey: "leg_press",
            head: "extension", generatorPattern: "press", sessionRestriction: .lowerOnly,
            headContributions: [
                .glutesMax: 1.0,
                .vastusLateralis: 0.7, .vastusMedialis: 0.8, .rectusFemoris: 0.4,
                .hamstringsHipExtension: 0.4, .adductors: 0.5
            ]),

        ExerciseDefinition(
            key: "frog_pump", displayName: "Frog Pump",
            movementPattern: .hipThrust, swapPattern: "isolation",
            primaryMuscles: ["Glutes"],
            secondaryMuscles: [],
            equipment: .bodyweight, isCompound: false, stretchPosition: .shortened,
            jointStressTags: [],
            swapKeys: ["glute_bridge"],
            swapWarning: nil, variationOfKey: nil,
            rank: 4, head: "extension", generatorPattern: "hip_thrust", sessionRestriction: .lowerOnly,
            headContributions: [
                .glutesMax: 1.0, .glutesMedius: 0.3
            ]),

        // ═══════════════════════════════════════
        // CALVES
        // ═══════════════════════════════════════

        ExerciseDefinition(
            key: "calf_raise_standing", displayName: "Standing Calf Raise",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Gastrocnemius"],
            secondaryMuscles: [.init(muscle: "Soleus", weight: 0.3)],
            equipment: .machine, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["calf_raise_leg_press", "calf_raise_smith", "calf_raise_single_leg"],
            swapWarning: nil, variationOfKey: nil,
            rank: 1, head: "gastro", generatorPattern: "calf_raise", sessionRestriction: .lowerOnly,
            headContributions: [
                .gastrocnemius: 1.0, .soleus: 0.4
            ]),

        ExerciseDefinition(
            key: "calf_raise_seated", displayName: "Seated Calf Raise",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Soleus"],
            secondaryMuscles: [.init(muscle: "Gastrocnemius", weight: 0.3)],
            equipment: .machine, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: [],
            swapWarning: "Knee-bent position isolates soleus — no direct equivalent. Do not swap to standing version.", variationOfKey: nil,
            head: "soleus", generatorPattern: "calf_raise", sessionRestriction: .lowerOnly,
            headContributions: [
                .soleus: 1.0, .gastrocnemius: 0.3
            ]),

        ExerciseDefinition(
            key: "calf_raise_leg_press", displayName: "Leg Press Calf Raise",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Gastrocnemius"],
            secondaryMuscles: [.init(muscle: "Soleus", weight: 0.3)],
            equipment: .machine, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["calf_raise_standing", "calf_raise_smith"],
            swapWarning: nil, variationOfKey: "calf_raise_standing",
            rank: 1, head: "gastro", generatorPattern: "calf_raise", sessionRestriction: .lowerOnly,
            headContributions: [
                .gastrocnemius: 0.9, .soleus: 0.5
            ]),

        ExerciseDefinition(
            key: "calf_raise_single_leg", displayName: "Single-Leg Calf Raise",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Gastrocnemius"],
            secondaryMuscles: [.init(muscle: "Soleus", weight: 0.3)],
            equipment: .bodyweight, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["calf_raise_standing"],
            swapWarning: nil, variationOfKey: "calf_raise_standing",
            rank: 3, head: "gastro", generatorPattern: "calf_raise", sessionRestriction: .lowerOnly,
            headContributions: [
                .gastrocnemius: 1.0, .soleus: 0.4
            ]),

        ExerciseDefinition(
            key: "calf_raise_donkey", displayName: "Donkey Calf Raise",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Gastrocnemius"],
            secondaryMuscles: [.init(muscle: "Soleus", weight: 0.3)],
            equipment: .machine, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["calf_raise_standing"],
            swapWarning: nil, variationOfKey: "calf_raise_standing",
            head: "gastro", generatorPattern: "calf_raise", sessionRestriction: .lowerOnly,
            headContributions: [
                .gastrocnemius: 1.0, .soleus: 0.4
            ]),

        ExerciseDefinition(
            key: "calf_raise_smith", displayName: "Smith Machine Calf Raise",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Gastrocnemius"],
            secondaryMuscles: [.init(muscle: "Soleus", weight: 0.3)],
            equipment: .machine, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["calf_raise_standing", "calf_raise_leg_press"],
            swapWarning: nil, variationOfKey: "calf_raise_standing",
            head: "gastro", generatorPattern: "calf_raise", sessionRestriction: .lowerOnly,
            headContributions: [
                .gastrocnemius: 1.0, .soleus: 0.4
            ]),

        ExerciseDefinition(
            key: "calf_raise_bodyweight", displayName: "Bodyweight Calf Raise",
            movementPattern: .isolation, swapPattern: "isolation",
            primaryMuscles: ["Gastrocnemius"],
            secondaryMuscles: [.init(muscle: "Soleus", weight: 0.3)],
            equipment: .bodyweight, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["calf_raise_standing"],
            swapWarning: nil, variationOfKey: "calf_raise_standing",
            rank: 3, head: "gastro", generatorPattern: "calf_raise", sessionRestriction: .lowerOnly,
            headContributions: [
                .gastrocnemius: 1.0, .soleus: 0.4
            ]),

        // ═══════════════════════════════════════
        // CORE
        // ═══════════════════════════════════════

        ExerciseDefinition(
            key: "cable_crunch", displayName: "Cable Crunch",
            movementPattern: .core, swapPattern: "core",
            primaryMuscles: ["Rectus Abdominis"],
            secondaryMuscles: [.init(muscle: "Obliques", weight: 0.3)],
            equipment: .cable, isCompound: false, stretchPosition: .mid,
            jointStressTags: [],
            swapKeys: ["hanging_leg_raise", "ab_wheel"],
            swapWarning: nil, variationOfKey: nil,
            generatorPattern: "core"),

        ExerciseDefinition(
            key: "hanging_leg_raise", displayName: "Hanging Leg Raise",
            movementPattern: .core, swapPattern: "core",
            primaryMuscles: ["Rectus Abdominis", "Hip Flexors"],
            secondaryMuscles: [.init(muscle: "Obliques", weight: 0.3)],
            equipment: .bodyweight, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["cable_crunch", "ab_wheel"],
            swapWarning: nil, variationOfKey: nil,
            generatorPattern: "core"),

        ExerciseDefinition(
            key: "ab_wheel", displayName: "Ab Wheel Rollout",
            movementPattern: .core, swapPattern: "core",
            primaryMuscles: ["Rectus Abdominis"],
            secondaryMuscles: [.init(muscle: "Lats", weight: 0.3), .init(muscle: "Obliques", weight: 0.3)],
            equipment: .other, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["cable_crunch", "hanging_leg_raise"],
            swapWarning: nil, variationOfKey: nil,
            generatorPattern: "core"),

        ExerciseDefinition(
            key: "plank", displayName: "Plank",
            movementPattern: .core, swapPattern: "core",
            primaryMuscles: ["Rectus Abdominis", "Obliques"],
            secondaryMuscles: [.init(muscle: "Lower Back", weight: 0.3)],
            equipment: .bodyweight, isCompound: false, stretchPosition: .mid,
            jointStressTags: [],
            swapKeys: ["dead_bug", "pallof_press"],
            swapWarning: nil, variationOfKey: nil,
            generatorPattern: "core"),

        ExerciseDefinition(
            key: "side_plank", displayName: "Side Plank",
            movementPattern: .core, swapPattern: "core",
            primaryMuscles: ["Obliques"],
            secondaryMuscles: [],
            equipment: .bodyweight, isCompound: false, stretchPosition: .mid,
            jointStressTags: [],
            swapKeys: ["pallof_press", "russian_twist"],
            swapWarning: nil, variationOfKey: nil,
            generatorPattern: "core"),

        ExerciseDefinition(
            key: "russian_twist", displayName: "Russian Twist",
            movementPattern: .core, swapPattern: "core",
            primaryMuscles: ["Obliques"],
            secondaryMuscles: [.init(muscle: "Rectus Abdominis", weight: 0.3)],
            equipment: .bodyweight, isCompound: false, stretchPosition: .mid,
            jointStressTags: [],
            swapKeys: ["side_plank", "landmine_twist"],
            swapWarning: nil, variationOfKey: nil,
            generatorPattern: "core"),

        ExerciseDefinition(
            key: "pallof_press", displayName: "Pallof Press",
            movementPattern: .core, swapPattern: "core",
            primaryMuscles: ["Obliques", "Transverse Abdominis"],
            secondaryMuscles: [],
            equipment: .cable, isCompound: false, stretchPosition: .mid,
            jointStressTags: [],
            swapKeys: ["side_plank", "russian_twist"],
            swapWarning: nil, variationOfKey: nil,
            generatorPattern: "core"),

        ExerciseDefinition(
            key: "dead_bug", displayName: "Dead Bug",
            movementPattern: .core, swapPattern: "core",
            primaryMuscles: ["Rectus Abdominis", "Transverse Abdominis"],
            secondaryMuscles: [],
            equipment: .bodyweight, isCompound: false, stretchPosition: .mid,
            jointStressTags: [],
            swapKeys: ["plank", "pallof_press"],
            swapWarning: nil, variationOfKey: nil,
            generatorPattern: "core"),

        ExerciseDefinition(
            key: "landmine_twist", displayName: "Landmine Twist",
            movementPattern: .core, swapPattern: "core",
            primaryMuscles: ["Obliques"],
            secondaryMuscles: [.init(muscle: "Shoulders", weight: 0.3)],
            equipment: .barbell, isCompound: false, stretchPosition: .mid,
            jointStressTags: [],
            swapKeys: ["russian_twist", "pallof_press"],
            swapWarning: nil, variationOfKey: nil,
            generatorPattern: "core"),

        // ═══════════════════════════════════════
        // HAMSTRINGS (Good Morning — also listed under Back, duplicated primary here)
        // ═══════════════════════════════════════

        ExerciseDefinition(
            key: "good_morning_hamstring", displayName: "Good Morning (Hamstring Focus)",
            movementPattern: .hinge, swapPattern: "hip_hinge",
            primaryMuscles: ["Hamstrings"],
            secondaryMuscles: [.init(muscle: "Lower Back", weight: 0.5), .init(muscle: "Glutes", weight: 0.5)],
            equipment: .barbell, isCompound: true, stretchPosition: .lengthened,
            jointStressTags: ["low_back"],
            swapKeys: ["rdl_barbell", "stiff_leg_deadlift"],
            swapWarning: nil, variationOfKey: "good_morning",
            rank: 3, head: "hip_hinge", generatorPattern: "hinge", sessionRestriction: .lowerOnly,
            headContributions: [
                .hamstringsHipExtension: 1.0,
                .glutesMax: 0.6,
                .lowerBack: 0.6
            ]),

        // ═══════════════════════════════════════
        // ADDITIONAL EXERCISES (machine variants & smith variants)
        // ═══════════════════════════════════════

        ExerciseDefinition(
            key: "machine_chest_press", displayName: "Machine Chest Press",
            movementPattern: .horizontalPush, swapPattern: "horizontal_push",
            primaryMuscles: ["Chest"],
            secondaryMuscles: [.init(muscle: "Triceps", weight: 0.5), .init(muscle: "Front Delts", weight: 0.3)],
            equipment: .machine, isCompound: true, stretchPosition: .mid,
            jointStressTags: [],
            swapKeys: ["bench_press_barbell", "bench_press_dumbbell", "bench_press_smith"],
            swapWarning: nil, variationOfKey: nil,
            head: "mid", generatorPattern: "horizontal_press",
            headContributions: [
                .chestMid: 1.0, .chestLower: 0.3,
                .tricepsLateral: 0.5, .tricepsMedial: 0.4, .tricepsLong: 0.3,
                .deltsFront: 0.4
            ]),

        ExerciseDefinition(
            key: "incline_machine_press", displayName: "Incline Machine Press",
            movementPattern: .horizontalPush, swapPattern: "horizontal_push_incline",
            primaryMuscles: ["Upper Chest"],
            secondaryMuscles: [.init(muscle: "Triceps", weight: 0.5), .init(muscle: "Front Delts", weight: 0.5)],
            equipment: .machine, isCompound: true, stretchPosition: .mid,
            jointStressTags: [],
            swapKeys: ["bench_press_incline_barbell", "bench_press_incline_dumbbell", "landmine_press"],
            swapWarning: nil, variationOfKey: nil,
            head: "upper", generatorPattern: "incline_press",
            headContributions: [
                .chestUpper: 1.0, .chestMid: 0.5,
                .deltsFront: 0.6,
                .tricepsLateral: 0.5, .tricepsMedial: 0.4, .tricepsLong: 0.4
            ]),

        ExerciseDefinition(
            key: "bench_press_incline_smith", displayName: "Smith Machine Incline Bench",
            movementPattern: .horizontalPush, swapPattern: "horizontal_push_incline",
            primaryMuscles: ["Upper Chest"],
            secondaryMuscles: [.init(muscle: "Triceps", weight: 0.5), .init(muscle: "Front Delts", weight: 0.5)],
            equipment: .machine, isCompound: true, stretchPosition: .mid,
            jointStressTags: ["shoulder"],
            swapKeys: ["bench_press_incline_barbell", "bench_press_incline_dumbbell", "incline_machine_press"],
            swapWarning: nil, variationOfKey: "bench_press_barbell",
            head: "upper", generatorPattern: "incline_press",
            headContributions: [
                .chestUpper: 1.0, .chestMid: 0.5,
                .deltsFront: 0.6,
                .tricepsLateral: 0.5, .tricepsMedial: 0.4, .tricepsLong: 0.4
            ]),

        ExerciseDefinition(
            key: "bench_press_decline_smith", displayName: "Smith Machine Decline Bench",
            movementPattern: .horizontalPush, swapPattern: "horizontal_push_decline",
            primaryMuscles: ["Lower Chest"],
            secondaryMuscles: [.init(muscle: "Triceps", weight: 0.5), .init(muscle: "Front Delts", weight: 0.3)],
            equipment: .machine, isCompound: true, stretchPosition: .shortened,
            jointStressTags: ["shoulder"],
            swapKeys: ["bench_press_decline_barbell", "bench_press_decline_dumbbell", "dips_chest"],
            swapWarning: nil, variationOfKey: "bench_press_barbell",
            head: "lower", generatorPattern: "decline_press",
            headContributions: [
                .chestLower: 1.0, .chestMid: 0.4,
                .tricepsLateral: 0.5, .tricepsMedial: 0.4, .tricepsLong: 0.4,
                .deltsFront: 0.3
            ]),

        ExerciseDefinition(
            key: "single_leg_leg_press", displayName: "Single-Leg Leg Press",
            movementPattern: .squat, swapPattern: "single_leg",
            primaryMuscles: ["Quads"],
            secondaryMuscles: [.init(muscle: "Glutes", weight: 0.5)],
            equipment: .machine, isCompound: true, stretchPosition: .lengthened,
            jointStressTags: ["knee"],
            swapKeys: ["bulgarian_split_squat", "lunge_dumbbell", "step_up"],
            swapWarning: nil, variationOfKey: nil,
            head: "compound", generatorPattern: "single_leg", sessionRestriction: .lowerOnly,
            headContributions: [
                .vastusLateralis: 1.0, .vastusMedialis: 1.0, .rectusFemoris: 0.6,
                .glutesMax: 0.6, .glutesMedius: 0.3,
                .hamstringsHipExtension: 0.3
            ]),

        ExerciseDefinition(
            key: "machine_dip", displayName: "Machine Dip",
            movementPattern: .horizontalPush, swapPattern: "tricep_compound",
            primaryMuscles: ["Triceps"],
            secondaryMuscles: [.init(muscle: "Chest", weight: 0.4), .init(muscle: "Front Delts", weight: 0.3)],
            equipment: .machine, isCompound: true, stretchPosition: .mid,
            jointStressTags: [],
            swapKeys: ["dips_tricep", "close_grip_bench", "jm_press"],
            swapWarning: nil, variationOfKey: nil,
            head: "lateral", generatorPattern: "tricep_compound",
            headContributions: [
                .tricepsLateral: 0.9, .tricepsMedial: 0.7, .tricepsLong: 0.5,
                .chestLower: 0.5, .chestMid: 0.4,
                .deltsFront: 0.4
            ]),

        ExerciseDefinition(
            key: "tricep_pushdown_machine", displayName: "Machine Triceps Pushdown",
            movementPattern: .isolation, swapPattern: "tricep_pushdown",
            primaryMuscles: ["Triceps"],
            secondaryMuscles: [],
            equipment: .machine, isCompound: false, stretchPosition: .shortened,
            jointStressTags: [],
            swapKeys: ["tricep_pushdown_cable", "tricep_pushdown_rope", "kickback_dumbbell"],
            swapWarning: nil, variationOfKey: nil,
            head: "lateral", generatorPattern: "tricep_push",
            headContributions: [
                .tricepsLateral: 1.0, .tricepsMedial: 0.9, .tricepsLong: 0.4
            ]),

        // ═══════════════════════════════════════
        // FUNDAMENTAL ADDITIONS
        // ═══════════════════════════════════════

        // ── Hamstrings (user-requested) ──
        ExerciseDefinition(
            key: "leg_curl_standing", displayName: "Standing Leg Curl Machine",
            movementPattern: .isolation, swapPattern: "hamstring_curl",
            primaryMuscles: ["Hamstrings"],
            secondaryMuscles: [],
            equipment: .machine, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["leg_curl_seated", "leg_curl_lying", "nordic_hamstring_curl"],
            swapWarning: nil, variationOfKey: nil,
            head: "knee_flexion", generatorPattern: "leg_curl", sessionRestriction: .lowerOnly,
            headContributions: [
                .hamstringsKneeFlexion: 1.0
            ]),

        ExerciseDefinition(
            key: "leg_curl_standing_single", displayName: "Single-Leg Standing Curl",
            movementPattern: .isolation, swapPattern: "hamstring_curl",
            primaryMuscles: ["Hamstrings"],
            secondaryMuscles: [],
            equipment: .machine, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["leg_curl_standing", "leg_curl_seated_single", "rdl_single_leg"],
            swapWarning: nil, variationOfKey: nil,
            head: "knee_flexion", generatorPattern: "leg_curl", sessionRestriction: .lowerOnly,
            headContributions: [
                .hamstringsKneeFlexion: 1.0
            ]),

        ExerciseDefinition(
            key: "leg_curl_seated_single", displayName: "Single-Leg Seated Leg Curl",
            movementPattern: .isolation, swapPattern: "hamstring_curl",
            primaryMuscles: ["Hamstrings"],
            secondaryMuscles: [],
            equipment: .machine, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["leg_curl_seated", "leg_curl_standing_single", "leg_curl_lying"],
            swapWarning: nil, variationOfKey: nil,
            head: "knee_flexion", generatorPattern: "leg_curl", sessionRestriction: .lowerOnly,
            headContributions: [
                .hamstringsKneeFlexion: 1.0, .hamstringsHipExtension: 0.3
            ]),

        // ── Quads (user-requested) ──
        ExerciseDefinition(
            key: "leg_extension_single", displayName: "Single-Leg Leg Extension",
            movementPattern: .isolation, swapPattern: "quad_isolation",
            primaryMuscles: ["Quads"],
            secondaryMuscles: [],
            equipment: .machine, isCompound: false, stretchPosition: .shortened,
            jointStressTags: ["knee"],
            swapKeys: ["leg_extension", "sissy_squat"],
            swapWarning: nil, variationOfKey: nil,
            head: "isolation", generatorPattern: "quad_isolation", sessionRestriction: .lowerOnly,
            headContributions: [
                .rectusFemoris: 1.0, .vastusLateralis: 0.8, .vastusMedialis: 0.8
            ]),

        ExerciseDefinition(
            key: "v_squat_machine", displayName: "V-Squat Machine",
            movementPattern: .squat, swapPattern: "squat",
            primaryMuscles: ["Quads"],
            secondaryMuscles: [.init(muscle: "Glutes", weight: 0.4)],
            equipment: .machine, isCompound: true, stretchPosition: .lengthened,
            jointStressTags: ["knee"],
            swapKeys: ["hack_squat", "leg_press", "pendulum_squat"],
            swapWarning: nil, variationOfKey: nil,
            head: "compound", generatorPattern: "squat", sessionRestriction: .lowerOnly,
            headContributions: [
                .vastusLateralis: 1.0, .vastusMedialis: 1.0, .rectusFemoris: 0.6,
                .glutesMax: 0.6
            ]),

        // ── Biceps ──
        ExerciseDefinition(
            key: "curl_ez_bar", displayName: "EZ-Bar Curl",
            movementPattern: .isolation, swapPattern: "curl",
            primaryMuscles: ["Biceps"],
            secondaryMuscles: [.init(muscle: "Brachialis", weight: 0.4)],
            equipment: .barbell, isCompound: false, stretchPosition: .mid,
            jointStressTags: [],
            swapKeys: ["curl_barbell", "curl_dumbbell", "curl_cable"],
            swapWarning: nil, variationOfKey: nil,
            rank: 1, head: "both", generatorPattern: "curl",
            headContributions: [
                .bicepsShort: 0.9, .bicepsLong: 0.7, .brachialis: 0.5
            ]),

        // ── Triceps ──
        ExerciseDefinition(
            key: "skullcrusher_ez_bar", displayName: "Skull Crusher (EZ-Bar)",
            movementPattern: .isolation, swapPattern: "tricep_overhead",
            primaryMuscles: ["Triceps"],
            secondaryMuscles: [],
            equipment: .barbell, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["skullcrusher_barbell", "skullcrusher_dumbbell", "tricep_overhead_cable"],
            swapWarning: nil, variationOfKey: nil,
            head: "long", generatorPattern: "tricep_extension",
            headContributions: [
                .tricepsLong: 1.0, .tricepsLateral: 0.7, .tricepsMedial: 0.6
            ]),

        ExerciseDefinition(
            key: "tricep_extension_machine", displayName: "Machine Tricep Extension",
            movementPattern: .isolation, swapPattern: "tricep_overhead",
            primaryMuscles: ["Triceps"],
            secondaryMuscles: [],
            equipment: .machine, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["tricep_overhead_cable", "skullcrusher_barbell", "tricep_overhead_dumbbell"],
            swapWarning: nil, variationOfKey: nil,
            head: "long", generatorPattern: "tricep_extension",
            headContributions: [
                .tricepsLong: 1.0, .tricepsLateral: 0.6, .tricepsMedial: 0.5
            ]),

        // ── Glutes ──
        ExerciseDefinition(
            key: "hip_thrust_dumbbell", displayName: "Dumbbell Hip Thrust",
            movementPattern: .hipThrust, swapPattern: "hip_thrust",
            primaryMuscles: ["Glutes"],
            secondaryMuscles: [.init(muscle: "Hamstrings", weight: 0.3)],
            equipment: .dumbbell, isCompound: true, stretchPosition: .shortened,
            jointStressTags: [],
            swapKeys: ["hip_thrust_barbell", "hip_thrust_machine", "glute_bridge"],
            swapWarning: nil, variationOfKey: nil,
            head: "extension", generatorPattern: "hip_thrust", sessionRestriction: .lowerOnly,
            headContributions: [
                .glutesMax: 1.0,
                .hamstringsHipExtension: 0.5
            ]),

        ExerciseDefinition(
            key: "adduction_machine", displayName: "Hip Adduction Machine",
            movementPattern: .isolation, swapPattern: "adduction",
            primaryMuscles: ["Adductors"],
            secondaryMuscles: [],
            equipment: .machine, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["cable_hip_abduction", "abduction_machine"],
            swapWarning: nil, variationOfKey: nil,
            head: "adduction", generatorPattern: "glute_isolation", sessionRestriction: .lowerOnly,
            headContributions: [
                .adductors: 1.0
            ]),

        // ── Chest ──
        ExerciseDefinition(
            key: "cable_fly_crossover", displayName: "Cable Crossover Fly",
            movementPattern: .horizontalPush, swapPattern: "horizontal_push",
            primaryMuscles: ["Chest"],
            secondaryMuscles: [.init(muscle: "Front Delts", weight: 0.2)],
            equipment: .cable, isCompound: false, stretchPosition: .lengthened,
            jointStressTags: [],
            swapKeys: ["cable_fly_neutral", "fly_dumbbell", "pec_deck"],
            swapWarning: nil, variationOfKey: nil,
            head: "mid", generatorPattern: "fly",
            headContributions: [
                .chestMid: 1.0, .chestLower: 0.5,
                .deltsFront: 0.3
            ]),

        // ── Shoulders ──
        ExerciseDefinition(
            key: "ohp_smith", displayName: "Smith Machine Overhead Press",
            movementPattern: .verticalPush, swapPattern: "overhead_press",
            primaryMuscles: ["Front Delts", "Mid Delts"],
            secondaryMuscles: [.init(muscle: "Triceps", weight: 0.5)],
            equipment: .machine, isCompound: true, stretchPosition: .mid,
            jointStressTags: ["shoulder"],
            swapKeys: ["ohp_barbell", "ohp_dumbbell", "shoulder_press_machine"],
            swapWarning: nil, variationOfKey: nil,
            head: "anterior", generatorPattern: "overhead_press",
            headContributions: [
                .deltsFront: 1.0, .deltsLateral: 0.5,
                .tricepsLateral: 0.5, .tricepsMedial: 0.4, .tricepsLong: 0.4,
                .traps: 0.3
            ]),

        // ── Back ──
        ExerciseDefinition(
            key: "row_cable_single_arm", displayName: "Single-Arm Cable Row",
            movementPattern: .horizontalPull, swapPattern: "horizontal_pull",
            primaryMuscles: ["Lats", "Mid Back"],
            secondaryMuscles: [.init(muscle: "Biceps", weight: 0.5), .init(muscle: "Rear Delts", weight: 0.3)],
            equipment: .cable, isCompound: true, stretchPosition: .mid,
            jointStressTags: [],
            swapKeys: ["row_cable_narrow", "row_dumbbell", "row_meadows"],
            swapWarning: nil, variationOfKey: nil,
            head: "thickness", generatorPattern: "horizontal_row",
            headContributions: [
                .lats: 1.0, .midBack: 0.8, .rearDelts: 0.4,
                .bicepsLong: 0.5, .bicepsShort: 0.4, .brachialis: 0.4
            ]),

        // ── Traps ──
        ExerciseDefinition(
            key: "farmer_carry", displayName: "Farmer's Carry",
            movementPattern: .carry, swapPattern: "carry",
            primaryMuscles: ["Upper Traps"],
            secondaryMuscles: [.init(muscle: "Forearms", weight: 0.5)],
            equipment: .dumbbell, isCompound: true, stretchPosition: .shortened,
            jointStressTags: [],
            swapKeys: ["shrug_dumbbell", "shrug_barbell"],
            swapWarning: nil, variationOfKey: nil,
            head: "trap", generatorPattern: "carry",
            headContributions: [
                .traps: 0.8, .lowerBack: 0.3
            ]),

        // ── Core ──
        ExerciseDefinition(
            key: "wood_chop_cable", displayName: "Cable Wood Chop",
            movementPattern: .core, swapPattern: "core",
            primaryMuscles: ["Obliques"],
            secondaryMuscles: [.init(muscle: "Rectus Abdominis", weight: 0.2)],
            equipment: .cable, isCompound: false, stretchPosition: .mid,
            jointStressTags: [],
            swapKeys: ["pallof_press", "russian_twist"],
            swapWarning: nil, variationOfKey: nil,
            generatorPattern: "core"),
    ]
}
