# Block Sequence Configurator — Design

## What Opens When You Tap a Block in the Timeline

A full-screen sheet: **Block Sequence Editor**

### Section 1: Block List (editable)
Each block shows:
- Block number
- Block type (tappable to change: Training/Growth/Recovery for hyp; Accumulation/Intens/Peak/Deload for strength)
- Length in weeks (stepper 2-8)
- Volume multiplier (auto from type, or manual override)
- How it affects your program:
  - "Standard volume — same sets as configured"
  - "+15% more sets per muscle"
  - "Reduced volume — maintain, don't build"
- Drag to reorder blocks
- Add/remove blocks

### Section 2: How Blocks Affect Your Training
Visual explanation:
- Training Block: You keep your exercises, add weight/reps each week
- Growth Phase: 15% more sets, same exercises or rotated T2/T3
- Recovery: Half volume, light weights, movement quality focus
- (Strength) Intensification: fewer sets, heavier weight
- (Strength) Peaking: minimal sets, maximal weight

### Section 3: Exercise Rotation Settings
- Keep all exercises across blocks
- Rotate T2/T3 between blocks (T1 stays)
- Rotate everything

## Program Customization System

### Configure Program Button (Program Tab)
Opens a sheet with:

1. **Edit Sessions**
   - Rename any session
   - Add a session (permanent or this week only)
   - Remove a session (permanent or this week only)
   - Import a session from another program template

2. **Week Overrides**
   - For any week, override the schedule
   - "This week I want to run hypertrophy instead of powerbuilding"
   - Creates a week-scoped override that doesn't affect other weeks
   - Original program data preserved, override is layered on top

3. **Cross-Program Sessions**
   - Browse other program templates
   - Pick a session from another program
   - Add it to your current week or permanently

4. **Block Sequence**
   - Full block sequence editor (from above)
   - Changes apply to generated programs immediately
   - For seeded programs, shows a warning: "This program has pre-built templates. Block length changes affect labels but not exercise programming."
