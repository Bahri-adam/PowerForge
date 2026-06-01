import Foundation
import SwiftData

// ═══════════════════════════════════════════
// AESTHETIC SPLIT SEEDER  —  Program ID: 8
// 5-day: Push A / Lower A / Pull A / Push B / Lower B (Mon–Fri, Sat/Sun rest)
// Chest, quad, and arm emphasis built for a physique ("the look") goal.
//
// Coverage notes (from a volume audit against RP MEV/MAV landmarks):
//  - Rear delts: a Face Pull was added to Push A (the delt-focused day) so
//    rear delts reach MEV (~6 sets) instead of the single reverse-pec-deck slot.
//  - Back: a Straight-Arm Pulldown was added to Push B (lats don't fatigue
//    pressing) so weekly back volume reaches ~10 sets (MEV) with only one
//    dedicated pull day. Pull A itself is at the per-session set cap.
//  - Glutes are intentionally left to secondary work (RDL / Bulgarian / hack).
// ═══════════════════════════════════════════

struct AestheticSplitSeeder {

    static let programId = 8
    static let currentSeedVersion = 1
    static let durationWeeks = 16

    /// (exerciseKey, slotId, exerciseIndex, baseSets, repLow, repHigh, rpe, restSeconds, isMainLift, note)
    typealias Slot = (String, String, Int, Int, Int, Int, Double, Int, Bool, String)

    // Day 1 — Push A (heavy): chest, front/side delts, triceps, rear delt
    static let pushA: [Slot] = [
        ("bench_press_barbell",  "A1", 0, 4, 5,  8,  8.0, 180, true,  "Heaviest pressing of the week. Full ROM, controlled eccentric."),
        ("incline_machine_press","A2", 1, 3, 8,  12, 8.5, 120, false, "Upper chest. Push hard without balancing a bar."),
        ("shoulder_press_machine","A3",2, 3, 8,  12, 8.5, 120, false, "Front delt."),
        ("lateral_raise_cable",  "A4", 3, 4, 12, 20, 9.0, 60,  false, "Side delt — pinky slightly up. Priority muscle, tolerates volume."),
        ("tricep_overhead_cable","A5", 4, 3, 10, 15, 9.0, 60,  false, "Triceps long head — stretched in the overhead position."),
        ("face_pull_cable",      "A6", 5, 3, 15, 20, 9.0, 60,  false, "Rear delts + upper-back balance (added for shoulder health)."),
        ("weighted_situp",       "A7", 6, 3, 12, 15, 9.0, 60,  false, "Abs.")
    ]

    // Day 2 — Lower A (quad focus): quads, hamstrings, calves, core
    static let lowerA: [Slot] = [
        ("hack_squat",            "B1", 0, 4, 8,  12, 8.5, 180, true,  "Heavy quad builder. True depth, controlled."),
        ("single_leg_leg_press",  "B2", 1, 3, 10, 15, 8.5, 90,  false, "More quad/glute volume, cheap on recovery."),
        ("leg_extension",         "B3", 2, 3, 12, 20, 9.0, 60,  false, "Rectus femoris + inner quad. Loaded stretch."),
        ("leg_curl_seated",       "B4", 3, 3, 10, 15, 9.0, 60,  false, "Hamstrings in a stretched hip position — top growth exercise."),
        ("calf_raise_standing",   "B5", 4, 4, 12, 20, 9.0, 60,  false, "Gastrocnemius. Full stretch, full squeeze, no bounce."),
        ("hanging_leg_raise",     "B6", 5, 3, 10, 15, 9.0, 60,  false, "Lower abs.")
    ]

    // Day 3 — Pull A: back, rear delts, biceps
    static let pullA: [Slot] = [
        ("pulldown_wide",         "C1", 0, 4, 8,  12, 8.5, 120, true,  "Vertical pull — best lat-width builder."),
        ("row_machine",           "C2", 1, 3, 8,  12, 8.5, 120, false, "Horizontal pull — mid-back + lats."),
        ("rear_delt_machine",     "C3", 2, 3, 15, 20, 9.0, 60,  false, "Rear delt — balances the shoulder, improves posture."),
        ("curl_barbell",          "C4", 3, 3, 12, 15, 9.0, 60,  false, "Biceps — overall mass."),
        ("curl_incline_dumbbell", "C5", 4, 3, 8,  12, 9.0, 60,  false, "Long head — lie back, let the arms hang behind the body."),
        ("curl_hammer",           "C6", 5, 3, 10, 15, 9.0, 60,  false, "Neutral grip — brachialis + forearm. Pushes the biceps up."),
        ("cable_crunch",          "C7", 6, 3, 12, 15, 9.0, 60,  false, "Upper abs.")
    ]

