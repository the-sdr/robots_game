"""Build step 1 of 2: level_map.xlsx -> level_design/build/level.json.

Usage (from the project root):
    python tools/level_build.py
    <godot> --headless --path . -s tools/level_bake.gd      (step 2: writes the scene)

Every object in the Layout sheet becomes a placement sitting on the terrain
from the Height sheet. Objects that already existed keep their exact position
and rotation (the sheet only knows 1 m cells); new ones sit at the cell centre.
Also generates the unreachable background forest around the map.
"""
import json
import math
import os
import random
import re

import numpy as np

import level_common as lc
from level_generate_forest import route, FOREST_NORTH_EDGE

BUILD_DIR = os.path.join(lc.ROOT, "level_design", "build")
PLACEMENTS = os.path.join(BUILD_DIR, "placements.json")   # exact transforms from the last build
WORLD = os.path.join(lc.ROOT, "scenes", "world.tscn")

BACKGROUND_DEPTH = 55.0        # how far the background forest reaches beyond the map edge
BACKGROUND_SPACING = 4.5
BACKGROUND_SEED = 20260927
BACKGROUND_MODELS = [("CommonTree_1", 3), ("CommonTree_2", 3), ("CommonTree_3", 3), ("CommonTree_4", 3),
                     ("CommonTree_5", 3), ("Pine_1", 3), ("Pine_2", 3), ("Pine_5", 3), ("DeadTree_1", 1.5),
                     ("TwistedTree_2", 1), ("TwistedTree_4", 1), ("TwistedTree_5", 1)]
GROUND_RADIUS = {"wall": 1.0, "building": 0.0, "bush": 0.5, "rock": 1.0, "prop": 0.3,
                 "stone": 0.0, "collectible": 0.0}


def exact_transforms():
    """(code, cell_x, cell_z) -> (x, z, basis) for objects placed before."""
    if os.path.exists(PLACEMENTS):
        return {tuple(json.loads(k)): v for k, v in json.load(open(PLACEMENTS)).items()}
    # First build: take them from the hand-placed nodes in world.tscn.
    code_of = {asset: code for code, (asset, kind) in lc.CODES.items() if kind != "tree"}
    text = open(WORLD, encoding="utf-8").read()
    ext = {m.group(2): m.group(1) for m in re.finditer(
        r'\[ext_resource type="PackedScene"[^\]]*path="([^"]+)" id="([^"]+)"\]', text)}
    out = {}
    for blk in re.split(r"\n(?=\[node )", text):
        m = re.match(r'\[node name="[^"]+" parent="\.".*?instance=ExtResource\("([^"]+)"\)\]', blk)
        if not m:
            continue
        mp = re.search(r'model_path = "([^"]+)"', blk)
        asset = (mp.group(1) if mp else ext[m.group(1)]).split("/")[-1].rsplit(".", 1)[0]
        if asset not in code_of:
            continue
        tr = re.search(r"transform = Transform3D\(([^)]*)\)", blk)
        v = [float(n) for n in tr.group(1).split(",")] if tr else [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]
        out[(code_of[asset], round(v[9]), round(v[11]))] = [v[9], v[11], v[:9]]
    return out


def normal_at(grid, x, z):
    e = 0.5
    dx = (lc.height_at(grid, x + e, z) - lc.height_at(grid, x - e, z)) / (2 * e)
    dz = (lc.height_at(grid, x, z + e) - lc.height_at(grid, x, z - e)) / (2 * e)
    n = np.array([-dx, 1.0, -dz])
    return n / np.linalg.norm(n)


def tilt_basis(basis, normal):
    """Rotate a row-major basis so its up axis follows the ground normal."""
    up = np.array([0.0, 1.0, 0.0])
    axis = np.cross(up, normal)
    s = np.linalg.norm(axis)
    if s < 1e-6:
        return basis
    axis /= s
    c = float(np.dot(up, normal))
    K = np.array([[0, -axis[2], axis[1]], [axis[2], 0, -axis[0]], [-axis[1], axis[0], 0]])
    R = np.eye(3) + K * s + K @ K * (1 - c)
    return list((R @ np.array(basis).reshape(3, 3)).flatten())


