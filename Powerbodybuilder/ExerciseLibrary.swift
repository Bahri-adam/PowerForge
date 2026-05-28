import SwiftUI
import SwiftData

// ═══════════════════════════════════════════
// PRELOAD FUNCTION
// ═══════════════════════════════════════════

/// Seed version — bump to trigger re-seed on existing installs
private let exerciseSeedVersion = 3

func preloadExercisesIfNeeded(context: ModelContext) {
    // Check seed version via UserDefaults
    let lastVersion = UserDefaults.standard.integer(forKey: "exerciseSeedVersion")
    let descriptor = FetchDescriptor<Exercise>()
    let existing = (try? context.fetch(descriptor)) ?? []

    if lastVersion >= exerciseSeedVersion && !existing.isEmpty { return }

    // Delete non-custom exercises on re-seed (preserve user-created ones)
    if lastVersion < exerciseSeedVersion {
        for ex in existing where !ex.isCustom {
            context.delete(ex)
        }
    }

    // Seed from ExerciseDictionary
    let existingKeys = Set(existing.filter { $0.isCustom }.map { $0.exerciseKey })
    for (_, def) in ExerciseDictionary.all {
        guard !existingKeys.contains(def.key) else { continue }
        let ex = Exercise(
            exerciseKey: def.key,
            displayName: def.displayName,
            movementPattern: def.movementPattern,
            musclesPrimary: def.primaryMuscles,
            musclesSecondary: def.secondaryMuscles.map { $0.muscle },
            equipment: def.equipment,
            isCompound: def.isCompound,
            jointStressTags: def.jointStressTags,
            variationOfKey: def.variationOfKey,
            stretchPosition: def.stretchPosition
        )
        context.insert(ex)
    }

    UserDefaults.standard.set(exerciseSeedVersion, forKey: "exerciseSeedVersion")
}

// ═══════════════════════════════════════════
// EXERCISE LIBRARY VIEW
// ═══════════════════════════════════════════

struct ExerciseLibraryView: View {

    @Environment(\.modelContext) private var modelContext
    @Query private var exercises: [Exercise]

    @State private var searchText = ""
    @State private var selectedMuscle = "All"
    @State private var showAddExercise = false
    @State private var showDeleteConfirm = false
    @State private var deleteTarget: Exercise? = nil
    @State private var editTarget: Exercise? = nil

    let muscleFilters = ExerciseDictionary.exerciseFilters

    var filtered: [Exercise] {
        exercises
            .filter { ex in
                let muscleMatch: Bool
                if selectedMuscle == "All" {
                    muscleMatch = true
                } else {
                    // Normalize exercise muscles to tracking groups for matching
                    let normalizedPrimary = ex.musclesPrimary.compactMap { ExerciseDictionary.normalizeMuscle($0) }
                    let normalizedSecondary = ex.musclesSecondary.compactMap { ExerciseDictionary.normalizeMuscle($0) }
                    muscleMatch = normalizedPrimary.contains(selectedMuscle)
                        || normalizedSecondary.contains(selectedMuscle)
                }
                let searchMatch = searchText.isEmpty ||
                    ex.displayName.localizedCaseInsensitiveContains(searchText)
                return muscleMatch && searchMatch
            }
            .sorted { $0.displayName < $1.displayName }
    }

    var body: some View {
        ZStack {
            Color.appBG.ignoresSafeArea()

            VStack(spacing: 0) {

                // HEADER
                VStack(spacing: 12) {
                    HStack {
                        Text("EXERCISE LIBRARY")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(.appTextPrimary)
                        Spacer()
                        Button(action: { showAddExercise = true }) {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.appRed)
                                .padding(10)
                                .background(Color.appRed.opacity(0.1))
                                .clipShape(Circle())
                        }
                    }

                    // Search
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.appTextDim)
                        TextField("Search exercises...", text: $searchText)
                            .foregroundColor(.appTextPrimary)
                    }
                    .padding(12)
                    .background(Color.appSurface2)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))

                    // Muscle filter pills
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(muscleFilters, id: \.self) { muscle in
                                Button(action: { selectedMuscle = muscle }) {
                                    Text(muscle)
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(selectedMuscle == muscle ? .white : .appTextSecondary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 7)
                                        .background(selectedMuscle == muscle ? Color.appRed : Color.appSurface2)
                                        .cornerRadius(20)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 20)
                                                .stroke(selectedMuscle == muscle ? Color.appRed : Color.appBorder, lineWidth: 1)
                                        )
                                }
                            }
                        }
                        .padding(.horizontal, 1)
                    }

                    HStack {
                        Text("\(filtered.count) exercises")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.appTextDim)
                        Spacer()
                    }
                }
                .padding(16)
                .background(Color.appSurface)
                .overlay(Rectangle().frame(height: 1).foregroundColor(.appBorder), alignment: .bottom)

                // LIST
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(filtered, id: \.exerciseKey) { exercise in
                            ExerciseRow(
                                exercise: exercise,
                                onDelete: exercise.isCustom ? {
                                    deleteTarget = exercise
                                    showDeleteConfirm = true
                                } : nil,
                                onEdit: exercise.isCustom ? {
                                    editTarget = exercise
                                } : nil)
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 40)
                }
            }
        }
        .sheet(isPresented: $showAddExercise) {
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
        .onAppear {
            preloadExercisesIfNeeded(context: modelContext)
        }
    }
}

