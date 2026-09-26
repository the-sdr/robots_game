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
