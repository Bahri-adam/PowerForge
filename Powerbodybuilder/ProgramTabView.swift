import SwiftUI
import SwiftData

// ═══════════════════════════════════════════
// PROGRAM TAB
// Central hub for viewing, editing, and
// configuring your training program.
// ═══════════════════════════════════════════

struct ProgramTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @Query(filter: #Predicate<UserProgramInstance> { $0.isActive == true })
    private var activeInstances: [UserProgramInstance]
    @Query private var allExercises: [Exercise]
    @Query private var programTemplates: [ProgramTemplate]
    @Query private var allSessionTemplates: [ProgramSessionTemplate]

    var profile: UserProfile? { profiles.first }
    var instance: UserProgramInstance? { activeInstances.first }

    /// User's UI density — gates advanced cards (BlockConfigCard,
    /// Muscle Priorities cycler, etc.). Engine code untouched.
    private var density: UIDensity { profile?.density ?? .advanced }

    /// Whether the user uses block periodization. When false, hide all
    /// block/mesocycle/phase UI (mesocycle summary, BlockConfigCard,
    /// Configure → Blocks tab). The user is on continuous training.
    private var usesPeriodization: Bool { profile?.usesPeriodization ?? true }

    @State private var selectedSection: ProgramSection = .overview
    @State private var showSwitchProgram = false
    @State private var showGenerateProgram = false
    @State private var showBuildProgram = false
    @State private var showBlockInfo = false
    @State private var showBlockSequenceEditor = false
    @State private var blockEditorFocusIndex: Int = 0
    @State private var showProgramConfigurator = false
    @State private var editingWeek: Int = 1
    @State private var showStrengthGoalSheet = false
    @State private var editingGoal: StrengthGoal? = nil
    @State private var editSessionItem: SessionEditorItem? = nil
    @State private var volumeAdjustMuscle: String? = nil
    /// Advanced-density head-breakdown expansion. When set, a sub-panel
    /// renders beneath the Weekly Volume bars showing per-head programmed
    /// sets for the named muscle.
    @State private var expandedHeadMuscle: String? = nil
    @State private var expandedHeadRow: MuscleHead? = nil

    enum ProgramSection: String, CaseIterable {
        case overview = "Overview"
        case weeks = "Weeks"
        case templates = "Templates"
        case exercises = "Exercises"
    }

    var body: some View {
        ZStack {
            Color.appBG.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // ── HEADER ──
                    programHeader
                    // ── SECTION PICKER ──
                    sectionPicker
                    // ── CONTENT ──
                    switch selectedSection {
                    case .overview:  overviewSection
                    case .weeks:     weeksSection
                    case .templates: templatesSection
                    case .exercises: exercisesSection
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $showSwitchProgram) {
            if let p = profile {
                ProgramSelectionView(recommendedId: recommendProgram(
                    goal: p.goal.rawValue, experience: p.experience.rawValue, daysPerWeek: p.daysPerWeek))
            }
        }
        .fullScreenCover(isPresented: $showGenerateProgram) {
            NavigationStack {
                GeneratedProgramPreviewView(
                    programId: 200 + (instance?.programId ?? 100),
                    programName: "Auto-Generated Program")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { showGenerateProgram = false }
                            .foregroundColor(.appTextSecondary)
                    }
                }
            }
        }
        .sheet(isPresented: $showBlockInfo) {
            BlockInfoSheet(instance: instance, profile: profile)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showBlockSequenceEditor) {
            if let inst = instance, let p = profile {
                BlockSequenceEditor(instance: inst, profile: p, focusBlockIndex: blockEditorFocusIndex)
                    .presentationDetents([.large])
            }
        }
        .sheet(isPresented: $showProgramConfigurator) {
            if let inst = instance {
                ProgramConfiguratorSheet(
                    instance: inst,
                    profile: profile,
                    onRequestSequenceEditor: {
                        // Configurator already dismissed itself; present the
                        // editor at the parent level so we avoid sheet-within-sheet.
                        blockEditorFocusIndex = 0
                        showBlockSequenceEditor = true
                    }
                )
                .presentationDetents([.large])
            }
        }
        .sheet(isPresented: $showStrengthGoalSheet) {
            StrengthGoalCreatorSheet(instance: instance, exercises: allExercises,
                                     allLogs: instance?.logs ?? [])
                .presentationDetents([.large])
        }
        .sheet(item: $volumeAdjustMuscle) { muscle in
            if let inst = instance {
                VolumeAdjusterSheet(muscle: muscle, instance: inst, profile: profile, week: inst.currentWeek)
            }
        }
        .sheet(item: $editingGoal) { goal in
            StrengthGoalEditorSheet(goal: goal)
                .presentationDetents([.medium])
        }
        .fullScreenCover(isPresented: $showBuildProgram) {
            ProgramBuilderV2View()
        }
        .sheet(item: $editSessionItem) { item in
            if let inst = instance {
                SessionDetailEditor(sessionType: item.sessionType, templates: item.templates,
                                    exercises: allExercises, overrides: inst.overrides,
                                    instance: inst, week: editingWeek,
                                    onDismiss: { editSessionItem = nil })
            }
        }
        .onAppear { editingWeek = instance?.currentWeek ?? 1 }
    }

    // ═══════════════════════════════════════
    // HEADER
    // ═══════════════════════════════════════

    private var programHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Program icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Color.appRed.opacity(0.1))
                        .frame(width: 48, height: 48)
                    Image(systemName: instance?.isGenerated == true ? "wand.and.stars" : "dumbbell.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(instance?.isGenerated == true ? .appGreen : .appRed)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(instance?.name.uppercased() ?? "NO PROGRAM")
                        .font(.system(size: 16, weight: .black)).foregroundColor(.appTextPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    if let p = profile {
                        HStack(spacing: 8) {
                            Text(p.goal.displayName).font(.system(size: 11, weight: .bold)).foregroundColor(.appTextSecondary)
                            Text("·").foregroundColor(.appTextDim)
                            Text("\(p.daysPerWeek) days").font(.system(size: 11)).foregroundColor(.appTextDim)
                            Text("·").foregroundColor(.appTextDim)
                            Text(p.experience.rawValue).font(.system(size: 11)).foregroundColor(.appTextDim)
                        }
                    }
                }
                Spacer()

                // Week badge
                if let inst = instance, inst.programId != 0 {
                    VStack(spacing: 1) {
                        Text("WK").font(.system(size: 8, weight: .bold)).foregroundColor(.appTextDim)
                        Text("\(inst.currentWeek)").font(.system(size: 20, weight: .black, design: .rounded)).foregroundColor(.appRed)
                    }
                }
                TabHelpButton(chapter: .program)
            }

            // Action buttons
            HStack(spacing: 8) {
                programActionButton(title: "Switch", icon: "arrow.triangle.2.circlepath", color: .appTextSecondary) {
                    showSwitchProgram = true
                }
                programActionButton(title: "Generate", icon: "wand.and.stars", color: .appGreen) {
                    showGenerateProgram = true
                }
                programActionButton(title: "Build", icon: "hammer.fill", color: .appRed) {
                    showBuildProgram = true
                }
            }
            // Configure button (full width)
            if instance != nil && instance?.programId != 0 {
                Button { showProgramConfigurator = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape.2.fill").font(.system(size: 12, weight: .bold))
                        Text("Configure Program").font(.system(size: 12, weight: .bold))
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 10))
                    }
                    .foregroundColor(.appGold)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color.appGold.opacity(0.06)).cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appGold.opacity(0.2), lineWidth: 1))
                }.buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color.appSurface).cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.appBorder, lineWidth: 1))
        .padding(.top, 8)
    }

    /// Programmed sets for a given muscle in the current week (matches VolumeAdjusterSheet).
    /// Filters out templates whose session has been removed via Configure Program,
    /// and falls back to cross-program lookup for imported session types so they
    /// contribute their real exercise counts to the volume metrics.
    private func programmedSetsForMuscle(_ muscle: String) -> Int {
        guard let inst = instance else { return 0 }
        let week = inst.currentWeek
        var total = 0
        let activeSessions = activeSessionsForWeek(
            programId: inst.programId, instance: inst, profile: profile, week: week,
            templates: programTemplates)
        // Block-aware lookup so volume metrics match what the user will train
        // under their current block layout. Also covers the imported-session
        // cross-program fallback.
        let goal = profile?.goal ?? .hypertrophy
        var templates: [ProgramSessionTemplate] = []
        for st in activeSessions {
            templates.append(contentsOf: lookupAdaptedTemplates(
                programId: inst.programId, week: week, sessionType: st,
                allTemplates: allSessionTemplates,
                instance: inst, totalWeeks: totalWeeks,
                blockLength: inst.blockLength, goal: goal))
        }
        for t in templates {
            let key = resolveExerciseKey(slotId: t.slotId, originalKey: t.exerciseKey,
                                         overrides: inst.overrides, week: week)
            let targets: Bool = {
                if let def = ExerciseDictionary.all[key] {
                    return def.primaryMuscles.contains { ExerciseDictionary.normalizeMuscle($0) == muscle }
                }
                if let ex = allExercises.first(where: { $0.exerciseKey == key }) {
                    return ex.musclesPrimary.contains { ExerciseDictionary.normalizeMuscle($0) == muscle }
                }
                return false
            }()
            guard targets else { continue }
            let delta = inst.overrides
                .filter { ov in
                    ov.targetSlotId == t.slotId && ov.sessionType == t.sessionType &&
                    ov.setCountDelta != 0 && !ov.isAddition && ov.appliesTo(week: week)
                }
                .reduce(0) { $0 + $1.setCountDelta }
            total += max(0, t.targetSets + delta)
        }
        for ov in inst.overrides where ov.isAddition && ov.appliesTo(week: week) {
            let key = ov.replacementExerciseKey
            if let def = ExerciseDictionary.all[key] {
                if def.primaryMuscles.contains(where: { ExerciseDictionary.normalizeMuscle($0) == muscle }) {
                    total += ov.addedSets
                }
            } else if let ex = allExercises.first(where: { $0.exerciseKey == key }) {
                if ex.musclesPrimary.contains(where: { ExerciseDictionary.normalizeMuscle($0) == muscle }) {
                    total += ov.addedSets
                }
            }
        }
        return total
    }

    // ═══════════════════════════════════════
    // HEAD-LEVEL VOLUME (Advanced)
    // Mirrors HomeView's headBreakdownPanel but the data source is
    // PROGRAMMED templates (not logged sets). Computes per-head set
    // credits by multiplying each template's head contributions by
    // its effective targetSets, then aggregating per head.
    // ═══════════════════════════════════════

    /// Returns programmed per-head set credits for a parent muscle this
    /// week. Includes block-aware template lookup + setCountDelta + addition
    /// overrides — same data path as `programmedSetsForMuscle`.
    private func programmedHeadCredits(for muscle: String) -> [(head: MuscleHead, sets: Double)] {
        guard let inst = instance else { return MuscleHead.heads(of: muscle).map { ($0, 0) } }
        let week = inst.currentWeek
        let goal = profile?.goal ?? .hypertrophy
        let activeSessions = activeSessionsForWeek(
            programId: inst.programId, instance: inst, profile: profile, week: week,
            templates: programTemplates)

        var templates: [ProgramSessionTemplate] = []
        for st in activeSessions {
            templates.append(contentsOf: lookupAdaptedTemplates(
                programId: inst.programId, week: week, sessionType: st,
                allTemplates: allSessionTemplates,
                instance: inst, totalWeeks: totalWeeks,
                blockLength: inst.blockLength, goal: goal))
        }

        var totals: [MuscleHead: Double] = [:]

        for t in templates {
            let key = resolveExerciseKey(slotId: t.slotId, originalKey: t.exerciseKey,
                                         overrides: inst.overrides, week: week)
            let contributions = lookupHeadContributionsForKey(key)
            guard !contributions.isEmpty else { continue }
            let delta = inst.overrides
                .filter { ov in
                    ov.targetSlotId == t.slotId && ov.sessionType == t.sessionType &&
                    ov.setCountDelta != 0 && !ov.isAddition && ov.appliesTo(week: week)
                }
                .reduce(0) { $0 + $1.setCountDelta }
            let effectiveSets = max(0, t.targetSets + delta)
            for (head, weight) in contributions where head.parentMuscle == muscle {
                totals[head, default: 0] += weight * Double(effectiveSets)
            }
        }

        for ov in inst.overrides where ov.isAddition && ov.appliesTo(week: week) {
            let key = ov.replacementExerciseKey
            let contributions = lookupHeadContributionsForKey(key)
            for (head, weight) in contributions where head.parentMuscle == muscle {
                totals[head, default: 0] += weight * Double(ov.addedSets)
            }
        }

        return MuscleHead.heads(of: muscle).map { ($0, totals[$0] ?? 0) }
    }

    /// Dictionary lookup first, then custom Exercise (stored or inferred).
    private func lookupHeadContributionsForKey(_ exerciseKey: String) -> [MuscleHead: Double] {
        if let def = ExerciseDictionary.all[exerciseKey] {
            return def.headContributions
        }
        if let ex = allExercises.first(where: { $0.exerciseKey == exerciseKey }) {
            let stored = ex.headContributions
            return stored.isEmpty
                ? Exercise.inferHeadContributions(primary: ex.musclesPrimary,
                                                  secondary: ex.musclesSecondary)
                : stored
        }
        return [:]
    }

    @ViewBuilder
    private func programHeadBreakdown(muscle: String) -> some View {
        let credits = programmedHeadCredits(for: muscle)
        // Match the parent bar's "programmed" count — head bars below show
        // how those programmed sets distribute across the muscle's heads.
        // Heads overlap (one set fires multiple), so summing them double-counts.
        let totalParent = Double(programmedSetsForMuscle(muscle))
        let tier = profile?.muscleTiers[muscle] ?? .neutral
        let mrv = VolumeLandmark.effectiveMRV(
            muscle: muscle, experience: profile?.experience ?? .intermediate,
            tier: tier, calorieContext: profile?.calorieContext ?? .surplus)

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("\(muscle.uppercased()) — HEADS")
                    .font(.system(size: 9, weight: .black))
                    .foregroundColor(.appBlue).kerning(1)
                JargonHelp(termId: "head_credits", size: 10)
                Spacer()
                Text(setsLabelDouble(totalParent))
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(.appTextDim)
            }
            if credits.allSatisfy({ $0.sets < 0.05 }) {
                Text("No programmed sets target this muscle's heads. Add exercises in Configure Program or Day Templates.")
                    .font(.system(size: 11)).foregroundColor(.appTextSecondary)
                    .lineSpacing(2)
            } else {
                // ── Interpretation banner ─────────────────────────────
                let targetForInterp = profile?.effectiveTarget(for: muscle) ?? Int(mrv)
                if let interp = programInterpretation(muscle: muscle, credits: credits,
                                                      parentCredit: totalParent,
                                                      target: targetForInterp) {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: interp.icon).font(.system(size: 11, weight: .bold))
                            .foregroundColor(interp.color)
                        Text(interp.text)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.appTextPrimary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                    .background(interp.color.opacity(0.08))
                    .cornerRadius(6)
                }

                // Per-head emphasis tags need the average — compute once.
                let nonZero = credits.filter { $0.sets > 0.05 }
                let avg: Double = nonZero.isEmpty ? 0
                    : nonZero.reduce(0) { $0 + $1.sets } / Double(nonZero.count)

                ForEach(credits, id: \.head) { entry in
                    let v = entry.sets
                    let frac = mrv > 0 ? min(v / Double(mrv), 1.2) : 0
                    let isExpanded = expandedHeadRow == entry.head
                    let tag = programEmphasisTag(value: v, average: avg)
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            expandedHeadRow = isExpanded ? nil : entry.head
                        }
                    } label: {
                        HStack(spacing: 6) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(entry.head.laymanName.capitalizingFirst)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.appTextPrimary)
                                    .lineLimit(1).minimumScaleFactor(0.85)
                                if entry.head.laymanDiffersFromDisplay {
                                    Text(entry.head.displayName)
                                        .font(.system(size: 8))
                                        .foregroundColor(.appTextDim)
                                        .lineLimit(1).minimumScaleFactor(0.85)
                                }
                            }
                            .frame(width: 100, alignment: .leading)
                            if let tag = tag {
                                Text(tag.label)
                                    .font(.system(size: 7, weight: .black)).kerning(0.5)
                                    .foregroundColor(tag.color)
                                    .padding(.horizontal, 3).padding(.vertical, 1)
                                    .background(tag.color.opacity(0.15))
                                    .cornerRadius(3)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2).fill(Color.appSurface2).frame(height: 5)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(programHeadBarColor(v, mrv: Double(mrv)))
                                        .frame(width: geo.size.width * CGFloat(min(frac, 1.0)), height: 5)
                                }
                            }.frame(height: 6)
                            Text(setsLabelDouble(v))
                                .font(.system(size: 10, weight: .black, design: .monospaced))
                                .foregroundColor(.appTextPrimary)
                                .frame(width: 30, alignment: .trailing)
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(isExpanded ? .appBlue : .appTextDim.opacity(0.6))
                                .frame(width: 10)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if isExpanded {
                        programHeadDrilldown(head: entry.head)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }

            // Footer: explainer + Adjust Volume entry point
            Text("Each programmed set distributes stimulus across multiple heads. Head bars show that distribution — they don't add up to the total because heads overlap within a single set. Tap a head to see what feeds it and what could build it more.")
                .font(.system(size: 9))
                .foregroundColor(.appTextDim)
                .lineSpacing(1.5)
                .padding(.top, 4)

            Button {
                volumeAdjustMuscle = muscle
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 11, weight: .bold))
                    Text("ADJUST \(muscle.uppercased()) VOLUME")
                        .font(.system(size: 10, weight: .black)).kerning(1)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                }
                .foregroundColor(.appBlue)
                .padding(.vertical, 9).padding(.horizontal, 10)
                .background(Color.appBlue.opacity(0.10))
                .cornerRadius(7)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.appBlue.opacity(0.30), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(10)
        .background(Color.appBlue.opacity(0.05))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBlue.opacity(0.2), lineWidth: 1))
    }

    private func setsLabelDouble(_ v: Double) -> String {
        if abs(v - v.rounded()) < 0.05 { return "\(Int(v.rounded()))" }
        return String(format: "%.1f", v)
    }

    private func programHeadBarColor(_ sets: Double, mrv: Double) -> Color {
        guard mrv > 0 else { return .appTextDim }
        let frac = sets / mrv
        if frac < 0.20 { return .appRed }
        if frac < 0.40 { return .appYellow }
        if frac <= 0.85 { return .appGreen }
        return .appOrange
    }

    // ═══════════════════════════════════════════
    // PROGRAM HEAD INTERPRETATION
    // Translates the programmed head distribution into one actionable
    // sentence. Mirrors HomeView's `headInterpretation` but reads
    // PROGRAMMED data (the plan), not logged data — so no pacing branch.
    // ═══════════════════════════════════════════

    private struct ProgramHeadInterpretation {
        let text: String
        let icon: String
        let color: Color
    }

    private struct ProgramEmphasisTag {
        let label: String
        let color: Color
    }

    private func programEmphasisTag(value: Double, average: Double) -> ProgramEmphasisTag? {
        guard average > 0.5 else { return nil }
        let ratio = value / average
        if ratio >= 1.4 { return .init(label: "HIGH", color: .appBlue) }
        if ratio <= 0.6 { return .init(label: "LOW", color: .appOrange) }
        return nil
    }

    private func programInterpretation(
        muscle: String,
        credits: [(head: MuscleHead, sets: Double)],
        parentCredit: Double,
        target: Int
    ) -> ProgramHeadInterpretation? {
        let nonZero = credits.filter { $0.sets > 0.5 }
        let zeroHeads = parentCredit >= 3.0
            ? credits.filter { $0.sets < 0.3 }
            : []

        let targetD = Double(max(target, 0))
        let underTarget = targetD > 0 && parentCredit < targetD * 0.7
        let overTarget  = targetD > 0 && parentCredit > targetD * 1.25

        let maxEntry = nonZero.max(by: { $0.sets < $1.sets })
        let minNonZero = nonZero.min(by: { $0.sets < $1.sets })
        let ratio: Double = {
            guard let mx = maxEntry?.sets, let mn = minNonZero?.sets, mn > 0 else { return 1.0 }
            return mx / mn
        }()
        let strongImbalance = ratio >= 1.8
        let mildEmphasis = ratio >= 1.3 && ratio < 1.8
        let balanced = nonZero.count >= 2 && ratio < 1.3

        // 1. Missing head(s) entirely
        if !zeroHeads.isEmpty, let missing = zeroHeads.first {
            let names = zeroHeads.prefix(2).map { $0.head.laymanName }.joined(separator: " and ")
            if underTarget {
                return .init(
                    text: "Your program is under target for \(muscle.lowercased()) AND not hitting \(names). Add an exercise that targets \(missing.head.laymanName).",
                    icon: "exclamationmark.triangle.fill", color: .appOrange)
            }
            return .init(
                text: "Your program isn't hitting \(names). Tap that head below to see exercises that build it.",
                icon: "arrow.up.arrow.down", color: .appOrange)
        }

        // 2. Over target
        if overTarget {
            if mildEmphasis || strongImbalance, let mx = maxEntry {
                return .init(
                    text: "Program is over target for \(muscle.lowercased()), with \(mx.head.laymanName) doing most of the work. Consider trimming or rebalancing.",
                    icon: "exclamationmark.circle.fill", color: .appRed)
            }
            return .init(
                text: "Program is over target for \(muscle.lowercased()) by ~\(Int(parentCredit.rounded()) - target) sets. Consider trimming if recovery is suffering.",
                icon: "exclamationmark.circle.fill", color: .appRed)
        }

        // 3. Under target
        if underTarget {
            let missing = max(1, target - Int(parentCredit.rounded()))
            if strongImbalance, let mn = minNonZero {
                return .init(
                    text: "Program is under target by ~\(missing) sets, with \(mn.head.laymanName) lagging. Add an exercise that emphasizes it.",
                    icon: "exclamationmark.triangle.fill", color: .appOrange)
            }
            if balanced {
                return .init(
                    text: "Program is under target by ~\(missing) sets, but distribution is even. Add any direct \(muscle.lowercased()) exercise.",
                    icon: "exclamationmark.triangle.fill", color: .appOrange)
            }
            return .init(
                text: "Program is under target by ~\(missing) sets. Add more direct \(muscle.lowercased()) work.",
                icon: "exclamationmark.triangle.fill", color: .appOrange)
        }

        // 4. On target — describe balance
        if strongImbalance, let mn = minNonZero, let mx = maxEntry {
            return .init(
                text: "On target but \(mx.head.laymanName) is dominant while \(mn.head.laymanName) is lagging. Tap \(mn.head.laymanName) to find exercises that emphasize it.",
                icon: "arrow.up.arrow.down", color: .appBlue)
        }
        if mildEmphasis, let mx = maxEntry {
            return .init(
                text: "On target with mild emphasis on \(mx.head.laymanName). All heads are getting useful work.",
                icon: "checkmark.circle.fill", color: .appGreen)
        }
        if balanced {
            return .init(
                text: "Program is balanced and on target — every \(muscle.lowercased()) head is getting proportional stimulus.",
                icon: "checkmark.circle.fill", color: .appGreen)
        }
        if nonZero.count == 1, let only = nonZero.first {
            return .init(
                text: "All your programmed \(muscle.lowercased()) work goes to \(only.head.laymanName). Add variety for the other heads.",
                icon: "arrow.up.arrow.down", color: .appOrange)
        }
        return nil
    }

    // ═══════════════════════════════════════════
    // PROGRAM HEAD DRILLDOWN
    // Tap a head row → see exercises in the program that hit it +
    // recommendations from the dictionary to grow it more.
    // ═══════════════════════════════════════════

    private struct ProgramHeadContribution: Identifiable {
        let id: String  // exerciseKey
        let displayName: String
        let setCount: Int
        let weight: Double
        let credit: Double
    }

    private func programmedExercisesContributingTo(_ head: MuscleHead) -> [ProgramHeadContribution] {
        guard let inst = instance else { return [] }
        let week = inst.currentWeek
        let goal = profile?.goal ?? .hypertrophy
        let activeSessions = activeSessionsForWeek(
            programId: inst.programId, instance: inst, profile: profile, week: week,
            templates: programTemplates)
        var templates: [ProgramSessionTemplate] = []
        for st in activeSessions {
            templates.append(contentsOf: lookupAdaptedTemplates(
                programId: inst.programId, week: week, sessionType: st,
                allTemplates: allSessionTemplates,
                instance: inst, totalWeeks: totalWeeks,
                blockLength: inst.blockLength, goal: goal))
        }

        // Group by resolved exerciseKey, sum sets per key
        var byKey: [String: (name: String, sets: Int, weight: Double)] = [:]
        for t in templates {
            let key = resolveExerciseKey(slotId: t.slotId, originalKey: t.exerciseKey,
                                         overrides: inst.overrides, week: week)
            let contributions = lookupHeadContributionsForKey(key)
            guard let weight = contributions[head], weight > 0.05 else { continue }
            let delta = inst.overrides
                .filter { ov in
                    ov.targetSlotId == t.slotId && ov.sessionType == t.sessionType &&
                    ov.setCountDelta != 0 && !ov.isAddition && ov.appliesTo(week: week)
                }
                .reduce(0) { $0 + $1.setCountDelta }
            let effectiveSets = max(0, t.targetSets + delta)
            let name = ExerciseDictionary.all[key]?.displayName
                ?? allExercises.first(where: { $0.exerciseKey == key })?.displayName
                ?? key
            if let existing = byKey[key] {
                byKey[key] = (existing.name, existing.sets + effectiveSets, weight)
            } else {
                byKey[key] = (name, effectiveSets, weight)
            }
        }

        for ov in inst.overrides where ov.isAddition && ov.appliesTo(week: week) {
            let key = ov.replacementExerciseKey
            let contributions = lookupHeadContributionsForKey(key)
            guard let weight = contributions[head], weight > 0.05 else { continue }
            let name = ExerciseDictionary.all[key]?.displayName
                ?? allExercises.first(where: { $0.exerciseKey == key })?.displayName
                ?? key
            if let existing = byKey[key] {
                byKey[key] = (existing.name, existing.sets + ov.addedSets, weight)
            } else {
                byKey[key] = (name, ov.addedSets, weight)
            }
        }

        return byKey
            .map { ProgramHeadContribution(id: $0.key, displayName: $0.value.name,
                                           setCount: $0.value.sets, weight: $0.value.weight,
                                           credit: Double($0.value.sets) * $0.value.weight) }
            .sorted { $0.credit > $1.credit }
    }

    private func programRecommendedExercisesForHead(_ head: MuscleHead, excluding: Set<String>) -> [ExerciseDefinition] {
        ExerciseDictionary.all.values
            .filter { def in
                guard let w = def.headContributions[head], w >= 0.7 else { return false }
                return !excluding.contains(def.key)
            }
            .sorted { (a, b) -> Bool in
                let aw = a.headContributions[head] ?? 0
                let bw = b.headContributions[head] ?? 0
                if aw != bw { return aw > bw }
                return a.displayName < b.displayName
            }
            .prefix(4)
            .map { $0 }
    }

    @ViewBuilder
    private func programHeadDrilldown(head: MuscleHead) -> some View {
        let contributions = programmedExercisesContributingTo(head)
        let inUseKeys = Set(contributions.map { $0.id })
        let recommended = programRecommendedExercisesForHead(head, excluding: inUseKeys)
        VStack(alignment: .leading, spacing: 8) {
            if contributions.isEmpty {
                Text("Your program has no exercises that hit \(head.laymanName).")
                    .font(.system(size: 11)).foregroundColor(.appTextDim)
                    .italic()
            } else {
                Text("PROGRAM HAS")
                    .font(.system(size: 8, weight: .black))
                    .foregroundColor(.appTextDim).kerning(1)
                ForEach(contributions) { c in
                    HStack(spacing: 6) {
                        Text(c.displayName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.appTextPrimary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        Spacer()
                        HStack(spacing: 3) {
                            Text("\(c.setCount)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.appTextPrimary)
                            Text("×")
                                .font(.system(size: 8))
                                .foregroundColor(.appTextDim)
                            Text(String(format: "%.1f", c.weight))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.appTextDim)
                            Text("=")
                                .font(.system(size: 8))
                                .foregroundColor(.appTextDim)
                            Text(setsLabelDouble(c.credit))
                                .font(.system(size: 11, weight: .black, design: .monospaced))
                                .foregroundColor(.appBlue)
                                .frame(width: 28, alignment: .trailing)
                        }
                    }
                }
            }
            if !recommended.isEmpty {
                Text("BUILD IT WITH")
                    .font(.system(size: 8, weight: .black))
                    .foregroundColor(.appTextDim).kerning(1)
                    .padding(.top, contributions.isEmpty ? 0 : 4)
                ForEach(recommended, id: \.key) { rec in
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.appGreen.opacity(0.85))
                        Text(rec.displayName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.appTextPrimary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        Spacer()
                        Text(String(format: "%.1f", rec.headContributions[head] ?? 0))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.appGreen)
                            .frame(width: 28, alignment: .trailing)
                    }
                }
                Text("Numbers show how strongly each exercise hits \(head.laymanName).")
                    .font(.system(size: 9))
                    .foregroundColor(.appTextDim)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .padding(.leading, 14)
        .background(Color.appSurface)
        .cornerRadius(6)
    }

    private func programActionButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 11, weight: .bold))
                Text(title).font(.system(size: 11, weight: .bold)).kerning(0.3)
            }
            .foregroundColor(color)
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(color.opacity(0.06)).cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // ═══════════════════════════════════════
    // SECTION PICKER
    // ═══════════════════════════════════════

    private var sectionPicker: some View {
        HStack(spacing: 4) {
            ForEach(ProgramSection.allCases, id: \.self) { section in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selectedSection = section }
                } label: {
                    Text(section.rawValue)
                        .font(.system(size: 12, weight: selectedSection == section ? .black : .medium))
                        .foregroundColor(selectedSection == section ? .white : .appTextSecondary)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(selectedSection == section ? Color.appRed : Color.appSurface2)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4).background(Color.appSurface).cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))
    }

    // ═══════════════════════════════════════
    // OVERVIEW SECTION
    // ═══════════════════════════════════════

    private var overviewSection: some View {
        VStack(spacing: 14) {
            // Mesocycle summary — derived from current week so the phase label
            // and block number reflect what week the user is actually on, not
            // the stale stored inst.blockType.
            if usesPeriodization, let inst = instance, inst.programId != 0 {
                let goal = profile?.goal ?? .hypertrophy
                let info = ComputedBlockInfo.compute(
                    forWeek: inst.currentWeek,
                    programId: inst.programId,
                    blockLength: inst.blockLength,
                    totalWeeks: programTemplates.first(where: { $0.programId == inst.programId })?.durationWeeks ?? 24,
                    goal: goal,
                    instance: inst,
                    usesPeriodization: usesPeriodization,
                    skipDeloads: profile?.skipDeloads ?? false
                )

                // Mesocycle summary — minimal collapses to just program-week.
                // Advanced shows full phase name + block number + week-in-block.
                VStack(alignment: .leading, spacing: 10) {
                    Text("MESOCYCLE").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(2)

                    if density.showsBlockPhaseName {
                        HStack(spacing: 16) {
                            VStack(spacing: 2) {
                                Text(info.displayPhaseName)
                                    .font(.system(size: 14, weight: .black)).foregroundColor(.appTextPrimary)
                                Text("Current Phase").font(.system(size: 10)).foregroundColor(.appTextDim)
                            }
                            Spacer()
                            VStack(spacing: 2) {
                                Text("\(info.weekInBlock)/\(info.blockTrainingWeeks)")
                                    .font(.system(size: 18, weight: .black, design: .rounded)).foregroundColor(.appRed)
                                Text("Block Week").font(.system(size: 10)).foregroundColor(.appTextDim)
                            }
                            VStack(spacing: 2) {
                                Text("#\(info.blockNumber)")
                                    .font(.system(size: 18, weight: .black, design: .rounded)).foregroundColor(.appBlue)
                                Text("Block").font(.system(size: 10)).foregroundColor(.appTextDim)
                            }
                        }
                    } else {
                        HStack {
                            Text("Week \(inst.currentWeek) of \(totalWeeks)")
                                .font(.system(size: 14, weight: .black)).foregroundColor(.appTextPrimary)
                            Spacer()
                            Text("\(info.weekInBlock)/\(info.blockTrainingWeeks)")
                                .font(.system(size: 14, weight: .bold)).foregroundColor(.appTextSecondary)
                        }
                    }
                }
                .padding(14).background(Color.appSurface).cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
            }

            // Block configurator — advanced only AND periodization on.
            // Hidden in continuous-training mode (no blocks to configure).
            if density.showsBlockConfigCard, usesPeriodization,
               let inst = instance, inst.programId != 0 {
                BlockConfigCard(inst: inst, goal: profile?.goal ?? .hypertrophy,
                                totalWeeks: totalWeeks,
                                onTapBlock: { idx in blockEditorFocusIndex = idx; showBlockSequenceEditor = true },
                                modelContext: modelContext,
                                usesPeriodization: usesPeriodization,
                                skipDeloads: profile?.skipDeloads ?? false)
            }

            // Strength goals — hidden in minimal (peaking protocols are advanced).
            if density.showsProgramStrengthGoals, let inst = instance {
                strengthGoalsManagement(inst: inst)
            }

            // Volume — programmed vs target. Hidden in minimal.
            if density.showsWeeklyVolumeBars {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("WEEKLY VOLUME").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(2)
                    Spacer()
                    Text("Programmed / Target").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim).kerning(0.5)
                }

                ForEach(ExerciseDictionary.trackingMuscles, id: \.self) { muscle in
                    let tier = profile?.muscleTiers[muscle] ?? .neutral
                    // Unified target: profile.effectiveTarget(for:) — used by
                    // Home muscle bars + Volume Adjuster, so all three displays
                    // show the same "weekly target" denominator.
                    let target = profile?.effectiveTarget(for: muscle)
                        ?? ProgramGenerator.resolveWeeklySetTarget(
                            muscle: muscle, week: instance?.currentWeek ?? 1,
                            blockType: instance?.blockType ?? .accumulation,
                            muscleTier: tier, experience: profile?.experience ?? .intermediate,
                            calorieContext: profile?.calorieContext ?? .surplus, calibration: nil)
                    let mrv = VolumeLandmark.effectiveMRV(
                        muscle: muscle, experience: profile?.experience ?? .intermediate,
                        tier: tier, calorieContext: profile?.calorieContext ?? .surplus)
                    let programmed = programmedSetsForMuscle(muscle)
                    let underTarget = programmed < target

                    let isExpanded = (density == .advanced && expandedHeadMuscle == muscle)
                    Button {
                        if density == .advanced {
                            // Advanced: toggle head breakdown below.
                            // Volume Adjuster reachable from inside the panel.
                            withAnimation(.easeInOut(duration: 0.2)) {
                                expandedHeadMuscle = isExpanded ? nil : muscle
                            }
                        } else {
                            volumeAdjustMuscle = muscle
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(muscle).font(.system(size: 11, weight: .bold))
                                .foregroundColor(tier == .priority ? .appGold : (tier == .maintenance ? .appTextDim : .appTextPrimary))
                                .frame(width: 70, alignment: .leading)
                            if tier == .priority { Text("★").font(.system(size: 9)).foregroundColor(.appGold) }
                            GeometryReader { geo in
                                let progPct = mrv > 0 ? min(CGFloat(programmed) / CGFloat(mrv), 1.0) : 0
                                let targPct = mrv > 0 ? min(CGFloat(target) / CGFloat(mrv), 1.0) : 0
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3).fill(Color.appSurface2).frame(height: 8)
                                    // Programmed fill (solid)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(tier == .priority ? Color.appGold : (underTarget ? Color.appOrange : Color.appGreen))
                                        .frame(width: geo.size.width * progPct, height: 8)
                                    // Target marker (vertical line)
                                    Rectangle().fill(Color.appTextPrimary).frame(width: 1.5, height: 12)
                                        .offset(x: geo.size.width * targPct - 1, y: -2)
                                }
                            }.frame(height: 12)
                            Text("\(programmed)/\(target)").font(.system(size: 10, weight: .black, design: .rounded))
                                .foregroundColor(underTarget ? .appOrange : .appTextPrimary).frame(width: 42, alignment: .trailing)
                            Image(systemName: density == .advanced
                                  ? (isExpanded ? "chevron.up" : "chevron.down")
                                  : "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(isExpanded ? .appBlue : .appTextDim)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // Inline head breakdown directly under the muscle row,
                    // so the relationship is obvious. Indented + boxed.
                    if isExpanded {
                        programHeadBreakdown(muscle: muscle)
                            .padding(.leading, 10)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }

                // Legend
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 1).fill(Color.appGreen).frame(width: 8, height: 4)
                        Text("Programmed").font(.system(size: 9)).foregroundColor(.appTextDim)
                    }
                    HStack(spacing: 4) {
                        Rectangle().fill(Color.appTextPrimary).frame(width: 1.5, height: 8)
                        Text("Target").font(.system(size: 9)).foregroundColor(.appTextDim)
                    }
                    Spacer()
                }
                .padding(.top, 4)
            }
            .padding(14).background(Color.appSurface).cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
            } // end if density.showsWeeklyVolumeBars

            // Muscle priority cycler — advanced only. Casual users had
            // priority muscles set in onboarding and rarely change them.
            if density.showsMusclePrioritiesCycler, profile != nil {
                muscleTierEditor
            }

            // Split structure
            if let inst = instance, inst.programId != 0 {
                let split = programSplit()
                VStack(alignment: .leading, spacing: 10) {
                    Text("SPLIT STRUCTURE").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(2)
                    ForEach(Array(split.enumerated()), id: \.offset) { idx, day in
                        HStack(spacing: 8) {
                            Text("D\(idx + 1)").font(.system(size: 10, weight: .black, design: .monospaced))
                                .foregroundColor(.appRed).frame(width: 22)
                            Text(day.0).font(.system(size: 13, weight: .bold)).foregroundColor(.appTextPrimary)
                            Spacer()
                            Text(day.1).font(.system(size: 11)).foregroundColor(.appTextDim).lineLimit(1)
                        }
                    }
                }
                .padding(14).background(Color.appSurface).cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
            }

            // Session duration estimates — hidden in minimal.
            if density.showsSessionDuration {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SESSION ESTIMATES").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(2)
                    let split = programSplit()
                    ForEach(Array(split.enumerated()), id: \.offset) { idx, day in
                        let sets = estimateSessionSets(sessionMuscles: day.1)
                        let minutes = sets * 3  // ~3 min per set average
                        HStack {
                            Text(day.0).font(.system(size: 12, weight: .bold)).foregroundColor(.appTextSecondary)
                            Spacer()
                            Text("\(sets) sets").font(.system(size: 11, weight: .bold)).foregroundColor(.appTextPrimary)
                            Text("~\(minutes) min").font(.system(size: 11)).foregroundColor(.appTextDim)
                        }
                    }
                }
                .padding(14).background(Color.appSurface).cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
            }
        }
    }

    // ═══════════════════════════════════════
    // STRENGTH GOALS MANAGEMENT
    // ═══════════════════════════════════════

    private func strengthGoalsManagement(inst: UserProgramInstance) -> some View {
        let activeGoals = inst.strengthGoals.filter { $0.isActive }

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("STRENGTH GOALS").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(2)
                Spacer()
                if activeGoals.count < 3 {
                    Button { showStrengthGoalSheet = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                            Text("ADD").font(.system(size: 10, weight: .black))
                        }
                        .foregroundColor(.appRed).padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.appRed.opacity(0.08)).cornerRadius(6)
                    }.buttonStyle(.plain)
                } else {
                    Text("3/3").font(.system(size: 10, weight: .bold)).foregroundColor(.appTextDim)
                }
            }

            if activeGoals.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "target").font(.system(size: 16)).foregroundColor(.appTextDim)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No strength goals set").font(.system(size: 13, weight: .bold)).foregroundColor(.appTextSecondary)
                        Text("Pick a compound lift and set a target. The algorithm will build a peaking plan.")
                            .font(.system(size: 11)).foregroundColor(.appTextDim)
                    }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.appSurface).cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
            } else {
                ForEach(activeGoals, id: \.exerciseKey) { goal in
                    let bestE1rm = inst.logs.filter { $0.exerciseKey == goal.exerciseKey }
                        .map { $0.e1rm }.max() ?? goal.startE1RM
                    let progress = min(1.0, max(0, (bestE1rm - goal.startE1RM) / max(goal.targetWeight - goal.startE1RM, 1)))
                    let isHyp = profile?.goal == .hypertrophy || profile?.goal == .recomp

                    Button { editingGoal = goal } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: "target").font(.system(size: 13)).foregroundColor(.appRed)
                                Text(goal.displayName).font(.system(size: 14, weight: .black)).foregroundColor(.appTextPrimary)
                                Spacer()
                                Text("\(Int(goal.targetWeight)) lb")
                                    .font(.system(size: 16, weight: .black, design: .rounded)).foregroundColor(.appGold)
                                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundColor(.appTextDim)
                            }

                            // Progress bar
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4).fill(Color.appSurface2).frame(height: 8)
                                    RoundedRectangle(cornerRadius: 4).fill(Color.appRed)
                                        .frame(width: max(0, geo.size.width * progress), height: 8)
                                }
                            }.frame(height: 8)

                            HStack {
                                Text("e1RM \(Int(bestE1rm)) → \(Int(goal.targetWeight)) lb (\(Int(progress * 100))%)")
                                    .font(.system(size: 11, weight: .bold)).foregroundColor(.appTextSecondary)
                                Spacer()
                                // Phase badge
                                HStack(spacing: 4) {
                                    Circle().fill(goalPhaseColor(goal.phase)).frame(width: 6, height: 6)
                                    Text("\(goal.phase.displayName) Wk \(goal.phaseWeek)/\(goal.currentPhaseLength)")
                                        .font(.system(size: 10, weight: .bold)).foregroundColor(.appTextDim)
                                }
                            }

                            // Week-by-week impact preview
                            VStack(alignment: .leading, spacing: 4) {
                                Text("PROGRAM IMPACT").font(.system(size: 8, weight: .bold)).foregroundColor(.appTextDim).kerning(1)
                                let rr = goal.phase.repRange
                                HStack(spacing: 12) {
                                    Label("\(goal.phase.targetSets)×\(rr.low)-\(rr.high)", systemImage: "dumbbell.fill")
                                        .font(.system(size: 10, weight: .bold)).foregroundColor(.appTextSecondary)
                                    Label("RPE \(String(format: "%.0f", goal.phase.targetRPE))", systemImage: "flame")
                                        .font(.system(size: 10, weight: .bold)).foregroundColor(.appTextSecondary)
                                    Label("Rest 3:00+", systemImage: "timer")
                                        .font(.system(size: 10, weight: .bold)).foregroundColor(.appTextSecondary)
                                }

                                if isHyp {
                                    Text("Other exercises stay hypertrophy (8-12 reps)")
                                        .font(.system(size: 9)).foregroundColor(.appTextDim)
                                }
                            }
                            .padding(8).background(Color.appSurface2).cornerRadius(6)
                        }
                        .padding(14).background(Color.appSurface).cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appRed.opacity(0.2), lineWidth: 1))
                    }.buttonStyle(.plain)
                }

                if activeGoals.count >= 3 {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle").font(.system(size: 10)).foregroundColor(.appBlue)
                        Text("Max 3 active goals — each strength goal adds systemic fatigue and reduces accessory volume. The algorithm manages recovery, but more than 3 would leave too little room for hypertrophy work.")
                            .font(.system(size: 10)).foregroundColor(.appTextDim)
                    }
                    .padding(10).background(Color.appBlue.opacity(0.04)).cornerRadius(8)
                }
            }
        }
    }

    private func goalPhaseColor(_ phase: StrengthGoalPhase) -> Color {
        switch phase {
        case .building: return .appGreen
        case .intensifying: return .appOrange
        case .peaking: return .appRed
        case .testing: return .appGold
        }
    }

    // blockConfigurator is now BlockConfigCard (separate struct below)
    // ═══════════════════════════════════════
    // MUSCLE TIER EDITOR
    // ═══════════════════════════════════════

    private var muscleTierEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("MUSCLE PRIORITIES").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(2)
                Spacer()
                Text("Tap to cycle").font(.system(size: 10)).foregroundColor(.appTextDim)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 95), spacing: 8)], spacing: 8) {
                ForEach(ExerciseDictionary.trackingMuscles, id: \.self) { muscle in
                    let tier = profile?.muscleTiers[muscle] ?? .neutral

                    Button {
                        guard let p = profile else { return }
                        var tiers = p.muscleTiers
                        switch tier {
                        case .neutral:     tiers[muscle] = .priority
                        case .priority:    tiers[muscle] = .maintenance
                        case .maintenance: tiers[muscle] = .neutral
                        }
                        p.muscleTiers = tiers
                        try? modelContext.save()
                    } label: {
                        VStack(spacing: 3) {
                            Text(muscle)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(tier == .priority ? .appGold : (tier == .maintenance ? .appTextDim : .appTextPrimary))
                            HStack(spacing: 3) {
                                Circle().fill(tierColor(tier)).frame(width: 6, height: 6)
                                Text(tier.label)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(tier == .priority ? .appGold : (tier == .maintenance ? .appTextDim : .appTextSecondary))
                            }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(tier == .priority ? Color.appGold.opacity(0.08) : (tier == .maintenance ? Color.appSurface2.opacity(0.5) : Color.appSurface2))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(tier == .priority ? Color.appGold.opacity(0.3) : Color.appBorder, lineWidth: tier == .priority ? 1.5 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Legend
            HStack(spacing: 16) {
                legendItem(color: .appGold, label: "Priority", detail: "+4 sets, 1.5x MRV")
                legendItem(color: .appGreen, label: "Neutral", detail: "Standard volume")
                legendItem(color: .appTextDim, label: "Maintenance", detail: "0.7x MRV ceiling")
            }
            .padding(.top, 4)
        }
        .padding(14).background(Color.appSurface).cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
    }

    private func tierColor(_ tier: MuscleTier) -> Color {
        switch tier {
        case .priority: return .appGold
        case .neutral: return .appGreen
        case .maintenance: return .appTextDim
        }
    }

    private func legendItem(color: Color, label: String, detail: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label).font(.system(size: 9, weight: .bold)).foregroundColor(color)
            Text(detail).font(.system(size: 8)).foregroundColor(.appTextDim)
        }
    }

    // ═══════════════════════════════════════
    // WEEKS SECTION
    // ═══════════════════════════════════════

    private var weeksSection: some View {
        VStack(spacing: 14) {
            // Week picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    let total = totalWeeks
                    ForEach(1...max(total, 1), id: \.self) { w in
                        Button { editingWeek = w } label: {
                            Text("\(w)")
                                .font(.system(size: 12, weight: editingWeek == w ? .black : .medium))
                                .foregroundColor(editingWeek == w ? .white : (w == instance?.currentWeek ? .appRed : .appTextSecondary))
                                .frame(width: 32, height: 32)
                                .background(editingWeek == w ? Color.appRed : Color.appSurface2)
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8)
                                    .stroke(w == instance?.currentWeek ? Color.appRed.opacity(0.5) : Color.clear, lineWidth: 1.5))
                        }.buttonStyle(.plain)
                    }
                }
            }

            // Week info with context
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("WEEK \(editingWeek)").font(.system(size: 14, weight: .black)).foregroundColor(.appTextPrimary)
                        if editingWeek == instance?.currentWeek {
                            Text("CURRENT").font(.system(size: 9, weight: .black)).foregroundColor(.appRed).kerning(1)
                                .padding(.horizontal, 6).padding(.vertical, 2).background(Color.appRed.opacity(0.1)).cornerRadius(4)
                        }
                    }
                    // Show what kind of week this is
                    let weekType = weekTypeLabel(editingWeek)
                    Text(weekType)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(weekType.contains("Recovery") || weekType.contains("Deload") ? .appBlue : .appGreen)
                }
                Spacer()
            }

            // Recovery week notice
            let isRecovery = isRecoveryWeek(editingWeek)
            if isRecovery {
                HStack(spacing: 8) {
                    Image(systemName: "leaf.fill").foregroundColor(.appBlue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recovery Week").font(.system(size: 13, weight: .bold)).foregroundColor(.appBlue)
                        Text("Reduced volume and intensity. Focus on movement quality and recovery.")
                            .font(.system(size: 11)).foregroundColor(.appTextSecondary)
                    }
                }
                .padding(12).background(Color.appBlue.opacity(0.06)).cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBlue.opacity(0.15), lineWidth: 1))
            }

            // Sessions for this week — base program rotation, plus any sessions
            // imported via Configure Program for this specific week. Order: base
            // first (preserves the user's program order), extras appended.
            let rotation = displayRotation(forWeek: editingWeek)
            let templatesBySession = sessionsForWeek(editingWeek)

            if rotation.isEmpty {
                HStack {
                    Image(systemName: "tray").foregroundColor(.appTextDim)
                    Text("No sessions configured").font(.system(size: 13)).foregroundColor(.appTextDim)
                    Spacer()
                }
                .padding(14).background(Color.appSurface).cornerRadius(10)
            } else {
                // Only show sessions that actually have templates this week
                let activeSessions = rotation.filter { !(templatesBySession[$0] ?? []).isEmpty }
                if activeSessions.isEmpty && isRecovery {
                    HStack(spacing: 8) {
                        Image(systemName: "leaf.fill").foregroundColor(.appBlue)
                        Text("No scheduled sessions this week — recovery only")
                            .font(.system(size: 13)).foregroundColor(.appTextSecondary)
                    }
                    .padding(14).background(Color.appSurface).cornerRadius(10)
                } else if activeSessions.isEmpty {
                    ForEach(Array(rotation.enumerated()), id: \.offset) { idx, sessionType in
                        weekSessionCard(sessionType: sessionType, templates: [])
                    }
                } else {
                    ForEach(Array(activeSessions.enumerated()), id: \.offset) { idx, sessionType in
                        let templates = templatesBySession[sessionType] ?? []
                        weekSessionCard(sessionType: sessionType, templates: templates)
                    }
                    // Show skipped sessions
                    let skipped = rotation.filter { (templatesBySession[$0] ?? []).isEmpty }
                    if !skipped.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "moon.zzz.fill").font(.system(size: 11)).foregroundColor(.appTextDim)
                            Text("Resting: \(skipped.map { $0.shortLabel }.joined(separator: ", "))")
                                .font(.system(size: 11)).foregroundColor(.appTextDim)
                        }
                        .padding(10).background(Color.appSurface2).cornerRadius(8)
                    }
                }
            }

            // Copy week button
            Button {
                // TODO: Copy week functionality
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.doc").font(.system(size: 12))
                    Text("Copy This Week's Setup").font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(.appBlue).frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(Color.appBlue.opacity(0.06)).cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBlue.opacity(0.15), lineWidth: 1))
            }.buttonStyle(.plain)
        }
    }

    private func weekSessionCard(sessionType: SessionType, templates: [ProgramSessionTemplate]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(instance?.customLabel(for: sessionType) ?? sessionType.shortLabel)
                    .font(.system(size: 13, weight: .black)).foregroundColor(.appTextPrimary)
                Spacer()
                Text("\(templates.count) exercises").font(.system(size: 11)).foregroundColor(.appTextDim)
                Button {
                    editSessionItem = SessionEditorItem(sessionType: sessionType, templates: templates)
                } label: {
                    Image(systemName: "pencil").font(.system(size: 12, weight: .bold)).foregroundColor(.appBlue)
                        .frame(width: 36, height: 36).contentShape(Rectangle()).background(Color.appBlue.opacity(0.1)).cornerRadius(8)
                }.buttonStyle(.plain)
            }

            ForEach(templates.sorted { $0.exerciseIndex < $1.exerciseIndex }) { t in
                let name = ExerciseDictionary.all[t.exerciseKey]?.displayName ?? t.exerciseKey
                let def = ExerciseDictionary.all[t.exerciseKey]
                let tierLabel = t.isMainLift ? "T1" : (def?.isCompound == false ? "T3" : "T2")
                let tierColor: Color = t.isMainLift ? .appRed : (def?.isCompound == false ? .appGreen : .appBlue)

                HStack(spacing: 8) {
                    Text(tierLabel).font(.system(size: 9, weight: .black)).foregroundColor(tierColor).frame(width: 20)
                    Text(name).font(.system(size: 12)).foregroundColor(.appTextSecondary).lineLimit(1)
                    Spacer()
                    Text("\(t.targetSets)×\(t.targetRepsLow)-\(t.targetRepsHigh)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.appTextDim)
                }
            }
        }
        .padding(12).background(Color.appSurface).cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))
    }

    // ═══════════════════════════════════════
    // TEMPLATES SECTION
    // ═══════════════════════════════════════

    private var templatesSection: some View {
        VStack(spacing: 14) {
            // Embedded inline — not a sheet — so the inline + button shows
            // (the old NavigationView toolbar wasn't reliable when nested).
            DayTemplateLibraryView(presentsAsSheet: false)
        }
    }

    // ═══════════════════════════════════════
    // EXERCISES SECTION
    // ═══════════════════════════════════════

    private var exercisesSection: some View {
        ExerciseLibraryBrowser(exercises: allExercises)
    }

    // ═══════════════════════════════════════
    // HELPERS
    // ═══════════════════════════════════════

    private var totalWeeks: Int {
        if let inst = instance, inst.isGenerated {
            return (inst.blockLength + 1) * 4
        }
        if let tmpl = programTemplates.first(where: { $0.programId == instance?.programId ?? 1 }) {
            return tmpl.durationWeeks
        }
        return instance?.programId == 2 ? 16 : 24
    }

    private func programSplit() -> [(String, String)] {
        guard let p = profile, let inst = instance else { return [] }
        // Seeded programs (ID 1-10) — use hardcoded rotation
        if inst.programId <= 10 && inst.programId > 0 {
            let rotation: [SessionType]
            switch inst.programId {
            case 2: rotation = [.pushA, .pullA, .legsA, .pushB, .pullB, .legsB]
            case 7: rotation = [.legQuadFocus, .chestBack, .armsDelts, .legsPosterior, .chestArms, .legsVolume]
            default: rotation = [.heavyUpper, .heavyLower, .hypertrophyUpper, .hypertrophyLower]
            }
            // Honor user's custom session labels — renaming "Heavy Upper"
            // here flows through to the Split Structure card and the
            // Session Estimates card below.
            return rotation.map {
                (inst.customLabel(for: $0) ?? $0.shortLabel, $0.muscleSubtitle)
            }
        }
        // Generated or custom programs — derive from profile
        let split = ProgramGenerator.resolveSplitStructure(
            daysPerWeek: p.daysPerWeek, goal: p.goal, priorityMuscles: p.priorityMuscles)
        return split.filter { $0.sessionType != .rest }.map {
            let name = inst.customLabel(for: $0.sessionType) ?? $0.label
            return (name, $0.primaryMuscles.joined(separator: ", "))
        }
    }

    /// True only when periodization is on, skipDeloads is off, AND this is
    /// a configured deload week. Routing through ComputedBlockInfo keeps
    /// this in sync with every other recovery-week display.
    private func isRecoveryWeek(_ week: Int) -> Bool {
        guard let inst = instance else { return false }
        return ComputedBlockInfo.compute(
            forWeek: week, programId: inst.programId,
            blockLength: inst.blockLength, totalWeeks: totalWeeks,
            goal: profile?.goal ?? .hypertrophy, instance: inst,
            usesPeriodization: usesPeriodization,
            skipDeloads: profile?.skipDeloads ?? false
        ).isDeloadWeek
    }

    private func weekTypeLabel(_ week: Int) -> String {
        guard let inst = instance else { return "Training" }
        let info = ComputedBlockInfo.compute(
            forWeek: week,
            programId: inst.programId,
            blockLength: inst.blockLength,
            totalWeeks: totalWeeks,
            goal: profile?.goal ?? .hypertrophy,
            instance: inst,
            usesPeriodization: usesPeriodization,
            skipDeloads: profile?.skipDeloads ?? false
        )
        if info.isDeloadWeek {
            return profile?.goal == .strength || profile?.goal == .powerbuilding
                ? "Deload Week"
                : "Recovery Week"
        }
        return "\(info.displayPhaseName) — Week \(info.weekInBlock) of \(info.blockTrainingWeeks)"
    }

    /// The program's actual session rotation — source of truth for what sessions exist
    /// Display order for the Weeks tab: base rotation first, then any sessions
    /// imported via Configure Program for this week. Skips sessions that have
    /// been removed via permanent or week-specific rest-day overrides.
    private func displayRotation(forWeek week: Int) -> [SessionType] {
        let base = programRotation()
        guard let inst = instance else { return base }
        let active = activeSessionsForWeek(
            programId: inst.programId, instance: inst, profile: profile,
            week: week, templates: programTemplates)
        var ordered: [SessionType] = []
        for st in base where active.contains(st) && !ordered.contains(st) {
            ordered.append(st)
        }
        for st in active where !ordered.contains(st) {
            ordered.append(st)
        }
        return ordered
    }

    private func programRotation() -> [SessionType] {
        guard let inst = instance else { return [] }
        // Seeded programs
        switch inst.programId {
        case 1: return [.heavyUpper, .heavyLower, .hypertrophyUpper, .hypertrophyLower]
        case 2: return [.pushA, .pullA, .legsA, .pushB, .pullB, .legsB]
        case 7: return [.legQuadFocus, .chestBack, .armsDelts, .legsPosterior, .chestArms, .legsVolume]
        default: break
        }
        // Generated programs
        if inst.isGenerated, let p = profile {
            let split = ProgramGenerator.resolveSplitStructure(
                daysPerWeek: p.daysPerWeek, goal: p.goal, priorityMuscles: p.priorityMuscles)
            return split.filter { $0.sessionType != .rest }.map { $0.sessionType }
        }
        // Custom programs
        if let tmpl = programTemplates.first(where: { $0.programId == inst.programId }) {
            return tmpl.sessionTypes
        }
        return [.heavyUpper, .heavyLower, .hypertrophyUpper, .hypertrophyLower]
    }

    private func sessionsForWeek(_ week: Int) -> [SessionType: [ProgramSessionTemplate]] {
        guard let inst = instance else { return [:] }

        // Try the exact week first
        var templates = allSessionTemplates.filter {
            $0.programId == inst.programId && $0.week == week
        }

        // If this should be a training week (per blockLength) but templates are empty or sparse,
        // fall back to the nearest non-deload week's templates
        let rotation = programRotation()
        let sessionTypesFound = Set(templates.map { $0.sessionType })
        let missingSessionTypes = rotation.filter { !sessionTypesFound.contains($0) }

        if !isRecoveryWeek(week) && !missingSessionTypes.isEmpty {
            let bl = inst.blockLength > 0 ? inst.blockLength : 5
            let totalWk = totalWeeks
            for offset in [1, -1, 2, -2, 3, -3, 4, -4] {
                let fallbackWeek = week + offset
                guard fallbackWeek >= 1 && fallbackWeek <= totalWk else { continue }
                guard !isRecoveryWeek(fallbackWeek) else { continue }
                let fallbackTemplates = allSessionTemplates.filter {
                    $0.programId == inst.programId && $0.week == fallbackWeek
                }
                let fallbackTypes = Set(fallbackTemplates.map { $0.sessionType })
                // Check if this fallback week has the missing session types
                if missingSessionTypes.allSatisfy({ fallbackTypes.contains($0) }) {
                    // Add the missing session templates from the fallback week
                    for missing in missingSessionTypes {
                        let fallbackForSession = fallbackTemplates.filter { $0.sessionType == missing }
                        templates.append(contentsOf: fallbackForSession)
                    }
                    break
                }
            }
        }

        // Cross-program fallback: any session type that's active for this week
        // (base rotation + imported sessions via schedule overrides) but still
        // missing from templates gets borrowed from another program that defines
        // it. Iterating active sessions instead of just base rotation ensures
        // imported sessions show their exercises in the Weeks tab.
        let active = activeSessionsForWeek(
            programId: inst.programId, instance: inst, profile: profile,
            week: week, templates: programTemplates)
        let typesAfterInProgram = Set(templates.map { $0.sessionType })
        let goal = profile?.goal ?? .hypertrophy
        for st in active where !typesAfterInProgram.contains(st) {
            let foreign = lookupAdaptedTemplates(
                programId: inst.programId, week: week, sessionType: st,
                allTemplates: allSessionTemplates,
                instance: inst, totalWeeks: totalWeeks,
                blockLength: inst.blockLength, goal: goal)
            templates.append(contentsOf: foreign)
        }

        // Deduplicate: keep latest version per slotId
        var best: [String: ProgramSessionTemplate] = [:]
        for t in templates {
            let key = "\(t.sessionTypeRaw)_\(t.slotId)"
            if let existing = best[key] {
                if t.programVersion >= existing.programVersion { best[key] = t }
            } else {
                best[key] = t
            }
        }
        return Dictionary(grouping: Array(best.values)) { $0.sessionType }
    }

    private func estimateSessionSets(sessionMuscles: String) -> Int {
        let muscles = sessionMuscles.components(separatedBy: ", ")
        guard let p = profile else { return 12 }
        var total = 0
        for m in muscles {
            let target = ProgramGenerator.resolveWeeklySetTarget(
                muscle: m, week: 1, blockType: .accumulation,
                muscleTier: p.muscleTiers[m] ?? .neutral,
                experience: p.experience, calorieContext: p.calorieContext, calibration: nil)
            let freq = max(1, programSplit().filter { $0.1.contains(m) }.count)
            total += target / freq
        }
        return min(total, 24)
    }
}

