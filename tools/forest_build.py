"""Build step 1 of 2 for the forest: level_design/forest_design.json -> level_design/build/level.json.

Usage (from the project root):
    python tools/forest_build.py
    <godot> --headless --path . -s tools/level_bake.gd      (step 2: writes the scene)
    python tools/forest_verify.py                             (seal + reachability check)

The design file is the source of truth (review it with tools/forest_map.py -
the map and this build share the same path and height code). This script:
  - shapes the terrain (design heights inside, rising ground outside),
  - lays ground layers (path dirt, stream mud, moss, forest floor),
  - fills the forest with a sealed checkerboard of trees, each area with its
    own tree mix and leaf colours; trees near paths stay individual (shadows,
    future interaction), the unreachable interior is merged into chunks,
  - places landmarks (Fallen Giant, Ruin Fragment), brambles, rocks,
    undergrowth, collectibles at dead ends, kept props and the city.
"""
import json
import math
import os
import random

import numpy as np

import level_common as lc
from forest_map import Design, polyline_length

BUILD_DIR = os.path.join(lc.ROOT, "level_design", "build")
OLD_PLACEMENTS = os.path.join(BUILD_DIR, "placements.json")

TERRAIN = {"x0": -110, "x1": 110, "z0": -200, "z1": 80}
DENSE_BAND = 6.0          # full-density trees within this distance of reachable ground
INDIVIDUAL_REACH = 3.0    # trees nearer than this to reachable ground stay individual nodes
SHOULDER = 0.3            # extra clearance between a trunk and the path edge
DEAD_END_CLEARING = 2.0
JUNCTION_WIDEN = 1.2
BACKGROUND_DEPTH = 55.0
BACKGROUND_SPACING = 4.5
SEED = 20260927
GROUND_RADIUS = {"wall": 1.0, "building": 0.0, "bush": 0.5, "rock": 1.0, "prop": 0.3,
                 "stone": 0.0, "collectible": 0.0, "charger": 0.9}

# Leaf palettes (sRGB) per area mood.
PALETTES = {
    "fresh": [(0.48, 0.66, 0.26), (0.40, 0.60, 0.24), (0.52, 0.62, 0.22), (0.44, 0.64, 0.32)],
    "deep": [(0.24, 0.40, 0.16), (0.30, 0.44, 0.18), (0.20, 0.34, 0.15), (0.34, 0.42, 0.16)],
    "cool": [(0.30, 0.52, 0.34), (0.26, 0.46, 0.30), (0.36, 0.56, 0.30), (0.32, 0.50, 0.38)],
    "dry": [(0.62, 0.60, 0.28), (0.56, 0.56, 0.24), (0.66, 0.54, 0.24), (0.50, 0.56, 0.26)],
    "pine": [(0.18, 0.36, 0.20), (0.22, 0.40, 0.22), (0.16, 0.32, 0.24), (0.26, 0.42, 0.18)],
}
AUTUMN = [(0.80, 0.56, 0.18), (0.74, 0.36, 0.14), (0.66, 0.20, 0.14)]

# The Fallen Giant's blocking footprint in its local frame (X along the body):
# segments (x0, z0, x1, z1, half_width). The raised middle hull is left out -
# the stream bed passes under it.
GIANT_BLOCKERS = [(-10.7, 0, -5.0, 0, 2.1), (5.0, 0, 10.7, 0, 2.1), (-14.7, 0.6, -10.2, 0.6, 2.3),
                  (10.7, 1.6, 21.0, 1.6, 1.0), (10.7, -1.6, 21.0, -1.6, 1.0), (-6.0, -2.1, -6.0, -10.5, 1.0),
                  (-9.2, 0, -8.6, 0, 0.8)]
GIANT_FULL = GIANT_BLOCKERS + [(-5.0, 0, 5.0, 0, 2.3)]      # for keeping trees clear of it


