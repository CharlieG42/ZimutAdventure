#!/usr/bin/env python3
"""Génère les assets d'atmosphère : couverture nuageuse du ciel, vignette, grain film.

Usage (depuis la racine du projet) :
    python3 tools/generate_atmosphere_assets.py

Sorties :
  - assets/vfx/sky/cloud_cover.png    1024x512, bruit fractal seuillé, tileable (x et y),
                                       alpha = densité des nuages (blanc = nuage) ;
                                       branchée sur ProceduralSkyMaterial.sky_cover.
  - assets/vfx/overlays/vignette.png  1024x1024, alpha radiale (transparent au centre,
                                       sombre aux coins), posée en multiply sur le HUD.
  - assets/vfx/overlays/grain.png      128x128, bruit gris uniforme, alpha faible (~7 %),
                                       animé en décalant la position (grain film subtil).

Dépendances : Pillow. Aucune image externe.
"""
import math
import os
import random

from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "vfx")


def _value_noise_tileable(w, h, cells_x, cells_y, seed):
    """Bruit de valeur tileable : la grille de hashs boucle en x et y."""
    rng = random.Random(seed)
    grid = [[rng.random() for _ in range(cells_x)] for _ in range(cells_y)]

    def sample(fx, fy):
        ix, iy = math.floor(fx), math.floor(fy)
        tx, ty = fx - ix, fy - iy
        tx = tx * tx * (3 - 2 * tx)
        ty = ty * ty * (3 - 2 * ty)
        x0, x1 = ix % cells_x, (ix + 1) % cells_x
        y0, y1 = iy % cells_y, (iy + 1) % cells_y
        a = grid[y0][x0] + (grid[y0][x1] - grid[y0][x0]) * tx
        b = grid[y1][x0] + (grid[y1][x1] - grid[y1][x0]) * tx
        return a + (b - a) * ty

    img = Image.new("L", (w, h))
    px = img.load()
    for y in range(h):
        fy = y / h * cells_y
        for x in range(w):
            fx = x / w * cells_x
            px[x, y] = int(sample(fx, fy) * 255)
    return img


def _fractal(w, h, seed, octaves=5, base_cells=4):
    total = Image.new("L", (w, h))
    tp = total.load()
    amp, norm = 1.0, 0.0
    cells = base_cells
    for o in range(octaves):
        layer = _value_noise_tileable(w, h, cells, max(2, cells * h // w), seed + o * 101)
        lp = layer.load()
        for y in range(h):
            for x in range(w):
                tp[x, y] = int(tp[x, y] + lp[x, y] * amp)
        norm += amp
        amp *= 0.55
        cells *= 2
    for y in range(h):
        for x in range(w):
            # lp est déjà en 0..255 : on moyenne (pas de remise à l'échelle 255).
            tp[x, y] = int(tp[x, y] / norm)
    return total


def make_cloud_cover(path, w=1024, h=512):
    n = _fractal(w, h, seed=7, octaves=5, base_cells=4)
    # Second calque plus fin pour le détail des bords.
    detail = _fractal(w, h, seed=19, octaves=4, base_cells=16)
    np_, dp = n.load(), detail.load()
    # Normalisation entre min/max réels (le fractal ne touche jamais 0/255).
    vals = [np_[x, y] * 0.75 + dp[x, y] * 0.25 for y in range(h) for x in range(w)]
    lo, hi = min(vals), max(vals)
    img = Image.new("RGBA", (w, h))
    ip = img.load()
    for y in range(h):
        for x in range(w):
            v = (np_[x, y] * 0.75 + dp[x, y] * 0.25 - lo) / max(1.0, hi - lo)
            # Seuil doux : moutons de nuages (~30 % de couverture) aux bords estompés.
            a = max(0.0, min(1.0, (v - 0.63) * 5.0))
            a = a * a * (3 - 2 * a)
            ip[x, y] = (255, 255, 255, int(a * 235))
    img.save(path)
    print("écrit", os.path.normpath(path), img.size)


def make_vignette(path, size=1024):
    img = Image.new("RGBA", (size, size))
    px = img.load()
    c = (size - 1) / 2.0
    max_d = math.hypot(c, c)
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - c, y - c) / max_d
            # Doux : transparent jusqu'à 55 %, puis montée vers les coins (max ~38 %).
            a = max(0.0, (d - 0.55) / 0.45)
            a = a * a * (3 - 2 * a)
            px[x, y] = (10, 6, 4, int(a * 97))
    img.save(path)
    print("écrit", os.path.normpath(path), img.size)


def make_grain(path, size=128):
    rng = random.Random(1234)
    img = Image.new("RGBA", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            v = rng.randint(96, 160)
            px[x, y] = (v, v, v, 20)  # alpha ~8 % : grain très discret
    img.save(path)
    print("écrit", os.path.normpath(path), img.size)


def main():
    sky = os.path.join(ROOT, "sky")
    overlays = os.path.join(ROOT, "overlays")
    os.makedirs(sky, exist_ok=True)
    os.makedirs(overlays, exist_ok=True)
    make_cloud_cover(os.path.join(sky, "cloud_cover.png"))
    make_vignette(os.path.join(overlays, "vignette.png"))
    make_grain(os.path.join(overlays, "grain.png"))


if __name__ == "__main__":
    main()
