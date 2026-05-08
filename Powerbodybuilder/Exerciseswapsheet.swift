import SwiftUI
import SwiftData

// ═══════════════════════════════════════════
// EXERCISE SWAP SHEET
// Shown when user taps swap on any exercise slot in WeekConfig.
// Smart ranking by muscle + fallback to full library.
// Custom exercise creation built in.
// ═══════════════════════════════════════════

struct ExerciseSwapSheet: View {
    let slot: SwapTarget
    let instance: UserProgramInstance
    let week: Int
    let onDismiss: () -> Void
    let onSwapApplied: (String, OverrideScope) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var allExercises: [Exercise]

    @State private var searchText = ""
    @State private var selectedKey: String? = nil
    @State private var scope: OverrideScope = .future
    @State private var showCreateCustom = false
    @State private var selectedMuscleFilter: String? = nil
    @State private var cachedAlternatives: [RankedAlternative]? = nil

    // ── Smart ranking (cached on first access) ────────────────────────────

    private var alternatives: [RankedAlternative] {
        if let cached = cachedAlternatives { return cached }
        return []
    }

    private func computeAlternatives() {
        cachedAlternatives = allExercises
            .filter { $0.exerciseKey != slot.exerciseKey }
            .compactMap { ex -> RankedAlternative? in
                let (score, warning) = similarityScoreWithWarning(ex)
                guard score > 0 else { return nil }
                return RankedAlternative(exercise: ex, score: score, swapWarning: warning)
            }
            .sorted { $0.score > $1.score }
    }

    private var hasMuscleData: Bool {
        !slot.musclesPrimary.isEmpty
    }

    private var filtered: [RankedAlternative] {
        // When the user searches, ignore body-part scoping and search the FULL library.
        // Token-based match: every word in the query must appear somewhere in the
        // searchable text (handles "tricep extension" → "Triceps Extension" by allowing
        // partial token match since "tricep" is a prefix of "triceps").
        if !searchText.isEmpty {
            let tokens = searchText
                .lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
            return allExercises
                .filter { $0.exerciseKey != slot.exerciseKey }
                .filter { ex in
                    let haystack = ([ex.displayName] + ex.musclesPrimary + ex.musclesSecondary + [ex.equipmentRaw])
                        .joined(separator: " ")
                        .lowercased()
                    return tokens.allSatisfy { haystack.contains($0) }
                }
                .map { RankedAlternative(exercise: $0, score: 50) }
                .sorted { $0.exercise.displayName < $1.exercise.displayName }
        }

        let base: [RankedAlternative]
        if hasMuscleData {
            base = alternatives
        } else {
            base = allExercises
                .filter { $0.exerciseKey != slot.exerciseKey }
                .map { RankedAlternative(exercise: $0, score: 50) }
                .sorted { $0.exercise.displayName < $1.exercise.displayName }
        }

        // Apply muscle filter chip (only when not searching)
        var result = base
        if let mf = selectedMuscleFilter {
            let slotNorm = slot.musclesPrimary.compactMap { ExerciseDictionary.normalizeMuscle($0) }
            if slotNorm.contains(mf) {
                result = result.filter { ex in
                    let priNorm = ex.exercise.musclesPrimary.compactMap { ExerciseDictionary.normalizeMuscle($0) }
                    return priNorm.contains(mf)
                }
            } else {
                result = allExercises
                    .filter { $0.exerciseKey != slot.exerciseKey }
                    .filter { ex in
                        let priNorm = ex.musclesPrimary.compactMap { ExerciseDictionary.normalizeMuscle($0) }
                        let secNorm = ex.musclesSecondary.compactMap { ExerciseDictionary.normalizeMuscle($0) }
                        return priNorm.contains(mf) || secNorm.contains(mf)
                    }
                    .map { RankedAlternative(exercise: $0, score: 30) }
                    .sorted { $0.exercise.displayName < $1.exercise.displayName }
            }
        }
        return result
    }

    private var smartPicks: [RankedAlternative] {
        guard hasMuscleData && searchText.isEmpty && selectedMuscleFilter == nil else { return [] }
        return Array(filtered.prefix(4))
    }

