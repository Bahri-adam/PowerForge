import SwiftUI
import SwiftData

struct SettingsView: View {

    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @Query private var programs: [UserProgram]
    @Query(filter: #Predicate<UserProgramInstance> { $0.isActive == true })
    private var activeInstances: [UserProgramInstance]

    var profile: UserProfile? { profiles.first }
    var activeProgram: UserProgram? {
        let active = programs.first(where: { $0.isActive })
        return active
    }
    var activeInstance: UserProgramInstance? { activeInstances.first }

    @Query private var programTemplatesList: [ProgramTemplate]

    @Query(sort: \WorkoutLog.workoutDate) private var allWorkoutLogs: [WorkoutLog]

    @State private var showEditProfile = false
    @State private var showSwitchProgram = false
    @State private var showWeekPicker = false
    @State private var showProgramBuilder = false
    @State private var showGeneratedPreview = false
    @State private var showImportPicker = false
    @State private var showLearn = false
    @State private var showImportConfirm = false
    @State private var importURL: URL? = nil
    @State private var showExportShare = false
    @State private var exportFileURL: URL? = nil
    @State private var showDayTemplates = false
    @State private var showResetProgram = false
    @State private var iCloudStatus: (signedIn: Bool, message: String) = (false, "Checking…")

    private func programDef(for programId: Int) -> ProgramDef? {
        if let def = allPrograms.first(where: { $0.id == programId }) { return def }
        if let def = customPrograms.first(where: { $0.id == programId }) { return def }
        // Build from ProgramTemplate for custom programs
        if let tmpl = programTemplatesList.first(where: { $0.programId == programId }) {
            return ProgramDef(
                id: programId,
                name: tmpl.name.uppercased(),
                subtitle: "Custom Program",
                description: "Custom program",
                days: "\(tmpl.sessionTypes.count) days/week",
                sessionLength: "60–90 min",
                split: tmpl.sessionTypes.map { $0.shortLabel }.joined(separator: " / "),
                difficulty: "Custom",
                icon: "hammer.fill",
                accentColor: .appRed,
                tags: ["Custom"],
                repRanges: "Varies",
                volumePerMuscle: "Varies",
                whoItsFor: "Custom built.",
                days_per_week_range: tmpl.sessionTypes.count...tmpl.sessionTypes.count
            )
        }
        // Generated programs: build ProgramDef from instance + profile
        if let inst = activeInstance, inst.isGenerated, inst.programId == programId, let p = profile {
            let split = ProgramGenerator.resolveSplitStructure(
                daysPerWeek: p.daysPerWeek, goal: p.goal, priorityMuscles: p.priorityMuscles)
            let sessionNames = split.filter { $0.sessionType != .rest }.map { $0.label }
            return ProgramDef(
                id: programId,
                name: inst.name.uppercased(),
                subtitle: "Auto-Generated \(p.goal.displayName)",
                description: "Generated program based on your profile.",
                days: "\(p.daysPerWeek) days/week",
                sessionLength: "60–90 min",
                split: sessionNames.joined(separator: " / "),
                difficulty: p.experience.rawValue,
                icon: "wand.and.stars",
                accentColor: .appGreen,
                tags: ["Generated", p.goal.displayName],
                repRanges: "Auto-periodized",
                volumePerMuscle: "Signal-driven",
                whoItsFor: "Personalized to your profile.",
                days_per_week_range: p.daysPerWeek...p.daysPerWeek
            )
        }
        return nil
    }
    
    var body: some View {
        ZStack {
            Color.appBG
                .ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    
                    // HEADER
                    HStack {
                        Text("SETTINGS")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(.appTextPrimary)
                        Spacer()
                    }
                    .padding(20)
                    .background(Color.appSurface)
                    .overlay(
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(.appBorder),
                        alignment: .bottom
                    )
                    
                    VStack(spacing: 20) {
                        
                        // PROFILE CARD
                        VStack(spacing: 0) {
                            SectionHeader(title: "PROFILE")
                                .padding(.bottom, 10)
                            
                            VStack(spacing: 0) {
                                HStack(spacing: 14) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.appRed.opacity(0.15))
                                            .frame(width: 52, height: 52)
                                        Text(String(profile?.name.prefix(1).uppercased() ?? "A"))
                                            .font(.system(size: 22, weight: .black, design: .rounded))
                                            .foregroundColor(.appRed)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(profile?.name ?? "Athlete")
                                            .font(.system(size: 18, weight: .black))
                                            .foregroundColor(.appTextPrimary)
                                        HStack(spacing: 8) {
                                            Text(profile?.experienceRaw ?? "")
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(.appTextSecondary)
                                            if let bw = profile?.bodyweight, bw > 0 {
                                                Text("•")
                                                    .foregroundColor(.appTextDim)
                                                Text("\(String(format: "%.0f", bw)) \(profile?.useMetric == true ? "kg" : "lbs")")
                                                    .font(.system(size: 12, weight: .medium))
                                                    .foregroundColor(.appTextSecondary)
                                            }
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    Button(action: { showEditProfile = true }) {
                                        Text("Edit")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(.appRed)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                            .background(Color.appRed.opacity(0.1))
                                            .cornerRadius(8)
                                    }
                                }
                                .padding(16)
                                
                                Divider()
                                    .background(Color.appBorder)
                                
                                HStack(spacing: 0) {
                                    ProfileStat(label: "GOAL", value: profile?.goal.displayName ?? "--")
                                    Rectangle()
                                        .frame(width: 1, height: 28)
                                        .foregroundColor(.appBorder)
                                    ProfileStat(label: "DAYS/WK", value: "\(profile?.daysPerWeek ?? 0)")
                                    Rectangle()
                                        .frame(width: 1, height: 28)
                                        .foregroundColor(.appBorder)
                                    ProfileStat(label: "AGE", value: "\(profile?.age ?? 0)")
                                }
                            }
                            .appCard()
                        }
                        
                        // ACTIVE PROGRAM CARD
                        VStack(spacing: 0) {
                            SectionHeader(title: "ACTIVE PROGRAM")
                                .padding(.bottom, 10)
                            
                            VStack(spacing: 12) {
                                if let program = activeProgram,
                                   let def = programDef(for: program.programId) {
                                    
                                    HStack(spacing: 12) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(def.accentColor.opacity(0.15))
                                                .frame(width: 44, height: 44)
                                            Image(systemName: def.icon)
                                                .font(.system(size: 18, weight: .bold))
                                                .foregroundColor(def.accentColor)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(def.name)
                                                .font(.system(size: 15, weight: .black))
                                                .foregroundColor(.appTextPrimary)
                                            Text(def.subtitle)
                                                .font(.system(size: 12))
                                                .foregroundColor(.appTextSecondary)
                                        }
                                        
                                        Spacer()

                                        if program.programId != 0 {
                                            Button(action: { showWeekPicker = true }) {
                                                VStack(alignment: .trailing, spacing: 2) {
                                                    Text("WEEK")
                                                        .font(.system(size: 9, weight: .bold))
                                                        .foregroundColor(.appTextDim)
                                                        .kerning(1)
                                                    HStack(spacing: 4) {
                                                        Text("\(activeInstance?.currentWeek ?? program.currentWeek)")
                                                            .font(.system(size: 22, weight: .black, design: .rounded))
                                                            .foregroundColor(def.accentColor)
                                                        Image(systemName: "chevron.up.chevron.down")
                                                            .font(.system(size: 10, weight: .bold))
                                                            .foregroundColor(.appTextDim)
                                                    }
                                                }
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }

                                    HStack(spacing: 8) {
                                        Button(action: { showSwitchProgram = true }) {
                                            HStack {
                                                Image(systemName: "arrow.triangle.2.circlepath")
                                                    .font(.system(size: 13))
                                                Text("SWITCH")
                                                    .font(.system(size: 12, weight: .bold))
                                                    .kerning(0.5)
                                            }
                                            .foregroundColor(.appTextSecondary)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(Color.appSurface2)
                                            .cornerRadius(10)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .stroke(Color.appBorder, lineWidth: 1)
                                            )
                                        }
                                        .buttonStyle(.plain)

                                        Button(action: { showProgramBuilder = true }) {
                                            HStack {
                                                Image(systemName: "hammer.fill")
                                                    .font(.system(size: 13))
                                                Text("BUILD")
                                                    .font(.system(size: 12, weight: .bold))
                                                    .kerning(0.5)
                                            }
                                            .foregroundColor(.appRed)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(Color.appRed.opacity(0.08))
                                            .cornerRadius(10)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .stroke(Color.appRed.opacity(0.2), lineWidth: 1)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }

                                    // GENERATE AUTO PROGRAM
                                    Button(action: { showGeneratedPreview = true }) {
                                        HStack {
                                            Image(systemName: "wand.and.stars")
                                                .font(.system(size: 13))
                                            Text("GENERATE PROGRAM")
                                                .font(.system(size: 12, weight: .bold))
                                                .kerning(0.5)
                                        }
                                        .foregroundColor(.appGreen)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color.appGreen.opacity(0.08))
                                        .cornerRadius(10)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(Color.appGreen.opacity(0.2), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)

                                    // Program start date
                                    if let inst = activeInstance {
                                        HStack(spacing: 10) {
                                            Image(systemName: "calendar")
                                                .font(.system(size: 14)).foregroundColor(.appTextDim)
                                            Text("Start Date")
                                                .font(.system(size: 13, weight: .bold)).foregroundColor(.appTextSecondary)
                                            Spacer()
                                            DatePicker("", selection: Binding(
                                                get: { inst.startDate },
                                                set: { inst.startDate = $0; try? modelContext.save() }
                                            ), displayedComponents: .date)
                                            .labelsHidden()
                                            .tint(.appRed)
                                        }
                                        .padding(.top, 8)
                                    }
                                }
                            }
                            .padding(16)
                            .appCard()
                        }

                        // DAY TEMPLATES
                        VStack(spacing: 0) {
                            SectionHeader(title: "DAY TEMPLATES")
                                .padding(.bottom, 10)
                            Button(action: { showDayTemplates = true }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "square.stack.3d.up.fill")
                                        .font(.system(size: 14)).foregroundColor(.appBlue).frame(width: 20)
                                    Text("Manage Templates")
                                        .font(.system(size: 15, weight: .medium)).foregroundColor(.appTextPrimary)
                                    Spacer()
                                    Text("Reusable sessions")
                                        .font(.system(size: 11)).foregroundColor(.appTextDim)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .semibold)).foregroundColor(.appTextDim)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 14)
                            }
                            .buttonStyle(.plain)
                            .appCard()
                        }

                        // PREFERENCES
                        VStack(spacing: 0) {
                            SectionHeader(title: "PREFERENCES")
                                .padding(.bottom, 10)

                            VStack(spacing: 0) {
                                SettingsRow(
                                    icon: "scalemass.fill",
                                    label: "Units",
                                    value: profile?.useMetric == true ? "Metric (kg)" : "Imperial (lbs)"
                                )
                            }
                            .appCard()
                        }
                        
                        // ALGORITHM
                        AlgorithmModePicker(profile: profile, modelContext: modelContext)

                        // WARM-UPS
                        if let profile = profile {
                            VStack(spacing: 0) {
                                HStack(spacing: 12) {
                                    Image(systemName: "flame")
                                        .font(.system(size: 14)).foregroundColor(.appOrange)
                                        .frame(width: 20)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Warm-Up Sets")
                                            .font(.system(size: 15, weight: .medium)).foregroundColor(.appTextPrimary)
                                        Text("Auto-generated ramp for your first compounds")
                                            .font(.system(size: 11)).foregroundColor(.appTextDim)
                                    }
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { profile.showWarmups },
                                        set: { profile.showWarmups = $0; try? modelContext.save() }
                                    ))
                                    .tint(.appRed)
                                    .labelsHidden()
                                }
                                .padding(.horizontal, 16).padding(.vertical, 12)
                            }
                            .appCard()
                        }

                        // WORKOUT DISPLAY
                        if let profile = profile {
                            VStack(spacing: 0) {
                                SectionHeader(title: "WORKOUT DISPLAY")
                                    .padding(.horizontal, 16).padding(.bottom, 10)

                                displayToggle(icon: "number", label: "Rep Range", detail: "Target rep range per exercise",
                                              isOn: Binding(get: { profile.showRepRange }, set: { profile.showRepRange = $0; try? modelContext.save() }))
                                Divider().background(Color.appBorder).padding(.leading, 46)
                                displayToggle(icon: "gauge.medium", label: "RPE Targets", detail: "Rate of perceived exertion",
                                              isOn: Binding(get: { profile.showRPE }, set: { profile.showRPE = $0; try? modelContext.save() }))
                                Divider().background(Color.appBorder).padding(.leading, 46)
                                displayToggle(icon: "timer", label: "Rest Timer", detail: "Countdown between sets",
                                              isOn: Binding(get: { profile.showRestTimer }, set: { profile.showRestTimer = $0; try? modelContext.save() }))
                                Divider().background(Color.appBorder).padding(.leading, 46)
                                displayToggle(icon: "moon.zzz.fill", label: "Skip Deload Weeks", detail: "Replace recovery weeks with normal training",
                                              isOn: Binding(get: { profile.skipDeloads }, set: { profile.skipDeloads = $0; try? modelContext.save() }))
                            }
                            .appCard()
                        }

                        // LEARN
                        VStack(spacing: 0) {
                            SectionHeader(title: "LEARN")
                                .padding(.bottom, 10)
                            Button(action: { showLearn = true }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "book.fill")
                                        .font(.system(size: 14)).foregroundColor(.appBlue)
                                        .frame(width: 20)
                                    Text("Guides & Education")
                                        .font(.system(size: 15, weight: .medium)).foregroundColor(.appTextPrimary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12)).foregroundColor(.appTextDim)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 14)
                            }
                            .buttonStyle(.plain)
                            .appCard()
                        }

                        // DATA
                        VStack(spacing: 0) {
                            SectionHeader(title: "DATA")
                                .padding(.bottom, 10)

                            VStack(spacing: 0) {
                                // Export CSV
                                Button(action: exportCSV) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "square.and.arrow.up")
                                            .font(.system(size: 14)).foregroundColor(.appRed)
                                            .frame(width: 20)
                                        Text("Export Workout History")
                                            .font(.system(size: 15, weight: .medium)).foregroundColor(.appTextPrimary)
                                        Spacer()
                                        let logCount = (activeInstance?.logs.count ?? 0) + allWorkoutLogs.count
                                        Text("\(logCount) sets")
                                            .font(.system(size: 13, weight: .semibold)).foregroundColor(.appTextDim)
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 14)
                                }
                                .buttonStyle(.plain)
                                Divider().padding(.leading, 48)

                                // Export JSON backup
                                Button(action: exportJSONBackup) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "externaldrive.fill")
                                            .font(.system(size: 14)).foregroundColor(.appBlue)
                                            .frame(width: 20)
                                        Text("Backup All Data (JSON)")
                                            .font(.system(size: 15, weight: .medium)).foregroundColor(.appTextPrimary)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12)).foregroundColor(.appTextDim)
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 14)
                                }
                                .buttonStyle(.plain)
                                Divider().padding(.leading, 48)

                                // Import JSON backup
                                Button(action: { showImportPicker = true }) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "square.and.arrow.down")
                                            .font(.system(size: 14)).foregroundColor(.appGreen)
                                            .frame(width: 20)
                                        Text("Restore from Backup")
                                            .font(.system(size: 15, weight: .medium)).foregroundColor(.appTextPrimary)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12)).foregroundColor(.appTextDim)
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 14)
                                }
                                .buttonStyle(.plain)
                            }
                            .appCard()
                        }

                        // RESET PROGRAM
                        VStack(spacing: 0) {
                            SectionHeader(title: "RESET PROGRAM")
                                .padding(.horizontal, 16).padding(.bottom, 10)
                            Button { showResetProgram = true } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "arrow.counterclockwise.circle.fill")
                                        .font(.system(size: 14)).foregroundColor(.appOrange)
                                        .frame(width: 20)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Reset to Week 1")
                                            .font(.system(size: 15, weight: .medium)).foregroundColor(.appTextPrimary)
                                        Text("Clear workout history, keep PRs and lift data")
                                            .font(.system(size: 11)).foregroundColor(.appTextDim)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12)).foregroundColor(.appTextDim)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 14)
                            }
                            .buttonStyle(.plain)
                            .appCard()
                        }

                        // HOW IT WORKS
                        AlgorithmExplainerSection()

                        // ICLOUD STATUS
                        VStack(spacing: 0) {
                            SectionHeader(title: "ICLOUD SYNC")
                                .padding(.horizontal, 16).padding(.bottom, 10)
                            iCloudStatusRow
                                .appCard()
                        }

                        // APP INFO
                        VStack(spacing: 0) {
                            SectionHeader(title: "APP")
                                .padding(.bottom, 10)

                            VStack(spacing: 0) {
                                SettingsRow(icon: "info.circle.fill", label: "Version", value: "1.0.0")
                                Divider().background(Color.appBorder)
                                SettingsRow(icon: "flask.fill", label: "Engine", value: "v4 — Adaptive")
                            }
                            .appCard()
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 40)
                }
            }
        }
        .sheet(isPresented: $showEditProfile) {
            EditProfileView()
        }
        .fullScreenCover(isPresented: $showProgramBuilder) {
            ProgramBuilderV2View()
        }
        .sheet(isPresented: $showSwitchProgram) {
            if let profile = profile {
                ProgramSelectionView(
                    recommendedId: recommendProgram(
                        goal: profile.goal.rawValue,
                        experience: profile.experience.rawValue,
                        daysPerWeek: profile.daysPerWeek
                    )
                )
            }
        }
        .sheet(isPresented: $showWeekPicker) {
            let maxWk = (activeInstance?.programId ?? activeProgram?.programId ?? 1) == 2 ? 16 : 24
            if let inst = activeInstance {
                WeekPickerSheet(
                    instance: inst,
                    legacyProgram: activeProgram,
                    maxWeek: maxWk
                )
                .presentationDetents([.medium])
            } else if let prog = activeProgram {
                WeekPickerSheet(
                    instance: nil,
                    legacyProgram: prog,
                    maxWeek: maxWk
                )
                .presentationDetents([.medium])
            }
        }
        .sheet(isPresented: $showExportShare) {
            if let url = exportFileURL {
                ShareSheet(activityItems: [url])
            }
        }
        .sheet(isPresented: $showDayTemplates) {
            DayTemplateLibraryView()
        }
        .sheet(isPresented: $showLearn) {
            NavigationStack { LearnView() }
        }
        .sheet(isPresented: $showResetProgram) {
            ResetProgramSheet(onReset: { resetProgramData() })
        }
        .fileImporter(isPresented: $showImportPicker, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result {
                importJSONBackup(from: url)
            }
        }
        .fullScreenCover(isPresented: $showGeneratedPreview) {
            NavigationStack {
                GeneratedProgramPreviewView(
                    programId: 200 + (activeInstance?.programId ?? 100),
                    programName: "Auto-Generated Program"
                )
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { showGeneratedPreview = false }
                            .foregroundColor(.appTextSecondary)
                    }
                }
            }
        }
    }

    // ── Reset Program ──────────────────────────────────────────────────

    /// Clears workout logs and program state but preserves PRs, ProgressionState, and StrengthGoals
    /// so the algorithm still has its memory of best lifts.
    private func resetProgramData() {
        guard let inst = activeInstance else { return }

        // Delete non-PR workout logs (keeps manual PRs intact)
        let logsToDelete = inst.logs.filter { !$0.isManualPR }
        for log in logsToDelete { modelContext.delete(log) }

        // Delete active workout snapshots
        for w in inst.workouts { modelContext.delete(w) }

        // Delete schedule overrides
        for s in inst.schedules { modelContext.delete(s) }

        // Delete session overrides (week-scoped exercise swaps)
        for o in inst.overrides { modelContext.delete(o) }

        // Reset block + week tracking
        inst.microcycleIndex = 0
        inst.blockWeek = 1
        inst.nextRotationIndex = 0
        inst.blockType = .accumulation
        inst.totalBlocksCompleted = 0
        inst.currentWeekSets = [:]
        inst.nextWeekSetAdjustments = [:]
        inst.mrvSignalScores = [:]
        inst.previousBlockExerciseKeys = []
        inst.startDate = Date()

        // Note: ProgressionState, StrengthGoals, LandmarkCalibration all preserved
        // so the algorithm keeps its memory of best lifts and adaptive landmarks

        try? modelContext.save()
    }

    // ── CSV Export ─────────────────────────────────────────────────────

    private func exportCSV() {
        // Collect logs from both global query AND instance
        var logs = Array(allWorkoutLogs)
        if let instLogs = activeInstance?.logs {
            let existingIds = Set(logs.map { $0.id })
            for log in instLogs where !existingIds.contains(log.id) {
                logs.append(log)
            }
        }
        guard !logs.isEmpty else { return }

        var csv = "Date,Week,Session Type,Exercise,Set,Weight,Reps,RPE,e1RM,Is Main Lift,Notes\n"
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        for log in logs.sorted(by: { $0.workoutDate < $1.workoutDate }) {
            let date = df.string(from: log.workoutDate)
            let sessionType = log.sessionTypeRaw
            let name = log.displayName.replacingOccurrences(of: ",", with: ";")
            let notes = log.sessionNotes.replacingOccurrences(of: ",", with: ";")
                .replacingOccurrences(of: "\n", with: " ")
            csv += "\(date),\(log.week),\(sessionType),\(name),\(log.setIndex + 1),\(String(format: "%.1f", log.weight)),\(log.reps),\(String(format: "%.1f", log.rpe)),\(String(format: "%.1f", log.e1rm)),\(log.isMainLift),\(notes)\n"
        }

        let fileName = "PowerBodybuilder_Export_\(df.string(from: Date())).csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try csv.write(to: tempURL, atomically: true, encoding: .utf8)
            exportFileURL = tempURL
            showExportShare = true
        } catch {
            print("Export error: \(error)")
        }
    }

    // ── JSON Backup (full data) ──────────────────────────────────────

    private func exportJSONBackup() {
        var backup: [[String: Any]] = []
        let df = ISO8601DateFormatter()

        // Collect all logs
        var logs = Array(allWorkoutLogs)
        if let instLogs = activeInstance?.logs {
            let existingIds = Set(logs.map { $0.id })
            for log in instLogs where !existingIds.contains(log.id) {
                logs.append(log)
            }
        }

        for log in logs {
            backup.append([
                "workoutDate": df.string(from: log.workoutDate),
                "date": df.string(from: log.date),
                "week": log.week,
                "sessionType": log.sessionTypeRaw,
                "exerciseKey": log.exerciseKey,
                "displayName": log.displayName,
                "slotId": log.slotId,
                "setIndex": log.setIndex,
                "weight": log.weight,
                "reps": log.reps,
                "rpe": log.rpe,
                "e1rm": log.e1rm,
                "isMainLift": log.isMainLift,
                "isTopSet": log.isTopSet,
                "hitTargetReps": log.hitTargetReps,
                "suggestedWeight": log.suggestedWeight,
                "sessionNotes": log.sessionNotes,
                "targetRepsLow": log.targetRepsLow,
                "previousWeight": log.previousWeight
            ])
        }

        // Add profile data
        var profileData: [String: Any] = [:]
        if let p = profile {
            profileData = [
                "name": p.name,
                "bodyweight": p.bodyweight,
                "age": p.age,
                "useMetric": p.useMetric,
                "goal": p.goalRaw,
                "experience": p.experienceRaw,
                "daysPerWeek": p.daysPerWeek,
                "calorieContext": p.calorieContextRaw
            ]
        }

        // Add instance data
        var instanceData: [String: Any] = [:]
        if let inst = activeInstance {
            instanceData = [
                "programId": inst.programId,
                "name": inst.name,
                "microcycleIndex": inst.microcycleIndex,
                "blockTypeRaw": inst.blockTypeRaw,
                "blockWeek": inst.blockWeek,
                "blockLength": inst.blockLength,
                "totalBlocksCompleted": inst.totalBlocksCompleted,
                "isGenerated": inst.isGenerated
            ]
        }

        let fullBackup: [String: Any] = [
            "version": 1,
            "exportDate": df.string(from: Date()),
            "profile": profileData,
            "instance": instanceData,
            "logs": backup
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: fullBackup, options: .prettyPrinted) else { return }

        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        let fileName = "PowerBodybuilder_Backup_\(dateFmt.string(from: Date())).json"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: tempURL)
            exportFileURL = tempURL
            showExportShare = true
        } catch {
            print("Backup error: \(error)")
        }
    }

    // ── JSON Import ──────────────────────────────────────────────────

    private func importJSONBackup(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let logsArray = json["logs"] as? [[String: Any]] else { return }

        let df = ISO8601DateFormatter()
        guard let inst = activeInstance else { return }

        for entry in logsArray {
            let log = WorkoutLog(
                date: df.date(from: entry["date"] as? String ?? "") ?? Date(),
                workoutDate: df.date(from: entry["workoutDate"] as? String ?? "") ?? Date(),
                week: entry["week"] as? Int ?? 1,
                sessionType: SessionType(rawValue: entry["sessionType"] as? String ?? "Heavy Upper") ?? .heavyUpper,
                exerciseKey: entry["exerciseKey"] as? String ?? "",
                displayName: entry["displayName"] as? String ?? "",
                slotId: entry["slotId"] as? String ?? "",
                setIndex: entry["setIndex"] as? Int ?? 0,
                weight: entry["weight"] as? Double ?? 0,
                reps: entry["reps"] as? Int ?? 0,
                rpe: entry["rpe"] as? Double ?? 0,
                isMainLift: entry["isMainLift"] as? Bool ?? false
            )
            log.e1rm = entry["e1rm"] as? Double ?? 0
            log.sessionNotes = entry["sessionNotes"] as? String ?? ""
            log.targetRepsLow = entry["targetRepsLow"] as? Int ?? 0
            log.previousWeight = entry["previousWeight"] as? Double ?? 0
            inst.logs.append(log)
        }

        try? modelContext.save()
    }

    private var iCloudStatusRow: some View {
        HStack(spacing: 12) {
            Image(systemName: iCloudStatus.signedIn ? "icloud.fill" : "icloud.slash.fill")
                .font(.system(size: 14)).foregroundColor(iCloudStatus.signedIn ? .appGreen : .appOrange)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(iCloudStatus.signedIn ? "Synced to iCloud" : "Not Synced")
                    .font(.system(size: 15, weight: .medium)).foregroundColor(.appTextPrimary)
                Text(iCloudStatus.message)
                    .font(.system(size: 11)).foregroundColor(.appTextDim)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .onAppear { checkICloudStatus() }
    }

    private func checkICloudStatus() {
        let token = FileManager.default.ubiquityIdentityToken
        if token == nil {
            iCloudStatus = (false, "Sign into iCloud in Settings to enable sync.")
            return
        }
        // Token exists — iCloud is signed in. SwiftData+CloudKit handles the rest.
        iCloudStatus = (true, "Your data syncs across devices using your iCloud account.")
    }

    private func displayToggle(icon: String, label: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14)).foregroundColor(.appBlue)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 15, weight: .medium)).foregroundColor(.appTextPrimary)
                Text(detail).font(.system(size: 11)).foregroundColor(.appTextDim)
            }
            Spacer()
            Toggle("", isOn: isOn).tint(.appRed).labelsHidden()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

