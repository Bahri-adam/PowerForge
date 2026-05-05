#!/usr/bin/env python3
"""
Powerbodybuilder Algorithm Simulation
Reimplements core algorithm functions in Python and runs EVERY combination.
Flags anomalies: negative values, MRV violations, MV violations, dead code paths, etc.
"""

import math
from itertools import product

# ═══════════════════════════════════════════════════════════════
# CONSTANTS & ENUMS
# ═══════════════════════════════════════════════════════════════

GOALS = ["hypertrophy", "strength", "powerbuilding", "recomp"]
EXPERIENCES = ["beginner", "intermediate", "advanced", "elite"]
TIERS = ["priority", "neutral", "maintenance"]
BLOCK_TYPES = ["accumulation", "intensification", "reaccumulation", "peak", "deload"]
CALORIE_CONTEXTS = ["surplus", "maintenance", "mild_deficit", "moderate_deficit", "aggressive_deficit"]
MUSCLES = ["Chest", "Back", "Quads", "Hamstrings", "Glutes", "Calves", "Biceps", "Triceps", "Delts"]

TIER_MULTIPLIER = {"priority": 1.5, "neutral": 1.0, "maintenance": 0.7}
CALORIE_MRV_MOD = {
    "surplus": 1.0, "maintenance": 1.0, "unknown": 1.0,
    "mild_deficit": 0.90, "moderate_deficit": 0.85, "aggressive_deficit": 0.75
}
BLOCK_MULTIPLIER = {
    "accumulation": 1.0, "intensification": 0.65, "reaccumulation": 1.15,
    "peak": 0.50, "deload": 1.0
}
MEV_EXP_MULT = {"beginner": 1.0, "intermediate": 1.4, "advanced": 2.0, "elite": 2.3}
MRV_EXP_MULT = {"beginner": 1.0, "intermediate": 1.2, "advanced": 1.35, "elite": 1.45}

DEFAULTS = {
    "Chest":      {"mev": 6, "mavLow": 10, "mavHigh": 16, "mrv": 22},
    "Back":       {"mev": 8, "mavLow": 12, "mavHigh": 18, "mrv": 24},
    "Quads":      {"mev": 6, "mavLow": 10, "mavHigh": 16, "mrv": 22},
    "Hamstrings": {"mev": 4, "mavLow": 8,  "mavHigh": 12, "mrv": 18},
    "Glutes":     {"mev": 2, "mavLow": 6,  "mavHigh": 12, "mrv": 18},
    "Calves":     {"mev": 4, "mavLow": 6,  "mavHigh": 10, "mrv": 16},
    "Biceps":     {"mev": 4, "mavLow": 8,  "mavHigh": 12, "mrv": 18},
    "Triceps":    {"mev": 4, "mavLow": 6,  "mavHigh": 10, "mrv": 16},
    "Delts":      {"mev": 6, "mavLow": 10, "mavHigh": 14, "mrv": 20},
}

MV = {
    "Chest": 6, "Back": 6, "Quads": 6, "Calves": 6,
    "Hamstrings": 4, "Glutes": 4, "Delts": 4, "Triceps": 4, "Biceps": 4
}

T1_MUSCLES = {"Chest", "Back", "Quads", "Delts"}

ALL_MUSCLES = ["Chest", "Back", "Quads", "Hamstrings", "Glutes", "Delts", "Triceps", "Biceps", "Calves"]
PUSH_MUSCLES = ["Chest", "Delts", "Triceps"]
PULL_MUSCLES = ["Back", "Biceps"]
LEG_MUSCLES = ["Quads", "Hamstrings", "Glutes", "Calves"]
UPPER_MUSCLES = ["Chest", "Back", "Delts", "Triceps", "Biceps"]
LOWER_MUSCLES = ["Quads", "Hamstrings", "Glutes", "Calves"]

bugs = []
warnings = []
stats = {"total_combinations": 0, "g1_clamps": 0, "g2_floors": 0, "anomalies": 0}

# ═══════════════════════════════════════════════════════════════
# ALGORITHM FUNCTIONS (exact Swift reimplementation)
# ═══════════════════════════════════════════════════════════════

def scaled_mev(muscle, experience):
    base = DEFAULTS[muscle]["mev"]
    return int(base * MEV_EXP_MULT[experience])

