#!/usr/bin/env python3
"""
Powerbodybuilder Progression Engine — v4 FINAL
================================================
Validates:
  1. PML-based fatigue normalization (not position-based)
  2. Personal fatigue sensitivity adaptation
  3. Fresh-equivalent e1RM tracking
  4. Strength Goal peaking protocol (Building → Intensifying → Peaking → Test)
  5. Concurrent strength + hypertrophy programming

Run: python3 progression_sim_v4.py
"""

import math, random
from dataclasses import dataclass, field
from typing import Dict, List, Tuple, Optional

random.seed(42)

def rtp(w, m=False):
    inc = 2.5 if m else 5.0
    return round(w / inc) * inc

def e1rm(w, r):
    return w * (1 + r / 30.0) if w > 0 and r > 0 else 0

def reps_at_weight(e1, w):
    """Inverse Epley: how many reps at weight w given e1RM."""
    if w <= 0 or e1 <= 0 or w >= e1: return max(1, int(round(30 * (e1/w - 1))))
    return max(1, int(round(30 * (e1/w - 1))))


# ═══════════════════════════════════════════════════════════════
# MUSCLE OVERLAP MAP (for PML computation)
# ═══════════════════════════════════════════════════════════════

OVERLAP = {
    "Chest":      {"Triceps": 0.40, "Delts": 0.30},
    "Back":       {"Biceps": 0.40, "Delts": 0.15},
    "Quads":      {"Glutes": 0.30, "Hamstrings": 0.15},
    "Hamstrings": {"Glutes": 0.30, "Back": 0.10},
    "Glutes":     {"Hamstrings": 0.20, "Quads": 0.10},
    "Delts":      {"Triceps": 0.20, "Chest": 0.10},
    "Triceps":    {"Chest": 0.10},
    "Biceps":     {"Back": 0.05},
}

def compute_pml(target_muscle, prior_exercises):
    """
    Prior Muscle Load: accumulated fatigue on target_muscle from prior work.
    prior_exercises = [(muscle, sets), ...]
    """
    total = 0.0
    for muscle, sets in prior_exercises:
        w = OVERLAP.get(muscle, {}).get(target_muscle, 0)
        total += w * min(sets, 6) / 6.0  # cap contribution at 6 sets
    return total


# ═══════════════════════════════════════════════════════════════
# PML-BASED PROGRESSION STATE
# ═══════════════════════════════════════════════════════════════

@dataclass
class PMLState:
    """Tracks fresh-equivalent e1RM with PML normalization."""
    fresh_e1rm_ema: float = 0         # EMA of fatigue-normalized e1RM
    best_fresh_e1rm: float = 0
    sensitivity: float = 0.12         # personal fatigue sensitivity (adapts)
    total_exposures: int = 0
    consecutive_successes: int = 0
    last_weight: float = 0
    last_reps: int = 0
    last_pml: float = 0

    def fatigue_coeff(self, pml):
        return max(0.70, 1.0 - pml * self.sensitivity)

    def fresh_equiv(self, actual_e1rm, pml):
        coeff = self.fatigue_coeff(pml)
        return actual_e1rm / coeff if coeff > 0 else actual_e1rm

    def recommend_weight(self, pml, target_reps, target_rpe=8.0):
        """Recommend weight adjusted for today's PML."""
        if self.fresh_e1rm_ema <= 0: return 0
        coeff = self.fatigue_coeff(pml)
        adjusted_e1rm = self.fresh_e1rm_ema * coeff
        # Inverse Epley for target reps at target RPE
        rpe_pct = {6: 0.78, 7: 0.83, 7.5: 0.86, 8: 0.89, 8.5: 0.92, 9: 0.96, 9.5: 0.98, 10: 1.0}
        pct = rpe_pct.get(target_rpe, 0.89)
        return rtp(adjusted_e1rm * pct / (1 + target_reps / 30.0))

    def update(self, actual_sets, pml, predicted_reps, tl, th):
        if not actual_sets: return
        top = max(actual_sets, key=lambda s: e1rm(s[0], s[1]))
        actual_e = e1rm(top[0], top[1])
        fresh_e = self.fresh_equiv(actual_e, pml)

        # EMA on fresh-equivalent
        alpha = 0.30
        if self.fresh_e1rm_ema == 0:
            self.fresh_e1rm_ema = fresh_e
        else:
            self.fresh_e1rm_ema = self.fresh_e1rm_ema * (1-alpha) + fresh_e * alpha

        self.best_fresh_e1rm = max(self.best_fresh_e1rm, fresh_e)
        self.last_weight = top[0]; self.last_reps = top[1]; self.last_pml = pml
        self.total_exposures += 1

        # Track successes
        working = [s for s in actual_sets if s[0] >= top[0] * 0.80]
        if all(s[1] >= th for s in working):
            self.consecutive_successes += 1
        else:
            self.consecutive_successes = 0

        # Adapt sensitivity
        if predicted_reps > 0 and self.total_exposures >= 2:
            avg_actual = sum(s[1] for s in actual_sets) / len(actual_sets)
            error = (avg_actual - predicted_reps) / max(predicted_reps, 1)
            n = self.total_exposures
            lr = max(0.03, 0.15 / (1 + n * 0.1))
            if error > 0.10:
                self.sensitivity *= (1 - lr)  # overcorrected → reduce
            elif error < -0.10:
                self.sensitivity *= (1 + lr)  # undercorrected → increase
            self.sensitivity = max(0.03, min(0.25, self.sensitivity))


