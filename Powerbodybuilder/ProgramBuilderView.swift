import SwiftUI
import SwiftData

// ═══════════════════════════════════════════
// PROGRAM BUILDER — 4-step wizard
// ═══════════════════════════════════════════

struct ProgramBuilderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allExercises: [Exercise]
    @Query private var existingTemplates: [ProgramTemplate]

    @State private var step = 1
    @State private var programName = ""
    @State private var daysPerWeek = 4
    @State private var sessionTypes: [SessionType] = []
    @State private var sessionExercises: [SessionType: [BuilderExercise]] = [:]
    @State private var showExercisePicker = false
    @State private var pickingForSession: SessionType? = nil

    private let availableSessionTypes: [SessionType] = [
        .heavyUpper, .heavyLower, .hypertrophyUpper, .hypertrophyLower,
        .push, .pull, .legs, .fullBody, .fullBodyA, .fullBodyB,
        .upperPower, .lowerPower, .strengthHypertrophy,
        .legQuadFocus, .legsPosterior, .chestBack, .armsDelts, .chestArms, .legsVolume
    ]

    private var nextCustomId: Int {
        let existingIds = existingTemplates.map { $0.programId }
        let maxId = existingIds.max() ?? 0
        return max(100, maxId + 1)
    }

    var body: some View {
        ZStack {
            Color.appBG.ignoresSafeArea()

            VStack(spacing: 0) {
                builderHeader
                stepContent
            }
        }
        .sheet(isPresented: $showExercisePicker) {
            if let session = pickingForSession {
                ExercisePickerView(exercises: allExercises) { selected in
                    let builder = BuilderExercise(
                        exerciseKey: selected.exerciseKey,
                        displayName: selected.displayName,
                        isCompound: selected.isCompound,
                        role: selected.isCompound ? .supplemental : .accessory,
                        isMainLift: false,
                        targetSets: 3,
                        targetRepsLow: 8,
                        targetRepsHigh: 12,
                        targetRPE: 7.5,
                        restSeconds: 120
                    )
                    sessionExercises[session, default: []].append(builder)
                }
            }
        }
    }

    // ── Header ──

    private var builderHeader: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.appTextSecondary)

                Spacer()

                Text("BUILD PROGRAM")
                    .font(.system(size: 15, weight: .black))
                    .foregroundColor(.appTextPrimary)
                    .kerning(1)

                Spacer()

                if step > 1 {
                    Button("Back") { withAnimation { step -= 1 } }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.appTextSecondary)
                } else {
                    Text("").frame(width: 50)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.appSurface)

            // Step indicator
            HStack(spacing: 4) {
                ForEach(1...4, id: \.self) { s in
                    Capsule()
                        .fill(s <= step ? Color.appRed : Color.appSurface2)
                        .frame(height: 3)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color.appSurface)

            Rectangle().frame(height: 1).foregroundColor(.appBorder)
        }
    }

    // ── Step content ──

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 1: step1Basics
        case 2: step2Sessions
        case 3: step3Exercises
        case 4: step4Review
        default: EmptyView()
        }
    }

    // ═══════════════════════════════════════════
    // STEP 1 — NAME & DAYS
    // ═══════════════════════════════════════════

    private var step1Basics: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "PROGRAM NAME")
                    AppTextField(placeholder: "e.g. My Push Pull Legs", text: $programName, icon: "pencil")
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "DAYS PER WEEK")
                    HStack(spacing: 8) {
                        ForEach([3, 4, 5, 6], id: \.self) { d in
                            Button(action: {
                                daysPerWeek = d
                                // Trim sessions if too many
                                if sessionTypes.count > d {
                                    sessionTypes = Array(sessionTypes.prefix(d))
                                }
                            }) {
                                VStack(spacing: 2) {
                                    Text("\(d)")
                                        .font(.system(size: 22, weight: .black, design: .rounded))
                                        .foregroundColor(daysPerWeek == d ? .white : .appTextSecondary)
                                    Text("days")
                                        .font(.system(size: 10))
                                        .foregroundColor(daysPerWeek == d ? .white.opacity(0.8) : .appTextDim)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(daysPerWeek == d ? Color.appRed : Color.appSurface)
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(daysPerWeek == d ? Color.appRed : Color.appBorder, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                PrimaryButton(title: "NEXT", icon: "arrow.right") {
                    guard !programName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    withAnimation { step = 2 }
                }
                .opacity(programName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            }
            .padding(20)
        }
    }

    // ═══════════════════════════════════════════
    // STEP 2 — CHOOSE SESSION TYPES
    // ═══════════════════════════════════════════

    private var step2Sessions: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    SectionHeader(title: "CHOOSE \(daysPerWeek) SESSION TYPES")
                    Text("Pick the training days that make up your weekly rotation.")
                        .font(.system(size: 13)).foregroundColor(.appTextSecondary)
                }

                // Selected sessions
                if !sessionTypes.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(Array(sessionTypes.enumerated()), id: \.offset) { idx, st in
                            HStack(spacing: 12) {
                                Text("S\(idx + 1)")
                                    .font(.system(size: 11, weight: .black, design: .monospaced))
                                    .foregroundColor(.appRed)
                                    .frame(width: 30, height: 30)
                                    .background(Color.appRed.opacity(0.1))
                                    .cornerRadius(6)
                                Text(st.shortLabel)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.appTextPrimary)
                                Spacer()
                                Button(action: {
                                    sessionTypes.remove(at: idx)
                                    sessionExercises.removeValue(forKey: st)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(.appTextDim)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(12)
                            .background(Color.appSurface)
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))
                        }
                    }
                }

                // Available to add
                if sessionTypes.count < daysPerWeek {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TAP TO ADD")
                            .font(.system(size: 9, weight: .black))
                            .foregroundColor(.appTextDim)
                            .kerning(1.5)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(availableSessionTypes, id: \.self) { st in
                                Button(action: {
                                    if sessionTypes.count < daysPerWeek {
                                        sessionTypes.append(st)
                                    }
                                }) {
                                    Text(st.shortLabel)
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(sessionTypes.contains(st) ? .appTextDim : .appTextSecondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color.appSurface)
                                        .cornerRadius(8)
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorder, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                PrimaryButton(title: "NEXT — ADD EXERCISES", icon: "arrow.right") {
                    withAnimation { step = 3 }
                }
                .opacity(sessionTypes.count == daysPerWeek ? 1 : 0.5)
                .disabled(sessionTypes.count != daysPerWeek)
            }
            .padding(20)
        }
    }

    // ═══════════════════════════════════════════
    // STEP 3 — EXERCISES PER SESSION
    // ═══════════════════════════════════════════

    private var step3Exercises: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                ForEach(sessionTypes, id: \.self) { session in
                    VStack(spacing: 10) {
                        HStack {
                            SectionHeader(title: session.shortLabel)
                            Spacer()
                            Button(action: {
                                pickingForSession = session
                                showExercisePicker = true
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                                    Text("ADD").font(.system(size: 12, weight: .black))
                                }
                                .foregroundColor(.appRed)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.appRed.opacity(0.1))
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }

                        let exercises = sessionExercises[session] ?? []
                        if exercises.isEmpty {
                            HStack {
                                Image(systemName: "plus.circle.dashed")
                                    .font(.system(size: 16)).foregroundColor(.appTextDim)
                                Text("No exercises yet — tap ADD")
                                    .font(.system(size: 13)).foregroundColor(.appTextDim)
                                Spacer()
                            }
                            .padding(16)
                            .background(Color.appSurface)
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder.opacity(0.5), lineWidth: 1))
                        } else {
                            ForEach(Array(exercises.enumerated()), id: \.element.id) { idx, ex in
                                BuilderExerciseRow(
                                    exercise: binding(for: session, index: idx),
                                    index: idx,
                                    onRemove: {
                                        sessionExercises[session]?.remove(at: idx)
                                    },
                                    onMoveUp: idx > 0 ? {
                                        sessionExercises[session]?.swapAt(idx, idx - 1)
                                    } : nil,
                                    onMoveDown: idx < exercises.count - 1 ? {
                                        sessionExercises[session]?.swapAt(idx, idx + 1)
                                    } : nil
                                )
                            }
                        }
                    }
                }

                let totalExercises = sessionExercises.values.flatMap { $0 }.count
                PrimaryButton(title: "REVIEW PROGRAM", icon: "checkmark.circle") {
                    withAnimation { step = 4 }
                }
                .opacity(totalExercises > 0 ? 1 : 0.5)
                .disabled(totalExercises == 0)
            }
            .padding(20)
        }
    }

    private func binding(for session: SessionType, index: Int) -> Binding<BuilderExercise> {
        Binding(
            get: { sessionExercises[session]?[index] ?? BuilderExercise.empty },
            set: { sessionExercises[session]?[index] = $0 }
        )
    }

    // ═══════════════════════════════════════════
    // STEP 4 — REVIEW & CREATE
    // ═══════════════════════════════════════════

    private var step4Review: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // Summary card
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(programName.uppercased())
                                .font(.system(size: 18, weight: .black, design: .rounded))
                                .foregroundColor(.appTextPrimary)
                            Text("\(daysPerWeek) days/week · 24 weeks · Auto-periodized")
                                .font(.system(size: 12)).foregroundColor(.appTextSecondary)
                        }
                        Spacer()
                    }

                    Divider().background(Color.appBorder)

                    // Periodization preview
                    VStack(alignment: .leading, spacing: 6) {
                        Text("AUTO-PERIODIZATION")
                            .font(.system(size: 9, weight: .black)).foregroundColor(.appTextDim).kerning(1.5)
                        periodizationRow(label: "Weeks 1–8", block: "Accumulation", rpe: "RPE 7.0–7.5", color: .appGreen)
                        periodizationRow(label: "Week 4", block: "Deload", rpe: "RPE 6.0", color: .appBlue)
                        periodizationRow(label: "Weeks 9–16", block: "Intensification", rpe: "RPE 8.0–8.5", color: .appGold)
                        periodizationRow(label: "Week 12", block: "Deload", rpe: "RPE 6.5", color: .appBlue)
                        periodizationRow(label: "Weeks 17–23", block: "Peaking", rpe: "RPE 8.5–9.0", color: .appRed)
                        periodizationRow(label: "Week 20", block: "Deload", rpe: "RPE 6.5", color: .appBlue)
                        periodizationRow(label: "Week 24", block: "Testing", rpe: "RPE 9.5", color: .appRed)
                    }
                }
                .padding(16)
                .appCard()

                // Sessions breakdown
                ForEach(sessionTypes, id: \.self) { session in
                    VStack(spacing: 8) {
                        HStack {
                            SectionHeader(title: session.shortLabel)
                            Spacer()
                            let count = sessionExercises[session]?.count ?? 0
                            Text("\(count) exercises")
                                .font(.system(size: 11, weight: .bold)).foregroundColor(.appTextDim)
                        }
                        ForEach(sessionExercises[session] ?? [], id: \.id) { ex in
                            HStack(spacing: 10) {
                                Circle().fill(roleColor(ex.role)).frame(width: 8, height: 8)
                                Text(ex.displayName)
                                    .font(.system(size: 13, weight: .bold)).foregroundColor(.appTextPrimary)
                                Spacer()
                                Text("\(ex.targetSets)x\(ex.targetRepsLow)–\(ex.targetRepsHigh)")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(.appTextDim)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 8)
                        }
                    }
                    .padding(12)
                    .appCard()
                }

                PrimaryButton(title: "CREATE PROGRAM", icon: "bolt.fill") {
                    createProgram()
                }
                .padding(.bottom, 40)
            }
            .padding(20)
        }
    }

    private func periodizationRow(label: String, block: String, rpe: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.system(size: 11, weight: .bold)).foregroundColor(.appTextSecondary)
                .frame(width: 80, alignment: .leading)
            Text(block).font(.system(size: 11, weight: .black)).foregroundColor(color)
            Spacer()
            Text(rpe).font(.system(size: 10, weight: .bold)).foregroundColor(.appTextDim)
        }
    }

    private func roleColor(_ role: ExerciseRole) -> Color {
        switch role {
        case .mainLift: return .appRed
        case .supplemental: return .appGold
        case .accessory: return .appBlue
        case .finisher: return .appTextDim
        }
    }

    // ═══════════════════════════════════════════
    // CREATE PROGRAM — seeds all 24 weeks
    // ═══════════════════════════════════════════

    private func createProgram() {
        let pid = nextCustomId

        // 1. ProgramTemplate
        let template = ProgramTemplate(
            programId: pid,
            name: programName,
            version: 1,
            durationWeeks: 24,
            sessionTypes: sessionTypes,
            scheduleOptions: []
        )
        modelContext.insert(template)

        // 2. ProgramSessionTemplates — 24 weeks of periodized slots
        for week in 1...24 {
            let params = weekParams(week: week)
            for session in sessionTypes {
                let exercises = sessionExercises[session] ?? []
                for (idx, ex) in exercises.enumerated() {
                    let slotLetter = String(UnicodeScalar(65 + (sessionTypes.firstIndex(of: session) ?? 0))!)
                    let slotId = "\(slotLetter)\(idx + 1)"

                    let periodized = periodize(base: ex, params: params)

                    let slot = ProgramSessionTemplate(
                        programId: pid,
                        programVersion: 1,
                        week: week,
                        sessionType: session,
                        slotId: slotId,
                        exerciseIndex: idx,
                        exerciseKey: ex.exerciseKey,
                        role: ex.role,
                        isMainLift: ex.isMainLift,
                        targetSets: periodized.sets,
                        targetRepsLow: periodized.repsLow,
                        targetRepsHigh: periodized.repsHigh,
                        targetRPE: periodized.rpe,
                        restSeconds: periodized.rest,
                        notes: params.isDeload ? "Deload — reduce load ~40%" :
                               (params.isTesting ? "Testing week" : "")
                    )
                    modelContext.insert(slot)
                }
            }
        }

        // 3. Add to allPrograms for display
        // (Custom programs use ProgramTemplate directly — allPrograms is for built-in only)

        // 4. Legacy UserProgram
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let userProgram = UserProgram(
            programId: pid,
            name: programName,
            startDate: formatter.string(from: Date())
        )
        modelContext.insert(userProgram)

        // 5. UserProgramInstance
        let instance = UserProgramInstance(
            programId: pid,
            programVersion: 1,
            name: programName,
            missedWorkoutPolicy: .rotation
        )
        modelContext.insert(instance)

        // 6. Add to allPrograms runtime list
        let def = ProgramDef(
            id: pid,
            name: programName.uppercased(),
            subtitle: "Custom \(daysPerWeek)-Day Program",
            description: "Your custom \(daysPerWeek)-day program with auto-periodized progression over 24 weeks.",
            days: "\(daysPerWeek) days/week",
            sessionLength: "60–90 min",
            split: sessionTypes.map { $0.shortLabel }.joined(separator: " / "),
            difficulty: "Custom",
            icon: "hammer.fill",
            accentColor: .appRed,
            tags: ["Custom", "\(daysPerWeek)-Day"],
            repRanges: "Varies",
            volumePerMuscle: "Varies",
            whoItsFor: "You built this.",
            days_per_week_range: daysPerWeek...daysPerWeek
        )
        customPrograms.append(def)

        try? modelContext.save()
        dismiss()
    }

    // ── Periodization params per week ──

    private struct WeekPeriodization {
        let isDeload: Bool
        let isTesting: Bool
        let setsMultiplier: Double
        let rpeOffset: Double
        let repShift: Int  // negative = fewer reps (heavier), positive = more reps
        let restMultiplier: Double
    }

    private func weekParams(week: Int) -> WeekPeriodization {
        // Deload weeks
        if week == 4 || week == 12 || week == 20 {
            return WeekPeriodization(isDeload: true, isTesting: false,
                                     setsMultiplier: 0.6, rpeOffset: -1.5, repShift: 0, restMultiplier: 0.8)
        }
        // Testing week
        if week == 24 {
            return WeekPeriodization(isDeload: false, isTesting: true,
                                     setsMultiplier: 0.5, rpeOffset: 2.0, repShift: -4, restMultiplier: 1.5)
        }
        // Block 1 — Accumulation (1–8)
        if week <= 8 {
            let ramp = Double(week - 1) / 7.0 * 0.5
            return WeekPeriodization(isDeload: false, isTesting: false,
                                     setsMultiplier: 1.0, rpeOffset: ramp, repShift: 0, restMultiplier: 1.0)
        }
        // Block 2 — Intensification (9–16)
        if week <= 16 {
            let ramp = Double(week - 9) / 7.0 * 0.5
            return WeekPeriodization(isDeload: false, isTesting: false,
                                     setsMultiplier: 1.0, rpeOffset: 1.0 + ramp, repShift: -1, restMultiplier: 1.1)
        }
        // Block 3 — Peaking (17–23)
        let ramp = Double(week - 17) / 6.0 * 0.5
        return WeekPeriodization(isDeload: false, isTesting: false,
                                 setsMultiplier: 0.85, rpeOffset: 1.5 + ramp, repShift: -2, restMultiplier: 1.2)
    }

    private struct PeriodizedValues {
        let sets: Int
        let repsLow: Int
        let repsHigh: Int
        let rpe: Double
        let rest: Int
    }

    private func periodize(base: BuilderExercise, params: WeekPeriodization) -> PeriodizedValues {
        let sets = max(1, Int(round(Double(base.targetSets) * params.setsMultiplier)))
        let repsLow = max(1, base.targetRepsLow + params.repShift)
        let repsHigh = max(repsLow, base.targetRepsHigh + params.repShift)
        let rpe = min(10.0, max(5.0, base.targetRPE + params.rpeOffset))
        let rest = Int(Double(base.restSeconds) * params.restMultiplier)
        return PeriodizedValues(sets: sets, repsLow: repsLow, repsHigh: repsHigh, rpe: rpe, rest: rest)
    }
}

