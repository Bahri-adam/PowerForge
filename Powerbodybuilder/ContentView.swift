import SwiftUI
import SwiftData

struct ContentView: View {

    @Environment(\.modelContext) private var modelContext

    @State private var selectedTab: Int = 0
    @Query private var profiles: [UserProfile]
    @Query private var programs: [UserProgram]
    @Query private var programTemplates: [ProgramTemplate]

    var body: some View {
        Group {
            // TODO: This gates on legacy UserProgram model. Migrate to UserProgramInstance check
            // without breaking the onboarding → program selection → main flow.
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
            loadCustomPrograms()
        }
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
