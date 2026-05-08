import SwiftData
import Foundation

// ═══════════════════════════════════════════
// PPL HYPERTROPHY SEEDER  v1
// Seeds programId = 2 (Pure Hypertrophy PPL) — 16 weeks
//
// 6-day Push/Pull/Legs A/B alternating:
//   Push A — Bench emphasis (Chest · OHP · Laterals · Triceps)
//   Pull A — Row emphasis   (Row · Pulldown · Cable Row · Face Pull · Curls)
//   Legs A — Squat emphasis (Squat · Leg Press · Ext · Curl · Calves)
//   Push B — OHP emphasis   (OHP · Incline · Fly · Laterals · Triceps)
//   Pull B — Deadlift emph  (Deadlift · DB Row · Pulldown · Curls)
//   Legs B — RDL emphasis   (RDL · Leg Press · Curl · Ext · Calves)
//
// Periodization:
//   Block 1 (Weeks 1–8):  Accumulation    — RPE 7.5–8.5, volume builds
//   Block 2 (Weeks 9–16): Intensification — RPE 8.0–9.0, heavier, slightly less volume
//   Deload weeks: 4, 12
//   Week 16: Final deload / movement prep
//
// slotId convention: "[SessionLetter][SlotNumber]"
//   A = Push A, B = Pull A, C = Legs A, D = Push B, E = Pull B, F = Legs B
// ═══════════════════════════════════════════

enum PPLSeeder {

    static let programId          = 2
    static let currentSeedVersion = 2

    // ── Public entry point ──

    static func seedPPLProgram(context: ModelContext) {

        var tDesc = FetchDescriptor<ProgramTemplate>(
            predicate: #Predicate { $0.programId == 2 }
        )
        tDesc.fetchLimit = 1
        let existing = (try? context.fetch(tDesc)) ?? []

        if let old = existing.first {
            guard old.version < currentSeedVersion else { return }
            context.delete(old)
            let slotDesc = FetchDescriptor<ProgramSessionTemplate>(
                predicate: #Predicate { $0.programId == 2 }
            )
            let staleSlots = (try? context.fetch(slotDesc)) ?? []
            for s in staleSlots { context.delete(s) }
        }

        let template = ProgramTemplate(
            programId: programId,
            name: "Pure Hypertrophy (PPL)",
            version: currentSeedVersion,
            durationWeeks: 16,
            sessionTypes: [.pushA, .pullA, .legsA, .pushB, .pullB, .legsB],
            scheduleOptions: ["Mon/Tue/Wed/Fri/Sat/Sun"]
        )
        context.insert(template)

        for slot in buildAllSlots() { context.insert(slot) }
        try? context.save()
    }

    // ── Build all 16 weeks ──

    private static func buildAllSlots() -> [ProgramSessionTemplate] {
        var all: [ProgramSessionTemplate] = []
        for week in 1...16 {
            let p = params(week: week)
            all += pushASlots(week: week, p: p)
            all += pullASlots(week: week, p: p)
            all += legsASlots(week: week, p: p)
            all += pushBSlots(week: week, p: p)
            all += pullBSlots(week: week, p: p)
            all += legsBSlots(week: week, p: p)
        }
        return all
    }

    // ═══════════════════════════════════════════
    // PERIODIZATION PARAMS
    // ═══════════════════════════════════════════

    struct P {
        let isDeload: Bool
        let mainSets: Int;  let mainLow: Int;  let mainHigh: Int;  let mainRPE: Double;  let mainRest: Int
        let suppSets: Int;  let suppLow: Int;  let suppHigh: Int;  let suppRPE: Double;  let suppRest: Int
        let accSets: Int;   let accLow: Int;   let accHigh: Int;   let accRPE: Double;   let accRest: Int
    }

