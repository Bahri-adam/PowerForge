import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct HomeView: View {
    var switchToTrain: (() -> Void)? = nil
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @Query(filter: #Predicate<UserProgramInstance> { $0.isActive == true })
    private var activeInstances: [UserProgramInstance]
    @Query private var allProgramInstances: [UserProgramInstance]
    @Query(sort: \WorkoutLog.date, order: .reverse) private var recentLogs: [WorkoutLog]
    @Query private var allExercises: [Exercise]
    @Query private var programTemplates: [ProgramTemplate]
    @Query private var allSessionTemplates: [ProgramSessionTemplate]

    var profile: UserProfile? { profiles.first }
    var instance: UserProgramInstance? { activeInstances.first }

    @State private var viewingWeek: Int = 0
    @State private var showWeekHub = false
    @State private var showBodyweightEntry = false
    @State private var showBlockInfo = false
    @State private var showWeekOverview = false
    @State private var showSetWeekConfirm = false
    @State private var weekToSet: Int = 0
    @State private var bodyweightInput = ""
    @State private var scheduleByDay: Bool = UserDefaults.standard.object(forKey: "scheduleByDay") as? Bool ?? true
    @State private var editSessionItem: SessionEditorItem? = nil
    @State private var volumeAdjustMuscle: String? = nil

    private var displayWeek: Int { viewingWeek > 0 ? viewingWeek : (instance?.currentWeek ?? 1) }

    private var weekLogs: [WorkoutLog] {
        guard let inst = instance else { return [] }
        return inst.logs.filter { $0.week == displayWeek && !$0.isManualPR }
    }

    private var weekSessions: Int { Set(weekLogs.map { Calendar.current.startOfDay(for: $0.date) }).count }
    private var weekSets: Int { weekLogs.count }
    private var weekVolume: Int { Int(weekLogs.reduce(0.0) { $0 + ($1.weight * Double($1.reps)) }) }

    private var streak: Int {
        guard let inst = instance else { return 0 }
        let cal = Calendar.current
        let days = Set(inst.logs.map { cal.startOfDay(for: $0.date) }).sorted(by: >)
        guard !days.isEmpty else { return 0 }
        var count = 0
        var check = cal.startOfDay(for: Date())
        if !days.contains(check) { check = cal.date(byAdding: .day, value: -1, to: check)! }
        for day in days {
            if day == check { count += 1; check = cal.date(byAdding: .day, value: -1, to: check)! }
            else { break }
        }
        return count
    }

    private var recentPRs: [WorkoutLog] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: Date())!
        return recentLogs.filter { $0.hitTargetReps && $0.date >= cutoff && $0.isTopSet }.prefix(4).map { $0 }
    }

    private func splitRotation(for programId: Int) -> [SessionType] {
        if programId == 0 { return [.freeform] }
        if programId == 2 { return [.pushA, .pullA, .legsA, .pushB, .pullB, .legsB] }
        if programId == 3 { return [.heavyLower, .heavyUpper, .hypertrophyLower, .hypertrophyUpper] }
        if programId == 4 { return [.fullBodyA, .fullBodyB, .fullBodyA] }
        if programId == 5 { return [.upperPower, .lowerPower, .hypertrophyUpper, .hypertrophyLower] }
        if programId == 6 { return [.fullBodyA, .fullBodyB, .fullBody] }
        if programId == 7 { return [.legQuadFocus, .chestBack, .armsDelts, .legsPosterior, .chestArms, .legsVolume] }

        // Generated programs (ID > 10): derive rotation from profile settings
        if let inst = instance, inst.isGenerated, programId > 10, let p = profile {
            let split = ProgramGenerator.resolveSplitStructure(
                daysPerWeek: p.daysPerWeek, goal: p.goal, priorityMuscles: p.priorityMuscles)
            return split.filter { $0.sessionType != .rest }.map { $0.sessionType }
        }

        if programId >= 100 {
            if let tmpl = programTemplates.first(where: { $0.programId == programId }) {
                return tmpl.sessionTypes
            }
        }
        return [.heavyUpper, .heavyLower, .hypertrophyUpper, .hypertrophyLower]
    }

    private var dayAssignments: [Int: SessionType] {
        guard let inst = instance else { return [:] }
        // Start with default rotation
        let rotation = splitRotation(for: inst.programId)
        var map: [Int: SessionType] = [:]
        let workDays: [Int]
        switch rotation.count {
        case 2: workDays = [1, 4]
        case 3: workDays = [1, 3, 5]
        case 4: workDays = [1, 2, 4, 5]
        case 5: workDays = [1, 2, 3, 5, 6]
        case 6: workDays = [1, 2, 3, 4, 6, 7]
        case 7: workDays = [1, 2, 3, 4, 5, 6, 7]
        default: workDays = Array(1...min(rotation.count, 7))
        }
        for (i, day) in workDays.prefix(rotation.count).enumerated() { map[day] = rotation[i] }
        // Apply permanent overrides first
        for s in inst.schedules where s.isPermanent {
            let dow = s.dayOfWeek == 0 ? 7 : s.dayOfWeek
            map[dow] = s.isRestDay ? .rest : s.sessionType
        }
        // Then apply week-specific overrides (higher priority)
        for s in inst.schedules where !s.isPermanent && s.week == displayWeek {
            let dow = s.dayOfWeek == 0 ? 7 : s.dayOfWeek
            map[dow] = s.isRestDay ? .rest : s.sessionType
        }
        return map
    }

    private var loggedDaysThisWeek: Set<Int> {
        var result = Set<Int>()
        for log in weekLogs {
            var dow = Calendar.current.component(.weekday, from: log.date) - 1
            if dow == 0 { dow = 7 }
            result.insert(dow)
        }
        return result
    }

    // ── Block info helpers ──
    private var blockTypeLabel: String {
        guard let inst = instance else { return "Training" }
        return blockDisplayName(inst.blockType, goal: profile?.goal ?? .hypertrophy)
    }

    /// Goal-aware block naming. Strength/powerbuilding use periodization terms.
    /// Hypertrophy/recomp just use "Training Block" since accumulation/intensification
    /// are strength-specific concepts with no meaningful hypertrophy application.
    private func blockDisplayName(_ bt: BlockType, goal: GoalType) -> String {
        switch goal {
        case .hypertrophy, .recomp:
            switch bt {
            case .accumulation:    return "Training Block"
            case .reaccumulation:  return "Growth Phase"
            case .deload:          return "Recovery"
            case .intensification: return "Training Block"  // shouldn't appear for hyp but fallback
            case .peak:            return "Training Block"
            }
        case .strength:
            switch bt {
            case .accumulation:    return "Accumulation"
            case .intensification: return "Intensification"
            case .peak:            return "Peaking"
            case .deload:          return "Deload"
            case .reaccumulation:  return "Accumulation"
            }
        case .powerbuilding:
            switch bt {
            case .accumulation:    return "Accumulation"
            case .intensification: return "Intensification"
            case .reaccumulation:  return "Volume Phase"
            case .peak:            return "Peaking"
            case .deload:          return "Deload"
            }
        }
    }

    /// For seeded programs, derive block week from display week and program structure
    /// rather than relying on stored blockWeek which may be stale after program switch
    private var effectiveBlockWeek: Int {
        guard let inst = instance else { return 1 }
        if inst.isGenerated { return inst.blockWeek }
        // Seeded programs: compute from display week
        let w = displayWeek
        if inst.programId == 7 {
            // Bahri: 3-week blocks with deload every 3rd week
            return ((w - 1) % 3) + 1
        }
        if inst.programId == 2 {
            // PPL: 8-week blocks
            if w <= 8 { return w }
            return w - 8
        }
        // Powerbuilding (ID 1) and others: 8-week blocks
        if w <= 8 { return w }
        if w <= 16 { return w - 8 }
        return w - 16
    }

    private var effectiveBlockLength: Int {
        guard let inst = instance else { return 5 }
        if inst.isGenerated { return inst.blockLength }
        if inst.programId == 7 { return 3 }
        return 8
    }

    private var blockProgressLabel: String {
        let remaining = effectiveBlockLength - effectiveBlockWeek
        if remaining <= 0 { return "Final week" }
        return "\(remaining) week\(remaining == 1 ? "" : "s") left"
    }

    private var todaySessionType: SessionType? {
        var dow = Calendar.current.component(.weekday, from: Date()) - 1
        if dow == 0 { dow = 7 }
        return dayAssignments[dow]
    }

    private var isTodayDone: Bool {
        guard let st = todaySessionType, st != .rest else { return false }
        return completedSessionTypes.contains(st.rawValue)
    }

    private var todayWorkoutCard: some View {
        Group {
            if let st = todaySessionType, st != .rest {
                VStack(spacing: 0) {
                    if isTodayDone {
                        // Completed state
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 28)).foregroundColor(.appGreen)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("TODAY'S SESSION COMPLETE").font(.system(size: 10, weight: .black)).foregroundColor(.appGreen).kerning(1.5)
                                Text(st.shortLabel).font(.system(size: 16, weight: .black)).foregroundColor(.appTextPrimary)
                                let todayLogs = weekLogs.filter { $0.sessionTypeRaw == st.rawValue }
                                Text("\(todayLogs.count) sets logged").font(.system(size: 12)).foregroundColor(.appTextSecondary)
                            }
                            Spacer()
                        }
                        .padding(16)
                        .background(Color.appGreen.opacity(0.06))
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appGreen.opacity(0.2), lineWidth: 1))
                    } else {
                        // Ready to train
                        HStack(spacing: 12) {
                            VStack(spacing: 4) {
                                Image(systemName: "figure.strengthtraining.traditional").font(.system(size: 22)).foregroundColor(.appRed)
                            }
                            .frame(width: 44, height: 44)
                            .background(Color.appRed.opacity(0.1)).cornerRadius(10)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("TODAY").font(.system(size: 10, weight: .black)).foregroundColor(.appRed).kerning(1.5)
                                Text(st.shortLabel).font(.system(size: 18, weight: .black)).foregroundColor(.appTextPrimary)
                                Text(st.muscleSubtitle).font(.system(size: 12)).foregroundColor(.appTextSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).foregroundColor(.appRed)
                        }
                        .padding(16)
                        .background(Color.appRed.opacity(0.04))
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appRed.opacity(0.15), lineWidth: 1))
                        .onTapGesture { switchToTrain?() }
                    }
                }
            } else {
                // Rest day
                HStack(spacing: 12) {
                    Image(systemName: "moon.zzz.fill").font(.system(size: 22)).foregroundColor(.appBlue.opacity(0.6))
                        .frame(width: 44, height: 44).background(Color.appBlue.opacity(0.06)).cornerRadius(10)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("REST DAY").font(.system(size: 10, weight: .black)).foregroundColor(.appBlue).kerning(1.5)
                        let nextSession = nextTrainingDay()
                        Text(nextSession ?? "Recovery & sleep priority").font(.system(size: 13, weight: .semibold)).foregroundColor(.appTextSecondary)
                    }
                    Spacer()
                }
                .padding(16).background(Color.appSurface).cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
            }
        }
    }

    private func nextTrainingDay() -> String? {
        var dow = Calendar.current.component(.weekday, from: Date()) - 1
        if dow == 0 { dow = 7 }
        for offset in 1...7 {
            let check = ((dow - 1 + offset) % 7) + 1
            if let st = dayAssignments[check], st != .rest {
                let dayNames = ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"]
                return "Next: \(st.shortLabel) on \(dayNames[check - 1])"
            }
        }
        return nil
    }

    private func setCurrentWeek(_ week: Int) {
        guard let inst = instance else { return }
        inst.microcycleIndex = week - 1  // 0-based
        // Update blockWeek to match — calculate position within block
        let blockLen = inst.blockLength > 0 ? inst.blockLength : 5
        let weekInBlock = ((week - 1) % (blockLen + 1)) + 1  // +1 for deload week
        inst.blockWeek = min(weekInBlock, blockLen)
        viewingWeek = 0  // reset to current
        try? modelContext.save()
    }

    private func templatesFor(session: SessionType) -> [ProgramSessionTemplate] {
        guard let inst = instance else { return [] }
        let direct = allSessionTemplates
            .filter { $0.programId == inst.programId && $0.week == displayWeek && $0.sessionType == session }
            .sorted { $0.exerciseIndex < $1.exerciseIndex }

        // If this is a training week but no templates exist for this session,
        // fall back to the nearest training week
        let bl = inst.blockLength > 0 ? inst.blockLength : 5
        let posInBlock = ((displayWeek - 1) % (bl + 1)) + 1
        let isTrainingWeek = posInBlock <= bl

        if isTrainingWeek && direct.isEmpty {
            let total = programTemplates.first(where: { $0.programId == inst.programId })?.durationWeeks ?? 24
            for offset in [1, -1, 2, -2, 3, -3] {
                let fw = displayWeek + offset
                guard fw >= 1 && fw <= total else { continue }
                let fwPos = ((fw - 1) % (bl + 1)) + 1
                guard fwPos <= bl else { continue }
                let fallback = allSessionTemplates
                    .filter { $0.programId == inst.programId && $0.week == fw && $0.sessionType == session }
                    .sorted { $0.exerciseIndex < $1.exerciseIndex }
                if !fallback.isEmpty { return fallback }
            }
            // Last resort: borrow templates from any other program that has this session type
            let foreignAtWeek = allSessionTemplates.filter { $0.sessionType == session && $0.week == displayWeek }
            if let foreignPid = foreignAtWeek.first?.programId {
                return foreignAtWeek.filter { $0.programId == foreignPid }
                    .sorted { $0.exerciseIndex < $1.exerciseIndex }
            }
            let foreignWeek1 = allSessionTemplates.filter { $0.sessionType == session && $0.week == 1 }
            if let foreignPid = foreignWeek1.first?.programId {
                return foreignWeek1.filter { $0.programId == foreignPid }
                    .sorted { $0.exerciseIndex < $1.exerciseIndex }
            }
        }

        return direct
    }

    private var completedSessionTypes: Set<String> {
        Set(weekLogs.map { $0.sessionTypeRaw })
    }

    var body: some View {
        ZStack {
            Color.appBG.ignoresSafeArea()
            Circle().fill(Color.appRed.opacity(0.04)).frame(width: 350).blur(radius: 80).offset(x: 130, y: -100)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    HomeHeroHeader(profile: profile, instance: instance, displayWeek: displayWeek, onTapProgram: { showWeekHub = true })
                    // Stats strip
                    HStack(spacing: 0) {
                        statCell(value: "\(weekSessions)", label: "SESSIONS")
                        statDivider()
                        statCell(value: "\(weekSets)", label: "SETS")
                        statDivider()
                        statCell(value: weekVolume > 1000 ? "\(weekVolume/1000)K" : "\(weekVolume)", label: "VOLUME")
                        statDivider()
                        Button(action: { showBodyweightEntry = true }) {
                            statCell(value: profile != nil ? String(format: "%.0f", profile!.bodyweight) : "--",
                                     label: (profile?.useMetric == true ? "KG" : "LBS") + " ✎")
                        }.buttonStyle(.plain)
                    }
                    .background(Color.appSurface)
                    .overlay(Rectangle().frame(height: 1).foregroundColor(.appBorder), alignment: .bottom)

                    VStack(spacing: 16) {
                        // Week strip (hidden for Freestyle)
                        if instance?.programId != 0 {
                            WeekStrip(displayWeek: displayWeek, currentWeek: instance?.currentWeek ?? 1,
                                      programId: instance?.programId ?? 1,
                                      totalWeeks: programTemplates.first(where: { $0.programId == instance?.programId ?? 1 })?.durationWeeks ?? 24,
                                      instance: instance, onSelectWeek: { viewingWeek = $0 },
                                      onTapHeader: { showWeekOverview = true })

                            // Set as current week button
                            if displayWeek != (instance?.currentWeek ?? 1) {
                                Button {
                                    weekToSet = displayWeek
                                    showSetWeekConfirm = true
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.right.circle.fill").font(.system(size: 12))
                                        Text("Jump to Week \(displayWeek)")
                                            .font(.system(size: 12, weight: .bold))
                                    }
                                    .foregroundColor(.appBlue)
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                                    .background(Color.appBlue.opacity(0.06)).cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBlue.opacity(0.15), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        // ── TODAY'S WORKOUT CARD ──
                        if instance?.programId != 0 {
                            todayWorkoutCard
                        }

                        // ── BLOCK INFO (tappable) ──
                        if instance?.programId != 0 {
                            Button(action: { showBlockInfo = true }) {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(blockTypeLabel.uppercased())
                                            .font(.system(size: 10, weight: .black)).foregroundColor(.appRed).kerning(1.5)
                                        Text("Week \(effectiveBlockWeek) of \(effectiveBlockLength)")
                                            .font(.system(size: 12, weight: .bold)).foregroundColor(.appTextSecondary)
                                    }
                                    Spacer()
                                    Text(blockProgressLabel)
                                        .font(.system(size: 11, weight: .bold)).foregroundColor(.appTextDim)
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(Color.appSurface2).cornerRadius(6)
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 14)).foregroundColor(.appBlue)
                                }
                                .padding(12)
                            }
                            .buttonStyle(.plain)
                            .background(Color.appSurface).cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))
                        }

                        // Schedule section
                        VStack(spacing: 0) {
                            HStack(spacing: 8) {
                                Text(instance?.programId == 0 ? "THIS WEEK" : "WEEK \(displayWeek) SCHEDULE")
                                    .font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(2)
                                Spacer()
                                if instance?.programId != 0 {
                                // Day / Session toggle
                                HStack(spacing: 0) {
                                    Button(action: { scheduleByDay = true; UserDefaults.standard.set(true, forKey: "scheduleByDay") }) {
                                        Text("DAYS")
                                            .font(.system(size: 9, weight: .black)).kerning(0.5)
                                            .foregroundColor(scheduleByDay ? .white : .appTextDim)
                                            .padding(.horizontal, 10).padding(.vertical, 5)
                                            .background(scheduleByDay ? Color.appRed : Color.clear)
                                            .cornerRadius(5)
                                    }.buttonStyle(.plain)
                                    Button(action: { scheduleByDay = false; UserDefaults.standard.set(false, forKey: "scheduleByDay") }) {
                                        Text("SESSIONS")
                                            .font(.system(size: 9, weight: .black)).kerning(0.5)
                                            .foregroundColor(!scheduleByDay ? .white : .appTextDim)
                                            .padding(.horizontal, 10).padding(.vertical, 5)
                                            .background(!scheduleByDay ? Color.appRed : Color.clear)
                                            .cornerRadius(5)
                                    }.buttonStyle(.plain)
                                }
                                .background(Color.appSurface2).cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.appBorder, lineWidth: 1))
                                }
                            }
                            .padding(.horizontal, 4).padding(.bottom, 8)

                            // ── CONFIGURE WEEK (full width, visible) ──
                            if instance?.programId != 0 {
                                Button(action: { showWeekHub = true }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "slider.horizontal.3").font(.system(size: 13, weight: .bold)).foregroundColor(.appBlue)
                                        Text("Configure Week").font(.system(size: 12, weight: .bold)).foregroundColor(.appBlue)
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundColor(.appTextDim)
                                    }
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .background(Color.appBlue.opacity(0.06)).cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBlue.opacity(0.15), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 4).padding(.bottom, 8)
                            }

                            if instance?.programId == 0 {
                                // Freestyle: show logged days this week
                                ForEach(1...7, id: \.self) { dow in
                                    let isDone = loggedDaysThisWeek.contains(dow)
                                    HomeDayCard(dayOfWeek: dow, sessionType: isDone ? .freeform : nil,
                                                isDone: isDone, weekLogs: weekLogs)
                                    if dow < 7 { Divider().background(Color.appBorder).padding(.leading, 16) }
                                }
                            } else if scheduleByDay {
                                // Day-of-week view with drag-and-drop + tap to edit
                                let days = Array(1...7)
                                ForEach(days, id: \.self) { dow in
                                    let st = dayAssignments[dow]
                                    let isDayDone: Bool = {
                                        guard let s = st, s != .rest else { return false }
                                        return completedSessionTypes.contains(s.rawValue)
                                    }()
                                    HomeDayCard(dayOfWeek: dow, sessionType: st,
                                                isDone: isDayDone, weekLogs: weekLogs)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            if let session = st, session != .rest, instance != nil {
                                                let t = templatesFor(session: session)
                                                if !t.isEmpty {
                                                    editSessionItem = SessionEditorItem(sessionType: session, templates: t)
                                                }
                                            }
                                        }
                                        .onDrag { NSItemProvider(object: String(dow) as NSString) }
                                        .onDrop(of: [UTType.text], delegate: DayDropDelegate(
                                            targetDay: dow,
                                            instance: instance,
                                            dayAssignments: dayAssignments,
                                            splitRotation: splitRotation(for: instance?.programId ?? 1),
                                            week: displayWeek,
                                            modelContext: modelContext
                                        ))
                                    if dow < 7 { Divider().background(Color.appBorder).padding(.leading, 16) }
                                }
                            } else {
                                // Rotation/session view with overrides applied
                                let sessions: [SessionType] = [1,2,3,4,5,6,7].compactMap { dow in
                                    guard let st = dayAssignments[dow], st != .rest else { return nil }
                                    return st
                                }
                                ForEach(Array(sessions.enumerated()), id: \.offset) { idx, st in
                                    HomeSessionCard(
                                        sessionNumber: idx + 1,
                                        sessionType: st,
                                        isDone: completedSessionTypes.contains(st.rawValue),
                                        weekLogs: weekLogs.filter { $0.sessionTypeRaw == st.rawValue }
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if let _ = instance {
                                            let t = templatesFor(session: st)
                                            if !t.isEmpty {
                                                editSessionItem = SessionEditorItem(sessionType: st, templates: t)
                                            }
                                        }
                                    }
                                    if idx < sessions.count - 1 { Divider().background(Color.appBorder).padding(.leading, 16) }
                                }
                            }
                        }
                        .background(Color.appSurface).cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))

                        MuscleCoverageCard(
                            weekLogs: weekLogs,
                            exercises: allExercises,
                            priorityMuscles: profile?.priorityMuscles ?? [],
                            muscleTiers: profile?.muscleTiers ?? [:],
                            experience: profile?.experience ?? .intermediate,
                            instance: instance,
                            allTemplates: allSessionTemplates,
                            displayWeek: displayWeek,
                            targetOverrides: profile?.muscleTargetOverrides ?? [:],
                            onAdjustVolume: { muscle in volumeAdjustMuscle = muscle }
                        )

                        // ── MRV fatigue warnings ──
                        let priorityMuscleNames = (profile?.muscleTiers ?? [:])
                            .filter { $0.value == .priority }.map { $0.key }
                        let warningMuscles = priorityMuscleNames
                            .filter {
                                let s = instance?.mrvSignalScores[$0] ?? 0
                                return s >= 5 && s < 7
                            }

                        ForEach(warningMuscles, id: \.self) { muscle in
                            HStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.appGold)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(muscle) fatigue building")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.appTextPrimary)
                                    Text("Consider 2–3 fewer sets this week")
                                        .font(.system(size: 11))
                                        .foregroundColor(.appTextSecondary)
                                }
                                Spacer()
                            }
                            .padding(12)
                            .appCard()
                        }

                        if let inst = instance,
                           MRVSignalEngine.requiresFullDeload(
                               scores: inst.mrvSignalScores,
                               priorityMuscles: priorityMuscleNames) {
                            VStack(spacing: 8) {
                                Text("High fatigue detected")
                                    .font(.system(size: 15, weight: .black))
                                    .foregroundColor(.appTextPrimary)
                                Text("A deload this week will maximize what you've built.")
                                    .font(.system(size: 12))
                                    .foregroundColor(.appTextSecondary)
                                    .multilineTextAlignment(.center)
                                Button("Schedule Deload") {
                                    inst.blockType = .deload
                                }
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.appRed)
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                .background(Color.appRed.opacity(0.1)).cornerRadius(8)
                            }
                            .padding(16)
                            .background(Color.appRed.opacity(0.08))
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.appRed.opacity(0.3), lineWidth: 1))
                        }

                        ACWRCard(logs: instance?.logs ?? [])

                        if !recentPRs.isEmpty {
                            VStack(spacing: 10) {
                                SectionHeader(title: "RECENT TARGET HITS")
                                ForEach(recentPRs, id: \.id) { log in RecentPRRow(log: log, useMetric: profile?.useMetric ?? false) }
                            }
                        }
                        RecentSessionsList(instance: instance, allInstances: allProgramInstances)
                    }
                    .padding(16).padding(.bottom, 40)
                }
            }
        }
        .onAppear { if viewingWeek == 0 { viewingWeek = instance?.currentWeek ?? 1 } }
        .onChange(of: instance?.currentWeek) { _, new in if let w = new { viewingWeek = w } }
        .onChange(of: instance?.programId) { _, _ in viewingWeek = instance?.currentWeek ?? 1 }
        .sheet(isPresented: $showWeekHub) {
            if let inst = instance { WeekHubSheet(instance: inst, viewingWeek: $viewingWeek, onDismiss: { showWeekHub = false }) }
        }
        .sheet(item: $volumeAdjustMuscle) { muscle in
            if let inst = instance {
                VolumeAdjusterSheet(muscle: muscle, instance: inst, profile: profile, week: displayWeek)
            }
        }
        .sheet(isPresented: $showBlockInfo) {
            BlockInfoSheet(instance: instance, profile: profile)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showWeekOverview) {
            WeekOverviewSheet(instance: instance, profile: profile, displayWeek: displayWeek,
                              onSelectWeek: { w in viewingWeek = w; showWeekOverview = false },
                              onSetWeek: { w in weekToSet = w; showSetWeekConfirm = true; showWeekOverview = false })
                .presentationDetents([.large])
        }
        .confirmationDialog("Set Current Week", isPresented: $showSetWeekConfirm) {
            Button("Set to Week \(weekToSet)") {
                setCurrentWeek(weekToSet)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will update your program to Week \(weekToSet). Your workout history is preserved.")
        }
        .sheet(item: $editSessionItem) { item in
            if let inst = instance {
                SessionDetailEditor(sessionType: item.sessionType, templates: item.templates, exercises: allExercises,
                                    overrides: inst.overrides, instance: inst, week: displayWeek,
                                    onDismiss: { editSessionItem = nil })
            }
        }
        .alert("Update Bodyweight", isPresented: $showBodyweightEntry) {
            TextField(profile?.useMetric == true ? "kg" : "lbs", text: $bodyweightInput).keyboardType(.decimalPad)
            Button("Save") { if let bw = Double(bodyweightInput), bw > 0 { profile?.bodyweight = bw; try? modelContext.save() }; bodyweightInput = "" }
            Button("Cancel", role: .cancel) { bodyweightInput = "" }
        } message: { Text("Enter your current bodyweight") }
    }

    @ViewBuilder private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 18, weight: .black, design: .rounded)).foregroundColor(.appTextPrimary)
            Text(label).font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim).kerning(1)
        }.frame(maxWidth: .infinity).padding(.vertical, 12)
    }
    @ViewBuilder private func statDivider() -> some View {
        Rectangle().frame(width: 1, height: 28).foregroundColor(.appBorder)
    }
}

