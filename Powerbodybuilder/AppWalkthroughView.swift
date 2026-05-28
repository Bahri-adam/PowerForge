import SwiftUI
import SwiftData

// ═══════════════════════════════════════════
// APP WALKTHROUGH
// Video-game-style guided tour shown after onboarding and replayable
// from Settings. Steps are chaptered (Intro/Home/Train/Program/Progress/
// Settings/Outro) and density-aware — minimal users skip the advanced-
// jargon steps.
//
// Each step shows a chapter chip, step counter, title, action prompt,
// a small mockup illustration of the relevant UI, and a description.
// User reads, taps Next, applies what they learned in the real app.
// ═══════════════════════════════════════════

enum WalkthroughChapter: String, CaseIterable {
    case intro    = "WELCOME"
    case home     = "HOME TAB"
    case train    = "TRAIN TAB"
    case program  = "PROGRAM TAB"
    case progress = "PROGRESS TAB"
    case settings = "SETTINGS"
    case outro    = "YOU'RE READY"

    var color: Color {
        switch self {
        case .intro:    return .appRed
        case .home:     return .appRed
        case .train:    return .appBlue
        case .program:  return .appGreen
        case .progress: return .appGold
        case .settings: return .appOrange
        case .outro:    return .appRed
        }
    }
}

struct WalkthroughStep: Identifiable {
    let id: Int
    let chapter: WalkthroughChapter
    let title: String
    let action: String?       // optional one-liner: "Tap Configure Week"
    let description: String
    let densities: Set<UIDensity>
    let mockup: () -> AnyView
}

// ═══════════════════════════════════════════
// STEP CATALOG
// ═══════════════════════════════════════════