def scaled_mrv(muscle, experience):
    base = DEFAULTS[muscle]["mrv"]
    return int(base * MRV_EXP_MULT[experience])

def effective_mrv(muscle, experience, tier, calorie_ctx):
    s = scaled_mrv(muscle, experience)
    tiered = int(s * TIER_MULTIPLIER[tier])
    return int(tiered * CALORIE_MRV_MOD[calorie_ctx])

def mv(muscle):
    return MV[muscle]

def resolve_weekly_set_target(muscle, week, block_type, tier, experience, calorie_ctx,
                               next_week_adj=0, prev_block_peak=None):
    if block_type == "deload":
        return mv(muscle), "deload→MV"

    base_mev = scaled_mev(muscle, experience)
    priority_bonus = 4 if tier == "priority" else 0
    block_mult = BLOCK_MULTIPLIER[block_type]
    base = int((base_mev + priority_bonus) * block_mult)

    week_adj = 0 if week == 1 else next_week_adj
    result = base + week_adj

    notes = []
    if week == 1 and prev_block_peak is not None:
        capped = min(result, prev_block_peak - 2)
        if capped < result:
            notes.append(f"peak_cap:{result}→{capped}")
            result = capped

    mrv_ceil = effective_mrv(muscle, experience, tier, calorie_ctx)
    mv_floor = mv(muscle)

    if result > mrv_ceil:
        notes.append(f"G1:{result}→{mrv_ceil}")
        stats["g1_clamps"] += 1
        result = mrv_ceil
    if result < mv_floor:
        notes.append(f"G2:{result}→{mv_floor}")
        stats["g2_floors"] += 1
        result = mv_floor

    return result, " ".join(notes) if notes else "ok"

def block_type_next(current, goal, block_number):
    if goal == "hypertrophy" and current == "accumulation":
        return "deload"
    if goal == "hypertrophy" and current == "deload":
        cycle = (block_number + 1) // 2
        return "reaccumulation" if cycle % 2 == 1 else "accumulation"
    if current == "reaccumulation":
        return "deload"
    if goal == "strength" and current == "accumulation":
        return "deload"
    if goal == "strength" and current == "deload" and block_number < 3:
        return "intensification"
    if goal == "strength" and current == "intensification":
        return "deload"
    if goal == "strength" and current == "deload":
        return "peak"
    if goal == "powerbuilding" and current == "accumulation":
        return "deload"
    if goal == "powerbuilding" and current == "intensification":
        return "deload"
    if goal == "powerbuilding" and current == "deload" and block_number % 3 == 1:
        return "intensification"
    if goal == "powerbuilding" and current == "deload":
        return "reaccumulation"
    if goal == "recomp" and current == "deload":
        return "accumulation"
    if goal == "recomp":
        return "deload"
    return "accumulation"

def block_length(goal, experience):
    if goal == "recomp":
        return 3
    if experience in ("beginner", "intermediate"):
        return 5
    return 4

def resolve_split(days, goal, priorities):
    days = min(days, 7)
    if days <= 2:
        return [("Full Body A", ALL_MUSCLES), ("Full Body B", ALL_MUSCLES)]
    if days == 3:
        if goal == "strength":
            return [("Full Body A", ALL_MUSCLES), ("Full Body B", ALL_MUSCLES), ("Full Body C", ALL_MUSCLES)]
        return [("Push", PUSH_MUSCLES), ("Pull", PULL_MUSCLES), ("Legs", LEG_MUSCLES)]
    if days == 4:
        return [("Heavy Upper", UPPER_MUSCLES), ("Heavy Lower", LOWER_MUSCLES),
                ("Hyp Upper", UPPER_MUSCLES), ("Hyp Lower", LOWER_MUSCLES)]
    if days == 5:
        p1 = [priorities[0]] if len(priorities) > 0 else PUSH_MUSCLES
        p2 = [priorities[1]] if len(priorities) > 1 else PULL_MUSCLES
        return [("Push A", PUSH_MUSCLES), ("Pull A", PULL_MUSCLES), ("Legs A", LEG_MUSCLES),
                ("Priority 1", p1), ("Priority 2", p2)]
    if days == 6:
        legs_a = ("Legs-QuadFocus", ["Quads", "Calves"]) if "Quads" in priorities else ("Legs A", LEG_MUSCLES)
        legs_b = ("Legs-Posterior", ["Hamstrings", "Glutes", "Calves"]) if ("Hamstrings" in priorities or "Glutes" in priorities) else ("Legs B", LEG_MUSCLES)
        return [("Push A", PUSH_MUSCLES), ("Pull A", PULL_MUSCLES), legs_a,
                ("Push B", PUSH_MUSCLES), ("Pull B", PULL_MUSCLES), legs_b]
    # 7 days
    six = resolve_split(6, goal, priorities)
    return six + [("Rest", [])]

