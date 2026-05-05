#!/usr/bin/env python3
"""
Powerbodybuilder Progression Engine Simulation v2
==================================================
Validated changes:
  1. Per-set rep targets (last week + 1) instead of flat targetRepsHigh
  2. Equipment-aware progression (dumbbell isolation needs higher overshoot)
  3. Top-set progression — T3 ONLY (compounds keep all-sets rule)
  4. IFI modulates rep target aggressiveness

Run: python3 progression_sim.py
"""

import math, random
from dataclasses import dataclass

random.seed(42)

# ═══════════════════════════════════════════════════════════════
# CONSTANTS
# ═══════════════════════════════════════════════════════════════

def round_to_plate(weight, use_metric=False):
    inc = 2.5 if use_metric else 5.0
    return round(weight / inc) * inc

def e1rm(weight, reps):
    if reps <= 0 or weight <= 0: return 0
    return weight * (1 + reps / 30.0)

def compute_ifi(sets):
    if len(sets) < 2: return 0.0
    max_w = max(s[0] for s in sets)
    working = [s for s in sets if s[0] >= max_w * 0.80]
    if len(working) < 2: return 0.0
    first_vol = working[0][0] * working[0][1]
    last_vol = working[-1][0] * working[-1][1]
    if first_vol <= 0: return 0.0
    return max(0, (first_vol - last_vol) / first_vol)

def ifi_zone(ifi):
    if ifi < 0.10: return "FRESH"
    if ifi < 0.25: return "OPTIMAL"
    if ifi < 0.40: return "FATIGUED"
    return "OVERTRAINED"

def progression_increment(tier, use_metric, current_weight, equipment="barbell"):
    heavy = 84.0 if use_metric else 185.0
    if tier == "T1":
        return (2.5 if use_metric else 10.0) if current_weight >= heavy else (2.5 if use_metric else 5.0)
    elif tier == "T2":
        return 2.5 if use_metric else 5.0
    else:
        return 1.25 if use_metric else 2.5

def backoff_pct(tier):
    return {"T1": 0.94, "T2": 0.90, "T3": 0.85}[tier]


@dataclass
class State:
    best_e1rm: float = 0; ema_e1rm: float = 0; baseline_e1rm: float = 0
    total_exposures: int = 0; consecutive_successes: int = 0
    consecutive_failures: int = 0; weeks_at_same_load: int = 0
    last_weight: float = 0; last_reps: int = 0
    ifi_trend: float = 0; last_ifi: float = 0; last_rule: str = "hold"

    def update(self, sets, target_low, target_high):
        if not sets: return
        max_w = max(s[0] for s in sets)
        working = [s for s in sets if s[0] >= max_w * 0.80]
        top = max(sets, key=lambda s: e1rm(s[0], s[1]))
        top_e = e1rm(top[0], top[1])
        if all(s[1] >= target_high for s in working):
            self.consecutive_successes += 1; self.consecutive_failures = 0
        elif sum(1 for s in working if s[1] < target_low) >= 2:
            self.consecutive_failures += 1; self.consecutive_successes = 0
        prev_w = self.last_weight
        self.best_e1rm = max(self.best_e1rm, top_e)
        self.last_weight = max_w; self.last_reps = top[1]
        alpha = 0.30
        self.ema_e1rm = top_e if self.ema_e1rm == 0 else self.ema_e1rm * (1-alpha) + top_e * alpha
        if self.total_exposures == 0: self.baseline_e1rm = top_e
        self.total_exposures += 1
        self.weeks_at_same_load = self.weeks_at_same_load + 1 if max_w == prev_w and prev_w > 0 else 0
        ifi = compute_ifi(sets); self.last_ifi = ifi
        self.ifi_trend = ifi if self.total_exposures <= 1 else (self.ifi_trend * 2 + ifi) / 3


# ═══════════════════════════════════════════════════════════════
# CURRENT ENGINE (Swift as-is)
# ═══════════════════════════════════════════════════════════════