// ═══════════════════════════════════════════
// SHARE SHEET
// ═══════════════════════════════════════════

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// ═══════════════════════════════════════════
// WEEK PICKER SHEET
// ═══════════════════════════════════════════

struct WeekPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var programTemplates: [ProgramTemplate]

    var instance: UserProgramInstance?
    var legacyProgram: UserProgram?
    let maxWeek: Int

    @State private var selectedWeek: Int = 1

    private var currentWeek: Int {
        instance?.currentWeek ?? legacyProgram?.currentWeek ?? 1
    }

    var body: some View {
        ZStack {
            Color.appBG.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.appTextSecondary)

                    Spacer()

                    Text("SELECT WEEK")
                        .font(.system(size: 15, weight: .black))
                        .foregroundColor(.appTextPrimary)
                        .kerning(1)

                    Spacer()

                    Button("Save") {
                        if let inst = instance {
                            let rotationSize = sessionRotation(for: inst.programId, templates: programTemplates).count
                            inst.microcycleIndex = selectedWeek - 1
                            inst.nextRotationIndex = (selectedWeek - 1) * rotationSize
                        }
                        legacyProgram?.currentWeek = selectedWeek
                        try? modelContext.save()
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.appRed)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color.appSurface)
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.appBorder),
                    alignment: .bottom
                )

                // Week grid
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                        ForEach(1...maxWeek, id: \.self) { week in
                            Button(action: { selectedWeek = week }) {
                                VStack(spacing: 2) {
                                    Text("\(week)")
                                        .font(.system(size: 20, weight: .black, design: .rounded))
                                    if week == currentWeek {
                                        Text("current")
                                            .font(.system(size: 8, weight: .medium))
                                            .foregroundColor(selectedWeek == week ? .white.opacity(0.8) : .appTextDim)
                                    }
                                }
                                .foregroundColor(selectedWeek == week ? .white : .appTextSecondary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(selectedWeek == week ? Color.appRed : Color.appSurface)
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(selectedWeek == week ? Color.appRed : week == currentWeek ? Color.appRed.opacity(0.4) : Color.appBorder, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .onAppear {
            selectedWeek = currentWeek
        }
    }
}

// ═══════════════════════════════════════════
// ═══════════════════════════════════════════
// ALGORITHM EXPLAINER
// ═══════════════════════════════════════════

struct AlgorithmExplainerSection: View {
    @State private var expandedTopic: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "HOW IT WORKS")
                .padding(.bottom, 10)

            VStack(spacing: 0) {
                // Intro
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.appRed.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.appRed)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("SMART PROGRESSION ENGINE")
                                .font(.system(size: 13, weight: .black))
                                .foregroundColor(.appTextPrimary)
                                .kerning(0.5)
                            Text("Evidence-based, adapts to your performance")
                                .font(.system(size: 11))
                                .foregroundColor(.appTextSecondary)
                        }
                    }

                    Text("This app doesn't just track your workouts — it watches how you perform set to set, week to week, and automatically adjusts your programming. Here's what powers it:")
                        .font(.system(size: 12))
                        .foregroundColor(.appTextSecondary)
                        .padding(.top, 4)
                }
                .padding(16)

                Divider().background(Color.appBorder)

                // Topics
                explainerTopic(
                    id: "progression",
                    icon: "arrow.up.right",
                    title: "Smart Progression",
                    subtitle: "Two signals decide when you add weight",
                    body: """
                    The engine uses two layers of intelligence:

                    PRIMARY (6+ sessions): Your estimated 1RM trend. If your e1RM is genuinely rising (>2.5%), weight goes up. If declining, weight drops. This catches real strength changes while ignoring session-to-session noise.

                    SECONDARY (<6 sessions): Double progression. Hit the top of your rep range on all working sets → add weight. Miss the bottom for 2 sessions in a row → reduce weight.

                    Per-set targets are personalized: instead of showing "12/12/12" for every set, the engine shows your last week's reps +1 per set (e.g., "11/10/9"). This accounts for natural fatigue across sets and gives you a realistic, motivating target.

                    For isolation exercises (T3), the engine uses top-set progression — if your first set hits the top of the range, weight goes up even if sets 2-3 are slightly below. For compounds (T1/T2), ALL sets must hit the top, keeping progression stable.
                    """
                )

                explainerTopic(
                    id: "ifi",
                    icon: "waveform.path.ecg",
                    title: "Intraset Fatigue Index (IFI)",
                    subtitle: "Objective fatigue measurement — no other app has this",
                    body: """
                    IFI measures how much your performance drops from your first working set to your last:

                    Example: 10, 9, 7 reps → IFI = 0.30

                    FRESH (< 10%) — Barely fatigued. Rep targets pushed +2 next session.
                    OPTIMAL (10-25%) — Normal drop-off. Standard +1 rep progression.
                    FATIGUED (25-40%) — Blocks weight increases. Rep targets hold steady.
                    OVERTRAINED (40%+) — Forces weight reduction.

                    IFI also feeds into stall diagnosis, volume decisions, and the MRV signal engine. It's the single most important metric in the system — entirely objective, no self-reporting needed.
                    """
                )

                explainerTopic(
                    id: "pml",
                    icon: "figure.walk.motion",
                    title: "Prior Muscle Load (PML)",
                    subtitle: "Adjusts for exercise order within your session",
                    body: """
                    If you do tricep pushdowns after 4 sets of bench press, your triceps are already fatigued. The engine knows this.

                    PML computes accumulated fatigue on each muscle from earlier exercises using a muscle overlap map (e.g., bench press fatigues triceps at 40%). It adjusts your weight recommendation down so you're not trying to lift "fresh" weight with pre-fatigued muscles.

                    The adjustment is adaptive — over time, the engine learns YOUR personal sensitivity to pre-fatigue. Some people's triceps barely notice chest work. Others lose 30% capacity. The engine figures out which you are and calibrates accordingly.

                    You'll see a subtle note on adjusted exercises: "Adjusted for earlier chest work." Tap for details.
                    """
                )

                explainerTopic(
                    id: "readiness",
                    icon: "heart.text.square",
                    title: "Pre-Workout Readiness",
                    subtitle: "Bad day? Great day? The algorithm adapts.",
                    body: """
                    Before each workout, rate how you feel on a 1-5 scale:

                    1 (Very Low) — Weight drops 10%, rep targets -3, volume cut 40%. Protects you from injury on terrible days.
                    2 (Below Avg) — Weight drops 5%, rep targets -1.
                    3 (Normal) — No changes. This is the default if you skip.
                    4 (Good) — Rep targets pushed +1. Great day to build reps.
                    5 (Excellent) — Weight bumps +2%, rep targets +2. Go hard.

                    Skip = Normal. No penalty for not answering.
                    """
                )

                explainerTopic(
                    id: "volume",
                    icon: "chart.bar.fill",
                    title: "Volume Landmarks",
                    subtitle: "MEV / MAV / MRV — your optimal training zone",
                    body: """
                    Every muscle has a volume sweet spot:

                    MEV (Minimum Effective) — Below this, you're not doing enough.
                    MAV (Maximum Adaptive) — The productive range where gains happen.
                    MRV (Maximum Recoverable) — Above this, you can't recover.

                    The app tracks weekly sets per muscle (primary = 1.0, secondary = weighted 0.2-0.7) and classifies your volume zone with color coding. These landmarks adapt over time based on your actual performance — the more you train, the more accurate they become.
                    """
                )

                explainerTopic(
                    id: "stall",
                    icon: "exclamationmark.triangle.fill",
                    title: "Stall Detection & Diagnosis",
                    subtitle: "Knows WHY you're stuck, not just that you are",
                    body: """
                    When progress flatlines, the engine diagnoses the cause:

                    FATIGUE STALL — High IFI + declining e1RM. You need a deload.
                    INTENSITY STALL — Low IFI + flat e1RM. Push harder — you're sandbagging.
                    TRUE PLATEAU — Normal IFI + flat e1RM. Swap exercises for fresh stimulus.
                    VOLUME STALL — Very high IFI everywhere. Cut sets, let recovery catch up.

                    Each diagnosis has specific, actionable advice. The engine also tracks escalation — first time is a suggestion, second time is a warning, third time is action required.
                    """
                )

                explainerTopic(
                    id: "strength",
                    icon: "target",
                    title: "Strength Goals",
                    subtitle: "Peak a specific lift while staying hypertrophy",
                    body: """
                    Want to hit a 275 bench while running a hypertrophy program? Set a Strength Goal.

                    The engine creates a phased peaking plan for that ONE lift:
                    • Building — 4×3-5 @ RPE 7-8 (build strength base)
                    • Intensifying — 3×2-3 @ RPE 8-9 (shift to heavier loads)
                    • Peaking — 2×1-2 @ RPE 9+ (near-max preparation)
                    • Testing — 1×1 (go for your target)

                    Everything else in your program stays hypertrophy. Phase lengths auto-scale based on how far you are from the target. Max 2 goals active at once.
                    """
                )

                explainerTopic(
                    id: "modes",
                    icon: "slider.horizontal.3",
                    title: "Algorithm Modes",
                    subtitle: "Full control over how much the engine does",
                    body: """
                    In Settings, choose how the algorithm works:

                    FULL — Weight pre-filled, rep targets shown, volume and stall decisions auto-applied. The engine drives everything.

                    SUGGESTIONS — Shows recommended weights and targets as gray hints. Nothing is pre-filled. You see the suggestions but make every decision.

                    OFF — Pure logger. No recommendations shown. But the algorithm still tracks your e1RM, IFI, and trends in the background — so switching back to Full or Suggestions gives you instant recommendations with full history.
                    """
                )
            }
            .appCard()

            // What makes this different
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.appGold)
                    Text("WHAT MAKES THIS DIFFERENT")
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(.appGold)
                        .kerning(1)
                }

                VStack(alignment: .leading, spacing: 8) {
                    diffPoint(text: "Per-set rep targets — shows 11/10/9 based on YOUR last session, not a flat ceiling like every other app.")
                    diffPoint(text: "IFI catches fatigue before you feel it — no other app measures intra-session rep drop-off as a first-class signal.")
                    diffPoint(text: "PML adjusts for exercise order — your pushdowns know you already did bench. No other app does this.")
                    diffPoint(text: "Adaptive sensitivity — the engine learns how YOUR body responds to fatigue, not a one-size-fits-all formula.")
                    diffPoint(text: "Strength Goals let you peak one lift while staying hypertrophy everywhere else — a feature not available in RP, Alpha Progression, or any competitor.")
                    diffPoint(text: "4 types of stall diagnosis — we don't just say you're stuck, we tell you WHY and what to do about it.")
                    diffPoint(text: "Algorithm modes — Full, Suggestions, or Off. You choose how much control the engine has, and it never stops learning.")
                    diffPoint(text: "Every set you log makes every future recommendation smarter. The more you train, the better it gets.")
                }
            }
            .padding(16)
            .background(Color.appGold.opacity(0.06))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appGold.opacity(0.2), lineWidth: 1))
            .padding(.top, 10)
        }
    }

    @ViewBuilder
    private func explainerTopic(id: String, icon: String, title: String, subtitle: String, body: String) -> some View {
        VStack(spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    expandedTopic = expandedTopic == id ? nil : id
                }
            }) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.appRed)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 13, weight: .black))
                            .foregroundColor(.appTextPrimary)
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundColor(.appTextDim)
                    }
                    Spacer()
                    Image(systemName: expandedTopic == id ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.appTextDim)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            if expandedTopic == id {
                Text(body)
                    .font(.system(size: 12))
                    .foregroundColor(.appTextSecondary)
                    .lineSpacing(4)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider().background(Color.appBorder)
        }
    }

    private func diffPoint(text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Color.appGold)
                .frame(width: 4, height: 4)
                .padding(.top, 6)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.appTextSecondary)
                .lineSpacing(2)
        }
    }
}