// ═══════════════════════════════════════════
// RUNTIME CUSTOM PROGRAMS STORE
// ═══════════════════════════════════════════

var customPrograms: [ProgramDef] = []

var allAvailablePrograms: [ProgramDef] {
    allPrograms + customPrograms
}

// ═══════════════════════════════════════════
// BUILDER EXERCISE MODEL (in-memory)
// ═══════════════════════════════════════════

struct BuilderExercise: Identifiable, Codable {
    var id = UUID()
    var exerciseKey: String
    var displayName: String
    var isCompound: Bool
    var role: ExerciseRole
    var isMainLift: Bool
    var targetSets: Int
    var targetRepsLow: Int
    var targetRepsHigh: Int
    var targetRPE: Double
    var restSeconds: Int
    var notes: String = ""

    enum CodingKeys: String, CodingKey {
        case exerciseKey, displayName, isCompound, role, isMainLift
        case targetSets, targetRepsLow, targetRepsHigh, targetRPE, restSeconds, notes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        exerciseKey = try c.decode(String.self, forKey: .exerciseKey)
        displayName = try c.decode(String.self, forKey: .displayName)
        isCompound = try c.decode(Bool.self, forKey: .isCompound)
        role = try c.decode(ExerciseRole.self, forKey: .role)
        isMainLift = try c.decode(Bool.self, forKey: .isMainLift)
        targetSets = try c.decode(Int.self, forKey: .targetSets)
        targetRepsLow = try c.decode(Int.self, forKey: .targetRepsLow)
        targetRepsHigh = try c.decode(Int.self, forKey: .targetRepsHigh)
        targetRPE = try c.decode(Double.self, forKey: .targetRPE)
        restSeconds = try c.decode(Int.self, forKey: .restSeconds)
        notes = (try? c.decode(String.self, forKey: .notes)) ?? ""
    }