// ═══════════════════════════════════════════
// EXERCISE LIBRARY BROWSER (for Program tab)
// ═══════════════════════════════════════════

struct ExerciseLibraryBrowser: View {
    let exercises: [Exercise]
    @Environment(\.modelContext) private var modelContext
    @State private var selectedMuscle: String? = nil
    @State private var searchText = ""
    @State private var expandedKey: String? = nil
    @State private var showCreateCustom = false
    @State private var editTarget: Exercise? = nil
    @State private var deleteTarget: Exercise? = nil
    @State private var showDeleteConfirm = false

    private let muscles = ExerciseDictionary.trackingMuscles

    private var filtered: [Exercise] {
        var result = exercises.sorted { $0.displayName < $1.displayName }
        if let m = selectedMuscle {
            result = result.filter { ex in
                let priNorm = ex.musclesPrimary.compactMap { ExerciseDictionary.normalizeMuscle($0) }
                let def = ExerciseDictionary.all[ex.exerciseKey]
                let addlNorm = (def?.additionalFilterMuscles ?? []).compactMap { ExerciseDictionary.normalizeMuscle($0) }
                return priNorm.contains(m) || addlNorm.contains(m)
            }
        }
        if !searchText.isEmpty {
            result = result.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 10) {
            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(.appTextDim)
                TextField("Search exercises...", text: $searchText)
                    .font(.system(size: 14)).foregroundColor(.appTextPrimary)
            }
            .padding(10).background(Color.appSurface2).cornerRadius(8)

            // Muscle chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chipButton("All", selected: selectedMuscle == nil) { selectedMuscle = nil }
                    ForEach(muscles, id: \.self) { m in
                        chipButton(m, selected: selectedMuscle == m) { selectedMuscle = selectedMuscle == m ? nil : m }
                    }
                }
            }

            // Create custom + count
            HStack {
                Text("\(filtered.count) exercises").font(.system(size: 11)).foregroundColor(.appTextDim)
                Spacer()
                Button(action: { showCreateCustom = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 12))
                        Text("Create Custom").font(.system(size: 11, weight: .bold))
                    }.foregroundColor(.appGreen)
                }.buttonStyle(.plain)
            }

            ForEach(filtered) { ex in
                let def = ExerciseDictionary.all[ex.exerciseKey]
                let isExpanded = expandedKey == ex.exerciseKey

                VStack(alignment: .leading, spacing: 0) {
                    Button { withAnimation(.easeInOut(duration: 0.15)) { expandedKey = isExpanded ? nil : ex.exerciseKey } } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(ex.displayName).font(.system(size: 13, weight: .bold)).foregroundColor(.appTextPrimary).lineLimit(1)
                                Text(ex.musclesPrimary.prefix(2).joined(separator: " · "))
                                    .font(.system(size: 11)).foregroundColor(.appTextDim)
                            }
                            Spacer()
                            if ex.isCompound {
                                Text("Compound").font(.system(size: 9, weight: .bold)).foregroundColor(.appBlue)
                                    .padding(.horizontal, 5).padding(.vertical, 2).background(Color.appBlue.opacity(0.1)).cornerRadius(3)
                            }
                            if ex.isCustom {
                                Text("Custom").font(.system(size: 9, weight: .bold)).foregroundColor(.appGold)
                                    .padding(.horizontal, 5).padding(.vertical, 2).background(Color.appGold.opacity(0.1)).cornerRadius(3)
                            }
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9)).foregroundColor(.appTextDim)
                        }
                        .padding(10)
                    }.buttonStyle(.plain)

                    if isExpanded {
                        VStack(alignment: .leading, spacing: 6) {
                            Divider().background(Color.appBorder)
                            // Dictionary-backed details (built-in exercises)
                            if let d = def {
                                detailRow("Equipment", value: d.equipment.rawValue.capitalized)
                                detailRow("Stretch", value: d.stretchPosition.rawValue.capitalized)
                                if !d.head.isEmpty { detailRow("Targets", value: d.head.capitalized) }
                                if !d.generatorPattern.isEmpty { detailRow("Pattern", value: d.generatorPattern.replacingOccurrences(of: "_", with: " ").capitalized) }
                                if d.isAnchorableAsTier1 { detailRow("Tier", value: "T1 Anchor — strength tracker") }
                                if !d.secondaryMuscles.isEmpty {
                                    detailRow("Secondary", value: d.secondaryMuscles.map { "\($0.muscle) (\(Int($0.weight * 100))%)" }.joined(separator: ", "))
                                }
                            } else {
                                // Custom exercise — pull details from the Exercise record
                                detailRow("Equipment", value: ex.equipmentRaw.capitalized)
                                if !ex.musclesSecondary.isEmpty {
                                    detailRow("Secondary", value: ex.musclesSecondary.joined(separator: ", "))
                                }
                            }
                            // Edit / delete affordance for custom exercises
                            if ex.isCustom {
                                HStack(spacing: 8) {
                                    Button {
                                        editTarget = ex
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "pencil").font(.system(size: 11, weight: .bold))
                                            Text("Edit").font(.system(size: 11, weight: .bold))
                                        }
                                        .foregroundColor(.appBlue)
                                        .padding(.horizontal, 10).padding(.vertical, 6)
                                        .background(Color.appBlue.opacity(0.10)).cornerRadius(6)
                                    }.buttonStyle(.plain)

                                    Button {
                                        deleteTarget = ex
                                        showDeleteConfirm = true
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "trash").font(.system(size: 11, weight: .bold))
                                            Text("Delete").font(.system(size: 11, weight: .bold))
                                        }
                                        .foregroundColor(.appRed)
                                        .padding(.horizontal, 10).padding(.vertical, 6)
                                        .background(Color.appRed.opacity(0.08)).cornerRadius(6)
                                    }.buttonStyle(.plain)

                                    Spacer()
                                }
                                .padding(.top, 4)
                            }
                        }
                        .padding(.horizontal, 10).padding(.bottom, 10)
                    }
                }
                .background(Color.appSurface).cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorder, lineWidth: 1))
            }
        }
        .sheet(isPresented: $showCreateCustom) {
            AddExerciseView()
        }
        .sheet(item: $editTarget) { ex in
            AddExerciseView(editing: ex)
        }
        .alert("Delete Exercise?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let ex = deleteTarget {
                    modelContext.delete(ex)
                    try? modelContext.save()
                    deleteTarget = nil
                }
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("This will remove \"\(deleteTarget?.displayName ?? "")\" from your library. Your workout history will be preserved.")
        }
    }

    private func chipButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: selected ? .black : .medium))
                .foregroundColor(selected ? .white : .appTextSecondary)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(selected ? Color.appRed : Color.appSurface2).cornerRadius(6)
        }.buttonStyle(.plain)
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 10, weight: .bold)).foregroundColor(.appTextDim).frame(width: 70, alignment: .leading)
            Text(value).font(.system(size: 11)).foregroundColor(.appTextSecondary)
            Spacer()
        }
    }
}

