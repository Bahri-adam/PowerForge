import SwiftData
import Foundation

// ═══════════════════════════════════════════
// ATHLETIC PERFORMANCE SEEDER  v1
// Seeds programId = 5 — 16 weeks
//
// 4-day Upper Power / Lower Power / Upper Strength-Hypertrophy / Lower Strength-Hypertrophy:
//   A = Upper Power   — bench (explosive), OHP, barbell row, pullup, face pull
//   B = Lower Power   — squat (explosive), deadlift, bulgarian split squat, leg curl, calf raise
//   C = Upper Strength-Hypertrophy — incline DB press, DB row, pulldown, lateral raise, tricep pushdown, curl
//   D = Lower Strength-Hypertrophy — front squat, RDL, leg press, leg extension, hip thrust, calf raise
//
// Periodization:
//   Block 1 (Weeks 1–8):  Foundation   — RPE 7–7.5, build work capacity, Week 4 deload
//   Block 2 (Weeks 9–16): Performance  — RPE 8–8.5, peak power + strength, Week 12 deload, Week 16 testing
//
// Design rationale:
//   - Power days (A/B): low reps (3–5), longer rest (3–4 min), compound-heavy
//   - Strength-Hypertrophy days (C/D): moderate reps (6–12), shorter rest (90–150s), accessory volume
//   - No isolation-only days — every session has compound movements
//   - Explosive intent on power days (controlled eccentric, fast concentric)
//   - Hip hinge + single-leg work for posterior chain athleticism
//   - Face pulls + lateral raises for shoulder health and stability
// ═══════════════════════════════════════════

enum AthleticSeeder {

    static let programId          = 5
    static let currentSeedVersion = 1

    static func seedIfNeeded(context: ModelContext) {
        var tDesc = FetchDescriptor<ProgramTemplate>(
            predicate: #Predicate { $0.programId == 5 }
        )
        tDesc.fetchLimit = 1
        let existing = (try? context.fetch(tDesc)) ?? []

        if let tmpl = existing.first {
            guard tmpl.version < currentSeedVersion else { return }
            context.delete(tmpl)
            let slotDesc = FetchDescriptor<ProgramSessionTemplate>(
                predicate: #Predicate { $0.programId == 5 }
            )
            for s in (try? context.fetch(slotDesc)) ?? [] { context.delete(s) }
        }

        let template = ProgramTemplate(
            programId: programId,
            name: "Athletic Performance",
            version: currentSeedVersion,
            durationWeeks: 16,
            sessionTypes: [.upperPower, .lowerPower, .hypertrophyUpper, .hypertrophyLower],
            scheduleOptions: ["Mon/Tue/Thu/Fri", "Mon/Wed/Thu/Sat"]
        )
        context.insert(template)

        for slot in buildAllSlots() { context.insert(slot) }
        try? context.save()
    }

    // ── Params ──────────────────────────────────────────────────────────────

    struct BlockParams {
        let isDeload: Bool
        let isTesting: Bool
        let powerSets: Int; let powerRepsLow: Int; let powerRepsHigh: Int; let powerRPE: Double; let powerRest: Int
        let suppSets: Int; let suppRepsLow: Int; let suppRepsHigh: Int; let suppRPE: Double; let suppRest: Int
        let accSets: Int; let accRepsLow: Int; let accRepsHigh: Int; let accRPE: Double; let accRest: Int
    }

