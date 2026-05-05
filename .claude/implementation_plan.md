# Implementation Plan — Adaptive Deload + UX Clarity Pass

## Priority 1: Adaptive Deload System

### Current State
- Static deloads every N weeks (hardcoded in seeders: wk 4/12/20 for most programs)
- `generateBlock()` appends +1 deload week to every block automatically
- Users can skip/add deloads manually via `customDeloadWeeks`/`skippedDeloadWeeks`

### Target State
- Remove static deload scheduling for hypertrophy, powerbuilding, recomp
- Keep static deloads ONLY for strength goal (peaking cycle needs predictable structure)
- Deload triggers based on performance data:
  - 2+ muscles have progressionRule == .backoff for 2+ consecutive sessions
  - IFI trend > 0.30 across 3+ exercises
  - e1RM declining on 2+ T1 exercises simultaneously
- When triggered: suggest deload (user can accept or dismiss)
- "I need a break" button in settings/home for manual override
- Deload = 1 week at MV volume, RPE 6.0 (same as current deload week content)

### Files to Change
- `Models.swift` — `BlockType.next()` skip auto-deload for non-strength
- `ProgramGenerator.swift` — `generateBlock()` remove the +1 deload week for non-strength
- `WorkoutView.swift` — `finalizeWorkout()` check deload triggers after VDE
- `HomeView.swift` — show deload suggestion banner when triggered
- New: `DeloadSuggestionView` — explains why, shows the data, accept/dismiss

## Priority 2: UX Clarity Pass

### Issues from User Testing
1. Week indicator (Week 1, Week 2) not tappable, unclear what it represents
2. Mesocycle/block info in Train tab not tappable
3. Weekly muscle coverage not tappable
4. Configure week button too small in corner, gets missed
5. Everything should be tappable with clear affordance

### Specific Changes Needed

#### Home Screen
- **Week strip** — each week pill should be tappable (already is via WeekStrip)
  but needs clearer visual affordance (larger tap target, label)
- **"WEEK 3 SCHEDULE" header** — tap to open week overview modal showing:
  - Block type (Accumulation, Reaccumulation, etc.)
  - Block week X of Y
  - RPE target range for this week
  - Volume adjustments active
  - "I need a break" deload request button
- **Muscle coverage section** — needs to exist as tappable row that opens
  per-muscle volume breakdown (sets done this week vs target vs MRV)
- **Configure button** — make it a full-width tappable row instead of
  small icon in corner

#### Train Screen
- **Mesocycle indicator** — tap to open block info sheet showing:
  - Current block type + number
  - Block sequence so far
  - What comes next
  - Weeks remaining in block
  - Performance trend summary

#### General
- Add chevron.right or info.circle to all tappable rows
- Use consistent tap affordance pattern across app