    private var morePicks: [RankedAlternative] {
        guard hasMuscleData && searchText.isEmpty && selectedMuscleFilter == nil else { return filtered }
        return filtered.count > 4 ? Array(filtered.dropFirst(4)) : []
    }

    /// 9 canonical muscle groups for filter chips (not raw anatomy names)
    private var allMusclesInLibrary: [String] {
        ExerciseDictionary.trackingMuscles
    }

    var body: some View {
        ZStack {
            Color.appBG.ignoresSafeArea()
            VStack(spacing: 0) {

                RoundedRectangle(cornerRadius: 3).fill(Color.appBorder)
                    .frame(width: 36, height: 4).padding(.top, 12)

                // Header
                VStack(spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("SWAP EXERCISE")
                                .font(.system(size: 11, weight: .bold)).foregroundColor(.appRed).kerning(2)
                            Text(slot.displayName)
                                .font(.system(size: 20, weight: .black, design: .rounded)).foregroundColor(.appTextPrimary)
                            if !slot.muscleLabel.isEmpty {
                                Text(slot.muscleLabel)
                                    .font(.system(size: 12)).foregroundColor(.appTextSecondary)
                            } else {
                                Text("Search or browse the full library below")
                                    .font(.system(size: 12)).foregroundColor(.appTextSecondary)
                            }
                        }
                        Spacer()
                        Button(action: onDismiss) {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold)).foregroundColor(.appTextSecondary)
                                .frame(width: 32, height: 32).background(Color.appSurface2).clipShape(Circle())
                        }
                    }
                    // Scope picker
                    HStack(spacing: 0) {
                        ForEach([OverrideScope.single, .future], id: \.rawValue) { s in
                            Button(action: { scope = s }) {
                                Text(s == .single ? "THIS SESSION ONLY" : "ALL FUTURE SESSIONS")
                                    .font(.system(size: 10, weight: .black)).kerning(1)
                                    .foregroundColor(scope == s ? .white : .appTextDim)
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                                    .background(scope == s ? Color.appRed : Color.appSurface2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorder, lineWidth: 1))
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(Color.appSurface)
                .overlay(Rectangle().frame(height: 1).foregroundColor(.appBorder), alignment: .bottom)

                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundColor(.appTextDim)
                    TextField("Search by name, muscle, or equipment...", text: $searchText)
                        .font(.system(size: 15)).foregroundColor(.appTextPrimary)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.appTextDim)
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(Color.appSurface2)
                .overlay(Rectangle().frame(height: 1).foregroundColor(.appBorder), alignment: .bottom)

                // Muscle filter chips
                if searchText.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            FilterChip(label: "All", isSelected: selectedMuscleFilter == nil) {
                                selectedMuscleFilter = nil
                            }
                            ForEach(allMusclesInLibrary, id: \.self) { muscle in
                                FilterChip(label: muscle, isSelected: selectedMuscleFilter == muscle) {
                                    selectedMuscleFilter = selectedMuscleFilter == muscle ? nil : muscle
                                }
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                    }
                    .background(Color.appSurface)
                    .overlay(Rectangle().frame(height: 1).foregroundColor(.appBorder), alignment: .bottom)
                }

