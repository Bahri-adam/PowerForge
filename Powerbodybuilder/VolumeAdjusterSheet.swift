import SwiftUI
import SwiftData

// ═══════════════════════════════════════════
// VOLUME ADJUSTER SHEET
// Tap a muscle bar in Home or Program tab → opens this sheet.
// Shows current programmed sets vs target, suggests good additions,
// adds them as SessionOverride(isAddition: true) injected into buildPreview.
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

    @State private var selectedSession: SessionType? = nil
    @State private var selectedExerciseKey: String? = nil
    @State private var setsToAdd: Int = 2
    @State private var step: Int = 1  // 1 = overview, 2 = exercise picker

    // ── Volume math ────────────────────────────────────────────────────────

    /// Current programmed sets per session for this muscle, for the current week
    private var sessionsWithMuscle: [(session: SessionType, currentSets: Int)] {
        let rotation = sessionRotation(for: instance.programId, instance: instance, profile: profile)
        var result: [(SessionType, Int)] = []
        for st in Set(rotation) {
            let sets = setsForMuscle(in: st, week: week)
            if sets > 0 { result.append((st, sets)) }
        }
        return result.sorted { $0.1 > $1.1 }
    }

    private func setsForMuscle(in session: SessionType, week: Int) -> Int {
        let templates = allTemplates.filter {
            $0.programId == instance.programId && $0.week == week && $0.sessionType == session
        }
        var count = 0
        for t in templates {
            let key = resolveExerciseKey(slotId: t.slotId, originalKey: t.exerciseKey,
                                         overrides: instance.overrides, week: week)
            if exerciseTargetsMuscle(key: key) { count += t.targetSets }
        }
        // Plus any existing additions for this session/week
        for ov in instance.overrides where ov.isAddition && ov.sessionType == session && ov.appliesTo(week: week) {
            if exerciseTargetsMuscle(key: ov.replacementExerciseKey) { count += ov.addedSets }
        }
        return count
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
        return (mev, scaled.mavLow, scaled.mavHigh, mrv)
    }

    private var zoneColor: Color {
        let r = targetRange
        let cur = totalCurrentSets
        if cur < r.mev { return .appRed }
        if cur < r.mavLow { return .appYellow }
        if cur <= r.mrv { return .appGreen }
        return .appOrange
    }

    private var zoneLabel: String {
        let r = targetRange
        let cur = totalCurrentSets
        if cur < r.mev { return "Under target" }
        if cur < r.mavLow { return "Building" }
        if cur <= r.mrv { return "Optimal" }
        return "Over target"
    }

    // ── Suggested exercises for additions ───────────────────────────────────

    private var suggestedExercises: [Exercise] {
        let candidates = allExercises.filter { ex in
            ex.musclesPrimary.contains { ExerciseDictionary.normalizeMuscle($0) == muscle }
        }
        // Prefer isolations + variety, deprioritize what's already in the rotation
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
            if aIn != bIn { return !aIn }  // not-in-rotation first
            if a.isCompound != b.isCompound { return !a.isCompound }  // isolations first for additions
            return a.displayName < b.displayName
        }
    }

    // ── Body ────────────────────────────────────────────────────────────────

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBG.ignoresSafeArea()
                if step == 1 { overviewStep } else { pickerStep }
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
    }

    // ── Step 1 — Overview + per-session list ───────────────────────────────

    private var overviewStep: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Volume bar
                VStack(spacing: 12) {
                    HStack {
                        Text("WEEK \(week) VOLUME").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(1)
                        Spacer()
                        Text(zoneLabel).font(.system(size: 10, weight: .black)).foregroundColor(zoneColor).kerning(1)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(totalCurrentSets)")
                            .font(.system(size: 40, weight: .black, design: .rounded)).foregroundColor(zoneColor)
                        Text("sets / \(targetRange.mavLow)–\(targetRange.mrv) target")
                            .font(.system(size: 13, weight: .medium)).foregroundColor(.appTextSecondary)
                        Spacer()
                    }
                    volumeBar
                    HStack(spacing: 12) {
                        legendDot(color: .appRed, label: "MEV \(targetRange.mev)")
                        legendDot(color: .appGreen, label: "Optimal \(targetRange.mavLow)–\(targetRange.mavHigh)")
                        legendDot(color: .appOrange, label: "MRV \(targetRange.mrv)")
                    }
                }
                .padding(16).background(Color.appSurface).cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))

                // Per-session breakdown
                if !sessionsWithMuscle.isEmpty {
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
                                    withAnimation { step = 2 }
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                                        Text("ADD").font(.system(size: 10, weight: .black)).kerning(0.5)
                                    }
                                    .foregroundColor(.appRed)
                                    .padding(.horizontal, 10).padding(.vertical, 7)
                                    .background(Color.appRed.opacity(0.08)).cornerRadius(7)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 4)
                            if item.session != sessionsWithMuscle.last?.session { Divider() }
                        }
                    }
                    .padding(16).background(Color.appSurface).cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
                }

                // Active additions (allow removal)
                let activeAdditions = instance.overrides.filter { ov in
                    ov.isAddition && exerciseTargetsMuscle(key: ov.replacementExerciseKey) && ov.appliesTo(week: week)
                }
                if !activeAdditions.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("YOUR ADDITIONS").font(.system(size: 10, weight: .black)).foregroundColor(.appBlue).kerning(1)
                        ForEach(activeAdditions) { ov in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(displayName(for: ov.replacementExerciseKey))
                                        .font(.system(size: 13, weight: .bold)).foregroundColor(.appTextPrimary)
                                    Text("+\(ov.addedSets) sets in \(ov.sessionType.shortLabel)")
                                        .font(.system(size: 11)).foregroundColor(.appTextDim)
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
                    }
                    .padding(16).background(Color.appBlue.opacity(0.04)).cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBlue.opacity(0.2), lineWidth: 1))
                }

                // Add to a new session button
                if sessionsWithMuscle.isEmpty {
                    Text("No \(muscle.lowercased()) work in your program this week. Add an exercise:")
                        .font(.system(size: 13)).foregroundColor(.appTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    let rotation = sessionRotation(for: instance.programId, instance: instance, profile: profile)
                    ForEach(Array(Set(rotation)), id: \.self) { st in
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
            .padding(20)
        }
    }

    // ── Step 2 — Exercise picker + sets selector ───────────────────────────

    private var pickerStep: some View {
        VStack(spacing: 0) {
            // Sets selector
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

            // Exercise list
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

    // ── Helpers ─────────────────────────────────────────────────────────────

    private var volumeBar: some View {
        let r = targetRange
        let maxScale = max(r.mrv + 4, totalCurrentSets + 2)
        return GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.appSurface2).frame(height: 10).cornerRadius(5)
                // Optimal zone band
                Rectangle().fill(Color.appGreen.opacity(0.15))
                    .frame(width: w * CGFloat(r.mavHigh - r.mavLow) / CGFloat(maxScale), height: 10)
                    .offset(x: w * CGFloat(r.mavLow) / CGFloat(maxScale))
                    .cornerRadius(2)
                // Current sets fill
                Rectangle().fill(zoneColor)
                    .frame(width: w * CGFloat(totalCurrentSets) / CGFloat(maxScale), height: 10)
                    .cornerRadius(5)
                // MEV marker
                Rectangle().fill(Color.appBorder).frame(width: 1, height: 14)
                    .offset(x: w * CGFloat(r.mev) / CGFloat(maxScale), y: -2)
                // MRV marker
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

    private func applyAddition(exercise: Exercise) {
        guard let session = selectedSession else { return }
        let isCompound = exercise.isCompound
        let override = SessionOverride(
            sessionType: session,
            targetExerciseKey: "",
            targetSlotId: "VA-\(UUID().uuidString.prefix(6))",
            replacementExerciseKey: exercise.exerciseKey,
            appliesFromWeek: week,
            scope: .future,
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
}
