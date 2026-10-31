#!/usr/bin/env python3
"""Map preview renderer. Owner: D.

Reads build/maps/*.json (written by `lune run tools/dump_maps.luau`) and writes
build/previews/<Name>_top.png  (top-down height map + outlines + markers + zone circles + reachability)
build/previews/<Name>_iso.png  (isometric 3D view, z-buffered, part colors, near perimeter cut away)

Usage: python3 tools/map_preview.py [map names...]
"""
import glob
import json
import math
import os
import sys

import numpy as np
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib import cm, colors as mcolors  # noqa: E402
from matplotlib.patches import Circle, Ellipse, Polygon, Rectangle  # noqa: E402,F401

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAPS = os.path.join(ROOT, "build", "maps")
OUT = os.path.join(ROOT, "build", "previews")

MARKER_STYLE = {
    "PlayerSpawn": ("#2ecc40", "^", "spawn"),
    "Red": ("#ff2222", "o", "Red"),
    "White": ("#d8d8d8", "o", "White"),
    "WeaponPickup": ("#ffd400", "*", "weapon"),
    "Board": ("#1f6fff", "s", "board"),
    "HealthPickup": ("#ff3030", "P", "health"),
    "AmmoPickup": ("#27c45a", "s", "ammo"),
    "Other": ("#bb66ff", "D", "other"),
}
# drawn as shapes, not as point icons
SHAPE_MARKERS = ("StartDoor", "StartRoom")
# ceilings / roof trims: hidden in the top view (so the start room's inside shows), translucent in the iso view
OVERHEAD = ("StartRoomRoof", "DoorLintel", "RoomBand")


# ----------------------------------------------------------------------------- geometry

def rot_matrix(rot):
    """CFrame.Angles(rx, ry, rz) in degrees = Rx * Ry * Rz."""
    if not rot:
        return np.eye(3)
    a, b, c = (math.radians(v) for v in rot)
    rx = np.array([[1, 0, 0], [0, math.cos(a), -math.sin(a)], [0, math.sin(a), math.cos(a)]])
    ry = np.array([[math.cos(b), 0, math.sin(b)], [0, 1, 0], [-math.sin(b), 0, math.cos(b)]])
    rz = np.array([[math.cos(c), -math.sin(c), 0], [math.sin(c), math.cos(c), 0], [0, 0, 1]])
    return rx @ ry @ rz


def box_faces(hx, hy, hz):
    v = np.array([[sx * hx, sy * hy, sz * hz] for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)])
    # index = (sx>0)*4 + (sy>0)*2 + (sz>0)
    quads = [
        (0, 1, 3, 2),  # -x
        (4, 6, 7, 5),  # +x
        (0, 4, 5, 1),  # -y
        (2, 3, 7, 6),  # +y
        (0, 2, 6, 4),  # -z
        (1, 5, 7, 3),  # +z
    ]
    return [[v[i] for i in q] for q in quads]


def wedge_faces(hx, hy, hz):
    # Roblox WedgePart: full back face at +Z, slope rising from front-bottom (-Z) to back-top (+Z).
    fb = [np.array([sx * hx, -hy, -hz]) for sx in (-1, 1)]
    bb = [np.array([sx * hx, -hy, hz]) for sx in (-1, 1)]
    bt = [np.array([sx * hx, hy, hz]) for sx in (-1, 1)]
    return [
        [fb[0], fb[1], bb[1], bb[0]],  # bottom
        [bb[0], bb[1], bt[1], bt[0]],  # back
        [fb[0], bt[0], bt[1], fb[1]],  # slope
        [fb[0], bb[0], bt[0]],  # -x side
        [fb[1], bt[1], bb[1]],  # +x side
    ]