def exercise_tier_allocation(sets_needed, has_t1):
    if sets_needed <= 0:
        return {"T1": 0, "T2a": 0, "T2b": 0, "T3": 0, "total": 0, "dropped": 0}
    if has_t1:
        t1 = min(5, sets_needed)
        rem = sets_needed - t1
        t2a = min(4, rem) if rem > 0 else 0
        rem -= t2a
        t2b = min(3, rem) if rem > 0 else 0
        rem -= t2b
        t3 = min(3, rem) if rem > 0 else 0
        rem -= t3
        total = t1 + t2a + t2b + t3
        return {"T1": t1, "T2a": t2a, "T2b": t2b, "T3": t3, "total": total, "dropped": sets_needed - total}
    else:
        t2a = min(4, sets_needed)
        rem = sets_needed - t2a
        t2b = min(3, rem) if rem > 0 else 0
        rem -= t2b
        t3 = min(3, rem) if rem > 0 else 0
        rem -= t3
        total = t2a + t2b + t3
        return {"T1": 0, "T2a": t2a, "T2b": t2b, "T3": t3, "total": total, "dropped": sets_needed - total}

# ═══════════════════════════════════════════════════════════════
# RUN EVERY COMBINATION
# ═══════════════════════════════════════════════════════════════

output_lines = []
def log(s):
    output_lines.append(s)

def log_bug(s):
    bugs.append(s)
    output_lines.append(f"  *** BUG: {s}")

def log_warn(s):
    warnings.append(s)
    output_lines.append(f"  ! WARNING: {s}")

log("=" * 90)
log("POWERBODYBUILDER ALGORITHM SIMULATION — ACTUAL COMPUTED OUTPUT")
log("Every combination run through the algorithm functions")
log("=" * 90)
log("")

# ─── TEST 1: SPLIT STRUCTURE ─────────────────────────────────────

log("=" * 90)
log("TEST 1: SPLIT STRUCTURE — every days × goal × priority combination")
log("=" * 90)

for days in range(1, 8):
    for goal in GOALS:
        for prio_set in [[], ["Quads"], ["Chest", "Back"], ["Quads", "Hamstrings"]]:
            split = resolve_split(days, goal, prio_set)
            # Check all muscles are covered at least once
            covered = set()
            for label, muscles in split:
                covered.update(muscles)

            missing = set(ALL_MUSCLES) - covered
            log(f"  {days}d {goal:14s} prio={str(prio_set):30s} → {len(split)} sessions")
            for label, muscles in split:
                log(f"    {label:20s} → {muscles}")

            if days >= 3 and goal != "strength" and missing:
                log_warn(f"{days}d {goal} prio={prio_set}: muscles not covered: {missing}")

            # Check session count matches days
            if len(split) != max(2, min(days, 7)):
                if not (days <= 2 and len(split) == 2):
                    if not (days == 3 and goal == "strength" and len(split) == 3):
                        log_bug(f"{days}d {goal}: expected {days} sessions, got {len(split)}")

            stats["total_combinations"] += 1
        log("")

# ─── TEST 2: WEEKLY SET TARGETS ──────────────────────────────────

log("")
log("=" * 90)
log("TEST 2: WEEKLY SET TARGETS — every muscle × experience × tier × blockType × calorie")
log("=" * 90)