enum WalkthroughCatalog {
    static let all: [WalkthroughStep] = {
        var steps: [WalkthroughStep] = []
        var id = 0
        func step(_ c: WalkthroughChapter, _ t: String, _ a: String?, _ d: String,
                  _ den: Set<UIDensity> = [.minimal, .standard, .advanced],
                  _ m: @escaping () -> AnyView) -> WalkthroughStep {
            id += 1
            return WalkthroughStep(id: id, chapter: c, title: t, action: a, description: d, densities: den, mockup: m)
        }

        let all: Set<UIDensity> = [.minimal, .standard, .advanced]
        let stdAdv: Set<UIDensity> = [.standard, .advanced]
        let advOnly: Set<UIDensity> = [.advanced]

        // ── INTRO ────────────────────────────────────────────────
        steps.append(step(.intro,
            "Welcome to PowerForge",
            nil,
            "Let's walk through every feature in about two minutes. Tap Next to advance, Skip to bail out anytime, and Back to revisit. You can replay this whole tour later from Settings.",
            all,
            { AnyView(MockupIcon(symbol: "dumbbell.fill", color: .appRed)) }))

        // ── HOME TAB ─────────────────────────────────────────────
        steps.append(step(.home,
            "Home is your dashboard",
            nil,
            "Stats, your week's schedule, today's workout, recent PRs, and recent sessions all live here.",
            all,
            { AnyView(MockupTabBar(highlighted: "Home", icon: "house.fill")) }))

        steps.append(step(.home,
            "Week strip",
            "Tap a week to jump there.",
            "The horizontal row of weeks at the top of Home lets you browse your whole program. Past weeks show completed sessions; future weeks let you preview what's coming.",
            all,
            { AnyView(MockupWeekStrip()) }))

        steps.append(step(.home,
            "Today's workout card",
            "Tap to start, or swipe past if it's a rest day.",
            "Shows your scheduled session for today with a quick muscle-group summary. If you've already logged it, a green checkmark replaces the start button.",
            all,
            { AnyView(MockupTodayCard()) }))

        steps.append(step(.home,
            "What's a mesocycle?",
            nil,
            "A mesocycle is a multi-week training block with a specific focus — usually 4–8 weeks of building volume, then a recovery week. The block info card on Home shows you where you are in that cycle. If you'd rather train without blocks at all, you can turn periodization off in Settings → Training Style — the engine will keep recommending weight without the block-phase shifts.",
            stdAdv,
            { AnyView(MockupMesocycle()) }))

        steps.append(step(.home,
            "Schedule section — DAYS or SESSIONS view",
            "Toggle between them with the chip at the top.",
            "DAYS view shows your week as Mon–Sun with the session scheduled for each. SESSIONS view shows the order your sessions rotate, regardless of calendar day. Both lead to the same edit screen on tap.",
            all,
            { AnyView(MockupDaysSessionsToggle()) }))

        steps.append(step(.home,
            "Drag to rearrange your week",
            "Long-press a day in DAYS view, then drag it to swap.",
            "Only available on the Home tab. Useful if you want to move Tuesday's session to Wednesday because of a schedule conflict — drag, drop, done. Changes apply to the displayed week only.",
            all,
            { AnyView(MockupDragDrop()) }))

        steps.append(step(.home,
            "Tap a day to edit it",
            "One tap opens the session editor.",
            "From there you can change the exercises, sets, or reps for that session. To replace it with a rest day, use Configure Week (next step).",
            all,
            { AnyView(MockupDayTap()) }))

        steps.append(step(.home,
            "Configure Week button",
            "Tap to add, swap, or remove sessions.",
            "Opens a 4-tab editor (Sessions / Schedule / Blocks / Import) where you reshape the week's plan. Use it to mark a day as rest, add a bonus session, or import a session from another program.",
            all,
            { AnyView(MockupConfigureWeekButton()) }))

        steps.append(step(.home,
            "Muscle coverage card",
            "Tap any bar to drill in.",
            "Shows sets per muscle this week with target bars. Green = on target. Orange = under target. Red bars = under-training. Tap any muscle in advanced mode to expand the head-by-head breakdown (e.g. Triceps → Long / Lateral / Medial) with a one-line interpretation telling you which heads are lagging. Then tap a head to see which exercises feed it AND get recommendations to grow it. In non-advanced modes, tapping opens the Volume Adjuster directly.",
            stdAdv,
            { AnyView(MockupMuscleBars()) }))

        steps.append(step(.home,
            "Configure Week — Sessions tab",
            "Rename, add, swap, or remove sessions in this week's rotation.",
            "First tab inside Configure Week. Rename 'Heavy Upper' to 'Bench Day' if you want — the new name shows up everywhere. Swap a session for a different type (Pull → Legs etc.). Remove sessions you're not doing this week. Add a brand-new session at the bottom.",
            all,
            { AnyView(MockupHomeSessionsRename()) }))

        steps.append(step(.home,
            "Configure Week — Schedule tab",
            "Visual 7-day calendar. Tap a day for action options.",
            "Tap any day in the calendar and you get three choices: Replace with… (pick a different session from your rotation), Mark as Rest, or Clear. This is the cleanest way to turn a specific day into rest or shuffle which session lands where. Changes apply to this week only — your base rotation is untouched.",
            all,
            { AnyView(MockupHomeScheduleTap()) }))

        steps.append(step(.home,
            "Configure Week — Import tab",
            "Pull a session or full week from any other program — or a Day Template.",
            "Two sections here. FROM PROGRAMS shows sessions from every other program you have access to (Powerbuilding, PPL, Bahri Split, your custom programs) — tap + to drop one into the selected day. DAY TEMPLATES below shows your saved templates. Same flow: pick a day, tap + on the template.",
            all,
            { AnyView(MockupHomeImportTab()) }))

        steps.append(step(.home,
            "Day Templates — build once, assign anywhere",
            "Configure Week → Import → Day Templates → + to assign.",
            "A Day Template is a reusable session structure: name, color, exercises with sets/reps/RPE/rest. Build it once from Settings → Day Templates (or Program → Templates), then assign it to any day of any week through Configure Week → Import. Edit the template and every assignment updates. Great for freestyle days you repeat.",
            all,
            { AnyView(MockupHomeDayTemplateAssign()) }))

        // ── TRAIN TAB ────────────────────────────────────────────
        steps.append(step(.train,
            "Train tab is where you log workouts",
            "Tap TODAY at the top, or any session card below.",
            "TODAY highlights the session scheduled for today. The cards below show every session in your rotation with a checkmark on the ones you've completed this week. Tap any card to preview it before starting.",
            all,
            { AnyView(MockupTabBar(highlighted: "Train", icon: "dumbbell.fill")) }))

        steps.append(step(.train,
            "Starting a workout",
            "Tap a session card → Preview → START WORKOUT.",
            "The preview shows what the algorithm has prescribed: per-set weights, rep targets, RPE, rest times — everything based on your last session of this lift. From there, hit START WORKOUT (or back out if you want to make changes first).",
            all,
            { AnyView(MockupTrainPreview()) }))

        steps.append(step(.train,
            "Edit the prescription before you start",
            "Tap any exercise card on the preview to expand it.",
            "Each exercise has fields you can tweak in place: target sets, rep range (low–high), target RPE, rest seconds, notes. Change them and they apply to THIS workout only. The base program stays untouched. If you want a permanent change, edit the program template instead.",
            stdAdv,
            { AnyView(MockupTrainPrescriptionEdit()) }))

        steps.append(step(.train,
            "Double-tap an exercise for full history + cues",
            "Quick double-tap on the exercise header.",
            "Opens that exercise's Exercise History sheet: e1RM chart, every session ever logged with weights/reps/RPE, your strength goal status, and an Exercise Cues editor. Cues are short notes you write to yourself ('drive heels through floor', 'tuck elbows') that show up on the exercise card during future workouts.",
            stdAdv,
            { AnyView(MockupTrainHistorySheet()) }))

        steps.append(step(.train,
            "Readiness check",
            "Rate yourself 1–5 before each workout.",
            "1 = beat up. 5 = feeling great. The algorithm adjusts weight and rep targets accordingly. Skip if you don't want to rate — it'll assume average (3).",
            stdAdv,
            { AnyView(MockupReadiness()) }))

        steps.append(step(.train,
            "Logging sets",
            "Tap a set row, type weight + reps, hit the green check.",
            "Weight and reps come pre-filled with the algorithm's recommendation. Tap a field to override. The set is logged the instant you tap the green check. Tap any of the role badges (TOP SET / FEEDER / BACKOFF) or the recommendation arrow above to see WHY the engine is suggesting what it is.",
            all,
            { AnyView(MockupSetRow()) }))

        steps.append(step(.train,
            "Mid-workout tools",
            "Use the action icons on each exercise.",
            "Swap (blue arrows) — replace the exercise. Move (up/down) — reorder. Trash — delete from this workout. Plus the + button anywhere to add a freestyle exercise. You can swap multiple ways too: this session only, or all future sessions.",
            all,
            { AnyView(MockupExerciseActions()) }))

        steps.append(step(.train,
            "Finish & Save",
            "When done, hit FINISH in the top right.",
            "Logs your sets, updates progression state, advances your week if you've completed enough sessions, and recalibrates your fatigue signals.",
            all,
            { AnyView(MockupFinishButton()) }))

        // ── PROGRAM TAB ──────────────────────────────────────────
        steps.append(step(.program,
            "Program tab manages your training plan",
            "Four sections: Overview / Weeks / Templates / Exercises.",
            "Overview shows your mesocycle, volume, and goals. Weeks lets you preview future sessions. Templates are reusable session structures. Exercises is the full library.",
            all,
            { AnyView(MockupTabBar(highlighted: "Program", icon: "list.bullet.clipboard.fill")) }))

        steps.append(step(.program,
            "Configure Program button",
            "Top of the Program tab. Big red CTA.",
            "Opens the same 4-tab editor as Configure Week on Home, but scoped to the whole program. This is where you reshape blocks, import sessions, and edit the schedule long-term.",
            all,
            { AnyView(MockupConfigureProgramButton()) }))

        steps.append(step(.program,
            "Sessions tab (inside Configure)",
            "Rename, add, swap, or remove sessions in your rotation.",
            "Changes here can be week-scoped (this week only) or permanent (whole program). Each session has a Swap and Remove button next to it.",
            all,
            { AnyView(MockupConfigSessions()) }))

        steps.append(step(.program,
            "Schedule tab (inside Configure)",
            "Visual 7-day calendar. Tap any day to assign a session.",
            "Pick from your rotation, replace with rest, or clear the day. Useful for one-off changes like 'I'll do legs on Sunday instead of Saturday.'",
            stdAdv,
            { AnyView(MockupConfigSchedule()) }))

        steps.append(step(.program,
            "Blocks tab (inside Configure)",
            "Set block type and length, or open the Sequence Editor for deep control.",
            "Block type affects volume multipliers (Accumulation = 100%, Intensification = 65%, Reaccumulation = 115%, Peak = 50%, Deload = recovery). The Sequence Editor lets you fully redesign the block order.",
            advOnly,
            { AnyView(MockupConfigBlocks()) }))

        steps.append(step(.program,
            "Import tab (inside Configure)",
            "Mix sessions from other programs into your week.",
            "Tap a day, then tap any session from any built-in or custom program. Useful for hybrid programs — e.g., your usual PPL plus one heavy upper from Powerbuilding.",
            advOnly,
            { AnyView(MockupConfigImport()) }))

        steps.append(step(.program,
            "Day Templates",
            "Reusable session structures you build once and reuse.",
            "Create a template (e.g., 'My Push Day'), then assign it to any day. Editing the template updates every assignment. Useful for freestyle sessions you do regularly.",
            stdAdv,
            { AnyView(MockupTemplate()) }))

        steps.append(step(.program,
            "Creating a template",
            "Settings → Day Templates → +, OR Program → Templates → +.",
            "Name it, pick a color, add exercises with sets/reps/RPE/rest. Tap Save. Now assign it from Configure Week → Import → Day Templates.",
            stdAdv,
            { AnyView(MockupTemplateCreate()) }))

        steps.append(step(.program,
            "Strength Goals",
            "Set targets like 'Bench 315 lb'.",
            "When you set a goal, the algorithm enters a 4-phase peaking protocol: Building → Intensifying → Peaking → Testing. T1 exercise prescriptions shift toward strength rep ranges automatically. Up to 2 active goals.",
            stdAdv,
            { AnyView(MockupStrengthGoal()) }))

        steps.append(step(.program,
            "Weekly volume bars",
            "Programmed (filled bar) vs Target (vertical line).",
            "Each muscle's bar shows the sets you have scheduled this week and a target marker. Below target = consider adding sets. Over target = consider holding or trimming. Tap a bar to open the Volume Adjuster.",
            stdAdv,
            { AnyView(MockupVolumeBars()) }))

        steps.append(step(.program,
            "Muscle Priorities",
            "Tap a muscle to cycle: Neutral → Priority → Maintenance.",
            "Priority muscles get 1.5× volume targets. Maintenance get 0.7×. Neutral is 1.0×. Useful if you want to emphasize a lagging muscle group without rebuilding your whole program.",
            advOnly,
            { AnyView(MockupMusclePriorities()) }))

        // ── PROGRESS TAB ─────────────────────────────────────────
        steps.append(step(.progress,
            "Progress tab is where your data lives",
            "Four sections: Overview / Strength / Volume / History.",
            "Overview = stats and recent PRs. Strength = goals, trends, balance ratios. Volume = weekly volume charts. History = every session you've logged.",
            all,
            { AnyView(MockupTabBar(highlighted: "Progress", icon: "trophy.fill")) }))

        steps.append(step(.progress,
            "Recent PRs and trends",
            "Tap any PR to see the exercise's full history.",
            "PRs are e1RM-based (estimated 1-rep max from your sets, not actual 1RM tests). The trend chart in Strength shows a line through your last 15 sessions.",
            all,
            { AnyView(MockupPRRow()) }))

        steps.append(step(.progress,
            "Weekly volume chart",
            "Filter by muscle to see trends over 12 weeks.",
            "Helps you spot whether you're truly progressing (rising volume + rising e1RM) or just accumulating fatigue (rising volume + flat or falling e1RM).",
            stdAdv,
            { AnyView(MockupVolumeChart()) }))

        steps.append(step(.progress,
            "Log a PR from outside the app",
            "Use the LOG A PR button at the top of Overview.",
            "If you did a workout outside PowerForge but hit a PR, log it manually. It enters your history with a 'manual' tag so it doesn't affect the algorithm's progression tracking.",
            all,
            { AnyView(MockupLogPR()) }))

        // ── SETTINGS ─────────────────────────────────────────────
        steps.append(step(.settings,
            "Interface density",
            "Top of Settings. Tap any level to change.",
            "Minimal hides jargon and advanced cards. Standard adds volume tracking and PRs in plain language. Advanced shows everything including IFI, PML, MRV, stall diagnoses. You can switch anytime — your data stays.",
            all,
            { AnyView(MockupDensityPicker()) }))

        steps.append(step(.settings,
            "Glossary",
            "Settings → Learn → Glossary tab.",
            "Every term the app uses, defined with examples and what-to-do guidance. Plus, in Advanced mode, you'll see small 'ⓘ' icons next to jargon — tap any one to open its glossary entry.",
            stdAdv,
            { AnyView(MockupGlossary()) }))

        steps.append(step(.settings,
            "Other settings",
            nil,
            "Units (kg/lbs), warm-up auto-generation, workout display toggles, data export, iCloud sync status, and Reset Program (clears history but keeps PRs).",
            stdAdv,
            { AnyView(MockupIcon(symbol: "gearshape.fill", color: .appOrange)) }))

        // ── OUTRO ────────────────────────────────────────────────
        steps.append(step(.outro,
            "You're ready to train",
            nil,
            "Pick today's workout from Home and hit Start. You can replay this walkthrough anytime from Settings → Replay Walkthrough. Tap ⓘ icons throughout the app for in-context explanations.",
            all,
            { AnyView(MockupIcon(symbol: "checkmark.circle.fill", color: .appGreen)) }))

        return steps
    }()
}