// ═══════════════════════════════════════════
// BLOCK CONFIGURATION CARD
// Extracted as standalone struct to avoid
// type-checker issues with complex closures.
// ═══════════════════════════════════════════

struct BlockConfigCard: View {
    let inst: UserProgramInstance
    let goal: GoalType
    let totalWeeks: Int
    let onTapBlock: (Int) -> Void   // passes block index in timeline
    let modelContext: ModelContext
    /// Both periodization flags passed from parent so this card honors the
    /// same toggles (Continuous Training + Skip Deloads) as the rest of
    /// the Program tab.
    var usesPeriodization: Bool = true
    var skipDeloads: Bool = false

    private var isHyp: Bool { goal == .hypertrophy || goal == .recomp }
    /// Computed block info for the current week — single source of truth for
    /// what phase/block/week-in-block the user is actually in.
    private var info: ComputedBlockInfo {
        ComputedBlockInfo.compute(
            forWeek: inst.currentWeek,
            programId: inst.programId,
            blockLength: inst.blockLength,
            totalWeeks: totalWeeks,
            goal: goal,
            instance: inst,
            usesPeriodization: usesPeriodization,
            skipDeloads: skipDeloads
        )
    }
    private var isDeloadBlock: Bool { info.isDeloadWeek }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TRAINING BLOCK").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(2)

