# Claude Notes

Working notes for AI-assisted sessions on this project. Update this as we go
— it's collaboration history and hard-won lessons, not game design (that's
`PROJECT_VISION.md`).

## Architecture

- **Scene structure**: `scenes/world.tscn` is the main scene. Reusable
  objects (player, shed, house, props) are separate scene files instanced
  into it, not built inline.
- **Input**: fully routed through Godot's Input Map (`project.godot`
  `[input]` section) — named actions (`move_forward`, `jump`, `zoom_in`,
  etc.), each bound to keyboard *and* gamepad equivalents. Scripts never
  check raw keys. This was a deliberate early investment specifically so
  gamepad/mobile-gesture support later only needs new event bindings on the
  same action names, not script changes.
- **Debug keys** (all Input Map actions): F2 coordinate overlay (with FPS),
  F3 save position to `playtest/saves.md` (save_1, ...), F4 5-second
  performance log to `playtest/perf.md` (perf_1, ...: frame times, draw
  calls, triangles), F7 god mode — double-tap Space to fly (no collision),
  hold Space up / Shift down. Owner measures performance with F4 in their
  own playtests; Claude reads the file (no windowed runs by Claude).
- **Branch `wip/perf-pass` is superseded** (its MultiMesh batching saved empty;
  the forest rebuild does merged chunks instead) (batched
  interior trees, LOD bias 0.4, 2-cascade 50 m shadows). After it was baked
  the owner's Intel UHD laptop hung on every load (whole screen black,
  D3D12 "device removed" 0x887a0005 in the Godot log, also hung on Vulkan).
  `main` runs the pre-pass level. Reintroduce its pieces one at a time,
  with the owner testing each.
- **Camera**: third-person, `CameraRig` (yaw) → `CameraArm` (pitch) →
  `Camera3D`, with distance computed each frame via a **sphere shape-cast**
  (not a raycast — see Lessons) against real collision, smoothed with
  `lerp()` rather than snapping instantly.
- **Interior collision**: hand-built invisible collision shells (simple
  `BoxShape3D` walls + ceiling), sized from a *measured* bounding box, not
  trusted to auto-generate from imported meshes. See Lessons.
- **Reusable collision wrappers**: `scripts/solid_tree.gd` /
  `solid_rock.gd` + matching `scenes/props/solid_*.tscn` — a `StaticBody3D`
  that loads a model by exported path and adds simple capsule/sphere
  collision at runtime. Used for every tree/rock placement so collision is
  never forgotten and never depends on the source mesh's own geometry.
  Tree trunk radii are a measured per-model table (`TRUNKS` in
  `solid_tree.gd`, mirrored in `tools/level_common.py`).
- **Level pipeline — `level_design/forest_design.json` is the source of truth**
  (areas, paths, nodes, landmarks, blockers, terrain features, per-area tree
  mix / leaf palette / ground / undergrowth). Steps:
  `python tools/forest_map.py` (review map, owner approves) →
  `python tools/forest_build.py` (→ `level_design/build/level.json`) →
  `python tools/forest_verify.py` (seal, reachability, "only ways north"
  gate test, brambles block) → headless `tools/level_bake.gd` (→
  `scenes/level/generated_level.tscn` + chunk meshes) → headless drive tests
  to every design node. `python tools/forest_map.py --built` draws what was
  actually placed — use it as the shared reference in playtests.
  `world.tscn` only holds fixed things (house, player, charger, environment).
  **Never hand-edit `generated_level.tscn` or the chunk folders.** The old
  spreadsheet pipeline is retired in `tools/legacy_sheet/`.
- **Performance setup**: trees within 3 m of a path are individual
  `solid_tree` nodes (shadows, future interaction); all other trees are
  merged into chunk meshes (`InteriorForestNear` LOD 1 / `Far` LOD 2) with a
  trunk capsule each for collision; undergrowth and background are merged
  chunks too. Sun shadows: 2 cascades, 50 m. Robot speed 3 m/s.
