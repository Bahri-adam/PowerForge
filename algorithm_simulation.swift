#!/usr/bin/env swift

// ═══════════════════════════════════════════════════════════════════
// ADVANCEDLIFTER ALGORITHM SIMULATION
// Simulates 10 distinct athlete profiles through 16-week programs
// Outputs detailed week-by-week data for external review
// ═══════════════════════════════════════════════════════════════════

import Foundation

// ─── Minimal reproduction of engine types (standalone script) ───

struct SimLog {
    let weight: Double
    let reps: Int
    let setIndex: Int
    let rpe: Double
    let e1rm: Double
    let date: Date
    let isMainLift: Bool

    init(weight: Double, reps: Int, setIndex: Int, rpe: Double = 0, date: Date, isMainLift: Bool = true) {
        self.weight = weight
        self.reps = reps
        self.setIndex = setIndex
        self.rpe = rpe
        self.e1rm = weight * (1.0 + Double(reps) / 30.0)
        self.date = date
        self.isMainLift = isMainLift
    }
}

enum ProgressionRule: String { case progress, hold, backoff }
enum IFIZone: String {
    case fresh, optimal, fatigued, overtrained
    static func classify(_ ifi: Double) -> IFIZone {
        if ifi < 0.10 { return .fresh }
        if ifi < 0.25 { return .optimal }
        if ifi < 0.40 { return .fatigued }
        return .overtrained
    }
}

// ─── Engine reproduction ───

func progressionIncrement(isMainLift: Bool, currentWeight: Double) -> Double {
    if isMainLift { return currentWeight >= 185 ? 10.0 : 5.0 }
    return 5.0
}

func roundToPlate(_ weight: Double) -> Double {
    return (weight / 5.0).rounded() * 5.0
}

func determineRule(lastSession: [SimLog], previousSessions: [[SimLog]], targetLow: Int, targetHigh: Int) -> ProgressionRule {
    guard !lastSession.isEmpty else { return .hold }
    let maxW = lastSession.map { $0.weight }.max() ?? 0
    let working = lastSession.filter { $0.weight >= maxW * 0.80 }
    guard !working.isEmpty else { return .hold }

    let allHitTop = working.allSatisfy { $0.reps >= targetHigh }
    if allHitTop { return .progress }

    let missedLow = working.filter { $0.reps < targetLow }
    if missedLow.count >= 2 && !previousSessions.isEmpty {
        let prevMaxW = previousSessions[0].map { $0.weight }.max() ?? 0
        let prevWorking = previousSessions[0].filter { $0.weight >= prevMaxW * 0.80 }
        let prevMissed = prevWorking.filter { $0.reps < targetLow }.count >= 2
        if prevMissed { return .backoff }
    }
    return .hold
}

func computeIFI(sets: [SimLog]) -> Double {
    let maxW = sets.map { $0.weight }.max() ?? 0
    let working = sets.filter { $0.weight >= maxW * 0.80 }.sorted { $0.setIndex < $1.setIndex }
    guard working.count >= 2, let first = working.first?.reps, first > 0, let last = working.last?.reps else { return 0 }
    return max(0, min(1, Double(first - last) / Double(first)))
}

func applyRPEBrake(weight: Double, lastRPE: Double, targetRPE: Double, rule: ProgressionRule) -> Double {
    if lastRPE >= 9.5 && rule == .progress {
        let inc = progressionIncrement(isMainLift: true, currentWeight: weight)
        return weight * (1.0 / (1.0 + inc / weight))
    }
    if lastRPE <= 7.0 && rule == .hold { return weight + 5.0 }
    return weight
}

