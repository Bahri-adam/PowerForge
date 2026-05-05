import SwiftUI
import SwiftData

@main
struct PowerbodybuilderApp: App {

    @State private var showSplash = true

    let modelContainer: ModelContainer

    init() {
        let schema = Schema([
            UserProfile.self,
            Exercise.self,
            ProgramTemplate.self,
            ProgramSessionTemplate.self,
            UserProgramInstance.self,
            ProgramSchedule.self,
            SessionOverride.self,
            ActiveWorkout.self,
            WorkoutLog.self,
            ProgressionState.self,
            UserProgram.self,
            LandmarkCalibration.self,
            DayTemplate.self,
            StrengthGoal.self
        ])

        do {
            modelContainer = try ModelContainer(for: schema)
        } catch {
            // Schema migration failed — delete old store and retry
            print("⚠️ ModelContainer failed: \(error). Deleting store and retrying...")
            let url = URL.applicationSupportDirectory.appending(path: "default.store")
            try? FileManager.default.removeItem(at: url)
            // Also remove WAL/SHM files
            try? FileManager.default.removeItem(at: url.appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: url.appendingPathExtension("shm"))
            do {
                modelContainer = try ModelContainer(for: schema)
            } catch {
                fatalError("Could not create ModelContainer even after reset: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .onAppear {
                        // Intentionally empty — seeding happens in ContentView
                        // which has guaranteed modelContext access via @Environment
                    }

                if showSplash {
                    SplashScreen()
                        .transition(.opacity)
                        .zIndex(1)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) {
                                withAnimation(.easeOut(duration: 0.5)) {
                                    showSplash = false
                                }
                            }
                        }
                }
            }
        }
        .modelContainer(modelContainer)
    }
}
