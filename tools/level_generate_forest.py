"""Regenerate the forest in level_design/level_map.xlsx from the drawn path.

Usage (from the project root):
    python tools/level_generate_forest.py

Reads the P / SPS path cells, joins them into a route (minimum spanning tree:
the main path plus any side branches), keeps a drivable corridor along it, and
fills the rest of the forest with trees on a checkerboard of cells - two
diagonal trunks ~1.4 m apart leave no gap the robot fits through, so the
forest is sealed. Dead-end branches get a small clearing and a collectible.
Every other token in the sheet is left alone; all existing tree codes are
replaced. Run tools/level_build.py afterwards to rebuild the level.
"""
import math
import sys

import level_common as lc

CORRIDOR_HALF_WIDTH = 1.1      # clear ground either side of the route centre line
DEAD_END_CLEARING = 2.2        # radius of the clearing at a dead end
MIN_DEAD_END_LENGTH = 4.0      # shorter side spurs are just wiggles in the path
DENSE_BAND = 6.0               # full density within this distance of reachable ground
FOREST_NORTH_EDGE = -50        # forest fills z >= this; north of it is the hill / city
OPEN_BORDER_COLUMNS = 4        # sealed tree columns either side of the hill / city area
OPEN_BORDER_ROWS = 4           # sealed tree rows along the north edge
HOUSE_STRIP = 1.2              # walkable gap left between trunks and the house walls
MODELS = ["CommonTree_1", "CommonTree_3", "CommonTree_5", "DeadTree_1", "TwistedTree_2", "TwistedTree_4"]
CODE_OF = {v: k for k, v in lc.TREE_CODES.items()}


def mst(points):
    """Prim's algorithm; returns edges (i, j)."""
    n = len(points)
    in_tree = [False] * n
    best = [(math.inf, -1)] * n
    best[0] = (0.0, -1)
    edges = []
    for _ in range(n):
        i = min((k for k in range(n) if not in_tree[k]), key=lambda k: best[k][0])
        in_tree[i] = True
        if best[i][1] >= 0:
            edges.append((best[i][1], i))
        for k in range(n):
            if not in_tree[k]:
                d = math.dist(points[i], points[k])
                if d < best[k][0]:
                    best[k] = (d, i)
    return edges


def route(sheet):
    pts = sorted({(x, z) for x, z, toks in sheet.cells()
                  if any(lc.parse_token(t)[0] in ("P", "SPS") for t in toks)})
    if not pts:
        sys.exit("No P or SPS cells in the Layout sheet - draw the path first.")
    edges = mst(pts)
    nbrs = {i: [] for i in range(len(pts))}
    for a, b in edges:
        nbrs[a].append(b)
        nbrs[b].append(a)
    door = (0.0, lc.HOUSE_MIN[1] - 0.2)
    start = min(range(len(pts)), key=lambda i: math.dist(pts[i], door))
    exit_ = min(range(len(pts)), key=lambda i: pts[i][1])          # furthest north
    dead_ends = []
    for leaf in (i for i, v in nbrs.items() if len(v) == 1 and i not in (start, exit_)):
        length, prev, cur = 0.0, None, leaf
        while True:                                                 # walk back to a junction
            nxt = [k for k in nbrs[cur] if k != prev]
            if len(nbrs[cur]) >= 3 or not nxt or cur in (start, exit_):
                break
            length += math.dist(pts[cur], pts[nxt[0]])
            prev, cur = cur, nxt[0]
        if length >= MIN_DEAD_END_LENGTH:
            dead_ends.append(pts[leaf])
    segments = [(pts[a], pts[b]) for a, b in edges]
    segments.append((door, pts[start]))                             # door to first path cell
    ex = pts[exit_]
    segments.append((ex, (ex[0], FOREST_NORTH_EDGE - 3.0)))         # out onto the hill
    return pts, segments, dead_ends, pts[start], ex