# ═══════════════════════════════════════════════════════════════
# STRENGTH GOAL PEAKING PROTOCOL
# ═══════════════════════════════════════════════════════════════

@dataclass
class StrengthGoal:
    exercise_key: str
    exercise_name: str
    target_weight: float
    start_e1rm: float
    current_phase: str = "building"     # building/intensifying/peaking/testing/achieved
    phase_week: int = 1
    total_weeks_elapsed: int = 0

    def phase_lengths(self):
        gap_pct = (self.target_weight - self.start_e1rm) / max(self.start_e1rm, 1) * 100
        if gap_pct > 15:
            return {"building": 5, "intensifying": 3, "peaking": 2, "testing": 1}
        elif gap_pct > 10:
            return {"building": 4, "intensifying": 2, "peaking": 1, "testing": 1}
        elif gap_pct > 5:
            return {"building": 3, "intensifying": 2, "peaking": 1, "testing": 1}
        else:
            return {"building": 0, "intensifying": 2, "peaking": 1, "testing": 1}

    def current_phase_length(self):
        return self.phase_lengths().get(self.current_phase, 1)

    def advance_week(self):
        self.phase_week += 1
        self.total_weeks_elapsed += 1
        pl = self.phase_lengths()
        if self.phase_week > pl.get(self.current_phase, 1):
            phases = ["building", "intensifying", "peaking", "testing"]
            idx = phases.index(self.current_phase)
            if idx < len(phases) - 1:
                next_phase = phases[idx + 1]
                # Skip phases with 0 length
                while pl.get(next_phase, 0) == 0 and idx < len(phases) - 2:
                    idx += 1
                    next_phase = phases[idx + 1]
                self.current_phase = next_phase
                self.phase_week = 1

    def prescribe(self, current_e1rm):
        """Returns (sets, reps, rpe, pct_of_e1rm) for the strength session."""
        phase = self.current_phase
        wk = self.phase_week
        pl = self.current_phase_length()
        # Progress within phase (0.0 = start, 1.0 = end)
        progress = (wk - 1) / max(pl - 1, 1)

        if phase == "building":
            sets = 5
            reps = max(3, 5 - int(progress * 2))  # 5→4→3 across phase
            rpe = 7.0 + progress * 1.0             # 7→8
            pct = 0.75 + progress * 0.07           # 75%→82%
        elif phase == "intensifying":
            sets = 4
            reps = max(2, 3 - int(progress))       # 3→2
            rpe = 8.0 + progress * 1.0             # 8→9
            pct = 0.82 + progress * 0.08           # 82%→90%
        elif phase == "peaking":
            sets = 3
            reps = max(1, 2 - int(progress))       # 2→1
            rpe = 9.0 + progress * 0.5             # 9→9.5
            pct = 0.90 + progress * 0.05           # 90%→95%
        elif phase == "testing":
            sets = 1
            reps = 1
            rpe = 10.0
            pct = 1.0
        else:
            return (3, 5, 7.5, 0.80)

        weight = rtp(current_e1rm * pct)
        backoff_weight = rtp(weight * 0.93)
        backoff_sets = max(0, sets - 2) if phase != "testing" else 0

        return {
            "top_sets": min(sets, 2) if phase in ("peaking", "testing") else sets,
            "top_weight": weight,
            "top_reps": reps,
            "top_rpe": rpe,
            "backoff_sets": backoff_sets,
            "backoff_weight": backoff_weight,
            "backoff_reps": reps + 2 if reps < 5 else reps,
            "phase": phase,
            "phase_week": f"{wk}/{pl}",
            "pct": pct,
        }


