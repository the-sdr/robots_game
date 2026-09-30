"""Drive routes from the house door to every design node, for the physics drive test.

Usage (from the project root):
    python tools/forest_routes.py            -> level_design/build/routes.json
    python tools/forest_routes.py --design hub --start hub_entry --out hub_routes.json
    <godot> --headless --fixed-fps 60 --path . -s tools/forest_drive_test.gd

Each route follows the design's own path curves (shortest way through the path
graph), sampled every few metres, so the robot drives exactly what was designed.
A route to a node with "behind" names the blocker that must be cleared first.
"""
import heapq
import json
import math
import os
import sys

from forest_map import Design, catmull_rom

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    args = sys.argv[1:]
    def opt(flag, default):
        return args[args.index(flag) + 1] if flag in args else default
    name = opt("--design", "forest")
    start_node = opt("--start", "door")
    out = os.path.join(ROOT, "level_design", "build", opt("--out", "routes.json"))
    design = Design(os.path.join(ROOT, "level_design", "%s_design.json" % name))
    edges = {}
    for p in design.d["paths"]:
        pts = p["points"]
        named = [i for i, q in enumerate(pts) if isinstance(q, str)]
        for ia, ib in zip(named, named[1:]):
            seq = [design.nodes[q]["pos"] if isinstance(q, str) else q for q in pts[ia:ib + 1]]
            curve = catmull_rom([list(map(float, q)) for q in seq], samples=4) if len(seq) >= 3 else [tuple(seq[0]), tuple(seq[-1])]
            length = sum(math.dist(curve[k], curve[k + 1]) for k in range(len(curve) - 1))
            a, b = pts[ia], pts[ib]
            edges.setdefault(a, []).append((b, length, curve))
            edges.setdefault(b, []).append((a, length, list(reversed(curve))))

    def route(target):
        dist, prev, heap = {start_node: 0.0}, {}, [(0.0, start_node)]
        while heap:
            d, u = heapq.heappop(heap)
            if u == target:
                break
            for v, length, curve in edges.get(u, []):
                if d + length < dist.get(v, 1e9):
                    dist[v], prev[v] = d + length, (u, curve)
                    heapq.heappush(heap, (dist[v], v))
        pts, n = [], target
        while n != start_node:
            u, curve = prev[n]
            pts = curve + pts[1:] if pts else curve
            n = u
        dense = [pts[0]]                 # straight legs get a point every <= 3 m (the driver's per-point budget)
        for a, b in zip(pts, pts[1:]):
            steps = max(1, int(math.ceil(math.dist(a, b) / 3.0)))
            for k in range(1, steps + 1):
                dense.append((a[0] + (b[0] - a[0]) * k / steps, a[1] + (b[1] - a[1]) * k / steps))
        return [[round(x, 2), round(z, 2)] for x, z in dense]

    targets = [n for n, v in design.nodes.items() if v["kind"] not in ("blocker", "start")]
    routes = {t: {"points": route(t), "behind": design.nodes[t].get("behind")} for t in targets}
    routes["_start"] = {"node": start_node, "pos": design.nodes[start_node]["pos"]}
    os.makedirs(os.path.dirname(out), exist_ok=True)
    json.dump(routes, open(out, "w"))
    print("wrote %s: %d routes" % (out, len(routes) - 1))


if __name__ == "__main__":
    main()