def ground_layers(sheet, grid):
    """Per-terrain-vertex weights for the painterly terrain shader:
    (dirt, mud, moss); the rest is forest floor. Rules:
      path centre -> dirt, path edges and damp dips -> mud,
      hill / open ground and steep forest slopes -> moss and rock."""
    nx, nz = grid["nx"], grid["nz"]
    X, Z = np.meshgrid(grid["x0"] + np.arange(nx), grid["z0"] + np.arange(nz))
    _, segments, dead_ends, _, _ = route(sheet)
    d = np.full(X.shape, np.inf)
    for (ax, az), (bx, bz) in segments:
        dx, dz = bx - ax, bz - az
        L = dx * dx + dz * dz or 1e-9
        t = np.clip(((X - ax) * dx + (Z - az) * dz) / L, 0, 1)
        d = np.minimum(d, np.hypot(X - (ax + t * dx), Z - (az + t * dz)))
    for ex, ez in dead_ends:
        d = np.minimum(d, np.maximum(np.hypot(X - ex, Z - ez) - 1.2, 0))
    (hx0, hz0), (hx1, hz1) = lc.HOUSE_MIN, lc.HOUSE_MAX
    house = np.hypot(np.maximum(np.maximum(hx0 - X, X - hx1), 0), np.maximum(np.maximum(hz0 - Z, Z - hz1), 0))
    h = grid["heights"]
    gz, gx = np.gradient(h)
    slope = np.degrees(np.arctan(np.hypot(gx, gz)))
    p = np.pad(h, 3, mode="edge")                 # local average for damp dips
    local = sum(p[3 + i:3 + i + nz, 3 + j:3 + j + nx] for i in range(-3, 4) for j in range(-3, 4)) / 49.0
    dip = np.clip((local - h) * 2.0, 0, 1)

    dirt = 1.0 - lc.smoothstep(0.8, 1.5, d)
    dirt = np.maximum(dirt, 0.6 * (1.0 - lc.smoothstep(0.5, 1.8, house)))
    mud = lc.smoothstep(0.7, 1.3, d) * (1.0 - lc.smoothstep(1.6, 2.8, d)) * 0.85
    mud = np.maximum(mud, dip * 0.7)
    open_area = lc.smoothstep(FOREST_NORTH_EDGE + 1.0, FOREST_NORTH_EDGE - 2.0, Z)
    inside = (X >= sheet.x_min) & (X <= sheet.x_max) & (Z >= sheet.z_min) & (Z <= sheet.z_max)
    moss = np.maximum(open_area * inside, lc.smoothstep(22.0, 35.0, slope) * 0.7)
    moss *= 1.0 - dirt
    mud *= 1.0 - dirt
    total = dirt + mud + moss
    scale = np.where(total > 1.0, 1.0 / np.maximum(total, 1e-6), 1.0)
    return np.stack([dirt * scale, mud * scale, moss * scale], axis=-1)


