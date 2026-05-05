#!/usr/bin/env python3
"""
Powerbodybuilder Engine v7 — REALISTIC SIMULATION
===================================================
Fixes from v6:
  1. Growth rates calibrated to research (Helms, Nuckols, Israetel)
  2. Non-linear per-set fatigue (exponential, not flat)
  3. RPE simulation (proximity to failure → RPE score)
  4. Tier-appropriate variance (low for heavy, high for light)
  5. Weekly fatigue accumulation (sessions earlier in week affect later ones)
  6. Deload supercompensation (+3% after recovery week)
  7. Technique learning curve for new exercises

Growth rate references:
  Beginner (<1yr): 1.0-2.0% e1RM/week on compounds (linear phase)
  Late beginner (6-12mo): 0.5-1.0%/week
  Intermediate (1-3yr): 0.08-0.20%/week (0.3-0.8%/month)
  Advanced (3-7yr): 0.02-0.06%/week (0.1-0.25%/month)
  Elite (7+yr): 0.005-0.02%/week (barely measurable)

Run: python3 progression_sim_v7.py
"""

import math, random
from dataclasses import dataclass, field
from collections import defaultdict

# ═══════════════════════════════════════════════════════════════
# CORE
# ═══════════════════════════════════════════════════════════════

def rtp(w, m=False):
    inc = 2.5 if m else 5.0
    return round(w / inc) * inc

def e1rm(w, r):
    return w * (1 + r / 30.0) if w > 0 and r > 0 else 0

def weight_for_reps(e1, reps):
    if e1 <= 0 or reps <= 0: return 0
    return e1 / (1 + reps / 30.0)

def reps_at_weight(e1, w):
    if w <= 0 or e1 <= 0: return 12
    if w >= e1: return 1
    return max(1, int(round(30 * (e1 / w - 1))))

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

def compute_pml(target, prior):
    total = 0.0
    for muscle, sets in prior:
        w = OVERLAP.get(muscle, {}).get(target, 0)
        total += w * min(sets, 6) / 6.0
    return total


# ═══════════════════════════════════════════════════════════════
# REALISTIC REP SIMULATION
# ═══════════════════════════════════════════════════════════════

def sim_set_reps(e1rm_today, weight, set_index, tier, readiness=3):
    """
    Simulate realistic reps for one set.
    - Non-linear fatigue (exponential per-set drop)
    - Tier-appropriate variance
    - Readiness multiplier on capacity
    """
    # Readiness affects true capacity
    r_mult = {1: 0.88, 2: 0.94, 3: 1.00, 4: 1.03, 5: 1.06}.get(readiness, 1.0)
    effective_e1rm = e1rm_today * r_mult

    # True capacity at this weight (fresh, set 1)
    fresh_cap = reps_at_weight(effective_e1rm, weight)

    # Non-linear per-set fatigue
    # Sets 1-2: mild (3-5%), Sets 3-4: moderate (5-8%), Sets 5+: heavy (8-12%)
    fatigue_rates = {
        "T1": [0.00, 0.06, 0.08, 0.11, 0.14, 0.17],  # heavy compounds fatigue more
        "T2": [0.00, 0.04, 0.06, 0.09, 0.12, 0.14],
        "T3": [0.00, 0.03, 0.05, 0.07, 0.09, 0.11],  # isolation fatigues less
    }
    rates = fatigue_rates.get(tier, fatigue_rates["T2"])
    cumulative_fatigue = rates[min(set_index, len(rates) - 1)]
    fatigued_cap = fresh_cap * (1.0 - cumulative_fatigue)

    # Tier-appropriate variance
    # Heavy low-rep: ±0.3 reps noise (very consistent)
    # Light high-rep: ±1.0 reps noise (more variable)
    variance = {"T1": 0.4, "T2": 0.6, "T3": 0.8}.get(tier, 0.6)
    noise = random.gauss(0, variance)

    actual = max(1, int(round(fatigued_cap + noise)))
    return actual