// ═══════════════════════════════════════════
// EXERCISE ROW
// ═══════════════════════════════════════════

struct ExerciseRow: View {
    let exercise: Exercise
    let onDelete: (() -> Void)?
    let onEdit: (() -> Void)?

    init(exercise: Exercise, onDelete: (() -> Void)? = nil, onEdit: (() -> Void)? = nil) {
        self.exercise = exercise
        self.onDelete = onDelete
        self.onEdit = onEdit
    }

    var body: some View {
        HStack(spacing: 12) {
            // Compound indicator
            Rectangle()
                .fill(exercise.isCompound ? Color.appRed : Color.appBlue)
                .frame(width: 3)
                .cornerRadius(2)

            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.displayName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.appTextPrimary)

                HStack(spacing: 6) {
                    ForEach(exercise.musclesPrimary.prefix(2), id: \.self) { muscle in
                        Text(muscle)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.appRed)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.appRed.opacity(0.1))
                            .cornerRadius(4)
                    }
                    if !exercise.musclesSecondary.isEmpty {
                        Text(exercise.musclesSecondary[0])
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.appTextDim)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.appSurface2)
                            .cornerRadius(4)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(exercise.equipment.rawValue.capitalized)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.appTextDim)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.appSurface2)
                    .cornerRadius(6)

                if exercise.isCompound {
                    Text("COMPOUND")
                        .font(.system(size: 8, weight: .black))
                        .foregroundColor(.appRed)
                        .kerning(0.5)
                } else {
                    Text("ISOLATION")
                        .font(.system(size: 8, weight: .black))
                        .foregroundColor(.appBlue)
                        .kerning(0.5)
                }
                if exercise.isCustom {
                    Text("CUSTOM")
                        .font(.system(size: 8, weight: .black))
                        .foregroundColor(.appGold)
                        .kerning(0.5)
                }
            }
            if onEdit != nil {
                Button(action: { onEdit?() }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.appBlue.opacity(0.75))
                        .frame(width: 28, height: 28)
                        .background(Color.appBlue.opacity(0.08))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            if onDelete != nil {
                Button(action: { onDelete?() }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.appRed.opacity(0.6))
                        .frame(width: 28, height: 28)
                        .background(Color.appRed.opacity(0.08))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.appSurface)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(exercise.isCustom ? Color.appGold.opacity(0.3) : Color.appBorder, lineWidth: 1))
    }
}

// ═══════════════════════════════════════════
// ADD EXERCISE VIEW
// ═══════════════════════════════════════════

