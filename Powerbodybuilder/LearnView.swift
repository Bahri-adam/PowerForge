import SwiftUI
import SwiftData

struct LearnView: View {
    
    @Query private var programs: [UserProgram]
    @Query private var profiles: [UserProfile]
    
    var activeProgram: UserProgram? { programs.first(where: { $0.isActive }) }
    var profile: UserProfile? { profiles.first }
    
    @State private var selectedSection: LearnSection = .foundation
    
    enum LearnSection: String, CaseIterable {
        case foundation = "Foundation"
        case yourProgram = "Your Program"
        case concepts = "Concepts"
        case glossary = "Glossary"
        case comparisons = "Why Yours"
    }
    
    var body: some View {
        ZStack {
            Color.appBG
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                
                // HEADER
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("LEARN")
                                .font(.system(size: 28, weight: .black, design: .rounded))
                                .foregroundColor(.appTextPrimary)
                            Text("The science behind your training")
                                .font(.system(size: 13))
                                .foregroundColor(.appTextSecondary)
                        }
                        Spacer()
                        Image(systemName: "flask.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.appGold)
                    }
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(LearnSection.allCases, id: \.self) { section in
                                Button(action: { selectedSection = section }) {
                                    Text(section.rawValue)
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(selectedSection == section ? .white : .appTextSecondary)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(selectedSection == section ? Color.appGold : Color.appSurface2)
                                        .cornerRadius(20)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 20)
                                                .stroke(selectedSection == section ? Color.appGold : Color.appBorder, lineWidth: 1)
                                        )
                                }
                            }
                        }
                        .padding(.horizontal, 1)
                    }
                }
                .padding(20)
                .background(Color.appSurface)
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.appBorder),
                    alignment: .bottom
                )
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        switch selectedSection {
                        case .foundation:
                            FoundationSection()
                        case .yourProgram:
                            YourProgramSection(activeProgram: activeProgram)
                        case .concepts:
                            ConceptsSection()
                        case .glossary:
                            GlossarySection()
                        case .comparisons:
                            ComparisonsSection(activeProgram: activeProgram)
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 40)
                }
            }
        }
    }
}

// ═══════════════════════════════════════════
// LEARN CARD
// ═══════════════════════════════════════════

struct LearnCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let headline: String
    let cardContent: String
    @State private var expanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    expanded.toggle()
                }
            }) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(iconColor.opacity(0.15))
                            .frame(width: 40, height: 40)
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(iconColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.appTextDim)
                            .kerning(1.5)
                        Text(headline)
                            .font(.system(size: 15, weight: .black))
                            .foregroundColor(.appTextPrimary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                    
                    Spacer()
                    
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.appTextDim)
                }
                .padding(16)
            }
            .buttonStyle(.plain)
            
            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.appBorder)
                    
                    Text(cardContent)
                        .font(.system(size: 14))
                        .foregroundColor(.appTextSecondary)
                        .lineSpacing(5)
                        .padding(16)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.appSurface)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(expanded ? iconColor.opacity(0.3) : Color.appBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
    }
}

// ═══════════════════════════════════════════
// SECTION 1 — FOUNDATION
// ═══════════════════════════════════════════

