# Robots — sprint 1 summary (2026-09-27, cloud session)

Branch: `claude/godot-headless-setup-fdm8ay`

## Setup
- Godot 4.7.2 runs headless in the cloud sandbox; `tools/cloud_setup.sh` fixed
  (builds `level.json` before verifying, puts Godot on PATH, generates routes).
- Headless tests were pacing physics to real time; `--fixed-fps 60` cuts the
  drive test from 7 min to ~10 s. Documented everywhere the command appears.
- CLAUDE.md: laptop is an Intel i3 + Intel UHD, CPU-bound as much as GPU-bound.

## Vision
- Area 3 renamed **the Hub** in PROJECT_VISION.md (approved): the city's
  central district; parts unlock to reach further dungeons; one unlock +
  dungeon ≈ one sprint.

## Performance (unmeasured, needs F4)
- 3D render scale 0.8, 2048 shadow map, 30 m shadow distance, tree LOD bias 0.5.
  No re-bake needed. Owner re-measures perf_4 and perf_5.

## The vertical slice (built, headlessly verified)
1. **Opening menu** (Continue / New game / Quit) is the main scene.
2. **Foundation**: autoloads `Catalog` (items, tools, recipes as data),
   `Clock` (8-minute day, sun position), `Energy` (battery), `Game` (flags,
   inventory, crafting, one JSON autosave written on dock), `Story` (beats).
3. **Energy loop**: driving drains ~0.9 %/s; chargers hold a capacity and fill
   from real sun angle (tilted panel); docking transfers charge and autosaves
   ("consciousness copied"); zero energy → shutdown → reboot at the last
   charger next morning, inventory kept.
4. **Day/night**: one light plays sun and moon; sky, fog, ambient and clouds
   keyed on the sun; headlights and eye glow at dusk.
5. **Tools**: data-driven framework (a new tool is a Catalog entry). Smasher and
   Cutter built. `Breakable` (effects, health, drops, flag) and `LockedGate`
   (key item, flag) are the obstacle components; both persist across saves.
6. **Inventory + crafting**: Tab panel, craft anywhere, Subnautica-style
   have/need counts. Pickups are real items and stay collected.
7. **The house**: wake beside the charger (moved off the wall); hammer head
   behind the crate by the door, actuator arm on the corner crate; build the
   Smasher; three hits open the jammed door.
8. **The forest**: brambles are a cuttable Breakable hiding a pocket with a
   second charger; a charger in the Dry Clearing; the Giant can be inspected;
   story triggers at every design node.
9. **The Hub**: new `hub_design.json` and a generalised district pipeline
   (`district_build.py`, `district_verify.py`, routes/bake/drive test with
   `++ hub`). Walled avenue to a 34 m relay tower; rubble (smash) → gate key →
   iron gate → relay card → tower door. Unlocking the tower ends the slice.
   The hill got a flat pad with a long blend (north face 37°).
10. **Narrative**: placeholder beats with a Greek-myth touchstone (Talos,
    Delphi, the hearth), one data file the owner can rewrite.
11. **Look pass**: wheels spin with speed, chest light shows battery, eye
    lenses brighten at night, charger core pulses while docked, tool hits
    flash, tower beacon blinks.

## Verification
| Check | Result |
|---|---|
| Forest verifier | sealed; 22 open places; pocket sealed until brambles cut |
| Forest drive test | 22 of 22 routes; hill ↔ city ok |
| Hub verifier | sealed; 5 open places; 3 gated in order |
| Hub drive test | 7 of 7 routes; gates hold, then open |
| Systems test (`tools/systems_test.gd`) | 100+ checks, 0 failures |

## First playtest findings
- Tab (parts screen) and Esc paused the tree, and the key handler that closes
  them lived on the paused player: the screens could not be closed from the
  keyboard. Fixed: the panels handle their own close keys; Close button added.

## Not verified
- Looks and frame rate (no GPU in the sandbox).
- Energy/charger numbers are guesses; tune after the playtest.

## Constraints hit
- Only GitHub is reachable from the sandbox; all new art is primitives and the
  existing Quaternius kits. New packs need the owner's push.
- The old local day/night system was never in the repo; a new one was written.

## Next
- Owner playtest with the checklist in `TODO.md` (F2/F3/F4 reports).
- Then: relay tower as dungeon 1, more tools (hover, laser, matter gen),
  charger upgrades, combat prototype, cuttable trees, the zombie Easter egg.