- **Game systems (sprint 1)**, all autoloads in `scripts/game/`:
  `Catalog` (items, tools, recipes as plain dictionaries — a new tool is a
  Catalog entry), `Clock` (8-minute day; `sun_direction()` shared by lighting
  and solar chargers), `Energy` (battery: idle/drive drain, `spend`, `depleted`),
  `Game` (flags, inventory, tools, crafting, one JSON autosave at
  `user://save.json`, written when the robot docks), `Story` (beats shown
  once per save). `scripts/world.gd` starts/loads the game and handles the
  shutdown → reboot-at-last-charger loop; `scripts/day_night.gd` drives the
  one directional light as sun/moon plus sky, fog, ambient, cloud tint.
- **Settings (sprint 2)**: autoload `Settings` (`scripts/game/settings.gd`) holds
  preferences that are not progress, in `user://settings.cfg` (not the save).
  Difficulty Easy/Medium/Hard changes **fights only** (`Settings.tuning()`:
  timing ring speed, good/perfect windows, miss damage, dodge window, "NOW!"
  cue, enemy damage/health, whether the tutorial can be lost). Easy must stay
  winnable by a six-year-old (vision, "Who it's for"). One cycling button
  (`scripts/ui/difficulty_button.gd`) on the main menu and the pause menu.
- **Interaction**: `Interactable` (Area3D + prompt; `Inspectable` plays a
  beat) found by the player's `InteractProbe`; E uses the nearest. HUD group
  "hud": `show_notice`, `show_message(title, text)`, `set_prompt`.
- **Tools**: `scripts/tools/tool_rig.gd` on the right arm builds a placeholder
  head per tool, swings on click, applies `effect` to the nearest `Breakable`
  in front (sphere query). `Breakable` (StaticBody3D: effects, health, drops,
  flag) and `LockedGate` (key item, flag, rises when opened) are the two
  obstacle components; both stay cleared across saves via flags. Pickups
  (`collectible_part.gd`) add Catalog items and remember being taken.
- **Hub pipeline**: `tools/district_build.py` + `district_verify.py` +
  `forest_routes.py --design hub` + `level_bake.gd ++ hub` + drive test
  `++ hub`. A district has no terrain: the forest design carries a `flat`
  feature (`hub pad`, blend 14 m) for it, and the forest's `open_north` tree
  rows seal it. Walls are 2 m brick pieces along design segments; buildings
  are the city kit with measured footprints (`level_design/build/assets.json`,
  `tools/level_measure_assets.gd`).
- **`house_setup.gd`-style fixup scripts**: attached to imported building
  models to override materials (imported FBX materials can silently fail)
  and force double-sided rendering — a repeatable pattern for any future
  imported structure with the same issue.

## Performance (owner's Intel UHD laptop, Mobile renderer, target 25 FPS)

Owner F4 captures after the forest rebuild (2026-09-27, `playtest/perf.md`):

| F4 | Where (camera) | ms | FPS | triangles | draws |
|---|---|---|---|---|---|
| perf_3 | garden gate (0, −11), N up the path | 48.5 | 21 | 5.3M | 858 |
| perf_4 | pine path (10, −23), E into the pines | 69.0 | 14 | 5.3M | 916 |
| perf_5 | stream bed by the Giant (−8, −44), W along the stream | 76.7 | 13 | 4.8M | 619 |
| perf_6 | near the Dry Clearing (21, −51), N | 47.1 | 21 | 4.2M | 748 |
| perf_7 | hill crest (0, −85), NW to the city | 19.6 | 51 | 1.7M | 116 |

Reading: triangles alone don't explain it — perf_3 and perf_4 draw the same
5.3M, but the pine view is 40 % slower, and the stream view is slowest with
fewer triangles. Both are full of overlapping alpha-cutout leaf cards (pine
needles; canopies stacked down a long corridor) → per-pixel overdraw, which
integrated GPUs handle worst.