extension Calendar {
    func startOfWeek(for date: Date) -> Date {
        let comps = dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return self.date(from: comps) ?? date
    }
}

// MARK: - Week Strip
struct WeekStrip: View {
    let displayWeek: Int; let currentWeek: Int; let programId: Int; let totalWeeks: Int; let instance: UserProgramInstance?; let onSelectWeek: (Int) -> Void
    var onTapHeader: (() -> Void)? = nil
    private func isDeload(_ w: Int) -> Bool {
        // ALL programs use blockLength as source of truth (synced everywhere)
        guard let inst = instance else { return false }
        let bl = inst.blockLength > 0 ? inst.blockLength : 5
        let posInBlock = ((w - 1) % (bl + 1)) + 1
        return posInBlock > bl
    }
    var body: some View {
        VStack(spacing: 8) {
            Button(action: { onTapHeader?() }) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("WEEK \(displayWeek)").font(.system(size: 14, weight: .black)).foregroundColor(.appTextPrimary)
                            if displayWeek != currentWeek {
                                Text("(current: W\(currentWeek))").font(.system(size: 10, weight: .bold)).foregroundColor(.appTextDim)
                            }
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundColor(.appBlue)
                        }
                        if let inst = instance {
                            Text(inst.weekDateLabel(for: displayWeek))
                                .font(.system(size: 11, weight: .medium)).foregroundColor(.appTextDim)
                        }
                    }
                    Spacer()
                    if isDeload(displayWeek) {
                        Text("DELOAD").font(.system(size: 9, weight: .black)).foregroundColor(.appBlue).kerning(1)
                            .padding(.horizontal, 7).padding(.vertical, 3).background(Color.appBlue.opacity(0.12)).cornerRadius(4)
                    }
                }
            }.buttonStyle(.plain)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(1...max(totalWeeks, 1), id: \.self) { w in
                            Button(action: { onSelectWeek(w) }) {
                                Text(isDeload(w) ? "W\(w)↺" : "W\(w)")
                                    .font(.system(size: w == displayWeek ? 11 : 10, weight: w == displayWeek ? .black : .semibold))
                                    .foregroundColor(pillTextColor(w))
                                    .padding(.horizontal, 9).padding(.vertical, 5)
                                    .background(pillBG(w)).cornerRadius(6)
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(w == currentWeek ? Color.appGold.opacity(0.6) : Color.clear, lineWidth: 1.5))
                            }.buttonStyle(.plain).id(w)
                        }
                    }.padding(.horizontal, 2)
                }
                .onAppear { proxy.scrollTo(displayWeek, anchor: .center) }
                .onChange(of: displayWeek) { _, w in withAnimation { proxy.scrollTo(w, anchor: .center) } }
            }
            HStack(spacing: 12) {
                legendPill(.appRed, "Viewing"); legendPill(.appGold, "Current"); legendPill(Color.appGreen.opacity(0.7), "Done")
                Spacer()
                if displayWeek != currentWeek {
                    Button(action: { onSelectWeek(currentWeek) }) { Text("Jump to current").font(.system(size: 11, weight: .bold)).foregroundColor(.appBlue) }
                }
            }
        }.padding(14).appCard()
    }
    private func pillTextColor(_ w: Int) -> Color {
        if w == displayWeek { return .white }
        if w < currentWeek { return Color.appGreen }
        if w == currentWeek { return Color.appGold }
        return .appTextDim
    }
    private func pillBG(_ w: Int) -> Color {
        if w == displayWeek { return .appRed }
        if w < currentWeek { return Color.appGreen.opacity(0.12) }
        if w == currentWeek { return Color.appGold.opacity(0.12) }
        if isDeload(w) { return Color.appBlue.opacity(0.08) }
        return Color.appSurface2
    }
    @ViewBuilder private func legendPill(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 12, height: 8); Text(label).font(.system(size: 9)).foregroundColor(.appTextDim) }
    }
}

// MARK: - Home Day Card
struct HomeDayCard: View {
    let dayOfWeek: Int; let sessionType: SessionType?; let isDone: Bool; let weekLogs: [WorkoutLog]
    private let dayNames = ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"]
    private var dayName: String { dayNames[dayOfWeek - 1] }
    private var sessionLogs: [WorkoutLog] {
        guard let st = sessionType else { return [] }
        return weekLogs.filter { $0.sessionTypeRaw == st.rawValue }
    }
    private var sessionVolume: Int { Int(sessionLogs.reduce(0.0) { $0 + ($1.weight * Double($1.reps)) }) }
    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(stripeColor).frame(width: 3)
            HStack(spacing: 12) {
                VStack(spacing: 1) {
                    Text(dayName).font(.system(size: 10, weight: .black)).foregroundColor(stripeColor)
                    if isDone { Image(systemName: "checkmark").font(.system(size: 8, weight: .black)).foregroundColor(.appGreen) }
                }.frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                    if let st = sessionType, st != .rest {
                        Text(st.shortLabel).font(.system(size: 13, weight: .black)).foregroundColor(isDone ? .appGreen : .appTextPrimary)
                        Text(st.muscleSubtitle).font(.system(size: 11)).foregroundColor(.appTextDim)
                        if isDone {
                            Text("\(sessionLogs.count) sets · \(sessionVolume > 1000 ? "\(sessionVolume/1000)K" : "\(sessionVolume)") lbs")
                                .font(.system(size: 10, weight: .bold)).foregroundColor(.appGreen.opacity(0.9))
                        }
                    } else {
                        Text("REST & RECOVERY").font(.system(size: 12, weight: .black)).foregroundColor(.appTextDim)
                        Text("Active recovery · sleep priority").font(.system(size: 10)).foregroundColor(.appTextDim.opacity(0.7))
                    }
                }
                Spacer()
                if let st = sessionType, st != .rest {
                    if isDone { Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundColor(.appGreen) }
                    else { Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundColor(.appTextDim) }
                } else { Image(systemName: "moon.fill").font(.system(size: 14)).foregroundColor(.appTextDim.opacity(0.4)) }
            }.padding(.horizontal, 14).padding(.vertical, 11)
        }
    }
    private var stripeColor: Color {
        guard let st = sessionType, st != .rest else { return Color.appTextDim.opacity(0.2) }
        if isDone { return .appGreen }
        return st.sessionColor
    }
}

// MARK: - Day Drop Delegate (drag-and-drop schedule reorder)
struct DayDropDelegate: DropDelegate {
    let targetDay: Int
    let instance: UserProgramInstance?
    let dayAssignments: [Int: SessionType]
    let splitRotation: [SessionType]
    let week: Int
    let modelContext: ModelContext

    func performDrop(info: DropInfo) -> Bool {
        guard let item = info.itemProviders(for: [UTType.text]).first else { return false }
        item.loadObject(ofClass: NSString.self) { reading, _ in
            guard let str = reading as? String, let sourceDay = Int(str), sourceDay != targetDay else { return }
            DispatchQueue.main.async {
                swapDays(source: sourceDay, target: targetDay)
            }
        }
        return true
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.text])
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    private func swapDays(source: Int, target: Int) {
        guard let inst = instance else { return }
        let sourceSession = dayAssignments[source]
        let targetSession = dayAssignments[target]

        func ensureSchedule(dow: Int, session: SessionType?) {
            let swiftDow = dow == 7 ? 0 : dow
            let isRest = session == nil || session == .rest
            let st = session ?? splitRotation.first ?? .heavyUpper
            // Week-specific override (not permanent)
            let existing = inst.schedules.first(where: { $0.dayOfWeek == swiftDow && !$0.isPermanent && $0.week == week })
            if let existing {
                existing.isRestDay = isRest
                if !isRest { existing.sessionType = st }
            } else {
                let s = ProgramSchedule(dayOfWeek: swiftDow, sessionType: st, isRestDay: isRest, week: week, isPermanent: false)
                inst.schedules.append(s)
            }
        }

        ensureSchedule(dow: source, session: targetSession)
        ensureSchedule(dow: target, session: sourceSession)
        try? modelContext.save()
    }
}

// MARK: - Home Session Card (rotation/number view)
struct HomeSessionCard: View {
    let sessionNumber: Int
    let sessionType: SessionType
    let isDone: Bool
    let weekLogs: [WorkoutLog]