struct FoundationSection: View {
    var body: some View {
        VStack(spacing: 12) {
            
            HStack(spacing: 12) {
                Image(systemName: "atom")
                    .font(.system(size: 20))
                    .foregroundColor(.appGold)
                VStack(alignment: .leading, spacing: 4) {
                    Text("THE SCIENCE FOUNDATION")
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(.appGold)
                        .kerning(1.5)
                    Text("Three mechanisms drive all muscle growth. Everything in your program targets at least one of them.")
                        .font(.system(size: 13))
                        .foregroundColor(.appTextSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .background(Color.appGold.opacity(0.06))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.appGold.opacity(0.2), lineWidth: 1)
            )
            
            LearnCard(
                icon: "bolt.fill",
                iconColor: .appRed,
                title: "MECHANISM 01",
                headline: "The most important thing happening when you lift.",
                cardContent: """
When a muscle fiber is loaded, the physical force of that load is transmitted through the contractile proteins — specifically the titin filaments and the sarcomere structure — and this deformation is detected by mechanosensors embedded in the cell membrane and cytoskeleton. The signal doesn't travel through your bloodstream. It's local, immediate, and mechanical.

This process is called mechanotransduction — the conversion of a physical force into a biochemical signal. The primary downstream effect is the activation of mTOR (mechanistic target of rapamycin), which is the master regulator of muscle protein synthesis. Mechanical tension activates mTOR through the ERK/TSC2 pathway and through the synthesis of phosphatidic acid by an enzyme called phospholipase D. Phosphatidic acid can also directly phosphorylate p70S6K — a downstream protein that drives ribosome activity and protein assembly — independent of mTOR entirely. So there are multiple parallel pathways activated simultaneously just by loading the muscle.

The research on what specifically drives the tension signal is worth understanding. Studies using animal models found that peak tension is a better predictor of anabolic signaling than time under tension alone — but a separate series of experiments found a linear relationship between time under tension and JNK signaling. The practical takeaway is that both the magnitude of the load and how long the muscle is under that load matter. This is why the app programs use controlled 3-second eccentrics on hypertrophy sets — you're extending the duration of peak tension on the portion of the rep where tension is highest, without simply adding fatigue-inducing reps.

One more important mechanistic detail: eccentric actions generate greater mechanosensitive signaling than concentric or isometric actions at equivalent loads. Rat plantaris muscle studies showed that eccentric stimulation produced the greatest phosphorylation of JNK and ERK1/2 compared to all other contraction types. This is a core reason why eccentric overload techniques are consistently effective for hypertrophy beyond what you'd expect from the load alone.

The practical takeaway: Mechanical tension is the primary driver of hypertrophy. You generate it by lifting loads heavy enough to challenge the muscle through a full range of motion, with controlled eccentrics, close to failure. Everything else in your program supports this.
"""
            )
            
            LearnCard(
                icon: "flame.fill",
                iconColor: .appGold,
                title: "MECHANISM 02",
                headline: "The burn, the pump, and why they're not just in your head.",
                cardContent: """
When you perform moderate-rep, higher-volume sets — the kind that create that burning feeling and skin-tightening pump — you're generating metabolic byproducts inside the muscle fiber: primarily lactate, inorganic phosphate (Pi), and hydrogen ions (H+). These aren't just uncomfortable waste products. They appear to trigger anabolic signaling through multiple mechanisms that are at least partially independent from mechanical tension.

The four proposed mechanisms for metabolic stress-driven hypertrophy:

1. Fiber recruitment. As H+ accumulates during a set, fast-twitch Type II fibers begin to fatigue. The nervous system compensates by recruiting additional high-threshold motor units to maintain force output. By the end of a high-rep set taken close to failure, you've recruited essentially the full available motor unit pool — similar to what you'd achieve with a maximal-effort heavy set — but you've done it through metabolic depletion rather than sheer load.

2. Cell swelling. When you perform a pump-style set, intracellular fluid shifts into the muscle cell, causing acute cellular hydration. Research suggests that cell swelling creates pressure against the cytoskeleton and cell membrane that the cell interprets as a mechanical threat to its structural integrity. In response, it upregulates anabolic protein-kinase cascades through integrin-associated volume osmosensors. This pathway appears to operate partially through mTOR and partially in an mTOR-independent fashion via MAPK modules.

3. Myokine production. Metabolic stress stimulates muscle fibers to secrete local signaling proteins called myokines — including IL-6, IGF-1 isoforms, and myostatin inhibitors — that act directly on the muscle tissue to promote protein synthesis and suppress protein breakdown.

4. Hormonal response. High-volume, short-rest protocols produce acute elevations in systemic testosterone, GH, and IGF-1. While the evidence for transient hormonal spikes as a primary driver of hypertrophy remains unclear, there is a rationale for a permissive role.

The practical takeaway: The pump sets in your program aren't filler. They're hitting a distinct anabolic pathway that your heavy compound sets don't fully activate. Running 12–20 rep pump finishers on isolation movements after your main hypertrophy work is mechanistically justified, not just tradition.
"""
            )
            
            LearnCard(
                icon: "bandage.fill",
                iconColor: .appBlue,
                title: "MECHANISM 03",
                headline: "Why you're sore — and what it's actually doing.",
                cardContent: """
Intense resistance training, particularly when it involves novel movements or heavy eccentric loading, causes exercise-induced muscle damage (EIMD). This can range from minor disruption to a few sarcomeres, all the way to small tears in the sarcolemma, cytoskeleton, and connective tissue around the contractile elements.

EIMD triggers a cascade that includes: local inflammation, disrupted calcium regulation (free Ca²⁺ leaks into the cell, activating proteolytic enzymes), activation of satellite cells (the muscle's stem cells), and the secretion of substances from damaged fibers that signal the body's repair system. The pain you feel 24–48 hours later — DOMS — is a byproduct of this inflammatory response, not the damage itself.

The relationship between EIMD and hypertrophy is real but nuanced. Controlled EIMD stimulates satellite cell activation and fusion, which adds myonuclei to muscle fibers — expanding the fiber's transcriptional capacity and long-term potential for growth. More myonuclei means more ribosome production capacity, which is the actual long-term limiting factor for hypertrophy.

However, there is a threshold beyond which additional EIMD stops contributing to growth and starts interfering with it. Excessive damage significantly reduces force-producing capacity in the days following training, which means you can't train with adequate volume and intensity in subsequent sessions. The lost stimulus from impaired training cancels out any additional damage signal you created.

Important: soreness is not the goal. A well-trained muscle adapts through the repeated bout effect — it becomes progressively more resistant to EIMD without losing its capacity for growth. As you get more advanced, you will be less sore from the same stimulus. This is a sign of adaptation, not a sign the training stopped working.

The practical takeaway: Chase stimulus, not soreness. Eccentric emphasis and novel exercises are your primary tools for generating productive EIMD. Keep it controlled. Excessive EIMD is counterproductive.
"""
            )
        }
    }
}

// ═══════════════════════════════════════════
// SECTION 2 — YOUR PROGRAM
// ═══════════════════════════════════════════

struct YourProgramSection: View {
    let activeProgram: UserProgram?
    
    var programTitle: String {
        guard let program = activeProgram else { return "No Active Program" }
        switch program.programId {
        case 1: return "Why You're On Powerbuilding"
        case 2: return "Why You're On Pure Hypertrophy"
        case 3: return "Why You're On Strength"
        case 4: return "Why You're On Beginner Full Body"
        case 5: return "Why You're On Athletic Performance"
        case 6: return "Why You're On Minimalist"
        default: return "Your Program"
        }
    }
    
    var programBody: String {
        guard let program = activeProgram else { return "Complete onboarding to see your program breakdown." }
        switch program.programId {
        case 1: return powerbuildingBody
        case 2: return hypertrophyBody
        case 3: return strengthBody
        case 4: return beginnerBody
        case 5: return athleticBody
        case 6: return minimalistBody
        default: return "Content coming soon."
        }
    }
    