for muscle in MUSCLES:
    log(f"\n  ─── {muscle} ───")
    for exp in EXPERIENCES:
        for tier in TIERS:
            for bt in BLOCK_TYPES:
                for cal in CALORIE_CONTEXTS:
                    for week in [1, 3]:  # Test week 1 (adj=0) and week 3 (adj applies)
                        for adj in [0, 2, -2]:
                            result, notes = resolve_weekly_set_target(
                                muscle, week, bt, tier, exp, cal,
                                next_week_adj=adj, prev_block_peak=None)

                            mrv_ceil = effective_mrv(muscle, exp, tier, cal) if bt != "deload" else 999
                            mv_floor = mv(muscle)

                            # ANOMALY CHECKS
                            if result < 0:
                                log_bug(f"{muscle} {exp} {tier} {bt} {cal} wk{week} adj={adj}: NEGATIVE sets={result}")
                                stats["anomalies"] += 1
                            if bt != "deload" and result > mrv_ceil:
                                log_bug(f"{muscle} {exp} {tier} {bt} {cal} wk{week} adj={adj}: EXCEEDS MRV {result}>{mrv_ceil}")
                                stats["anomalies"] += 1
                            if result < mv_floor:
                                log_bug(f"{muscle} {exp} {tier} {bt} {cal} wk{week} adj={adj}: BELOW MV {result}<{mv_floor}")
                                stats["anomalies"] += 1

                            stats["total_combinations"] += 1

            # Log one representative line per muscle/exp/tier
            r_acc, _ = resolve_weekly_set_target(muscle, 2, "accumulation", tier, exp, "surplus")
            r_int, _ = resolve_weekly_set_target(muscle, 2, "intensification", tier, exp, "surplus")
            r_rea, _ = resolve_weekly_set_target(muscle, 2, "reaccumulation", tier, exp, "surplus")
            r_pea, _ = resolve_weekly_set_target(muscle, 2, "peak", tier, exp, "surplus")
            r_del, _ = resolve_weekly_set_target(muscle, 2, "deload", tier, exp, "surplus")
            mrv_s = effective_mrv(muscle, exp, tier, "surplus")
            mrv_a = effective_mrv(muscle, exp, tier, "aggressive_deficit")
            log(f"    {exp:12s} {tier:11s} acc={r_acc:2d} int={r_int:2d} reacc={r_rea:2d} peak={r_pea:2d} deload={r_del:2d}  MRV(sur)={mrv_s:2d} MRV(agg)={mrv_a:2d}")

# ─── TEST 3: BLOCK SEQUENCES ────────────────────────────────────

log("")
log("=" * 90)
log("TEST 3: BLOCK SEQUENCES — 20 transitions per goal")
log("=" * 90)

for goal in GOALS:
    log(f"\n  ─── {goal} ───")
    current = "accumulation"
    for bn in range(20):
        nxt = block_type_next(current, goal, bn)
        log(f"    bn={bn:2d}  {current:18s} → {nxt}")

        # ANOMALY: infinite deload loop
        if current == "deload" and nxt == "deload":
            log_bug(f"{goal}: deload→deload at bn={bn} — INFINITE LOOP")
            stats["anomalies"] += 1

        # ANOMALY: same block type repeating (not deload)
        if current == nxt and current != "deload":
            log_warn(f"{goal}: {current}→{current} at bn={bn} — same block repeating")

        current = nxt
        stats["total_combinations"] += 1

    # Check that non-deload training block types actually appear
    current = "accumulation"
    training_blocks_seen = set()
    for bn in range(30):
        if current != "deload":
            training_blocks_seen.add(current)
        current = block_type_next(current, goal, bn)

    for bt in ["accumulation"]:
        if bt not in training_blocks_seen:
            log_warn(f"{goal}: '{bt}' never appears in 30-block trace")

    if goal == "hypertrophy" and "reaccumulation" not in training_blocks_seen:
        log_bug(f"hypertrophy: 'reaccumulation' never appears in 30-block trace")
    if goal == "powerbuilding" and "reaccumulation" not in training_blocks_seen:
        log_bug(f"powerbuilding: 'reaccumulation' never appears in 30-block trace")
    if goal == "powerbuilding" and "intensification" not in training_blocks_seen:
        log_bug(f"powerbuilding: 'intensification' never appears in 30-block trace")

# ─── TEST 4: EXERCISE TIER ALLOCATION ────────────────────────────

log("")
log("=" * 90)
log("TEST 4: EXERCISE TIER ALLOCATION — sets 0-20 for T1 and non-T1 muscles")
log("=" * 90)

