import SwiftUI
import SwiftData

// ═══════════════════════════════════════════
// HELPER — Sheet item for day assignment
// ═══════════════════════════════════════════

struct DayAssignmentItem: Identifiable {
    let id: Int
    let dow: Int
    init(dow: Int) { self.id = dow; self.dow = dow }
}

// ═══════════════════════════════════════════
// DAY ASSIGNMENT SHEET
// ═══════════════════════════════════════════
// Presented when tapping a day row in WeekHubSheet.
// Shows Rest, Program Sessions, and My Templates.

struct DayAssignmentSheet: View {
    let dow: Int
    let instance: UserProgramInstance
    let week: Int
    let permanent: Bool
    let onAssign: (SessionType, String?) -> Void
    let onDismiss: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var allTemplates: [ProgramSessionTemplate]
    @Query private var dayTemplates: [DayTemplate]
    @Query private var programTemplates: [ProgramTemplate]

    @State private var showCreateTemplate = false

    private let dayNames = ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"]

    private var rotation: [SessionType] {
        sessionRotation(for: instance.programId, templates: programTemplates)
    }

    private func exerciseCount(for st: SessionType) -> Int {
        allTemplates.filter { $0.programId == instance.programId && $0.week == week && $0.sessionType == st }.count
    }

    var body: some View {
        ZStack {
            Color.appBG.ignoresSafeArea()
            VStack(spacing: 0) {
                // Drag handle
                RoundedRectangle(cornerRadius: 3).fill(Color.appBorder)
                    .frame(width: 36, height: 4).padding(.top, 12)

                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ASSIGN DAY")
                            .font(.system(size: 11, weight: .bold)).foregroundColor(.appRed).kerning(2)
                        Text(dayNames[dow - 1])
                            .font(.system(size: 20, weight: .black, design: .rounded)).foregroundColor(.appTextPrimary)
                        Text(permanent ? "Applies to all weeks" : "Week \(week) only")
                            .font(.system(size: 11)).foregroundColor(.appTextDim)
                    }
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold)).foregroundColor(.appTextSecondary)
                            .frame(width: 32, height: 32).background(Color.appSurface2).clipShape(Circle())
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(Color.appSurface)
                .overlay(Rectangle().frame(height: 1).foregroundColor(.appBorder), alignment: .bottom)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        // Section 1 — Rest
                        restSection

                        // Section 2 — Program Sessions
                        programSessionsSection