// ALGORITHM MODE PICKER (isolated state to avoid full-view refresh lag)
// ═══════════════════════════════════════════

struct AlgorithmModePicker: View {
    let profile: UserProfile?
    let modelContext: ModelContext
    @State private var selected: AlgorithmMode = .full

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "ALGORITHM")
                .padding(.bottom, 10)

            VStack(spacing: 0) {
                ForEach(AlgorithmMode.allCases, id: \.self) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { selected = mode }
                        profile?.algorithmMode = mode
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            try? modelContext.save()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selected == mode ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 16))
                                .foregroundColor(selected == mode ? .appRed : .appTextDim)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.displayName)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.appTextPrimary)
                                Text(mode.subtitle)
                                    .font(.system(size: 11))
                                    .foregroundColor(.appTextDim)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    if mode != .off {
                        Divider().background(Color.appBorder).padding(.leading, 44)
                    }
                }
            }
            .appCard()
        }
        .onAppear { selected = profile?.algorithmMode ?? .full }
    }
}

// PROFILE STAT
// ═══════════════════════════════════════════

struct ProfileStat: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.appTextDim)
                .kerning(1)
            Text(value)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.appTextSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

// ═══════════════════════════════════════════
// SETTINGS ROW
// ═══════════════════════════════════════════

