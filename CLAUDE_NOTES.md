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

## Session log

Newest first. Session ID links follow the
`https://claude.ai/code/session_...` format.

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
