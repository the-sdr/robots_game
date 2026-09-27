"""Check the level map: is the forest sealed, and can the robot reach what it should?

Usage (from the project root):
    python tools/level_verify.py [--map]

Flood-fills from outside the house door on a 0.2 m grid, treating the robot as
a circle of its collision radius and every trunk, ruin wall, house wall and
building as solid. Reports any reachable ground far from the path (a leak) and
whether the hill crest and each collectible can be reached. --map prints an
ASCII overview (1 char = 1 m).
"""
import math
import sys

import numpy as np

import level_common as lc
from level_generate_forest import route, CORRIDOR_HALF_WIDTH, DEAD_END_CLEARING, FOREST_NORTH_EDGE, HOUSE_STRIP

CELL = 0.2
LEAK_MARGIN = 2.0      # reachable ground this far beyond the corridor/clearings counts as a leak


def main():
    sheet = lc.Sheet()
    assets = lc.load_assets()
    x0, x1 = sheet.x_min - 0.5, sheet.x_max + 0.5
    z0, z1 = sheet.z_min - 0.5, sheet.z_max + 0.5
    nx, nz = int((x1 - x0) / CELL) + 1, int((z1 - z0) / CELL) + 1
    X = x0 + np.arange(nx) * CELL
    Z = z0 + np.arange(nz) * CELL
    GX, GZ = np.meshgrid(X, Z)
    blocked = np.zeros((nz, nx), dtype=bool)
    R = lc.ROBOT_RADIUS

    def block_circle(cx, cz, r):
        blocked[(GX - cx) ** 2 + (GZ - cz) ** 2 < (r + R) ** 2] = True

    def block_segment(ax, az, bx, bz, half):
        dx, dz = bx - ax, bz - az
        L = dx * dx + dz * dz
        t = np.clip(((GX - ax) * dx + (GZ - az) * dz) / L, 0, 1)
        blocked[np.hypot(GX - (ax + t * dx), GZ - (az + t * dz)) < half + R] = True

    collectibles = []
    plants = []
    trees = 0
    for x, z, toks in sheet.cells():
        for tok in toks:
            code, _, heading = lc.parse_token(tok)
            if code in lc.TREE_CODES:
                r, ox, oz = lc.TRUNKS[lc.TREE_CODES[code]]
                a = math.radians(-heading)
                cx = x + ox * math.cos(a) + oz * math.sin(a)
                cz = z - ox * math.sin(a) + oz * math.cos(a)
                block_circle(cx, cz, r)
                trees += 1
            elif code == "WUB":
                a = math.radians(-heading)
                dx, dz = math.cos(a), -math.sin(a)
                block_segment(x - dx, z - dz, x + dx, z + dz, lc.WALL_SIZE[2] / 2)
            elif code in lc.CODES and lc.CODES[code][1] == "building":
                lo, hi = assets[lc.CODES[code][0]]["min"], assets[lc.CODES[code][0]]["max"]
                blocked[(GX > x + lo[0] - R) & (GX < x + hi[0] + R) & (GZ > z + lo[2] - R) & (GZ < z + hi[2] + R)] = True
            elif code == "RM1":
                block_circle(x, z, 1.2)
                plants.append((x, z))
            elif code.startswith("CP"):
                collectibles.append((code, x, z))
            elif code in lc.CODES and lc.CODES[code][1] in ("bush", "prop", "rock"):
                plants.append((x, z))
    # House walls (outline of HouseCollision) with the door gap on the north face.
    (hx0, hz0), (hx1, hz1) = lc.HOUSE_MIN, lc.HOUSE_MAX
    for seg in [((hx0, hz0), (hx0, hz1)), ((hx1, hz0), (hx1, hz1)), ((hx0, hz1), (hx1, hz1)),
                ((hx0, hz0), (-0.7, hz0)), ((0.7, hz0), (hx1, hz0))]:
        block_segment(seg[0][0], seg[0][1], seg[1][0], seg[1][1], 0.1)
    # The map edge is the edge of the world for this check.
    blocked[0, :] = blocked[-1, :] = blocked[:, 0] = blocked[:, -1] = True

    def idx(x, z):
        return int(round((z - z0) / CELL)), int(round((x - x0) / CELL))

    start = idx(0.0, lc.HOUSE_MIN[1] - 0.6)
    if blocked[start]:
        sys.exit("Start point outside the door is blocked")
    seen = np.zeros_like(blocked)
    seen[start] = True
    frontier = [start]
    while frontier:
        nxt = []
        for i, j in frontier:
            for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                a, b = i + di, j + dj
                if not blocked[a, b] and not seen[a, b]:
                    seen[a, b] = True
                    nxt.append((a, b))
        frontier = nxt

    pts, segments, dead_ends, _, _ = route(sheet)
    corr = np.full(blocked.shape, np.inf)
    for (ax, az), (bx, bz) in segments:
        dx, dz = bx - ax, bz - az
        L = dx * dx + dz * dz or 1e-9
        t = np.clip(((GX - ax) * dx + (GZ - az) * dz) / L, 0, 1)
        corr = np.minimum(corr, np.hypot(GX - (ax + t * dx), GZ - (az + t * dz)) - CORRIDOR_HALF_WIDTH)
    allowed = corr < LEAK_MARGIN
    for de in dead_ends:
        allowed |= np.hypot(GX - de[0], GZ - de[1]) < DEAD_END_CLEARING + LEAK_MARGIN
    hd = np.hypot(np.maximum(np.maximum(hx0 - GX, GX - hx1), 0), np.maximum(np.maximum(hz0 - GZ, GZ - hz1), 0))
    allowed |= hd < HOUSE_STRIP + LEAK_MARGIN
    allowed |= GZ < FOREST_NORTH_EDGE + 0.5
    for px, pz in plants:                      # trees keep clear of plants/rocks: small bounded nooks
        allowed |= np.hypot(GX - px, GZ - pz) < 3.0
    leaks = seen & ~allowed

    print("trees %d | reachable ground %.0f m2 | leak cells %d" % (trees, seen.sum() * CELL * CELL, leaks.sum()))
    if leaks.any():
        li, lj = np.nonzero(leaks)
        for k in range(0, len(li), max(1, len(li) // 10)):
            print("  leak near (%.1f, %.1f)" % (X[lj[k]], Z[li[k]]))
    targets = [("hill crest", 0.0, -57.0)] + [(c, x, z) for c, x, z in collectibles]
    ok = not leaks.any()
    for name, x, z in targets:
        near = seen[max(0, idx(x, z)[0] - 5):idx(x, z)[0] + 6, max(0, idx(x, z)[1] - 5):idx(x, z)[1] + 6].any()
        print("  %-10s at (%5.1f, %5.1f): %s" % (name, x, z, "reachable" if near else "NOT REACHABLE"))
        ok &= bool(near)
    print("RESULT:", "OK - sealed and completable" if ok else "PROBLEMS FOUND")

    if "--map" in sys.argv:
        for z in range(sheet.z_min, sheet.z_max + 1):
            row = ""
            for x in range(sheet.x_min, sheet.x_max + 1):
                i, j = idx(x, z)
                toks = [lc.parse_token(t)[0] for t in sheet.tokens(x, z)]
                if any(t in lc.TREE_CODES for t in toks): ch = "#"
                elif any(t.startswith("CP") for t in toks): ch = "*"
                elif "WUB" in toks: ch = "W"
                elif any(t in ("SHO", "SCH", "SPN", "X") for t in toks): ch = "H"
                elif leaks[i, j]: ch = "!"
                elif seen[i, j]: ch = "."
                else: ch = " "
                row += ch
            print("%4d %s" % (z, row))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
