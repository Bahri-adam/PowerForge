import SwiftUI
import SwiftData

// ═══════════════════════════════════════════
// VOLUME ADJUSTER SHEET
// Tap a muscle bar in Home or Program tab → opens this sheet.
// Two flows:
//   • Add a new exercise (creates SessionOverride with isAddition: true)
//   • Adjust set count on existing exercises ± (creates SessionOverride with setCountDelta)
// Scope picker at top controls week range for any change made in this session.
// ═══════════════════════════════════════════

struct VolumeAdjusterSheet: View {
    let muscle: String
    let instance: UserProgramInstance
    let profile: UserProfile?
    let week: Int

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allTemplates: [ProgramSessionTemplate]
    @Query private var allExercises: [Exercise]
    @Query private var activeWorkouts: [ActiveWorkout]
    @Query private var allProgramTemplates: [ProgramTemplate]

    @State private var selectedSession: SessionType? = nil
    @State private var selectedExerciseKey: String? = nil
    @State private var setsToAdd: Int = 2
    @State private var step: Int = 1  // 1 = overview, 2 = exercise picker, 3 = adjust existing

    @State private var scopeMode: ScopeMode = .future
    @State private var rangeStart: Int = 1
    @State private var rangeEnd: Int = 24
    @State private var showingTargetEditor: Bool = false

    enum ScopeMode: String, CaseIterable, Identifiable {
        case thisWeek, thisBlock, future, range
        var id: String { rawValue }
        var label: String {
            switch self {
            case .thisWeek:  return "This week"
            case .thisBlock: return "This block"
            case .future:    return "All future"
            case .range:     return "Range"
            }
        }
    }

    // ── Scope resolution ───────────────────────────────────────────────────

    /// Resolves the scope picker's current selection into concrete (scope, fromWeek, endWeek)
    /// values for SessionOverride creation. Past-week protection: clamps fromWeek >= week.
    private var resolvedScope: (scope: OverrideScope, from: Int, end: Int?) {
        switch scopeMode {
        case .thisWeek:
            return (.single, week, nil)
        case .thisBlock:
            let blockStart = max(1, week - max(0, instance.blockWeek - 1))
            let blockEnd = blockStart + max(1, instance.blockLength) - 1
            return (.range, max(week, blockStart), max(week, blockEnd))
        case .future:
            return (.future, week, nil)
        case .range:
            let from = max(week, rangeStart)
            let end = max(from, rangeEnd)
            return (.range, from, end)
        }
    }

    private var hasActiveWorkout: Bool {
        activeWorkouts.contains { !$0.isComplete && $0.programInstance === instance }
    }

    // ── Volume math ────────────────────────────────────────────────────────

    /// Current programmed sets per session for this muscle, for the current week.
    /// Filters out sessions that have been removed via Configure Program.
    private var sessionsWithMuscle: [(session: SessionType, currentSets: Int)] {
        let active = activeSessionsForWeek(
            programId: instance.programId, instance: instance, profile: profile,
            week: week, templates: allProgramTemplates)
        var result: [(SessionType, Int)] = []
        for st in active {
            let sets = setsForMuscle(in: st, week: week)
            if sets > 0 { result.append((st, sets)) }
        }
        return result.sorted { $0.1 > $1.1 }
    }

    /// Effective sets in a session for this muscle, including deltas and additions
    private func setsForMuscle(in session: SessionType, week: Int) -> Int {
        let templates = allTemplates.filter {
            $0.programId == instance.programId && $0.week == week && $0.sessionType == session
        }
        var count = 0
        for t in templates {
            let key = resolveExerciseKey(slotId: t.slotId, originalKey: t.exerciseKey,
                                         overrides: instance.overrides, week: week)
            guard exerciseTargetsMuscle(key: key) else { continue }
            let delta = totalDelta(forSlot: t.slotId, session: session, week: week)
            count += max(0, t.targetSets + delta)
        }
        for ov in instance.overrides where ov.isAddition && ov.sessionType == session && ov.appliesTo(week: week) {
            if exerciseTargetsMuscle(key: ov.replacementExerciseKey) { count += ov.addedSets }
        }
        return count
    }