// ═══════════════════════════════════════════
// THE WALKTHROUGH VIEW
// ═══════════════════════════════════════════

struct AppWalkthroughView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]
    @State private var pageIndex: Int = 0

    /// When non-nil, the walkthrough only shows steps from this chapter.
    /// Used by the per-tab "?" icon to launch a focused tab tour without
    /// running the entire app walkthrough.
    let restrictToChapter: WalkthroughChapter?

    init(restrictToChapter: WalkthroughChapter? = nil) {
        self.restrictToChapter = restrictToChapter
    }

    private var density: UIDensity { profiles.first?.density ?? .standard }

    /// Steps filtered to those visible at the user's density level,
    /// optionally narrowed to a single chapter for per-tab tours.
    private var steps: [WalkthroughStep] {
        WalkthroughCatalog.all
            .filter { $0.densities.contains(density) }
            .filter { restrictToChapter == nil || $0.chapter == restrictToChapter }
    }

    private var currentStep: WalkthroughStep? {
        guard pageIndex >= 0, pageIndex < steps.count else { return nil }
        return steps[pageIndex]
    }

    private func endTour() {
        UserDefaults.standard.set(true, forKey: "hasSeenTour")
        dismiss()
    }

    var body: some View {
        ZStack {
            Color.appBG.ignoresSafeArea()

            if let step = currentStep {
                VStack(spacing: 0) {

                    // Header: chapter + step counter + skip
                    HStack {
                        Text(step.chapter.rawValue)
                            .font(.system(size: 10, weight: .black))
                            .kerning(2)
                            .foregroundColor(.white)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(step.chapter.color)
                            .cornerRadius(6)

                        Spacer()

                        Text("\(pageIndex + 1) / \(steps.count)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.appTextDim)

                        Spacer()

                        Button("Skip") {
                            endTour()
                        }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.appTextDim)
                    }
                    .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 10)

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Color.appSurface2.frame(height: 3)
                            step.chapter.color
                                .frame(width: geo.size.width * CGFloat(pageIndex + 1) / CGFloat(steps.count), height: 3)
                                .animation(.easeOut(duration: 0.2), value: pageIndex)
                        }
                    }
                    .frame(height: 3)
                    .padding(.bottom, 24)

                    // Content
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 22) {
                            // Title + action
                            VStack(spacing: 8) {
                                Text(step.title)
                                    .font(.system(size: 26, weight: .black, design: .rounded))
                                    .foregroundColor(.appTextPrimary)
                                    .multilineTextAlignment(.center)

                                if let action = step.action {
                                    Text(action)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(step.chapter.color)
                                        .multilineTextAlignment(.center)
                                }
                            }

                            // Mockup
                            step.mockup()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)

                            // Description
                            Text(step.description)
                                .font(.system(size: 15))
                                .foregroundColor(.appTextSecondary)
                                .lineSpacing(4)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 6)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)
                    }

                    Spacer(minLength: 0)

                    // Nav buttons
                    HStack(spacing: 12) {
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                pageIndex = max(0, pageIndex - 1)
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(pageIndex > 0 ? .appTextSecondary : .appTextDim.opacity(0.3))
                                .frame(width: 50, height: 50)
                                .background(Color.appSurface2)
                                .cornerRadius(12)
                        }
                        .disabled(pageIndex == 0)
                        .buttonStyle(.plain)

                        if pageIndex == steps.count - 1 {
                            Button {
                                endTour()
                            } label: {
                                HStack(spacing: 8) {
                                    Text("LET'S GO")
                                        .font(.system(size: 14, weight: .black))
                                        .kerning(1)
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 13, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.appRed)
                                .cornerRadius(12)
                                .shadow(color: Color.appRed.opacity(0.3), radius: 8, x: 0, y: 4)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    pageIndex = min(steps.count - 1, pageIndex + 1)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Text("NEXT")
                                        .font(.system(size: 14, weight: .black))
                                        .kerning(1)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(step.chapter.color)
                                .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20).padding(.bottom, 30)
                }
            }
        }
    }
}