    // Day 4 — Push B (pump, upper-chest focus): chest, side delts, arms, back
    static let pushB: [Slot] = [
        ("incline_machine_press", "D1", 0, 4, 8,  12, 8.0, 120, true,  "Lead with the upper chest — highest-value area for the look."),
        ("cable_fly_neutral",     "D2", 1, 3, 12, 15, 9.0, 60,  false, "Deep stretch, arms across the body. Slow, big stretch at the bottom."),
        ("lateral_raise_cable",   "D3", 2, 4, 12, 20, 9.0, 60,  false, "Second side-delt day. Top priority for the physique."),
        ("pulldown_straight_arm", "D4", 3, 3, 12, 15, 9.0, 60,  false, "Lats — added back volume (doesn't fatigue the pressing)."),
        ("curl_cable",            "D5", 4, 3, 10, 12, 9.0, 60,  false, "Short head / overall biceps."),
        ("tricep_pushdown_cable", "D6", 5, 3, 10, 15, 9.0, 60,  false, "Lateral + medial heads, arms at the sides."),
        ("machine_dip",           "D7", 6, 2, 8,  12, 9.5, 90,  false, "Lower chest + triceps. Near failure.")
    ]

    // Day 5 — Lower B (posterior chain focus)
    static let lowerB: [Slot] = [
        ("rdl_barbell",           "E1", 0, 4, 8,  12, 8.5, 180, true,  "Hamstrings at the hip + glutes. Hips back, feel the stretch, don't squat it."),
        ("leg_curl_lying",        "E2", 1, 3, 10, 12, 9.0, 60,  false, "Knee flexion in a different position than the seated curl."),
        ("leg_curl_seated",       "E3", 2, 3, 10, 15, 9.0, 60,  false, "Seated stretch position."),
        ("bulgarian_split_squat", "E4", 3, 3, 10, 12, 9.0, 90,  false, "Quads + glutes, single-leg."),
        ("calf_raise_seated",     "E5", 4, 4, 15, 20, 9.0, 60,  false, "Soleus — knees bent.")
    ]

    static let sessions: [(SessionType, [Slot])] = [
        (.pushA, pushA), (.legsA, lowerA), (.pullA, pullA), (.pushB, pushB), (.legsB, lowerB)
    ]

    static func isDeload(_ w: Int) -> Bool { w == 6 || w == 12 }

    static func seedIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<ProgramTemplate>(
            predicate: #Predicate { $0.programId == 8 }
        )
        let existing = (try? context.fetch(descriptor)) ?? []
        if let t = existing.first, t.version >= currentSeedVersion { return }

        for t in existing { context.delete(t) }
        let slotDesc = FetchDescriptor<ProgramSessionTemplate>(
            predicate: #Predicate { $0.programId == 8 }
        )
        for s in (try? context.fetch(slotDesc)) ?? [] { context.delete(s) }

        let template = ProgramTemplate(
            programId: programId,
            name: "Aesthetic Split",
            version: currentSeedVersion,
            durationWeeks: durationWeeks,
            sessionTypes: [.pushA, .legsA, .pullA, .pushB, .legsB],
            scheduleOptions: []
        )
        context.insert(template)

        for week in 1...durationWeeks {
            let deload = isDeload(week)
            for (sessionType, slots) in sessions {
                for s in slots {
                    let sets = deload ? max(1, Int((Double(s.3) * 0.5).rounded())) : s.3
                    let lo   = deload ? s.4 + 2 : s.4
                    let hi   = deload ? s.5 + 2 : s.5
                    let rpe  = deload ? 6.0 : s.6
                    let note = deload ? "Deload — light, stop well short. \(s.9)" : s.9
                    context.insert(ProgramSessionTemplate(
                        programId: programId,
                        programVersion: currentSeedVersion,
                        week: week,
                        sessionType: sessionType,
                        slotId: s.1,
                        exerciseIndex: s.2,
                        exerciseKey: s.0,
                        role: s.8 ? .mainLift : .accessory,
                        isMainLift: s.8,
                        targetSets: sets,
                        targetRepsLow: lo,
                        targetRepsHigh: hi,
                        targetRPE: max(4.0, rpe),
                        restSeconds: s.7,
                        notes: note
                    ))
                }
            }
        }
        try? context.save()
        print("[AestheticSplitSeeder] Seeded v\(currentSeedVersion) — \(durationWeeks) weeks")
    }
}