    let powerbuildingBody = """
You told us your goal is to build strength and size simultaneously, you're past the beginner stage, and you're training 4–5 days per week. Powerbuilding is the only structure that deliberately targets both adaptations every single week rather than cycling between them seasonally.

THE CORE STRUCTURAL LOGIC

The program runs on Daily Undulating Periodization (DUP). Most programs either run heavy for months then shift to moderate loads, or they pick one lane and stay there. DUP rotates between heavy (3–5 reps) and moderate (8–12 reps) loading zones across the week.

This works because strength and hypertrophy adaptations, while complementary, involve partially distinct mechanisms. Heavy loading builds maximal motor unit recruitment, myofibrillar density, and neuromuscular efficiency. Moderate loading accumulates more total volume and drives greater metabolic stress alongside mechanical tension. Running both every week means you don't sacrifice one to train the other.

WHY UPPER/LOWER SPECIFICALLY

The upper/lower split hits each muscle group twice per week. Schoenfeld's frequency research confirms that once weekly volume exceeds 10 sets per muscle, splitting it across at least two sessions per week produces superior hypertrophy to cramming it into one session. The per-session ceiling for productive volume appears to be around 10 quality sets.

By training upper body twice and lower body twice, you stay under that ceiling in each session while accumulating 14–20 sets per muscle weekly — comfortably in the optimal range.

THE NON-NEGOTIABLE TECHNIQUES

3-second eccentrics: Eccentric actions generate the greatest mechanosensitive signaling. Slowing the descent extends the duration of peak tension and increases time under mechanical load.

Loaded stretch holds: Preliminary research suggests holding a stretch under load during rest may amplify the hypertrophic stimulus through fascial elongation and sarcomere-in-series growth. The mechanistic rationale is sound.

RPE targets instead of fixed percentages: Your daily readiness fluctuates based on sleep, fatigue, stress hormones, and nutrition. Using RPE auto-regulates for this reality — you're always training at the right intensity regardless of what the number on the bar says.

WHAT THE DELOAD WEEK IS DOING

By week 4, fatigue is masking your actual fitness level. You're stronger than you feel — but accumulated neural fatigue, muscle damage repair debt, and hormonal shifts are suppressing expression of that strength. Dropping volume by 40% while maintaining loads for one week allows this fatigue to dissipate and actual fitness to surface. This is supercompensation.
"""
    