def leaf_tint(palette, autumn_share, asset, x, z):
    h = lc.cell_hash(int(round(x * 10)), int(round(z * 10)), 7)
    if asset.startswith("Pine"):
        base = PALETTES["pine"][h % 4]
    elif (h >> 4) % 100 < autumn_share:
        base = AUTUMN[(h >> 8) % len(AUTUMN)]
    else:
        pal = PALETTES[palette]
        base = pal[(h >> 8) % len(pal)]
    k = 0.92 + ((h >> 12) % 17) / 100.0
    return [round(min(c * k, 1.0), 3) for c in base]


def point_in_poly(x, z, poly):
    inside = False
    for (x1, z1), (x2, z2) in zip(poly, poly[1:] + poly[:1]):
        if (z1 > z) != (z2 > z) and x < (x2 - x1) * (z - z1) / (z2 - z1) + x1:
            inside = not inside
    return inside


def seg_dist(px_, pz, ax, az, bx, bz):
    return lc.point_segment_distance(px_, pz, ax, az, bx, bz)


def curve_dist(x, z, curve):
    return min(seg_dist(x, z, a[0], a[1], b[0], b[1]) for a, b in zip(curve[:-1], curve[1:]))


class Forest:
    def __init__(self):
        self.design = Design()
        self.d = self.design.d
        self.assets = lc.load_assets()
        self.fb = self.d["forest_bounds"]
        self.north = self.d["open_north"]
        self.areas = {a["id"]: a for a in self.d["areas"]}
        self.stream = self.design.paths["stream"]
        # giant frame
        g = next(l for l in self.d["landmarks"] if l["id"] == "giant")
        (ax, az), (bx, bz) = g["body"]
        L = math.dist((ax, az), (bx, bz))
        self.giant_axis = ((bx - ax) / L, (bz - az) / L)
        self.giant_mid = ((ax + bx) / 2, (az + bz) / 2)

    # --- geometry helpers --------------------------------------------------------
    def giant_to_world(self, lx, lz):
        (dx, dz), (mx, mz) = self.giant_axis, self.giant_mid
        return mx + lx * dx - lz * dz, mz + lx * dz + lz * dx      # local Z = X rotated 90° (right-handed)

    def giant_segments(self, full=False):
        out = []
        for x0, z0, x1, z1, hw in (GIANT_FULL if full else GIANT_BLOCKERS):
            a, b = self.giant_to_world(x0, z0), self.giant_to_world(x1, z1)
            out.append((a[0], a[1], b[0], b[1], hw))
        return out

    def area_at(self, x, z):
        if curve_dist(x, z, self.stream["curve"]) < self.areas["stream"]["band_half_width"]:
            return "stream"
        for aid in ("clearing", "ruins", "garden", "pines", "old_wood", "edge"):
            if point_in_poly(x, z, self.areas[aid]["polygon"]):
                return aid
        return "edge"

    def corridor_clearance(self, x, z):
        """Distance from (x, z) to the nearest walkable edge (negative = on a path/clearing)."""
        best = 1e9
        for p in self.design.paths.values():
            best = min(best, curve_dist(x, z, p["curve"]) - p["width"] / 2)
        for name, n in self.design.nodes.items():
            k = n["kind"]
            r = n.get("radius", DEAD_END_CLEARING if k == "dead_end" else JUNCTION_WIDEN if k == "junction" else 0)
            if r and k != "blocker":
                best = min(best, math.dist((x, z), n["pos"]) - r)
        # the walkable strip around the house: trees next to it must be dense too
        best = min(best, lc.box_distance(x, z, lc.HOUSE_MIN, lc.HOUSE_MAX) - 1.2)
        return best

    def reach_distance(self, x, z):
        """Like corridor_clearance, but also counting the open hill/city ground north of
        the forest. Used for tree density and batching, not for keeping trees clear."""
        return min(self.corridor_clearance(x, z), z - self.fb["z_min"])

    # --- terrain -----------------------------------------------------------------
    def terrain(self):
        xs = np.arange(TERRAIN["x0"], TERRAIN["x1"] + 1)
        zs = np.arange(TERRAIN["z0"], TERRAIN["z1"] + 1)
        X, Z = np.meshgrid(xs, zs)
        rx0, rx1 = self.fb["x_min"], self.fb["x_max"]
        rz0, rz1 = self.north["z_min"], self.fb["z_max"]
        cx, cz = np.clip(X, rx0, rx1), np.clip(Z, rz0, rz1)
        inner_xs = np.arange(rx0, rx1 + 1)
        inner_zs = np.arange(rz0, rz1 + 1)
        inner = self.design.heights(inner_xs, inner_zs)
        base = inner[(cz - rz0).astype(int), (cx - rx0).astype(int)]
        d_out = np.hypot(X - cx, Z - cz)
        rolling = 0.8 * np.sin(0.13 * X + 0.4) * np.cos(0.11 * Z + 1.1) + 0.5 * np.sin(0.23 * X - 0.19 * Z)
        rise = 7.0 * lc.smoothstep(0.0, 45.0, d_out) + rolling * lc.smoothstep(0.0, 15.0, d_out)
        return {"x0": int(TERRAIN["x0"]), "z0": int(TERRAIN["z0"]), "nx": len(xs), "nz": len(zs),
                "heights": (base + rise).astype(float)}

    def ground_layers(self, grid):
        nx, nz = grid["nx"], grid["nz"]
        X, Z = np.meshgrid(grid["x0"] + np.arange(nx), grid["z0"] + np.arange(nz))
        def dist_to(curve):
            d = np.full(X.shape, np.inf)
            for (ax, az), (bx, bz) in zip(curve[:-1], curve[1:]):
                dx, dz = bx - ax, bz - az
                L = dx * dx + dz * dz or 1e-9
                t = np.clip(((X - ax) * dx + (Z - az) * dz) / L, 0, 1)
                d = np.minimum(d, np.hypot(X - (ax + t * dx), Z - (az + t * dz)))
            return d
        path_edge = np.full(X.shape, np.inf)
        for p in self.design.paths.values():
            if p["kind"] != "stream":
                path_edge = np.minimum(path_edge, dist_to(p["curve"]) - p["width"] / 2)
        stream_edge = dist_to(self.stream["curve"]) - self.stream["width"] / 2
        h = grid["heights"]
        gz, gx = np.gradient(h)
        slope = np.degrees(np.arctan(np.hypot(gx, gz)))

        dirt = 1.0 - lc.smoothstep(-0.3, 0.4, path_edge)
        mud = 1.0 - lc.smoothstep(0.0, 1.5, stream_edge)
        mud = np.maximum(mud, lc.smoothstep(-0.6, 0.0, path_edge) * (1 - lc.smoothstep(0.3, 1.2, path_edge)) * 0.6)
        moss = lc.smoothstep(24.0, 36.0, slope) * 0.7
        # area ground bias
        area_bias = {"mud": (0, 0.35, 0), "moss": (0, 0, 0.8), "dirt": (0.55, 0, 0)}
        for aid, a in self.areas.items():
            bias = area_bias.get(a.get("ground"))
            if not bias or "polygon" not in a:
                continue
            poly = np.array(a["polygon"], dtype=float)
            inside = np.zeros(X.shape, dtype=bool)
            xmin, zmin = poly.min(axis=0)
            xmax, zmax = poly.max(axis=0)
            box = (X >= xmin) & (X <= xmax) & (Z >= zmin) & (Z <= zmax)
            for iz, ix in zip(*np.nonzero(box)):
                inside[iz, ix] = point_in_poly(X[iz, ix], Z[iz, ix], a["polygon"])
            if aid == "clearing":                      # dry sunny core, fading out
                n = self.design.nodes["clearing"]
                core = 1 - lc.smoothstep(n["radius"] * 0.6, n["radius"] + 3, np.hypot(X - n["pos"][0], Z - n["pos"][1]))
                dirt = np.maximum(dirt, core * 0.75)
                moss = np.maximum(moss, inside * 0.3)
                continue
            dirt = np.maximum(dirt, inside * bias[0])
            mud = np.maximum(mud, inside * bias[1])
            moss = np.maximum(moss, inside * bias[2])
        open_north = (Z < self.fb["z_min"] - 1) & (np.abs(X) <= self.north["x_max"])
        moss = np.maximum(moss, open_north * 1.0)
        moss *= 1 - dirt
        mud *= 1 - dirt
        total = dirt + mud + moss
        scale = np.where(total > 1, 1 / np.maximum(total, 1e-6), 1.0)
        return np.stack([dirt * scale, mud * scale, moss * scale], axis=-1)


