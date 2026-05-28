import SwiftUI

// ═══════════════════════════════════════════
// JARGON GLOSSARY
// In-app reference for sports-science terms surfaced in advanced density.
// Each term is hand-tuned: short summary, full explanation, an example,
// and actionable guidance. Sourced from research summaries + the actual
// engine implementation.
// ═══════════════════════════════════════════

struct JargonTerm: Identifiable {
    let id: String
    let name: String
    let abbrev: String?
    let oneLineSummary: String
    let explanation: String
    let example: String?
    let whatToDo: String?
}

enum JargonGlossary {
    static let all: [String: JargonTerm] = Dictionary(
        uniqueKeysWithValues: entries.map { ($0.id, $0) }
    )

    /// Ordered for the Glossary view — most common at the top.
    static let entries: [JargonTerm] = [

        JargonTerm(
            id: "ifi",
            name: "Intra-set Fatigue Index",
            abbrev: "IFI",
            oneLineSummary: "How much your reps drop across a working set, from first set to last.",
            explanation:
                "IFI measures the percentage drop-off in reps between your first working set and your last working set on an exercise. A higher IFI means you fatigued more during the workout — the algorithm uses it to decide whether to push weight, hold, or back off next session.",
            example: "Bench 185×10, 185×8, 185×7 → 30% drop-off → 'fatigued' IFI.",
            whatToDo:
                "Fresh (<10%): you have capacity, push weight. Optimal (10–25%): productive fatigue, hold or push. Fatigued (25–40%): meaningful cost, hold. Overtrained (>40%): back off."
        ),

        JargonTerm(
            id: "pml",
            name: "Prior Muscle Load",
            abbrev: "PML",
            oneLineSummary: "Reduces today's weight based on fatigue from exercises earlier in the same session.",
            explanation:
                "If you bench heavy first, your tricep pushdowns later will be slightly weaker. PML applies a small weight reduction (typically 3–15%) to account for the carry-over fatigue. The amount adapts to you personally as the algorithm learns how your body recovers between exercises in a session.",
            example: "After heavy bench (chest), tricep pushdown weight drops ~5–10% from its usual recommendation because the long head of the triceps is pre-fatigued.",
            whatToDo:
                "Nothing — the algorithm handles it. When you see 'Adjusted for prior chest work' on an exercise, it just means PML reduced the weight. Trust it; pushing through artificially-high numbers leads to form breakdown."
        ),

        JargonTerm(
            id: "mrv",
            name: "Maximum Recoverable Volume",
            abbrev: "MRV",
            oneLineSummary: "The most sets per week your body can recover from before performance drops.",
            explanation:
                "Each muscle has a ceiling where adding more sets stops helping and starts hurting. Past MRV, you can't recover by the next session. The algorithm tracks 5 fatigue signals — declining e1RM, rising IFI, stuck loads, dropping volume-load, missed reps — and scores each muscle to detect when you're approaching MRV.",
            example: "Chest MRV around 18–22 sets/week for intermediates. If you're hitting 22 and your bench is going down, you're past MRV.",
            whatToDo:
                "When the app flags 'high fatigue' or recommends a deload, take it. MRV resets after a recovery week."
        ),

        JargonTerm(
            id: "mev",
            name: "Minimum Effective Volume",
            abbrev: "MEV",
            oneLineSummary: "The fewest sets per week that actually grow a muscle.",
            explanation:
                "Below MEV, you're maintaining at best. Above it, every set adds. MEV depends on the muscle, your training experience, and your recovery capacity — it climbs as you advance.",
            example: "Beginner Chest MEV is around 6–8 sets/week. Advanced Chest MEV climbs to 10–14 sets/week as the muscle adapts.",
            whatToDo:
                "If a muscle is in the under-training zone (below MEV), add sets — they're nearly 'free' growth at that point."
        ),

        JargonTerm(
            id: "mav",
            name: "Maximum Adaptive Volume",
            abbrev: "MAV",
            oneLineSummary: "The sweet-spot volume range where you get the most growth per set.",
            explanation:
                "Between MEV and MRV is your 'adaptive zone' — the volume range where each set still drives growth without exceeding recovery. MAV-Low to MAV-High is where most of your weekly sets should land for hypertrophy.",
            example: "Chest with MEV=8 and MRV=18 has an MAV zone of roughly 10–14 sets — the 'on target' green band on your volume bars.",
            whatToDo:
                "Aim for the target marker shown in your volume bars. Below it, build up. Above it (but still under MRV), you can hold."
        ),

        JargonTerm(
            id: "e1rm",
            name: "Estimated 1-Rep Max",
            abbrev: "e1RM",
            oneLineSummary: "Predicted max single-rep weight from your normal training sets.",
            explanation:
                "You can't always test a true 1-rep max, so we estimate it: weight × (1 + reps/30). It's a rough but reliable proxy for strength that updates every session. PRs are tracked on e1RM, not actual 1RM tests.",
            example: "Bench 225×8 estimates roughly to a 285 lb 1-rep max.",
            whatToDo:
                "Use e1RM for trends, not as a literal max. If it rises 5% over a month, you've gained real strength. Single-session e1RM swings of ±5% are normal noise."
        ),

        JargonTerm(
            id: "rpe",
            name: "Rate of Perceived Exertion",
            abbrev: "RPE",
            oneLineSummary: "How hard a set felt, from 1 (easy) to 10 (max effort, no reps left).",
            explanation:
                "RPE 10 = no reps in reserve. RPE 9 = 1 rep left in the tank. RPE 8 = 2 reps left. RPE 7 = 3 reps left. The engine uses your logged RPE to detect overreach and decide when to push weight up.",
            example: "Bench 225×8 with 2 reps left in the tank = RPE 8.",
            whatToDo:
                "Aim for the prescribed target RPE — usually 7–8 for hypertrophy work, 8–9 for strength. Going above 9.5 regularly accumulates fatigue and triggers the RPE brake (no weight increase)."
        ),

        JargonTerm(
            id: "stall",
            name: "Stall",
            abbrev: nil,
            oneLineSummary: "Your strength has stopped improving for several sessions in a row.",
            explanation:
                "When e1RM goes flat (or declines) for 3+ sessions, the algorithm flags a stall and tries to diagnose why. Four diagnoses: Fatigue Stall (recovery problem), Intensity Stall (not pushing hard enough), Volume Stall (too many sets), or True Plateau (this phase has run its course).",
            example: "Bench 225×8 for 3 weeks straight with rising IFI → Fatigue Stall. Same scenario with low RPE → Intensity Stall.",
            whatToDo:
                "Read the stall card's diagnosis. Fatigue → deload. Intensity → push harder, log RPE honestly. Volume → drop 2 sets. Plateau → switch rep range or accept the new ceiling."
        ),

        JargonTerm(
            id: "block_phase",
            name: "Block Phase",
            abbrev: nil,
            oneLineSummary: "Where you are in your training cycle — building volume, cranking intensity, peaking, or recovering.",
            explanation:
                "Programs are organized into multi-week blocks that each emphasize a different quality. Accumulation = high volume, moderate load. Intensification = lower volume, heavier load. Peaking = max load, low reps. Deload = light recovery week. Hypertrophy programs alternate accumulation and re-accumulation. Strength programs cycle accumulation → intensification → peaking.",
            example: "Powerbuilding goes: Accumulation (weeks 1–7) → Deload (8) → Intensification (9–15) → Deload (16) → Peaking (17–23) → Test (24).",
            whatToDo:
                "Trust the phase. Each prescribes different rep ranges and RPE targets on purpose. Don't try to PR during accumulation; don't chase volume during peaking."
        ),

        JargonTerm(
            id: "deload",
            name: "Deload",
            abbrev: nil,
            oneLineSummary: "A planned light week to recover from accumulated fatigue.",
            explanation:
                "Deload weeks reduce volume to ~50% and lighten weights. They dissipate accumulated fatigue so the next block can hit hard. Your program schedules them; the engine may also recommend an unplanned deload if MRV signals get high.",
            example: "Normal week: 4×8 bench. Deload week: 2–3×4–5 reps at the same weight (or 80% of it).",
            whatToDo:
                "Don't skip. The temptation is to push through, but skipped deloads lead to stalls and overreaching."
        ),

        JargonTerm(
            id: "acwr",
            name: "Acute:Chronic Workload Ratio",
            abbrev: "ACWR",
            oneLineSummary: "This week's training load compared to your 4-week average.",
            explanation:
                "A ratio of 'hot vs typical' training. Sweet spot is 0.8–1.3. Below means you're easing off; above means you've ramped faster than you've adapted, which elevates injury risk. Originally from sports-medicine research on injury prediction.",
            example: "Last 4 weeks averaged 100k tonnage. This week is 140k → ACWR 1.4 — a sizable spike.",
            whatToDo:
                "Spikes above 1.5 are red zone — back off this week. Drops below 0.8 mean you may lose adaptation; bump it up next week."
        ),

        JargonTerm(
            id: "balance_ratios",
            name: "Strength Balance Ratios",
            abbrev: nil,
            oneLineSummary: "How your push lifts compare to your pull lifts, anterior to posterior, etc.",
            explanation:
                "Persistent imbalances between opposing movements raise injury risk and can hold overall strength back. Four ratios tracked: Push:Pull (ideal 0.85–1.15), Posterior:Anterior (0.70–1.10), OHP:Bench (0.55–0.75), Squat:Deadlift (0.75–0.90).",
            example: "Bench 1RM 250, Barbell Row 1RM 150 → Push:Pull = 1.67, heavily push-dominant.",
            whatToDo:
                "If a ratio is outside the green zone, prioritize the lagging side. Don't chase the ratio aggressively — small persistent imbalances are usually fine."
        ),

        JargonTerm(
            id: "genetic_potential",
            name: "Genetic Potential (Estimate)",
            abbrev: nil,
            oneLineSummary: "A rough drug-free strength ceiling per lift, scaled to your bodyweight.",
            explanation:
                "Natural lifters tend to top out around bench=1.75×BW, squat=2.25×BW, deadlift=2.75×BW, OHP=1.15×BW. These are population averages from competition data and meta-analyses. Your individual ceiling depends on genetics, leverages, and how long you've been training seriously.",
            example: "At 180 lb bodyweight, estimated natural bench ceiling ≈ 315 lb. Benching 280 = 89% of estimated potential, Advanced tier.",
            whatToDo:
                "Use it as long-term reference, not a hard limit. The numbers are population averages — outliers exist in both directions."
        ),

        JargonTerm(
            id: "predictive_1rm",
            name: "Predictive 1RM Timeline",
            abbrev: nil,
            oneLineSummary: "Projects how many weeks until you hit a target weight, based on your trend.",
            explanation:
                "Linear regression on your last several sessions of e1RM. Requires 4+ sessions of data. Confidence depends on consistency — noisy data lowers confidence. The further out the prediction, the less reliable it gets.",
            example: "Bench gaining 2.5 lb/week, current e1RM 280, target 315 → ~14 weeks predicted.",
            whatToDo:
                "Useful for goal-setting and reality checks. Don't over-rely on it past a couple months — trends rarely hold cleanly that long."
        ),

        JargonTerm(
            id: "volume_zones",
            name: "Volume Zones",
            abbrev: nil,
            oneLineSummary: "How your weekly sets per muscle classify: under-training, building, optimal, or over-reaching.",
            explanation:
                "The 4-zone model: under-training (<MEV, no growth signal), building (MEV–MAVLow, growth ramping), optimal (MAVLow–MRV, best growth per set), over-reaching (>MRV, exceeding recovery). The color bars on the muscle coverage card show which zone each muscle is in this week.",
            example: "Chest at 14 sets/week with MEV=8, MAV=10–14, MRV=18 → optimal zone (green).",
            whatToDo:
                "Build up muscles in red/yellow zones, hold in green, drop sets in orange. Priority-tier muscles get higher targets than neutral-tier muscles."
        ),

        JargonTerm(
            id: "exercise_tiers",
            name: "Exercise Tiers",
            abbrev: "T1 / T2 / T3",
            oneLineSummary: "How exercises rank per muscle: T1 anchors, T2 supplements, T3 isolation finishers.",
            explanation:
                "T1 = the heavy compound anchor (e.g. barbell bench for chest). T2 = secondary compounds (e.g. incline DB). T3 = isolation/finisher movements (e.g. cable fly). Each tier has different rep ranges, RPE targets, and progression rules.",
            example: "Chest day: T1 bench (3–5 reps, RPE 8) → T2 incline DB (8–12 reps, RPE 7) → T3 cable fly (12–15 reps, RPE 9).",
            whatToDo:
                "Treat T1 like the priority — fresh, heavy. T2 builds size at moderate intensity. T3 finishes the muscle near failure."
        ),

        JargonTerm(
            id: "working_set",
            name: "Working Set",
            abbrev: nil,
            oneLineSummary: "Any set at 80%+ of your top weight that session — the ones that count for progress signals.",
            explanation:
                "Warm-ups, feeders, and back-off sets don't drive progress decisions. The engine only uses 'working sets' (≥80% of session max) to track rep performance, classify the progression rule (push/hold/back off), and compute IFI.",
            example: "Top set is 225×6. Anything 180+ counts as a working set. 135-lb pyramid sets at the start don't.",
            whatToDo:
                "Make sure your top working sets are logged accurately. Warm-ups can be sloppy — they don't change anything algorithmically."
        ),

        JargonTerm(
            id: "head_credits",
            name: "Head-Level Credits (Set-Equivalents)",
            abbrev: nil,
            oneLineSummary: "Each set credits a muscle's heads by how much that head contributes to the lift.",
            explanation:
                "When you log one set of any exercise, the muscle's heads don't all get full credit — they get a fraction based on the lift's anatomy. A chin-up gives the biceps long head about 0.7 of a set and the short head 0.9 (the underhand grip emphasizes the short head). Sum those fractions across the week to get each head's 'set-equivalents' — a continuous measure of how hard that head was worked.\n\nThe weight values come from EMG amplitude studies (Schoenfeld, MacDougall, others), competition-data analyses, and biomechanical reasoning about lever angles and joint positions. Standard compound exercises follow research-backed values; isolation exercises use the heuristic that the targeted head gets 1.0 and others get whatever they help with mechanically.",
            example: "3 chin-ups + 2 incline curls in a week:\n  Long head: 3 × 0.7 + 2 × 1.0 = 4.1 credits\n  Short head: 3 × 0.9 + 2 × 0.5 = 3.7 credits\n  Brachialis: 3 × 0.5 + 2 × 0.3 = 2.1 credits",
            whatToDo:
                "Use the head breakdown to spot which heads of a muscle are getting most of your stimulus. If one is lagging, swap in or add an exercise that emphasizes it (e.g., incline curl for long-head biceps, preacher curl for short-head). Tap a head row to see exactly which exercises are contributing to it this week."
        ),
    ]
}

