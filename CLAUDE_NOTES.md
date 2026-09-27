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
- **Performance pass is PARKED on branch `wip/perf-pass`** (batched
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
- **Level pipeline — the spreadsheet is the source of truth.**
  `level_design/level_map.xlsx` (1 m cells, north up, headers = world X/Z)
  → `tools/level_generate_forest.py` (only when the path changes: writes
  the sealed checkerboard forest + dead-end collectibles into the sheet)
  → `tools/level_build.py` (sheet → `level_design/build/level.json`)
  → `tools/level_bake.gd` (Godot, headless → `scenes/level/generated_level.tscn`
  + terrain/background `.res`) → `tools/level_verify.py` (flood-fill seal
  check). `world.tscn` only holds fixed things (house, player, charger,
  environment) and instances the generated scene. **Never hand-edit
  `generated_level.tscn`** — it is overwritten on every bake; edit the sheet.
  `level_design/build/placements.json` keeps exact transforms of objects
  placed before, so rebuilds don't snap them to cell centres.
- **`house_setup.gd`-style fixup scripts**: attached to imported building
  models to override materials (imported FBX materials can silently fail)
  and force double-sided rendering — a repeatable pattern for any future
  imported structure with the same issue.

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

## Session log

Newest first. Session ID links follow the
`https://claude.ai/code/session_...` format.

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