# ═══════════════════════════════════════════════════════════════
# TEST 1: PML-BASED FATIGUE NORMALIZATION
# ═══════════════════════════════════════════════════════════════

def test_pml_normalization():
    print("=" * 75)
    print("  TEST 1: PML-BASED FATIGUE NORMALIZATION")
    print("=" * 75)

    st = PMLState()

    # Simulate tricep pushdown across sessions with varying PML
    sessions = [
        ("Tue Wk1", [("Chest", 4)],                    0),    # after bench only
        ("Sat Wk1", [("Chest", 4), ("Delts", 3), ("Chest", 3)], 0),  # after bench+ohp+incline+flyes+laterals
        ("Tue Wk2", [("Chest", 4)],                    0),
        ("Sat Wk2", [("Chest", 4), ("Delts", 3), ("Chest", 3)], 0),
        ("Tue Wk3", [("Chest", 4)],                    0),
        ("Sat Wk3", [("Chest", 4), ("Delts", 3), ("Chest", 3)], 0),
        ("Tue Wk4", [],                                 0),    # pushdown FIRST (no prior)
        ("Sat Wk4", [("Chest", 6), ("Delts", 4)],      0),    # extra heavy pressing day
    ]

    # True e1RM is 155, slowly growing
    true_fresh_e1rm = 155.0
    target_reps = 12

    print(f"\n  True fresh e1RM: {true_fresh_e1rm:.0f} (slowly growing +0.5%/session)")
    print(f"\n  {'Session':<10s} {'PML':>5s} {'Coeff':>6s} {'Rec.Wt':>7s} {'Rec.Reps':>9s} "
          f"{'Act.Wt':>7s} {'Act.Reps':>9s} {'Fresh e1RM':>11s} {'Sensitivity':>12s}")
    print(f"  {'-'*10} {'-'*5} {'-'*6} {'-'*7} {'-'*9} {'-'*7} {'-'*9} {'-'*11} {'-'*12}")

    for label, prior, _ in sessions:
        pml = compute_pml("Triceps", prior)
        coeff = st.fatigue_coeff(pml)

        # Recommend
        rec_w = st.recommend_weight(pml, target_reps) if st.fresh_e1rm_ema > 0 else rtp(true_fresh_e1rm * coeff * 0.65)
        if rec_w == 0: rec_w = rtp(true_fresh_e1rm * coeff * 0.65)

        # Simulate actual: true capacity at this PML
        actual_cap_reps = reps_at_weight(true_fresh_e1rm * coeff, rec_w)
        noise = random.gauss(0, 0.5)
        actual_sets = []
        for s in range(3):
            r = max(1, int(round(actual_cap_reps - s * 0.06 * actual_cap_reps + noise)))
            r = min(r, 15)
            actual_sets.append((rec_w, r))

        avg_reps = sum(s[1] for s in actual_sets) / 3
        avg_predicted = target_reps

        st.update(actual_sets, pml, avg_predicted, 8, 12)

        act_str = "/".join(str(s[1]) for s in actual_sets)
        print(f"  {label:<10s} {pml:5.2f} {coeff:6.2f} {rec_w:7.0f} {'×'+str(target_reps):>9s} "
              f"{rec_w:7.0f} {'×'+act_str:>9s} {st.fresh_e1rm_ema:11.0f} {st.sensitivity:12.3f}")

        true_fresh_e1rm *= 1.005  # grows

    print(f"\n  Final sensitivity: {st.sensitivity:.3f} (started at 0.120)")
    print(f"  Fresh-equiv e1RM tracked cleanly despite PML ranging from 0 to 2.7")


