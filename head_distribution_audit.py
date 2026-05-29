#!/usr/bin/env python3
"""
Audits ExerciseDictionary.swift muscle-head distribution.

The app credits muscles two ways:
  - If headContributions is non-empty, musclesCredit() = MAX head weight per
    parent muscle (heads → parentMuscle). The legacy primary/secondary strings
    are then IGNORED for volume credit.
  - If headContributions is empty, it falls back to primary(1.0)/secondary(weight).

So for any exercise WITH headContributions, every primary muscle must be
represented by a head at near-full weight, and meaningful secondaries should
have a head — otherwise that muscle is silently undercounted (the adductor bug).

Run: python3 head_distribution_audit.py
"""
import re, sys

SRC = "Powerbodybuilder/ExerciseDictionary.swift"

# MuscleHead case name -> parent tracking muscle (from MuscleHeads.swift)
HEAD_PARENT = {
    "chestUpper": "Chest", "chestMid": "Chest", "chestLower": "Chest",
    "lats": "Back", "midBack": "Back", "traps": "Back", "lowerBack": "Back",
    "deltsFront": "Delts", "deltsLateral": "Delts", "rearDelts": "Delts",
    "rectusFemoris": "Quads", "vastusLateralis": "Quads", "vastusMedialis": "Quads",
    "hamstringsKneeFlexion": "Hamstrings", "hamstringsHipExtension": "Hamstrings", "adductors": "Hamstrings",
    "glutesMax": "Glutes", "glutesMedius": "Glutes",
    "gastrocnemius": "Calves", "soleus": "Calves",
    "bicepsLong": "Biceps", "bicepsShort": "Biceps", "brachialis": "Biceps",
    "tricepsLong": "Triceps", "tricepsLateral": "Triceps", "tricepsMedial": "Triceps",
}

def normalize(raw):
    l = raw.lower()
    if "chest" in l or "pec" in l: return "Chest"
    if "lat" in l or "mid back" in l or "lower back" in l or "trap" in l or l == "back": return "Back"
    if "quad" in l or "rectus femoris" in l: return "Quads"
    if "hamstring" in l: return "Hamstrings"
    if "abduct" in l: return "Glutes"
    if "adduct" in l: return "Hamstrings"
    if "glute" in l: return "Glutes"
    if "calf" in l or "calves" in l or "gastrocnemius" in l or "soleus" in l: return "Calves"
    if "bicep" in l or "brachialis" in l or "brachioradialis" in l: return "Biceps"
    if "tricep" in l: return "Triceps"
    if "delt" in l or "shoulder" in l: return "Delts"
    if "ab" in l or "oblique" in l or "core" in l or "transverse" in l or "hip flexor" in l: return "Core"
    if "rotator" in l: return "Delts"
    return None

txt = open(SRC).read()
chunks = txt.split("ExerciseDefinition(")[1:]

def field_array(chunk, label):
    m = re.search(label + r"\s*:\s*\[(.*?)\]", chunk, re.DOTALL)
    return m.group(1) if m else None

bugs, warns, no_heads = [], [], []
total = 0
for c in chunks:
    km = re.search(r'key:\s*"([^"]+)"', c)
    if not km: continue
    key = km.group(1)
    total += 1

    prim_raw = field_array(c, "primaryMuscles") or ""
    primaries = re.findall(r'"([^"]+)"', prim_raw)
    sec_raw = field_array(c, "secondaryMuscles") or ""
    secondaries = re.findall(r'muscle:\s*"([^"]+)"', sec_raw)
    head_raw = field_array(c, "headContributions") or ""
    heads = {h: float(w) for h, w in re.findall(r'\.(\w+):\s*([0-9.]+)', head_raw)}

    if not heads:
        no_heads.append((key, primaries, secondaries))
        continue

    # max head weight per parent muscle
    cred = {}
    for h, w in heads.items():
        if h not in HEAD_PARENT:
            warns.append(f"{key}: unknown head '.{h}'")
            continue
        p = HEAD_PARENT[h]
        cred[p] = max(cred.get(p, 0), w)

    prim_norm = {normalize(p) for p in primaries} - {None}
    sec_norm = {normalize(s) for s in secondaries} - {None}

    # PRIMARY muscle undercounted by heads
    for p in prim_norm:
        if cred.get(p, 0) < 0.8:
            bugs.append(f"{key}: PRIMARY {p} has head-credit {cred.get(p,0):.1f} (<0.8) — undercounted")

    # SECONDARY muscle with no head at all
    for s in sec_norm:
        if s not in cred:
            warns.append(f"{key}: secondary {s} not represented in headContributions")

    # head crediting a muscle not in primary/secondary
    for p in cred:
        if p not in prim_norm and p not in sec_norm:
            warns.append(f"{key}: head credits {p} but it's not a listed primary/secondary muscle")

print(f"Audited {total} exercises ({len(no_heads)} have no headContributions / legacy path)\n")
print(f"=== BUGS: primary muscle undercounted by heads ({len(bugs)}) ===")
for b in bugs: print("  " + b)
print(f"\n=== WARNINGS: secondary/extra mismatches ({len(warns)}) ===")
for w in warns: print("  " + w)
print(f"\n=== No headContributions (legacy primary/secondary — fine for abs/forearms) ({len(no_heads)}) ===")
for k, p, s in no_heads: print(f"  {k}: primary={p} secondary={s}")