    init(exerciseKey: String, displayName: String, isCompound: Bool, role: ExerciseRole, isMainLift: Bool,
         targetSets: Int, targetRepsLow: Int, targetRepsHigh: Int, targetRPE: Double, restSeconds: Int,
         notes: String = "") {
        self.id = UUID()
        self.exerciseKey = exerciseKey
        self.displayName = displayName
        self.isCompound = isCompound
        self.role = role
        self.isMainLift = isMainLift
        self.targetSets = targetSets
        self.targetRepsLow = targetRepsLow
        self.targetRepsHigh = targetRepsHigh
        self.targetRPE = targetRPE
        self.restSeconds = restSeconds
        self.notes = notes
    }

    static let empty = BuilderExercise(
        exerciseKey: "", displayName: "", isCompound: false,
        role: .accessory, isMainLift: false,
        targetSets: 3, targetRepsLow: 8, targetRepsHigh: 12,
        targetRPE: 7.5, restSeconds: 120
    )
}

// ═══════════════════════════════════════════
// BUILDER EXERCISE ROW — editable parameters
// ═══════════════════════════════════════════

struct BuilderExerciseRow: View {
    @Binding var exercise: BuilderExercise
    let index: Int
    let onRemove: () -> Void
    let onMoveUp: (() -> Void)?
    let onMoveDown: (() -> Void)?

    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Exercise header
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack(spacing: 10) {
                    Text("\(index + 1)")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundColor(.appRed)
                        .frame(width: 26, height: 26)
                        .background(Color.appRed.opacity(0.1))
                        .cornerRadius(6)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.displayName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.appTextPrimary)
                        Text("\(exercise.targetSets) sets · \(exercise.targetRepsLow)–\(exercise.targetRepsHigh) reps · RPE \(String(format: "%.1f", exercise.targetRPE))")
                            .font(.system(size: 11))
                            .foregroundColor(.appTextDim)
                    }
                    Spacer()

                    HStack(spacing: 4) {
                        if let up = onMoveUp {
                            Button(action: up) {
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 10, weight: .bold)).foregroundColor(.appTextDim)
                                    .frame(width: 34, height: 34).contentShape(Rectangle()).background(Color.appSurface2).cornerRadius(6)
                            }.buttonStyle(.plain)
                        }
                        if let down = onMoveDown {
                            Button(action: down) {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .bold)).foregroundColor(.appTextDim)
                                    .frame(width: 34, height: 34).contentShape(Rectangle()).background(Color.appSurface2).cornerRadius(6)
                            }.buttonStyle(.plain)
                        }
                        Button(action: onRemove) {
                            Image(systemName: "trash")
                                .font(.system(size: 10, weight: .bold)).foregroundColor(.appRed.opacity(0.7))
                                .frame(width: 34, height: 34).contentShape(Rectangle()).background(Color.appRed.opacity(0.08)).cornerRadius(6)
                        }.buttonStyle(.plain)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold)).foregroundColor(.appTextDim)
                }
            }
            .buttonStyle(.plain)
            .padding(12)

            if isExpanded {
                Divider().background(Color.appBorder)
                expandedEditor
            }
        }
        .background(Color.appSurface)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))
    }

    private var expandedEditor: some View {
        VStack(spacing: 14) {
            // Role picker
            VStack(alignment: .leading, spacing: 6) {
                Text("ROLE").font(.system(size: 9, weight: .black)).foregroundColor(.appTextDim).kerning(1)
                HStack(spacing: 6) {
                    ForEach([ExerciseRole.mainLift, .supplemental, .accessory, .finisher], id: \.rawValue) { role in
                        Button(action: {
                            exercise.role = role
                            exercise.isMainLift = (role == .mainLift)
                        }) {
                            Text(role.rawValue.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(exercise.role == role ? .white : .appTextSecondary)
                                .padding(.horizontal, 8).padding(.vertical, 6)
                                .background(exercise.role == role ? Color.appRed : Color.appSurface2)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Sets
            HStack {
                Text("SETS").font(.system(size: 9, weight: .black)).foregroundColor(.appTextDim).kerning(1)
                Spacer()
                HStack(spacing: 8) {
                    Button(action: { exercise.targetSets = max(1, exercise.targetSets - 1) }) {
                        Image(systemName: "minus").font(.system(size: 12, weight: .bold)).foregroundColor(.appTextDim)
                            .frame(width: 30, height: 30).background(Color.appSurface2).cornerRadius(6)
                    }.buttonStyle(.plain)
                    Text("\(exercise.targetSets)")
                        .font(.system(size: 18, weight: .black, design: .rounded)).foregroundColor(.appTextPrimary)
                        .frame(width: 30)
                    Button(action: { exercise.targetSets = min(8, exercise.targetSets + 1) }) {
                        Image(systemName: "plus").font(.system(size: 12, weight: .bold)).foregroundColor(.appTextDim)
                            .frame(width: 30, height: 30).background(Color.appSurface2).cornerRadius(6)
                    }.buttonStyle(.plain)
                }
            }

            // Rep range
            HStack {
                Text("REP RANGE").font(.system(size: 9, weight: .black)).foregroundColor(.appTextDim).kerning(1)
                Spacer()
                HStack(spacing: 6) {
                    stepperField(value: $exercise.targetRepsLow, range: 1...30)
                    Text("–").foregroundColor(.appTextDim)
                    stepperField(value: $exercise.targetRepsHigh, range: 1...30)
                }
            }

            // RPE
            HStack {
                Text("TARGET RPE").font(.system(size: 9, weight: .black)).foregroundColor(.appTextDim).kerning(1)
                Spacer()
                HStack(spacing: 8) {
                    Button(action: { exercise.targetRPE = max(5, exercise.targetRPE - 0.5) }) {
                        Image(systemName: "minus").font(.system(size: 12, weight: .bold)).foregroundColor(.appTextDim)
                            .frame(width: 30, height: 30).background(Color.appSurface2).cornerRadius(6)
                    }.buttonStyle(.plain)
                    Text(String(format: "%.1f", exercise.targetRPE))
                        .font(.system(size: 18, weight: .black, design: .rounded)).foregroundColor(.appTextPrimary)
                        .frame(width: 40)
                    Button(action: { exercise.targetRPE = min(10, exercise.targetRPE + 0.5) }) {
                        Image(systemName: "plus").font(.system(size: 12, weight: .bold)).foregroundColor(.appTextDim)
                            .frame(width: 30, height: 30).background(Color.appSurface2).cornerRadius(6)
                    }.buttonStyle(.plain)
                }
            }

            // Rest
            HStack {
                Text("REST (sec)").font(.system(size: 9, weight: .black)).foregroundColor(.appTextDim).kerning(1)
                Spacer()
                HStack(spacing: 6) {
                    ForEach([60, 90, 120, 180, 240], id: \.self) { sec in
                        Button(action: { exercise.restSeconds = sec }) {
                            Text("\(sec)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(exercise.restSeconds == sec ? .white : .appTextSecondary)
                                .padding(.horizontal, 8).padding(.vertical, 6)
                                .background(exercise.restSeconds == sec ? Color.appRed : Color.appSurface2)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
    }

    private func stepperField(value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 4) {
            Button(action: { value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1) }) {
                Image(systemName: "minus").font(.system(size: 10, weight: .bold)).foregroundColor(.appTextDim)
                    .frame(width: 34, height: 34).contentShape(Rectangle()).background(Color.appSurface2).cornerRadius(6)
            }.buttonStyle(.plain)
            Text("\(value.wrappedValue)")
                .font(.system(size: 16, weight: .black, design: .rounded)).foregroundColor(.appTextPrimary)
                .frame(width: 28)
            Button(action: { value.wrappedValue = min(range.upperBound, value.wrappedValue + 1) }) {
                Image(systemName: "plus").font(.system(size: 10, weight: .bold)).foregroundColor(.appTextDim)
                    .frame(width: 34, height: 34).contentShape(Rectangle()).background(Color.appSurface2).cornerRadius(6)
            }.buttonStyle(.plain)
        }
    }
}

// ═══════════════════════════════════════════
// EXERCISE PICKER — browse & select from library
// ═══════════════════════════════════════════

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let exercises: [Exercise]
    let onSelect: (Exercise) -> Void

    @State private var searchText = ""
    @State private var selectedMuscle: String? = nil

    private let muscles = ExerciseDictionary.trackingMuscles

    private var filtered: [Exercise] {
        var result = exercises
        if let muscle = selectedMuscle {
            result = result.filter { ex in
                let priNorm = ex.musclesPrimary.compactMap { ExerciseDictionary.normalizeMuscle($0) }
                let secNorm = ex.musclesSecondary.compactMap { ExerciseDictionary.normalizeMuscle($0) }
                let def = ExerciseDictionary.all[ex.exerciseKey]
                let addlNorm = (def?.additionalFilterMuscles ?? []).compactMap { ExerciseDictionary.normalizeMuscle($0) }
                return priNorm.contains(muscle) || secNorm.contains(muscle) || addlNorm.contains(muscle)
            }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter { $0.displayName.lowercased().contains(q) }
        }
        return result.sorted { $0.displayName < $1.displayName }
    }

    var body: some View {
        ZStack {
            Color.appBG.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.appRed)
                    Spacer()
                    Text("ADD EXERCISE")
                        .font(.system(size: 15, weight: .black))
                        .foregroundColor(.appTextPrimary)
                        .kerning(1)
                    Spacer()
                    Text("").frame(width: 50) // balance
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color.appSurface)
                .overlay(Rectangle().frame(height: 1).foregroundColor(.appBorder), alignment: .bottom)

                // Search
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundColor(.appTextDim)
                    TextField("Search exercises...", text: $searchText)
                        .font(.system(size: 15)).foregroundColor(.appTextPrimary)
                }
                .padding(12)
                .background(Color.appSurface2)
                .cornerRadius(10)
                .padding(.horizontal, 16).padding(.top, 12)

                // Muscle filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Button(action: { selectedMuscle = nil }) {
                            Text("ALL")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(selectedMuscle == nil ? .white : .appTextSecondary)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(selectedMuscle == nil ? Color.appRed : Color.appSurface2)
                                .cornerRadius(6)
                        }.buttonStyle(.plain)

                        ForEach(muscles, id: \.self) { muscle in
                            Button(action: { selectedMuscle = muscle }) {
                                Text(muscle.uppercased())
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(selectedMuscle == muscle ? .white : .appTextSecondary)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(selectedMuscle == muscle ? Color.appRed : Color.appSurface2)
                                    .cornerRadius(6)
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 8)

                // Exercise list
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(filtered) { exercise in
                            Button(action: {
                                onSelect(exercise)
                                dismiss()
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: exercise.isCompound ? "circle.grid.cross.fill" : "circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(exercise.isCompound ? .appGold : .appBlue)
                                        .frame(width: 24)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(exercise.displayName)
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(.appTextPrimary)
                                        Text(exercise.musclesPrimary.joined(separator: ", "))
                                            .font(.system(size: 11))
                                            .foregroundColor(.appTextDim)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle")
                                        .font(.system(size: 16))
                                        .foregroundColor(.appRed)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                            Divider().background(Color.appBorder).padding(.leading, 52)
                        }
                    }
                }
            }
        }
    }
}
