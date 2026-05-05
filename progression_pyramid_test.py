#!/usr/bin/env python3
"""
Per-Set Weight-Aware Progression Test
======================================
Validates the proposed engine upgrade that preserves per-set weight patterns
(straight sets, ascending pyramid, reverse pyramid, mixed) instead of flattening
everything to the top weight.

Key rules:
  1. Detect pattern from last session's weights
  2. STRAIGHT: same weight all sets, front-loaded progression
  3. ASCENDING: preserve feeder weights, progress top set only
  4. REVERSE: preserve descending, top set is set 1
  5. MIXED: fallback to straight sets at top weight
  6. Use ranges for uncertain predictions (e.g., "15-18")
  7. Inverted Epley for new-weight rep predictions
  8. Nuzzo decay for sets beyond the top (if at same/similar weight)

Run: python3 progression_pyramid_test.py
"""

# ═══════════════════════════════════════════════════════════════
# CORE MATH
# ═══════════════════════════════════════════════════════════════

def e1rm(weight, reps):
    """Epley formula, valid for 1-12 reps."""
    if weight <= 0 or reps <= 0: return 0.0
    return weight * (1.0 + reps / 30.0)


def reps_at_weight(e1, weight):
    """Inverted Epley: estimate reps achievable at a given weight from e1RM."""
    if weight <= 0 or e1 <= 0 or weight >= e1: return 1
    return max(1, int(round(30.0 * (e1 / weight - 1.0))))


def compute_ifi(sets):
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


# ═══════════════════════════════════════════════════════════════
# WEIGHT PATTERN DETECTION
# ═══════════════════════════════════════════════════════════════

def detect_pattern(last_session):
    """
    last_session: [(weight, reps)] sorted by set index
    Returns: ("STRAIGHT"|"ASCENDING"|"REVERSE"|"MIXED", weights_list)
    """
    if not last_session:
        return ("NONE", [])

    weights = [s[0] for s in last_session]
    unique = sorted(set(weights))

    if len(unique) == 1:
        return ("STRAIGHT", weights)

    # Check if all weights within 5% of each other — still straight
    if max(weights) / min(weights) <= 1.05:
        return ("STRAIGHT", weights)

    # Check monotonic patterns
    ascending = all(weights[i] <= weights[i+1] for i in range(len(weights)-1))
    descending = all(weights[i] >= weights[i+1] for i in range(len(weights)-1))

    if ascending and not descending:
        return ("ASCENDING", weights)
    if descending and not ascending:
        return ("REVERSE", weights)

    return ("MIXED", weights)


# ═══════════════════════════════════════════════════════════════
# PREDICTION HELPERS
# ═══════════════════════════════════════════════════════════════

def predict_reps_range(max_e1rm, target_weight, target_low, target_high,
                        position_from_fresh=0):
    """
    Predict a rep range at target_weight given the user's max e1RM.
    position_from_fresh: 0 = set 1 (fresh), 1 = set 2, etc.
    Applies Nuzzo decay: ~5% loss per set position at same weight.
    Returns (low, high) tuple within the target rep range.
    """
    if max_e1rm <= 0 or target_weight <= 0:
        return (target_low, target_high)

    base_reps = reps_at_weight(max_e1rm, target_weight)
    # Apply position decay (conservative — 5% per position)
    fatigue_mult = max(0.70, 1.0 - position_from_fresh * 0.05)
    adjusted = max(1, int(round(base_reps * fatigue_mult)))

    # Return a ±1 range centered on prediction
    low = max(target_low, adjusted - 1)
    high = min(target_high, adjusted + 1)

    # Sanity check: low <= high
    if low > high:
        low = high = max(target_low, min(target_high, adjusted))

    return (low, high)


# ═══════════════════════════════════════════════════════════════
# PROGRESSION ENGINE (NEW — PATTERN-AWARE)
# ═══════════════════════════════════════════════════════════════

