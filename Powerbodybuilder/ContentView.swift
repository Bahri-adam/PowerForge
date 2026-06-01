import SwiftUI
import SwiftData

struct ContentView: View {

    @Environment(\.modelContext) private var modelContext

    @State private var selectedTab: Int = 0
    @State private var showRestorePrompt = false
    @State private var didCheckBackup = false
    @Query private var profiles: [UserProfile]
    @Query private var programs: [UserProgram]
    @Query private var programTemplates: [ProgramTemplate]

    var body: some View {
        Group {
            if profiles.isEmpty || programs.isEmpty {
                OnboardingView()
            } else {
                TabView(selection: $selectedTab) {
                    HomeView(switchToTrain: { selectedTab = 1 })
                        .tabItem { Label("Home", systemImage: "house.fill") }.tag(0)
                    WorkoutView()
                        .tabItem { Label("Train", systemImage: "dumbbell.fill") }.tag(1)
                    ProgramTabView()
                        .tabItem { Label("Program", systemImage: "list.bullet.clipboard.fill") }.tag(2)
                    ProgressView()
                        .tabItem { Label("Progress", systemImage: "trophy.fill") }.tag(3)
                    SettingsView()
                        .tabItem { Label("Settings", systemImage: "gearshape.fill") }.tag(4)
                }
                .tint(.appRed)
            }
        }
        .onAppear {
            preloadExercisesIfNeeded(context: modelContext)
            ProgramSeeder.seedPowerbuildingProgram(context: modelContext)
            PPLSeeder.seedPPLProgram(context: modelContext)
            BahriSplitSeeder.seedIfNeeded(context: modelContext)
            BahriSplitSeeder.migrateLegacyKeysIfNeeded(context: modelContext)
            AthleticSeeder.seedIfNeeded(context: modelContext)
            StrengthSeeder.seedIfNeeded(context: modelContext)
            BeginnerSeeder.seedIfNeeded(context: modelContext)
            MinimalistSeeder.seedIfNeeded(context: modelContext)
            AestheticSplitSeeder.seedIfNeeded(context: modelContext)
            migrateBrokenCustomProgramsIfNeeded(context: modelContext)
            resetStaleMRVSignalScoresIfNeeded(context: modelContext)
            clearStaleDeloadOverridesIfNeeded(context: modelContext)
            loadCustomPrograms()

            // Check for backup on first launch (no profile yet) — show restore prompt
            if !didCheckBackup {
                didCheckBackup = true
                if profiles.isEmpty && BackupManager.shared.backupExists() {
                    showRestorePrompt = true
                }
            }
        }
        .onChange(of: profiles.count) { _, _ in
            // Schedule a backup whenever data changes meaningfully
            BackupManager.shared.scheduleBackup(context: modelContext)
        }
        .alert("Restore from iCloud Backup?", isPresented: $showRestorePrompt) {
            Button("Restore") {
                Task {
                    let count = await BackupManager.shared.restoreFromBackup(context: modelContext)
                    print("📦 Restored \(count ?? 0) records from backup")
                }
            }
            Button("Start Fresh", role: .cancel) {}
        } message: {
            if let meta = BackupManager.shared.backupMetadata() {
                let dateStr = DateFormatter.localizedString(from: meta.date, dateStyle: .medium, timeStyle: .short)
                Text("Found a backup from \(dateStr). Restore your workouts, custom programs, and PRs?")
            } else {
                Text("Found a backup in your iCloud. Restore your data?")
            }
        }
    }

    /// One-time migration: an earlier V2 builder bug allocated custom-program IDs
    /// in the 8..<100 range when only built-in templates existed. Those IDs fall
    /// through sessionRotation's switch and get rendered as heavyUpper/Lower with
    /// 0 templates. Rewrites them to fresh pids >= 100 across ProgramTemplate,
    /// ProgramSessionTemplate, UserProgramInstance, and UserProgram.
    /// One-time clear of accumulated MRV signal scores. Earlier versions of
    /// MRVSignalEngine.computeScore fired S1 (e1RM decline +3) and S2 (high
    /// IFI +2) without a minimum-exposures guard, so scores accumulated
    /// rapidly on fresh sessions and triggered false "High fatigue" alerts.
    /// The engine now guards by totalExposures, but stored scores from the
    /// old logic stay in place. Clearing them lets the new logic rebuild
    /// scores correctly from the next session forward.
    private func resetStaleMRVSignalScoresIfNeeded(context: ModelContext) {
        let flag = "ProgramMigrations.resetStaleMRVScores.v1"
        if UserDefaults.standard.bool(forKey: flag) { return }
        let instances = (try? context.fetch(FetchDescriptor<UserProgramInstance>())) ?? []
        for inst in instances { inst.mrvSignalScores = [:] }
        try? context.save()
        UserDefaults.standard.set(true, forKey: flag)
    }

