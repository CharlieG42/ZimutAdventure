#!/usr/bin/env python3
"""Génère des cactus saguaro en vrai maillage 3D (GLB), couleurs dans les sommets.

Tronc cylindrique à côtes (rayon modulé par l'angle), 0 à 2 bras (coude horizontal
puis montant), dégradé vertical et ombre à la base, base posée au sol.

Usage (depuis la racine du projet) :
    python3 tools/make_cactus_glb.py all
        -> assets/props/generated/cactus_saguaro_a/b/c.glb
    python3 tools/make_cactus_glb.py out.glb [graine] [hauteur_m]

Stdlib pur (pas de numpy) : les cylindres sont construits à la main.
"""
import json
import math
import os
import struct
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT_DIR = os.path.join(ROOT, "assets", "props", "generated")

GREEN = (0.23, 0.40, 0.15)
GREEN_LIGHT = (0.38, 0.55, 0.24)
RIB_DARK = 0.72  # les sillons sont plus sombres


class Mesh:
    def __init__(self):
        self.pts = []
        self.nrm = []
        self.col = []
        self.idx = []

    def vert(self, p, n, c):
        self.pts.append(p)
        self.nrm.append(n)
        self.col.append(c)
        return len(self.pts) - 1

    def tri(self, a, b, c):
        self.idx.append((a, b, c))


def lerp(a, b, t):
    return a + (b - a) * t


def add_cylinder(mesh, base, radius, height, sides, ribs, color_fn):
    """Cylindre vertical à base `base`, avec côtes : r modulé par cos(ribs*theta).
    color_fn(theta, y01) -> couleur (r,g,b)."""
    ring0 = []
    ring1 = []
    for i in range(sides):
        th = 2.0 * math.pi * i / sides
        r = radius * (1.0 + 0.07 * math.cos(ribs * th))
        x = base[0] + r * math.cos(th)
        z = base[2] + r * math.sin(th)
        n = (math.cos(th), 0.0, math.sin(th))
        c = color_fn(th, 0.0)
        ring0.append(mesh.vert((x, base[1], z), n, c))
        c = color_fn(th, 1.0)
        ring1.append(mesh.vert((x, base[1] + height, z), n, c))
    for i in range(sides):
        j = (i + 1) % sides
        # Deux triangles par quad, ordre anti-horaire vu de l'extérieur.
        mesh.tri(ring0[i], ring0[j], ring1[j])
        mesh.tri(ring0[i], ring1[j], ring1[i])
    # Bouchon supérieur.
    top_c = color_fn(0.0, 1.0)
    ci = mesh.vert((base[0], base[1] + height, base[2]), (0.0, 1.0, 0.0), top_c)
    for i in range(sides):
        j = (i + 1) % sides
        mesh.tri(ci, ring1[j], ring1[i])


def add_elbow(mesh, base, radius, length, sides, ribs, color_fn, axis):
    """Cylindre horizontal le long de `axis` ('x' ou 'z'), de base à base+length."""
    rings = [[], []]
    for k in range(2):
        off = length * k
        for i in range(sides):
            th = 2.0 * math.pi * i / sides
            r = radius * (1.0 + 0.05 * math.cos(ribs * th))
            dx = r * math.cos(th)
            dy = r * math.sin(th)
            if axis == "x":
                p = (base[0] + off, base[1] + dy, base[2] + dx)
                n = (0.0, math.sin(th), math.cos(th))
            else:
                p = (base[0] + dx, base[1] + dy, base[2] + off)
                n = (math.cos(th), math.sin(th), 0.0)
            rings[k].append(mesh.vert(p, n, color_fn(th, float(k))))
    for i in range(sides):
        j = (i + 1) % sides
        mesh.tri(rings[0][i], rings[1][i], rings[1][j])
        mesh.tri(rings[0][i], rings[1][j], rings[0][j])


def saguaro_color(y01):
    g = tuple(lerp(GREEN[k], GREEN_LIGHT[k], y01 * 0.7 + 0.15) for k in range(3))
    ao = lerp(0.62, 1.0, min(1.0, y01 * 2.5))
    return (g[0] * ao, g[1] * ao, g[2] * ao)