for has_t1 in [True, False]:
    label = "WITH T1 anchor" if has_t1 else "WITHOUT T1 anchor"
    log(f"\n  ─── {label} ───")
    for sets_needed in range(0, 21):
        alloc = exercise_tier_allocation(sets_needed, has_t1)
        log(f"    sets={sets_needed:2d}  T1={alloc['T1']} T2a={alloc['T2a']} T2b={alloc['T2b']} T3={alloc['T3']}  "
            f"assigned={alloc['total']} dropped={alloc['dropped']}")

        if alloc["total"] > sets_needed:
            log_bug(f"tier alloc: assigned {alloc['total']} > needed {sets_needed}")
            stats["anomalies"] += 1
        if alloc["dropped"] < 0:
            log_bug(f"tier alloc: negative dropped {alloc['dropped']}")
            stats["anomalies"] += 1
        if sets_needed > 0 and alloc["total"] == 0:
            log_bug(f"tier alloc: 0 assigned for {sets_needed} needed")
            stats["anomalies"] += 1

        stats["total_combinations"] += 1

# ─── TEST 5: SESSION SET TOTALS ──────────────────────────────────

log("")
log("=" * 90)
log("TEST 5: SESSION SET TOTALS — does any session exceed 24 sets?")
log("=" * 90)

SESSION_CAP = 24

for days in [2, 3, 4, 5, 6]:
    for goal in GOALS:
        for exp in EXPERIENCES:
            for tier_config in ["all_neutral", "all_priority"]:
                split = resolve_split(days, goal, [])
                for label, session_muscles in split:
                    if not session_muscles:
                        continue

                    sessions_per_muscle = {}
                    for m in session_muscles:
                        count = sum(1 for _, ms in split if m in ms)
                        sessions_per_muscle[m] = count

                    session_total = 0
                    muscle_sets = {}
                    for m in session_muscles:
                        t = "priority" if tier_config == "all_priority" else "neutral"
                        weekly, _ = resolve_weekly_set_target(m, 2, "accumulation", t, exp, "surplus")
                        per_session = weekly // max(1, sessions_per_muscle[m])
                        capped = min(per_session, SESSION_CAP - session_total)
                        capped = max(0, capped)
                        muscle_sets[m] = capped
                        session_total += capped

                    if session_total > SESSION_CAP:
                        log_bug(f"{days}d {goal} {exp} {tier_config} {label}: {session_total} sets > 24 cap!")
                        stats["anomalies"] += 1

                    if session_total > 20:  # Flag dense sessions
                        dropped = [m for m in session_muscles if muscle_sets.get(m, 0) == 0]
                        log(f"  {days}d {goal:14s} {exp:12s} {tier_config:12s} {label:20s}: {session_total} sets"
                            f"{'  DROPPED: ' + str(dropped) if dropped else ''}")

                    stats["total_combinations"] += 1

# ─── TEST 6: previousBlockPeakSets EDGE CASES ───────────────────

log("")
log("=" * 90)
log("TEST 6: previousBlockPeakSets cap on week 1")
log("=" * 90)

for muscle in ["Chest", "Back", "Hamstrings"]:
    log(f"\n  ─── {muscle} (intermediate, neutral, accumulation, surplus) ───")
    for peak in [None, 20, 14, 10, 8, 6, 4, 2, 0]:
        result, notes = resolve_weekly_set_target(
            muscle, 1, "accumulation", "neutral", "intermediate", "surplus",
            prev_block_peak=peak)
        log(f"    peak={str(peak):5s}  result={result:2d}  {notes}")

        if result < mv(muscle):
            log_bug(f"{muscle} peak={peak}: result {result} below MV {mv(muscle)}")
            stats["anomalies"] += 1

        stats["total_combinations"] += 1

# ─── TEST 7: EXTREME nextWeekAdjustment ──────────────────────────

log("")
log("=" * 90)
log("TEST 7: Extreme nextWeekAdjustment values")
log("=" * 90)

for muscle in ["Chest", "Hamstrings", "Glutes"]:
    log(f"\n  ─── {muscle} (intermediate, neutral, accumulation, surplus, week 3) ───")
    for adj in range(-15, 16):
        result, notes = resolve_weekly_set_target(
            muscle, 3, "accumulation", "neutral", "intermediate", "surplus",
            next_week_adj=adj)
        flag = ""
        mrv = effective_mrv(muscle, "intermediate", "neutral", "surplus")
        if result == mrv:
            flag = " [AT MRV CEILING]"
        if result == mv(muscle):
            flag = " [AT MV FLOOR]"
        if adj in [-15, -10, -5, 0, 5, 10, 15]:
            log(f"    adj={adj:+3d}  result={result:2d}  MRV={mrv} MV={mv(muscle)}{flag}  {notes}")

        stats["total_combinations"] += 1

