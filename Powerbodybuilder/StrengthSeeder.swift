import SwiftData
import Foundation

// ═══════════════════════════════════════════
// STRENGTH PROGRAM SEEDER  v1
// Seeds programId = 3 — 16 weeks
//
// 4-day Squat / Bench / Deadlift / Bench2:
//   A = Squat Day     — squat (main), leg press, leg curl, leg extension
//   B = Bench Day     — bench (main), OHP, row, tricep pushdown, curl
//   C = Deadlift Day  — deadlift (main), RDL, pullup, barbell row, face pull
//   D = Bench Volume  — bench (supplemental), incline DB, pulldown, lateral raise, tricep overhead
//
// Periodization:
//   Block 1 (Weeks 1–8):  Accumulation    — RPE 7–7.5, volume base
//   Block 2 (Weeks 9–13): Intensification — RPE 8–9, load climbs
//   Block 3 (Weeks 14–16): Peaking        — RPE 9–9.5, volume drops, Week 16 testing
//   Deloads: Weeks 4, 8, 13
// ═══════════════════════════════════════════

enum StrengthSeeder {

    static let programId          = 3
    static let currentSeedVersion = 1

    static func seedIfNeeded(context: ModelContext) {
        var tDesc = FetchDescriptor<ProgramTemplate>(
            predicate: #Predicate { $0.programId == 3 }
        )
        tDesc.fetchLimit = 1
        let existing = (try? context.fetch(tDesc)) ?? []

        if let tmpl = existing.first {
            guard tmpl.version < currentSeedVersion else { return }
            context.delete(tmpl)
            let slotDesc = FetchDescriptor<ProgramSessionTemplate>(
                predicate: #Predicate { $0.programId == 3 }
            )
            for s in (try? context.fetch(slotDesc)) ?? [] { context.delete(s) }
        }

        let template = ProgramTemplate(
            programId: programId,
            name: "Strength",
            version: currentSeedVersion,
            durationWeeks: 16,
            sessionTypes: [.heavyUpper, .heavyLower, .hypertrophyUpper, .hypertrophyLower],
            scheduleOptions: ["Mon/Wed/Fri/Sat", "Mon/Tue/Thu/Fri"]
        )
        context.insert(template)
        for slot in buildAllSlots() { context.insert(slot) }
        try? context.save()
    }

    struct P {
        let isDeload: Bool; let isTesting: Bool
        let mainS: Int; let mainRL: Int; let mainRH: Int; let mainRPE: Double; let mainRest: Int
        let suppS: Int; let suppRL: Int; let suppRH: Int; let suppRPE: Double; let suppRest: Int
        let accS: Int; let accRL: Int; let accRH: Int; let accRPE: Double; let accRest: Int
    }

    private static func params(_ w: Int) -> P {
        if [4, 8, 13].contains(w) {
            return P(isDeload: true, isTesting: false,
                     mainS: 2, mainRL: 3, mainRH: 5, mainRPE: 6.0, mainRest: 180,
                     suppS: 2, suppRL: 6, suppRH: 8, suppRPE: 6.0, suppRest: 120,
                     accS: 2, accRL: 8, accRH: 10, accRPE: 6.0, accRest: 90)
        }
        if w == 16 {
            return P(isDeload: false, isTesting: true,
                     mainS: 3, mainRL: 1, mainRH: 3, mainRPE: 9.5, mainRest: 300,
                     suppS: 2, suppRL: 3, suppRH: 5, suppRPE: 8.0, suppRest: 240,
                     accS: 2, accRL: 6, accRH: 8, accRPE: 7.0, accRest: 90)
        }
        if w <= 8 {
            let post = w > 4
            return P(isDeload: false, isTesting: false,
                     mainS: post ? 5 : 4, mainRL: 3, mainRH: 5, mainRPE: post ? 7.5 : 7.0, mainRest: 240,
                     suppS: 3, suppRL: 5, suppRH: 8, suppRPE: 7.0, suppRest: 180,
                     accS: 3, accRL: 8, accRH: 12, accRPE: 7.0, accRest: 90)
        }
        if w <= 13 {
            let post = w > 8
            return P(isDeload: false, isTesting: false,
                     mainS: 5, mainRL: 2, mainRH: 4, mainRPE: post ? 8.5 : 8.0, mainRest: 270,
                     suppS: 3, suppRL: 4, suppRH: 6, suppRPE: 8.0, suppRest: 210,
                     accS: 3, accRL: 6, accRH: 10, accRPE: 7.5, accRest: 90)
        }
        return P(isDeload: false, isTesting: false,
                 mainS: 4, mainRL: 1, mainRH: 3, mainRPE: 9.0, mainRest: 300,
                 suppS: 2, suppRL: 3, suppRH: 5, suppRPE: 8.5, suppRest: 240,
                 accS: 2, accRL: 6, accRH: 8, accRPE: 7.0, accRest: 90)
    }

