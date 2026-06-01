import SwiftUI

// ═══════════════════════════════════════════
// PROGRAM DEFINITION MODEL
// ═══════════════════════════════════════════

struct ProgramDef: Identifiable {
    let id: Int
    let name: String
    let subtitle: String
    let description: String
    let days: String
    let sessionLength: String
    let split: String
    let difficulty: String
    let icon: String
    let accentColor: Color
    let tags: [String]
    let repRanges: String
    let volumePerMuscle: String
    let whoItsFor: String
    let days_per_week_range: ClosedRange<Int>
}

// ═══════════════════════════════════════════
// ALL PROGRAMS
// ═══════════════════════════════════════════

let allPrograms: [ProgramDef] = [

    ProgramDef(
        id: 0,
        name: "FREESTYLE",
        subtitle: "No Program — Just Train",
        description: "No structured program. Build your own workouts each day by picking exercises from the full library. All sets are logged and tracked with progression just like any program.",
        days: "Any",
        sessionLength: "Any",
        split: "You decide each session",
        difficulty: "Any Level",
        icon: "figure.mixed.cardio",
        accentColor: .appTextSecondary,
        tags: ["Flexible", "Custom", "No Structure"],
        repRanges: "Any",
        volumePerMuscle: "You decide",
        whoItsFor: "Anyone who wants to log workouts without following a fixed program.",
        days_per_week_range: 1...7
    ),

    ProgramDef(
        id: 1,
        name: "POWERBUILDING",
        subtitle: "Strength + Size Simultaneously",
        description: "Build maximal strength on the big three compound lifts while accumulating significant hypertrophy across all major muscle groups via a dual-stimulus approach.",
        days: "4–5 days/week",
        sessionLength: "75–90 min",
        split: "Upper / Lower with DUP",
        difficulty: "Intermediate",
        icon: "bolt.fill",
        accentColor: .appRed,
        tags: ["Strength", "Hypertrophy", "Compounds"],
        repRanges: "3–5 | 8–12 | 12–15",
        volumePerMuscle: "14–20 sets/week",
        whoItsFor: "Intermediate lifters who want to be both strong and aesthetic without fully specializing in one direction.",
        days_per_week_range: 4...5
    ),
    
    ProgramDef(
        id: 2,
        name: "PURE HYPERTROPHY",
        subtitle: "PPL A/B · Maximum Muscle Growth",
        description: "16-week Push/Pull/Legs A/B split targeting maximum hypertrophy. Two blocks: accumulation builds volume, intensification drives load. Deloads at weeks 4 and 12.",
        days: "6 days/week",
        sessionLength: "60–75 min",
        split: "Push A / Pull A / Legs A / Push B / Pull B / Legs B",
        difficulty: "Intermediate",
        icon: "figure.strengthtraining.traditional",
        accentColor: .appBlue,
        tags: ["Hypertrophy", "PPL", "6-Day", "Volume"],
        repRanges: "3–6 | 6–10 | 10–15 | 15–20",
        volumePerMuscle: "16–22 sets/week",
        whoItsFor: "Lifters who care primarily about muscle size and aesthetics over strength numbers.",
        days_per_week_range: 6...6
    ),
    
    ProgramDef(
        id: 3,
        name: "STRENGTH",
        subtitle: "Powerlifting Focus",
        description: "Maximize 1RM performance on squat, bench, and deadlift through systematic heavy loading, neural adaptation, and RPE-based auto-regulation.",
        days: "3–4 days/week",
        sessionLength: "60–80 min",
        split: "Squat / Bench / Deadlift",
        difficulty: "Intermediate",
        icon: "scalemass.fill",
        accentColor: .appGold,
        tags: ["Strength", "Powerlifting", "Heavy"],
        repRanges: "1–3 | 3–5 | 6–8",
        volumePerMuscle: "10–14 sets/week",
        whoItsFor: "Anyone who wants to compete in powerlifting or simply get as strong as possible.",
        days_per_week_range: 3...4
    ),
    
    ProgramDef(
        id: 4,
        name: "BEGINNER FULL BODY",
        subtitle: "Build the Foundation",
        description: "Build simultaneous base strength and muscle through linear progression on the major compound movements. Exploit the novice window while it lasts.",
        days: "3 days/week",
        sessionLength: "45–60 min",
        split: "Full Body A/B Alternating",
        difficulty: "Beginner",
        icon: "star.fill",
        accentColor: .appGreen,
        tags: ["Beginner", "Full Body", "Linear Progression"],
        repRanges: "5 | 8–10 | 10–12",
        volumePerMuscle: "9–12 sets/week",
        whoItsFor: "Anyone under 1 year of consistent structured training.",
        days_per_week_range: 3...3
    ),
    
    ProgramDef(
        id: 5,
        name: "ATHLETIC PERFORMANCE",
        subtitle: "Strength, Power, Conditioning",
        description: "Develop functional strength, explosive power, and metabolic conditioning simultaneously. Build athletes who are fast, powerful, and conditioned.",
        days: "4 days/week",
        sessionLength: "60–75 min",
        split: "Upper Power / Lower Power / Strength-Hypertrophy",
        difficulty: "Intermediate",
        icon: "figure.run",
        accentColor: .appGold,
        tags: ["Power", "Athletic", "Conditioning"],
        repRanges: "1–5 | 6–10 | Explosive",
        volumePerMuscle: "12–16 sets/week",
        whoItsFor: "Athletes in team or combat sports, or lifters with an athletic background.",
        days_per_week_range: 4...4
    ),
    
    ProgramDef(
        id: 6,
        name: "MINIMALIST",
        subtitle: "Maximum Efficiency",
        description: "Maintain or slowly build strength and muscle with the minimum time investment required to produce a meaningful stimulus. Compound-only. No wasted sets.",
        days: "3 days/week",
        sessionLength: "35–45 min",
        split: "Full Body 3x/week",
        difficulty: "Any Level",
        icon: "timer",
        accentColor: .appTextSecondary,
        tags: ["Busy", "Efficient", "Maintenance"],
        repRanges: "5–8",
        volumePerMuscle: "6–10 sets/week",
        whoItsFor: "Busy professionals or anyone who can only commit 3 days and sub-45 minute sessions.",
        days_per_week_range: 3...3
    ),

    ProgramDef(
        id: 7,
        name: "BAHRI SPLIT",
        subtitle: "6-Day Hypertrophy Specialization",
        description: "Adam Bahri's personal 24-week periodized split targeting maximum hypertrophy with high-frequency leg training and intelligent upper body volume distribution.",
        days: "6 days/week",
        sessionLength: "75–100 min",
        split: "Mon Legs · Tue Upper · Wed Arms · Thu Legs · Sat Upper · Sun Legs",
        difficulty: "Advanced",
        icon: "flame.fill",
        accentColor: .appRed,
        tags: ["Hypertrophy", "6-Day", "High Frequency", "Legs 3x"],
        repRanges: "3–5 | 6–8 | 10–12 | 15–20",
        volumePerMuscle: "18–26 sets/week",
        whoItsFor: "Advanced lifters who want maximum hypertrophy with high-frequency leg training.",
        days_per_week_range: 6...6
    ),

    ProgramDef(
        id: 8,
        name: "AESTHETIC SPLIT",
        subtitle: "5-Day Physique Split",
        description: "A 16-week chest, quad, and arm–emphasis Push/Pull/Lower split built around the look — broad shoulders, full chest, capped delts, and a tight waist. Two push days, two lower days, one big pull day.",
        days: "5 days/week",
        sessionLength: "60–80 min",
        split: "Mon Push · Tue Lower (quad) · Wed Pull · Thu Push · Fri Lower (posterior)",
        difficulty: "Intermediate",
        icon: "figure.arms.open",
        accentColor: .appGold,
        tags: ["Hypertrophy", "5-Day", "Push/Pull/Lower", "Aesthetics"],
        repRanges: "5–8 | 8–12 | 10–15 | 12–20",
        volumePerMuscle: "10–16 sets/week",
        whoItsFor: "Intermediates chasing a balanced physique with extra chest, delt, and arm volume.",
        days_per_week_range: 5...5
    )
]

// ═══════════════════════════════════════════
// RECOMMENDATION ENGINE
// ═══════════════════════════════════════════

func recommendProgram(goal: String, experience: String, daysPerWeek: Int) -> Int {
    let goalType = GoalType.migrate(from: goal)
    if daysPerWeek <= 3 { return 6 }
    switch goalType {
    case .recomp:        return 6
    case .strength:      return 3
    case .hypertrophy:   return daysPerWeek >= 5 ? 2 : 1
    case .powerbuilding: return 1
    }
}