                        // Section 3 — My Templates
                        myTemplatesSection
                    }
                    .padding(16).padding(.bottom, 40)
                }
            }
        }
        .sheet(isPresented: $showCreateTemplate) {
            DayTemplateCreatorSheet()
        }
    }

    // ── Rest ────────────────────────────────────────────────────────────

    private var restSection: some View {
        VStack(spacing: 8) {
            SectionHeader(title: "REST")
            Button(action: { onAssign(.rest, nil) }) {
                HStack(spacing: 12) {
                    Image(systemName: "moon.fill").font(.system(size: 18)).foregroundColor(.appTextDim)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rest Day").font(.system(size: 14, weight: .black)).foregroundColor(.appTextPrimary)
                        Text("Recovery · No training").font(.system(size: 11)).foregroundColor(.appTextDim)
                    }
                    Spacer()
                }
                .padding(14)
                .background(Color.appSurface).cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    // ── Program Sessions ────────────────────────────────────────────────

    private var programSessionsSection: some View {
        VStack(spacing: 8) {
            SectionHeader(title: "PROGRAM SESSIONS")
            ForEach(rotation, id: \.self) { st in
                let count = exerciseCount(for: st)
                Button(action: { onAssign(st, nil) }) {
                    HStack(spacing: 0) {
                        Rectangle().fill(st.sessionColor).frame(width: 3, height: 42).cornerRadius(1.5)
                            .padding(.trailing, 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(st.shortLabel).font(.system(size: 13, weight: .black)).foregroundColor(.appTextPrimary)
                            Text(st.muscleSubtitle).font(.system(size: 10)).foregroundColor(.appTextDim).lineLimit(1)
                        }
                        Spacer()
                        if count > 0 {
                            Text("\(count) exercises")
                                .font(.system(size: 10, weight: .bold)).foregroundColor(.appTextDim)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.appSurface2).cornerRadius(5)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color.appSurface).cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // ── My Templates ────────────────────────────────────────────────────

    private var myTemplatesSection: some View {
        VStack(spacing: 8) {
            SectionHeader(title: "MY TEMPLATES")

            if dayTemplates.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "dumbbell.fill").font(.system(size: 24)).foregroundColor(.appTextDim)
                    Text("No templates yet").font(.system(size: 14, weight: .bold)).foregroundColor(.appTextSecondary)
                    Text("Create reusable day templates below.")
                        .font(.system(size: 12)).foregroundColor(.appTextDim)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 20)
                .background(Color.appSurface).cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
            } else {
                ForEach(dayTemplates, id: \.templateId) { template in
                    Button(action: { onAssign(.freeform, template.templateId.uuidString) }) {
                        HStack(spacing: 0) {
                            Rectangle().fill(templateColor(template.colorHex)).frame(width: 3, height: 42).cornerRadius(1.5)
                                .padding(.trailing, 10)
                            Image(systemName: template.iconName).font(.system(size: 16))
                                .foregroundColor(templateColor(template.colorHex)).frame(width: 28)
                                .padding(.trailing, 8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.name).font(.system(size: 13, weight: .black)).foregroundColor(.appTextPrimary)
                                let exNames = template.exercises.prefix(3).map { $0.displayName }
                                let preview = exNames.joined(separator: " · ")
                                let more = template.exercises.count > 3 ? " +\(template.exercises.count - 3) more" : ""
                                Text(preview + more).font(.system(size: 10)).foregroundColor(.appTextDim).lineLimit(1)
                            }
                            Spacer()
                            Text("\(template.exercises.count) exercises")
                                .font(.system(size: 10, weight: .bold)).foregroundColor(.appTextDim)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.appSurface2).cornerRadius(5)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Color.appSurface).cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Create template button
            Button(action: { showCreateTemplate = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill").font(.system(size: 16))
                    Text("CREATE TEMPLATE").font(.system(size: 12, weight: .black)).kerning(0.5)
                }
                .foregroundColor(.appBlue)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(Color.appSurface2).cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBlue.opacity(0.2), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }
}

// ═══════════════════════════════════════════
// COLOR HELPER
// ═══════════════════════════════════════════

func templateColor(_ hex: String) -> Color {
    switch hex {
    case "appRed":    return .appRed
    case "appBlue":   return .appBlue
    case "appGold":   return .appGold
    case "appGreen":  return .appGreen
    case "appOrange": return .appOrange
    default:          return .appRed
    }
}

// ═══════════════════════════════════════════
// DAY TEMPLATE CREATOR SHEET
// ═══════════════════════════════════════════

struct DayTemplateCreatorSheet: View {
    var editingTemplate: DayTemplate? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allExercises: [Exercise]

    @State private var step = 1
    @State private var templateName = ""
    @State private var selectedColor = "appRed"
    @State private var selectedIcon = "dumbbell.fill"
    @State private var exercises: [BuilderExercise] = []

    private let colorOptions = ["appRed", "appBlue", "appGold", "appGreen", "appOrange", "appTextSecondary"]
    private let iconOptions = ["dumbbell.fill", "figure.strengthtraining.traditional", "bolt.fill",
                                "flame.fill", "arrow.up.circle.fill", "heart.fill", "star.fill", "checkmark.seal.fill"]

    var body: some View {
        ZStack {
            Color.appBG.ignoresSafeArea()
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(editingTemplate != nil ? "EDIT TEMPLATE" : "NEW TEMPLATE")
                            .font(.system(size: 11, weight: .bold)).foregroundColor(.appRed).kerning(2)
                        Text("Step \(step) of 3")
                            .font(.system(size: 18, weight: .black, design: .rounded)).foregroundColor(.appTextPrimary)
                    }
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold)).foregroundColor(.appTextSecondary)
                            .frame(width: 32, height: 32).background(Color.appSurface2).clipShape(Circle())
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(Color.appSurface)
                .overlay(Rectangle().frame(height: 1).foregroundColor(.appBorder), alignment: .bottom)

                // Steps
                switch step {
                case 1: stepOneName
                case 2: stepTwoExercises
                default: stepThreeReview
                }
            }
        }
        .onAppear {
            if let t = editingTemplate {
                templateName = t.name
                selectedColor = t.colorHex
                selectedIcon = t.iconName
                exercises = t.exercises
            }
        }
    }

    // ── Step 1 — Name & Style ───────────────────────────────────────────

    private var stepOneName: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("TEMPLATE NAME").font(.system(size: 10, weight: .bold)).foregroundColor(.appTextDim).kerning(1.5)
                    TextField("e.g. Push Day Variation", text: $templateName)
                        .font(.system(size: 16, weight: .bold)).foregroundColor(.appTextPrimary)
                        .padding(14)
                        .background(Color.appSurface2).cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("COLOR").font(.system(size: 10, weight: .bold)).foregroundColor(.appTextDim).kerning(1.5)
                    HStack(spacing: 12) {
                        ForEach(colorOptions, id: \.self) { hex in
                            Button(action: { selectedColor = hex }) {
                                ZStack {
                                    Circle().fill(templateColor(hex)).frame(width: 36, height: 36)
                                    if selectedColor == hex {
                                        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("ICON").font(.system(size: 10, weight: .bold)).foregroundColor(.appTextDim).kerning(1.5)
                    HStack(spacing: 10) {
                        ForEach(iconOptions, id: \.self) { icon in
                            Button(action: { selectedIcon = icon }) {
                                Image(systemName: icon).font(.system(size: 18))
                                    .foregroundColor(selectedIcon == icon ? templateColor(selectedColor) : .appTextDim)
                                    .frame(width: 40, height: 40)
                                    .background(selectedIcon == icon ? templateColor(selectedColor).opacity(0.15) : Color.appSurface2)
                                    .cornerRadius(8)
                            }.buttonStyle(.plain)
                        }
                    }
                }

                Spacer(minLength: 40)

                PrimaryButton(title: "NEXT — ADD EXERCISES", icon: "arrow.right") {
                    step = 2
                }
                .opacity(templateName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                .disabled(templateName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16).padding(.bottom, 40)
        }
    }

    // ── Step 2 — Exercises ──────────────────────────────────────────────

    @State private var showExercisePicker = false
    @State private var showCreateCustom = false
    @State private var expandedExerciseId: UUID? = nil

    private var stepTwoExercises: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    if exercises.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "plus.circle").font(.system(size: 32)).foregroundColor(.appTextDim)
                            Text("No exercises added").font(.system(size: 14, weight: .bold)).foregroundColor(.appTextSecondary)
                            Text("Tap below to add exercises from your library.")
                                .font(.system(size: 12)).foregroundColor(.appTextDim)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 30)
                        .appCard()
                    } else {
                        ForEach(Array(exercises.enumerated()), id: \.element.id) { idx, ex in
                            templateExerciseCard(idx: idx, ex: ex)
                        }
                    }

                    // Add exercise + Create custom
                    HStack(spacing: 8) {
                        Button(action: { showExercisePicker = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill").font(.system(size: 15))
                                Text("ADD EXERCISE").font(.system(size: 12, weight: .black)).kerning(0.5)
                            }
                            .foregroundColor(.appRed)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Color.appRed.opacity(0.08)).cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appRed.opacity(0.25), lineWidth: 1))
                        }.buttonStyle(.plain)

                        Button(action: { showCreateCustom = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "star.circle.fill").font(.system(size: 15))
                                Text("CREATE CUSTOM").font(.system(size: 12, weight: .black)).kerning(0.5)
                            }
                            .foregroundColor(.appGold)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Color.appGold.opacity(0.08)).cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appGold.opacity(0.25), lineWidth: 1))
                        }.buttonStyle(.plain)
                    }

                    // Exercise count
                    if !exercises.isEmpty {
                        HStack {
                            Text("\(exercises.count) exercise\(exercises.count == 1 ? "" : "s")")
                                .font(.system(size: 11, weight: .bold)).foregroundColor(.appTextDim)
                            Spacer()
                            let totalSets = exercises.reduce(0) { $0 + $1.targetSets }
                            Text("\(totalSets) total sets")
                                .font(.system(size: 11, weight: .bold)).foregroundColor(.appTextDim)
                        }.padding(.horizontal, 4).padding(.top, 4)
                    }
                }
                .padding(16).padding(.bottom, 40)
            }

            // Bottom bar
            VStack(spacing: 0) {
                Divider().background(Color.appBorder)
                HStack(spacing: 12) {
                    Button(action: { step = 1 }) {
                        Text("BACK").font(.system(size: 13, weight: .black)).kerning(0.5)
                            .foregroundColor(.appTextSecondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Color.appSurface2).cornerRadius(10)
                    }.buttonStyle(.plain)

                    PrimaryButton(title: "REVIEW", icon: "checkmark") {
                        step = 3
                    }
                    .opacity(exercises.isEmpty ? 0.4 : 1)
                    .disabled(exercises.isEmpty)
                }
                .padding(.horizontal, 16).padding(.vertical, 14).background(Color.appBG)
            }
        }
        .sheet(isPresented: $showExercisePicker) {
            TemplateExercisePickerView(exercises: allExercises) { ex in
                let def = ExerciseDictionary.all[ex.exerciseKey]
                let stretch = def?.stretchPosition ?? .mid
                let defaultRest = ex.isCompound ? 180 : 90
                let builder = BuilderExercise(
                    exerciseKey: ex.exerciseKey,
                    displayName: ex.displayName,
                    isCompound: ex.isCompound,
                    role: .accessory,
                    isMainLift: false,
                    targetSets: 3,
                    targetRepsLow: 8,
                    targetRepsHigh: 12,
                    targetRPE: 0,
                    restSeconds: defaultRest,
                    notes: stretch == .lengthened ? "Focus on deep stretch at bottom" : ""
                )
                exercises.append(builder)
                expandedExerciseId = builder.id
                showExercisePicker = false
            }
        }
        .sheet(isPresented: $showCreateCustom) {
            AddExerciseView()
        }
    }

    private func templateExerciseCard(idx: Int, ex: BuilderExercise) -> some View {
        let isExpanded = expandedExerciseId == ex.id
        let def = ExerciseDictionary.all[ex.exerciseKey]
        let stretch = def?.stretchPosition ?? .mid
        let muscles = def?.primaryMuscles.joined(separator: ", ") ?? ""

        return VStack(spacing: 0) {
            // Header — always visible, tap to expand
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedExerciseId = isExpanded ? nil : ex.id
                }
            } label: {
                HStack(spacing: 10) {
                    Text("\(idx + 1)").font(.system(size: 10, weight: .black, design: .monospaced)).foregroundColor(.appRed)
                        .frame(width: 30, height: 30).background(Color.appRed.opacity(0.1)).cornerRadius(6)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(ex.displayName).font(.system(size: 13, weight: .black)).foregroundColor(.appTextPrimary)
                                .lineLimit(1)
                            // Stretch badge
                            Text(stretch.rawValue.uppercased())
                                .font(.system(size: 7, weight: .black))
                                .foregroundColor(stretchColor(stretch))
                                .padding(.horizontal, 4).padding(.vertical, 2)
                                .background(stretchColor(stretch).opacity(0.12)).cornerRadius(3)
                        }
                        HStack(spacing: 4) {
                            Text("\(ex.targetSets)×\(ex.targetRepsLow)-\(ex.targetRepsHigh)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.appTextSecondary)
                            if ex.targetRPE > 0 {
                                Text("RPE \(String(format: "%.0f", ex.targetRPE))")
                                    .font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim)
                            }
                            if !muscles.isEmpty {
                                Text("· \(muscles)").font(.system(size: 9)).foregroundColor(.appTextDim).lineLimit(1)
                            }
                        }
                    }
                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold)).foregroundColor(.appTextDim)
                }
            }.buttonStyle(.plain)
            .padding(12)

            // Expanded editor
            if isExpanded {
                Divider().background(Color.appBorder)

                VStack(spacing: 14) {
                    // Sets
                    paramRow(label: "SETS", value: "\(ex.targetSets)") {
                        stepper(value: Binding(get: { exercises[idx].targetSets }, set: { exercises[idx].targetSets = $0 }),
                                range: 1...10, color: .appRed)
                    }

                    // Rep range
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("REP RANGE").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim).kerning(1)
                            Text("\(ex.targetRepsLow) – \(ex.targetRepsHigh)")
                                .font(.system(size: 16, weight: .black, design: .rounded)).foregroundColor(.appTextPrimary)
                        }
                        Spacer()
                        VStack(spacing: 2) {
                            Text("LOW").font(.system(size: 7, weight: .bold)).foregroundColor(.appTextDim)
                            stepper(value: Binding(get: { exercises[idx].targetRepsLow }, set: { exercises[idx].targetRepsLow = $0 }),
                                    range: 1...30, color: .appBlue)
                        }
                        VStack(spacing: 2) {
                            Text("HIGH").font(.system(size: 7, weight: .bold)).foregroundColor(.appTextDim)
                            stepper(value: Binding(get: { exercises[idx].targetRepsHigh }, set: { exercises[idx].targetRepsHigh = $0 }),
                                    range: 1...30, color: .appBlue)
                        }.padding(.leading, 8)
                    }

                    // RPE (optional)
                    paramRow(label: "RPE (OPTIONAL)", value: ex.targetRPE > 0 ? String(format: "%.0f", ex.targetRPE) : "Off") {
                        HStack(spacing: 6) {
                            if ex.targetRPE > 0 {
                                Button { exercises[idx].targetRPE = 0 } label: {
                                    Text("Off").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim)
                                        .frame(width: 28, height: 26).background(Color.appSurface2).cornerRadius(5)
                                }.buttonStyle(.plain)
                            }
                            stepper(value: Binding(
                                get: { Int(exercises[idx].targetRPE) },
                                set: { exercises[idx].targetRPE = Double($0) }),
                                range: 5...10, color: .appOrange)
                        }
                    }

                    // Rest
                    paramRow(label: "REST", value: restLabel(ex.restSeconds)) {
                        HStack(spacing: 6) {
                            ForEach([60, 90, 120, 180], id: \.self) { sec in
                                Button { exercises[idx].restSeconds = sec } label: {
                                    Text(restLabel(sec))
                                        .font(.system(size: 10, weight: ex.restSeconds == sec ? .black : .medium))
                                        .foregroundColor(ex.restSeconds == sec ? .white : .appTextSecondary)
                                        .padding(.horizontal, 8).padding(.vertical, 5)
                                        .background(ex.restSeconds == sec ? Color.appBlue : Color.appSurface2).cornerRadius(5)
                                }.buttonStyle(.plain)
                            }
                        }
                    }

                    // Notes / Cues
                    VStack(alignment: .leading, spacing: 4) {
                        Text("NOTES / CUES").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim).kerning(1)
                        TextField("e.g. Pause at bottom, squeeze at top", text: Binding(
                            get: { exercises[idx].notes },
                            set: { exercises[idx].notes = $0 }
                        ))
                        .font(.system(size: 13)).foregroundColor(.appTextPrimary)
                        .padding(10)
                        .background(Color.appBG).cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorder, lineWidth: 1))
                    }

                    // Actions
                    HStack(spacing: 10) {
                        if idx > 0 {
                            Button { exercises.swapAt(idx, idx - 1) } label: {
                                Image(systemName: "arrow.up").font(.system(size: 11, weight: .bold)).foregroundColor(.appTextDim)
                                    .frame(width: 32, height: 28).background(Color.appSurface2).cornerRadius(6)
                            }.buttonStyle(.plain)
                        }
                        if idx < exercises.count - 1 {
                            Button { exercises.swapAt(idx, idx + 1) } label: {
                                Image(systemName: "arrow.down").font(.system(size: 11, weight: .bold)).foregroundColor(.appTextDim)
                                    .frame(width: 32, height: 28).background(Color.appSurface2).cornerRadius(6)
                            }.buttonStyle(.plain)
                        }
                        Spacer()
                        Button {
                            withAnimation { let _ = exercises.remove(at: idx) }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "trash").font(.system(size: 10, weight: .bold))
                                Text("Remove").font(.system(size: 10, weight: .bold))
                            }
                            .foregroundColor(.appRed)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.appRed.opacity(0.06)).cornerRadius(6)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 12)
            }
        }
        .background(Color.appSurface).cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(
            isExpanded ? Color.appRed.opacity(0.3) : Color.appBorder, lineWidth: 1))
    }

    // ── Template exercise card helpers ──

    private func paramRow(label: String, value: String, @ViewBuilder controls: () -> some View) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim).kerning(1)
                Text(value).font(.system(size: 16, weight: .black, design: .rounded)).foregroundColor(.appTextPrimary)
            }
            Spacer()
            controls()
        }
    }

    private func stepper(value: Binding<Int>, range: ClosedRange<Int>, color: Color) -> some View {
        HStack(spacing: 6) {
            Button { if value.wrappedValue > range.lowerBound { value.wrappedValue -= 1 } } label: {
                Image(systemName: "minus").font(.system(size: 11, weight: .bold)).foregroundColor(color)
                    .frame(width: 30, height: 26).background(color.opacity(0.06)).cornerRadius(5)
            }.buttonStyle(.plain)
            Text("\(value.wrappedValue)").font(.system(size: 14, weight: .black, design: .rounded)).foregroundColor(.appTextPrimary)
                .frame(width: 22)
            Button { if value.wrappedValue < range.upperBound { value.wrappedValue += 1 } } label: {
                Image(systemName: "plus").font(.system(size: 11, weight: .bold)).foregroundColor(color)
                    .frame(width: 30, height: 26).background(color.opacity(0.06)).cornerRadius(5)
            }.buttonStyle(.plain)
        }
    }

    private func restLabel(_ seconds: Int) -> String {
        if seconds >= 60 { return "\(seconds / 60):\(String(format: "%02d", seconds % 60))" }
        return "\(seconds)s"
    }

    private func stretchColor(_ s: StretchPosition) -> Color {
        switch s {
        case .lengthened: return .appGreen
        case .mid: return .appBlue
        case .shortened: return .appOrange
        }
    }

    // ── Step 3 — Review & Save ──────────────────────────────────────────

    private var stepThreeReview: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // Preview card
                    HStack(spacing: 12) {
                        Rectangle().fill(templateColor(selectedColor)).frame(width: 4, height: 44).cornerRadius(2)
                        Image(systemName: selectedIcon).font(.system(size: 22))
                            .foregroundColor(templateColor(selectedColor))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(templateName).font(.system(size: 16, weight: .black)).foregroundColor(.appTextPrimary)
                            Text("\(exercises.count) exercises").font(.system(size: 12)).foregroundColor(.appTextDim)
                        }
                        Spacer()
                    }
                    .padding(16).appCard()

                    // Exercise list
                    VStack(spacing: 0) {
                        ForEach(Array(exercises.enumerated()), id: \.element.id) { idx, ex in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 10) {
                                    Text("\(idx + 1)").font(.system(size: 10, weight: .black, design: .monospaced)).foregroundColor(.appTextDim)
                                        .frame(width: 22)
                                    Text(ex.displayName).font(.system(size: 13, weight: .bold)).foregroundColor(.appTextPrimary)
                                    Spacer()
                                    Text("\(ex.targetSets) × \(ex.targetRepsLow)–\(ex.targetRepsHigh)")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(.appTextSecondary)
                                }
                                if ex.targetRPE > 0 || !ex.notes.isEmpty {
                                    HStack(spacing: 8) {
                                        Spacer().frame(width: 22)
                                        if ex.targetRPE > 0 {
                                            Text("RPE \(String(format: "%.0f", ex.targetRPE))")
                                                .font(.system(size: 9, weight: .bold)).foregroundColor(.appOrange)
                                        }
                                        if !ex.notes.isEmpty {
                                            Text(ex.notes).font(.system(size: 9)).foregroundColor(.appTextDim).lineLimit(1)
                                        }
                                        Spacer()
                                    }
                                }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            if idx < exercises.count - 1 {
                                Divider().background(Color.appBorder).padding(.leading, 46)
                            }
                        }
                    }
                    .appCard()
                }
                .padding(16).padding(.bottom, 40)
            }

            // Bottom bar
            VStack(spacing: 0) {
                Divider().background(Color.appBorder)
                HStack(spacing: 12) {
                    Button(action: { step = 2 }) {
                        Text("BACK").font(.system(size: 13, weight: .black)).kerning(0.5)
                            .foregroundColor(.appTextSecondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Color.appSurface2).cornerRadius(10)
                    }.buttonStyle(.plain)

                    PrimaryButton(title: "SAVE TEMPLATE", icon: "checkmark.circle.fill") {
                        saveTemplate()
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 14).background(Color.appBG)
            }
        }
    }

    private func saveTemplate() {
        let trimmed = templateName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !exercises.isEmpty else { return }

        if let existing = editingTemplate {
            existing.name = trimmed
            existing.colorHex = selectedColor
            existing.iconName = selectedIcon
            existing.exercises = exercises
        } else {
            let t = DayTemplate(name: trimmed, iconName: selectedIcon, colorHex: selectedColor)
            t.exercises = exercises
            modelContext.insert(t)
        }
        try? modelContext.save()
        dismiss()
    }
}