def main():
    os.makedirs(BUILD_DIR, exist_ok=True)
    f = Forest()
    d, assets = f.d, f.assets
    grid = f.terrain()
    rng = random.Random(SEED)
    objects, interior, undergrowth = [], [], []

    def ground(x, z, radius=0.0):
        return lc.min_height_around(grid, x, z, radius)

    def add(code_kind, asset, x, z, heading=0.0, y_offset=0.0, radius=None, basis=None, extra=None):
        kind = code_kind
        b = basis or lc.heading_to_basis(heading)
        r = GROUND_RADIUS.get(kind, 0.3) if radius is None else radius
        o = {"code": asset[:3].upper(), "asset": asset, "kind": kind,
             "path": assets[asset]["path"] if asset in assets else "",
             "basis": [float(v) for v in b], "origin": [x, ground(x, z, r) + y_offset, z]}
        o.update(extra or {})
        objects.append(o)
        return o

    # --- obstacles trees must keep clear of ---------------------------------------
    blockers = []           # (kind, data) used by tree placement and the verifier
    # kept props from the old level: house vines, gate walls + vines, city buildings (moved north)
    old = {tuple(json.loads(k)): v for k, v in json.load(open(OLD_PLACEMENTS)).items()} if os.path.exists(OLD_PLACEMENTS) else {}
    shift = d.get("city_shift_z", 0)
    for (code, cx, cz), (px_, pz, basis) in old.items():
        if code in ("SC1", "SC2", "SC3"):
            asset = lc.CODES[code][0]
            o = add("building", asset, px_, pz + shift, basis=basis)
            o["code"] = code
            lo, hi = assets[asset]["min"], assets[asset]["max"]
            blockers.append(("box", (px_ + lo[0], pz + shift + lo[2], px_ + hi[0], pz + shift + hi[2])))
        elif code == "WUB" and abs(px_) < 3 and -10 < pz < -8:            # the two gate walls
            o = add("wall", "Wall_UnevenBrick_Straight", px_, pz, basis=basis)
            o["code"] = "WUB"
            blockers.append(("wall", (px_, pz, basis)))
        elif code in ("VN1", "VN2") and abs(px_) < 4 and -12 < pz < 0:    # house + gate vines
            o = add("prop", lc.CODES[code][0], px_, pz, basis=basis, y_offset=4.0 if pz > -8 else 3.0)
            o["code"] = code

    # Fallen Giant
    gx, gz = f.giant_mid
    (ax, az) = f.giant_axis
    giant_basis = [ax, 0.0, -az, 0.0, 1.0, 0.0, az, 0.0, ax]
    objects.append({"code": "GIANT", "asset": "fallen_giant", "kind": "giant", "path": "res://scenes/props/fallen_giant.tscn",
                    "basis": giant_basis, "origin": [gx, lc.height_at(grid, gx, gz), gz]})
    for seg in f.giant_segments(full=True):
        blockers.append(("segment", seg))

    # Ruin Fragment
    ruin_lm = next(l for l in d["landmarks"] if l["id"] == "ruin")
    rx, rz = d["nodes"]["ruin"]["pos"]
    def path_clearance(x, z):
        return min(curve_dist(x, z, p["curve"]) - p["width"] / 2 for p in f.design.paths.values())

    placed_pieces = []          # (original offset, final x, z, footprint)
    for piece in [p for p in ruin_lm["pieces"] if not p["asset"].startswith("Prop_Vine")]:
        asset = piece["asset"]
        lo, hi = assets[asset]["min"], assets[asset]["max"]
        footprint = max(hi[0] - lo[0], hi[2] - lo[2]) / 2
        x0_, z0_ = rx + piece["offset"][0], rz + piece["offset"][1]
        # smallest move that clears every path and the other pieces
        best = None
        for ring in [0.0] + [0.5 * k for k in range(1, 13)]:
            for step in range(1 if ring == 0 else 16):
                ang = step * math.pi / 8
                x, z = x0_ + math.cos(ang) * ring, z0_ + math.sin(ang) * ring
                if path_clearance(x, z) < footprint + 0.6:
                    continue
                if any(math.dist((x, z), (px2, pz2)) < (footprint + fp2) * 0.8 for _, px2, pz2, fp2 in placed_pieces):
                    continue
                best = (x, z)
                break
            if best:
                break
        x, z = best or (x0_, z0_)
        placed_pieces.append((piece["offset"], x, z, footprint))
        kind = "wall" if asset.startswith("Wall_UnevenBrick") else "building"
        o = add(kind, asset, x, z, piece["heading"], radius=1.0)
        o["code"] = "RUIN"
        blockers.append(("circle", (x, z, footprint)))
    for piece in [p for p in ruin_lm["pieces"] if p["asset"].startswith("Prop_Vine")]:
        # a vine hangs on the piece whose original spot was nearest, moved with it
        off, px2, pz2, _ = min(placed_pieces, key=lambda t: math.dist(t[0], piece["offset"]))
        x = px2 + piece["offset"][0] - off[0]
        z = pz2 + piece["offset"][1] - off[1]
        add("prop", piece["asset"], x, z, piece["heading"], y_offset=piece.get("raise", 3.0), radius=1.0)

    # Brambles blocking the stream's east end: a Breakable the cutter clears. Its
    # bushes are its own children (they vanish with it), not merged undergrowth.
    behind_boxes = {}
    for b in d.get("blockers", []):
        (x0, z0), (x1, z1) = b["from"], b["to"]
        oy = ground((x0 + x1) / 2, (z0 + z1) / 2, 2.0)
        bushes = []
        for k in range(14):                                   # dense dark thorny bushes as the visual
            x, z = rng.uniform(x0 + 0.4, x1 - 0.4), rng.uniform(z0 + 0.4, z1 - 0.4)
            bushes.append({"asset": "Bush_Common", "path": assets["Bush_Common"]["path"],
                           "basis": [v * rng.uniform(1.1, 1.6) for v in lc.heading_to_basis(rng.uniform(0, 360))],
                           "origin": [x - (x0 + x1) / 2, ground(x, z, 0.5) - 0.1 - oy, z - (z0 + z1) / 2], "tint": [0.20, 0.24, 0.12]})
        objects.append({"code": "BRAMBLE", "asset": "brambles", "kind": "bramble", "path": "", "id": b["id"],
                        "basis": [1, 0, 0, 0, 1, 0, 0, 0, 1],
                        "origin": [(x0 + x1) / 2, oy, (z0 + z1) / 2],
                        "size": [x1 - x0, 2.6, z1 - z0], "note": b["note"], "bushes": bushes})
        blockers.append(("box", (x0, z0, x1, z1)))
        behind_boxes[b["id"]] = [x0, z0, x1, z1]

    # Solar charging stations (fixed scenes; trees keep clear of them)
    for c in d.get("chargers", []):
        x, z = c["pos"]
        o = add("charger", "charger", x, z, c.get("heading", 0), radius=0.9)
        o.update({"code": "CHG", "path": "res://scenes/props/charging_station.tscn", "name": c["name"], "id": c["id"],
                  "capacity": c.get("capacity", 100), "panel_rate": c.get("panel_rate", 0.45), "stored": c.get("stored", 50)})
        blockers.append(("circle", (x, z, 0.9)))

    # Collectibles at dead ends
    names = [n for n, v in d["nodes"].items() if v["kind"] == "dead_end" and v.get("reward") == "collectible"]
    for i, n in enumerate(sorted(names, key=lambda n: d["nodes"][n]["pos"][0]), start=1):
        x, z = d["nodes"][n]["pos"]
        objects.append({"code": "CP%d" % i, "asset": "collectible", "kind": "collectible", "path": "",
                        "basis": [1, 0, 0, 0, 1, 0, 0, 0, 1], "origin": [x, ground(x, z), z], "node": n})

    # Stream: rocks on the banks, flat stones in the bed
    curve = f.stream["curve"]
    total = polyline_length(curve)
    stones_every, rocks_every = 2.8, 6.5
    dist_along = 0.0
    next_stone, next_rock, side = 1.0, 3.0, 1
    for (x0, z0), (x1, z1) in zip(curve[:-1], curve[1:]):
        seg = math.dist((x0, z0), (x1, z1))
        nx_, nz_ = -(z1 - z0) / (seg or 1), (x1 - x0) / (seg or 1)
        while next_stone <= dist_along + seg:
            t = (next_stone - dist_along) / seg
            x, z = x0 + (x1 - x0) * t, z0 + (z1 - z0) * t
            off = rng.uniform(-1.4, 1.4)
            asset = "RockPath_Round_Small_%d" % rng.randint(1, 3)
            undergrowth.append({"asset": asset, "path": assets[asset]["path"],
                                "basis": lc.heading_to_basis(rng.uniform(0, 360)),
                                "origin": [x + nx_ * off, lc.height_at(grid, x + nx_ * off, z + nz_ * off) - 0.03, z + nz_ * off]})
            next_stone += stones_every
        while next_rock <= dist_along + seg:
            t = (next_rock - dist_along) / seg
            x, z = x0 + (x1 - x0) * t, z0 + (z1 - z0) * t
            asset = "Rock_Medium_%d" % rng.randint(1, 3)
            lo, hi = assets[asset]["min"], assets[asset]["max"]
            rr = min(hi[0] - lo[0], hi[2] - lo[2]) / 2 * 0.85
            off = side * (f.stream["width"] / 2 + rr + 0.4)
            rxp, rzp = x + nx_ * off, z + nz_ * off
            if f.corridor_clearance(rxp, rzp) > rr * 0.6 and all(
                    math.dist((rxp, rzp), n["pos"]) > 5 for n in d["nodes"].values()):
                o = add("rock", asset, rxp, rzp, rng.uniform(0, 360), radius=rr)
                o["collision_radius"] = round(rr, 2)
                blockers.append(("circle", (rxp, rzp, rr)))
            side = -side
            next_rock += rocks_every
        dist_along += seg

    # --- trees -------------------------------------------------------------------
    def blocked(x, z, r):
        for kind, data in blockers:
            if kind == "circle" and math.dist((x, z), data[:2]) - r < data[2] + 0.4:
                return True
            if kind == "box":
                x0, z0, x1, z1 = data
                if lc.box_distance(x, z, (x0, z0), (x1, z1)) - r < 0.3:
                    return True
            if kind == "segment" and seg_dist(x, z, *data[:4]) - r < data[4] + 0.2:
                return True
            if kind == "wall":
                wx, wz, b = data
                dx, dz = b[0], b[6]
                if seg_dist(x, z, wx - dx, wz - dz, wx + dx, wz + dz) - r < 0.45:
                    return True
        return False

    tree_models = sorted({m for a in f.areas.values() for m in a["trees"]})
    trees_individual = trees_merged = skipped = 0
    fbx0, fbx1, fbz0, fbz1 = f.fb["x_min"], f.fb["x_max"], f.north["z_min"], f.fb["z_max"]
    for x in range(fbx0, fbx1 + 1):
        for z in range(fbz0, fbz1 + 1):
            if (x + z) % 2:
                continue
            in_forest = z >= f.fb["z_min"]
            if not in_forest:                                     # hill/city: only sealed border rows
                n = f.north
                if not (x <= n["x_min"] + 3 or x >= n["x_max"] - 3 or z <= n["z_min"] + 3):
                    continue
            clearance = f.corridor_clearance(x, z)
            reach = f.reach_distance(x, z)
            if in_forest and reach > DENSE_BAND and (x % 2 or z % 2):
                continue                                          # deep interior: half density
            house_d = lc.box_distance(x, z, lc.HOUSE_MIN, lc.HOUSE_MAX)
            area = f.area_at(x, z) if in_forest else "edge"
            weights = f.areas[area]["trees"]
            models = sorted(weights, key=lambda m: -math.log((lc.cell_hash(x, z, tree_models.index(m)) % 100000 + 1) / 100001.0) / weights[m])
            chosen = None
            for m in models:
                r = lc.TRUNKS[m][0]
                low = assets[m]["spread_below_3m"]
                roof = assets[m]["spread_below_house_roof"]
                if clearance - r < SHOULDER:
                    continue
                if clearance < 3 and low > clearance + 1.0:
                    continue
                if house_d - r < 1.2 or house_d < roof + 0.2:
                    continue
                if blocked(x, z, r):
                    continue
                chosen = m
                break
            if chosen is None:
                skipped += 1
                continue
            a = f.areas[area]
            heading = (lc.cell_hash(x, z, 99) % 24) * 15
            tint = leaf_tint(a["leaves"], a["autumn_share"], chosen, x, z)
            o = {"code": "T", "asset": chosen, "kind": "tree", "path": assets[chosen]["path"],
                 "basis": lc.heading_to_basis(heading),
                 "origin": [float(x), ground(x, z, lc.TRUNKS[chosen][0]) - 0.05, float(z)],
                 "tint": tint, "trunk": list(lc.TRUNKS[chosen]), "area": area}
            if clearance <= INDIVIDUAL_REACH:               # beside a real path: individual node
                objects.append(o)
                trees_individual += 1
            else:
                o["lod"] = 1 if clearance < 8 else 2        # trees just behind path-side ones keep more detail
                interior.append(o)
                trees_merged += 1

    # --- undergrowth along paths and in clearings ------------------------------------
    tree_pos = [(o["origin"][0], o["origin"][2], o["trunk"][0]) for o in objects + interior if o["kind"] == "tree"]
    tree_cells = {}
    for tx, tz, tr in tree_pos:
        tree_cells.setdefault((int(tx // 4), int(tz // 4)), []).append((tx, tz, tr))
    def near_tree(x, z, pad):
        for i in (-1, 0, 1):
            for j in (-1, 0, 1):
                for tx, tz, tr in tree_cells.get((int(x // 4) + i, int(z // 4) + j), []):
                    if math.dist((x, z), (tx, tz)) < tr + pad:
                        return True
        return False
    for aid, a in f.areas.items():
        items = a.get("undergrowth", {})
        if not items:
            continue
        # candidate area: the forest bounds; keep ones that land in this area near walkable ground
        area_m2 = 72 * 90 / 7.0
        for asset, per100 in items.items():
            count = int(per100 * area_m2 / 100 * 2.5)
            placed = tries = 0
            while placed < count and tries < count * 40:
                tries += 1
                x, z = rng.uniform(fbx0 + 1, fbx1 - 1), rng.uniform(f.fb["z_min"] + 1, fbz1 - 1)
                if f.area_at(x, z) != aid:
                    continue
                c = f.corridor_clearance(x, z)
                if not (0.25 < c < 3.5) and not (aid == "clearing" and c < 0 and math.dist((x, z), d["nodes"]["clearing"]["pos"]) < 7):
                    continue
                if aid == "clearing" and c < 0:
                    if any(curve_dist(x, z, p["curve"]) < p["width"] / 2 + 0.2 for p in f.design.paths.values()):
                        continue
                if near_tree(x, z, 0.5) or blocked(x, z, 0.3) or lc.box_distance(x, z, lc.HOUSE_MIN, lc.HOUSE_MAX) < 0.8:
                    continue
                s = rng.uniform(0.8, 1.3)
                item = {"asset": asset, "path": assets[asset]["path"],
                        "basis": [v * s for v in lc.heading_to_basis(rng.uniform(0, 360))],
                        "origin": [x, lc.height_at(grid, x, z) - 0.05, z]}
                if asset.startswith("Bush"):
                    item["tint"] = leaf_tint(a["leaves"], 0, "Bush", x, z)
                undergrowth.append(item)
                placed += 1

    # --- background forest (seen, never reached) -----------------------------------
    footprints = [data for kind, data in blockers if kind == "box"]
    background = []
    bg_models = [("CommonTree_1", 3), ("CommonTree_2", 3), ("CommonTree_3", 3), ("CommonTree_4", 3), ("CommonTree_5", 3),
                 ("Pine_1", 3), ("Pine_2", 3), ("Pine_5", 3), ("DeadTree_1", 1.5), ("TwistedTree_2", 1),
                 ("TwistedTree_4", 1), ("TwistedTree_5", 1)]
    s = BACKGROUND_SPACING
    for i in range(int((TERRAIN["x1"] - TERRAIN["x0"]) / s)):
        for j in range(int((TERRAIN["z1"] - TERRAIN["z0"]) / s)):
            x = TERRAIN["x0"] + (i + 0.5 + rng.uniform(-0.4, 0.4)) * s
            z = TERRAIN["z0"] + (j + 0.5 + rng.uniform(-0.4, 0.4)) * s
            cx, cz = min(max(x, fbx0 - 0.5), fbx1 + 0.5), min(max(z, fbz0 - 0.5), fbz1 + 0.5)
            dd = math.hypot(x - cx, z - cz)
            keep = 1.0 if dd < 20 else 0.6 if dd < 38 else 0.35
            if dd < 1.2 or dd > BACKGROUND_DEPTH or rng.random() > keep:
                continue
            if any(x0 - 2 <= x <= x1 + 2 and z0 - 2 <= z <= z1 + 2 for x0, z0, x1, z1 in footprints):
                continue
            model = rng.choices([m for m, _ in bg_models], [w for _, w in bg_models])[0]
            sc = rng.uniform(0.85, 1.25)
            background.append({"asset": model, "path": assets[model]["path"],
                               "basis": [v * sc for v in lc.heading_to_basis(rng.uniform(0, 360))],
                               "origin": [x, lc.min_height_around(grid, x, z, 0.8) - 0.1, z],
                               "tint": leaf_tint("fresh" if rng.random() < 0.5 else "deep", 12, model, x, z)})

    level = {"terrain": {k: grid[k] for k in ("x0", "z0", "nx", "nz")},
             "objects": objects, "interior": interior, "undergrowth": undergrowth, "background": background,
             "blockers": blockers, "behind_boxes": behind_boxes, "giant": {"mid": list(f.giant_mid), "axis": list(f.giant_axis)},
             "giant_segments": f.giant_segments(full=True)}
    level["terrain"]["heights"] = [round(float(v), 3) for v in grid["heights"].flatten()]
    level["terrain"]["layers"] = [round(float(v), 2) for v in f.ground_layers(grid).reshape(-1)]
    json.dump(level, open(os.path.join(BUILD_DIR, "level.json"), "w"))
    kinds = {}
    for o in objects:
        kinds[o["kind"]] = kinds.get(o["kind"], 0) + 1
    tris = {m: 0 for m in tree_models}
    print("objects %s | trees: %d individual, %d merged interior, %d cells skipped | undergrowth %d | background %d | terrain %dx%d" % (
        kinds, trees_individual, trees_merged, skipped, len(undergrowth), len(background), grid["nx"], grid["nz"]))
    by_area = {}
    for o in objects + interior:
        if o["kind"] == "tree":
            by_area.setdefault(o["area"], {}).setdefault(o["asset"], 0)
            by_area[o["area"]][o["asset"]] += 1
    for aid, m in by_area.items():
        print("  %-9s %4d trees: %s" % (aid, sum(m.values()), ", ".join("%s %d" % kv for kv in sorted(m.items(), key=lambda kv: -kv[1]))))


if __name__ == "__main__":
    main()