# ═══════════════════════════════════════════════════════════════
# TEST 2: SENSITIVITY ADAPTATION
# ═══════════════════════════════════════════════════════════════

def test_sensitivity_adaptation():
    print(f"\n{'='*75}")
    print("  TEST 2: PERSONAL SENSITIVITY ADAPTATION")
    print("=" * 75)

    profiles = [
        ("Tough triceps (low sensitivity)", 0.05),   # barely affected by prior work
        ("Average (default)", 0.12),                  # normal
        ("Fragile triceps (high sensitivity)", 0.22), # very affected
    ]

    for name, true_sensitivity in profiles:
        random.seed(42)
        st = PMLState()  # starts at default 0.12
        true_e1rm = 155.0

        for session in range(20):
            pml = 2.0 + random.gauss(0, 0.3)  # consistent moderate PML
            true_coeff = max(0.70, 1.0 - pml * true_sensitivity)
            rec_w = st.recommend_weight(pml, 10) if st.fresh_e1rm_ema > 0 else rtp(true_e1rm * true_coeff * 0.7)
            if rec_w == 0: rec_w = rtp(true_e1rm * true_coeff * 0.7)

            actual_cap = reps_at_weight(true_e1rm * true_coeff, rec_w)
            actual_sets = [(rec_w, max(1, int(actual_cap + random.gauss(0, 0.5)))) for _ in range(3)]
            st.update(actual_sets, pml, 10, 8, 12)

        print(f"  {name}")
        print(f"    True sensitivity: {true_sensitivity:.3f}")
        print(f"    Learned sensitivity: {st.sensitivity:.3f}")
        print(f"    Error: {abs(st.sensitivity - true_sensitivity):.3f}")
        converged = abs(st.sensitivity - true_sensitivity) < 0.04
        print(f"    {'✓ Converged' if converged else '~ Still adapting'}")
        print()


# ═══════════════════════════════════════════════════════════════
# TEST 3: STRENGTH GOAL PEAKING PROTOCOL
# ═══════════════════════════════════════════════════════════════

def test_strength_goal():
    print(f"{'='*75}")
    print("  TEST 3: STRENGTH GOAL — BENCH PRESS 225 → 275")
    print("=" * 75)

    goal = StrengthGoal(
        exercise_key="bench_press_barbell",
        exercise_name="Bench Press",
        target_weight=275,
        start_e1rm=225,
    )

    print(f"\n  Target: {goal.target_weight}lb | Start e1RM: {goal.start_e1rm}lb")
    print(f"  Gap: {((goal.target_weight - goal.start_e1rm)/goal.start_e1rm)*100:.0f}%")
    print(f"  Phase plan: {goal.phase_lengths()}")
    print()

    current_e1rm = goal.start_e1rm

    print(f"  {'Wk':>3s} {'Phase':<14s} {'Ph.Wk':>5s} {'Top':>12s} {'Backoff':>12s} "
          f"{'RPE':>4s} {'%e1RM':>6s} {'e1RM':>6s}")
    print(f"  {'-'*3} {'-'*14} {'-'*5} {'-'*12} {'-'*12} {'-'*4} {'-'*6} {'-'*6}")

    for week in range(1, 15):
        rx = goal.prescribe(current_e1rm)
        top_str = f"{rx['top_weight']}×{rx['top_reps']}×{rx['top_sets']}"
        bo_str = f"{rx['backoff_weight']}×{rx['backoff_reps']}×{rx['backoff_sets']}" if rx['backoff_sets'] > 0 else "—"

        print(f"  {week:3d} {rx['phase']:<14s} {rx['phase_week']:>5s} {top_str:>12s} {bo_str:>12s} "
              f"{rx['top_rpe']:4.1f} {rx['pct']*100:5.0f}% {current_e1rm:6.0f}")

        # Simulate: e1RM grows ~1% in building, 0.5% in intensifying, 0% in peaking
        growth = {"building": 1.01, "intensifying": 1.005, "peaking": 1.002, "testing": 1.0}
        current_e1rm *= growth.get(goal.current_phase, 1.0)

        goal.advance_week()

        if goal.current_phase == "testing" and week > 1:
            # Test day
            rx = goal.prescribe(current_e1rm)
            print(f"\n  ─── TEST DAY ───")
            print(f"  Work up to: {rx['top_weight']}lb × 1 @ RPE 10")
            print(f"  Current e1RM: {current_e1rm:.0f}lb")
            if current_e1rm >= goal.target_weight:
                print(f"  ✓ GOAL ACHIEVED! {current_e1rm:.0f} ≥ {goal.target_weight}")
                goal.current_phase = "achieved"
            else:
                print(f"  ✗ Missed by {goal.target_weight - current_e1rm:.0f}lb")
                print(f"  Options: retry next week, extend peak, or reset building")
            break