def progression_engine_v2(last_session, target_low, target_high, n_sets, tier="T3"):
    """
    Returns a list of per-set prescriptions.
    Each prescription is a dict:
      {
        "weight": float,
        "reps_target": int or (int, int) for range,
        "role": "feeder" | "top" | "primary",
        "note": str (optional explanation)
      }
    """
    pattern, weights = detect_pattern(last_session)

    # Compute user's max e1RM across all logged sets
    max_e1rm = max((e1rm(s[0], s[1]) for s in last_session if s[1] <= 12),
                   default=0.0)
    if max_e1rm == 0 and last_session:
        # Fallback: use highest weight even if reps > 12
        max_e1rm = max(s[0] * (1 + min(s[1], 12) / 30.0) for s in last_session)

    ifi = compute_ifi(last_session)
    zone = ifi_zone(ifi)

    # ─── NO HISTORY ───
    if pattern == "NONE":
        return [
            {"weight": 0, "reps_target": target_high, "role": "primary", "note": "no history"}
            for _ in range(n_sets)
        ]

    # ─── STRAIGHT SETS — use existing logic ───
    if pattern == "STRAIGHT":
        return _straight_sets_prescription(last_session, target_low, target_high,
                                            n_sets, zone, max_e1rm, tier)

    # ─── ASCENDING PYRAMID ───
    if pattern == "ASCENDING":
        return _ascending_prescription(last_session, target_low, target_high,
                                        n_sets, zone, max_e1rm, tier)

    # ─── REVERSE PYRAMID ───
    if pattern == "REVERSE":
        return _reverse_prescription(last_session, target_low, target_high,
                                      n_sets, zone, max_e1rm, tier)

    # ─── MIXED — fallback to straight sets at top weight ───
    top_weight = max(weights)
    synthetic_last = [(top_weight, last_session[-1][1])] * len(last_session)
    return _straight_sets_prescription(synthetic_last, target_low, target_high,
                                        n_sets, zone, max_e1rm, tier)


def _straight_sets_prescription(last_session, tl, th, n_sets, zone, max_e1rm, tier):
    """Same weight all sets, front-loaded rep progression."""
    weight = last_session[0][0] if last_session else 0
    sorted_sets = sorted(enumerate(last_session), key=lambda x: x[0])

    # Front-loaded bump
    if zone == "FRESH":
        bump_top, bump_sec = 2, 1
    elif zone == "OPTIMAL":
        bump_top, bump_sec = 1, 1
    elif zone == "FATIGUED":
        bump_top, bump_sec = 0, 0
    else:  # OVERTRAINED
        bump_top, bump_sec = -1, -1  # reduce

    # Check if all sets hit top — if so, progress weight
    all_hit_top = all(s[1] >= th for _, s in sorted_sets)
    if all_hit_top:
        # Bump weight, drop reps to bottom
        inc = 5.0 if tier in ("T1", "T2") else 2.5
        new_weight = weight + inc
        predicted = predict_reps_range(max_e1rm, new_weight, tl, th)
        return [
            {"weight": new_weight, "reps_target": predicted, "role": "primary",
             "note": f"weight +{inc:.1f}, predicted {predicted[0]}-{predicted[1]}"}
            for _ in range(n_sets)
        ]

    # Hold weight, progress reps
    result = []
    for i in range(n_sets):
        if i < len(sorted_sets):
            last_reps = sorted_sets[i][1][1]
        else:
            last_reps = sorted_sets[-1][1][1] if sorted_sets else tl
        bump = bump_top if i == 0 else bump_sec
        target = max(tl, min(th, last_reps + bump))
        result.append({
            "weight": weight,
            "reps_target": target,
            "role": "primary",
            "note": f"last {last_reps} + {bump}" if bump >= 0 else f"last {last_reps} {bump}"
        })
    return result