**Suggestions (NOT done yet — owner to approve, then re-measure perf_4/perf_5):**
1. Render 3D at ~75–80 % resolution and upscale (`rendering/scaling_3d/scale`)
   — roughly halves per-pixel cost, the overdraw problem; painterly look hides
   the softness. Probably the biggest single win; one project setting.
2. Simpler trees sooner: LOD bias ~0.5 on individual trees (`solid_tree.gd`),
   near-interior chunks at LOD 2 (`forest_build.py`, `o["lod"]`). ~30–40 % fewer
   triangles.
3. Shorter sun shadows: `directional_shadow_max_distance` 50 → 30 m
   (`scenes/world.tscn`) — shadow casters are drawn twice.
4. Only if still short: thin the pines' leaf cards, or slightly sparser pines
   along paths.

## Sprint 1 — vertical slice (decided with the owner, 2026-09-27)

Goal: ~20 minutes of complete play, wake to the Hub. Systems built broad and
independent so they land in any order. Owner decisions:
- Opening menu (Continue / New Game / Quit). One autosave, written at every dock.
- Getting out of the house is an activity: find smasher parts, attach the
  smasher, break the door.
- Energy loop is core. 8-minute day. Chargers have capacity and refill from
  sunlight with real solar-panel physics (sun angle); upgrades later. Reaching
  the Hub in one go is not guaranteed; going back to a charger is the game.
  Zero energy: shutdown, reboot at the last charger next morning, inventory kept.
- Tools: dozens eventually (smash, cut, hover/fly, lasers, matter generation),
  so the framework is data-driven; the slice builds Smasher and Cutter.
- Inventory + crafting: simple, Subnautica-inspired; **no benches, craft
  anywhere** (the robot self-crafts).
- Area 3 is **the Hub**: parts unlock to reach further dungeons; one unlock +
  dungeon ≈ one sprint. At least 20 interesting areas in the long run.
- Combat: robot vs robot later (Stick of Truth / Clair Obscur as references).
  The zombie is an Easter egg (annoy it → shrunk for two days). Not in the slice.
- Narrative: placeholder text now, Greek mythology as the touchstone. The owner
  wants a diegetic reason robot consciousness can be copied at a charger (the
  save). Story decision pending.
- Assets: the sandbox reaches only GitHub; new packs come via the owner's push.
- Performance: i3 target is a goal, not a hard limit (a Surface Pro may arrive).
- The Fallen Giant has no good assets yet; keep it as a placeholder story object.

## Working from the cloud (Claude Code on the web)
- Setup once: `bash tools/cloud_setup.sh`. Loop: cloud builds/verifies/pushes →
  owner pulls, playtests locally, sends F4/F3 results (or pushes
  `playtest/*.md`, now tracked) → cloud reads them.
- Local-only (not reachable from the cloud): the Godot program on the laptop,
  Godot's run logs (`%APPDATA%\Godotpp_userdata\Robots_game_godotfile\logs\`
  — a local session has standing read-only access), `C:\projects\Global_assets`
  (downloaded asset zips — must be committed into the project to be usable),
  Claude's local memory (its rules are copied into `CLAUDE.md`).
- **Chunk meshes are committed** (~90 MB in `scenes/level/*/`) so every
  checkout has a working level even where Godot can't run. They're
  deterministic, so an alternative is to git-ignore them and bake after each
  pull; revisit if the repository grows too fast.

## Lessons learned / do not repeat

- **`PROJECT_VISION.md` belongs to the project owner.** Never edit it
  without explicit approval — propose the change in chat (quote the exact
  wording) and wait for a yes. Established 2026-09-27; the last
  Claude-authored version is the one committed that day.
