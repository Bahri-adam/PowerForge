import SwiftData
import Foundation

// ═══════════════════════════════════════════
// MINIMALIST PROGRAM SEEDER  v1
// Seeds programId = 6 — 12 weeks
//
// 3-day Full Body, compound-only:
//   A = Squat + Bench + Row + Face Pull
//   B = Deadlift + OHP + Chinup + Lateral Raise
//   C = Front Squat + Incline DB Press + Cable Row + Hip Thrust
//
// Schedule: Mon A / Wed B / Fri C
//
// Periodization:
//   Block 1 (Weeks 1–6):  Maintenance    — RPE 7, 3 sets, 35-40 min sessions
//   Block 2 (Weeks 7–12): Progression    — RPE 7.5, 3-4 sets, slow volume ramp
//   Deloads: Weeks 4, 8
//
// Design:
//   - 4 exercises per session max — no isolation, no fluff
//   - Every compound movement covers 2-3 muscle groups
//   - 3 sessions/week = ~9-12 sets per major muscle group
//   - Squat/Deadlift/Front Squat rotation covers quads, glutes, hamstrings, back
//   - Bench/OHP/Incline covers chest, delts, triceps
//   - Row/Chinup/Cable Row covers back, biceps
//   - Face pull + lateral raise = minimal shoulder health work
//   - Hip thrust on day C = glute emphasis without a dedicated leg day
// ═══════════════════════════════════════════

enum MinimalistSeeder {

    static let programId          = 6
    static let currentSeedVersion = 1

    static func seedIfNeeded(context: ModelContext) {
        var tDesc = FetchDescriptor<ProgramTemplate>(
            predicate: #Predicate { $0.programId == 6 }
        )
        tDesc.fetchLimit = 1
        let existing = (try? context.fetch(tDesc)) ?? []

        if let tmpl = existing.first {
            guard tmpl.version < currentSeedVersion else { return }
            context.delete(tmpl)
            let slotDesc = FetchDescriptor<ProgramSessionTemplate>(
                predicate: #Predicate { $0.programId == 6 }
            )
            for s in (try? context.fetch(slotDesc)) ?? [] { context.delete(s) }
        }

        let template = ProgramTemplate(
            programId: programId,
            name: "Minimalist",
            version: currentSeedVersion,
            durationWeeks: 12,
            sessionTypes: [.fullBodyA, .fullBodyB, .fullBody],
            scheduleOptions: ["Mon/Wed/Fri", "Tue/Thu/Sat"]
        )
        context.insert(template)
        for slot in buildAllSlots() { context.insert(slot) }
        try? context.save()
    }

    struct P {
        let isDeload: Bool
        let mainS: Int; let mainRL: Int; let mainRH: Int; let mainRPE: Double; let mainRest: Int
        let accS: Int; let accRL: Int; let accRH: Int; let accRPE: Double; let accRest: Int
    }

    private static func params(_ w: Int) -> P {
        if [4, 8].contains(w) {
            return P(isDeload: true,
                     mainS: 2, mainRL: 5, mainRH: 8, mainRPE: 6.0, mainRest: 120,
                     accS: 2, accRL: 8, accRH: 12, accRPE: 6.0, accRest: 60)
        }
        if w <= 6 {
            return P(isDeload: false,
                     mainS: 3, mainRL: 5, mainRH: 8, mainRPE: 7.0, mainRest: 150,
                     accS: 3, accRL: 8, accRH: 12, accRPE: 7.0, accRest: 60)
        }
        return P(isDeload: false,
                 mainS: 4, mainRL: 5, mainRH: 8, mainRPE: 7.5, mainRest: 180,
                 accS: 3, accRL: 8, accRH: 12, accRPE: 7.0, accRest: 60)
    }

    private static func buildAllSlots() -> [ProgramSessionTemplate] {
        var all: [ProgramSessionTemplate] = []
        for w in 1...12 {
            let p = params(w)
            // A — Squat + Bench + Row + Face Pull
            all += [
                s(w, .fullBodyA, "A1", "squat_barbell", .mainLift, p.mainS, p.mainRL, p.mainRH, p.mainRPE, p.mainRest, true),
                s(w, .fullBodyA, "A2", "bench_press_barbell", .mainLift, p.mainS, p.mainRL, p.mainRH, p.mainRPE, p.mainRest, true),
                s(w, .fullBodyA, "A3", "row_barbell", .supplemental, p.mainS, p.mainRL, p.mainRH, p.mainRPE, p.mainRest, false),
                s(w, .fullBodyA, "A4", "face_pull_cable", .accessory, p.accS, 12, 15, p.accRPE, p.accRest, false),
            ]
            // B — Deadlift + OHP + Chinup + Lateral Raise
            all += [
                s(w, .fullBodyB, "B1", "deadlift_barbell", .mainLift, p.mainS, p.mainRL, p.mainRH, p.mainRPE, p.mainRest, true),
                s(w, .fullBodyB, "B2", "ohp_barbell", .mainLift, p.mainS, p.mainRL, p.mainRH, p.mainRPE, p.mainRest, true),
                s(w, .fullBodyB, "B3", "chinup", .supplemental, p.mainS, p.accRL, p.accRH, p.accRPE, 120, false),
                s(w, .fullBodyB, "B4", "lateral_raise_dumbbell", .accessory, p.accS, 12, 15, p.accRPE, p.accRest, false),
            ]
            // C — Front Squat + Incline DB + Cable Row + Hip Thrust
            all += [
                s(w, .fullBody, "C1", "squat_front", .mainLift, p.mainS, p.mainRL, p.mainRH, p.mainRPE, p.mainRest, true),
                s(w, .fullBody, "C2", "bench_press_incline_dumbbell", .supplemental, p.mainS, p.accRL, p.accRH, p.accRPE, 120, false),
                s(w, .fullBody, "C3", "row_cable_narrow", .supplemental, p.mainS, p.accRL, p.accRH, p.accRPE, 90, false),
                s(w, .fullBody, "C4", "hip_thrust_barbell", .accessory, p.accS, 8, 12, p.accRPE, 90, false),
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