def _ascending_prescription(last_session, tl, th, n_sets, zone, max_e1rm, tier):
    """
    Ascending pyramid: preserve feeder weights, progress top set only.
    Top set = heaviest weight in last session.
    """
    if not last_session:
        return []

    weights = [s[0] for s in last_session]
    top_weight = max(weights)
    top_idx = weights.index(top_weight)  # first occurrence of top weight

    result = []
    for i in range(n_sets):
        if i >= len(last_session):
            # Extra set beyond what user did — repeat last weight
            last_w = last_session[-1][0]
            last_r = last_session[-1][1]
            result.append({
                "weight": last_w,
                "reps_target": max(tl, min(th, last_r)),
                "role": "extra",
                "note": f"new set — match last"
            })
            continue

        last_w, last_r = last_session[i]
        is_top = i == top_idx

        if is_top:
            # Progress the top set
            if last_r >= th:
                # Hit top of range: bump weight, drop reps
                inc = 5.0 if tier in ("T1", "T2") else 2.5
                new_weight = last_w + inc
                predicted = predict_reps_range(max_e1rm, new_weight, tl, th)
                result.append({
                    "weight": new_weight,
                    "reps_target": predicted,
                    "role": "top",
                    "note": f"top set: weight +{inc:.1f}"
                })
            else:
                # Add reps at same weight
                bump = 1 if zone in ("FRESH", "OPTIMAL") else 0
                target = max(tl, min(th, last_r + bump))
                result.append({
                    "weight": last_w,
                    "reps_target": target,
                    "role": "top",
                    "note": f"top set: +{bump} rep"
                })
        else:
            # Feeder set — preserve weight, conservative rep target
            # If last rep count was unusually high (> target_high), show as range
            if last_r > th:
                # Unusual max-effort feeder — show range, don't force repeat
                low_target = th
                high_target = min(last_r, th + 5)
                result.append({
                    "weight": last_w,
                    "reps_target": (low_target, high_target),
                    "role": "feeder",
                    "note": f"feeder (was max-effort {last_r})"
                })
            else:
                # Normal feeder — match last week, +1 if FRESH
                bump = 1 if zone == "FRESH" else 0
                target = max(tl, min(th, last_r + bump))
                result.append({
                    "weight": last_w,
                    "reps_target": target,
                    "role": "feeder",
                    "note": "feeder — hold weight"
                })
    return result


def _reverse_prescription(last_session, tl, th, n_sets, zone, max_e1rm, tier):
    """
    Reverse pyramid: set 1 is heaviest, weight drops across sets.
    Progress set 1 first (it's the top set).
    """
    if not last_session:
        return []

    result = []
    for i in range(n_sets):
        if i >= len(last_session):
            last_w = last_session[-1][0]
            last_r = last_session[-1][1]
            result.append({
                "weight": last_w,
                "reps_target": max(tl, min(th, last_r)),
                "role": "extra",
                "note": "new set — match last"
            })
            continue

        last_w, last_r = last_session[i]
        is_top = i == 0  # set 1 is heaviest in RPT

        if is_top:
            if last_r >= th:
                inc = 5.0 if tier in ("T1", "T2") else 2.5
                new_weight = last_w + inc
                predicted = predict_reps_range(max_e1rm, new_weight, tl, th)
                result.append({
                    "weight": new_weight,
                    "reps_target": predicted,
                    "role": "top",
                    "note": f"top set: weight +{inc:.1f}"
                })
            else:
                bump = 1 if zone in ("FRESH", "OPTIMAL") else 0
                target = max(tl, min(th, last_r + bump))
                result.append({
                    "weight": last_w,
                    "reps_target": target,
                    "role": "top",
                    "note": f"top set: +{bump} rep"
                })
        else:
            # Back-off set — preserve weight, allow small rep progression
            bump = 1 if zone in ("FRESH", "OPTIMAL") else 0
            target = max(tl, min(th, last_r + bump))
            result.append({
                "weight": last_w,
                "reps_target": target,
                "role": "backoff",
                "note": f"back-off — +{bump} rep"
            })
    return result


# ═══════════════════════════════════════════════════════════════
# TEST SCENARIOS
# ═══════════════════════════════════════════════════════════════