    private var sessionVolume: Int { Int(weekLogs.reduce(0.0) { $0 + ($1.weight * Double($1.reps)) }) }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(isDone ? Color.appGreen : sessionType.sessionColor).frame(width: 3)
            HStack(spacing: 12) {
                VStack(spacing: 1) {
                    Text("S\(sessionNumber)")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundColor(isDone ? .appGreen : sessionType.sessionColor)
                    if isDone { Image(systemName: "checkmark").font(.system(size: 8, weight: .black)).foregroundColor(.appGreen) }
                }.frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(sessionType.shortLabel)
                        .font(.system(size: 13, weight: .black)).foregroundColor(isDone ? .appGreen : .appTextPrimary)
                    Text(sessionType.muscleSubtitle)
                        .font(.system(size: 11)).foregroundColor(.appTextDim)
                    if isDone {
                        Text("\(weekLogs.count) sets · \(sessionVolume > 1000 ? "\(sessionVolume/1000)K" : "\(sessionVolume)") lbs")
                            .font(.system(size: 10, weight: .bold)).foregroundColor(.appGreen.opacity(0.9))
                    }
                }
                Spacer()
                if isDone {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundColor(.appGreen)
                } else {
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundColor(.appTextDim)
                }
            }.padding(.horizontal, 14).padding(.vertical, 11)
        }
    }
}

extension SessionType {
    var sessionColor: Color {
        switch self {
        case .heavyUpper, .chestBack:           return .appRed
        case .heavyLower, .legsPosterior:       return Color(red: 0.88, green: 0.48, blue: 0.37)
        case .hypertrophyUpper, .chestArms:     return .appBlue
        case .hypertrophyLower, .legQuadFocus:  return Color(red: 0.50, green: 0.70, blue: 0.60)
        case .armsDelts:                        return .appGold
        case .legsVolume:                       return Color(red: 0.95, green: 0.80, blue: 0.56)
        case .pushA, .pushB:                    return .appRed
        case .pullA, .pullB:                    return .appBlue
        case .legsA, .legsB:                    return Color(red: 0.50, green: 0.70, blue: 0.60)
        case .freeform:                         return .appTextSecondary
        default:                                return .appRed
        }
    }
    var muscleSubtitle: String {
        switch self {
        case .heavyUpper:           return "Chest · Back · Shoulders · Arms"
        case .heavyLower:           return "Squat · Hinge · Calves"
        case .hypertrophyUpper:     return "Chest · Arms · Delts"
        case .hypertrophyLower:     return "Quads · Hamstrings · Calves"
        case .legQuadFocus:         return "Quads · Hamstrings · Calves"
        case .legsPosterior:        return "Hinge · Hamstrings · Glutes"
        case .chestBack:            return "Chest · Back · Core"
        case .armsDelts:            return "Biceps · Triceps · Delts"
        case .chestArms:            return "Chest · Triceps · Delts"
        case .legsVolume:           return "Quads · Hamstrings · Calves — Volume"
        case .pushA:                return "Bench · Incline · OHP · Laterals · Triceps"
        case .pushB:                return "OHP · Incline · Chest Fly · Laterals · Triceps"
        case .pullA:                return "Row · Pulldown · Cable Row · Face Pull · Curls"
        case .pullB:                return "Deadlift · DB Row · Pulldown · Curls"
        case .legsA:                return "Squat · Leg Press · Extensions · Leg Curl · Calves"
        case .legsB:                return "RDL · Leg Press · Leg Curl · Extensions · Calves"
        case .freeform:             return "Build your own workout"
        default:                    return rawValue
        }
    }
}

// MARK: - Hero Header
struct HomeHeroHeader: View {
    let profile: UserProfile?; let instance: UserProgramInstance?; let displayWeek: Int; let onTapProgram: () -> Void
    private var isFreestyle: Bool { instance?.programId == 0 }
    private var progress: Double { Double(displayWeek) / 24.0 }
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    if isFreestyle {
                        Text("FREESTYLE").font(.system(size: 9, weight: .black)).foregroundColor(.appTextSecondary).kerning(2)
                    } else {
                        HStack(spacing: 6) {
                            Text(blockLabel).font(.system(size: 9, weight: .black)).foregroundColor(.appRed).kerning(2)
                            Text("WEEK \(displayWeek)").font(.system(size: 9, weight: .black)).foregroundColor(.appTextDim).kerning(2)
                        }
                    }
                    Text((profile?.name ?? "ATHLETE").uppercased())
                        .font(.system(size: 28, weight: .black, design: .rounded)).foregroundColor(.appTextPrimary).lineLimit(1).minimumScaleFactor(0.5)
                    Button(action: onTapProgram) {
                        HStack(spacing: 5) {
                            Text(instance?.name.uppercased() ?? "SELECT PROGRAM").font(.system(size: 11, weight: .bold)).foregroundColor(.appTextSecondary)
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4).background(Color.appSurface2).cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.appBorder, lineWidth: 1))
                    }.buttonStyle(.plain)
                }
                Spacer()
                if !isFreestyle {
                    ZStack {
                        Circle().stroke(Color.appBorder, lineWidth: 3)
                        Circle().trim(from: 0, to: progress).stroke(Color.appRed, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90)).animation(.easeOut(duration: 0.8), value: progress)
                        VStack(spacing: 0) {
                            Text("\(displayWeek)").font(.system(size: 20, weight: .black, design: .rounded)).foregroundColor(.appRed)
                            Text("/ 24").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim)
                        }
                    }.frame(width: 58, height: 58)
                }
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 14).background(LinearGradient.appHeader)
            Rectangle().frame(height: 1.5).foregroundColor(.appRed.opacity(0.5))
        }
    }
    private var blockLabel: String {
        guard let inst = instance else { return "TRAINING" }
        if inst.programId == 0 { return "FREESTYLE" }
        let goal = profile?.goal ?? .hypertrophy
        let isHyp = goal == .hypertrophy || goal == .recomp

        // Generated programs — use block type with goal-aware naming
        if inst.isGenerated {
            switch (isHyp, inst.blockType) {
            case (true, .accumulation):    return "TRAINING BLOCK"
            case (true, .reaccumulation):  return "GROWTH PHASE"
            case (true, .deload):          return "RECOVERY"
            case (true, _):                return "TRAINING BLOCK"
            case (false, _):               return inst.blockType.rawValue.uppercased()
            }
        }

        // Seeded programs
        let w = displayWeek
        if inst.programId == 7 { if [3,6,9,12,15,18,21].contains(w) || w == 24 { return isHyp ? "RECOVERY" : "DELOAD" }; if w <= 9 { return "BLOCK 1" }; if w <= 15 { return "BLOCK 2" }; return "BLOCK 3" }
        if [4,8,12,16,20].contains(w) { return isHyp ? "RECOVERY" : "DELOAD" }; if w == 24 { return "TESTING" }
        if w <= 8 { return isHyp ? "TRAINING BLOCK" : "ACCUMULATION" }; if w <= 16 { return isHyp ? "GROWTH PHASE" : "INTENSIFICATION" }; return isHyp ? "TRAINING BLOCK" : "PEAKING"
    }
}

// Helper to bundle editor sheet data as an Identifiable item
struct SessionEditorItem: Identifiable {
    let id = UUID()
    let sessionType: SessionType
    let templates: [ProgramSessionTemplate]
}

// MARK: - Week Hub Sheet
struct WeekHubSheet: View {
    let instance: UserProgramInstance
    @Binding var viewingWeek: Int
    let onDismiss: () -> Void
    @Environment(\.modelContext) private var modelContext
    @Query private var allTemplates: [ProgramSessionTemplate]
    @Query private var allExercises: [Exercise]
    @Query private var programTemplates: [ProgramTemplate]
    @State private var localWeek: Int
    @State private var editorItem: SessionEditorItem? = nil
    @State private var confirmAdvance = false
    @State private var confirmGoBack = false
    @State private var selectedDayForAssignment: Int? = nil

    private var totalWeeks: Int {
        programTemplates.first(where: { $0.programId == instance.programId })?.durationWeeks ?? (instance.programId == 2 ? 16 : 24)
    }

    init(instance: UserProgramInstance, viewingWeek: Binding<Int>, onDismiss: @escaping () -> Void) {
        self.instance = instance; self._viewingWeek = viewingWeek; self.onDismiss = onDismiss
        _localWeek = State(initialValue: viewingWeek.wrappedValue)
    }

    private func splitOrder(for pid: Int) -> [SessionType] {
        if pid == 0 { return [.freeform] }
        if pid == 2 { return [.pushA, .pullA, .legsA, .pushB, .pullB, .legsB] }
        if pid == 7 { return [.legQuadFocus, .chestBack, .armsDelts, .legsPosterior, .chestArms, .legsVolume] }
        if pid >= 100, let tmpl = programTemplates.first(where: { $0.programId == pid }) { return tmpl.sessionTypes }
        return [.heavyUpper, .heavyLower, .hypertrophyUpper, .hypertrophyLower]
    }
    private var sessionsForWeek: [(SessionType, [ProgramSessionTemplate])] {
        let rotation = splitOrder(for: instance.programId)
        var result: [(SessionType, [ProgramSessionTemplate])] = rotation.compactMap { st in
            let t = allTemplates.filter { $0.programId == instance.programId && $0.week == localWeek && $0.sessionType == st }.sorted { $0.exerciseIndex < $1.exerciseIndex }
            return t.isEmpty ? nil : (st, t)
        }
        // Include session types assigned via schedule overrides that aren't in the rotation
        let rotationSet = Set(rotation)
        let scheduledExtras: [SessionType] = scheduleMap.values
            .filter { !$0.1 && !rotationSet.contains($0.0) }  // not rest, not already in rotation
            .map { $0.0 }
        let uniqueExtras = Array(Set(scheduledExtras))
        for st in uniqueExtras {
            let t = allTemplates.filter { $0.programId == instance.programId && $0.week == localWeek && $0.sessionType == st }.sorted { $0.exerciseIndex < $1.exerciseIndex }
            if !t.isEmpty { result.append((st, t)) }
        }
        return result
    }
    private var exerciseNames: [String: String] { Dictionary(allExercises.map { ($0.exerciseKey, $0.displayName) }, uniquingKeysWith: { first, _ in first }) }
    private var scheduleMap: [Int: (SessionType, Bool)] {
        var map: [Int: (SessionType, Bool)] = [:]
        // Permanent overrides first
        for s in instance.schedules where s.isPermanent {
            let dow = s.dayOfWeek == 0 ? 7 : s.dayOfWeek
            map[dow] = (s.sessionType, s.isRestDay)
        }
        // Week-specific overrides take priority
        for s in instance.schedules where !s.isPermanent && s.week == localWeek {
            let dow = s.dayOfWeek == 0 ? 7 : s.dayOfWeek
            map[dow] = (s.sessionType, s.isRestDay)
        }
        return map
    }

