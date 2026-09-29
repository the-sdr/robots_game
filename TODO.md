# TODO — next session

## Start here: the owner's sprint 2 playtest (feedback + bug fixes)
1. Open `playtest/sprint2_feedback.md`. If the owner hasn't filled it in, go
   through it with them one question at a time (most important first) and
   write each answer on its `Answer:` line. Also read new entries in
   `playtest/perf.md` / `playtest/saves.md` (F4/F3), **including their
   `Note:` lines** (the owner's typed feedback), and note the machine.
2. List the bugs and wanted changes from the answers here, most serious first,
   and confirm the order with the owner before fixing.
3. Work on `claude/sync-local-fixes-b85lpn` (playtests run from it until the
   owner merges it into `main`). After each fix run the matching pipeline and
   tests (`CLAUDE.md` → Level pipeline / Verify); commit and push only when
   the owner asks.

## From the 2026-09-29 playtest (laptop)
- [x] Controller: A presses menu buttons, right trigger uses the tool.
      **Playtest:** menus, the Tab screen (build with A) and tool use with the pad.
- [x] Tiny curse 10x smaller (0.04, about 5 cm) and a 7 cm mouse hole.
      **Playtest:** does the world feel giant? Camera OK in the hole? Can
      your son find the hole? (It is small: say if it needs a hint.)
- [x] Candle: plain wax + small flame, no longer glows like a pickup.
- [x] Charge bar: a ring blinks only while energy moves (docked, or sun filling).
- [x] Dock cable: reels out of the post into the robot's back, and back in.
- [x] Fall rescue: falling off the world puts the robot back on solid ground.
- [x] Battery by difficulty (evening playtest): a full battery lasts 15 / 10 / 5
      minutes of driving on Easy / Medium / Hard (was under 2 minutes).
      **Playtest:** does Easy feel relaxed now? Are chargers still worth finding?
- [x] Jump kept (owner) and animated: stretch + tread push at takeoff, arms out
      in the air, a squash sized by the fall on landing with a springy
      recovery, a nod, dust and a small camera dip. **Playtest:** does it read
      as a robot pushing off? Landing too much / too little? Tiny jump OK?
- [x] **Phase A: detector test build.** R / pad Y toggles it; a sweep every 5 s
      (1 s of robot view: grid + height contours on the ground, warm spots that
      tighten as you close in, a warm haze above the trees for far ones, signal
      bars bottom centre). Robot can always dig (E / pad X on the spot).
      Six test finds: garden gate, garden nook, fork path, three in the Dry
      Clearing (see the X marks on forest_map_v3_built.png). Pad remap: Menu =
      crafting, View = pause, LB/RB = cycle tool, Y = detector.
      **Playtest:** does the sweep rhythm feel good? Too bright / too faint?
      Does the far haze help in the trees? Ground shader OK (not pink/black)?
- [ ] Phase B: button pictures (keyboard/pad), tool cards, "Tools & controls" page.
- [ ] Phase C: tools with their own feel (cutter hold/heat, smasher rapid, laser trace).
- [ ] Phase D: find types - weeds (cut), containers (smash), wrecks (salvage; laser = better loot).
- [x] F3 also saves a screenshot (playtest/shots/save_N.jpg, 1280 wide, named on
      the entry's line) of what was on screen when F3 was pressed. Commit them
      with the logs; read them when reviewing notes.
- [ ] **Detector ("robot vision"), design in progress with the owner.** Owner's
      direction so far: visual only (deaf-friendly: no beeps needed to play);
      the overlay shows the robot's view - a grid with contours following the
      terrain; far away, warm spots with randomness give a sense of direction,
      getting less random as you close in; maybe the scan shows ~1 s out of
      every 5. Finds are dug up or taken from containers that make sense in the
      world (Detectorists as inspiration). Memories are computer parts it finds.
      Open: where the detector comes from, the buttons, what is buried first,
      and whether the labyrinth layout should open up (open world / hybrid).
      Owner liked the "sweep" rhythm: a wave rolls out every few seconds,
      warm spots flare and tighten as you close in. Finds come out different
      ways: dug up, salvaged (wrecks, defeated robots), hidden in weeds to cut
      away, inside containers to smash.
- [ ] **Tools that each feel different to use (owner, 2026-09-29).** Cutting:
      hold the button, release before it overheats. Bashing: rapid presses.
      Laser, and more tools later, each with their own feel. The game must
      teach each one well: an elegant, non-diegetic controls popup (the robot
      knows how; the player doesn't) that shows which button does what,
      keyboard or pad. Design first, with the owner.
- [ ] **Design with the owner: content beyond the tree line for the tiny
      robot** (the escape stays: the owner likes it). Enough to fill a full
      charge. Question raised: procedural content from a point outward, to
      keep it light to run. Talk through options before building.
- [ ] More controller polish if the playtest asks: zoom on the pad, B = back.

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
- [x] Phase 4: combat, hill sentry, laser. **Playtest (try Easy first, then
      Medium and Hard):** build the Laser (Tab) from the optic lens + circuit
      board + antenna coil. Tab shows the "Fight kit" row: click a slot to
      change its tool. Walk up the hill: the Hill Sentry rolls in. Your turn:
      1/2/3 (hold W or S for other moves); press Space when the ring closes.
      Its turn: Space as its ring closes = dodge. Win → capacitor, the sentry
      sits beside the path. On Medium/Hard losing rolls you back down the hill.
      Is Easy easy enough for a six-year-old? Is the camera framing OK? Laser:
      does the beam read? (Nothing burnable yet: vines come with the Agora.)
- [x] Phase 5: charger upgrades, solar HUD, segmented charge bar. **Playtest:**
      each charger's post now has five glowing rings (the filling one blinks).
      Top-left HUD: a sun (moon at night) with "Sun NN%", and your charger's
      charge and fill rate. Dock, then Tab: "Battery bank" (capacitor from the
      sentry), "Sun tracker" (from the crooked house's mouse hole) and "Panel
      extension" (2 solar cells: one on the crooked house shelf, the second
      comes with the relay vault) fit to that charger and show on it.
- [x] Phase 6: opening cutscene. **Playtest:** New Game (not Continue) plays it
      (~21 s): forest from above → the roof, a robin lands on the board → it
      wobbles → close-up, it flies off → the board slides off, the solar panel
      glints → the dock's bar lights, one ring blinking → the robot's eye, the
      iris opens a little. Space/Esc skips. Check the camera framing in each
      shot, and the frame rate of the first (over the forest) on the laptop.
- [x] Phase 7: relay vault dungeon, Pythia, hover. **Playtest:** open the
      tower door (relay card) → E on the glowing lift pad → the Relay Vault.
      The mirror hall: E on a mirror turns it; by day sunlight comes down a
      shaft onto the west lens (or zap that lens with the laser any time).
      Steer the beam into the big lens on the north wall → the door opens →
      Pythia talks (E for her next line) and gives 2 lift fans + a gyro;
      the second solar cell is in her room. Build the hover pack (Tab): jump
      and hold Space in the air to hover up to ~2.5 m. Is the puzzle clear
      enough for a six-year-old? Does the vault feel sealed and lit well?
- [x] Phase 8: the Agora district, fabricator. **Playtest:** in the Hub's east
      yard (behind the rubble) the east wall has a 4 m curtain of vines at
      (28, −114): the smasher bounces off, the laser burns it (2 zaps). The
      Agora (x 28…62, z −128…−100): a market square with wagons, fences,
      crates and the Agora charger (36, −107). North lane → the printer shop's
      jammed shutter (50, −121): smash it (3 hits, 2 scrap) → printer core +
      nozzle → Tab: Fabricator. With it, Tab also lists "Print a power cell /
      solar cell / capacitor bank" from scrap. South-east: a 1.6 m stone ledge
      (54, −106) with a scrap cache: hover up from any side, or stand at its
      west foot (46.5, −106) and press E (or click with the fabricator) at the
      glowing ghost ramp → it prints for 2 scrap → drive up. Fight kit: the
      fabricator's moves are Patch up (heal) / Plate / Sticky blob. Do the
      vines read as burnable? Is the ghost ramp obvious? Frame rate in the
      square (its walls are merged: 6 draws instead of 44)?

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
Sprint 2 built the relay vault + Pythia, laser/hover/fabricator, charger
upgrades + solar HUD, combat + the hill sentry, the zombie and the Agora.
Still open:
- **Cuttable trees** (owner decision which), dead-end props (spring pipe, hatch).
- **More fights**: a second enemy (the Agora? the vault?), enemy moves that use
  the timing ring differently, a rematch arena.
- **More districts**: each `<name>_design.json` (see the Agora) opens from the
  Hub or the Agora; the forest's `open_extra` rects extend the ground.
- **More buildables** (`scripts/interact/buildable.gd`): bridges, ladders,
  a printed charger panel.
- The consciousness-copy story (Pythia's lines are placeholders).

## 3. Performance (still the open problem until measured)
- Perf pass 1 applied (project.godot, world.tscn, solid_tree.gd). Next levers if
  needed: fewer individual trees (`INDIVIDUAL_REACH` 3.0 → 1.5 in forest_build.py,
  needs a re-bake), thinner pine leaf cards, sparser pines on paths.
- Watch draw calls in the Hub: 116 wall pieces are 116 draws. The Agora merges
  its walls into chunk meshes (`"merge_walls": true`, 44 pieces → 6 draws);
  set the same flag in `hub_design.json` and re-bake if F4 says so.

## 4. Textures / look (unchanged from before the sprint)
- Owner collecting Poly Haven sets locally; wanted: mossy meadow ground,
  rock for slopes. Approve extraction to `assets/polyhaven/`.
- Grass cards, tree revamp, colour grade — after performance is known.

## 5. Owner decisions (vision)
- [ ] The diegetic reason robot consciousness can be copied at a charger (the save).
- [ ] Which trees can be cut / smashed.
- [ ] Zombie details; combat system reference.
- [ ] Names: Delphi (the Hub), Talos (the giant), the hearth (chargers) are placeholders.