    private static func params(week: Int) -> BlockParams {
        // Block 1 — Foundation (Weeks 1–8)
        if week <= 8 {
            if week == 4 {
                return BlockParams(
                    isDeload: true, isTesting: false,
                    powerSets: 2, powerRepsLow: 3, powerRepsHigh: 5, powerRPE: 6.0, powerRest: 180,
                    suppSets: 2, suppRepsLow: 6, suppRepsHigh: 8, suppRPE: 6.0, suppRest: 120,
                    accSets: 2, accRepsLow: 10, accRepsHigh: 12, accRPE: 6.0, accRest: 90
                )
            }
            let post = week > 4
            return BlockParams(
                isDeload: false, isTesting: false,
                powerSets: post ? 4 : 3, powerRepsLow: 3, powerRepsHigh: 5,
                powerRPE: post ? 7.5 : 7.0, powerRest: 240,
                suppSets: 3, suppRepsLow: 6, suppRepsHigh: 8,
                suppRPE: post ? 7.5 : 7.0, suppRest: 150,
                accSets: 3, accRepsLow: 8, accRepsHigh: 12, accRPE: 7.0, accRest: 90
            )
        }

        // Block 2 — Performance (Weeks 9–16)
        if week == 12 {
            return BlockParams(
                isDeload: true, isTesting: false,
                powerSets: 2, powerRepsLow: 3, powerRepsHigh: 5, powerRPE: 6.5, powerRest: 240,
                suppSets: 2, suppRepsLow: 6, suppRepsHigh: 8, suppRPE: 6.0, suppRest: 120,
                accSets: 2, accRepsLow: 10, accRepsHigh: 12, accRPE: 6.0, accRest: 90
            )
        }
        if week == 16 {
            return BlockParams(
                isDeload: false, isTesting: true,
                powerSets: 3, powerRepsLow: 1, powerRepsHigh: 3, powerRPE: 9.5, powerRest: 300,
                suppSets: 2, suppRepsLow: 3, suppRepsHigh: 5, suppRPE: 8.0, suppRest: 180,
                accSets: 2, accRepsLow: 8, accRepsHigh: 10, accRPE: 7.0, accRest: 90
            )
        }
        let post = week > 12
        return BlockParams(
            isDeload: false, isTesting: false,
            powerSets: 4, powerRepsLow: 2, powerRepsHigh: 4,
            powerRPE: post ? 8.5 : 8.0, powerRest: 270,
            suppSets: 3, suppRepsLow: 5, suppRepsHigh: 8,
            suppRPE: post ? 8.0 : 7.5, suppRest: 150,
            accSets: 3, accRepsLow: 8, accRepsHigh: 12, accRPE: 7.5, accRest: 90
        )
    }

    // ── Slot builders ───────────────────────────────────────────────────────

    private static func buildAllSlots() -> [ProgramSessionTemplate] {
        var all: [ProgramSessionTemplate] = []
        for week in 1...16 {
            let p = params(week: week)
            all += upperPowerSlots(week: week, p: p)
            all += lowerPowerSlots(week: week, p: p)
            all += upperStrHypSlots(week: week, p: p)
            all += lowerStrHypSlots(week: week, p: p)
        }
        return all
    }

    // A — Upper Power
    private static func upperPowerSlots(week: Int, p: BlockParams) -> [ProgramSessionTemplate] {
        [
            slot(week: week, session: .upperPower, id: "A1", key: "bench_press_barbell",
                 role: .mainLift, sets: p.powerSets, rLow: p.powerRepsLow, rHigh: p.powerRepsHigh,
                 rpe: p.powerRPE, rest: p.powerRest, isMain: true),
            slot(week: week, session: .upperPower, id: "A2", key: "ohp_barbell",
                 role: .supplemental, sets: p.suppSets, rLow: p.suppRepsLow, rHigh: p.suppRepsHigh,
                 rpe: p.suppRPE, rest: p.suppRest, isMain: false),
            slot(week: week, session: .upperPower, id: "A3", key: "row_barbell",
                 role: .supplemental, sets: p.suppSets, rLow: p.suppRepsLow, rHigh: p.suppRepsHigh,
                 rpe: p.suppRPE, rest: p.suppRest, isMain: false),
            slot(week: week, session: .upperPower, id: "A4", key: "pullup",
                 role: .accessory, sets: p.accSets, rLow: p.accRepsLow, rHigh: p.accRepsHigh,
                 rpe: p.accRPE, rest: p.accRest, isMain: false),
            slot(week: week, session: .upperPower, id: "A5", key: "face_pull_cable",
                 role: .accessory, sets: p.accSets, rLow: 12, rHigh: 15,
                 rpe: p.accRPE, rest: 60, isMain: false),
        ]
    }

    // B — Lower Power
    private static func lowerPowerSlots(week: Int, p: BlockParams) -> [ProgramSessionTemplate] {
        [
            slot(week: week, session: .lowerPower, id: "B1", key: "squat_barbell",
                 role: .mainLift, sets: p.powerSets, rLow: p.powerRepsLow, rHigh: p.powerRepsHigh,
                 rpe: p.powerRPE, rest: p.powerRest, isMain: true),
            slot(week: week, session: .lowerPower, id: "B2", key: "deadlift_barbell",
                 role: .supplemental, sets: p.suppSets, rLow: p.suppRepsLow, rHigh: p.suppRepsHigh,
                 rpe: p.suppRPE, rest: p.suppRest, isMain: false),
            slot(week: week, session: .lowerPower, id: "B3", key: "bulgarian_split_squat",
                 role: .accessory, sets: p.accSets, rLow: 6, rHigh: 10,
                 rpe: p.accRPE, rest: 120, isMain: false),
            slot(week: week, session: .lowerPower, id: "B4", key: "leg_curl_lying",
                 role: .accessory, sets: p.accSets, rLow: 8, rHigh: 12,
                 rpe: p.accRPE, rest: 90, isMain: false),
            slot(week: week, session: .lowerPower, id: "B5", key: "calf_raise_standing",
                 role: .accessory, sets: 3, rLow: 10, rHigh: 15,
                 rpe: p.accRPE, rest: 60, isMain: false),
        ]
    }