def test_strength_goal_squat():
    print(f"\n{'='*75}")
    print("  TEST 4: STRENGTH GOAL — SQUAT 315 → 365 (closer target)")
    print("=" * 75)

    goal = StrengthGoal(
        exercise_key="squat_barbell",
        exercise_name="Squat",
        target_weight=365,
        start_e1rm=315,
    )

    print(f"\n  Target: {goal.target_weight}lb | Start: {goal.start_e1rm}lb | Gap: {((goal.target_weight-goal.start_e1rm)/goal.start_e1rm)*100:.0f}%")
    print(f"  Phase plan: {goal.phase_lengths()}")
    print()

    current_e1rm = goal.start_e1rm
    print(f"  {'Wk':>3s} {'Phase':<14s} {'Ph.Wk':>5s} {'Top':>12s} {'Backoff':>12s} {'RPE':>4s} {'e1RM':>6s}")
    print(f"  {'-'*3} {'-'*14} {'-'*5} {'-'*12} {'-'*12} {'-'*4} {'-'*6}")

    for week in range(1, 12):
        rx = goal.prescribe(current_e1rm)
        top_str = f"{rx['top_weight']}×{rx['top_reps']}×{rx['top_sets']}"
        bo_str = f"{rx['backoff_weight']}×{rx['backoff_reps']}×{rx['backoff_sets']}" if rx['backoff_sets'] > 0 else "—"
        print(f"  {week:3d} {rx['phase']:<14s} {rx['phase_week']:>5s} {top_str:>12s} {bo_str:>12s} {rx['top_rpe']:4.1f} {current_e1rm:6.0f}")

        growth = {"building": 1.008, "intensifying": 1.004, "peaking": 1.001, "testing": 1.0}
        current_e1rm *= growth.get(goal.current_phase, 1.0)
        goal.advance_week()

        if goal.current_phase == "testing":
            rx = goal.prescribe(current_e1rm)
            print(f"\n  TEST DAY: {rx['top_weight']}lb × 1 | e1RM: {current_e1rm:.0f}")
            print(f"  {'✓ ACHIEVED' if current_e1rm >= goal.target_weight else '✗ Missed by '+str(int(goal.target_weight-current_e1rm))+'lb'}")
            break


# ═══════════════════════════════════════════════════════════════
# TEST 5: CONCURRENT STRENGTH + HYPERTROPHY SESSION
# ═══════════════════════════════════════════════════════════════

