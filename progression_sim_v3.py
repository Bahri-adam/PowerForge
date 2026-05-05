#!/usr/bin/env python3
"""
Powerbodybuilder Progression Engine Simulation v3
==================================================
Tests:
  1. Per-set rep targets (validated in v2)
  2. Equipment-aware dumbbell progression (validated in v2)
  3. T3-only top-set progression (validated in v2)
  4. IFI-modulated targets (validated in v2)
  5. NEW: Pre-workout readiness modifier
  6. NEW: Cross-exercise fatigue modeling
  7. NEW: Warm-up set generation
  8. NEW: Strength balance ratios
  9. NEW: Predictive 1RM timeline
  10. NEW: Genetic potential estimation

Run: python3 progression_sim_v3.py
"""

import math, random
from dataclasses import dataclass, field

random.seed(42)

def round_to_plate(w, metric=False):
    inc = 2.5 if metric else 5.0
    return round(w / inc) * inc

def e1rm(w, r):
    if r <= 0 or w <= 0: return 0
    return w * (1 + r / 30.0)

def compute_ifi(sets):
    if len(sets) < 2: return 0.0
    mx = max(s[0] for s in sets)
    wk = [s for s in sets if s[0] >= mx * 0.80]
    if len(wk) < 2: return 0.0
    f = wk[0][0] * wk[0][1]; l = wk[-1][0] * wk[-1][1]
    return max(0, (f - l) / f) if f > 0 else 0.0

def ifi_zone(ifi):
    if ifi < 0.10: return "FRESH"
    if ifi < 0.25: return "OPTIMAL"
    if ifi < 0.40: return "FATIGUED"
    return "OVERTRAINED"


# ═══════════════════════════════════════════════════════════════
# 1. WARM-UP SET GENERATION
# ═══════════════════════════════════════════════════════════════

def generate_warmup(working_weight, working_reps, is_compound, use_metric=False):
    """
    Generate warm-up ramp leading to working weight.
    Returns list of (weight, reps) tuples.
    Rules:
      - Start with empty bar (45lb / 20kg)
      - 3-5 warm-up sets depending on working weight
      - Reps decrease as weight increases
      - Final warm-up at ~90% of working weight × 1-2 reps
    """
    bar = 20.0 if use_metric else 45.0
    if working_weight <= bar:
        return [(bar, 10)]  # just bar work

    warmups = []

    if not is_compound or working_weight < bar * 2:
        # Light isolation / bodyweight: just 1-2 warm-up sets
        warmups.append((round_to_plate(working_weight * 0.5, use_metric), min(12, working_reps + 2)))
        if working_weight >= bar * 1.5:
            warmups.append((round_to_plate(working_weight * 0.75, use_metric), min(8, working_reps)))
        return warmups

    # Compound: structured ramp
    # Percentages: 30%, 50%, 70%, 85%, (optional 92%)
    pcts = [0.30, 0.50, 0.70, 0.85]
    if working_weight >= 225:  # heavy — add 92% single
        pcts.append(0.92)

    rep_scheme = [10, 6, 4, 2, 1]

    for i, pct in enumerate(pcts):
        w = round_to_plate(working_weight * pct, use_metric)
        if w < bar: w = bar
        r = rep_scheme[i] if i < len(rep_scheme) else 1
        # Don't duplicate weights
        if warmups and warmups[-1][0] == w:
            continue
        warmups.append((w, r))

    return warmups


# ═══════════════════════════════════════════════════════════════
# 2. CROSS-EXERCISE FATIGUE MODELING
# ═══════════════════════════════════════════════════════════════

# Muscle overlap map: exercise → secondary muscles with fatigue contribution
MUSCLE_OVERLAP = {
    "Quads":      {"Glutes": 0.3, "Hamstrings": 0.15},
    "Hamstrings":  {"Glutes": 0.3, "Back": 0.1},
    "Glutes":      {"Hamstrings": 0.2, "Quads": 0.1},
    "Chest":       {"Triceps": 0.4, "Delts": 0.3},
    "Back":        {"Biceps": 0.4, "Delts": 0.15},
    "Delts":       {"Triceps": 0.2, "Chest": 0.1},
    "Triceps":     {"Chest": 0.1},
    "Biceps":      {"Back": 0.05},
}