                // Results
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 16) {

                        // Create custom exercise CTA
                        Button(action: { showCreateCustom = true }) {
                            HStack(spacing: 10) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8).fill(Color.appRed.opacity(0.12)).frame(width: 36, height: 36)
                                    Image(systemName: "plus").font(.system(size: 16, weight: .bold)).foregroundColor(.appRed)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Create Custom Exercise")
                                        .font(.system(size: 14, weight: .bold)).foregroundColor(.appTextPrimary)
                                    Text("Not in the library? Add your own")
                                        .font(.system(size: 11)).foregroundColor(.appTextDim)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundColor(.appTextDim)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(Color.appSurface)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appRed.opacity(0.25), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)

                        if !smartPicks.isEmpty {
                            VStack(spacing: 8) {
                                SectionHeader(title: "BEST MATCHES").padding(.horizontal, 16)
                                ForEach(smartPicks) { alt in
                                    AlternativeRow(
                                        alt: alt,
                                        isSelected: selectedKey == alt.exercise.exerciseKey,
                                        onSelect: { selectedKey = alt.exercise.exerciseKey }
                                    ).padding(.horizontal, 16)
                                }
                            }
                        }

                        if !morePicks.isEmpty || (!hasMuscleData && !filtered.isEmpty) || (searchText.isEmpty && selectedMuscleFilter != nil && !filtered.isEmpty) {
                            VStack(spacing: 8) {
                                SectionHeader(title: smartPicks.isEmpty ? "ALL EXERCISES" : "MORE OPTIONS").padding(.horizontal, 16)
                                let picks = smartPicks.isEmpty ? filtered : morePicks
                                ForEach(picks) { alt in
                                    AlternativeRow(
                                        alt: alt,
                                        isSelected: selectedKey == alt.exercise.exerciseKey,
                                        onSelect: { selectedKey = alt.exercise.exerciseKey }
                                    ).padding(.horizontal, 16)
                                }
                            }
                        }

                        if filtered.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "magnifyingglass").font(.system(size: 28)).foregroundColor(.appTextDim)
                                Text(searchText.isEmpty ? "No exercises match this filter" : "No matches for \"\(searchText)\"")
                                    .font(.system(size: 14)).foregroundColor(.appTextSecondary)
                                Text("Try creating a custom exercise above")
                                    .font(.system(size: 12)).foregroundColor(.appTextDim)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 40)
                        }
                    }
                    .padding(.vertical, 16).padding(.bottom, 100)
                }

                // Confirm
                VStack(spacing: 0) {
                    Divider().background(Color.appBorder)
                    PrimaryButton(
                        title: selectedKey != nil ? "APPLY SWAP" : "SELECT AN EXERCISE",
                        icon: "arrow.triangle.2.circlepath"
                    ) {
                        guard let key = selectedKey else { return }
                        applySwap(replacementKey: key)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14).background(Color.appBG)
                    .disabled(selectedKey == nil).opacity(selectedKey != nil ? 1.0 : 0.5)
                }
            }
        }
        .sheet(isPresented: $showCreateCustom) {
            CreateCustomExerciseSheet(modelContext: modelContext) { newKey in
                selectedKey = newKey
                showCreateCustom = false
            }
        }
        .onAppear { if cachedAlternatives == nil { computeAlternatives() } }
    }

    // ── Scoring ──────────────────────────────────────────────────────────────

    /// Exercises that should never appear as swap suggestions for a given key.
    /// Use when the fallback scoring would rank them highly but they're bad swaps.
    private static let swapExclusions: [String: Set<String>] = [
        "hack_squat": ["step_up"],
        "leg_press": ["step_up"],
        "pendulum_squat": ["step_up"],
    ]

    private func similarityScoreWithWarning(_ ex: Exercise) -> (score: Int, warning: String?) {
        // Hard exclusions
        if let excluded = Self.swapExclusions[slot.exerciseKey], excluded.contains(ex.exerciseKey) {
            return (0, nil)
        }

        // If slot has no muscle data, give everything a base score
        if slot.musclesPrimary.isEmpty {
            return (50, nil)
        }

        let slotDef = ExerciseDictionary.all[slot.exerciseKey]
        let candDef = ExerciseDictionary.all[ex.exerciseKey]

        // Priority 1: Dictionary swap list — ordered position-based scoring
        if let sDef = slotDef, let idx = sDef.swapKeys.firstIndex(of: ex.exerciseKey) {
            let positionScore = max(100 - idx * 10, 30)
            var warning = sDef.swapWarning

            // Compound → isolation cross-type warning
            if warning == nil && sDef.isCompound && !ex.isCompound {
                warning = "This swap reduces total muscle stimulus — consider keeping a compound movement in your program."
            }
            // Candidate-specific warning (e.g. preacher curl's own warning)
            if warning == nil, let cDef = candDef, let cw = cDef.swapWarning {
                warning = cw
            }
            return (positionScore, warning)
        }

        // Priority 2: Fallback muscle/pattern scoring
        var score = 0
        let samePrimary = ex.musclesPrimary.contains(where: { slot.musclesPrimary.contains($0) })
        let anyMatch = ex.musclesPrimary.contains(where: { slot.musclesPrimary.contains($0) || slot.musclesSecondary.contains($0) })
            || ex.musclesSecondary.contains(where: { slot.musclesPrimary.contains($0) })

        // Also check normalized muscles for matching
        let slotPriNorm = slot.musclesPrimary.compactMap { ExerciseDictionary.normalizeMuscle($0) }
        let exPriNorm = ex.musclesPrimary.compactMap { ExerciseDictionary.normalizeMuscle($0) }
        let normalizedMatch = !Set(slotPriNorm).intersection(Set(exPriNorm)).isEmpty

        guard anyMatch || normalizedMatch else { return (0, nil) }
        if samePrimary || normalizedMatch { score += 50 }
        else { score += 20 }

        // Swap pattern match (more granular than movementPattern)
        if let sDef = slotDef, let cDef = candDef, sDef.swapPattern == cDef.swapPattern {
            score += 30
        } else if ex.movementPatternRaw == slot.movementPattern {
            score += 30
        }

        if ex.equipmentRaw == slot.equipment { score += 10 }
        if ex.isCompound == slot.isCompound { score += 10 }

        // Stretch position match bonus
        if let sDef = slotDef, let cDef = candDef, sDef.stretchPosition == cDef.stretchPosition {
            score += 15
        }

        // Generate warnings
        var warning: String? = nil
        if let sDef = slotDef, sDef.isCompound && !ex.isCompound {
            warning = "This swap reduces total muscle stimulus — consider keeping a compound movement in your program."
        }
        if warning == nil, let cDef = candDef {
            warning = cDef.swapWarning
        }

        return (score, warning)
    }

    private func applySwap(replacementKey: String) {
        let override = SessionOverride(
            sessionType: slot.sessionType,
            targetExerciseKey: slot.exerciseKey,
            targetSlotId: slot.slotId,
            replacementExerciseKey: replacementKey,
            appliesFromWeek: week,
            scope: scope,
            reason: "userSwap"
        )
        instance.overrides.append(override)
        try? modelContext.save()
        onSwapApplied(replacementKey, scope)
        onDismiss()
    }
}