def main():
    os.makedirs(BUILD_DIR, exist_ok=True)
    sheet = lc.Sheet()
    assets = lc.load_assets()
    grid = lc.terrain_grid(sheet)
    exact = exact_transforms()
    placements, objects, used_exact = {}, [], 0
    trees = 0

    for x, z, toks in sheet.cells():
        for tok in toks:
            code, yoff, heading = lc.parse_token(tok)
            if code in lc.IGNORED:
                continue
            if code not in lc.CODES:
                raise SystemExit("Unknown code %r in cell (%d, %d)" % (code, x, z))
            asset, kind = lc.CODES[code]
            key = (code, x, z)
            if key in exact and kind != "tree":
                px, pz, basis = exact[key]
                used_exact += 1
            else:
                px, pz, basis = float(x), float(z), lc.heading_to_basis(heading)
            placements[json.dumps([code, x, z])] = [px, pz, basis]
            if kind == "tree":
                ground = lc.min_height_around(grid, px, pz, lc.TRUNKS[asset][0]) - 0.05
                trees += 1
            elif kind == "building":
                lo, hi = assets[asset]["min"], assets[asset]["max"]
                ground = min(lc.height_at(grid, px + a, pz + b) for a in (lo[0], hi[0]) for b in (lo[2], hi[2]))
            else:
                ground = lc.min_height_around(grid, px, pz, GROUND_RADIUS[kind])
            if kind == "stone":
                basis = tilt_basis(basis, normal_at(grid, px, pz))
                ground = lc.height_at(grid, px, pz) - 0.03 + (lc.cell_hash(x, z) % 5) * 0.004
            obj = {"code": code, "asset": asset, "kind": kind,
                   "path": assets[asset]["path"] if asset in assets else "",
                   "basis": [float(b) for b in basis], "origin": [px, ground + yoff, pz]}
            if kind == "tree":
                obj["tint"] = lc.leaf_tint(asset, px, pz)
            objects.append(obj)

    # Background forest: seen, never reached. Not on the sheet (it has no design meaning).
    rng = random.Random(BACKGROUND_SEED)
    weights = [w for _, w in BACKGROUND_MODELS]
    footprints = []
    for o in objects:
        if o["kind"] == "building":
            lo, hi = assets[o["asset"]]["min"], assets[o["asset"]]["max"]
            footprints.append((o["origin"][0] + lo[0] - 2, o["origin"][2] + lo[2] - 2,
                               o["origin"][0] + hi[0] + 2, o["origin"][2] + hi[2] + 2))
    background = []
    gx0, gz0 = grid["x0"], grid["z0"]
    gx1, gz1 = gx0 + grid["nx"] - 1, gz0 + grid["nz"] - 1
    s = BACKGROUND_SPACING
    for i in range(int((gx1 - gx0) / s)):
        for j in range(int((gz1 - gz0) / s)):
            x = gx0 + (i + 0.5 + rng.uniform(-0.4, 0.4)) * s
            z = gz0 + (j + 0.5 + rng.uniform(-0.4, 0.4)) * s
            cx = min(max(x, sheet.x_min - 0.5), sheet.x_max + 0.5)
            cz = min(max(z, sheet.z_min - 0.5), sheet.z_max + 0.5)
            d = math.hypot(x - cx, z - cz)
            keep = 1.0 if d < 20 else 0.6 if d < 38 else 0.35
            r = rng.random()
            if d < 1.2 or d > BACKGROUND_DEPTH or r > keep:
                continue
            if any(a <= x <= c and b <= z <= e for a, b, c, e in footprints):
                continue
            model = rng.choices([m for m, _ in BACKGROUND_MODELS], weights)[0]
            heading = rng.uniform(0, 360)
            scale = rng.uniform(0.85, 1.25)
            basis = [v * scale for v in lc.heading_to_basis(heading)]
            background.append({"asset": model, "path": assets[model]["path"], "basis": basis,
                               "origin": [x, lc.min_height_around(grid, x, z, 0.8) - 0.1, z],
                               "tint": lc.leaf_tint(model, x, z)})

    level = {"terrain": {k: grid[k] for k in ("x0", "z0", "nx", "nz")},
             "objects": objects, "background": background}
    level["terrain"]["heights"] = [round(float(v), 3) for v in grid["heights"].flatten()]
    level["terrain"]["layers"] = [round(float(v), 2) for v in ground_layers(sheet, grid).reshape(-1)]
    json.dump(level, open(os.path.join(BUILD_DIR, "level.json"), "w"))
    json.dump(placements, open(PLACEMENTS, "w"))
    kinds = {}
    for o in objects:
        kinds[o["kind"]] = kinds.get(o["kind"], 0) + 1
    print("objects: %s | kept exact positions for %d | background trees %d | terrain %dx%d, %.1f..%.1f m" % (
        kinds, used_exact, len(background), grid["nx"], grid["nz"], grid["heights"].min(), grid["heights"].max()))


if __name__ == "__main__":
    main()