def fatigue_modifier(current_muscle, prior_exercises):
    """
    Calculate capacity reduction for current_muscle based on what was
    already done in this session.
    prior_exercises = list of (muscle_group, sets_done) earlier in session.
    Returns a multiplier 0.7-1.0 (1.0 = no fatigue, 0.7 = significant fatigue).
    """
    total_fatigue = 0.0
    for prior_muscle, sets in prior_exercises:
        overlap = MUSCLE_OVERLAP.get(prior_muscle, {})
        if current_muscle in overlap:
            contribution = overlap[current_muscle] * min(sets, 6) / 6.0  # cap at 6 sets
            total_fatigue += contribution

    # Cap at 30% reduction
    modifier = max(0.70, 1.0 - total_fatigue)
    return modifier


# ═══════════════════════════════════════════════════════════════
# 3. PRE-WORKOUT READINESS
# ═══════════════════════════════════════════════════════════════

def readiness_modifier(readiness_score):
    """
    readiness_score: 1-5 (1=terrible, 3=normal, 5=great)
    Returns (weight_mod, volume_mod, target_rep_mod)
    """
    mods = {
        1: (0.90, 0.60, -3),   # Terrible: drop weight 10%, cut volume 40%, -3 rep target
        2: (0.95, 0.80, -1),   # Poor: drop weight 5%, cut volume 20%, -1 rep target
        3: (1.00, 1.00,  0),   # Normal: no change
        4: (1.00, 1.00, +1),   # Good: push rep targets +1
        5: (1.02, 1.00, +2),   # Great: slight weight bump, push rep targets +2
    }
    return mods.get(readiness_score, (1.0, 1.0, 0))


# ═══════════════════════════════════════════════════════════════
# 4. STRENGTH BALANCE ANALYSIS
# ═══════════════════════════════════════════════════════════════

def analyze_strength_balance(exercise_e1rms):
    """
    exercise_e1rms = dict of exercise_key → e1RM
    Returns list of (ratio_name, value, status, ideal_range) tuples
    """
    results = []

    # Extract representative lifts
    bench = max([v for k, v in exercise_e1rms.items() if "bench" in k.lower() and "incline" not in k.lower()], default=0)
    row = max([v for k, v in exercise_e1rms.items() if "row" in k.lower() and "upright" not in k.lower()], default=0)
    squat = max([v for k, v in exercise_e1rms.items() if "squat" in k.lower()], default=0)
    rdl = max([v for k, v in exercise_e1rms.items() if "rdl" in k.lower() or "deadlift" in k.lower() or "romanian" in k.lower()], default=0)
    ohp = max([v for k, v in exercise_e1rms.items() if "ohp" in k.lower() or "overhead" in k.lower() or "shoulder_press" in k.lower()], default=0)
    curl = max([v for k, v in exercise_e1rms.items() if "curl" in k.lower()], default=0)
    extension = max([v for k, v in exercise_e1rms.items() if "extension" in k.lower() or "pushdown" in k.lower() or "skullcrusher" in k.lower()], default=0)

    def ratio(a, b, name, ideal_low, ideal_high):
        if a > 0 and b > 0:
            r = a / b
            if r < ideal_low:
                status = f"LOW — {name.split(':')[0]} is weak"
            elif r > ideal_high:
                status = f"HIGH — {name.split(':')[1] if ':' in name else 'second lift'} is weak"
            else:
                status = "BALANCED"
            results.append((name, r, status, f"{ideal_low:.2f}-{ideal_high:.2f}"))

    ratio(row, bench, "Pull:Push", 0.85, 1.15)
    ratio(rdl, squat, "Posterior:Anterior", 0.80, 1.20)
    ratio(ohp, bench, "OHP:Bench", 0.55, 0.75)
    ratio(curl, extension, "Bicep:Tricep", 0.70, 1.00)

    # Squat:Deadlift (should be ~0.80-0.85)
    deadlift = max([v for k, v in exercise_e1rms.items() if "deadlift" in k.lower() and "romanian" not in k.lower()], default=0)
    if squat > 0 and deadlift > 0:
        ratio(squat, deadlift, "Squat:Deadlift", 0.75, 0.90)

    return results


