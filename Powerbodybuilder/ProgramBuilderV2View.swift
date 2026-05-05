import SwiftUI
import SwiftData

// ═══════════════════════════════════════════
// PROGRAM BUILDER V2 — Root View
// Freeform navigation, two modes, live analytics.
// ═══════════════════════════════════════════

struct ProgramBuilderV2View: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]
    @Query private var allExercises: [Exercise]
    @Query private var existingTemplates: [ProgramTemplate]
    @Query private var allInstances: [UserProgramInstance]
    @Query private var allUserPrograms: [UserProgram]

    @State private var state = ProgramBuilderState()
    @State private var didSeed = false
    @State private var showExercisePicker = false
    @State private var addingToSessionIndex: Int = 0

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        ZStack {
            Color.appBG.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                builderHeader
                // Section nav
                sectionNav
                // Content
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        switch state.activeSection {
                        case .split:     splitSection
                        case .exercises: exercisesSection
                        case .blocks:    blocksSection
                        case .analytics: analyticsSection
                        case .review:    reviewSection
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 80)
                }
                // Live preview bar
                livePreviewBar
            }
        }
        .onAppear { seedIfNeeded() }
        .sheet(isPresented: $showExercisePicker) {
            exercisePickerSheet
        }
    }

    // ═══════════════════════════════════════
    // HEADER
    // ═══════════════════════════════════════

    private var builderHeader: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .font(.system(size: 15, weight: .medium)).foregroundColor(.appTextSecondary)
                Spacer()
                Text("PROGRAM BUILDER")
                    .font(.system(size: 14, weight: .black)).foregroundColor(.appTextPrimary).kerning(1.5)
                Spacer()
                // Mode toggle
                Menu {
                    ForEach(BuilderMode.allCases, id: \.self) { m in
                        Button(m.rawValue) { state.mode = m; if m == .assisted { state.regenerateSuggestions() } }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: state.mode == .assisted ? "wand.and.stars" : "wrench.fill")
                            .font(.system(size: 10))
                        Text(state.mode.rawValue).font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(state.mode == .assisted ? .appGreen : .appBlue)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background((state.mode == .assisted ? Color.appGreen : Color.appBlue).opacity(0.1)).cornerRadius(6)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Color.appSurface)
            Rectangle().frame(height: 1).foregroundColor(.appBorder)
        }
    }

    // ═══════════════════════════════════════
    // SECTION NAV
    // ═══════════════════════════════════════

    private var sectionNav: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(BuilderSection.allCases, id: \.self) { s in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { state.activeSection = s }
                    } label: {
                        Text(s.rawValue)
                            .font(.system(size: 11, weight: state.activeSection == s ? .black : .medium))
                            .foregroundColor(state.activeSection == s ? .white : .appTextSecondary)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(state.activeSection == s ? Color.appRed : Color.appSurface2)
                            .cornerRadius(7)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .background(Color.appSurface)
        .overlay(Rectangle().frame(height: 1).foregroundColor(.appBorder), alignment: .bottom)
    }

    // ═══════════════════════════════════════
    // SPLIT SECTION
    // ═══════════════════════════════════════

    private var splitSection: some View {
        VStack(spacing: 14) {
            // Program name
            VStack(alignment: .leading, spacing: 6) {
                Text("PROGRAM NAME").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(1)
                TextField("My Program", text: $state.programName)
                    .font(.system(size: 16, weight: .bold)).foregroundColor(.appTextPrimary)
                    .padding(12).background(Color.appSurface2).cornerRadius(8)
            }

            // Session builder
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("SESSIONS").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(2)
                    Spacer()
                    if state.mode == .assisted {
                        Button {
                            state.regenerateSuggestions()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "wand.and.stars").font(.system(size: 10))
                                Text("Auto-fill").font(.system(size: 10, weight: .bold))
                            }.foregroundColor(.appGreen)
                        }.buttonStyle(.plain)
                    }
                }

                // Existing sessions
                ForEach(state.sessions) { session in
                    let idx = state.sessions.firstIndex(where: { $0.id == session.id })
                    if let idx = idx {
                        let dayNum = idx + 1
                        let dayLabel = dayNum <= 7 ? "D\(dayNum)" : "S\(dayNum)"
                        HStack(spacing: 8) {
                            Text(dayLabel).font(.system(size: 10, weight: .black, design: .monospaced))
                                .foregroundColor(.appRed).frame(width: 22)
                            TextField("Session name", text: Binding(
                                get: { state.sessions.first(where: { $0.id == session.id })?.label ?? "" },
                                set: { newVal in
                                    if let i = state.sessions.firstIndex(where: { $0.id == session.id }) {
                                        state.sessions[i].label = newVal
                                        state.sessions[i].isUserModified = true
                                    }
                                }
                            ))
                            .font(.system(size: 13, weight: .bold)).foregroundColor(.appTextPrimary)
                            Spacer()
                            Text("\(session.exercises.count) ex")
                                .font(.system(size: 10)).foregroundColor(.appTextDim)
                            Button {
                                withAnimation {
                                    state.sessions.removeAll(where: { $0.id == session.id })
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundColor(.appTextDim)
                            }.buttonStyle(.plain)
                        }
                        .padding(10).background(Color.appSurface2).cornerRadius(8)
                    }
                }

                // Add session button
                Button {
                    let types: [SessionType] = [.push, .pull, .legs, .heavyUpper, .heavyLower, .fullBody, .freeform]
                    let next = types[state.sessions.count % types.count]
                    let num = state.sessions.count + 1
                    let label = num <= 7 ? "Day \(num)" : "Session \(num)"
                    state.sessions.append(BuilderSession(label: label, sessionType: next))
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 13))
                        Text("Add Session").font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(.appBlue).frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(Color.appBlue.opacity(0.06)).cornerRadius(8)
                }.buttonStyle(.plain)

                // Quick presets
                if state.sessions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("QUICK START").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim).kerning(1)
                        HStack(spacing: 6) {
                            presetButton("PPL") {
                                state.sessions = [
                                    BuilderSession(label: "Push", sessionType: .push),
                                    BuilderSession(label: "Pull", sessionType: .pull),
                                    BuilderSession(label: "Legs", sessionType: .legs)
                                ]
                                state.daysPerWeek = 3
                            }
                            presetButton("Upper/Lower") {
                                state.sessions = [
                                    BuilderSession(label: "Heavy Upper", sessionType: .heavyUpper),
                                    BuilderSession(label: "Heavy Lower", sessionType: .heavyLower),
                                    BuilderSession(label: "Hyp Upper", sessionType: .hypertrophyUpper),
                                    BuilderSession(label: "Hyp Lower", sessionType: .hypertrophyLower)
                                ]
                                state.daysPerWeek = 4
                            }
                            presetButton("PPL x2") {
                                state.sessions = [
                                    BuilderSession(label: "Push A", sessionType: .pushA),
                                    BuilderSession(label: "Pull A", sessionType: .pullA),
                                    BuilderSession(label: "Legs A", sessionType: .legsA),
                                    BuilderSession(label: "Push B", sessionType: .pushB),
                                    BuilderSession(label: "Pull B", sessionType: .pullB),
                                    BuilderSession(label: "Legs B", sessionType: .legsB)
                                ]
                                state.daysPerWeek = 6
                            }
                            presetButton("Full Body") {
                                state.sessions = [
                                    BuilderSession(label: "Full Body A", sessionType: .fullBodyA),
                                    BuilderSession(label: "Full Body B", sessionType: .fullBodyB),
                                    BuilderSession(label: "Full Body C", sessionType: .fullBodyA)
                                ]
                                state.daysPerWeek = 3
                            }
                        }
                    }
                }
            }
        }
    }

    // ═══════════════════════════════════════
    // EXERCISES SECTION
    // ═══════════════════════════════════════

    private var exercisesSection: some View {
        VStack(spacing: 14) {
            if state.sessions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray").font(.system(size: 30)).foregroundColor(.appTextDim)
                    Text(state.mode == .assisted ? "Tap 'Generate Program' in the Split section" : "Add sessions in the Split section first")
                        .font(.system(size: 14)).foregroundColor(.appTextSecondary).multilineTextAlignment(.center)
                }.padding(40)
            } else {
                // Session picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(state.sessions.enumerated()), id: \.element.id) { idx, session in
                            chip(session.label, selected: state.activeSessionIndex == idx) {
                                state.activeSessionIndex = idx
                            }
                        }
                    }
                }

                // Active session exercises
                if state.activeSessionIndex < state.sessions.count {
                    let session = state.sessions[state.activeSessionIndex]
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(session.label.uppercased()).font(.system(size: 12, weight: .black)).foregroundColor(.appTextPrimary)
                            Spacer()
                            let totalSets = session.exercises.reduce(0) { $0 + $1.targetSets }
                            Text("\(totalSets) sets · \(session.exercises.count) exercises")
                                .font(.system(size: 11)).foregroundColor(.appTextDim)
                        }

                        ForEach(Array(session.exercises.enumerated()), id: \.element.id) { idx, ex in
                            exerciseCard(ex, sessionIdx: state.activeSessionIndex, exIdx: idx)
                        }
                        .onMove { from, to in
                            state.sessions[state.activeSessionIndex].exercises.move(fromOffsets: from, toOffset: to)
                            state.sessions[state.activeSessionIndex].isUserModified = true
                        }

                        // Add exercise button
                        Button {
                            addingToSessionIndex = state.activeSessionIndex
                            showExercisePicker = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill").font(.system(size: 14))
                                Text("Add Exercise").font(.system(size: 13, weight: .bold))
                            }
                            .foregroundColor(.appGreen).frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(Color.appGreen.opacity(0.06)).cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appGreen.opacity(0.15), lineWidth: 1))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func exerciseCard(_ ex: BuilderExerciseV2, sessionIdx: Int, exIdx: Int) -> some View {
        let tierColor: Color = ex.tier == .tier1 ? .appRed : (ex.tier == .tier2 ? .appBlue : .appGreen)
        let tierLabel = ex.tier == .tier1 ? "T1" : (ex.tier == .tier2 ? "T2" : "T3")

        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(tierLabel).font(.system(size: 9, weight: .black)).foregroundColor(tierColor).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ex.displayName).font(.system(size: 13, weight: .bold)).foregroundColor(.appTextPrimary).lineLimit(1)
                    Text("\(ex.targetSets) × \(ex.targetRepsLow)-\(ex.targetRepsHigh) · Rest \(ex.restSeconds/60):\(String(format: "%02d", ex.restSeconds%60))")
                        .font(.system(size: 10)).foregroundColor(.appTextDim)
                }
                Spacer()
                // Edit params inline
                Menu {
                    ForEach([2,3,4,5], id: \.self) { s in
                        Button("\(s) sets") { state.sessions[sessionIdx].exercises[exIdx].targetSets = s; state.sessions[sessionIdx].isUserModified = true }
                    }
                    Divider()
                    Button("Remove", role: .destructive) {
                        state.sessions[sessionIdx].exercises.remove(at: exIdx)
                        state.sessions[sessionIdx].isUserModified = true
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 14)).foregroundColor(.appTextDim)
                        .frame(width: 36, height: 36).contentShape(Rectangle()).background(Color.appSurface2).cornerRadius(8)
                }
            }
            .padding(10)
        }
        .background(Color.appSurface).cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorder, lineWidth: 1))
    }

    // ═══════════════════════════════════════
    // BLOCKS SECTION
    // ═══════════════════════════════════════

    private var blocksSection: some View {
        let isHyp = state.goal == .hypertrophy || state.goal == .recomp
        return VStack(spacing: 14) {
            Text("MESOCYCLE BLOCKS").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(2)

            ForEach(Array(state.blocks.enumerated()), id: \.element.id) { idx, block in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Block \(idx + 1)").font(.system(size: 13, weight: .black)).foregroundColor(.appTextPrimary)
                        Spacer()
                        Text("\(block.totalLength) weeks").font(.system(size: 11, weight: .bold)).foregroundColor(.appTextDim)
                        if state.blocks.count > 1 {
                            Button { state.blocks.remove(at: idx) } label: {
                                Image(systemName: "trash").font(.system(size: 11)).foregroundColor(.appRed)
                            }.buttonStyle(.plain)
                        }
                    }

                    // Block type
                    let types: [BlockType] = isHyp ? [.accumulation, .reaccumulation, .deload] :
                        [.accumulation, .intensification, .reaccumulation, .peak, .deload]
                    HStack(spacing: 4) {
                        ForEach(types, id: \.self) { bt in
                            Button {
                                state.blocks[idx].blockType = bt
                            } label: {
                                let label = isHyp ? (bt == .accumulation ? "Training" : (bt == .reaccumulation ? "Growth" : "Recovery")) : bt.rawValue.capitalized
                                Text(label).font(.system(size: 9, weight: state.blocks[idx].blockType == bt ? .black : .medium))
                                    .foregroundColor(state.blocks[idx].blockType == bt ? .white : .appTextSecondary)
                                    .padding(.horizontal, 8).padding(.vertical, 5)
                                    .background(state.blocks[idx].blockType == bt ? Color.appRed : Color.appSurface2).cornerRadius(5)
                            }.buttonStyle(.plain)
                        }
                    }

                    // Training weeks
                    HStack {
                        Text("Training weeks").font(.system(size: 12)).foregroundColor(.appTextSecondary)
                        Spacer()
                        Stepper("", value: Binding(
                            get: { state.blocks[idx].trainingWeeks },
                            set: { state.blocks[idx].trainingWeeks = max(2, min(8, $0)) }
                        )).labelsHidden()
                        Text("\(state.blocks[idx].trainingWeeks)").font(.system(size: 14, weight: .black)).foregroundColor(.appRed).frame(width: 20)
                    }

                    // Deload toggle
                    Toggle("Include recovery week", isOn: Binding(
                        get: { state.blocks[idx].includeDeload },
                        set: { state.blocks[idx].includeDeload = $0 }
                    ))
                    .font(.system(size: 12)).foregroundColor(.appTextSecondary)
                    .tint(.appBlue)

                    // Rotation rule
                    HStack {
                        Text("Exercise rotation").font(.system(size: 12)).foregroundColor(.appTextSecondary)
                        Spacer()
                        Menu {
                            ForEach(RotationRule.allCases, id: \.self) { r in
                                Button { state.blocks[idx].rotationRule = r } label: {
                                    Text("\(r.rawValue) — \(r.detail)")
                                }
                            }
                        } label: {
                            Text(state.blocks[idx].rotationRule.rawValue)
                                .font(.system(size: 11, weight: .bold)).foregroundColor(.appBlue)
                        }
                    }
                }
                .padding(12).background(Color.appSurface).cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))
            }

            // Add block
            Button {
                state.blocks.append(BuilderBlock())
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill").font(.system(size: 14))
                    Text("Add Block").font(.system(size: 13, weight: .bold))
                }
                .foregroundColor(.appBlue).frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(Color.appBlue.opacity(0.06)).cornerRadius(8)
            }.buttonStyle(.plain)

            // Total
            HStack {
                Text("Total program length").font(.system(size: 12, weight: .bold)).foregroundColor(.appTextSecondary)
                Spacer()
                Text("\(state.totalWeeks) weeks").font(.system(size: 14, weight: .black)).foregroundColor(.appRed)
            }
            .padding(12).background(Color.appSurface).cornerRadius(8)
        }
    }

    // ═══════════════════════════════════════
    // ANALYTICS SECTION
    // ═══════════════════════════════════════

    private var analyticsSection: some View {
        let a = state.analytics
        return VStack(spacing: 14) {
            // Volume per muscle
            VStack(alignment: .leading, spacing: 8) {
                Text("WEEKLY VOLUME").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(2)
                ForEach(ExerciseDictionary.trackingMuscles, id: \.self) { muscle in
                    let sets = a.volumePerMuscle[muscle] ?? 0
                    let tier = state.muscleTiers[muscle] ?? .neutral
                    let mrv = VolumeLandmark.effectiveMRV(muscle: muscle, experience: state.experience,
                                                          tier: tier, calorieContext: state.calorieContext)
                    HStack(spacing: 6) {
                        Text(muscle).font(.system(size: 10, weight: .bold))
                            .foregroundColor(tier == .priority ? .appGold : .appTextPrimary)
                            .frame(width: 75, alignment: .leading)
                        GeometryReader { geo in
                            let pct = mrv > 0 ? min(CGFloat(sets) / CGFloat(mrv), 1.0) : 0
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3).fill(Color.appSurface2)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(sets > mrv ? Color.appOrange : (tier == .priority ? Color.appGold : Color.appGreen))
                                    .frame(width: geo.size.width * pct)
                            }
                        }.frame(height: 8)
                        Text("\(sets)").font(.system(size: 10, weight: .black)).foregroundColor(.appTextPrimary).frame(width: 20, alignment: .trailing)
                    }
                }
            }
            .padding(14).background(Color.appSurface).cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))

            // Frequency
            VStack(alignment: .leading, spacing: 8) {
                Text("FREQUENCY (sessions/week)").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(2)
                ForEach(ExerciseDictionary.trackingMuscles, id: \.self) { muscle in
                    let freq = a.frequencyPerMuscle[muscle] ?? 0
                    HStack {
                        Text(muscle).font(.system(size: 11)).foregroundColor(.appTextSecondary).frame(width: 80, alignment: .leading)
                        HStack(spacing: 2) {
                            ForEach(0..<freq, id: \.self) { _ in
                                Circle().fill(Color.appGreen).frame(width: 8, height: 8)
                            }
                        }
                        Spacer()
                        Text("\(freq)x").font(.system(size: 11, weight: .bold)).foregroundColor(.appTextPrimary)
                    }
                }
            }
            .padding(14).background(Color.appSurface).cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))

            // Warnings
            if !a.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("WARNINGS").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(2)
                    ForEach(a.warnings) { w in
                        HStack(spacing: 8) {
                            Image(systemName: w.severity == .error ? "xmark.circle.fill" : (w.severity == .caution ? "exclamationmark.triangle.fill" : "info.circle.fill"))
                                .foregroundColor(w.severity == .error ? .appRed : (w.severity == .caution ? .appOrange : .appBlue))
                                .font(.system(size: 12))
                            Text(w.message).font(.system(size: 12)).foregroundColor(.appTextSecondary)
                        }
                    }
                }
                .padding(14).background(Color.appSurface).cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
            }

            // Session durations
            VStack(alignment: .leading, spacing: 8) {
                Text("SESSION DURATION ESTIMATES").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(2)
                ForEach(state.sessions) { session in
                    let dur = a.sessionDurations[session.id] ?? 0
                    let sets = session.exercises.reduce(0) { $0 + $1.targetSets }
                    HStack {
                        Text(session.label).font(.system(size: 12, weight: .bold)).foregroundColor(.appTextSecondary)
                        Spacer()
                        Text("\(sets) sets").font(.system(size: 11)).foregroundColor(.appTextDim)
                        Text("~\(dur) min").font(.system(size: 11, weight: .bold))
                            .foregroundColor(dur > state.sessionDurationTarget ? .appOrange : .appGreen)
                    }
                }
            }
            .padding(14).background(Color.appSurface).cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
        }
    }

    // ═══════════════════════════════════════
    // REVIEW SECTION
    // ═══════════════════════════════════════

    private var reviewSection: some View {
        let a = state.analytics
        return VStack(spacing: 14) {
            // Summary
            VStack(alignment: .leading, spacing: 8) {
                Text("PROGRAM SUMMARY").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(2)
                summaryRow("Name", value: state.programName.isEmpty ? "(unnamed)" : state.programName)
                summaryRow("Goal", value: state.goal.displayName)
                summaryRow("Days/Week", value: "\(state.daysPerWeek)")
                summaryRow("Sessions", value: "\(state.sessions.count)")
                summaryRow("Blocks", value: "\(state.blocks.count)")
                summaryRow("Total Weeks", value: "\(state.totalWeeks)")
                summaryRow("Weekly Sets", value: "\(a.totalWeeklySets)")
            }
            .padding(14).background(Color.appSurface).cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))

            // Validation
            let errors = a.warnings.filter { $0.severity == .error }
            if !errors.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("MUST FIX").font(.system(size: 10, weight: .black)).foregroundColor(.appRed).kerning(1)
                    ForEach(errors) { w in
                        Text("• \(w.message)").font(.system(size: 12)).foregroundColor(.appRed)
                    }
                }
                .padding(14).background(Color.appRed.opacity(0.04)).cornerRadius(10)
            }

            // Create button
            Button { createProgram() } label: {
                Text(state.programName.isEmpty ? "CREATE PROGRAM" : "CREATE \(state.programName.uppercased())")
                    .font(.system(size: 15, weight: .black)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(state.sessions.isEmpty ? Color.appTextDim : Color.appRed).cornerRadius(14)
            }
            .buttonStyle(.plain)
            .disabled(state.sessions.isEmpty)
        }
    }

    private func summaryRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundColor(.appTextDim)
            Spacer()
            Text(value).font(.system(size: 12, weight: .bold)).foregroundColor(.appTextPrimary)
        }
    }

    // ═══════════════════════════════════════
    // LIVE PREVIEW BAR
    // ═══════════════════════════════════════

    private var livePreviewBar: some View {
        let a = state.analytics
        return HStack(spacing: 12) {
            HStack(spacing: 4) {
                Image(systemName: "calendar").font(.system(size: 10)).foregroundColor(.appTextDim)
                Text("\(state.totalWeeks) wks").font(.system(size: 11, weight: .bold)).foregroundColor(.appTextPrimary)
            }
            Divider().frame(height: 16)
            HStack(spacing: 4) {
                Image(systemName: "list.bullet").font(.system(size: 10)).foregroundColor(.appTextDim)
                Text("\(state.sessions.count) sessions").font(.system(size: 11, weight: .bold)).foregroundColor(.appTextPrimary)
            }
            Divider().frame(height: 16)
            HStack(spacing: 4) {
                Image(systemName: "flame").font(.system(size: 10)).foregroundColor(.appTextDim)
                Text("\(a.totalWeeklySets) sets/wk").font(.system(size: 11, weight: .bold)).foregroundColor(.appTextPrimary)
            }
            Spacer()
            if !a.warnings.isEmpty {
                let errorCount = a.warnings.filter { $0.severity == .error }.count
                if errorCount > 0 {
                    Text("\(errorCount)").font(.system(size: 10, weight: .black)).foregroundColor(.white)
                        .frame(width: 18, height: 18).background(Color.appRed).clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color.appSurface)
        .overlay(Rectangle().frame(height: 1).foregroundColor(.appBorder), alignment: .top)
    }

    // ═══════════════════════════════════════
    // EXERCISE PICKER SHEET
    // ═══════════════════════════════════════

    private var exercisePickerSheet: some View {
        InWorkoutAddSheet(allExercises: allExercises) { exercise in
            guard addingToSessionIndex < state.sessions.count else { return }
            let def = ExerciseDictionary.all[exercise.exerciseKey]
            let muscle = exercise.musclesPrimary.compactMap { ExerciseDictionary.normalizeMuscle($0) }.first ?? ""
            let tier: ExerciseTier = def?.isAnchorableAsTier1 == true ? .tier1 : (def?.isCompound == true ? .tier2 : .tier3)
            let reps = tier == .tier1 ? (5, 8) : (tier == .tier2 ? (8, 12) : (12, 20))
            let rest = tier == .tier1 ? 210 : (tier == .tier2 ? 150 : 90)

            state.sessions[addingToSessionIndex].exercises.append(
                BuilderExerciseV2(exerciseKey: exercise.exerciseKey, displayName: exercise.displayName,
                                  muscleGroup: muscle, tier: tier, targetSets: 3,
                                  targetRepsLow: reps.0, targetRepsHigh: reps.1,
                                  targetRPE: 7.5, restSeconds: rest))
            state.sessions[addingToSessionIndex].isUserModified = true
            showExercisePicker = false
        }
    }

    // ═══════════════════════════════════════
    // SEED & CREATE
    // ═══════════════════════════════════════

    private func seedIfNeeded() {
        guard !didSeed else { return }
        if let p = profile, state.mode == .assisted {
            state.seedFromProfile(p)
            state.regenerateSuggestions()
        }
        didSeed = true
    }

    private func createProgram() {
        guard !state.sessions.isEmpty else { return }

        let pid = (existingTemplates.map { $0.programId }.max() ?? 99) + 1
        let name = state.programName.isEmpty ? "Custom Program" : state.programName

        // Create ProgramTemplate
        let template = ProgramTemplate(
            programId: pid, name: name, version: 1,
            durationWeeks: state.totalWeeks,
            sessionTypes: state.sessions.map { $0.sessionType },
            scheduleOptions: [])
        modelContext.insert(template)

        // Create ProgramSessionTemplate records for each block × week × session × exercise
        var absoluteWeek = 1
        for block in state.blocks {
            let mult: Double = switch block.blockType {
            case .accumulation: 1.0
            case .intensification: 0.65
            case .reaccumulation: 1.15
            case .peak: 0.50
            case .deload: 1.0
            }

            for weekInBlock in 1...block.totalLength {
                let isDeload = weekInBlock > block.trainingWeeks
                for session in state.sessions {
                    for (idx, ex) in session.exercises.enumerated() {
                        let sets = isDeload ? max(2, ex.targetSets / 2) : Int(Double(ex.targetSets) * mult)
                        let rpe = isDeload ? 6.0 : ex.targetRPE
                        let slotId = "\(session.label.prefix(1).uppercased())\(idx + 1)"

                        let pst = ProgramSessionTemplate(
                            programId: pid, programVersion: 1, week: absoluteWeek,
                            sessionType: session.sessionType, slotId: slotId,
                            exerciseIndex: idx, exerciseKey: ex.exerciseKey,
                            role: ex.tier == .tier1 ? .mainLift : (ex.tier == .tier2 ? .supplemental : .accessory),
                            isMainLift: ex.tier == .tier1, targetSets: max(2, sets),
                            targetRepsLow: ex.targetRepsLow, targetRepsHigh: ex.targetRepsHigh,
                            targetRPE: rpe, restSeconds: ex.restSeconds, notes: "")
                        modelContext.insert(pst)
                    }
                }
                absoluteWeek += 1
            }
        }

        // Deactivate all existing
        for inst in allInstances { inst.isActive = false }
        for up in allUserPrograms { up.isActive = false }

        // Create instance
        let instance = UserProgramInstance(programId: pid, programVersion: 1, name: name)
        instance.blockLength = state.blocks.first?.trainingWeeks ?? 5
        instance.blockType = state.blocks.first?.blockType ?? .accumulation
        modelContext.insert(instance)

        // Create legacy UserProgram
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let up = UserProgram(programId: pid, name: name, startDate: fmt.string(from: Date()))
        modelContext.insert(up)

        try? modelContext.save()
        dismiss()
    }

    // ═══════════════════════════════════════
    // CHIP HELPER
    // ═══════════════════════════════════════

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: selected ? .black : .medium))
                .foregroundColor(selected ? .white : .appTextSecondary)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(selected ? Color.appRed : Color.appSurface2).cornerRadius(6)
        }.buttonStyle(.plain)
    }

    private func presetButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: .bold))
                .foregroundColor(.appBlue)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.appBlue.opacity(0.06)).cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.appBlue.opacity(0.15), lineWidth: 1))
        }.buttonStyle(.plain)
    }
}
