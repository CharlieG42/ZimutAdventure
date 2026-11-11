#!/usr/bin/env python3
"""Génère l'empreinte de pas (assets/vfx/overlays/footprint.png).

Usage (depuis la racine du projet) :
    python3 tools/generate_footprint.py

Silhouette blanche avec alpha (orteils + avant-pied + talon, bords estompés),
orientée vers le haut ; teintée sombre au rendu (albedo_color du matériau).
Dépendances : Pillow.
"""
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "vfx", "overlays")


def main():
    w, h = 128, 256
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx = w // 2
    toes = [(cx - 26, 34, 11), (cx - 12, 24, 12), (cx + 2, 22, 13), (cx + 16, 26, 12), (cx + 29, 36, 10)]
    for (x, y, r) in toes:
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, 235))
    d.ellipse([cx - 34, 30, cx + 34, 140], fill=(255, 255, 255, 245))
    d.ellipse([cx - 22, 150, cx + 22, 236], fill=(255, 255, 255, 245))
    img = img.filter(ImageFilter.GaussianBlur(1.6))
    os.makedirs(ROOT, exist_ok=True)
    path = os.path.join(ROOT, "footprint.png")
    img.save(path)
    print("écrit", os.path.normpath(path), img.size)


if __name__ == "__main__":
    main()