# ═══════════════════════════════════════════════════════════════
# 5. PREDICTIVE 1RM TIMELINE
# ═══════════════════════════════════════════════════════════════

def predict_e1rm_timeline(current_e1rm, weekly_growth_pct, targets):
    """
    current_e1rm: current estimated 1RM
    weekly_growth_pct: e.g., 0.008 (0.8% per week)
    targets: list of target weights to predict
    Returns list of (target, estimated_weeks) tuples
    """
    if weekly_growth_pct <= 0:
        return [(t, None) for t in targets]

    results = []
    for target in targets:
        if current_e1rm >= target:
            results.append((target, 0))
        else:
            weeks = math.log(target / current_e1rm) / math.log(1 + weekly_growth_pct)
            results.append((target, int(math.ceil(weeks))))
    return results


# ═══════════════════════════════════════════════════════════════
# 6. GENETIC POTENTIAL ESTIMATION
# ═══════════════════════════════════════════════════════════════

def estimate_genetic_potential(bodyweight, sex="male"):
    """
    Uses Martin Berkhan's formula for natural muscular potential (male).
    Returns estimated competition-level maxes at ~10% body fat.
    """
    if sex == "male":
        # Height-based is better, but we use BW as proxy
        # Approximate elite natural 1RMs at competition bodyweight
        return {
            "bench":    bodyweight * 1.75,   # Elite natural: ~1.75x BW
            "squat":    bodyweight * 2.25,    # Elite natural: ~2.25x BW
            "deadlift": bodyweight * 2.75,    # Elite natural: ~2.75x BW
            "ohp":      bodyweight * 1.15,    # Elite natural: ~1.15x BW
        }
    else:
        return {
            "bench":    bodyweight * 1.0,
            "squat":    bodyweight * 1.6,
            "deadlift": bodyweight * 2.0,
            "ohp":      bodyweight * 0.65,
        }

def genetic_potential_pct(current_e1rm, potential):
    """Returns percentage of estimated genetic potential."""
    if potential <= 0: return 0
    return min(100, (current_e1rm / potential) * 100)


# ═══════════════════════════════════════════════════════════════
# 7. PRE-WORKOUT READINESS SIMULATION
# ═══════════════════════════════════════════════════════════════

@dataclass
class State:
    best_e1rm: float = 0; ema_e1rm: float = 0; baseline_e1rm: float = 0
    total_exposures: int = 0; consecutive_successes: int = 0
    consecutive_failures: int = 0; weeks_at_same_load: int = 0
    last_weight: float = 0; last_reps: int = 0
    ifi_trend: float = 0; last_ifi: float = 0

    def update(self, sets, tl, th):
        if not sets: return
        mx = max(s[0] for s in sets)
        wk = [s for s in sets if s[0] >= mx * 0.80]
        top = max(sets, key=lambda s: e1rm(s[0], s[1]))
        te = e1rm(top[0], top[1])
        if all(s[1] >= th for s in wk):
            self.consecutive_successes += 1; self.consecutive_failures = 0
        elif sum(1 for s in wk if s[1] < tl) >= 2:
            self.consecutive_failures += 1; self.consecutive_successes = 0
        pw = self.last_weight
        self.best_e1rm = max(self.best_e1rm, te)
        self.last_weight = mx; self.last_reps = top[1]
        a = 0.30
        self.ema_e1rm = te if self.ema_e1rm == 0 else self.ema_e1rm * (1-a) + te * a
        if self.total_exposures == 0: self.baseline_e1rm = te
        self.total_exposures += 1
        self.weeks_at_same_load = self.weeks_at_same_load + 1 if mx == pw and pw > 0 else 0
        ifi = compute_ifi(sets); self.last_ifi = ifi
        self.ifi_trend = ifi if self.total_exposures <= 1 else (self.ifi_trend * 2 + ifi) / 3


