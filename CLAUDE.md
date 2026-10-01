# CLAUDE.md — read this first

**Robots**: a Godot 4.7 exploration game — a small tracked robot wakes in the
remains of a failed civilization that nature has reclaimed. You are working
with the project owner, who is learning Godot alongside this project.

Also read before substantial work:
- `CLAUDE_NOTES.md` — architecture, lessons learned (hard-won; don't repeat them), session log.
- `TODO.md` — current priorities.
- `PROJECT_VISION.md` — the game's direction. **Owned by the owner** (see rules).
- `level_design/forest_design.json` + `level_design/maps/` — the current level design.

## Rules (from the owner — follow exactly)

1. **`PROJECT_VISION.md` is owner-controlled.** Never edit it without explicit
   approval. Propose exact wording in chat, wait for a yes.
2. **Never launch the game with a visible window, and never create screenshots,
   without asking first.** On the owner's laptop a windowed run took over their
   machine (window focus, mouse capture, GPU). In a cloud sandbox there is no
   GPU anyway: **the owner playtests**; you build, verify headlessly, push.
3. **Headless Godot runs are fine without asking — but say each time that one
   is running** (resource draw), and name any other external executable you run.
4. **Stay inside the project.** Don't touch other locations without explicit
   approval. **Ask before copying external asset files into the project.**
5. **Memory:** propose anything worth remembering as short y/n items; save only
   the yes ones. Durable project knowledge goes into `CLAUDE_NOTES.md`.
6. **Every interior needs a fully sealed collision shell** — walls AND ceiling —
   or the camera escapes through the top.
7. **"Might" often means "will".** When the owner writes that something
   "might" need doing, treat it as a likely request: check whether it's a
   "will" (do it, or ask in one line) rather than filing it as an idea.
8. **Communication style:** one short, plain sentence before each action about
   *that* action (no bundled "I'll do X, then Y, then Z"). Explain *why*, not
   just what. The owner's feedback is terse — treat it as a precise course
   correction, don't soften or over-explain it back. Flag real risks (scale,
   collision, destructive changes, performance) *before* acting. Report
   outcomes faithfully, including failures.
9. **Don't switch renderers** (`project.godot`) without the owner agreeing to
   test it. Renderer is **Mobile** (Forward+ hung the owner's laptop).
10. **Never push to `main`** (only the working branch). Before every push,
   check what is going out (`git diff --stat origin/<branch>..HEAD`); if it
   deletes files you didn't mean to delete, stop and tell the owner. (On
   2026-09-30 a push from a failed clone emptied `main`; restored in f96fe92.)
11. **Standing permission to commit and push to the working branch** — no need
   to ask first. After each one, give a brief plain-language summary of what
   was committed and why. Merging into `main`, force-pushing, and deleting
   branches still need the owner's go-ahead. End commit messages with the
   attribution line the environment provides.

