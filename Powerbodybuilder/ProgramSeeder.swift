import SwiftData
import Foundation

// ═══════════════════════════════════════════
// PROGRAM SEEDER  v2
// Seeds programId = 1 (Powerbuilding / DUP) — 24 weeks
//
// 4-day Upper/Lower split:
//   A = Heavy Upper       — bench (main), OHP, barbell row, pulldown, tricep pushdown, barbell curl
//   B = Heavy Lower       — squat (main), deadlift, lying leg curl, leg extension
//   C = Hypertrophy Upper — incline DB press (main), cable fly, DB row, face pull, laterals, overhead tricep, hammer curl
//   D = Hypertrophy Lower — RDL (main), hip thrust, leg press, seated leg curl, calf raise
//
// Periodization:
//   Block 1 (Weeks 1–8):   Accumulation    — RPE 7–7.5, volume builds, Week 4 deload
//   Block 2 (Weeks 9–16):  Intensification — RPE 8–8.5, load climbs, Week 12 deload
//   Block 3 (Weeks 17–24): Peaking         — RPE 8.5–9+, volume drops, Week 20 deload, Week 24 testing
//
// Key design decisions:
//   1. HYPERTROPHY LAG: C/D sessions use a separate resolver (~one sub-phase behind A/B).
//      During peaking weeks, hypertrophy work sits at late-intensification RPE.
//      Rationale: stacking peak-RPE hypertrophy volume with near-maximal strength work
//      accumulates fatigue precisely when heavy session quality matters most.
//
//   2. WEEK 24 C/D = MOVEMENT PREP: Low load, low RPE, no real stimulus.
//      Testing week is entirely about fatigue management.
//
//   3. B4 = LEG EXTENSION, NOT LEG PRESS: Leg press lives in D3 (hypertrophy lower).
//      Identical exerciseKey across slots conflates ProgressionState lookups until
//      RPEEngine scopes progression by slotId rather than exerciseKey alone.
//      Leg extension is a valid quad accessory here and keeps the keys distinct.
//
//   4. VERSIONED RE-SEED: Bump `currentSeedVersion` to push updated programming to
//      existing installs. Old template + slots are deleted and replaced.
//
// slotId convention: "[SessionLetter][SlotNumber]" — e.g. "A1" = Heavy Upper slot 1
// ═══════════════════════════════════════════

enum ProgramSeeder {

    static let programId          = 1
    static let currentSeedVersion = 3   // ← bump to trigger re-seed for existing users

    // ── Public entry point ──────────────────────────────────────────────────

    /// Call once at startup, after preloadExercisesIfNeeded.
    /// Idempotent — skips if ProgramTemplate.version already matches currentSeedVersion.
    /// Deletes stale template + slots and re-seeds if a lower version is found.
    static func seedPowerbuildingProgram(context: ModelContext) {

        var tDesc = FetchDescriptor<ProgramTemplate>(
            predicate: #Predicate { $0.programId == 1 }
        )
        tDesc.fetchLimit = 1
        let existingTemplates = (try? context.fetch(tDesc)) ?? []

        if let existing = existingTemplates.first {
            guard existing.version < currentSeedVersion else { return }
            // Stale — purge
            context.delete(existing)
            let slotDesc = FetchDescriptor<ProgramSessionTemplate>(
                predicate: #Predicate { $0.programId == 1 }
            )
            let staleSlots = (try? context.fetch(slotDesc)) ?? []
            for s in staleSlots { context.delete(s) }
        }

        let template = ProgramTemplate(
            programId: programId,
            name: "Powerbuilding (DUP)",
            version: currentSeedVersion,
            durationWeeks: 24,
            sessionTypes: [.heavyUpper, .heavyLower, .hypertrophyUpper, .hypertrophyLower],
            scheduleOptions: ["Mon/Tue/Thu/Fri", "Mon/Wed/Fri/Sat"]
        )
        context.insert(template)

        for slot in buildAllSlots() { context.insert(slot) }
        try? context.save()
    }

    // ── Top-level builder ────────────────────────────────────────────────────

    private static func buildAllSlots() -> [ProgramSessionTemplate] {
        var all: [ProgramSessionTemplate] = []
        for week in 1...24 {
            let sp = strengthParams(week: week)
            let hp = hypertrophyParams(week: week)
            all += heavyUpperSlots(week: week, p: sp)
            all += heavyLowerSlots(week: week, p: sp)
            all += hypertrophyUpperSlots(week: week, p: hp)
            all += hypertrophyLowerSlots(week: week, p: hp)
        }
        return all
    }