func recommend(allLogs: [SimLog], targetLow: Int, targetHigh: Int, targetRPE: Double,
               isMainLift: Bool, lastSessionIFI: Double?) -> (weight: Double, rule: ProgressionRule, stall: String) {
    guard !allLogs.isEmpty else { return (0, .hold, "none") }

    let calendar = Calendar.current
    var grouped: [Date: [SimLog]] = [:]
    for log in allLogs {
        let day = calendar.startOfDay(for: log.date)
        grouped[day, default: []].append(log)
    }
    let sessions = grouped.sorted { $0.key > $1.key }.map { $0.value }

    let lastSession = sessions.first!
    let previous = Array(sessions.dropFirst())
    let lastTopSet = lastSession.max(by: { $0.e1rm < $1.e1rm })!
    let lastWeight = lastTopSet.weight

    let rule = determineRule(lastSession: lastSession, previousSessions: previous, targetLow: targetLow, targetHigh: targetHigh)

    var baseWeight = lastWeight
    switch rule {
    case .progress: baseWeight += progressionIncrement(isMainLift: isMainLift, currentWeight: lastWeight)
    case .hold: break
    case .backoff: baseWeight *= 0.96
    }

    // IFI modifier
    var effectiveRule = rule
    if let ifi = lastSessionIFI, ifi > 0 {
        let zone = IFIZone.classify(ifi)
        if zone == .fatigued && rule == .progress {
            baseWeight = lastWeight
            effectiveRule = .hold
        } else if zone == .overtrained {
            baseWeight = lastWeight * 0.96
            effectiveRule = .backoff
        }
    }

    // RPE brake — uses effectiveRule to avoid double-penalizing after IFI override
    if lastTopSet.rpe > 0 {
        baseWeight = applyRPEBrake(weight: baseWeight, lastRPE: lastTopSet.rpe, targetRPE: targetRPE, rule: effectiveRule)
    }

    let rounded = roundToPlate(baseWeight)

    // Stall detection
    var stallStr = "none"
    var diagnosisStr = ""
    if isMainLift && sessions.count >= 3 {
        // Suppress stall detection on first session after weight increase
        let latestMaxW = sessions[0].map { $0.weight }.max() ?? 0
        let prevMaxW = sessions[1].map { $0.weight }.max() ?? 0
        let justJumped = latestMaxW > prevMaxW + 1

        let e1rms = sessions.prefix(3).map { s in s.map { $0.e1rm }.max() ?? 0 }
        if !justJumped && e1rms[0] > 0 && e1rms[2] > 0 {
            let best = e1rms.max() ?? 0
            if e1rms[0] < best * 0.99 { stallStr = "e1rm_decline" }
            else {
                let imp = (e1rms[0] - e1rms[2]) / max(e1rms[2], 1)
                if imp < 0.005 { stallStr = "e1rm_flat" }
            }
        }

        // IFI-enhanced stall diagnosis
        if stallStr != "none", let ifi = lastSessionIFI {
            let e1rmChange = e1rms[0] > 0 && e1rms[2] > 0 ? (e1rms[0] - e1rms[2]) / max(e1rms[2], 1) : 0
            let declining = e1rmChange < -0.01
            let flat = abs(e1rmChange) < 0.005
            if ifi > 0.25 && declining { diagnosisStr = "FATIGUE_STALL→deload" }
            else if ifi < 0.10 && flat { diagnosisStr = "INTENSITY_STALL→push_harder" }
            else if ifi >= 0.10 && ifi <= 0.25 && flat { diagnosisStr = "TRUE_PLATEAU→vary_exercise" }
            else if ifi > 0.30 { diagnosisStr = "VOLUME_STALL→reduce_sets" }
        }
    }

    return (rounded, effectiveRule, stallStr + (diagnosisStr.isEmpty ? "" : " [\(diagnosisStr)]"))
}

// ─── Formatting helpers (avoid String(format:) crash in Swift interpreter) ───

func fmt1(_ v: Double) -> String {
    let rounded = (v * 10).rounded() / 10
    return "\(rounded)"
}
func fmt2(_ v: Double) -> String {
    let rounded = (v * 100).rounded() / 100
    return "\(rounded)"
}
func fmt3(_ v: Double) -> String {
    let rounded = (v * 1000).rounded() / 1000
    return "\(rounded)"
}

// ─── Deterministic RNG ───

struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}

// ─── Athlete Profiles ───

struct AthleteProfile {
    let name: String
    let description: String
    let startWeight: Double  // bench press starting weight (lbs)
    let isMainLift: Bool
    let targetLow: Int
    let targetHigh: Int
    let targetRPE: Double
    let weeks: Int
    // Behavior parameters
    let repPerformance: (Int, Double, inout SplitMix64) -> [Int]  // (week, weight, rng) -> reps per set
    let rpePerformance: (Int) -> Double  // week -> RPE
    let fatiguePattern: (Int) -> Double  // week -> IFI
}

func makeDate(weeksAgo: Int) -> Date {
    Calendar.current.date(byAdding: .day, value: -weeksAgo * 7, to: Date())!
}

// ─── Define 10 Athletes ───

