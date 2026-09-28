"""Build step 1 for a city district: level_design/<name>_design.json -> level_design/build/<name>.json.

Usage (from the project root):
    python tools/district_build.py hub
    python tools/district_verify.py hub
    python tools/forest_routes.py --design hub --start hub_entry --out hub_routes.json
    <godot> --headless --path . -s tools/level_bake.gd ++ hub          (-> scenes/level_hub/generated_hub.tscn)
    <godot> --headless --fixed-fps 60 --path . -s tools/forest_drive_test.gd ++ hub

A district has no terrain of its own: it sits on the forest terrain (give it a
"flat" feature in forest_design.json). Everything here is curated placement:
buildings, wall segments (built from 2 m pieces), gates (rubble = Breakable,
locked = needs a key item), chargers, collectibles, props, hand-made scenes.
"""
import json
import math
import os
import sys

import level_common as lc
from forest_map import Design

BUILD_DIR = os.path.join(lc.ROOT, "level_design", "build")
WALL_PIECE = "Wall_UnevenBrick_Straight"
WALL_LEN = 2.0
ROCKS = ["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"]
FENCE = "Prop_MetalFence_Simple"
VINES = ["Prop_Vine1", "Prop_Vine2"]
WALL_BOX = [2.0, 3.12, 0.41, 0.0, 1.56, -0.11]    # collision size + centre of a wall piece (as level_bake.gd's WALL_SIZE/WALL_CENTRE)


def load_design(name):
    return json.load(open(os.path.join(lc.ROOT, "level_design", "%s_design.json" % name), encoding="utf-8"))


def footprint(asset, assets, x, z, heading):
    """World-space box (x0, z0, x1, z1) of an asset's measured bounds placed at (x, z) with a heading."""
    lo, hi = assets[asset]["min"], assets[asset]["max"]
    b = lc.heading_to_basis(heading)
    xs, zs = [], []
    for lx in (lo[0], hi[0]):
        for lz in (lo[2], hi[2]):
            xs.append(x + b[0] * lx + b[2] * lz)
            zs.append(z + b[6] * lx + b[8] * lz)
    return (min(xs), min(zs), max(xs), max(zs))