- **Always ask before copying external assets into the project directory.**
- **Always state clearly when running an executable outside the project
  folder** (the Godot binary lives at `C:\Godot_v4.7.2-stable_win64.exe\`).
- **Never trust auto-generated collision on imported meshes** for anything
  concave or with an intentional opening (a doorway). Tried trimesh
  (one-directional — walk out but not back in) and multiple-convex
  decomposition (can seal openings that should stay open) on the same
  house; both failed differently. Simple hand-built primitive collision,
  sized from measured real dimensions, is the reliable approach — same
  lesson applies to walls, not just buildings.
- **Measure before placing.** Before hand-placing anything from a new
  asset pack, instance one sample, walk its `MeshInstance3D` tree, compute
  a world-space AABB, and print it via a throwaway debug scene/script run
  headless. Caught a 2.5x scale-off building early this way; a second pack
  needed no correction at all — you can't tell which without measuring.
- **Every interior needs a *sealed* collision shell — walls AND a
  ceiling.** Walls alone stop the player but not a camera that pitches up;
  it'll float out through the open top into a god's-eye view.
- **Camera wall-avoidance needs a shape-cast, not a thin raycast.** A
  zero-width ray can find a clear line through a doorway gap at a grazing
  angle where a real camera "lens" shouldn't fit — this let the camera
  escape outside at "a specific angle." Switched to a small sphere cast
  (`PhysicsShapeQueryParameters3D` + `cast_motion`), which has real width
  and can't thread the same gap.
- **GDScript strict-typing + `:=` type inference fails on Variant-returning
  built-ins** (`lerp()`, `clamp()`) — "warning treated as error" at
  runtime. Use explicit `var x: float = ...` for anything assigned from
  those, not inferred typing.
- **Headless verification catches real bugs, not just parse errors** —
  script logic (e.g. a scattering loop) actually executes during
  `--headless --quit`, so wrong method names/types surface even without a
  visual check. Still can't catch visual/geometric correctness — that
  needs the user's eyes, every time.
- **New asset files need an editor import pass** (`--headless --editor
  --path . --quit`), not just a plain run, before they're usable —
  otherwise you get stale-UID warnings or missing-resource errors.
- **Keep scale grounded to what was actually asked.** Built an entire
  ~160m corridor labyrinth + distant city when "the immediate 100-200
  square meters surrounding the shed" was explicit. When a size is stated,
  treat it literally before designing anything.
- **The maze *is* the forest, not a separate structure next to it** — when
  asked for a labyrinth of overgrowth, the trees themselves need to form
  the maze walls (dense, sealed, one path through), with ruins as curated
  accents woven in — not a distinct walled-corridor area built with
  ancient-wall assets alongside plain garden trees elsewhere.
- **"Level design" means real, saved nodes — runtime procedural generation
  is not an acceptable substitute even for background-density content,**
  once explicitly rejected. Resolution that satisfies both speed and
  editability: write the placement logic once, run it, print each
  instance's transform, convert that into real `.tscn` node blocks, then
  delete the runtime script. Same generation speed, permanent/editable
  result.
- **When given a relative density/scale instruction** ("half the density,
  10x the area"), compute it explicitly as count/area and show the math —
  don't eyeball a new spacing value and hope.
- **Before bulk-replacing a line range in a scene file** (e.g. via `sed`),
  verify the *exact* boundaries first. Assumed a block was "just the
  generated trees" and it also contained 14 hand-placed nodes (gate,
  ruins, undergrowth) sitting in the same range — nearly lost them.
  Recovered via `git show <last-commit>:<path>`. Check git diff after any
  large mechanical file surgery, not just headless load success.
- **A structure needs forest/walls on *every* side to read as enclosed**,
  not just the side facing the path — the other sides being open ground is
  exactly as bad as no forest at all, even if the "maze" side is dense.

- **A generic collision size is a guess — measure it against the mesh.**
  Trees used one 0.35 m capsule; every real trunk was 0.50–1.15 m, so the
  robot drove into bark and the "maze" only worked because of it. Measure
  per model at the height the player actually touches.
- **A 2D "is it sealed?" check isn't enough on its own** — also drive the
  real CharacterBody into the geometry headlessly (routes to every goal,
  sideways rams off the path). Teleporting a body *into* a collider makes
  Jolt push it out through thin floors: keep ground collision thick.
- **`ResourceSaver` flags don't make a PackedScene reference a resource
  externally** — reload the saved file (`ResourceLoader.load`) and assign
  that copy, or the data gets embedded (6.7 MB scene instead of 0.4 MB).
- **Blending sparse height anchors (harmonic fill) spikes at lone
  anchors** — use several anchors to shape a feature, plus a light blur.

- **Never run the game (a visible Godot window) without explicit
  permission first, and never create screenshots without saying so.**
  On 2026-09-27 Claude launched the game windowed ~9 times for
  screenshots/frame timing without asking; it took over the owner's
  machine (window, mouse capture, GPU) while they were working. Work only
  inside the project folder unless something else is explicitly agreed
  (Claude's session scratch folder is approved). Headless Godot runs are
  fine without asking, but say each time that one is running (resource draw).
  (Technique, only with permission: a non-headless run that saves
  `get_viewport().get_texture().get_image()` to PNG gives real screenshots
  and frame times.)
- **Vertex colours need `vertex_color_is_srgb = true`** when they're
  ordinary picked colours; otherwise they're read as linear and wash out
  (the terrain rendered pale teal instead of green).
- **Dev machine GPU is Intel UHD (integrated).** Measured 2026-09-27: hill
  view looking over the forest ~80–88 ms/frame (~12 FPS), city view ~40 ms,
  same on Forward+ and Mobile — the cost is tree geometry, not the renderer.
  Forward+ was tried the same day and reverted: the owner got a black
  window and major slowdowns playing on it. **Renderer is Mobile.** Don't
  switch renderers again without the owner agreeing to test it.

- **Never use MultiMesh in a headless bake.** Godot's headless stand-in
  renderer keeps no MultiMesh data, so the saved batches are silently
  empty (`instance_count` set, no `buffer`). The background forest was
  invisible from day one and the parked perf pass's batched interior trees
  were empty too — a plausible cause of the owner's GPU hangs. Background
  trees are now merged into ordinary chunk meshes (LOD 2), which headless
  saves correctly. Check saved scenes for real data, not just "bake OK".

- **2D map checks approximate shapes — always also drive the real physics.**
  The seal check modelled ruin pieces as small circles and passed, but the
  actual box collision blocked two paths; only the headless drive test to
  every node caught it. Also check slopes both ways: a 52° drop into the
  city would have let the player slide down and never climb back.

- **Headless `-s` scripts and autoloads (sprint 1):** the main-loop script is
  compiled before the autoload names are registered, so `Game`/`Clock` are
  "Identifier not found" there — fetch them with `root.get_node("Game")` (scene
  scripts loaded later see them normally). `_initialize()` runs before the root
  joins the tree: `await process_frame` before touching `get_tree()`. A script
  error inside an awaiting coroutine never reaches `quit()` and the run hangs;
  `systems_test.gd` has a watchdog timer for that. Godot's stdout is fully
  buffered when piped, so a killed run loses its output — `stdbuf -oL`.
- **A new `class_name` is invisible until the editor import pass** has
  rebuilt `.godot/global_script_class_cache.cfg` (`--headless --editor --quit`).
- **`_set` is a reserved virtual.** Naming a method `_set(value)` is a parse
  error that takes the autoload down with it; the only visible symptom was
  "Identifier not found: Game" elsewhere.
- **Headless still runs in real time** unless `--fixed-fps` is given (the drive
  test took 7 minutes for 20 routes; 11 s with `--fixed-fps 60`).
- **Route drivers need dense points.** The drive test allows 200 frames per
  point; a 15 m straight leg between two named nodes timed out and read as
  "stuck" with no collision at all. Routes are now densified to ≤ 3 m steps.
- **Flattening terrain next to a hill steepens the hill.** The Hub's flat pad
  with the default 6 m blend made the hill's north face 47°; a 14 m blend
  brings it to 37°. Always re-run the hill<->city drive check after terrain edits.
- **Pickups within ~1 m of a route get collected by the drive test** (the
  hammer head by the door was picked up on the way to the door); place test
  items on nodes deliberately, and keep story-relevant parts off the driven line.
- **Coordinates inside the house:** the door wall is the *north* wall
  (z −7.74); the charger corner (−1.6, −3.2) is the south-west corner. "Into the
  room" from there is (+X, −Z).

- **Apple exports:** universal/arm64 macOS exports refuse to run unless
  `rendering/textures/vram_compression/import_etc2_astc` is on (one-time
  re-import of every texture). Export templates live outside the project
  (`~/.local/share/godot/export_templates/4.7.2.stable`, 2 GB) and must be
  downloaded per machine. The cloud can build and verify the `.app` (boot the
  `.pck` with `--main-pack`), but signing/upload is Mac-only: see
  `docs/apple_release.md`. "Beta" apps go to TestFlight, not the App Store.

- **Checking an exported build in the cloud:** `godot --headless --main-pack
  "<exe or pck>" -s <script>` loads the embedded data, but run it from an empty
  folder: from the project folder, `res://` falls back to the real files and
  hides what the export left out. Feature-tag overrides (`config/name.<tag>`)
  apply only through `ProjectSettings.get_setting_with_override()`; the Windows
  preset sets the custom tag `robots_beta` so the editor keeps its own name
  and user folder. See `docs/windows_release.md`.

- **The house model (`1Story.fbx`) has its own door.** A slab in the north
  doorway, just inside `HouseDoor` (z −7.74), hid the smashable door from
  inside: smashing looked like nothing happened and the "door" stayed after
  it broke. `scripts/house_setup.gd` cuts it out of the mesh on load
  (`BUILT_IN_DOOR` box; systems_test checks the count). Imported buildings
  can carry doors, glass or props — check the mesh before layering gameplay
  objects over them.
- **Tool hits use a box from the robot out to the tool's reach.** The old ball
  centred ahead missed anything the robot was pressed against (a door at
  arm's length took no hits). The house test now swings from flush (z −7.2).
- **Never commit `.import` files or `project.godot` from the Surface.** The
  ARM64 Windows editor re-imports textures as ETC2/ASTC only and drops the
  desktop `s3tc` format the x64 exe needs; it also reorders `project.godot`.
  Commit those only from the laptop or the cloud. A deliberate hand edit to
  `project.godot` is fine: `git checkout -- project.godot` first, edit, and
  check `git diff` shows only your lines.
- **Alt+Enter crashes on the Surface under Vulkan** (exe and native ARM64
  editor run alike: exception 0x87a in KERNELBASE.dll, empty Godot log).
  Qualcomm's Vulkan driver handles Alt+Enter itself before Godot sees it, so
  no game code can stop it. With `--rendering-driver d3d12` it survives
  (Alt+Enter just does nothing). The game's own toggle is F11 / Alt+Enter
  (`toggle_fullscreen`, handled in `game.gd`, borderless fullscreen). The
  owner chose "F11 only" for now; a native ARM64 exe on D3D12 for the Surface
  is the parked option. Note: `--rendering-driver d3d12` alone also switches
  the renderer to Forward+; add `--rendering-method mobile` to keep Mobile.

## Session log

Newest first. Session ID links follow the
`https://claude.ai/code/session_...` format.

- **2026-09-28 (local, Surface Pro)** — first session on the owner's second
  machine (ARM64, Adreno X1-45; native ARM64 Godot 4.7.2). Merged the cloud
  sprint branch to `main` (PR #1). Fixed the house door: cut the model's
  built-in door slab, box-shaped tool hits. perf_10 (12 FPS, door looking
  north) / perf_11 (36 FPS, doorway looking into the house) are Surface
  captures. Released v0.1.1-beta.

- **2026-09-27 (cloud, sprint 1)** — `session_01XVn1FgoerKkQG5JNTTccvE`.
  First cloud session: Godot 4.7.2 runs headless here; setup script fixed;
  `--fixed-fps` for tests. Vision: Area 3 → the Hub. Perf pass 1 (unmeasured).
  Built the vertical slice broad: menu, save/load, clock + day/night + solar
  chargers, energy loop with reboot, interaction, HUD, tools (Smasher, Cutter)
  + Breakables, inventory/crafting anywhere, house sequence (parts → smasher →
  door), forest content (cuttable brambles, hidden pocket charger, clearing
  charger, giant inspect), story beats, the Hub district with its own
  pipeline (rubble → key → gate → card → tower door), look pass. Three headless
  tests green (22 + 7 routes, systems). Awaiting the owner's playtest.

- **2026-09-27 (later)** — Forest rebuilt from a design file: 72 × 90 m,
  seven areas (garden, old wood, pines, stream bed, dry clearing, ruin grove,
  thinning edge), the Fallen Giant (placeholder machine blocking the way
  north), Ruin Fragment, brambles at the stream's east end, 6 collectibles,
  textured painterly terrain, per-tree leaf colours, 2,273 trees (620
  individual). Laptop GPU hangs traced to empty MultiMesh batches. Robot 3 m/s.

- **2026-09-27** — Johnny Five–style modular player robot; F2 coordinate
  overlay, F3 position saves, F7 god mode/fly. Fixed trees through the
  house walls and trees you could drive through (measured trunk collision).
  Vision doc handed over to the owner (owner-controlled from here). Built
  the spreadsheet level pipeline: owner drew the path; generated sealed
  forest (1,125 trees), terrain with real slopes and a ~5.4 m hill, dead-end
  collectibles, endless background forest (750 batched trees) and depth fog.

- **2026-09-26** — `session_01EY1wXvCYc4QNCvTMF7y3d9`. Full first working
  day: player/camera/movement systems (Input Map, sphere-cast camera
  collision), first house (placeholder box, then a real Quaternius
  building with measured collision + material fixes), asset gallery tool
  for browsing Quaternius packs in-engine, imported Nature/Medieval
  Village/Downtown City packs. Area 2 (garden/forest maze) went through
  several full rebuilds based on playtesting: too sparse → corridor
  labyrinth built way oversized (~160m, wrong approach entirely) →
  corrected to a compact forest-is-the-maze design → too sparse again →
  runtime-procedural mass forest (rejected, wanted real level design) →
  baked into real nodes, tuned down twice, finally extended to surround
  the house on every side but the front path (789 trees, all real nodes).
  Set up `README.md`/`PROJECT_VISION.md`/`CLAUDE_NOTES.md`. Committed and
  pushed (`1b20c29`).

## Conventions

- Verify every scene/script change with a clean headless Godot run before
  reporting it done. This has caught real, otherwise-invisible errors
  repeatedly.
- Prefer curated, hand-placed content for anything narrative-relevant.
  Deterministic formulas (a tree ring, a dense grid minus a path) count as
  curated; true randomness does not, except for background atmosphere.
- Keep pre-tool-call narration to one short, plain sentence about the
  immediate next action — no bundled "I'll do X, then Y, then Z."

## User preferences

- Not a professional developer — learning Godot's editor GUI alongside
  this project; explanations of *why*, not just *what*, are welcome.
- Prefers fast iteration with quick, testable steps over long upfront
  theorizing — but wants real risk (scale, collision, destructive changes)
  flagged plainly before committing to it, not discovered after the fact.
- Direct, terse feedback style; corrections should be taken as precise
  course-corrections, not softened or over-explained back.