// ═══════════════════════════════════════════
// MOCKUP COMPONENTS — small SwiftUI illustrations for each step
// Stylized representations of the actual UI, no screenshots.
// ═══════════════════════════════════════════

private struct MockupIcon: View {
    let symbol: String
    let color: Color
    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.12)).frame(width: 110, height: 110)
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .bold))
                .foregroundColor(color)
        }
    }
}

private struct MockupTabBar: View {
    let highlighted: String
    let icon: String
    var body: some View {
        let tabs: [(String, String)] = [
            ("Home", "house.fill"),
            ("Train", "dumbbell.fill"),
            ("Program", "list.bullet.clipboard.fill"),
            ("Progress", "trophy.fill"),
            ("Settings", "gearshape.fill")
        ]
        HStack(spacing: 8) {
            ForEach(tabs, id: \.0) { name, sym in
                let isOn = (name == highlighted)
                VStack(spacing: 3) {
                    Image(systemName: sym)
                        .font(.system(size: isOn ? 18 : 13, weight: isOn ? .bold : .regular))
                        .foregroundColor(isOn ? .appRed : .appTextDim.opacity(0.6))
                    Text(name)
                        .font(.system(size: isOn ? 9 : 8, weight: isOn ? .black : .regular))
                        .foregroundColor(isOn ? .appRed : .appTextDim.opacity(0.6))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(isOn ? Color.appRed.opacity(0.08) : .clear)
                .cornerRadius(8)
            }
        }
        .padding(8)
        .background(Color.appSurface)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
    }
}

private struct MockupWeekStrip: View {
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(1..<6) { i in
                    let isCurrent = i == 3
                    VStack(spacing: 2) {
                        Text("W\(i)").font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundColor(isCurrent ? .white : .appTextSecondary)
                        Text("Mar \(i*7)").font(.system(size: 8))
                            .foregroundColor(isCurrent ? .white.opacity(0.9) : .appTextDim)
                    }
                    .frame(width: 50, height: 36)
                    .background(isCurrent ? Color.appRed : Color.appSurface2)
                    .cornerRadius(8)
                }
            }
            HStack(spacing: 4) {
                Image(systemName: "arrow.up").font(.system(size: 9)).foregroundColor(.appRed)
                Text("Tap to jump").font(.system(size: 10, weight: .bold)).foregroundColor(.appRed)
            }
        }
    }
}

private struct MockupTodayCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("TODAY").font(.system(size: 9, weight: .black)).foregroundColor(.appRed).kerning(1.5)
                Spacer()
                Image(systemName: "bolt.fill").font(.system(size: 11)).foregroundColor(.appRed)
            }
            Text("Heavy Upper")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundColor(.appTextPrimary)
            Text("Chest · Back · Delts")
                .font(.system(size: 11)).foregroundColor(.appTextDim)
            HStack { Spacer()
                Text("START").font(.system(size: 11, weight: .black))
                    .foregroundColor(.white).padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Color.appRed).cornerRadius(8)
            }
        }
        .padding(14)
        .background(Color.appSurface).cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appRed.opacity(0.3), lineWidth: 1))
        .frame(maxWidth: 260)
    }
}

private struct MockupMesocycle: View {
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(0..<7) { i in
                    let isCurrent = i == 2
                    let isDeload = i == 6
                    Rectangle()
                        .fill(isDeload ? Color.appBlue : (i < 3 ? Color.appRed : Color.appRed.opacity(0.4)))
                        .frame(width: 26, height: isCurrent ? 36 : 22)
                        .cornerRadius(4)
                        .overlay(
                            Group {
                                if isCurrent {
                                    Text("NOW").font(.system(size: 7, weight: .black))
                                        .foregroundColor(.white).kerning(0.5)
                                }
                            }
                        )
                }
            }
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Rectangle().fill(Color.appRed).frame(width: 8, height: 4)
                    Text("Training").font(.system(size: 9)).foregroundColor(.appTextDim)
                }
                HStack(spacing: 4) {
                    Rectangle().fill(Color.appBlue).frame(width: 8, height: 4)
                    Text("Recovery").font(.system(size: 9)).foregroundColor(.appTextDim)
                }
            }
        }
    }
}

private struct MockupDaysSessionsToggle: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("DAYS").font(.system(size: 9, weight: .black))
                .foregroundColor(.white).kerning(0.5)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Color.appRed).cornerRadius(6)
            Text("SESSIONS").font(.system(size: 9, weight: .black))
                .foregroundColor(.appTextDim).kerning(0.5)
                .padding(.horizontal, 14).padding(.vertical, 7)
        }
        .background(Color.appSurface2).cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.appBorder, lineWidth: 1))
    }
}

private struct MockupDragDrop: View {
    var body: some View {
        VStack(spacing: 6) {
            ForEach(["Mon — Heavy Upper", "Tue — Heavy Lower", "Wed — Hypertrophy Upper"], id: \.self) { label in
                HStack(spacing: 10) {
                    VStack(spacing: 2) {
                        Circle().fill(Color.appTextDim).frame(width: 3, height: 3)
                        Circle().fill(Color.appTextDim).frame(width: 3, height: 3)
                        Circle().fill(Color.appTextDim).frame(width: 3, height: 3)
                    }
                    Text(label).font(.system(size: 12, weight: .bold)).foregroundColor(.appTextPrimary)
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Color.appSurface).cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorder, lineWidth: 1))
            }
            HStack(spacing: 4) {
                Image(systemName: "hand.draw.fill").font(.system(size: 11)).foregroundColor(.appRed)
                Text("Long-press, then drag").font(.system(size: 10, weight: .bold)).foregroundColor(.appRed)
            }
        }
        .frame(maxWidth: 280)
    }
}

