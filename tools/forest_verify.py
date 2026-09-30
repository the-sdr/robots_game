"""Check the built forest (level_design/build/level.json): sealed, and every place reachable?

Usage (from the project root, after tools/forest_build.py):
    python tools/forest_verify.py [--map]

Flood-fills from outside the house door on a 0.25 m grid, treating the robot
as a circle of its collision radius and every trunk, rock, wall, ruin piece,
building, bramble patch, house wall and the Fallen Giant (except its raised
middle, which the stream passes under) as solid. Reports ground reachable far
from any designed path or clearing (a leak), and whether every design place
and the hill crest can be reached. --map writes a PNG of the reachable area.
"""
import json
import math
import os
import sys

import numpy as np

import level_common as lc
from forest_build import Forest, GIANT_BLOCKERS

CELL = 0.25
LEAK_MARGIN = 2.5        # reachable this far beyond a path edge counts as a leak (small nooks are fine)


def main():
    f = Forest()
    level = json.load(open(os.path.join(lc.ROOT, "level_design", "build", "level.json")))
    fb, north = f.fb, f.north
    x0, x1 = fb["x_min"] - 1, fb["x_max"] + 1
    z0, z1 = north["z_min"] - 1, fb["z_max"] + 1
    nx, nz = int((x1 - x0) / CELL) + 1, int((z1 - z0) / CELL) + 1
    GX, GZ = np.meshgrid(x0 + np.arange(nx) * CELL, z0 + np.arange(nz) * CELL)
    blocked = np.zeros((nz, nx), dtype=bool)
    R = lc.ROBOT_RADIUS

    def circle(cx, cz, r):
        i0, i1 = max(int((cz - r - R - z0) / CELL), 0), min(int((cz + r + R - z0) / CELL) + 2, nz)
        j0, j1 = max(int((cx - r - R - x0) / CELL), 0), min(int((cx + r + R - x0) / CELL) + 2, nx)
        sub = (GX[i0:i1, j0:j1] - cx) ** 2 + (GZ[i0:i1, j0:j1] - cz) ** 2 < (r + R) ** 2
        blocked[i0:i1, j0:j1] |= sub

    def segment(ax, az, bx, bz, half):
        dx, dz = bx - ax, bz - az
        L = dx * dx + dz * dz or 1e-9
        t = np.clip(((GX - ax) * dx + (GZ - az) * dz) / L, 0, 1)
        blocked[np.hypot(GX - (ax + t * dx), GZ - (az + t * dz)) < half + R] = True

    def box(bx0, bz0, bx1, bz1):
        blocked[(GX > bx0 - R) & (GX < bx1 + R) & (GZ > bz0 - R) & (GZ < bz1 + R)] = True

    trees = 0
    for o in level["objects"] + level["interior"]:
        if o["kind"] == "tree":
            r, ox, oz = o["trunk"]
            b = o["basis"]
            cx = o["origin"][0] + b[0] * ox + b[2] * oz
            cz = o["origin"][2] + b[6] * ox + b[8] * oz
            circle(cx, cz, r)
            trees += 1
        elif o["kind"] == "rock":
            circle(o["origin"][0], o["origin"][2], o.get("collision_radius", 0.8))
        elif o["kind"] == "wall":
            b = o["basis"]
            dx, dz = b[0], b[6]
            ox_, oz_ = o["origin"][0] + b[2] * lc.WALL_CENTRE_Z, o["origin"][2] + b[8] * lc.WALL_CENTRE_Z
            segment(ox_ - dx, oz_ - dz, ox_ + dx, oz_ + dz, lc.WALL_SIZE[2] / 2)
    behind_boxes = level.get("behind_boxes", {})
    for kind, data in level["blockers"]:
        if kind == "box" and list(data) not in behind_boxes.values():
            box(*data)
        elif kind == "circle" and data[2] > 0:
            circle(*data)
    for o in level["objects"]:
        if o["kind"] == "charger":
            circle(o["origin"][0], o["origin"][2], 0.85)
    for seg in f.giant_segments(full=False):           # raised middle is passable
        segment(*seg)
    (hx0, hz0), (hx1, hz1) = lc.HOUSE_MIN, lc.HOUSE_MAX
    for a, b in [((hx0, hz0), (hx0, hz1)), ((hx1, hz0), (hx1, hz1)), ((hx0, hz1), (hx1, hz1)),
                 ((hx0, hz0), (-0.7, hz0)), ((0.7, hz0), (hx1, hz0))]:
        segment(a[0], a[1], b[0], b[1], 0.1)
    blocked[0, :] = blocked[-1, :] = blocked[:, 0] = blocked[:, -1] = True
    blocked[(GZ < fb["z_min"]) & ((GX < north["x_min"]) | (GX > north["x_max"]))] = True
    open_blocked = blocked.copy()                      # every blocker cleared (brambles cut)
    for bx0, bz0, bx1, bz1 in behind_boxes.values():
        box(bx0, bz0, bx1, bz1)

    def idx(x, z):
        return int(round((z - z0) / CELL)), int(round((x - x0) / CELL))

    def flood(grid, start):
        seen = np.zeros_like(grid)
        seen[start] = True
        frontier = [start]
        while frontier:
            nxt = []
            for i, j in frontier:
                for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    a, b = i + di, j + dj
                    if not grid[a, b] and not seen[a, b]:
                        seen[a, b] = True
                        nxt.append((a, b))
            frontier = nxt
        return seen

    def near(seen, x, z, cells=6):
        i, j = idx(x, z)
        return bool(seen[max(0, i - cells):i + cells + 1, max(0, j - cells):j + cells + 1].any())

    start = idx(0.0, lc.HOUSE_MIN[1] - 0.6)
    seen = flood(blocked, start)
    seen_open = flood(open_blocked, start)

    # allowed ground: along any path / clearing / node, the hill+city area, and small nooks
    allowed = np.zeros_like(seen)
    for p in f.design.paths.values():
        curve = p["curve"]
        dmin = np.full(GX.shape, np.inf)
        for (ax, az), (bx, bz) in zip(curve[:-1], curve[1:]):
            dx, dz = bx - ax, bz - az
            L = dx * dx + dz * dz or 1e-9
            t = np.clip(((GX - ax) * dx + (GZ - az) * dz) / L, 0, 1)
            dmin = np.minimum(dmin, np.hypot(GX - (ax + t * dx), GZ - (az + t * dz)))
        allowed |= dmin < p["width"] / 2 + LEAK_MARGIN
    for n in f.design.nodes.values():
        r = n.get("radius", 2.0)
        allowed |= np.hypot(GX - n["pos"][0], GZ - n["pos"][1]) < r + LEAK_MARGIN
    allowed |= GZ < fb["z_min"] + 2.5         # the meadow side of the edge row
    for o in level["objects"]:
        if o["kind"] in ("rock", "building", "wall"):
            allowed |= np.hypot(GX - o["origin"][0], GZ - o["origin"][2]) < 4.0
    for ax, az, bx, bz, hw in f.giant_segments(full=True):     # nooks hugging the Giant
        dx, dz = bx - ax, bz - az
        L = dx * dx + dz * dz or 1e-9
        t = np.clip(((GX - ax) * dx + (GZ - az) * dz) / L, 0, 1)
        allowed |= np.hypot(GX - (ax + t * dx), GZ - (az + t * dz)) < hw + 3.5
    for kind, data in level["blockers"]:
        if kind == "box":
            allowed |= (GX > data[0] - 3) & (GX < data[2] + 3) & (GZ > data[1] - 3) & (GZ < data[3] + 3)
    hd = np.hypot(np.maximum(np.maximum(hx0 - GX, GX - hx1), 0), np.maximum(np.maximum(hz0 - GZ, GZ - hz1), 0))
    allowed |= hd < 3.0
    leaks = seen_open & ~allowed              # with every blocker cleared, still nothing leaks

    print("trees %d | reachable ground %.0f m2 | leak cells %d" % (trees, seen.sum() * CELL * CELL, leaks.sum()))
    if leaks.any():
        li, lj = np.nonzero(leaks)
        pts = sorted({(round(GX[i, j]), round(GZ[i, j])) for i, j in zip(li, lj)})
        print("  leaks near:", pts[:: max(1, len(pts) // 12)])
    ok = not leaks.any()
    plain = behind = 0
    for name, n in list(f.design.nodes.items()):
        if n["kind"] == "blocker":
            continue
        if n.get("behind"):
            behind += 1
            if near(seen, *n["pos"]):
                ok = False
                print("  REACHABLE TOO EARLY (behind %s): %s at %s" % (n["behind"], name, n["pos"]))
            if not near(seen_open, *n["pos"]):
                ok = False
                print("  NOT REACHABLE even with %s cleared: %s at %s" % (n["behind"], name, n["pos"]))
            continue
        plain += 1
        if not near(seen, *n["pos"]):
            ok = False
            print("  NOT REACHABLE: %s at %s" % (name, n["pos"]))
    print("  all %d open design places reachable, %d places sealed behind blockers until cleared: %s" % (plain, behind, "yes" if ok else "NO"))
    # Gate test: with the Ruin Grove and the Dry Clearing blocked, the way north must be shut
    # (proves nothing slips past the Fallen Giant), even with every blocker cleared.
    gated = open_blocked.copy()
    for name in ("ruin", "clearing"):
        n = f.design.nodes[name]
        gated |= np.hypot(GX - n["pos"][0], GZ - n["pos"][1]) < n.get("radius", 4) + 1.0
    seen2 = flood(gated, start)
    sneaky = near(seen2, *f.design.nodes["edge_join"]["pos"])
    print("  only ways north are via the Ruin Grove or the Dry Clearing: %s" % ("yes" if not sneaky else "NO - a bypass exists"))
    ok &= not sneaky
    print("RESULT:", "OK - sealed and completable" if ok else "PROBLEMS FOUND")

    if "--map" in sys.argv:
        from PIL import Image
        img = np.zeros(blocked.shape + (3,), dtype=np.uint8)
        img[:] = (40, 70, 40)
        img[seen_open] = (200, 185, 140)
        img[seen] = (230, 215, 170)
        img[leaks] = (230, 40, 40)
        img[blocked & ~seen] = (25, 45, 25)
        out = os.path.join(lc.ROOT, "level_design", "maps", "reachable.png")
        Image.fromarray(img).resize((nx * 2, nz * 2), Image.NEAREST).save(out)
        print("  map:", out)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
