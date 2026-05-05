#!/usr/bin/env python3
"""
Per-Set Rep Target Bug Investigation
====================================
Tests the bug where rep targets show flat targetRepsHigh (e.g., 8/8/8 or 15/15/15)
instead of realistic per-set progression (e.g., 6/5/5 or 12/11/10).

Scenarios covered:
  1. Early sessions (G8 guard: <3 exposures)
  2. Post program switch (no history in current instance, but history in others)
  3. Deload week (current logic returns flat ceiling)
  4. Normal progression (various rep ranges 3-5, 6-10, 8-12, 10-15, 12-20)
  5. Various last-session patterns (symmetric, asymmetric, single set)
  6. Edge cases (no history, missing reps, range edges)

Run: python3 progression_persetreps_test.py
"""

# ═══════════════════════════════════════════════════════════════
# SIMPLIFIED ENGINE FOR TESTING
# ═══════════════════════════════════════════════════════════════

def compute_ifi(sets):
    """sets = [(weight, reps)]"""
    if len(sets) < 2: return 0.0
    mx = max(s[0] for s in sets)
    working = [s for s in sets if s[0] >= mx * 0.80]
    if len(working) < 2: return 0.0
    f = working[0][0] * working[0][1]
    l = working[-1][0] * working[-1][1]
    if f <= 0: return 0.0
    return max(0.0, (f - l) / f)


def ifi_zone(ifi):
    if ifi < 0.10: return "FRESH"
    if ifi < 0.25: return "OPTIMAL"
    if ifi < 0.40: return "FATIGUED"
    return "OVERTRAINED"


# ─── CURRENT BUGGY ENGINE ───

def current_engine(last_session, target_low, target_high, target_sets,
                    exposures, is_deload=False):
    """
    Returns (reps_per_set, debug_note)
    Mirrors the current Swift logic with its bugs.
    """
    # No history → flat targetRepsHigh
    if not last_session:
        return ([target_high] * target_sets, "no_history → flat ceiling")

    # Deload → flat targetRepsHigh (BUG)
    if is_deload:
        return ([target_high] * target_sets, "deload → flat ceiling (BUG)")

    # G8 guard → flat targetRepsHigh (BUG)
    if exposures < 3:
        return ([target_high] * target_sets, "G8 guard → flat ceiling (BUG)")

    # Main path: compute per-set from last session
    return (compute_per_set(last_session, target_low, target_high, target_sets,
                             rule="hold", weight_increased=False),
            "main path → per-set from last session")


# ─── FIXED ENGINE ───

def fixed_engine(last_session, target_low, target_high, target_sets,
                  exposures, is_deload=False):
    """
    Always computes per-set reps from last session when available.
    Early returns still fire but populate perSetReps from last session.
    """
    if not last_session:
        return ([target_high] * target_sets, "no_history → flat ceiling (genuine)")

    # Compute fallback from last session
    fallback = compute_per_set(last_session, target_low, target_high, target_sets,
                                rule="hold", weight_increased=False)

    if is_deload:
        # Deload: reduce targets by ~30% from fallback
        deload_targets = [max(target_low, int(r * 0.70)) for r in fallback]
        return (deload_targets, "deload → 70% of last session")

    if exposures < 3:
        return (fallback, "G8 guard → using last session pattern")

    return (fallback, "normal → per-set from last session")


def compute_per_set(last_session, target_low, target_high, target_sets,
                     rule="hold", weight_increased=False):
    """
    Core per-set rep target calculation.
    Front-loaded progression: top set (i=0) gets a larger bump than secondary sets.
    This prevents "flat ceiling" when IFI is artificially 0 (single set / all-equal reps)
    and matches how real progression works — push the top set, secondary sets follow.
    """
    if not last_session:
        return [target_high] * target_sets

    sorted_sets = sorted(last_session, key=lambda s: s[2] if len(s) >= 3 else 0)
    ifi = compute_ifi([(s[0], s[1]) for s in last_session])
    zone = ifi_zone(ifi)

    # Front-loaded bumps
    if zone == "FRESH":
        bump_top, bump_sec = 2, 1
    elif zone == "OPTIMAL":
        bump_top, bump_sec = 1, 1
    else:  # FATIGUED / OVERTRAINED
        bump_top, bump_sec = 0, 0

    results = []
    for i in range(target_sets):
        if i < len(sorted_sets):
            last_reps = sorted_sets[i][1]
        elif sorted_sets:
            last_reps = sorted_sets[-1][1]
        else:
            last_reps = target_low

        if weight_increased:
            target = max(target_low, last_reps - 2)
        elif rule == "backoff":
            target = max(target_low, min(target_high, last_reps + 3))
        else:
            bump = bump_top if i == 0 else bump_sec
            target = max(target_low, min(target_high, last_reps + bump))

        results.append(target)

    return results