    let hypertrophyBody = """
You told us muscle size is the primary goal, you're training 5–6 days per week, and you're past the beginner stage. Pure Hypertrophy (PPL) is the most efficient structure that exists for maximizing weekly volume per muscle group while respecting the biological constraints on per-session quality and recovery frequency.

THE CORE STRUCTURAL LOGIC

Push/Pull/Legs run twice per week — six training days total. This structure exists for one specific reason: it allows you to accumulate 16–22 working sets per muscle per week while keeping each individual session under the per-session quality ceiling of approximately 8–10 hard sets per muscle.

Why does the per-session ceiling exist? As set number increases within a session, the quality of the stimulus degrades. Fatigue reduces force output, technique deteriorates, and the signal-to-noise ratio of anabolic signaling drops. Schoenfeld's dose-response research found that more sets drive more growth — but only up to the point where fatigue compromises the quality of subsequent sets. Spreading volume across two sessions per muscle per week lets you capture the full volume benefit without hitting that quality ceiling.

THE A/B ALTERNATING STRUCTURE

Push A and Push B are not the same session. This is intentional. Push A leads with flat barbell bench (horizontal press dominant). Push B leads with overhead press (vertical press dominant). The A/B alternation achieves two things simultaneously:

1. Movement pattern coverage. Horizontal and vertical pressing recruit the anterior deltoid, triceps, and pectoralis major through different moment arms and from different joint positions. Running both twice per week ensures complete coverage without doubling session length.

2. Stimulus novelty. The repeated bout effect means a muscle rapidly adapts to a specific stimulus. Rotating exercises between sessions slows this accommodation and maintains productive exercise-induced muscle damage across the full mesocycle.

THE THREE REP RANGES — NOT INTERCHANGEABLE

The program deliberately cycles through three rep ranges across the week. This is not arbitrary — each range targets a partially distinct hypertrophic pathway:

Heavy sets (4–6 reps, 80–85% 1RM): These maximize mechanical tension on high-threshold motor units. At these loads, you're recruiting the full motor unit pool including the largest Type IIx fibers. Heavy low-rep work is the primary driver of myofibrillar protein accretion — growth in the actual contractile machinery of the muscle cell.

Moderate sets (8–12 reps, 65–75% 1RM): The most efficient range for combined mechanical tension and metabolic stress. These sets generate substantial lactate, inorganic phosphate, and hydrogen ion accumulation while maintaining enough load to drive robust mechanosensory signaling. This is where the majority of your working volume sits because it delivers the best return per unit of fatigue.

Light pump sets (12–20 reps, 50–65% 1RM): The mechanism here is cell swelling driven by metabolite accumulation and fluid shifts into the muscle cell. Research indicates this cellular hydration creates osmotic pressure against the cytoskeleton that triggers anabolic signaling via MAPK pathways — partially independent of mTOR. This is genuinely additive stimulus, not redundant with heavier work. It also creates significant muscular endurance adaptations in the oxidative fibers.

Using all three rep ranges means you're stimulating hypertrophy through three partially independent pathways every week. A program locked into one rep range is leaving stimulus on the table.

PROXIMITY TO FAILURE

Every working set is taken to RIR 1–2 (RPE 8–9). This is non-negotiable for maximum hypertrophic stimulus. Schoenfeld's research is explicit: sets stopped more than 3 reps from failure produce significantly less hypertrophic stimulus than sets taken close to failure, regardless of the load used. The mechanism is motor unit recruitment — only when accumulated fatigue forces the nervous system to recruit additional high-threshold motor units does the hypertrophic signal reach those fibers.

The RPE targets in this program are therefore not suggestions. They're the mechanism.

THE DELOAD STRUCTURE

Weeks 4, 12, and 16 are deload weeks. This is the General Adaptation Syndrome (Selye, 1956) applied directly to training programming. The GAS model has three phases: alarm (acute training stress), resistance (adaptation), and exhaustion (accumulated fatigue exceeds recovery capacity). Deloads prevent the transition into exhaustion by deliberately dropping stimulus before fatigue compounds.

Practically: by week 3, accumulated peripheral fatigue (muscle damage, glycogen depletion, connective tissue stress) and central fatigue (reduced neuromuscular drive, elevated cortisol, downregulated anabolic signaling) begin to mask actual fitness expression. You are stronger than you feel, but the fatigue is suppressing it. Dropping to MEV (6–8 sets per muscle) for one week while maintaining loads allows fatigue to dissipate and actual fitness to surface — this is supercompensation. The week after a properly executed deload consistently produces strength and performance PRs.

Block 2 (weeks 9–16) runs at slightly higher intensity with modestly lower volume compared to Block 1. This is the intensification phase: you've built the volume tolerance and movement efficiency in Block 1, now you're converting that base into peak performance. Main lifts shift to 3–5 rep ranges at RPE 8.5–9.0, squeezing out the last available neural adaptations before the final deload.

THE SCIENCE OF FREQUENCY

Each muscle is trained twice per week. This matches the research consensus on optimal training frequency for intermediate hypertrophy. Muscle protein synthesis (MPS) is elevated for approximately 24–48 hours post-training in trained individuals before returning to baseline. Training a muscle once per week means 5–6 days of baseline MPS between sessions — wasted anabolic time. Twice-per-week frequency keeps each muscle cycling through the MPS elevation twice, roughly doubling the cumulative anabolic time over a training week.

Studies comparing 1x vs 2x vs 3x weekly frequency at equated volume consistently show frequency 2x or higher produces superior hypertrophy to 1x. Frequency beyond 2x produces additional benefit only at very high volumes that most lifters can't sustain.

THE CONTROLLED ECCENTRIC

All hypertrophy sets use a 3-second eccentric. The scientific basis: eccentric actions generate greater mechanosensitive signaling than concentric or isometric actions at equivalent loads. Studies using rat plantaris muscle showed eccentric stimulation produced the greatest phosphorylation of JNK and ERK1/2 — key upstream kinases in hypertrophic signaling cascades — compared to concentric and isometric contractions. Slowing the eccentric extends the duration of peak tension through the stretch position, which is where passive mechanical tension through titin is highest. You are generating more hypertrophic signal per rep simply by controlling the descent.
"""
    
    let strengthBody = """
Your goal is purely maximizing your squat, bench, and deadlift — either for competition or personal standard.

THE CORE STRUCTURAL LOGIC

Strength gains in trained lifters are primarily neurological — greater motor unit recruitment, rate coding, synchronization, and inter-muscular coordination. Mechanical tension at near-maximal loads is necessary to recruit high-threshold fast-twitch motor units (Henneman's Size Principle), which are otherwise undertrained in hypertrophy rep ranges. Training the three competition lifts with high specificity drives the precise neuromuscular pattern required for maximal force expression.

RPE AUTO-REGULATION

RPE auto-regulation rather than fixed percentages is supported by evidence that daily fluctuations in readiness significantly affect training stimulus. An RPE 8 on a poor recovery day may be the same weight as RPE 6 on a peak day — rigid percentage-based programming ignores this.

LOWER VOLUME BY DESIGN

The lower weekly volume (10–14 sets/muscle) reflects the recovery demand of heavy CNS-taxing loads. Research confirms muscle adapts with lower volumes when intensity is high — the trade-off is intentional. You're trading volume for intensity, and at this level of loading, intensity wins.
"""
    
    let beginnerBody = """
Your training age means your primary adaptation right now is neural — your body is learning to recruit muscle fibers, coordinate movement patterns, and express force efficiently. This adaptation happens through practice frequency, not volume overload.

THE NOVICE WINDOW

Early-phase strength gains in beginners are almost entirely neural — improved motor unit recruitment, rate coding, synchronization, and doublet firing. True structural hypertrophy takes 6–8 weeks to manifest. This means a beginner can train the same movement pattern every 48 hours because the adaptation mechanism (neural, not structural) recovers faster.

Full body 3x/week is optimal because each movement pattern is practiced 3 times per week, accelerating motor learning and cementing technique before load becomes dangerous.

LINEAR PROGRESSION — USE IT WHILE YOU CAN

Adding weight every session matches the novice's rate of adaptation exactly. No other training structure allows this. When this stalls consistently, the novice window has closed — graduate to Program 01 or 02.

A beginner doing PPL or Powerbuilding is like a student trying to master calculus before algebra — the structure is too complex for the current stage of adaptation.
"""
    