# ─── TEST 8: CALORIE CONTEXT SENSITIVITY ─────────────────────────

log("")
log("=" * 90)
log("TEST 8: Does calorie context actually constrain anything?")
log("=" * 90)

constrained_count = 0
for muscle in MUSCLES:
    for exp in EXPERIENCES:
        for tier in TIERS:
            surplus_result, _ = resolve_weekly_set_target(
                muscle, 2, "accumulation", tier, exp, "surplus")
            agg_result, _ = resolve_weekly_set_target(
                muscle, 2, "accumulation", tier, exp, "aggressive_deficit")
            if surplus_result != agg_result:
                constrained_count += 1
                log(f"  {muscle:12s} {exp:12s} {tier:11s}: surplus={surplus_result} agg_deficit={agg_result} (MRV constrains)")

log(f"\n  Calorie context changed the result in {constrained_count} of {len(MUSCLES)*len(EXPERIENCES)*len(TIERS)} combinations")
if constrained_count == 0:
    log_warn("Calorie context NEVER constrains base set targets at week 2 accumulation. "
             "It only matters when volume escalates via nextWeekAdjustment or reaccumulation blocks.")

# ─── TEST 9: BLOCK LENGTH MATRIX ────────────────────────────────

log("")
log("=" * 90)
log("TEST 9: Block length for every goal × experience")
log("=" * 90)

for goal in GOALS:
    for exp in EXPERIENCES:
        bl = block_length(goal, exp)
        log(f"  {goal:14s} {exp:12s}: {bl} weeks + 1 deload = {bl+1} total")
        stats["total_combinations"] += 1

# ─── TEST 10: MRV CEILING AUDIT ─────────────────────────────────

log("")
log("=" * 90)
log("TEST 10: Can base set target EVER exceed MRV ceiling?")
log("=" * 90)

violations = 0
for muscle in MUSCLES:
    for exp in EXPERIENCES:
        for tier in TIERS:
            for bt in ["accumulation", "intensification", "reaccumulation", "peak"]:
                for cal in CALORIE_CONTEXTS:
                    result, notes = resolve_weekly_set_target(
                        muscle, 2, bt, tier, exp, cal)
                    mrv = effective_mrv(muscle, exp, tier, cal)
                    if result > mrv:
                        violations += 1
                        log_bug(f"{muscle} {exp} {tier} {bt} {cal}: {result} > MRV {mrv}")

log(f"  MRV violations found: {violations}")
if violations == 0:
    log(f"  G1 (clampToMRV) is working correctly across all {len(MUSCLES)*len(EXPERIENCES)*len(TIERS)*4*len(CALORIE_CONTEXTS)} combinations")

# ─── TEST 11: MV FLOOR AUDIT ────────────────────────────────────

log("")
log("=" * 90)
log("TEST 11: Can base set target EVER go below MV floor?")
log("=" * 90)

mv_violations = 0
for muscle in MUSCLES:
    for exp in EXPERIENCES:
        for tier in TIERS:
            for bt in BLOCK_TYPES:
                for cal in CALORIE_CONTEXTS:
                    result, notes = resolve_weekly_set_target(
                        muscle, 2, bt, tier, exp, cal)
                    if result < mv(muscle):
                        mv_violations += 1
                        log_bug(f"{muscle} {exp} {tier} {bt} {cal}: {result} < MV {mv(muscle)}")

log(f"  MV violations found: {mv_violations}")
if mv_violations == 0:
    log(f"  G2 (floorAtMV) is working correctly across all combinations")

# ─── TEST 12: FULL PROGRAM GENERATION SIMULATION ────────────────

log("")
log("=" * 90)
log("TEST 12: FULL PROGRAM SIMULATION — 5 representative profiles")
log("=" * 90)