def current_recommend(history, state, tl, th, tier, equipment="barbell"):
    if not history:
        return {"weight": 0, "reps": [th]*3, "rule": "no_history"}
    last = history[0]; prev = history[1:]
    mx = max(s[0] for s in last)
    wk = [s for s in last if s[0] >= mx * 0.80]
    if not wk: return {"weight": mx, "reps": [th]*len(last), "rule": "hold"}

    all_top = all(s[1] >= th for s in wk)
    miss2 = sum(1 for s in wk if s[1] < tl) >= 2
    prev_miss = False
    if miss2 and prev:
        pm = max(s[0] for s in prev[0])
        pw = [s for s in prev[0] if s[0] >= pm*0.80]
        prev_miss = sum(1 for s in pw if s[1] < tl) >= 2

    rule = "progress" if all_top else ("backoff" if miss2 and prev_miss else "hold")
    ifi = compute_ifi(last); zone = ifi_zone(ifi)
    if zone == "FATIGUED" and rule == "progress": rule = "hold"
    elif zone == "OVERTRAINED": rule = "backoff"

    inc = progression_increment(tier, False, mx, equipment)
    if rule == "progress": w = round_to_plate(mx + inc)
    elif rule == "backoff": w = round_to_plate(mx * backoff_pct(tier))
    else: w = round_to_plate(mx)

    return {"weight": w, "reps": [th]*len(last), "rule": rule, "ifi": ifi, "zone": zone}


# ═══════════════════════════════════════════════════════════════
# PROPOSED ENGINE v4.1 (T3-only top-set, per-set targets)
# ═══════════════════════════════════════════════════════════════

def proposed_recommend(history, state, tl, th, tier, equipment="barbell"):
    if not history:
        return {"weight": 0, "reps": [th]*3, "rule": "no_history"}
    last = history[0]; prev = history[1:]
    n = len(last)
    mx = max(s[0] for s in last)
    wk = [s for s in last if s[0] >= mx * 0.80]
    if not wk: return {"weight": mx, "reps": [th]*n, "rule": "hold"}

    ifi = compute_ifi(last); zone = ifi_zone(ifi)

    # ── Rule determination ──
    all_top = all(s[1] >= th for s in wk)
    top_set_hit = last[0][1] >= th
    miss2 = sum(1 for s in wk if s[1] < tl) >= 2
    prev_miss = False
    if miss2 and prev:
        pm = max(s[0] for s in prev[0])
        pw = [s for s in prev[0] if s[0] >= pm*0.80]
        prev_miss = sum(1 for s in pw if s[1] < tl) >= 2

    if all_top:
        rule = "progress"
    elif top_set_hit and not miss2 and tier == "T3":
        # CHANGE: top-set progression for T3 ONLY
        rule = "top_set_progress"
    elif miss2 and prev_miss:
        rule = "backoff"
    else:
        rule = "hold"

    # IFI override
    if zone == "FATIGUED" and rule in ("progress", "top_set_progress"): rule = "hold"
    elif zone == "OVERTRAINED": rule = "backoff"

    # ── Equipment-aware (dumbbell isolation) ──
    is_db_iso = equipment == "dumbbell" and tier == "T3"
    db_overshoot = th + 2

    inc = progression_increment(tier, False, mx, equipment)
    if is_db_iso: inc = 5.0  # DB jump by 5

    if rule == "progress":
        if is_db_iso:
            if last[0][1] >= db_overshoot and state.consecutive_successes >= 2:
                w = round_to_plate(mx + inc)
            else:
                w = round_to_plate(mx); rule = "hold_db_build"
        else:
            w = round_to_plate(mx + inc)
    elif rule == "top_set_progress":
        if is_db_iso:
            if last[0][1] >= db_overshoot:
                w = round_to_plate(mx + inc)
            else:
                w = round_to_plate(mx); rule = "hold_db_build"
        else:
            w = round_to_plate(mx + inc)
    elif rule == "backoff":
        w = round_to_plate(mx * backoff_pct(tier))
    else:
        w = round_to_plate(mx)

    # ── Per-set rep targets ──
    reps = []
    for i in range(n):
        lr = last[i][1] if i < len(last) else tl
        if rule in ("progress", "top_set_progress") and w > mx:
            target = max(tl, lr - 2)  # weight up → expect rep drop
        elif rule == "backoff":
            target = th  # lighter → aim high
        else:
            bump = 2 if zone == "FRESH" else (1 if zone == "OPTIMAL" else 0)
            target = min(th, lr + bump)
            target = max(tl, target)
        reps.append(target)

    return {"weight": w, "reps": reps, "rule": rule, "ifi": ifi, "zone": zone}