struct AddExerciseView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var profilesQuery: [UserProfile]

    /// When non-nil, the form is editing an existing exercise rather than
    /// creating a new one. State is hydrated from the record on appear,
    /// and `saveExercise()` updates the same record instead of inserting.
    let editing: Exercise?

    init(editing: Exercise? = nil) {
        self.editing = editing
    }

    @State private var name = ""
    @State private var selectedMuscles: Set<String> = []
    @State private var selectedSecondary: Set<String> = []
    @State private var selectedEquipment: EquipmentType = .barbell
    @State private var selectedPattern: MovementPattern = .isolation
    @State private var isCompound = false

    // Advanced-density: optional head-level detail.
    @State private var customizeHeads: Bool = false
    @State private var headWeights: [MuscleHead: Double] = [:]

    private var density: UIDensity { profilesQuery.first?.density ?? .advanced }
    private var isEditing: Bool { editing != nil }

    let muscles = ExerciseDictionary.trackingMuscles + ["Core", "Traps", "Forearms"]

    var body: some View {
        ZStack {
            Color.appBG.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.appTextSecondary)
                    Spacer()
                    Text(isEditing ? "EDIT EXERCISE" : "ADD EXERCISE")
                        .font(.system(size: 15, weight: .black))
                        .foregroundColor(.appTextPrimary)
                    Spacer()
                    Button("Save") { saveExercise() }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.appRed)
                        .disabled(name.isEmpty || selectedMuscles.isEmpty)
                }
                .padding(20)
                .background(Color.appSurface)
                .overlay(Rectangle().frame(height: 1).foregroundColor(.appBorder), alignment: .bottom)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {

                        AppTextField(placeholder: "Exercise name", text: $name, icon: "dumbbell.fill")

                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "PRIMARY MUSCLES")
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                ForEach(muscles, id: \.self) { muscle in
                                    let selected = selectedMuscles.contains(muscle)
                                    Button(action: {
                                        if selected { selectedMuscles.remove(muscle) }
                                        else { selectedMuscles.insert(muscle) }
                                    }) {
                                        Text(muscle)
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(selected ? .white : .appTextSecondary)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background(selected ? Color.appRed : Color.appSurface)
                                            .cornerRadius(8)
                                            .overlay(RoundedRectangle(cornerRadius: 8)
                                                .stroke(selected ? Color.appRed : Color.appBorder, lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "SECONDARY MUSCLES")
                            Text("Muscles that assist but aren't the main target. Affects volume tracking — these count as partial sets.")
                                .font(.system(size: 11)).foregroundColor(.appTextDim)
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                ForEach(muscles.filter { !selectedMuscles.contains($0) }, id: \.self) { muscle in
                                    let selected = selectedSecondary.contains(muscle)
                                    Button(action: {
                                        if selected { selectedSecondary.remove(muscle) }
                                        else { selectedSecondary.insert(muscle) }
                                    }) {
                                        Text(muscle)
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(selected ? .white : .appTextSecondary)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background(selected ? Color.appBlue : Color.appSurface)
                                            .cornerRadius(8)
                                            .overlay(RoundedRectangle(cornerRadius: 8)
                                                .stroke(selected ? Color.appBlue : Color.appBorder, lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "EQUIPMENT")
                            HStack(spacing: 8) {
                                ForEach([EquipmentType.barbell, .dumbbell, .cable, .machine, .bodyweight], id: \.self) { eq in
                                    Button(action: { selectedEquipment = eq }) {
                                        Text(eq.rawValue.capitalized)
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(selectedEquipment == eq ? .white : .appTextSecondary)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 8)
                                            .background(selectedEquipment == eq ? Color.appRed : Color.appSurface)
                                            .cornerRadius(8)
                                            .overlay(RoundedRectangle(cornerRadius: 8)
                                                .stroke(selectedEquipment == eq ? Color.appRed : Color.appBorder, lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        HStack {
                            Image(systemName: "bolt.fill")
                                .foregroundColor(.appTextDim)
                            Text("Compound movement")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.appTextSecondary)
                            Spacer()
                            Toggle("", isOn: $isCompound).tint(.appRed)
                        }
                        .padding(14)
                        .background(Color.appSurface2)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))

                        // Advanced-density: optional head-level detail.
                        // Minimal/standard users never see this — they create
                        // exercises with simple primary/secondary picks and
                        // the algorithm infers head contributions automatically.
                        if density == .advanced, !selectedMuscles.isEmpty {
                            CustomHeadPicker(
                                primaryMuscles: selectedMuscles,
                                secondaryMuscles: selectedSecondary,
                                customizeHeads: $customizeHeads,
                                headWeights: $headWeights
                            )
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 40)
                }
            }
        }
        .onAppear { hydrateFromEditingTarget() }
    }

    /// Pre-populate the form state from an existing Exercise when in edit
    /// mode. No-op when creating a new exercise.
    private func hydrateFromEditingTarget() {
        guard let ex = editing, name.isEmpty else { return }
        name = ex.displayName
        selectedMuscles = Set(ex.musclesPrimary)
        selectedSecondary = Set(ex.musclesSecondary)
        selectedEquipment = ex.equipment
        selectedPattern = ex.movementPattern
        isCompound = ex.isCompound
        let stored = ex.headContributions
        if !stored.isEmpty {
            customizeHeads = true
            headWeights = stored
        }
    }

    func saveExercise() {
        if let ex = editing {
            // Edit existing record. Preserve exerciseKey (so workout logs
            // referencing it remain valid) — only mutable fields change.
            ex.displayName = name
            ex.musclesPrimary = Array(selectedMuscles)
            ex.musclesSecondary = Array(selectedSecondary)
            ex.equipmentRaw = selectedEquipment.rawValue
            ex.movementPatternRaw = selectedPattern.rawValue
            ex.isCompound = isCompound
            ex.updatedAt = Date()
            if customizeHeads && !headWeights.isEmpty {
                ex.headContributions = headWeights.filter { $0.value > 0.01 }
            } else {
                ex.headContributions = [:]  // clear stored heads — fall back to inference
            }
            try? modelContext.save()
            dismiss()
            return
        }
        let key = name.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "[^a-z0-9_]", with: "", options: .regularExpression)
        let exercise = Exercise(
            exerciseKey: "custom_\(key)_\(Int(Date().timeIntervalSince1970))",
            displayName: name,
            movementPattern: selectedPattern,
            musclesPrimary: Array(selectedMuscles),
            musclesSecondary: Array(selectedSecondary),
            equipment: selectedEquipment,
            isCompound: isCompound,
            isCustom: true
        )
        if customizeHeads && !headWeights.isEmpty {
            exercise.headContributions = headWeights.filter { $0.value > 0.01 }
        }
        modelContext.insert(exercise)
        dismiss()
    }
}

// ═══════════════════════════════════════════
// CUSTOM HEAD PICKER (reusable)
// Used by both AddExerciseView and CreateCustomExerciseSheet so head-
// level UI stays consistent. Caller passes primary/secondary muscle
// sets + bindings to customizeHeads + headWeights state. Internally
// computes relevant heads and renders 4-step chips per head.
// ═══════════════════════════════════════════

struct CustomHeadPicker: View {
    let primaryMuscles: Set<String>
    let secondaryMuscles: Set<String>
    @Binding var customizeHeads: Bool
    @Binding var headWeights: [MuscleHead: Double]

    private var relevantHeads: [MuscleHead] {
        var heads: [MuscleHead] = []
        var seen: Set<MuscleHead> = []
        for raw in primaryMuscles.sorted() {
            guard let normalized = ExerciseDictionary.normalizeMuscle(raw) else { continue }
            for head in MuscleHead.heads(of: normalized) where !seen.contains(head) {
                heads.append(head); seen.insert(head)
            }
        }
        for raw in secondaryMuscles.sorted() {
            guard let normalized = ExerciseDictionary.normalizeMuscle(raw) else { continue }
            for head in MuscleHead.heads(of: normalized) where !seen.contains(head) {
                heads.append(head); seen.insert(head)
            }
        }
        return heads
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                SectionHeader(title: "HEAD-LEVEL DETAIL")
                Text("(advanced)").font(.system(size: 9, weight: .bold))
                    .foregroundColor(.appBlue).kerning(0.8)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.appBlue.opacity(0.12)).cornerRadius(4)
                Spacer()
                Toggle("", isOn: $customizeHeads).labelsHidden().tint(.appRed)
            }

            if customizeHeads {
                VStack(alignment: .leading, spacing: 6) {
                    Text("How hard does this exercise hit each head?")
                        .font(.system(size: 11)).foregroundColor(.appTextDim)
                    // Per-chip multiplier so users see what they're picking
                    HStack(spacing: 10) {
                        legendChip(label: "None", multiplier: "0×", color: .appTextDim)
                        legendChip(label: "Light", multiplier: "0.4×", color: .appYellow)
                        legendChip(label: "Med", multiplier: "0.7×", color: .appBlue)
                        legendChip(label: "Heavy", multiplier: "1.0×", color: .appRed)
                    }
                    Text("Each set of this exercise distributes credit to each head by its multiplier. Bars in the muscle breakdown show those numbers; the algorithm flags lagging heads from them.")
                        .font(.system(size: 10)).foregroundColor(.appTextDim).lineSpacing(2)
                }
                .padding(10).background(Color.appBlue.opacity(0.06)).cornerRadius(8)

                let grouped: [(muscle: String, heads: [MuscleHead])] = {
                    var byParent: [String: [MuscleHead]] = [:]
                    for h in relevantHeads { byParent[h.parentMuscle, default: []].append(h) }
                    return byParent.keys.sorted().map { ($0, byParent[$0] ?? []) }
                }()

                VStack(spacing: 12) {
                    ForEach(grouped, id: \.muscle) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.muscle.uppercased())
                                .font(.system(size: 9, weight: .black)).kerning(1)
                                .foregroundColor(.appTextDim)
                            ForEach(group.heads, id: \.self) { head in
                                HStack(spacing: 6) {
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(head.laymanName.capitalizingFirst)
                                            .font(.system(size: 12, weight: .medium)).foregroundColor(.appTextPrimary)
                                            .lineLimit(1).minimumScaleFactor(0.8)
                                        if head.laymanDiffersFromDisplay {
                                            Text(head.displayName)
                                                .font(.system(size: 8))
                                                .foregroundColor(.appTextDim)
                                                .lineLimit(1).minimumScaleFactor(0.8)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    chip(head: head, label: "None", value: 0.0)
                                    chip(head: head, label: "Light", value: 0.4)
                                    chip(head: head, label: "Med", value: 0.7)
                                    chip(head: head, label: "Heavy", value: 1.0)
                                }
                            }
                        }
                        .padding(10).background(Color.appSurface).cornerRadius(8)
                    }
                }

                // Worked example using the current selections
                if !headWeights.isEmpty {
                    workedExample
                }
            } else {
                Text("The algorithm will infer head-level contributions from your primary and secondary muscle picks. Toggle on to fine-tune.")
                    .font(.system(size: 11)).foregroundColor(.appTextDim).lineSpacing(2)
            }
        }
    }

    /// Real-time preview of how the selected multipliers translate to head
    /// credit per set. Updates as the user picks chips so the math isn't
    /// abstract.
    private var workedExample: some View {
        let entries = headWeights
            .filter { $0.value > 0.01 }
            .sorted { $0.value > $1.value }
        return VStack(alignment: .leading, spacing: 6) {
            Text("PER SET, YOU'RE TELLING THE APP:")
                .font(.system(size: 9, weight: .black)).foregroundColor(.appBlue).kerning(1)
            ForEach(entries, id: \.key) { (head, weight) in
                HStack(spacing: 6) {
                    Text("•").foregroundColor(.appBlue)
                    Text(head.laymanName.capitalizingFirst)
                        .font(.system(size: 11)).foregroundColor(.appTextPrimary)
                    Spacer()
                    Text(String(format: "+%.1f credit", weight))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.appBlue)
                }
            }
            // Parent muscle total = MAX, not sum, since one set fires the
            // muscle once. Surface this so the user sees why their picks
            // don't add up to "+2.1 triceps" or similar.
            if let topWeight = entries.first?.value,
               let topHead = entries.first?.key {
                Divider().background(Color.appBorder).padding(.vertical, 2)
                HStack(spacing: 6) {
                    Text(topHead.parentMuscle + " total:")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.appTextPrimary)
                    Spacer()
                    Text(String(format: "+%.1f set", topWeight))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.appTextPrimary)
                }
                Text("Parent total = the strongest head's value (heads overlap — one set hits all of them at once, so they're not added).")
                    .font(.system(size: 9))
                    .foregroundColor(.appTextDim).lineSpacing(1.5)
            }
        }
        .padding(10).background(Color.appBlue.opacity(0.06)).cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBlue.opacity(0.25), lineWidth: 1))
    }

    private func legendChip(label: String, multiplier: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(label).font(.system(size: 9, weight: .black)).foregroundColor(color)
            Text(multiplier).font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.appTextDim)
        }
        .frame(maxWidth: .infinity)
    }

    private func chip(head: MuscleHead, label: String, value: Double) -> some View {
        let current = headWeights[head] ?? -1.0
        let isSelected = abs(current - value) < 0.05
        return Button {
            headWeights[head] = value
        } label: {
            VStack(spacing: 1) {
                Text(label)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(isSelected ? .white : .appTextSecondary)
                Text(value == 0 ? "0×" : String(format: "%.1f×", value))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(isSelected ? .white.opacity(0.85) : .appTextDim)
            }
            .padding(.horizontal, 5).padding(.vertical, 4)
            .background(isSelected ? Color.appRed : Color.appSurface2)
            .cornerRadius(5)
        }
        .buttonStyle(.plain)
    }
}