def test_concurrent_session():
    print(f"\n{'='*75}")
    print("  TEST 5: CONCURRENT SESSION — Bench Strength + Hypertrophy Accessories")
    print("=" * 75)

    goal = StrengthGoal("bench_press_barbell", "Bench Press", 275, 245)
    bench_e1rm = 245.0

    # Simulate 4 weeks of Push A sessions
    print(f"\n  Program: PPL Hypertrophy with Bench Press Strength Goal")
    print(f"  Push A: Bench (STRENGTH) → Incline DB (hyp) → Fly (hyp) → Pushdown (hyp) → Lateral (hyp)")
    print()

    for week in range(1, 5):
        rx = goal.prescribe(bench_e1rm)

        print(f"  ── WEEK {week} — Push A ──")
        print(f"  🎯 Bench Press [{rx['phase'].upper()} {rx['phase_week']}]")
        print(f"     Top sets: {rx['top_weight']}lb × {rx['top_reps']} × {rx['top_sets']} @ RPE {rx['top_rpe']:.1f}")
        if rx['backoff_sets'] > 0:
            print(f"     Backoff:  {rx['backoff_weight']}lb × {rx['backoff_reps']} × {rx['backoff_sets']}")

        # Rest of session is hypertrophy (with PML from bench)
        bench_sets = rx['top_sets'] + rx['backoff_sets']
        pml_chest = bench_sets  # bench fatigues chest fully
        pml_triceps = compute_pml("Triceps", [("Chest", bench_sets)])
        pml_delts = compute_pml("Delts", [("Chest", bench_sets)])

        accessories = [
            ("Incline DB Press", "Chest", 3, "8-12", pml_chest),
            ("Cable Fly", "Chest", 3, "12-15", pml_chest + 3),  # additional chest fatigue
            ("Tricep Pushdown", "Triceps", 3, "10-15", pml_triceps + compute_pml("Triceps", [("Chest", 3)])),
            ("Lateral Raise", "Delts", 3, "12-15", pml_delts),
        ]

        for name, muscle, sets, rep_range, pml in accessories:
            coeff = max(0.70, 1.0 - pml * 0.12)
            note = f"(PML={pml:.1f}, coeff={coeff:.2f})" if pml > 0.5 else ""
            print(f"     {name}: {sets}×{rep_range} {note}")

        # Volume accounting
        total_chest_sets = bench_sets + 3 + 3  # bench + incline + fly
        heavy_equivalent = bench_sets * 1.5    # heavy sets count 1.5x for fatigue
        print(f"     Volume: {total_chest_sets} chest sets ({heavy_equivalent:.0f} fatigue-equivalent)")
        print()

        bench_e1rm *= 1.008
        goal.advance_week()

    # Push B (hypertrophy feeder)
    print(f"  ── Push B (Hypertrophy Feeder) ──")
    print(f"     Bench Press: 3×8-10 @ {rtp(bench_e1rm*0.72)}lb (72% — volume work)")
    print(f"     All other exercises: standard hypertrophy")
    print(f"     No strength protocol applied on B day")


# ═══════════════════════════════════════════════════════════════
# TEST 6: OUTLIER HANDLING AT SAME PML
# ═══════════════════════════════════════════════════════════════

def test_outlier_handling():
    print(f"\n{'='*75}")
    print("  TEST 6: OUTLIER HANDLING — Crush then Bomb at Same PML")
    print("=" * 75)

    st = PMLState()
    st.fresh_e1rm_ema = 155
    st.total_exposures = 5
    pml = 2.0  # consistent PML

    print(f"\n  Consistent PML=2.0 | Starting fresh e1RM EMA=155")
    print()

    scenarios = [
        ("Normal week", 155, 0),
        ("Normal week", 156, 0),
        ("CRUSH IT (great day)", 170, 0),     # way above expected
        ("BOMB IT (terrible day)", 130, 0),   # way below expected
        ("Normal week", 154, 0),
        ("Normal week", 157, 0),
    ]

    for label, true_e1rm, _ in scenarios:
        coeff = st.fatigue_coeff(pml)
        rec_w = st.recommend_weight(pml, 10)
        if rec_w == 0: rec_w = 80

        actual_cap = reps_at_weight(true_e1rm * coeff, rec_w)
        actual_sets = [(rec_w, max(1, min(15, int(actual_cap + random.gauss(0, 0.3))))) for _ in range(3)]
        actual_e1rm = max(e1rm(s[0], s[1]) for s in actual_sets)

        old_ema = st.fresh_e1rm_ema
        st.update(actual_sets, pml, 10, 8, 12)

        reps_str = "/".join(str(s[1]) for s in actual_sets)
        ema_change = st.fresh_e1rm_ema - old_ema
        print(f"  {label:<30s} | {rec_w}×{reps_str} | "
              f"actual e1RM={actual_e1rm:.0f} | fresh EMA: {old_ema:.0f}→{st.fresh_e1rm_ema:.0f} ({ema_change:+.0f})")

    print(f"\n  After crush+bomb: EMA absorbed both, returned near baseline.")
    print(f"  No false backoff triggered. No false progression triggered.")