private struct MockupDayTap: View {
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("WED").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(1)
                    Text("Hypertrophy Upper").font(.system(size: 13, weight: .bold)).foregroundColor(.appTextPrimary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundColor(.appTextDim)
            }
            .padding(12)
            .background(Color.appSurface).cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appRed.opacity(0.4), lineWidth: 1.5))

            HStack(spacing: 4) {
                Image(systemName: "hand.tap.fill").font(.system(size: 11)).foregroundColor(.appRed)
                Text("Tap → edit session").font(.system(size: 10, weight: .bold)).foregroundColor(.appRed)
            }
        }
        .frame(maxWidth: 280)
    }
}

private struct MockupConfigureWeekButton: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 13, weight: .bold)).foregroundColor(.appBlue)
            Text("Configure Week").font(.system(size: 13, weight: .bold)).foregroundColor(.appBlue)
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundColor(.appTextDim)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color.appBlue.opacity(0.06)).cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBlue.opacity(0.3), lineWidth: 1))
        .frame(maxWidth: 260)
    }
}

private struct MockupMuscleBars: View {
    var body: some View {
        VStack(spacing: 6) {
            ForEach([("Chest", 0.7, Color.appGreen), ("Back", 0.55, Color.appOrange), ("Quads", 0.85, Color.appGreen)], id: \.0) { label, pct, color in
                HStack(spacing: 8) {
                    Text(label).font(.system(size: 10, weight: .bold)).foregroundColor(.appTextPrimary).frame(width: 50, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(Color.appSurface2).frame(height: 8)
                            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: geo.size.width * pct, height: 8)
                            Rectangle().fill(Color.appTextPrimary).frame(width: 1.5, height: 12)
                                .offset(x: geo.size.width * 0.7, y: -2)
                        }
                    }.frame(height: 12)
                }
            }
        }
        .frame(maxWidth: 280)
    }
}

private struct MockupReadiness: View {
    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { i in
                Text("\(i)").font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(i == 3 ? .white : .appTextDim)
                    .frame(width: 40, height: 40)
                    .background(i == 3 ? Color.appRed : Color.appSurface2)
                    .cornerRadius(10)
            }
        }
    }
}

private struct MockupSetRow: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("1").font(.system(size: 12, weight: .black, design: .monospaced))
                .foregroundColor(.appTextDim).frame(width: 24)
            VStack(spacing: 2) {
                Text("WEIGHT").font(.system(size: 7, weight: .bold)).foregroundColor(.appTextDim).kerning(1)
                Text("185").font(.system(size: 18, weight: .black, design: .rounded)).foregroundColor(.appTextPrimary)
            }
            .frame(width: 60, height: 44).background(Color.appSurface2).cornerRadius(8)
            Text("×").font(.system(size: 14, weight: .bold)).foregroundColor(.appTextDim)
            VStack(spacing: 2) {
                Text("REPS").font(.system(size: 7, weight: .bold)).foregroundColor(.appTextDim).kerning(1)
                Text("8").font(.system(size: 18, weight: .black, design: .rounded)).foregroundColor(.appTextPrimary)
            }
            .frame(width: 50, height: 44).background(Color.appSurface2).cornerRadius(8)
            Image(systemName: "checkmark").font(.system(size: 16, weight: .black))
                .foregroundColor(.white).frame(width: 44, height: 44)
                .background(Color.appGreen).cornerRadius(10)
        }
    }
}

private struct MockupExerciseActions: View {
    var body: some View {
        HStack(spacing: 6) {
            ForEach([("chevron.up", Color.appTextDim), ("chevron.down", Color.appTextDim),
                     ("arrow.triangle.2.circlepath", Color.appBlue), ("plus", Color.appGreen),
                     ("trash", Color.appRed.opacity(0.7))], id: \.0) { sym, c in
                Image(systemName: sym).font(.system(size: 11, weight: .bold)).foregroundColor(c)
                    .frame(width: 32, height: 32)
                    .background(c.opacity(0.1)).cornerRadius(6)
            }
        }
    }
}

private struct MockupFinishButton: View {
    var body: some View {
        Text("FINISH").font(.system(size: 13, weight: .black)).foregroundColor(.appRed)
            .padding(.horizontal, 18).padding(.vertical, 10)
            .background(Color.appRed.opacity(0.12)).cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appRed.opacity(0.3), lineWidth: 1))
    }
}

private struct MockupConfigureProgramButton: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "slider.horizontal.3").font(.system(size: 13, weight: .bold))
            Text("Configure Program").font(.system(size: 13, weight: .black))
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(Color.appRed).cornerRadius(10)
        .shadow(color: Color.appRed.opacity(0.3), radius: 6, x: 0, y: 3)
    }
}

private struct MockupConfigTabs: View {
    let tabs: [String]
    let highlighted: String
    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs, id: \.self) { t in
                let isOn = t == highlighted
                Text(t).font(.system(size: 10, weight: isOn ? .black : .medium))
                    .foregroundColor(isOn ? .white : .appTextSecondary)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(isOn ? Color.appRed : Color.appSurface2)
                    .cornerRadius(6)
            }
        }
    }
}

// Renamable session list — emphasizes the inline rename + swap actions
// from inside Configure Week → Sessions tab. Distinct from
// MockupConfigSessions so the Home walkthrough shows the renamed state.
private struct MockupHomeSessionsRename: View {
    var body: some View {
        VStack(spacing: 6) {
            MockupConfigTabs(tabs: ["Sessions", "Schedule", "Blocks", "Import"], highlighted: "Sessions")
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Text("D1").font(.system(size: 9, weight: .black, design: .monospaced)).foregroundColor(.appRed)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text("Bench Day").font(.system(size: 11, weight: .black)).foregroundColor(.appTextPrimary)
                            Image(systemName: "pencil").font(.system(size: 7)).foregroundColor(.appBlue)
                        }
                        Text("was Heavy Upper").font(.system(size: 7)).foregroundColor(.appTextDim).italic()
                    }
                    Spacer()
                    Text("SWAP").font(.system(size: 7, weight: .black)).foregroundColor(.appBlue)
                        .padding(.horizontal, 4).padding(.vertical, 1).background(Color.appBlue.opacity(0.12)).cornerRadius(3)
                    Text("REMOVE").font(.system(size: 7, weight: .black)).foregroundColor(.appRed)
                        .padding(.horizontal, 4).padding(.vertical, 1).background(Color.appRed.opacity(0.10)).cornerRadius(3)
                }
                .padding(7).background(Color.appSurface).cornerRadius(5)
                HStack(spacing: 6) {
                    Text("D2").font(.system(size: 9, weight: .black, design: .monospaced)).foregroundColor(.appRed)
                    Text("Heavy Lower").font(.system(size: 11, weight: .bold)).foregroundColor(.appTextPrimary)
                    Spacer()
                    Image(systemName: "plus.circle").font(.system(size: 10)).foregroundColor(.appGreen)
                    Text("ADD").font(.system(size: 7, weight: .black)).foregroundColor(.appGreen)
                }
                .padding(7).background(Color.appSurface).cornerRadius(5)
            }
        }
        .frame(maxWidth: 280)
    }
}

