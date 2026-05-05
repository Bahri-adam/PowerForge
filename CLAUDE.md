# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test

```bash
# Build (simulator — works when Xcode closed)
xcodebuild -project Powerbodybuilder.xcodeproj -scheme Powerbodybuilder -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' build

# Build (device — no signing, just compilation check)
xcodebuild -project Powerbodybuilder.xcodeproj -scheme Powerbodybuilder build -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO

# Run tests
xcodebuild -project Powerbodybuilder.xcodeproj -scheme Powerbodybuilder -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' test
```

No package manager dependencies. Pure SwiftUI + SwiftData. If Xcode is open, CLI builds fail with "database locked" — close Xcode first or build from Xcode with `Cmd+B`. User deploys to physical iPhone, not simulator.

If CLI builds fail with "xcode-select: error: tool 'xcodebuild' requires Xcode", run: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`

Tests use Swift Testing (`@Suite`, `@Test`) in `PowerbodybuilderTests/PowerbodybuilderTests.swift`. Helper functions: `makeLog()`, `makeSession()`, `daysAgo()`.

---

## File Inventory (26 Swift files)

| File | Role |
|------|------|
| `Models.swift` | All SwiftData models, enums, value types, override resolution helpers |
| `RPEEngine.swift` | Progression algorithm, stall detection, IFI, RPE table |
| `ExerciseDictionary.swift` | ~140 exercise definitions with muscles, stretch position, swap lists |
| `ExerciseLibrary.swift` | Exercise seed function + library browser UI (with custom exercise delete) |
| `ExerciseSwapSheet.swift` | Swap scoring, override creation, custom exercise creation, swap exclusions |
| `HomeView.swift` | Home tab — dashboard, week strip (with dates), volume tracking, schedule, workout log editor |
| `WorkoutView.swift` | Train tab — workout lifecycle, set logging, override-aware preview, finalization |
| `SettingsView.swift` | Settings tab — profile, tiers, program start date picker, algorithm explainer |
| `OnboardingView.swift` | 3-page setup wizard |
| `ProgramSelectionView.swift` | Program cards + recommendation |
| `ProgramBuilderView.swift` | 4-step custom program wizard with auto-periodization |
| `ProgramData.swift` | 8 built-in program definitions + recommendation engine |
| `ProgramSeeder.swift` | Powerbuilding program (ID 1) — 24-week DUP |
| `PPLSeeder.swift` | PPL program (ID 2) — 16-week 6-day split |
| `Bahrisplitseeder.swift` | Bahri Split (ID 7) — 24-week 6-day, 3x legs |
| `ContentView.swift` | Root navigation gating + seed orchestration |
| `PowerbodybuilderApp.swift` | @main entry, ModelContainer with error recovery (deletes store on schema failure) |
| `DesignSystem.swift` | Dark theme colors, reusable components |
| `LearnView.swift` | Education tab — RPE guides, form tips |
| `SplashScreen.swift` | Launch animation |
| `ProgramGenerator.swift` | Auto-periodized program generation: split structure, weekly set targets, exercise selection, block generation |
| `VolumeDecisionEngine.swift` | Signal-driven volume decisions: addSets/holdVolume/reduceSets/deload per muscle |
| `MRVSignalEngine.swift` | 5-signal MRV fatigue scoring per muscle, deload triggers |
| `GuardRails.swift` | 10 safety guards (G1–G10): volume clamps, progression blockers, tier order validation |
| `DebugDashboardView.swift` | Debug/diagnostics view |
| `ProgressView.swift` | Progress tab — 4 sections (Overview/Strength/Volume/History), PRs, e1RM trends, strength goals, balance ratios, genetic potential, predictive 1RM, frequency heatmap, workout history browser |
| `AnalyticsView.swift` | Analytics stub (unused) |
| `ProgramTabView.swift` | Program tab — Overview, Weeks, Templates, Exercises sections, BlockConfigCard, block sequence editor |
| `ProgramBuilderV2View.swift` | Program Builder V2 — Split/Exercises/Blocks/Analytics/Review sections |
| `BuilderState.swift` | ProgramBuilderState @Observable, BuilderBlock/Session/ExerciseV2 types, analytics engine |
| `BlockSequenceEditor.swift` | Block sequence configuration — types, lengths, recovery weeks, rotation rules |
| `ProgramConfiguratorSheet.swift` | Configure Program — Sessions tab, Week Override tab, Import tab (week portal + program catalog) |
| `GeneratedProgramPreviewView.swift` | Auto-generated program preview with live configurator |
| `DayTemplateViews.swift` | Day template CRUD — creator with expandable exercise cards (sets/reps/RPE/rest/notes), template library, template exercise picker |
| `ExerciseHistorySheet.swift` | Per-exercise history — e1RM chart, all sessions, cue editing, strength goal button |

---

## Architecture Overview

### Navigation Flow (`ContentView.swift`)

```
App Launch
  → PowerbodybuilderApp.init: ModelContainer with schema error recovery
  → onAppear: seed exercises, seed programs (3 seeders)
  → Gate:
      No UserProfile?       → OnboardingView (3 pages)
      No UserProgram?       → ProgramSelectionView
      Both exist?           → TabView [Home, Train, Program, Progress, Settings]