    private static func params(week: Int) -> P {
        switch week {
        // ── Block 1: Accumulation ──
        case 1:
            return P(isDeload: false,
                     mainSets: 4, mainLow: 4, mainHigh: 6, mainRPE: 7.5, mainRest: 240,
                     suppSets: 3, suppLow: 8, suppHigh: 10, suppRPE: 7.5, suppRest: 150,
                     accSets: 3, accLow: 12, accHigh: 15, accRPE: 7.5, accRest: 90)
        case 2:
            return P(isDeload: false,
                     mainSets: 4, mainLow: 4, mainHigh: 6, mainRPE: 8.0, mainRest: 240,
                     suppSets: 3, suppLow: 8, suppHigh: 10, suppRPE: 8.0, suppRest: 150,
                     accSets: 3, accLow: 12, accHigh: 15, accRPE: 7.5, accRest: 90)
        case 3:
            return P(isDeload: false,
                     mainSets: 4, mainLow: 4, mainHigh: 6, mainRPE: 8.5, mainRest: 240,
                     suppSets: 4, suppLow: 8, suppHigh: 10, suppRPE: 8.0, suppRest: 150,
                     accSets: 4, accLow: 12, accHigh: 15, accRPE: 8.0, accRest: 90)
        case 4: // DELOAD
            return P(isDeload: true,
                     mainSets: 2, mainLow: 4, mainHigh: 6, mainRPE: 6.0, mainRest: 180,
                     suppSets: 2, suppLow: 8, suppHigh: 10, suppRPE: 6.0, suppRest: 120,
                     accSets: 2, accLow: 12, accHigh: 15, accRPE: 6.0, accRest: 60)
        case 5:
            return P(isDeload: false,
                     mainSets: 4, mainLow: 4, mainHigh: 6, mainRPE: 8.0, mainRest: 240,
                     suppSets: 3, suppLow: 8, suppHigh: 10, suppRPE: 8.0, suppRest: 150,
                     accSets: 3, accLow: 12, accHigh: 15, accRPE: 8.0, accRest: 90)
        case 6:
            return P(isDeload: false,
                     mainSets: 4, mainLow: 4, mainHigh: 6, mainRPE: 8.5, mainRest: 240,
                     suppSets: 4, suppLow: 8, suppHigh: 10, suppRPE: 8.0, suppRest: 150,
                     accSets: 4, accLow: 12, accHigh: 15, accRPE: 8.0, accRest: 90)
        case 7:
            return P(isDeload: false,
                     mainSets: 5, mainLow: 4, mainHigh: 6, mainRPE: 8.5, mainRest: 270,
                     suppSets: 4, suppLow: 8, suppHigh: 10, suppRPE: 8.5, suppRest: 150,
                     accSets: 4, accLow: 12, accHigh: 15, accRPE: 8.0, accRest: 90)
        case 8: // Intensity ramp into Block 2
            return P(isDeload: false,
                     mainSets: 4, mainLow: 3, mainHigh: 5, mainRPE: 8.5, mainRest: 270,
                     suppSets: 3, suppLow: 6, suppHigh: 8, suppRPE: 8.5, suppRest: 180,
                     accSets: 3, accLow: 10, accHigh: 12, accRPE: 8.0, accRest: 90)

        // ── Block 2: Intensification ──
        case 9:
            return P(isDeload: false,
                     mainSets: 4, mainLow: 3, mainHigh: 5, mainRPE: 8.5, mainRest: 270,
                     suppSets: 3, suppLow: 6, suppHigh: 8, suppRPE: 8.5, suppRest: 180,
                     accSets: 3, accLow: 10, accHigh: 12, accRPE: 8.0, accRest: 90)
        case 10:
            return P(isDeload: false,
                     mainSets: 4, mainLow: 3, mainHigh: 5, mainRPE: 9.0, mainRest: 270,
                     suppSets: 3, suppLow: 6, suppHigh: 8, suppRPE: 8.5, suppRest: 180,
                     accSets: 3, accLow: 10, accHigh: 12, accRPE: 8.5, accRest: 90)
        case 11:
            return P(isDeload: false,
                     mainSets: 5, mainLow: 3, mainHigh: 5, mainRPE: 9.0, mainRest: 300,
                     suppSets: 4, suppLow: 6, suppHigh: 8, suppRPE: 8.5, suppRest: 180,
                     accSets: 4, accLow: 10, accHigh: 12, accRPE: 8.5, accRest: 90)
        case 12: // DELOAD
            return P(isDeload: true,
                     mainSets: 2, mainLow: 3, mainHigh: 5, mainRPE: 6.0, mainRest: 180,
                     suppSets: 2, suppLow: 6, suppHigh: 8, suppRPE: 6.0, suppRest: 120,
                     accSets: 2, accLow: 10, accHigh: 12, accRPE: 6.0, accRest: 60)
        case 13:
            return P(isDeload: false,
                     mainSets: 4, mainLow: 3, mainHigh: 5, mainRPE: 8.5, mainRest: 270,
                     suppSets: 3, suppLow: 6, suppHigh: 8, suppRPE: 8.5, suppRest: 180,
                     accSets: 3, accLow: 10, accHigh: 12, accRPE: 8.0, accRest: 90)
        case 14:
            return P(isDeload: false,
                     mainSets: 5, mainLow: 3, mainHigh: 5, mainRPE: 9.0, mainRest: 300,
                     suppSets: 4, suppLow: 6, suppHigh: 8, suppRPE: 9.0, suppRest: 180,
                     accSets: 4, accLow: 10, accHigh: 12, accRPE: 8.5, accRest: 90)
        case 15:
            return P(isDeload: false,
                     mainSets: 5, mainLow: 2, mainHigh: 4, mainRPE: 9.0, mainRest: 300,
                     suppSets: 3, suppLow: 5, suppHigh: 7, suppRPE: 9.0, suppRest: 180,
                     accSets: 3, accLow: 8, accHigh: 10, accRPE: 8.5, accRest: 90)
        case 16: // Final deload
            return P(isDeload: true,
                     mainSets: 2, mainLow: 3, mainHigh: 5, mainRPE: 5.5, mainRest: 180,
                     suppSets: 2, suppLow: 6, suppHigh: 8, suppRPE: 5.5, suppRest: 120,
                     accSets: 2, accLow: 10, accHigh: 12, accRPE: 5.5, accRest: 60)

        default:
            return P(isDeload: false,
                     mainSets: 4, mainLow: 4, mainHigh: 6, mainRPE: 8.0, mainRest: 240,
                     suppSets: 3, suppLow: 8, suppHigh: 10, suppRPE: 8.0, suppRest: 150,
                     accSets: 3, accLow: 12, accHigh: 15, accRPE: 8.0, accRest: 90)
        }
    }

