import SwiftData
import Foundation

// ═══════════════════════════════════════════
// BEGINNER FULL BODY SEEDER  v1
// Seeds programId = 4 — 12 weeks
//
// 3-day Full Body A/B alternating:
//   A = Squat + Bench + Row + OHP + Curl + Calf Raise
//   B = Deadlift + OHP + Pulldown + Bench (DB) + Tricep Pushdown + Leg Curl
//
// Schedule: Mon A / Wed B / Fri A → Mon B / Wed A / Fri B
//
// Periodization:
//   Block 1 (Weeks 1–6):  Linear Progression — RPE 7, add weight each session
//   Block 2 (Weeks 7–12): Volume Phase       — RPE 7.5, add sets
//   Deloads: Weeks 4, 8
//
// Design:
//   - Every session hits full body via compound movements
//   - Linear progression exploits the novice window
//   - Low accessory count to keep sessions under 60 min
//   - A/B split ensures squat + deadlift don't compete in same session
//   - 5 reps on main lifts for strength, 8-12 on accessories for hypertrophy
// ═══════════════════════════════════════════

enum BeginnerSeeder {

    static let programId          = 4
    static let currentSeedVersion = 1

    static func seedIfNeeded(context: ModelContext) {
        var tDesc = FetchDescriptor<ProgramTemplate>(
            predicate: #Predicate { $0.programId == 4 }
        )
        tDesc.fetchLimit = 1
        let existing = (try? context.fetch(tDesc)) ?? []

        if let tmpl = existing.first {
            guard tmpl.version < currentSeedVersion else { return }
            context.delete(tmpl)
            let slotDesc = FetchDescriptor<ProgramSessionTemplate>(
                predicate: #Predicate { $0.programId == 4 }
            )
            for s in (try? context.fetch(slotDesc)) ?? [] { context.delete(s) }
        }

        let template = ProgramTemplate(
            programId: programId,
            name: "Beginner Full Body",
            version: currentSeedVersion,
            durationWeeks: 12,
            sessionTypes: [.fullBodyA, .fullBodyB, .fullBodyA],
            scheduleOptions: ["Mon/Wed/Fri"]
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
                     mainS: 2, mainRL: 5, mainRH: 5, mainRPE: 6.0, mainRest: 150,
                     accS: 2, accRL: 8, accRH: 10, accRPE: 6.0, accRest: 60)
        }
        if w <= 6 {
            return P(isDeload: false,
                     mainS: 3, mainRL: 5, mainRH: 5, mainRPE: 7.0, mainRest: 180,
                     accS: 3, accRL: 8, accRH: 12, accRPE: 7.0, accRest: 90)
        }
        return P(isDeload: false,
                 mainS: 4, mainRL: 5, mainRH: 8, mainRPE: 7.5, mainRest: 180,
                 accS: 3, accRL: 10, accRH: 12, accRPE: 7.0, accRest: 90)
    }

    private static func buildAllSlots() -> [ProgramSessionTemplate] {
        var all: [ProgramSessionTemplate] = []
        for w in 1...12 {
            let p = params(w)
            // A — Squat-focused full body
            all += [
                s(w, .fullBodyA, "A1", "squat_barbell", .mainLift, p.mainS, p.mainRL, p.mainRH, p.mainRPE, p.mainRest, true),
                s(w, .fullBodyA, "A2", "bench_press_barbell", .mainLift, p.mainS, p.mainRL, p.mainRH, p.mainRPE, p.mainRest, true),
                s(w, .fullBodyA, "A3", "row_barbell", .supplemental, p.mainS, p.mainRL, p.mainRH, p.mainRPE, p.mainRest, false),
                s(w, .fullBodyA, "A4", "ohp_dumbbell", .accessory, p.accS, p.accRL, p.accRH, p.accRPE, p.accRest, false),
                s(w, .fullBodyA, "A5", "curl_dumbbell", .accessory, p.accS, p.accRL, p.accRH, p.accRPE, p.accRest, false),
                s(w, .fullBodyA, "A6", "calf_raise_standing", .finisher, 3, 10, 15, p.accRPE, 60, false),
            ]
            // B — Deadlift-focused full body
            all += [
                s(w, .fullBodyB, "B1", "deadlift_barbell", .mainLift, p.mainS, p.mainRL, p.mainRH, p.mainRPE, p.mainRest, true),
                s(w, .fullBodyB, "B2", "ohp_barbell", .mainLift, p.mainS, p.mainRL, p.mainRH, p.mainRPE, p.mainRest, true),
                s(w, .fullBodyB, "B3", "pulldown_wide", .supplemental, p.mainS, p.accRL, p.accRH, p.accRPE, 120, false),
                s(w, .fullBodyB, "B4", "bench_press_dumbbell", .accessory, p.accS, p.accRL, p.accRH, p.accRPE, p.accRest, false),
                s(w, .fullBodyB, "B5", "tricep_pushdown_rope", .accessory, p.accS, p.accRL, p.accRH, p.accRPE, 60, false),
                s(w, .fullBodyB, "B6", "leg_curl_lying", .finisher, 3, 10, 12, p.accRPE, 60, false),
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