SCENARIOS = [
    {
        "name": "1. USER BUG: Tricep pushdown 150×12, 150×20, 170×12",
        "last_session": [(150, 12), (150, 20), (170, 12)],
        "target_low": 10, "target_high": 15,
        "n_sets": 3, "tier": "T3",
        "expected_pattern": "ASCENDING",
        "validation": {
            "set0_weight": 150,  # feeder preserved
            "set1_weight": 150,  # feeder preserved
            "set2_weight": 170,  # top set
            "set2_weight_max": 175,  # or bump weight
            "notes": "Set 1 feeder at 150, set 2 feeder at 150, set 3 is top set at 170+",
        },
    },
    {
        "name": "2. Straight sets: 185×8/8/8 (6-10 range)",
        "last_session": [(185, 8), (185, 8), (185, 8)],
        "target_low": 6, "target_high": 10,
        "n_sets": 3, "tier": "T2",
        "expected_pattern": "STRAIGHT",
        "validation": {
            "all_same_weight": 185,
            "front_loaded": True,
            "notes": "All at 185, front-loaded rep progression",
        },
    },
    {
        "name": "3. Ascending 3-step: 95×12, 115×10, 135×8",
        "last_session": [(95, 12), (115, 10), (135, 8)],
        "target_low": 6, "target_high": 12,
        "n_sets": 3, "tier": "T2",
        "expected_pattern": "ASCENDING",
        "validation": {
            "set0_weight": 95,
            "set1_weight": 115,
            "set2_weight_min": 135,
            "notes": "Preserve all 3 weights, progress top set",
        },
    },
    {
        "name": "4. Reverse pyramid: 225×5, 205×7, 185×9",
        "last_session": [(225, 5), (205, 7), (185, 9)],
        "target_low": 5, "target_high": 10,
        "n_sets": 3, "tier": "T1",
        "expected_pattern": "REVERSE",
        "validation": {
            "set0_weight_min": 225,  # top set (heaviest first)
            "set1_weight": 205,
            "set2_weight": 185,
            "notes": "Preserve descending, progress set 1 first",
        },
    },
    {
        "name": "5. Single set logged: 135×6",
        "last_session": [(135, 6)],
        "target_low": 5, "target_high": 8,
        "n_sets": 3, "tier": "T3",
        "expected_pattern": "STRAIGHT",
        "validation": {
            "all_same_weight": 135,
            "notes": "1 set logged, 3 sets requested — extend as straight sets",
        },
    },
    {
        "name": "6. Mixed unclear: 145×10, 165×8, 155×9",
        "last_session": [(145, 10), (165, 8), (155, 9)],
        "target_low": 8, "target_high": 12,
        "n_sets": 3, "tier": "T2",
        "expected_pattern": "MIXED",
        "validation": {
            "all_same_weight": 165,  # fallback to top weight
            "notes": "Unclear pattern → fallback to straight sets at 165",
        },
    },
    {
        "name": "7. Big ascending jumps: 115×12, 150×12, 185×12",
        "last_session": [(115, 12), (150, 12), (185, 12)],
        "target_low": 8, "target_high": 12,
        "n_sets": 3, "tier": "T2",
        "expected_pattern": "ASCENDING",
        "validation": {
            "set0_weight": 115,
            "set1_weight": 150,
            "set2_weight_min": 185,
            "set2_all_hit_top": True,  # should bump weight since hit top
            "notes": "Hit top of range on all sets — weight bump on top set",
        },
    },
    {
        "name": "8. Top set max rep anomaly: 150×12, 150×20 (user went hard on set 2)",
        "last_session": [(150, 12), (150, 20)],
        "target_low": 10, "target_high": 15,
        "n_sets": 3, "tier": "T3",
        "expected_pattern": "STRAIGHT",  # both at 150
        "validation": {
            "all_same_weight": 150,
            "notes": "Both at 150, set 2 was anomaly. Should not chase 20 reps",
        },
    },
]


# ═══════════════════════════════════════════════════════════════
# TEST RUNNER
# ═══════════════════════════════════════════════════════════════

def format_prescription(pres):
    """Format a single set prescription for display."""
    w = pres["weight"]
    r = pres["reps_target"]
    if isinstance(r, tuple):
        rep_str = f"{r[0]}-{r[1]}"
    else:
        rep_str = str(r)
    role_badge = {
        "top": "[TOP]",
        "feeder": "[fdr]",
        "backoff": "[bo]",
        "primary": "[primary]",
        "extra": "[extra]",
    }.get(pres["role"], "")
    return f"{w:.0f}×{rep_str} {role_badge}"


