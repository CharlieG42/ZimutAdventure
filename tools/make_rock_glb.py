#!/usr/bin/env python3
"""Génère des rochers de grès en vrai maillage 3D (GLB) : sphère géodésique déformée par du bruit
fractal, aplatie à la base, avec strates de couleur et ombre « cuite » dans les couleurs des sommets.
Usage : python3 tools/make_rock_glb.py out.glb [graine] [largeur_m]
Dépend de numpy."""
import json, struct, sys
import numpy as np

def icosphere(levels):
    t = (1 + 5 ** 0.5) / 2
    v = [(-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t), (0, -1, -t), (0, 1, -t),
         (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1)]
    f = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6),
         (7, 1, 8), (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10),
         (8, 6, 7), (9, 8, 1)]
    verts = [np.array(p, float) / np.linalg.norm(p) for p in v]
    cache = {}
    def mid(a, b):
        key = (min(a, b), max(a, b))
        if key not in cache:
            p = (verts[a] + verts[b]) / 2
            verts.append(p / np.linalg.norm(p))
            cache[key] = len(verts) - 1
        return cache[key]
    for _ in range(levels):
        nf = []
        for a, b, c in f:
            ab, bc, ca = mid(a, b), mid(b, c), mid(c, a)
            nf += [(a, ab, ca), (b, bc, ab), (c, ca, bc), (ab, bc, ca)]
        f = nf
    return np.array(verts), np.array(f)

def value_noise(p, seed):
    """Bruit de valeur 3D lissé, vectorisé (p : N×3)."""
    def h(ix, iy, iz):
        n = (ix * 374761393 + iy * 668265263 + iz * 2147483647 + seed * 1274126177) & 0xFFFFFFFF
        n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
        return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0
    i = np.floor(p).astype(np.int64)
    f = p - np.floor(p)
    f = f * f * (3 - 2 * f)
    out = 0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (f[:, 0] if dx else 1 - f[:, 0]) * (f[:, 1] if dy else 1 - f[:, 1]) * (f[:, 2] if dz else 1 - f[:, 2])
                out = out + w * h(i[:, 0] + dx, i[:, 1] + dy, i[:, 2] + dz)
    return out

def fractal(p, seed, octaves=4):
    total, amp, freq, norm = 0, 1.0, 1.0, 0
    for o in range(octaves):
        total = total + amp * value_noise(p * freq, seed + o * 17)
        norm += amp
        amp *= 0.5
        freq *= 2.1
    return total / norm