    // ═══════════════════════════════════════════════════════════════════════
    // BLOCK PARAMS — two separate structs, two separate resolvers
    // ═══════════════════════════════════════════════════════════════════════

    struct StrengthParams {
        let isDeload: Bool
        let isTesting: Bool
        let mainSets: Int
        let mainRepsLow: Int
        let mainRepsHigh: Int
        let mainRPE: Double
        let mainRest: Int
        let suppSets: Int
        let suppRepsLow: Int
        let suppRepsHigh: Int
        let suppRPE: Double
        let suppRest: Int
        let accSets: Int
        let accRepsLow: Int
        let accRepsHigh: Int
        let accRPE: Double
        let accRest: Int
    }

    struct HypertrophyParams {
        let isDeload: Bool
        let isMovementPrep: Bool
        let mainSets: Int
        let mainRepsLow: Int
        let mainRepsHigh: Int
        let mainRPE: Double
        let mainRest: Int
        let accSets: Int
        let accRepsLow: Int
        let accRepsHigh: Int
        let accRPE: Double
        let accRest: Int
    }

    // ── Strength resolver (drives A + B) ────────────────────────────────────

    private static func strengthParams(week: Int) -> StrengthParams {

        // Block 1 — Accumulation (Weeks 1–8)
        if week <= 8 {
            if week == 4 {  // Deload
                return StrengthParams(
                    isDeload: true, isTesting: false,
                    mainSets: 2, mainRepsLow: 5, mainRepsHigh: 5, mainRPE: 6.0, mainRest: 180,
                    suppSets: 2, suppRepsLow: 8, suppRepsHigh: 10, suppRPE: 6.0, suppRest: 150,
                    accSets: 2, accRepsLow: 10, accRepsHigh: 12, accRPE: 6.0, accRest: 90
                )
            }
            let post = week > 4
            return StrengthParams(
                isDeload: false, isTesting: false,
                mainSets: post ? 4 : 3, mainRepsLow: 4, mainRepsHigh: 6,
                mainRPE: post ? 7.5 : 7.0, mainRest: 240,
                suppSets: 3, suppRepsLow: 8, suppRepsHigh: 10, suppRPE: 7.0, suppRest: 180,
                accSets: 3, accRepsLow: 10, accRepsHigh: 12, accRPE: 7.0, accRest: 120
            )
        }

        // Block 2 — Intensification (Weeks 9–16)
        if week <= 16 {
            if week == 12 {  // Deload
                return StrengthParams(
                    isDeload: true, isTesting: false,
                    mainSets: 2, mainRepsLow: 3, mainRepsHigh: 4, mainRPE: 6.5, mainRest: 240,
                    suppSets: 2, suppRepsLow: 6, suppRepsHigh: 8, suppRPE: 6.5, suppRest: 180,
                    accSets: 2, accRepsLow: 10, accRepsHigh: 12, accRPE: 6.0, accRest: 90
                )
            }
            let post = week > 12
            return StrengthParams(
                isDeload: false, isTesting: false,
                mainSets: 4, mainRepsLow: 3, mainRepsHigh: 5,
                mainRPE: post ? 8.5 : 8.0, mainRest: 270,
                suppSets: 3, suppRepsLow: 6, suppRepsHigh: 8,
                suppRPE: post ? 8.0 : 7.5, suppRest: 210,
                accSets: 3, accRepsLow: 8, accRepsHigh: 12, accRPE: 7.5, accRest: 120
            )
        }

        // Block 3 — Peaking (Weeks 17–24)
        if week == 20 {  // Deload
            return StrengthParams(
                isDeload: true, isTesting: false,
                mainSets: 2, mainRepsLow: 2, mainRepsHigh: 3, mainRPE: 6.5, mainRest: 300,
                suppSets: 2, suppRepsLow: 5, suppRepsHigh: 6, suppRPE: 6.5, suppRest: 240,
                accSets: 2, accRepsLow: 10, accRepsHigh: 12, accRPE: 6.0, accRest: 90
            )
        }
        if week == 24 {  // 1RM Testing
            return StrengthParams(
                isDeload: false, isTesting: true,
                mainSets: 1, mainRepsLow: 1, mainRepsHigh: 1, mainRPE: 9.5, mainRest: 360,
                suppSets: 2, suppRepsLow: 3, suppRepsHigh: 3, suppRPE: 8.5, suppRest: 300,
                accSets: 2, accRepsLow: 6, accRepsHigh: 8, accRPE: 7.0, accRest: 120
            )
        }
        // Weeks 17–19, 21–23
        let late = week >= 21
        return StrengthParams(
            isDeload: false, isTesting: false,
            mainSets: late ? 3 : 4, mainRepsLow: 2, mainRepsHigh: 4,
            mainRPE: late ? 9.0 : 8.5, mainRest: 300,
            suppSets: 3, suppRepsLow: 4, suppRepsHigh: 6,
            suppRPE: late ? 8.5 : 8.0, suppRest: 240,
            accSets: 3, accRepsLow: 8, accRepsHigh: 10, accRPE: 7.5, accRest: 120
        )
    }