def recommend_with_readiness(history, state, tl, th, tier, readiness=3, prior_fatigue=None):
    """Full proposed engine with readiness and cross-exercise fatigue."""
    if not history:
        return {"weight": 0, "reps": [th]*3, "rule": "no_history"}

    last = history[0]
    mx = max(s[0] for s in last)
    wk = [s for s in last if s[0] >= mx * 0.80]
    if not wk:
        return {"weight": mx, "reps": [th]*len(last), "rule": "hold"}

    ifi = compute_ifi(last); zone = ifi_zone(ifi)
    n = len(last)

    # Standard progression rule
    all_top = all(s[1] >= th for s in wk)
    miss2 = sum(1 for s in wk if s[1] < tl) >= 2
    prev_miss = False
    if miss2 and len(history) > 1:
        pm = max(s[0] for s in history[1])
        pw = [s for s in history[1] if s[0] >= pm*0.80]
        prev_miss = sum(1 for s in pw if s[1] < tl) >= 2

    rule = "progress" if all_top else ("backoff" if miss2 and prev_miss else "hold")
    if zone == "FATIGUED" and rule == "progress": rule = "hold"
    elif zone == "OVERTRAINED": rule = "backoff"

    inc = 5.0 if tier == "T1" else (5.0 if tier == "T2" else 2.5)
    if rule == "progress": w = round_to_plate(mx + inc)
    elif rule == "backoff": w = round_to_plate(mx * {"T1": 0.94, "T2": 0.90, "T3": 0.85}[tier])
    else: w = round_to_plate(mx)

    # ── Readiness modifier ──
    w_mod, vol_mod, rep_mod = readiness_modifier(readiness)
    w = round_to_plate(w * w_mod)

    # ── Cross-exercise fatigue modifier ──
    fatigue_mult = 1.0
    if prior_fatigue:
        fatigue_mult = fatigue_modifier("target_muscle", prior_fatigue)

    # ── Per-set rep targets ──
    reps = []
    for i in range(n):
        lr = last[i][1] if i < len(last) else tl
        if rule == "progress" and w > mx:
            target = max(tl, lr - 2)
        elif rule == "backoff":
            target = th
        else:
            bump = 2 if zone == "FRESH" else (1 if zone == "OPTIMAL" else 0)
            target = min(th, lr + bump)
            target = max(tl, target)

        # Apply readiness rep modifier
        target = max(tl, min(th, target + rep_mod))

        # Apply fatigue reduction (subtle: -1 rep if significant prior fatigue)
        if fatigue_mult < 0.85:
            target = max(tl, target - 1)

        reps.append(target)

    return {"weight": w, "reps": reps, "rule": rule, "ifi": ifi, "zone": zone,
            "readiness": readiness, "fatigue_mult": fatigue_mult}


# ═══════════════════════════════════════════════════════════════
# TESTS
# ═══════════════════════════════════════════════════════════════