struct SettingsRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.appTextDim)
                .frame(width: 20)
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.appTextSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.appTextDim)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// ═══════════════════════════════════════════
// EDIT PROFILE VIEW
// ═══════════════════════════════════════════

struct EditProfileView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]
    
    var profile: UserProfile? { profiles.first }
    
    @State private var name: String = ""
    @State private var bodyweight: String = ""
    @State private var age: String = ""
    @State private var useMetric: Bool = false
    @State private var goal: String = "hypertrophy"
    @State private var experience: String = "Beginner"
    @State private var daysPerWeek: Int = 4
    @State private var priorityMuscles: Set<String> = []
    @State private var muscleTierSelections: [String: MuscleTier] = [:]
    @State private var muscleTargetOverrides: [String: Int] = [:]
    @State private var editingTargetMuscle: String? = nil

    let goals = GoalType.allCases
    let experiences = ["Beginner", "Intermediate", "Advanced"]
    let muscles = ExerciseDictionary.trackingMuscles
    
    var body: some View {
        ZStack {
            Color.appBG
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                
                HStack {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.appTextSecondary)
                    
                    Spacer()
                    
                    Text("EDIT PROFILE")
                        .font(.system(size: 15, weight: .black))
                        .foregroundColor(.appTextPrimary)
                        .kerning(1)
                    
                    Spacer()
                    
                    Button("Save") { saveChanges() }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.appRed)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color.appSurface)
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.appBorder),
                    alignment: .bottom
                )
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        
                        // BASIC INFO
                        VStack(spacing: 10) {
                            SectionHeader(title: "BASIC INFO")
                            AppTextField(placeholder: "Your name", text: $name, icon: "person.fill")
                            AppTextField(
                                placeholder: useMetric ? "Bodyweight (kg)" : "Bodyweight (lbs)",
                                text: $bodyweight,
                                keyboardType: .decimalPad,
                                icon: "scalemass.fill"
                            )
                            AppTextField(placeholder: "Age", text: $age, keyboardType: .numberPad, icon: "calendar")
                            
                            HStack {
                                Image(systemName: "globe")
                                    .font(.system(size: 14))
                                    .foregroundColor(.appTextDim)
                                Text("Use Metric (kg/cm)")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.appTextSecondary)
                                Spacer()
                                Toggle("", isOn: $useMetric)
                                    .tint(.appRed)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Color.appSurface2)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.appBorder, lineWidth: 1)
                            )
                        }
                        
                        // GOAL
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "MAIN GOAL")
                            ForEach(goals, id: \.self) { g in
                                Button(action: { goal = g.rawValue }) {
                                    HStack {
                                        Text(g.displayName)
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundColor(goal == g.rawValue ? .white : .appTextSecondary)
                                        Spacer()
                                        if goal == g.rawValue {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.white)
                                        }
                                    }
                                    .padding(14)
                                    .background(goal == g.rawValue ? Color.appRed : Color.appSurface)
                                    .cornerRadius(10)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(goal == g.rawValue ? Color.appRed : Color.appBorder, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        
                        // EXPERIENCE
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "EXPERIENCE LEVEL")
                            HStack(spacing: 8) {
                                ForEach(experiences, id: \.self) { exp in
                                    Button(action: { experience = exp }) {
                                        Text(exp)
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(experience == exp ? .white : .appTextSecondary)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 14)
                                            .background(experience == exp ? Color.appRed : Color.appSurface)
                                            .cornerRadius(10)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .stroke(experience == exp ? Color.appRed : Color.appBorder, lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        
                        // DAYS
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "DAYS PER WEEK")
                            HStack(spacing: 8) {
                                ForEach([3, 4, 5, 6], id: \.self) { d in
                                    Button(action: { daysPerWeek = d }) {
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
                        
                        // MUSCLE PRIORITY TIERS
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "MUSCLE PRIORITIES")
                            Text("Tap to cycle: Neutral → Priority → Maintenance → Neutral")
                                .font(.system(size: 11))
                                .foregroundColor(.appTextDim)

                            let priorityCount = muscleTierSelections.values.filter { $0 == .priority }.count
                            let maintenanceCount = muscleTierSelections.values.filter { $0 == .maintenance }.count
                            let priorityCap = tierCap(for: ExperienceLevel(rawValue: experience) ?? .beginner)

                            // Volume budget preview
                            let totalMAV = muscles.reduce(0) { sum, m in
                                let tier = muscleTierSelections[m] ?? .neutral
                                let lm = VolumeLandmark.defaults[m] ?? VolumeLandmark(mev: 4, mavLow: 8, mavHigh: 12, mrv: 18)
                                return sum + Int(round(Double(lm.mav) * tier.multiplier))
                            }
                            HStack(spacing: 6) {
                                Text("Est. weekly volume:").font(.system(size: 11, weight: .medium)).foregroundColor(.appTextDim)
                                Text("\(totalMAV) sets").font(.system(size: 12, weight: .black, design: .rounded))
                                    .foregroundColor(totalMAV > 140 ? .appOrange : .appGreen)
                                Spacer()
                                HStack(spacing: 4) {
                                    Text("★ \(priorityCount)/\(priorityCap)").font(.system(size: 10, weight: .bold)).foregroundColor(.appGold)
                                    Text("▼ \(maintenanceCount)").font(.system(size: 10, weight: .bold)).foregroundColor(.appBlue)
                                }
                            }
                            .padding(.horizontal, 4)

                            ForEach(muscles, id: \.self) { muscle in
                                muscleRow(
                                    muscle: muscle,
                                    priorityCount: priorityCount,
                                    priorityCap: priorityCap
                                )
                            }

                            if priorityCount >= priorityCap {
                                Text("You can prioritize up to \(priorityCap) muscles at this level.")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.appRed)
                                    .padding(.horizontal, 4)
                            }
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 40)
                }
            }
        }
        .onAppear {
            loadCurrentValues()
        }
        .sheet(item: Binding(
            get: { editingTargetMuscle.map(MuscleEdit.init) },
            set: { editingTargetMuscle = $0?.name }
        )) { edit in
            NumericInputSheet(
                title: edit.name,
                subtitle: "Set your weekly target sets for \(edit.name).",
                initialValue: muscleTargetOverrides[edit.name] ?? autoDefaultTarget(for: edit.name),
                suggestionLow: suggestedLowerLimit(for: edit.name),
                suggestionHigh: suggestedUpperLimit(for: edit.name),
                onSave: { value in
                    setTargetOverride(muscle: edit.name, value: value,
                                      autoDefault: autoDefaultTarget(for: edit.name))
                }
            )
            .presentationDetents([.medium])
        }
    }

    /// Identifiable wrapper so sheet(item:) can drive the muscle target editor.
    private struct MuscleEdit: Identifiable {
        let name: String
        var id: String { name }
    }

    func loadCurrentValues() {
        guard let profile = profile else { return }
        name = profile.name
        bodyweight = String(format: "%.0f", profile.bodyweight)
        age = "\(profile.age)"
        useMetric = profile.useMetric
        goal = profile.goalRaw
        experience = profile.experienceRaw
        daysPerWeek = profile.daysPerWeek
        priorityMuscles = Set(profile.priorityMuscles)
        muscleTierSelections = profile.muscleTiers
        muscleTargetOverrides = profile.muscleTargetOverrides
    }

    func saveChanges() {
        guard let profile = profile else { return }
        profile.name = name
        profile.bodyweight = Double(bodyweight) ?? profile.bodyweight
        profile.age = Int(age) ?? profile.age
        profile.useMetric = useMetric
        profile.goalRaw = goal
        profile.experienceRaw = experience
        profile.daysPerWeek = daysPerWeek
        profile.muscleTiers = muscleTierSelections
        profile.muscleTargetOverrides = muscleTargetOverrides
        dismiss()
    }

    /// Auto-computed default target for a muscle (tier-derived MAVHigh, scaled).
    private func autoDefaultTarget(for muscle: String) -> Int {
        let tier = muscleTierSelections[muscle] ?? .neutral
        let base = VolumeLandmark.defaults[muscle] ?? VolumeLandmark(mev: 4, mavLow: 8, mavHigh: 12, mrv: 18)
        return Int(round(Double(base.mavHigh) * tier.multiplier))
    }

    /// Suggested upper limit (effective MRV) given tier + experience.
    private func suggestedUpperLimit(for muscle: String) -> Int {
        let tier = muscleTierSelections[muscle] ?? .neutral
        let exp = ExperienceLevel(rawValue: experience) ?? .intermediate
        return VolumeLandmark.effectiveMRV(muscle: muscle, experience: exp, tier: tier)
    }

    /// MEV (effective floor) for the suggestion text range.
    private func suggestedLowerLimit(for muscle: String) -> Int {
        let tier = muscleTierSelections[muscle] ?? .neutral
        let exp = ExperienceLevel(rawValue: experience) ?? .intermediate
        return VolumeLandmark.effectiveMEV(muscle: muscle, experience: exp, tier: tier)
    }

    /// One muscle row: tier-cycle button on top, target stepper + suggestion below.
    @ViewBuilder
    private func muscleRow(muscle: String, priorityCount: Int, priorityCap: Int) -> some View {
        let currentTier = muscleTierSelections[muscle] ?? .neutral
        let mev = suggestedLowerLimit(for: muscle)
        let mrv = suggestedUpperLimit(for: muscle)
        let autoDefault = autoDefaultTarget(for: muscle)
        let custom = muscleTargetOverrides[muscle]
        let effectiveTarget = custom.flatMap { $0 > 0 ? $0 : nil } ?? autoDefault

        VStack(spacing: 8) {
            // Tier-cycle row
            Button(action: {
                let next = cycleTier(muscle, current: currentTier,
                                     priorityCount: priorityCount,
                                     priorityCap: priorityCap)
                if next == .neutral {
                    muscleTierSelections.removeValue(forKey: muscle)
                } else {
                    muscleTierSelections[muscle] = next
                }
            }) {
                HStack(spacing: 10) {
                    tierBadge(currentTier)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(muscle)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(tierTextColor(currentTier))
                        if currentTier == .maintenance {
                            Text("Frees recovery for priorities")
                                .font(.system(size: 10))
                                .foregroundColor(.appTextDim)
                        }
                    }
                    Spacer()
                    Text(tierLabel(currentTier))
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(tierTextColor(currentTier).opacity(0.7))
                        .kerning(0.5)
                }
            }
            .buttonStyle(.plain)

            // Target stepper row
            HStack(spacing: 10) {
                Text("Target")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.appTextDim)

                Button {
                    let cur = effectiveTarget
                    let next = max(0, cur - 1)
                    setTargetOverride(muscle: muscle, value: next, autoDefault: autoDefault)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.appRed)
                }
                .buttonStyle(.plain)

                Button {
                    editingTargetMuscle = muscle
                } label: {
                    Text("\(effectiveTarget)")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundColor(custom != nil && custom! > 0 ? .appBlue : .appTextPrimary)
                        .frame(minWidth: 36)
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(Color.appBG.opacity(0.6))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.appBorder, lineWidth: 0.5))
                }
                .buttonStyle(.plain)

                Button {
                    let cur = effectiveTarget
                    setTargetOverride(muscle: muscle, value: cur + 1, autoDefault: autoDefault)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.appGreen)
                }
                .buttonStyle(.plain)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Suggested \(mev)–\(mrv)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.appTextDim)
                    if effectiveTarget > mrv {
                        Text("Above MRV — recovery risk")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.appOrange)
                    } else if effectiveTarget < mev && effectiveTarget > 0 {
                        Text("Below MEV — minimal growth")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.appRed)
                    } else if custom != nil && custom! > 0 {
                        Text("Custom · tap auto to reset")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.appBlue)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.appBG.opacity(0.4))
            .cornerRadius(8)

            if custom != nil && custom! > 0 {
                Button {
                    muscleTargetOverrides.removeValue(forKey: muscle)
                } label: {
                    Text("Reset to auto (\(autoDefault))")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.appBlue)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(tierBGColor(currentTier))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(tierBorderColor(currentTier), lineWidth: 1)
        )
    }

    /// Set a custom override only when value differs from the auto-default;
    /// otherwise clear the override so the row reverts to auto-tracking.
    private func setTargetOverride(muscle: String, value: Int, autoDefault: Int) {
        if value == autoDefault {
            muscleTargetOverrides.removeValue(forKey: muscle)
        } else {
            muscleTargetOverrides[muscle] = value
        }
    }

    private func tierCap(for exp: ExperienceLevel) -> Int {
        switch exp {
        case .beginner:      return 2
        case .intermediate:  return 3
        case .advanced:      return 4
        case .elite:         return 4
        }
    }

    private func cycleTier(_ muscle: String, current: MuscleTier,
                           priorityCount: Int, priorityCap: Int) -> MuscleTier {
        switch current {
        case .neutral:
            // Skip priority if at cap → go straight to maintenance
            return priorityCount < priorityCap ? .priority : .maintenance
        case .priority:
            return .maintenance
        case .maintenance:
            return .neutral
        }
    }

    private func tierLabel(_ tier: MuscleTier) -> String {
        switch tier {
        case .priority:    return "PRIORITY"
        case .neutral:     return "NEUTRAL"
        case .maintenance: return "MAINTAIN"
        }
    }

    @ViewBuilder
    private func tierBadge(_ tier: MuscleTier) -> some View {
        switch tier {
        case .priority:
            Image(systemName: "star.fill").font(.system(size: 14)).foregroundColor(.appGold)
        case .maintenance:
            Image(systemName: "arrow.down.circle").font(.system(size: 13)).foregroundColor(.appBlue)
        case .neutral:
            Image(systemName: "circle").font(.system(size: 12)).foregroundColor(.appTextDim)
        }
    }

    private func tierTextColor(_ tier: MuscleTier) -> Color {
        switch tier {
        case .priority: return .appGold
        case .neutral: return .appTextSecondary
        case .maintenance: return .appBlue
        }
    }

    private func tierBGColor(_ tier: MuscleTier) -> Color {
        switch tier {
        case .priority: return Color.appGold.opacity(0.1)
        case .neutral: return Color.appSurface
        case .maintenance: return Color.appBlue.opacity(0.08)
        }
    }

    private func tierBorderColor(_ tier: MuscleTier) -> Color {
        switch tier {
        case .priority: return Color.appGold.opacity(0.4)
        case .neutral: return Color.appBorder
        case .maintenance: return Color.appBlue.opacity(0.3)
        }
    }
}

