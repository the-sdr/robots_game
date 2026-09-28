# TODO — next session

## Sprint 2 (cloud, started 2026-09-28) — branch `claude/sync-local-fixes-b85lpn`
Plan approved by the owner: crooked house + Angry Zombie + tiny curse, the hill
sentry tutorial fight (turn-based, 3-tool loadout), Easy/Medium/Hard, real part
models, laser/hover/fabricator, charger upgrades + solar HUD, opening cutscene,
relay vault dungeon + Pythia, the Agora district. Each phase is pushed when its
headless tests pass; pull the branch to playtest any of them.

- [x] Phase 0: vision wording added (owner-approved with the plan).
- [x] Phase 1: difficulty setting. **Playtest:** main menu and pause menu show
      "Difficulty: Easy"; clicking cycles Easy → Medium → Hard; it is remembered
      after quitting. (It only matters once fights exist, phase 4.)
- [x] Phase 2: crooked house, Angry Zombie, tiny curse. **Playtest:** from the
      garden gate (0, −12) take the new path south-west to the crooked house
      (−25, 3). Sign "ANGRY ZOMBIE — DO NOT POKE". Inside: the zombie, a solar
      cell on the shelf (north wall). Poke him (E) three times, or hit him with
      the smasher → ZAP, tiny for two days (HUD shows the countdown). Tiny: drive
      through the mouse hole at the bottom of the wardrobe (south-west corner)
      to the sun tracker. Does the house read as crooked? Anything poking
      through walls or roof? (Say where, F3.) Can the camera escape?
- [x] Phase 3: real collectible models. **Playtest:** every pickup is now its
      own little model (servo, lens, power cell, circuit board, gear train,
      antenna coil, hammer head, actuator arm, scrap, key, card, solar cell...).
      Do they read at a glance, day and night? Anything too small or too shiny?
- [ ] Phase 4: combat, hill sentry, laser.
- [ ] Phase 5: charger upgrades, solar HUD, segmented charge bar.
- [ ] Phase 6: opening cutscene.
- [ ] Phase 7: relay vault dungeon, Pythia, hover.
- [ ] Phase 8: the Agora district, fabricator.

Written 2026-09-27 at the end of sprint 1 (cloud). Newest priorities first.

## 0. Owner playtest of the vertical slice (nothing below moves until this)
The slice is on `main` (merged via PR #1). Open in Godot 4.7.2, press Play
(main scene is now the menu). ~20 minutes. Please report with F2/F3
coordinates and F4 perf logs as before. Checklist:
- [ ] Menu: New game starts beside the house charger; Continue is greyed until a dock.
- [ ] House: find the hammer head (behind the crate by the door) and the actuator
      arm (on the corner crate); Tab → build the Smasher; click to smash the door (3 hits).
- [ ] HUD reads right: battery %, Day/clock, tool line, [E] prompts, notices, story cards.
- [ ] Energy: driving drains ~0.9 %/s; docking (E at a charger) fills and says
      "consciousness copied"; Esc pause; a dead battery reboots you next morning.
      **Tuning numbers are guesses** (`scripts/game/energy.gd`, `charger.gd`).
- [ ] Day/night: 8-minute day; sunset colours, moonlight, headlights and eye glow
      at night; the clearing charger fills fastest at noon.
- [ ] Forest: the six parts still at the dead ends; brambles say "thorns" to the
      smasher; Cutter needs servo + gear train + blade strip (2 scrap) + power cell;
      cutting the brambles reveals the pocket charger.
- [ ] Hill → Hub: the city is on a flat pad, the hill's north face is 37°.
- [ ] Hub: rubble (4 smashes) → gate key → west gate → relay card → tower door →
      "The relay" card. Do the walls/buildings read as a city? Does it feel sealed?
- [ ] Performance: F4 at perf_4 (pines, 10, −23, E), perf_5 (stream by the Giant,
      −8, −44, W), in the Hub avenue looking north, and at night in the forest.
      Perf pass 1 (render scale 0.8, 2048 shadows, 30 m, LOD bias) is unmeasured.
- [ ] Anything that looks wrong: say where (coordinates) and what.

## 0a. Windows release (Robots Beta)
- [ ] Owner: export `Robots Beta.exe` (`docs/windows_release.md`), run it once
      outside the editor, share with testers.

## 0b. Apple release (Robots Beta)
- [ ] Owner: on a Mac, follow `docs/apple_release.md` (TestFlight). Needs an Apple
      developer account, Xcode, certificates, a provisioning profile.
- [ ] Decide: iPhone/iPad too? Needs touch controls first.

## 1. Known rough edges (fix after the playtest, in this order)
- Placeholder art everywhere new: tool heads, relay tower, gates, the Fallen
  Giant, the robot. Real kits need the owner's push (sandbox reaches GitHub only).
- The two house crates are not smashable (scrap only comes from the door and
  rubble); consider making crates Breakables that drop scrap.
- Story text is placeholder; ids in `scripts/game/story.gd` are what the code uses.
- Debug overlay (F2) and HUD may overlap at the top-right; move one if so.
- Save: a single autosave; a save written by a future version is ignored
  (`SAVE_VERSION` in game.gd) — bump it when the format changes.

## 2. Next sprint candidates (owner picks)
- **The relay tower as dungeon 1** (interior, sealed shell, a puzzle, the first
  NPC robot / consciousness-copy story beat).
- **More tools** on the framework: hover/fly (energy per second while airborne),
  laser (ranged "burn"), matter generation (turn scrap into parts). Each is a
  Catalog entry + one effect in `tool_rig.gd` / a `Breakable` effect name.
- **Charger upgrades** (capacity, panel tilt/size) and a solar readout on the HUD.
- **Combat** prototype: robot vs robot, turn-based (Stick of Truth / Clair Obscur).
- **Cuttable trees** (owner decision which), dead-end props (spring pipe, hatch).
- **The zombie Easter egg** (annoy it → shrunk for two days).
- More Hub districts: each new `<name>_design.json` unlocks from the Hub.

## 3. Performance (still the open problem until measured)
- Perf pass 1 applied (project.godot, world.tscn, solid_tree.gd). Next levers if
  needed: fewer individual trees (`INDIVIDUAL_REACH` 3.0 → 1.5 in forest_build.py,
  needs a re-bake), thinner pine leaf cards, sparser pines on paths.
- Watch draw calls in the Hub: 118 wall pieces are 118 draws; merge them into
  chunks like trees if F4 says so.

## 4. Textures / look (unchanged from before the sprint)
- Owner collecting Poly Haven sets locally; wanted: mossy meadow ground,
  rock for slopes. Approve extraction to `assets/polyhaven/`.
- Grass cards, tree revamp, colour grade — after performance is known.

## 5. Owner decisions (vision)
- [ ] The diegetic reason robot consciousness can be copied at a charger (the save).
- [ ] Which trees can be cut / smashed.
- [ ] Zombie details; combat system reference.
- [ ] Names: Delphi (the Hub), Talos (the giant), the hearth (chargers) are placeholders.