// ═══════════════════════════════════════════
// JARGON HELP — small "ⓘ" icon next to a jargon term
// Opens an explainer sheet on tap. Caller is responsible for
// gating to advanced density (most call sites already are).
// ═══════════════════════════════════════════

struct JargonHelp: View {
    let termId: String
    var size: CGFloat = 11
    var color: Color = .appBlue

    @State private var showSheet = false

    var body: some View {
        Button {
            showSheet = true
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: size, weight: .medium))
                .foregroundColor(color)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSheet) {
            if let term = JargonGlossary.all[termId] {
                JargonExplainerSheet(term: term)
                    .presentationDetents([.medium, .large])
            }
        }
    }
}

// ═══════════════════════════════════════════
// JARGON EXPLAINER SHEET — body of a term's full explanation
// ═══════════════════════════════════════════

struct JargonExplainerSheet: View {
    let term: JargonTerm
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.appBorder)
                    .frame(width: 36, height: 4)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)

                // Header
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        if let abbrev = term.abbrev {
                            Text(abbrev)
                                .font(.system(size: 11, weight: .black, design: .monospaced))
                                .foregroundColor(.appRed)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.appRed.opacity(0.1))
                                .cornerRadius(5)
                        }
                        Text(term.name)
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(.appTextPrimary)
                    }
                    Text(term.oneLineSummary)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.appTextSecondary)
                }

                // Body
                section(label: "WHAT IT MEANS") {
                    Text(term.explanation)
                        .font(.system(size: 14))
                        .foregroundColor(.appTextPrimary)
                        .lineSpacing(4)
                }

                if let example = term.example {
                    section(label: "EXAMPLE") {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "quote.opening")
                                .font(.system(size: 11))
                                .foregroundColor(.appGold)
                            Text(example)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.appTextSecondary)
                                .lineSpacing(3)
                                .italic()
                        }
                        .padding(12)
                        .background(Color.appGold.opacity(0.06))
                        .cornerRadius(10)
                    }
                }

                if let whatToDo = term.whatToDo {
                    section(label: "WHAT TO DO") {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.appGreen)
                            Text(whatToDo)
                                .font(.system(size: 13))
                                .foregroundColor(.appTextPrimary)
                                .lineSpacing(3)
                        }
                        .padding(12)
                        .background(Color.appGreen.opacity(0.06))
                        .cornerRadius(10)
                    }
                }

                Button("Close") {
                    dismiss()
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.appTextSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.appSurface)
                .cornerRadius(10)
                .padding(.top, 8)
            }
            .padding(20)
            .padding(.bottom, 20)
        }
        .background(Color.appBG)
    }

    private func section<C: View>(label: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .black))
                .kerning(1.5)
                .foregroundColor(.appTextDim)
            content()
        }
    }
}