def test_warmups():
    print("=" * 70)
    print("  TEST 1: WARM-UP SET GENERATION")
    print("=" * 70)

    cases = [
        ("Bench Press 225lb", 225, 5, True),
        ("Squat 315lb", 315, 5, True),
        ("Deadlift 405lb", 405, 3, True),
        ("OHP 135lb", 135, 8, True),
        ("DB Curl 40lb", 40, 10, False),
        ("Lateral Raise 20lb", 20, 12, False),
        ("Squat 135lb (beginner)", 135, 8, True),
        ("Bench 315lb (advanced)", 315, 3, True),
    ]

    for name, w, reps, compound in cases:
        wu = generate_warmup(w, reps, compound)
        sets_str = " → ".join(f"{s[0]:.0f}×{s[1]}" for s in wu)
        print(f"\n  {name}: working weight {w}×{reps}")
        print(f"    Warm-up: {sets_str} → [{w}×{reps} working]")
        total_warmup_reps = sum(s[1] for s in wu)
        print(f"    Total warm-up reps: {total_warmup_reps} across {len(wu)} sets")


def test_cross_fatigue():
    print(f"\n{'='*70}")
    print("  TEST 2: CROSS-EXERCISE FATIGUE MODELING")
    print("=" * 70)

    scenarios = [
        ("Triceps after heavy bench (4 sets chest)",
         "Triceps", [("Chest", 4)]),
        ("Biceps after heavy rows (4 sets back)",
         "Biceps", [("Back", 4)]),
        ("Hamstrings after squats (4 sets quads)",
         "Hamstrings", [("Quads", 4)]),
        ("Delts after bench + flyes (6 sets chest)",
         "Delts", [("Chest", 6)]),
        ("Biceps after rows AND pulldowns (8 sets back)",
         "Biceps", [("Back", 8)]),
        ("Chest first exercise (no prior fatigue)",
         "Chest", []),
        ("Glutes after squats + leg press (8 sets quads)",
         "Glutes", [("Quads", 8)]),
    ]

    for name, muscle, prior in scenarios:
        mod = fatigue_modifier(muscle, prior)
        reduction = (1.0 - mod) * 100
        print(f"\n  {name}")
        print(f"    Capacity modifier: {mod:.2f} ({reduction:.0f}% reduction)")
        if mod < 0.85:
            print(f"    → Rep targets reduced by 1 (significant fatigue)")
        elif mod < 0.95:
            print(f"    → Subtle fatigue, no target adjustment")
        else:
            print(f"    → No meaningful fatigue impact")


def test_readiness():
    print(f"\n{'='*70}")
    print("  TEST 3: PRE-WORKOUT READINESS SIMULATION")
    print("=" * 70)

    # Simulate same lifter at same point, but with different readiness scores
    base_session = [(155, 10), (155, 9), (155, 8)]
    st = State()
    st.update(base_session, 6, 10)

    print(f"\n  Last session: 155×10/9/8 | Range 6-10 | T2")
    print(f"  {'Readiness':>10s}  {'Weight':>7s}  {'Targets':>12s}  {'Rule':>10s}  Notes")
    print(f"  {'-'*10}  {'-'*7}  {'-'*12}  {'-'*10}  {'-'*30}")

    for score in [1, 2, 3, 4, 5]:
        rec = recommend_with_readiness([base_session], st, 6, 10, "T2", readiness=score)
        label = {1: "Terrible", 2: "Poor", 3: "Normal", 4: "Good", 5: "Great"}[score]
        rt = "/".join(str(r) for r in rec["reps"])
        w_mod, v_mod, r_mod = readiness_modifier(score)
        notes = f"weight×{w_mod:.2f} reps{r_mod:+d}"
        print(f"  {label:>10s}  {rec['weight']:7.0f}  {rt:>12s}  {rec['rule']:>10s}  {notes}")

    # Extended sim: 8 weeks with varying readiness
    print(f"\n  --- 8-Week Sim with Varying Readiness (T2 Barbell Row 155lb) ---")
    readiness_patterns = {
        "Always Normal (3)":    [3,3,3,3,3,3,3,3],
        "One Bad Week (wk4=1)": [3,3,3,1,3,3,3,3],
        "Two Bad Weeks (4,5)":  [3,3,3,1,1,3,3,3],
        "Trending Up":          [2,2,3,3,4,4,5,5],
        "Trending Down":        [5,4,4,3,3,2,2,1],
    }

    for pattern_name, readiness_list in readiness_patterns.items():
        random.seed(42)
        st2 = State()
        hist2 = []
        base_cap = 10
        true_1rm = e1rm(155, base_cap)

        print(f"\n  Pattern: {pattern_name}")
        for wk in range(8):
            readiness = readiness_list[wk]
            rec = recommend_with_readiness(hist2 if hist2 else [[(155,10),(155,9),(155,8)]],
                                           st2, 6, 10, "T2", readiness=readiness)
            w = rec["weight"] if rec["weight"] > 0 else 155

            # Simulate performance (readiness affects actual capacity too)
            w_mod, _, _ = readiness_modifier(readiness)
            cap = max(3, int(round(base_cap * w_mod + random.gauss(0, 0.5))))
            actual = []
            for s in range(3):
                r = max(1, int(round(cap - s * 0.07 * cap + random.gauss(0, 0.5))))
                actual.append((w, min(r, 13)))
            st2.update(actual, 6, 10)
            hist2.insert(0, actual)
            if len(hist2) > 5: hist2 = hist2[:5]

            rs = "/".join(f"{s[1]:2d}" for s in actual)
            ts = "/".join(f"{r:2d}" for r in rec["reps"][:3])
            print(f"    Wk{wk+1}: R={readiness} {w:5.0f}×{rs} (aim:{ts}) {rec['rule']:12s} e1RM={st2.ema_e1rm:.0f}")

        print(f"    Final e1RM: {st2.ema_e1rm:.0f}")