    var body: some View {
        ZStack {
            Color.appBG.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("WEEK HUB").font(.system(size: 10, weight: .black)).foregroundColor(.appRed).kerning(2)
                        Text("Configure Schedule & Workouts").font(.system(size: 15, weight: .black)).foregroundColor(.appTextPrimary)
                    }
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundColor(.appTextSecondary)
                            .frame(width: 32, height: 32).background(Color.appSurface2).clipShape(Circle())
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 14).background(Color.appSurface)
                .overlay(Rectangle().frame(height: 1).foregroundColor(.appBorder), alignment: .bottom)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        weekNavSection
                        dayAssignmentSection
                        sessionsSection
                        deloadControlSection
                        if localWeek == instance.currentWeek { weekControlButtons }
                    }
                    .padding(16).padding(.bottom, 40)
                }
            }
        }
        .sheet(item: $editorItem) { item in
            SessionDetailEditor(sessionType: item.sessionType, templates: item.templates, exercises: allExercises,
                                overrides: instance.overrides, instance: instance, week: localWeek,
                                onDismiss: { editorItem = nil })
        }
        .alert("Advance to Week \(instance.currentWeek + 1)?", isPresented: $confirmAdvance) {
            Button("Advance", role: .destructive) { advanceWeek() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Marks Week \(instance.currentWeek) complete and moves to Week \(instance.currentWeek + 1).") }
        .alert("Go Back to Week \(max(1, instance.currentWeek - 1))?", isPresented: $confirmGoBack) {
            Button("Go Back", role: .destructive) { goBackWeek() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Moves current week back by one. Logs are not deleted.") }
        .sheet(item: Binding(
            get: { selectedDayForAssignment.map { DayAssignmentItem(dow: $0) } },
            set: { if $0 == nil { selectedDayForAssignment = nil } }
        )) { item in
            DayAssignmentSheet(
                dow: item.dow,
                instance: instance,
                week: localWeek,
                permanent: permanentSchedule,
                onAssign: { sessionType, templateId in
                    assignDay(dow: item.dow, sessionType: sessionType, permanent: permanentSchedule)
                    if let tid = templateId, !tid.isEmpty {
                        let swiftDow = item.dow == 7 ? 0 : item.dow
                        if let schedule = instance.schedules.first(where: {
                            $0.dayOfWeek == swiftDow && (permanentSchedule ? $0.isPermanent : (!$0.isPermanent && $0.week == localWeek))
                        }) {
                            schedule.dayTemplateId = tid
                            try? modelContext.save()
                        }
                    }
                    selectedDayForAssignment = nil
                },
                onDismiss: { selectedDayForAssignment = nil }
            )
        }
    }

    private var weekNavSection: some View {
        VStack(spacing: 10) {
            HStack {
                Button(action: { if localWeek > 1 { localWeek -= 1; viewingWeek = localWeek } }) {
                    Image(systemName: "chevron.left.circle.fill").font(.system(size: 30))
                        .foregroundColor(localWeek > 1 ? .appRed : .appBorder)
                }.buttonStyle(.plain).disabled(localWeek <= 1)
                Spacer()
                VStack(spacing: 2) {
                    Text("WEEK \(localWeek)").font(.system(size: 24, weight: .black, design: .rounded)).foregroundColor(.appTextPrimary)
                    Text(blockLabel(localWeek)).font(.system(size: 10, weight: .black)).foregroundColor(blockColor(localWeek)).kerning(1)
                }
                Spacer()
                Button(action: { if localWeek < totalWeeks { localWeek += 1; viewingWeek = localWeek } }) {
                    Image(systemName: "chevron.right.circle.fill").font(.system(size: 30))
                        .foregroundColor(localWeek < totalWeeks ? .appRed : .appBorder)
                }.buttonStyle(.plain).disabled(localWeek >= totalWeeks)
            }
            HStack(spacing: 2) {
                ForEach(1...max(totalWeeks, 1), id: \.self) { w in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(w == localWeek ? Color.appRed : (w == instance.currentWeek ? Color.appGold : (w < instance.currentWeek ? Color.appGreen.opacity(0.5) : blockColor(w).opacity(0.25))))
                        .frame(height: 8).onTapGesture { localWeek = w; viewingWeek = w }
                }
            }
            HStack {
                legendDot(.appRed, "Viewing"); legendDot(.appGold, "Current"); legendDot(.appGreen.opacity(0.5), "Done")
                Spacer()
                if localWeek != instance.currentWeek {
                    Button(action: { localWeek = instance.currentWeek; viewingWeek = localWeek }) {
                        Text("Jump to current").font(.system(size: 11, weight: .bold)).foregroundColor(.appBlue)
                    }
                }
            }
        }.padding(14).appCard()
    }

    @State private var permanentSchedule = false

    private var dayAssignmentSection: some View {
        let rotation = splitOrder(for: instance.programId)
        return VStack(spacing: 0) {
            HStack {
                Text("DAY ASSIGNMENT").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(2)
                Spacer()
                Text(permanentSchedule ? "All weeks" : "Week \(localWeek) only")
                    .font(.system(size: 10, weight: .bold)).foregroundColor(permanentSchedule ? .appGold : .appBlue)
            }.padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 4)
            HStack(spacing: 8) {
                Button(action: { permanentSchedule = false }) {
                    Text("THIS WEEK").font(.system(size: 9, weight: .black)).kerning(0.5)
                        .foregroundColor(!permanentSchedule ? .white : .appTextDim)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(!permanentSchedule ? Color.appBlue : Color.clear).cornerRadius(5)
                }.buttonStyle(.plain)
                Button(action: { permanentSchedule = true }) {
                    Text("ALL WEEKS").font(.system(size: 9, weight: .black)).kerning(0.5)
                        .foregroundColor(permanentSchedule ? .white : .appTextDim)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(permanentSchedule ? Color.appGold : Color.clear).cornerRadius(5)
                }.buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.bottom, 8)
            .background(Color.appSurface2.cornerRadius(6).padding(.horizontal, 10))

            Divider().background(Color.appBorder)
            ForEach(1...7, id: \.self) { dow in
                let dayNames = ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"]
                let curAssignment = scheduleMap[dow].map { $0.1 ? SessionType.rest : $0.0 } ?? defaultAssignment(dow: dow, rotation: rotation)
                Button(action: { selectedDayForAssignment = dow }) {
                    HStack(spacing: 10) {
                        Text(dayNames[dow-1]).font(.system(size: 13, weight: .bold)).foregroundColor(.appTextPrimary)
                            .frame(width: 88, alignment: .leading)
                        Rectangle()
                            .fill(curAssignment == .rest ? Color.appTextDim.opacity(0.2) : curAssignment.sessionColor)
                            .frame(width: 3, height: 32).cornerRadius(1.5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(curAssignment == .rest ? "REST" : curAssignment.shortLabel)
                                .font(.system(size: 12, weight: .black))
                                .foregroundColor(curAssignment == .rest ? .appTextDim : .appTextPrimary)
                            Text(curAssignment == .rest ? "Recovery day" : curAssignment.muscleSubtitle)
                                .font(.system(size: 10)).foregroundColor(.appTextDim).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundColor(.appTextDim)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(curAssignment == .rest ? Color.appSurface2.opacity(0.4) : Color.clear)
                if dow < 7 { Divider().background(Color.appBorder).padding(.leading, 14) }
            }
        }
        .background(Color.appSurface).cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
    }

    private var sessionsSection: some View {
        VStack(spacing: 10) {
            HStack {
                Text("SESSIONS — WEEK \(localWeek)").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(2)
                Spacer()
                if localWeek != instance.currentWeek { Text("READ ONLY").font(.system(size: 9, weight: .black)).foregroundColor(.appTextDim).kerning(1) }
            }.padding(.horizontal, 4)
            if sessionsForWeek.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "calendar.badge.exclamationmark").font(.system(size: 28)).foregroundColor(.appTextDim)
                    Text("No sessions found for Week \(localWeek)").font(.system(size: 13)).foregroundColor(.appTextDim)
                }.padding(30).appCard()
            } else {
                ForEach(sessionsForWeek, id: \.0) { (st, templates) in
                    HubSessionCard(sessionType: st, templates: templates, exerciseNames: exerciseNames,
                                   overrides: instance.overrides, week: localWeek,
                                   onEdit: {
                                        let t = allTemplates
                                            .filter { $0.programId == instance.programId && $0.week == localWeek && $0.sessionType == st }
                                            .sorted { $0.exerciseIndex < $1.exerciseIndex }
                                        editorItem = SessionEditorItem(sessionType: st, templates: t)
                                   })
                }
            }
        }
    }

    private var weekControlButtons: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button(action: { if instance.currentWeek > 1 { confirmGoBack = true } }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.left.circle.fill").font(.system(size: 18)).foregroundColor(.appTextSecondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("GO BACK").font(.system(size: 11, weight: .black)).foregroundColor(.appTextSecondary).kerning(1)
                            Text("→ W\(max(1, instance.currentWeek - 1))").font(.system(size: 11)).foregroundColor(.appTextDim)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12).background(Color.appSurface2).cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))
                }
                .buttonStyle(.plain).opacity(instance.currentWeek > 1 ? 1 : 0.35).disabled(instance.currentWeek <= 1)

                Button(action: { if instance.currentWeek < 24 { confirmAdvance = true } }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.right.circle.fill").font(.system(size: 18)).foregroundColor(.appRed)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("ADVANCE").font(.system(size: 11, weight: .black)).foregroundColor(.appRed).kerning(1)
                            Text("→ W\(min(24, instance.currentWeek + 1))").font(.system(size: 11)).foregroundColor(.appTextDim)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12).background(Color.appRed.opacity(0.08)).cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appRed.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain).disabled(instance.currentWeek >= 24)
            }
            Button(action: { instance.nextRotationIndex = 0; try? modelContext.save() }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 12)).foregroundColor(.appTextDim)
                    Text("RESET SESSION ROTATION").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(1)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 10).background(Color.appSurface2).cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorder, lineWidth: 1))
            }.buttonStyle(.plain)
        }
    }

    private var deloadControlSection: some View {
        let programDefaults = UserProgramInstance.defaultDeloadWeeks(for: instance.programId)
        let isDefaultDeload = programDefaults.contains(localWeek)
        let isCustomDeload = instance.customDeloadWeeks.contains(localWeek)
        let isSkipped = instance.skippedDeloadWeeks.contains(localWeek)
        let isCurrentlyDeload = isDeload(localWeek)
        let suggestion = ProgressionEngine.shouldSuggestDeload(progressionStates: instance.progressionStates)

        return VStack(spacing: 8) {
            HStack {
                Text("RECOVERY / DELOAD").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(2)
                Spacer()
                if isCurrentlyDeload {
                    Text("ACTIVE").font(.system(size: 9, weight: .black)).foregroundColor(.appBlue)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.appBlue.opacity(0.12)).cornerRadius(4)
                }
            }.padding(.horizontal, 4)

            VStack(spacing: 10) {
                if isDefaultDeload && !isSkipped {
                    Button(action: {
                        instance.skippedDeloadWeeks.insert(localWeek)
                        try? modelContext.save()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "forward.fill").font(.system(size: 12)).foregroundColor(.appOrange)
                            Text("SKIP DELOAD THIS WEEK").font(.system(size: 11, weight: .black)).foregroundColor(.appOrange).kerning(0.5)
                            Spacer()
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(Color.appOrange.opacity(0.08)).cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appOrange.opacity(0.25), lineWidth: 1))
                    }.buttonStyle(.plain)
                } else if isDefaultDeload && isSkipped {
                    Button(action: {
                        instance.skippedDeloadWeeks.remove(localWeek)
                        try? modelContext.save()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.uturn.backward").font(.system(size: 12)).foregroundColor(.appBlue)
                            Text("RESTORE DELOAD").font(.system(size: 11, weight: .black)).foregroundColor(.appBlue).kerning(0.5)
                            Spacer()
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(Color.appBlue.opacity(0.08)).cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBlue.opacity(0.25), lineWidth: 1))
                    }.buttonStyle(.plain)
                } else if isCustomDeload {
                    Button(action: {
                        instance.customDeloadWeeks.remove(localWeek)
                        try? modelContext.save()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundColor(.appRed)
                            Text("REMOVE CUSTOM DELOAD").font(.system(size: 11, weight: .black)).foregroundColor(.appRed).kerning(0.5)
                            Spacer()
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(Color.appRed.opacity(0.08)).cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appRed.opacity(0.25), lineWidth: 1))
                    }.buttonStyle(.plain)
                } else {
                    Button(action: {
                        instance.customDeloadWeeks.insert(localWeek)
                        try? modelContext.save()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "battery.25percent").font(.system(size: 12)).foregroundColor(.appBlue)
                            Text("MAKE THIS A DELOAD WEEK").font(.system(size: 11, weight: .black)).foregroundColor(.appBlue).kerning(0.5)
                            Spacer()
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(Color.appBlue.opacity(0.08)).cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBlue.opacity(0.25), lineWidth: 1))
                    }.buttonStyle(.plain)
                }

                if suggestion && localWeek == instance.currentWeek && !isCurrentlyDeload {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 14)).foregroundColor(.appYellow)
                        Text("Multiple lifts showing fatigue. Consider taking a deload.")
                            .font(.system(size: 12)).foregroundColor(.appTextSecondary)
                    }
                    .padding(12)
                    .background(Color.appYellow.opacity(0.08)).cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appYellow.opacity(0.25), lineWidth: 1))
                }
            }
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) { Circle().fill(color).frame(width: 7, height: 7); Text(label).font(.system(size: 9)).foregroundColor(.appTextDim) }
    }
    private func advanceWeek() { instance.microcycleIndex = min(23, instance.microcycleIndex + 1); localWeek = instance.currentWeek; viewingWeek = localWeek; try? modelContext.save() }
    private func goBackWeek() { instance.microcycleIndex = max(0, instance.microcycleIndex - 1); localWeek = instance.currentWeek; viewingWeek = localWeek; try? modelContext.save() }
    private func assignDay(dow: Int, sessionType: SessionType, permanent: Bool = false) {
        let swiftDow = dow == 7 ? 0 : dow
        // Look for existing override for this week + day (or permanent if permanent)
        let existing = instance.schedules.first(where: {
            $0.dayOfWeek == swiftDow && (permanent ? $0.isPermanent : (!$0.isPermanent && $0.week == localWeek))
        })
        if let existing {
            existing.isRestDay = sessionType == .rest
            if sessionType != .rest { existing.sessionType = sessionType }
        } else {
            let rotation = splitOrder(for: instance.programId)
            let s = ProgramSchedule(
                dayOfWeek: swiftDow,
                sessionType: sessionType == .rest ? (rotation.first ?? .heavyUpper) : sessionType,
                isRestDay: sessionType == .rest,
                week: permanent ? 0 : localWeek,
                isPermanent: permanent
            )
            instance.schedules.append(s)
        }
        try? modelContext.save()
    }
    private func defaultAssignment(dow: Int, rotation: [SessionType]) -> SessionType {
        let workDays: [Int] = rotation.count == 6 ? [1,2,3,4,6,7] : rotation.count == 3 ? [1,3,5] : [1,2,4,5]
        if let idx = workDays.firstIndex(of: dow), idx < rotation.count { return rotation[idx] }
        return .rest
    }
    private func blockLabel(_ w: Int) -> String {
        if isDeload(w) { return "DELOAD" }; if w == 24 { return "TESTING" }
        if instance.programId == 7 { if w <= 9 { return "BLOCK 1 — HYPERTROPHY" }; if w <= 15 { return "BLOCK 2 — STRENGTH" }; return "BLOCK 3 — PEAK" }
        if w <= 8 { return "ACCUMULATION" }; if w <= 16 { return "INTENSIFICATION" }; return "PEAKING"
    }
    private func blockColor(_ w: Int) -> Color {
        if isDeload(w) { return .appBlue }; if w == 24 { return .appGold }
        if instance.programId == 7 { if w <= 9 { return .appGreen }; if w <= 15 { return .appGold }; return .appRed }
        if w <= 8 { return .appGreen }; if w <= 16 { return .appGold }; return .appRed
    }
    private func isDeload(_ w: Int) -> Bool {
        // Generated programs: deload is the last week of each block cycle
        // ALL programs use blockLength as source of truth
        let bl = instance.blockLength > 0 ? instance.blockLength : 5
        let posInBlock = ((w - 1) % (bl + 1)) + 1
        return posInBlock > bl
    }
}

// MARK: - Hub Session Card
struct HubSessionCard: View {
    let sessionType: SessionType
    let templates: [ProgramSessionTemplate]
    let exerciseNames: [String: String]
    let overrides: [SessionOverride]
    let week: Int
    let onEdit: () -> Void

    private var totalSets: Int { templates.reduce(0) { $0 + $1.targetSets } }
    private func resolvedKey(for t: ProgramSessionTemplate) -> String {
        resolveExerciseKey(slotId: t.slotId, originalKey: t.exerciseKey, overrides: overrides, week: week)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Rectangle().fill(sessionType.sessionColor).frame(width: 3).cornerRadius(2)
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(sessionType.shortLabel).font(.system(size: 14, weight: .black)).foregroundColor(.appTextPrimary)
                        Text("\(templates.count) exercises · \(totalSets) sets").font(.system(size: 11)).foregroundColor(.appTextDim)
                    }
                    Spacer()
                    let swapped = templates.filter { resolvedKey(for: $0) != $0.exerciseKey }.count
                    if swapped > 0 {
                        Text("\(swapped) swapped").font(.system(size: 9, weight: .black)).foregroundColor(.appBlue)
                            .padding(.horizontal, 6).padding(.vertical, 3).background(Color.appBlue.opacity(0.12)).cornerRadius(4)
                    }
                    Button(action: onEdit) {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil").font(.system(size: 11, weight: .bold))
                            Text("EDIT").font(.system(size: 10, weight: .black)).kerning(1)
                        }
                        .foregroundColor(.appRed).padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.appRed.opacity(0.10)).cornerRadius(7)
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.appRed.opacity(0.25), lineWidth: 1))
                    }.buttonStyle(.plain)
                }.padding(.horizontal, 14).padding(.vertical, 12)
            }
            Divider().background(Color.appBorder).padding(.horizontal, 14)
            VStack(spacing: 0) {
                ForEach(templates.prefix(3), id: \.slotId) { t in
                    let key = resolvedKey(for: t)
                    let name = exerciseNames[key] ?? key.replacingOccurrences(of: "_", with: " ").capitalized
                    let isSwapped = key != t.exerciseKey
                    HStack(spacing: 10) {
                        Text(t.slotId).font(.system(size: 8, weight: .black, design: .monospaced)).foregroundColor(.appRed)
                            .frame(width: 30, height: 30).contentShape(Rectangle()).background(Color.appRed.opacity(0.08)).cornerRadius(6)
                        Text(name).font(.system(size: 12, weight: .semibold)).foregroundColor(isSwapped ? .appBlue : .appTextSecondary).lineLimit(1)
                        Spacer()
                        Text("\(t.targetSets)×\(t.targetRepsLow)–\(t.targetRepsHigh)").font(.system(size: 10, design: .monospaced)).foregroundColor(.appTextDim)
                    }.padding(.horizontal, 14).padding(.vertical, 6)
                }
                if templates.count > 3 {
                    Text("+ \(templates.count - 3) more — tap EDIT to see all").font(.system(size: 10)).foregroundColor(.appTextDim)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                }
            }
        }
        .background(Color.appSurface).cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
    }
}

// MARK: - Session Detail Editor
struct SessionDetailEditor: View {
    let sessionType: SessionType
    @State var templates: [ProgramSessionTemplate]
    let exercises: [Exercise]
    let overrides: [SessionOverride]
    let instance: UserProgramInstance
    let week: Int
    let onDismiss: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var editMode: EditMode = .inactive
    @State private var swapTarget: SwapTarget? = nil
    @State private var editingTemplate: ProgramSessionTemplate? = nil
    @State private var editSets = ""
    @State private var editRepsLow = ""
    @State private var editRepsHigh = ""
    @State private var editRPE = ""
    @State private var editRestSeconds = ""
    @State private var showAddExercise = false
    @State private var deleteTarget: ProgramSessionTemplate? = nil
    @State private var showDeleteConfirm = false

