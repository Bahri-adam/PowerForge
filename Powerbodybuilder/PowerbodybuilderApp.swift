import SwiftUI
import SwiftData
import CloudKit

@main
struct PowerbodybuilderApp: App {

    @State private var showSplash = true

    let modelContainer: ModelContainer
    let usingCloudKit: Bool

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

        // Try EXPLICIT private CloudKit container first — more reliable than .automatic
        let cloudConfig = ModelConfiguration(
            "PowerForge",
            schema: schema,
            cloudKitDatabase: .private("iCloud.com.bahri.powerforge")
        )

        var container: ModelContainer? = nil
        var didUseCloud = false

        do {
            container = try ModelContainer(for: schema, configurations: [cloudConfig])
            didUseCloud = true
            print("☁️✅ CLOUDKIT INITIALIZED — container: iCloud.com.bahri.powerforge")
        } catch {
            print("☁️❌ CLOUDKIT INIT FAILED")
            print("☁️❌ Error: \(error)")
            print("☁️❌ Localized: \(error.localizedDescription)")
            print("☁️⚠️ Falling back to local-only storage")
        }

        if container == nil {
            let localConfig = ModelConfiguration("PowerForge", schema: schema, cloudKitDatabase: .none)
            do {
                container = try ModelContainer(for: schema, configurations: [localConfig])
                print("📦 Local-only container created (no iCloud sync)")
            } catch {
                print("💥 Local container also failed: \(error). Wiping store...")
                let url = URL.applicationSupportDirectory.appending(path: "PowerForge.store")
                try? FileManager.default.removeItem(at: url)
                try? FileManager.default.removeItem(at: url.appendingPathExtension("wal"))
                try? FileManager.default.removeItem(at: url.appendingPathExtension("shm"))
                container = try? ModelContainer(for: schema, configurations: [localConfig])
            }
        }

        guard let finalContainer = container else {
            fatalError("Could not create ModelContainer")
        }

        self.modelContainer = finalContainer
        self.usingCloudKit = didUseCloud

        // Check CloudKit account status asynchronously
        if didUseCloud {
            Task.detached {
                let ckContainer = CKContainer(identifier: "iCloud.com.bahri.powerforge")
                do {
                    let status = try await ckContainer.accountStatus()
                    let statusName: String
                    switch status {
                    case .available: statusName = "✅ AVAILABLE — sync should work"
                    case .noAccount: statusName = "❌ NO ACCOUNT — sign into iCloud in device Settings"
                    case .restricted: statusName = "❌ RESTRICTED — parental controls or device management"
                    case .couldNotDetermine: statusName = "❌ COULD NOT DETERMINE — network/auth issue"
                    case .temporarilyUnavailable: statusName = "❌ TEMPORARILY UNAVAILABLE — Apple's servers"
                    @unknown default: statusName = "❌ UNKNOWN STATE"
                    }
                    print("☁️🔍 CloudKit account status: \(statusName)")
                } catch {
                    print("☁️🔍 Could not check account status: \(error)")
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()

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