    /// Sum of all setCountDelta overrides applying to a given slot/session/week
    private func totalDelta(forSlot slotId: String, session: SessionType, week: Int) -> Int {
        instance.overrides
            .filter { ov in
                ov.targetSlotId == slotId &&
                ov.sessionType == session &&
                ov.setCountDelta != 0 &&
                !ov.isAddition &&
                ov.appliesTo(week: week)
            }
            .reduce(0) { $0 + $1.setCountDelta }
    }

    private func exerciseTargetsMuscle(key: String) -> Bool {
        if let def = ExerciseDictionary.all[key] {
            for pm in def.primaryMuscles {
                if ExerciseDictionary.normalizeMuscle(pm) == muscle { return true }
            }
        }
        if let ex = allExercises.first(where: { $0.exerciseKey == key }) {
            return ex.musclesPrimary.contains { ExerciseDictionary.normalizeMuscle($0) == muscle }
        }
        return false
    }

    private var totalCurrentSets: Int {
        sessionsWithMuscle.reduce(0) { $0 + $1.currentSets }
    }

    private var targetRange: (mev: Int, mavLow: Int, mavHigh: Int, mrv: Int) {
        let tier = profile?.muscleTiers[muscle] ?? (profile?.priorityMuscles.contains(muscle) == true ? .priority : .neutral)
        let exp = profile?.experience ?? .intermediate
        let mev = VolumeLandmark.effectiveMEV(muscle: muscle, experience: exp, tier: tier)
        let mrv = VolumeLandmark.effectiveMRV(muscle: muscle, experience: exp, tier: tier)
        let base = VolumeLandmark.defaults[muscle] ?? VolumeLandmark(mev: 4, mavLow: 8, mavHigh: 12, mrv: 18)
        let scaled = base.scaled(by: tier)
        // User's custom target replaces mavHigh if set
        let userTarget = profile?.effectiveTarget(for: muscle) ?? scaled.mavHigh
        let mavLow = min(scaled.mavLow, max(mev, userTarget - 4))
        return (mev, mavLow, userTarget, max(mrv, userTarget))
    }

    private var zoneColor: Color {
        let r = targetRange
        let cur = totalCurrentSets
        if cur < r.mev { return .appRed }
        if cur < r.mavLow { return .appYellow }
        if cur <= r.mavHigh { return .appGreen }
        if cur <= r.mrv { return .appYellow }
        return .appOrange
    }

    private var zoneLabel: String {
        let r = targetRange
        let cur = totalCurrentSets
        if cur < r.mev { return "Under target" }
        if cur < r.mavLow { return "Building" }
        if cur <= r.mavHigh { return "On target" }
        if cur <= r.mrv { return "Above target" }
        return "Over MRV"
    }

    // ── Suggested exercises for additions ───────────────────────────────────

    private var suggestedExercises: [Exercise] {
        let candidates = allExercises.filter { ex in
            ex.musclesPrimary.contains { ExerciseDictionary.normalizeMuscle($0) == muscle }
        }
        let inRotation: Set<String> = {
            var keys: Set<String> = []
            for (st, _) in sessionsWithMuscle {
                let templates = allTemplates.filter {
                    $0.programId == instance.programId && $0.week == week && $0.sessionType == st
                }
                for t in templates { keys.insert(t.exerciseKey) }
            }
            return keys
        }()
        return candidates.sorted { a, b in
            let aIn = inRotation.contains(a.exerciseKey)
            let bIn = inRotation.contains(b.exerciseKey)
            if aIn != bIn { return !aIn }
            if a.isCompound != b.isCompound { return !a.isCompound }
            return a.displayName < b.displayName
        }
    }