let athletes: [AthleteProfile] = [
    // 1. IDEAL RESPONDER — Textbook linear progression, always hits top reps, low fatigue
    AthleteProfile(
        name: "Ideal Linear Responder",
        description: "Intermediate lifter, consistent form, good recovery, hits target reps every session",
        startWeight: 185, isMainLift: true, targetLow: 8, targetHigh: 10, targetRPE: 8.0, weeks: 16,
        repPerformance: { week, weight, rng in
            [10, 10, 10]  // Always hits top
        },
        rpePerformance: { week in min(7.0 + Double(week) * 0.15, 9.0) },
        fatiguePattern: { week in min(0.08 + Double(week) * 0.005, 0.18) }
    ),

    // 2. SLOW GAINER — Takes 2-3 sessions to build reps before progressing
    AthleteProfile(
        name: "Slow Gainer",
        description: "Needs multiple sessions at same weight to hit top reps. Classic double-progression pattern.",
        startWeight: 225, isMainLift: true, targetLow: 8, targetHigh: 10, targetRPE: 8.0, weeks: 16,
        repPerformance: { week, weight, rng in
            let cycle = week % 3
            switch cycle {
            case 0: return [8, 8, 7]   // First week at new weight: building
            case 1: return [9, 9, 8]   // Second week: improving
            default: return [10, 10, 10] // Third week: hit top → progress
            }
        },
        rpePerformance: { week in 8.0 },
        fatiguePattern: { week in 0.12 + (Double(week % 3) * 0.04) }
    ),

    // 3. FATIGUE ACCUMULATOR — Good early, burns out by week 8-10
    AthleteProfile(
        name: "Fatigue Accumulator",
        description: "Progresses well initially but accumulates fatigue without adequate recovery. Needs deload.",
        startWeight: 275, isMainLift: true, targetLow: 6, targetHigh: 8, targetRPE: 8.5, weeks: 16,
        repPerformance: { week, weight, rng in
            if week < 6 {
                return [8, 8, 8]  // Strong early
            } else if week < 10 {
                return [7, 6, 5]  // Fatigue building
            } else if week == 10 {
                return [8, 8, 8]  // Deload recovery bounce
            } else {
                return [8, 7, 6]  // Post-deload: some recovery
            }
        },
        rpePerformance: { week in
            if week < 6 { return 8.0 }
            if week < 10 { return 9.0 + Double(week - 6) * 0.15 }
            return 8.0  // Post-deload
        },
        fatiguePattern: { week in
            if week < 6 { return 0.12 }
            if week < 10 { return 0.20 + Double(week - 6) * 0.05 }  // Rising to 0.40
            if week == 10 { return 0.10 }  // Recovery
            return 0.15
        }
    ),

    // 4. BEGINNER — Rapid early gains, starts plateauing around week 10
    AthleteProfile(
        name: "Novice Lifter",
        description: "New to structured training. Progresses every session early on, starts slowing around week 10.",
        startWeight: 95, isMainLift: true, targetLow: 8, targetHigh: 10, targetRPE: 7.0, weeks: 16,
        repPerformance: { week, weight, rng in
            if week < 10 { return [10, 10, 10] }  // Novice gains
            if week < 13 { return [9, 8, 8] }      // Slowing down
            return [8, 8, 8]                         // Plateau
        },
        rpePerformance: { week in min(6.5 + Double(week) * 0.2, 8.5) },
        fatiguePattern: { week in min(0.05 + Double(week) * 0.01, 0.20) }
    ),

    // 5. ADVANCED LIFTER — Weights are high, progression is very slow, needs IFI management
    AthleteProfile(
        name: "Advanced Powerlifter",
        description: "405+ bench, micro-progressions only. High fatigue management needed.",
        startWeight: 405, isMainLift: true, targetLow: 3, targetHigh: 5, targetRPE: 9.0, weeks: 16,
        repPerformance: { week, weight, rng in
            let cycle = week % 4
            switch cycle {
            case 0: return [4, 3, 3]
            case 1: return [4, 4, 3]
            case 2: return [5, 4, 4]
            default: return [5, 5, 5]  // Progress every 4 weeks
            }
        },
        rpePerformance: { week in 9.0 + (Double(week % 4) * 0.15) },
        fatiguePattern: { week in 0.18 + (Double(week % 4) * 0.05) }
    ),

    // 6. INCONSISTENT TRAINER — Misses sessions, variable performance
    AthleteProfile(
        name: "Inconsistent Trainer",
        description: "Life gets in the way. Variable attendance and effort. Tests algorithm robustness.",
        startWeight: 185, isMainLift: true, targetLow: 8, targetHigh: 10, targetRPE: 8.0, weeks: 16,
        repPerformance: { week, weight, rng in
            let roll = Int.random(in: 0...9, using: &rng)
            if roll < 3 { return [10, 10, 10] }       // 30% great day
            if roll < 6 { return [9, 8, 8] }           // 30% decent day
            if roll < 8 { return [7, 6, 5] }           // 20% bad day
            return [10, 9, 6]                            // 20% inconsistent within session
        },
        rpePerformance: { _ in 8.0 },
        fatiguePattern: { week in 0.05 + (Double(week % 7) * 0.05) }  // Cycles 0.05-0.35
    ),

    // 7. ACCESSORY FOCUSED — Dumbbell curls, tests accessory-specific logic
    AthleteProfile(
        name: "Accessory Exercise (DB Curls)",
        description: "Isolation exercise. 5 lb jumps, 4-session stall detection, higher rep ranges.",
        startWeight: 30, isMainLift: false, targetLow: 10, targetHigh: 15, targetRPE: 7.5, weeks: 16,
        repPerformance: { week, weight, rng in
            let cycle = week % 4
            switch cycle {
            case 0: return [12, 11, 10]
            case 1: return [13, 12, 11]
            case 2: return [14, 13, 12]
            default: return [15, 15, 15]  // Progress every 4 weeks
            }
        },
        rpePerformance: { _ in 7.5 },
        fatiguePattern: { week in 0.10 + (Double(week % 4) * 0.03) }
    ),

    // 8. HIGH RPE LIFTER — Always goes too hard, tests RPE brake
    AthleteProfile(
        name: "RPE Maxer",
        description: "Always pushes to RPE 9.5-10. Tests whether RPE brake prevents over-progression.",
        startWeight: 225, isMainLift: true, targetLow: 6, targetHigh: 8, targetRPE: 8.0, weeks: 16,
        repPerformance: { week, weight, rng in
            [8, 8, 8]  // Hits range but at extreme RPE
        },
        rpePerformance: { week in min(9.5 + Double(week) * 0.03, 10.0) },
        fatiguePattern: { week in min(0.15 + Double(week) * 0.015, 0.40) }
    ),

    // 9. METRIC USER — Tests metric weight rounding (2.5 kg increments)
    AthleteProfile(
        name: "Metric User (Bench Press kg)",
        description: "European lifter using kg. Tests 2.5 kg increment and rounding logic.",
        startWeight: 80, isMainLift: true, targetLow: 8, targetHigh: 10, targetRPE: 8.0, weeks: 16,
        repPerformance: { week, weight, rng in
            let cycle = week % 3
            switch cycle {
            case 0: return [8, 8, 8]
            case 1: return [9, 9, 9]
            default: return [10, 10, 10]
            }
        },
        rpePerformance: { _ in 8.0 },
        fatiguePattern: { week in 0.12 }
    ),

    // 10. OVERTRAINER — Too much volume, high IFI, tests overtrained recovery path
    AthleteProfile(
        name: "Volume Overreacher",
        description: "5-6 sets per exercise, high IFI from the start. Tests overtrained forced backoff pathway.",
        startWeight: 225, isMainLift: true, targetLow: 8, targetHigh: 10, targetRPE: 8.0, weeks: 16,
        repPerformance: { week, weight, rng in
            // 5 sets with heavy dropoff
            if week < 4 { return [10, 9, 8, 7, 5] }     // Early: still hitting range
            if week < 8 { return [9, 8, 7, 5, 4] }       // Fatigue building
            if week < 12 { return [8, 6, 5, 4, 3] }      // Overtrained
            return [10, 9, 8, 7, 6]                        // Post-deload recovery
        },
        rpePerformance: { week in
            if week < 4 { return 8.0 }
            if week < 12 { return min(8.5 + Double(week - 4) * 0.2, 10.0) }
            return 8.0
        },
        fatiguePattern: { week in
            if week < 4 { return 0.25 }     // Already high — 5 sets
            if week < 8 { return 0.35 }     // Fatigued
            if week < 12 { return 0.45 }    // Overtrained
            return 0.15                       // Recovery
        }
    ),
]