    // ═══════════════════════════════════════════
    // SESSION SLOT BUILDERS
    // ═══════════════════════════════════════════

    // ── Push A — Bench emphasis ──

    private static func pushASlots(week: Int, p: P) -> [ProgramSessionTemplate] {
        let note = p.isDeload ? "Deload — reduce load ~40%" : ""
        return [
            slot(w: week, st: .pushA, id: "A1", idx: 0, key: "bench_press_barbell",
                 role: .mainLift, main: true, sets: p.mainSets, lo: p.mainLow, hi: p.mainHigh,
                 rpe: p.mainRPE, rest: p.mainRest, note: note),
            slot(w: week, st: .pushA, id: "A2", idx: 1, key: "bench_press_incline_dumbbell",
                 role: .supplemental, sets: p.suppSets, lo: p.suppLow, hi: p.suppHigh,
                 rpe: p.suppRPE, rest: p.suppRest, note: note),
            slot(w: week, st: .pushA, id: "A3", idx: 2, key: "cable_fly_neutral",
                 role: .accessory, sets: p.accSets, lo: p.accLow, hi: p.accHigh,
                 rpe: p.accRPE, rest: p.accRest, note: note),
            slot(w: week, st: .pushA, id: "A4", idx: 3, key: "ohp_barbell",
                 role: .supplemental, sets: p.suppSets, lo: p.suppLow, hi: p.suppHigh,
                 rpe: p.suppRPE, rest: p.suppRest, note: note),
            slot(w: week, st: .pushA, id: "A5", idx: 4, key: "lateral_raise_cable",
                 role: .accessory, sets: p.accSets, lo: max(p.accLow, 15), hi: max(p.accHigh, 20),
                 rpe: p.accRPE, rest: 60, note: note),
            slot(w: week, st: .pushA, id: "A6", idx: 5, key: "tricep_pushdown_cable",
                 role: .accessory, sets: p.accSets, lo: p.accLow, hi: p.accHigh,
                 rpe: p.accRPE, rest: p.accRest, note: note)
        ]
    }

    // ── Pull A — Row emphasis ──

