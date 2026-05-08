import SwiftUI
import SwiftData

// ═══════════════════════════════════════════
// PROGRAM CONFIGURATOR
// Full control over your active program:
// rename sessions, add/remove days, import
// from other programs, week overrides.
// ═══════════════════════════════════════════

struct ProgramConfiguratorSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let instance: UserProgramInstance
    let profile: UserProfile?

    @Query private var allExercises: [Exercise]
    @Query private var programTemplates: [ProgramTemplate]
    @Query private var allInstances: [UserProgramInstance]
    @Query private var allSessionTemplates: [ProgramSessionTemplate]
    @Query private var dayTemplates: [DayTemplate]

    @State private var activeTab: ConfigTab = .sessions
    @State private var showImportPicker = false
    @State private var weekOverrideWeek: Int = 1
    @State private var configWeek: Int = 1

    enum ConfigTab: String, CaseIterable {
        case sessions = "Sessions"
        case weekOverride = "Week Override"
        case importSession = "Import"
    }

    /// Base rotation for the program (no overrides). Honors custom programs by
    /// reading from ProgramTemplate.sessionTypes when the programId isn't a
    /// hardcoded built-in.
    private var baseRotation: [SessionType] {
        switch instance.programId {
        case 2: return [.pushA, .pullA, .legsA, .pushB, .pullB, .legsB]
        case 7: return [.legQuadFocus, .chestBack, .armsDelts, .legsPosterior, .chestArms, .legsVolume]
        default:
            if instance.isGenerated, let p = profile {
                return ProgramGenerator.resolveSplitStructure(
                    daysPerWeek: p.daysPerWeek, goal: p.goal, priorityMuscles: p.priorityMuscles)
                    .filter { $0.sessionType != .rest }.map { $0.sessionType }
            }
            // Custom programs (and any pid with a matching template) read their
            // own session types from the persisted ProgramTemplate.
            if let tmpl = programTemplates.first(where: { $0.programId == instance.programId }) {
                return tmpl.sessionTypes
            }
            return [.heavyUpper, .heavyLower, .hypertrophyUpper, .hypertrophyLower]
        }
    }

    /// Effective rotation for the selected week (with overrides applied)
    /// Returns (dayOfWeek, sessionType) pairs so day tracking stays stable
    private var currentRotation: [(dow: Int, sessionType: SessionType)] {
        let base = baseRotation
        let workDays: [Int] = base.count >= 6 ? [1,2,3,4,6,7] :
            base.count == 5 ? [1,2,3,5,6] :
            base.count == 4 ? [1,2,4,5] :
            base.count == 3 ? [1,3,5] : [1,4]

        var result: [(dow: Int, sessionType: SessionType)] = []
        for (i, st) in base.enumerated() {
            guard i < workDays.count else { continue }
            let dow = workDays[i] == 7 ? 0 : workDays[i]

            let weekOverride = instance.schedules.first(where: { s in
                s.dayOfWeek == dow && !s.isPermanent && s.week == configWeek
            })
            let permOverride = instance.schedules.first(where: { s in
                s.dayOfWeek == dow && s.isPermanent
            })
            if let override = weekOverride ?? permOverride {
                if override.isRestDay { continue }
                result.append((dow: dow, sessionType: override.sessionType))
            } else {
                result.append((dow: dow, sessionType: st))
            }
        }

        let usedDows = Set(workDays.prefix(base.count).map { $0 == 7 ? 0 : $0 })
        let extraSessions = instance.schedules.filter { s in
            !s.isRestDay && (s.isPermanent || s.week == configWeek) && !usedDows.contains(s.dayOfWeek)
        }
        for extra in extraSessions {
            result.append((dow: extra.dayOfWeek, sessionType: extra.sessionType))
        }

        return result
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 3).fill(Color.appBorder).frame(width: 36, height: 4).padding(.top, 12)
                Text("CONFIGURE PROGRAM").font(.system(size: 12, weight: .black)).foregroundColor(.appRed).kerning(2)

                // Tab picker
                HStack(spacing: 4) {
                    ForEach(ConfigTab.allCases, id: \.self) { tab in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { activeTab = tab }
                        } label: {
                            Text(tab.rawValue)
                                .font(.system(size: 11, weight: activeTab == tab ? .black : .medium))
                                .foregroundColor(activeTab == tab ? .white : .appTextSecondary)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(activeTab == tab ? Color.appRed : Color.appSurface2).cornerRadius(7)
                        }.buttonStyle(.plain)
                    }
                }

                switch activeTab {
                case .sessions: sessionsTab
                case .weekOverride: weekOverrideTab
                case .importSession: importTab
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 40)
        }
        .background(Color.appBG)
        .onAppear {
            weekOverrideWeek = instance.currentWeek
            configWeek = instance.currentWeek
        }
    }

    // ═══════════════════════════════════════
    // SESSIONS TAB — rename, add, remove
    // ═══════════════════════════════════════

    @State private var showSessionPicker = false
    @State private var sessionPickerPermanent = false
    @State private var replacingSessionIndex: Int? = nil
    @State private var actionSessionIndex: Int? = nil
    @State private var showRemoveConfirm = false
    @State private var showReplaceConfirm = false
    @State private var showResetWeekConfirm = false

    private var sessionsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Week picker
            HStack(spacing: 6) {
                Text("WEEK").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim)
                Button { if configWeek > 1 { configWeek -= 1 } } label: {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold)).foregroundColor(.appTextDim)
                        .frame(width: 36, height: 36).contentShape(Rectangle()).background(Color.appSurface2).cornerRadius(8)
                }.buttonStyle(.plain)
                Text("\(configWeek)").font(.system(size: 16, weight: .black, design: .rounded)).foregroundColor(.appRed)
                Button { if configWeek < 24 { configWeek += 1 } } label: {
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundColor(.appTextDim)
                        .frame(width: 36, height: 36).contentShape(Rectangle()).background(Color.appSurface2).cornerRadius(8)
                }.buttonStyle(.plain)
                Spacer()
                if configWeek != instance.currentWeek {
                    Button { configWeek = instance.currentWeek } label: {
                        Text("Current").font(.system(size: 10, weight: .bold)).foregroundColor(.appBlue)
                    }.buttonStyle(.plain)
                }
            }

            Text("Manage sessions for week \(configWeek)").font(.system(size: 12)).foregroundColor(.appTextDim)

            ForEach(Array(currentRotation.enumerated()), id: \.offset) { idx, entry in
                HStack(spacing: 10) {
                    Text("D\(idx + 1)").font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundColor(.appRed).frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.sessionType.shortLabel).font(.system(size: 14, weight: .bold)).foregroundColor(.appTextPrimary)
                        Text(entry.sessionType.muscleSubtitle).font(.system(size: 11)).foregroundColor(.appTextDim)
                    }

                    Spacer()

                    // Replace button
                    Button {
                        actionSessionIndex = idx
                        showReplaceConfirm = true
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 10, weight: .bold))
                            Text("Swap").font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(.appBlue)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(Color.appBlue.opacity(0.08)).cornerRadius(6)
                    }.buttonStyle(.plain)

                    // Remove button
                    Button {
                        actionSessionIndex = idx
                        showRemoveConfirm = true
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "minus.circle.fill").font(.system(size: 10))
                            Text("Remove").font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(.appRed)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(Color.appRed.opacity(0.06)).cornerRadius(6)
                    }.buttonStyle(.plain)
                }
                .padding(10).background(Color.appSurface).cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorder, lineWidth: 1))
            }
            .confirmationDialog("Remove Session", isPresented: $showRemoveConfirm) {
                Button("This Week Only") {
                    if let idx = actionSessionIndex { removeSession(at: idx, permanent: false) }
                }
                Button("Permanently") {
                    if let idx = actionSessionIndex { removeSession(at: idx, permanent: true) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Remove this session for just this week, or permanently from your rotation?")
            }
            .confirmationDialog("Replace Session", isPresented: $showReplaceConfirm) {
                Button("This Week Only") {
                    if let idx = actionSessionIndex {
                        replacingSessionIndex = idx
                        sessionPickerPermanent = false
                        showSessionPicker = true
                    }
                }
                Button("Permanently") {
                    if let idx = actionSessionIndex {
                        replacingSessionIndex = idx
                        sessionPickerPermanent = true
                        showSessionPicker = true
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Replace this session for just this week, or permanently change your rotation?")
            }

            // Add session buttons
            HStack(spacing: 8) {
                Button {
                    replacingSessionIndex = nil
                    sessionPickerPermanent = false
                    showSessionPicker = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 13))
                        Text("Add This Week").font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(.appGreen).frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(Color.appGreen.opacity(0.06)).cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appGreen.opacity(0.15), lineWidth: 1))
                }.buttonStyle(.plain)

                Button {
                    replacingSessionIndex = nil
                    sessionPickerPermanent = true
                    showSessionPicker = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "pin.circle.fill").font(.system(size: 13))
                        Text("Add Permanent").font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(.appBlue).frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(Color.appBlue.opacity(0.06)).cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBlue.opacity(0.15), lineWidth: 1))
                }.buttonStyle(.plain)
            }

            // Reset week button — only show when there are overrides for this week
            if instance.schedules.contains(where: { !$0.isPermanent && $0.week == configWeek }) {
                Button { showResetWeekConfirm = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.counterclockwise").font(.system(size: 12, weight: .bold))
                        Text("Reset Week \(configWeek) to Original").font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(.appOrange).frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(Color.appOrange.opacity(0.06)).cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appOrange.opacity(0.15), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .confirmationDialog("Reset Week \(configWeek)?", isPresented: $showResetWeekConfirm) {
                    Button("Reset to Original", role: .destructive) { resetWeek() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will undo all changes you made to week \(configWeek) and restore the original program sessions. Permanent changes are not affected.")
                }
            }
        }
        .sheet(isPresented: $showSessionPicker) {
            SessionTypePickerSheet(
                onSelect: { st in
                    if let idx = replacingSessionIndex {
                        replaceSession(at: idx, with: st)
                    } else {
                        addSession(st, permanent: sessionPickerPermanent)
                    }
                    showSessionPicker = false
                },
                onDismiss: { showSessionPicker = false }
            )
            .presentationDetents([.medium])
        }
    }

    private func removeSession(at index: Int, permanent: Bool) {
        guard index < currentRotation.count else { return }
        let entry = currentRotation[index]
        let dow = entry.dow

        if permanent {
            instance.schedules.removeAll { $0.dayOfWeek == dow && $0.isPermanent }
        } else {
            instance.schedules.removeAll { $0.dayOfWeek == dow && !$0.isPermanent && $0.week == configWeek }
        }

        let sched = ProgramSchedule(dayOfWeek: dow, sessionType: entry.sessionType,
                                     isRestDay: true, week: permanent ? 0 : configWeek,
                                     isPermanent: permanent)
        instance.schedules.append(sched)
        try? modelContext.save()
    }

    private func replaceSession(at index: Int, with newType: SessionType) {
        guard index < currentRotation.count else { return }
        let dow = currentRotation[index].dow

        if sessionPickerPermanent {
            instance.schedules.removeAll { $0.dayOfWeek == dow && $0.isPermanent }
        } else {
            instance.schedules.removeAll { $0.dayOfWeek == dow && !$0.isPermanent && $0.week == configWeek }
        }

        let sched = ProgramSchedule(dayOfWeek: dow, sessionType: newType,
                                     isRestDay: false,
                                     week: sessionPickerPermanent ? 0 : configWeek,
                                     isPermanent: sessionPickerPermanent)
        instance.schedules.append(sched)
        try? modelContext.save()
    }

    private func resetWeek() {
        instance.schedules.removeAll { !$0.isPermanent && $0.week == configWeek }
        try? modelContext.save()
    }

    private var allSessionTypes: [SessionType] {
        [.heavyUpper, .heavyLower, .hypertrophyUpper, .hypertrophyLower,
         .push, .pull, .legs, .pushA, .pushB, .pullA, .pullB, .legsA, .legsB,
         .fullBody, .fullBodyA, .fullBodyB,
         .legQuadFocus, .legsPosterior, .chestBack, .armsDelts, .chestArms, .legsVolume]
    }

    private func addSession(_ st: SessionType, permanent: Bool) {
        // Find next available rest day
        let usedDays = instance.schedules
            .filter { !$0.isRestDay && ($0.isPermanent || $0.week == configWeek) }
            .map { $0.dayOfWeek }
        let base = baseRotation
        let workDays = base.count >= 6 ? [1,2,3,4,6,7] : (base.count == 5 ? [1,2,3,5,6] : (base.count == 4 ? [1,2,4,5] : [1,3,5]))
        let allDays = Set(0...6)
        let occupiedDays = Set(workDays.map { $0 == 7 ? 0 : $0 }).union(Set(usedDays))
        let freeDays = allDays.subtracting(occupiedDays)
        let targetDay = freeDays.min() ?? 6

        let schedule = ProgramSchedule(dayOfWeek: targetDay, sessionType: st,
                                        isRestDay: false, week: permanent ? 0 : configWeek,
                                        isPermanent: permanent)
        instance.schedules.append(schedule)
        try? modelContext.save()
    }

    // ═══════════════════════════════════════
    // WEEK OVERRIDE TAB — swap program for a week
    // ═══════════════════════════════════════

    private var weekOverrideTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Try a different program for a specific week. Your original program data is preserved.")
                .font(.system(size: 12)).foregroundColor(.appTextDim)

            // Week picker
            VStack(alignment: .leading, spacing: 6) {
                Text("WHICH WEEK").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(1)
                HStack(spacing: 6) {
                    ForEach(max(1, instance.currentWeek - 1)...min(instance.currentWeek + 4, 24), id: \.self) { w in
                        Button { weekOverrideWeek = w } label: {
                            Text("\(w)")
                                .font(.system(size: 12, weight: weekOverrideWeek == w ? .black : .medium))
                                .foregroundColor(weekOverrideWeek == w ? .white : .appTextSecondary)
                                .frame(width: 32, height: 32)
                                .background(weekOverrideWeek == w ? Color.appRed : Color.appSurface2).cornerRadius(8)
                        }.buttonStyle(.plain)
                    }
                }
            }

            // Program options
            VStack(alignment: .leading, spacing: 6) {
                Text("OVERRIDE WITH").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(1)

                // Preset overrides
                overrideOption("Hypertrophy Focus", detail: "Higher reps, more volume, pump-focused",
                               sessions: [.pushA, .pullA, .legsA, .pushB, .pullB, .legsB])
                overrideOption("Strength Focus", detail: "Lower reps, heavier weight, compound-heavy",
                               sessions: [.heavyUpper, .heavyLower, .hypertrophyUpper, .hypertrophyLower])
                overrideOption("Full Body", detail: "Hit everything each session, lower frequency",
                               sessions: [.fullBodyA, .fullBodyB, .fullBodyA])
                overrideOption("Recovery Week", detail: "Light weights, maintenance volume, active recovery",
                               sessions: [])  // empty = use current but at deload volume
            }

            // Active overrides
            let activeOverrides = instance.schedules.filter { !$0.isPermanent && $0.week == weekOverrideWeek }
            if !activeOverrides.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("ACTIVE OVERRIDES FOR WEEK \(weekOverrideWeek)").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(1)
                        Spacer()
                        Button {
                            for o in activeOverrides {
                                if let idx = instance.schedules.firstIndex(where: { $0.id == o.id }) {
                                    instance.schedules.remove(at: idx)
                                }
                            }
                            try? modelContext.save()
                        } label: {
                            Text("Clear All").font(.system(size: 10, weight: .bold)).foregroundColor(.appRed)
                        }.buttonStyle(.plain)
                    }
                    ForEach(activeOverrides) { override_ in
                        HStack {
                            Text(override_.sessionType.shortLabel).font(.system(size: 12, weight: .bold)).foregroundColor(.appTextPrimary)
                            Spacer()
                            let dayNames = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
                            Text(dayNames[override_.dayOfWeek]).font(.system(size: 11)).foregroundColor(.appTextDim)
                        }
                        .padding(8).background(Color.appSurface2).cornerRadius(6)
                    }
                }
            }
        }
    }

    private func overrideOption(_ title: String, detail: String, sessions: [SessionType]) -> some View {
        Button {
            applyWeekOverride(sessions: sessions, week: weekOverrideWeek)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .bold)).foregroundColor(.appTextPrimary)
                    Text(detail).font(.system(size: 10)).foregroundColor(.appTextDim)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundColor(.appTextDim)
            }
            .padding(10).background(Color.appSurface).cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorder, lineWidth: 1))
        }.buttonStyle(.plain)
    }

    private func applyWeekOverride(sessions: [SessionType], week: Int) {
        // Remove existing overrides for this week
        instance.schedules.removeAll { !$0.isPermanent && $0.week == week }

        if sessions.isEmpty {
            // Recovery week — mark block type as deload for this week
            // (handled by existing deload detection)
            return
        }

        // Assign sessions to days
        let daySlots: [Int] = sessions.count >= 6 ? [1,2,3,4,6,7] :
            sessions.count == 5 ? [1,2,3,5,6] :
            sessions.count == 4 ? [1,2,4,5] :
            sessions.count == 3 ? [1,3,5] : [1,4]

        for (i, st) in sessions.prefix(daySlots.count).enumerated() {
            let dow = daySlots[i] == 7 ? 0 : daySlots[i]
            let sched = ProgramSchedule(dayOfWeek: dow, sessionType: st,
                                         isRestDay: false, week: week, isPermanent: false)
            instance.schedules.append(sched)
        }

        try? modelContext.save()
    }

    // ═══════════════════════════════════════
    // IMPORT TAB — week portal + program catalog
    // ═══════════════════════════════════════

    @State private var importSelectedDow: Int? = nil
    @State private var importPermanent: Bool = false

    /// Full 7-day layout for the selected week (Mon–Sun, dow order: 1,2,3,4,5,6,0)
    private var weekLayout: [(dow: Int, session: SessionType?)] {
        let base = baseRotation
        let workDays: [Int] = base.count >= 6 ? [1,2,3,4,6,7] :
            base.count == 5 ? [1,2,3,5,6] :
            base.count == 4 ? [1,2,4,5] :
            base.count == 3 ? [1,3,5] : [1,4]

        var layout: [Int: SessionType] = [:]

        // Map base sessions to days
        for (i, st) in base.enumerated() {
            guard i < workDays.count else { continue }
            let dow = workDays[i] == 7 ? 0 : workDays[i]
            layout[dow] = st
        }

        // Apply overrides for selected week
        for sched in instance.schedules where sched.isPermanent || sched.week == configWeek {
            if sched.isRestDay {
                layout.removeValue(forKey: sched.dayOfWeek)
            } else {
                layout[sched.dayOfWeek] = sched.sessionType
            }
        }

        // Mon(1) through Sat(6), then Sun(0)
        return [1,2,3,4,5,6,0].map { dow in (dow: dow, session: layout[dow]) }
    }

    private let dowLabels = ["SUN","MON","TUE","WED","THU","FRI","SAT"]

    private var importTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Week picker (shared state with sessions tab)
            HStack(spacing: 6) {
                Text("WEEK").font(.system(size: 9, weight: .bold)).foregroundColor(.appTextDim)
                Button { if configWeek > 1 { configWeek -= 1 } } label: {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold)).foregroundColor(.appTextDim)
                        .frame(width: 36, height: 36).contentShape(Rectangle()).background(Color.appSurface2).cornerRadius(8)
                }.buttonStyle(.plain)
                Text("\(configWeek)").font(.system(size: 16, weight: .black, design: .rounded)).foregroundColor(.appRed)
                Button { if configWeek < 24 { configWeek += 1 } } label: {
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundColor(.appTextDim)
                        .frame(width: 36, height: 36).contentShape(Rectangle()).background(Color.appSurface2).cornerRadius(8)
                }.buttonStyle(.plain)
                Spacer()
                if configWeek != instance.currentWeek {
                    Button { configWeek = instance.currentWeek } label: {
                        Text("Current").font(.system(size: 10, weight: .bold)).foregroundColor(.appBlue)
                    }.buttonStyle(.plain)
                }
            }

            // ── Week Calendar Grid ──
            Text("Tap a day to select it, then pick a session below.").font(.system(size: 11)).foregroundColor(.appTextDim)

            // 7-day grid
            HStack(spacing: 4) {
                ForEach(weekLayout, id: \.dow) { day in
                    let isSelected = importSelectedDow == day.dow
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            importSelectedDow = isSelected ? nil : day.dow
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text(dowLabels[day.dow])
                                .font(.system(size: 8, weight: .black)).kerning(0.5)
                                .foregroundColor(isSelected ? .white : .appTextDim)
                            if let st = day.session {
                                Text(st.shortLabel)
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(isSelected ? .white : .appTextPrimary)
                                    .lineLimit(2).multilineTextAlignment(.center)
                            } else {
                                Text("REST")
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundColor(isSelected ? .white.opacity(0.7) : .appTextDim)
                            }
                        }
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(isSelected ? Color.appRed : (day.session != nil ? Color.appSurface : Color.appSurface2))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(
                            isSelected ? Color.appRed : Color.appBorder, lineWidth: isSelected ? 2 : 1))
                    }.buttonStyle(.plain)
                }
            }

            // Selected day actions
            if let dow = importSelectedDow {
                let daySession = weekLayout.first(where: { $0.dow == dow })?.session
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(dowLabels[dow])").font(.system(size: 12, weight: .black)).foregroundColor(.appRed)
                        Text(daySession?.shortLabel ?? "Rest Day").font(.system(size: 11)).foregroundColor(.appTextSecondary)
                    }
                    Spacer()

                    // Permanent toggle
                    Button {
                        importPermanent.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: importPermanent ? "pin.fill" : "pin").font(.system(size: 10))
                            Text(importPermanent ? "Permanent" : "This Week").font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(importPermanent ? .appBlue : .appTextDim)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(importPermanent ? Color.appBlue.opacity(0.1) : Color.appSurface2).cornerRadius(6)
                    }.buttonStyle(.plain)

                    // Remove (only if day has a session)
                    if daySession != nil {
                        Button {
                            removeFromDay(dow: dow, permanent: importPermanent)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                                Text("Clear").font(.system(size: 10, weight: .bold))
                            }
                            .foregroundColor(.appRed)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(Color.appRed.opacity(0.06)).cornerRadius(6)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(10).background(Color.appSurface).cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appRed.opacity(0.3), lineWidth: 1))
            }

            // ── Program Catalog ──
            if importSelectedDow != nil {
                importCatalog
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "hand.tap").font(.system(size: 16)).foregroundColor(.appTextDim)
                    Text("Select a day above to see available sessions")
                        .font(.system(size: 12)).foregroundColor(.appTextDim)
                }
                .frame(maxWidth: .infinity).padding(20)
                .background(Color.appSurface).cornerRadius(10)
            }
        }
    }

    /// Catalog of built-in programs + templates to import from
    private var importCatalog: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("CHOOSE A SESSION").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(1)

            // Built-in programs
            ForEach(programCatalog, id: \.name) { prog in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: prog.icon).font(.system(size: 11)).foregroundColor(prog.color)
                        Text(prog.name).font(.system(size: 11, weight: .black)).foregroundColor(.appTextPrimary)
                        Text(prog.subtitle).font(.system(size: 9)).foregroundColor(.appTextDim)
                        Spacer()
                    }

                    ForEach(prog.sessions, id: \.self) { st in
                        Button {
                            assignToSelectedDay(st)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle").font(.system(size: 12)).foregroundColor(.appGreen)
                                Text(st.shortLabel).font(.system(size: 12, weight: .bold)).foregroundColor(.appTextPrimary)
                                Text(st.muscleSubtitle).font(.system(size: 10)).foregroundColor(.appTextDim)
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 8)).foregroundColor(.appTextDim)
                            }
                            .padding(8).background(Color.appSurface2).cornerRadius(6)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(10).background(Color.appSurface).cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))
            }

            // Day templates
            if !dayTemplates.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc").font(.system(size: 11)).foregroundColor(.appGold)
                        Text("MY TEMPLATES").font(.system(size: 11, weight: .black)).foregroundColor(.appTextPrimary)
                        Spacer()
                    }

                    ForEach(dayTemplates) { template in
                        Button {
                            assignToSelectedDay(.freeform)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle").font(.system(size: 12)).foregroundColor(.appGreen)
                                Image(systemName: template.iconName).font(.system(size: 12)).foregroundColor(.appRed)
                                Text(template.name).font(.system(size: 12, weight: .bold)).foregroundColor(.appTextPrimary)
                                Text("\(template.exercises.count) exercises").font(.system(size: 10)).foregroundColor(.appTextDim)
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 8)).foregroundColor(.appTextDim)
                            }
                            .padding(8).background(Color.appSurface2).cornerRadius(6)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(10).background(Color.appSurface).cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))
            }
        }
    }

    // ── Program catalog data ──

    private struct ProgramCatalogEntry {
        let name: String
        let subtitle: String
        let icon: String
        let color: Color
        let sessions: [SessionType]
    }

    private var programCatalog: [ProgramCatalogEntry] {
        [
            ProgramCatalogEntry(name: "POWERBUILDING", subtitle: "Upper/Lower DUP",
                                icon: "bolt.fill", color: .appRed,
                                sessions: [.heavyUpper, .heavyLower, .hypertrophyUpper, .hypertrophyLower]),
            ProgramCatalogEntry(name: "PURE HYPERTROPHY", subtitle: "PPL A/B",
                                icon: "figure.strengthtraining.traditional", color: .appBlue,
                                sessions: [.pushA, .pullA, .legsA, .pushB, .pullB, .legsB]),
            ProgramCatalogEntry(name: "STRENGTH", subtitle: "Powerlifting",
                                icon: "scalemass.fill", color: .appGold,
                                sessions: [.heavyUpper, .heavyLower]),
            ProgramCatalogEntry(name: "ATHLETIC", subtitle: "Power + Conditioning",
                                icon: "figure.run", color: .appGold,
                                sessions: [.fullBodyA, .fullBodyB, .fullBody]),
            ProgramCatalogEntry(name: "BEGINNER", subtitle: "Full Body A/B",
                                icon: "star.fill", color: .appGreen,
                                sessions: [.fullBodyA, .fullBodyB]),
            ProgramCatalogEntry(name: "FULL BODY", subtitle: "Hit Everything",
                                icon: "figure.strengthtraining.traditional", color: .appOrange,
                                sessions: [.fullBody, .fullBodyA, .fullBodyB]),
            ProgramCatalogEntry(name: "BAHRI SPLIT", subtitle: "6-Day Hypertrophy",
                                icon: "flame.fill", color: .appRed,
                                sessions: [.legQuadFocus, .chestBack, .armsDelts, .legsPosterior, .chestArms, .legsVolume]),
            ProgramCatalogEntry(name: "SPECIALTY", subtitle: "Individual Sessions",
                                icon: "sparkles", color: .appTextSecondary,
                                sessions: [.push, .pull, .legs, .freeform]),
        ]
    }

    // ── Import actions ──

    private func assignToSelectedDay(_ st: SessionType) {
        guard let dow = importSelectedDow else { return }

        // Remove existing overrides for this day
        if importPermanent {
            instance.schedules.removeAll { $0.dayOfWeek == dow && $0.isPermanent }
        } else {
            instance.schedules.removeAll { $0.dayOfWeek == dow && !$0.isPermanent && $0.week == configWeek }
        }

        let sched = ProgramSchedule(dayOfWeek: dow, sessionType: st,
                                     isRestDay: false,
                                     week: importPermanent ? 0 : configWeek,
                                     isPermanent: importPermanent)
        instance.schedules.append(sched)
        try? modelContext.save()
    }

    private func removeFromDay(dow: Int, permanent: Bool) {
        let currentSession = weekLayout.first(where: { $0.dow == dow })?.session ?? .rest

        if permanent {
            instance.schedules.removeAll { $0.dayOfWeek == dow && $0.isPermanent }
        } else {
            instance.schedules.removeAll { $0.dayOfWeek == dow && !$0.isPermanent && $0.week == configWeek }
        }

        let sched = ProgramSchedule(dayOfWeek: dow, sessionType: currentSession,
                                     isRestDay: true,
                                     week: permanent ? 0 : configWeek,
                                     isPermanent: permanent)
        instance.schedules.append(sched)
        try? modelContext.save()
    }
}

