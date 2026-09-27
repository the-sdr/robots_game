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
7. **Communication style:** one short, plain sentence before each action about
   *that* action (no bundled "I'll do X, then Y, then Z"). Explain *why*, not
   just what. The owner's feedback is terse — treat it as a precise course
   correction, don't soften or over-explain it back. Flag real risks (scale,
   collision, destructive changes, performance) *before* acting. Report
   outcomes faithfully, including failures.
8. **Don't switch renderers** (`project.godot`) without the owner agreeing to
   test it. Renderer is **Mobile** (Forward+ hung the owner's laptop).
9. **Commit/push only when the owner asks.** End commit messages with the
   attribution line the environment provides.

## The owner's machine and targets
- Windows laptop, **Intel UHD integrated graphics**. Target **25 FPS** there.
- Godot 4.7.2 at `C:\Godot_v4.7.2-stable_win64.exe\` (local sessions only).
- In the cloud: run `bash tools/cloud_setup.sh` once (Python packages + Linux
  Godot for headless baking/tests). If Godot can't be downloaded, the Python
  tools still work; say so and let the owner bake locally.

## Shared language (proven in playtests — use it)
- Coordinates are **Godot world metres**: **X east (+), Z north (−)**, Y up.
  Compass: North = −Z, East = +X, South = +Z, West = −X; headings clockwise from North.
- In game: **F2** overlay (position, facing, camera heading, pitch, FPS),
  **F3** saves a position (`playtest/saves.md`: save_1, save_2…), **F4** logs a
  5-second performance sample (`playtest/perf.md`: perf_1…), **F7** god mode
  (double-tap Space to fly, Space up / Shift down, no collision).
- Talk about places as coordinates, save names, design node names
  (`fork`, `giant_ford`, `clearing`…) or area names, and check them against
  `level_design/maps/forest_map_v3_built.png` (everything actually placed,
  same grid as F2). Review issues at that level of reference.

## Level pipeline (source of truth: `level_design/forest_design.json`)
```
python tools/forest_map.py            # review map from the design (owner approves before building)
python tools/forest_build.py          # design -> level_design/build/level.json
python tools/forest_verify.py --map   # sealed? all places reachable? only ways north via ruin/clearing? brambles hold?
godot --headless --path . -s tools/level_bake.gd        # level.json -> scenes/level/ (generated scene + chunk meshes)
python tools/forest_routes.py         # drive routes to every design node
godot --headless --path . -s tools/forest_drive_test.gd  # real physics: all routes, collectibles, house, hill<->city
python tools/forest_map.py --built    # as-built map for the owner
```
- `scenes/world.tscn` holds only fixed things (house, player, charger,
  environment) and instances `scenes/level/generated_level.tscn`.
- **Never hand-edit** `generated_level.tscn` or `scenes/level/*/chunk_*.res` —
  rebuilt every bake. Change the design file or the tools.
- Tunable by hand (kept across rebuilds): `materials/terrain_painterly.tres`
  (terrain look), `materials/leaves_*.tres` (leaf material).
- The spreadsheet pipeline is retired (`tools/legacy_sheet/`, don't run it).

## Verify — "the bake said OK" is not verification
- Always run `forest_verify.py` **and** the headless drive test after a build.
  The 2D check approximates shapes; only real physics caught ruin pieces
  blocking paths.
- Check slopes both ways (robot climbs ≤ 45°; nothing may trap the player).
- Inspect saved output for real data. **Never use MultiMesh in a headless
  bake** — Godot's headless renderer drops MultiMesh data, so the batches save
  empty (this made the background invisible and likely hung the owner's GPU).
  Use merged chunk meshes (see `_build_merged` in `tools/level_bake.gd`).
- GDScript: explicit types for anything from Variant-returning built-ins
  (`lerp`, `clamp`, `Array.filter`…) — inferred `:=` fails as an error.
- Headless proves logic and collision, never looks or frame rate. The owner
  measures with F4 and reports; read `playtest/perf.md`.

## Current state (2026-09-27)
Area 2 forest rebuilt from the approved design: 72 × 90 m, seven areas,
the Fallen Giant (placeholder machine blocking the way north), Ruin Fragment,
brambles at the stream's east end, 6 collectibles, textured painterly terrain,
per-tree leaf colours, 2,273 trees. Owner: "layout is good, forest feels much
better". **Performance is the open problem** — 13–21 FPS in the forest, 51 on
the hill; see `CLAUDE_NOTES.md` → *Performance* for measurements and the
suggested next steps (not yet done).