// ═══════════════════════════════════════════
// CREATE CUSTOM EXERCISE SHEET
// ═══════════════════════════════════════════

struct CreateCustomExerciseSheet: View {
    let modelContext: ModelContext
    let onCreated: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var exerciseName = ""
    @State private var primaryMuscles: Set<String> = []
    @State private var secondaryMuscles: Set<String> = []
    @State private var selectedEquipment: String = "barbell"
    @State private var isCompound = true
    @State private var errorMessage = ""

    private let availableMuscles = ExerciseDictionary.trackingMuscles + [
        "Core", "Traps", "Lats", "Forearms"
    ]

    private let equipmentOptions: [(String, String)] = [
        ("barbell", "Barbell"),
        ("dumbbell", "Dumbbell"),
        ("cable", "Cable"),
        ("machine", "Machine"),
        ("bodyweight", "Bodyweight"),
        ("kettlebell", "Kettlebell"),
        ("bands", "Bands"),
        ("other", "Other")
    ]

    var body: some View {
        ZStack {
            Color.appBG.ignoresSafeArea()
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold)).foregroundColor(.appTextSecondary)
                            .frame(width: 32, height: 32).background(Color.appSurface2).clipShape(Circle())
                    }
                    Spacer()
                    Text("CUSTOM EXERCISE")
                        .font(.system(size: 13, weight: .black)).foregroundColor(.appTextPrimary).kerning(1)
                    Spacer()
                    Color.clear.frame(width: 32, height: 32)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(Color.appSurface)
                .overlay(Rectangle().frame(height: 1).foregroundColor(.appBorder), alignment: .bottom)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {

                        // Name
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: "EXERCISE NAME")
                            AppTextField(placeholder: "e.g. Meadows Row", text: $exerciseName, keyboardType: .default, icon: "pencil")
                        }

                        // Primary muscles
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "PRIMARY MUSCLES")
                            Text("Select all main muscles this exercise targets")
                                .font(.system(size: 12)).foregroundColor(.appTextDim)
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                ForEach(availableMuscles, id: \.self) { muscle in
                                    MuscleToggleChip(
                                        label: muscle,
                                        isSelected: primaryMuscles.contains(muscle),
                                        color: .appRed
                                    ) {
                                        if primaryMuscles.contains(muscle) {
                                            primaryMuscles.remove(muscle)
                                        } else {
                                            primaryMuscles.insert(muscle)
                                            secondaryMuscles.remove(muscle) // can't be both
                                        }
                                    }
                                }
                            }
                        }

                        // Secondary muscles
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "SECONDARY MUSCLES")
                            Text("Muscles worked but not the main focus")
                                .font(.system(size: 12)).foregroundColor(.appTextDim)
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                ForEach(availableMuscles.filter { !primaryMuscles.contains($0) }, id: \.self) { muscle in
                                    MuscleToggleChip(
                                        label: muscle,
                                        isSelected: secondaryMuscles.contains(muscle),
                                        color: .appBlue
                                    ) {
                                        if secondaryMuscles.contains(muscle) {
                                            secondaryMuscles.remove(muscle)
                                        } else {
                                            secondaryMuscles.insert(muscle)
                                        }
                                    }
                                }
                            }
                        }

                        // Equipment
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "EQUIPMENT")
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                ForEach(equipmentOptions, id: \.0) { (key, label) in
                                    Button(action: { selectedEquipment = key }) {
                                        HStack(spacing: 8) {
                                            ZStack {
                                                Circle()
                                                    .stroke(selectedEquipment == key ? Color.appRed : Color.appBorder, lineWidth: 2)
                                                    .frame(width: 16, height: 16)
                                                if selectedEquipment == key {
                                                    Circle().fill(Color.appRed).frame(width: 8, height: 8)
                                                }
                                            }
                                            Text(label).font(.system(size: 13, weight: .bold))
                                                .foregroundColor(selectedEquipment == key ? .appTextPrimary : .appTextSecondary)
                                            Spacer()
                                        }
                                        .padding(.horizontal, 12).padding(.vertical, 10)
                                        .background(selectedEquipment == key ? Color.appRed.opacity(0.06) : Color.appSurface)
                                        .cornerRadius(10)
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(
                                            selectedEquipment == key ? Color.appRed.opacity(0.35) : Color.appBorder, lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Compound / Isolation toggle
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "MOVEMENT TYPE")
                            HStack(spacing: 0) {
                                Button(action: { isCompound = true }) {
                                    Text("COMPOUND")
                                        .font(.system(size: 11, weight: .black)).kerning(1)
                                        .foregroundColor(isCompound ? .white : .appTextDim)
                                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                                        .background(isCompound ? Color.appRed : Color.appSurface2)
                                }
                                .buttonStyle(.plain)
                                Button(action: { isCompound = false }) {
                                    Text("ISOLATION")
                                        .font(.system(size: 11, weight: .black)).kerning(1)
                                        .foregroundColor(!isCompound ? .white : .appTextDim)
                                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                                        .background(!isCompound ? Color.appBlue : Color.appSurface2)
                                }
                                .buttonStyle(.plain)
                            }
                            .cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorder, lineWidth: 1))
                        }

                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(.system(size: 12)).foregroundColor(.appRed)
                                .padding(10).background(Color.appRed.opacity(0.08)).cornerRadius(8)
                        }
                    }
                    .padding(16).padding(.bottom, 100)
                }

                // Save button
                VStack(spacing: 0) {
                    Divider().background(Color.appBorder)
                    PrimaryButton(title: "SAVE EXERCISE", icon: "checkmark.circle.fill") {
                        saveExercise()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14).background(Color.appBG)
                    .disabled(exerciseName.trimmingCharacters(in: .whitespaces).isEmpty || primaryMuscles.isEmpty)
                    .opacity(exerciseName.trimmingCharacters(in: .whitespaces).isEmpty || primaryMuscles.isEmpty ? 0.5 : 1)
                }
            }
        }
    }

    private func saveExercise() {
        let name = exerciseName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { errorMessage = "Exercise name is required."; return }
        guard !primaryMuscles.isEmpty else { errorMessage = "Select at least one primary muscle."; return }

        // Reject duplicate display names (case-insensitive) — prevents crash from duplicate exerciseKey
        let descriptor = FetchDescriptor<Exercise>()
        let existing = (try? modelContext.fetch(descriptor)) ?? []
        if existing.contains(where: { $0.displayName.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            errorMessage = "An exercise named \"\(name)\" already exists. Pick a different name."
            return
        }

        // Build a stable, unique exerciseKey from the name + timestamp
        let baseSlug = name.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0 == "_" }
        let timestamp = Int(Date().timeIntervalSince1970)
        let key = "custom_\(baseSlug)_\(timestamp)"

        let exercise = Exercise(
            exerciseKey: key,
            displayName: name,
            movementPattern:.horizontalPush, // default — user can refine later
            musclesPrimary: Array(primaryMuscles),
            musclesSecondary: Array(secondaryMuscles),
            equipment: EquipmentType(rawValue: selectedEquipment) ?? .other,
            isCompound: isCompound,
            isCustom: true
        )

        modelContext.insert(exercise)
        try? modelContext.save()
        onCreated(key)
    }
}

