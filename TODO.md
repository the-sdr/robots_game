# TODO — next session

Written 2026-09-27 before a reboot. Newest priorities first.

## 1. Performance (next) — forest runs 13–21 FPS, target 25 on the owner's laptop
- [x] Owner F4 round after the rebuild: perf_3–perf_7 (table in `CLAUDE_NOTES.md` → Performance).
- [ ] Suggestions awaiting the owner's go-ahead (details in `CLAUDE_NOTES.md`):
      1. 3D render scale ~0.75–0.8, 2. simpler trees sooner (LOD bias / interior LOD 2),
      3. sun shadows 30 m, 4. only if needed: thinner pine leaf cards / sparser pines.
- [ ] Then the owner re-measures perf_4 (pines, 10, −23, E) and perf_5 (stream by the Giant, −8, −44, W).

## 1b. Cloud handover
- [x] `CLAUDE.md` (rules + workflow), test scripts in `tools/`, `tools/cloud_setup.sh`, all committed.
- [ ] First cloud session: `bash tools/cloud_setup.sh`, then `python3 tools/forest_verify.py`.

## 2. Known placeholders
- Fallen Giant (primitive machine), Ruin Fragment (medieval kit pieces), brambles
  (bushes + invisible box), collectibles (spinning gears, no inventory).
- Brambles: future gameplay — craft a cutter to open the stream's east end.

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
