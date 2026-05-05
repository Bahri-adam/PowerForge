# Smart Progression Engine — Technical Reference

This document describes every decision the Powerbodybuilder progression engine makes, what inputs drive those decisions, and how the system reacts to different training scenarios.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [The Recommendation Pipeline](#2-the-recommendation-pipeline)
3. [Layer 1 — Double Progression Rule Engine](#3-layer-1--double-progression-rule-engine)
4. [Layer 2 — Weight Calculation](#4-layer-2--weight-calculation)
5. [Layer 3 — IFI Modifier](#5-layer-3--ifi-modifier)
6. [Layer 4 — RPE Brake](#6-layer-4--rpe-brake)
7. [Layer 5 — Plate Rounding & Backoff Sets](#7-layer-5--plate-rounding--backoff-sets)
8. [Stall Detection](#8-stall-detection)
9. [Stall Diagnosis with IFI](#9-stall-diagnosis-with-ifi)
10. [Intraset Fatigue Index (IFI)](#10-intraset-fatigue-index-ifi)
11. [Progression State Tracking](#11-progression-state-tracking)
12. [Volume Landmarks & Adaptive Calibration](#12-volume-landmarks--adaptive-calibration)
13. [Training Load Consistency](#13-training-load-consistency)
14. [Deload Suggestion](#14-deload-suggestion)
15. [Data Confidence](#15-data-confidence)
16. [Worked Examples](#16-worked-examples)
17. [All Magic Numbers Reference](#17-all-magic-numbers-reference)

---

## 1. Architecture Overview

The engine is a **pure function pipeline** — no mutable state, no side effects. Every recommendation is computed fresh from the raw workout logs.

```
Input:  Recent WorkoutLogs for one exercise
        + Target rep range (e.g. 8-12)
        + Target RPE (e.g. 8.0)
        + Is this a main lift? (bool)
        + Metric or imperial? (bool)
        + Cached ProgressionState (optional)
        + Last session IFI (optional)

Output: ProgressionRecommendation
        - recommendedWeight (top set)
        - backoffWeight (main lifts only)
        - recommendedReps
        - progressionRule (.progress / .hold / .backoff)
        - stallDetected (bool) + stallReason
        - confidence level
        - debugNote (human-readable explanation)
```

The system separates **what to do** (double progression rules) from **safety checks** (IFI modifier, RPE brake). Each layer can only reduce or hold a recommendation — never inflate it beyond what the rule engine decided.

---

## 2. The Recommendation Pipeline

Every call to `recommend()` flows through these stages **in order**. Each stage can override the previous, but only in the conservative direction.

```
┌──────────────────────────────────────────────────────────┐
│  1. DOUBLE PROGRESSION RULE                              │
│     → Determines: .progress / .hold / .backoff           │
│     → Calculates: base weight                            │
├──────────────────────────────────────────────────────────┤
│  2. IFI MODIFIER (if IFI data available)                 │
│     → Can downgrade .progress → .hold                    │
│     → Can force .backoff if overtrained                  │
│     → Tracks "effective rule" for RPE brake              │
├──────────────────────────────────────────────────────────┤
│  3. RPE BRAKE (if RPE was logged)                        │
│     → Can block progression at RPE ≥ 9.5                 │
│     → Can bump weight at RPE ≤ 7.0                       │
│     → Uses effective rule (won't double-penalize IFI)    │
├──────────────────────────────────────────────────────────┤
│  4. PLATE ROUNDING                                       │
│     → Imperial: nearest 5 lbs                            │
│     → Metric: nearest 2.5 kg                             │
├──────────────────────────────────────────────────────────┤
│  5. BACKOFF WEIGHT (main lifts only)                     │
│     → backoff = top set × 0.92, rounded                  │
├──────────────────────────────────────────────────────────┤
│  6. STALL DETECTION (independent — doesn't change weight)│
│     → Flags stall + reason for UI display                │
└──────────────────────────────────────────────────────────┘
```

**Key design rule:** The IFI modifier and RPE brake **never stack penalties**. If IFI already downgrades the rule, the RPE brake sees the new effective rule and won't penalize again.

---

## 3. Layer 1 — Double Progression Rule Engine

This is the primary decision maker. It looks at your **last session's working sets** and decides if you should add weight, hold, or back off.

### Working Set Definition

A **working set** is any set where the weight is ≥ 80% of the session's maximum weight. This filters out warm-up sets automatically.

```
Example session: 135×10, 185×8, 225×6, 225×5, 225×4
Session max = 225
Working set threshold = 225 × 0.80 = 180
Working sets = 225×6, 225×5, 225×4  (the 135 and 185 are warm-ups)
```

### The Three Rules

| Rule | Condition | What Happens |
|------|-----------|--------------|
| **PROGRESS** | ALL working sets hit `targetRepsHigh` | Add weight next session |
| **HOLD** | Working sets are between `targetRepsLow` and `targetRepsHigh` | Same weight, try for more reps |
| **BACKOFF** | 2+ working sets below `targetRepsLow` **for 2 consecutive sessions** | Reduce weight by 4% |

### Decision Flowchart

```
Last session working sets:
│
├── ALL sets ≥ targetRepsHigh?
│   └── YES → PROGRESS ✓
│
├── 2+ sets < targetRepsLow?
│   └── YES → Check previous session...
│       ├── Previous session ALSO had 2+ sets < targetRepsLow?
│       │   └── YES → BACKOFF ✓
│       │   └── NO  → HOLD (single bad day, don't overreact)
│
└── Otherwise → HOLD ✓
```

### Why Backoff Requires Two Sessions

A single bad session can happen for many reasons (poor sleep, bad nutrition, life stress). The engine requires the **same failure pattern in 2 consecutive sessions** before backing off. This prevents knee-jerk deloads from one-off bad days.

### Concrete Example

Target: 8-12 reps on Bench Press at 185 lbs

| Session | Set 1 | Set 2 | Set 3 | Rule |
|---------|-------|-------|-------|------|
| Week 1 | 185×10 | 185×9 | 185×8 | **HOLD** — all in range but not all at 12 |
| Week 2 | 185×11 | 185×10 | 185×10 | **HOLD** — still building |
| Week 3 | 185×12 | 185×12 | 185×12 | **PROGRESS** — all hit 12! Add weight |
| Week 4 | 195×10 | 195×8 | 195×7 | **HOLD** — in range at new weight |
| Week 5 | 195×7  | 195×6 | 195×5 | **HOLD** — 2 sets below 8, but need 2 bad sessions |
| Week 6 | 195×6  | 195×5 | 195×5 | **BACKOFF** — 2nd consecutive session with 2+ below 8 |

---

## 4. Layer 2 — Weight Calculation

Once the rule is determined, the base weight is calculated:

### Progression Increments

| Category | Imperial | Metric | Condition |
|----------|----------|--------|-----------|
| Main lift (heavy) | +10 lbs | +2.5 kg | Current weight ≥ 185 lbs |
| Main lift (light) | +5 lbs | +2.5 kg | Current weight < 185 lbs |
| Accessory | +5 lbs | +2.5 kg | Always |

### Weight by Rule

```
PROGRESS: baseWeight = lastWorkingWeight + increment
HOLD:     baseWeight = lastWorkingWeight
BACKOFF:  baseWeight = lastWorkingWeight × 0.96
```

### Example

Bench Press at 225 lbs (main lift, imperial):
- PROGRESS: 225 + 10 = **235 lbs**
- HOLD: **225 lbs**
- BACKOFF: 225 × 0.96 = **216 lbs** (rounds to 215 after plate rounding)

Lateral Raise at 25 lbs (accessory, imperial):
- PROGRESS: 25 + 5 = **30 lbs**
- HOLD: **25 lbs**
- BACKOFF: 25 × 0.96 = **24 lbs** (rounds to 25 — stays same due to rounding)

---

## 5. Layer 3 — IFI Modifier

If the engine has IFI data from the last session (see [Section 10](#10-intraset-fatigue-index-ifi)), it can **override** the double progression rule.

### IFI Zones

| IFI Value | Zone | Meaning |
|-----------|------|---------|
| < 0.10 | FRESH | Almost no rep drop-off. May not be pushing hard enough. |
| 0.10 – 0.25 | OPTIMAL | Normal fatigue. Productive training. |
| 0.25 – 0.40 | FATIGUED | Significant rep degradation. Recovery may be compromised. |
| ≥ 0.40 | OVERTRAINED | Severe drop-off. Immediate recovery needed. |

### IFI Override Rules

| IFI Zone | Double Progression Rule | IFI Override | Result |
|----------|----------------------|--------------|--------|
| FRESH | Any | None | Normal progression |
| OPTIMAL | Any | None | Normal progression |
| FATIGUED | **PROGRESS** | → HOLD | **Blocks weight increase** — reps are degrading too much to safely add load |
| FATIGUED | HOLD | None | Already holding |
| FATIGUED | BACKOFF | None | Already backing off |
| OVERTRAINED | **Any** | → BACKOFF | **Forces 4% reduction** regardless of what double progression decided |

### Why IFI Can Block Progress

You might hit your target reps on every set, but if set 1 is 12 reps and set 3 is 8 reps, your IFI is 0.33 (fatigued). Even though you technically "hit the reps," the intra-session fatigue pattern suggests you're at your recovery limit. Adding weight would likely cause failure.

### Effective Rule Tracking

When IFI overrides the progression rule, the engine tracks an **effective rule** that gets passed to the RPE brake. This prevents double-penalization:

```
Original rule: PROGRESS
IFI override:  → HOLD (effective rule = HOLD)
RPE brake:     Sees HOLD, won't penalize further
```

Without this, a lifter with high IFI AND high RPE would get penalized twice — IFI would hold them, then RPE would also try to hold/reduce.

---

## 6. Layer 4 — RPE Brake

The RPE brake is a **safety valve** that only fires if the user logged RPE on their last session. It operates on the **effective rule** (after IFI modification).

### RPE Brake Rules

| Last RPE | Effective Rule | RPE Action | Rationale |
|----------|---------------|------------|-----------|
| ≥ 9.5 | PROGRESS | **Block → return to lastWorkingWeight** | Near-maximal effort + progress = injury risk. Hold at current weight. |
| ≥ 9.5 | HOLD | None | Already holding |
| ≥ 9.5 | BACKOFF | None | Already backing off |
| ≤ 7.0 | HOLD | **Bump → add one increment** | Weight felt easy but reps didn't all hit top target. Try a small bump. |
| ≤ 7.0 | PROGRESS | None | Already progressing |
| 7.1 – 9.4 | Any | None | Normal range — no override |

### RPE Brake Interaction Matrix (Full Pipeline)

| Scenario | Double Prog | IFI Zone | Effective Rule | RPE | Final Weight |
|----------|------------|----------|----------------|-----|-------------|
| Perfect session | PROGRESS | OPTIMAL | PROGRESS | 8.0 | lastWeight + increment |
| Strong but grinding | PROGRESS | OPTIMAL | PROGRESS | 9.5 | lastWeight (blocked) |
| Strong but fatigued | PROGRESS | FATIGUED | HOLD | 8.0 | lastWeight |
| Easy hold | HOLD | FRESH | HOLD | 6.5 | lastWeight + increment (bumped) |
| Struggling | BACKOFF | OVERTRAINED | BACKOFF | 9.5 | lastWeight × 0.96 |

---

## 7. Layer 5 — Plate Rounding & Backoff Sets

### Plate Rounding

All final weights are rounded to the nearest loadable plate:
- **Imperial:** nearest 5.0 lbs (2.5 lb plates per side)
- **Metric:** nearest 2.5 kg (1.25 kg plates per side)

```
Example: 217.6 lbs → rounds to 220 lbs
Example: 63.7 kg → rounds to 65 kg
```

### Backoff Sets (Main Lifts Only)

Main lifts use a top set + backoff set scheme:
- **Set 1 (top set):** Full recommended weight
- **Sets 2+:** `top set × 0.92`, rounded to plates

```
Example: Top set = 225 lbs
Backoff = 225 × 0.92 = 207 → rounds to 205 lbs

Session layout:
  Set 1: 225 lbs (top set)
  Set 2: 205 lbs (backoff)
  Set 3: 205 lbs (backoff)
```

Accessories use the same weight for all sets.

---

## 8. Stall Detection

Stall detection runs **independently** of the weight recommendation. It flags issues for the UI to display but does not change the recommended weight (that's handled by the rule engine and modifiers).

### Main Lifts (3+ sessions required)

**Load Jump Suppression:** On the first session at a new weight, stall detection is skipped entirely. E1RM naturally dips when load increases (fewer reps at higher weight), and this would falsely trigger a stall alert.

```
Session 1: 225 × 8 (e1RM = 285)
Session 2: 235 × 6 (e1RM = 282) ← natural dip, NOT a stall
```

After suppression passes, two checks run:

| Check | Condition | StallReason |
|-------|-----------|-------------|
| **E1RM Decline** | Latest e1RM < best of last 3 sessions × 0.99 (>1% below peak) | `.e1rmDecline` |
| **E1RM Flat** | Improvement over 3 sessions < 0.5% | `.e1rmFlat` |
| **RPE Rising** | E1RM flat AND average RPE rose >0.5 over 3 sessions | `.rpeRising` |

### Accessories (4+ sessions required)

| Check | Condition | StallReason |
|-------|-----------|-------------|
| **Reps Flat** | Max reps across all 4 sessions within baseline ± 1 at same load | `.repsFlat` |

The ±1 tolerance prevents false positives from natural rep variance (e.g., 10, 11, 10, 11 is not a stall — 10, 10, 10, 10 is).

### E1RM Formula

```
e1RM = weight × (1 + reps / 30)
```

Examples:
- 225 × 8 = 225 × 1.267 = **285 e1RM**
- 185 × 12 = 185 × 1.400 = **259 e1RM**
- 315 × 3 = 315 × 1.100 = **347 e1RM**

---

## 9. Stall Diagnosis with IFI

When stall detection fires, the engine combines the **IFI trend** (fatigue pattern over time) with **e1RM trajectory** to diagnose the root cause. This tells the user **why** they're stuck, not just that they are.

### Diagnosis Matrix

| IFI Trend | E1RM Trend | Diagnosis | Meaning | Recommended Fix |
|-----------|-----------|-----------|---------|-----------------|
| > 0.25 (high fatigue) | Declining (< -1%) | **Fatigue Stall** | Over-fatigued, can't recover | Deload or reduce volume |
| < 0.10 (low fatigue) | Flat (< 0.5%) | **Intensity Stall** | Not pushing hard enough | Increase RPE/intensity |
| 0.10 – 0.25 (normal) | Flat (< 0.5%) | **True Plateau** | Genuine limit reached | Swap exercise variation |
| > 0.30 (very high) | Any | **Volume Stall** | Too many hard sets | Cut 2-3 sets per session |

### Hysteresis (Preventing Diagnosis Flickering)

When IFI trend sits near a boundary between two diagnoses, the system could flip back and forth between them week to week. Hysteresis prevents this by requiring the IFI to move **0.05 points outside** the current diagnosis's band before switching.

| Current Diagnosis | Stays Active While IFI In Range |
|------------------|-------------------------------|
| Fatigue Stall | 0.20 – 1.00 |
| Intensity Stall | 0.00 – 0.15 |
| True Plateau | 0.05 – 0.30 |
| Volume Stall | 0.25 – 1.00 |

```
Example:
  Week 5: IFI trend = 0.26, e1RM declining → Fatigue Stall
  Week 6: IFI trend = 0.23, e1RM declining → Still Fatigue Stall (0.23 within 0.20-1.00)
  Week 7: IFI trend = 0.18, e1RM flat → NOW switches to True Plateau (left the band)
```

### Stall Urgency Escalation

The same diagnosis persisting across sessions escalates urgency:

| Consecutive Occurrences | Urgency | UI Treatment |
|------------------------|---------|-------------|
| 1st | **Suggestion** | Subtle info card |
| 2nd | **Warning** | Yellow alert |
| 3rd+ | **Action Required** | Red alert, hard prompt to act |

---

## 10. Intraset Fatigue Index (IFI)

IFI measures how much your reps **drop off within a single session**. It's the engine's proxy for fatigue and recovery status.

### Formula

```
IFI = (firstWorkingSetReps - lastWorkingSetReps) / firstWorkingSetReps
```

Only **working sets** (≥ 80% of session max) count, sorted by set index.

### Examples

| Set 1 | Set 2 | Set 3 | IFI | Zone |
|-------|-------|-------|-----|------|
| 12 | 12 | 12 | 0.00 | FRESH |
| 12 | 11 | 10 | 0.17 | OPTIMAL |
| 10 | 8 | 7 | 0.30 | FATIGUED |
| 10 | 6 | 4 | 0.60 | OVERTRAINED |

### IFI Trend (Exponential Moving Average)

The raw per-session IFI is smoothed into a trend using a **2/3 + 1/3 EMA**:

```
ifiTrend = (previousTrend × 2 + currentIFI) / 3
```

This weights the previous trend at 66% and the new data at 33%, giving a rolling 3-session average that smooths out single-session spikes. The trend is what the stall diagnosis system uses — not the raw IFI.

### First Session Handling

On the very first session for an exercise (`totalExposures == 1`), the trend is set equal to the raw IFI (no history to smooth against).

---

## 11. Progression State Tracking

After every workout, `updateProgressionState()` updates a cached per-exercise `ProgressionState` with the session's results. This state persists across sessions and powers the UI's overload cards and stall alerts.

### Fields Updated Per Session

| Field | How It's Set |
|-------|-------------|
| `bestE1RM` | `max(current bestE1RM, session top e1RM)` — only goes up |
| `lastSessionWeight` | Session max weight |
| `lastSessionReps` | Top set reps |
| `lastSessionRPE` | Top set RPE |
| `consecutiveSuccesses` | +1 if ALL working sets ≥ targetRepsHigh, reset on failure |
| `consecutiveFailures` | +1 if 2+ working sets < targetRepsLow, reset on success |
| `totalExposures` | +1 every session |
| `weeksAtSameLoad` | +1 if session max within 0.1 lbs of previous, else reset to 0 |
| `lastIFI` | Raw IFI from this session |
| `ifiTrend` | EMA: `(oldTrend × 2 + newIFI) / 3` |
| `lastStallDiagnosis` | Diagnosis with hysteresis applied |
| `consecutiveStallDiagnoses` | +1 if same diagnosis repeats, 1 if new diagnosis, 0 if no stall |

### weeksAtSameLoad Bug Fix

The engine captures `previousSessionWeight` **before** mutating `lastSessionWeight`:

```swift
let previousSessionWeight = state.lastSessionWeight  // capture FIRST
state.lastSessionWeight = sessionMaxWeight            // then mutate
let sameLoad = abs(sessionMaxWeight - previousSessionWeight) < 0.1
state.weeksAtSameLoad = sameLoad ? state.weeksAtSameLoad + 1 : 0
```

Without this, the comparison would always be `sessionMaxWeight vs sessionMaxWeight` = always true.

---

## 12. Volume Landmarks & Adaptive Calibration

### The 4-Point Volume Model

For each of the 9 tracked muscle groups, the engine maintains volume landmarks that define training zones:

```
  MEV          MAV Low        MAV High          MRV
   │              │              │               │
   ▼              ▼              ▼               ▼
───┤──────────────┤──────────────┤───────────────┤───
   │  UNDER-      │   BUILDING   │    OPTIMAL    │  OVER-
   │  TRAINING    │              │               │  REACHING
```

| Zone | Range | Color | Meaning |
|------|-------|-------|---------|
| Under-training | < MEV | Red | Not enough stimulus for growth |
| Building | MEV to MAV Low | Yellow | Stimulus present, not yet optimal |
| Optimal | MAV Low to MRV | Green | Best stimulus-to-recovery ratio |
| Over-reaching | > MRV | Orange | More volume than you can recover from |

### Default Landmarks (Direct Sets Per Week)

| Muscle | MEV | MAV Low | MAV High | MRV |
|--------|-----|---------|----------|-----|
| Chest | 6 | 10 | 16 | 22 |
| Back | 8 | 12 | 18 | 24 |
| Quads | 6 | 10 | 16 | 22 |
| Hamstrings | 4 | 8 | 12 | 18 |
| Glutes | 2 | 6 | 12 | 18 |
| Calves | 4 | 6 | 10 | 16 |
| Biceps | 4 | 8 | 12 | 18 |
| Triceps | 4 | 6 | 10 | 16 |
| Delts | 6 | 10 | 14 | 20 |

### Muscle Tier Scaling

Users can set each muscle to a tier that scales all landmarks:

| Tier | Multiplier | Effect |
|------|-----------|--------|
| Priority | 1.5× | 50% more volume tolerated/needed |
| Neutral | 1.0× | Default |
| Maintenance | 0.7× | 30% less volume needed |

```
Example: Chest at Priority tier
  MEV: 6 × 1.5 = 9
  MAV: 10-16 → 15-24
  MRV: 22 × 1.5 = 33
```

### Indirect Volume Tracking

Compound exercises contribute partial volume to secondary muscles. Each exercise in the dictionary has specific secondary weights (0.2 – 0.7, not flat 0.5):

| Exercise | Primary (1.0 each) | Secondary (variable) |
|----------|-------------------|---------------------|
| Chin-Up | Back | Biceps (0.7) |
| Pull-Up | Back | Biceps (0.5) |
| Bench Press | Chest | Triceps (0.5), Front Delts (0.3) |
| Barbell Row | Back | Biceps (0.5), Rear Delts (0.5), Traps (0.3) |

### Adaptive Calibration (LandmarkCalibration)

Every 2 weeks, the engine recalibrates landmarks for each muscle based on real performance data:

**MEV Calibration:**
- Progressing near MEV (e1RM change > 0.5%) → lower MEV by 1 (you need less than we thought)
- Declining in building zone (e1RM change < -1%) → raise MEV by 1 (you need more)

**MRV Calibration:**
- High IFI (> 0.30) + declining e1RM at high volume → lower MRV by 2 (you're overreaching sooner)
- Low IFI (< 0.15) + progressing at high volume → raise MRV by 2 (you can handle more)
- Hard cap: MRV ≤ 30 sets

**MAV Calibration:**
- Great progress (e1RM > 1%, IFI < 0.20) in optimal zone → widen MAV High by 1
- Declining (e1RM < -0.5%, IFI > 0.25) → narrow MAV High by 1

**Safety invariants enforced after every calibration:**
```
MEV < MAV Low < MAV High < MRV
```

**Confidence levels:**

| Weeks of Data | Confidence | Calibration Behavior |
|--------------|-----------|---------------------|
| 0 | Seeded | Using defaults only |
| 1-3 | Low | No recalibration yet (needs ≥ 2 weeks) |
| 4-8 | Medium | Calibrating with moderate confidence |
| 9+ | High | Full adaptive calibration |

---

## 13. Training Load Consistency

Compares your last 7 days of training volume against your 28-day rolling average. This is a **consistency metric** — it tells you whether you're training at, above, or below your established baseline. It is not an injury predictor.

### Formula

```
Acute Load  = total sets in last 7 days
Chronic Load = total sets in last 28 days ÷ 4 (weekly average)
Ratio = Acute / Chronic
```

A ratio of 1.0 means this week matches your monthly average exactly.

### Zones

| Ratio | Zone | Color | What It Means |
|-------|------|-------|---------------|
| < 0.80 | Ramping Down | Blue | Training less than your baseline. Could be intentional (deload, travel) or a sign you're losing momentum. |
| 0.80 – 1.30 | Consistent | Green | Volume is in line with your recent norm. Steady, sustainable training. |
| 1.30 – 1.50 | Ramping Up | Yellow | Training noticeably more than usual. Fine if deliberate (overreach block), worth monitoring if unplanned. |
| > 1.50 | Big Spike | Orange | Large jump above baseline. Sudden volume spikes are harder to recover from — consider whether this is sustainable. |

### What This Is NOT

This metric comes from the acute:chronic workload ratio (ACWR) concept. The original ACWR research framed this as an injury predictor, but that evidence base is limited to team sports and has not been validated for gym-based resistance training. We use the same math because the **consistency signal is genuinely useful** — but we do not make injury risk claims.

### Requirements

Only computed when at least **14 days** of log data exist. Returns nothing otherwise.

---

## 14. Deload Suggestion

The engine suggests a deload when **systemic fatigue** is detected across multiple lifts simultaneously.

### Trigger Conditions (either one):
- **≥ 50%** of tracked lifts are flagged as stalled
- **≥ 50%** of tracked lifts have IFI > 0.25 (fatigued or worse)

Minimum 3 tracked lifts required to make a suggestion.

### User-Controlled Deloads

Users can add or remove deload weeks independently of the engine's suggestion:

- **Skip** a program-default deload week (e.g., skip Week 4 deload)
- **Add** a custom deload to any week
- The effective deload state = (program defaults - skipped) + custom

---

## 15. Data Confidence

The engine self-reports confidence based on available data:

| Sessions Logged | Confidence | Effect |
|----------------|-----------|--------|
| 0 | None | Returns weight = 0, user enters manually |
| 1 | Low | Single data point, recommendation based on one session |
| 2-3 | Medium | Trend emerging, backoff requires confirmation |
| 4+ | High | Full pattern recognition, stall detection active |

---

## 16. Worked Examples

### Example A: Textbook Progression (Bench Press, Main Lift)

```
Target: 8-12 reps, RPE 8.0, Imperial, Main Lift

Session 1: 185 × 10, 185 × 9, 185 × 8
  IFI = (10 - 8) / 10 = 0.20 (OPTIMAL)
  Rule: HOLD (not all at 12)
  → Recommend: 185 lbs

Session 2: 185 × 11, 185 × 11, 185 × 10
  IFI = (11 - 10) / 11 = 0.09 (FRESH)
  Rule: HOLD (still building)
  → Recommend: 185 lbs

Session 3: 185 × 12, 185 × 12, 185 × 12
  IFI = 0.00 (FRESH)
  Rule: PROGRESS (all hit 12!)
  Increment: 185 ≥ 185, so +10 lbs
  → Recommend: 195 lbs top set, 180 lbs backoff (195 × 0.92)
```

### Example B: IFI Blocks Progression

```
Session 4: 195 × 12, 195 × 9, 195 × 7
  IFI = (12 - 7) / 12 = 0.42 (OVERTRAINED!)
  Rule: PROGRESS (all working sets... wait, 7 < 8)
  Actually: Set at 195 × 7 is below targetRepsLow=8
  Rule: HOLD (only 1 set below low, need 2 for backoff)
  IFI Override: OVERTRAINED → force BACKOFF
  → Recommend: 195 × 0.96 = 187 → rounds to 185 lbs
```

### Example C: RPE Brake Catches Over-Reaching

```
Session 5: 185 × 12, 185 × 12, 185 × 12 (RPE 9.8)
  IFI = 0.00 (FRESH)
  Rule: PROGRESS
  IFI: no override (FRESH)
  RPE Brake: 9.8 ≥ 9.5 AND rule is PROGRESS → BLOCK
  → Recommend: 185 lbs (held, not progressed)
  Debug note: "Weight felt near-maximal. Holding to build confidence."
```

### Example D: RPE Bump on Easy Hold

```
Session 6: 185 × 10, 185 × 10, 185 × 9 (RPE 6.5)
  IFI = (10 - 9) / 10 = 0.10 (OPTIMAL)
  Rule: HOLD (not all at 12)
  IFI: no override
  RPE Brake: 6.5 ≤ 7.0 AND rule is HOLD → BUMP
  Increment: +10 lbs (main lift ≥ 185)
  → Recommend: 195 lbs
  Debug note: "Weight felt easy. Trying +10."
```

### Example E: Accessory Stall Detection

```
Cable Curl, Target 10-15 reps

Session 1: 30 × 14  (max reps = 14)
Session 2: 30 × 14  (max reps = 14)
Session 3: 30 × 15  (max reps = 15)
Session 4: 30 × 14  (max reps = 14)
  Baseline = Session 4 (oldest) = 14
  All within baseline ± 1? 14, 14, 15, 14 → YES (all ≤ 15)
  → Stall detected: repsFlat
  But wait — Session 3 hit 15 = targetRepsHigh
  Rule for Session 3 would have been PROGRESS
  The stall detection is informational — the rule engine already progressed
```

### Example F: Fatigue Stall Diagnosis

```
Squat, IFI trend over 4 weeks:
  Week 1: IFI = 0.15, e1RM = 350
  Week 2: IFI = 0.22, e1RM = 348
  Week 3: IFI = 0.28, e1RM = 345
  Week 4: IFI = 0.31, e1RM = 340

  IFI Trend (EMA):
    W1: 0.15
    W2: (0.15×2 + 0.22)/3 = 0.173
    W3: (0.173×2 + 0.28)/3 = 0.209
    W4: (0.209×2 + 0.31)/3 = 0.243

  At Week 4:
    IFI trend = 0.243 (< 0.25, borderline)
    e1RM change over 3 sessions: (340 - 348) / 348 = -0.023 (-2.3%, declining)

  Since IFI > 0.25 is the fatigue stall threshold and we're at 0.243...
  Raw diagnosis check: IFI 0.243 and e1RM declining...
    0.243 is NOT > 0.25 → doesn't match fatigue stall
    0.243 is in 0.10-0.25 range AND e1RM is declining (not flat) → no match either
    → noStall (the criteria for diagnosis require e1RM to be flat, not declining, for truePlateau)

  If IFI trend were 0.27:
    IFI > 0.25 AND e1RM declining → FATIGUE STALL
    → UI shows: "Fatigue Stall — consider a deload or reducing volume"
```

---

## 17. All Magic Numbers Reference

| Value | Where Used | What It Controls |
|-------|-----------|-----------------|
| **0.80 (80%)** | Working set filter | Sets ≥ 80% of session max count as "working sets" |
| **0.96 (4%)** | Backoff rule | Weight × 0.96 when backing off |
| **0.92 (8%)** | Backoff sets | Main lift sets 2+ = top set × 0.92 |
| **185 lbs** | Increment threshold | Main lifts ≥ 185: +10 lbs. Below: +5 lbs |
| **5.0 lbs / 2.5 kg** | Plate rounding | Smallest loadable increment |
| **2.5 kg** | Metric increment | All exercises in metric |
| **9.5 RPE** | RPE brake (high) | Blocks progression above this |
| **7.0 RPE** | RPE brake (low) | Allows bump when holding below this |
| **3 sessions** | Main lift stall | Minimum data for stall detection |
| **4 sessions** | Accessory stall | Minimum data for stall detection |
| **0.99 (1%)** | E1RM decline | Latest e1RM < 99% of recent peak = decline |
| **0.005 (0.5%)** | E1RM flat | < 0.5% improvement over 3 sessions = flat |
| **0.5 RPE** | RPE rising | RPE increase > 0.5 over 3 sessions = concerning |
| **± 1 rep** | Accessory stall | Tolerance band for rep flatness |
| **0.10 IFI** | Fresh/Optimal boundary | Below this = not pushing hard enough |
| **0.25 IFI** | Optimal/Fatigued boundary | Above this = recovery compromised |
| **0.40 IFI** | Fatigued/Overtrained | Above this = immediate deload territory |
| **0.30 IFI** | Volume stall trigger | IFI trend above this = too much volume |
| **2/3 + 1/3** | IFI EMA | `(trend × 2 + current) / 3` |
| **0.05** | Hysteresis band | IFI must move ± 0.05 outside band to switch diagnosis |
| **2 sessions** | Backoff confirmation | Must miss reps low 2 sessions in a row |
| **0.1 lbs** | Same load detection | Weight difference < 0.1 = same load |
| **2.6 lbs** | Suggestion acceptance | Within ± 2.6 of suggested = accepted |
| **14 days** | Load consistency minimum | Need 14+ days of data for load consistency ratio |
| **50%** | Deload suggestion | ≥ 50% of lifts stalled/fatigued = suggest deload |
| **30 sets** | MRV hard cap | Adaptive MRV can never exceed 30 |
| **± 2 sets** | Calibration cap | Max shift per recalibration cycle |
| **2 weeks** | Calibration interval | Minimum time between recalibrations |