    // ── Body ────────────────────────────────────────────────────────────────

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBG.ignoresSafeArea()
                if step == 1 { overviewStep }
                else if step == 2 { pickerStep }
                else { adjustStep }
            }
            .navigationTitle(muscle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if step == 1 {
                        Button("Cancel") { dismiss() }.foregroundColor(.appTextSecondary)
                    } else {
                        Button("Back") { withAnimation { step = 1 } }.foregroundColor(.appTextSecondary)
                    }
                }
            }
        }
        .onAppear {
            if let p = profile, let custom = p.muscleTargetOverrides[muscle], custom > 0 {
                _ = custom // (read to avoid warnings; targetRange already uses it)
            }
            rangeStart = week
            rangeEnd = min(week + 4, instance.programDurationWeeks ?? 24)
        }
        .sheet(isPresented: $showingTargetEditor) {
            NumericInputSheet(
                title: muscle,
                subtitle: "Set your weekly target sets for \(muscle).",
                initialValue: targetRange.mavHigh,
                suggestionLow: targetRange.mev,
                suggestionHigh: targetRange.mrv,
                onSave: { value in
                    guard let p = profile else { return }
                    var overrides = p.muscleTargetOverrides
                    let autoDefault = autoDefaultTarget(for: muscle)
                    if value == autoDefault {
                        overrides.removeValue(forKey: muscle)
                    } else {
                        overrides[muscle] = max(0, value)
                    }
                    p.muscleTargetOverrides = overrides
                    try? modelContext.save()
                }
            )
            .presentationDetents([.medium])
        }
    }

    /// Auto-default target (tier-derived MAVHigh, scaled). Used to detect
    /// when the user has typed a value matching the default — in which case we
    /// clear the override rather than persist a redundant value.
    private func autoDefaultTarget(for muscle: String) -> Int {
        let tier = profile?.muscleTiers[muscle] ?? .neutral
        let base = VolumeLandmark.defaults[muscle] ?? VolumeLandmark(mev: 4, mavLow: 8, mavHigh: 12, mrv: 18)
        return Int(round(Double(base.mavHigh) * tier.multiplier))
    }

    // ── Step 1 — Overview + per-session list ───────────────────────────────

    private var overviewStep: some View {
        ScrollView {
            VStack(spacing: 16) {
                volumeHeader

                if hasActiveWorkout {
                    activeWorkoutWarning
                }

                scopePicker

                if scopeMode == .range { rangeStepper }

                if !sessionsWithMuscle.isEmpty {
                    perSessionList
                }

                activeOverridesList

                // If no work for this muscle exists, allow adding to any session
                if sessionsWithMuscle.isEmpty {
                    addToNewSessionList
                }
            }
            .padding(20)
        }
    }

    private var volumeHeader: some View {
        VStack(spacing: 12) {
            HStack {
                Text("WEEK \(week) VOLUME").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(1)
                Spacer()
                Text(zoneLabel).font(.system(size: 10, weight: .black)).foregroundColor(zoneColor).kerning(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(totalCurrentSets)")
                    .font(.system(size: 40, weight: .black, design: .rounded)).foregroundColor(zoneColor)
                Text("sets")
                    .font(.system(size: 13, weight: .medium)).foregroundColor(.appTextSecondary)
                Spacer()
                Button {
                    showingTargetEditor = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil").font(.system(size: 10, weight: .bold)).foregroundColor(.appBlue)
                        Text("target \(targetRange.mavHigh)")
                            .font(.system(size: 12, weight: .bold)).foregroundColor(.appBlue)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.appBlue.opacity(0.08)).cornerRadius(7)
                }.buttonStyle(.plain)
            }
            volumeBar
            HStack(spacing: 12) {
                legendDot(color: .appRed, label: "MEV \(targetRange.mev)")
                legendDot(color: .appGreen, label: "Target \(targetRange.mavHigh)")
                legendDot(color: .appOrange, label: "MRV \(targetRange.mrv)")
            }
        }
        .padding(16).background(Color.appSurface).cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
    }

    private var activeWorkoutWarning: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.appYellow)
            Text("Workout in progress — changes apply from your next session, not the active one.")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.appTextSecondary)
        }
        .padding(12)
        .background(Color.appYellow.opacity(0.08))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appYellow.opacity(0.3), lineWidth: 1))
    }

    private var scopePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("APPLY CHANGES TO").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(1)
            HStack(spacing: 6) {
                ForEach(ScopeMode.allCases) { mode in
                    Button { scopeMode = mode } label: {
                        Text(mode.label)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(scopeMode == mode ? .white : .appTextSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(scopeMode == mode ? Color.appRed : Color.appSurface)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .stroke(scopeMode == mode ? Color.appRed : Color.appBorder, lineWidth: 1))
                    }.buttonStyle(.plain)
                }
            }
            Text(scopeDescription)
                .font(.system(size: 10))
                .foregroundColor(.appTextDim)
                .padding(.horizontal, 4)
        }
    }

    private var scopeDescription: String {
        let r = resolvedScope
        switch r.scope {
        case .single: return "Only week \(r.from). Past weeks are never modified."
        case .future:  return "Weeks \(r.from)–\(instance.programDurationWeeks ?? 24)."
        case .range:   return "Weeks \(r.from)–\(r.end ?? r.from)."
        }
    }

    private var rangeStepper: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Text("From").font(.system(size: 11)).foregroundColor(.appTextDim)
                Stepper(value: $rangeStart, in: week...(instance.programDurationWeeks ?? 24)) {
                    Text("Wk \(rangeStart)").font(.system(size: 13, weight: .bold)).foregroundColor(.appTextPrimary)
                }
                .labelsHidden()
                Text("Wk \(rangeStart)").font(.system(size: 13, weight: .bold)).foregroundColor(.appTextPrimary)
            }
            HStack(spacing: 4) {
                Text("To").font(.system(size: 11)).foregroundColor(.appTextDim)
                Stepper(value: $rangeEnd, in: rangeStart...(instance.programDurationWeeks ?? 24)) {
                    Text("Wk \(rangeEnd)").font(.system(size: 13, weight: .bold)).foregroundColor(.appTextPrimary)
                }
                .labelsHidden()
                Text("Wk \(rangeEnd)").font(.system(size: 13, weight: .bold)).foregroundColor(.appTextPrimary)
            }
        }
        .padding(12)
        .background(Color.appSurface)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))
    }

    private var perSessionList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CURRENT DISTRIBUTION").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(1)
            ForEach(sessionsWithMuscle, id: \.session) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.session.shortLabel).font(.system(size: 14, weight: .bold)).foregroundColor(.appTextPrimary)
                        Text("\(item.currentSets) sets of \(muscle.lowercased())")
                            .font(.system(size: 11)).foregroundColor(.appTextDim)
                    }
                    Spacer()
                    Button {
                        selectedSession = item.session
                        withAnimation { step = 3 }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "slider.horizontal.3").font(.system(size: 10, weight: .bold))
                            Text("ADJUST").font(.system(size: 10, weight: .black)).kerning(0.5)
                        }
                        .foregroundColor(.appBlue)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Color.appBlue.opacity(0.08)).cornerRadius(7)
                    }.buttonStyle(.plain)
                    Button {
                        selectedSession = item.session
                        withAnimation { step = 2 }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                            Text("ADD").font(.system(size: 10, weight: .black)).kerning(0.5)
                        }
                        .foregroundColor(.appRed)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Color.appRed.opacity(0.08)).cornerRadius(7)
                    }.buttonStyle(.plain)
                }
                .padding(.vertical, 4)
                if item.session != sessionsWithMuscle.last?.session { Divider() }
            }
        }
        .padding(16).background(Color.appSurface).cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
    }

    private var activeOverridesList: some View {
        let muscleAdditions = instance.overrides.filter { ov in
            ov.isAddition && exerciseTargetsMuscle(key: ov.replacementExerciseKey) && ov.appliesTo(week: week)
        }
        let muscleDeltas = instance.overrides.filter { ov in
            !ov.isAddition && ov.setCountDelta != 0 && ov.appliesTo(week: week) &&
            slotTargetsMuscle(slotId: ov.targetSlotId, session: ov.sessionType, week: week)
        }
        return Group {
            if !muscleAdditions.isEmpty || !muscleDeltas.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("YOUR ADJUSTMENTS").font(.system(size: 10, weight: .black)).foregroundColor(.appBlue).kerning(1)
                    ForEach(muscleAdditions) { ov in
                        overrideRow(name: displayName(for: ov.replacementExerciseKey),
                                    detail: "+\(ov.addedSets) sets · \(ov.sessionType.shortLabel) · \(scopeShortLabel(for: ov))",
                                    ov: ov)
                    }
                    ForEach(muscleDeltas) { ov in
                        let prefix = ov.setCountDelta > 0 ? "+\(ov.setCountDelta)" : "\(ov.setCountDelta)"
                        overrideRow(name: slotDisplayName(slotId: ov.targetSlotId, session: ov.sessionType, week: week),
                                    detail: "\(prefix) sets · \(ov.sessionType.shortLabel) · \(scopeShortLabel(for: ov))",
                                    ov: ov)
                    }
                }
                .padding(16).background(Color.appBlue.opacity(0.04)).cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBlue.opacity(0.2), lineWidth: 1))
            }
        }
    }

    private func overrideRow(name: String, detail: String, ov: SessionOverride) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 13, weight: .bold)).foregroundColor(.appTextPrimary)
                Text(detail).font(.system(size: 11)).foregroundColor(.appTextDim)
            }
            Spacer()
            Button {
                modelContext.delete(ov)
                try? modelContext.save()
            } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundColor(.appTextDim)
            }.buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private var addToNewSessionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No \(muscle.lowercased()) work in your program this week. Add to a session:")
                .font(.system(size: 13)).foregroundColor(.appTextSecondary)
            let active = activeSessionsForWeek(
                programId: instance.programId, instance: instance, profile: profile,
                week: week, templates: allProgramTemplates)
            ForEach(Array(active), id: \.self) { st in
                Button {
                    selectedSession = st
                    withAnimation { step = 2 }
                } label: {
                    HStack {
                        Text(st.shortLabel).font(.system(size: 14, weight: .bold)).foregroundColor(.appTextPrimary)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 11)).foregroundColor(.appTextDim)
                    }
                    .padding(14).background(Color.appSurface).cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))
                }.buttonStyle(.plain)
            }
        }
    }

    // ── Step 2 — Exercise picker for ADDITION ──────────────────────────────

    private var pickerStep: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Text("HOW MANY SETS?").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(1)
                HStack(spacing: 10) {
                    ForEach([1, 2, 3, 4], id: \.self) { n in
                        Button {
                            setsToAdd = n
                        } label: {
                            VStack(spacing: 2) {
                                Text("+\(n)").font(.system(size: 22, weight: .black, design: .rounded))
                                    .foregroundColor(setsToAdd == n ? .white : .appTextSecondary)
                                Text("set\(n == 1 ? "" : "s")").font(.system(size: 9, weight: .bold))
                                    .foregroundColor(setsToAdd == n ? .white.opacity(0.8) : .appTextDim).kerning(0.5)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(setsToAdd == n ? Color.appRed : Color.appSurface).cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(setsToAdd == n ? Color.appRed : Color.appBorder, lineWidth: 1))
                        }.buttonStyle(.plain)
                    }
                }
            }
            .padding(16).background(Color.appSurface).cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
            .padding(.horizontal, 20).padding(.top, 16)

            ScrollView {
                LazyVStack(spacing: 8) {
                    Text("PICK AN EXERCISE")
                        .font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4).padding(.top, 8)
                    ForEach(suggestedExercises) { ex in
                        Button {
                            selectedExerciseKey = ex.exerciseKey
                            applyAddition(exercise: ex)
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ex.displayName).font(.system(size: 14, weight: .bold)).foregroundColor(.appTextPrimary)
                                    Text("\(ex.musclesPrimary.joined(separator: " · "))  ·  \(ex.equipmentRaw.capitalized)")
                                        .font(.system(size: 11)).foregroundColor(.appTextDim)
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill").font(.system(size: 18)).foregroundColor(.appRed)
                            }
                            .padding(12).background(Color.appSurface).cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 40)
            }
        }
    }

    // ── Step 3 — Adjust existing exercises ±  ──────────────────────────────

    private var adjustStep: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(selectedSession?.shortLabel.uppercased() ?? "SESSION")
                    .font(.system(size: 11, weight: .black)).foregroundColor(.appTextDim).kerning(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Tap − or + on each exercise. Changes use the scope set on the previous screen.")
                    .font(.system(size: 11)).foregroundColor(.appTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(adjustableSlots, id: \.slotId) { row in
                    adjustRow(row: row)
                }
            }
            .padding(20)
        }
    }

    /// Each adjustable row in step 3: a slot in the selected session that targets this muscle
    private struct AdjustableRow {
        let slotId: String
        let exerciseKey: String
        let displayName: String
        let baseSets: Int    // template's targetSets
        let currentSets: Int // template + any existing delta in scope
    }

    private var adjustableSlots: [AdjustableRow] {
        guard let session = selectedSession else { return [] }
        let templates = allTemplates.filter {
            $0.programId == instance.programId && $0.week == week && $0.sessionType == session
        }.sorted { $0.exerciseIndex < $1.exerciseIndex }

        return templates.compactMap { t in
            let key = resolveExerciseKey(slotId: t.slotId, originalKey: t.exerciseKey,
                                         overrides: instance.overrides, week: week)
            guard exerciseTargetsMuscle(key: key) else { return nil }
            let delta = totalDelta(forSlot: t.slotId, session: session, week: week)
            return AdjustableRow(
                slotId: t.slotId,
                exerciseKey: key,
                displayName: displayName(for: key),
                baseSets: t.targetSets,
                currentSets: max(0, t.targetSets + delta)
            )
        }
    }

    private func adjustRow(row: AdjustableRow) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.displayName).font(.system(size: 14, weight: .bold)).foregroundColor(.appTextPrimary)
                Text("Currently \(row.currentSets) set\(row.currentSets == 1 ? "" : "s")")
                    .font(.system(size: 11)).foregroundColor(.appTextDim)
            }
            Spacer()
            Button {
                applyDelta(row: row, delta: -1)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 26))
                    .foregroundColor(row.currentSets > 0 ? .appRed : .appTextDim)
            }
            .disabled(row.currentSets == 0)
            .buttonStyle(.plain)
            Text("\(row.currentSets)")
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundColor(.appTextPrimary)
                .frame(minWidth: 28)
            Button {
                applyDelta(row: row, delta: +1)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 26))
                    .foregroundColor(.appGreen)
            }.buttonStyle(.plain)
        }
        .padding(12).background(Color.appSurface).cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))
    }

    // ── Helpers ─────────────────────────────────────────────────────────────

    private var volumeBar: some View {
        let r = targetRange
        let maxScale = max(r.mrv + 4, totalCurrentSets + 2, r.mavHigh + 4)
        return GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.appSurface2).frame(height: 10).cornerRadius(5)
                Rectangle().fill(Color.appGreen.opacity(0.15))
                    .frame(width: w * CGFloat(max(0, r.mavHigh - r.mavLow)) / CGFloat(maxScale), height: 10)
                    .offset(x: w * CGFloat(r.mavLow) / CGFloat(maxScale))
                    .cornerRadius(2)
                Rectangle().fill(zoneColor)
                    .frame(width: w * CGFloat(totalCurrentSets) / CGFloat(maxScale), height: 10)
                    .cornerRadius(5)
                Rectangle().fill(Color.appBorder).frame(width: 1, height: 14)
                    .offset(x: w * CGFloat(r.mev) / CGFloat(maxScale), y: -2)
                Rectangle().fill(Color.appGreen).frame(width: 1, height: 14)
                    .offset(x: w * CGFloat(r.mavHigh) / CGFloat(maxScale), y: -2)
                Rectangle().fill(Color.appOrange).frame(width: 1, height: 14)
                    .offset(x: w * CGFloat(r.mrv) / CGFloat(maxScale), y: -2)
            }
        }
        .frame(height: 14)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.system(size: 10, weight: .medium)).foregroundColor(.appTextDim)
        }
    }

    private func displayName(for key: String) -> String {
        if let def = ExerciseDictionary.all[key] { return def.displayName }
        if let ex = allExercises.first(where: { $0.exerciseKey == key }) { return ex.displayName }
        return key.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func slotDisplayName(slotId: String, session: SessionType, week: Int) -> String {
        if let t = allTemplates.first(where: {
            $0.programId == instance.programId && $0.week == week &&
            $0.sessionType == session && $0.slotId == slotId
        }) {
            let key = resolveExerciseKey(slotId: slotId, originalKey: t.exerciseKey,
                                         overrides: instance.overrides, week: week)
            return displayName(for: key)
        }
        return slotId
    }

    private func slotTargetsMuscle(slotId: String, session: SessionType, week: Int) -> Bool {
        guard let t = allTemplates.first(where: {
            $0.programId == instance.programId && $0.week == week &&
            $0.sessionType == session && $0.slotId == slotId
        }) else { return false }
        let key = resolveExerciseKey(slotId: slotId, originalKey: t.exerciseKey,
                                     overrides: instance.overrides, week: week)
        return exerciseTargetsMuscle(key: key)
    }

    private func scopeShortLabel(for ov: SessionOverride) -> String {
        switch ov.scope {
        case .single: return "wk \(ov.appliesFromWeek)"
        case .future: return "wk \(ov.appliesFromWeek)+"
        case .range:  return "wk \(ov.appliesFromWeek)–\(ov.scopeEndWeek ?? ov.appliesFromWeek)"
        }
    }

    // ── Apply mutations ─────────────────────────────────────────────────────

    private func applyAddition(exercise: Exercise) {
        guard let session = selectedSession else { return }
        let isCompound = exercise.isCompound
        let r = resolvedScope
        let override = SessionOverride(
            sessionType: session,
            targetExerciseKey: "",
            targetSlotId: "VA-\(UUID().uuidString.prefix(6))",
            replacementExerciseKey: exercise.exerciseKey,
            appliesFromWeek: r.from,
            scope: r.scope,
            scopeEndWeek: r.end,
            reason: "volumeAdjuster",
            isAddition: true
        )
        override.addedSets = setsToAdd
        override.addedRepsLow = isCompound ? 6 : 8
        override.addedRepsHigh = isCompound ? 10 : 15
        override.addedRPE = isCompound ? 8.0 : 8.5
        override.addedRest = isCompound ? 120 : 75
        instance.overrides.append(override)
        try? modelContext.save()
        withAnimation { step = 1 }
    }

    private func applyDelta(row: AdjustableRow, delta: Int) {
        guard let session = selectedSession else { return }
        let r = resolvedScope
        // Don't reduce below zero
        if delta < 0 && row.currentSets <= 0 { return }
        let override = SessionOverride(
            sessionType: session,
            targetExerciseKey: row.exerciseKey,
            targetSlotId: row.slotId,
            replacementExerciseKey: row.exerciseKey,
            appliesFromWeek: r.from,
            scope: r.scope,
            scopeEndWeek: r.end,
            reason: "volumeAdjuster",
            isAddition: false
        )
        override.setCountDelta = delta
        instance.overrides.append(override)
        try? modelContext.save()
    }
}