// 7-day calendar with one day tapped showing the action buttons
// (Replace with… / Clear). Distinct from MockupConfigSchedule so the
// Home walkthrough teaches the "tap a day to mark it rest" flow.
private struct MockupHomeScheduleTap: View {
    var body: some View {
        VStack(spacing: 8) {
            MockupConfigTabs(tabs: ["Sessions", "Schedule", "Blocks", "Import"], highlighted: "Schedule")
            HStack(spacing: 3) {
                ForEach(Array(zip(["M","T","W","T","F","S","S"], [true,false,true,false,true,true,false])), id: \.0) { _, has in
                    Rectangle().fill(has ? Color.appRed.opacity(0.30) : Color.appSurface2)
                        .frame(width: 30, height: 24).cornerRadius(3)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.appBorder, lineWidth: 1))
                }
            }
            // Wednesday tapped → action chips
            HStack(spacing: 6) {
                Image(systemName: "hand.tap.fill").font(.system(size: 9)).foregroundColor(.appRed)
                Text("WED tapped").font(.system(size: 8, weight: .black)).foregroundColor(.appRed)
                Spacer()
            }
            HStack(spacing: 4) {
                Text("Replace with…").font(.system(size: 8, weight: .bold)).foregroundColor(.appBlue)
                    .padding(.horizontal, 5).padding(.vertical, 3).background(Color.appBlue.opacity(0.12)).cornerRadius(3)
                Text("Mark as Rest").font(.system(size: 8, weight: .bold)).foregroundColor(.appOrange)
                    .padding(.horizontal, 5).padding(.vertical, 3).background(Color.appOrange.opacity(0.12)).cornerRadius(3)
                Text("Clear").font(.system(size: 8, weight: .bold)).foregroundColor(.appTextDim)
                    .padding(.horizontal, 5).padding(.vertical, 3).background(Color.appSurface2).cornerRadius(3)
            }
        }
        .frame(maxWidth: 280)
    }
}

// Import tab — shows BOTH "sessions from other programs" AND
// "Day Templates" sections, so the walkthrough teaches that Day Templates
// flow through this same tab. Different from the bare MockupConfigImport
// which only shows the program list.
private struct MockupHomeImportTab: View {
    var body: some View {
        VStack(spacing: 8) {
            MockupConfigTabs(tabs: ["Sessions", "Schedule", "Blocks", "Import"], highlighted: "Import")
            VStack(alignment: .leading, spacing: 3) {
                Text("FROM PROGRAMS").font(.system(size: 8, weight: .black)).foregroundColor(.appTextDim).kerning(0.5)
                HStack {
                    Text("PPL · Push A").font(.system(size: 10, weight: .bold)).foregroundColor(.appTextPrimary)
                    Spacer()
                    Image(systemName: "plus.circle.fill").font(.system(size: 11)).foregroundColor(.appGreen)
                }.padding(6).background(Color.appSurface).cornerRadius(4)
                HStack {
                    Text("Bahri · Chest & Back").font(.system(size: 10, weight: .bold)).foregroundColor(.appTextPrimary)
                    Spacer()
                    Image(systemName: "plus.circle.fill").font(.system(size: 11)).foregroundColor(.appGreen)
                }.padding(6).background(Color.appSurface).cornerRadius(4)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("DAY TEMPLATES").font(.system(size: 8, weight: .black)).foregroundColor(.appBlue).kerning(0.5)
                HStack(spacing: 5) {
                    Circle().fill(Color.appBlue).frame(width: 6, height: 6)
                    Text("Saturday Arms").font(.system(size: 10, weight: .bold)).foregroundColor(.appTextPrimary)
                    Spacer()
                    Image(systemName: "plus.circle.fill").font(.system(size: 11)).foregroundColor(.appGreen)
                }.padding(6).background(Color.appBlue.opacity(0.06)).cornerRadius(4)
            }
        }
        .frame(maxWidth: 280)
    }
}

// Build-and-assign flow: template card → arrow → day on calendar.
// Distinct from MockupTemplateCreate which shows the Settings menu path.
private struct MockupHomeDayTemplateAssign: View {
    var body: some View {
        HStack(spacing: 10) {
            // Template card
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Circle().fill(Color.appBlue).frame(width: 6, height: 6)
                    Text("Saturday Arms").font(.system(size: 9, weight: .black)).foregroundColor(.appTextPrimary)
                }
                Text("5 exercises").font(.system(size: 7)).foregroundColor(.appTextDim)
            }
            .padding(7).background(Color.appBlue.opacity(0.08)).cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.appBlue.opacity(0.30), lineWidth: 1))
            Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold)).foregroundColor(.appTextDim)
            // Mini calendar with SAT highlighted in blue
            HStack(spacing: 2) {
                ForEach(Array(zip(["M","T","W","T","F","S","S"], [false,false,false,false,false,true,false])), id: \.0) { d, sel in
                    VStack(spacing: 1) {
                        Text(d).font(.system(size: 7, weight: .bold)).foregroundColor(sel ? .white : .appTextDim)
                        Rectangle().fill(sel ? Color.appBlue : Color.appSurface2)
                            .frame(width: 14, height: 14).cornerRadius(2)
                    }
                }
            }
        }
        .frame(maxWidth: 280)
    }
}

// Workout preview screen — shows what the user sees BEFORE pressing
// START WORKOUT. Pre-filled weight/reps, target RPE, and the start CTA.
// Distinct from MockupSetRow which is a per-set logging row.
private struct MockupTrainPreview: View {
    var body: some View {
        VStack(spacing: 8) {
            // Exercise header
            HStack(spacing: 6) {
                Text("A").font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4).padding(.vertical, 2).background(Color.appRed).cornerRadius(3)
                Text("Bench Press").font(.system(size: 12, weight: .black)).foregroundColor(.appTextPrimary)
                Spacer()
                Text("3 SETS").font(.system(size: 8, weight: .bold)).foregroundColor(.appTextDim)
            }
            // Pre-filled set rows
            VStack(spacing: 3) {
                ForEach([("225","8"),("245","6"),("245","6")], id: \.0) { (w, r) in
                    HStack(spacing: 6) {
                        Text("•").font(.system(size: 9)).foregroundColor(.appTextDim)
                        Text(w).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(.appTextPrimary)
                        Text("lb ×").font(.system(size: 8)).foregroundColor(.appTextDim)
                        Text(r).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(.appTextPrimary)
                        Text("RPE 8").font(.system(size: 8, weight: .bold)).foregroundColor(.appBlue)
                        Spacer()
                    }
                    .padding(.horizontal, 6).padding(.vertical, 4).background(Color.appSurface2).cornerRadius(4)
                }
            }
            HStack {
                Spacer()
                Text("START WORKOUT").font(.system(size: 10, weight: .black)).foregroundColor(.white).kerning(1)
                    .padding(.horizontal, 12).padding(.vertical, 6).background(Color.appRed).cornerRadius(6)
                Spacer()
            }.padding(.top, 2)
        }
        .padding(8).background(Color.appSurface).cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorder, lineWidth: 1))
        .frame(maxWidth: 260)
    }
}