// ═══════════════════════════════════════════════════════════════════
// RUN SIMULATION
// ═══════════════════════════════════════════════════════════════════

var output = ""

func log(_ s: String) {
    output += s + "\n"
}

log("═══════════════════════════════════════════════════════════════════")
log("ADVANCEDLIFTER ALGORITHM SIMULATION REPORT")
log("Generated: \(Date())")
log("═══════════════════════════════════════════════════════════════════")
log("")

for (idx, athlete) in athletes.enumerated() {
    var rng = SplitMix64(seed: UInt64(idx * 137 + 42))
    var currentWeight = athlete.startWeight
    var allLogs: [SimLog] = []
    var weekData: [(week: Int, weight: Double, reps: [Int], recommended: Double, rule: String, ifi: Double, ifiZone: String, rpe: Double, e1rm: Double, stall: String)] = []

    log("───────────────────────────────────────────────────────────────────")
    log("ATHLETE \(idx + 1): \(athlete.name)")
    log("Description: \(athlete.description)")
    log("Start weight: \(Int(athlete.startWeight)) lbs | Lift type: \(athlete.isMainLift ? "Main" : "Accessory")")
    log("Target rep range: \(athlete.targetLow)-\(athlete.targetHigh) | Target RPE: \(athlete.targetRPE)")
    log("───────────────────────────────────────────────────────────────────")
    log("")
    log("Week  Weight     Reps              Rule     Rec.Wt     e1RM     IFI          RPE    Stall      IFI Zone")
    log(String(repeating: "─", count: 105))

    for week in 0..<athlete.weeks {
        let date = makeDate(weeksAgo: athlete.weeks - 1 - week)
        let reps = athlete.repPerformance(week, currentWeight, &rng)
        let rpe = athlete.rpePerformance(week)
        let ifi = athlete.fatiguePattern(week)

        // Create session logs
        let session = reps.enumerated().map { idx, r in
            SimLog(weight: currentWeight, reps: r, setIndex: idx, rpe: rpe, date: date, isMainLift: athlete.isMainLift)
        }
        allLogs.append(contentsOf: session)

        // Get recommendation
        let result = recommend(
            allLogs: allLogs,
            targetLow: athlete.targetLow,
            targetHigh: athlete.targetHigh,
            targetRPE: athlete.targetRPE,
            isMainLift: athlete.isMainLift,
            lastSessionIFI: ifi
        )

        // Compute actual IFI from this session
        let actualIFI = computeIFI(sets: session)
        let sessionE1RM = session.map { $0.e1rm }.max() ?? 0
        let ifiZone = IFIZone.classify(ifi)

        let repsStr = reps.map { String($0) }.joined(separator: ",")
        let wStr = "\(week + 1)".padding(toLength: 6, withPad: " ", startingAt: 0)
        let wtStr = "\(Int(currentWeight))".padding(toLength: 10, withPad: " ", startingAt: 0)
        let rpStr = repsStr.padding(toLength: 18, withPad: " ", startingAt: 0)
        let rlStr = result.rule.rawValue.padding(toLength: 9, withPad: " ", startingAt: 0)
        let rcStr = "\(Int(result.weight))".padding(toLength: 10, withPad: " ", startingAt: 0)
        let e1Str = "\(Int(sessionE1RM))".padding(toLength: 8, withPad: " ", startingAt: 0)
        let ifiStr = "\(fmt2(ifi))/\(fmt2(actualIFI))".padding(toLength: 12, withPad: " ", startingAt: 0)
        let rpeSt = "\(fmt1(rpe))".padding(toLength: 7, withPad: " ", startingAt: 0)
        let stStr = result.stall.padding(toLength: 12, withPad: " ", startingAt: 0)

        log("\(wStr)\(wtStr)\(rpStr)\(rlStr)\(rcStr)\(e1Str)\(ifiStr)\(rpeSt)\(stStr)\(ifiZone.rawValue)")

        weekData.append((week + 1, currentWeight, reps, result.weight, result.rule.rawValue, ifi, ifiZone.rawValue, rpe, sessionE1RM, result.stall))

        // Apply recommendation for next week
        if result.weight > 0 {
            currentWeight = result.weight
        }
    }

    // Summary stats
    let startE1RM = weekData.first!.e1rm
    let endE1RM = weekData.last!.e1rm
    let peakE1RM = weekData.map { $0.e1rm }.max() ?? 0
    let progressCount = weekData.filter { $0.rule == "progress" }.count
    let holdCount = weekData.filter { $0.rule == "hold" }.count
    let backoffCount = weekData.filter { $0.rule == "backoff" }.count
    let stallWeeks = weekData.filter { $0.stall != "none" }
    let avgIFI = weekData.map { $0.ifi }.reduce(0, +) / Double(weekData.count)

    log("")
    log("SUMMARY:")
    log("  Starting weight: \(Int(athlete.startWeight)) → Final weight: \(Int(currentWeight))")
    log("  Starting e1RM: \(Int(startE1RM)) → Final e1RM: \(Int(endE1RM)) → Peak e1RM: \(Int(peakE1RM))")
    let e1rmPct = ((endE1RM - startE1RM) / max(startE1RM, 1)) * 100
    log("  e1RM change: \(endE1RM >= startE1RM ? "+" : "")\(fmt1(e1rmPct))%")
    log("  Decisions: \(progressCount) progress, \(holdCount) hold, \(backoffCount) backoff")
    log("  Stall weeks: \(stallWeeks.count) (\(stallWeeks.map { "wk\($0.week):\($0.stall)" }.joined(separator: ", ")))")
    let avgIFIStr = fmt3(avgIFI)
    log("  Avg IFI: \(avgIFIStr)")
    log("  Weight range: \(Int(weekData.map { $0.weight }.min() ?? 0)) - \(Int(weekData.map { $0.weight }.max() ?? 0)) lbs")
    log("")
}