    // C — Upper Strength-Hypertrophy
    private static func upperStrHypSlots(week: Int, p: BlockParams) -> [ProgramSessionTemplate] {
        [
            slot(week: week, session: .hypertrophyUpper, id: "C1", key: "bench_press_incline_dumbbell",
                 role: .mainLift, sets: p.suppSets, rLow: p.suppRepsLow, rHigh: p.suppRepsHigh,
                 rpe: p.suppRPE, rest: p.suppRest, isMain: true),
            slot(week: week, session: .hypertrophyUpper, id: "C2", key: "row_dumbbell",
                 role: .supplemental, sets: p.suppSets, rLow: p.suppRepsLow, rHigh: p.suppRepsHigh,
                 rpe: p.suppRPE, rest: p.suppRest, isMain: false),
            slot(week: week, session: .hypertrophyUpper, id: "C3", key: "pulldown_wide",
                 role: .accessory, sets: p.accSets, rLow: 8, rHigh: 12,
                 rpe: p.accRPE, rest: 90, isMain: false),
            slot(week: week, session: .hypertrophyUpper, id: "C4", key: "lateral_raise_dumbbell",
                 role: .accessory, sets: p.accSets, rLow: 12, rHigh: 15,
                 rpe: p.accRPE, rest: 60, isMain: false),
            slot(week: week, session: .hypertrophyUpper, id: "C5", key: "tricep_pushdown_rope",
                 role: .finisher, sets: 3, rLow: 10, rHigh: 15,
                 rpe: p.accRPE, rest: 60, isMain: false),
            slot(week: week, session: .hypertrophyUpper, id: "C6", key: "curl_ez_bar",
                 role: .finisher, sets: 3, rLow: 10, rHigh: 12,
                 rpe: p.accRPE, rest: 60, isMain: false),
        ]
    }

    // D — Lower Strength-Hypertrophy
    private static func lowerStrHypSlots(week: Int, p: BlockParams) -> [ProgramSessionTemplate] {
        [
            slot(week: week, session: .hypertrophyLower, id: "D1", key: "squat_front",
                 role: .mainLift, sets: p.suppSets, rLow: p.suppRepsLow, rHigh: p.suppRepsHigh,
                 rpe: p.suppRPE, rest: p.suppRest, isMain: true),
            slot(week: week, session: .hypertrophyLower, id: "D2", key: "rdl_barbell",
                 role: .supplemental, sets: p.suppSets, rLow: p.suppRepsLow, rHigh: p.suppRepsHigh,
                 rpe: p.suppRPE, rest: p.suppRest, isMain: false),
            slot(week: week, session: .hypertrophyLower, id: "D3", key: "leg_press",
                 role: .accessory, sets: p.accSets, rLow: 8, rHigh: 12,
                 rpe: p.accRPE, rest: 120, isMain: false),
            slot(week: week, session: .hypertrophyLower, id: "D4", key: "leg_extension",
                 role: .accessory, sets: p.accSets, rLow: 10, rHigh: 15,
                 rpe: p.accRPE, rest: 60, isMain: false),
            slot(week: week, session: .hypertrophyLower, id: "D5", key: "hip_thrust_barbell",
                 role: .accessory, sets: p.accSets, rLow: 8, rHigh: 12,
                 rpe: p.accRPE, rest: 90, isMain: false),
            slot(week: week, session: .hypertrophyLower, id: "D6", key: "calf_raise_seated",
                 role: .finisher, sets: 3, rLow: 12, rHigh: 15,
                 rpe: p.accRPE, rest: 60, isMain: false),
        ]
    }

    // ── Slot factory ────────────────────────────────────────────────────────

    private static func slot(
        week: Int, session: SessionType, id: String, key: String,
        role: ExerciseRole, sets: Int, rLow: Int, rHigh: Int,
        rpe: Double, rest: Int, isMain: Bool
    ) -> ProgramSessionTemplate {
        ProgramSessionTemplate(
            programId: programId, programVersion: currentSeedVersion,
            week: week, sessionType: session,
            slotId: id, exerciseIndex: Int(id.last!.asciiValue! - 48) - 1,
            exerciseKey: key, role: role, isMainLift: isMain,
            targetSets: sets, targetRepsLow: rLow, targetRepsHigh: rHigh,
            targetRPE: rpe, restSeconds: rest
        )
    }
}
