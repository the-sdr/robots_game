"""Drive routes from the house door to every design node, for the physics drive test.

Usage (from the project root):
    python tools/forest_routes.py            -> level_design/build/routes.json
    <godot> --headless --path . -s tools/forest_drive_test.gd

Each route follows the design's own path curves (shortest way through the path
graph), sampled every few metres, so the robot drives exactly what was designed.
"""
import heapq
import json
import math
import os

from forest_map import Design, catmull_rom

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "level_design", "build", "routes.json")


def main():
    design = Design()
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
        dist, prev, heap = {"door": 0.0}, {}, [(0.0, "door")]
        while heap:
            d, u = heapq.heappop(heap)
            if u == target:
                break
            for v, length, curve in edges.get(u, []):
                if d + length < dist.get(v, 1e9):
                    dist[v], prev[v] = d + length, (u, curve)
                    heapq.heappush(heap, (dist[v], v))
        pts, n = [], target
        while n != "door":
            u, curve = prev[n]
            pts = curve + pts[1:] if pts else curve
            n = u
        return [[round(x, 2), round(z, 2)] for x, z in pts]

    targets = [n for n, v in design.nodes.items() if v["kind"] not in ("blocker", "start")]
    routes = {t: route(t) for t in targets}
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    json.dump(routes, open(OUT, "w"))
    print("wrote %s: %d routes" % (OUT, len(routes)))


if __name__ == "__main__":
    main()