    let athleticBody = """
You have an athletic background and want to be functional and explosive, not just strong in a cage.

THE CORE STRUCTURAL LOGIC

Power = force × velocity. Pure strength training builds force but not rate of force development (RFD). Pure hypertrophy builds muscle cross-section but not neuromuscular efficiency for explosive movement. Athletic performance requires both — and it requires training the nervous system to express force rapidly.

POST-ACTIVATION POTENTIATION

The contrast loading principle — pairing a heavy compound set with an explosive movement targeting the same muscle group — is grounded in post-activation potentiation (PAP). The heavy preceding set acutely elevates neuromuscular excitability and phosphorylation of myosin regulatory light chains, which enhances the force and velocity of subsequent explosive contractions. This is why Day 1 pairs heavy bench with medicine ball throws, and Day 2 pairs heavy squats with box jumps.

VELOCITY INTENT

Velocity intent on the concentric phase is the critical training cue. Research confirms that submaximal loads lifted with maximal intent recruit motor unit populations approaching those recruited under truly maximal loads — preserving the neural adaptation stimulus at lower, more manageable loads.
"""
    
    let minimalistBody = """
Not because it produces the best results — it doesn't. The Minimalist program is a life management tool.

MINIMUM EFFECTIVE VOLUME

MEV (Minimum Effective Volume) is the lowest number of sets per muscle per week that produces a positive adaptive response — approximately 6–10 sets/muscle/week for most intermediate trainees. Below MEV you detrain. Above MRV you accumulate fatigue faster than you recover. The Minimalist program deliberately targets MEV — not to optimize gains, but to remain on the positive side of the adaptation curve with minimum investment.

WHY FULL BODY 3X/WEEK AT LOW VOLUME

Full body 3x/week maximizes stimulus frequency at low volume — each muscle is hit 3x/week. At low volumes, frequency matters more because the protein synthetic response is triggered more often. Schoenfeld notes that in trained individuals, muscle protein synthesis peaks higher but returns to baseline in under 28 hours — meaning time away from training a muscle is time at baseline MPS.

SUPERSETS

Supersets on accessory exercises cut effective session time by 30–40% with no loss of hypertrophic stimulus when rest between muscle groups is adequate — the resting muscle group recovers during the working muscle's set.

When your schedule opens up, transition to Program 01 or 02 and you'll find your fitness largely intact and your strength expression ready to build on.
"""
    
    var body: some View {
        VStack(spacing: 12) {
            
            if let program = activeProgram,
               let def = allPrograms.first(where: { $0.id == program.programId }) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(def.accentColor.opacity(0.15))
                            .frame(width: 40, height: 40)
                        Image(systemName: def.icon)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(def.accentColor)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ACTIVE PROGRAM")
                            .font(.system(size: 9, weight: .black))
                            .foregroundColor(def.accentColor)
                            .kerning(1.5)
                        Text(def.name)
                            .font(.system(size: 16, weight: .black))
                            .foregroundColor(.appTextPrimary)
                    }
                    Spacer()
                    Text("WK \(program.currentWeek)")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(def.accentColor)
                }
                .padding(14)
                .background(def.accentColor.opacity(0.06))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(def.accentColor.opacity(0.2), lineWidth: 1)
                )
            }
            
            LearnCard(
                icon: "book.fill",
                iconColor: activeProgram.flatMap { p in allPrograms.first(where: { $0.id == p.programId }) }?.accentColor ?? .appGold,
                title: "YOUR PROGRAM BREAKDOWN",
                headline: programTitle,
                cardContent: programBody
            )
        }
    }
}

// ═══════════════════════════════════════════
// SECTION 3 — CONCEPTS
// ═══════════════════════════════════════════