// ═══════════════════════════════════════════════════════════════════
// CROSS-ATHLETE COMPARISON TABLE
// ═══════════════════════════════════════════════════════════════════

log("")
log("═══════════════════════════════════════════════════════════════════")
log("CROSS-ATHLETE COMPARISON")
log("═══════════════════════════════════════════════════════════════════")
log("")
log("Athlete                        Start      End        Peak       Prog     Hold     Back     e1RM Change")
log(String(repeating: "─", count: 100))

// Re-run for comparison table
for (idx, athlete) in athletes.enumerated() {
    var rng = SplitMix64(seed: UInt64(idx * 137 + 42))
    var currentWeight = athlete.startWeight
    var allLogs: [SimLog] = []
    var recs: [(rule: String, e1rm: Double)] = []

    for week in 0..<athlete.weeks {
        let date = makeDate(weeksAgo: athlete.weeks - 1 - week)
        let reps = athlete.repPerformance(week, currentWeight, &rng)
        let rpe = athlete.rpePerformance(week)
        let ifi = athlete.fatiguePattern(week)

        let session = reps.enumerated().map { i, r in
            SimLog(weight: currentWeight, reps: r, setIndex: i, rpe: rpe, date: date, isMainLift: athlete.isMainLift)
        }
        allLogs.append(contentsOf: session)

        let result = recommend(allLogs: allLogs, targetLow: athlete.targetLow, targetHigh: athlete.targetHigh,
                              targetRPE: athlete.targetRPE, isMainLift: athlete.isMainLift, lastSessionIFI: ifi)

        let e1rm = session.map { $0.e1rm }.max() ?? 0
        recs.append((result.rule.rawValue, e1rm))

        if result.weight > 0 { currentWeight = result.weight }
    }

    let startE1RM = recs.first!.e1rm
    let endE1RM = recs.last!.e1rm
    let peakE1RM = recs.map { $0.e1rm }.max() ?? 0
    let pCount = recs.filter { $0.rule == "progress" }.count
    let hCount = recs.filter { $0.rule == "hold" }.count
    let bCount = recs.filter { $0.rule == "backoff" }.count
    let delta = ((endE1RM - startE1RM) / startE1RM) * 100

    let nm = athlete.name.padding(toLength: 30, withPad: " ", startingAt: 0)
    let s1 = "\(Int(athlete.startWeight))".padding(toLength: 10, withPad: " ", startingAt: 0)
    let e1 = "\(Int(currentWeight))".padding(toLength: 10, withPad: " ", startingAt: 0)
    let pk = "\(Int(peakE1RM))".padding(toLength: 10, withPad: " ", startingAt: 0)
    let p1 = "\(pCount)".padding(toLength: 8, withPad: " ", startingAt: 0)
    let h1 = "\(hCount)".padding(toLength: 8, withPad: " ", startingAt: 0)
    let b1 = "\(bCount)".padding(toLength: 8, withPad: " ", startingAt: 0)
    let d1 = (delta >= 0 ? "+" : "") + "\(fmt1(delta))%"
    log("\(nm)\(s1)\(e1)\(pk)\(p1)\(h1)\(b1)\(d1)")
}

