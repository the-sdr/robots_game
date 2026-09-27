"""Check a built district (level_design/build/<name>.json): sealed, every place reachable, gates hold?

Usage (from the project root, after tools/district_build.py <name>):
    python tools/district_verify.py hub [--map]

Same method as forest_verify.py: flood-fill from the start node on a 0.25 m
grid with the robot as a circle; buildings, wall pieces, gates, chargers,
solids and the forest's own border trees (from build/level.json) are solid.
Places with "behind" must be sealed until their blocker is cleared, and
reachable once it is. Ground reachable away from any street is a leak.
"""
import json
import os
import sys

import numpy as np

import level_common as lc
from district_build import load_design
from forest_map import Design

CELL = 0.25
LEAK_MARGIN = 2.5


def main(name="hub"):
    d = load_design(name)
    design = Design(os.path.join(lc.ROOT, "level_design", "%s_design.json" % name))
    level = json.load(open(os.path.join(lc.ROOT, "level_design", "build", "%s.json" % name)))
    forest = json.load(open(os.path.join(lc.ROOT, "level_design", "build", "level.json")))
    b = d["bounds"]
    x0, x1, z0, z1 = b["x_min"] - 3, b["x_max"] + 3, b["z_min"] - 3, b["z_max"] + 6
    nx, nz = int((x1 - x0) / CELL) + 1, int((z1 - z0) / CELL) + 1
    GX, GZ = np.meshgrid(x0 + np.arange(nx) * CELL, z0 + np.arange(nz) * CELL)
    blocked = np.zeros((nz, nx), dtype=bool)
    R = lc.ROBOT_RADIUS

    def circle(cx, cz, r):
        blocked[(GX - cx) ** 2 + (GZ - cz) ** 2 < (r + R) ** 2] = True

    def segment(ax, az, bx, bz, half):
        dx, dz = bx - ax, bz - az
        L = dx * dx + dz * dz or 1e-9
        t = np.clip(((GX - ax) * dx + (GZ - az) * dz) / L, 0, 1)
        blocked[np.hypot(GX - (ax + t * dx), GZ - (az + t * dz)) < half + R] = True

    def box(bx0, bz0, bx1, bz1):
        blocked[(GX > bx0 - R) & (GX < bx1 + R) & (GZ > bz0 - R) & (GZ < bz1 + R)] = True

    behind = level.get("behind_boxes", {})
    for kind, data in level["blockers"]:
        if kind == "box" and list(data) not in behind.values():
            box(*data)
        elif kind == "circle":
            circle(*data)
        elif kind == "segment":
            segment(*data)
    trees = 0
    for o in forest["objects"] + forest["interior"]:        # the forest's border rows seal the district
        if o["kind"] == "tree" and x0 <= o["origin"][0] <= x1 and z0 <= o["origin"][2] <= z1:
            r, ox, oz = o["trunk"]
            bb = o["basis"]
            circle(o["origin"][0] + bb[0] * ox + bb[2] * oz, o["origin"][2] + bb[6] * ox + bb[8] * oz, r)
            trees += 1
    blocked[0, :] = blocked[-1, :] = blocked[:, 0] = blocked[:, -1] = True
    open_blocked = blocked.copy()
    for bx0, bz0, bx1, bz1 in behind.values():
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
                    a, c = i + di, j + dj
                    if not grid[a, c] and not seen[a, c]:
                        seen[a, c] = True
                        nxt.append((a, c))
            frontier = nxt
        return seen

    def near(seen, x, z, cells=6):
        i, j = idx(x, z)
        return bool(seen[max(0, i - cells):i + cells + 1, max(0, j - cells):j + cells + 1].any())

    start = idx(*design.nodes[d["start"]]["pos"])
    if blocked[start]:
        print("START BLOCKED at", design.nodes[d["start"]]["pos"])
        return 1
    seen = flood(blocked, start)
    seen_open = flood(open_blocked, start)

    allowed = np.zeros_like(seen)
    for p in design.paths.values():
        curve = p["curve"]
        dmin = np.full(GX.shape, np.inf)
        for (ax, az), (bx, bz) in zip(curve[:-1], curve[1:]):
            dx, dz = bx - ax, bz - az
            L = dx * dx + dz * dz or 1e-9
            t = np.clip(((GX - ax) * dx + (GZ - az) * dz) / L, 0, 1)
            dmin = np.minimum(dmin, np.hypot(GX - (ax + t * dx), GZ - (az + t * dz)))
        allowed |= dmin < p["width"] / 2 + LEAK_MARGIN
    for n in design.nodes.values():
        allowed |= np.hypot(GX - n["pos"][0], GZ - n["pos"][1]) < n.get("radius", 2.0) + LEAK_MARGIN
    allowed |= GZ > b["z_max"]                    # the open hill south of the district
    leaks = seen_open & ~allowed
    print("%s: border trees %d | reachable ground %.0f m2 (all gates open %.0f) | leak cells %d" % (
        name, trees, seen.sum() * CELL * CELL, seen_open.sum() * CELL * CELL, leaks.sum()))
    if leaks.any():
        li, lj = np.nonzero(leaks)
        pts = sorted({(round(GX[i, j]), round(GZ[i, j])) for i, j in zip(li, lj)})
        print("  leaks near:", pts[:: max(1, len(pts) // 12)])
    ok = not leaks.any()
    plain = gated = 0
    for nm, n in design.nodes.items():
        if n.get("behind"):
            gated += 1
            if near(seen, *n["pos"]):
                ok = False
                print("  REACHABLE TOO EARLY (behind %s): %s at %s" % (n["behind"], nm, n["pos"]))
            if not near(seen_open, *n["pos"]):
                ok = False
                print("  NOT REACHABLE even with %s cleared: %s at %s" % (n["behind"], nm, n["pos"]))
            continue
        plain += 1
        if not near(seen, *n["pos"]):
            ok = False
            print("  NOT REACHABLE: %s at %s" % (nm, n["pos"]))
    print("  %d open places reachable, %d sealed behind gates until cleared: %s" % (plain, gated, "yes" if ok else "NO"))
    print("RESULT:", "OK - sealed and completable" if ok else "PROBLEMS FOUND")
    if "--map" in sys.argv:
        from PIL import Image
        img = np.zeros(blocked.shape + (3,), dtype=np.uint8)
        img[:] = (40, 70, 40)
        img[seen_open] = (200, 185, 140)
        img[seen] = (230, 215, 170)
        img[leaks] = (230, 40, 40)
        img[blocked & ~seen] = (25, 45, 25)
        out = os.path.join(lc.ROOT, "level_design", "maps", "%s_reachable.png" % name)
        Image.fromarray(img[::-1]).resize((nx * 3, nz * 3), Image.NEAREST).save(out)
        print("  map:", out)
    return 0 if ok else 1


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    sys.exit(main(args[0] if args else "hub"))
