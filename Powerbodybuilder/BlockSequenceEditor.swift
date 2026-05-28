import SwiftUI
import SwiftData

// ═══════════════════════════════════════════
// BLOCK SEQUENCE EDITOR
// Configure your mesocycle block structure:
// types, lengths, volume effects, rotation.
// ═══════════════════════════════════════════

struct BlockSequenceEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let instance: UserProgramInstance
    let profile: UserProfile?
    var focusBlockIndex: Int = 0

    @State private var blocks: [EditableBlock] = []
    @State private var rotationRule: String = "rotateT2T3"
    @State private var scrollTarget: UUID? = nil
    @State private var showResetConfirm: Bool = false

    private var goal: GoalType { profile?.goal ?? .hypertrophy }
    private var isHyp: Bool { goal == .hypertrophy || goal == .recomp }
    private var isSeeded: Bool { instance.programId <= 10 && instance.programId > 0 }

    struct EditableBlock: Identifiable {
        let id = UUID()
        var blockType: BlockType
        var weeks: Int
        var includeRecovery: Bool
        var recoveryWeeks: Int
        var volumeMultiplier: Double
        var isCurrent: Bool = false

        var totalWeeks: Int { weeks + (includeRecovery ? recoveryWeeks : 0) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.appBorder).frame(width: 36, height: 4).padding(.top, 12)

                    Text("BLOCK SEQUENCE").font(.system(size: 12, weight: .black)).foregroundColor(.appRed).kerning(2)

                    if isSeeded {
                        seededWarning
                    }

                    // Empty state — "Continuous Training" (no block structure)
                    if blocks.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "infinity").font(.system(size: 32)).foregroundColor(.appBlue)
                            Text("CONTINUOUS TRAINING")
                                .font(.system(size: 12, weight: .black)).foregroundColor(.appBlue).kerning(1.5)
                            Text("No block periodization — train through with no scheduled deloads. Tap Add Block below if you change your mind.")
                                .font(.system(size: 12)).foregroundColor(.appTextSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 12)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                        .background(Color.appBlue.opacity(0.04)).cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBlue.opacity(0.2), lineWidth: 1))
                    }

                    // Block list
                    ForEach(Array(blocks.enumerated()), id: \.element.id) { idx, block in
                        blockCard(idx: idx, block: block)
                            .id(block.id)
                    }

                    // Add block. Defaults `includeRecovery` to whatever's
                    // consistent with the user's current settings — false
                    // when Skip Deload Weeks is on, true otherwise.
                    Button {
                        let defaultRecovery = profile?.skipDeloads != true
                        blocks.append(EditableBlock(
                            blockType: isHyp ? .accumulation : .accumulation,
                            weeks: instance.blockLength > 0 ? instance.blockLength : 4,
                            includeRecovery: defaultRecovery,
                            recoveryWeeks: 1,
                            volumeMultiplier: 1.0))
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill").font(.system(size: 14))
                            Text("Add Block").font(.system(size: 13, weight: .bold))
                        }
                        .foregroundColor(.appBlue).frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Color.appBlue.opacity(0.06)).cornerRadius(8)
                    }.buttonStyle(.plain)

                    // Total duration
                    let total = blocks.reduce(0) { $0 + $1.totalWeeks }
                    HStack {
                        Text("Total program").font(.system(size: 12, weight: .bold)).foregroundColor(.appTextSecondary)
                        Spacer()
                        Text("\(total) weeks").font(.system(size: 14, weight: .black)).foregroundColor(.appRed)
                    }
                    .padding(12).background(Color.appSurface).cornerRadius(8)

                    // How blocks affect training
                    howBlocksWork

                    // Exercise rotation
                    rotationSection

                    // Reset to program default
                    Button { showResetConfirm = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.counterclockwise").font(.system(size: 12, weight: .bold))
                            Text("RESET TO PROGRAM DEFAULT")
                                .font(.system(size: 12, weight: .black)).kerning(0.5)
                        }
                        .foregroundColor(.appTextSecondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Color.appSurface).cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))
                    }.buttonStyle(.plain)

                    // Apply button
                    Button { applyChanges() } label: {
                        Text("APPLY BLOCK SEQUENCE")
                            .font(.system(size: 14, weight: .black)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Color.appRed).cornerRadius(12)
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 20).padding(.bottom, 40)
            }
            .background(Color.appBG)
            .onAppear {
                loadCurrentBlocks()
                // Scroll to focused block after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if let target = scrollTarget {
                        withAnimation { proxy.scrollTo(target, anchor: .center) }
                    }
                }
            }
            .alert("Reset block sequence?", isPresented: $showResetConfirm) {
                Button("Reset", role: .destructive) { resetToProgramDefault() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Restores the original deload schedule and block layout that came with this program. Any custom blocks you added will be cleared.")
            }
        }
    }

    // ── Block Card ──

    private func blockCard(idx: Int, block: EditableBlock) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(typeColor(block.blockType)).frame(width: 4, height: 16)
                    Text("Block \(idx + 1)").font(.system(size: 13, weight: .black)).foregroundColor(.appTextPrimary)
                    if block.isCurrent {
                        Text("NOW").font(.system(size: 8, weight: .black)).foregroundColor(.appRed).kerning(1)
                            .padding(.horizontal, 4).padding(.vertical, 1).background(Color.appRed.opacity(0.1)).cornerRadius(3)
                    }
                }
                Spacer()
                Text("\(block.totalWeeks) wks").font(.system(size: 11, weight: .bold)).foregroundColor(.appTextDim)
                Button {
                    // Resolve index by id at delete-time to avoid stale captured idx
                    // (prevents array-out-of-bounds crash on rapid taps / rerenders).
                    // Also: allow deleting to ZERO blocks — represents continuous training.
                    if let realIdx = blocks.firstIndex(where: { $0.id == block.id }),
                       realIdx < blocks.count {
                        blocks.remove(at: realIdx)
                    }
                } label: {
                    Image(systemName: "trash").font(.system(size: 11)).foregroundColor(.appRed)
                        .frame(width: 36, height: 36).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }

            // Block type picker
            HStack(spacing: 4) {
                ForEach(availableTypes, id: \.self) { bt in
                    Button { blocks[idx].blockType = bt; blocks[idx].volumeMultiplier = defaultMultiplier(bt) } label: {
                        Text(typeName(bt))
                            .font(.system(size: 10, weight: blocks[idx].blockType == bt ? .black : .medium))
                            .foregroundColor(blocks[idx].blockType == bt ? .white : typeColor(bt))
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(blocks[idx].blockType == bt ? typeColor(bt) : typeColor(bt).opacity(0.08))
                            .cornerRadius(5)
                    }.buttonStyle(.plain)
                }
            }

            // Training weeks stepper
            HStack {
                Text("Training weeks").font(.system(size: 12)).foregroundColor(.appTextSecondary)
                Spacer()
                HStack(spacing: 8) {
                    Button { if blocks[idx].weeks > 1 { blocks[idx].weeks -= 1 } } label: {
                        Image(systemName: "minus.circle.fill").font(.system(size: 18)).foregroundColor(.appTextDim)
                    }.buttonStyle(.plain)
                    Text("\(blocks[idx].weeks)").font(.system(size: 16, weight: .black, design: .rounded)).foregroundColor(.appRed)
                        .frame(width: 24)
                    Button { if blocks[idx].weeks < 12 { blocks[idx].weeks += 1 } } label: {
                        Image(systemName: "plus.circle.fill").font(.system(size: 18)).foregroundColor(.appRed)
                    }.buttonStyle(.plain)
                }
            }

            // Recovery toggle + length. Hidden entirely when the user has
            // Skip Deload Weeks on in Settings — adding recovery here while
            // skipDeloads is on would be a confusing no-op since the engine
            // would treat the week as training anyway.
            if profile?.skipDeloads != true {
                HStack {
                    Toggle("Recovery week", isOn: Binding(
                        get: { blocks[idx].includeRecovery },
                        set: { blocks[idx].includeRecovery = $0 }
                    ))
                    .font(.system(size: 12)).foregroundColor(.appTextSecondary).tint(.appBlue)

                    if blocks[idx].includeRecovery {
                        HStack(spacing: 6) {
                            Button { if blocks[idx].recoveryWeeks > 1 { blocks[idx].recoveryWeeks -= 1 } } label: {
                                Image(systemName: "minus").font(.system(size: 11, weight: .bold)).foregroundColor(.appBlue)
                                    .frame(width: 34, height: 34).contentShape(Rectangle()).background(Color.appBlue.opacity(0.06)).cornerRadius(6)
                            }.buttonStyle(.plain)
                            Text("\(blocks[idx].recoveryWeeks)").font(.system(size: 14, weight: .black, design: .rounded)).foregroundColor(.appBlue)
                            Button { if blocks[idx].recoveryWeeks < 3 { blocks[idx].recoveryWeeks += 1 } } label: {
                                Image(systemName: "plus").font(.system(size: 11, weight: .bold)).foregroundColor(.appBlue)
                                    .frame(width: 34, height: 34).contentShape(Rectangle()).background(Color.appBlue.opacity(0.06)).cornerRadius(6)
                            }.buttonStyle(.plain)
                            Text("wk").font(.system(size: 10)).foregroundColor(.appTextDim)
                        }
                    }
                }
            } else {
                // Skip Deloads on — surface why the toggle isn't here so the
                // user isn't left wondering what happened to it.
                HStack(spacing: 6) {
                    Image(systemName: "info.circle").font(.system(size: 11)).foregroundColor(.appTextDim)
                    Text("Recovery weeks disabled — Skip Deload Weeks is on in Settings.")
                        .font(.system(size: 10)).foregroundColor(.appTextDim)
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            // Volume effect
            HStack(spacing: 6) {
                Image(systemName: volumeIcon(block.blockType)).font(.system(size: 11)).foregroundColor(typeColor(block.blockType))
                Text(volumeDescription(block.blockType))
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(.appTextSecondary)
            }
            .padding(8).background(typeColor(block.blockType).opacity(0.04)).cornerRadius(6)
        }
        .padding(12).background(Color.appSurface).cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(
            block.isCurrent ? Color.appRed : Color.appBorder,
            lineWidth: block.isCurrent ? 2 : 1))
    }

    // ── Seeded Warning ──

    private var seededWarning: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill").foregroundColor(.appBlue)
            Text("This is a pre-built program. Block changes affect scheduling and labels. Exercise templates are fixed by the program.")
                .font(.system(size: 11)).foregroundColor(.appTextSecondary)
        }
        .padding(10).background(Color.appBlue.opacity(0.04)).cornerRadius(8)
    }

    // ── How Blocks Work ──

    private var howBlocksWork: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HOW BLOCKS AFFECT YOUR TRAINING").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(1)

            ForEach(availableTypes, id: \.self) { bt in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(typeColor(bt)).frame(width: 8, height: 8).padding(.top, 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(typeName(bt)).font(.system(size: 12, weight: .bold)).foregroundColor(.appTextPrimary)
                        Text(typeExplanation(bt)).font(.system(size: 11)).foregroundColor(.appTextDim)
                    }
                }
            }
        }
        .padding(12).background(Color.appSurface).cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))
    }

    // ── Rotation ──

    private var rotationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EXERCISE ROTATION BETWEEN BLOCKS").font(.system(size: 10, weight: .black)).foregroundColor(.appTextDim).kerning(1)
            ForEach(["keepAll", "rotateT2T3", "rotateAll"], id: \.self) { rule in
                Button { rotationRule = rule } label: {
                    HStack(spacing: 8) {
                        Image(systemName: rotationRule == rule ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(rotationRule == rule ? .appRed : .appTextDim)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(rotationName(rule)).font(.system(size: 12, weight: .bold)).foregroundColor(.appTextPrimary)
                            Text(rotationDetail(rule)).font(.system(size: 10)).foregroundColor(.appTextDim)
                        }
                        Spacer()
                    }
                    .padding(8)
                }.buttonStyle(.plain)
            }
        }
        .padding(12).background(Color.appSurface).cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))
    }

    // ── Helpers ──

    private var availableTypes: [BlockType] {
        isHyp ? [.accumulation, .reaccumulation, .deload] :
            [.accumulation, .intensification, .reaccumulation, .peak, .deload]
    }

    private func typeName(_ bt: BlockType) -> String {
        switch (isHyp, bt) {
        case (true, .accumulation): return "Training"
        case (true, .reaccumulation): return "Growth"
        case (true, .deload): return "Recovery"
        case (true, _): return "Training"
        case (false, _): return bt.rawValue.capitalized
        }
    }

    private func typeColor(_ bt: BlockType) -> Color {
        switch bt {
        case .accumulation: return .appGreen
        case .reaccumulation: return .appGold
        case .intensification: return .appOrange
        case .peak: return .appRed
        case .deload: return .appBlue
        }
    }

    private func typeExplanation(_ bt: BlockType) -> String {
        switch (isHyp, bt) {
        case (true, .accumulation): return "Standard volume. Progress by adding weight or reps each week."
        case (true, .reaccumulation): return "+15% more sets per muscle. Your body is primed after recovery — push the volume."
        case (true, .deload): return "Half volume, light weights. Reset fatigue for the next push."
        case (false, .accumulation): return "Build work capacity with moderate loads and higher volume."
        case (false, .intensification): return "Heavier weights, fewer reps. Transition from volume to intensity."
        case (false, .peak): return "Heaviest weights, minimal volume. Test your strength."
        case (false, .deload): return "Planned recovery. Reduced load to dissipate fatigue."
        case (false, .reaccumulation): return "Higher volume block. More sets to maximize hypertrophy."
        default: return "Standard training."
        }
    }

    private func volumeDescription(_ bt: BlockType) -> String {
        switch bt {
        case .accumulation: return "Standard volume (100%)"
        case .reaccumulation: return "+15% more sets per muscle"
        case .intensification: return "35% fewer sets, heavier loads"
        case .peak: return "50% fewer sets, maximum weight"
        case .deload: return "Maintenance volume only"
        }
    }

    private func volumeIcon(_ bt: BlockType) -> String {
        switch bt {
        case .accumulation: return "equal.circle.fill"
        case .reaccumulation: return "arrow.up.circle.fill"
        case .intensification: return "arrow.down.circle.fill"
        case .peak: return "bolt.circle.fill"
        case .deload: return "leaf.circle.fill"
        }
    }

    private func defaultMultiplier(_ bt: BlockType) -> Double {
        switch bt {
        case .accumulation: return 1.0
        case .reaccumulation: return 1.15
        case .intensification: return 0.65
        case .peak: return 0.50
        case .deload: return 1.0
        }
    }

    private func rotationName(_ r: String) -> String {
        switch r {
        case "keepAll": return "Keep All Exercises"
        case "rotateT2T3": return "Rotate Accessories"
        case "rotateAll": return "Rotate Everything"
        default: return r
        }
    }

    private func rotationDetail(_ r: String) -> String {
        switch r {
        case "keepAll": return "Same exercises every block — maximize progressive overload tracking"
        case "rotateT2T3": return "T1 anchors stay, T2/T3 accessories rotate — balanced variety"
        case "rotateAll": return "All exercises change between blocks — maximum variety"
        default: return ""
        }
    }

    // ── Load / Apply ──

    /// Total program weeks for the loaded instance — same source of truth
    /// used by applyChanges and the rest of the app.
    private var programWeeks: Int {
        (try? modelContext.fetch(FetchDescriptor<ProgramTemplate>())
            .first(where: { $0.programId == instance.programId })?.durationWeeks)
            ?? (instance.programId == 2 ? 16 : 24)
    }

    /// Loads the editor's block list. PREFERS the explicit `blockLayout`
    /// the user saved last time (round-trip fidelity), and falls back to
    /// reconstructing from the deload schedule for first-time use. Both
    /// paths produce a coherent block list — the difference is whether
    /// the saved boundaries are honored exactly.
    private func loadCurrentBlocks() {
        let total = programWeeks
        let currentWeek = instance.currentWeek

        // ── PRIMARY PATH: explicit user layout ──
        let saved = instance.blockLayout
        if !saved.isEmpty {
            var result: [EditableBlock] = []
            var weekCursor = 0
            for b in saved {
                let blockStart = weekCursor + 1
                let blockEnd = weekCursor + b.totalSpan
                let isCurrent = (blockStart...blockEnd).contains(currentWeek)
                result.append(EditableBlock(
                    blockType: b.blockType,
                    weeks: b.weeks,
                    includeRecovery: b.includeRecovery,
                    recoveryWeeks: b.recoveryWeeks,
                    volumeMultiplier: defaultMultiplier(b.blockType),
                    isCurrent: isCurrent))
                weekCursor = blockEnd
            }
            blocks = result
            if focusBlockIndex < blocks.count {
                scrollTarget = blocks[focusBlockIndex].id
            }
            return
        }

        // ── FALLBACK: derive from current deload schedule ──
        // Used the first time the editor opens (no saved layout yet).
        let deloads = deloadWeeks(for: instance.programId,
                                  blockLength: instance.blockLength,
                                  instance: instance)
        var result: [EditableBlock] = []
        var blockNumber = 1
        var trainingStart = 1
        var w = 1

        while w <= total {
            if deloads.contains(w) {
                let trainingLen = w - trainingStart
                if trainingLen > 0 {
                    let bt = blockTypeForNumber(blockNumber)
                    let isCurrent = (trainingStart...w).contains(currentWeek)
                    result.append(EditableBlock(
                        blockType: bt,
                        weeks: trainingLen,
                        includeRecovery: true,
                        recoveryWeeks: 1,
                        volumeMultiplier: defaultMultiplier(bt),
                        isCurrent: isCurrent))
                    blockNumber += 1
                }
                trainingStart = w + 1
            }
            w += 1
        }

        if trainingStart <= total {
            let trainingLen = total - trainingStart + 1
            let bt = blockTypeForNumber(blockNumber)
            let isCurrent = (trainingStart...total).contains(currentWeek)
            result.append(EditableBlock(
                blockType: bt,
                weeks: trainingLen,
                includeRecovery: false,
                recoveryWeeks: 0,
                volumeMultiplier: defaultMultiplier(bt),
                isCurrent: isCurrent))
        }

        blocks = result

        if focusBlockIndex < blocks.count {
            scrollTarget = blocks[focusBlockIndex].id
        }
    }

    /// Mirror of the block-type-from-number logic in ComputedBlockInfo so
    /// the editor and the rest of the app derive the same phase names.
    private func blockTypeForNumber(_ n: Int) -> BlockType {
        switch goal {
        case .hypertrophy, .recomp:
            return n % 2 == 1 ? .accumulation : .reaccumulation
        case .strength:
            let phase = (n - 1) % 3
            if phase == 0 { return .accumulation }
            if phase == 1 { return .intensification }
            return .peak
        case .powerbuilding:
            if n == 1 { return .accumulation }
            if n == 2 { return .intensification }
            return n % 2 == 1 ? .accumulation : .reaccumulation
        }
    }

    /// Restores the editor (and the saved instance state) to the program's
    /// original seeded deload schedule. Clears the explicit blockLayout AND
    /// the custom/skipped deload overrides so subsequent reads fall back
    /// to program defaults.
    private func resetToProgramDefault() {
        instance.blockLayout = []
        instance.skippedDeloadWeeks = []
        instance.customDeloadWeeks = []
        instance.blockLength = (profile?.experience == .beginner || profile?.experience == .intermediate) ? 5 : 4
        try? modelContext.save()
        loadCurrentBlocks()
    }

    private func applyChanges() {
        // No blocks = continuous training (no periodization, no deloads).
        // Save an empty layout AND fall back to long block-length + skip
        // defaults so the engine stops transitioning blocks.
        if blocks.isEmpty {
            let total = max(24, (try? modelContext.fetch(FetchDescriptor<ProgramTemplate>())
                .first(where: { $0.programId == instance.programId })?.durationWeeks) ?? 24)
            instance.blockLength = total + 1
            instance.blockType = .accumulation
            instance.skippedDeloadWeeks = UserProgramInstance.defaultDeloadWeeks(for: instance.programId)
            instance.customDeloadWeeks = []
            // Single span = whole program. SavedBlock with no recovery so
            // deloadWeeks() returns nothing for this layout.
            instance.blockLayout = [SavedBlock(
                blockType: .accumulation,
                weeks: total,
                includeRecovery: false,
                recoveryWeeks: 0)]
            try? modelContext.save()
            dismiss()
            return
        }

        // ── PERSIST THE EXPLICIT LAYOUT ──
        // This is the authoritative source for block boundaries — reloads
        // round-trip exactly because we save the user's choices verbatim
        // (block lengths, recovery on/off, block types) rather than
        // reconstructing from a deload schedule.
        instance.blockLayout = blocks.map { b in
            SavedBlock(blockType: b.blockType,
                       weeks: b.weeks,
                       includeRecovery: b.includeRecovery,
                       recoveryWeeks: b.recoveryWeeks)
        }

        let first = blocks[0]
        instance.blockLength = first.weeks
        instance.blockType = first.blockType

        // Translate the editable block sequence into a concrete deload-week
        // pattern. The blockLayout above is the primary source for the
        // editor, but customDeloadWeeks / skippedDeloadWeeks remain
        // populated for any legacy callers that don't yet read blockLayout.
        var deloadWeekNums: [Int] = []
        var trainingWeekNums: Set<Int> = []
        var weekCursor = 0
        for block in blocks {
            for _ in 0..<block.weeks {
                weekCursor += 1
                trainingWeekNums.insert(weekCursor)
            }
            if block.includeRecovery {
                for _ in 0..<block.recoveryWeeks {
                    weekCursor += 1
                    deloadWeekNums.append(weekCursor)
                }
            }
        }

        let programDefaults = UserProgramInstance.defaultDeloadWeeks(for: instance.programId)
        instance.skippedDeloadWeeks = programDefaults.intersection(trainingWeekNums)
        instance.customDeloadWeeks = Set(deloadWeekNums).subtracting(programDefaults)

        try? modelContext.save()
        dismiss()
    }
}