            // Current block status with adjustable controls
            HStack(spacing: 0) {
                blockWeekControl.frame(maxWidth: .infinity)
                Divider().frame(height: 40).padding(.horizontal, 4)
                blockLengthControl.frame(maxWidth: .infinity)
                Divider().frame(height: 40).padding(.horizontal, 4)
                blockNumberDisplay.frame(maxWidth: .infinity)
            }
            .padding(.vertical, 12).padding(.horizontal, 8)
            .background(Color.appSurface2).cornerRadius(8)

            // What's ahead timeline
            Text("WHAT'S AHEAD").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim).kerning(1)

            ForEach(0..<7, id: \.self) { i in
                let entry = timelineEntry(at: i)
                Button { onTapBlock(i) } label: {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(entry.color)
                            .frame(width: 4, height: entry.isCurrent ? 32 : 24)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(entry.name).font(.system(size: 12, weight: entry.isCurrent ? .black : .bold))
                                    .foregroundColor(entry.isCurrent ? .appTextPrimary : .appTextSecondary)
                                if entry.isCurrent {
                                    Text("NOW").font(.system(size: 8, weight: .black)).foregroundColor(.appRed).kerning(1)
                                        .padding(.horizontal, 4).padding(.vertical, 1).background(Color.appRed.opacity(0.1)).cornerRadius(3)
                                }
                                Text("\(entry.weeks) wk\(entry.weeks == 1 ? "" : "s")")
                                    .font(.system(size: 9, weight: .medium)).foregroundColor(.appTextDim)
                            }
                            Text(entry.detail).font(.system(size: 10)).foregroundColor(.appTextDim)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 9)).foregroundColor(.appTextDim)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14).background(Color.appSurface).cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
    }

    // ── Controls ──

    /// Navigates the program week (microcycleIndex) — not just within-block.
    /// Lets the user step forward into recovery/growth weeks instead of
    /// being capped at the current block's length.
    private var blockWeekControl: some View {
        VStack(spacing: 6) {
            Text("WEEK").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim)
            Text("\(info.weekInBlock) / \(info.blockTrainingWeeks)")
                .font(.system(size: 18, weight: .black, design: .rounded)).foregroundColor(.appRed)
                .lineLimit(1).minimumScaleFactor(0.6)
            HStack(spacing: 10) {
                Button {
                    if inst.microcycleIndex > 0 { inst.microcycleIndex -= 1; save() }
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold)).foregroundColor(.appTextDim)
                        .frame(width: 36, height: 28).background(Color.appBG).cornerRadius(6)
                }.buttonStyle(.plain)
                Button {
                    if inst.currentWeek < totalWeeks { inst.microcycleIndex += 1; save() }
                } label: {
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundColor(.appTextDim)
                        .frame(width: 36, height: 28).background(Color.appBG).cornerRadius(6)
                }.buttonStyle(.plain)
            }
        }
    }

    /// True for built-in seeded programs whose deload weeks are hardcoded
    /// (Powerbuilding, PPL, Strength, Beginner, Athletic, Minimalist, Bahri).
    /// For these, blockLength doesn't drive the structure — the seeded
    /// templates already define which weeks are training vs deload.
    private var isSeededProgram: Bool {
        let id = inst.programId
        return id >= 1 && id <= 10 && !inst.isGenerated
    }

    private var blockLengthControl: some View {
        VStack(spacing: 6) {
            Text("LENGTH").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim)
            // Display the COMPUTED training-week count for the current block —
            // matches what the user sees as "Wk X / N" everywhere else.
            Text("\(info.blockTrainingWeeks) wk\(info.blockTrainingWeeks == 1 ? "" : "s")")
                .font(.system(size: 18, weight: .black, design: .rounded)).foregroundColor(.appBlue)
                .lineLimit(1).minimumScaleFactor(0.6)
            if isSeededProgram {
                Text("Set by program")
                    .font(.system(size: 9, weight: .medium)).foregroundColor(.appTextDim)
                    .padding(.top, 2)
            } else {
                HStack(spacing: 10) {
                    Button {
                        if inst.blockLength > 1 { inst.blockLength -= 1; save() }
                    } label: {
                        Image(systemName: "minus").font(.system(size: 13, weight: .bold)).foregroundColor(.appBlue)
                            .frame(width: 36, height: 28).background(Color.appBlue.opacity(0.06)).cornerRadius(6)
                    }.buttonStyle(.plain)
                    Button {
                        if inst.blockLength < 12 { inst.blockLength += 1; save() }
                    } label: {
                        Image(systemName: "plus").font(.system(size: 13, weight: .bold)).foregroundColor(.appBlue)
                            .frame(width: 36, height: 28).background(Color.appBlue.opacity(0.06)).cornerRadius(6)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var blockNumberDisplay: some View {
        VStack(spacing: 4) {
            Text("BLOCK #").font(.system(size: 8, weight: .bold)).foregroundColor(.appTextDim)
            Text("\(info.blockNumber)")
                .font(.system(size: 16, weight: .black, design: .rounded)).foregroundColor(.appGreen)
        }
    }

    // ── Timeline ──
    /// Walk forward week-by-week from currentWeek and group runs into blocks.
    /// Each block in the timeline corresponds to a contiguous run of training
    /// weeks (or a single deload). Shown for the current block + next 6 blocks.

    private func timelineEntry(at index: Int) -> (name: String, detail: String, color: Color, isCurrent: Bool, weeks: Int) {
        let blocks = upcomingBlocks(maxBlocks: 7)
        guard index < blocks.count else {
            return ("—", "", .appTextDim, false, 0)
        }
        let b = blocks[index]
        let detail: String
        if index == 0 {
            detail = "Wk \(info.weekInBlock)/\(b.weeks) · \(volumeDesc(b.type))"
        } else {
            detail = volumeDesc(b.type)
        }
        return (blockName(b.type), detail, blockColor(b.type), b.isCurrent, b.weeks)
    }

    private func upcomingBlocks(maxBlocks: Int) -> [(type: BlockType, weeks: Int, isCurrent: Bool)] {
        var result: [(BlockType, Int, Bool)] = []
        var w = inst.currentWeek
        var current = true
        while result.count < maxBlocks && w <= totalWeeks {
            let bi = ComputedBlockInfo.compute(
                forWeek: w, programId: inst.programId,
                blockLength: inst.blockLength, totalWeeks: totalWeeks, goal: goal,
                instance: inst,
                usesPeriodization: usesPeriodization,
                skipDeloads: skipDeloads)
            if bi.isDeloadWeek {
                result.append((.deload, 1, current))
                w += 1
            } else {
                let weeksRemaining = bi.blockTrainingWeeks - bi.weekInBlock + 1
                result.append((bi.blockType, bi.blockTrainingWeeks, current))
                w += weeksRemaining
            }
            current = false
        }
        return result
    }

    private func blockName(_ bt: BlockType) -> String {
        switch (isHyp, bt) {
        case (true, .accumulation):    return "Training Block"
        case (true, .reaccumulation):  return "Growth Phase"
        case (true, .deload):          return "Recovery"
        case (true, _):                return "Training Block"
        case (false, _):               return bt.rawValue.capitalized
        }
    }

    private func blockColor(_ bt: BlockType) -> Color {
        switch bt {
        case .accumulation:    return .appGreen
        case .reaccumulation:  return .appGold
        case .intensification: return .appOrange
        case .peak:            return .appRed
        case .deload:          return .appBlue
        }
    }

    private func volumeDesc(_ bt: BlockType) -> String {
        switch bt {
        case .accumulation:    return "Standard volume"
        case .reaccumulation:  return "+15% volume"
        case .intensification: return "Lower volume, heavier"
        case .peak:            return "Minimal volume, max weight"
        case .deload:          return "Light recovery"
        }
    }

    private func save() { try? modelContext.save() }
}

// ═══════════════════════════════════════════
// STRENGTH GOAL EDITOR (tap to edit/remove)
// ═══════════════════════════════════════════

struct StrengthGoalEditorSheet: View {
    let goal: StrengthGoal
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var targetWeight: String = ""
    @State private var showRemoveConfirm = false

    private func editorPhaseColor(_ phase: StrengthGoalPhase) -> Color {
        switch phase {
        case .building: return .appGreen
        case .intensifying: return .appOrange
        case .peaking: return .appRed
        case .testing: return .appGold
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 3).fill(Color.appBorder).frame(width: 36, height: 4).padding(.top, 12)

                // Header
                HStack(spacing: 10) {
                    Image(systemName: "target").font(.system(size: 18)).foregroundColor(.appRed)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(goal.displayName).font(.system(size: 18, weight: .black)).foregroundColor(.appTextPrimary)
                        Text("Strength Goal").font(.system(size: 11)).foregroundColor(.appTextDim)
                    }
                    Spacer()
                    Text("\(Int(goal.targetWeight)) lb")
                        .font(.system(size: 22, weight: .black, design: .rounded)).foregroundColor(.appGold)
                }

                // ── Current Phase ──
                VStack(alignment: .leading, spacing: 8) {
                    Text("CURRENT PHASE").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim).kerning(1)
                    HStack(spacing: 10) {
                        Circle().fill(editorPhaseColor(goal.phase)).frame(width: 12, height: 12)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(goal.phase.displayName).font(.system(size: 16, weight: .black)).foregroundColor(.appTextPrimary)
                            Text("Week \(goal.phaseWeek) of \(goal.currentPhaseLength)")
                                .font(.system(size: 12)).foregroundColor(.appTextDim)
                        }
                        Spacer()
                        let rr = goal.phase.repRange
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(goal.phase.targetSets)×\(rr.low)-\(rr.high)")
                                .font(.system(size: 14, weight: .black, design: .monospaced)).foregroundColor(.appTextPrimary)
                            Text("RPE \(String(format: "%.0f", goal.phase.targetRPE))")
                                .font(.system(size: 10, weight: .bold)).foregroundColor(.appTextDim)
                        }
                    }
                }
                .padding(12).background(Color.appSurface).cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))

                // ── Week-by-Week Projection ──
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("WEEK-BY-WEEK PLAN").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim).kerning(1)
                        Spacer()
                        Text("\(Int(goal.startE1RM))lb → \(Int(goal.targetWeight))lb")
                            .font(.system(size: 10, weight: .bold)).foregroundColor(.appGold)
                    }

                    let projection = goal.weekByWeekProjection(useMetric: false)
                    ForEach(Array(projection.enumerated()), id: \.offset) { _, entry in
                        let isCurrent = entry.phase == goal.phase &&
                            (projection.prefix(while: { $0.phase != goal.phase }).count + goal.phaseWeek) == entry.week
                        let isPast = entry.week < (projection.prefix(while: { $0.phase != goal.phase }).count + goal.phaseWeek)

                        HStack(spacing: 8) {
                            Text("W\(entry.week)").font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(isCurrent ? .appRed : .appTextDim)
                                .frame(width: 22)
                            RoundedRectangle(cornerRadius: 2).fill(editorPhaseColor(entry.phase))
                                .frame(width: 3, height: 20)
                            Text("\(Int(entry.weight))lb").font(.system(size: 12, weight: .bold))
                                .foregroundColor(isPast ? .appTextDim : .appTextPrimary)
                                .frame(width: 50, alignment: .leading)
                            Text("\(entry.sets)×\(entry.repsLow)-\(entry.repsHigh)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.appTextSecondary)
                            Spacer()
                            if isCurrent {
                                Text("NOW").font(.system(size: 7, weight: .black)).foregroundColor(.appRed)
                                    .padding(.horizontal, 4).padding(.vertical, 2)
                                    .background(Color.appRed.opacity(0.1)).cornerRadius(3)
                            }
                        }
                        .padding(.vertical, 2)
                        .opacity(isPast ? 0.5 : 1.0)
                    }

                    Text("Weights increase as your e1RM grows. Testing phase targets your \(Int(goal.targetWeight))lb goal directly.")
                        .font(.system(size: 9)).foregroundColor(.appTextDim).padding(.top, 4)
                }
                .padding(12).background(Color.appSurface).cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))

                // ── How This Affects Your Program ──
                VStack(alignment: .leading, spacing: 6) {
                    Text("HOW THIS AFFECTS YOUR PROGRAM").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim).kerning(1)
                    VStack(alignment: .leading, spacing: 8) {
                        effectRow(icon: "dumbbell.fill", text: "\(goal.displayName) switches to \(goal.phase.targetSets)×\(goal.phase.repRange.low)-\(goal.phase.repRange.high) reps at RPE \(String(format: "%.0f", goal.phase.targetRPE))")
                        effectRow(icon: "arrow.triangle.2.circlepath", text: "Rep ranges and intensity change automatically as phases advance")
                        effectRow(icon: "figure.strengthtraining.traditional", text: "All other exercises remain at their normal hypertrophy rep ranges")
                        effectRow(icon: "timer", text: "Rest periods extended to 3+ minutes for strength sets")
                    }
                }
                .padding(12).background(Color.appSurface).cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))

                // ── Edit Target Weight ──
                VStack(alignment: .leading, spacing: 6) {
                    Text("TARGET WEIGHT").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim).kerning(1)
                    HStack(spacing: 8) {
                        TextField("Target", text: $targetWeight)
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(.appGold)
                            .keyboardType(.numberPad)
                            .padding(12).background(Color.appSurface2).cornerRadius(10)
                        Text("lbs").font(.system(size: 14, weight: .bold)).foregroundColor(.appTextDim)
                    }
                }

                // Save
                Button {
                    if let tw = Double(targetWeight), tw > goal.startE1RM {
                        goal.targetWeight = tw
                        try? modelContext.save()
                    }
                    dismiss()
                } label: {
                    Text("SAVE CHANGES")
                        .font(.system(size: 14, weight: .black)).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Color.appRed).cornerRadius(12)
                }.buttonStyle(.plain)

                // Remove
                Button { showRemoveConfirm = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash").font(.system(size: 12))
                        Text("Remove Goal").font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(.appRed)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Color.appRed.opacity(0.06)).cornerRadius(10)
                }.buttonStyle(.plain)
            }
            .padding(20).padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.appBG)
        .numberPadDoneButton()
        .onAppear { targetWeight = "\(Int(goal.targetWeight))" }
        .confirmationDialog("Remove Strength Goal?", isPresented: $showRemoveConfirm) {
            Button("Remove", role: .destructive) {
                goal.isActive = false
                try? modelContext.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will stop the strength-focused programming for \(goal.displayName).")
        }
    }

    private func effectRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).font(.system(size: 10)).foregroundColor(.appBlue)
                .frame(width: 16, alignment: .center).padding(.top, 2)
            Text(text).font(.system(size: 11)).foregroundColor(.appTextSecondary)
        }
    }
}

extension StrengthGoal: Identifiable {
    var id: String { exerciseKey }
}