// ═══════════════════════════════════════════
// DAY TEMPLATE LIBRARY VIEW
// ═══════════════════════════════════════════

struct DayTemplateLibraryView: View {
    /// When true (the default), the view wraps itself in a NavigationView with a
    /// dismiss button — used when presented as a sheet from Settings. When
    /// embedded inline (Program tab), set to false so the parent's nav chrome
    /// isn't duplicated. Either way the inline + button is always visible.
    var presentsAsSheet: Bool = true

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var dayTemplates: [DayTemplate]
    @State private var editingTemplate: DayTemplate? = nil
    @State private var showCreateNew = false

    var body: some View {
        if presentsAsSheet {
            NavigationView {
                content
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button(action: { dismiss() }) {
                                Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundColor(.appTextSecondary)
                            }
                        }
                        ToolbarItem(placement: .principal) {
                            Text("DAY TEMPLATES").font(.system(size: 14, weight: .black)).foregroundColor(.appTextPrimary).kerning(1)
                        }
                    }
            }
            .sheet(isPresented: $showCreateNew) { DayTemplateCreatorSheet() }
            .sheet(item: $editingTemplate) { template in
                DayTemplateCreatorSheet(editingTemplate: template)
            }
        } else {
            content
                .sheet(isPresented: $showCreateNew) { DayTemplateCreatorSheet() }
                .sheet(item: $editingTemplate) { template in
                    DayTemplateCreatorSheet(editingTemplate: template)
                }
        }
    }

    /// Inline + button — always rendered in the body so it shows up regardless
    /// of NavigationView/toolbar quirks. The toolbar one in sheet mode is gone.
    private var addTemplateRow: some View {
        Button {
            showCreateNew = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill").font(.system(size: 18)).foregroundColor(.appRed)
                Text("New Day Template").font(.system(size: 14, weight: .black)).foregroundColor(.appRed)
                Spacer()
            }
            .padding(14)
            .background(Color.appRed.opacity(0.06)).cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appRed.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var content: some View {
        ZStack {
            Color.appBG.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    addTemplateRow

                    if dayTemplates.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "doc.text.magnifyingglass").font(.system(size: 36)).foregroundColor(.appTextDim)
                            Text("No templates yet").font(.system(size: 16, weight: .bold)).foregroundColor(.appTextSecondary)
                            Text("Create reusable session templates that you can assign to any day.")
                                .font(.system(size: 13)).foregroundColor(.appTextDim).multilineTextAlignment(.center)
                        }.padding(.vertical, 30)
                    }

                    ForEach(dayTemplates, id: \.templateId) { template in
                        Button(action: { editingTemplate = template }) {
                            HStack(spacing: 0) {
                                Rectangle().fill(templateColor(template.colorHex)).frame(width: 3, height: 42).cornerRadius(1.5)
                                    .padding(.trailing, 10)
                                Image(systemName: template.iconName).font(.system(size: 16))
                                    .foregroundColor(templateColor(template.colorHex)).frame(width: 28)
                                    .padding(.trailing, 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.name).font(.system(size: 14, weight: .black)).foregroundColor(.appTextPrimary)
                                    Text("\(template.exercises.count) exercises").font(.system(size: 11)).foregroundColor(.appTextDim)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundColor(.appTextDim)
                            }
                            .padding(14)
                            .background(Color.appSurface).cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                modelContext.delete(template)
                                try? modelContext.save()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, presentsAsSheet ? 16 : 0)
                .padding(.bottom, 40)
            }
        }
    }
}

