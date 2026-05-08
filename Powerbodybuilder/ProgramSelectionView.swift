import SwiftUI
import SwiftData

struct ProgramSelectionView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query private var profiles: [UserProfile]
    @Query private var allInstances: [UserProgramInstance]
    @Query private var allUserPrograms: [UserProgram]
    @Query private var allSessionTemplates: [ProgramSessionTemplate]
    @Query private var allProgramTemplates: [ProgramTemplate]

    var profile: UserProfile? { profiles.first }

    let recommendedId: Int
    var onComplete: (() -> Void)? = nil

    @State private var selectedId: Int
    @State private var showDetail: ProgramDef? = nil
    @State private var showGeneratedPreview = false
    @State private var pendingDelete: ProgramDef? = nil

    init(recommendedId: Int, onComplete: (() -> Void)? = nil) {
        self.recommendedId = recommendedId
        self.onComplete = onComplete
        _selectedId = State(initialValue: recommendedId)
    }
    
    var body: some View {
        ZStack {
            Color.appBG
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                
                // HEADER
                VStack(spacing: 6) {
                    Text("CHOOSE YOUR PROGRAM")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(.appTextPrimary)
                    
                    Text("We recommended a program based on your goals")
                        .font(.system(size: 13))
                        .foregroundColor(.appTextSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(Color.appSurface)
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.appBorder),
                    alignment: .bottom
                )
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        
                        // RECOMMENDED BANNER
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 14))
                                .foregroundColor(.appGold)
                            Text("Based on your goals, we recommend \(allPrograms.first(where: { $0.id == recommendedId })?.name ?? "")")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.appTextSecondary)
                            Spacer()
                        }
                        .padding(14)
                        .background(Color.appGold.opacity(0.08))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.appGold.opacity(0.25), lineWidth: 1)
                        )
                        
                        // PROGRAM CARDS
                        ForEach(allAvailablePrograms, id: \.id) { program in
                            ProgramCard(
                                program: program,
                                isRecommended: program.id == recommendedId,
                                isSelected: program.id == selectedId,
                                isDeletable: program.id >= 100,
                                onSelect: { selectedId = program.id },
                                onDetail: { showDetail = program },
                                onDelete: { pendingDelete = program }
                            )
                        }
                        
                        // START / PREVIEW BUTTON
                        if profile?.useGeneratedPrograms == true {
                            PrimaryButton(title: "PREVIEW PROGRAM", icon: "eye.fill") {
                                showGeneratedPreview = true
                            }
                            .padding(.top, 8)
                        } else {
                            PrimaryButton(title: "START PROGRAM", icon: "play.fill") {
                                startProgram()
                            }
                            .padding(.top, 8)
                        }

                        PrimaryButton(title: "START PROGRAM", icon: "play.fill") {
                            startProgram()
                        }
                        .padding(.top, 4)
                        .padding(.bottom, 40)
                    }
                    .padding(16)
                }
            }
        }
        .sheet(item: $showDetail) { program in
            ProgramDetailView(program: program)
        }
        .alert("Delete \(pendingDelete?.name ?? "Program")?",
               isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } })) {
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete", role: .destructive) {
                if let p = pendingDelete { deleteCustomProgram(p) }
                pendingDelete = nil
            }
        } message: {
            Text("This permanently removes the program template, exercises, and any logged workouts under it. This cannot be undone.")
        }
        .fullScreenCover(isPresented: $showGeneratedPreview) {
            NavigationStack {
                GeneratedProgramPreviewView(
                    programId: selectedId,
                    programName: allAvailablePrograms.first(where: { $0.id == selectedId })?.name ?? "Generated Program"
                )
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back") { showGeneratedPreview = false }
                            .foregroundColor(.appTextSecondary)
                    }
                }
            }
        }
    }
    
    func startProgram() {
        let program = allAvailablePrograms.first(where: { $0.id == selectedId })
        guard let program = program else { return }

        // Infer goal from program choice and update profile
        if let prof = profile {
            switch selectedId {
            case 2, 7: prof.goal = .hypertrophy
            case 3: prof.goal = .strength
            case 1: prof.goal = .powerbuilding
            case 5: prof.goal = .powerbuilding
            default: break
            }
            let days = program.days_per_week_range.lowerBound
            if prof.daysPerWeek < days || prof.daysPerWeek > program.days_per_week_range.upperBound {
                prof.daysPerWeek = days
            }
        }

        // 1. Deactivate ALL existing instances & legacy programs
        for inst in allInstances {
            inst.isActive = false
        }
        for up in allUserPrograms {
            up.isActive = false
        }

        // 2. Reactivate existing instance for this program, or create new
        if let existing = allInstances.first(where: { $0.programId == selectedId }) {
            existing.isActive = true
            // Reset week tracking when switching back to a program
            existing.microcycleIndex = 0
            existing.blockWeek = 1
            existing.nextRotationIndex = 0
            // Seeded programs are not generated
            if selectedId <= 10 { existing.isGenerated = false }
        } else {
            let instance = UserProgramInstance(
                programId: selectedId,
                programVersion: 1,
                name: program.name,
                missedWorkoutPolicy: .rotation
            )
            modelContext.insert(instance)
        }

        // 3. Same for legacy UserProgram
        if let existingLegacy = allUserPrograms.first(where: { $0.programId == selectedId }) {
            existingLegacy.isActive = true
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let today = formatter.string(from: Date())
            let userProgram = UserProgram(
                programId: selectedId,
                name: program.name,
                startDate: today
            )
            modelContext.insert(userProgram)
        }

        // Generate block ONLY for auto-generated programs (ID > 10).
        // Seeded programs (ID 1-10) already have templates from their seeders
        // and must NOT go through ProgramGenerator or templates will stack.
        if selectedId > 10,
           let profile = profile,
           profile.useGeneratedPrograms,
           let inst = allInstances.first(where: { $0.programId == selectedId && $0.isActive }),
           !inst.isGenerated {
            do {
                inst.isGenerated = true
                let templates = try ProgramGenerator.generateBlock(
                    profile: profile,
                    instance: inst,
                    blockNumber: inst.totalBlocksCompleted + 1,
                    blockType: .accumulation,
                    previousBlockPeakSets: nil,
                    allLogs: inst.logs,
                    progressionStates: inst.progressionStates,
                    modelContext: modelContext)
                templates.forEach { modelContext.insert($0) }
                print("ProgramGenerator: generated \(templates.count) templates")
            } catch {
                print("ProgramGenerator: fallback to seeder — \(error)")
                inst.isGenerated = false
            }
        }

        // For seeded programs, ensure isGenerated is false and wipe/reseed if
        // templates are duplicated (corrupt state from a previous buggy code path).
        if selectedId <= 10,
           let inst = allInstances.first(where: { $0.programId == selectedId && $0.isActive }) {
            inst.isGenerated = false

            // Detect duplication: if the same (week, sessionType, exerciseIndex)
            // appears more than once, the templates have been stacked.
            let programSlots = allSessionTemplates.filter { $0.programId == selectedId }
            var seenKeys = Set<String>()
            var hasDuplicates = false
            for s in programSlots {
                let key = "\(s.week)|\(s.sessionTypeRaw)|\(s.exerciseIndex)|\(s.slotId)"
                if seenKeys.contains(key) {
                    hasDuplicates = true
                    break
                }
                seenKeys.insert(key)
            }

            if hasDuplicates {
                print("Cleanup: detected duplicate templates for program \(selectedId) — wiping \(programSlots.count) and re-seeding")
                // Wipe all session templates and program template for this program
                for s in programSlots { modelContext.delete(s) }
                let programs = allProgramTemplates.filter { $0.programId == selectedId }
                for p in programs { modelContext.delete(p) }

                try? modelContext.save()

                // Re-seed based on program ID
                switch selectedId {
                case 1: ProgramSeeder.seedPowerbuildingProgram(context: modelContext)
                case 2: PPLSeeder.seedPPLProgram(context: modelContext)
                case 7: BahriSplitSeeder.seedIfNeeded(context: modelContext)
                default: break
                }
            }
        }

        try? modelContext.save()
        onComplete?()
        dismiss()
    }

    /// Cascade-delete a custom program: ProgramTemplate, ProgramSessionTemplates,
    /// UserProgramInstances (with their cascaded children — logs, schedules,
    /// overrides, progression states, strength goals), and UserPrograms for the
    /// matching pid. Updates the runtime customPrograms list. Won't accept
    /// built-in pids (< 100).
    func deleteCustomProgram(_ program: ProgramDef) {
        guard program.id >= 100 else { return }
        let pid = program.id

        for tmpl in allProgramTemplates where tmpl.programId == pid {
            modelContext.delete(tmpl)
        }
        for st in allSessionTemplates where st.programId == pid {
            modelContext.delete(st)
        }
        for inst in allInstances where inst.programId == pid {
            modelContext.delete(inst)
        }
        for up in allUserPrograms where up.programId == pid {
            modelContext.delete(up)
        }

        try? modelContext.save()
        customPrograms.removeAll { $0.id == pid }

        // If the deleted program was the active selection, fall back to a built-in
        if selectedId == pid {
            selectedId = recommendedId
        }
    }

    // ═══════════════════════════════════════════
    // PROGRAM CARD
    // ═══════════════════════════════════════════

    struct ProgramCard: View {
        let program: ProgramDef
        let isRecommended: Bool
        let isSelected: Bool
        var isDeletable: Bool = false
        let onSelect: () -> Void
        let onDetail: () -> Void
        var onDelete: (() -> Void)? = nil
        
        var body: some View {
            Button(action: onSelect) {
                VStack(spacing: 0) {
                    
                    // TOP ROW
                    HStack(spacing: 12) {
                        
                        // Icon
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(program.accentColor.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: program.icon)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(program.accentColor)
                        }
                        
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(program.name)
                                    .font(.system(size: 15, weight: .black, design: .rounded))
                                    .foregroundColor(.appTextPrimary)
                                
                                if isRecommended {
                                    Text("RECOMMENDED")
                                        .font(.system(size: 8, weight: .black))
                                        .foregroundColor(.appGold)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.appGold.opacity(0.15))
                                        .cornerRadius(3)
                                }
                            }
                            
                            Text(program.subtitle)
                                .font(.system(size: 12))
                                .foregroundColor(.appTextSecondary)
                        }
                        
                        Spacer()
                        
                        // Selected indicator
                        ZStack {
                            Circle()
                                .stroke(isSelected ? program.accentColor : Color.appBorder, lineWidth: 2)
                                .frame(width: 22, height: 22)
                            
                            if isSelected {
                                Circle()
                                    .fill(program.accentColor)
                                    .frame(width: 13, height: 13)
                            }
                        }
                    }
                    .padding(14)
                    
                    // STATS ROW
                    HStack(spacing: 0) {
                        MiniStat(label: "DAYS", value: program.days)
                        Divider()
                            .background(Color.appBorder)
                            .frame(height: 24)
                        MiniStat(label: "SESSION", value: program.sessionLength)
                        Divider()
                            .background(Color.appBorder)
                            .frame(height: 24)
                        MiniStat(label: "LEVEL", value: program.difficulty)
                    }
                    .background(Color.appBG.opacity(0.5))
                    
                    // TAGS + INFO BUTTON
                    HStack(spacing: 6) {
                        ForEach(program.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(program.accentColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(program.accentColor.opacity(0.1))
                                .cornerRadius(6)
                        }

                        Spacer()

                        if isDeletable, let onDelete {
                            Button(action: onDelete) {
                                Image(systemName: "trash")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.appRed)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Color.appRed.opacity(0.08))
                                    .cornerRadius(6)
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.appRed.opacity(0.2), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }

                        Button(action: onDetail) {
                            HStack(spacing: 4) {
                                Text("Details")
                                    .font(.system(size: 11, weight: .semibold))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundColor(.appTextDim)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .background(
                    ZStack {
                        Color.appSurface
                        if isSelected {
                            program.accentColor.opacity(0.05)
                        }
                    }
                )
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            isSelected ? program.accentColor.opacity(0.6) : Color.appBorder,
                            lineWidth: isSelected ? 1.5 : 1
                        )
                )
                .shadow(
                    color: isSelected ? program.accentColor.opacity(0.15) : Color.black.opacity(0.2),
                    radius: isSelected ? 10 : 6,
                    x: 0,
                    y: 3
                )
            }
            .buttonStyle(.plain)
        }
    }
    
    // ═══════════════════════════════════════════
    // MINI STAT
    // ═══════════════════════════════════════════
    
    struct MiniStat: View {
        let label: String
        let value: String
        
        var body: some View {
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.appTextDim)
                    .kerning(1)
                Text(value)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.appTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
    
    // ═══════════════════════════════════════════
    // PROGRAM DETAIL VIEW
    // ═══════════════════════════════════════════
    
    struct ProgramDetailView: View {
        let program: ProgramDef
        @Environment(\.dismiss) private var dismiss
        
        var body: some View {
            ZStack {
                Color.appBG
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    
                    // HEADER
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.appTextSecondary)
                                .padding(10)
                                .background(Color.appSurface2)
                                .clipShape(Circle())
                        }
                        Spacer()
                    }
                    .padding(20)
                    
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 20) {
                            
                            // ICON + NAME
                            VStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(program.accentColor.opacity(0.15))
                                        .frame(width: 72, height: 72)
                                    Image(systemName: program.icon)
                                        .font(.system(size: 30, weight: .bold))
                                        .foregroundColor(program.accentColor)
                                }
                                
                                VStack(spacing: 4) {
                                    Text(program.name)
                                        .font(.system(size: 26, weight: .black, design: .rounded))
                                        .foregroundColor(.appTextPrimary)
                                    Text(program.subtitle)
                                        .font(.system(size: 14))
                                        .foregroundColor(.appTextSecondary)
                                }
                            }
                            
                            // STATS GRID
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                DetailStat(label: "DAYS PER WEEK", value: program.days, icon: "calendar")
                                DetailStat(label: "SESSION LENGTH", value: program.sessionLength, icon: "clock.fill")
                                DetailStat(label: "SPLIT", value: program.split, icon: "rectangle.split.2x1.fill")
                                DetailStat(label: "DIFFICULTY", value: program.difficulty, icon: "chart.bar.fill")
                                DetailStat(label: "REP RANGES", value: program.repRanges, icon: "arrow.up.arrow.down")
                                DetailStat(label: "VOLUME", value: program.volumePerMuscle, icon: "flame.fill")
                            }
                            
                            // DESCRIPTION
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: "OVERVIEW")
                                Text(program.description)
                                    .font(.system(size: 14))
                                    .foregroundColor(.appTextSecondary)
                                    .lineSpacing(4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(16)
                            .appCard()
                            
                            // WHO ITS FOR
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: "WHO IT'S FOR")
                                Text(program.whoItsFor)
                                    .font(.system(size: 14))
                                    .foregroundColor(.appTextSecondary)
                                    .lineSpacing(4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(16)
                            .appCard()
                            
                            // TAGS
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: "FOCUSES")
                                HStack(spacing: 8) {
                                    ForEach(program.tags, id: \.self) { tag in
                                        Text(tag)
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(program.accentColor)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                            .background(program.accentColor.opacity(0.1))
                                            .cornerRadius(8)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(program.accentColor.opacity(0.3), lineWidth: 1)
                                            )
                                    }
                                }
                            }
                            .padding(16)
                            .appCard()
                        }
                        .padding(16)
                        .padding(.bottom, 40)
                    }
                }
            }
        }
    }
    
    // ═══════════════════════════════════════════
    // DETAIL STAT CELL
    // ═══════════════════════════════════════════
    
    struct DetailStat: View {
        let label: String
        let value: String
        let icon: String
        
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                        .foregroundColor(.appTextDim)
                    Text(label)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.appTextDim)
                        .kerning(1)
                }
                Text(value)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.appTextSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appCard()
        }
    }
}
