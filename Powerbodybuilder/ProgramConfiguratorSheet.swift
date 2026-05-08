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
    /// Optional callback the parent uses to present the BlockSequenceEditor.
    /// Sheet-within-a-sheet presentations are unreliable on iOS — the parent
    /// dismisses this sheet and then presents BlockSequenceEditor itself.
    var onRequestSequenceEditor: (() -> Void)? = nil

    @Query private var allExercises: [Exercise]
    @Query private var programTemplates: [ProgramTemplate]
    @Query private var allInstances: [UserProgramInstance]
    @Query private var allSessionTemplates: [ProgramSessionTemplate]
    @Query private var dayTemplates: [DayTemplate]

    @State private var activeTab: ConfigTab = .sessions
    @State private var showImportPicker = false
    @State private var configWeek: Int = 1

    enum ConfigTab: String, CaseIterable {
        case sessions = "Sessions"
        case schedule = "Schedule"
        case blocks = "Blocks"
        case importSession = "Import"
    }

    @State private var activeChildSheet: ChildSheet? = nil
    @State private var scheduleSelectedDow: Int? = nil

    /// Single source of truth for sheet presentation. Multiple `.sheet(isPresented:)`
    /// modifiers on the same view can conflict and silently swallow taps; this enum
    /// + `.sheet(item:)` keeps presentation reliable.
    enum ChildSheet: Identifiable {
        case sessionPicker
        case blockSequenceEditor
        var id: Int { hashValue }
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
                case .schedule: scheduleTab
                case .blocks: blocksTab
                case .importSession: importTab
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 40)
        }
        .background(Color.appBG)
        .onAppear {
            configWeek = instance.currentWeek
        }
    }

    // ═══════════════════════════════════════
    // SESSIONS TAB — rename, add, remove
    // ═══════════════════════════════════════

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
                        activeChildSheet = .sessionPicker
                    }
                }
                Button("Permanently") {
                    if let idx = actionSessionIndex {
                        replacingSessionIndex = idx
                        sessionPickerPermanent = true
                        activeChildSheet = .sessionPicker
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
                    activeChildSheet = .sessionPicker
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
                    activeChildSheet = .sessionPicker
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
        .sheet(item: $activeChildSheet) { sheet in
            switch sheet {
            case .sessionPicker:
                SessionTypePickerSheet(
                    onSelect: { st in
                        if let idx = replacingSessionIndex {
                            replaceSession(at: idx, with: st)
                        } else {
                            addSession(st, permanent: sessionPickerPermanent)
                        }
                        activeChildSheet = nil
                    },
                    onDismiss: { activeChildSheet = nil }
                )
                .presentationDetents([.medium])
            case .blockSequenceEditor:
                // Fallback path — only used when no parent callback is wired.
                // Sheet-within-a-sheet works on iOS 14.5+ but is flaky; the
                // preferred path is dismissing this sheet and letting the
                // parent present.
                BlockSequenceEditor(instance: instance, profile: profile)
            }
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
            // Always shown: "Import all days" buttons don't require a day selection.
            // Per-session "+ Add" buttons still require a selected day below.
            if importSelectedDow == nil {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle").font(.system(size: 13)).foregroundColor(.appBlue)
                    Text("Tap “Import all days” for a full-week import, or pick a day above to add a single session.")
                        .font(.system(size: 11)).foregroundColor(.appTextSecondary)
                        .multilineTextAlignment(.leading)
                }
                .padding(10).background(Color.appBlue.opacity(0.06)).cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBlue.opacity(0.2), lineWidth: 1))
            }
            importCatalog
        }
    }

    /// Catalog of built-in programs + templates to import from
    private var importCatalog: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("CHOOSE A SESSION").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(1)

            // Built-in + custom programs
            ForEach(programCatalog, id: \.name) { prog in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: prog.icon).font(.system(size: 11)).foregroundColor(prog.color)
                        Text(prog.name).font(.system(size: 11, weight: .black)).foregroundColor(.appTextPrimary)
                        Text(prog.subtitle).font(.system(size: 9)).foregroundColor(.appTextDim)
                        Spacer()
                    }

                    // Import the entire program's week schedule in one tap.
                    // Replaces all schedule entries for the active scope
                    // (this week or permanent rotation) with the source's
                    // session-per-day layout.
                    Button {
                        importEntireWeek(from: prog)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar.badge.plus").font(.system(size: 12)).foregroundColor(.appBlue)
                            Text("IMPORT ALL \(prog.sessions.count) DAYS")
                                .font(.system(size: 10, weight: .black)).foregroundColor(.appBlue).kerning(0.5)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 8)).foregroundColor(.appBlue)
                        }
                        .padding(8).background(Color.appBlue.opacity(0.06)).cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.appBlue.opacity(0.25), lineWidth: 1))
                    }.buttonStyle(.plain)

                    if importSelectedDow != nil {
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
        var entries: [ProgramCatalogEntry] = [
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
        // Append the user's custom programs (pid >= 100). Excludes the active
        // program — no point importing from yourself.
        let customs = programTemplates
            .filter { $0.programId >= 100 && $0.programId != instance.programId }
            .sorted { $0.name < $1.name }
        for tmpl in customs {
            entries.append(ProgramCatalogEntry(
                name: tmpl.name.uppercased(),
                subtitle: "Custom · \(tmpl.sessionTypes.count)-day",
                icon: "hammer.fill",
                color: .appBlue,
                sessions: tmpl.sessionTypes
            ))
        }
        return entries
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

    /// Import every session of a source program into the user's week, replacing
    /// any existing schedule entries for the active scope (permanent rotation
    /// or week-specific). Maps the source's sessions onto standard work-day
    /// patterns based on session count (matches baseRotation's day mapping).
    private func importEntireWeek(from program: ProgramCatalogEntry) {
        let count = program.sessions.count
        let workDays: [Int] = count >= 6 ? [1, 2, 3, 4, 6, 7] :
            count == 5 ? [1, 2, 3, 5, 6] :
            count == 4 ? [1, 2, 4, 5] :
            count == 3 ? [1, 3, 5] : [1, 4]

        // Wipe existing schedule for the active scope
        if importPermanent {
            instance.schedules.removeAll { $0.isPermanent }
        } else {
            instance.schedules.removeAll { !$0.isPermanent && $0.week == configWeek }
        }

        // Days the import will use (in dayOfWeek 0-6 system)
        let importDows: Set<Int> = Set(workDays.prefix(count).map { $0 == 7 ? 0 : $0 })

        // Compute the base program's work days so we can REST-out uncovered ones
        let base = baseRotation
        let baseCount = base.count
        let baseWorkDays: [Int] = baseCount >= 6 ? [1, 2, 3, 4, 6, 7] :
            baseCount == 5 ? [1, 2, 3, 5, 6] :
            baseCount == 4 ? [1, 2, 4, 5] :
            baseCount == 3 ? [1, 3, 5] : [1, 4]
        let baseDows: Set<Int> = Set(baseWorkDays.prefix(baseCount).map { $0 == 7 ? 0 : $0 })

        // 1) Add new schedule entries for imported days
        for (i, st) in program.sessions.enumerated() {
            guard i < workDays.count else { break }
            let dow = workDays[i] == 7 ? 0 : workDays[i]
            let sched = ProgramSchedule(dayOfWeek: dow, sessionType: st,
                                         isRestDay: false,
                                         week: importPermanent ? 0 : configWeek,
                                         isPermanent: importPermanent)
            instance.schedules.append(sched)
        }

        // 2) For any BASE work day NOT covered by the import, add a rest override
        //    so the original program's session doesn't keep showing through
        for baseDow in baseDows where !importDows.contains(baseDow) {
            let restSched = ProgramSchedule(dayOfWeek: baseDow, sessionType: .rest,
                                            isRestDay: true,
                                            week: importPermanent ? 0 : configWeek,
                                            isPermanent: importPermanent)
            instance.schedules.append(restSched)
        }

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

    // ═══════════════════════════════════════
    // BLOCKS TAB — current block params + sequence editor launcher
    // ═══════════════════════════════════════

    private var blocksTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Configure your mesocycle: block type, length, and recovery weeks. Use the Sequence Editor for multi-block periodization.")
                .font(.system(size: 12))
                .foregroundColor(.appTextDim)

            currentBlockCard

            // Block type picker
            VStack(alignment: .leading, spacing: 8) {
                Text("BLOCK TYPE").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(1)

                let goal = profile?.goal ?? .hypertrophy
                let isHyp = goal == .hypertrophy || goal == .recomp
                let types: [BlockType] = isHyp
                    ? [.accumulation, .reaccumulation, .deload]
                    : [.accumulation, .intensification, .reaccumulation, .peak, .deload]

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(types, id: \.self) { bt in
                        let label = blockTypeLabel(bt, isHyp: isHyp)
                        let selected = instance.blockType == bt
                        Button {
                            instance.blockType = bt
                            try? modelContext.save()
                        } label: {
                            VStack(spacing: 2) {
                                Text(label).font(.system(size: 12, weight: .black))
                                    .foregroundColor(selected ? .white : .appTextSecondary)
                                Text(blockTypeDetail(bt)).font(.system(size: 9))
                                    .foregroundColor(selected ? .white.opacity(0.8) : .appTextDim)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(selected ? Color.appRed : Color.appSurface)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .stroke(selected ? Color.appRed : Color.appBorder, lineWidth: 1))
                        }.buttonStyle(.plain)
                    }
                }
            }

            // Block length stepper
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("BLOCK LENGTH").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(1)
                    Text("Training weeks before deload").font(.system(size: 10)).foregroundColor(.appTextDim)
                }
                Spacer()
                Stepper(value: Binding(
                    get: { instance.blockLength },
                    set: { instance.blockLength = max(2, min(12, $0)); try? modelContext.save() }
                ), in: 2...12) {
                    Text("\(instance.blockLength) wk")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundColor(.appRed)
                        .frame(minWidth: 50, alignment: .trailing)
                }.labelsHidden()
                Text("\(instance.blockLength) wk")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(.appRed)
                    .frame(minWidth: 50, alignment: .trailing)
            }
            .padding(12).background(Color.appSurface).cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorder, lineWidth: 1))

            // Sequence editor launcher
            Button {
                if let onRequestSequenceEditor {
                    // Dismiss this sheet first; the parent presents the editor
                    // after a brief delay to let SwiftUI clear the stack.
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        onRequestSequenceEditor()
                    }
                } else {
                    // Fallback: try sheet-within-sheet
                    activeChildSheet = .blockSequenceEditor
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.stack.fill").font(.system(size: 12))
                    Text("OPEN SEQUENCE EDITOR")
                        .font(.system(size: 11, weight: .black)).kerning(0.5)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 10))
                }
                .foregroundColor(.appBlue)
                .padding(12).background(Color.appBlue.opacity(0.06)).cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBlue.opacity(0.25), lineWidth: 1))
            }.buttonStyle(.plain)

            Text("Sequence Editor lets you build multi-block plans (e.g., accumulation → intensification → peak) with exercise rotation rules.")
                .font(.system(size: 10)).foregroundColor(.appTextDim)
        }
    }

    private var currentBlockCard: some View {
        let weekLabel = instance.blockType == .deload
            ? "DELOAD WEEK"
            : "WEEK \(instance.blockWeek) OF \(instance.blockLength)"
        let progress = instance.blockLength > 0
            ? min(1.0, Double(instance.blockWeek) / Double(instance.blockLength))
            : 0.0
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("CURRENT BLOCK").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(1)
                Spacer()
                Text(weekLabel).font(.system(size: 10, weight: .black)).foregroundColor(.appRed).kerning(0.5)
            }
            HStack {
                Text(blockTypeLabel(instance.blockType, isHyp: profile?.goal == .hypertrophy || profile?.goal == .recomp))
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(.appTextPrimary)
                Spacer()
            }
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.appSurface2).frame(height: 6)
                    RoundedRectangle(cornerRadius: 3).fill(Color.appRed)
                        .frame(width: geo.size.width * CGFloat(progress), height: 6)
                }
            }.frame(height: 6)
        }
        .padding(14).background(Color.appSurface).cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))
    }

    private func blockTypeLabel(_ bt: BlockType, isHyp: Bool) -> String {
        if isHyp {
            switch bt {
            case .accumulation:    return "Training Block"
            case .reaccumulation:  return "Growth Phase"
            case .deload:          return "Recovery"
            case .intensification: return "Training Block"
            case .peak:            return "Training Block"
            }
        } else {
            switch bt {
            case .accumulation:    return "Accumulation"
            case .intensification: return "Intensification"
            case .reaccumulation:  return "Volume Phase"
            case .peak:            return "Peaking"
            case .deload:          return "Deload"
            }
        }
    }

    private func blockTypeDetail(_ bt: BlockType) -> String {
        switch bt {
        case .accumulation:    return "Build volume"
        case .intensification: return "Push intensity"
        case .reaccumulation:  return "Re-build volume"
        case .peak:            return "Test maxes"
        case .deload:          return "Recovery"
        }
    }

    // ═══════════════════════════════════════
    // SCHEDULE TAB — visual 7-day calendar with per-day actions
    // ═══════════════════════════════════════

    private var scheduleTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            scheduleWeekPicker
            Text("Tap a day to swap or clear. Schedule changes apply to this week only.")
                .font(.system(size: 11)).foregroundColor(.appTextDim)
            scheduleDayGrid
            scheduleDayActions
        }
    }

    private var scheduleWeekPicker: some View {
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
    }

    private var scheduleDayGrid: some View {
        HStack(spacing: 4) {
            ForEach(weekLayout, id: \.dow) { day in
                scheduleDayCell(day: day)
            }
        }
    }

    private func scheduleDayCell(day: (dow: Int, session: SessionType?)) -> some View {
        let isSelected = scheduleSelectedDow == day.dow
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                scheduleSelectedDow = isSelected ? nil : day.dow
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
            .frame(maxWidth: .infinity).frame(height: 56)
            .background(isSelected ? Color.appRed : (day.session != nil ? Color.appSurface : Color.appSurface2))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(
                isSelected ? Color.appRed : Color.appBorder, lineWidth: isSelected ? 2 : 1))
        }.buttonStyle(.plain)
    }

    @ViewBuilder
    private var scheduleDayActions: some View {
        if let dow = scheduleSelectedDow {
            scheduleSelectedDayCard(dow: dow)
        } else {
            HStack(spacing: 8) {
                Image(systemName: "hand.tap").font(.system(size: 13)).foregroundColor(.appTextDim)
                Text("Tap a day above to swap, clear, or replace it with another session.")
                    .font(.system(size: 11)).foregroundColor(.appTextSecondary)
            }
            .padding(10).background(Color.appBlue.opacity(0.05)).cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBlue.opacity(0.2), lineWidth: 1))
        }
    }

    private func scheduleSelectedDayCard(dow: Int) -> some View {
        let dayName = dowLabels[dow]
        let currentSession = weekLayout.first(where: { $0.dow == dow })?.session
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(dayName) — WEEK \(configWeek)")
                    .font(.system(size: 11, weight: .black)).foregroundColor(.appRed).kerning(1)
                Spacer()
                if currentSession != nil {
                    Button {
                        removeFromDay(dow: dow, permanent: false)
                        scheduleSelectedDow = nil
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

            Text("REPLACE WITH").font(.system(size: 9, weight: .black)).foregroundColor(.appTextDim).kerning(0.5)

            scheduleReplaceGrid(dow: dow)

            Text("Need a session from another program? Use the Import tab.")
                .font(.system(size: 10)).foregroundColor(.appTextDim).padding(.top, 4)
        }
        .padding(12).background(Color.appSurface.opacity(0.5)).cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appRed.opacity(0.3), lineWidth: 1))
    }

    private func scheduleReplaceGrid(dow: Int) -> some View {
        let rotation = baseRotation
        let unique = Array(Set(rotation))
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
            ForEach(unique, id: \.self) { st in
                Button {
                    replaceScheduleDay(dow: dow, with: st)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: sessionIcon(st)).font(.system(size: 10))
                            .foregroundColor(.appBlue)
                        Text(st.shortLabel)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.appTextPrimary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(Color.appSurface).cornerRadius(7)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.appBorder, lineWidth: 1))
                }.buttonStyle(.plain)
            }
        }
    }

    /// Same icon mapping as SessionTypePickerSheet — duplicated locally so the
    /// Schedule tab's per-session pills can show consistent icons without
    /// reaching across struct boundaries.
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

    /// Replaces the session on `dow` for the current configWeek with `newType`.
    /// Always week-scoped (not permanent) — the Schedule tab is for current-week
    /// adjustments. Permanent rotation changes belong in the Sessions tab.
    private func replaceScheduleDay(dow: Int, with newType: SessionType) {
        instance.schedules.removeAll { !$0.isPermanent && $0.dayOfWeek == dow && $0.week == configWeek }
        let sched = ProgramSchedule(dayOfWeek: dow, sessionType: newType,
                                     isRestDay: false, week: configWeek, isPermanent: false)
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