    private static func pullASlots(week: Int, p: P) -> [ProgramSessionTemplate] {
        let note = p.isDeload ? "Deload — reduce load ~40%" : ""
        return [
            slot(w: week, st: .pullA, id: "B1", idx: 0, key: "row_barbell",
                 role: .mainLift, main: true, sets: p.mainSets, lo: p.mainLow, hi: p.mainHigh,
                 rpe: p.mainRPE, rest: p.mainRest, note: note),
            slot(w: week, st: .pullA, id: "B2", idx: 1, key: "pulldown_cable",
                 role: .supplemental, sets: p.suppSets, lo: p.suppLow, hi: p.suppHigh,
                 rpe: p.suppRPE, rest: p.suppRest, note: note),
            slot(w: week, st: .pullA, id: "B3", idx: 2, key: "row_cable_neutral",
                 role: .supplemental, sets: p.suppSets, lo: max(p.suppLow, 10), hi: max(p.suppHigh, 12),
                 rpe: p.suppRPE, rest: p.suppRest, note: note),
            slot(w: week, st: .pullA, id: "B4", idx: 3, key: "face_pull_cable",
                 role: .accessory, sets: p.accSets, lo: max(p.accLow, 15), hi: max(p.accHigh, 20),
                 rpe: p.accRPE, rest: 60, note: note),
            slot(w: week, st: .pullA, id: "B5", idx: 4, key: "curl_incline_dumbbell",
                 role: .accessory, sets: p.accSets, lo: p.accLow, hi: p.accHigh,
                 rpe: p.accRPE, rest: p.accRest, note: note),
            slot(w: week, st: .pullA, id: "B6", idx: 5, key: "curl_hammer",
                 role: .accessory, sets: p.accSets, lo: p.accLow, hi: p.accHigh,
                 rpe: p.accRPE, rest: p.accRest, note: note)
        ]
    }

    // ── Legs A — Squat emphasis ──

    private static func legsASlots(week: Int, p: P) -> [ProgramSessionTemplate] {
        let note = p.isDeload ? "Deload — reduce load ~40%" : ""
        return [
            slot(w: week, st: .legsA, id: "C1", idx: 0, key: "squat_barbell",
                 role: .mainLift, main: true, sets: p.mainSets, lo: p.mainLow, hi: p.mainHigh,
                 rpe: p.mainRPE, rest: p.mainRest, note: note),
            slot(w: week, st: .legsA, id: "C2", idx: 1, key: "leg_press",
                 role: .supplemental, sets: p.suppSets, lo: max(p.suppLow, 10), hi: max(p.suppHigh, 12),
                 rpe: p.suppRPE, rest: p.suppRest, note: note),
            slot(w: week, st: .legsA, id: "C3", idx: 2, key: "leg_extension",
                 role: .accessory, sets: p.accSets, lo: p.accLow, hi: p.accHigh,
                 rpe: p.accRPE, rest: p.accRest, note: note),
            slot(w: week, st: .legsA, id: "C4", idx: 3, key: "leg_curl_lying",
                 role: .accessory, sets: p.accSets, lo: max(p.accLow, 10), hi: max(p.accHigh, 12),
                 rpe: p.accRPE, rest: p.accRest, note: note),
            slot(w: week, st: .legsA, id: "C5", idx: 4, key: "calf_raise_standing",
                 role: .accessory, sets: 4, lo: p.accLow, hi: p.accHigh,
                 rpe: p.accRPE, rest: 60, note: note)
        ]
    }

    // ── Push B — OHP emphasis ──

    private static func pushBSlots(week: Int, p: P) -> [ProgramSessionTemplate] {
        let note = p.isDeload ? "Deload — reduce load ~40%" : ""
        return [
            slot(w: week, st: .pushB, id: "D1", idx: 0, key: "ohp_barbell",
                 role: .mainLift, main: true, sets: p.mainSets, lo: p.mainLow, hi: p.mainHigh,
                 rpe: p.mainRPE, rest: p.mainRest, note: note),
            slot(w: week, st: .pushB, id: "D2", idx: 1, key: "bench_press_incline_dumbbell",
                 role: .supplemental, sets: p.suppSets, lo: p.suppLow, hi: p.suppHigh,
                 rpe: p.suppRPE, rest: p.suppRest, note: note),
            slot(w: week, st: .pushB, id: "D3", idx: 2, key: "cable_fly_neutral",
                 role: .accessory, sets: p.accSets, lo: p.accLow, hi: p.accHigh,
                 rpe: p.accRPE, rest: p.accRest, note: note),
            slot(w: week, st: .pushB, id: "D4", idx: 3, key: "lateral_raise_dumbbell",
                 role: .accessory, sets: p.accSets, lo: max(p.accLow, 15), hi: max(p.accHigh, 20),
                 rpe: p.accRPE, rest: 60, note: note),
            slot(w: week, st: .pushB, id: "D5", idx: 4, key: "tricep_overhead_cable",
                 role: .accessory, sets: p.accSets, lo: p.accLow, hi: p.accHigh,
                 rpe: p.accRPE, rest: p.accRest, note: note),
            slot(w: week, st: .pushB, id: "D6", idx: 5, key: "tricep_pushdown_cable",
                 role: .finisher, sets: max(2, p.accSets - 1), lo: max(p.accLow, 15), hi: max(p.accHigh, 20),
                 rpe: p.accRPE, rest: 60, note: note)
        ]
    }

