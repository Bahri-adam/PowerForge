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
                            ExerciseRow(exercise: exercise, onDelete: exercise.isCustom ? {
                                deleteTarget = exercise
                                showDeleteConfirm = true
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

    init(exercise: Exercise, onDelete: (() -> Void)? = nil) {
        self.exercise = exercise
        self.onDelete = onDelete
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

    @State private var name = ""
    @State private var selectedMuscles: Set<String> = []
    @State private var selectedSecondary: Set<String> = []
    @State private var selectedEquipment: EquipmentType = .barbell
    @State private var selectedPattern: MovementPattern = .isolation
    @State private var isCompound = false

    let muscles = ExerciseDictionary.trackingMuscles + ["Core", "Traps", "Forearms"]

    var body: some View {
        ZStack {
            Color.appBG.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.appTextSecondary)
                    Spacer()
                    Text("ADD EXERCISE")
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
                    }
                    .padding(20)
                    .padding(.bottom, 40)
                }
            }
        }
    }

    func saveExercise() {
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
        modelContext.insert(exercise)
        dismiss()
    }
}