struct ConceptsSection: View {
    var body: some View {
        VStack(spacing: 12) {
            
            LearnCard(
                icon: "arrow.up.right",
                iconColor: .appGreen,
                title: "CONCEPT 01 — PROGRESSIVE OVERLOAD",
                headline: "The only rule that can't be broken.",
                cardContent: """
Progressive overload is the principle that the training stimulus must increase over time for adaptation to continue. Your body adapts to stress — once it has adapted, the same stimulus produces maintenance, not growth. You have to give it a reason to keep building.

There are five distinct vectors of progressive overload:

1. Load progression — adding weight to the bar. The most direct form. Valid when technique is solid and you're not approaching your maximum recoverable load.

2. Volume progression — adding sets over time. At equal effort and load, more weekly sets produce more hypertrophy up to the MRV ceiling.

3. Rep progression (double progression) — within a target rep range, progress reps before adding load. Hit 3×10 at 80kg this week, hit 3×12 next week, then jump to 3×10 at 85kg. This is the most practical method for hypertrophy training.

4. Density progression — doing the same work in less time. Less commonly tracked but valid as a fatigue-management strategy.

5. Technique progression — achieving greater range of motion, better mind-muscle connection, or more controlled eccentric phases at the same load. Highly relevant in early training stages.

What prevents progressive overload: Excessive fatigue accumulation (not deloading), insufficient nutrition (caloric deficit blunts mTOR signaling via AMPK activation), inadequate sleep (the majority of growth hormone secretion occurs during slow-wave sleep), and too many sets per session past the quality threshold. If your loads have been flat for 3+ weeks, the problem is almost always one of these four, not effort.
"""
            )
            
            LearnCard(
                icon: "moon.fill",
                iconColor: .appBlue,
                title: "CONCEPT 02 — DELOAD STRATEGY",
                headline: "You don't grow during training. You grow during recovery.",
                cardContent: """
A deload is a planned period of reduced training stress designed to allow accumulated fatigue to dissipate while preserving — and in many cases expressing — fitness gains that were previously masked.

THE PHYSIOLOGY

Intense resistance training is a stressor. Under Selye's General Adaptation Syndrome (GAS) framework, the body responds in three phases: alarm (acute inflammatory and catabolic response immediately post-training), resistance (adaptation and supercompensation — the muscle grows back stronger), and exhaustion (if stress continues without adequate recovery, the system breaks down). A deload is a deliberate trigger of the transition from resistance to supercompensation.

Schoenfeld's research references animal studies showing that chronic resistance training progressively suppresses phosphorylation of key intracellular anabolic signaling proteins, and that this suppression is restored after a brief detraining period. Without planned recovery periods, the anabolic signaling response to training progressively blunts over time.

Additionally, persistent failure training has been shown to cause reductions in resting IGF-1 concentrations and blunted testosterone levels over a 16-week period in trained individuals. Deloads prevent this hormonal suppression.

THE MOST IMPORTANT RULE FOR DELOADS

Keep the loads. Reducing weight reinforces the detraining response. Reducing volume while maintaining intensity keeps the neuromuscular system primed and allows fatigue to clear without losing the strength expression you've built.
"""
            )
            
            LearnCard(
                icon: "slider.horizontal.3",
                iconColor: .appRed,
                title: "CONCEPT 03 — REP RANGE SCIENCE",
                headline: "Why the 'hypertrophy range' isn't the whole story.",
                cardContent: """
The conventional wisdom is that 8–12 reps is the "hypertrophy range." This is partially correct but incomplete in a way that matters.

WHAT THE RESEARCH ACTUALLY SHOWS

Studies comparing heavy (1–5 reps), moderate (6–12 reps), and light (15–30 reps) training when sets are equated for effort (all taken close to failure) show similar hypertrophic outcomes across all three ranges. A landmark study by Schoenfeld et al. showed comparable muscle growth in groups training at 25–35% 1RM versus 70–80% 1RM when both trained to near-failure. The key variable is effort, not rep count.

THREE IMPORTANT DISTINCTIONS THAT REMAIN

1. Fiber type specificity. Type I (slow-twitch) fibers are best developed with higher rep, lower load training. Type II (fast-twitch) fibers respond well to heavy loading. For complete muscular development, you need both ends of the rep spectrum.

2. Volume efficiency. Training at 6–12 reps allows you to accumulate the most total volume-load per unit of time and fatigue. Very heavy sets require long rest and tax the CNS heavily. Very light sets are time-consuming and generate high peripheral fatigue.

3. Signaling specificity. Research shows divergent anabolic signaling responses between loading zones. Moderate loads (65% 1RM) produce greater phosphorylation of p70S6K. High loads (85% 1RM) produce greater phosphorylation of ERK1/2. These aren't redundant pathways — they converge on growth through partially distinct routes.

Your program intentionally uses multiple rep ranges across the week. Dropping any one of them leaves a physiological stimulus on the table.
"""
            )
            
            LearnCard(
                icon: "calendar",
                iconColor: .appGold,
                title: "CONCEPT 04 — FREQUENCY VS VOLUME",
                headline: "How often you train a muscle matters less than you think — until it doesn't.",
                cardContent: """
The short version: When weekly volume is held constant, training a muscle 1x, 2x, or 3x per week produces similar hypertrophy. Frequency by itself is not the driver of growth.

THE LONGER VERSION THAT ACTUALLY MATTERS

The reason frequency matters in practice is as a delivery mechanism for volume. There is a per-session ceiling for productive training volume — research points to approximately 10 high-quality sets per muscle group per session. Beyond that threshold, accumulated fatigue within the session degrades the quality of each subsequent set, and the stimulus-to-fatigue ratio drops sharply.

If your target weekly volume for a muscle is 10–14 sets, you can do it in one session. If your target is 16–22 sets, you can't efficiently fit that into one session without the second half being significantly lower quality. Splitting it across two sessions — each with 8–11 sets — maintains quality throughout.

PROTEIN SYNTHESIS TIMING

In beginners, muscle protein synthesis (MPS) remains elevated for 48+ hours after training. In trained individuals, MPS peaks higher but returns to baseline in under 28 hours. This means a trained lifter spending 4–5 days away from training a given muscle is spending significant time at baseline MPS — not growing. Higher frequency keeps the muscle in a more consistently elevated synthetic state.
"""
            )
            
            LearnCard(
                icon: "gauge.high",
                iconColor: .appGreen,
                title: "CONCEPT 05 — RIR AND RPE",
                headline: "The two most useful numbers you'll track in this app.",
                cardContent: """
RIR — REPS IN RESERVE

RIR is how many reps you had left in the tank when you stopped a set. RIR 0 = failure. RIR 1 = one rep left. RIR 2 = two reps left.

Schoenfeld's work is explicit that the proximity of a set to failure is one of the primary determinants of whether that set drives hypertrophy. Sets stopped too far from failure don't generate sufficient mechanical fatigue or motor unit recruitment to stimulate growth meaningfully. Most sets should be taken to RIR 1–2 to maximize stimulus while managing fatigue.

Failure training (RIR 0) can be selectively used on the final set of isolation exercises but should be used sparingly on multi-joint compound movements — they're far more taxing on the CNS and carry higher injury risk at true failure.

RPE — RATE OF PERCEIVED EXERTION

RPE is a 1–10 scale for how hard a set felt, with 10 being maximum effort:
- RPE 10 = could not have done another rep
- RPE 9 = could have done 1 more (≈ RIR 1)
- RPE 8 = could have done 2 more (≈ RIR 2)
- RPE 7 = could have done 3 more

WHY RPE BEATS FIXED PERCENTAGES

Your 1RM fluctuates daily based on sleep, stress, accumulated fatigue, hydration, and nutrition. A weight that represents 80% 1RM on a peak day might feel like 87% on a poor recovery day. Fixed-percentage programs ignore this and force you to train at incorrect intensities regularly. RPE-based prescriptions like "4×4 @ RPE 8" tell you to work at the right effort level regardless of what that requires in absolute weight.
"""
            )
            
            LearnCard(
                icon: "chart.line.uptrend.xyaxis",
                iconColor: .appRed,
                title: "CONCEPT 06 — e1RM",
                headline: "Your estimated max — and why it's more useful than your actual max.",
                cardContent: """
e1RM (estimated one-rep maximum) is a mathematical projection of what you could theoretically lift for a single maximal rep, based on the weight you lifted for multiple reps. The most widely used formula:

e1RM = weight × (1 + reps / 30)

Example: You bench 100kg for 8 reps. e1RM = 100 × (1 + 8/30) = 100 × 1.267 = 126.7kg.

WHY NOT JUST TEST YOUR ACTUAL 1RM?

Testing a true 1RM requires significant CNS preparation, carries injury risk, and is only accurate on a specific day under specific conditions. For the vast majority of training purposes — load selection, progress tracking, program design — e1RM is more useful because it can be calculated from every working set of every session, giving you a continuous trend line instead of a single data point every few months.

HOW THE APP USES e1RM

The app calculates e1RM from every logged set automatically. This creates a running trend line for every exercise. If your bench e1RM is trending upward over 8 weeks, you're getting stronger, regardless of what any individual session felt like. If it's flat or declining, something in recovery or programming needs to change.

The app's calculations are most reliable between 3 and 12 reps per set.
"""
            )
        }
    }
}

