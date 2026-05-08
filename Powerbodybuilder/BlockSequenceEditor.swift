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

                    // Block list
                    ForEach(Array(blocks.enumerated()), id: \.element.id) { idx, block in
                        blockCard(idx: idx, block: block)
                            .id(block.id)
                    }

                    // Add block
                    Button {
                        blocks.append(EditableBlock(
                            blockType: isHyp ? .accumulation : .accumulation,
                            weeks: instance.blockLength > 0 ? instance.blockLength : 4,
                            includeRecovery: true,
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
                if blocks.count > 1 {
                    Button { blocks.remove(at: idx) } label: {
                        Image(systemName: "trash").font(.system(size: 11)).foregroundColor(.appRed)
                            .frame(width: 36, height: 36).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
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

            // Recovery toggle + length
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

    private func loadCurrentBlocks() {
        let baseLen = instance.blockLength > 0 ? instance.blockLength : 4

        // Generate the full block sequence using BlockType.next()
        // Start from current block, generate ~6 cycles ahead
        var bt = instance.blockType
        var blockNum = instance.totalBlocksCompleted
        var result: [EditableBlock] = []

        // First block = current
        result.append(EditableBlock(
            blockType: bt, weeks: baseLen,
            includeRecovery: false, recoveryWeeks: 1,
            volumeMultiplier: defaultMultiplier(bt),
            isCurrent: true))

        // Generate future blocks (enough for ~6 training blocks + their recoveries)
        var trainingBlocksSeen = 0
        for _ in 0..<20 {
            let nextBT = BlockType.next(current: bt, goal: goal, blockNumber: blockNum)
            blockNum += 1
            bt = nextBT

            if bt == .deload {
                // Attach recovery to previous training block if it doesn't have one yet
                if let lastIdx = result.indices.last, !result[lastIdx].includeRecovery && result[lastIdx].blockType != .deload {
                    result[lastIdx].includeRecovery = true
                    result[lastIdx].recoveryWeeks = 1
                }
                continue
            }

            result.append(EditableBlock(
                blockType: bt, weeks: baseLen,
                includeRecovery: false, recoveryWeeks: 1,
                volumeMultiplier: defaultMultiplier(bt)))
            trainingBlocksSeen += 1
            if trainingBlocksSeen >= 5 { break }
        }

        blocks = result

        // Set scroll target to the focused block
        if focusBlockIndex < blocks.count {
            scrollTarget = blocks[focusBlockIndex].id
        }
    }

    private func applyChanges() {
        guard let first = blocks.first else { return }
        instance.blockLength = first.weeks
        instance.blockType = first.blockType

        // Translate the editable block sequence into a concrete deload-week
        // pattern. Each block contributes `weeks` training weeks followed by
        // its `recoveryWeeks` deload week(s). The resulting deload-week numbers
        // are stored as customDeloadWeeks; any program-default deloads that
        // fall on training weeks under the new layout get added to
        // skippedDeloadWeeks so they no longer fire.
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

        // Program-default deloads that are now training weeks → skip them.
        let programDefaults = UserProgramInstance.defaultDeloadWeeks(for: instance.programId)
        instance.skippedDeloadWeeks = programDefaults.intersection(trainingWeekNums)
        // Any new deload weeks not in the program default → mark custom.
        instance.customDeloadWeeks = Set(deloadWeekNums).subtracting(programDefaults)

        try? modelContext.save()
        dismiss()
    }
}