    // ── Hypertrophy resolver (drives C + D) — intentionally lags strength ────
    //
    // Lag map:
    //   Strength accumulation (1–3, 5–8)  → Hyp: accumulation (same — fatigue tolerance fresh early)
    //   Strength deloads (4, 12, 20)      → Hyp: always deload — match deloads unconditionally
    //   Strength intensification (9–11)   → Hyp: late-accumulation RPE (~7.0–7.5)
    //   Strength intensification (13–16)  → Hyp: early-intensification RPE (~7.5–8.0)
    //   Strength peaking (17–19, 21–23)   → Hyp: late-intensification RPE (~7.5–8.0) — NOT peaking
    //   Strength testing (24)             → Hyp: movement prep — no stimulus

    private static func hypertrophyParams(week: Int) -> HypertrophyParams {

        if week == 24 {  // Movement prep — no stimulus
            return HypertrophyParams(
                isDeload: false, isMovementPrep: true,
                mainSets: 2, mainRepsLow: 12, mainRepsHigh: 15, mainRPE: 5.5, mainRest: 90,
                accSets: 2, accRepsLow: 15, accRepsHigh: 20, accRPE: 5.0, accRest: 60
            )
        }

        if week == 4 || week == 12 || week == 20 {  // Deload — always match
            return HypertrophyParams(
                isDeload: true, isMovementPrep: false,
                mainSets: 2, mainRepsLow: 12, mainRepsHigh: 15, mainRPE: 6.0, mainRest: 90,
                accSets: 2, accRepsLow: 15, accRepsHigh: 20, accRPE: 5.5, accRest: 60
            )
        }

        // Block 1 — same phase as strength (early program, fatigue tolerance is fresh)
        if week <= 8 {
            let post = week > 4
            return HypertrophyParams(
                isDeload: false, isMovementPrep: false,
                mainSets: post ? 4 : 3, mainRepsLow: 10, mainRepsHigh: 12,
                mainRPE: post ? 7.5 : 7.0, mainRest: 120,
                accSets: post ? 4 : 3, accRepsLow: 12, accRepsHigh: 15,
                accRPE: post ? 7.0 : 6.5, accRest: 75
            )
        }

        // Block 2 — strength is intensifying; hyp lags at accumulation/early-intensification RPE
        if week <= 16 {
            let post = week > 12
            return HypertrophyParams(
                isDeload: false, isMovementPrep: false,
                mainSets: 4, mainRepsLow: 8, mainRepsHigh: 10,
                mainRPE: post ? 8.0 : 7.5, mainRest: 150,
                accSets: 3, accRepsLow: 10, accRepsHigh: 12,
                accRPE: post ? 7.5 : 7.0, accRest: 90
            )
        }

        // Block 3 — strength is peaking; hyp sits at late-intensification (NOT peaking)
        let late = week >= 21
        return HypertrophyParams(
            isDeload: false, isMovementPrep: false,
            mainSets: late ? 3 : 4, mainRepsLow: 6, mainRepsHigh: 8,
            mainRPE: late ? 8.0 : 7.5, mainRest: 150,  // capped below strength peaking RPE
            accSets: 3, accRepsLow: 10, accRepsHigh: 12,
            accRPE: late ? 7.5 : 7.0, accRest: 90
        )
    }

    // ── Slot constructor ─────────────────────────────────────────────────────