## The owner's machines and targets
The owner works on **two Windows machines**; check which one before talking
about paths or performance (`$env:PROCESSOR_ARCHITECTURE`: AMD64 = laptop,
ARM64 = Surface).
- **Laptop** — Lenovo, x64, **Intel i3 CPU** and **Intel UHD integrated
  graphics**: CPU-bound as much as GPU-bound. Watch draw calls, node counts
  and per-frame script cost, not only triangles. Target **25 FPS** there
  (the weakest machine sets the bar). Godot 4.7.2 at
  `C:\Godot_v4.7.2-stable_win64.exe\`.
- **Surface Pro** (12", Snapdragon X Plus, 16 GB) — ARM64, **Adreno X1-45**
  (shared memory, native Vulkan + D3D12 drivers, no native OpenGL), screen
  2196 × 1464 @ 60 Hz. Godot 4.7.2 **native ARM64** at
  `C:\Godot_v4.7.2-stable_windows_arm64\` (`..._console.exe` for logs).
  Performance here is not yet measured — don't assume laptop numbers apply.
  If Vulkan misbehaves, try `--rendering-driver d3d12` (per-run, not a
  renderer switch).
- Record which machine each F4 capture came from in `playtest/perf.md`.
- In the cloud: run `bash tools/cloud_setup.sh` once (Python packages + Linux
  Godot for headless baking/tests). If Godot can't be downloaded, the Python
  tools still work; say so and let the owner bake locally.

## Shared language (proven in playtests — use it)
- Coordinates are **Godot world metres**: **X east (+), Z north (−)**, Y up.
  Compass: North = −Z, East = +X, South = +Z, West = −X; headings clockwise from North.
- In game: **F2** overlay (position, facing, camera heading, pitch, FPS),
  **F3** saves a position (`playtest/saves.md`: save_1, save_2…) with a typed
  playtest note (`- **Note:**` line under it) and a screenshot
  (`playtest/shots/save_N.jpg`, look at it), **F4** logs a
  5-second performance sample (`playtest/perf.md`: perf_1…), **F7** god mode
  (double-tap Space to fly, Space up / Shift down, no collision), **F9 / F10**
  detector / tool tuning panels (sliders; closing one logs the values to
  `playtest/tuning.md` as tune_N: bake good values into `scripts/game/tuning.gd`).
- **F1** (pad: D-pad down) opens Help in the game: controls, the testing notes,
  and the as-built map with the robot on it.
- **When a control or mechanic changes, update everything that tells the
  player about it** in the same commit: tool cards (`scripts/ui/tool_card.gd`),
  F1 help (`scripts/ui/help_menu.gd`), fight coach texts, HUD prompts and
  notices, the main menu bar and the testing notes. Button names always come
  from `Glyphs`, never typed into the text. Grep for the old wording before
  committing.
- **Testing notes** (`playtest/testing_notes.json`) are what the owner sees on
  the main menu and in F1: this sprint's playtest targets, each with "try" and
  "ask". **Keep them current**: rewrite them whenever a sprint's targets
  change, before pushing a build for the owner to play.
- Talk about places as coordinates, save names, design node names
  (`fork`, `giant_ford`, `clearing`…) or area names, and check them against
  `level_design/maps/forest_map_v3_built.png` (everything actually placed,
  same grid as F2). Review issues at that level of reference.

## Level pipeline (source of truth: the design files in `level_design/`)
Forest (Area 2, `forest_design.json`, owns the terrain):
```
python tools/forest_map.py            # review map from the design (owner approves before building)
python tools/forest_build.py          # design -> level_design/build/level.json
python tools/forest_verify.py --map   # sealed? all places reachable? gated places sealed until cleared? only ways north via ruin/clearing?
godot --headless --path . -s tools/level_bake.gd        # level.json -> scenes/level/ (generated scene + chunk meshes)
python tools/forest_routes.py         # drive routes to every design node (routes.json)
godot --headless --fixed-fps 60 --path . -s tools/forest_drive_test.gd ++ serious  # real physics: all routes, blockers hold then clear, collectibles, house, hill<->city (run with ++ silly too)
python tools/forest_map.py --built    # as-built map for the owner
```
Hub (Area 3, `hub_design.json`, a district on the forest terrain; the same for any future district `<name>_design.json`):
```
python tools/district_build.py hub    # -> level_design/build/hub.json (buildings, wall runs, gates, chargers, pickups, props)
python tools/district_verify.py hub --map
python tools/forest_routes.py --design hub --start hub_entry --out hub_routes.json
godot --headless --path . -s tools/level_bake.gd ++ hub                              # -> scenes/level_hub/generated_hub.tscn
godot --headless --fixed-fps 60 --path . -s tools/forest_drive_test.gd ++ hub        # routes; gates hold, then open with their key/tool
```
The Agora (the second district, `agora_design.json`, east of the Hub; build the Hub first, they check each other's walls):
```
python tools/district_build.py agora && python tools/district_verify.py agora --map
python tools/forest_routes.py --design agora --start agora_entry --out agora_routes.json
godot --headless --path . -s tools/level_bake.gd ++ agora                            # -> scenes/level_agora/generated_agora.tscn
godot --headless --fixed-fps 60 --path . -s tools/forest_drive_test.gd ++ agora
```
Game systems (no level change needed) — run in **both modes** (Silly, Serious):
```
godot --headless --fixed-fps 60 --path . -s tools/systems_test.gd ++ silly    # catalog, crafting, save/load, sun, energy, docking, tools, house, hub, fights, vault, agora, cutscene, reboot
godot --headless --fixed-fps 60 --path . -s tools/systems_test.gd ++ serious  # the same in Serious (the old robot, no curse, grade, paint)
```
Tests write only `test_` save/settings files (never the player's own).
- `scenes/world.tscn` holds only fixed things (house + door + crates + parts,
  player, HouseCharger, environment, DayNight, story triggers, HUD) and
  instances `scenes/level/generated_level.tscn`, `scenes/level_hub/generated_hub.tscn`,
  `scenes/level_agora/generated_agora.tscn` and the Relay Vault.
- **Never hand-edit** `generated_*.tscn` or `scenes/level*/**/chunk_*.res` —
  rebuilt every bake. Change the design file or the tools.
- Design grammar shared by both: `nodes` (kind, pos, radius, `reward`,
  `behind: <blocker id>` = sealed until that blocker is cleared), `paths`
  (named nodes + free points), `blockers` (forest: brambles → Breakable "cut";
  district: `rubble` → Breakable "smash", `locked` → LockedGate with `key`),
  `chargers`, `scenes` (hand-made scenes; in the forest with a tree-exclusion
  `footprint`) and `solids` (verify-only boxes for their collision). The Hub adds
  `walls.segments` (2 m pieces: keep lengths multiples of 2), `buildings`,
  `collectibles`, `props`. The Agora adds `vines` blockers (Breakable "burn"),
  `neighbours`, `merge_walls`, `sealed_south`, `open_ground`, props with
  `"solid": true` and nodes with `"requires"` (see CLAUDE_NOTES.md).
- Generated props: `godot --headless --path . -s tools/crooked_house_build.gd`
  rebuilds the crooked house shell (`scenes/props/crooked_house/generated_*`);
  `tools/relay_vault_build.gd` rebuilds the Relay Vault's shell from
  `level_design/relay_vault_design.json` (`scenes/level_vault/generated_*`);
  `tools/item_models_bake.gd` rebuilds every Catalog item's pickup model
  (`scenes/props/items/<id>.res`) — run it after adding an item (and give the
  item a recipe in the tool's `_build`; systems_test fails an item without one).
- Tunable by hand (kept across rebuilds): `materials/terrain_painterly.tres`
  (terrain look), `materials/leaves_*.tres` (leaf material).
- The spreadsheet pipeline is retired (`tools/legacy_sheet/`, don't run it).

## Verify — "the bake said OK" is not verification
- Always run the verifier **and** the headless drive test after a build, and
  `tools/systems_test.gd` after any script change. The 2D check approximates
  shapes; only real physics caught ruin pieces blocking paths, and the tests
  caught every regression in sprint 1.
- Check slopes both ways (robot climbs ≤ 45°; nothing may trap the player).
  The hill's north face is 37° after the Hub's flat pad; keep it under 40°.
- Inspect saved output for real data. **Never use MultiMesh in a headless
  bake** — Godot's headless renderer drops MultiMesh data, so the batches save
  empty (this made the background invisible and likely hung the owner's GPU).
  Use merged chunk meshes (see `_build_merged` in `tools/level_bake.gd`).
- GDScript: explicit types for anything from Variant-returning built-ins
  (`lerp`, `clamp`, `Array.filter`…) — inferred `:=` fails as an error.
  `_set`, `_get`, `_ready`… are reserved Object/Node virtuals: never name your
  own methods that way (a parse error there silently breaks every script that
  references the autoload).
- Headless `-s` scripts: the script compiles **before** autoload names exist
  (fetch them with `root.get_node("Game")`), `_initialize()` runs **before**
  the root joins the tree (`await process_frame` first), and a new `class_name`
  needs the editor import pass (`godot --headless --editor --path . --quit`)
  before other scripts can see it. Put a watchdog timer in long tests: a script
  error inside a coroutine otherwise hangs the run and its buffered output is
  lost when it is killed (`stdbuf -oL godot …` keeps it).
- `--fixed-fps 60` on any physics test: without it headless Godot still paces
  physics to the wall clock (7 min for 20 routes); with it, ~10 s, same result.
- Headless proves logic and collision, never looks or frame rate. The owner
  measures with F4 and reports; read `playtest/perf.md`.

## Current state (2026-10-02, sprint 4 — Silly and Serious, awaiting the owner's playtest)
The owner's redesign: **two games on one engine** (like Breath of the Wild and
Tears of the Kingdom). **Silly** (kids: Angry Zombie + tiny curse, wobbly
robot, toy paint, synthesized sounds) and **Serious** (adults: the old zombie
robot, darker grade, worn metal, no curse). Picked on the main menu; one save
and one difficulty per mode. Everything mode-specific asks `Game.silly()` /
`Game.serious()` — see `CLAUDE_NOTES.md` → Architecture. Built and headlessly
verified in both modes on `claude/sync-local-fixes-b85lpn`. **Next session:
start at `TODO.md` → "Start here"** (pending: the owner's playtest, then
the save_70–81 items).

### Sprint 2 (2026-09-28)
Sprint 2 (for the owner's six-year-old son) is built on
`claude/sync-local-fixes-b85lpn` and headlessly verified, not yet played:
Easy/Medium/Hard, the crooked house + Angry Zombie + tiny curse, real part
models, turn-based timing combat + the Hill Sentry, laser, charger upgrades +
solar HUD, the opening cutscene, the Relay Vault + Pythia + hover pack, the
Agora + fabricator. `TODO.md` has a playtest note per phase.
Its playtest questions are in `playtest/sprint2_feedback.md`.

### Sprint 1 (2026-09-27)
The vertical slice is built and headlessly verified, not yet played by the
owner: opening menu → wake at the house charger → find the hammer head and
actuator arm, build the Smasher (Tab, craft anywhere) → smash the door →
forest (2,743 trees, 6 parts at dead ends, chargers in the Dry Clearing and
behind the brambles) → build the Cutter, clear the brambles → hill → **the Hub**
(walled gate district: rubble → gate key → iron gate → relay card → relay tower
door; unlocking it ends the slice). Energy drains, chargers fill from the sun
(8-minute day), docking autosaves ("consciousness copied"), zero energy reboots
you at the last charger next morning. Story beats are placeholders (Greek myth
touchstone). **Performance is unmeasured since the perf pass** (render scale
0.8, 2048 shadows, 30 m, LOD bias) — the owner measures perf_4/perf_5 with F4.
See `TODO.md` for the playtest checklist and the next sprint.