// ═══════════════════════════════════════════
// FILTER CHIP
// ═══════════════════════════════════════════

struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(isSelected ? .white : .appTextSecondary)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(isSelected ? Color.appRed : Color.appSurface2)
                .cornerRadius(20)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(isSelected ? Color.appRed : Color.appBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// ═══════════════════════════════════════════
// MUSCLE TOGGLE CHIP
// ═══════════════════════════════════════════

struct MuscleToggleChip: View {
    let label: String
    let isSelected: Bool
    let color: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                if isSelected {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .black)).foregroundColor(color)
                }
                Text(label)
                    .font(.system(size: 11, weight: isSelected ? .black : .bold))
                    .foregroundColor(isSelected ? color : .appTextSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? color.opacity(0.1) : Color.appSurface)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? color.opacity(0.4) : Color.appBorder, lineWidth: isSelected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }
}

// ═══════════════════════════════════════════
// SWAP TARGET
// ═══════════════════════════════════════════

struct SwapTarget: Identifiable {
    let id = UUID()
    let exerciseKey: String
    let displayName: String
    let slotId: String
    let sessionType: SessionType
    let movementPattern: String
    let equipment: String
    let musclesPrimary: [String]
    let musclesSecondary: [String]
    let isCompound: Bool

    var muscleLabel: String { musclesPrimary.prefix(2).joined(separator: " · ") }