    /// One-time cleanup: earlier sessions could leave an instance's per-week
    /// deload overrides (skippedDeloadWeeks / customDeloadWeeks / blockLayout)
    /// in a state that contradicted the program's seeded deload schedule — e.g.
    /// Bahri weeks 3 & 4 both flagged as deloads after toggling Skip Deloads.
    /// Those overrides fight the global Skip Deloads toggle and surface phantom
    /// deloads when it's turned off. For built-in (seeded) programs the seeded
    /// schedule is the source of truth, so clear the overrides and fall back to
    /// it — this makes toggling Skip Deloads on/off seamless. Custom/generated
    /// programs (pid >= 100) are left alone since their blockLayout may be the
    /// only source of block structure.
    private func clearStaleDeloadOverridesIfNeeded(context: ModelContext) {
        let flag = "ProgramMigrations.clearStaleDeloadOverrides.v1"
        if UserDefaults.standard.bool(forKey: flag) { return }
        let instances = (try? context.fetch(FetchDescriptor<UserProgramInstance>())) ?? []
        for inst in instances where inst.programId <= 7 {
            inst.skippedDeloadWeeks = []
            inst.customDeloadWeeks = []
            inst.blockLayout = []
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: flag)
        print("[ProgramMigrations] Cleared stale deload overrides on built-in program instances")
    }

    private func migrateBrokenCustomProgramsIfNeeded(context: ModelContext) {
        let flag = "ProgramMigrations.brokenCustomPrograms.v1"
        if UserDefaults.standard.bool(forKey: flag) { return }

        let knownBuiltIn: Set<Int> = [0, 1, 2, 3, 4, 5, 6, 7]
        let allTemplates = (try? context.fetch(FetchDescriptor<ProgramTemplate>())) ?? []
        let broken = allTemplates.filter { !knownBuiltIn.contains($0.programId) && $0.programId < 100 }
        guard !broken.isEmpty else {
            UserDefaults.standard.set(true, forKey: flag)
            return
        }

        let sessionTemplates = (try? context.fetch(FetchDescriptor<ProgramSessionTemplate>())) ?? []
        let instances = (try? context.fetch(FetchDescriptor<UserProgramInstance>())) ?? []
        let userPrograms = (try? context.fetch(FetchDescriptor<UserProgram>())) ?? []

        var nextId = max(100, (allTemplates.map { $0.programId }.max() ?? 99) + 1)

        for tmpl in broken {
            let oldId = tmpl.programId
            let newId = nextId
            nextId += 1

            tmpl.programId = newId
            for st in sessionTemplates where st.programId == oldId { st.programId = newId }
            for inst in instances where inst.programId == oldId { inst.programId = newId }
            for up in userPrograms where up.programId == oldId { up.programId = newId }
        }

        try? context.save()
        UserDefaults.standard.set(true, forKey: flag)
        print("[ProgramMigrations] Migrated \(broken.count) broken custom program(s) to pid >= 100")
    }

    private func loadCustomPrograms() {
        customPrograms = programTemplates
            .filter { $0.programId >= 100 }
            .map { tmpl in
                ProgramDef(
                    id: tmpl.programId,
                    name: tmpl.name.uppercased(),
                    subtitle: "Custom \(tmpl.sessionTypes.count)-Day Program",
                    description: "Custom \(tmpl.sessionTypes.count)-day program with auto-periodized progression.",
                    days: "\(tmpl.sessionTypes.count) days/week",
                    sessionLength: "60–90 min",
                    split: tmpl.sessionTypes.map { $0.shortLabel }.joined(separator: " / "),
                    difficulty: "Custom",
                    icon: "hammer.fill",
                    accentColor: .appRed,
                    tags: ["Custom", "\(tmpl.sessionTypes.count)-Day"],
                    repRanges: "Varies",
                    volumePerMuscle: "Varies",
                    whoItsFor: "Custom built.",
                    days_per_week_range: tmpl.sessionTypes.count...tmpl.sessionTypes.count
                )
            }
    }
}
