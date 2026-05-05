#!/usr/bin/env python3
"""
Powerbodybuilder Engine v6 — FIXED & CALIBRATED
=================================================
Fixes from v5:
  1. Weight recommendation calibrated (no double-discount)
  2. Per-set targets properly read from last session
  3. Stall detection uses fresh-equiv e1RM
  4. Sensitivity only adapts when weight was in realistic range
  5. Strength goal loading matches actual e1RM percentages
  6. Realistic lifter simulation (capacity matches real-world performance)

Run: python3 progression_sim_v6.py
"""

import math, random
from dataclasses import dataclass, field
from collections import defaultdict

# ═══════════════════════════════════════════════════════════════
# CORE MATH
# ═══════════════════════════════════════════════════════════════

def rtp(w, m=False):
    inc = 2.5 if m else 5.0
    return round(w / inc) * inc

def e1rm(w, r):
    return w * (1 + r / 30.0) if w > 0 and r > 0 else 0

def weight_for_reps(e1, reps):
    """Inverse Epley: what weight for N reps at a given e1RM."""
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
# ENGINE STATE
# ═══════════════════════════════════════════════════════════════

@dataclass
class State:
    fresh_e1rm: float = 0          # EMA of fatigue-normalized e1RM
    best_e1rm: float = 0
    baseline_e1rm: float = 0       # set at first session (fresh-equiv)
    raw_e1rm_history: list = field(default_factory=list)  # last 5 fresh-equiv e1RMs
    total_exposures: int = 0
    consec_success: int = 0
    consec_fail: int = 0
    weeks_same_load: int = 0
    last_weight: float = 0
    last_reps_per_set: list = field(default_factory=list)
    sensitivity: float = 0.12
    last_ifi: float = 0
    ifi_trend: float = 0
    stall: str = "none"

    def coeff(self, pml):
        return max(0.70, 1.0 - pml * self.sensitivity)

    def update(self, sets, pml, tl, th, rec_weight):
        if not sets: return
        top = max(sets, key=lambda s: e1rm(s[0], s[1]))
        actual_e = e1rm(top[0], top[1])
        c = self.coeff(pml)
        fresh_e = actual_e / c if c > 0 else actual_e

        # EMA
        alpha = 0.25
        if self.fresh_e1rm == 0:
            self.fresh_e1rm = fresh_e
            self.baseline_e1rm = fresh_e
        else:
            self.fresh_e1rm = self.fresh_e1rm * (1 - alpha) + fresh_e * alpha

        self.best_e1rm = max(self.best_e1rm, fresh_e)
        self.raw_e1rm_history.append(fresh_e)
        if len(self.raw_e1rm_history) > 6: self.raw_e1rm_history = self.raw_e1rm_history[-6:]

        # Success/fail
        mx = max(s[0] for s in sets)
        working = [s for s in sets if s[0] >= mx * 0.80]
        if all(s[1] >= th for s in working):
            self.consec_success += 1; self.consec_fail = 0
        elif sum(1 for s in working if s[1] < tl) >= 2:
            self.consec_fail += 1; self.consec_success = 0
        else:
            pass  # neither full success nor double-miss

        prev = self.last_weight
        self.last_weight = mx
        self.last_reps_per_set = [s[1] for s in sets]
        self.weeks_same_load = (self.weeks_same_load + 1) if mx == prev and prev > 0 else 0
        self.total_exposures += 1

        # IFI
        ifi = compute_ifi(sets); self.last_ifi = ifi
        self.ifi_trend = ifi if self.total_exposures <= 1 else (self.ifi_trend * 2 + ifi) / 3

        # Sensitivity adaptation — ONLY when weight was realistic (within 30% of expected)
        if pml > 0.1 and self.total_exposures >= 3 and rec_weight > 0:
            expected_w = weight_for_reps(self.fresh_e1rm * c, (tl + th) // 2)
            if expected_w > 0 and abs(rec_weight - expected_w) / expected_w < 0.30:
                avg_actual = sum(s[1] for s in sets) / len(sets)
                mid_target = (tl + th) / 2.0
                error = (avg_actual - mid_target) / max(mid_target, 1)
                lr = max(0.04, 0.15 / (1 + self.total_exposures * 0.08))
                if error > 0.10:
                    self.sensitivity = max(0.03, self.sensitivity * (1 - lr))
                elif error < -0.10:
                    self.sensitivity = min(0.25, self.sensitivity * (1 + lr))

        # Stall detection (fresh-equiv based)
        if len(self.raw_e1rm_history) >= 4:
            recent = self.raw_e1rm_history[-3:]
            older = self.raw_e1rm_history[-6:-3] if len(self.raw_e1rm_history) >= 6 else self.raw_e1rm_history[:3]
            avg_recent = sum(recent) / len(recent)
            avg_older = sum(older) / len(older)
            if avg_older > 0:
                trend = (avg_recent - avg_older) / avg_older
                if trend < -0.02 and self.ifi_trend > 0.25:
                    self.stall = "fatigue_stall"
                elif trend < -0.02:
                    self.stall = "e1rm_decline"
                elif abs(trend) < 0.005 and self.weeks_same_load >= 3:
                    self.stall = "true_plateau"
                elif self.ifi_trend > 0.35:
                    self.stall = "volume_stall"
                elif abs(trend) < 0.01 and self.ifi_trend < 0.08:
                    self.stall = "intensity_stall"
                else:
                    self.stall = "none"


def recommend(st, history, tl, th, tier, equip, pml, n_sets, readiness=3):
    """Calibrated recommendation engine."""
    r_mods = {1: (0.90, -3), 2: (0.95, -1), 3: (1.00, 0), 4: (1.00, 1), 5: (1.02, 2)}
    w_mod, rep_mod = r_mods.get(readiness, (1.0, 0))

    # No history — seed from e1RM if available
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

    # Progression rule
    all_top = all(s[1] >= th for s in wk)
    top_hit = last[0][1] >= th
    miss2 = sum(1 for s in wk if s[1] < tl) >= 2
    prev_miss = False
    if miss2 and len(history) > 1:
        pm = max(s[0] for s in history[1])
        pw = [s for s in history[1] if s[0] >= pm * 0.80]
        prev_miss = sum(1 for s in pw if s[1] < tl) >= 2

    if all_top:
        rule = "progress"
    elif top_hit and not miss2 and tier == "T3":
        rule = "top_set_prog"
    elif miss2 and prev_miss:
        rule = "backoff"
    else:
        rule = "hold"

    # IFI gate
    if zone == "FATIGUED" and rule in ("progress", "top_set_prog"): rule = "hold"
    elif zone == "OVERTRAINED": rule = "backoff"

    # G8
    if st.total_exposures < 3 and rule == "progress": rule = "hold"

    # Weight calc — from LAST SESSION WEIGHT (not from e1RM table)
    inc = {"T1": 5.0, "T2": 5.0, "T3": 2.5}.get(tier, 5.0)
    is_db_iso = equip == "dumbbell" and tier == "T3"
    if is_db_iso: inc = 5.0

    if rule == "progress":
        if is_db_iso and st.consec_success < 2:
            w = rtp(mx); rule = "hold_db"
        else:
            w = rtp(mx + inc)
    elif rule == "top_set_prog":
        w = rtp(mx + inc)
    elif rule == "backoff":
        bp = {"T1": 0.94, "T2": 0.90, "T3": 0.85}[tier]
        w = rtp(mx * bp)
    else:
        w = rtp(mx)

    w = rtp(w * w_mod)

    # Per-set rep targets from LAST SESSION actual reps
    per_set = []
    weight_up = w > mx
    for i in range(n_sets):
        lr = st.last_reps_per_set[i] if i < len(st.last_reps_per_set) else (tl + th) // 2
        if weight_up:
            target = max(tl, lr - 2)
        elif rule == "backoff":
            target = th
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

    def prescribe(self, current_e1rm):
        pl = self.lengths(); ln = pl.get(self.phase, 1)
        prog = (self.wk - 1) / max(ln - 1, 1)
        if self.phase == "building":
            reps = max(3, 5 - int(prog * 2)); rpe = 7.0 + prog; pct = 0.78 + prog * 0.07; sets = 4
        elif self.phase == "intensifying":
            reps = max(2, 3 - int(prog)); rpe = 8.5 + prog * 0.5; pct = 0.85 + prog * 0.07; sets = 3
        elif self.phase == "peaking":
            reps = max(1, 2 - int(prog)); rpe = 9.0 + prog * 0.5; pct = 0.92 + prog * 0.05; sets = 2
        else:
            reps = 1; rpe = 10; pct = 0.98; sets = 1
        w = rtp(current_e1rm * pct)
        bo = rtp(w * 0.90)
        bo_sets = max(0, sets - 1) if self.phase not in ("peaking", "testing") else 0
        return {"w": w, "reps": reps, "rpe": rpe, "sets": sets, "bo_w": bo, "bo_sets": bo_sets,
                "phase": self.phase, "pw": f"{self.wk}/{ln}", "pct": pct}

    def advance(self):
        self.wk += 1; pl = self.lengths()
        if self.wk > pl.get(self.phase, 1):
            phases = ["building", "intensifying", "peaking", "testing"]
            idx = phases.index(self.phase)
            if idx < len(phases) - 1: self.phase = phases[idx + 1]; self.wk = 1


# ═══════════════════════════════════════════════════════════════
# LIFTER MODEL
# ═══════════════════════════════════════════════════════════════

@dataclass
class Lifter:
    name: str; exercise: str; muscle: str; true_e1rm: float
    tier: str; equip: str; tl: int; th: int; n_sets: int; weeks: int
    growth: float = 0.005       # weekly e1RM growth rate
    fatigue: float = 0.06       # per-set rep drop rate
    true_sens: float = 0.12     # real fatigue sensitivity
    noise: float = 0.5          # session variance
    pml_type: str = "mid"       # zero/low/mid/high/alternating/random
    pml_base: float = 0.4
    readiness_type: str = "normal"  # normal/variable/declining/improving/bad_week
    goal: float = 0             # strength goal target (0=none)

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

    def simulate_reps(self, weight, set_idx, readiness):
        """Realistic rep simulation based on true capacity."""
        r_mult = {1: 0.82, 2: 0.91, 3: 1.0, 4: 1.04, 5: 1.08}.get(readiness, 1.0)
        true_cap = reps_at_weight(self.true_e1rm * r_mult, weight)
        # Per-set fatigue
        drop = set_idx * self.fatigue * true_cap
        actual = max(1, int(round(true_cap - drop + random.gauss(0, self.noise))))
        return actual


def run_lifter(l, verbose=False):
    random.seed(hash(l.name) % 2**31)
    st = State()
    # Seed fresh e1RM from true value
    st.fresh_e1rm = l.true_e1rm
    st.baseline_e1rm = l.true_e1rm

    history = []
    true_e1rm_start = l.true_e1rm
    goal = StrengthGoal(l.goal, l.true_e1rm) if l.goal > 0 else None
    log = []

    for wk in range(1, l.weeks + 1):
        pml = l.get_pml(wk)
        readiness = l.get_readiness(wk)
        true_coeff = max(0.70, 1.0 - pml * l.true_sens)
        # Apply PML to true capacity for this session
        effective_e1rm = l.true_e1rm * true_coeff

        if goal and goal.phase != "achieved":
            rx = goal.prescribe(l.true_e1rm)
            w = rx["w"]
            per_set = [rx["reps"]] * rx["sets"]
            rule = f"goal_{rx['phase']}"
            n_sets = rx["sets"]
        else:
            rec = recommend(st, history, l.tl, l.th, l.tier, l.equip, pml, l.n_sets, readiness)
            w = rec["weight"] if rec["weight"] > 0 else rtp(weight_for_reps(effective_e1rm, l.th))
            per_set = rec["per_set"]
            rule = rec["rule"]
            n_sets = l.n_sets

        # Simulate actual performance at recommended weight
        actual = []
        for s in range(n_sets):
            r = l.simulate_reps(w, s, readiness)
            r = min(r, l.th + 5)  # soft cap
            actual.append((w, r))

        st.update(actual, pml, l.tl, l.th, w)
        st.last_rule = rule
        history.insert(0, actual)
        if len(history) > 5: history = history[:5]

        ifi = compute_ifi(actual)
        act_s = "/".join(f"{s[1]}" for s in actual)
        tgt_s = "/".join(str(r) for r in per_set[:n_sets])

        log.append({"wk": wk, "w": w, "actual": act_s, "target": tgt_s, "rule": rule,
                     "ifi": ifi, "e1rm": st.fresh_e1rm, "sens": st.sensitivity,
                     "pml": pml, "R": readiness, "stall": st.stall})

        if verbose:
            stall_s = f" [{st.stall}]" if st.stall != "none" else ""
            print(f"    Wk{wk:2d} R={readiness} PML={pml:.1f} {w:6.0f}×{act_s:<15s} "
                  f"(aim:{tgt_s:<15s}) {rule:<16s} IFI={ifi:.2f} "
                  f"e1RM={st.fresh_e1rm:.0f} sens={st.sensitivity:.3f}{stall_s}")

        l.true_e1rm *= (1 + l.growth)
        if goal: goal.advance()

    gap_closed = 0
    if l.goal > 0 and l.goal != true_e1rm_start:
        gap_closed = (st.fresh_e1rm - true_e1rm_start) / (l.goal - true_e1rm_start) * 100

    return {"name": l.name, "start": true_e1rm_start, "final": st.fresh_e1rm,
            "best": st.best_e1rm, "sens": st.sensitivity, "true_sens": l.true_sens,
            "stall": st.stall, "gap_closed": gap_closed, "log": log}


# ═══════════════════════════════════════════════════════════════
# ALL LIFTER PROFILES
# ═══════════════════════════════════════════════════════════════

LIFTERS = [
    # ── T1 MAIN LIFTS ──
    Lifter("Beginner Bench", "bench", "Chest", 155, "T1", "barbell", 5, 8, 4, 12,
           growth=0.015, fatigue=0.08, true_sens=0.10, pml_type="zero"),
    Lifter("Intermediate Bench", "bench", "Chest", 265, "T1", "barbell", 3, 5, 4, 12,
           growth=0.006, fatigue=0.10, true_sens=0.08, pml_type="low", pml_base=0.3),
    Lifter("Advanced Bench (315)", "bench", "Chest", 350, "T1", "barbell", 3, 5, 3, 12,
           growth=0.002, fatigue=0.12, true_sens=0.06, pml_type="zero", noise=0.8),
    Lifter("Beginner Squat", "squat", "Quads", 185, "T1", "barbell", 5, 8, 4, 12,
           growth=0.018, fatigue=0.09, true_sens=0.08, pml_type="zero"),
    Lifter("Intermediate Squat", "squat", "Quads", 335, "T1", "barbell", 3, 5, 4, 10,
           growth=0.005, fatigue=0.10, true_sens=0.06, pml_type="zero"),
    Lifter("Advanced Squat (455)", "squat", "Quads", 475, "T1", "barbell", 3, 5, 3, 12,
           growth=0.001, fatigue=0.12, true_sens=0.05, pml_type="zero", noise=1.0),
    Lifter("Beginner Deadlift", "dl", "Back", 225, "T1", "barbell", 3, 5, 3, 12,
           growth=0.015, fatigue=0.12, true_sens=0.06, pml_type="zero"),
    Lifter("Intermediate Deadlift", "dl", "Back", 425, "T1", "barbell", 3, 5, 3, 10,
           growth=0.004, fatigue=0.14, true_sens=0.05, pml_type="zero"),
    Lifter("OHP Beginner", "ohp", "Delts", 105, "T1", "barbell", 5, 8, 4, 12,
           growth=0.012, fatigue=0.09, true_sens=0.12, pml_type="zero"),
    Lifter("OHP Intermediate", "ohp", "Delts", 165, "T1", "barbell", 3, 5, 4, 10,
           growth=0.004, fatigue=0.10, true_sens=0.10, pml_type="low", pml_base=0.3),

    # ── T2 ACCESSORIES ──
    Lifter("BB Row T2", "row", "Back", 215, "T2", "barbell", 6, 10, 3, 10,
           growth=0.005, fatigue=0.07, true_sens=0.08, pml_type="low", pml_base=0.3),
    Lifter("Incline Bench T2", "incline", "Chest", 195, "T2", "barbell", 6, 10, 3, 10,
           growth=0.006, fatigue=0.08, true_sens=0.12, pml_type="mid", pml_base=0.4),
    Lifter("RDL T2", "rdl", "Hams", 275, "T2", "barbell", 6, 10, 3, 10,
           growth=0.005, fatigue=0.08, true_sens=0.08, pml_type="mid", pml_base=0.3),
    Lifter("Leg Press T2", "lp", "Quads", 405, "T2", "machine", 8, 12, 4, 10,
           growth=0.007, fatigue=0.06, true_sens=0.10, pml_type="mid", pml_base=0.5),
    Lifter("DB Press T2", "dbp", "Delts", 115, "T2", "dumbbell", 6, 10, 3, 10,
           growth=0.005, fatigue=0.07, true_sens=0.12, pml_type="mid", pml_base=0.3),

    # ── T3 ISOLATION ──
    Lifter("DB Curl (40lb)", "curl", "Biceps", 90, "T3", "dumbbell", 8, 12, 3, 10,
           growth=0.004, fatigue=0.05, true_sens=0.18, pml_type="mid", pml_base=0.4),
    Lifter("Pushdown (cable)", "pushdown", "Triceps", 155, "T3", "cable", 10, 15, 3, 10,
           growth=0.005, fatigue=0.04, true_sens=0.15, pml_type="alternating", pml_base=0.3),
    Lifter("Lateral Raise (20lb DB)", "lat_raise", "Delts", 48, "T3", "dumbbell", 12, 15, 3, 10,
           growth=0.003, fatigue=0.04, true_sens=0.10, pml_type="low", pml_base=0.2),
    Lifter("Cable Fly", "fly", "Chest", 75, "T3", "cable", 12, 15, 3, 8,
           growth=0.004, fatigue=0.04, true_sens=0.08, pml_type="mid", pml_base=0.6),
    Lifter("Leg Curl", "legcurl", "Hams", 160, "T3", "machine", 8, 12, 3, 10,
           growth=0.004, fatigue=0.05, true_sens=0.10, pml_type="mid", pml_base=0.3),
    Lifter("Calf Raise", "calf", "Calves", 220, "T3", "machine", 12, 20, 3, 8,
           growth=0.002, fatigue=0.03, true_sens=0.05, pml_type="zero"),
    Lifter("Face Pull", "fp", "Delts", 65, "T3", "cable", 12, 20, 3, 8,
           growth=0.003, fatigue=0.03, true_sens=0.08, pml_type="low", pml_base=0.15),

    # ── PML EDGE CASES ──
    Lifter("Pushdown FIRST (PML=0)", "pd0", "Triceps", 155, "T3", "cable", 10, 15, 3, 8,
           true_sens=0.15, pml_type="zero"),
    Lifter("Pushdown LAST (PML=high)", "pd5", "Triceps", 155, "T3", "cable", 10, 15, 3, 8,
           true_sens=0.15, pml_type="high", pml_base=0.4),
    Lifter("Curl Alternating PML", "curl_alt", "Biceps", 90, "T3", "dumbbell", 8, 12, 3, 12,
           true_sens=0.20, pml_type="alternating", pml_base=0.3),
    Lifter("Curl Random PML", "curl_rand", "Biceps", 90, "T3", "dumbbell", 8, 12, 3, 12,
           true_sens=0.14, pml_type="random", pml_base=0.3, noise=0.8),

    # ── SENSITIVITY EXTREMES ──
    Lifter("Tough Triceps (sens=0.04)", "td_tough", "Triceps", 155, "T3", "cable", 10, 15, 3, 14,
           true_sens=0.04, pml_type="mid", pml_base=0.5),
    Lifter("Fragile Biceps (sens=0.22)", "bc_frag", "Biceps", 90, "T3", "dumbbell", 8, 12, 3, 14,
           true_sens=0.22, pml_type="mid", pml_base=0.5),

    # ── READINESS PATTERNS ──
    Lifter("Variable Readiness", "bench_var", "Chest", 215, "T1", "barbell", 5, 8, 4, 10,
           growth=0.008, readiness_type="variable", pml_type="zero"),
    Lifter("Declining Health", "bench_dec", "Chest", 215, "T1", "barbell", 5, 8, 4, 10,
           growth=0.001, readiness_type="declining", pml_type="zero"),
    Lifter("Improving Recovery", "bench_imp", "Chest", 215, "T1", "barbell", 5, 8, 4, 10,
           growth=0.010, readiness_type="improving", pml_type="zero"),
    Lifter("One Terrible Week (wk4)", "bench_bad", "Chest", 215, "T1", "barbell", 5, 8, 4, 10,
           growth=0.008, readiness_type="bad_week", pml_type="zero"),

    # ── STALL SCENARIOS ──
    Lifter("True Plateau (0% growth)", "plat", "Chest", 265, "T1", "barbell", 3, 5, 4, 14,
           growth=0.000, fatigue=0.10, noise=0.6, pml_type="zero"),
    Lifter("Overtraining (-0.3%/wk)", "overtrain", "Quads", 365, "T1", "barbell", 3, 5, 4, 12,
           growth=-0.003, fatigue=0.14, noise=0.8, pml_type="zero"),
    Lifter("High Day-to-Day Noise", "noisy", "Chest", 240, "T1", "barbell", 3, 5, 4, 10,
           growth=0.005, noise=1.5, fatigue=0.10, pml_type="zero"),

    # ── STRENGTH GOALS ──
    Lifter("Bench Goal 225→275", "bg275", "Chest", 245, "T1", "barbell", 3, 5, 4, 14,
           growth=0.008, pml_type="zero", goal=275),
    Lifter("Squat Goal 335→405", "sg405", "Quads", 355, "T1", "barbell", 3, 5, 4, 14,
           growth=0.006, pml_type="zero", goal=405),
    Lifter("DL Goal 425→500", "dg500", "Back", 445, "T1", "barbell", 3, 5, 3, 14,
           growth=0.004, pml_type="zero", goal=500),
    Lifter("OHP Goal 145→185", "og185", "Delts", 155, "T1", "barbell", 3, 5, 4, 12,
           growth=0.006, pml_type="zero", goal=185),
    Lifter("Close Goal (5% away)", "close", "Chest", 285, "T1", "barbell", 3, 5, 4, 8,
           growth=0.006, pml_type="zero", goal=300),

    # ── EXTREME EDGE CASES ──
    Lifter("First Timer (bar only)", "newbie", "Chest", 75, "T1", "barbell", 5, 10, 3, 8,
           growth=0.025, fatigue=0.06, noise=1.0, pml_type="zero"),
    Lifter("Hyper-Responder Beginner", "hyper", "Quads", 125, "T2", "barbell", 8, 12, 3, 12,
           growth=0.020, fatigue=0.05, pml_type="zero"),
    Lifter("5-Set Heavy Bench", "bench5", "Chest", 235, "T1", "barbell", 3, 5, 5, 10,
           growth=0.006, fatigue=0.10, pml_type="zero"),
    Lifter("6-Set Leg Press", "lp6", "Quads", 500, "T2", "machine", 8, 12, 6, 8,
           growth=0.005, fatigue=0.05, pml_type="mid", pml_base=0.3),
    Lifter("High PML + Bad Readiness", "combo_bad", "Triceps", 120, "T3", "cable", 10, 15, 3, 8,
           growth=0.003, true_sens=0.18, pml_type="high", pml_base=0.5, readiness_type="declining"),
    Lifter("Zero PML + Great Readiness", "combo_good", "Chest", 215, "T1", "barbell", 5, 8, 4, 8,
           growth=0.010, pml_type="zero", readiness_type="improving"),
    Lifter("Female Beginner Squat", "fem_sq", "Quads", 105, "T1", "barbell", 5, 8, 4, 12,
           growth=0.012, fatigue=0.07, pml_type="zero"),
    Lifter("Older Lifter (slow)", "older", "Chest", 185, "T1", "barbell", 5, 8, 3, 12,
           growth=0.002, fatigue=0.08, noise=0.8, pml_type="zero"),
    Lifter("Deficit Cutting", "cut", "Chest", 250, "T1", "barbell", 3, 5, 4, 10,
           growth=-0.001, fatigue=0.10, readiness_type="declining", pml_type="zero"),
]


# ═══════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════

if __name__ == "__main__":
    print("=" * 80)
    print(f"  POWERBODYBUILDER ENGINE v6 — {len(LIFTERS)} LIFTERS")
    print("=" * 80)

    results = []
    for l in LIFTERS:
        r = run_lifter(l)
        results.append((l, r))

    # ── SCORECARD ──
    print(f"\n{'─'*80}")
    print(f"  {'Name':<33s} {'e1RM':>5s} {'Start':>6s} {'Final':>6s} {'Δ%':>6s} "
          f"{'Sens':>5s}→{'Lrn':>5s} {'Stall':<14s}")
    print(f"  {'─'*33} {'─'*5} {'─'*6} {'─'*6} {'─'*6} {'─'*5} {'─'*5} {'─'*14}")

    cats = defaultdict(list)
    for l, r in results:
        pct = ((r["final"] - r["start"]) / r["start"] * 100) if r["start"] > 0 else 0
        if l.goal > 0: cat = "GOAL"
        elif "PML" in l.name or "Tough" in l.name or "Fragile" in l.name: cat = "PML"
        elif l.readiness_type != "normal": cat = "READY"
        elif "Plateau" in l.name or "Overtrain" in l.name or "Noise" in l.name or "Cut" in l.name: cat = "STALL"
        elif l.tier == "T1": cat = "T1"
        elif l.tier == "T2": cat = "T2"
        else: cat = "T3"
        cats[cat].append((l, r, pct))

        stall = r["stall"] if r["stall"] != "none" else ""
        flag = "✓" if pct > 0 else ("✗" if pct < -5 else "—")
        print(f"  {flag} {r['name']:<30s} {l.tier:>5s} {r['start']:6.0f} {r['final']:6.0f} {pct:+5.1f}% "
              f"{l.true_sens:5.2f}→{r['sens']:5.3f} {stall:<14s}")

    # ── CATEGORY SUMMARY ──
    print(f"\n{'='*80}")
    print(f"  CATEGORY SUMMARY")
    print(f"{'='*80}")
    for cat in ["T1", "T2", "T3", "PML", "READY", "STALL", "GOAL"]:
        items = cats.get(cat, [])
        if not items: continue
        avg = sum(p for _, _, p in items) / len(items)
        regressions = sum(1 for _, _, p in items if p < -5)
        positives = sum(1 for _, _, p in items if p > 0)
        print(f"\n  {cat} ({len(items)} lifters): avg {avg:+.1f}% | "
              f"{positives} progressed | {regressions} regressed >5%")

    # ── SENSITIVITY CONVERGENCE ──
    print(f"\n{'='*80}")
    print(f"  SENSITIVITY CONVERGENCE")
    print(f"{'='*80}")
    sens_cases = [(l, r) for l, r in results if l.pml_base > 0.15 and l.weeks >= 10]
    converged = 0
    for l, r in sens_cases:
        err = abs(r["sens"] - l.true_sens)
        ok = err < 0.06
        if ok: converged += 1
        print(f"  {'✓' if ok else '~'} {l.name:<30s} true={l.true_sens:.3f} learned={r['sens']:.3f} err={err:.3f}")
    print(f"  Converged: {converged}/{len(sens_cases)}")

    # ── STALL DETECTION ──
    print(f"\n{'='*80}")
    print(f"  STALL DETECTION")
    print(f"{'='*80}")
    stall_expected = [(l, r) for l, r in results
                      if "Plateau" in l.name or "Overtrain" in l.name or "Cut" in l.name]
    for l, r in stall_expected:
        detected = r["stall"] != "none"
        print(f"  {'✓' if detected else '✗'} {l.name}: detected='{r['stall']}'")

    # ── STRENGTH GOALS ──
    print(f"\n{'='*80}")
    print(f"  STRENGTH GOALS")
    print(f"{'='*80}")
    goal_lifters = [(l, r) for l, r in results if l.goal > 0]
    for l, r in goal_lifters:
        print(f"  {l.name}: {r['start']:.0f}→{r['final']:.0f} (target {l.goal:.0f}) "
              f"| {r['gap_closed']:.0f}% gap closed")

    # ── DETAILED TRACES ──
    traces = ["Intermediate Bench", "DB Curl (40lb)", "Pushdown (cable)",
              "One Terrible Week (wk4)", "Bench Goal 225→275", "True Plateau (0% growth)",
              "Curl Alternating PML", "Deficit Cutting"]
    print(f"\n{'='*80}")
    print(f"  DETAILED TRACES")
    print(f"{'='*80}")
    for name in traces:
        l = next((x for x in LIFTERS if x.name == name), None)
        if l:
            print(f"\n  ── {name} ({l.tier} {l.equip}, e1RM={l.true_e1rm:.0f}, "
                  f"growth={l.growth*100:.1f}%/wk, sens={l.true_sens:.2f}) ──")
            # Reset true_e1rm since run_lifter mutates it
            l.true_e1rm = next(x.true_e1rm for x in LIFTERS if x.name == name)
            run_lifter(l, verbose=True)