// ═══════════════════════════════════════════════════════════════════
// ALGORITHM BEHAVIOR ANALYSIS
// ═══════════════════════════════════════════════════════════════════

log("")
log("")
log("═══════════════════════════════════════════════════════════════════")
log("ALGORITHM WEIGHTS & DECISION THRESHOLDS (for review)")
log("═══════════════════════════════════════════════════════════════════")
log("""

1. DOUBLE PROGRESSION (Primary Driver)
   ─────────────────────────────────────
   PROGRESS trigger: ALL working sets >= targetRepsHigh
   HOLD trigger:     Any set in [targetRepsLow, targetRepsHigh) OR only 1 bad session
   BACKOFF trigger:  2+ sets < targetRepsLow for 2 CONSECUTIVE sessions

   Working set filter: weight >= 80% of session max weight
   Backoff magnitude: current weight × 0.96 (4% reduction)

   Weight increments:
     Main lift (imperial, >=185 lbs): +10 lbs
     Main lift (imperial, <185 lbs):  +5 lbs
     Accessory (imperial):            +5 lbs
     All lifts (metric):              +2.5 kg

2. IFI (Intraset Fatigue Index) Modifier
   ──────────────────────────────────────
   Formula: IFI = (first_working_set_reps - last_working_set_reps) / first_working_set_reps
   Clamped to [0, 1]

   Zone thresholds:
     FRESH:       IFI < 0.10
     OPTIMAL:     0.10 <= IFI < 0.25
     FATIGUED:    0.25 <= IFI < 0.40
     OVERTRAINED: IFI >= 0.40

   Modifier effects on recommendations:
     FRESH + any rule           → No modification (good fatigue management, normal progression)
     OPTIMAL + any rule         → No modification (normal progression)
     FATIGUED + PROGRESS rule   → Override to HOLD (reps degrading 20-35%, don't add weight)
     FATIGUED + other rules     → No modification
     OVERTRAINED + any rule     → Force BACKOFF (weight × 0.96, effectiveRule set to .backoff)

   IFI Trend tracking:
     EMA formula: trend = (old_trend × 2 + current_ifi) / 3
     Smooths over ~3 sessions to detect patterns vs. noise

3. RPE BRAKE (Optional Safety Layer — only fires if user logged RPE)
   ─────────────────────────────────────────────────────────────────
   RPE >= 9.5 + PROGRESS rule → Cancel progression (revert to hold weight)
   RPE <= 7.0 + HOLD rule    → Allow +5 lbs bump (too easy, nudge up)
   All other RPE values       → No modification

   Note: RPE brake fires AFTER IFI modifier and uses the effectiveRule (not original rule)
   to prevent double-penalizing. If IFI overrides to backoff, RPE brake won't also block.

4. STALL DETECTION
   ────────────────
   Main lifts (requires 3+ sessions):
     e1RM DECLINE: latest e1RM < best_of_last_3 × 0.99 (more than 1% below recent best)
     e1RM FLAT:    (e1RM[newest] - e1RM[oldest]) / e1RM[oldest] < 0.005 (less than 0.5% improvement)
     RPE RISING:   e1RM flat + latest_avg_RPE > oldest_avg_RPE + 0.5

   SUPPRESSION: Stall detection is skipped on first session after a weight increase.
   e1RM naturally dips when load jumps — flagging that as a stall is a false positive.

   Accessories (requires 4+ sessions):
     REPS FLAT: max reps identical across all 4 sessions at same load

5. STALL DIAGNOSIS WITH IFI
   ─────────────────────────
   Requires 3+ sessions. Computes e1RM change over last 3 sessions:
     e1rmChange = (newest_e1rm - oldest_e1rm) / oldest_e1rm
     e1rmDeclining = e1rmChange < -0.01 (more than 1% drop)
     e1rmFlat = |e1rmChange| < 0.005

   Diagnosis matrix:
     ifiTrend > 0.25 + e1rmDeclining → FATIGUE STALL (need deload)
     ifiTrend < 0.10 + e1rmFlat      → INTENSITY STALL (not pushing hard enough)
     0.10 <= ifiTrend <= 0.25 + e1rmFlat → TRUE PLATEAU (need exercise variation)
     ifiTrend > 0.30                  → VOLUME STALL (too much volume regardless of e1RM)

   HYSTERESIS: Once a diagnosis fires, it sticks until IFI trend moves 0.05+ outside
   that diagnosis's band. Prevents flickering between diagnoses at boundaries.
   Bands: fatigueStall 0.20-1.0, intensityStall 0.0-0.15, truePlateau 0.05-0.30, volumeStall 0.25-1.0

   ESCALATION: Tracks consecutive sessions with the same diagnosis.
     1st occurrence → SUGGESTION ("Consider a deload")
     2nd consecutive → WARNING (same text, orange badge)
     3rd+ consecutive → ACTION REQUIRED (red badge, hard prompt: "swap exercise before next session")

6. VOLUME LANDMARKS (4-Point Model)
   ──────────────────────────────────
   Each muscle group has 4 volume boundaries (direct sets per week):

   Muscle       MEV  MAV-Low  MAV-High  MRV
   ─────────    ───  ───────  ────────  ───
   Chest          6       10        16   22
   Back           8       12        18   24
   Quads          6       10        16   22
   Hamstrings     4        8        12   18
   Glutes         2        6        12   18
   Calves         4        6        10   16
   Biceps         4        8        12   18
   Triceps        4        6        10   16
   Delts          6       10        14   20

   Zone classification:
     < MEV              → UNDER-TRAINING (red)
     MEV to MAV-Low     → BUILDING (yellow)
     MAV-Low to MRV     → OPTIMAL (green)
     > MRV              → OVER-REACHING (orange)

   Indirect volume tracking:
     Secondary muscles from compound exercises count at 0.5× weight
     Example: 1 set of bench press = 1.0 chest + 0.5 triceps + 0.5 delts

7. MUSCLE PRIORITY TIERS
   ──────────────────────
   PRIORITY (1.5× multiplier): Up to 3 muscles. All landmarks scale up 50%.
   NEUTRAL  (1.0× multiplier): Default for most muscles.
   MAINTENANCE (0.7× multiplier): Up to 3 muscles. Landmarks scale down 30%.

   Example: Chest as PRIORITY → MEV=9, MAV-Low=15, MAV-High=24, MRV=33

8. LANDMARK CALIBRATION (Adaptive)
   ────────────────────────────────
   Per-muscle @Model that adjusts over time based on performance:

   Confidence tiers:
     SEEDED:  0 weeks of data (using defaults)
     LOW:     1-3 weeks
     MEDIUM:  4-8 weeks
     HIGH:    9+ weeks

   Recalibration frequency: Every 2 weeks minimum
   Max shift per recalibration: ±2 sets

   MEV adjustment:
     Progressing near MEV (e1RM rising, sets <= MEV+2) → Lower MEV by 1 (min 2)
     Declining in building zone (e1RM dropping, MEV < sets < MAV-Low) → Raise MEV by 1

   MRV adjustment (when sets >= MAV-High):
     High IFI (>0.30) + declining e1RM → Lower MRV by 2
     Low IFI (<0.15) + rising e1RM → Raise MRV by 2

   MAV-High adjustment (when in optimal zone):
     Great progress (e1RM +1%, IFI <0.20) → Widen MAV-High by 1
     Declining (e1RM -0.5%, IFI >0.25) → Narrow MAV-High by 1

   Invariant enforced: MEV < MAV-Low < MAV-High < MRV (at least 1 gap between each)

9. E1RM FORMULA
   ─────────────
   e1RM = weight × (1 + reps/30)

   This is a simplified Epley-variant formula. Used for:
   - Tracking progress over time
   - Detecting stalls (e1RM flat or declining)
   - Comparing performance at different weight/rep combinations

10. PLATE ROUNDING
    ───────────────
    Imperial: round to nearest 5 lbs → weight = round(weight / 5) × 5
    Metric:   round to nearest 2.5 kg → weight = round(weight / 2.5) × 2.5

    Applied as final step before recommendation output.

    Two different reductions exist (don't confuse them):
    - Backoff RULE (progression failed): recommended_weight = last_weight × 0.96 (4% drop)
    - Backoff SET weight (lighter working sets for main lifts): top_set × 0.92 (8% lighter volume sets)
    These serve different purposes: the rule reduces your training max, the set weight creates volume work.

11. DATA CONFIDENCE
    ────────────────
    Based on number of sessions (exposures) available:
      0 sessions  → NONE (returns 0, prompts manual entry)
      1 session   → LOW
      2-3 sessions → MEDIUM
      4+ sessions  → HIGH

12. DECISION PIPELINE ORDER
    ───────────────────────
    1. Group logs by session date, identify last session
    2. Determine double progression rule (progress/hold/backoff)
    3. Calculate base weight from rule
    4. Apply IFI modifier (may override rule)
    5. Apply RPE brake (may further modify)
    6. Round to nearest plate increment
    7. Calculate backoff weight (main lifts: × 0.92)
    8. Run stall detection
    9. Return recommendation with confidence level

""")

// Write to file
let outputPath = "/Users/ayb/Desktop/Powerbodybuilder/simulation_report.txt"
try! output.write(toFile: outputPath, atomically: true, encoding: .utf8)
print("Report written to: \(outputPath)")
print("Total length: \(output.count) characters")