    static func from(
        exerciseKey: String,
        displayName: String,
        slotId: String,
        sessionType: SessionType,
        exercises: [Exercise]
    ) -> SwapTarget {
        if let ex = exercises.first(where: { $0.exerciseKey == exerciseKey }) {
            return SwapTarget(
                exerciseKey: ex.exerciseKey,
                displayName: ex.displayName,
                slotId: slotId,
                sessionType: sessionType,
                movementPattern: ex.movementPatternRaw,
                equipment: ex.equipmentRaw,
                musclesPrimary: ex.musclesPrimary,
                musclesSecondary: ex.musclesSecondary,
                isCompound: ex.isCompound
            )
        }
        if let def = ExerciseDictionary.all[exerciseKey] {
            return SwapTarget(
                exerciseKey: exerciseKey,
                displayName: def.displayName,
                slotId: slotId,
                sessionType: sessionType,
                movementPattern: def.movementPattern.rawValue,
                equipment: def.equipment.rawValue,
                musclesPrimary: def.primaryMuscles,
                musclesSecondary: def.secondaryMuscles.map { $0.muscle },
                isCompound: def.isCompound
            )
        }
        return SwapTarget(
            exerciseKey: exerciseKey,
            displayName: displayName,
            slotId: slotId,
            sessionType: sessionType,
            movementPattern: "",
            equipment: "",
            musclesPrimary: [],
            musclesSecondary: [],
            isCompound: true
        )
    }
}

// ═══════════════════════════════════════════
// RANKED ALTERNATIVE
// ═══════════════════════════════════════════

struct RankedAlternative: Identifiable {
    let id = UUID()
    let exercise: Exercise
    let score: Int
    let swapWarning: String?

    init(exercise: Exercise, score: Int, swapWarning: String? = nil) {
        self.exercise = exercise
        self.score = score
        self.swapWarning = swapWarning
    }

    var matchLabel: String {
        if score >= 80 { return "PERFECT MATCH" }
        if score >= 60 { return "GREAT MATCH" }
        if score >= 40 { return "GOOD MATCH" }
        return "SIMILAR"
    }