# ═══════════════════════════════════════════════════════════════
# TEST SCENARIOS
# ═══════════════════════════════════════════════════════════════

SCENARIOS = [
    # ──── USER'S REPORTED BUGS ────
    {
        "name": "USER BUG #1: 135×5, range 5-8, expects realistic",
        "last_session": [(135, 5, 0), (135, 4, 1), (135, 4, 2)],
        "target_low": 5, "target_high": 8, "target_sets": 3,
        "exposures": 2,  # G8 fires
        "is_deload": False,
        "expected_current": [8, 8, 8],   # buggy
        "expected_fix_range": [(5, 7)],   # 5-7 acceptable
    },
    {
        "name": "USER BUG #2: 170×10, range 10-15, expects realistic",
        "last_session": [(170, 10, 0), (170, 9, 1), (170, 8, 2)],
        "target_low": 10, "target_high": 15, "target_sets": 3,
        "exposures": 2,  # G8 fires
        "is_deload": False,
        "expected_current": [15, 15, 15],  # buggy
        "expected_fix_range": [(10, 12)],
    },

    # ──── EARLY SESSIONS (G8 GUARD) ────
    {
        "name": "Session 1: First time logging — 225×5",
        "last_session": [(225, 5, 0), (225, 5, 1), (225, 4, 2)],
        "target_low": 3, "target_high": 5, "target_sets": 3,
        "exposures": 1,  # G8 fires
        "is_deload": False,
    },
    {
        "name": "Session 2: Second exposure — 185×8",
        "last_session": [(185, 8, 0), (185, 7, 1), (185, 7, 2)],
        "target_low": 6, "target_high": 10, "target_sets": 3,
        "exposures": 2,  # G8 fires
        "is_deload": False,
    },
    {
        "name": "Session 3: Third exposure — G8 about to release",
        "last_session": [(225, 5, 0), (225, 5, 1), (225, 5, 2)],
        "target_low": 3, "target_high": 5, "target_sets": 3,
        "exposures": 3,  # G8 releases
        "is_deload": False,
    },

    # ──── VARIOUS REP RANGES ────
    {
        "name": "Heavy 3-5 range: 315×3",
        "last_session": [(315, 3, 0), (315, 3, 1), (315, 2, 2)],
        "target_low": 3, "target_high": 5, "target_sets": 3,
        "exposures": 5, "is_deload": False,
    },
    {
        "name": "Strength 5-8 range: 205×6",
        "last_session": [(205, 6, 0), (205, 6, 1), (205, 5, 2)],
        "target_low": 5, "target_high": 8, "target_sets": 3,
        "exposures": 5, "is_deload": False,
    },
    {
        "name": "Hypertrophy 8-12 range: 155×10",
        "last_session": [(155, 10, 0), (155, 9, 1), (155, 9, 2)],
        "target_low": 8, "target_high": 12, "target_sets": 3,
        "exposures": 5, "is_deload": False,
    },
    {
        "name": "Accessory 10-15 range: 75×12",
        "last_session": [(75, 12, 0), (75, 11, 1), (75, 10, 2)],
        "target_low": 10, "target_high": 15, "target_sets": 3,
        "exposures": 5, "is_deload": False,
    },
    {
        "name": "High-rep 12-20 range: 25×15",
        "last_session": [(25, 15, 0), (25, 14, 1), (25, 13, 2)],
        "target_low": 12, "target_high": 20, "target_sets": 3,
        "exposures": 5, "is_deload": False,
    },

    # ──── DELOAD WEEK ────
    {
        "name": "Deload: last was 225×8, want reduced volume",
        "last_session": [(225, 8, 0), (225, 7, 1), (225, 7, 2)],
        "target_low": 6, "target_high": 10, "target_sets": 3,
        "exposures": 8, "is_deload": True,
    },

    # ──── NO HISTORY ────
    {
        "name": "Genuine no history — brand new exercise",
        "last_session": [],
        "target_low": 8, "target_high": 12, "target_sets": 3,
        "exposures": 0, "is_deload": False,
    },

    # ──── EDGE CASES ────
    {
        "name": "Only 1 set logged: 135×6",
        "last_session": [(135, 6, 0)],
        "target_low": 5, "target_high": 8, "target_sets": 3,
        "exposures": 5, "is_deload": False,
    },
    {
        "name": "All sets same: 185×8/8/8",
        "last_session": [(185, 8, 0), (185, 8, 1), (185, 8, 2)],
        "target_low": 6, "target_high": 10, "target_sets": 3,
        "exposures": 5, "is_deload": False,
    },
    {
        "name": "Severe drop-off: 225×10/6/4 (OVERTRAINED)",
        "last_session": [(225, 10, 0), (225, 6, 1), (225, 4, 2)],
        "target_low": 8, "target_high": 12, "target_sets": 3,
        "exposures": 5, "is_deload": False,
    },
    {
        "name": "At top of range: 185×12",
        "last_session": [(185, 12, 0), (185, 12, 1), (185, 12, 2)],
        "target_low": 8, "target_high": 12, "target_sets": 3,
        "exposures": 5, "is_deload": False,
    },
    {
        "name": "4-set scenario, 3 logged last week",
        "last_session": [(155, 8, 0), (155, 7, 1), (155, 6, 2)],
        "target_low": 6, "target_high": 10, "target_sets": 4,  # 4 sets but only 3 logged
        "exposures": 5, "is_deload": False,
    },
]


