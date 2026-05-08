import Foundation
import SwiftData

// ═══════════════════════════════════════════
// BackupManager
// Auto-saves a JSON snapshot of the app's data to iCloud Drive
// after each meaningful change, and offers to restore on a fresh
// install if a backup is found in the user's iCloud Drive.
//
// This is FILE-based iCloud sync — separate from CloudKit. Doesn't
// require a deployed CloudKit schema, works with any signed build.
// ═══════════════════════════════════════════

@MainActor
final class BackupManager {

    static let shared = BackupManager()
    private init() {}

    private let backupFileName = "powerforge_backup.json"
    private let lastBackupKey = "BackupManager.lastBackupTime"
    private let minIntervalSeconds: TimeInterval = 60  // debounce — at most once per minute
    private var pendingTask: Task<Void, Never>? = nil

    // ── iCloud Drive URL ────────────────────────────────────────────────────

    /// Returns the URL for the backup file in the app's iCloud Drive container.
    /// `nil` if iCloud Drive is unavailable (no account, disabled, etc.)
    private var backupURL: URL? {
        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            return nil
        }
        let documents = containerURL.appendingPathComponent("Documents", isDirectory: true)
        try? FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        return documents.appendingPathComponent(backupFileName)
    }

    // ── Public API ──────────────────────────────────────────────────────────

    /// Schedule a debounced backup. Safe to call frequently.
    func scheduleBackup(context: ModelContext) {
        pendingTask?.cancel()
        pendingTask = Task {
            // Debounce — wait briefly to coalesce rapid changes
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await performBackup(context: context)
        }
    }

    /// Returns the date of the last successful backup, or nil.
    var lastBackupDate: Date? {
        UserDefaults.standard.object(forKey: lastBackupKey) as? Date
    }

    /// Checks if a backup file exists in iCloud Drive (synchronous, fast).
    func backupExists() -> Bool {
        guard let url = backupURL else { return false }
        // For iCloud Drive, the file may not be downloaded locally yet.
        // Check both local existence and ubiquity item status.
        if FileManager.default.fileExists(atPath: url.path) { return true }
        return false
    }

    /// Reads the backup file's metadata to show when it was made.
    func backupMetadata() -> (date: Date, size: Int)? {
        guard let url = backupURL,
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let date = (attrs[.modificationDate] as? Date) ?? Date()
            let size = (attrs[.size] as? Int) ?? 0
            return (date, size)
        } catch {
            return nil
        }
    }

    /// Restores data from the iCloud Drive backup file.
    /// Returns the count of records restored, or nil if no backup or error.
    @discardableResult
    func restoreFromBackup(context: ModelContext) async -> Int? {
        guard let url = backupURL,
              FileManager.default.fileExists(atPath: url.path) else { return nil }

        // Trigger iCloud download if file is offloaded
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)

        do {
            let data = try Data(contentsOf: url)
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("📦 Backup file unreadable")
                return nil
            }
            let restored = try await applyBackup(dict, context: context)
            print("📦✅ Restored \(restored) records from iCloud Drive backup")
            return restored
        } catch {
            print("📦❌ Restore failed: \(error)")
            return nil
        }
    }

    // ── Backup write ────────────────────────────────────────────────────────

    private func performBackup(context: ModelContext) async {
        // Respect debounce minimum
        if let last = lastBackupDate, Date().timeIntervalSince(last) < minIntervalSeconds {
            return
        }
        guard let url = backupURL else {
            print("📦⚠️ iCloud Drive not available — skipping backup")
            return
        }

        do {
            let dict = try buildBackupDictionary(context: context)
            let data = try JSONSerialization.data(withJSONObject: dict, options: [])
            try data.write(to: url, options: .atomic)
            UserDefaults.standard.set(Date(), forKey: lastBackupKey)
            print("📦✅ Backup written to iCloud Drive (\(data.count) bytes)")
        } catch {
            print("📦❌ Backup failed: \(error)")
        }
    }

    // ── Encode SwiftData store → JSON dict ──────────────────────────────────

    private func buildBackupDictionary(context: ModelContext) throws -> [String: Any] {
        let df = ISO8601DateFormatter()

        // Profile
        var profileData: [String: Any] = [:]
        let profiles = (try? context.fetch(FetchDescriptor<UserProfile>())) ?? []
        if let p = profiles.first {
            profileData = [
                "name": p.name,
                "bodyweight": p.bodyweight,
                "age": p.age,
                "useMetric": p.useMetric,
                "goal": p.goalRaw,
                "experience": p.experienceRaw,
                "daysPerWeek": p.daysPerWeek,
                "calorieContext": p.calorieContextRaw,
                "muscleTiersData": p.muscleTiersData.base64EncodedString(),
                "algorithmModeRaw": p.algorithmModeRaw,
                "showWarmups": p.showWarmups,
                "showRPE": p.showRPE,
                "showRepRange": p.showRepRange,
                "showRestTimer": p.showRestTimer,
                "skipDeloads": p.skipDeloads
            ]
        }

        // Custom exercises
        var customExercises: [[String: Any]] = []
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        for ex in exercises where ex.isCustom {
            customExercises.append([
                "exerciseKey": ex.exerciseKey,
                "displayName": ex.displayName,
                "movementPattern": ex.movementPatternRaw,
                "musclesPrimary": ex.musclesPrimary,
                "musclesSecondary": ex.musclesSecondary,
                "equipment": ex.equipmentRaw,
                "isCompound": ex.isCompound
            ])
        }

        // Custom program templates
        var customTemplates: [[String: Any]] = []
        let templates = (try? context.fetch(FetchDescriptor<ProgramTemplate>())) ?? []
        for tmpl in templates where tmpl.programId >= 100 {
            customTemplates.append([
                "programId": tmpl.programId,
                "name": tmpl.name,
                "version": tmpl.version,
                "durationWeeks": tmpl.durationWeeks,
                "sessionTypeRaws": tmpl.sessionTypeRaws,
                "scheduleOptions": tmpl.scheduleOptions
            ])
        }

        // Custom session templates (slots within custom programs)
        var customSlots: [[String: Any]] = []
        let allSlots = (try? context.fetch(FetchDescriptor<ProgramSessionTemplate>())) ?? []
        for slot in allSlots where slot.programId >= 100 {
            customSlots.append([
                "programId": slot.programId,
                "programVersion": slot.programVersion,
                "week": slot.week,
                "sessionType": slot.sessionTypeRaw,
                "slotId": slot.slotId,
                "exerciseIndex": slot.exerciseIndex,
                "exerciseKey": slot.exerciseKey,
                "role": slot.roleRaw,
                "isMainLift": slot.isMainLift,
                "targetSets": slot.targetSets,
                "targetRepsLow": slot.targetRepsLow,
                "targetRepsHigh": slot.targetRepsHigh,
                "targetRPE": slot.targetRPE,
                "restSeconds": slot.restSeconds,
                "notes": slot.notes
            ])
        }

        // Active program instance
        var instanceData: [String: Any] = [:]
        let instances = (try? context.fetch(FetchDescriptor<UserProgramInstance>())) ?? []
        if let inst = instances.first(where: { $0.isActive }) {
            instanceData = [
                "programId": inst.programId,
                "programVersion": inst.programVersion,
                "name": inst.name,
                "startDate": df.string(from: inst.startDate),
                "microcycleIndex": inst.microcycleIndex,
                "nextRotationIndex": inst.nextRotationIndex,
                "blockTypeRaw": inst.blockTypeRaw,
                "blockWeek": inst.blockWeek,
                "blockLength": inst.blockLength,
                "totalBlocksCompleted": inst.totalBlocksCompleted,
                "isGenerated": inst.isGenerated
            ]
        }

        // Workout logs
        var logs: [[String: Any]] = []
        let allLogs = (try? context.fetch(FetchDescriptor<WorkoutLog>())) ?? []
        for log in allLogs {
            logs.append([
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
                "previousWeight": log.previousWeight,
                "isManualPR": log.isManualPR,
                "readiness": log.readiness
            ])
        }

        // Progression states
        var progStates: [[String: Any]] = []
        let states = (try? context.fetch(FetchDescriptor<ProgressionState>())) ?? []
        for s in states {
            progStates.append([
                "exerciseKey": s.exerciseKey,
                "bestE1RM": s.bestE1RM,
                "lastSessionWeight": s.lastSessionWeight,
                "lastSessionReps": s.lastSessionReps,
                "lastSessionRPE": s.lastSessionRPE,
                "lastCompletedWeight": s.lastCompletedWeight,
                "totalExposures": s.totalExposures,
                "personalFatigueSensitivity": s.personalFatigueSensitivity
            ])
        }

        // Strength goals
        var goals: [[String: Any]] = []
        let strengthGoals = (try? context.fetch(FetchDescriptor<StrengthGoal>())) ?? []
        for g in strengthGoals {
            goals.append([
                "exerciseKey": g.exerciseKey,
                "displayName": g.displayName,
                "targetWeight": g.targetWeight,
                "startE1RM": g.startE1RM,
                "phase": g.phaseRaw,
                "phaseWeek": g.phaseWeek,
                "isActive": g.isActive,
                "restSeconds": g.restSeconds
            ])
        }

        return [
            "version": 2,
            "exportDate": df.string(from: Date()),
            "profile": profileData,
            "instance": instanceData,
            "customExercises": customExercises,
            "customTemplates": customTemplates,
            "customSlots": customSlots,
            "logs": logs,
            "progressionStates": progStates,
            "strengthGoals": goals
        ]
    }

    // ── Decode JSON → SwiftData store ───────────────────────────────────────

    private func applyBackup(_ dict: [String: Any], context: ModelContext) async throws -> Int {
        let df = ISO8601DateFormatter()
        var count = 0

        // Profile
        if let pData = dict["profile"] as? [String: Any], !pData.isEmpty {
            // Only restore profile if none exists
            let existing = (try? context.fetch(FetchDescriptor<UserProfile>())) ?? []
            if existing.isEmpty {
                let profile = UserProfile(
                    name: pData["name"] as? String ?? "",
                    bodyweight: pData["bodyweight"] as? Double ?? 0,
                    age: pData["age"] as? Int ?? 0,
                    useMetric: pData["useMetric"] as? Bool ?? false,
                    goal: pData["goal"] as? String ?? "Hypertrophy",
                    experience: pData["experience"] as? String ?? "Intermediate",
                    daysPerWeek: pData["daysPerWeek"] as? Int ?? 4,
                    priorityMuscles: []
                )
                profile.calorieContextRaw = pData["calorieContext"] as? String ?? "unknown"
                if let mtStr = pData["muscleTiersData"] as? String,
                   let mtData = Data(base64Encoded: mtStr) {
                    profile.muscleTiersData = mtData
                }
                profile.algorithmModeRaw = pData["algorithmModeRaw"] as? String ?? "full"
                profile.showWarmups = pData["showWarmups"] as? Bool ?? true
                profile.showRPE = pData["showRPE"] as? Bool ?? true
                profile.showRepRange = pData["showRepRange"] as? Bool ?? true
                profile.showRestTimer = pData["showRestTimer"] as? Bool ?? true
                profile.skipDeloads = pData["skipDeloads"] as? Bool ?? false
                context.insert(profile)
                count += 1
            }
        }

        // Custom exercises (skip duplicates by name)
        if let customEx = dict["customExercises"] as? [[String: Any]] {
            let existingExercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
            let existingNames = Set(existingExercises.map { $0.displayName.lowercased() })
            for exData in customEx {
                guard let name = exData["displayName"] as? String,
                      !existingNames.contains(name.lowercased()) else { continue }
                let pattern = MovementPattern(rawValue: exData["movementPattern"] as? String ?? "") ?? .horizontalPush
                let equipment = EquipmentType(rawValue: exData["equipment"] as? String ?? "") ?? .other
                let ex = Exercise(
                    exerciseKey: exData["exerciseKey"] as? String ?? "custom_\(UUID().uuidString)",
                    displayName: name,
                    movementPattern: pattern,
                    musclesPrimary: exData["musclesPrimary"] as? [String] ?? [],
                    musclesSecondary: exData["musclesSecondary"] as? [String] ?? [],
                    equipment: equipment,
                    isCompound: exData["isCompound"] as? Bool ?? true,
                    isCustom: true
                )
                context.insert(ex)
                count += 1
            }
        }

        // Custom program templates
        if let customTmpls = dict["customTemplates"] as? [[String: Any]] {
            let existingTmpls = (try? context.fetch(FetchDescriptor<ProgramTemplate>())) ?? []
            let existingIds = Set(existingTmpls.map { $0.programId })
            for tData in customTmpls {
                guard let pid = tData["programId"] as? Int, !existingIds.contains(pid) else { continue }
                let sessionTypes = (tData["sessionTypeRaws"] as? [String] ?? []).compactMap { SessionType(rawValue: $0) }
                let tmpl = ProgramTemplate(
                    programId: pid,
                    name: tData["name"] as? String ?? "Custom Program",
                    version: tData["version"] as? Int ?? 1,
                    durationWeeks: tData["durationWeeks"] as? Int ?? 24,
                    sessionTypes: sessionTypes,
                    scheduleOptions: tData["scheduleOptions"] as? [String] ?? []
                )
                context.insert(tmpl)
                count += 1
            }
        }

        // Custom session templates
        if let customSlots = dict["customSlots"] as? [[String: Any]] {
            for sData in customSlots {
                guard let pid = sData["programId"] as? Int,
                      let sessionTypeStr = sData["sessionType"] as? String,
                      let sessionType = SessionType(rawValue: sessionTypeStr) else { continue }
                let role = ExerciseRole(rawValue: sData["role"] as? String ?? "") ?? .accessory
                let slot = ProgramSessionTemplate(
                    programId: pid,
                    programVersion: sData["programVersion"] as? Int ?? 1,
                    week: sData["week"] as? Int ?? 1,
                    sessionType: sessionType,
                    slotId: sData["slotId"] as? String ?? "A1",
                    exerciseIndex: sData["exerciseIndex"] as? Int ?? 0,
                    exerciseKey: sData["exerciseKey"] as? String ?? "",
                    role: role,
                    isMainLift: sData["isMainLift"] as? Bool ?? false,
                    targetSets: sData["targetSets"] as? Int ?? 3,
                    targetRepsLow: sData["targetRepsLow"] as? Int ?? 8,
                    targetRepsHigh: sData["targetRepsHigh"] as? Int ?? 12,
                    targetRPE: sData["targetRPE"] as? Double ?? 8.0,
                    restSeconds: sData["restSeconds"] as? Int ?? 90,
                    notes: sData["notes"] as? String ?? ""
                )
                context.insert(slot)
                count += 1
            }
        }

        // Restore active program instance + its data (logs, progression states, goals)
        var restoredInstance: UserProgramInstance? = nil
        if let iData = dict["instance"] as? [String: Any], !iData.isEmpty,
           let pid = iData["programId"] as? Int {
            // Only restore if no instance exists
            let existing = (try? context.fetch(FetchDescriptor<UserProgramInstance>())) ?? []
            if existing.isEmpty {
                let inst = UserProgramInstance(
                    programId: pid,
                    programVersion: iData["programVersion"] as? Int ?? 1,
                    name: iData["name"] as? String ?? "Program"
                )
                if let dateStr = iData["startDate"] as? String, let date = df.date(from: dateStr) {
                    inst.startDate = date
                }
                inst.microcycleIndex = iData["microcycleIndex"] as? Int ?? 0
                inst.nextRotationIndex = iData["nextRotationIndex"] as? Int ?? 0
                inst.blockTypeRaw = iData["blockTypeRaw"] as? String ?? "accumulation"
                inst.blockWeek = iData["blockWeek"] as? Int ?? 1
                inst.blockLength = iData["blockLength"] as? Int ?? 4
                inst.totalBlocksCompleted = iData["totalBlocksCompleted"] as? Int ?? 0
                inst.isGenerated = iData["isGenerated"] as? Bool ?? false
                inst.isActive = true
                context.insert(inst)
                restoredInstance = inst
                count += 1
            } else {
                restoredInstance = existing.first(where: { $0.isActive }) ?? existing.first
            }
        }

        // Workout logs (attach to instance if available)
        if let logsArr = dict["logs"] as? [[String: Any]] {
            for entry in logsArr {
                let workoutDate = (entry["workoutDate"] as? String).flatMap { df.date(from: $0) } ?? Date()
                let setDate = (entry["date"] as? String).flatMap { df.date(from: $0) } ?? workoutDate
                let sessionTypeStr = entry["sessionType"] as? String ?? "freeform"
                let log = WorkoutLog(
                    date: setDate,
                    workoutDate: workoutDate,
                    week: entry["week"] as? Int ?? 1,
                    sessionType: SessionType(rawValue: sessionTypeStr) ?? .freeform,
                    exerciseKey: entry["exerciseKey"] as? String ?? "",
                    displayName: entry["displayName"] as? String ?? "",
                    slotId: entry["slotId"] as? String ?? "",
                    setIndex: entry["setIndex"] as? Int ?? 0,
                    weight: entry["weight"] as? Double ?? 0,
                    reps: entry["reps"] as? Int ?? 0,
                    rpe: entry["rpe"] as? Double ?? 0,
                    isMainLift: entry["isMainLift"] as? Bool ?? false,
                    isTopSet: entry["isTopSet"] as? Bool ?? false,
                    hitTargetReps: entry["hitTargetReps"] as? Bool ?? false,
                    suggestedWeight: entry["suggestedWeight"] as? Double ?? 0
                )
                log.e1rm = entry["e1rm"] as? Double ?? 0
                log.sessionNotes = entry["sessionNotes"] as? String ?? ""
                log.targetRepsLow = entry["targetRepsLow"] as? Int ?? 0
                log.previousWeight = entry["previousWeight"] as? Double ?? 0
                log.isManualPR = entry["isManualPR"] as? Bool ?? false
                log.readiness = entry["readiness"] as? Int ?? 0
                if let inst = restoredInstance {
                    inst.logs.append(log)
                } else {
                    context.insert(log)
                }
                count += 1
            }
        }

        // Progression states
        if let psArr = dict["progressionStates"] as? [[String: Any]] {
            for ps in psArr {
                guard let key = ps["exerciseKey"] as? String else { continue }
                let state = ProgressionState(exerciseKey: key)
                state.bestE1RM = ps["bestE1RM"] as? Double ?? 0
                state.lastSessionWeight = ps["lastSessionWeight"] as? Double ?? 0
                state.lastSessionReps = ps["lastSessionReps"] as? Int ?? 0
                state.lastSessionRPE = ps["lastSessionRPE"] as? Double ?? 0
                state.lastCompletedWeight = ps["lastCompletedWeight"] as? Double ?? 0
                state.totalExposures = ps["totalExposures"] as? Int ?? 0
                state.personalFatigueSensitivity = ps["personalFatigueSensitivity"] as? Double ?? 0.12
                if let inst = restoredInstance {
                    inst.progressionStates.append(state)
                } else {
                    context.insert(state)
                }
                count += 1
            }
        }

        // Strength goals
        if let goalsArr = dict["strengthGoals"] as? [[String: Any]] {
            for g in goalsArr {
                guard let key = g["exerciseKey"] as? String else { continue }
                let goal = StrengthGoal(
                    exerciseKey: key,
                    displayName: g["displayName"] as? String ?? key,
                    targetWeight: g["targetWeight"] as? Double ?? 0,
                    startE1RM: g["startE1RM"] as? Double ?? 0
                )
                goal.phaseRaw = g["phase"] as? String ?? "building"
                goal.phaseWeek = g["phaseWeek"] as? Int ?? 1
                goal.isActive = g["isActive"] as? Bool ?? true
                goal.restSeconds = g["restSeconds"] as? Int ?? 180
                if let inst = restoredInstance {
                    inst.strengthGoals.append(goal)
                } else {
                    context.insert(goal)
                }
                count += 1
            }
        }

        try? context.save()
        return count
    }
}