def cylinder_faces(hx, r, n=16):
    faces = []
    ring = [(math.cos(2 * math.pi * k / n) * r, math.sin(2 * math.pi * k / n) * r) for k in range(n)]
    for k in range(n):
        (y0, z0), (y1, z1) = ring[k], ring[(k + 1) % n]
        faces.append([np.array([-hx, y0, z0]), np.array([hx, y0, z0]), np.array([hx, y1, z1]), np.array([-hx, y1, z1])])
    faces.append([np.array([hx, y, z]) for y, z in ring])
    faces.append([np.array([-hx, y, z]) for y, z in reversed(ring)])
    return faces


def ball_faces(r, nlat=8, nlon=14):
    faces = []
    for i in range(nlat):
        t0, t1 = math.pi * i / nlat, math.pi * (i + 1) / nlat
        for j in range(nlon):
            p0, p1 = 2 * math.pi * j / nlon, 2 * math.pi * (j + 1) / nlon

            def pt(t, p):
                return np.array([r * math.sin(t) * math.cos(p), r * math.cos(t), r * math.sin(t) * math.sin(p)])

            quad = [pt(t0, p0), pt(t0, p1), pt(t1, p1), pt(t1, p0)]
            faces.append(quad)
    return faces


def part_faces(part):
    """World-space polygons (list of Nx3 arrays) and outward normals for a part."""
    sx, sy, sz = part["Size"]
    shape = part.get("Shape", "Block")
    if shape == "Wedge":
        local = wedge_faces(sx / 2, sy / 2, sz / 2)
    elif shape == "Cylinder":
        local = cylinder_faces(sx / 2, min(sy, sz) / 2)
    elif shape == "Ball":
        local = ball_faces(min(sx, sy, sz) / 2)
    else:
        local = box_faces(sx / 2, sy / 2, sz / 2)
    m = rot_matrix(part.get("Rot"))
    pos = np.array(part["Pos"], dtype=float)
    out = []
    for poly in local:
        p = np.array(poly) @ m.T + pos
        n = np.cross(p[1] - p[0], p[2] - p[0])
        if np.linalg.norm(n) < 1e-9 and len(p) > 3:
            n = np.cross(p[2] - p[0], p[3] - p[0])
        ln = np.linalg.norm(n)
        if ln < 1e-12:
            continue
        n = n / ln
        # make the normal point away from the part center
        if np.dot(n, p.mean(axis=0) - pos) < 0:
            n = -n
        out.append((p, n))
    return out


def hex_rgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])


# ----------------------------------------------------------------------------- rasterizer

class Raster:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.depth = np.full((h, w), np.inf)
        self.color = np.zeros((h, w, 3))
        self.fid = np.full((h, w), -1, dtype=np.int64)
        self.height = np.full((h, w), np.nan)
        self.base = np.zeros((h, w, 3))

    def tri(self, s, depth, color, fid, wy=None, alpha=1.0, base=None):
        """s: 3x2 screen coords, depth: 3 values (smaller = nearer), wy: world y per vertex."""
        x0 = max(int(math.floor(s[:, 0].min())), 0)
        x1 = min(int(math.ceil(s[:, 0].max())), self.w - 1)
        y0 = max(int(math.floor(s[:, 1].min())), 0)
        y1 = min(int(math.ceil(s[:, 1].max())), self.h - 1)
        if x0 > x1 or y0 > y1:
            return
        (ax, ay), (bx, by), (cx, cy) = s
        den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(den) < 1e-9:
            return
        xs = np.arange(x0, x1 + 1) + 0.5
        ys = np.arange(y0, y1 + 1) + 0.5
        px, py = np.meshgrid(xs, ys)
        l1 = ((by - cy) * (px - cx) + (cx - bx) * (py - cy)) / den
        l2 = ((cy - ay) * (px - cx) + (ax - cx) * (py - cy)) / den
        l3 = 1 - l1 - l2
        eps = -1e-6
        inside = (l1 >= eps) & (l2 >= eps) & (l3 >= eps)
        if not inside.any():
            return
        d = l1 * depth[0] + l2 * depth[1] + l3 * depth[2]
        zb = self.depth[y0:y1 + 1, x0:x1 + 1]
        win = inside & (d < zb - 1e-6)
        if not win.any():
            return
        cb = self.color[y0:y1 + 1, x0:x1 + 1]
        if alpha >= 0.999:
            zb[win] = d[win]
            cb[win] = color
            self.fid[y0:y1 + 1, x0:x1 + 1][win] = fid
            if wy is not None:
                hb = self.height[y0:y1 + 1, x0:x1 + 1]
                hb[win] = (l1 * wy[0] + l2 * wy[1] + l3 * wy[2])[win]
            if base is not None:
                self.base[y0:y1 + 1, x0:x1 + 1][win] = base
        else:
            cb[win] = cb[win] * (1 - alpha) + np.asarray(color) * alpha

    def poly(self, s, depth, color, fid, wy=None, alpha=1.0, base=None):
        for k in range(1, len(s) - 1):
            idx = [0, k, k + 1]
            self.tri(s[idx], depth[idx], color, fid, None if wy is None else wy[idx], alpha, base)

    def edges(self, strength=0.45):
        f = self.fid
        e = np.zeros_like(f, dtype=bool)
        e[:, :-1] |= (f[:, :-1] != f[:, 1:]) & (f[:, :-1] >= 0)
        e[:-1, :] |= (f[:-1, :] != f[1:, :]) & (f[:-1, :] >= 0)
        return e


