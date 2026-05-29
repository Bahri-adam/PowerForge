import Foundation

// ═══════════════════════════════════════════
// MUSCLE HEADS
// Segmented breakdown of the canonical 9 tracking muscles into their
// functional/anatomical heads. Used in Advanced density to surface
// per-head volume tracking; aggregated to the canonical 9 for
// minimal/standard density and for all engine code.
//
// Adding a new head: add the case, add to `parentMuscle`, add to
// `displayName`. Then optionally annotate ExerciseDefinition entries
// with `headContributions: [MuscleHead: Double]`.
// ═══════════════════════════════════════════

enum MuscleHead: String, Codable, CaseIterable, Hashable {
    // Chest
    case chestUpper        = "chest_upper"
    case chestMid          = "chest_mid"
    case chestLower        = "chest_lower"

    // Back
    case lats              = "lats"
    case midBack           = "mid_back"
    case traps             = "traps"
    case lowerBack         = "lower_back"
    case rearDelts         = "rear_delts"     // part of Delts — rear-delt flyes/face pulls and rows' rear-delt portion credit Delts (matches normalizeMuscle "Rear Delts" → Delts)

    // Delts (anterior + lateral; rear is grouped under Back above)
    case deltsFront        = "delts_front"
    case deltsLateral      = "delts_lateral"

    // Quads
    case rectusFemoris     = "rectus_femoris"
    case vastusLateralis   = "vastus_lateralis"
    case vastusMedialis    = "vastus_medialis"

    // Hamstrings (grouped by function rather than individual muscle)
    case hamstringsKneeFlexion = "hams_knee_flexion"   // biceps femoris short head emphasis (curls)
    case hamstringsHipExtension = "hams_hip_extension" // long head + semi-* (hinges)
    case adductors = "adductors"                       // inner thigh — tracked under Hamstrings (adductor magnus is a hip extensor); fed by hip adduction work

    // Glutes
    case glutesMax         = "glutes_max"
    case glutesMedius      = "glutes_medius"

    // Calves
    case gastrocnemius     = "gastrocnemius"
    case soleus            = "soleus"

    // Biceps
    case bicepsLong        = "biceps_long"
    case bicepsShort       = "biceps_short"
    case brachialis        = "brachialis"

    // Triceps
    case tricepsLong       = "triceps_long"
    case tricepsLateral    = "triceps_lateral"
    case tricepsMedial     = "triceps_medial"

    /// Maps to one of the canonical 9 tracking muscles. Used for backward-
    /// compatible volume aggregation.
    var parentMuscle: String {
        switch self {
        case .chestUpper, .chestMid, .chestLower:
            return "Chest"
        case .lats, .midBack, .traps, .lowerBack:
            return "Back"
        case .deltsFront, .deltsLateral, .rearDelts:
            return "Delts"
        case .rectusFemoris, .vastusLateralis, .vastusMedialis:
            return "Quads"
        case .hamstringsKneeFlexion, .hamstringsHipExtension, .adductors:
            return "Hamstrings"
        case .glutesMax, .glutesMedius:
            return "Glutes"
        case .gastrocnemius, .soleus:
            return "Calves"
        case .bicepsLong, .bicepsShort, .brachialis:
            return "Biceps"
        case .tricepsLong, .tricepsLateral, .tricepsMedial:
            return "Triceps"
        }
    }

    var displayName: String {
        switch self {
        case .chestUpper:        return "Upper Chest"
        case .chestMid:          return "Mid Chest"
        case .chestLower:        return "Lower Chest"
        case .lats:              return "Lats"
        case .midBack:           return "Mid Back"
        case .traps:             return "Traps"
        case .lowerBack:         return "Lower Back"
        case .rearDelts:         return "Rear Delts"
        case .deltsFront:        return "Front Delts"
        case .deltsLateral:      return "Side Delts"
        case .rectusFemoris:     return "Rectus Femoris"
        case .vastusLateralis:   return "Vastus Lateralis"
        case .vastusMedialis:    return "Vastus Medialis (VMO)"
        case .hamstringsKneeFlexion:  return "Hams (Knee Flexion)"
        case .hamstringsHipExtension: return "Hams (Hip Extension)"
        case .adductors:         return "Adductors"
        case .glutesMax:         return "Glute Max"
        case .glutesMedius:      return "Glute Medius (Abduction)"
        case .gastrocnemius:     return "Gastrocnemius"
        case .soleus:            return "Soleus"
        case .bicepsLong:        return "Biceps Long Head"
        case .bicepsShort:       return "Biceps Short Head"
        case .brachialis:        return "Brachialis"
        case .tricepsLong:       return "Triceps Long Head"
        case .tricepsLateral:    return "Triceps Lateral Head"
        case .tricepsMedial:     return "Triceps Medial Head"
        }
    }

    /// Short plain-English label (~12 char max so it fits in the head row
    /// without truncating). Describes WHERE the head sits or what BUILDS it,
    /// not the anatomical name.
    var laymanName: String {
        switch self {
        case .chestUpper:        return "upper chest"
        case .chestMid:          return "mid chest"
        case .chestLower:        return "lower chest"
        case .lats:              return "lats"
        case .midBack:           return "mid back"
        case .traps:             return "traps"
        case .lowerBack:         return "lower back"
        case .rearDelts:         return "rear delts"
        case .deltsFront:        return "front delts"
        case .deltsLateral:      return "side delts"
        // User's mental model — anatomical names map cleanly to "where it
        // sits on the leg" rather than direction terms.
        case .rectusFemoris:     return "middle quad"
        case .vastusLateralis:   return "outer quad"
        case .vastusMedialis:    return "inner quad"
        // Hamstrings split by function/exercise rather than anatomy. The
        // knee-flexion fibers ARE biased lower on the leg (built by curls);
        // the hip-extension fibers sit higher (built by RDLs/hinges).
        case .hamstringsKneeFlexion:  return "lower hams"
        case .hamstringsHipExtension: return "upper hams"
        case .adductors:         return "inner thigh"
        case .glutesMax:         return "glute max"
        case .glutesMedius:      return "side glute / abduction"
        case .gastrocnemius:     return "upper calf"
        case .soleus:            return "lower calf"
        case .bicepsLong:        return "outer biceps"
        case .bicepsShort:       return "inner biceps"
        // Brachialis is hard to name without lying. Sits between biceps and
        // triceps on the outside of the upper arm; visible as the "secondary"
        // bulge below the biceps peak when flexed.
        case .brachialis:        return "brachialis"
        case .tricepsLong:       return "long tricep"
        case .tricepsLateral:    return "outer tricep"
        case .tricepsMedial:     return "inner tricep"
        }
    }

    /// Returns true when the layman name differs meaningfully from the
    /// technical display name. Used to decide whether to show both
    /// (e.g. "Outer Quad" / "vastus lateralis") or just one.
    var laymanDiffersFromDisplay: Bool {
        laymanName.lowercased() != displayName.lowercased()
    }

    /// All heads belonging to a given canonical muscle. Used by the
    /// Advanced-density MuscleCoverageCard expansion view.
    static func heads(of muscle: String) -> [MuscleHead] {
        Self.allCases.filter { $0.parentMuscle == muscle }
    }
}

extension String {
    /// Capitalizes only the first character — preserves the rest of the
    /// string as-is. Useful for sentence-cased label text where Swift's
    /// `capitalized` would over-capitalize each word.
    var capitalizingFirst: String {
        guard let first = first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