def main():
    sheet = lc.Sheet()
    assets = lc.load_assets()
    pts, segments, dead_ends, start, exit_ = route(sheet)
    print("route: %d path cells, start %s, exit %s, dead ends %s" % (len(pts), start, exit_, dead_ends))

    # Obstacles already in the sheet (walls, buildings, props) that trees must avoid.
    walls, boxes, props = [], [], []
    for x, z, toks in sheet.cells():
        for t in toks:
            code, _, heading = lc.parse_token(t)
            if code not in lc.CODES or code in lc.TREE_CODES:
                continue
            asset, kind = lc.CODES[code]
            if kind == "wall":
                a = math.radians(-heading)
                dx, dz = math.cos(a), -math.sin(a)                   # wall runs along its local X
                walls.append((x - dx, z - dz, x + dx, z + dz))
            elif kind == "building":
                lo, hi = assets[asset]["min"], assets[asset]["max"]
                boxes.append(((x + lo[0], z + lo[2]), (x + hi[0], z + hi[2])))
            elif kind not in ("collectible",):
                props.append((x, z))

    def corridor_distance(x, z):
        return min(lc.point_segment_distance(x, z, a[0], a[1], b[0], b[1]) for a, b in segments)

    def in_open_area(x, z):
        return z < FOREST_NORTH_EDGE

    def in_open_border(x, z):
        return in_open_area(x, z) and (x < sheet.x_min + OPEN_BORDER_COLUMNS or
                                       x > sheet.x_max - OPEN_BORDER_COLUMNS or
                                       z < sheet.z_min + OPEN_BORDER_ROWS)

    def reach_distance(x, z):
        """Distance to ground the player can reach (path, clearings, house strip, hill/city)."""
        d = corridor_distance(x, z) - CORRIDOR_HALF_WIDTH
        for de in dead_ends:
            d = min(d, math.dist((x, z), de) - DEAD_END_CLEARING)
        d = min(d, lc.box_distance(x, z, lc.HOUSE_MIN, lc.HOUSE_MAX) - HOUSE_STRIP)
        if not in_open_area(x, z):
            d = min(d, z - FOREST_NORTH_EDGE)
        return d

    placed = {}
    skipped = 0
    for x in sheet.xs:
        for z in sheet.zs:
            if (x + z) % 2:
                continue
            if in_open_area(x, z) and not in_open_border(x, z):
                continue
            reach = reach_distance(x, z)
            if not in_open_area(x, z) and reach > DENSE_BAND and (x % 2 or z % 2):
                continue                                             # deep interior: half density
            if any(math.dist((x, z), p) < 1.5 for p in props):
                continue
            house_d = lc.box_distance(x, z, lc.HOUSE_MIN, lc.HOUSE_MAX)
            corr_d = corridor_distance(x, z)
            choices = sorted(MODELS, key=lambda m: lc.cell_hash(x, z, MODELS.index(m)))
            chosen = None
            for m in choices:
                r = lc.TRUNKS[m][0]
                low = assets[m]["spread_below_3m"]
                roof = assets[m]["spread_below_house_roof"]
                if corr_d - r < CORRIDOR_HALF_WIDTH:
                    continue                                         # trunk would narrow the path
                if corr_d < CORRIDOR_HALF_WIDTH + 3 and low > corr_d + 0.5:
                    continue                                         # low branches hang across the path
                if any(math.dist((x, z), de) - r < DEAD_END_CLEARING for de in dead_ends):
                    continue
                if house_d - r < HOUSE_STRIP or house_d < roof + 0.2:
                    continue                                         # trunk or branches in the house
                if any(lc.point_segment_distance(x, z, *w) - r < 0.45 for w in walls):
                    continue
                if any(lc.box_distance(x, z, lo, hi) - r < 0.3 for lo, hi in boxes):
                    continue
                chosen = m
                break
            if chosen is None:
                skipped += 1
                continue
            heading = (lc.cell_hash(x, z, 99) % 24) * 15
            placed[(x, z)] = lc.format_token(CODE_OF[chosen], 0.0, heading)

    # Write back: drop every old tree and collectible code, add the new ones.
    for x in sheet.xs:
        for z in sheet.zs:
            toks = [t for t in sheet.tokens(x, z)
                    if lc.parse_token(t)[0] not in lc.TREE_CODES and not lc.parse_token(t)[0].startswith("CP")]
            if (x, z) in placed:
                toks.append(placed[(x, z)])
            sheet.set_tokens(x, z, toks)
    for i, (x, z) in enumerate(sorted(dead_ends, key=lambda p: p[0]), start=1):
        sheet.set_tokens(x, z, sheet.tokens(x, z) + ["CP%d" % i])
    sheet.save()
    counts = {}
    for t in placed.values():
        counts[t[:3]] = counts.get(t[:3], 0) + 1
    print("trees placed: %d (%s), cells with no model that fits: %d" % (
        len(placed), ", ".join("%s %d" % kv for kv in sorted(counts.items())), skipped))
    print("collectibles:", ["CP%d at %s" % (i, p) for i, p in enumerate(sorted(dead_ends, key=lambda p: p[0]), 1)])


if __name__ == "__main__":
    main()