def make_cactus(seed, height):
    import random
    rng = random.Random(seed)
    m = Mesh()
    r = 0.16 + rng.random() * 0.05
    sides, ribs = 10, 10

    def trunk_color(th, y01):
        c = saguaro_color(y01)
        rib = RIB_DARK + 0.28 * (0.5 + 0.5 * math.cos(ribs * th))
        return (c[0] * rib, c[1] * rib, c[2] * rib)

    add_cylinder(m, (0.0, 0.0, 0.0), r, height, sides, ribs, trunk_color)
    # Bras : coude horizontal puis montant.
    n_arms = rng.choice([0, 1, 1, 2])
    for a in range(n_arms):
        side = 1.0 if a % 2 == 0 else -1.0
        y0 = height * rng.uniform(0.35, 0.6)
        reach = r * rng.uniform(2.2, 3.2)
        arm_len = height * rng.uniform(0.22, 0.38)
        arm_r = r * rng.uniform(0.62, 0.78)

        def arm_color(th, t):
            c = saguaro_color(0.35 + 0.4 * t)
            rib = RIB_DARK + 0.28 * (0.5 + 0.5 * math.cos(ribs * th))
            return (c[0] * rib, c[1] * rib, c[2] * rib)

        elbow_base = (side * r * 0.9, y0, 0.0)
        add_elbow(m, elbow_base, arm_r, reach, sides, ribs, arm_color, "x")
        up_base = (side * (r * 0.9 + reach), y0, 0.0)
        add_cylinder(m, up_base, arm_r, arm_len, sides, ribs, arm_color)
    return m


def write_glb(path, mesh):
    pts = b"".join(struct.pack("<fff", *p) for p in mesh.pts)
    nrm = b"".join(struct.pack("<fff", *n) for n in mesh.nrm)
    col = b"".join(struct.pack("<ffff", c[0], c[1], c[2], 1.0) for c in mesh.col)
    idx = b"".join(struct.pack("<III", *t) for t in mesh.idx)
    blobs = [pts, nrm, col, idx]
    offsets, data = [], b""
    for b in blobs:
        offsets.append(len(data))
        data += b
        data += b"\0" * (-len(data) % 4)
    xs = [p[0] for p in mesh.pts]
    ys = [p[1] for p in mesh.pts]
    zs = [p[2] for p in mesh.pts]
    js = {
        "asset": {"version": "2.0", "generator": "tools/make_cactus_glb.py"},
        "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0, "name": "cactus"}],
        "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "COLOR_0": 2}, "indices": 3, "material": 0}]}],
        "materials": [{"name": "cactus", "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0.0, "roughnessFactor": 0.9}}],
        "buffers": [{"byteLength": len(data)}],
        "bufferViews": [{"buffer": 0, "byteOffset": offsets[i], "byteLength": len(blobs[i])} for i in range(4)],
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": len(mesh.pts), "type": "VEC3", "min": [min(xs), min(ys), min(zs)], "max": [max(xs), max(ys), max(zs)]},
            {"bufferView": 1, "componentType": 5126, "count": len(mesh.nrm), "type": "VEC3"},
            {"bufferView": 2, "componentType": 5126, "count": len(mesh.col), "type": "VEC4"},
            {"bufferView": 3, "componentType": 5125, "count": len(mesh.idx) * 3, "type": "SCALAR"},
        ],
    }
    j = json.dumps(js).encode()
    j += b" " * (-len(j) % 4)
    total = 12 + 8 + len(j) + 8 + len(data)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as fh:
        fh.write(struct.pack("<4sII", b"glTF", 2, total))
        fh.write(struct.pack("<I4s", len(j), b"JSON") + j)
        fh.write(struct.pack("<I4s", len(data), b"BIN\0") + data)


def main():
    if len(sys.argv) >= 2 and sys.argv[1] != "all":
        out = sys.argv[1]
        seed = int(sys.argv[2]) if len(sys.argv) > 2 else 1
        height = float(sys.argv[3]) if len(sys.argv) > 3 else 2.8
        m = make_cactus(seed, height)
        write_glb(out, m)
        print("%s : %d sommets, %d triangles" % (out, len(m.pts), len(m.idx)))
        return
    specs = [("cactus_saguaro_a.glb", 11, 2.6), ("cactus_saguaro_b.glb", 23, 3.1), ("cactus_saguaro_c.glb", 37, 2.2)]
    for name, seed, h in specs:
        m = make_cactus(seed, h)
        path = os.path.join(OUT_DIR, name)
        write_glb(path, m)
        print("%s : %d sommets, %d triangles" % (os.path.normpath(path), len(m.pts), len(m.idx)))


if __name__ == "__main__":
    main()