# ----------------------------------------------------------------------------- views

LIGHT = np.array([0.35, 1.0, 0.55])
LIGHT = LIGHT / np.linalg.norm(LIGHT)


def shade(rgb, n):
    k = 0.58 + 0.42 * max(0.0, float(np.dot(n, LIGHT)))
    return np.clip(rgb * k, 0, 1)


def board_panels(spec):
    """MapBuilder turns each Board marker into a visible dark-green panel: draw it too."""
    out = []
    for m in spec["Markers"]:
        if m["Tag"] == "Board":
            a = m.get("Attr") or {}
            out.append({"Shape": "Block", "Size": [a.get("Width", 12), a.get("Height", 7), 0.4],
                        "Pos": m["Pos"], "Rot": m.get("Rot"), "Color": "#2E4E3A", "Material": "SmoothPlastic",
                        "Name": "BoardPanel"})
    return out


def start_room(spec):
    """(min_x, min_z, max_x, max_z, center, size) of the StartRoom marker, or None."""
    for m in spec["Markers"]:
        if m["Tag"] == "StartRoom":
            try:
                sx, sy, sz = (float(v) for v in str((m.get("Attr") or {}).get("Size", "")).split(","))
            except ValueError:
                return None
            x, y, z = m["Pos"]
            return (x - sx / 2, z - sz / 2, x + sx / 2, z + sz / 2, (x, y, z), (sx, sy, sz))
    return None


def in_room(room, x, z, pad=0.0):
    return room is not None and room[0] - pad <= x <= room[2] + pad and room[1] - pad <= z <= room[3] + pad


def door_parts(spec):
    return [p for p in spec["Parts"] if p.get("Name") == "StartDoor" and p.get("Collide", True) is not False]


def door_slide(spec):
    for m in spec["Markers"]:
        if m["Tag"] == "StartDoor":
            try:
                return [float(v) for v in str((m.get("Attr") or {}).get("Slide", "")).split(",")]
            except ValueError:
                return None
    return None


def collect(spec, top_view=False):
    items = []
    room = start_room(spec)
    for i, part in enumerate(list(spec["Parts"]) + board_panels(spec)):
        t = part.get("Transparency", 0) or 0
        if t >= 0.95:
            continue
        name = part.get("Name", "")
        if top_view and (name in OVERHEAD or (name == "Light" and in_room(room, part["Pos"][0], part["Pos"][2]))):
            continue
        faces = part_faces(part)
        items.append((i, part, faces, t))
    return items