    private static func buildAllSlots() -> [ProgramSessionTemplate] {
        var all: [ProgramSessionTemplate] = []
        for w in 1...16 {
            let p = params(w)
            // A — Squat Day (uses heavyLower)
            all += [
                s(w, .heavyLower, "A1", "squat_barbell", .mainLift, p.mainS, p.mainRL, p.mainRH, p.mainRPE, p.mainRest, true),
                s(w, .heavyLower, "A2", "leg_press", .supplemental, p.suppS, p.suppRL, p.suppRH, p.suppRPE, p.suppRest, false),
                s(w, .heavyLower, "A3", "leg_curl_seated", .accessory, p.accS, p.accRL, p.accRH, p.accRPE, p.accRest, false),
                s(w, .heavyLower, "A4", "leg_extension", .accessory, p.accS, 8, 12, p.accRPE, p.accRest, false),
            ]
            // B — Bench Day (uses heavyUpper)
            all += [
                s(w, .heavyUpper, "B1", "bench_press_barbell", .mainLift, p.mainS, p.mainRL, p.mainRH, p.mainRPE, p.mainRest, true),
                s(w, .heavyUpper, "B2", "ohp_barbell", .supplemental, p.suppS, p.suppRL, p.suppRH, p.suppRPE, p.suppRest, false),
                s(w, .heavyUpper, "B3", "row_barbell", .supplemental, p.suppS, p.suppRL, p.suppRH, p.suppRPE, p.suppRest, false),
                s(w, .heavyUpper, "B4", "tricep_pushdown_cable", .accessory, p.accS, 8, 12, p.accRPE, 60, false),
                s(w, .heavyUpper, "B5", "curl_barbell", .accessory, p.accS, 8, 12, p.accRPE, 60, false),
            ]
            // C — Deadlift Day (uses hypertrophyLower)
            all += [
                s(w, .hypertrophyLower, "C1", "deadlift_barbell", .mainLift, p.mainS, p.mainRL, p.mainRH, p.mainRPE, p.mainRest, true),
                s(w, .hypertrophyLower, "C2", "rdl_barbell", .supplemental, p.suppS, p.suppRL, p.suppRH, p.suppRPE, p.suppRest, false),
                s(w, .hypertrophyLower, "C3", "pullup", .accessory, p.accS, p.accRL, p.accRH, p.accRPE, 120, false),
                s(w, .hypertrophyLower, "C4", "row_barbell_underhand", .accessory, p.accS, p.accRL, p.accRH, p.accRPE, 90, false),
                s(w, .hypertrophyLower, "C5", "face_pull_cable", .accessory, 3, 12, 15, p.accRPE, 60, false),
            ]
            // D — Bench Volume (uses hypertrophyUpper)
            all += [
                s(w, .hypertrophyUpper, "D1", "bench_press_barbell", .supplemental, p.suppS, p.suppRL, p.suppRH, p.suppRPE, p.suppRest, true),
                s(w, .hypertrophyUpper, "D2", "bench_press_incline_dumbbell", .accessory, p.accS, 6, 10, p.accRPE, 120, false),
                s(w, .hypertrophyUpper, "D3", "pulldown_wide", .accessory, p.accS, 8, 12, p.accRPE, 90, false),
                s(w, .hypertrophyUpper, "D4", "lateral_raise_dumbbell", .accessory, 3, 12, 15, p.accRPE, 60, false),
                s(w, .hypertrophyUpper, "D5", "tricep_overhead_cable", .accessory, 3, 10, 15, p.accRPE, 60, false),
            ]
        }
        return all
    }

    private static func s(_ w: Int, _ st: SessionType, _ id: String, _ key: String,
                           _ role: ExerciseRole, _ sets: Int, _ rl: Int, _ rh: Int,
                           _ rpe: Double, _ rest: Int, _ main: Bool) -> ProgramSessionTemplate {
        ProgramSessionTemplate(
            programId: programId, programVersion: currentSeedVersion,
            week: w, sessionType: st, slotId: id,
            exerciseIndex: Int(id.last!.asciiValue! - 48) - 1,
            exerciseKey: key, role: role, isMainLift: main,
            targetSets: sets, targetRepsLow: rl, targetRepsHigh: rh,
            targetRPE: rpe, restSeconds: rest
        )
    }
}
