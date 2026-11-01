"""Render enemy shell models (build/models/*.json) to build/previews/model_<Kind>.png.

Front 3/4, side and back views with simple Lambert shading. Shapes: Block, Wedge, Ball,
Cylinder (axis = local X), Ellipsoid. Rotations follow Roblox CFrame.Angles(x, y, z) = Rx*Ry*Rz.
Usage (repo root): lune run tools/model_preview/dump.luau && python3 tools/model_preview/render.py
"""
import glob
import json
import os

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
from mpl_toolkits.mplot3d.art3d import Poly3DCollection  # noqa: E402

LIGHT = np.array([-0.4, 0.8, -0.6])
LIGHT = LIGHT / np.linalg.norm(LIGHT)


def rot(deg):
    x, y, z = np.radians(deg)
    rx = np.array([[1, 0, 0], [0, np.cos(x), -np.sin(x)], [0, np.sin(x), np.cos(x)]])
    ry = np.array([[np.cos(y), 0, np.sin(y)], [0, 1, 0], [-np.sin(y), 0, np.cos(y)]])
    rz = np.array([[np.cos(z), -np.sin(z), 0], [np.sin(z), np.cos(z), 0], [0, 0, 1]])
    return rx @ ry @ rz


def box_faces(sx, sy, sz):
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    v = np.array([[x, y, z] for x in (-hx, hx) for y in (-hy, hy) for z in (-hz, hz)])
    idx = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    return [v[list(f)] for f in idx]


def wedge_faces(sx, sy, sz):
    # Roblox wedge: full bottom, back face (+z) full height, slope from back-top to front-bottom.
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    a = np.array([-hx, -hy, -hz]); b = np.array([hx, -hy, -hz])
    c = np.array([hx, -hy, hz]); d = np.array([-hx, -hy, hz])
    e = np.array([-hx, hy, hz]); f = np.array([hx, hy, hz])
    return [np.array(p) for p in ([a, b, c, d], [d, c, f, e], [a, d, e], [b, f, c], [a, e, f, b])]


def ellipsoid_faces(sx, sy, sz, nu=18, nv=12):
    us = np.linspace(0, 2 * np.pi, nu + 1)
    vs = np.linspace(-np.pi / 2, np.pi / 2, nv + 1)
    faces = []
    for i in range(nu):
        for j in range(nv):
            quad = []
            for u, v in ((us[i], vs[j]), (us[i + 1], vs[j]), (us[i + 1], vs[j + 1]), (us[i], vs[j + 1])):
                quad.append([sx / 2 * np.cos(v) * np.cos(u), sy / 2 * np.sin(v), sz / 2 * np.cos(v) * np.sin(u)])
            faces.append(np.array(quad))
    return faces


def cylinder_faces(sx, sy, sz, n=18):
    r_y, r_z, h = sy / 2, sz / 2, sx / 2
    ts = np.linspace(0, 2 * np.pi, n + 1)
    faces = []
    for i in range(n):
        p = lambda t, x: [x, r_y * np.cos(t), r_z * np.sin(t)]  # noqa: E731
        faces.append(np.array([p(ts[i], -h), p(ts[i + 1], -h), p(ts[i + 1], h), p(ts[i], h)]))
    for x in (-h, h):
        faces.append(np.array([[x, r_y * np.cos(t), r_z * np.sin(t)] for t in ts[:-1]]))
    return faces


def shell_faces(s):
    sx, sy, sz = s["Size"]
    shape = s["Shape"]
    if shape == "Block":
        faces = box_faces(sx, sy, sz)
    elif shape == "Wedge":
        faces = wedge_faces(sx, sy, sz)
    elif shape == "Ball":
        d = min(sx, sy, sz)
        faces = ellipsoid_faces(d, d, d)
    elif shape == "Ellipsoid":
        faces = ellipsoid_faces(sx, sy, sz)
    elif shape == "Cylinder":
        d = min(sy, sz)
        faces = cylinder_faces(sx, d, d)
    else:
        faces = box_faces(sx, sy, sz)
    r = rot(s["Rot"])
    pos = np.array(s["Pos"])
    return [f @ r.T + pos for f in faces]


def hex_rgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i : i + 2], 16) / 255 for i in (0, 2, 4)])


def render(model, path):
    views = [("앞", -90, 8), ("앞 3/4", -50, 14), ("옆", 0, 6), ("뒤 3/4", 130, 14)]
    fig = plt.figure(figsize=(15, 5.4), facecolor="#E9EEF5")
    for k, (title, azim, elev) in enumerate(views):
        ax = fig.add_subplot(1, 4, k + 1, projection="3d", computed_zorder=False)
        ax.set_facecolor("#E9EEF5")
        polys, colors = [], []
        # camera direction (for back-face culling & depth); Roblox Y-up -> plot Z-up, Roblox Z -> plot Y
        az, el = np.radians(azim), np.radians(elev)
        cam = np.array([np.cos(el) * np.cos(az), np.cos(el) * np.sin(az), np.sin(el)])  # plot coords
        items = []
        for s in model["Shells"]:
            base = hex_rgb(s["Color"])
            neon = s.get("Material") == "Neon"
            for f in shell_faces(s):
                if len(f) < 3:
                    continue
                n = np.cross(f[1] - f[0], f[2] - f[0])
                if np.linalg.norm(n) < 1e-9:
                    continue
                n = n / np.linalg.norm(n)
                c = f.mean(axis=0)
                pf = f[:, [0, 2, 1]] * np.array([1, 1, 1])  # x, z, y
                pn = np.array([n[0], n[2], n[1]])
                pc = np.array([c[0], c[2], c[1]])
                # orientation of faces is not guaranteed outward; use centroid of the shell instead
                sc = np.array(s["Pos"])
                out = c - sc
                if np.dot(n, out) < 0:
                    n, pn = -n, -pn
                if np.dot(pn, cam) < -0.05:
                    continue
                shade = 1.0 if neon else 0.45 + 0.55 * max(0.0, float(np.dot(n, LIGHT)))
                col = np.clip(base * shade, 0, 1)
                items.append((float(np.dot(pc, cam)), pf, col))
        items.sort(key=lambda t: t[0])
        for _, pf, col in items:
            polys.append(pf)
            colors.append(col)
        pc = Poly3DCollection(polys, facecolors=colors, edgecolors=colors, linewidths=0.2)
        ax.add_collection3d(pc)
        ax.set_xlim(-2, 2)
        ax.set_ylim(-2, 2)
        ax.set_zlim(0, 6.2)
        ax.set_box_aspect((4, 4, 6.2))
        ax.view_init(elev=elev, azim=azim)
        ax.set_axis_off()
        ax.set_title(title, fontsize=11)
    fig.suptitle(f"{model['Kind']} (키 약 {max(np.array(s['Pos'])[1] + s['Size'][1] / 2 for s in model['Shells']):.1f} 스터드)", fontsize=13)
    fig.tight_layout()
    fig.savefig(path, dpi=110)
    plt.close(fig)


def main():
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    os.makedirs(os.path.join(root, "build", "previews"), exist_ok=True)
    for p in sorted(glob.glob(os.path.join(root, "build", "models", "*.json"))):
        model = json.load(open(p))
        out = os.path.join(root, "build", "previews", f"model_{model['Kind']}.png")
        render(model, out)
        print("wrote", os.path.relpath(out, root))


if __name__ == "__main__":
    for f in ("NanumGothic", "Noto Sans CJK KR", "UnDotum"):
        try:
            matplotlib.font_manager.findfont(f, fallback_to_default=False)
            plt.rcParams["font.family"] = f
            break
        except Exception:
            pass
    main()