// Editable prescription fields — what shows up when you tap an exercise
// card on the preview to expand it. Sets/Reps/RPE/Rest as numeric fields.
private struct MockupTrainPrescriptionEdit: View {
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Text("Bench Press").font(.system(size: 11, weight: .black)).foregroundColor(.appTextPrimary)
                Image(systemName: "chevron.up").font(.system(size: 8)).foregroundColor(.appTextDim)
                Spacer()
            }
            HStack(spacing: 6) {
                fieldChip(label: "SETS", value: "3")
                fieldChip(label: "REPS", value: "6–8")
                fieldChip(label: "RPE", value: "8.0")
                fieldChip(label: "REST", value: "180s")
            }
            HStack(spacing: 4) {
                Text("Notes:").font(.system(size: 8, weight: .bold)).foregroundColor(.appTextDim)
                Text("focus on bar path").font(.system(size: 8)).foregroundColor(.appTextSecondary)
                Spacer()
            }
            Text("Changes apply to THIS workout only").font(.system(size: 7)).italic().foregroundColor(.appTextDim)
        }
        .padding(8).background(Color.appSurface).cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBlue.opacity(0.30), lineWidth: 1))
        .frame(maxWidth: 280)
    }
    private func fieldChip(label: String, value: String) -> some View {
        VStack(spacing: 1) {
            Text(label).font(.system(size: 7, weight: .black)).foregroundColor(.appTextDim).kerning(0.5)
            Text(value).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(.appBlue)
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(Color.appBlue.opacity(0.10)).cornerRadius(4)
    }
}

// Exercise History sheet — what double-tap opens. Mini chart + cues editor.
private struct MockupTrainHistorySheet: View {
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Text("Bench Press · HISTORY").font(.system(size: 9, weight: .black)).foregroundColor(.appTextDim).kerning(0.5)
                Spacer()
                Image(systemName: "xmark.circle").font(.system(size: 10)).foregroundColor(.appTextDim)
            }
            // Sparkline-ish e1RM chart
            ZStack {
                Rectangle().fill(Color.appSurface2).frame(height: 28).cornerRadius(4)
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach([10,14,12,18,22,20,24], id: \.self) { h in
                        Rectangle().fill(Color.appGreen).frame(width: 5, height: CGFloat(h))
                    }
                }
            }
            Text("e1RM trend (last 7 sessions)").font(.system(size: 7)).foregroundColor(.appTextDim)
            // Cue editor
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "lightbulb.fill").font(.system(size: 8)).foregroundColor(.appGold)
                    Text("EXERCISE CUES").font(.system(size: 7, weight: .black)).foregroundColor(.appGold).kerning(0.5)
                }
                Text("• drive heels through floor").font(.system(size: 8)).foregroundColor(.appTextPrimary)
                Text("• tuck elbows ~70°").font(.system(size: 8)).foregroundColor(.appTextPrimary)
            }
            .padding(6).background(Color.appGold.opacity(0.08)).cornerRadius(4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8).background(Color.appSurface).cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorder, lineWidth: 1))
        .frame(maxWidth: 260)
    }
}

private struct MockupConfigSessions: View {
    var body: some View {
        VStack(spacing: 8) {
            MockupConfigTabs(tabs: ["Sessions", "Schedule", "Blocks", "Import"], highlighted: "Sessions")
            VStack(spacing: 4) {
                ForEach(["D1 · Heavy Upper", "D2 · Heavy Lower"], id: \.self) { label in
                    HStack {
                        Text(label).font(.system(size: 11, weight: .bold)).foregroundColor(.appTextPrimary)
                        Spacer()
                        Text("SWAP").font(.system(size: 8, weight: .black)).foregroundColor(.appBlue)
                            .padding(.horizontal, 5).padding(.vertical, 2).background(Color.appBlue.opacity(0.1)).cornerRadius(3)
                    }
                    .padding(8).background(Color.appSurface).cornerRadius(6)
                }
            }
        }
        .frame(maxWidth: 280)
    }
}

private struct MockupConfigSchedule: View {
    var body: some View {
        VStack(spacing: 8) {
            MockupConfigTabs(tabs: ["Sessions", "Schedule", "Blocks", "Import"], highlighted: "Schedule")
            HStack(spacing: 4) {
                ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { d in
                    VStack(spacing: 2) {
                        Text(d).font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim)
                        Rectangle().fill(Color.appRed.opacity(0.3)).frame(height: 26).cornerRadius(3)
                    }
                    .frame(width: 30)
                }
            }
        }
        .frame(maxWidth: 280)
    }
}

private struct MockupConfigBlocks: View {
    var body: some View {
        VStack(spacing: 8) {
            MockupConfigTabs(tabs: ["Sessions", "Schedule", "Blocks", "Import"], highlighted: "Blocks")
            VStack(alignment: .leading, spacing: 4) {
                Text("CURRENT BLOCK").font(.system(size: 8, weight: .black)).foregroundColor(.appTextDim).kerning(1)
                Text("Accumulation").font(.system(size: 14, weight: .black)).foregroundColor(.appTextPrimary)
                Text("Volume: 100%").font(.system(size: 10)).foregroundColor(.appTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10).background(Color.appSurface).cornerRadius(8)
        }
        .frame(maxWidth: 280)
    }
}

private struct MockupConfigImport: View {
    var body: some View {
        VStack(spacing: 8) {
            MockupConfigTabs(tabs: ["Sessions", "Schedule", "Blocks", "Import"], highlighted: "Import")
            VStack(spacing: 4) {
                ForEach(["PPL · Push A", "Bahri · Chest Back"], id: \.self) { name in
                    HStack {
                        Text(name).font(.system(size: 11, weight: .bold)).foregroundColor(.appTextPrimary)
                        Spacer()
                        Text("+").font(.system(size: 12, weight: .black)).foregroundColor(.appGreen)
                    }
                    .padding(8).background(Color.appSurface).cornerRadius(6)
                }
            }
        }
        .frame(maxWidth: 280)
    }
}

private struct MockupTemplate: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up.fill").font(.system(size: 13)).foregroundColor(.appBlue)
                Text("My Push Day").font(.system(size: 13, weight: .black)).foregroundColor(.appTextPrimary)
            }
            Text("5 exercises · ~60 min").font(.system(size: 10)).foregroundColor(.appTextDim)
        }
        .padding(12).background(Color.appBlue.opacity(0.06)).cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBlue.opacity(0.3), lineWidth: 1))
        .frame(maxWidth: 260)
    }
}