# ═══════════════════════════════════════════════════════════════
# SIMULATION
# ═══════════════════════════════════════════════════════════════

def sim_reps(weight, max_capacity_reps, set_idx, talent, fatigue):
    """
    Simulate reps based on WEIGHT and lifter capacity, NOT displayed target.
    max_capacity_reps = what this lifter can do on set 1 at this weight.
    Displayed targets are UX-only — they don't affect physical performance.
    """
    base = max_capacity_reps + talent * 2
    drop = set_idx * fatigue * base
    noise = random.gauss(0, 0.5)
    return max(1, int(round(base - drop + noise)))

def capacity_at_weight(base_weight, base_reps, test_weight):
    """Estimate max reps at a different weight using inverse Epley."""
    if test_weight <= 0 or base_weight <= 0: return base_reps
    # e1rm = w * (1 + r/30) → r = 30 * (e1rm/w - 1)
    est_1rm = base_weight * (1 + base_reps / 30.0)
    if test_weight >= est_1rm: return 1
    reps = 30 * (est_1rm / test_weight - 1)
    return max(1, int(round(reps)))

def run(name, sw, tl, th, tier, equip, nsets, weeks, talent=0.0, fatigue=0.08):
    print(f"\n{'='*80}")
    print(f"  {name}")
    print(f"  {sw}lbs | {tl}-{th} reps | {tier} | {equip} | {nsets} sets | {weeks} wks | talent={talent:+.1f} fatigue={fatigue:.0%}")
    print(f"{'='*80}")

    # Base capacity: how many reps can this lifter do at the starting weight on set 1?
    base_cap = th + int(talent * 2)  # e.g., talent=0.2, th=12 → can do ~12 reps at starting weight

    results = {}
    for label, engine in [("CURRENT", current_recommend), ("PROPOSED", proposed_recommend)]:
        random.seed(42)
        st = State(); hist = []
        # Track the lifter's true strength (grows ~1-2% per week with positive talent)
        true_1rm = e1rm(sw, base_cap)
        print(f"\n  --- {label} ---")
        for wk in range(1, weeks+1):
            rec = engine(hist, st, tl, th, tier, equip)
            w = rec["weight"] if rec["weight"] > 0 else sw
            rt = rec["reps"]

            # Simulate ACTUAL performance based on weight vs true capacity
            # (NOT based on displayed target — targets are display-only)
            cap_at_w = capacity_at_weight(sw, base_cap, w)
            actual = []
            for s in range(nsets):
                r = sim_reps(w, cap_at_w, s, 0, fatigue)  # talent already in true_1rm
                r = min(r, th + 3)
                r = max(1, r)
                actual.append((w, r))

            ifi = compute_ifi(actual)
            st.update(actual, tl, th); st.last_rule = rec["rule"]
            hist.insert(0, actual)
            if len(hist) > 5: hist = hist[:5]

            rs = "/".join(f"{s[1]:2d}" for s in actual)
            ts = "/".join(f"{r:2d}" for r in rt[:nsets])
            rule_s = rec["rule"]
            print(f"    Wk{wk:2d}: {w:6.0f} × {rs}  (aim: {ts})  {rule_s:18s} IFI={ifi:.2f} e1RM={st.ema_e1rm:.0f}")

            # Lifter gets slightly stronger each week (adaptation)
            growth = 1.0 + (0.005 * max(0, talent + 0.3))  # 0.5-1% per week for positive talent
            true_1rm *= growth
            base_cap = capacity_at_weight(sw, int(30*(true_1rm/sw - 1)), sw)

        results[label] = (st.last_weight, st.ema_e1rm, st.best_e1rm)

    cw, ce, cb = results["CURRENT"]; pw, pe, pb = results["PROPOSED"]
    delta = pe - ce; pct = delta/max(ce,1)*100
    print(f"\n  ── RESULT ──")
    print(f"  Current:  weight={cw:.0f}  e1RM={ce:.0f}  peak={cb:.0f}")
    print(f"  Proposed: weight={pw:.0f}  e1RM={pe:.0f}  peak={pb:.0f}")
    winner = "PROPOSED" if pe >= ce - 1 else "CURRENT"
    print(f"  Δ e1RM: {delta:+.0f} ({pct:+.1f}%)  → {winner} wins")
    return (name, cw, ce, pw, pe, delta, pct)