    private static func slot(
        week: Int, session: SessionType, slotId: String, index: Int,
        key: String, role: ExerciseRole, isMain: Bool = false,
        sets: Int, repsLow: Int, repsHigh: Int, rpe: Double, rest: Int,
        notes: String = ""
    ) -> ProgramSessionTemplate {
        ProgramSessionTemplate(
            programId: programId, programVersion: currentSeedVersion,
            week: week, sessionType: session, slotId: slotId, exerciseIndex: index,
            exerciseKey: key, role: role, isMainLift: isMain,
            targetSets: sets, targetRepsLow: repsLow, targetRepsHigh: repsHigh,
            targetRPE: rpe, restSeconds: rest, notes: notes
        )
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SESSION A — HEAVY UPPER
    //
    // A1  Barbell Bench Press     mainLift
    // A2  Overhead Press          supplemental
    // A3  Barbell Row             supplemental
    // A4  Cable Lat Pulldown      accessory
    // A5  Cable Tricep Pushdown   accessory
    // A6  Barbell Curl            accessory
    // ═══════════════════════════════════════════════════════════════════════

    private static func heavyUpperSlots(week: Int, p: StrengthParams) -> [ProgramSessionTemplate] {
        let s = SessionType.heavyUpper
        let mainNotes: String
        if p.isTesting {
            mainNotes = "1RM test — pyramid up with long rests: 60%×5, 75%×3, 85%×1, 92%×1, attempt max. Rest fully between heavy singles."
        } else if p.isDeload {
            mainNotes = "Deload — bar speed is the goal. Stop 3–4 reps short of failure. Move fast off the chest."
        } else {
            mainNotes = ""
        }
        return [
            slot(week: week, session: s, slotId: "A1", index: 0,
                 key: "bench_press_barbell", role: .mainLift, isMain: true,
                 sets: p.mainSets, repsLow: p.mainRepsLow, repsHigh: p.mainRepsHigh,
                 rpe: p.mainRPE, rest: p.mainRest, notes: mainNotes),
            slot(week: week, session: s, slotId: "A2", index: 1,
                 key: "ohp_barbell", role: .supplemental,
                 sets: p.suppSets, repsLow: p.suppRepsLow, repsHigh: p.suppRepsHigh,
                 rpe: p.suppRPE, rest: p.suppRest,
                 notes: "Strict press — no leg drive. Elbows slightly in front of the bar at start position."),
            slot(week: week, session: s, slotId: "A3", index: 2,
                 key: "row_barbell", role: .supplemental,
                 sets: p.suppSets, repsLow: p.suppRepsLow, repsHigh: p.suppRepsHigh,
                 rpe: p.suppRPE, rest: p.suppRest,
                 notes: "Overhand, torso ~45°. Pull to lower chest. Retract scapula before initiating the pull."),
            slot(week: week, session: s, slotId: "A4", index: 3,
                 key: "pulldown_cable", role: .accessory,
                 sets: p.accSets, repsLow: p.accRepsLow, repsHigh: p.accRepsHigh,
                 rpe: p.accRPE, rest: p.accRest,
                 notes: "Slight lean back. Pull elbows to hips, not hands to chest. Full dead-hang stretch at top."),
            slot(week: week, session: s, slotId: "A5", index: 4,
                 key: "tricep_pushdown_cable", role: .accessory,
                 sets: p.accSets, repsLow: p.accRepsLow, repsHigh: p.accRepsHigh,
                 rpe: p.accRPE, rest: p.accRest,
                 notes: "Elbows pinned at sides. Full lockout every rep. Rope or straight bar — either works."),
            slot(week: week, session: s, slotId: "A6", index: 5,
                 key: "curl_barbell", role: .accessory,
                 sets: p.accSets, repsLow: p.accRepsLow, repsHigh: p.accRepsHigh,
                 rpe: p.accRPE, rest: p.accRest,
                 notes: "Supinated grip. No body swing. Slow eccentric — 2 sec down."),
        ]
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SESSION B — HEAVY LOWER
    //
    // B1  Barbell Back Squat    mainLift
    // B2  Barbell Deadlift      supplemental + mainLift flag (tracked for e1RM independently)
    // B3  Lying Leg Curl        accessory
    // B4  Leg Extension         accessory  ← NOT leg press; see design decision #3 in file header
    // ═══════════════════════════════════════════════════════════════════════

    private static func heavyLowerSlots(week: Int, p: StrengthParams) -> [ProgramSessionTemplate] {
        let s = SessionType.heavyLower
        let squatNotes: String
        if p.isTesting {
            squatNotes = "Squat 1RM test — work up methodically, long rests. After max squat, rest 15+ min before deadlift attempt."
        } else if p.isDeload {
            squatNotes = "Deload — maintain bracing cues and bar path. Leave 3+ reps in tank every set."
        } else {
            squatNotes = ""
        }
        return [
            slot(week: week, session: s, slotId: "B1", index: 0,
                 key: "squat_barbell", role: .mainLift, isMain: true,
                 sets: p.mainSets, repsLow: p.mainRepsLow, repsHigh: p.mainRepsHigh,
                 rpe: p.mainRPE, rest: p.mainRest, notes: squatNotes),
            slot(week: week, session: s, slotId: "B2", index: 1,
                 key: "deadlift_barbell", role: .supplemental, isMain: true,
                 sets: p.suppSets, repsLow: p.suppRepsLow, repsHigh: p.suppRepsHigh,
                 rpe: p.suppRPE, rest: p.suppRest,
                 notes: "Secondary main lift — e1RM tracked independently from squat. Hook grip or straps when load demands it."),
            slot(week: week, session: s, slotId: "B3", index: 2,
                 key: "leg_curl_lying", role: .accessory,
                 sets: p.accSets, repsLow: p.accRepsLow, repsHigh: p.accRepsHigh,
                 rpe: p.accRPE, rest: p.accRest,
                 notes: "Hamstring complement after heavy hinge work. 3 sec eccentric — resist the pad on the way down."),
            slot(week: week, session: s, slotId: "B4", index: 3,
                 key: "leg_extension", role: .accessory,
                 sets: p.accSets, repsLow: p.accRepsLow, repsHigh: p.accRepsHigh,
                 rpe: p.accRPE, rest: p.accRest,
                 notes: "VMO work to reinforce squat lockout strength. Full extension at top, controlled descent."),
        ]
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SESSION C — HYPERTROPHY UPPER
    //
    // C1  Incline DB Press         mainLift
    // C2  Cable Chest Fly          accessory
    // C3  Dumbbell Row             supplemental
    // C4  Cable Face Pull          accessory  — shoulder health, never skip
    // C5  Dumbbell Lateral Raise   accessory
    // C6  Overhead Tricep (Cable)  finisher
    // C7  Hammer Curl              finisher
    //
    // RPE intentionally lower than same-week A session — lagged resolver.
    // ═══════════════════════════════════════════════════════════════════════

    private static func hypertrophyUpperSlots(week: Int, p: HypertrophyParams) -> [ProgramSessionTemplate] {
        let s = SessionType.hypertrophyUpper
        let mainNotes: String
        if p.isMovementPrep {
            mainNotes = "Movement prep week — light load, full ROM. No pushing near failure. This session exists to stay loose before testing, not to create stimulus."
        } else if p.isDeload {
            mainNotes = "Deload — pump focus. High reps, low load, strong mind-muscle connection."
        } else {
            mainNotes = "Upper chest emphasis. Elbows at ~75° — not fully flared, not tucked. Control the descent."
        }
        return [
            slot(week: week, session: s, slotId: "C1", index: 0,
                 key: "bench_press_incline_dumbbell", role: .mainLift, isMain: true,
                 sets: p.mainSets, repsLow: p.mainRepsLow, repsHigh: p.mainRepsHigh,
                 rpe: p.mainRPE, rest: p.mainRest, notes: mainNotes),
            slot(week: week, session: s, slotId: "C2", index: 1,
                 key: "cable_fly_neutral", role: .accessory,
                 sets: p.accSets, repsLow: p.accRepsLow, repsHigh: p.accRepsHigh,
                 rpe: p.accRPE, rest: p.accRest,
                 notes: "Deep stretch at bottom. Hard squeeze at top. Cable maintains constant tension throughout — more effective than dumbbell fly here."),
            slot(week: week, session: s, slotId: "C3", index: 2,
                 key: "row_dumbbell", role: .supplemental,
                 sets: p.mainSets, repsLow: p.mainRepsLow, repsHigh: p.mainRepsHigh,
                 rpe: p.mainRPE, rest: p.mainRest,
                 notes: "Let the shoulder blade move fully — protract at bottom, retract and depress at top."),
            slot(week: week, session: s, slotId: "C4", index: 3,
                 key: "face_pull_cable", role: .accessory,
                 sets: p.accSets, repsLow: p.accRepsLow, repsHigh: p.accRepsHigh,
                 rpe: p.accRPE, rest: p.accRest,
                 notes: "Shoulder health — do not skip, even on deload weeks. Rope to forehead, elbows high, external rotation at end range."),
            slot(week: week, session: s, slotId: "C5", index: 4,
                 key: "lateral_raise_dumbbell", role: .accessory,
                 sets: p.accSets, repsLow: p.accRepsLow, repsHigh: p.accRepsHigh,
                 rpe: p.accRPE, rest: 75,
                 notes: "Slight forward lean, lead with the elbow not the hand. Thumb slightly down at top."),
            slot(week: week, session: s, slotId: "C6", index: 5,
                 key: "tricep_overhead_cable", role: .finisher,
                 sets: p.accSets, repsLow: p.accRepsLow, repsHigh: p.accRepsHigh,
                 rpe: p.accRPE, rest: 75,
                 notes: "Long head stretch — overhead cable hits what pushdowns miss. Keep elbows close to ears."),
            slot(week: week, session: s, slotId: "C7", index: 6,
                 key: "curl_hammer", role: .finisher,
                 sets: p.accSets, repsLow: p.accRepsLow, repsHigh: p.accRepsHigh,
                 rpe: p.accRPE, rest: 75,
                 notes: "Neutral grip for brachialis and brachioradialis — complements supinated barbell curl on A day."),
        ]
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SESSION D — HYPERTROPHY LOWER
    //
    // D1  Romanian Deadlift     mainLift
    // D2  Barbell Hip Thrust    supplemental
    // D3  Leg Press             accessory  (exerciseKey distinct from B4 leg_extension)
    // D4  Seated Leg Curl       accessory  (long-head stretch > lying variation)
    // D5  Standing Calf Raise   finisher   (fixed 15–20 rep range regardless of block)
    //
    // RPE intentionally lower than same-week B session — lagged resolver.
    // ═══════════════════════════════════════════════════════════════════════

    private static func hypertrophyLowerSlots(week: Int, p: HypertrophyParams) -> [ProgramSessionTemplate] {
        let s = SessionType.hypertrophyLower
        let rdlNotes: String
        if p.isMovementPrep {
            rdlNotes = "Movement prep — light RDL to flush the legs and reinforce hinge pattern. Not a training stimulus. Keep it easy."
        } else if p.isDeload {
            rdlNotes = "Deload — focus on the stretch, not the load. Feel the hamstrings load under tension."
        } else {
            rdlNotes = "3 sec eccentric — feel the hamstrings stretch below the knee. Do not round lower back chasing depth."
        }
        return [
            slot(week: week, session: s, slotId: "D1", index: 0,
                 key: "rdl_barbell", role: .mainLift, isMain: true,
                 sets: p.mainSets, repsLow: p.mainRepsLow, repsHigh: p.mainRepsHigh,
                 rpe: p.mainRPE, rest: p.mainRest, notes: rdlNotes),
            slot(week: week, session: s, slotId: "D2", index: 1,
                 key: "hip_thrust_barbell", role: .supplemental,
                 sets: p.mainSets, repsLow: p.mainRepsLow, repsHigh: p.mainRepsHigh,
                 rpe: p.mainRPE, rest: p.mainRest,
                 notes: "Full hip extension at top, posterior pelvic tilt. Drive through the heel. Pause 1 sec at peak contraction."),
            slot(week: week, session: s, slotId: "D3", index: 2,
                 key: "leg_press", role: .accessory,
                 sets: p.accSets, repsLow: p.accRepsLow, repsHigh: p.accRepsHigh,
                 rpe: p.accRPE, rest: p.accRest,
                 notes: "High and wide foot placement for glute bias. Full ROM — don't cut depth to load more weight."),
            slot(week: week, session: s, slotId: "D4", index: 3,
                 key: "leg_curl_seated", role: .accessory,
                 sets: p.accSets, repsLow: p.accRepsLow, repsHigh: p.accRepsHigh,
                 rpe: p.accRPE, rest: p.accRest,
                 notes: "Seated keeps the hip flexed, putting the biceps femoris long head in a stretched position — greater hypertrophy stimulus than lying variation."),
            slot(week: week, session: s, slotId: "D5", index: 4,
                 key: "calf_raise_standing", role: .finisher,
                 sets: p.accSets, repsLow: 15, repsHigh: 20,   // fixed — calves always high rep
                 rpe: p.accRPE, rest: 60,
                 notes: "Full ROM — 1 sec pause at stretch, hard squeeze at top. Calves respond to frequency and ROM, not load chasing."),
        ]
    }
}
