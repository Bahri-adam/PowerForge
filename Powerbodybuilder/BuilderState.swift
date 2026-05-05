import Foundation
import SwiftData

// ═══════════════════════════════════════════
// PROGRAM BUILDER V2 — State Model
// Single source of truth while builder is open.
// ═══════════════════════════════════════════

enum BuilderMode: String, Codable, CaseIterable {
    case assisted = "Assisted"
    case fromScratch = "From Scratch"
}

enum DeloadPlacement: Codable, Equatable {
    case afterEveryBlock
    case manual
    case none

    var label: String {
        switch self {
        case .afterEveryBlock: return "After Every Block"
        case .manual:          return "Manual"
        case .none:            return "None"
        }
    }
}

enum RotationRule: String, Codable, CaseIterable {
    case keepAll = "Keep All"
    case rotateT2T3 = "Rotate T2/T3"
    case rotateAll = "Rotate All"

    var detail: String {
        switch self {
        case .keepAll:    return "Same exercises every block"
        case .rotateT2T3: return "T1 stays, accessories rotate"
        case .rotateAll:  return "Everything rotates between blocks"
        }
    }
}

// ═══════════════════════════════════════════
// BUILDER BLOCK
// ═══════════════════════════════════════════

struct BuilderBlock: Identifiable, Codable {
    let id: UUID
    var blockType: BlockType
    var trainingWeeks: Int
    var includeDeload: Bool
    var rotationRule: RotationRule

    var totalLength: Int { trainingWeeks + (includeDeload ? 1 : 0) }

    init(blockType: BlockType = .accumulation, trainingWeeks: Int = 5,
         includeDeload: Bool = true, rotationRule: RotationRule = .rotateT2T3) {
        self.id = UUID()
        self.blockType = blockType
        self.trainingWeeks = trainingWeeks
        self.includeDeload = includeDeload
        self.rotationRule = rotationRule
    }
}

// ═══════════════════════════════════════════
// BUILDER SESSION
// ═══════════════════════════════════════════

struct BuilderSession: Identifiable, Codable {
    let id: UUID
    var label: String
    var sessionType: SessionType
    var exercises: [BuilderExerciseV2]
    var isUserModified: Bool

    init(label: String, sessionType: SessionType, exercises: [BuilderExerciseV2] = []) {
        self.id = UUID()
        self.label = label
        self.sessionType = sessionType
        self.exercises = exercises
        self.isUserModified = false
    }
}

// ═══════════════════════════════════════════
// BUILDER EXERCISE V2
// ═══════════════════════════════════════════

struct BuilderExerciseV2: Identifiable, Codable {
    let id: UUID
    var exerciseKey: String
    var displayName: String
    var muscleGroup: String  // normalized primary muscle
    var tier: ExerciseTier
    var targetSets: Int
    var targetRepsLow: Int
    var targetRepsHigh: Int
    var targetRPE: Double
    var restSeconds: Int
    var isLocked: Bool  // if true, never rotated across blocks

    init(exerciseKey: String, displayName: String, muscleGroup: String = "",
         tier: ExerciseTier = .tier2, targetSets: Int = 3,
         targetRepsLow: Int = 8, targetRepsHigh: Int = 12,
         targetRPE: Double = 7.5, restSeconds: Int = 150, isLocked: Bool = false) {
        self.id = UUID()
        self.exerciseKey = exerciseKey
        self.displayName = displayName
        self.muscleGroup = muscleGroup
        self.tier = tier
        self.targetSets = targetSets
        self.targetRepsLow = targetRepsLow
        self.targetRepsHigh = targetRepsHigh
        self.targetRPE = targetRPE
        self.restSeconds = restSeconds
        self.isLocked = isLocked
    }
}

// ═══════════════════════════════════════════
// BUILDER ANALYTICS
// ═══════════════════════════════════════════

struct BuilderWarning: Identifiable {
    let id = UUID()
    let severity: WarningSeverity
    let message: String
}

enum WarningSeverity { case info, caution, error }

struct BuilderAnalytics {
    let volumePerMuscle: [String: Int]
    let frequencyPerMuscle: [String: Int]
    let sessionDurations: [UUID: Int]
    let totalWeeklySets: Int
    let warnings: [BuilderWarning]
}

// ═══════════════════════════════════════════
// BUILDER STATE (Observable)
// ═══════════════════════════════════════════

@Observable
final class ProgramBuilderState {
    // ── Identity ──
    var programName: String = ""
    var mode: BuilderMode = .assisted