extension DayTemplate: Identifiable {
    var id: UUID { templateId }
}

// ═══════════════════════════════════════════
// TEMPLATE EXERCISE PICKER
// Enhanced picker with search, muscle filters,
// exercise details, and custom exercise creation.
// ═══════════════════════════════════════════

struct TemplateExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let exercises: [Exercise]
    let onSelect: (Exercise) -> Void

    @State private var searchText = ""
    @State private var selectedMuscle: String? = nil
    @State private var showCreateCustom = false

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
            result = result.filter { $0.displayName.lowercased().contains(q) ||
                $0.musclesPrimary.joined(separator: " ").lowercased().contains(q) }
        }
        return result.sorted { $0.displayName < $1.displayName }
    }

    var body: some View {
        ZStack {
            Color.appBG.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 15, weight: .bold)).foregroundColor(.appTextSecondary)
                    Spacer()
                    Text("ADD EXERCISE").font(.system(size: 14, weight: .black)).foregroundColor(.appTextPrimary).kerning(1)
                    Spacer()
                    Button("Custom") { showCreateCustom = true }
                        .font(.system(size: 14, weight: .bold)).foregroundColor(.appGold)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(Color.appSurface)
                .overlay(Rectangle().frame(height: 1).foregroundColor(.appBorder), alignment: .bottom)

                // Search
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundColor(.appTextDim)
                    TextField("Search exercises...", text: $searchText)
                        .font(.system(size: 15)).foregroundColor(.appTextPrimary)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.appTextDim)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(12).background(Color.appSurface2).cornerRadius(10)
                .padding(.horizontal, 16).padding(.top, 12)

                // Muscle filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Button { selectedMuscle = nil } label: {
                            Text("ALL")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(selectedMuscle == nil ? .white : .appTextSecondary)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(selectedMuscle == nil ? Color.appRed : Color.appSurface2).cornerRadius(6)
                        }.buttonStyle(.plain)

                        ForEach(muscles, id: \.self) { muscle in
                            Button { selectedMuscle = selectedMuscle == muscle ? nil : muscle } label: {
                                Text(muscle.uppercased())
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(selectedMuscle == muscle ? .white : .appTextSecondary)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(selectedMuscle == muscle ? Color.appRed : Color.appSurface2).cornerRadius(6)
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 16)
                }.padding(.vertical, 8)

                // Results count
                HStack {
                    Text("\(filtered.count) exercises").font(.system(size: 11, weight: .bold)).foregroundColor(.appTextDim)
                    Spacer()
                }.padding(.horizontal, 20).padding(.bottom, 4)

                // Exercise list
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        ForEach(filtered) { exercise in
                            let def = ExerciseDictionary.all[exercise.exerciseKey]
                            let stretch = def?.stretchPosition ?? .mid

                            Button {
                                onSelect(exercise)
                            } label: {
                                HStack(spacing: 12) {
                                    // Stretch position indicator
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(stretchPickerColor(stretch))
                                        .frame(width: 3, height: 36)

                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text(exercise.displayName)
                                                .font(.system(size: 14, weight: .bold)).foregroundColor(.appTextPrimary)
                                            if exercise.isCompound {
                                                Text("COMPOUND").font(.system(size: 7, weight: .black)).foregroundColor(.appGold)
                                                    .padding(.horizontal, 3).padding(.vertical, 1)
                                                    .background(Color.appGold.opacity(0.12)).cornerRadius(3)
                                            }
                                        }
                                        HStack(spacing: 6) {
                                            Text(exercise.musclesPrimary.joined(separator: ", "))
                                                .font(.system(size: 10)).foregroundColor(.appTextDim)
                                            if let eq = def?.equipment {
                                                Text("· \(eq.rawValue)").font(.system(size: 10)).foregroundColor(.appTextDim)
                                            }
                                            Text("· \(stretch.rawValue)").font(.system(size: 10))
                                                .foregroundColor(stretchPickerColor(stretch))
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle.fill").font(.system(size: 18)).foregroundColor(.appRed)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 10)
                            }.buttonStyle(.plain)

                            Divider().background(Color.appBorder).padding(.leading, 32)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showCreateCustom) {
            AddExerciseView()
        }
    }

    private func stretchPickerColor(_ s: StretchPosition) -> Color {
        switch s {
        case .lengthened: return .appGreen
        case .mid: return .appBlue
        case .shortened: return .appOrange
        }
    }
}
