import Foundation
import SwiftData

// ═══════════════════════════════════════════
// BAHRI SPLIT SEEDER  —  Program ID: 7
// 6-day: Mon/Tue/Wed/Thu/Sat/Sun (Fri = rest)
// ═══════════════════════════════════════════

struct BahriSplitSeeder {

    static let programId = 7
    static let currentSeedVersion = 1

    static func seedIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<ProgramTemplate>(
            predicate: #Predicate { $0.programId == 7 }
        )
        let existing = (try? context.fetch(descriptor)) ?? []
        if let t = existing.first, t.version >= currentSeedVersion { return }

        for t in existing { context.delete(t) }
        let slotDesc = FetchDescriptor<ProgramSessionTemplate>(
            predicate: #Predicate { $0.programId == 7 }
        )
        for s in (try? context.fetch(slotDesc)) ?? [] { context.delete(s) }

        // ProgramTemplate init uses sessionTypes: [SessionType] (not sessionTypeRaws)
        let template = ProgramTemplate(
            programId: programId,
            name: "Bahri Split",
            version: currentSeedVersion,
            durationWeeks: 24,
            sessionTypes: [
                .legQuadFocus,
                .chestBack,
                .armsDelts,
                .legsPosterior,
                .chestArms,
                .legsVolume
            ],
            scheduleOptions: []
        )
        context.insert(template)