    // ── Global Config ──
    var daysPerWeek: Int = 4
    var goal: GoalType = .hypertrophy
    var experience: ExperienceLevel = .intermediate
    var calorieContext: CalorieContext = .surplus
    var muscleTiers: [String: MuscleTier] = [:]
    var equipment: Set<EquipmentType> = [.barbell, .dumbbell, .cable, .machine, .bodyweight]
    var sessionDurationTarget: Int = 90

    // ── Block Architecture ──
    var blocks: [BuilderBlock] = [BuilderBlock()]
    var deloadPlacement: DeloadPlacement = .afterEveryBlock

    // ── Sessions ──
    var sessions: [BuilderSession] = []

    // ── Navigation ──
    var activeSection: BuilderSection = .split
    var activeSessionIndex: Int = 0

    // ── Computed ──
    var totalWeeks: Int { blocks.reduce(0) { $0 + $1.totalLength } }

    var analytics: BuilderAnalytics {
        BuilderAnalyticsEngine.compute(sessions: sessions, experience: experience,
                                        muscleTiers: muscleTiers, calorieContext: calorieContext)
    }

    // ── Seed from profile ──
    func seedFromProfile(_ profile: UserProfile) {
        goal = profile.goal
        experience = profile.experience
        daysPerWeek = profile.daysPerWeek
        calorieContext = profile.calorieContext
        muscleTiers = profile.muscleTiers
    }

    // ── Assisted mode: generate suggestions ──
    func regenerateSuggestions() {
        guard mode == .assisted else { return }

        // Generate split
        let split = ProgramGenerator.resolveSplitStructure(
            daysPerWeek: daysPerWeek, goal: goal,
            priorityMuscles: muscleTiers.filter { $0.value == .priority }.map { $0.key })

        // Generate block sequence
        if blocks.count <= 1 {
            blocks = defaultBlockSequence()
        }

        // Generate sessions (only for non-user-modified ones)
        let upperSet: Set<String> = ["Chest", "Back", "Delts", "Triceps", "Biceps"]
        let lowerSet: Set<String> = ["Quads", "Hamstrings", "Glutes", "Calves"]
        var allSeenKeys: [String: Set<String>] = [:]
        var catSeen: [String: Int] = [:]

        var newSessions: [BuilderSession] = []

        for day in split where day.sessionType != .rest {
            // Check if user already modified this session
            if let existing = sessions.first(where: { $0.sessionType == day.sessionType && $0.isUserModified }) {
                newSessions.append(existing)
                continue
            }

            let ms = Set(day.primaryMuscles)
            let cat = ms.isSubset(of: Set(["Chest","Delts","Triceps"])) ? "push" :
                      ms.isSubset(of: Set(["Back","Biceps"])) ? "pull" :
                      ms.isSubset(of: lowerSet) ? "legs" :
                      ms.isSubset(of: upperSet) ? "upper" : "fullbody"
            let occ = catSeen[cat, default: 0]; catSeen[cat, default: 0] += 1
            let isB = occ > 0
            let ctx: ProgramGenerator.SessionContext =
                ms.isSubset(of: upperSet) ? .upper : (ms.isSubset(of: lowerSet) ? .lower : .fullbody)

            var exercises: [BuilderExerciseV2] = []

            for muscle in day.primaryMuscles {
                let freq = split.filter { $0.primaryMuscles.contains(muscle) }.count
                let target = ProgramGenerator.resolveWeeklySetTarget(
                    muscle: muscle, week: 1, blockType: .accumulation,
                    muscleTier: muscleTiers[muscle] ?? .neutral,
                    experience: experience, calorieContext: calorieContext, calibration: nil)

                let base = target / max(1, freq)
                let rem = target % max(1, freq)
                let sets = isB ? base : base + rem
                guard sets >= 2 else { continue }

                let usedKeys = allSeenKeys[muscle] ?? []
                let slots = ProgramGenerator.selectExercisesForMuscle(
                    muscle: muscle, setsNeeded: sets, muscleTier: muscleTiers[muscle] ?? .neutral,
                    goal: goal, equipment: equipment, usedKeys: usedKeys,
                    blockNumber: 0, isSecondarySession: isB, sessionsPerWeek: freq, sessionContext: ctx)

                for slot in slots {
                    allSeenKeys[muscle, default: []].insert(slot.exerciseKey)
                    let def = ExerciseDictionary.all[slot.exerciseKey]
                    exercises.append(BuilderExerciseV2(
                        exerciseKey: slot.exerciseKey,
                        displayName: def?.displayName ?? slot.exerciseKey,
                        muscleGroup: muscle,
                        tier: slot.exerciseTier,
                        targetSets: slot.sets,
                        targetRepsLow: slot.repsLow,
                        targetRepsHigh: slot.repsHigh,
                        targetRPE: 7.5,
                        restSeconds: slot.restSeconds
                    ))
                }
            }

            // Sort by tier
            exercises.sort { $0.tier.sortValue < $1.tier.sortValue }
            newSessions.append(BuilderSession(label: day.label, sessionType: day.sessionType, exercises: exercises))
        }

        sessions = newSessions
    }