def test_strength_balance():
    print(f"\n{'='*70}")
    print("  TEST 4: STRENGTH BALANCE ANALYSIS")
    print("=" * 70)

    profiles = {
        "Push-dominant lifter": {
            "bench_press": 250, "barbell_row": 175, "squat": 315,
            "rdl": 225, "ohp": 155, "curl": 80, "pushdown": 100
        },
        "Balanced intermediate": {
            "bench_press": 225, "barbell_row": 215, "squat": 275,
            "deadlift": 335, "ohp": 145, "curl": 90, "pushdown": 95
        },
        "Pull-dominant (climber)": {
            "bench_press": 155, "barbell_row": 225, "squat": 185,
            "deadlift": 275, "ohp": 95, "curl": 70, "pushdown": 55
        },
    }

    for name, e1rms in profiles.items():
        print(f"\n  {name}:")
        results = analyze_strength_balance(e1rms)
        for ratio_name, value, status, ideal in results:
            symbol = "✓" if "BALANCED" in status else "⚠"
            print(f"    {symbol} {ratio_name:<20s} {value:.2f}  (ideal: {ideal})  {status}")


def test_predictive_1rm():
    print(f"\n{'='*70}")
    print("  TEST 5: PREDICTIVE 1RM TIMELINE")
    print("=" * 70)

    profiles = [
        ("Beginner bench (e1RM=135, +1.5%/wk)", 135, 0.015, [185, 225, 275, 315]),
        ("Intermediate squat (e1RM=275, +0.6%/wk)", 275, 0.006, [315, 365, 405]),
        ("Advanced deadlift (e1RM=455, +0.2%/wk)", 455, 0.002, [475, 495, 500, 545]),
    ]

    for name, current, growth, targets in profiles:
        print(f"\n  {name}")
        predictions = predict_e1rm_timeline(current, growth, targets)
        for target, weeks in predictions:
            if weeks is None:
                print(f"    → {target}lb: Not achievable at current rate")
            elif weeks == 0:
                print(f"    → {target}lb: Already achieved!")
            else:
                months = weeks / 4.3
                print(f"    → {target}lb: ~{weeks} weeks ({months:.1f} months)")