def run_scenario(s):
    name = s["name"]
    last = s["last_session"]
    tl, th = s["target_low"], s["target_high"]
    n = s["n_sets"]
    tier = s["tier"]
    expected_pattern = s["expected_pattern"]
    validation = s["validation"]

    pattern, weights = detect_pattern(last)
    prescription = progression_engine_v2(last, tl, th, n, tier)

    print(f"\n  {name}")
    print(f"  ──────────────────────────────────────────────────────")
    last_str = " / ".join(f"{w:.0f}×{r}" for w, r in last) if last else "(none)"
    print(f"  Last session: {last_str}")
    print(f"  Range: {tl}-{th}, sets: {n}, tier: {tier}")
    print(f"  Detected pattern: {pattern}  (expected: {expected_pattern})")
    pattern_ok = pattern == expected_pattern

    print(f"  Prescription:")
    for i, pres in enumerate(prescription):
        fmt = format_prescription(pres)
        note = pres.get("note", "")
        print(f"    Set {i+1}: {fmt:<18s}  {note}")

    # Validation checks
    checks = []

    if pattern_ok:
        checks.append(("Pattern detection", True, ""))
    else:
        checks.append(("Pattern detection", False, f"got {pattern}, expected {expected_pattern}"))

    if "all_same_weight" in validation:
        expected_w = validation["all_same_weight"]
        all_match = all(abs(p["weight"] - expected_w) <= 0.1 for p in prescription)
        checks.append((f"All sets at {expected_w}", all_match,
                       f"got {[p['weight'] for p in prescription]}"))

    if "set0_weight" in validation:
        got = prescription[0]["weight"]
        expected = validation["set0_weight"]
        ok = abs(got - expected) <= 0.1
        checks.append((f"Set 0 weight = {expected}", ok, f"got {got}"))

    if "set1_weight" in validation:
        got = prescription[1]["weight"]
        expected = validation["set1_weight"]
        ok = abs(got - expected) <= 0.1
        checks.append((f"Set 1 weight = {expected}", ok, f"got {got}"))

    if "set2_weight" in validation:
        got = prescription[2]["weight"]
        expected = validation["set2_weight"]
        ok = abs(got - expected) <= 0.1
        checks.append((f"Set 2 weight = {expected}", ok, f"got {got}"))

    if "set2_weight_min" in validation:
        got = prescription[2]["weight"]
        expected = validation["set2_weight_min"]
        ok = got >= expected
        checks.append((f"Set 2 weight ≥ {expected}", ok, f"got {got}"))

    if "set0_weight_min" in validation:
        got = prescription[0]["weight"]
        expected = validation["set0_weight_min"]
        ok = got >= expected
        checks.append((f"Set 0 weight ≥ {expected}", ok, f"got {got}"))

    if "set2_weight_max" in validation:
        got = prescription[2]["weight"]
        expected = validation["set2_weight_max"]
        ok = got <= expected
        checks.append((f"Set 2 weight ≤ {expected}", ok, f"got {got}"))

    if "set2_all_hit_top" in validation:
        # Check that top set had a weight bump (not just rep bump)
        top_weight_changed = prescription[2]["weight"] > last[2][0]
        checks.append(("Top set weight bumped", top_weight_changed,
                       f"last {last[2][0]} → new {prescription[2]['weight']}"))

    print(f"  Checks:")
    for check_name, ok, detail in checks:
        symbol = "✓" if ok else "✗"
        detail_str = f"  ({detail})" if detail and not ok else ""
        print(f"    {symbol} {check_name}{detail_str}")

    all_pass = all(c[1] for c in checks)
    return all_pass, name


# ═══════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════

if __name__ == "__main__":
    print("=" * 72)
    print("  PER-SET WEIGHT-AWARE PROGRESSION — VALIDATION TEST")
    print("  Preserving user's weight pattern (straight, pyramid, reverse, mixed)")
    print("=" * 72)

    results = []
    for s in SCENARIOS:
        passed, name = run_scenario(s)
        results.append((passed, name))

    print(f"\n{'=' * 72}")
    print(f"  SUMMARY")
    print(f"{'=' * 72}")
    for passed, name in results:
        symbol = "✓" if passed else "✗"
        print(f"  {symbol} {name}")

    total = len(results)
    passed_count = sum(1 for p, _ in results if p)
    print(f"\n  {passed_count}/{total} scenarios passed")

    if passed_count == total:
        print("  ✓ ALL TESTS PASS — Ready to port to Swift")
    else:
        print(f"  ✗ {total - passed_count} tests failing — fix before implementing")