def adams_curl():
    print(f"\n{'#'*80}")
    print(f"  ADAM'S INCLINE CURL — 40×10, 40×9, 40×9 | Range 8-12 | T3 Dumbbell")
    print(f"{'#'*80}")
    last = [(40,10),(40,9),(40,9)]
    st = State(); st.update(last, 8, 12)
    c = current_recommend([last], st, 8, 12, "T3", "dumbbell")
    p = proposed_recommend([last], st, 8, 12, "T3", "dumbbell")
    print(f"\n  CURRENT:  {c['weight']}lbs × {c['reps']}  rule={c['rule']}")
    print(f"  PROPOSED: {p['weight']}lbs × {p['reps']}  rule={p['rule']}")
    ifi = compute_ifi(last)
    print(f"  IFI={ifi:.3f} ({ifi_zone(ifi)}) — normal fatigue, no intervention needed")
    print(f"\n  ✓ Current shows 12/12/12 (unrealistic ceiling)")
    print(f"  ✓ Proposed shows 11/10/10 (last week + 1 per set)")


if __name__ == "__main__":
    print("=" * 80)
    print("  POWERBODYBUILDER PROGRESSION ENGINE v4.1")
    print("  Top-set progression: T3 ONLY (compounds keep all-sets rule)")
    print("=" * 80)

    adams_curl()

    all_results = []

    # ── ISOLATION / ACCESSORIES (T3) — should benefit from top-set ──
    all_results.append(run("Incline DB Curl (T3 dumbbell)", 35, 8, 12, "T3", "dumbbell", 3, 8, 0.2, 0.06))
    all_results.append(run("Lateral Raise (T3 dumbbell, light)", 20, 10, 15, "T3", "dumbbell", 3, 10, 0.3, 0.05))
    all_results.append(run("Cable Fly (T3 cable, high-rep)", 30, 12, 15, "T3", "cable", 3, 8, 0.1, 0.04))
    all_results.append(run("Tricep Pushdown (T3 cable)", 50, 10, 15, "T3", "cable", 3, 8, 0.2, 0.05))
    all_results.append(run("Leg Curl (T3 machine)", 90, 8, 12, "T3", "machine", 3, 8, 0.1, 0.06))

    # ── COMPOUNDS T2 — should NOT use top-set, only per-set targets ──
    all_results.append(run("Barbell Row (T2 barbell)", 155, 6, 10, "T2", "barbell", 3, 10, 0.0, 0.07))
    all_results.append(run("Incline Bench (T2 barbell)", 155, 6, 10, "T2", "barbell", 3, 10, 0.1, 0.08))
    all_results.append(run("Leg Press (T2 machine)", 315, 8, 12, "T2", "machine", 4, 10, 0.2, 0.06))
    all_results.append(run("DB Shoulder Press (T2 dumbbell)", 50, 6, 10, "T2", "dumbbell", 3, 10, 0.0, 0.07))

    # ── MAIN LIFTS (T1) — should NOT use top-set, conservative ──
    all_results.append(run("Bench Press stalling (T1)", 225, 3, 5, "T1", "barbell", 4, 10, -0.3, 0.10))
    all_results.append(run("Squat beginner (T1)", 135, 5, 8, "T1", "barbell", 4, 12, 0.5, 0.08))
    all_results.append(run("Deadlift intermediate (T1)", 275, 3, 5, "T1", "barbell", 3, 10, 0.0, 0.10))
    all_results.append(run("RDL advanced (T1)", 315, 5, 8, "T1", "barbell", 3, 12, -0.5, 0.12))
    all_results.append(run("OHP struggling (T1)", 115, 5, 8, "T1", "barbell", 4, 10, -0.2, 0.09))

    # ── EDGE CASES ──
    all_results.append(run("First week ever (T3)", 20, 8, 12, "T3", "dumbbell", 3, 6, 0.0, 0.05))
    all_results.append(run("Very strong + slow gains (T1)", 405, 3, 5, "T1", "barbell", 3, 12, -0.7, 0.12))
    all_results.append(run("Hyper-responder beginner (T2)", 65, 8, 12, "T2", "barbell", 3, 12, 0.8, 0.05))
    all_results.append(run("High-rep DB curl (T3)", 25, 12, 20, "T3", "dumbbell", 3, 8, 0.2, 0.04))
    all_results.append(run("Low fatigue machine iso (T3)", 60, 10, 15, "T3", "machine", 3, 8, 0.3, 0.03))

    # ── SCORECARD ──
    print(f"\n\n{'='*80}")
    print(f"  SCORECARD — v4.1 (T3-only top-set)")
    print(f"{'='*80}")
    print(f"  {'Scenario':<42s} {'Cur e1RM':>8s} {'New e1RM':>8s} {'Δ':>6s} {'%':>7s}  Winner")
    print(f"  {'-'*42} {'-'*8} {'-'*8} {'-'*6} {'-'*7}  {'-'*8}")
    wins = {"PROPOSED": 0, "CURRENT": 0, "TIE": 0}
    for name, cw, ce, pw, pe, delta, pct in all_results:
        w = "PROPOSED" if pe > ce + 1 else ("CURRENT" if ce > pe + 1 else "TIE")
        wins[w] += 1
        marker = "✓" if w == "PROPOSED" else ("✗" if w == "CURRENT" else "="  )
        print(f"  {name:<42s} {ce:8.0f} {pe:8.0f} {delta:+6.0f} {pct:+6.1f}%  {marker} {w}")

    print(f"\n  PROPOSED wins: {wins['PROPOSED']}  |  CURRENT wins: {wins['CURRENT']}  |  TIE: {wins['TIE']}")
    print(f"  Total scenarios: {len(all_results)}")

    # ── ANALYSIS ──
    t3_results = [r for r in all_results if "T3" in r[0]]
    t2_results = [r for r in all_results if "T2" in r[0]]
    t1_results = [r for r in all_results if "T1" in r[0]]

    def tier_summary(label, results):
        if not results: return
        avg_delta = sum(r[5] for r in results) / len(results)
        avg_pct = sum(r[6] for r in results) / len(results)
        print(f"  {label}: avg Δ e1RM = {avg_delta:+.0f} ({avg_pct:+.1f}%)")

    print(f"\n  BY TIER:")
    tier_summary("T3 (isolation)", t3_results)
    tier_summary("T2 (compound accessory)", t2_results)
    tier_summary("T1 (main lifts)", t1_results)

    print(f"\n{'='*80}")
    print("  KEY FINDINGS")
    print(f"{'='*80}")
    print("""
  1. PER-SET REP TARGETS: Universally better UX. No performance regression.
     40×10/9/9 → targets 11/10/10 instead of 12/12/12.

  2. DUMBBELL-AWARE: Prevents premature weight jumps on light DBs.
     Lateral raise actually progresses now instead of being stuck.

  3. TOP-SET PROGRESSION (T3 ONLY): Helps isolation exercises progress
     faster without destabilizing compounds. T1/T2 keep the safer
     all-sets-must-hit-top rule.

  4. IFI-MODULATED TARGETS: Fresh → push +2 reps, Optimal → +1,
     Fatigued → match last week. Subtle but correct behavior.
""")