profiles = [
    {"name": "Beginner Hypertrophy 4d Surplus", "goal": "hypertrophy", "exp": "beginner",
     "days": 4, "cal": "surplus", "tiers": {m: "neutral" for m in MUSCLES}, "priorities": []},
    {"name": "Intermediate Strength 3d Maintenance", "goal": "strength", "exp": "intermediate",
     "days": 3, "cal": "maintenance", "tiers": {m: "neutral" for m in MUSCLES}, "priorities": []},
    {"name": "Advanced PB 6d ModDeficit Quad+Chest Prio", "goal": "powerbuilding", "exp": "advanced",
     "days": 6, "cal": "moderate_deficit",
     "tiers": {**{m: "neutral" for m in MUSCLES}, "Quads": "priority", "Chest": "priority"},
     "priorities": ["Quads", "Chest"]},
    {"name": "Elite Hypertrophy 6d AggDeficit 4 Priorities", "goal": "hypertrophy", "exp": "elite",
     "days": 6, "cal": "aggressive_deficit",
     "tiers": {**{m: "neutral" for m in MUSCLES}, "Chest": "priority", "Back": "priority",
               "Quads": "priority", "Delts": "priority"},
     "priorities": ["Quads"]},
    {"name": "Intermediate Recomp 4d Maintenance", "goal": "recomp", "exp": "intermediate",
     "days": 4, "cal": "maintenance", "tiers": {m: "neutral" for m in MUSCLES}, "priorities": []},
]

for prof in profiles:
    log(f"\n  {'═'*80}")
    log(f"  PROFILE: {prof['name']}")
    log(f"  {'═'*80}")

    bl = block_length(prof["goal"], prof["exp"])
    split = resolve_split(prof["days"], prof["goal"], prof["priorities"])

    log(f"  Block length: {bl} weeks + 1 deload")
    log(f"  Split: {', '.join(label for label, _ in split)}")

    # Simulate 3 blocks
    current_block = "accumulation"
    for block_idx in range(3):
        nxt = block_type_next(current_block, prof["goal"], block_idx)
        log(f"\n  Block {block_idx}: {current_block} (multiplier={BLOCK_MULTIPLIER[current_block]:.2f})")

        for week in [1, bl]:  # First and last training week
            log(f"    Week {week}:")
            for label, session_muscles in split:
                if not session_muscles:
                    continue

                session_total = 0
                session_detail = []
                for m in session_muscles:
                    freq = sum(1 for _, ms in split if m in ms)
                    t = prof["tiers"].get(m, "neutral")
                    weekly, notes = resolve_weekly_set_target(
                        m, week, current_block, t, prof["exp"], prof["cal"])
                    per_session = weekly // max(1, freq)
                    capped = min(per_session, SESSION_CAP - session_total)
                    capped = max(0, capped)

                    has_t1 = m in T1_MUSCLES
                    if prof["goal"] == "strength" and m not in {"Chest", "Back", "Quads", "Delts"}:
                        has_t1 = False
                    alloc = exercise_tier_allocation(capped, has_t1)

                    session_detail.append(f"{m}={capped}({alloc['T1']}+{alloc['T2a']}+{alloc['T2b']}+{alloc['T3']})")
                    session_total += capped

                log(f"      {label:20s} [{session_total:2d} sets] {', '.join(session_detail)}")

                if session_total > SESSION_CAP:
                    log_bug(f"Profile '{prof['name']}' {label} week {week}: {session_total} > 24 sets")

        current_block = nxt

# ─── SUMMARY ─────────────────────────────────────────────────────

log("")
log("=" * 90)
log("SIMULATION SUMMARY")
log("=" * 90)
log(f"  Total combinations tested: {stats['total_combinations']}")
log(f"  G1 (MRV clamp) activations: {stats['g1_clamps']}")
log(f"  G2 (MV floor) activations: {stats['g2_floors']}")
log(f"  Anomalies found: {stats['anomalies']}")
log(f"  Bugs found: {len(bugs)}")
log(f"  Warnings: {len(warnings)}")

if bugs:
    log(f"\n  *** BUGS ***")
    for b in bugs:
        log(f"    • {b}")
else:
    log(f"\n  NO BUGS FOUND — all guard rails working correctly")

if warnings:
    log(f"\n  WARNINGS:")
    for w in warnings:
        log(f"    • {w}")

# ─── WRITE TO FILE ───────────────────────────────────────────────

output_path = "/Users/ayb/Desktop/Powerbodybuilder/SimulationOutput.txt"
with open(output_path, "w") as f:
    f.write("\n".join(output_lines))

print(f"Simulation complete. {stats['total_combinations']} combinations tested.")
print(f"Bugs: {len(bugs)}, Warnings: {len(warnings)}, Anomalies: {stats['anomalies']}")
print(f"Results written to: {output_path}")