```

### Data Layer — SwiftData Models (`Models.swift`)

All models are `@Model` classes. Enums stored as raw strings (`sessionTypeRaw`) with computed property wrappers (`sessionType: SessionType`). This is a SwiftData limitation.

**Model container** (`PowerbodybuilderApp.swift`) registers 14 types with error recovery — if schema migration fails, the store is deleted and recreated:
`UserProfile`, `Exercise`, `ProgramTemplate`, `ProgramSessionTemplate`, `UserProgramInstance`, `ProgramSchedule`, `SessionOverride`, `ActiveWorkout`, `WorkoutLog`, `ProgressionState`, `UserProgram` (legacy), `LandmarkCalibration`, `DayTemplate`, `StrengthGoal`

#### Relationship Hierarchy

```
UserProgramInstance (aggregate root — all children cascade-delete)
├── ProgramSchedule[]        — weekly day→session mapping
├── SessionOverride[]        — exercise substitutions (week-scoped)
├── ActiveWorkout[]          — materialized workout snapshots
├── WorkoutLog[]             — per-set completion records (with workoutDate, readiness)
├── ProgressionState[]       — cached per-lift tracking (includes personalFatigueSensitivity)
├── LandmarkCalibration[]    — per-muscle adaptive volume boundaries
└── StrengthGoal[]           — active strength targets with phased peaking protocol
```

#### Key Models

**Exercise** — library entry. Fields: `exerciseKey`, `displayName`, `movementPatternRaw`, `musclesPrimary: [String]`, `musclesSecondary: [String]`, `equipmentRaw`, `isCompound`, `isCustom`, `stretchPositionRaw` (default `"mid"`), `jointStressTags`, `variationOfKey?`. Custom exercises can be deleted from the library.

**UserProfile** — user data. Fields: `name`, `bodyweight`, `age`, `useMetric`, `goalRaw`, `experienceRaw`, `daysPerWeek`, `priorityMuscles` (legacy), `muscleTiersData` (JSON `[String: String]`), `algorithmModeRaw` (full/suggestions/off), `progressionRateRaw` (fast/normal/slow). Computed `muscleTiers`, `algorithmMode`, `progressionRate`.

**ProgramSessionTemplate** — one slot in one week. Fields: `programId`, `programVersion`, `week`, `sessionTypeRaw`, `slotId`, `exerciseIndex`, `exerciseKey`, `roleRaw`, `isMainLift`, `targetSets`, `targetRepsLow`, `targetRepsHigh`, `targetRPE`, `restSeconds`, `notes`. SlotId convention: `"[SessionLetter][SlotNumber]"` e.g. `"A1"` = Heavy Upper slot 1.

**UserProgramInstance** — active program run. Fields: `programId`, `programVersion`, `name`, `startDate`, `microcycleIndex` (0-based week index), `nextRotationIndex`, `isActive`. Computed `currentWeek = microcycleIndex + 1`. Methods: `weekStartDate(for:)` computes calendar date for any week, `weekDateLabel(for:)` returns formatted date range string.

**SessionOverride** — exercise substitution scoped to specific weeks. Fields: `targetExerciseKey`, `targetSlotId`, `replacementExerciseKey`, `appliesFromWeek`, `scopeRaw` (`.single`/`.future`/`.range`), `scopeEndWeek?`, `isAddition`, `createdAt`. Method `appliesTo(week:)` checks whether override is active for a given week number. Global helper `resolveExerciseKey(slotId:originalKey:overrides:week:)` returns the effective exercise key for a slot at a given week.

**ActiveWorkout** — snapshot of a workout. Exercises stored as JSON-encoded `[RenderedExercise]` in `renderedExercisesData`. Each `RenderedExercise` contains `exerciseKey`, `slotId`, `targetSets/Reps/RPE`, and `sets: [RenderedSet]` where each set tracks `recommendedWeight`, `loggedWeight?`, `loggedReps?`, `loggedRPE?`, `isComplete`.

**WorkoutLog** — one completed set. Fields: `date` (set completion time), `workoutDate` (permanent session date — set once at finalization, never changed on edits), `week`, `exerciseKey`, `displayName`, `slotId`, `setIndex`, `weight`, `reps`, `rpe`, `e1rm`, `isMainLift`, `isTopSet`, `hitTargetReps`, `suggestedWeight`, `acceptedSuggestion`, `readiness` (1-5 pre-workout score). E1RM formula: `weight * (1 + reps/30)`. Method `recomputeE1RM()` recalculates from current weight/reps.

**ProgressionState** — cached per-lift state. Fields: `exerciseKey`, `bestE1RM`, `lastSessionWeight/Reps/RPE`, `consecutiveSuccesses/Failures`, `totalExposures`, `weeksAtSameLoad`, `isStalled`, `stallReasonRaw`, `lastIFI`, `ifiTrend`, `lastStallDiagnosisRaw`, `consecutiveStallDiagnoses`, `personalFatigueSensitivity` (adaptive PML sensitivity, default 0.12).

**StrengthGoal** — strength target with phased peaking. Fields: `exerciseKey`, `displayName`, `targetWeight`, `startE1RM`, `phaseRaw` (building/intensifying/peaking/testing), `phaseWeek`, `isActive`, `restSeconds`. Methods: `prescribeWeight()`, `advanceWeek()`. Phase lengths auto-scale based on gap% between start and target. Relationship: `programInstance: UserProgramInstance`.

**LandmarkCalibration** — adaptive volume boundaries per muscle. Fields: `muscleGroup`, `adjustedMEV/MavLow/MavHigh/MRV`, `weeksTracked`, `confidenceRaw`. Method `recalibrate()` shifts landmarks ±2 sets based on e1RM trends and IFI. Enforces MEV < MAVLow < MAVHigh < MRV.

#### Enums Reference

| Enum | Cases | Notes |
|------|-------|-------|
| `MovementPattern` | horizontalPush/Pull, verticalPush/Pull, squat, hinge, lunge, hipThrust, isolation, carry, core | 11 cases |
| `EquipmentType` | barbell, dumbbell, cable, machine, bodyweight, kettlebell, band, other | 8 cases |
| `SessionType` | heavyUpper/Lower, hypertrophyUpper/Lower, push/pull/legs, fullBody/A/B, upperPower, lowerPower, strengthHypertrophy, rest, legQuadFocus, legsPosterior, chestBack, armsDelts, chestArms, legsVolume, pushA/B, pullA/B, legsA/B, freeform | 27 cases |
| `ExerciseRole` | mainLift, supplemental, accessory, finisher | 4 tiers |
| `MuscleTier` | priority (1.5x), neutral (1.0x), maintenance (0.7x) | Volume scaling |
| `VolumeZone` | underTraining, building, optimal, overReaching | Classified from MEV/MAV/MRV |
| `IFIZone` | fresh (<0.10), optimal (0.10-0.25), fatigued (0.25-0.40), overtrained (≥0.40) | Rep drop-off zones |
| `StallDiagnosis` | fatigueStall, intensityStall, truePlateau, volumeStall, noStall | IFI + e1RM trend |
| `StallUrgency` | suggestion (1st), warning (2nd), actionRequired (3rd+) | Consecutive same diagnosis |
| `StretchPosition` | lengthened, mid, shortened | Per-exercise in ExerciseDictionary |
| `OverrideScope` | single, future, range | Week scoping for exercise swaps |
| `AlgorithmMode` | full, suggestions, off | Controls what the engine shows/auto-applies |
| `StrengthGoalPhase` | building, intensifying, peaking, testing | Phased strength peaking protocol |

---

### Progression Engine (`RPEEngine.swift`)

All functions are `static` on `ProgressionEngine`. No instance state.

#### `recommend()` — Main Entry Point

Decision pipeline (sequential — each layer can override the previous):

```
1. STRENGTH GOAL CHECK
   → If active StrengthGoal exists for this exercise (T1 only):
     override targetRepsLow/High, targetSets, targetRPE from goal.phase
     override weight from goal.prescribeWeight(currentE1RM)