// ═══════════════════════════════════════════
// RESET PROGRAM SHEET
// Two-step destructive confirmation requiring typed phrase
// ═══════════════════════════════════════════

struct ResetProgramSheet: View {
    let onReset: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var step: Int = 1
    @State private var typedConfirmation: String = ""
    private let confirmationPhrase = "RESET"

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBG.ignoresSafeArea()
                if step == 1 { explainStep } else { confirmStep }
            }
            .navigationTitle("Reset Program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundColor(.appTextSecondary)
                }
            }
        }
    }

    // ── Step 1: Explain what's reset vs preserved ──
    private var explainStep: some View {
        ScrollView {
            VStack(spacing: 20) {
                ZStack {
                    Circle().fill(Color.appOrange.opacity(0.1)).frame(width: 80, height: 80)
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.system(size: 36)).foregroundColor(.appOrange)
                }
                .padding(.top, 16)

                Text("Start Over From Week 1")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(.appTextPrimary)

                Text("This resets your current program back to a clean slate. Your training history is cleared, but your strength data stays so the algorithm still knows your lifts.")
                    .font(.system(size: 14)).foregroundColor(.appTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                // What's preserved
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.shield.fill").foregroundColor(.appGreen)
                        Text("PRESERVED").font(.system(size: 11, weight: .black)).foregroundColor(.appGreen).kerning(1)
                    }
                    bulletItem(text: "All logged PRs (manually entered)")
                    bulletItem(text: "Best e1RM and last session weights")
                    bulletItem(text: "Algorithm's adaptive memory")
                    bulletItem(text: "Strength goals and targets")
                    bulletItem(text: "Volume landmark calibration")
                    bulletItem(text: "Profile and settings")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color.appGreen.opacity(0.04)).cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appGreen.opacity(0.2), lineWidth: 1))

                // What's cleared
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash.fill").foregroundColor(.appOrange)
                        Text("CLEARED").font(.system(size: 11, weight: .black)).foregroundColor(.appOrange).kerning(1)
                    }
                    bulletItem(text: "All workout logs from sessions", color: .appOrange)
                    bulletItem(text: "Week and block progress", color: .appOrange)
                    bulletItem(text: "Schedule customizations", color: .appOrange)
                    bulletItem(text: "Exercise swaps for the program", color: .appOrange)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color.appOrange.opacity(0.04)).cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appOrange.opacity(0.2), lineWidth: 1))

                Button { withAnimation { step = 2 } } label: {
                    HStack(spacing: 6) {
                        Text("CONTINUE").font(.system(size: 14, weight: .black)).kerning(1)
                        Image(systemName: "arrow.right").font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color.appOrange).cornerRadius(12)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(20)
        }
    }

    // ── Step 2: Type RESET to confirm ──
    private var confirmStep: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle().fill(Color.appRed.opacity(0.1)).frame(width: 80, height: 80)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36)).foregroundColor(.appRed)
            }

            Text("Are You Sure?")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundColor(.appTextPrimary)

            Text("This cannot be undone. All workout logs from your current program will be permanently deleted.")
                .font(.system(size: 14)).foregroundColor(.appTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            VStack(spacing: 8) {
                Text("Type \(confirmationPhrase) to confirm")
                    .font(.system(size: 12, weight: .bold)).foregroundColor(.appTextDim)
                TextField("", text: $typedConfirmation)
                    .font(.system(size: 18, weight: .black, design: .monospaced))
                    .foregroundColor(.appTextPrimary)
                    .multilineTextAlignment(.center)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .background(Color.appSurface2).cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(
                        typedConfirmation == confirmationPhrase ? Color.appRed : Color.appBorder,
                        lineWidth: 1.5))
                    .padding(.horizontal, 20)
            }
            .padding(.top, 8)

            Spacer()

            VStack(spacing: 10) {
                Button {
                    onReset()
                    dismiss()
                } label: {
                    Text("RESET PROGRAM")
                        .font(.system(size: 14, weight: .black)).kerning(1)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(typedConfirmation == confirmationPhrase ? Color.appRed : Color.appSurface2)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .disabled(typedConfirmation != confirmationPhrase)

                Button { withAnimation { step = 1; typedConfirmation = "" } } label: {
                    Text("Go Back")
                        .font(.system(size: 14, weight: .medium)).foregroundColor(.appTextSecondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.bottom, 40)
        }
    }

    private func bulletItem(text: String, color: Color = .appGreen) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(color).frame(width: 4, height: 4).padding(.top, 7)
            Text(text).font(.system(size: 13)).foregroundColor(.appTextSecondary)
        }
    }
}