    var matchColor: Color {
        if score >= 80 { return .appGreen }
        if score >= 60 { return .appBlue }
        return .appTextDim
    }
}

// ═══════════════════════════════════════════
// ALTERNATIVE ROW
// ═══════════════════════════════════════════

struct AlternativeRow: View {
    let alt: RankedAlternative
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(isSelected ? Color.appRed : Color.appBorder, lineWidth: 2).frame(width: 22, height: 22)
                    if isSelected { Circle().fill(Color.appRed).frame(width: 12, height: 12) }
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(alt.exercise.displayName)
                            .font(.system(size: 14, weight: .bold)).foregroundColor(.appTextPrimary)
                        Text(alt.matchLabel)
                            .font(.system(size: 8, weight: .black))
                            .foregroundColor(alt.matchColor)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(alt.matchColor.opacity(0.12)).cornerRadius(3)
                        if alt.exercise.isCustom {
                            Text("CUSTOM").font(.system(size: 8, weight: .black)).foregroundColor(.appGold)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.appGold.opacity(0.12)).cornerRadius(3)
                        }
                    }
                    HStack(spacing: 8) {
                        Text(alt.exercise.musclesPrimary.prefix(2).joined(separator: " · "))
                            .font(.system(size: 11)).foregroundColor(.appTextSecondary)
                        if !alt.exercise.equipmentRaw.isEmpty {
                            Text("·").foregroundColor(.appTextDim)
                            Text(alt.exercise.equipmentRaw.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.system(size: 11)).foregroundColor(.appTextDim)
                        }
                    }
                    // Swap context — why this is a good alternative
                    Text(swapReason(alt))
                        .font(.system(size: 10)).foregroundColor(.appBlue.opacity(0.8))
                    if let warning = alt.swapWarning {
                        Text(warning)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.appOrange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                if alt.exercise.isCompound {
                    Text("COMPOUND")
                        .font(.system(size: 8, weight: .black)).foregroundColor(.appRed)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.appRed.opacity(0.1)).cornerRadius(3)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(isSelected ? Color.appRed.opacity(0.06) : Color.appSurface)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.appRed.opacity(0.4) : Color.appBorder, lineWidth: isSelected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }

    private func swapReason(_ alt: RankedAlternative) -> String {
        let def = ExerciseDictionary.all[alt.exercise.exerciseKey]
        guard let d = def else { return "" }

        if alt.score >= 80 { return "Top swap — best functional match" }

        var reasons: [String] = []

        // Specific head target
        let head = d.head
        if !head.isEmpty {
            switch head {
            case "mid":            reasons.append("mid/lower chest")
            case "upper":          reasons.append("upper chest emphasis")
            case "lower":          reasons.append("lower chest emphasis")
            case "thickness":      reasons.append("back thickness (rows)")
            case "width":          reasons.append("lat width (vertical pull)")
            case "anterior":       reasons.append("front delt")
            case "medial":         reasons.append("side delt — width builder")
            case "posterior":      reasons.append("rear delt — posture & balance")
            case "lateral":        reasons.append("tricep lateral/medial head")
            case "long":           reasons.append("long head — stretched overhead")
            case "short":          reasons.append("short head — peak contraction")
            case "both":           reasons.append("hits both bicep heads")
            case "brachio":        reasons.append("brachialis — arm thickness")
            case "compound":       reasons.append("quad compound movement")
            case "isolation":      reasons.append("quad isolation")
            case "hip_hinge":      reasons.append("hip hinge — hamstring stretch")
            case "knee_flexion":   reasons.append("knee flexion — hamstring curl")
            case "extension":      reasons.append("hip extension — glute driver")
            case "abduction":      reasons.append("glute medius — lateral stability")
            case "gastro":         reasons.append("gastrocnemius — straight knee")
            case "soleus":         reasons.append("soleus — bent knee")
            default: break
            }
        }

        // Movement quality
        if d.stretchPosition == .lengthened { reasons.append("loads at stretch") }
        if d.isCompound && reasons.count < 2 { reasons.append("compound") }

        return reasons.prefix(2).joined(separator: " · ")
    }
}