def main(name="hub"):
    os.makedirs(BUILD_DIR, exist_ok=True)
    d = load_design(name)
    assets = lc.load_assets()
    forest = Design()                       # the terrain the district sits on

    def ground(x, z):
        return float(forest.heights([x], [z])[0, 0])

    def basis(heading):
        return [float(v) for v in lc.heading_to_basis(heading)]

    objects, blockers, behind_boxes = [], [], {}
    merged_walls = []       # merge_walls: wall pieces baked into chunk meshes + box collision (few draw calls)

    for b in d.get("buildings", []):
        x, z = b["pos"]
        objects.append({"code": "BLD", "asset": b["asset"], "kind": "building", "path": assets[b["asset"]]["path"],
                        "basis": basis(b["heading"]), "origin": [x, ground(x, z), z]})
        blockers.append(("box", list(footprint(b["asset"], assets, x, z, b["heading"]))))

    for (x0, z0), (x1, z1) in d.get("walls", {}).get("segments", []):
        length = math.dist((x0, z0), (x1, z1))
        n = max(1, int(round(length / WALL_LEN)))
        heading = math.degrees(math.atan2(x1 - x0, -(z1 - z0))) + 90     # piece's long axis along the segment
        for k in range(n):
            t = (k + 0.5) / n
            x, z = x0 + (x1 - x0) * t, z0 + (z1 - z0) * t
            piece = {"code": "WUB", "asset": WALL_PIECE, "kind": "wall", "path": assets[WALL_PIECE]["path"],
                     "basis": basis(heading), "origin": [x, ground(x, z), z]}
            if d.get("merge_walls"):
                piece["box"] = WALL_BOX
                merged_walls.append(piece)
            else:
                objects.append(piece)
        blockers.append(("segment", [x0, z0, x1, z1, 0.25]))

    for box in d.get("solids", {}).get("boxes", []):
        blockers.append(("box", list(box)))

    for g in d.get("blockers", []):
        (x0, z0), (x1, z1) = g["from"], g["to"]
        cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
        o = {"code": "GATE", "asset": g["kind"], "kind": "gate_" + g["kind"], "id": g["id"], "path": "",
             "basis": [1, 0, 0, 0, 1, 0, 0, 0, 1], "origin": [cx, ground(cx, cz), cz],
             "size": [x1 - x0, 3.0, z1 - z0], "note": g.get("note", "")}
        if g["kind"] == "rubble":
            o["health"] = g.get("health", 120)
            o["drops"] = g.get("drops", {})
            rocks = []
            for k in range(6):
                h = lc.cell_hash(int(cx * 3) + k, int(cz * 3), 5)
                rx = x0 + 0.5 + (h % 100) / 100.0 * (x1 - x0 - 1.0)
                rz = z0 + 0.5 + ((h >> 7) % 100) / 100.0 * (z1 - z0 - 1.0)
                asset = ROCKS[k % 3]
                sc = 0.8 + ((h >> 14) % 40) / 100.0
                rocks.append({"asset": asset, "path": assets[asset]["path"],
                              "basis": [v * sc for v in lc.heading_to_basis((h >> 3) % 360)],
                              "origin": [rx - cx, -0.2, rz - cz]})
            o["rocks"] = rocks
        elif g["kind"] == "vines":
            # A curtain of hanging vines over a few bushes: a Breakable the laser burns.
            o["health"] = g.get("health", 60)
            along_x = (x1 - x0) >= (z1 - z0)
            span = (x1 - x0) if along_x else (z1 - z0)
            n = max(2, int(math.ceil(span / 1.1)))
            pieces = []
            for row, (y, off) in enumerate(((2.15, -0.12), (2.95, 0.12))):    # the vine hangs 2.1 m below its origin
                for k in range(n + row):
                    t = (k + 0.5) / n if row == 0 else k / n
                    along = (x0 + (x1 - x0) * t - cx) if along_x else (z0 + (z1 - z0) * t - cz)
                    asset = VINES[(k + row) % 2]
                    flip = 180 if (k + row) % 3 == 0 else 0
                    pieces.append({"asset": asset, "path": assets[asset]["path"],
                                   "basis": basis((0 if along_x else 90) + flip),
                                   "origin": [along if along_x else off, y, off if along_x else along]})
            bushes = []
            for k in range(n):
                t = (k + 0.5) / n
                along = (x0 + (x1 - x0) * t - cx) if along_x else (z0 + (z1 - z0) * t - cz)
                sc = 0.55 + 0.1 * (k % 2)
                bushes.append({"asset": "Bush_Common", "path": assets["Bush_Common"]["path"],
                               "basis": [v * sc for v in lc.heading_to_basis(37 * k)],
                               "origin": [along if along_x else 0.0, -0.05, 0.0 if along_x else along], "tint": [0.22, 0.30, 0.12]})
            o["pieces"], o["bushes"] = pieces, bushes
        else:
            o["key"] = g["key"]
            along_x = (x1 - x0) >= (z1 - z0)          # the fence runs across the street
            span = (x1 - x0) if along_x else (z1 - z0)
            n = max(1, int(math.ceil(span / 1.95)))
            pieces = []
            for k in range(n):
                t = (k + 0.5) / n
                px_ = (x0 + (x1 - x0) * t - cx) if along_x else 0.0
                pz = 0.0 if along_x else (z0 + (z1 - z0) * t - cz)
                pieces.append({"asset": FENCE, "path": assets[FENCE]["path"],
                               "basis": basis(0 if along_x else 90), "origin": [px_, 0.0, pz]})
            o["pieces"] = pieces
        objects.append(o)
        blockers.append(("box", [x0, z0, x1, z1]))
        behind_boxes[g["id"]] = [x0, z0, x1, z1]

    for sc in d.get("scenes", []):
        x, z = sc["pos"]
        objects.append({"code": "SCN", "asset": sc["id"], "kind": "scene", "id": sc["id"], "path": sc["path"],
                        "basis": basis(sc.get("heading", 0)), "origin": [x, ground(x, z), z]})

    for c in d.get("chargers", []):
        x, z = c["pos"]
        objects.append({"code": "CHG", "asset": "charger", "kind": "charger", "path": "res://scenes/props/charging_station.tscn",
                        "name": c["name"], "id": c["id"], "basis": basis(c.get("heading", 0)), "origin": [x, ground(x, z), z],
                        "capacity": c.get("capacity", 100), "panel_rate": c.get("panel_rate", 0.45), "stored": c.get("stored", 50)})
        blockers.append(("circle", [x, z, 0.9]))

    for i, c in enumerate(d.get("collectibles", []), start=1):
        x, z = c["pos"]
        objects.append({"code": "CP%d" % i, "asset": "collectible", "kind": "collectible", "path": "",
                        "basis": [1, 0, 0, 0, 1, 0, 0, 0, 1], "origin": [x, ground(x, z), z],
                        "item": c["item"], "name": c["name"], "colour": c.get("colour", [1, 1, 1])})

    for pr in d.get("props", []):
        x, z = pr["pos"]
        asset = pr["asset"]
        o = {"code": "PRP", "asset": asset, "kind": "prop", "path": assets[asset]["path"],
             "basis": basis(pr.get("heading", 0)), "origin": [x, ground(x, z) + pr.get("y_offset", 0.0), z]}
        if pr.get("solid"):
            # wagons, fences...: model + box collision (the bake's "building" path)
            o["kind"] = "building"
            blockers.append(("box", list(footprint(asset, assets, x, z, pr.get("heading", 0)))))
        elif asset.startswith("DeadTree") or asset.startswith("Prop_Crate"):
            o["kind"] = "tree" if asset.startswith("DeadTree") else "crate"
            if o["kind"] == "tree":
                o["tint"] = [0.4, 0.4, 0.3]
                o["trunk"] = list(lc.TRUNKS.get(asset, (0.5, 0, 0)))
                blockers.append(("circle", [x, z, o["trunk"][0]]))
            else:
                blockers.append(("circle", [x, z, 0.76]))
        objects.append(o)

    level = {"district": name, "objects": objects, "blockers": blockers, "behind_boxes": behind_boxes,
             "merged_walls": merged_walls}
    json.dump(level, open(os.path.join(BUILD_DIR, "%s.json" % name), "w"))
    kinds = {}
    for o in objects:
        kinds[o["kind"]] = kinds.get(o["kind"], 0) + 1
    print("%s: %s%s" % (name, kinds, ", %d wall pieces merged" % len(merged_walls) if merged_walls else ""))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "hub")