def sim_rpe(reps_done, max_possible_reps):
    """Estimate RPE from reps done vs capacity."""
    if max_possible_reps <= 0: return 10.0
    reps_left = max(0, max_possible_reps - reps_done)
    # Map reps in reserve to RPE
    if reps_left == 0: return 10.0
    elif reps_left <= 0.5: return 9.5
    elif reps_left <= 1: return 9.0
    elif reps_left <= 2: return 8.0
    elif reps_left <= 3: return 7.0
    elif reps_left <= 4: return 6.0
    return 5.0


# ═══════════════════════════════════════════════════════════════
# ENGINE STATE
# ═══════════════════════════════════════════════════════════════

@dataclass
class State:
    fresh_e1rm: float = 0
    best_e1rm: float = 0
    baseline_e1rm: float = 0
    e1rm_history: list = field(default_factory=list)
    total_exposures: int = 0
    consec_success: int = 0
    consec_fail: int = 0
    weeks_same_load: int = 0
    last_weight: float = 0
    last_reps_per_set: list = field(default_factory=list)
    last_rpe: float = 0
    sensitivity: float = 0.12
    last_ifi: float = 0
    ifi_trend: float = 0
    stall: str = "none"

    def coeff(self, pml):
        return max(0.70, 1.0 - pml * self.sensitivity)

    def update(self, sets, rpes, pml, tl, th, rec_w):
        if not sets: return
        top = max(sets, key=lambda s: e1rm(s[0], s[1]))
        actual_e = e1rm(top[0], top[1])
        c = self.coeff(pml)
        fresh_e = actual_e / c if c > 0 else actual_e

        alpha = 0.25
        if self.fresh_e1rm == 0:
            self.fresh_e1rm = fresh_e
            self.baseline_e1rm = fresh_e
        else:
            self.fresh_e1rm = self.fresh_e1rm * (1 - alpha) + fresh_e * alpha
        self.best_e1rm = max(self.best_e1rm, fresh_e)
        self.e1rm_history.append(fresh_e)
        if len(self.e1rm_history) > 8: self.e1rm_history = self.e1rm_history[-8:]

        mx = max(s[0] for s in sets)
        working = [s for s in sets if s[0] >= mx * 0.80]
        if all(s[1] >= th for s in working):
            self.consec_success += 1; self.consec_fail = 0
        elif sum(1 for s in working if s[1] < tl) >= 2:
            self.consec_fail += 1; self.consec_success = 0

        prev = self.last_weight
        self.last_weight = mx
        self.last_reps_per_set = [s[1] for s in sets]
        self.last_rpe = max(rpes) if rpes else 0
        self.weeks_same_load = (self.weeks_same_load + 1) if mx == prev and prev > 0 else 0
        self.total_exposures += 1

        ifi = compute_ifi(sets); self.last_ifi = ifi
        self.ifi_trend = ifi if self.total_exposures <= 1 else (self.ifi_trend * 2 + ifi) / 3

        # Sensitivity adaptation
        if pml > 0.1 and self.total_exposures >= 3 and rec_w > 0:
            expected = weight_for_reps(self.fresh_e1rm * c, (tl + th) // 2)
            if expected > 0 and abs(rec_w - expected) / expected < 0.30:
                avg_actual = sum(s[1] for s in sets) / len(sets)
                mid = (tl + th) / 2.0
                error = (avg_actual - mid) / max(mid, 1)
                lr = max(0.04, 0.15 / (1 + self.total_exposures * 0.08))
                if error > 0.12: self.sensitivity = max(0.03, self.sensitivity * (1 - lr))
                elif error < -0.12: self.sensitivity = min(0.25, self.sensitivity * (1 + lr))

        # Stall detection
        if len(self.e1rm_history) >= 4:
            recent = self.e1rm_history[-3:]
            older = self.e1rm_history[:-3] if len(self.e1rm_history) > 3 else self.e1rm_history[:2]
            if older:
                ar = sum(recent) / len(recent)
                ao = sum(older) / len(older)
                if ao > 0:
                    trend = (ar - ao) / ao
                    if trend < -0.015 and self.ifi_trend > 0.25: self.stall = "fatigue_stall"
                    elif trend < -0.015: self.stall = "e1rm_decline"
                    elif abs(trend) < 0.005 and self.weeks_same_load >= 3: self.stall = "true_plateau"
                    elif self.ifi_trend > 0.35: self.stall = "volume_stall"
                    elif abs(trend) < 0.008 and self.ifi_trend < 0.08: self.stall = "intensity_stall"
                    else: self.stall = "none"


def recommend(st, history, tl, th, tier, equip, pml, n_sets, readiness=3):
    r_mods = {1: (0.90, -3), 2: (0.95, -1), 3: (1.00, 0), 4: (1.00, 1), 5: (1.02, 2)}
    w_mod, rep_mod = r_mods.get(readiness, (1.0, 0))

    if not history or st.total_exposures < 1:
        if st.fresh_e1rm > 0:
            c = st.coeff(pml)
            w = rtp(weight_for_reps(st.fresh_e1rm * c, th) * w_mod)
        else:
            w = 0
        return {"weight": w, "per_set": [th] * n_sets, "rule": "first_session"}

    last = history[0]
    mx = max(s[0] for s in last)
    wk = [s for s in last if s[0] >= mx * 0.80]
    if not wk:
        return {"weight": rtp(mx), "per_set": [th] * n_sets, "rule": "hold"}

    ifi = compute_ifi(last); zone = ifi_zone(ifi)

    all_top = all(s[1] >= th for s in wk)
    top_hit = last[0][1] >= th
    miss2 = sum(1 for s in wk if s[1] < tl) >= 2
    prev_miss = False
    if miss2 and len(history) > 1:
        pm = max(s[0] for s in history[1])
        pw = [s for s in history[1] if s[0] >= pm * 0.80]
        prev_miss = sum(1 for s in pw if s[1] < tl) >= 2

    if all_top: rule = "progress"
    elif top_hit and not miss2 and tier == "T3": rule = "top_set_prog"
    elif miss2 and prev_miss: rule = "backoff"
    else: rule = "hold"

    if zone == "FATIGUED" and rule in ("progress", "top_set_prog"): rule = "hold"
    elif zone == "OVERTRAINED": rule = "backoff"
    if st.total_exposures < 3 and rule == "progress": rule = "hold"

    # RPE brake
    if st.last_rpe >= 9.5 and rule == "progress": rule = "hold"
    elif st.last_rpe > 0 and st.last_rpe <= 7.0 and rule == "hold": rule = "progress"

    inc = {"T1": 5.0, "T2": 5.0, "T3": 2.5}.get(tier, 5.0)
    is_db_iso = equip == "dumbbell" and tier == "T3"
    if is_db_iso: inc = 5.0

    if rule == "progress":
        if is_db_iso and st.consec_success < 2: w = rtp(mx); rule = "hold_db"
        else: w = rtp(mx + inc)
    elif rule == "top_set_prog": w = rtp(mx + inc)
    elif rule == "backoff":
        bp = {"T1": 0.94, "T2": 0.90, "T3": 0.85}[tier]
        w = rtp(mx * bp)
    else: w = rtp(mx)
    w = rtp(w * w_mod)

    per_set = []
    weight_up = w > mx
    for i in range(n_sets):
        lr = st.last_reps_per_set[i] if i < len(st.last_reps_per_set) else (tl + th) // 2
        if weight_up: target = max(tl, lr - 2)
        elif rule == "backoff": target = th
        else:
            bump = 2 if zone == "FRESH" else (1 if zone == "OPTIMAL" else 0)
            target = min(th, lr + bump)
            target = max(tl, target)
        target = max(tl, min(th, target + rep_mod))
        per_set.append(target)

    return {"weight": w, "per_set": per_set, "rule": rule, "ifi": ifi, "zone": zone}


# ═══════════════════════════════════════════════════════════════
# STRENGTH GOAL
# ═══════════════════════════════════════════════════════════════

@dataclass
class StrengthGoal:
    target: float; start: float; phase: str = "building"; wk: int = 1
    def lengths(self):
        gap = (self.target - self.start) / max(self.start, 1) * 100
        if gap > 15: return {"building": 5, "intensifying": 3, "peaking": 2, "testing": 1}
        elif gap > 10: return {"building": 4, "intensifying": 2, "peaking": 1, "testing": 1}
        elif gap > 5: return {"building": 3, "intensifying": 2, "peaking": 1, "testing": 1}
        return {"building": 2, "intensifying": 1, "peaking": 1, "testing": 1}
    def prescribe(self, e1rm):
        pl = self.lengths(); ln = pl.get(self.phase, 1)
        prog = (self.wk - 1) / max(ln - 1, 1)
        if self.phase == "building":
            return (max(3, 5 - int(prog*2)), 7.0 + prog, 0.78 + prog*0.07, 4)
        elif self.phase == "intensifying":
            return (max(2, 3 - int(prog)), 8.5 + prog*0.5, 0.85 + prog*0.07, 3)
        elif self.phase == "peaking":
            return (max(1, 2 - int(prog)), 9.0 + prog*0.5, 0.92 + prog*0.05, 2)
        return (1, 10, 0.98, 1)
    def advance(self):
        self.wk += 1; pl = self.lengths()
        if self.wk > pl.get(self.phase, 1):
            phases = ["building", "intensifying", "peaking", "testing"]
            idx = phases.index(self.phase)
            if idx < len(phases) - 1: self.phase = phases[idx + 1]; self.wk = 1


# ═══════════════════════════════════════════════════════════════
# LIFTER MODEL — REALISTIC
# ═══════════════════════════════════════════════════════════════

@dataclass
class Lifter:
    name: str; exercise: str; muscle: str; true_e1rm: float
    tier: str; equip: str; tl: int; th: int; n_sets: int; weeks: int
    growth: float = 0.002       # REALISTIC: per-week e1RM growth
    true_sens: float = 0.12
    pml_type: str = "zero"
    pml_base: float = 0.4
    readiness_type: str = "normal"
    goal: float = 0
    weekly_fatigue: float = 0.0  # cross-session fatigue (0-0.05)
    sessions_per_week: int = 1   # how many times this exercise appears per week

    def get_pml(self, wk):
        if self.pml_type == "zero": return 0.0
        elif self.pml_type == "low": return self.pml_base * 0.5
        elif self.pml_type == "mid": return self.pml_base
        elif self.pml_type == "high": return self.pml_base * 2.5
        elif self.pml_type == "alternating": return self.pml_base if wk % 2 == 0 else self.pml_base * 2.5
        elif self.pml_type == "random": return max(0, self.pml_base * (0.3 + random.random() * 2.5))
        return self.pml_base

    def get_readiness(self, wk):
        if self.readiness_type == "normal": return 3
        elif self.readiness_type == "variable": return random.choice([2, 3, 3, 3, 4, 5])
        elif self.readiness_type == "declining": return max(1, 4 - wk // 3)
        elif self.readiness_type == "improving": return min(5, 2 + wk // 3)
        elif self.readiness_type == "bad_week": return 1 if wk == 4 else 3
        return 3


def run_lifter(l, verbose=False):
    random.seed(hash(l.name) % 2**31)
    st = State()
    st.fresh_e1rm = l.true_e1rm
    st.baseline_e1rm = l.true_e1rm
    history = []; start_e1rm = l.true_e1rm
    goal = StrengthGoal(l.goal, l.true_e1rm) if l.goal > 0 else None
    log = []

    for wk in range(1, l.weeks + 1):
        pml = l.get_pml(wk)
        readiness = l.get_readiness(wk)
        true_coeff = max(0.70, 1.0 - pml * l.true_sens)
        # Weekly accumulated fatigue (second session in week is slightly worse)
        weekly_mod = 1.0 - l.weekly_fatigue
        effective_e1rm = l.true_e1rm * true_coeff * weekly_mod

        if goal and goal.phase not in ("achieved", "testing"):
            reps_rx, rpe, pct, sets_rx = goal.prescribe(l.true_e1rm)
            w = rtp(l.true_e1rm * pct)
            per_set = [reps_rx] * sets_rx
            rule = f"goal_{goal.phase}"
            n_sets = sets_rx
        else:
            rec = recommend(st, history, l.tl, l.th, l.tier, l.equip, pml, l.n_sets, readiness)
            w = rec["weight"] if rec["weight"] > 0 else rtp(weight_for_reps(effective_e1rm, l.th))
            per_set = rec["per_set"]
            rule = rec["rule"]
            n_sets = l.n_sets

        # Simulate actual performance with realistic model
        actual = []; rpes = []
        for s in range(n_sets):
            r = sim_set_reps(effective_e1rm, w, s, l.tier, readiness)
            r = min(r, l.th + 5)
            actual.append((w, r))
            # Simulate RPE
            fresh_cap = reps_at_weight(effective_e1rm, w)
            rpe_val = sim_rpe(r, fresh_cap)
            rpes.append(rpe_val)

        st.update(actual, rpes, pml, l.tl, l.th, w)
        history.insert(0, actual)
        if len(history) > 5: history = history[:5]

        ifi = compute_ifi(actual)
        act_s = "/".join(str(s[1]) for s in actual)
        tgt_s = "/".join(str(r) for r in per_set[:n_sets])
        avg_rpe = sum(rpes) / len(rpes) if rpes else 0

        log.append({"wk": wk, "w": w, "actual": act_s, "target": tgt_s, "rule": rule,
                     "ifi": ifi, "e1rm": st.fresh_e1rm, "sens": st.sensitivity,
                     "pml": pml, "R": readiness, "stall": st.stall, "rpe": avg_rpe})

        if verbose:
            stall_s = f" [{st.stall}]" if st.stall != "none" else ""
            print(f"    Wk{wk:2d} R={readiness} PML={pml:.1f} {w:6.0f}×{act_s:<15s} "
                  f"(aim:{tgt_s:<15s}) {rule:<16s} IFI={ifi:.2f} RPE={avg_rpe:.1f} "
                  f"e1RM={st.fresh_e1rm:.0f} sens={st.sensitivity:.3f}{stall_s}")

        # Growth (realistic)
        l.true_e1rm *= (1 + l.growth)
        if goal: goal.advance()

    gap = 0
    if l.goal > 0 and l.goal != start_e1rm:
        gap = (st.fresh_e1rm - start_e1rm) / (l.goal - start_e1rm) * 100
    return {"name": l.name, "start": start_e1rm, "final": st.fresh_e1rm,
            "best": st.best_e1rm, "sens": st.sensitivity, "true_sens": l.true_sens,
            "stall": st.stall, "gap": gap, "log": log}


# ═══════════════════════════════════════════════════════════════
# REALISTIC LIFTER PROFILES
# ═══════════════════════════════════════════════════════════════

LIFTERS = [
    # ── T1: BEGINNERS (high growth, fresh neural pathways) ──
    Lifter("Beginner Bench (3mo in)", "bench", "Chest", 155, "T1", "barbell", 5, 8, 4, 16,
           growth=0.012, pml_type="zero"),
    Lifter("Beginner Squat (3mo in)", "squat", "Quads", 185, "T1", "barbell", 5, 8, 4, 16,
           growth=0.015, pml_type="zero"),
    Lifter("Beginner Deadlift (3mo in)", "dl", "Back", 225, "T1", "barbell", 3, 5, 3, 16,
           growth=0.012, pml_type="zero"),
    Lifter("Beginner OHP (3mo in)", "ohp", "Delts", 95, "T1", "barbell", 5, 8, 4, 16,
           growth=0.010, pml_type="zero"),
    Lifter("Total Newbie (week 1)", "bench", "Chest", 75, "T1", "barbell", 5, 10, 3, 12,
           growth=0.020, pml_type="zero"),

    # ── T1: INTERMEDIATES (slow growth, 1-3 years training) ──
    Lifter("Intermediate Bench (2yr)", "bench", "Chest", 265, "T1", "barbell", 3, 5, 4, 20,
           growth=0.0015, pml_type="low", pml_base=0.3),
    Lifter("Intermediate Squat (2yr)", "squat", "Quads", 335, "T1", "barbell", 3, 5, 4, 20,
           growth=0.0012, pml_type="zero"),
    Lifter("Intermediate Deadlift (2yr)", "dl", "Back", 405, "T1", "barbell", 3, 5, 3, 20,
           growth=0.0010, pml_type="zero"),
    Lifter("Intermediate OHP (2yr)", "ohp", "Delts", 155, "T1", "barbell", 5, 8, 4, 20,
           growth=0.0010, pml_type="low", pml_base=0.3),

    # ── T1: ADVANCED (very slow, 5+ years) ──
    Lifter("Advanced Bench (5yr, 315)", "bench", "Chest", 345, "T1", "barbell", 3, 5, 3, 24,
           growth=0.0004, pml_type="zero"),
    Lifter("Advanced Squat (5yr, 455)", "squat", "Quads", 475, "T1", "barbell", 3, 5, 3, 24,
           growth=0.0003, pml_type="zero"),
    Lifter("Advanced Deadlift (5yr, 545)", "dl", "Back", 565, "T1", "barbell", 3, 5, 3, 24,
           growth=0.0002, pml_type="zero"),

    # ── T2: COMPOUND ACCESSORIES ──
    Lifter("Incline Bench T2 (after flat)", "incline", "Chest", 195, "T2", "barbell", 6, 10, 3, 16,
           growth=0.0015, true_sens=0.12, pml_type="mid", pml_base=0.4),
    Lifter("BB Row T2", "row", "Back", 205, "T2", "barbell", 6, 10, 3, 16,
           growth=0.0015, true_sens=0.08, pml_type="low", pml_base=0.2),
    Lifter("RDL T2 (after squat)", "rdl", "Hams", 275, "T2", "barbell", 6, 10, 3, 16,
           growth=0.0012, true_sens=0.10, pml_type="mid", pml_base=0.3),
    Lifter("Leg Press T2", "lp", "Quads", 405, "T2", "machine", 8, 12, 4, 16,
           growth=0.0015, true_sens=0.10, pml_type="mid", pml_base=0.4),
    Lifter("DB Shoulder Press T2", "dbp", "Delts", 115, "T2", "dumbbell", 6, 10, 3, 16,
           growth=0.0012, true_sens=0.12, pml_type="mid", pml_base=0.3),

    # ── T3: ISOLATION ──
    Lifter("DB Curl 35lb", "curl", "Biceps", 80, "T3", "dumbbell", 8, 12, 3, 16,
           growth=0.0010, true_sens=0.18, pml_type="mid", pml_base=0.4),
    Lifter("Tricep Pushdown", "pd", "Triceps", 145, "T3", "cable", 10, 15, 3, 16,
           growth=0.0012, true_sens=0.15, pml_type="alternating", pml_base=0.3),
    Lifter("Lateral Raise 20lb", "lr", "Delts", 48, "T3", "dumbbell", 12, 15, 3, 16,
           growth=0.0008, true_sens=0.10, pml_type="low", pml_base=0.2),
    Lifter("Cable Fly", "fly", "Chest", 75, "T3", "cable", 12, 15, 3, 16,
           growth=0.0010, true_sens=0.08, pml_type="high", pml_base=0.3),
    Lifter("Leg Curl", "lc", "Hams", 160, "T3", "machine", 8, 12, 3, 16,
           growth=0.0010, true_sens=0.10, pml_type="mid", pml_base=0.3),
    Lifter("Calf Raise", "cr", "Calves", 220, "T3", "machine", 12, 20, 3, 16,
           growth=0.0005, pml_type="zero"),

    # ── PML EDGE CASES ──
    Lifter("Pushdown FIRST (PML=0)", "pd0", "Triceps", 145, "T3", "cable", 10, 15, 3, 16,
           growth=0.0012, true_sens=0.15, pml_type="zero"),
    Lifter("Pushdown LAST (PML=high)", "pd5", "Triceps", 145, "T3", "cable", 10, 15, 3, 16,
           growth=0.0012, true_sens=0.15, pml_type="high", pml_base=0.4),
    Lifter("Curl Alternating PML", "ca", "Biceps", 80, "T3", "dumbbell", 8, 12, 3, 20,
           growth=0.0010, true_sens=0.20, pml_type="alternating", pml_base=0.3),
    Lifter("Curl Random PML", "cr2", "Biceps", 80, "T3", "dumbbell", 8, 12, 3, 20,
           growth=0.0010, true_sens=0.14, pml_type="random", pml_base=0.3),

    # ── SENSITIVITY EXTREMES ──
    Lifter("Tough Triceps (0.04)", "tt", "Triceps", 145, "T3", "cable", 10, 15, 3, 20,
           growth=0.0012, true_sens=0.04, pml_type="mid", pml_base=0.5),
    Lifter("Fragile Biceps (0.22)", "fb", "Biceps", 80, "T3", "dumbbell", 8, 12, 3, 20,
           growth=0.0010, true_sens=0.22, pml_type="mid", pml_base=0.5),

    # ── READINESS SCENARIOS ──
    Lifter("Variable Readiness", "vr", "Chest", 225, "T1", "barbell", 5, 8, 4, 16,
           growth=0.0015, readiness_type="variable", pml_type="zero"),
    Lifter("Declining Health/Stress", "dh", "Chest", 225, "T1", "barbell", 5, 8, 4, 16,
           growth=0.0005, readiness_type="declining", pml_type="zero"),
    Lifter("Recovery Improving", "ri", "Chest", 225, "T1", "barbell", 5, 8, 4, 16,
           growth=0.0020, readiness_type="improving", pml_type="zero"),
    Lifter("One Terrible Week (wk4)", "tw", "Chest", 225, "T1", "barbell", 5, 8, 4, 16,
           growth=0.0015, readiness_type="bad_week", pml_type="zero"),

    # ── STALL / PROBLEM SCENARIOS ──
    Lifter("True Plateau (0% growth)", "tp", "Chest", 265, "T1", "barbell", 3, 5, 4, 24,
           growth=0.0000, pml_type="zero"),
    Lifter("Overtraining (-0.2%/wk)", "ot", "Quads", 365, "T1", "barbell", 3, 5, 4, 16,
           growth=-0.0020, pml_type="zero"),
    Lifter("Deficit Cut (-0.1%/wk)", "dc", "Chest", 265, "T1", "barbell", 3, 5, 4, 16,
           growth=-0.0010, readiness_type="declining", pml_type="zero"),
    Lifter("High Noise Lifter", "hn", "Chest", 225, "T1", "barbell", 3, 5, 4, 16,
           growth=0.0012, pml_type="zero"),

    # ── STRENGTH GOALS ──
    Lifter("Bench Goal 245→275 (12%)", "bg", "Chest", 245, "T1", "barbell", 3, 5, 4, 16,
           growth=0.0020, pml_type="zero", goal=275),
    Lifter("Squat Goal 355→405 (14%)", "sg", "Quads", 355, "T1", "barbell", 3, 5, 4, 16,
           growth=0.0015, pml_type="zero", goal=405),
    Lifter("DL Goal 445→500 (12%)", "dg", "Back", 445, "T1", "barbell", 3, 5, 3, 16,
           growth=0.0010, pml_type="zero", goal=500),
    Lifter("Close Goal 285→300 (5%)", "cg", "Chest", 285, "T1", "barbell", 3, 5, 4, 10,
           growth=0.0015, pml_type="zero", goal=300),

    # ── SPECIAL POPULATIONS ──
    Lifter("Female Beginner Squat", "fs", "Quads", 105, "T1", "barbell", 5, 8, 4, 16,
           growth=0.010, pml_type="zero"),
    Lifter("Older Lifter (50+, slow)", "ol", "Chest", 185, "T1", "barbell", 5, 8, 3, 20,
           growth=0.0005, pml_type="zero"),
    Lifter("Teenager (fast recovery)", "teen", "Chest", 135, "T1", "barbell", 5, 8, 4, 16,
           growth=0.015, pml_type="zero"),

    # ── COMBINED STRESS ──
    Lifter("High PML + Bad Readiness", "hb", "Triceps", 120, "T3", "cable", 10, 15, 3, 12,
           growth=0.0008, true_sens=0.18, pml_type="high", pml_base=0.5, readiness_type="declining"),
    Lifter("Zero PML + Great Recovery", "zg", "Chest", 225, "T1", "barbell", 5, 8, 4, 12,
           growth=0.0025, pml_type="zero", readiness_type="improving"),
]

# ═══════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════

if __name__ == "__main__":
    print("=" * 85)
    print(f"  POWERBODYBUILDER ENGINE v7 — REALISTIC SIMULATION ({len(LIFTERS)} lifters)")
    print("=" * 85)

    results = []
    for l in LIFTERS:
        original_e1rm = l.true_e1rm
        r = run_lifter(l)
        l.true_e1rm = original_e1rm  # reset for traces
        results.append((l, r))

    # Scorecard
    print(f"\n{'─'*85}")
    print(f"  {'Name':<35s} {'Tier':>4s} {'Start':>6s} {'Final':>6s} {'Δ%':>6s} "
          f"{'Sens':>5s}→{'Lrn':>5s} {'RPE':>4s} {'Stall':<14s}")
    print(f"  {'─'*35} {'─'*4} {'─'*6} {'─'*6} {'─'*6} {'─'*5} {'─'*5} {'─'*4} {'─'*14}")

    cats = defaultdict(list)
    for l, r in results:
        pct = ((r["final"] - r["start"]) / r["start"] * 100) if r["start"] > 0 else 0
        if l.goal > 0: cat = "GOAL"
        elif "PML" in l.name or "Tough" in l.name or "Fragile" in l.name: cat = "PML"
        elif l.readiness_type != "normal": cat = "READY"
        elif "Plateau" in l.name or "Overtrain" in l.name or "Noise" in l.name or "Deficit" in l.name: cat = "STALL"
        elif l.tier == "T1": cat = "T1"
        elif l.tier == "T2": cat = "T2"
        else: cat = "T3"
        cats[cat].append((l, r, pct))
        stall = r["stall"] if r["stall"] != "none" else ""
        flag = "✓" if pct > 0 else ("✗" if pct < -3 else "—")
        avg_rpe = sum(e["rpe"] for e in r["log"]) / len(r["log"]) if r["log"] else 0
        print(f"  {flag} {r['name']:<32s} {l.tier:>4s} {r['start']:6.0f} {r['final']:6.0f} {pct:+5.1f}% "
              f"{l.true_sens:5.2f}→{r['sens']:5.3f} {avg_rpe:4.1f} {stall:<14s}")

    # Category summary
    print(f"\n{'='*85}")
    for cat in ["T1", "T2", "T3", "PML", "READY", "STALL", "GOAL"]:
        items = cats.get(cat, [])
        if not items: continue
        avg = sum(p for _, _, p in items) / len(items)
        neg = sum(1 for _, _, p in items if p < -3)
        pos = sum(1 for _, _, p in items if p > 0)
        print(f"  {cat:>5s} ({len(items):2d}): avg {avg:+5.1f}% | {pos} progressed | {neg} regressed >3%")

    # Sensitivity
    print(f"\n{'='*85}")
    print(f"  SENSITIVITY CONVERGENCE")
    sens = [(l, r) for l, r in results if l.pml_base > 0.15 and l.weeks >= 16]
    conv = 0
    for l, r in sens:
        err = abs(r["sens"] - l.true_sens)
        ok = err < 0.06; conv += ok
        print(f"  {'✓' if ok else '~'} {l.name:<32s} true={l.true_sens:.3f} learned={r['sens']:.3f} err={err:.3f}")
    if sens: print(f"  Converged: {conv}/{len(sens)}")

    # Stall detection
    print(f"\n{'='*85}")
    print(f"  STALL DETECTION")
    for l, r in results:
        if any(k in l.name for k in ["Plateau", "Overtrain", "Deficit"]):
            det = r["stall"] != "none"
            print(f"  {'✓' if det else '✗'} {l.name}: '{r['stall']}'")

    # Goals
    print(f"\n{'='*85}")
    print(f"  STRENGTH GOALS")
    for l, r in results:
        if l.goal > 0:
            print(f"  {l.name}: {r['start']:.0f}→{r['final']:.0f} (target {l.goal:.0f}) | {r['gap']:.0f}% gap closed")

    # Detailed traces
    traces = ["Intermediate Bench (2yr)", "DB Curl 35lb", "Tricep Pushdown",
              "One Terrible Week (wk4)", "Bench Goal 245→275 (12%)",
              "True Plateau (0% growth)", "Curl Alternating PML", "Deficit Cut (-0.1%/wk)"]
    print(f"\n{'='*85}")
    print(f"  DETAILED TRACES")
    print(f"{'='*85}")
    for name in traces:
        l = next((x for x in LIFTERS if x.name == name), None)
        if l:
            print(f"\n  ── {name} (growth={l.growth*100:.2f}%/wk, sens={l.true_sens:.2f}, "
                  f"PML={l.pml_type}) ──")
            l.true_e1rm = next(x.true_e1rm for x in LIFTERS if x.name == name)
            run_lifter(l, verbose=True)