// ═══════════════════════════════════════════
// SESSION TYPE PICKER (custom UI)
// ═══════════════════════════════════════════

struct SessionTypePickerSheet: View {
    let onSelect: (SessionType) -> Void
    let onDismiss: () -> Void

    private let sessionGroups: [(String, [SessionType])] = [
        ("Upper / Lower", [.heavyUpper, .heavyLower, .hypertrophyUpper, .hypertrophyLower]),
        ("Push / Pull / Legs", [.push, .pull, .legs, .pushA, .pushB, .pullA, .pullB, .legsA, .legsB]),
        ("Full Body", [.fullBody, .fullBodyA, .fullBodyB]),
        ("Specialty", [.legQuadFocus, .legsPosterior, .chestBack, .armsDelts, .chestArms, .legsVolume]),
        ("Other", [.freeform])
    ]

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 3).fill(Color.appBorder).frame(width: 36, height: 4).padding(.top, 12)
            HStack {
                Text("CHOOSE SESSION TYPE").font(.system(size: 12, weight: .black)).foregroundColor(.appRed).kerning(2)
                Spacer()
                Button("Cancel") { onDismiss() }.font(.system(size: 14, weight: .medium)).foregroundColor(.appTextSecondary)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    ForEach(sessionGroups, id: \.0) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.0.uppercased()).font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(1)
                            ForEach(group.1, id: \.self) { st in
                                Button { onSelect(st) } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: sessionIcon(st)).font(.system(size: 14)).foregroundColor(.appRed)
                                            .frame(width: 36, height: 36).contentShape(Rectangle()).background(Color.appRed.opacity(0.08)).cornerRadius(8)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(st.shortLabel).font(.system(size: 14, weight: .bold)).foregroundColor(.appTextPrimary)
                                            Text(st.muscleSubtitle).font(.system(size: 11)).foregroundColor(.appTextDim)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.system(size: 10)).foregroundColor(.appTextDim)
                                    }
                                    .padding(10).background(Color.appSurface).cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorder, lineWidth: 1))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 40)
            }
        }
        .background(Color.appBG)
    }

    private func sessionIcon(_ st: SessionType) -> String {
        switch st {
        case .heavyUpper, .hypertrophyUpper: return "figure.arms.open"
        case .heavyLower, .hypertrophyLower: return "figure.walk"
        case .push, .pushA, .pushB: return "arrow.up.right"
        case .pull, .pullA, .pullB: return "arrow.down.left"
        case .legs, .legsA, .legsB: return "figure.run"
        case .fullBody, .fullBodyA, .fullBodyB: return "figure.strengthtraining.traditional"
        case .legQuadFocus: return "bolt.fill"
        case .legsPosterior: return "arrow.backward"
        case .chestBack: return "rectangle.split.2x1"
        case .armsDelts: return "hands.clap"
        case .chestArms: return "hand.raised.fill"
        case .legsVolume: return "flame.fill"
        case .freeform: return "plus.circle"
        default: return "dumbbell.fill"
        }
    }
}