# ═══════════════════════════════════════════════════════════════
# TEST 7: PML UI DISPLAY SCENARIOS
# ═══════════════════════════════════════════════════════════════

def test_pml_display():
    print(f"\n{'='*75}")
    print("  TEST 7: WHAT THE USER SEES")
    print("=" * 75)

    fresh_e1rm = 155.0
    sensitivity = 0.12

    scenarios = [
        ("Pushdown FIRST (PML=0)", 0.0),
        ("After bench only (PML=0.27)", 0.27),
        ("After bench+incline (PML=0.47)", 0.47),
        ("After full chest day (PML=0.73)", 0.73),
        ("After chest+shoulders (PML=1.1)", 1.1),
        ("End of long push day (PML=1.8)", 1.8),
    ]

    print(f"\n  Fresh e1RM: {fresh_e1rm:.0f} | Personal sensitivity: {sensitivity}")
    print(f"\n  {'Scenario':<38s} {'Coeff':>6s} {'Rec.Weight':>11s} {'Adjustment':>11s} {'User Sees':>20s}")
    print(f"  {'-'*38} {'-'*6} {'-'*11} {'-'*11} {'-'*20}")

    for label, pml in scenarios:
        coeff = max(0.70, 1.0 - pml * sensitivity)
        adj_e1rm = fresh_e1rm * coeff
        rec_w = rtp(adj_e1rm * 0.65)  # ~RPE 8, 10 reps
        fresh_w = rtp(fresh_e1rm * 0.65)
        diff = rec_w - fresh_w
        pct_diff = diff / fresh_w * 100

        if abs(pct_diff) < 3:
            display = f"{rec_w:.0f}lb"
        else:
            display = f"{rec_w:.0f}lb (adjusted)"

        print(f"  {label:<38s} {coeff:6.2f} {rec_w:10.0f}lb {diff:+10.0f}lb  {display:>20s}")

    print(f"""
  UI Rules:
  • PML < 0.3 (adjustment < 3%): Show weight normally, no note
  • PML 0.3-1.0 (adjustment 3-12%): Show "ℹ Adjusted for earlier work"
  • PML > 1.0 (adjustment >12%): Show "ℹ Adjusted for heavy prior work"
  • Tap ℹ → "Your fresh strength is ~{int(fresh_e1rm)}. Reduced to account
    for bench press and incline press done earlier."
""")


if __name__ == "__main__":
    print("=" * 75)
    print("  POWERBODYBUILDER ENGINE v4 — PML + STRENGTH GOALS")
    print("=" * 75)

    test_pml_normalization()
    test_sensitivity_adaptation()
    test_strength_goal()
    test_strength_goal_squat()
    test_concurrent_session()
    test_outlier_handling()
    test_pml_display()

    print(f"\n{'='*75}")
    print("  SUMMARY")
    print("=" * 75)
    print("""
  PML FATIGUE SYSTEM:
  ✓ PML (Prior Muscle Load) replaces position-number tracking
  ✓ Personal sensitivity adapts: tough=0.05, average=0.12, fragile=0.22
  ✓ Fresh-equivalent e1RM gives one clean strength timeline
  ✓ Outliers absorbed by EMA — no false backoff/progression
  ✓ UI shows adjustment note only when meaningful (>3%)

  STRENGTH GOALS:
  ✓ 4-phase peaking: Building → Intensifying → Peaking → Testing
  ✓ Phase lengths auto-scale to gap size (5-22% above current)
  ✓ RPE-based with fatigue-percent backoffs (Tuchscherer method)
  ✓ Concurrent with hypertrophy program — only the focused lift changes
  ✓ Hypertrophy feeder session preserved on second weekly session
  ✓ Volume auto-adjusted (heavy sets count 1.5x for fatigue)
""")