// ── UserProgramInstance helper for duration ─────────────────────────────────

extension UserProgramInstance {
    /// Looks up program duration from the matching ProgramTemplate. nil if unknown.
    var programDurationWeeks: Int? {
        // The template lookup happens via @Query in views. This is a best-effort
        // fallback. Built-in programs are 24 weeks; PPL is 16.
        switch programId {
        case 2: return 16
        default: return 24
        }
    }
}

// ═══════════════════════════════════════════
// NUMERIC INPUT SHEET
// Reusable small sheet for direct exact-number entry. Used by VolumeAdjusterSheet
// and Settings → Muscle Priorities for setting target sets.
// ═══════════════════════════════════════════

struct NumericInputSheet: View {
    let title: String
    let subtitle: String
    let initialValue: Int
    let suggestionLow: Int
    let suggestionHigh: Int
    let onSave: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBG.ignoresSafeArea()
                VStack(spacing: 18) {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.appTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    TextField("0", text: $text)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 56, weight: .black, design: .rounded))
                        .foregroundColor(.appTextPrimary)
                        .focused($focused)
                        .padding(.vertical, 12)
                        .background(Color.appSurface)
                        .cornerRadius(14)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.appBorder, lineWidth: 1))
                        .padding(.horizontal, 40)

                    Text("sets per week")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.appTextDim)

                    suggestionBlock

                    Button {
                        save()
                    } label: {
                        Text("APPLY")
                            .font(.system(size: 14, weight: .black))
                            .foregroundColor(.white)
                            .kerning(1.5)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Color.appRed)
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)

                    Spacer()
                }
                .padding(.top, 24)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundColor(.appTextSecondary)
                }
            }
            .onAppear {
                text = "\(initialValue)"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    focused = true
                }
            }
        }
    }

    private var enteredValue: Int { Int(text) ?? 0 }

    @ViewBuilder
    private var suggestionBlock: some View {
        let v = enteredValue
        VStack(spacing: 6) {
            Text("Suggested \(suggestionLow)–\(suggestionHigh) sets/wk")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.appTextDim)
            if v > suggestionHigh {
                Text("Above suggested upper limit (\(suggestionHigh)) — recovery may suffer, but you can still set this.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.appOrange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            } else if v > 0 && v < suggestionLow {
                Text("Below suggested floor (\(suggestionLow)) — minimal growth stimulus.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.appRed)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .padding(.horizontal, 12)
    }

    private func save() {
        let v = max(0, enteredValue)
        onSave(v)
        dismiss()
    }
}