2. DOUBLE PROGRESSION RULE
   → determineProgressionRule() returns .progress / .hold / .backoff
   → Primary signal (6+ sessions): e1RM EMA trend (>2.5% = progress, <-2.5% = backoff)
   → Secondary signal (<6 sessions): rep performance (all hit top = progress)
   → T3 ONLY: top-set progression (set 1 hits top → progress even if sets 2-3 didn't)
   → .progress: baseWeight = lastWeight + increment
   → .hold:     baseWeight = lastWeight
   → .backoff:  baseWeight = lastWeight × backoff% (T1=0.94, T2=0.90, T3=0.85)

3. IFI MODIFIER (if lastSessionIFI provided)
   → .fatigued + .progress → override to .hold
   → .overtrained → force backoff

4. RPE BRAKE
   → RPE ≥ 9.5 + progress → block progression
   → RPE ≤ 7.0 + hold → allow +5 lb bump

5. PML ADJUSTMENT (Prior Muscle Load)
   → Computes accumulated fatigue from prior exercises this session
   → Uses muscle overlap map (e.g., Chest→Triceps 0.40)
   → Multiplies baseWeight by fatigue coefficient (0.70-1.00)
   → personalFatigueSensitivity adapts per-user (error threshold 0.12)

6. PLATE ROUNDING → Metric: 2.5 kg. Imperial: 5.0 lbs.

7. PER-SET REP TARGETS (computePerSetReps)
   → NOT flat targetRepsHigh for every set
   → Each set gets lastWeekReps[setIndex] + bump
   → IFI modulates bump: FRESH=+2, OPTIMAL=+1, FATIGUED=0
   → Weight increase → targets drop to lastReps-2 (expect rep drop)
   → Backoff → targets go to targetRepsHigh (lighter, aim high)

8. BACKOFF WEIGHT (T1 only) → backoffWeight = recommended × 0.92

9. STALL DETECTION → detectStall() + diagnoseStallWithIFI()
```

#### Key Thresholds & Magic Numbers

| Value | What It Controls |
|-------|-----------------|
| 0.80 (80%) | Working set threshold: sets ≥80% of session max weight |
| 0.94/0.90/0.85 | Backoff per tier: T1=0.94, T2=0.90, T3=0.85 |
| 0.92 (8%) | Backoff set weight: main lift backoff sets = top × 0.92 |
| 185 lbs | Main lift increment threshold: ≥185 → +10 lbs, <185 → +5 lbs |
| 2.5 kg / 5.0 lbs | Accessory increment (metric / imperial) |
| 9.5 RPE | RPE brake: blocks progression above this |
| 7.0 RPE | RPE bump: allows +5 lb when holding below this |
| 3 sessions | Main lift stall detection minimum |
| 4 sessions | Accessory stall detection minimum |
| 0.99 (1%) | E1RM decline threshold for stall |
| 0.005 (0.5%) | E1RM flat threshold for stall |
| 2/3 + 1/3 | IFI EMA: `(trend × 2 + ifi) / 3` |
| 0.05 | Hysteresis band: IFI must move ±0.05 outside diagnosis band to switch |

#### `determineProgressionRule()`

- Filters working sets (≥80% session max)
- `.progress`: ALL working sets hit `targetRepsHigh`
- `.backoff`: 2+ working sets below `targetRepsLow` for 2 consecutive sessions
- `.hold`: everything else

#### `detectStall()`

- **Main lifts** (3+ sessions): Suppresses on first session at new weight (load jump). Checks e1RM decline (>1% below recent peak → `.e1rmDecline`), flat improvement (<0.5% over 3 sessions → `.e1rmFlat` or `.rpeRising` if RPE up >0.5).
- **Accessories** (4+ sessions): All 4 sessions have identical max reps at same load → `.repsFlat`.

#### `computeIFI()`

```
IFI = (firstWorkingSetReps - lastWorkingSetReps) / firstWorkingSetReps
```
Clamped 0–1. Working sets = ≥80% session max, sorted by setIndex.

#### `diagnoseStallWithIFI()`

Uses IFI trend + e1RM change rate + hysteresis:
- High IFI (>0.25) + declining e1RM → `.fatigueStall`
- Low IFI (<0.10) + flat e1RM → `.intensityStall`
- Mid IFI (0.10-0.25) + flat e1RM → `.truePlateau`
- Very high IFI (>0.30) → `.volumeStall`

Hysteresis: previous diagnosis sticks until IFI moves 0.05+ outside that diagnosis's band.

#### `updateProgressionState()`

Called after every workout. Updates: bestE1RM, success/failure streaks, weeksAtSameLoad, IFI + IFI trend (EMA), stall diagnosis with escalation counter.

---

### Exercise Dictionary (`ExerciseDictionary.swift`)

Single source of truth for all exercise metadata. Static data, not SwiftData.

**`ExerciseDefinition`** struct: `key`, `displayName`, `movementPattern`, `swapPattern` (granular for swap matching), `primaryMuscles`, `secondaryMuscles: [SecondaryMuscle]` (with variable weights 0.2–0.7), `equipment`, `isCompound`, `stretchPosition`, `jointStressTags`, `swapKeys` (ordered best→worst), `swapWarning?`, `variationOfKey?`, `isAnchorableAsTier1` (default false — only Chest/Back/Quads/Delts exercises have this set to true)

**`ExerciseDictionary.all`**: `[String: ExerciseDefinition]` — all ~140 exercises keyed by exerciseKey.

**`ExerciseDictionary.trackingMuscles`**: The canonical 9 groups used everywhere: `["Chest", "Back", "Quads", "Hamstrings", "Glutes", "Calves", "Biceps", "Triceps", "Delts"]`

**`ExerciseDictionary.normalizeMuscle(_ raw: String) -> String?`**: Maps detailed names to tracking groups. E.g. "Upper Chest" → "Chest", "Lats"/"Mid Back"/"Traps" → "Back", "Gastrocnemius"/"Soleus" → "Calves", "Brachialis" → "Biceps", "Rear Delts"/"Front Delts" → "Delts".

**Secondary muscle weights are variable** (not flat 0.5). E.g. chin-up = Biceps 0.7, pull-up = Biceps 0.5, barbell row = Biceps 0.5 + Rear Delts 0.5 + Traps 0.3.

**Swap rules**: Each exercise has ordered `swapKeys`. Hard rules: seated leg curl ↔ lying leg curl flagged with warning (different stretch profiles). Incline curl ↔ preacher curl flagged (opposite ends of stretch spectrum). Compound → isolation swap auto-warns.

**Swap exclusions**: `ExerciseSwapSheet.swapExclusions` dict blocks specific bad matches from fallback scoring (e.g. step_up excluded from hack_squat/leg_press/pendulum_squat swaps).

---

### Volume Tracking System

#### Volume Landmarks (`VolumeLandmark` in `Models.swift`)

4-point model per muscle: MEV (minimum effective), MAVLow, MAVHigh, MRV (maximum recoverable). Defaults in `VolumeLandmark.defaults` for all 9 tracking muscles.

Scaled by `MuscleTier.multiplier` (priority 1.5x, neutral 1.0x, maintenance 0.7x).

#### Volume Zone Classification (`VolumeZone.classify()`)

```
< MEV           → .underTraining (red)
MEV to MAVLow   → .building (yellow)
MAVLow to MRV   → .optimal (green)
> MRV            → .overReaching (orange)
```

#### Indirect Volume Tracking (`IndirectVolumeMap`)

`IndirectVolumeMap.secondaryWeights(for: exerciseKey)` looks up per-exercise secondary weights from ExerciseDictionary. Returns normalized tracking-muscle → weight map. Falls back to flat 0.5 (`IndirectVolumeMap.secondaryWeight`) for custom exercises not in the dictionary.

`HomeView.setsByMuscle` uses dictionary weights: primary muscles = 1.0 per set, secondary muscles = their specific weight (0.2–0.7).

---

### Program Generator (`ProgramGenerator.swift`)

Generates auto-periodized programs with 4 functions:

#### `resolveSplitStructure(daysPerWeek, goal, priorityMuscles)`

Returns `[GeneratedDayTemplate]` with session types and primary muscles per day.

| Days | Split | Notes |
|------|-------|-------|
| ≤2 | 2× Full Body (A/B) | Uses `allMuscles` (8 groups — **Calves omitted**) |
| 3 (strength) | 3× Full Body | Same allMuscles (no Calves) |
| 3 (other) | Push / Pull / Legs | Legs includes Calves |
| 4 | Upper/Lower ×2 (Heavy/Hypertrophy) | Calves on lower days |
| 5 | PPL + 2 priority sessions | Priority muscle → session type auto-resolved |
| 6 | PPL ×2 | Quad priority → legQuadFocus; hamstring/glute priority → legsPosterior |
| 7 | 6-day + Active Recovery (.rest) | Rest day skipped in generateBlock |

Priority muscles only affect splits at 5 and 6 days. Goal only affects 3-day split (strength vs non-strength).

#### `resolveWeeklySetTarget(muscle, week, blockType, ...)`

Pipeline: deload → baseMEV (calibration blend) → priorityBonus (+4) → blockMultiplier → weekAdjustment → previousBlockPeakSets cap → G1 clamp to MRV → G2 floor at MV.

Block multipliers: accumulation=1.0, intensification=0.65, reaccumulation=1.15, peak=0.50.

#### `selectExercisesForMuscle(muscle, setsNeeded, ...)`

Three-tier selection: T1 (compound + `isAnchorableAsTier1`) → T2 (any primary match) → T3 (isolation only).

**T1-anchorable muscles:** Chest, Back, Quads, Delts only. Biceps, Triceps, Calves, Hamstrings, Glutes have NO T1 anchors — all sets go to T2/T3.

Strength goal adds barbell-only filter on T1. T1 max 5 sets, T2 max 4+3 (two exercises), T3 max 3. Max assignable per call = 15 sets.

T2 rotation: prefers "rested" exercises (not used in previous block). Falls back to "resting" pool if insufficient rested candidates.

#### `generateBlock(...)`

Orchestrates full block generation: determines blockLength (experience × goal), iterates weeks 1...(blockLength+1), applies session set cap (24), duration budget, suggestedWeight from e1RM, RPE from blockType × tier table, validates G6/G7.

Block length: recomp=3, beginner/intermediate=5, advanced/elite=4. Extra +1 week is always deload.

---

### Volume Decision Engine (`VolumeDecisionEngine.swift`)

`decide(state, currentSets, mev, mrv)` → `VolumeDecision` (addSets/holdVolume/reduceSets/deload)

Priority order:
1. `.acuteOverreach` IFI → deload
2. `.fatigueStall` → deload
3. Load progressing (`.progress` or e1RM rising) → holdVolume
4. `respondsBetterTo == .lowVolumeHighIntensity` → holdVolume
5. `.backoff` rule → holdVolume
6. `.intensityStall` → holdVolume
7. `.fatigued` IFI or `.volumeStall` → reduceSets (max 2, down to MEV)
8. `evaluateStimulus()` — 4-signal weighted scoring (>0.5 score + ≥0.5 confidence) → addSets (1-2, up to MRV)
9. Default → holdVolume

---

### MRV Signal Engine (`MRVSignalEngine.swift`)

5 fatigue signals per muscle, point-based scoring with decay:
- S1: e1RM decline >2.5% → +3
- S2: IFI >0.30 → +2, IFI trend >0.25 → +2 (stack to +4 per exercise)
- S3: Stuck at same load 2+ weeks → +2
- S4: Volume-load declining week-over-week → +2
- S5: Rep miss rate >30% in last 20 hard sets → +1

Action thresholds: 0-2=none, 3-4=monitor, 5-6=reduceVolume, 7+=deload. Deload week resets to 0.

`requiresFullDeload()`: any muscle ≥8, OR 2+ priority muscles ≥5.

---

### Guard Rails (`GuardRails.swift`)

| Guard | Rule | Status |
|-------|------|--------|
| G1 clampToMRV | sets ≤ MRV | **Active** — resolveWeeklySetTarget |
| G2 floorAtMV | sets ≥ MV | **Active** — resolveWeeklySetTarget |
| G3 deloadSetFloor | deload sets ≥ 2 | **Defined only** — not called (mv() always ≥ 4) |
| G4 clampRPE | RPE ≤ 9.5 | **Defined only** — not called (max generated RPE = 9.0) |
| G5 blockProgressAfterBackoff | no .progress immediately after .backoff | **Active** — recommend() |
| G6 validateSessionSetCount | session ≤ 24 sets | **Active** — generateBlock (log-only; inline cap is the real enforcement) |
| G7 validateTierOrder | T1 before T2 before T3 per muscle | **Active** — generateBlock (log-only) |
| G8 allowProgressionSignal | ≥ 3 exposures before signals fire | **Active** — recommend() |
| G9 suppressPostDeload | no progression on week 1 after deload | **Active** — recommend() |
| G10 assertSameUnit | unit consistency | **Defined only** — no production call sites |

---

### Block Transitions (`BlockType.next()` in `Models.swift`)

Block phase computed property (`UserProgramInstance.blockPhase`):
- `blockType == .deload` → `.deload`
- `blockWeek == 1 && totalBlocksCompleted > 0` → `.postDeloadReintro`
- `blockWeek ≤ midpoint` → `.earlyAccumulation`
- `blockWeek > midpoint` → `.lateAccumulation`
- **Note:** `.intensification` is never returned, even during intensification blocks.

Block sequences (actual, as traced — see `ProgramGeneratorAudit.txt` for details):

| Goal | Sequence | Known Issues |
|------|----------|--------------|
| Hypertrophy | accum → deload → accum → deload → ... | `.reaccumulation` never triggers (blockNumber always odd at deload exit) |
| Strength (1st cycle) | accum → deload → intensification → deload → peak | Subsequent cycles skip intensification (blockNumber ≥ 3) |
| Powerbuilding | accum → deload → intensification → accum → ... | `.reaccumulation` never triggers (blockNumber always ≡1 mod 3) |
| Recomp | accum → deload → deload → deload → ... | **BUG:** infinite deload loop (`(.recomp, _)` catches deload→deload) |

---

### Exercise Swap System (`ExerciseSwapSheet.swift`)

#### Unified Swap Sheet

Both Home screen and mid-workout swaps use the same `ExerciseSwapSheet` with full features:
- Smart scoring with dictionary swap lists and fallback muscle/pattern scoring
- Scope picker: "THIS SESSION ONLY" / "ALL FUTURE SESSIONS"
- Custom exercise creation
- Muscle filter chips
- Swap warnings (exercise-specific + auto compound→isolation)

For freestyle mode (no program instance), `FreestyleSwapSheet` in WorkoutView provides scoring + custom exercise creation without SwiftData persistence.

#### Scoring Priority

1. **Dictionary swap list**: If slot exercise has `swapKeys`, candidates get position-based scores: 100, 90, 80, ... down to 30.
2. **Swap exclusions**: Hardcoded bad matches return score 0 (e.g. step_up for hack_squat).
3. **Fallback scoring**: Same primary muscle (+50), swap pattern match (+30), equipment (+10), compound/isolation (+10), stretch position (+15).

#### Override Persistence & Week Scoping

`SessionOverride` records use `appliesTo(week:)` to determine if they apply:
- `.single`: only the exact `appliesFromWeek`
- `.future`: all weeks ≥ `appliesFromWeek`
- `.range`: between `appliesFromWeek` and `scopeEndWeek`

The global `resolveExerciseKey(slotId:originalKey:overrides:week:)` function is used consistently in HomeView (`HubSessionCard`, `SessionDetailEditor`) and WorkoutView (`buildPreview`) to resolve the effective exercise key for any slot at any week.

---

### Program System

#### Built-in Programs

| ID | Name | Duration | Sessions | Seeder |
|----|------|----------|----------|--------|
| 0 | Freestyle | — | Freeform | None |
| 1 | Powerbuilding (DUP) | 24 weeks | Heavy Upper/Lower + Hypertrophy Upper/Lower | `ProgramSeeder.swift` |
| 2 | Pure Hypertrophy (PPL) | 16 weeks | Push A/B + Pull A/B + Legs A/B | `PPLSeeder.swift` |
| 7 | Bahri Split | 24 weeks | LegQuad, ChestBack, ArmsDelts, LegsPosterior, ChestArms, LegsVolume | `Bahrisplitseeder.swift` |
| 3-6 | Strength, Beginner, Athletic, Minimalist | — | Defined in ProgramData but not seeded | — |
| ≥100 | Custom | 24 weeks | User-defined | `ProgramBuilderView.swift` |

#### Seeding Pattern

All seeders are **versioned** and **idempotent**. Pattern:
1. Check `UserDefaults` for seed version
2. If version mismatch: delete old non-custom templates, re-insert from scratch
3. Update UserDefaults version

Bump `currentSeedVersion` constant in the seeder to push updates. Exercise seed version in `ExerciseLibrary.swift` (`exerciseSeedVersion = 2`).

#### Periodization Architecture

**Powerbuilding (ID 1)** — Dual-resolver: StrengthParams (sessions A+B) and HypertrophyParams (sessions C+D). Hypertrophy intentionally lags 1 sub-phase behind strength in RPE. 3 blocks: Accumulation (1-8), Intensification (9-16), Peaking (17-24). Deloads: 4, 12, 20. Testing: 24.

**PPL (ID 2)** — Single resolver, all 6 sessions synchronized. 2 blocks: Accumulation (1-8), Intensification (9-16). Deloads: 4, 12, 16.

**Bahri (ID 7)** — 3x legs/week. 3 blocks with frequent deloads (every 3 weeks). Dynamic rep shifts.

**Custom (≥100)** — Auto-periodized by `ProgramBuilderView.weekParams()`. Deloads at 4/12/20, testing at 24, 3-block progression.

#### Week Tracking & Dates

`UserProgramInstance.microcycleIndex` (0-based) advances after completing a rotation cycle. `currentWeek = microcycleIndex + 1`. `nextRotationIndex` tracks position in session rotation. Week advances in `WorkoutView.finalizeWorkout()` when `nextRotationIndex / rotationSize` changes.

`UserProgramInstance.startDate` anchors the calendar. `weekStartDate(for:)` computes the calendar date for any week. `weekDateLabel(for:)` returns a formatted "MMM d – MMM d" range. Start date is editable in Settings.

`HomeView.weekLogs` filters by `WorkoutLog.week == displayWeek`.

`WorkoutLog.workoutDate` is set once at finalization (from `session.startedAt`) and never changed during edits. `WorkoutLog.date` stores per-set completion timestamps. Recent sessions group by `workoutDate`.

---

### Workout Lifecycle (`WorkoutView.swift`)

```
1. BUILD PREVIEW — buildPreview(sessionType:)
   → Fetch ProgramSessionTemplate for (programId, week, sessionType)
   → Resolve overrides via resolveExerciseKey() per slot (week-scoped)
   → Check for active StrengthGoal → override T1 rep/set/RPE parameters
   → Accumulate priorExercisesForPML as we iterate exercises
   → Compute PML (Prior Muscle Load) per exercise from prior exercises
   → Call ProgressionEngine.recommend() per exercise (with pmlFactor)
   → Apply AlgorithmMode filter (Full=prefill, Suggestions=hints, Off=blank)
   → Generate WarmupSets for T1/T2 compounds
   → Create LiveExercise[] with LiveSet[] + WarmupSet[]
   → Attach PML notes and StrengthGoal phase badges to exercise notes

2. READINESS PROMPT — ReadinessPromptView
   → Shown between PreWorkoutView and ActiveWorkoutView
   → 1-5 numerical scale with descriptions of what each level adjusts
   → Skip defaults to 3 (Normal)
   → applyReadinessToSession() modifies all set weights/reps

3. ACTIVE WORKOUT — ActiveWorkoutView
   → User logs weight/reps/RPE per set
   → Warm-up section (collapsible, above working sets, T1/T2 only, not logged)
   → Two layout modes: paginated (swipe per exercise) or scroll (all visible)
   → Mid-workout swaps via ExerciseSwapSheet
   → ProgressiveOverloadCard shows stall diagnosis
   → Rest timer between sets

4. FINALIZE — finalizeWorkout(session:)
   1. Create WorkoutLog per logged set (workoutDate, readiness saved)
   2. Append logs, advance nextRotationIndex
   3. Update ProgressionState + PML sensitivity learning (learnFatigueSensitivity)
   4. Advance StrengthGoal phases (advanceWeek, check if target hit in testing)
   5. LandmarkCalibration.recalibrate() per trained muscle
   6. Advance blockWeek, block transitions
   7. MRV signal scoring, VDE decisions
   8. assessProgressionRate(), assessRespondsBetterTo()
   → Save to SwiftData
```

---

### Design System (`DesignSystem.swift`)

Dark navy theme. All colors are `Color` extensions.

| Token | Use |
|-------|-----|
| `.appBG` | Page background (darkest) |
| `.appSurface` | Card background |
| `.appSurface2` | Input/elevated surface |
| `.appBorder` | Subtle borders (0.6 opacity) |
| `.appTextPrimary` | Main text (off-white) |
| `.appTextSecondary` | Subtitle text (muted) |
| `.appTextDim` | Tertiary text (very dim) |
| `.appRed` | Primary CTA, accents |
| `.appGold` | Priority tier, custom badges |
| `.appGreen` | Success, optimal zone |
| `.appBlue` | Info, secondary actions |
| `.appYellow` | Building zone, caution |
| `.appOrange` | Over-reaching zone, warnings |

Reusable components: `AppCard` (modifier), `SectionHeader`, `PrimaryButton`, `AppTextField`, `AnimatedNumber`, `PremiumStatCell`.

---

## Key Conventions

- **Exercise keys**: snake_case — `bench_press_barbell`, `curl_incline_dumbbell`. Custom exercises: `custom_[name]_[timestamp]`.
- **SlotIds**: `"[SessionLetter][SlotNumber]"` — `"A1"` through `"D5"` etc.
- **Muscle names in code**: Use `ExerciseDictionary.trackingMuscles` (9 canonical groups) everywhere. Detailed names (Upper Chest, Lats, etc.) are normalized via `ExerciseDictionary.normalizeMuscle()`.
- **Muscle lists**: Never hardcode. Always use `ExerciseDictionary.trackingMuscles` or `ExerciseDictionary.exerciseFilters`.
- **Enum storage**: Always `fooRaw: String` stored + `foo: FooEnum` computed get/set.
- **E1RM formula**: `weight * (1 + reps/30)` (version 1).
- **Working sets**: ≥80% of session max weight.
- **SwiftData migration**: New fields MUST have default values in the property declaration (e.g. `var foo: String = "default"`). Add to init with default parameter. Computed property fallback handles nil/missing. Without defaults, `ModelContainer` init fails with "invalid reuse after initialization failure".
- **Seed versioning**: Bump `currentSeedVersion` (or `exerciseSeedVersion`) constant to re-seed on update.
- **ExerciseDictionary is static data** — not persisted in SwiftData. It feeds the seed function and swap scoring at runtime.
- **Override resolution**: Always use `resolveExerciseKey(slotId:originalKey:overrides:week:)` when resolving exercise keys. Never filter overrides without checking `appliesTo(week:)`.
- **Swap exclusions**: Add entries to `ExerciseSwapSheet.swapExclusions` to block bad fallback matches (exercises that score high via muscle matching but are poor swaps).
- **Workout dates**: `WorkoutLog.workoutDate` is immutable after creation. Use `workoutDate` for grouping/display. `date` is per-set completion time.
- **Custom exercises**: `isCustom = true` flag. Deletable from library. Logs preserve `exerciseKey`/`displayName` as strings, so history survives deletion.
- **ModelContainer error recovery**: `PowerbodybuilderApp.init()` catches schema failures, deletes the store, and retries. This handles breaking schema changes gracefully.

## Testing

Tests in `PowerbodybuilderTests.swift` use Swift Testing framework (`@Suite`, `@Test`). Helpers:
- `makeLog(weight:reps:setIndex:rpe:date:exerciseKey:isMainLift:)` — creates a `WorkoutLog`
- `makeSession(weight:reps:date:rpe:exerciseKey:isMainLift:)` — creates `[WorkoutLog]` (one per rep value)
- `daysAgo(_ days:)` — date offset helper

Test suites cover: double progression rules, weight increments, RPE brake, stall detection, IFI computation/zones, volume landmarks, muscle tiers, data confidence, progression state updates.

## Audit Documents

`ProgramGeneratorAudit.txt` — Comprehensive edge-case analysis covering 9 sections. Historical — some bugs fixed since.

`AlgorithmTraceReport.txt` — Hand-computed truth tables for every input→output combination.

## Python Algorithm Simulation — VALIDATED ✓

**Progression Engine Simulation:** `progression_sim_v7.py` is the final validated version. 46 realistic lifters covering beginners through elite, all tiers, PML edge cases, readiness patterns, stall scenarios, and strength goals. Growth rates calibrated to research (Helms, Nuckols): beginner 1-2%/wk, intermediate 0.08-0.20%/wk, advanced 0.02-0.06%/wk. Non-linear per-set fatigue model. RPE simulation. Run `python3 progression_sim_v7.py` to re-validate.

**Key validated thresholds:** IFI zones (0.10/0.25/0.40), PML sensitivity error threshold 0.12, backoff percentages (T1=0.94/T2=0.90/T3=0.85), e1RM noise floor 2.5%, sensitivity range 0.03-0.25.

**Program Audit:** `program_audit.py` v5 validates exercise selection algorithm. 29 profiles, 0 flags. Run `python3 program_audit.py` to regenerate `ProgramAudit.txt`.

**What the Python model implements (v5 — final):**
- Ranked exercise database with: `rank` (1-4), `head` (muscle head/region), `pattern` (movement), `restrict` (session type), `grp` (equipment group)
- T1/T2/T3 tier system with T1 cap (3 for 1x/week, 5 for 2x/week)
- Back dual T1 (vertical pull + horizontal row when ≥5 sets)
- Rear delt reservation (2 sets reserved upfront when Delts ≥6 sets)
- 1x/week forced head coverage: triceps long head, hamstrings knee flexion, biceps short head, calves soleus
- Category-based A/B detection (upper/lower/push/pull/legs)
- Session restrictions (deadlift/squats/leg exercises = lower_only)
- Movement pattern deduplication (no double pulldown)
- Biceps A=long head first, B=short head first; Calves A=gastro, B=soleus
- T1 cap reserves 2 sets for secondary head when volume supports it (≥5 sets)
- Cumulative key tracking across B and C sessions (Full Body B ≠ C)
- Tier sort within sessions (T1→T2→T3)
- Strength compounds use T1 rep range (2-5) even in T2 slots
- Equipment profiles: full_gym, no_cable, no_machine, home_gym, db_only
- Swap engine with same-head priority
- Low-volume muscle consolidation (<2 sets/session → skip B session)

**Swift Implementation Order (5 sessions):**

Session 1 — Exercise Database: Add `rank`, `head`, `pattern`, `restrict` fields to `ExerciseDefinition`. Set `isAnchorableAsTier1 = true` on rdl_barbell, close_grip_bench, hip_thrust_barbell. Add bodyweight calf raise. Update all exercise entries with head/pattern/restrict values from Python `E` dict.

Session 2 — `selectExercisesForMuscle()`: Port the full selection logic: equipment filter, session restriction, T1 cap by frequency, dual-T1 for Back, rear delt reservation, head-forced coverage for 1x/week, calves/biceps head alternation, strength compound rep override, tier sort. Add `sessionType`, `sessionsPerWeek`, `isSecondarySession` parameters.

Session 3 — Swap Engine: Create `SwapEngine.suggestions(for:)` with same-head priority sort, equipment filter, session restriction, exclude-in-session. Returns top 5 ranked.

Session 4 — `generateBlock()`: Wire category-based A/B detection, cumulative key tracking (all_seen_keys), remainder-first set distribution, session type detection, pass new params to selectExercisesForMuscle.

Session 5 — Block transitions & multipliers: Already partially applied (fixes 1-9 below). Verify multipliers match Python: accum=1.0, intens=0.65, reaccum=1.15, peak=0.50.

**Swift fixes already applied (need phone to build-test):**
1. Recomp infinite deload fix (Models.swift BlockType.next)
2. Hypertrophy accum↔reaccum alternation (cycle-based formula)
3. Powerbuilding intensification→deload transition added
4. MRV signal lastSignalDate now written (WorkoutView.swift)
5. T1 continuity bonus off-by-one fix (blockNumber > 0)
6. Calves added to allMuscles for 2/3-day splits
7. Integer division remainder fix (partial — in generateBlock)
8. 4 test fixes for G8 suppression (makeProgState)

**Known limitations to address post-launch:**
- Rep ranges fixed per goal, not per block phase (intensification/peak should shift T1 to lower reps) — PARTIALLY ADDRESSED by StrengthGoal phase overrides
- Recomp 3-week blocks limit per-block adaptation signal — by design, documented

---

## Progression Engine v4 Features (Implemented in Swift)

All features below are validated in Python (`progression_sim_v7.py`) with 46 lifters and zero regressions, then implemented in Swift.

### Per-Set Rep Targets (`computePerSetReps` in RPEEngine.swift)
Instead of flat `targetRepsHigh` for every set, each set gets `lastWeekReps[setIndex] + bump`. IFI modulates bump: FRESH=+2, OPTIMAL=+1, FATIGUED=0. Weight increase → targets drop by 2. Backoff → targets go to targetRepsHigh. T3 exercises get top-set progression (set 1 hits top → progress even if sets 2-3 didn't). T1/T2 compounds keep all-sets-must-hit-top rule.

### Algorithm Modes (`AlgorithmMode` enum, `UserProfile.algorithmModeRaw`)
- **Full**: Weight pre-filled, per-set targets shown, volume/stall decisions auto-applied
- **Suggestions**: Weight shown as gray hint (not pre-filled), targets as hints, decisions shown as cards
- **Off**: Blank fields, no recommendations. Algorithm still tracks e1RM/IFI/streaks in background.
Settings UI: ALGORITHM section in SettingsView with radio buttons.

### Pre-Workout Readiness (`ReadinessPromptView` in WorkoutView.swift)
1-5 numerical scale shown between PreWorkoutView and ActiveWorkoutView. Each level shows description + what the algorithm adjusts. Skip defaults to 3. Modifiers: 1=weight×0.90 reps-3, 2=weight×0.95 reps-1, 3=none, 4=reps+1, 5=weight×1.02 reps+2. Score saved to `WorkoutLog.readiness`.

### Warm-Up Set Generation (`generateWarmupSets` in RPEEngine.swift)
T1/T2 compounds get auto-generated warm-up ramp: bar→40%→60%→75%→90% of working weight. Shown as collapsible orange-tinted section above working sets in ActiveWorkoutView. Visual checkmarks (not logged). Skips T3 isolation. Handles dedup and light weights.

### PML — Prior Muscle Load (`computePML`, `learnFatigueSensitivity` in RPEEngine.swift)
Tracks accumulated muscle fatigue from prior exercises in the session using overlap map (e.g., Chest→Triceps 0.40). Computes fatigue coefficient (0.70-1.00). Adjusts recommended weight down. `personalFatigueSensitivity` on ProgressionState adapts per-user (default 0.12, range 0.03-0.25, error threshold 0.12 before adjusting, learning rate decays with exposure). When PML adjustment >3%, exercise notes show "Adjusted for prior chest work".

### Strength Goals (`StrengthGoal` model, `StrengthGoalPhase` enum)
Users set strength targets (e.g., "Bench 275lb") with two modes:
- **Adjust program**: Overrides T1 slot to strength rep ranges. 4-phase peaking: Building (4×3-5 RPE 7.5) → Intensifying (3×2-3 RPE 8.5) → Peaking (2×1-2 RPE 9) → Testing (1×1 RPE 10). Phase lengths auto-scale by gap%. Weight prescribed from phase % of e1RM. Rest of program stays hypertrophy.
- **Track only**: Just tracks progress toward target, no program changes.
Max 2 active goals. Phase advances in finalizeWorkout(). Goal achieved when user hits target weight in testing phase. Entry points: Progress tab Strength section + ExerciseHistorySheet.

### Strength Balance Ratios (`StrengthAnalytics.computeBalanceRatios`)
Computes from logged e1RMs: Push:Pull (ideal 0.85-1.15), Posterior:Anterior (0.70-1.10), OHP:Bench (0.55-0.75), Squat:Deadlift (0.75-0.90). Shown in Progress tab Strength section with bar indicators and imbalance advice.

### Genetic Potential Estimation (`StrengthAnalytics.estimateGeneticPotential`)
Bodyweight-relative ceilings for natural lifters: bench 1.75×, squat 2.25×, deadlift 2.75×, OHP 1.15×, hack squat 2.0×, etc. Shows current/ceiling with % bars. Tier labels: Beginner (<40%), Intermediate (40-60%), Advanced (60-80%), Elite (80%+).

### Predictive 1RM Timeline (`StrengthAnalytics.predictTimeToTarget`)
Linear regression on session-grouped e1RM data. Requires 4+ sessions. Returns weekly gain rate, estimated weeks to target, confidence level. Shown below e1RM trend chart: "At current rate: 315lb in ~8 weeks". Auto-targets strength goal target or next 25lb milestone.

### Progress Tab (`ProgressView.swift`)
4 sections: Overview (stats, most improved, recent PRs, weak points), Strength (goals, PRs, e1RM trend with prediction, balance ratios, genetic potential), Volume (line chart with muscle filter, frequency heatmap), History (all sessions + searchable exercise browser with drill-down).
