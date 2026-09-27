# TODO — next session

Written 2026-09-27 before a reboot. Newest priorities first.

## 1. Graphics stability — resolved
- [x] Owner had a black screen and major slowdowns running the game on Forward+.
      Windows event log showed no driver crash/reset (clean restart only).
      **Switched back to the Mobile renderer** (`renderer/rendering_method="mobile"`).
      Forward+ can be revisited later (e.g. for volumetric fog) — test carefully,
      first run on a new renderer can sit on a black window while shaders compile.

## 2. Uncommitted work (on disk, safe across reboot)
- [ ] Renderer: back on Mobile (Android setting stays Mobile too).
- [ ] Terrain colour fix (`vertex_color_is_srgb`) + re-bake.
- [ ] FPS on the F2 overlay, FPS in F3 saves, **F4** 5-second performance log (`playtest/perf.md`).
- [ ] Performance pass: 876 interior trees batched (collision kept), LOD bias 0.4,
      sun shadows 2 cascades / 50 m, no shadows on interior/background trees.
- [ ] Notes/memory rules from today. → Commit + push.

## 3. Measure performance (owner, F4)
- [ ] Hill crest (0, −57) looking **south** over the forest (before: ~80–88 ms, ≈11 FPS).
- [ ] Hill crest looking **north** at the city (before: ~40 ms, ≈25 FPS).
- [ ] A spot on the maze path. Then tell Claude "logged".

## 4. Textures
- [ ] Owner is collecting more Poly Haven sets in `C:\projects\Global_assets\polyhaven`.
      Current: forest_ground_06 (base under trees), dirt_floor (path),
      brown_mud_leaves_01 (path edges / wet dips), roots (around trunks).
- [ ] Still wanted: mossy/meadow ground for the hill + city; rock for steep slopes.
- [ ] Approve: Claude extracts from the zips into `assets/polyhaven/`, converting
      colour/ARM/displacement to JPG and keeping normals PNG (~35 MB/set instead of 70).
- [ ] Terrain shader with painterly stylisation sliders (colour banding, palette
      remap, detail softening, optional brush pattern).
- [ ] New "Ground" sheet in the level map (G grass, D dirt, M mud, L leaves) +
      automatic rules (path → dirt/leaves, slopes → dirt/rock, under trees → litter).

## 5. Look and feel
- [ ] Grass cards: batched in chunks, wind sway, colour taken from the ground below.
- [ ] Revamp tree models — current forest looks too homogeneous; consider the
      painterly-canopy technique (leaf cards + sphere-like shading).
- [ ] Colour grade / post effects once the above exist (watch integrated-GPU cost).

## 6. Pipeline / tech
- [ ] Name trees by cell (e.g. `Tree_-9_-21`) so names survive rebuilds — needed
      before saved games or cuttable trees.
- [ ] Top-down level image for Claude to check layouts — needs a rendered (windowed)
      run, so only with the owner's permission each time.

## 7. Owner decisions (vision)
- [ ] Which trees can be cut / smashed (tool-gated? dead trees only?).
- [ ] Scope: aim for a ~20-minute vertical slice first (areas 1–3, energy loop, one tool, one craft)?
- [ ] Zombies vs. corrupted machines / overgrowth creatures.
- [ ] Energy/solar charging as the core loop?
- [ ] Confirm the coordinate language works → Claude adds it to `CLAUDE_NOTES.md`.
