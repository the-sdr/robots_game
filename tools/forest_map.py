"""Render the forest design (level_design/forest_design.json) as a top-down review map.

Usage (from the project root):
    python tools/forest_map.py [output.png]            design review map
    python tools/forest_map.py --built [output.png]    same, plus everything the last build placed

Default output: level_design/maps/forest_map_v<version>.png. North (-Z) is up,
grid lines every 10 m with the same X/Z numbers as the F2 overlay. Pure
Python drawing - no game or GPU involved.
"""
import heapq
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DESIGN = os.path.join(ROOT, "level_design", "forest_design.json")

X0, X1, Z0, Z1 = -42, 42, -96, 16      # world area drawn
S = 9                                   # pixels per metre
M = 46                                  # margin around the map (px)
PANEL = 400                             # legend panel width (px)

PATH_FILL = (232, 217, 176)
PATH_EDGE = (120, 95, 60)
MAIN_EDGE = (70, 45, 20)
STREAM = (110, 150, 175)
INK = (30, 30, 30)
GIANT = (60, 50, 70)


def font(size):
    return ImageFont.load_default(size=size)


def px(x, z):
    return (M + (x - X0) * S, M + (z - Z0) * S)


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def catmull_rom(points, samples=12):
    """Smooth curve through all points."""
    if len(points) < 3:
        return [tuple(points[0]), tuple(points[-1])]
    pts = [points[0]] + points + [points[-1]]
    out = []
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = (np.array(p, dtype=float) for p in pts[i - 1:i + 3])
        for k in range(samples):
            t = k / samples
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                                    + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)))
    out.append(tuple(points[-1]))
    return out


def thick_line(draw, curve, width_px, colour):
    """Wide smooth stroke: stamp discs along the curve (PIL's wide lines get jagged joints)."""
    r = width_px / 2.0
    step = max(r / 2.5, 1.0) / S
    for (ax, az), (bx, bz) in zip(curve[:-1], curve[1:]):
        n = max(int(math.dist((ax, az), (bx, bz)) / step), 1)
        for k in range(n + 1):
            x, z = px(ax + (bx - ax) * k / n, az + (bz - az) * k / n)
            draw.ellipse([x - r, z - r, x + r, z + r], fill=colour)


def polyline_length(pts):
    return sum(math.dist(pts[i], pts[i + 1]) for i in range(len(pts) - 1))


class Design:
    def __init__(self, path=DESIGN):
        self.d = json.load(open(path, encoding="utf-8"))
        self.nodes = self.d["nodes"]
        self.paths = {}
        for p in self.d["paths"]:
            pts = [self.nodes[q]["pos"] if isinstance(q, str) else q for q in p["points"]]
            self.paths[p["id"]] = dict(p, curve=catmull_rom([list(map(float, q)) for q in pts]))

    def graph(self):
        """Edges between consecutive named nodes along each path, with curve lengths."""
        edges = []
        for p in self.d["paths"]:
            names = [(i, q) for i, q in enumerate(p["points"]) if isinstance(q, str)]
            pts = [self.nodes[q]["pos"] if isinstance(q, str) else q for q in p["points"]]
            for (ia, a), (ib, b) in zip(names, names[1:]):
                seg = catmull_rom([list(map(float, q)) for q in pts[ia:ib + 1]]) if ib - ia >= 2 else [pts[ia], pts[ib]]
                edges.append((a, b, polyline_length(seg), p["kind"]))
            # a path ending on an unnamed point joins the nearest node there
            if not isinstance(p["points"][-1], str):
                end = p["points"][-1]
                nearest = min(self.nodes, key=lambda n: math.dist(self.nodes[n]["pos"], end))
                if math.dist(self.nodes[nearest]["pos"], end) < 3 and names:
                    edges.append((names[-1][1], nearest, polyline_length(pts[names[-1][0]:]), p["kind"]))
        return edges

    def heights(self, xs, zs):
        X, Z = np.meshgrid(xs, zs)
        t = self.d["terrain"]
        h = t["base_roll"] * (np.sin(0.21 * X + 0.7) * np.cos(0.17 * Z + 1.3) + 0.5 * np.sin(0.37 * X - 0.29 * Z + 2.1))
        flat = np.zeros_like(X)
        for f in t["features"]:
            if f["kind"] == "bump":
                d = np.hypot(X - f["pos"][0], Z - f["pos"][1])
                h += f["height"] * 0.5 * (1 + np.cos(np.pi * np.clip(d / f["radius"], 0, 1)))
            elif f["kind"] == "channel":
                curve = np.array(self.paths[f["path"]]["curve"])
                d = np.full(X.shape, np.inf)
                for (ax, az), (bx, bz) in zip(curve[:-1], curve[1:]):
                    dx, dz = bx - ax, bz - az
                    L = dx * dx + dz * dz or 1e-9
                    tt = np.clip(((X - ax) * dx + (Z - az) * dz) / L, 0, 1)
                    d = np.minimum(d, np.hypot(X - (ax + tt * dx), Z - (az + tt * dz)))
                w = np.clip((d - f["half_width"]) / f["falloff"], 0, 1)
                h -= f["depth"] * (1 - w * w * (3 - 2 * w))
            elif f["kind"] == "flat":                # level ground; "blend" metres of ramp beyond the radius
                d = np.hypot(X - f["pos"][0], Z - f["pos"][1])
                flat = np.maximum(flat, 1 - np.clip((d - f["radius"]) / f.get("blend", 6.0), 0, 1))
        return h * (1 - flat)