    private func defaultBlockSequence() -> [BuilderBlock] {
        let isHyp = goal == .hypertrophy || goal == .recomp
        let bl = goal == .recomp ? 3 : (experience == .beginner || experience == .intermediate ? 5 : 4)

        if isHyp {
            return [
                BuilderBlock(blockType: .accumulation, trainingWeeks: bl),
                BuilderBlock(blockType: .reaccumulation, trainingWeeks: bl)
            ]
        }
        switch goal {
        case .strength:
            return [
                BuilderBlock(blockType: .accumulation, trainingWeeks: bl),
                BuilderBlock(blockType: .intensification, trainingWeeks: bl),
                BuilderBlock(blockType: .peak, trainingWeeks: max(2, bl - 1))
            ]
        case .powerbuilding:
            return [
                BuilderBlock(blockType: .accumulation, trainingWeeks: bl),
                BuilderBlock(blockType: .intensification, trainingWeeks: bl),
                BuilderBlock(blockType: .reaccumulation, trainingWeeks: bl)
            ]
        default:
            return [BuilderBlock(blockType: .accumulation, trainingWeeks: bl)]
        }
    }
}

// ═══════════════════════════════════════════
// BUILDER SECTION ENUM
// ═══════════════════════════════════════════

enum BuilderSection: String, CaseIterable {
    case split = "Split"
    case exercises = "Exercises"
    case blocks = "Blocks"
    case analytics = "Analytics"
    case review = "Review"
}

// ═══════════════════════════════════════════
// ANALYTICS ENGINE
// ═══════════════════════════════════════════

struct BuilderAnalyticsEngine {
    static func compute(sessions: [BuilderSession], experience: ExperienceLevel,
                        muscleTiers: [String: MuscleTier], calorieContext: CalorieContext) -> BuilderAnalytics {
        var volume: [String: Int] = [:]
        var frequency: [String: Set<UUID>] = [:]
        var durations: [UUID: Int] = [:]
        var warnings: [BuilderWarning] = []

        for session in sessions {
            var sessionSets = 0
            for ex in session.exercises {
                let muscle = ex.muscleGroup
                if !muscle.isEmpty {
                    volume[muscle, default: 0] += ex.targetSets
                    frequency[muscle, default: []].insert(session.id)
                }
                sessionSets += ex.targetSets
            }
            let avgRest = session.exercises.isEmpty ? 120 :
                session.exercises.reduce(0) { $0 + $1.restSeconds } / session.exercises.count
            durations[session.id] = sessionSets * (45 + avgRest) / 60

            if sessionSets > 24 {
                warnings.append(BuilderWarning(severity: .caution,
                    message: "\(session.label) has \(sessionSets) sets — consider splitting"))
            }
            if session.exercises.isEmpty {
                warnings.append(BuilderWarning(severity: .info,
                    message: "\(session.label) has no exercises"))
            }
        }

        // Check volume zones
        for muscle in ExerciseDictionary.trackingMuscles {
            let sets = volume[muscle] ?? 0
            let tier = muscleTiers[muscle] ?? .neutral
            let mev = VolumeLandmark.effectiveMEV(muscle: muscle, experience: experience, tier: tier)
            let mrv = VolumeLandmark.effectiveMRV(muscle: muscle, experience: experience, tier: tier, calorieContext: calorieContext)

            if sets == 0 {
                warnings.append(BuilderWarning(severity: .caution,
                    message: "\(muscle) has 0 weekly sets"))
            } else if sets < mev {
                warnings.append(BuilderWarning(severity: .info,
                    message: "\(muscle) below MEV (\(sets)/\(mev) sets)"))
            } else if sets > mrv {
                warnings.append(BuilderWarning(severity: .error,
                    message: "\(muscle) exceeds MRV (\(sets)/\(mrv) sets)"))
            }
        }

        let freqMap = frequency.mapValues { $0.count }
        let totalSets = volume.values.reduce(0, +)

        return BuilderAnalytics(volumePerMuscle: volume, frequencyPerMuscle: freqMap,
                                sessionDurations: durations, totalWeeklySets: totalSets, warnings: warnings)
    }
}