private struct MockupTemplateCreate: View {
    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 4) {
                Image(systemName: "gearshape.fill").font(.system(size: 18)).foregroundColor(.appOrange)
                Text("Settings").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim)
            }
            Image(systemName: "arrow.right").font(.system(size: 10)).foregroundColor(.appTextDim)
            VStack(spacing: 4) {
                Image(systemName: "square.stack.3d.up.fill").font(.system(size: 18)).foregroundColor(.appBlue)
                Text("Templates").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim)
            }
            Image(systemName: "arrow.right").font(.system(size: 10)).foregroundColor(.appTextDim)
            VStack(spacing: 4) {
                Image(systemName: "plus.circle.fill").font(.system(size: 18)).foregroundColor(.appGreen)
                Text("Create").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim)
            }
        }
    }
}

private struct MockupStrengthGoal: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "target").font(.system(size: 12)).foregroundColor(.appRed)
                Text("Bench Press").font(.system(size: 12, weight: .black)).foregroundColor(.appTextPrimary)
                Spacer()
                Text("315 lb").font(.system(size: 14, weight: .black)).foregroundColor(.appGold)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.appSurface2).frame(height: 6)
                    RoundedRectangle(cornerRadius: 3).fill(Color.appRed).frame(width: geo.size.width * 0.6, height: 6)
                }
            }.frame(height: 6)
            HStack {
                Text("e1RM 280 → 315 (60%)").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextSecondary)
                Spacer()
                Text("Building Wk 2/4").font(.system(size: 8, weight: .bold)).foregroundColor(.appTextDim)
            }
        }
        .padding(12).background(Color.appSurface).cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))
        .frame(maxWidth: 280)
    }
}

private struct MockupVolumeBars: View {
    var body: some View {
        MockupMuscleBars()  // same illustration
    }
}

private struct MockupMusclePriorities: View {
    var body: some View {
        HStack(spacing: 6) {
            ForEach([("Chest", "★", Color.appGold), ("Back", "•", Color.appTextSecondary), ("Calves", "—", Color.appTextDim)], id: \.0) { name, mark, color in
                VStack(spacing: 3) {
                    Text(mark).font(.system(size: 12, weight: .black)).foregroundColor(color)
                    Text(name).font(.system(size: 9, weight: .bold)).foregroundColor(.appTextPrimary)
                }
                .frame(width: 56, height: 50).background(Color.appSurface).cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.4), lineWidth: 1))
            }
        }
    }
}

private struct MockupPRRow: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "trophy.fill").font(.system(size: 13)).foregroundColor(.appGold)
            VStack(alignment: .leading, spacing: 2) {
                Text("Bench Press").font(.system(size: 12, weight: .black)).foregroundColor(.appTextPrimary)
                Text("225 × 8 · e1RM 285").font(.system(size: 10)).foregroundColor(.appTextDim)
            }
            Spacer()
            Text("NEW").font(.system(size: 8, weight: .black)).foregroundColor(.appGold)
                .padding(.horizontal, 5).padding(.vertical, 2).background(Color.appGold.opacity(0.12)).cornerRadius(3)
        }
        .padding(10).background(Color.appSurface).cornerRadius(8)
        .frame(maxWidth: 280)
    }
}

private struct MockupVolumeChart: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CHEST · 12 WEEKS").font(.system(size: 9, weight: .black)).foregroundColor(.appTextDim).kerning(1)
            ZStack {
                // grid
                Path { p in
                    for x in stride(from: 0, through: 240, by: 30) {
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: 70))
                    }
                }.stroke(Color.appBorder.opacity(0.3), lineWidth: 0.5)
                // line
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 50))
                    p.addLine(to: CGPoint(x: 40, y: 45))
                    p.addLine(to: CGPoint(x: 80, y: 30))
                    p.addLine(to: CGPoint(x: 120, y: 35))
                    p.addLine(to: CGPoint(x: 160, y: 20))
                    p.addLine(to: CGPoint(x: 200, y: 15))
                    p.addLine(to: CGPoint(x: 240, y: 10))
                }.stroke(Color.appBlue, lineWidth: 2)
            }
            .frame(width: 240, height: 70)
        }
        .padding(10).background(Color.appSurface).cornerRadius(8)
        .frame(maxWidth: 280)
    }
}

private struct MockupLogPR: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "trophy.fill").font(.system(size: 14)).foregroundColor(.appGold)
            Text("LOG A PR").font(.system(size: 12, weight: .black)).foregroundColor(.appTextPrimary)
            Spacer()
            Image(systemName: "plus.circle.fill").font(.system(size: 16)).foregroundColor(.appGold)
        }
        .padding(12).background(Color.appGold.opacity(0.08)).cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appGold.opacity(0.3), lineWidth: 1))
        .frame(maxWidth: 240)
    }
}

private struct MockupDensityPicker: View {
    var body: some View {
        VStack(spacing: 6) {
            ForEach([("Minimal", false), ("Standard", true), ("Advanced", false)], id: \.0) { name, selected in
                HStack(spacing: 10) {
                    ZStack {
                        Circle().stroke(selected ? Color.appRed : Color.appBorder, lineWidth: 1.5).frame(width: 16, height: 16)
                        if selected { Circle().fill(Color.appRed).frame(width: 8, height: 8) }
                    }
                    Text(name).font(.system(size: 12, weight: .bold)).foregroundColor(.appTextPrimary)
                    Spacer()
                }
                .padding(10).background(Color.appSurface).cornerRadius(8)
            }
        }
        .frame(maxWidth: 240)
    }
}

private struct MockupGlossary: View {
    var body: some View {
        VStack(spacing: 4) {
            ForEach([("IFI", "Intra-set Fatigue"), ("MRV", "Max Recoverable Vol"), ("PML", "Prior Muscle Load")], id: \.0) { abbr, name in
                HStack(spacing: 6) {
                    Text(abbr).font(.system(size: 9, weight: .black, design: .monospaced)).foregroundColor(.appRed)
                        .padding(.horizontal, 5).padding(.vertical, 2).background(Color.appRed.opacity(0.1)).cornerRadius(3)
                    Text(name).font(.system(size: 11, weight: .bold)).foregroundColor(.appTextPrimary)
                    Spacer()
                }
                .padding(8).background(Color.appSurface).cornerRadius(6)
            }
        }
        .frame(maxWidth: 260)
    }
}

// ═══════════════════════════════════════════
// PER-TAB HELP BUTTON
// Small `?` icon that opens a chapter-restricted walkthrough. Drop one
// into any tab's view to give the user a focused tour of just that tab's
// features. The walkthrough auto-filters to the user's density level.
// ═══════════════════════════════════════════

struct TabHelpButton: View {
    let chapter: WalkthroughChapter
    @State private var showWalkthrough = false

    var body: some View {
        Button {
            showWalkthrough = true
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(chapter.color)
                .frame(width: 32, height: 32)
                .background(chapter.color.opacity(0.10))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show \(chapter.rawValue) walkthrough")
        .sheet(isPresented: $showWalkthrough) {
            AppWalkthroughView(restrictToChapter: chapter)
        }
    }
}