def render_top(spec, path):
    w, _, d = spec["Size"]
    margin = 4
    ppu = max(4.0, min(12.0, 1100.0 / (max(w, d) + 2 * margin)))
    W = int((w + 2 * margin) * ppu)
    H = int((d + 2 * margin) * ppu)
    R = Raster(W, H)

    def to_screen(p):
        return np.stack([(p[:, 0] + w / 2 + margin) * ppu, (p[:, 2] + d / 2 + margin) * ppu], axis=1)

    for i, part, faces, t in collect(spec, top_view=True):
        base = hex_rgb(part["Color"])
        for fi, (p, n) in enumerate(faces):
            if n[1] <= 1e-3 and part.get("Shape") not in ("Ball",):
                # only up-facing faces matter from straight above (balls: all upper faces)
                continue
            if n[1] <= 0:
                continue
            s = to_screen(p)
            R.poly(s, -p[:, 1], base, i * 64 + fi, wy=p[:, 1], base=base)

    hmap = R.height
    valid = ~np.isnan(hmap)
    top = max(1.0, np.nanmax(hmap) if valid.any() else 1.0)
    norm = mcolors.Normalize(vmin=-6, vmax=max(16.0, top))
    cmap = plt.get_cmap("viridis")
    img = np.ones((H, W, 3)) * 0.12
    hc = cmap(norm(np.where(valid, hmap, 0)))[..., :3]
    mix = 0.68 * hc + 0.32 * R.base
    img[valid] = mix[valid]
    e = R.edges()
    img[e] *= 0.35

    # reachability overlay: dim cells not reachable on foot, magenta traps
    reach = spec.get("Reach")
    if reach:
        nx, nz, res = reach["NX"], reach["NZ"], reach["Res"]
        cells = reach["Cells"]
        arr = np.frombuffer(cells.encode(), dtype=np.uint8).reshape(nz, nx)
        ys, xs = np.mgrid[0:H, 0:W]
        wx = xs / ppu - margin - w / 2
        wz = ys / ppu - margin - d / 2
        ci = np.floor((wx - reach["X0"]) / res).astype(int)
        ck = np.floor((wz - reach["Z0"]) / res).astype(int)
        ok = (ci >= 0) & (ci < nx) & (ck >= 0) & (ck < nz)
        val = np.zeros((H, W), dtype=np.uint8)
        val[ok] = arr[ck[ok], ci[ok]]
        unreach = ok & (val == ord("0")) & valid
        img[unreach] = img[unreach] * 0.55 + np.array([0.05, 0.05, 0.1]) * 0.45
        trap = ok & (val == ord("t"))
        img[trap] = img[trap] * 0.3 + np.array([1, 0, 1]) * 0.7

    fig_w = W / 100 + 2.6
    fig, ax = plt.subplots(figsize=(fig_w, H / 100 + 1.2), dpi=100)
    ext = [-w / 2 - margin, w / 2 + margin, d / 2 + margin, -d / 2 - margin]
    ax.imshow(img, extent=ext, interpolation="nearest")
    ax.set_xlim(ext[0], ext[1])
    ax.set_ylim(ext[2], ext[3])
    ax.set_xticks(np.arange(-(w // 20) * 10, w / 2 + 1, 10))
    ax.set_yticks(np.arange(-(d // 20) * 10, d / 2 + 1, 10))
    ax.tick_params(labelsize=7)
    ax.set_xlabel("x (east →)", fontsize=8)
    ax.set_ylabel("z (south ↓)", fontsize=8)
    draw_markers_top(ax, spec)
    sm = cm.ScalarMappable(norm=norm, cmap=cmap)
    cb = fig.colorbar(sm, ax=ax, fraction=0.035, pad=0.02)
    cb.set_label("top height (studs)", fontsize=8)
    cb.ax.tick_params(labelsize=7)
    st = spec.get("Validation", {}).get("Stats", {})
    errs = spec.get("Validation", {}).get("Errors", [])
    ax.set_title(
        f"{spec['Name']}  {int(w)}×{int(d)}  parts {len(spec['Parts'])}  red weight {st.get('redWeight')}  "
        f"reach {st.get('reachablePct')}%  {'OK' if not errs else str(len(errs)) + ' ERRORS'}\n"
        "dim = not reachable on foot (door open), magenta = trap, circles = enemy zones, "
        "dashed box = start room (roof hidden), white bar = start door",
        fontsize=9,
    )
    fig.tight_layout()
    fig.savefig(path)
    plt.close(fig)


def marker_kind(m):
    tag = m["Tag"]
    if tag == "EnemySpawn":
        k = (m.get("Attr") or {}).get("Kind")
        return k if k in ("Red", "White") else "Other"
    return tag if tag in MARKER_STYLE else "Other"


def marker_label(m):
    a = m.get("Attr") or {}
    tag = m["Tag"]
    if tag == "EnemySpawn":
        if a.get("Kind") == "Red":
            return f"R w{a.get('Weight')} z{a.get('Zone')}"
        return f"{a.get('Kind', '?')[0]}×{a.get('Count')} z{a.get('Zone')}"
    if tag == "WeaponPickup":
        return f"{a.get('Weapon')} ({m.get('Id')})"
    if tag == "Board":
        return "board"
    if tag == "HealthPickup":
        return f"+HP ({m.get('Id')})"
    if tag == "AmmoPickup":
        w = a.get("Weapon")
        return f"ammo{' ' + w if w else ''} ({m.get('Id')})"
    return ""


def draw_start_room_top(ax, spec):
    room = start_room(spec)
    if room:
        x0, z0, x1, z1 = room[:4]
        ax.add_patch(Rectangle((x0, z0), x1 - x0, z1 - z0, fill=False, ec="#00e5ff", lw=1.6, ls="--"))
        # one label block beside the room: size + what lies inside (keeps the small room readable)
        lines = [f"start room {room[5][0]:g}×{room[5][2]:g}, h{room[5][1]:g}"]
        for m in spec["Markers"]:
            if m["Tag"] in ("WeaponPickup", "HealthPickup", "AmmoPickup") and in_room(room, m["Pos"][0], m["Pos"][2]):
                lines.append("· " + marker_label(m))
        ax.text(x0 - 1.5, z1 - 0.5, "\n".join(lines), fontsize=7, color="white", ha="right", va="bottom",
                bbox=dict(boxstyle="round,pad=0.25", fc="#006070", alpha=0.8, lw=0))
    slide = door_slide(spec)
    for p in door_parts(spec):
        sx, _, sz = p["Size"]
        x, _, z = p["Pos"]
        if slide:
            # open position (slid into the wall), ghosted
            ax.add_patch(Rectangle((x + slide[0] - sx / 2, z + slide[2] - sz / 2), sx, sz, fill=False,
                                   ec="white", lw=0.8, ls=":"))
            ax.annotate("", xy=(x + slide[0] * 0.8, z + slide[2] * 0.8 - 1.6), xytext=(x, z - 1.6),
                        arrowprops=dict(arrowstyle="->", color="white", lw=1.0))
        ax.add_patch(Rectangle((x - sx / 2, z - sz / 2), sx, sz, fill=True, fc="white", ec="black", lw=1.6,
                               zorder=5))
        ax.text(x, z - 2.6, "door", fontsize=7, color="black", ha="center",
                bbox=dict(boxstyle="round,pad=0.12", fc="white", alpha=0.85, lw=0), zorder=6)


def draw_markers_top(ax, spec):
    draw_start_room_top(ax, spec)
    for m in spec["Markers"]:
        if m["Tag"] in SHAPE_MARKERS:
            continue
        kind = marker_kind(m)
        col, sym, _ = MARKER_STYLE[kind]
        x, y, z = m["Pos"]
        a = m.get("Attr") or {}
        if m["Tag"] == "EnemySpawn" and a.get("Zone"):
            ax.add_patch(Circle((x, z), a["Zone"], fill=False, ec=col, lw=1.4, ls="--", alpha=0.95))
            ax.add_patch(Circle((x, z), a["Zone"], fill=True, fc=col, alpha=0.10, lw=0))
        if m["Tag"] == "HealthPickup":
            ax.plot([x], [z], marker="s", color="white", markersize=12, mec="black", mew=0.8)
            ax.plot([x], [z], marker="P", color=col, markersize=10, mec=col, mew=0.5)
        elif m["Tag"] == "AmmoPickup":
            ax.plot([x], [z], marker="s", color=col, markersize=11, mec="#0b4d22", mew=1.4)
            ax.plot([x], [z], marker="|", color="#ffd400", markersize=7, mew=2.2)
        else:
            ax.plot([x], [z], marker=sym, color=col, markersize=9 if sym != "*" else 14, mec="black", mew=0.8)
        rot = m.get("Rot")
        if rot and m["Tag"] in ("PlayerSpawn", "Board"):
            yaw = math.radians(rot[1])
            fx, fz = -math.sin(yaw), -math.cos(yaw)
            ax.annotate("", xy=(x + fx * 4, z + fz * 4), xytext=(x, z),
                        arrowprops=dict(arrowstyle="->", color=col, lw=1.2))
        lab = marker_label(m)
        if lab and m["Tag"] != "Board" and in_room(start_room(spec), x, z):
            lab = ""  # listed in the start room label block
        if lab:
            if y > 4.5:
                lab += f" y{y - 3:.0f}" if m["Tag"] == "EnemySpawn" else ""
            ax.text(x + 1.5, z - 1.5, lab, fontsize=7, color="white",
                    bbox=dict(boxstyle="round,pad=0.15", fc="black", alpha=0.55, lw=0))


def render_iso(spec, path):
    w, _, d = spec["Size"]
    cam = np.array([1.0, 1.15, 1.0])
    cam /= np.linalg.norm(cam)
    fwd = -cam
    right = np.cross(fwd, np.array([0.0, 1.0, 0.0]))
    right /= np.linalg.norm(right)
    up = np.cross(right, fwd)

    items = collect(spec)
    # screen bounds from all vertices
    allp = np.concatenate([p for _, _, faces, _ in items for p, _ in faces]) if items else np.zeros((1, 3))
    sx = allp @ right
    sy = allp @ up
    pad = 20
    W_target = 1500
    scale = (W_target - 2 * pad) / max(1e-6, sx.max() - sx.min())
    W = W_target
    H = int((sy.max() - sy.min()) * scale + 2 * pad)
    H = max(H, 300)
    R = Raster(W, H)

    def proj(p):
        s = np.stack([(p @ right - sx.min()) * scale + pad, (sy.max() - p @ up) * scale + pad], axis=1)
        return s, p @ fwd

    # cut away the near perimeter (south and east sides) so the arena is visible
    def near_perimeter(part):
        if not str(part.get("Name", "")).startswith("Perimeter"):
            return False
        x, _, z = part["Pos"]
        return x > w / 2 - 0.5 or z > d / 2 - 0.5

    room = start_room(spec)

    # start room: roof and the walls facing the camera are see-through so the inside shows
    def near_room_wall(part):
        if room is None or part.get("Name") != "StartRoomWall":
            return False
        cx, _, cz = room[4]
        x, _, z = part["Pos"]
        return (x - cx) + (z - cz) > 2.5

    transparent = []
    for i, part, faces, t in items:
        base = hex_rgb(part["Color"])
        alpha = 1.0
        name = part.get("Name", "")
        if near_perimeter(part):
            alpha = 0.12
        elif name in OVERHEAD and room is not None and in_room(room, part["Pos"][0], part["Pos"][2], 2):
            alpha = 0.15
        elif near_room_wall(part):
            alpha = 0.22
        elif t > 0:
            alpha = max(0.3, 1 - t)
        for fi, (p, n) in enumerate(faces):
            if np.dot(n, cam) <= 0:
                continue  # back face
            s, dep = proj(p)
            col = shade(base, n)
            if alpha < 0.999:
                transparent.append((dep.mean(), s, dep, col, alpha))
            else:
                R.poly(s, dep, col, i * 64 + fi)
    img = R.color.copy()
    bg = R.fid < 0
    img[bg] = np.array([0.93, 0.95, 0.98])
    e = R.edges()
    img[e] *= 0.55
    R.color = img
    for _, s, dep, col, alpha in sorted(transparent, key=lambda t: -t[0]):
        R.poly(s, dep, col, -2, alpha=alpha)
    img = R.color

    fig, ax = plt.subplots(figsize=(W / 100, H / 100 + 0.5), dpi=100)
    ax.imshow(img, extent=[0, W, H, 0], interpolation="bilinear")
    ax.set_xlim(0, W)
    ax.set_ylim(H, 0)
    ax.axis("off")
    for m in spec["Markers"]:
        if m["Tag"] in SHAPE_MARKERS:
            continue
        kind = marker_kind(m)
        col, sym, _ = MARKER_STYLE[kind]
        p = np.array([m["Pos"]], dtype=float)
        s, _ = proj(p)
        a = m.get("Attr") or {}
        if m["Tag"] == "EnemySpawn" and a.get("Zone"):
            ang = np.linspace(0, 2 * math.pi, 48)
            ring = np.stack([p[0, 0] + np.cos(ang) * a["Zone"], np.full_like(ang, p[0, 1] - 2.9),
                             p[0, 2] + np.sin(ang) * a["Zone"]], axis=1)
            rs, _ = proj(ring)
            ax.plot(rs[:, 0], rs[:, 1], color=col, lw=1.3, ls="--")
        big = sym in ("*", "P")
        ax.plot([s[0, 0]], [s[0, 1]], marker=sym, color=col, markersize=14 if big else 9,
                mec="black" if kind != "HealthPickup" else "white", mew=0.8)
    for part in door_parts(spec):
        for p, n in part_faces(part):
            if np.dot(n, cam) > 0:
                fs, _ = proj(np.vstack([p, p[:1]]))
                ax.plot(fs[:, 0], fs[:, 1], color="black", lw=1.6)
    if room is not None:
        x0, z0, x1, z1 = room[:4]
        y = room[4][1] - room[5][1] / 2 + 0.25
        corners = np.array([[x0, y, z0], [x1, y, z0], [x1, y, z1], [x0, y, z1], [x0, y, z0]])
        cs, _ = proj(corners)
        ax.plot(cs[:, 0], cs[:, 1], color="#00e5ff", lw=1.3, ls="--")
    ax.set_title(f"{spec['Name']} — iso view from south-east (near walls cut away, start room roof see-through)",
                 fontsize=10)
    fig.tight_layout()
    fig.savefig(path)
    plt.close(fig)


def main(argv):
    os.makedirs(OUT, exist_ok=True)
    files = sorted(glob.glob(os.path.join(MAPS, "*.json")))
    if argv:
        files = [f for f in files if os.path.splitext(os.path.basename(f))[0] in argv]
    if not files:
        print("no map json found; run: lune run tools/dump_maps.luau")
        return 1
    for f in files:
        with open(f, encoding="utf-8") as fh:
            spec = json.load(fh)
        name = spec["Name"]
        top = os.path.join(OUT, f"{name}_top.png")
        iso = os.path.join(OUT, f"{name}_iso.png")
        render_top(spec, top)
        render_iso(spec, iso)
        print(f"wrote {os.path.relpath(top, ROOT)}, {os.path.relpath(iso, ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
