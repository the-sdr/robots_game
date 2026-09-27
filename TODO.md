# TODO — next session

Written 2026-09-27 before a reboot. Newest priorities first.

## 1. Graphics stability (in progress)
- [x] Forward+ reverted to **Mobile**; graphics API now **Vulkan** (Godot default; log confirms it's used).
- [x] Windows event log: no driver crash logged. Godot log (13:56): D3D12 "device removed" then crash.
- [x] Every load since the performance pass (baked 13:45) hung right after GPU start, on D3D12 and Vulkan.
      → Performance pass **parked on branch `wip/perf-pass`**; `main` has the last working level
      plus FPS/F4 logging, Mobile, terrain colour fix.
- [ ] Owner tests: does the game load now?
      - Yes → reintroduce the pass one piece at a time (shadow settings, LOD bias, batching), owner tests each.
      - No → the level itself is too heavy for this laptop even as before → reduce trees/background.
- [ ] Optional: clear the editor's "reopen scenes" list (in `.godot/editor/`) so the editor opens empty.

## 2. Commit
- [ ] Once loading works: commit `main` (FPS/F4 logging, Mobile, terrain colour fix, notes, TODO) and push.

## 2b. Done since (uncommitted until tested)
- [x] Textured painterly terrain: 4 Poly Haven layers, shader in `shaders/terrain_painterly.gdshader`,
      tunable material `materials/terrain_painterly.tres`. perf_1 (hill, SW): 66.8 ms / 15 FPS, 16.3M tris.
- [x] Tree variety: 12 models (added CommonTree_2/4, Pine_1/2/5, TwistedTree_5), weighted mix
      (twisted ~9 %), per-tree leaf colours (mostly greens, autumn accents, evergreen pines).
- [x] **Bug fixed:** background forest was never drawn (MultiMesh saves empty in headless bakes).
      Now merged chunk meshes, 785k triangles.
- [ ] Owner tests: loads? looks? F4 at the perf_1 spot (hill crest, looking SW).

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