    // ── Pull B — Deadlift emphasis ──

    private static func pullBSlots(week: Int, p: P) -> [ProgramSessionTemplate] {
        let note = p.isDeload ? "Deload — reduce load ~40%" : ""
        return [
            slot(w: week, st: .pullB, id: "E1", idx: 0, key: "deadlift_barbell",
                 role: .mainLift, main: true, sets: p.mainSets, lo: max(p.mainLow, 3), hi: max(p.mainHigh, 5),
                 rpe: p.mainRPE, rest: p.mainRest, note: note),
            slot(w: week, st: .pullB, id: "E2", idx: 1, key: "row_dumbbell",
                 role: .supplemental, sets: p.suppSets, lo: p.suppLow, hi: p.suppHigh,
                 rpe: p.suppRPE, rest: p.suppRest, note: note),
            slot(w: week, st: .pullB, id: "E3", idx: 2, key: "pulldown_cable",
                 role: .supplemental, sets: p.suppSets, lo: max(p.suppLow, 10), hi: max(p.suppHigh, 12),
                 rpe: p.suppRPE, rest: p.suppRest, note: note),
            slot(w: week, st: .pullB, id: "E4", idx: 3, key: "face_pull_cable",
                 role: .accessory, sets: p.accSets, lo: max(p.accLow, 15), hi: max(p.accHigh, 20),
                 rpe: p.accRPE, rest: 60, note: note),
            slot(w: week, st: .pullB, id: "E5", idx: 4, key: "curl_barbell",
                 role: .accessory, sets: p.accSets, lo: max(p.accLow, 10), hi: max(p.accHigh, 12),
                 rpe: p.accRPE, rest: p.accRest, note: note),
            slot(w: week, st: .pullB, id: "E6", idx: 5, key: "curl_incline_dumbbell",
                 role: .finisher, sets: max(2, p.accSets - 1), lo: max(p.accLow, 15), hi: max(p.accHigh, 20),
                 rpe: p.accRPE, rest: 60, note: note)
        ]
    }

    // ── Legs B — RDL / posterior emphasis ──

    private static func legsBSlots(week: Int, p: P) -> [ProgramSessionTemplate] {
        let note = p.isDeload ? "Deload — reduce load ~40%" : ""
        return [
            slot(w: week, st: .legsB, id: "F1", idx: 0, key: "rdl_barbell",
                 role: .mainLift, main: true, sets: p.mainSets, lo: max(p.mainLow, 6), hi: max(p.mainHigh, 8),
                 rpe: p.mainRPE, rest: p.mainRest, note: note),
            slot(w: week, st: .legsB, id: "F2", idx: 1, key: "leg_press",
                 role: .supplemental, sets: p.suppSets, lo: max(p.suppLow, 10), hi: max(p.suppHigh, 12),
                 rpe: p.suppRPE, rest: p.suppRest, note: note),
            slot(w: week, st: .legsB, id: "F3", idx: 2, key: "leg_curl_lying",
                 role: .accessory, sets: p.accSets, lo: max(p.accLow, 10), hi: max(p.accHigh, 12),
                 rpe: p.accRPE, rest: p.accRest, note: note),
            slot(w: week, st: .legsB, id: "F4", idx: 3, key: "leg_extension",
                 role: .accessory, sets: p.accSets, lo: p.accLow, hi: p.accHigh,
                 rpe: p.accRPE, rest: p.accRest, note: note),
            slot(w: week, st: .legsB, id: "F5", idx: 4, key: "calf_raise_seated",
                 role: .accessory, sets: 4, lo: max(p.accLow, 15), hi: max(p.accHigh, 20),
                 rpe: p.accRPE, rest: 60, note: note)
        ]
    }

    // ── Slot helper ──

    private static func slot(
        w: Int, st: SessionType, id: String, idx: Int, key: String,
        role: ExerciseRole = .accessory, main: Bool = false,
        sets: Int, lo: Int, hi: Int, rpe: Double, rest: Int, note: String = ""
    ) -> ProgramSessionTemplate {
        ProgramSessionTemplate(
            programId: programId,
            programVersion: 1,
            week: w,
            sessionType: st,
            slotId: id,
            exerciseIndex: idx,
            exerciseKey: key,
            role: role,
            isMainLift: main,
            targetSets: sets,
            targetRepsLow: lo,
            targetRepsHigh: hi,
            targetRPE: rpe,
            restSeconds: rest,
            notes: note
        )
    }
}