    private var exerciseNames: [String: String] { Dictionary(exercises.map { ($0.exerciseKey, $0.displayName) }, uniquingKeysWith: { first, _ in first }) }
    private func resolvedKey(for t: ProgramSessionTemplate) -> String {
        resolveExerciseKey(slotId: t.slotId, originalKey: t.exerciseKey, overrides: overrides, week: week)
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.appBG.ignoresSafeArea()
                if templates.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass").font(.system(size: 36)).foregroundColor(.appTextDim)
                        Text("No exercises found").font(.system(size: 16, weight: .bold)).foregroundColor(.appTextSecondary)
                        Text("Tap + to add exercises to this session.")
                            .font(.system(size: 13)).foregroundColor(.appTextDim).multilineTextAlignment(.center)
                    }.padding(40)
                }
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(Array(templates.enumerated()), id: \.element.slotId) { idx, t in
                            let key = resolvedKey(for: t)
                            let name = exerciseNames[key] ?? key.replacingOccurrences(of: "_", with: " ").capitalized
                            let isSwapped = key != t.exerciseKey

                            VStack(spacing: 0) {
                                // Exercise header
                                HStack(spacing: 10) {
                                    Text(t.slotId).font(.system(size: 9, weight: .black, design: .monospaced)).foregroundColor(.appRed)
                                        .frame(width: 34, height: 34).contentShape(Rectangle()).background(Color.appRed.opacity(0.10)).cornerRadius(6)
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(name).font(.system(size: 13, weight: .black)).foregroundColor(isSwapped ? .appBlue : .appTextPrimary)
                                            if t.isMainLift {
                                                Text("MAIN").font(.system(size: 7, weight: .black)).foregroundColor(.appGold)
                                                    .padding(.horizontal, 4).padding(.vertical, 2).background(Color.appGold.opacity(0.15)).cornerRadius(3)
                                            }
                                            if isSwapped {
                                                Text("SWAPPED").font(.system(size: 7, weight: .black)).foregroundColor(.appBlue)
                                                    .padding(.horizontal, 4).padding(.vertical, 2).background(Color.appBlue.opacity(0.12)).cornerRadius(3)
                                            }
                                        }
                                    }
                                    Spacer()
                                    // Action buttons
                                    HStack(spacing: 4) {
                                        // Reorder
                                        if idx > 0 {
                                            Button(action: { moveTemplate(from: idx, direction: -1) }) {
                                                Image(systemName: "chevron.up").font(.system(size: 10, weight: .bold)).foregroundColor(.appTextDim)
                                                    .frame(width: 34, height: 34).contentShape(Rectangle()).background(Color.appSurface2).cornerRadius(6)
                                            }.buttonStyle(.plain)
                                        }
                                        if idx < templates.count - 1 {
                                            Button(action: { moveTemplate(from: idx, direction: 1) }) {
                                                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundColor(.appTextDim)
                                                    .frame(width: 34, height: 34).contentShape(Rectangle()).background(Color.appSurface2).cornerRadius(6)
                                            }.buttonStyle(.plain)
                                        }
                                        // Delete
                                        Button(action: { deleteTarget = t; showDeleteConfirm = true }) {
                                            Image(systemName: "trash").font(.system(size: 10, weight: .bold)).foregroundColor(.appRed.opacity(0.7))
                                                .frame(width: 34, height: 34).contentShape(Rectangle()).background(Color.appRed.opacity(0.08)).cornerRadius(6)
                                        }.buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)

                                // Inline parameter controls
                                HStack(spacing: 0) {
                                    editorPill(label: "SETS", value: "\(t.targetSets)") { openEdit(t) }
                                    pillDivider
                                    editorPill(label: "REPS", value: "\(t.targetRepsLow)–\(t.targetRepsHigh)") { openEdit(t) }
                                    pillDivider
                                    editorPill(label: "RPE", value: String(format: "%.1f", t.targetRPE)) { openEdit(t) }
                                    pillDivider
                                    editorPill(label: "REST", value: restLabel(t.restSeconds)) { openEdit(t) }
                                }
                                .background(Color.appSurface2).cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorder, lineWidth: 1))
                                .padding(.horizontal, 14)

                                // Quick set adjusters
                                HStack(spacing: 10) {
                                    // Quick set +/- buttons
                                    HStack(spacing: 4) {
                                        Button(action: { adjustSets(t, by: -1) }) {
                                            Image(systemName: "minus").font(.system(size: 10, weight: .bold)).foregroundColor(.appTextDim)
                                                .frame(width: 36, height: 36).contentShape(Rectangle()).background(Color.appSurface2).cornerRadius(8)
                                        }.buttonStyle(.plain)
                                        Text("\(t.targetSets) sets")
                                            .font(.system(size: 12, weight: .bold)).foregroundColor(.appTextSecondary)
                                            .frame(minWidth: 48)
                                        Button(action: { adjustSets(t, by: 1) }) {
                                            Image(systemName: "plus").font(.system(size: 10, weight: .bold)).foregroundColor(.appTextDim)
                                                .frame(width: 36, height: 36).contentShape(Rectangle()).background(Color.appSurface2).cornerRadius(8)
                                        }.buttonStyle(.plain)
                                    }

                                    Spacer()

                                    // Swap button
                                    Button(action: {
                                        swapTarget = SwapTarget.from(exerciseKey: key, displayName: name, slotId: t.slotId, sessionType: sessionType, exercises: exercises)
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 11))
                                            Text("SWAP").font(.system(size: 10, weight: .black)).kerning(0.5)
                                        }
                                        .foregroundColor(.appTextSecondary).padding(.horizontal, 10).padding(.vertical, 6)
                                        .background(Color.appSurface2).cornerRadius(7)
                                    }.buttonStyle(.plain)
                                }
                                .padding(.horizontal, 14).padding(.top, 6).padding(.bottom, 12)
                            }
                            .background(Color.appSurface)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
                            .padding(.horizontal, 16).padding(.top, idx == 0 ? 16 : 8)
                        }

                        // Add Exercise button
                        Button(action: { showAddExercise = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill").font(.system(size: 18))
                                Text("ADD EXERCISE").font(.system(size: 13, weight: .black)).kerning(1)
                            }
                            .foregroundColor(.appRed)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Color.appRed.opacity(0.08)).cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appRed.opacity(0.25), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16).padding(.top, 12)

                        Spacer(minLength: 80)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: onDismiss) { Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundColor(.appTextSecondary) }
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(sessionType.shortLabel).font(.system(size: 13, weight: .black)).foregroundColor(.appTextPrimary)
                        Text("Week \(week)  ·  \(templates.count) exercises").font(.system(size: 10)).foregroundColor(.appTextDim)
                    }
                }
            }
        }
        .sheet(item: $swapTarget) { target in
            ExerciseSwapSheet(slot: target, instance: instance, week: week,
                              onDismiss: { swapTarget = nil },
                              onSwapApplied: { _, _ in })
        }
        .sheet(item: $editingTemplate) { t in
            ExerciseParamEditor(template: t, setsInput: $editSets, repsLowInput: $editRepsLow,
                                repsHighInput: $editRepsHigh, rpeInput: $editRPE, restInput: $editRestSeconds,
                                onSave: {
                                    t.targetSets = Int(editSets) ?? t.targetSets
                                    t.targetRepsLow = Int(editRepsLow) ?? t.targetRepsLow
                                    t.targetRepsHigh = Int(editRepsHigh) ?? t.targetRepsHigh
                                    t.targetRPE = Double(editRPE) ?? t.targetRPE
                                    t.restSeconds = Int(editRestSeconds) ?? t.restSeconds
                                    try? modelContext.save()
                                    editingTemplate = nil
                                },
                                onDismiss: { editingTemplate = nil })
        }
        .sheet(isPresented: $showAddExercise) {
            InWorkoutAddSheet(allExercises: exercises) { exercise in
                addExerciseToSession(exercise)
                showAddExercise = false
            }
        }
        .confirmationDialog("Remove Exercise?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let target = deleteTarget { removeTemplate(target) }
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("Remove this exercise from the session template?")
        }
    }

    // ── Helpers ──────────────────────────────────────────────────────────

    private func openEdit(_ t: ProgramSessionTemplate) {
        editingTemplate = t
        editSets = "\(t.targetSets)"
        editRepsLow = "\(t.targetRepsLow)"
        editRepsHigh = "\(t.targetRepsHigh)"
        editRPE = String(format: "%.1f", t.targetRPE)
        editRestSeconds = "\(t.restSeconds)"
    }

    private func adjustSets(_ t: ProgramSessionTemplate, by delta: Int) {
        let newSets = max(1, min(10, t.targetSets + delta))
        t.targetSets = newSets
        try? modelContext.save()
    }

    private func moveTemplate(from index: Int, direction: Int) {
        let newIndex = index + direction
        guard newIndex >= 0, newIndex < templates.count else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            templates.swapAt(index, newIndex)
            for (i, t) in templates.enumerated() { t.exerciseIndex = i }
            try? modelContext.save()
        }
    }

    private func removeTemplate(_ t: ProgramSessionTemplate) {
        withAnimation {
            templates.removeAll { $0.slotId == t.slotId }
            modelContext.delete(t)
            // Re-index remaining
            for (i, tmpl) in templates.enumerated() { tmpl.exerciseIndex = i }
            try? modelContext.save()
        }
    }

    private func addExerciseToSession(_ exercise: Exercise) {
        let nextIndex = templates.count
        let sessionLetter = String(sessionType.shortLabel.prefix(1))
        let slotId = "\(sessionLetter)\(nextIndex + 1)"

        let newTemplate = ProgramSessionTemplate(
            programId: instance.programId,
            programVersion: 1,
            week: week,
            sessionType: sessionType,
            slotId: slotId,
            exerciseIndex: nextIndex,
            exerciseKey: exercise.exerciseKey,
            role: .accessory,
            isMainLift: false,
            targetSets: 3,
            targetRepsLow: 8,
            targetRepsHigh: 12,
            targetRPE: 8.0,
            restSeconds: 90
        )
        modelContext.insert(newTemplate)
        templates.append(newTemplate)
        try? modelContext.save()
    }

    private func restLabel(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let mins = seconds / 60
        let secs = seconds % 60
        return secs > 0 ? "\(mins):\(String(format: "%02d", secs))" : "\(mins)m"
    }

    @ViewBuilder private func editorPill(label: String, value: String, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            VStack(spacing: 1) {
                Text(value).font(.system(size: 13, weight: .black, design: .rounded)).foregroundColor(.appTextPrimary)
                Text(label).font(.system(size: 8, weight: .bold)).foregroundColor(.appTextDim).kerning(1)
            }.frame(minWidth: 50).padding(.vertical, 8).padding(.horizontal, 3)
        }.buttonStyle(.plain)
    }

    private var pillDivider: some View {
        Divider().frame(height: 30)
    }
}

extension ProgramSessionTemplate: Identifiable {}

// MARK: - Exercise Param Editor
struct ExerciseParamEditor: View {
    let template: ProgramSessionTemplate
    @Binding var setsInput: String
    @Binding var repsLowInput: String
    @Binding var repsHighInput: String
    @Binding var rpeInput: String
    @Binding var restInput: String
    let onSave: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationView {
            ZStack {
                Color.appBG.ignoresSafeArea()
                VStack(spacing: 20) {
                    Text(template.exerciseKey.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.system(size: 16, weight: .black)).foregroundColor(.appTextPrimary).multilineTextAlignment(.center).padding(.top, 8)
                    VStack(spacing: 12) {
                        paramRow(label: "Sets", value: $setsInput, keyboard: .numberPad)
                        Divider().background(Color.appBorder)
                        paramRow(label: "Reps low", value: $repsLowInput, keyboard: .numberPad)
                        Divider().background(Color.appBorder)
                        paramRow(label: "Reps high", value: $repsHighInput, keyboard: .numberPad)
                        Divider().background(Color.appBorder)
                        paramRow(label: "Target RPE", value: $rpeInput, keyboard: .decimalPad)
                        Divider().background(Color.appBorder)
                        paramRow(label: "Rest (sec)", value: $restInput, keyboard: .numberPad)
                    }
                    .padding(16).background(Color.appSurface).cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
                    Text("Changes apply to the seeded Week \(template.week) templates permanently.")
                        .font(.system(size: 11)).foregroundColor(.appTextDim).multilineTextAlignment(.center)
                    Spacer()
                }.padding(20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel", action: onDismiss).foregroundColor(.appTextSecondary) }
                ToolbarItem(placement: .navigationBarTrailing) { Button("Save") { onSave() }.font(.system(size: 14, weight: .black)).foregroundColor(.appRed) }
            }
        }.presentationDetents([.medium])
    }
    @ViewBuilder private func paramRow(label: String, value: Binding<String>, keyboard: UIKeyboardType) -> some View {
        HStack {
            Text(label).font(.system(size: 14, weight: .semibold)).foregroundColor(.appTextSecondary)
            Spacer()
            TextField("", text: value).keyboardType(keyboard).multilineTextAlignment(.trailing)
                .font(.system(size: 18, weight: .black, design: .rounded)).foregroundColor(.appTextPrimary).frame(width: 80)
        }
    }
}

// MARK: - Muscle Coverage
struct MuscleCoverageCard: View {
    let weekLogs: [WorkoutLog]
    let exercises: [Exercise]
    let priorityMuscles: [String]
    let muscleTiers: [String: MuscleTier]
    let experience: ExperienceLevel
    var instance: UserProgramInstance? = nil
    var allTemplates: [ProgramSessionTemplate] = []
    var displayWeek: Int = 1
    var targetOverrides: [String: Int] = [:]
    var onAdjustVolume: ((String) -> Void)? = nil
    private let muscles = ExerciseDictionary.trackingMuscles
    @State private var selectedMuscle: String? = nil

    init(weekLogs: [WorkoutLog], exercises: [Exercise], priorityMuscles: [String], muscleTiers: [String: MuscleTier] = [:], experience: ExperienceLevel = .intermediate, instance: UserProgramInstance? = nil, allTemplates: [ProgramSessionTemplate] = [], displayWeek: Int = 1, targetOverrides: [String: Int] = [:], onAdjustVolume: ((String) -> Void)? = nil) {
        self.weekLogs = weekLogs
        self.exercises = exercises
        self.priorityMuscles = priorityMuscles
        self.experience = experience
        self.muscleTiers = muscleTiers
        self.instance = instance
        self.allTemplates = allTemplates
        self.displayWeek = displayWeek
        self.targetOverrides = targetOverrides
        self.onAdjustVolume = onAdjustVolume
    }

    /// Programmed sets per muscle for the current week from templates + additions + deltas.
    /// This is the PLANNED volume — same metric used by VolumeAdjusterSheet.
    /// Filters out templates whose session has been removed via Configure Program.
    private var programmedSetsByMuscle: [String: Int] {
        guard let inst = instance else { return [:] }
        var result: [String: Int] = [:]
        let activeSessions = activeSessionsForWeek(
            programId: inst.programId, instance: inst, profile: nil, week: displayWeek)
        // Templates for this week, restricted to sessions still on the schedule
        let weekTemplates = allTemplates.filter {
            $0.programId == inst.programId && $0.week == displayWeek &&
            activeSessions.contains($0.sessionType)
        }
        for t in weekTemplates {
            let key = resolveExerciseKey(slotId: t.slotId, originalKey: t.exerciseKey,
                                         overrides: inst.overrides, week: displayWeek)
            let delta = inst.overrides
                .filter { ov in
                    ov.targetSlotId == t.slotId && ov.sessionType == t.sessionType &&
                    ov.setCountDelta != 0 && !ov.isAddition && ov.appliesTo(week: displayWeek)
                }
                .reduce(0) { $0 + $1.setCountDelta }
            let effectiveSets = max(0, t.targetSets + delta)
            if let def = ExerciseDictionary.all[key] {
                for pm in def.primaryMuscles {
                    if let n = ExerciseDictionary.normalizeMuscle(pm) {
                        result[n, default: 0] += effectiveSets
                    }
                }
            } else if let ex = exercises.first(where: { $0.exerciseKey == key }) {
                for pm in ex.musclesPrimary {
                    if let n = ExerciseDictionary.normalizeMuscle(pm) {
                        result[n, default: 0] += effectiveSets
                    }
                }
            }
        }
        // Add isAddition overrides
        for ov in inst.overrides where ov.isAddition && ov.appliesTo(week: displayWeek) {
            let key = ov.replacementExerciseKey
            if let def = ExerciseDictionary.all[key] {
                for pm in def.primaryMuscles {
                    if let n = ExerciseDictionary.normalizeMuscle(pm) {
                        result[n, default: 0] += ov.addedSets
                    }
                }
            } else if let ex = exercises.first(where: { $0.exerciseKey == key }) {
                for pm in ex.musclesPrimary {
                    if let n = ExerciseDictionary.normalizeMuscle(pm) {
                        result[n, default: 0] += ov.addedSets
                    }
                }
            }
        }
        return result
    }

    /// Direct sets only (primaryMuscles at 1.0) — used for zone classification and bar display
    private var directSetsByMuscle: [String: Int] {
        var vol: [String: Double] = [:]
        for log in weekLogs {
            if let def = ExerciseDictionary.all[log.exerciseKey] {
                for pm in def.primaryMuscles {
                    if let n = ExerciseDictionary.normalizeMuscle(pm) { vol[n, default: 0] += 1.0 }
                }
            } else {
                let ex = exercises.first { $0.exerciseKey == log.exerciseKey }
                if let ex = ex {
                    let pri = ex.musclesPrimary.compactMap { ExerciseDictionary.normalizeMuscle($0) }
                    if !pri.isEmpty {
                        for m in pri { vol[m, default: 0] += 1.0 }
                    } else {
                        let name = log.displayName.lowercased()
                        if name.contains("bench") || name.contains("chest") || name.contains("fly") { vol["Chest", default: 0] += 1.0 }
                        else if name.contains("row") || name.contains("pull") || name.contains("lat") || name.contains("back") { vol["Back", default: 0] += 1.0 }
                        else if name.contains("squat") || name.contains("leg press") || name.contains("lunge") { vol["Quads", default: 0] += 1.0 }
                        else if name.contains("curl") && !name.contains("leg") { vol["Biceps", default: 0] += 1.0 }
                        else if name.contains("tricep") || name.contains("pushdown") || name.contains("skull") { vol["Triceps", default: 0] += 1.0 }
                        else if name.contains("shoulder") || name.contains("delt") || name.contains("lateral") { vol["Delts", default: 0] += 1.0 }
                    }
                }
            }
        }
        return vol.mapValues { Int(round($0)) }
    }

    /// Effective sets (primary + weighted secondary) — used for informational display only
    private var effectiveSetsByMuscle: [String: Int] {
        var vol: [String: Double] = [:]
        for log in weekLogs {
            if let def = ExerciseDictionary.all[log.exerciseKey] {
                for pm in def.primaryMuscles {
                    if let n = ExerciseDictionary.normalizeMuscle(pm) { vol[n, default: 0] += 1.0 }
                }
                for sm in def.secondaryMuscles {
                    if let n = ExerciseDictionary.normalizeMuscle(sm.muscle) { vol[n, default: 0] += sm.weight }
                }
            } else {
                let ex = exercises.first { $0.exerciseKey == log.exerciseKey }
                if let ex = ex {
                    let pri = ex.musclesPrimary.compactMap { ExerciseDictionary.normalizeMuscle($0) }
                    let sec = ex.musclesSecondary.compactMap { ExerciseDictionary.normalizeMuscle($0) }
                    for m in pri { vol[m, default: 0] += 1.0 }
                    for m in sec where !pri.contains(m) { vol[m, default: 0] += IndirectVolumeMap.secondaryWeight }
                }
            }
        }
        return vol.mapValues { Int(round($0)) }
    }

    private func tier(for muscle: String) -> MuscleTier {
        muscleTiers[muscle] ?? (priorityMuscles.contains(muscle) ? .priority : .neutral)
    }

    private func landmark(for muscle: String) -> VolumeLandmark {
        let t = tier(for: muscle)
        let mev = VolumeLandmark.effectiveMEV(muscle: muscle, experience: experience, tier: t)
        let mrv = VolumeLandmark.effectiveMRV(muscle: muscle, experience: experience, tier: t)
        let base = VolumeLandmark.defaults[muscle] ?? VolumeLandmark(mev: 4, mavLow: 8, mavHigh: 12, mrv: 18)
        let scaled = base.scaled(by: t)
        // User's custom target replaces mavHigh if set; mavLow shifts to keep range coherent
        if let custom = targetOverrides[muscle], custom > 0 {
            let mavLow = max(mev, min(scaled.mavLow, custom - 4))
            return VolumeLandmark(mev: mev, mavLow: mavLow, mavHigh: custom, mrv: max(mrv, custom))
        }
        return VolumeLandmark(mev: mev, mavLow: scaled.mavLow, mavHigh: scaled.mavHigh, mrv: mrv)
    }

    private func zoneColor(_ zone: VolumeZone) -> Color {
        switch zone {
        case .underTraining: return .appRed
        case .building:      return .appYellow
        case .optimal:       return .appGreen
        case .overReaching:  return .appOrange
        }
    }