def main():
    design = Design()
    d = design.d
    fb = d["forest_bounds"]
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    suffix = "_built" if "--built" in sys.argv else ""
    out = args[0] if args else os.path.join(ROOT, "level_design", "maps", "forest_map_v%d%s.png" % (d["version"], suffix))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    W, H = int((X1 - X0) * S + 2 * M), int((Z1 - Z0) * S + 2 * M)
    img = Image.new("RGB", (W + PANEL, H), (245, 243, 236))

    # --- heights: hillshade + area colours -------------------------------------
    res = 0.5
    xs = np.arange(X0, X1, res) + res / 2
    zs = np.arange(Z0, Z1, res) + res / 2
    h = design.heights(xs, zs)
    gz, gx = np.gradient(h, res)
    shade = np.clip(0.82 + (-gx * 0.6 - gz * 0.4) * 0.35, 0.55, 1.15)
    base = np.zeros(h.shape + (3,))
    base[:] = (150, 160, 140)                                   # outside the forest: background
    area_img = Image.new("RGB", (len(xs), len(zs)), (0, 0, 0))
    ad = ImageDraw.Draw(area_img)
    inside = Image.new("L", (len(xs), len(zs)), 0)
    ImageDraw.Draw(inside).rectangle([(fb["x_min"] - X0) / res, (fb["z_min"] - Z0) / res,
                                      (fb["x_max"] - X0) / res, (fb["z_max"] - Z0) / res], fill=255)
    for a in d["areas"]:
        if "polygon" in a:
            ad.polygon([((x - X0) / res, (z - Z0) / res) for x, z in a["polygon"]], fill=hex_rgb(a["colour"]))
    area = np.asarray(area_img, dtype=float)
    mask = np.asarray(inside) > 0
    base[mask] = area[mask]
    north = np.array([[z < fb["z_min"] for _ in xs] for z in zs])     # hill / meadow beyond the forest
    base[north & (np.abs(xs)[None, :] < 24)] = (170, 200, 130)
    rgb = np.clip(base * shade[..., None], 0, 255).astype(np.uint8)
    terrain = Image.fromarray(rgb, "RGB").resize((int((X1 - X0) * S), int((Z1 - Z0) * S)), Image.BILINEAR)
    img.paste(terrain, (M, M))
    draw = ImageDraw.Draw(img, "RGBA")

    # contours every metre
    levels = np.floor(h)
    edge = (levels[1:, 1:] != levels[:-1, 1:]) | (levels[1:, 1:] != levels[1:, :-1])
    for iz, ix in zip(*np.nonzero(edge)):
        x, z = xs[ix + 1], zs[iz + 1]
        draw.point(px(x, z), fill=(60, 50, 30, 110))

    # background hatch outside the forest (unreachable, generated trees)
    fx0, fz0 = px(fb["x_min"], fb["z_min"])
    fx1, fz1 = px(fb["x_max"], fb["z_max"])
    hatch = Image.new("RGBA", img.size, (0, 0, 0, 0))
    hd = ImageDraw.Draw(hatch)
    for k in range(-H, W, 14):
        hd.line([(M + k, M), (M + k + H, M + H)], fill=(255, 255, 255, 60), width=1)
    hd.rectangle([fx0, fz0, fx1, fz1], fill=(0, 0, 0, 0))
    hd.rectangle([W, 0, W + PANEL, H], fill=(0, 0, 0, 0))
    img.paste(hatch, (0, 0), hatch)
    draw = ImageDraw.Draw(img, "RGBA")
    draw.rectangle([fx0, fz0, fx1, fz1], outline=(40, 60, 30), width=3)

    # grid
    f_small, f_mid, f_big = font(12), font(15), font(20)
    for x in range(-40, 41, 10):
        a, b = px(x, Z0), px(x, Z1)
        draw.line([a, b], fill=(0, 0, 0, 45), width=1)
        draw.text((a[0], M - 16), "X %d" % x, fill=INK, font=f_small, anchor="mm")
    for z in range(-90, 11, 10):
        a, b = px(X0, z), px(X1, z)
        draw.line([a, b], fill=(0, 0, 0, 45), width=1)
        draw.text((M - 6, a[1]), "Z %d" % z, fill=INK, font=f_small, anchor="rm")

    # stream band, then paths (edge then fill)
    for p in design.paths.values():
        if p["kind"] == "stream":
            thick_line(draw, p["curve"], p["width"] * S, STREAM)
    for p in design.paths.values():
        if p["kind"] != "stream":
            edge_col = MAIN_EDGE if p["kind"] == "main" else PATH_EDGE
            thick_line(draw, p["curve"], p["width"] * S + 4, edge_col)
    for p in design.paths.values():
        if p["kind"] != "stream":
            thick_line(draw, p["curve"], p["width"] * S, PATH_FILL)
    for p in design.paths.values():                     # stream centre line on top of crossings
        if p["kind"] == "stream":
            draw.line([px(*q) for q in p["curve"]], fill=(70, 110, 140), width=2, joint="curve")

    # clearings and landmark sites
    for n in design.nodes.values():
        if n["kind"] in ("clearing", "landmark_site"):
            cx, cz = px(*n["pos"])
            r = n.get("radius", 4) * S
            col = (240, 225, 160, 170) if n["kind"] == "clearing" else (200, 190, 175, 170)
            draw.ellipse([cx - r, cz - r, cx + r, cz + r], fill=col, outline=PATH_EDGE, width=2)

    # house
    hx0, hz0 = px(-2.8, -7.8)
    hx1, hz1 = px(2.8, -2.2)
    draw.rectangle([hx0, hz0, hx1, hz1], fill=(150, 90, 60), outline=INK, width=2)
    draw.text(((hx0 + hx1) / 2, hz1 - 10), "House", fill=(255, 255, 255), font=f_small, anchor="mm")
    # hand-made scenes (the crooked house...): footprint, then their solid walls/furniture
    for s in d.get("scenes", []):
        if "footprint" in s:
            fx0_, fz0_, fx1_, fz1_ = s["footprint"]
            a, b = px(fx0_, fz0_), px(fx1_, fz1_)
            draw.rectangle([a[0], a[1], b[0], b[1]], fill=(120, 80, 110, 120), outline=INK, width=2)
            draw.text(((a[0] + b[0]) / 2, b[1] + 10), s["id"].replace("_", " ").title(), fill=INK, font=f_small, anchor="mm",
                      stroke_width=2, stroke_fill=(250, 248, 240))
    for bx0_, bz0_, bx1_, bz1_ in d.get("solids", {}).get("boxes", []):
        if not (-40 < bx0_ < 44 and -90 < bz0_ < 12):
            continue                                            # Hub solids live on the hub map
        a, b = px(bx0_, bz0_), px(bx1_, bz1_)
        draw.rectangle([a[0], a[1], b[0], b[1]], fill=(90, 50, 40, 220))

    # Fallen Giant + sightlines
    giant = next(l for l in d["landmarks"] if l["id"] == "giant")
    gp = px(*giant["peak"])
    for v in giant["visible_from"]:
        a = px(*design.nodes[v]["pos"])
        n = int(math.dist(a, gp) / 10)
        for k in range(0, n, 2):
            p0 = (a[0] + (gp[0] - a[0]) * k / n, a[1] + (gp[1] - a[1]) * k / n)
            p1 = (a[0] + (gp[0] - a[0]) * (k + 1) / n, a[1] + (gp[1] - a[1]) * (k + 1) / n)
            draw.line([p0, p1], fill=(90, 60, 140, 170), width=2)
        draw.ellipse([a[0] - 7, a[1] - 7, a[0] + 7, a[1] + 7], outline=(90, 60, 140), width=2)
    b0, b1 = giant["body"]
    draw.line([px(*b0), px(*b1)], fill=GIANT, width=int(3.5 * S))
    draw.line([px(*b0), px(*b1)], fill=(120, 105, 135), width=int(1.2 * S))
    draw.regular_polygon((gp[0], gp[1], 11), 3, fill=(90, 60, 140), outline=(255, 255, 255))
    lx, lz = px(giant["body"][1][0] + 3, giant["body"][1][1] - 8)
    draw.text((lx, lz), "THE FALLEN GIANT", fill=(255, 255, 255), font=f_mid, anchor="lm",
              stroke_width=3, stroke_fill=(60, 30, 100))
    draw.line([(lx - 4, lz), gp], fill=(60, 30, 100, 200), width=2)

    # nodes
    for name, n in design.nodes.items():
        x, z = px(*n["pos"])
        k = n["kind"]
        if k == "junction":
            draw.ellipse([x - 4, z - 4, x + 4, z + 4], fill=INK)
        elif k == "dead_end":
            draw.line([x - 7, z - 7, x + 7, z + 7], fill=(160, 30, 30), width=3)
            draw.line([x - 7, z + 7, x + 7, z - 7], fill=(160, 30, 30), width=3)
            if n.get("reward") == "collectible":
                draw.regular_polygon((x + 12, z - 10, 7), 5, fill=(240, 180, 30), outline=INK)
        elif k in ("exit", "start"):
            draw.regular_polygon((x, z, 8), 4, fill=(40, 130, 60), outline=INK)
        elif k == "vista":
            draw.regular_polygon((x, z, 12), 3, fill=(70, 150, 70), outline=INK)
    draw.text(px(4, -88), "Hill crest - city reveal", fill=INK, font=f_mid, anchor="lm")
    draw.text(px(0, -95), "City (north)", fill=INK, font=f_mid, anchor="mm")

    # labels
    for a in d["areas"]:
        if "polygon" in a:
            poly = np.array(a["polygon"], dtype=float)
            cx, cz = poly.mean(axis=0)
            if a["id"] == "edge":
                cx, cz = -24, -73
            if a["id"] == "old_wood":
                cx, cz = -24, -14
            if a["id"] == "ruins":
                cx, cz = -29, -47
            draw.text(px(cx, cz), a["name"].upper(), fill=(255, 255, 255), font=f_mid, anchor="mm",
                      stroke_width=3, stroke_fill=(30, 40, 20))
    draw.text(px(-30, -44.5), "STREAM BED", fill=(255, 255, 255), font=f_mid, anchor="mm", stroke_width=3, stroke_fill=(30, 60, 90))
    tags = {"clearing": ("THE DRY CLEARING", 0, -10), "ruin": ("THE RUIN FRAGMENT", 0, 7),
            "spring": ("spring / old pipe", 0, 3), "hollow_tree": ("hollow tree", 0, -3.2),
            "pine_end": ("deep pines", 0, 3), "garden_nook": ("greenhouse frame", 0, 3),
            "ruin_far": ("sealed hatch", 3, -1.5), "fork": ("first fork", 5, 0),
            "under_giant": ("inside the Giant", -3, -1.5)}
    for n, (text, dx, dz) in tags.items():
        x, z = design.nodes[n]["pos"]
        draw.text(px(x + dx, z + dz), text, fill=INK, font=f_small if text[0].islower() else f_mid,
                  anchor=("lm" if dx > 0 else "rm") if dx else "mm", stroke_width=2, stroke_fill=(250, 248, 240))

    # brambles (blockers)
    for b in d.get("blockers", []):
        (bx0, bz0), (bx1, bz1) = b["from"], b["to"]
        p0, p1 = px(bx0, bz0), px(bx1, bz1)
        draw.rectangle([p0[0], p0[1], p1[0], p1[1]], fill=(70, 40, 30, 200), outline=(30, 15, 10), width=2)
        for k in range(int(p0[0]), int(p1[0]), 6):
            draw.line([k, p0[1], k + 6, p1[1]], fill=(150, 90, 60, 200), width=1)
        draw.text((p0[0] - 4, (p0[1] + p1[1]) / 2), "brambles", fill=INK, font=f_small, anchor="rm",
                  stroke_width=2, stroke_fill=(250, 248, 240))

    # as built: every placed tree, rock and ruin piece from the last build
    built_path = os.path.join(ROOT, "level_design", "build", "level.json")
    if "--built" in sys.argv and os.path.exists(built_path):
        built = json.load(open(built_path))
        for o in built.get("interior", []):
            x, z = px(o["origin"][0], o["origin"][2])
            draw.ellipse([x - 2, z - 2, x + 2, z + 2], fill=(20, 45, 20, 150))
        for o in built["objects"]:
            x, z = px(o["origin"][0], o["origin"][2])
            if o["kind"] == "tree":
                r = max(o["trunk"][0] * S, 3)
                draw.ellipse([x - r, z - r, x + r, z + r], fill=(35, 80, 35, 220), outline=(10, 30, 10))
            elif o["kind"] == "rock":
                r = o.get("collision_radius", 0.8) * S
                draw.ellipse([x - r, z - r, x + r, z + r], fill=(120, 120, 120), outline=INK)
            elif o.get("code") == "RUIN":
                draw.rectangle([x - 8, z - 8, x + 8, z + 8], fill=(150, 130, 110), outline=INK, width=2)
            elif o["kind"] == "collectible":
                draw.regular_polygon((x, z, 8), 5, fill=(240, 180, 30), outline=INK)
            elif o["kind"] in ("weeds", "container", "wreck"):
                draw.rectangle([x - 5, z - 5, x + 5, z + 5], outline=(170, 60, 20), width=3)   # a box: find inside
            elif o["kind"] == "buried":
                draw.line([x - 6, z - 6, x + 6, z + 6], fill=(170, 60, 20), width=3)      # X marks the spot
                draw.line([x - 6, z + 6, x + 6, z - 6], fill=(170, 60, 20), width=3)
        for x0_, z0_, x1_, z1_, hw in built.get("giant_segments", []):
            draw.line([px(x0_, z0_), px(x1_, z1_)], fill=(60, 30, 100, 160), width=int(hw * 2 * S))

    # north arrow + scale bar
    ax, az = W - M - 20, M + 40
    draw.polygon([(ax, az - 26), (ax - 10, az), (ax + 10, az)], fill=INK)
    draw.text((ax, az + 14), "N", fill=INK, font=f_mid, anchor="mm")
    sx, sz = M + 10, H - M + 22
    draw.line([sx, sz, sx + 10 * S, sz], fill=INK, width=3)
    draw.text((sx + 5 * S, sz + 12), "10 m", fill=INK, font=f_small, anchor="mm")
    draw.text((W // 2, 18), "Area 2 forest - design v%d%s (north up, 1 grid square = 10 m, same X/Z as F2)" % (d["version"], " AS BUILT" if suffix else ""),
              fill=INK, font=f_big, anchor="mm")

    # --- stats + legend panel ---------------------------------------------------
    edges = design.graph()
    adj = {}
    for a, b, L, _ in edges:
        adj.setdefault(a, []).append((b, L))
        adj.setdefault(b, []).append((a, L))
    dist, prev, heap = {"door": 0.0}, {}, [(0.0, "door")]
    while heap:
        dd, u = heapq.heappop(heap)
        if dd > dist.get(u, 1e9):
            continue
        for v, L in adj.get(u, []):
            if dd + L < dist.get(v, 1e9):
                dist[v], prev[v] = dd + L, u
                heapq.heappush(heap, (dist[v], v))
    main_len = dist.get("hill_crest", float("nan"))
    robot_speed = d.get("robot_speed", 3.0)          # m/s, matches player.gd SPEED
    total = sum(polyline_length(p["curve"]) for p in design.paths.values())
    nodes_used = set(adj)
    loops = len(edges) - len(nodes_used) + 1
    dead_ends = sum(1 for n in design.nodes.values() if n["kind"] == "dead_end")
    junctions = sum(1 for n in nodes_used if len(adj[n]) >= 3)
    area_m2 = (fb["x_max"] - fb["x_min"]) * (fb["z_max"] - fb["z_min"])
    route, n = [], "hill_crest"
    while n in prev:
        route.append(n)
        n = prev[n]
    route.append("door")

    px0 = W + 14
    y = 24
    draw.text((px0, y), "At a glance", fill=INK, font=f_big)
    y += 32
    for line in ["Forest: %d x %d m (%s m2), was 48 x 62 m" % (fb["x_max"] - fb["x_min"], fb["z_max"] - fb["z_min"], format(area_m2, ",")),
                 "Paths in total: %d m (+ stream bed)" % round(total - polyline_length(design.paths["stream"]["curve"])),
                 "Stream bed: %d m, walkable" % round(polyline_length(design.paths["stream"]["curve"])),
                 "Shortest door -> hill: %d m (~%d s driving)" % (round(main_len), round(main_len / robot_speed)),
                 "Junctions: %d   Loops: %d   Dead ends: %d" % (junctions, loops, dead_ends),
                 "Giant visible from %d of the key places" % len(giant["visible_from"])]:
        draw.text((px0, y), line, fill=INK, font=f_small)
        y += 19
    y += 14
    draw.text((px0, y), "Areas", fill=INK, font=f_big)
    y += 30
    for a in d["areas"]:
        draw.rectangle([px0, y + 2, px0 + 16, y + 16], fill=hex_rgb(a["colour"]), outline=INK)
        draw.text((px0 + 24, y), a["name"], fill=INK, font=f_mid)
        y += 19
        words, line = a["feel"].split(), ""
        for w in words:
            if len(line + " " + w) > 52:
                draw.text((px0 + 24, y), line, fill=(70, 70, 70), font=f_small)
                y += 15
                line = w
            else:
                line = (line + " " + w).strip()
        draw.text((px0 + 24, y), line, fill=(70, 70, 70), font=f_small)
        y += 22
    y += 4
    draw.text((px0, y), "Symbols", fill=INK, font=f_big)
    y += 30
    sym = [("main route", "main"), ("side path", "side"), ("stream bed (walkable)", "stream"),
           ("junction", "junction"), ("dead end + collectible", "dead"), ("sightline to the Giant", "sight"),
           ("start / exit", "exit"), ("contour line = 1 m of height", "contour"), ("hatched = background forest", "hatch")]
    for text, kind in sym:
        cx, cy = px0 + 20, y + 9
        if kind in ("main", "side"):
            draw.line([cx - 16, cy, cx + 16, cy], fill=MAIN_EDGE if kind == "main" else PATH_EDGE, width=12)
            draw.line([cx - 16, cy, cx + 16, cy], fill=PATH_FILL, width=8)
        elif kind == "stream":
            draw.line([cx - 16, cy, cx + 16, cy], fill=STREAM, width=12)
        elif kind == "junction":
            draw.ellipse([cx - 4, cy - 4, cx + 4, cy + 4], fill=INK)
        elif kind == "dead":
            draw.line([cx - 6, cy - 6, cx + 6, cy + 6], fill=(160, 30, 30), width=3)
            draw.line([cx - 6, cy + 6, cx + 6, cy - 6], fill=(160, 30, 30), width=3)
            draw.regular_polygon((cx + 13, cy - 4, 6), 5, fill=(240, 180, 30), outline=INK)
        elif kind == "sight":
            for k in range(-16, 16, 8):
                draw.line([cx + k, cy, cx + k + 4, cy], fill=(90, 60, 140), width=2)
        elif kind == "exit":
            draw.regular_polygon((cx, cy, 7), 4, fill=(40, 130, 60), outline=INK)
        elif kind == "contour":
            for k in range(-16, 16, 3):
                draw.point((cx + k, cy), fill=(60, 50, 30))
        elif kind == "hatch":
            draw.rectangle([cx - 16, cy - 7, cx + 16, cy + 7], fill=(150, 160, 140))
            for k in range(-16, 16, 6):
                draw.line([cx + k, cy - 7, cx + k + 6, cy + 7], fill=(255, 255, 255, 90))
        draw.text((px0 + 48, y + 1), text, fill=INK, font=f_small)
        y += 21
    y += 10
    text, line = "Shortest route: " + " > ".join(reversed(route)).replace("_", " "), ""
    for w in text.split(" "):
        if len(line + " " + w) > 60:
            draw.text((px0, y), line, fill=(70, 70, 70), font=f_small)
            y += 15
            line = w
        else:
            line = (line + " " + w).strip()
    draw.text((px0, y), line, fill=(70, 70, 70), font=f_small)

    img.save(out)
    print("saved", out)
    print("forest %dx%d m | paths %.0f m | stream %.0f m | door->hill %.0f m | junctions %d loops %d dead ends %d" % (
        fb["x_max"] - fb["x_min"], fb["z_max"] - fb["z_min"], total, polyline_length(design.paths["stream"]["curve"]),
        main_len, junctions, loops, dead_ends))


if __name__ == "__main__":
    main()