        for week in 1...24 { insertWeek(week: week, context: context) }
        try? context.save()
        print("[BahriSplitSeeder] Seeded v\(currentSeedVersion) — 24 weeks")
    }

    // ── Block params ─────────────────────────────────────────────────────────

    struct DayParams {
        let rpe: Double
        let setsMult: Double
        let repsShift: Int   // shift repsLow/High up (heavier = negative)
        let isDeload: Bool
    }

    static func params(week: Int) -> DayParams {
        if isDeload(week) { return DayParams(rpe: 5.5, setsMult: 0.5, repsShift: 2, isDeload: true) }
        if week <= 9 {
            let rpe: Double = week <= 2 ? 7.0 : week <= 5 ? 7.5 : 8.0
            return DayParams(rpe: rpe, setsMult: 1.0, repsShift: 0, isDeload: false)
        }
        if week <= 15 {
            return DayParams(rpe: week <= 11 ? 8.0 : 8.5, setsMult: 0.9, repsShift: -1, isDeload: false)
        }
        if week == 24 { return DayParams(rpe: 5.0, setsMult: 0.5, repsShift: 3, isDeload: true) }
        return DayParams(rpe: week <= 20 ? 8.5 : 9.0, setsMult: 1.0, repsShift: 0, isDeload: false)
    }

    static func isDeload(_ w: Int) -> Bool { [3,6,9,12,15,18,21].contains(w) || w == 24 }
    static func s(_ base: Int, _ mult: Double) -> Int { max(1, Int((Double(base) * mult).rounded())) }
    static func r(_ lo: Int, _ hi: Int, _ shift: Int) -> (Int, Int) { (max(1, lo+shift), max(lo+shift+1, hi+shift)) }

    // ── Main week dispatcher ──────────────────────────────────────────────────

    static func insertWeek(week: Int, context: ModelContext) {
        let p = params(week: week)
        if p.isDeload { insertDeload(week: week, p: p, context: context); return }
        insertMonday(week: week, p: p, context: context)
        insertTuesday(week: week, p: p, context: context)
        insertWednesday(week: week, p: p, context: context)
        insertThursday(week: week, p: p, context: context)
        insertSaturday(week: week, p: p, context: context)
        insertSunday(week: week, p: p, context: context)
    }

    // ── DELOAD — Full Body A (legQuadFocus) + Full Body B (legsPosterior) ─────

    static func insertDeload(week: Int, p: DayParams, context: ModelContext) {
        let (rl, rh) = r(8, 10, p.repsShift)
        // Deload A — Monday slot
        let deloadA: [(String, String, Int, Int, Int, Int, Double, Int, Bool, String)] = [
            ("hack_squat",             "A1", 0, s(3, p.setsMult), rl, rh, p.rpe,       120, false, "Smooth reps. Stop 4-5 short. No 3-sec eccentric."),
            ("rdl_barbell",            "A2", 1, s(3, p.setsMult), rl, rh, p.rpe,       120, false, "Controlled eccentric. Feel stretch without forcing."),
            ("bench_press_barbell",    "A3", 2, s(3, p.setsMult), rl, rh, p.rpe,       120, false, "Smooth eccentric. Full ROM. Stop 4-5 short."),
            ("lat_pulldown",           "A4", 3, s(3, p.setsMult), rl, rh, p.rpe,       90,  false, "Full stretch top, full contraction bottom."),
            ("lateral_raise_dumbbell", "A5", 4, s(2, p.setsMult), 15, 18, p.rpe,       60,  false, "Light. Stop well short of failure."),
            ("calf_raise_seated",      "A6", 5, s(2, p.setsMult), 15, 20, p.rpe,       60,  false, "Full ROM. No loaded interset stretch.")
        ]
        for (key, sl, idx, sets, lo, hi, rpe, rest, main, note) in deloadA {
            context.insert(makeSlot(week, .legQuadFocus, sl, idx, key, sets, lo, hi, rpe, rest, main, note))
        }
        // Deload B — Thursday slot
        let deloadB: [(String, String, Int, Int, Int, Int, Double, Int, Bool, String)] = [
            ("leg_press",              "D1", 0, s(3, p.setsMult), rl, rh, p.rpe,       120, false, "Comfortable depth. Stop 4-5 RIR. No forced stretch."),
            ("leg_curl_seated",        "D2", 1, s(3, p.setsMult), rl, rh, p.rpe,       90,  false, "Controlled eccentric. Stop 4-5 short."),
            ("incline_press_dumbbell", "D3", 2, s(3, p.setsMult), rl, rh, p.rpe,       120, false, "Full ROM. Controlled. Stop 4-5 short."),
            ("cable_row",              "D4", 3, s(3, p.setsMult), rl, rh, p.rpe,       90,  false, "Row to lower chest. Controlled."),
            ("face_pull_cable",        "D5", 4, s(2, p.setsMult), 15, 20, p.rpe,       60,  false, "Pull to face, external rotation. Stop short."),
            ("calf_raise_standing",    "D6", 5, s(2, p.setsMult), 12, 15, p.rpe,       60,  false, "Full ROM. No loaded interset stretch.")
        ]
        for (key, sl, idx, sets, lo, hi, rpe, rest, main, note) in deloadB {
            context.insert(makeSlot(week, .legsPosterior, sl, idx, key, sets, lo, hi, rpe, rest, main, note))
        }
    }

    // ── MONDAY — Legs: Quad Focus (Heavy) ────────────────────────────────────

    static func insertMonday(week: Int, p: DayParams, context: ModelContext) {
        let (rl5, rh5)   = r(5, 8, p.repsShift)
        let (rl10, rh10) = r(10, 12, 0)
        let (rl12, rh12) = r(12, 15, 0)
        let (rl15, rh15) = r(15, 20, 0)

        let slots: [(String, String, Int, Int, Int, Int, Double, Int, Bool, String)] = [
            ("hack_squat",          "A1", 0, s(5, p.setsMult), rl5,  rh5,  p.rpe,       180, true,  "True depth. 3-sec eccentric. Drive knees out. Rep 8 must be a grind."),
            ("leg_press_single",    "A2", 1, s(3, p.setsMult), rl10, rh10, p.rpe - 0.5, 90,  false, "Loaded stretch — hold bottom 20-30 sec after final set."),
            ("leg_extension",       "A3", 2, s(3, p.setsMult), rl12, rh12, p.rpe - 0.5, 60,  false, "3-sec eccentric. Loaded stretch every set. Drop set final set."),
            ("leg_curl_seated",     "A4", 3, s(3, p.setsMult), rl10, rh10, p.rpe - 0.5, 60,  false, "3-sec eccentric. Hold fully extended 20 sec after final set."),
            ("calf_raise_standing", "A5", 4, s(4, p.setsMult), rl12, rh12, p.rpe - 1.0, 60,  false, "Loaded interset stretch every set — 30 sec at bottom."),
            ("calf_raise_seated",   "A6", 5, s(3, p.setsMult), rl15, rh15, p.rpe - 1.0, 60,  false, "Soleus emphasis (knee bent). Slow eccentric.")
        ]
        for (key, sl, idx, sets, lo, hi, rpe, rest, main, note) in slots {
            context.insert(makeSlot(week, .legQuadFocus, sl, idx, key, sets, lo, hi, rpe, rest, main, note))
        }
    }

    // ── TUESDAY — Chest & Back: Full Upper ───────────────────────────────────

    static func insertTuesday(week: Int, p: DayParams, context: ModelContext) {
        let (rl3, rh3)   = r(3, 5, p.repsShift)
        let (rl8, rh8)   = r(8, 10, 0)
        let (rl12, rh12) = r(12, 15, 0)
        let (rl15, rh15) = r(15, 20, 0)

        let slots: [(String, String, Int, Int, Int, Int, Double, Int, Bool, String)] = [
            ("bench_press_barbell",    "B1", 0, s(4, p.setsMult), rl3,  rh3,  p.rpe,       180, true,  "Tight arch, lat engagement. 2-sec eccentric + pause."),
            ("incline_press_dumbbell", "B2", 1, s(3, p.setsMult), rl8,  rh8,  p.rpe - 0.5, 120, false, "Full ROM — stretch at bottom. 30-45° incline."),
            ("cable_fly",              "B3", 2, s(3, p.setsMult), rl12, rh12, p.rpe - 1.0, 90,  false, "3-sec eccentric. Pec stretch and contraction."),
            ("pullup_weighted",        "B4", 3, s(4, p.setsMult), rl3,  rh8,  p.rpe,       180, true,  "Pronated grip. Full stretch at top. Drive elbows to hips."),
            ("machine_row_plate",      "B5", 4, s(3, p.setsMult), rl8,  rh8,  p.rpe - 0.5, 120, false, "Neutral grip. Row to lower chest. No kipping."),
            ("lat_pullover_cable",     "B6", 5, s(3, p.setsMult), rl12, rh12, p.rpe - 1.0, 90,  false, "Full stretch at start. Slow eccentric on stretch phase."),
            ("face_pull_cable",        "B7", 6, s(3, p.setsMult), rl15, rh15, p.rpe - 1.5, 60,  false, "Pull to face, external rotation at end. NEVER skip.")
        ]
        for (key, sl, idx, sets, lo, hi, rpe, rest, main, note) in slots {
            context.insert(makeSlot(week, .chestBack, sl, idx, key, sets, lo, hi, rpe, rest, main, note))
        }
    }

    // ── WEDNESDAY — Arms + Delts ──────────────────────────────────────────────

    static func insertWednesday(week: Int, p: DayParams, context: ModelContext) {
        let (rl6, rh6)   = r(6, 8, p.repsShift)
        let (rl10, rh10) = r(10, 12, 0)
        let (rl12, rh12) = r(12, 15, 0)
        let (rl15, rh15) = r(15, 20, 0)

        let slots: [(String, String, Int, Int, Int, Int, Double, Int, Bool, String)] = [
            ("curl_barbell",          "C1", 0, s(4, p.setsMult), rl6,  rh6,  p.rpe,       120, false, "No cheat. Long head early range. Full extension at bottom."),
            ("curl_incline_dumbbell", "C2", 1, s(3, p.setsMult), rl10, rh10, p.rpe - 0.5, 90,  false, "Humerus BEHIND body = long head maximally stretched. 3-sec eccentric."),
            ("curl_hammer_cable",     "C3", 2, s(3, p.setsMult), rl12, rh12, p.rpe - 1.0, 60,  false, "Constant tension. Squeeze hard at top."),
            ("close_grip_bench",      "C4", 3, s(4, p.setsMult), rl6,  rh6,  p.rpe,       120, false, "Elbows tucked. Full lockout. Control eccentric."),
            ("tricep_overhead_cable", "C5", 4, s(3, p.setsMult), rl10, rh10, p.rpe - 0.5, 90,  false, "Shoulder at 180° = long head optimal. 3-sec eccentric."),
            ("tricep_pushdown_cable", "C6", 5, s(3, p.setsMult), rl12, rh12, p.rpe - 1.0, 60,  false, "Drop set final set. Lateral/medial dominant."),
            ("lateral_raise_machine", "C7", 6, s(4, p.setsMult), rl15, rh15, p.rpe - 1.5, 60,  false, "Pinky up — middle delt. No anterior delt."),
            ("rear_delt_fly_dumbbell","C8", 7, s(3, p.setsMult), rl15, rh15, p.rpe - 1.5, 60,  false, "Bent over or cable. Full contraction at top.")
        ]
        for (key, sl, idx, sets, lo, hi, rpe, rest, main, note) in slots {
            context.insert(makeSlot(week, .armsDelts, sl, idx, key, sets, lo, hi, rpe, rest, main, note))
        }
    }

    // ── THURSDAY — Legs: Posterior Chain Heavy ────────────────────────────────

    static func insertThursday(week: Int, p: DayParams, context: ModelContext) {
        let (rl6, rh6)   = r(6, 8, p.repsShift)
        let (rl8, rh8)   = r(8, 10, 0)
        let (rl10, rh10) = r(10, 12, 0)
        let (rl12, rh12) = r(12, 15, 0)
        let (rl15, rh15) = r(15, 20, 0)

        let slots: [(String, String, Int, Int, Int, Int, Double, Int, Bool, String)] = [
            ("belt_squat",            "D1", 0, s(4, p.setsMult), rl6,  rh6,  p.rpe,       180, true,  "Full depth. 3-sec eccentric. Preserves spinal recovery for RDL."),
            ("rdl_barbell",           "D2", 1, s(4, p.setsMult), rl8,  rh8,  p.rpe,       180, true,  "Feel FULL hamstring stretch at bottom. 3-sec eccentric is CRITICAL."),
            ("nordic_hamstring_curl", "D3", 2, s(3, p.setsMult), rl8,  rh8,  p.rpe - 0.5, 90,  false, "Slowest eccentric — 4-5 sec down. Biceps femoris."),
            ("leg_press",             "D4", 3, s(3, p.setsMult), rl15, rh15, p.rpe - 1.0, 90,  false, "Loaded stretch: hold bottom 20 sec after every set."),
            ("leg_extension",         "D5", 4, s(2, p.setsMult), rl12, rh12, p.rpe - 1.5, 60,  false, "Slow eccentric. Loaded stretch at bottom."),
            ("hip_abductor_machine",  "D6", 5, s(3, p.setsMult), rl15, rh15, p.rpe - 1.5, 60,  false, "Controlled. Feel glute med and min."),
            ("calf_raise_standing",   "D7", 6, s(4, p.setsMult), rl10, rh10, p.rpe - 1.5, 60,  false, "Loaded interset stretch every set — 30 sec at bottom."),
            ("calf_raise_seated",     "D8", 7, s(3, p.setsMult), rl15, rh15, p.rpe - 1.5, 60,  false, "Full range. Soleus emphasis.")
        ]
        for (key, sl, idx, sets, lo, hi, rpe, rest, main, note) in slots {
            context.insert(makeSlot(week, .legsPosterior, sl, idx, key, sets, lo, hi, rpe, rest, main, note))
        }
    }

    // ── SATURDAY — Chest & Arms: Arm Priority ─────────────────────────────────

    static func insertSaturday(week: Int, p: DayParams, context: ModelContext) {
        let (rl6, rh6)   = r(6, 8, p.repsShift)
        let (rl8, rh8)   = r(8, 10, 0)
        let (rl10, rh10) = r(10, 12, 0)
        let (rl12, rh12) = r(12, 15, 0)
        let (rl15, rh15) = r(15, 20, 0)

        let slots: [(String, String, Int, Int, Int, Int, Double, Int, Bool, String)] = [
            ("incline_press_barbell",    "E1", 0, s(3, p.setsMult), rl6,  rh6,  p.rpe,       180, true,  "Different angle to Tuesday flat. Upper chest growth."),
            ("cable_fly",                "E2", 1, s(3, p.setsMult), rl15, rh15, p.rpe - 1.0, 90,  false, "3-sec eccentric. Full chest stretch."),
            ("curl_hammer",              "E3", 2, s(4, p.setsMult), rl6,  rh6,  p.rpe,       120, false, "Neutral grip = brachialis. 3-sec eccentric."),
            ("curl_cable",               "E4", 3, s(3, p.setsMult), rl10, rh10, p.rpe - 0.5, 90,  false, "Different angle to Wednesday. Constant tension."),
            ("curl_incline_dumbbell",    "E5", 4, s(3, p.setsMult), rl12, rh12, p.rpe - 0.5, 90,  false, "Long head — humerus behind body. 3-sec eccentric."),
            ("spider_curl",              "E6", 5, s(3, p.setsMult), rl12, rh12, p.rpe - 1.0, 60,  false, "Short head dominant. Full contraction."),
            ("skullcrusher_barbell",     "E7", 6, s(4, p.setsMult), rl8,  rh8,  p.rpe,       120, false, "3-sec eccentric to forehead. Long head stretch at bottom."),
            ("tricep_overhead_dumbbell", "E8", 7, s(3, p.setsMult), rl10, rh10, p.rpe - 0.5, 90,  false, "Shoulder flexed overhead = long head. 3-sec eccentric.")
        ]
        for (key, sl, idx, sets, lo, hi, rpe, rest, main, note) in slots {
            context.insert(makeSlot(week, .chestArms, sl, idx, key, sets, lo, hi, rpe, rest, main, note))
        }
    }

    // ── SUNDAY — Legs: Volume / Metabolic Stress ──────────────────────────────

    static func insertSunday(week: Int, p: DayParams, context: ModelContext) {
        let (rl10, rh10) = r(10, 12, 0)
        let (rl12, rh12) = r(12, 15, 0)
        let (rl15, rh15) = r(15, 20, 0)

        let slots: [(String, String, Int, Int, Int, Int, Double, Int, Bool, String)] = [
            ("leg_press",            "F1", 0, s(4, p.setsMult), rl15, rh15, p.rpe - 0.5, 90,  false, "Loaded stretch after every set — hold bottom 20-30 sec."),
            ("hack_squat",           "F2", 1, s(3, p.setsMult), rl10, rh10, p.rpe - 0.5, 90,  false, "NOT max effort. Controlled. Feel the quad. Full depth."),
            ("leg_extension",        "F3", 2, s(4, p.setsMult), rl15, rh15, p.rpe - 1.0, 60,  false, "Loaded stretch every set. Drop set on final set."),
            ("stiff_leg_deadlift",   "F4", 3, s(3, p.setsMult), rl12, rh12, p.rpe - 0.5, 90,  false, "Feel hamstring stretch. Slight knee bend. Higher rep than RDL."),
            ("leg_curl_lying",       "F5", 4, s(4, p.setsMult), rl12, rh12, p.rpe - 1.0, 60,  false, "3-sec eccentric. Hold fully extended 20 sec after final set."),
            ("hip_abductor_machine", "F6", 5, s(3, p.setsMult), rl15, rh15, p.rpe - 1.5, 60,  false, "Second weekly gluteus medius session."),
            ("calf_raise_standing",  "F7", 6, s(4, p.setsMult), rl15, rh15, p.rpe - 1.5, 60,  false, "Loaded interset stretch every set — 30 sec at bottom. Every set.")
        ]
        for (key, sl, idx, sets, lo, hi, rpe, rest, main, note) in slots {
            context.insert(makeSlot(week, .legsVolume, sl, idx, key, sets, lo, hi, rpe, rest, main, note))
        }
    }

    // ── Slot builder — matches ProgramSessionTemplate's actual init ───────────

    static func makeSlot(
        _ week: Int,
        _ sessionType: SessionType,
        _ slotId: String,
        _ exerciseIndex: Int,
        _ exerciseKey: String,
        _ targetSets: Int,
        _ targetRepsLow: Int,
        _ targetRepsHigh: Int,
        _ targetRPE: Double,
        _ restSeconds: Int,
        _ isMainLift: Bool,
        _ notes: String
    ) -> ProgramSessionTemplate {
        ProgramSessionTemplate(
            programId: programId,
            programVersion: currentSeedVersion,   // correct param name
            week: week,
            sessionType: sessionType,
            slotId: slotId,
            exerciseIndex: exerciseIndex,
            exerciseKey: exerciseKey,
            role: isMainLift ? .mainLift : .accessory,
            isMainLift: isMainLift,
            targetSets: targetSets,
            targetRepsLow: targetRepsLow,
            targetRepsHigh: targetRepsHigh,
            targetRPE: max(4.0, targetRPE),
            restSeconds: restSeconds,
            notes: notes
        )
    }
}