    private var zoneCounts: (optimal: Int, building: Int, lagging: Int, over: Int) {
        var o = 0, b = 0, l = 0, v = 0
        for muscle in muscles {
            let sets = directSetsByMuscle[muscle] ?? 0
            let lm = landmark(for: muscle)
            switch VolumeZone.classify(sets: sets, landmark: lm) {
            case .optimal: o += 1
            case .building: b += 1
            case .underTraining: l += 1
            case .overReaching: v += 1
            }
        }
        return (o, b, l, v)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                SectionHeader(title: "WEEKLY MUSCLE COVERAGE")
                Spacer()
                Text("Logged this week").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim).kerning(0.5)
            }

            let counts = zoneCounts
            HStack(spacing: 6) {
                if counts.optimal > 0 {
                    Text("\(counts.optimal) optimal").font(.system(size: 11, weight: .bold)).foregroundColor(.appGreen)
                }
                if counts.building > 0 {
                    Text("· \(counts.building) building").font(.system(size: 11, weight: .bold)).foregroundColor(.appYellow)
                }
                if counts.lagging > 0 {
                    Text("· \(counts.lagging) lagging").font(.system(size: 11, weight: .bold)).foregroundColor(.appRed)
                }
                if counts.over > 0 {
                    Text("· \(counts.over) over").font(.system(size: 11, weight: .bold)).foregroundColor(.appOrange)
                }
                Spacer()
                Text("\(weekLogs.count) sets").font(.system(size: 11)).foregroundColor(.appTextDim)
            }

            LazyVGrid(columns: [GridItem(.flexible()),GridItem(.flexible()),GridItem(.flexible())], spacing: 8) {
                ForEach(muscles, id: \.self) { muscle in
                    // Coverage = sets logged this week (progress tracker)
                    let sets = directSetsByMuscle[muscle] ?? 0
                    let lm = landmark(for: muscle)
                    let zone = VolumeZone.classify(sets: sets, landmark: lm)
                    let color = zoneColor(zone)
                    let t = tier(for: muscle)
                    let fillFraction = lm.mrv > 0 ? min(Double(sets) / Double(lm.mrv), 1.2) : 0
                    let clampedFill = min(fillFraction, 1.0)

                    VStack(spacing: 5) {
                        HStack(spacing: 3) {
                            Text(muscle).font(.system(size: 9, weight: .black)).foregroundColor(color).lineLimit(1).minimumScaleFactor(0.7)
                            if t == .priority { Text("★").font(.system(size: 8)).foregroundColor(.appGold) }
                            if t == .maintenance { Text("▽").font(.system(size: 7)).foregroundColor(.appTextDim) }
                            if zone == .underTraining && sets > 0 {
                                Text("LOW").font(.system(size: 6, weight: .black)).foregroundColor(.appRed)
                            }
                        }
                        GeometryReader { geo in
                            let w = geo.size.width
                            let mevPos = lm.mrv > 0 ? CGFloat(lm.mev) / CGFloat(lm.mrv) * w : 0
                            let mavLowPos = lm.mrv > 0 ? CGFloat(lm.mavLow) / CGFloat(lm.mrv) * w : 0
                            let mrvPos = w
                            ZStack(alignment: .leading) {
                                // Track
                                RoundedRectangle(cornerRadius: 3).fill(Color.appSurface2).frame(height: 6)
                                // Fill
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(color)
                                    .frame(width: w * CGFloat(clampedFill), height: 6)
                                    .animation(.easeOut(duration: 0.5), value: clampedFill)
                                // MEV marker
                                Rectangle().fill(Color.appTextDim.opacity(0.5)).frame(width: 1, height: 8)
                                    .offset(x: mevPos)
                                // MAV-low marker (start of optimal zone)
                                Rectangle().fill(Color.appGreen.opacity(0.3)).frame(width: 1, height: 8)
                                    .offset(x: mavLowPos)
                                // MRV marker
                                Rectangle().fill(Color.appOrange.opacity(0.4)).frame(width: 1, height: 8)
                                    .offset(x: mrvPos - 1)
                            }
                        }.frame(height: 8)
                        let effective = effectiveSetsByMuscle[muscle] ?? 0
                        let indirect = effective - sets
                        if indirect >= 1 {
                            Text("\(sets)+\(indirect)").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundColor(color)
                        } else {
                            Text("\(sets)/\(lm.mav)").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(color)
                        }
                    }
                    .padding(8)
                    .background(zone == .optimal ? color.opacity(0.06) : Color.appSurface)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(zone == .optimal ? color.opacity(0.3) : Color.appBorder, lineWidth: 1))
                    .onTapGesture {
                        if let cb = onAdjustVolume { cb(muscle) }
                        else { selectedMuscle = muscle }
                    }
                }
            }

            // Volume zone legend
            HStack(spacing: 12) {
                legendDot(color: .appRed, label: "<MEV")
                legendDot(color: .appYellow, label: "Building")
                legendDot(color: .appGreen, label: "Optimal")
                legendDot(color: .appOrange, label: ">MRV")
            }
            .padding(.top, 4)
        }
        .sheet(item: $selectedMuscle) { muscle in
            MuscleDetailSheet(muscle: muscle, sets: directSetsByMuscle[muscle] ?? 0,
                              landmark: landmark(for: muscle), tier: tier(for: muscle),
                              weekLogs: weekLogs)
                .presentationDetents([.medium])
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label).font(.system(size: 8, weight: .medium)).foregroundColor(.appTextDim)
        }
    }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}

// ═══════════════════════════════════════════
// MUSCLE DETAIL SHEET
// ═══════════════════════════════════════════

struct MuscleDetailSheet: View {
    let muscle: String
    let sets: Int
    let landmark: VolumeLandmark
    let tier: MuscleTier
    let weekLogs: [WorkoutLog]

    private var zone: VolumeZone { VolumeZone.classify(sets: sets, landmark: landmark) }

    private var indirectSetsThisWeek: Double {
        var indirect = 0.0
        for log in weekLogs {
            guard let def = ExerciseDictionary.all[log.exerciseKey] else { continue }
            // Only count if this muscle is SECONDARY (not primary)
            let isPrimary = def.primaryMuscles.contains(where: { ExerciseDictionary.normalizeMuscle($0) == muscle })
            if isPrimary { continue }
            for sm in def.secondaryMuscles {
                if ExerciseDictionary.normalizeMuscle(sm.muscle) == muscle {
                    indirect += sm.weight
                }
            }
        }
        return indirect
    }
    private var zoneColor: Color {
        switch zone {
        case .underTraining: return .appRed
        case .building: return .appYellow
        case .optimal: return .appGreen
        case .overReaching: return .appOrange
        }
    }

    private var exercisesThisWeek: [(name: String, sets: Int)] {
        var counts: [String: Int] = [:]
        for log in weekLogs {
            // Check static dictionary first
            if let def = ExerciseDictionary.all[log.exerciseKey] {
                if def.primaryMuscles.contains(where: { ExerciseDictionary.normalizeMuscle($0) == muscle }) {
                    counts[log.displayName, default: 0] += 1
                }
            } else {
                // Custom exercise — try to match by display name keywords
                let name = log.displayName.lowercased()
                let matches: Bool = switch muscle {
                case "Chest": name.contains("bench") || name.contains("chest") || name.contains("fly") || name.contains("pec")
                case "Back": name.contains("row") || name.contains("pull") || name.contains("lat") || name.contains("back") || name.contains("deadlift")
                case "Quads": name.contains("squat") || name.contains("leg press") || name.contains("lunge") || name.contains("quad") || name.contains("extension")
                case "Hamstrings": name.contains("curl") && name.contains("leg") || name.contains("rdl") || name.contains("hamstring") || name.contains("deadlift") && name.contains("romanian")
                case "Glutes": name.contains("hip thrust") || name.contains("glute") || name.contains("kickback")
                case "Calves": name.contains("calf") || name.contains("raise") && name.contains("calf")
                case "Biceps": name.contains("curl") && !name.contains("leg") && !name.contains("ham")
                case "Triceps": name.contains("tricep") || name.contains("pushdown") || name.contains("skull") || name.contains("close grip")
                case "Delts": name.contains("shoulder") || name.contains("delt") || name.contains("lateral raise") || name.contains("ohp") || name.contains("press") && name.contains("shoulder")
                default: false
                }
                if matches { counts[log.displayName, default: 0] += 1 }
            }
        }
        return counts.sorted { $0.value > $1.value }.map { (name: $0.key, sets: $0.value) }
    }

    var body: some View {
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 3).fill(Color.appBorder).frame(width: 36, height: 4).padding(.top, 12)

            // Header
            HStack {
                Text(muscle.uppercased()).font(.system(size: 20, weight: .black)).foregroundColor(.appTextPrimary)
                if tier == .priority {
                    Text("PRIORITY").font(.system(size: 9, weight: .black)).foregroundColor(.appGold)
                        .padding(.horizontal, 6).padding(.vertical, 3).background(Color.appGold.opacity(0.12)).cornerRadius(4)
                } else if tier == .maintenance {
                    Text("MAINTENANCE").font(.system(size: 9, weight: .black)).foregroundColor(.appTextDim)
                        .padding(.horizontal, 6).padding(.vertical, 3).background(Color.appSurface2).cornerRadius(4)
                }
                Spacer()
            }

            // Volume status
            HStack(spacing: 20) {
                VStack(spacing: 3) {
                    Text("\(sets)").font(.system(size: 32, weight: .black, design: .rounded)).foregroundColor(zoneColor)
                    Text("SETS THIS WEEK").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim).kerning(0.5)
                }
                VStack(alignment: .leading, spacing: 6) {
                    thresholdRow("MV", value: VolumeLandmark.mv(muscle: muscle), desc: "Maintenance")
                    thresholdRow("MEV", value: landmark.mev, desc: "Min effective")
                    thresholdRow("MAV", value: landmark.mav, desc: "Target zone")
                    thresholdRow("MRV", value: landmark.mrv, desc: "Max recoverable")
                }
            }
            .padding(14).background(Color.appSurface).cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))

            // Zone badge
            HStack {
                Circle().fill(zoneColor).frame(width: 8, height: 8)
                Text(zone.rawValue).font(.system(size: 13, weight: .bold)).foregroundColor(zoneColor)
                Spacer()
                Text(zoneAdvice).font(.system(size: 12)).foregroundColor(.appTextSecondary)
            }
            .padding(12).background(zoneColor.opacity(0.06)).cornerRadius(10)

            // Indirect volume
            let indirect = indirectSetsThisWeek
            if indirect > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 12)).foregroundColor(.appBlue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("+\(String(format: "%.1f", indirect)) indirect sets from compound exercises")
                            .font(.system(size: 12, weight: .bold)).foregroundColor(.appBlue)
                        Text("Effective total: ~\(sets + Int(indirect.rounded())) sets this week")
                            .font(.system(size: 11)).foregroundColor(.appTextDim)
                    }
                }
                .padding(10).background(Color.appBlue.opacity(0.04)).cornerRadius(8)
            }

            // Exercises this week
            if !exercisesThisWeek.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("EXERCISES THIS WEEK").font(.system(size: 10, weight: .bold)).foregroundColor(.appTextDim).kerning(1)
                    ForEach(exercisesThisWeek, id: \.name) { ex in
                        HStack {
                            Text(ex.name).font(.system(size: 13, weight: .semibold)).foregroundColor(.appTextPrimary)
                            Spacer()
                            Text("\(ex.sets) sets").font(.system(size: 12, weight: .bold)).foregroundColor(.appTextSecondary)
                        }
                    }
                }
                .padding(12).background(Color.appSurface).cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .background(Color.appBG)
    }

    private func thresholdRow(_ label: String, value: Int, desc: String) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).frame(width: 30, alignment: .leading)
            Text("\(value)").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(.appTextPrimary)
            Text(desc).font(.system(size: 10)).foregroundColor(.appTextDim)
        }
    }

    private var zoneAdvice: String {
        switch zone {
        case .underTraining: return "Add more sets to stimulate growth"
        case .building: return "Approaching effective range"
        case .optimal: return "Sweet spot for growth"
        case .overReaching: return "Consider reducing volume"
        }
    }
}

// MARK: - Load Consistency Card
struct ACWRCard: View {
    let logs: [WorkoutLog]

    private var acwr: Double? { ProgressionEngine.computeACWR(logs: logs) }

    private var acwrLabel: String {
        guard let v = acwr else { return "—" }
        return String(format: "%.2f", v)
    }

    private var acwrZone: (label: String, color: Color) {
        guard let v = acwr else { return ("Insufficient Data", .appTextDim) }
        if v < 0.8 { return ("Ramping Down", .appBlue) }
        if v <= 1.3 { return ("Consistent", .appGreen) }
        if v <= 1.5 { return ("Ramping Up", .appYellow) }
        return ("Big Spike", .appOrange)
    }

    var body: some View {
        if acwr != nil {
            VStack(spacing: 8) {
                HStack {
                    Text("LOAD CONSISTENCY").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(1.5)
                    Spacer()
                    Text("7d vs 28d avg").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim)
                }
                HStack(alignment: .bottom, spacing: 8) {
                    Text(acwrLabel)
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundColor(acwrZone.color)
                    Text(acwrZone.label)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(acwrZone.color)
                    Spacer()
                }
                // Visual range bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Background zones
                        HStack(spacing: 0) {
                            Color.appBlue.opacity(0.15).frame(width: geo.size.width * 0.35)
                            Color.appGreen.opacity(0.15).frame(width: geo.size.width * 0.30)
                            Color.appYellow.opacity(0.15).frame(width: geo.size.width * 0.15)
                            Color.appOrange.opacity(0.15).frame(width: geo.size.width * 0.20)
                        }
                        .cornerRadius(4)
                        // Marker
                        if let v = acwr {
                            let clamped = max(0, min(v / 2.0, 1.0))
                            Circle().fill(acwrZone.color).frame(width: 10, height: 10)
                                .offset(x: geo.size.width * clamped - 5)
                        }
                    }
                }.frame(height: 10)
                HStack {
                    Text("0.8").font(.system(size: 8)).foregroundColor(.appTextDim)
                    Spacer()
                    Text("1.3").font(.system(size: 8)).foregroundColor(.appTextDim)
                    Spacer()
                    Text("1.5").font(.system(size: 8)).foregroundColor(.appTextDim)
                }
            }
            .padding(14).appCard()
        }
    }
}

// MARK: - Supporting Views
struct RecentPRRow: View {
    let log: WorkoutLog; let useMetric: Bool
    private var relativeDate: String {
        if Calendar.current.isDateInToday(log.date) { return "Today" }
        if Calendar.current.isDateInYesterday(log.date) { return "Yesterday" }
        let f = DateFormatter(); f.dateFormat = "EEE MMM d"; return f.string(from: log.date)
    }
    var body: some View {
        HStack(spacing: 12) {
            ZStack { RoundedRectangle(cornerRadius: 8).fill(Color.appGold.opacity(0.12)).frame(width: 38, height: 38); Image(systemName: "bolt.fill").font(.system(size: 16)).foregroundColor(.appGold) }
            VStack(alignment: .leading, spacing: 3) {
                Text(log.displayName).font(.system(size: 13, weight: .black)).foregroundColor(.appTextPrimary)
                Text("\(String(format: "%.0f", log.weight)) \(useMetric ? "kg" : "lbs") × \(log.reps) reps").font(.system(size: 12)).foregroundColor(.appTextSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(relativeDate).font(.system(size: 10)).foregroundColor(.appTextDim)
                Text("e1RM \(String(format: "%.0f", log.e1rm))").font(.system(size: 10, weight: .bold)).foregroundColor(.appGold)
            }
        }.padding(.horizontal, 14).padding(.vertical, 10).appCard()
    }
}

struct RecentSessionsList: View {
    @Environment(\.modelContext) private var modelContext
    let instance: UserProgramInstance?
    let allInstances: [UserProgramInstance]
    @State private var editingSession: (date: Date, logs: [WorkoutLog])? = nil