// ═══════════════════════════════════════════
// SECTION 4 — COMPARISONS
// ═══════════════════════════════════════════

struct ComparisonsSection: View {
    let activeProgram: UserProgram?
    
    var comparisonTitles: [String] {
        guard let program = activeProgram else { return [] }
        switch program.programId {
        case 1: return ["Powerbuilding vs Pure Hypertrophy", "Powerbuilding vs Strength"]
        case 2: return ["Pure Hypertrophy vs Powerbuilding", "Pure Hypertrophy vs Strength"]
        case 3: return ["Strength vs Powerbuilding"]
        case 4: return ["Beginner Full Body vs Everything Else"]
        case 5: return ["Athletic Performance vs Powerbuilding"]
        case 6: return ["Minimalist vs Any Other Program"]
        default: return []
        }
    }
    
    var comparisonBodies: [String] {
        guard let program = activeProgram else { return [] }
        switch program.programId {
        case 1: return [
            "You're training 4–5 days, not 5–6. And importantly, you want strength to track alongside your size. Pure Hypertrophy maximizes muscle growth but does so at the cost of strength development: higher rep ranges and greater per-session volume leave less room for the heavy neural adaptation work that moves your squat, bench, and deadlift.\n\nPowerbuilding gives you both by explicitly designating heavy sessions and hypertrophy sessions each week, running them in parallel rather than trading one off for the other.\n\nIf your days-per-week ever increase to 5–6 and aesthetics become your single priority, Program 02 would serve you better.",
            "You want to build muscle alongside strength, not just maximize your 1RMs. Program 03 is optimized for peak force expression: lower volume, longer rest periods, and almost no higher-rep work. It's excellent for competitive powerlifters.\n\nBut for someone who wants to look the part as well as perform, the volume in Program 03 is intentionally too low to drive meaningful hypertrophy. Powerbuilding maintains strength blocks while adding the volume necessary for aesthetic development."
        ]
        case 2: return [
            "You have the time for 5–6 days and muscle size is the only goal. PPL twice per week allows weekly volume to reach 16–22 sets per muscle while keeping each session under the quality ceiling.\n\nThat volume range is where the best-responding individuals in Schoenfeld's dose-response research sit. Powerbuilding at 4 days caps at 14–18 sets/muscle — still excellent, but structurally constrained by the fact that it allocates session space to strength-specific work (heavy doubles and triples at long rest periods) that doesn't contribute as efficiently to hypertrophy. If building maximum muscle is the singular goal and you can sustain 6 days, PPL is the correct tool.\n\nIf you want meaningful strength development alongside size, Powerbuilding is superior — the heavy sessions develop the neuromuscular adaptations that PPL's rep ranges don't optimally target.",
            "The Strength program runs 3–4 days at 85–95% 1RM with 10–14 sets per muscle per week. That volume is intentionally low — recovery demand from near-maximal loading limits how much total work the body can absorb.\n\nPure Hypertrophy runs 6 days at a much wider intensity range and 16–22 sets per muscle. The trade-off is direct: Strength produces superior neuromuscular adaptations (motor unit recruitment, rate coding, myofibrillar density at high percentages of max), but those adaptations don't translate to maximum muscle cross-sectional area.\n\nHypertrophy is primarily a volume game at the right intensity. Strength is primarily an intensity game at the right specificity. You chose hypertrophy — the 6-day PPL is the correct tool for that goal."
        ]
        case 3: return [
            "Your goal is purely maximizing your squat, bench, and deadlift — either for competition or personal standard.\n\nThe powerbuilding structure, while effective for concurrent goals, always involves compromise: some volume that could be devoted to heavy strength work goes to hypertrophy work instead. For pure strength expression, the Strength program's higher weekly intensity, longer rest periods, and competition-movement specificity will develop your lifts faster.\n\nIf aesthetics matter at all, Powerbuilding is the better choice. If they genuinely don't, Program 03 is the right tool."
        ]
        case 4: return [
            "Your training age means your primary adaptation right now is neural — your body is learning to recruit muscle fibers, coordinate movement patterns, and express force efficiently. This adaptation happens through practice frequency, not volume overload.\n\nA beginner doing PPL or Powerbuilding is like a student trying to master calculus before algebra — the structure is too complex for the current stage of adaptation. Full body 3x/week with linear progression exploits the novice window, where you can increase strength on a session-by-session basis, in a way no other training structure allows.\n\nOnce that progression stalls, the window has closed and more complex programming is warranted."
        ]
        case 5: return [
            "You have an athletic background and want to be functional and explosive, not just strong in a cage. Powerbuilding develops force at slow velocities — great for muscle size and absolute strength, but it doesn't train rate of force development (RFD), reactive strength, or the neuromuscular patterns needed for athletic performance.\n\nProgram 05 incorporates power work (box jumps, explosive pressing, contrast loading) that specifically trains the nervous system to express force at speed. If you never need to jump, sprint, or move reactively, Powerbuilding is more efficient. If you do, Program 05 builds the complete athletic profile."
        ]
        case 6: return [
            "Not because it produces the best results — it doesn't. The Minimalist program is a life management tool. It keeps you on the right side of the adaptation curve during periods when training can't be the priority.\n\nThe research on MEV confirms that 6–10 sets per muscle per week, performed with reasonable effort and progressive overload, is sufficient to maintain and in some cases slowly build muscle. That's the entire goal of this program.\n\nWhen your schedule opens up, transition to Program 01 or 02 and you'll find your fitness largely intact and your strength expression ready to build on."
        ]
        default: return []
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            
            if comparisonTitles.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 32))
                        .foregroundColor(.appTextDim)
                    Text("Complete onboarding to see why your program was recommended over the alternatives.")
                        .font(.system(size: 14))
                        .foregroundColor(.appTextSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(40)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14))
                        .foregroundColor(.appGold)
                    Text("Why your program was chosen over the alternatives — based on your specific goals and schedule.")
                        .font(.system(size: 13))
                        .foregroundColor(.appTextSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(Color.appGold.opacity(0.06))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.appGold.opacity(0.2), lineWidth: 1)
                )
                
                ForEach(0..<comparisonTitles.count, id: \.self) { i in
                    LearnCard(
                        icon: "arrow.triangle.branch",
                        iconColor: .appGold,
                        title: "PROGRAM COMPARISON",
                        headline: comparisonTitles[i],
                        cardContent: comparisonBodies[i]
                    )
                }
            }
        }
    }
}