def make_rock(seed=1, width=3.0):
    rng = np.random.default_rng(seed)
    v, f = icosphere(4)
    # Forme de base : ellipsoïde écrasé, orientation aléatoire des proportions.
    sx, sz = rng.uniform(1.0, 1.35), rng.uniform(0.8, 1.1)
    base = v * np.array([sx, 0.85, sz])
    n_large = fractal(v * 1.3 + seed * 3.1, seed, 3)
    n_fine = fractal(v * 5.0 + seed * 7.7, seed + 99, 3)
    ridge = 1 - np.abs(2 * fractal(v * 2.4 + seed * 5.3, seed + 41, 3) - 1)   # arêtes vives
    disp = 1 + (n_large - 0.5) * 0.7 + (ridge - 0.5) * 0.45 + (n_fine - 0.5) * 0.12
    pts = base * disp[:, None]
    # Strates : légères marches horizontales qui creusent la roche (grès stratifié).
    layer = np.sin(pts[:, 1] * 9.0 + n_large * 3.0)
    pts[:, 0] *= 1 + 0.025 * layer
    pts[:, 2] *= 1 + 0.025 * layer
    # Terrasses : les strates dures forment de petits ressauts horizontaux.
    k = 5.0
    stepped = np.floor(pts[:, 1] * k) / k + 0.5 / k * np.clip((pts[:, 1] * k) % 1.0 * 3.0 - 1.0, 0, 1)
    pts[:, 1] = pts[:, 1] * 0.55 + stepped * 0.45
    # Base plate posée au sol.
    floor = -0.34
    pts[:, 1] = np.maximum(pts[:, 1], floor + (pts[:, 1] - floor) * 0.0 + 0.0)
    pts[:, 1] -= pts[:, 1].min()
    scale = width / (pts[:, 0].max() - pts[:, 0].min())
    pts *= scale
    # Normales lissées pondérées par l'aire.
    tri = pts[f]
    fn = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    vn = np.zeros_like(pts)
    for k in range(3):
        np.add.at(vn, f[:, k], fn)
    vn /= np.linalg.norm(vn, axis=1)[:, None] + 1e-12
    # Orientation extérieure garantie : normale vers l'extérieur du centre.
    centre = pts.mean(axis=0)
    flip = np.einsum("ij,ij->i", vn, pts - centre) < 0
    vn[flip] *= -1
    # Couleurs : strates ocre/rouge + variations + ombre cuite (bas et creux plus sombres).
    h = pts[:, 1] / pts[:, 1].max()
    band = 0.5 + 0.5 * np.sin(pts[:, 1] * 7.5 / scale * 1.0 + n_large * 4.0)
    ochre = np.array([0.80, 0.55, 0.34])
    red = np.array([0.62, 0.30, 0.20])
    col = ochre[None] * (1 - band[:, None] * 0.55) + red[None] * (band[:, None] * 0.55)
    col *= (0.86 + 0.28 * n_fine)[:, None]
    hollow = np.clip((1.0 - disp / disp.mean()) * 1.6, 0, 1)
    ao = 0.55 + 0.45 * np.clip(h * 1.4, 0, 1)
    ao *= 1 - 0.35 * hollow
    col *= ao[:, None]
    up = np.clip(vn[:, 1], 0, 1)
    col = col * (1 - 0.12 * up[:, None]) + np.array([0.9, 0.78, 0.55]) * (0.10 * up[:, None])
    # Triangles dans le sens anti-horaire vu de l'extérieur (convention glTF).
    idx = f.copy()
    c = np.cross(pts[idx[:, 1]] - pts[idx[:, 0]], pts[idx[:, 2]] - pts[idx[:, 0]])
    out = np.einsum("ij,ij->i", c, pts[idx].mean(axis=1) - centre) < 0
    idx[out] = idx[out][:, ::-1]
    return pts.astype(np.float32), vn.astype(np.float32), np.clip(col, 0, 1).astype(np.float32), idx.astype(np.uint32)

def write_glb(path, pts, nrm, col, idx):
    col4 = np.concatenate([col, np.ones((len(col), 1), np.float32)], axis=1)
    blobs = [pts.tobytes(), nrm.tobytes(), col4.astype(np.float32).tobytes(), idx.reshape(-1).tobytes()]
    offsets, data = [], b""
    for b in blobs:
        offsets.append(len(data)); data += b
        data += b"\0" * (-len(data) % 4)
    js = {
        "asset": {"version": "2.0", "generator": "tools/make_rock_glb.py"},
        "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0, "name": "rock"}],
        "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "COLOR_0": 2}, "indices": 3, "material": 0}]}],
        "materials": [{"name": "sandstone", "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0.0, "roughnessFactor": 0.95}}],
        "buffers": [{"byteLength": len(data)}],
        "bufferViews": [{"buffer": 0, "byteOffset": offsets[i], "byteLength": len(blobs[i])} for i in range(4)],
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": len(pts), "type": "VEC3", "min": pts.min(0).tolist(), "max": pts.max(0).tolist()},
            {"bufferView": 1, "componentType": 5126, "count": len(pts), "type": "VEC3"},
            {"bufferView": 2, "componentType": 5126, "count": len(pts), "type": "VEC4"},
            {"bufferView": 3, "componentType": 5125, "count": int(idx.size), "type": "SCALAR"}],
    }
    j = json.dumps(js).encode(); j += b" " * (-len(j) % 4)
    total = 12 + 8 + len(j) + 8 + len(data)
    with open(path, "wb") as fh:
        fh.write(struct.pack("<4sII", b"glTF", 2, total))
        fh.write(struct.pack("<I4s", len(j), b"JSON") + j)
        fh.write(struct.pack("<I4s", len(data), b"BIN\0") + data)

if __name__ == "__main__":
    out = sys.argv[1]
    seed = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    width = float(sys.argv[3]) if len(sys.argv) > 3 else 3.0
    p, n, c, i = make_rock(seed, width)
    write_glb(out, p, n, c, i)
    print("%s : %d sommets, %d triangles" % (out, len(p), len(i)))