    private var sessions: [(date: Date, sessionTypeRaw: String, setCount: Int, logs: [WorkoutLog], sessionNotes: String, duration: TimeInterval?)] {
        // Pull from ALL instances so past program sessions are visible
        let allLogs = allInstances.flatMap { $0.logs }
        guard !allLogs.isEmpty else { return [] }
        let byDay = Dictionary(grouping: allLogs) { Calendar.current.startOfDay(for: $0.workoutDate) }
        return byDay.sorted { $0.key > $1.key }.prefix(8).map {
            let sortedLogs = $0.value.sorted { $0.exerciseKey == $1.exerciseKey ? $0.setIndex < $1.setIndex : $0.exerciseKey < $1.exerciseKey }
            let notes = $0.value.first(where: { !$0.sessionNotes.isEmpty })?.sessionNotes ?? ""
            let dates = $0.value.map { $0.date }
            let duration: TimeInterval? = dates.count >= 2 ? dates.max()!.timeIntervalSince(dates.min()!) : nil
            return (date: $0.key, sessionTypeRaw: $0.value.first?.sessionTypeRaw ?? "", setCount: $0.value.count, logs: sortedLogs, sessionNotes: notes, duration: duration)
        }
    }
    var body: some View {
        VStack(spacing: 10) {
            SectionHeader(title: "RECENT SESSIONS")
            if sessions.isEmpty {
                HStack(spacing: 14) {
                    Image(systemName: "dumbbell.fill").font(.system(size: 22)).foregroundColor(.appTextDim)
                    VStack(alignment: .leading, spacing: 4) { Text("No workouts yet").font(.system(size: 14, weight: .bold)).foregroundColor(.appTextSecondary); Text("Hit Train to log your first session").font(.system(size: 12)).foregroundColor(.appTextDim) }
                    Spacer()
                }.padding(16).appCard()
            } else {
                ForEach(sessions, id: \.date) { s in
                    RecentSessionRow(date: s.date, sessionTypeRaw: s.sessionTypeRaw, setCount: s.setCount, sessionNotes: s.sessionNotes, duration: s.duration)
                        .onTapGesture { editingSession = (date: s.date, logs: s.logs) }
                        .contextMenu {
                            Button { editingSession = (date: s.date, logs: s.logs) } label: {
                                Label("Edit Session", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                deleteSession(logs: s.logs)
                            } label: {
                                Label("Delete Session", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .sheet(item: Binding(
            get: { editingSession.map { EditableSession(date: $0.date, logs: $0.logs) } },
            set: { if $0 == nil { editingSession = nil } }
        )) { session in
            WorkoutLogEditorSheet(logs: session.logs, workoutDate: session.date, onDismiss: { editingSession = nil })
        }
    }

    private func deleteSession(logs: [WorkoutLog]) {
        guard let inst = instance else { return }
        for log in logs {
            if let idx = inst.logs.firstIndex(where: { $0.id == log.id }) {
                inst.logs.remove(at: idx)
            }
            modelContext.delete(log)
        }
        try? modelContext.save()
    }
}

struct EditableSession: Identifiable {
    let id: Date
    let date: Date
    let logs: [WorkoutLog]
    init(date: Date, logs: [WorkoutLog]) { self.id = date; self.date = date; self.logs = logs }
}

// ═══════════════════════════════════════════
// WORKOUT LOG EDITOR SHEET
// ═══════════════════════════════════════════

struct WorkoutLogEditorSheet: View {
    let logs: [WorkoutLog]
    let workoutDate: Date
    let onDismiss: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var notesText: String = ""
    @State private var historyExerciseKey: String? = nil
    @State private var historyExerciseName: String? = nil
    @State private var showExerciseHistory = false

    private var byExercise: [(key: String, name: String, sets: [WorkoutLog])] {
        let grouped = Dictionary(grouping: logs) { $0.exerciseKey }
        return grouped.sorted { $0.key < $1.key }.map { (key: $0.key, name: $0.value.first?.displayName ?? $0.key, sets: $0.value.sorted { $0.setIndex < $1.setIndex }) }
    }

    private var dateLabel: String {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"; return f.string(from: workoutDate)
    }

    var body: some View {
        ZStack {
            Color.appBG.ignoresSafeArea()
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 3).fill(Color.appBorder)
                    .frame(width: 36, height: 4).padding(.top, 12)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("EDIT WORKOUT")
                            .font(.system(size: 11, weight: .bold)).foregroundColor(.appRed).kerning(2)
                        Text(dateLabel)
                            .font(.system(size: 18, weight: .black, design: .rounded)).foregroundColor(.appTextPrimary)
                        Text("\(logs.count) sets logged")
                            .font(.system(size: 12)).foregroundColor(.appTextSecondary)
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
                    VStack(spacing: 20) {
                        ForEach(byExercise, id: \.key) { exercise in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 8) {
                                    Text(exercise.name)
                                        .font(.system(size: 15, weight: .black)).foregroundColor(.appTextPrimary)
                                        .onTapGesture {
                                            historyExerciseKey = exercise.key
                                            historyExerciseName = exercise.name
                                            showExerciseHistory = true
                                        }
                                    Text("\(exercise.sets.count) sets")
                                        .font(.system(size: 10, weight: .bold)).foregroundColor(.appTextDim)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.appSurface2).cornerRadius(4)
                                }
                                ForEach(exercise.sets, id: \.setIndex) { log in
                                    EditableSetRow(log: log, onSave: {
                                        try? modelContext.save()
                                    })
                                }
                            }
                            .padding(14)
                            .background(Color.appSurface)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
                        }

                        // Session notes
                        VStack(alignment: .leading, spacing: 6) {
                            Text("SESSION NOTES")
                                .font(.system(size: 10, weight: .bold)).foregroundColor(.appTextDim).kerning(1.5)
                            TextField("Add notes about this session...", text: $notesText, axis: .vertical)
                                .font(.system(size: 14)).foregroundColor(.appTextPrimary)
                                .lineLimit(3...6)
                                .padding(10)
                                .background(Color.appSurface2).cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorder, lineWidth: 1))
                        }
                        .padding(14)
                        .background(Color.appSurface)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
                    }
                    .padding(16).padding(.bottom, 40)
                }
                .onAppear {
                    notesText = logs.first(where: { !$0.sessionNotes.isEmpty })?.sessionNotes ?? ""
                }

                VStack(spacing: 0) {
                    Divider().background(Color.appBorder)
                    PrimaryButton(title: "DONE", icon: "checkmark") {
                        // Save session notes
                        let trimmed = notesText.trimmingCharacters(in: .whitespacesAndNewlines)
                        // Clear old notes, set on first log
                        logs.forEach { $0.sessionNotes = "" }
                        if !trimmed.isEmpty { logs.first?.sessionNotes = trimmed }
                        try? modelContext.save()
                        onDismiss()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14).background(Color.appBG)
                }
            }
        }
        .sheet(isPresented: $showExerciseHistory) {
            if let key = historyExerciseKey, let name = historyExerciseName {
                ExerciseHistorySheet(exerciseKey: key, displayName: name)
            }
        }
    }
}

struct EditableSetRow: View {
    @ObservedObject private var wrapper: LogWrapper
    let onSave: () -> Void

    init(log: WorkoutLog, onSave: @escaping () -> Void) {
        self.wrapper = LogWrapper(log: log)
        self.onSave = onSave
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("Set \(wrapper.log.setIndex + 1)")
                .font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(.appTextDim)
                .frame(width: 42)

            HStack(spacing: 4) {
                TextField("lbs", text: $wrapper.weightText)
                    .font(.system(size: 14, weight: .bold)).foregroundColor(.appTextPrimary)
                    .keyboardType(.decimalPad)
                    .frame(width: 55)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 6).padding(.horizontal, 4)
                    .background(Color.appSurface2).cornerRadius(6)
                    .onChange(of: wrapper.weightText) { _, val in
                        if let w = Double(val) { wrapper.log.weight = w; wrapper.log.recomputeE1RM(); onSave() }
                    }
                Text("×").font(.system(size: 12)).foregroundColor(.appTextDim)
                TextField("reps", text: $wrapper.repsText)
                    .font(.system(size: 14, weight: .bold)).foregroundColor(.appTextPrimary)
                    .keyboardType(.numberPad)
                    .frame(width: 40)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 6).padding(.horizontal, 4)
                    .background(Color.appSurface2).cornerRadius(6)
                    .onChange(of: wrapper.repsText) { _, val in
                        if let r = Int(val) { wrapper.log.reps = r; wrapper.log.recomputeE1RM(); onSave() }
                    }
            }

            Spacer()

            HStack(spacing: 4) {
                Text("RPE").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim)
                TextField("", text: $wrapper.rpeText)
                    .font(.system(size: 13, weight: .bold)).foregroundColor(.appRed)
                    .keyboardType(.decimalPad)
                    .frame(width: 35)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 6).padding(.horizontal, 4)
                    .background(Color.appRed.opacity(0.08)).cornerRadius(6)
                    .onChange(of: wrapper.rpeText) { _, val in
                        if let rpe = Double(val) { wrapper.log.rpe = rpe; onSave() }
                    }
            }
        }
    }
}

/// Observable wrapper around a WorkoutLog for inline editing
class LogWrapper: ObservableObject {
    let log: WorkoutLog
    @Published var weightText: String
    @Published var repsText: String
    @Published var rpeText: String

    init(log: WorkoutLog) {
        self.log = log
        self.weightText = log.weight > 0 ? String(format: "%g", log.weight) : ""
        self.repsText = log.reps > 0 ? "\(log.reps)" : ""
        self.rpeText = log.rpe > 0 ? String(format: "%g", log.rpe) : ""
    }
}

// MARK: - Bahri Program Def + Extensions

extension SessionType {
    var shortLabel: String {
        switch self {
        case .heavyUpper:       return "HEAVY UPPER"
        case .heavyLower:       return "HEAVY LOWER"
        case .hypertrophyUpper: return "HYPERTROPHY UPPER"
        case .hypertrophyLower: return "HYPERTROPHY LOWER"
        case .legQuadFocus:     return "LEGS — QUAD FOCUS"
        case .legsPosterior:    return "LEGS — POSTERIOR"
        case .chestBack:        return "CHEST & BACK"
        case .armsDelts:        return "ARMS & DELTS"
        case .chestArms:        return "CHEST & ARMS"
        case .legsVolume:       return "LEGS — VOLUME"
        case .pushA:            return "PUSH A"
        case .pushB:            return "PUSH B"
        case .pullA:            return "PULL A"
        case .pullB:            return "PULL B"
        case .legsA:            return "LEGS A"
        case .legsB:            return "LEGS B"
        case .freeform:         return "FREESTYLE"
        default:                return rawValue.uppercased()
        }
    }
}

struct TodaySessionCard: View {
    let sessionType: SessionType?
    var body: some View {
        VStack(spacing: 10) {
            SectionHeader(title: "TODAY")
            HStack(spacing: 0) {
                Rectangle().frame(width: 3).foregroundColor(accent).cornerRadius(2)
                VStack(alignment: .leading, spacing: 5) {
                    Text(sessionType?.shortLabel ?? "REST DAY").font(.system(size: 18, weight: .black, design: .rounded)).foregroundColor(.appTextPrimary)
                    Text(sessionType?.muscleSubtitle ?? "Recovery is part of the program").font(.system(size: 13, weight: .medium)).foregroundColor(.appTextSecondary)
                }.padding(.leading, 12)
                Spacer()
                Image(systemName: icon).font(.system(size: 22)).foregroundColor(accent.opacity(0.7))
            }.padding(16).appCard(glowRed: sessionType != nil)
        }
    }
    private var icon: String {
        switch sessionType {
        case .heavyUpper, .hypertrophyUpper, .chestBack, .chestArms, .armsDelts: return "figure.arms.open"
        case .heavyLower, .hypertrophyLower, .legQuadFocus, .legsPosterior, .legsVolume: return "figure.strengthtraining.traditional"
        default: return "moon.fill"
        }
    }
    private var accent: Color { sessionType != nil ? .appRed : .appTextDim }
}

struct RecentSessionRow: View {
    let date: Date; let sessionTypeRaw: String; let setCount: Int
    var sessionNotes: String = ""
    var duration: TimeInterval? = nil
    private var label: String { SessionType(rawValue: sessionTypeRaw)?.shortLabel ?? sessionTypeRaw.uppercased() }
    private var sessionColor: Color { SessionType(rawValue: sessionTypeRaw)?.sessionColor ?? .appRed }
    private var relativeDate: String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter(); f.dateFormat = "EEE MMM d"; return f.string(from: date)
    }
    private var durationLabel: String? {
        guard let dur = duration, dur > 0 else { return nil }
        let mins = Int(dur / 60)
        if mins < 60 { return "\(mins)m" }
        return "\(mins / 60)h \(mins % 60)m"
    }
    var body: some View {
        HStack(spacing: 0) {
            // UI-3: Session color bar
            RoundedRectangle(cornerRadius: 2)
                .fill(sessionColor)
                .frame(width: 4, height: 38)
                .padding(.trailing, 10)

            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.system(size: 13, weight: .black)).foregroundColor(.appTextPrimary).kerning(0.5)
                HStack(spacing: 6) {
                    Text(relativeDate).font(.system(size: 11)).foregroundColor(.appTextDim)
                    // UI-4: Workout duration
                    if let durLabel = durationLabel {
                        Text("·").font(.system(size: 11)).foregroundColor(.appTextDim)
                        Text(durLabel).font(.system(size: 11, weight: .semibold)).foregroundColor(.appTextSecondary)
                    }
                }
                // Feature 5: Session notes preview
                if !sessionNotes.isEmpty {
                    Text(sessionNotes)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.appTextSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(setCount) sets").font(.system(size: 12, weight: .bold)).foregroundColor(.appTextSecondary)
                Image(systemName: "pencil").font(.system(size: 9)).foregroundColor(.appTextDim)
            }
        }.padding(.horizontal, 14).padding(.vertical, 10).appCard()
    }
}

struct WeeklyVolumeChart: View {
    let volumeSets: [String: Int]
    private let muscles = ExerciseDictionary.trackingMuscles.map { $0.uppercased() }
    private let maxSets = 20
    var body: some View {
        HStack(spacing: 8) {
            ForEach(muscles, id: \.self) { muscle in
                let sets = volumeSets[muscle] ?? 0
                let fill = min(Double(sets) / Double(maxSets), 1.0)
                VStack(spacing: 6) {
                    Text("\(sets)").font(.system(size: 10, weight: .bold)).foregroundColor(sets > 0 ? .appRed : .appTextDim)
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 4).fill(Color.appSurface2).frame(width: 36, height: 60)
                        RoundedRectangle(cornerRadius: 4).fill(sets > 0 ? Color.appRed.opacity(0.75) : Color.appRed.opacity(0.1))
                            .frame(width: 36, height: max(CGFloat(fill) * 60, sets > 0 ? 4 : 0)).animation(.easeOut(duration: 0.5), value: fill)
                    }
                    Text(muscle).font(.system(size: 8, weight: .bold)).foregroundColor(.appTextDim).kerning(0.5)
                }.frame(maxWidth: .infinity)
            }
        }.padding(16).appCard()
    }
}

// ═══════════════════════════════════════════
// BLOCK INFO SHEET
// Shows mesocycle context when tapped
// ═══════════════════════════════════════════

// ═══════════════════════════════════════════
// WEEK OVERVIEW SHEET
// Shows all weeks, what's ahead, navigate between them
// ═══════════════════════════════════════════

struct WeekOverviewSheet: View {
    let instance: UserProgramInstance?
    let profile: UserProfile?
    let displayWeek: Int
    let onSelectWeek: (Int) -> Void
    let onSetWeek: (Int) -> Void

    @State private var expandedWeek: Int? = nil

    private var goal: GoalType { profile?.goal ?? .hypertrophy }
    private var isHyp: Bool { goal == .hypertrophy || goal == .recomp }
    private var bl: Int { max(instance?.blockLength ?? 5, 1) }
    private var currentWeek: Int { instance?.currentWeek ?? 1 }
    private var cycleLen: Int { bl + 1 }

    private var totalWeeks: Int {
        if let inst = instance, inst.isGenerated { return cycleLen * 4 }
        if instance?.programId == 2 { return 16 }
        return 24
    }

    private func posInBlock(_ w: Int) -> Int { ((w - 1) % cycleLen) + 1 }
    private func blockNum(_ w: Int) -> Int { (w - 1) / cycleLen }
    private func isRecoveryWeek(_ w: Int) -> Bool {
        if let inst = instance, inst.isGenerated { return posInBlock(w) > bl }
        if instance?.programId == 2 { return [4, 12, 16].contains(w) }
        return [4, 12, 20].contains(w)
    }

    private func phaseName(_ w: Int) -> String {
        if isRecoveryWeek(w) { return isHyp ? "Recovery" : "Deload" }
        if let inst = instance, inst.isGenerated {
            let bn = blockNum(w)
            if isHyp { return bn % 2 == 0 ? "Training Block" : "Growth Phase" }
            switch goal {
            case .strength: return bn == 0 ? "Accumulation" : (bn == 1 ? "Intensification" : "Peaking")
            case .powerbuilding: return bn % 3 == 0 ? "Accumulation" : (bn % 3 == 1 ? "Intensification" : "Volume Phase")
            default: return "Training"
            }
        }
        // Seeded
        if instance?.programId == 2 {
            return w <= 8 ? (isHyp ? "Training Block" : "Accumulation") : (isHyp ? "Growth Phase" : "Intensification")
        }
        if w <= 8 { return isHyp ? "Training Block" : "Accumulation" }
        if w <= 16 { return isHyp ? "Growth Phase" : "Intensification" }
        return isHyp ? "Training Block" : "Peaking"
    }

    private func weekTitle(_ w: Int) -> String {
        let pos = posInBlock(w)
        let phase = phaseName(w)
        if isRecoveryWeek(w) { return "Recovery Week" }
        if phase == "Growth Phase" {
            if pos == 1 { return "Growth Phase Begins" }
            if pos == bl { return "Final Push — Growth Phase" }
            return "Growth Phase — Week \(pos)"
        }
        if pos == 1 { return isHyp ? "New Block Starts" : "\(phase) Begins" }
        if pos == bl { return "Final Week Before Recovery" }
        return isHyp ? "Training Week \(pos)" : "\(phase) — Week \(pos)"
    }