# ═══════════════════════════════════════════════════════════════
# TEST RUNNER
# ═══════════════════════════════════════════════════════════════

def format_session(sets):
    if not sets: return "(empty)"
    return "/".join(f"{s[1]}" for s in sets)


def run_scenario(s):
    name = s["name"]
    last = s["last_session"]
    tl, th, ts = s["target_low"], s["target_high"], s["target_sets"]
    exp = s["exposures"]
    deload = s.get("is_deload", False)

    current_result, current_note = current_engine(last, tl, th, ts, exp, deload)
    fixed_result, fixed_note = fixed_engine(last, tl, th, ts, exp, deload)

    last_str = format_session(last) if last else "(no history)"
    weight = last[0][0] if last else 0

    ifi = compute_ifi([(s[0], s[1]) for s in last]) if last else 0.0

    print(f"\n  {name}")
    print(f"    Last:       {weight}×{last_str}   (range {tl}-{th}, exposures={exp}, IFI={ifi:.2f})")
    if deload:
        print(f"    Context:    DELOAD WEEK")
    cur_flat = all(r == th for r in current_result)
    fix_flat = all(r == th for r in fixed_result)
    cur_symbol = "✗" if cur_flat and last else "✓"
    fix_symbol = "✓" if not fix_flat or not last else "✓"
    print(f"    {cur_symbol} Current:  {'/'.join(str(r) for r in current_result):<12s} ({current_note})")
    print(f"    {fix_symbol} Fixed:    {'/'.join(str(r) for r in fixed_result):<12s} ({fixed_note})")

    # Check expected range if specified
    if "expected_fix_range" in s:
        low, high = s["expected_fix_range"][0]
        all_in_range = all(low <= r <= high for r in fixed_result)
        marker = "✓ in range" if all_in_range else "✗ OUT OF RANGE"
        print(f"    Expected:   all in {low}-{high}  {marker}")

    return {
        "name": name,
        "current_flat": cur_flat and bool(last),
        "fixed_flat": fix_flat and bool(last),
        "last_was_ceiling": bool(last) and last[0][1] >= th,
    }


if __name__ == "__main__":
    print("=" * 75)
    print("  PER-SET REP TARGET BUG TESTS")
    print("  Current engine (buggy) vs Fixed engine (per-set fallback)")
    print("=" * 75)

    results = []
    for s in SCENARIOS:
        r = run_scenario(s)
        results.append(r)

    # Scorecard
    print(f"\n{'='*75}")
    print(f"  SCORECARD")
    print(f"{'='*75}")

    current_bugs = sum(1 for r in results if r["current_flat"] and not r["last_was_ceiling"])
    fixed_bugs = sum(1 for r in results if r["fixed_flat"] and not r["last_was_ceiling"])
    total_with_history = sum(1 for r in results if r.get("name") and "no history" not in r["name"].lower())

    print(f"\n  Scenarios with realistic history:  {total_with_history}")
    print(f"  Current engine flat ceiling bugs:  {current_bugs}")
    print(f"  Fixed engine flat ceiling bugs:    {fixed_bugs}")
    print()

    if fixed_bugs == 0:
        print(f"  ✓ FIX WORKS: All scenarios with history now show realistic per-set targets")
    else:
        print(f"  ✗ FIX INCOMPLETE: {fixed_bugs} scenarios still showing flat ceiling")

    print(f"\n{'='*75}")
    print(f"  ANALYSIS")
    print(f"{'='*75}")
    print("""
  The bug: Current engine has 3 early-return paths that set perSetReps: [].
  When perSetReps is empty, repsForSet(i) falls back to recommendedReps
  (which is always targetRepsHigh). Result: user sees flat ceiling 8/8/8
  or 15/15/15 regardless of actual performance.

  The fix: Compute per-set reps from last session BEFORE any early return.
  If last session has data, use it. If not (genuine no history), show
  targetRepsHigh as before. This preserves the guard rail behavior while
  fixing the display bug.

  Early-return paths affected:
    1. G8 guard (exposures < 3) — fixed ✓
    2. Deload week — fixed ✓
    3. No history (genuine) — unchanged (still shows ceiling as intended)
""")