def test_genetic_potential():
    print(f"\n{'='*70}")
    print("  TEST 6: GENETIC POTENTIAL ESTIMATION")
    print("=" * 70)

    profiles = [
        ("180lb male, bench=225, squat=315, deadlift=405, ohp=155",
         180, "male", {"bench": 225, "squat": 315, "deadlift": 405, "ohp": 155}),
        ("200lb male, bench=315, squat=405, deadlift=500, ohp=185",
         200, "male", {"bench": 315, "squat": 405, "deadlift": 500, "ohp": 185}),
        ("150lb male beginner, bench=135, squat=185, deadlift=225, ohp=95",
         150, "male", {"bench": 135, "squat": 185, "deadlift": 225, "ohp": 95}),
        ("130lb female, bench=105, squat=175, deadlift=205, ohp=75",
         130, "female", {"bench": 105, "squat": 175, "deadlift": 205, "ohp": 75}),
    ]

    for name, bw, sex, lifts in profiles:
        print(f"\n  {name}")
        potential = estimate_genetic_potential(bw, sex)
        for lift, current in lifts.items():
            pot = potential.get(lift, 0)
            pct = genetic_potential_pct(current, pot)
            bar = "█" * int(pct / 5) + "░" * (20 - int(pct / 5))
            print(f"    {lift:<10s} {current:>4.0f} / {pot:.0f}  [{bar}] {pct:.0f}%")


if __name__ == "__main__":
    print("=" * 70)
    print("  POWERBODYBUILDER ENGINE v3 — FEATURE TESTS")
    print("=" * 70)

    test_warmups()
    test_cross_fatigue()
    test_readiness()
    test_strength_balance()
    test_predictive_1rm()
    test_genetic_potential()

    print(f"\n{'='*70}")
    print("  IMPLEMENTATION PLAN")
    print("=" * 70)
    print("""
  WARM-UP SETS (Train Tab):
    UI: Collapsed "Warm Up" section above working sets per exercise.
    - Default collapsed, tap to expand
    - Shows 3-5 warm-up sets with weight × reps
    - Tapping "Start Working Sets" auto-collapses warm-up
    - Toggle in Settings: "Show warm-up suggestions" (default ON)
    - Warm-up sets are NOT logged to WorkoutLog
    - Only shown for compound exercises by default,
      optional for isolations via per-exercise toggle

  CROSS-EXERCISE FATIGUE (Train Tab):
    UI: Invisible to user — just smarter targets.
    - When exercise B's target muscle was fatigued by exercise A,
      reduce per-set rep targets by 1 (if fatigue > 15%)
    - Show subtle note under rep target: "adjusted for prior chest work"
    - No extra buttons, no extra screens
    - Algorithm-only: affects rep targets, not weight

  PRE-WORKOUT READINESS (Train Tab):
    UI: One quick question before starting workout.
    - "How do you feel today?" with 5 emoji faces (or 1-5 scale)
    - Tappable, dismissable, optional (skip = score 3)
    - Score 1-2: reduces weight recommendation, lowers rep targets
    - Score 4-5: pushes rep targets up, allows slight weight bump
    - Show small badge on session: "Adjusted for low readiness"

  STRENGTH BALANCE (Progress Tab → Overview):
    UI: New card in Overview section.
    - 4 ratio bars: Push:Pull, Posterior:Anterior, OHP:Bench, Bicep:Tricep
    - Color coded: green=balanced, yellow=slight imbalance, red=significant
    - Tap for detail: "Your pull is 20% weaker than push. Consider adding
      1-2 more back sets per week."

  PREDICTIVE 1RM (Progress Tab → Strength):
    UI: Below each PR tile.
    - "At current rate: 315lb in ~8 weeks"
    - Only shown when 4+ sessions of data exist and trend is positive
    - Tap to see full timeline with milestones

  GENETIC POTENTIAL (Progress Tab → new card):
    UI: "YOUR POTENTIAL" card with 4 lift bars.
    - Each bar shows current / estimated ceiling with fill percentage
    - Label: "~65% of estimated natural potential"
    - Disclaimer: "Based on bodyweight estimates. Individual genetics vary."
    - Only shown when user has logged main compound lifts
""")