// ═══════════════════════════════════════════
// GLOSSARY SECTION
// All JargonGlossary entries as searchable, tappable rows.
// Tap a row → opens the same JargonExplainerSheet used by the
// in-context "ⓘ" icons throughout the app.
// ═══════════════════════════════════════════

struct GlossarySection: View {
    @State private var searchText: String = ""
    @State private var selectedTerm: JargonTerm? = nil

    private var filteredTerms: [JargonTerm] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return JargonGlossary.entries }
        return JargonGlossary.entries.filter { term in
            term.name.lowercased().contains(q)
                || (term.abbrev?.lowercased().contains(q) ?? false)
                || term.oneLineSummary.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            // Intro
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.appGold)
                    Text("Glossary")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(.appTextPrimary)
                }
                Text("Every metric and concept the app uses, defined in one place. Tap any term for the full explanation.")
                    .font(.system(size: 12))
                    .foregroundColor(.appTextSecondary)
                    .lineSpacing(2)
            }
            .padding(14)
            .background(Color.appGold.opacity(0.06))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.appGold.opacity(0.2), lineWidth: 1)
            )

            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundColor(.appTextDim)
                TextField("", text: $searchText)
                    .placeholder(when: searchText.isEmpty) {
                        Text("Search terms…").foregroundColor(.appTextDim)
                    }
                    .font(.system(size: 14))
                    .foregroundColor(.appTextPrimary)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.appTextDim)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color.appSurface2)
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))

            // Term list
            VStack(spacing: 0) {
                ForEach(Array(filteredTerms.enumerated()), id: \.element.id) { idx, term in
                    Button {
                        selectedTerm = term
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    if let abbrev = term.abbrev {
                                        Text(abbrev)
                                            .font(.system(size: 10, weight: .black, design: .monospaced))
                                            .foregroundColor(.appRed)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Color.appRed.opacity(0.1))
                                            .cornerRadius(4)
                                    }
                                    Text(term.name)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.appTextPrimary)
                                }
                                Text(term.oneLineSummary)
                                    .font(.system(size: 11))
                                    .foregroundColor(.appTextDim)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.appTextDim)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if idx < filteredTerms.count - 1 {
                        Divider().background(Color.appBorder).padding(.leading, 14)
                    }
                }

                if filteredTerms.isEmpty {
                    VStack(spacing: 6) {
                        Text("No matches")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.appTextSecondary)
                        Text("Try a different search term.")
                            .font(.system(size: 11))
                            .foregroundColor(.appTextDim)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                }
            }
            .background(Color.appSurface)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
        }
        .sheet(item: $selectedTerm) { term in
            JargonExplainerSheet(term: term)
                .presentationDetents([.medium, .large])
        }
    }
}