    private func weekDetail(_ w: Int) -> String {
        let pos = posInBlock(w)
        let phase = phaseName(w)

        if isRecoveryWeek(w) {
            return "Drop to maintenance volume. Use lighter weights — around 50-60% of your working loads. Focus on movement quality and full range of motion. This week resets accumulated fatigue so you can push harder in the next block."
        }

        if isHyp {
            let isGrowth = phase == "Growth Phase"
            switch pos {
            case 1:
                if isGrowth {
                    return "Volume increases ~15% from your last training block. Your body is recovered and primed for growth. Start with the same weights as your last block's early weeks — the extra sets are the new stimulus, not heavier weight."
                }
                return "Start of a new training block. Establish your working weights across all exercises. Focus on nailing your rep targets with good form before chasing heavier loads. This is your baseline for the block."
            case 2:
                return "You should have your working weights locked in. This week, aim to match or slightly beat last week on every exercise. If you hit the top of your rep range on all sets, you're ready to add weight next week."
            case 3:
                return "Progressive overload kicks in. Add 5 lbs to compounds or 1-2 reps to accessory movements if you hit your targets last week. If you missed reps, repeat the same weight — consistency beats ego lifting."
            case 4:
                if pos == bl {
                    return "Last training week before recovery. Push hard — this is your chance to set new benchmarks before the deload. Go for rep PRs on your T2/T3 exercises. Your T1 weights should be at their heaviest for this block."
                }
                return "You're in the thick of the block. Fatigue is building but so is fitness. Stay focused on progressive overload — even small jumps (2.5 lbs, 1 extra rep) compound over time."
            case 5:
                return "Final week of the block. Fatigue is highest but so is your fitness. Push for your best numbers — this week's performance sets the baseline for your next block. Recovery week follows."
            default:
                return "Continue progressive overload. Add weight when you hit the top of your rep range. Prioritize the exercises where you're closest to a new personal best."
            }
        }

        // Strength / Powerbuilding
        switch (phase, pos) {
        case ("Accumulation", 1): return "Build your base. Moderate weights, focus on volume and technique. Establish your working weights for the block."
        case ("Accumulation", _): return "Add weight or reps each session. Building work capacity that will support heavier loads in later phases."
        case ("Intensification", 1): return "Shift to heavier weights with fewer reps per set. Volume drops but intensity rises. Focus on bar speed and technique under load."
        case ("Intensification", _): return "Continue pushing intensity up. Each week should feel heavier than the last. Rest longer between sets if needed."
        case ("Peaking", 1): return "Heaviest weights of the cycle. Minimal volume. Every set counts — focus on maximal effort with perfect form."
        case ("Peaking", _): return "Test your strength. This is what the previous phases built towards. Go for PRs on your main lifts."
        case ("Volume Phase", 1): return "Higher volume block. More sets per muscle than the previous phase. Focus on hypertrophy work while maintaining your strength base."
        case ("Volume Phase", _): return "Push volume and chase the pump. Your strength foundation supports this higher workload."
        default: return "Progressive overload — beat last week's numbers."
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 3).fill(Color.appBorder).frame(width: 36, height: 4).padding(.top, 12)
                Text("MESOCYCLE OVERVIEW").font(.system(size: 11, weight: .black)).foregroundColor(.appRed).kerning(2)

                // Current position
                VStack(alignment: .leading, spacing: 4) {
                    Text("You're on Week \(currentWeek)")
                        .font(.system(size: 18, weight: .black)).foregroundColor(.appTextPrimary)
                    Text(phaseName(currentWeek) + " — \(weekTitle(currentWeek))")
                        .font(.system(size: 13, weight: .bold)).foregroundColor(.appBlue)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14).background(Color.appSurface).cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))

                // Week list
                ForEach(1...totalWeeks, id: \.self) { w in
                    let isCurrent = w == currentWeek
                    let isRecovery = isRecoveryWeek(w)
                    let isExpanded = expandedWeek == w

                    VStack(spacing: 0) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                expandedWeek = isExpanded ? nil : w
                            }
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle().fill(isCurrent ? Color.appRed : (isRecovery ? Color.appBlue.opacity(0.15) : Color.appSurface2))
                                        .frame(width: 36, height: 36)
                                    Text("\(w)").font(.system(size: 14, weight: .black, design: .rounded))
                                        .foregroundColor(isCurrent ? .white : (isRecovery ? .appBlue : .appTextPrimary))
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(weekTitle(w)).font(.system(size: 13, weight: .bold))
                                            .foregroundColor(isCurrent ? .appTextPrimary : .appTextSecondary)
                                        if isCurrent {
                                            Text("NOW").font(.system(size: 8, weight: .black)).foregroundColor(.appRed)
                                                .padding(.horizontal, 5).padding(.vertical, 2).background(Color.appRed.opacity(0.1)).cornerRadius(3)
                                        }
                                    }
                                    Text(phaseName(w)).font(.system(size: 10, weight: .bold))
                                        .foregroundColor(isRecovery ? .appBlue : .appGreen)
                                }
                                Spacer()
                                if w < currentWeek {
                                    Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundColor(.appGreen)
                                }
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 10, weight: .semibold)).foregroundColor(.appTextDim)
                            }
                            .padding(12)
                        }
                        .buttonStyle(.plain)

                        // Expanded detail
                        if isExpanded {
                            VStack(alignment: .leading, spacing: 10) {
                                Divider().background(Color.appBorder)
                                Text(weekDetail(w))
                                    .font(.system(size: 13)).foregroundColor(.appTextSecondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                // Volume change indicator
                                if !isRecovery {
                                    let phase = phaseName(w)
                                    let volLabel = phase == "Growth Phase" || phase == "Volume Phase" ? "↑ 15% more sets than standard" : (isRecoveryWeek(w) ? "↓ Maintenance volume only" : "Standard volume")
                                    HStack(spacing: 6) {
                                        Image(systemName: phase.contains("Growth") || phase.contains("Volume") ? "arrow.up.right" : "equal")
                                            .font(.system(size: 10)).foregroundColor(phase.contains("Growth") || phase.contains("Volume") ? .appGold : .appGreen)
                                        Text(volLabel).font(.system(size: 11, weight: .bold))
                                            .foregroundColor(phase.contains("Growth") || phase.contains("Volume") ? .appGold : .appTextDim)
                                    }
                                }

                                HStack(spacing: 8) {
                                    Button { onSelectWeek(w) } label: {
                                        Text("View Week").font(.system(size: 12, weight: .bold)).foregroundColor(.appBlue)
                                            .padding(.horizontal, 12).padding(.vertical, 8)
                                            .background(Color.appBlue.opacity(0.08)).cornerRadius(8)
                                    }.buttonStyle(.plain)

                                    if w != currentWeek {
                                        Button { onSetWeek(w) } label: {
                                            Text("Jump Here").font(.system(size: 12, weight: .bold)).foregroundColor(.appRed)
                                                .padding(.horizontal, 12).padding(.vertical, 8)
                                                .background(Color.appRed.opacity(0.08)).cornerRadius(8)
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.horizontal, 12).padding(.bottom, 12)
                        }
                    }
                    .background(isCurrent ? Color.appRed.opacity(0.04) : Color.appSurface)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(isCurrent ? Color.appRed.opacity(0.2) : Color.appBorder, lineWidth: isCurrent ? 1.5 : 1))
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 40)
        }
        .background(Color.appBG)
    }
}

struct BlockInfoSheet: View {
    let instance: UserProgramInstance?
    let profile: UserProfile?

    private var goal: GoalType { profile?.goal ?? .hypertrophy }
    private var isHyp: Bool { goal == .hypertrophy || goal == .recomp }

    private func dn(_ bt: BlockType) -> String {
        switch (isHyp, bt) {
        case (true, .accumulation):    return "Training Block"
        case (true, .reaccumulation):  return "Growth Phase"
        case (true, .deload):          return "Recovery"
        case (true, _):                return "Training Block"
        case (false, .accumulation):   return "Accumulation"
        case (false, .intensification):return "Intensification"
        case (false, .reaccumulation): return goal == .powerbuilding ? "Volume Phase" : "Accumulation"
        case (false, .peak):           return "Peaking"
        case (false, .deload):         return "Deload"
        }
    }

    private func blockColor(_ bt: BlockType) -> Color {
        switch bt {
        case .accumulation: return .appGreen
        case .reaccumulation: return .appGold
        case .intensification: return .appOrange
        case .peak: return .appRed
        case .deload: return .appBlue
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 3).fill(Color.appBorder).frame(width: 36, height: 4).padding(.top, 12)

                Text("YOUR MESOCYCLE").font(.system(size: 11, weight: .black)).foregroundColor(.appRed).kerning(2)

                if let inst = instance {
                    // ── CURRENT BLOCK ──
                    VStack(spacing: 8) {
                        Text(dn(inst.blockType))
                            .font(.system(size: 24, weight: .black, design: .rounded)).foregroundColor(.appTextPrimary)
                        HStack(spacing: 20) {
                            VStack(spacing: 2) {
                                Text("WEEK").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim)
                                Text("\(inst.blockWeek) / \(inst.blockLength)")
                                    .font(.system(size: 20, weight: .black, design: .rounded)).foregroundColor(.appRed)
                            }
                            Rectangle().fill(Color.appBorder).frame(width: 1, height: 32)
                            VStack(spacing: 2) {
                                Text("BLOCK").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim)
                                Text("#\(inst.totalBlocksCompleted + 1)")
                                    .font(.system(size: 20, weight: .black, design: .rounded)).foregroundColor(.appBlue)
                            }
                            Rectangle().fill(Color.appBorder).frame(width: 1, height: 32)
                            VStack(spacing: 2) {
                                Text("VOLUME").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim)
                                let mult = Int(blockMultiplier(inst.blockType) * 100)
                                Text("\(mult)%")
                                    .font(.system(size: 20, weight: .black, design: .rounded))
                                    .foregroundColor(mult > 100 ? .appGold : (mult < 100 ? .appBlue : .appGreen))
                            }
                        }
                    }
                    .padding(20).background(Color.appSurface).cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.appBorder, lineWidth: 1))

                    // ── WHAT THIS BLOCK MEANS ──
                    VStack(alignment: .leading, spacing: 8) {
                        blockExplanation(inst.blockType, goal: goal)
                    }
                    .padding(14).background(Color.appSurface).cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))

                    // ── WEEKLY FOCUS ──
                    VStack(alignment: .leading, spacing: 6) {
                        Text("THIS WEEK'S FOCUS").font(.system(size: 10, weight: .bold)).foregroundColor(.appTextDim).kerning(1)
                        Text(weekFocus(inst.blockType, blockWeek: inst.blockWeek, blockLength: inst.blockLength, goal: goal))
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(.appTextPrimary)
                    }
                    .padding(14).background(Color.appSurface).cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))

                    // ── WEEK-BY-WEEK PROGRESSION ──
                    VStack(alignment: .leading, spacing: 8) {
                        Text("WEEK-BY-WEEK WITHIN THIS BLOCK").font(.system(size: 10, weight: .bold)).foregroundColor(.appTextDim).kerning(1)
                        ForEach(1...inst.blockLength, id: \.self) { wk in
                            let isCurrent = wk == inst.blockWeek
                            HStack(spacing: 10) {
                                Circle().fill(isCurrent ? Color.appRed : Color.appBorder).frame(width: 8, height: 8)
                                Text("Week \(wk)").font(.system(size: 13, weight: isCurrent ? .bold : .medium))
                                    .foregroundColor(isCurrent ? .appTextPrimary : .appTextSecondary)
                                Spacer()
                                Text(weekDescription(wk, of: inst.blockLength, goal: goal))
                                    .font(.system(size: 11)).foregroundColor(.appTextDim)
                            }
                            .padding(.vertical, 4)
                            if isCurrent {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.right").font(.system(size: 8)).foregroundColor(.appRed)
                                    Text("YOU ARE HERE").font(.system(size: 9, weight: .black)).foregroundColor(.appRed).kerning(1)
                                }.padding(.leading, 18)
                            }
                        }
                        // Deload week
                        HStack(spacing: 10) {
                            Circle().fill(Color.appBlue).frame(width: 8, height: 8)
                            Text("Recovery Week").font(.system(size: 13, weight: .medium)).foregroundColor(.appBlue)
                            Spacer()
                            Text("Light weight, maintain movement").font(.system(size: 11)).foregroundColor(.appTextDim)
                        }.padding(.vertical, 4)
                    }
                    .padding(14).background(Color.appSurface).cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))

                    // ── BLOCK TIMELINE ──
                    VStack(alignment: .leading, spacing: 8) {
                        Text("YOUR BLOCK SEQUENCE").font(.system(size: 10, weight: .bold)).foregroundColor(.appTextDim).kerning(1)

                        let timeline = buildTimeline(inst)
                        ForEach(Array(timeline.enumerated()), id: \.offset) { idx, block in
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 3).fill(block.color)
                                    .frame(width: 4, height: block.isCurrent ? 36 : 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(block.name).font(.system(size: 12, weight: block.isCurrent ? .black : .bold))
                                        .foregroundColor(block.isCurrent ? .appTextPrimary : .appTextSecondary)
                                    Text(block.detail).font(.system(size: 10)).foregroundColor(.appTextDim)
                                }
                                Spacer()
                                if block.isCurrent {
                                    Text("CURRENT").font(.system(size: 8, weight: .black)).foregroundColor(.appRed).kerning(1)
                                        .padding(.horizontal, 6).padding(.vertical, 3)
                                        .background(Color.appRed.opacity(0.1)).cornerRadius(4)
                                } else if block.isPast {
                                    Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundColor(.appGreen)
                                }
                            }
                        }
                    }
                    .padding(14).background(Color.appSurface).cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))

                    // ── HOW IT EVOLVES ──
                    VStack(alignment: .leading, spacing: 8) {
                        Text("HOW YOUR PROGRAM EVOLVES").font(.system(size: 10, weight: .bold)).foregroundColor(.appTextDim).kerning(1)
                        if isHyp {
                            evolutionRow(icon: "1.circle.fill", text: "Each week: try to add weight or reps to every exercise")
                            evolutionRow(icon: "2.circle.fill", text: "Each block: volume adjusts based on your progress signals")
                            evolutionRow(icon: "3.circle.fill", text: "Growth phases get 15% more sets — priming you for new gains")
                            evolutionRow(icon: "4.circle.fill", text: "Recovery weeks let fatigue clear so you can push harder next block")
                            evolutionRow(icon: "5.circle.fill", text: "T2 exercises rotate between blocks for variety and balanced development")
                        } else {
                            evolutionRow(icon: "1.circle.fill", text: "Accumulation: build work capacity with moderate loads")
                            evolutionRow(icon: "2.circle.fill", text: "Intensification: heavier weights, fewer reps — express your strength")
                            evolutionRow(icon: "3.circle.fill", text: "Peaking: test your max — heaviest weights of the cycle")
                            evolutionRow(icon: "4.circle.fill", text: "Deload between phases lets fatigue clear for the next push")
                        }
                    }
                    .padding(14).background(Color.appSurface).cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
                }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 20)
        }
        .background(Color.appBG)
    }

    private func evolutionRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).font(.system(size: 14)).foregroundColor(.appRed)
            Text(text).font(.system(size: 12)).foregroundColor(.appTextSecondary)
        }
    }

    private func weekDescription(_ wk: Int, of total: Int, goal: GoalType) -> String {
        if isHyp {
            if wk <= 2 { return "Establish weights" }
            if wk == total { return "Push hardest" }
            return "Add weight or reps"
        }
        if wk <= 2 { return "Build base" }
        return "Progressive overload"
    }

    private func blockMultiplier(_ bt: BlockType) -> Double {
        switch bt {
        case .accumulation: return 1.0
        case .reaccumulation: return 1.15
        case .intensification: return 0.65
        case .peak: return 0.50
        case .deload: return 1.0
        }
    }

    struct TimelineBlock { let name: String; let detail: String; let color: Color; let isCurrent: Bool; let isPast: Bool }

    private func buildTimeline(_ inst: UserProgramInstance) -> [TimelineBlock] {
        var blocks: [TimelineBlock] = []
        var bt: BlockType = .accumulation
        let currentBlockNum = inst.totalBlocksCompleted

        for i in 0..<min(currentBlockNum + 4, 10) {
            let isCurrent = i == currentBlockNum
            let isPast = i < currentBlockNum

            if isCurrent { bt = inst.blockType }
            else if i > currentBlockNum {
                bt = BlockType.next(current: bt, goal: goal, blockNumber: i)
            } else {
                // Past blocks — approximate
                bt = i % 2 == 0 ? .accumulation : (isHyp ? .reaccumulation : .intensification)
                if goal == .strength && i > 2 { bt = .peak }
            }

            let name = dn(bt)
            let detail = isPast ? "Completed" : (isCurrent ? "Week \(inst.blockWeek)/\(inst.blockLength)" : "Upcoming")
            blocks.append(TimelineBlock(name: name, detail: detail, color: blockColor(bt), isCurrent: isCurrent, isPast: isPast))

            // Add deload between non-deload blocks for future
            if !isCurrent && !isPast && bt != .deload && i < currentBlockNum + 3 {
                bt = .deload
            }
        }
        return blocks
    }

    private func blockExplanation(_ bt: BlockType, goal: GoalType) -> some View {
        let (icon, title, desc): (String, String, String)

        switch (isHyp, bt) {
        case (true, .accumulation):
            (icon, title, desc) = ("dumbbell.fill", "Progressive Overload",
             "Add weight or reps each week. The goal is to do more than last week — that's what drives muscle growth.")
        case (true, .reaccumulation):
            (icon, title, desc) = ("flame.fill", "Growth Phase",
             "More sets per muscle this block. Your body recovered from the break — this is where the gains happen.")
        case (true, .deload):
            (icon, title, desc) = ("leaf.fill", "Recovery",
             "Lighter weights, fewer sets. Let your body recover so you can push harder in the next block.")
        case (false, .accumulation):
            (icon, title, desc) = ("arrow.up.right", "Accumulation",
             "Building work capacity with moderate weights. Setting the foundation for heavier loads.")
        case (false, .intensification):
            (icon, title, desc) = ("flame", "Intensification",
             "Heavier weights, fewer reps. Transitioning from volume to intensity.")
        case (false, .peak):
            (icon, title, desc) = ("star.fill", "Peaking",
             "Heaviest weights of the cycle. Minimal volume, maximal intensity.")
        case (false, .deload):
            (icon, title, desc) = ("leaf.fill", "Deload",
             "Planned recovery. Reduced load to dissipate fatigue.")
        case (false, .reaccumulation):
            (icon, title, desc) = ("arrow.up.right.circle", goal == .powerbuilding ? "Volume Phase" : "Accumulation",
             "Higher volume block after recovery. More sets to maximize growth.")
        default:
            (icon, title, desc) = ("dumbbell.fill", "Training", "Progressive overload — more weight or reps than last week.")
        }

        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundColor(.appRed).font(.system(size: 16))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .bold)).foregroundColor(.appTextPrimary)
                Text(desc).font(.system(size: 12)).foregroundColor(.appTextSecondary)
            }
        }
    }

    private func weekFocus(_ bt: BlockType, blockWeek: Int, blockLength: Int, goal: GoalType = .hypertrophy) -> String {
        if isHyp {
            if bt == .deload { return "Light week — recover and reset for the next push." }
            if blockWeek <= 2 { return "Establish your working weights. Hit your rep targets before adding load." }
            return "Push for progress — try to beat last week's numbers on every exercise."
        }
        switch bt {
        case .deload:
            return "Recovery week — light weights, maintain movement quality. Let fatigue dissipate."
        case .accumulation:
            if blockWeek <= 2 {
                return "Build your base — establish working weights and hit your rep targets consistently."
            }
            return "Push for progress — try to add weight or reps to last week's numbers."
        case .reaccumulation:
            if blockWeek <= 2 {
                return "Higher volume phase — more sets per muscle. Focus on execution and pump."
            }
            return "Volume is up — keep pushing reps and weight. Your body is primed for growth."
        case .intensification:
            return "Heavier weights, fewer reps per set. Focus on strength and bar speed."
        case .peak:
            return "Test your strength — heaviest weights of the cycle. Quality over quantity."
        }
    }
}
