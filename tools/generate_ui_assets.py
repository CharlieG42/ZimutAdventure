#!/usr/bin/env python3
"""Génère les textures d'interface tactile de ZimutAdventure.

Usage (depuis la racine du projet) :
    python3 tools/generate_ui_assets.py

Produit dans assets/ui/ :
  - joystick_base.png / joystick_knob.png : sticks virtuels (palette canyon)
  - icons/jump.png, icons/interact.png, icons/sprint.png : glyphes blancs
    (teintés par le thème du HUD)

Tout est dessiné en 4x puis réduit (anti-aliasing propre, sans dépendance
à une police). Dépendance : Pillow (pip install pillow).
"""
import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SS = 4  # facteur de sur-échantillonnage

SAND = (245, 232, 205)
OCHER = (224, 162, 92)
RUST = (176, 92, 44)
INK = (24, 16, 10)

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "ui")


def _canvas(size):
    return Image.new("RGBA", (size * SS, size * SS), (0, 0, 0, 0))


def _finish(img, size):
    return img.resize((size, size), Image.LANCZOS)


def _circle_bbox(cx, cy, r):
    return (cx - r, cy - r, cx + r, cy + r)


def make_base(size=512):
    img = _canvas(size)
    d = ImageDraw.Draw(img)
    c = size * SS / 2
    r_outer = (size / 2 - 22) * SS

    # Disque sombre translucide : lisible sur ciel clair comme sur sol sombre.
    d.ellipse(_circle_bbox(c, c, r_outer), fill=INK + (105,))

    # Léger dégradé intérieur (plus clair au centre) pour donner du volume.
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    steps = 40
    for i in range(steps):
        t = i / (steps - 1)
        r = r_outer * (1.0 - t * 0.85)
        a = int(34 * t)
        gd.ellipse(_circle_bbox(c, c, r), fill=SAND + (a,))
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).ellipse(_circle_bbox(c, c, r_outer), fill=255)
    glow.putalpha(ImageChops.multiply(glow.getchannel("A"), mask))
    img = Image.alpha_composite(img, glow)
    d = ImageDraw.Draw(img)

    # Anneau extérieur : liseré sombre (contraste) puis trait sable.
    d.ellipse(_circle_bbox(c, c, r_outer), outline=(0, 0, 0, 70), width=int(26 * SS / 2))
    d.ellipse(_circle_bbox(c, c, r_outer - 2 * SS), outline=SAND + (235,), width=int(12 * SS / 2))

    # Anneau intérieur fin (repère de la zone de marche).
    r_inner = r_outer * 0.62
    d.ellipse(_circle_bbox(c, c, r_inner), outline=SAND + (70,), width=int(4 * SS / 2))

    # Chevrons directionnels (haut, bas, gauche, droite).
    r_tick = r_outer * 0.80
    s = 15 * SS
    for ang in (0, 90, 180, 270):
        a = math.radians(ang)
        tip = (c + math.sin(a) * (r_tick + s), c - math.cos(a) * (r_tick + s))
        left = (c + math.sin(a) * r_tick + math.cos(a) * s, c - math.cos(a) * r_tick + math.sin(a) * s)
        right = (c + math.sin(a) * r_tick - math.cos(a) * s, c - math.cos(a) * r_tick - math.sin(a) * s)
        d.polygon([tip, left, right], fill=SAND + (150,))

    return _finish(img, size)


def make_knob(size=176):
    img = _canvas(size)
    c = size * SS / 2
    r = (size / 2 - 24) * SS

    # Ombre portée douce (marge suffisante pour ne pas être tronquée).
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.ellipse(_circle_bbox(c, c + 6 * SS, r), fill=(0, 0, 0, 120))
    shadow = shadow.filter(ImageFilter.GaussianBlur(5 * SS))
    img = Image.alpha_composite(img, shadow)
    d = ImageDraw.Draw(img)

    # Corps : dégradé radial sable -> ocre, éclairé en haut à gauche.
    body = Image.new("RGBA", img.size, (0, 0, 0, 0))
    bd = ImageDraw.Draw(body)
    steps = 60
    hx, hy = c - r * 0.22, c - r * 0.26
    for i in range(steps):
        t = i / (steps - 1)  # 0 = bord, 1 = point chaud
        col = tuple(int(OCHER[k] + (SAND[k] - OCHER[k]) * t) for k in range(3))
        rr = r * (1.0 - t * 0.9)
        cx = c + (hx - c) * t
        cy = c + (hy - c) * t
        bd.ellipse(_circle_bbox(cx, cy, rr), fill=col + (255,))
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).ellipse(_circle_bbox(c, c, r), fill=255)
    body.putalpha(ImageChops.multiply(body.getchannel("A"), mask))
    img = Image.alpha_composite(img, body)
    d = ImageDraw.Draw(img)

    # Contour sombre fin + liseré clair intérieur.
    d.ellipse(_circle_bbox(c, c, r), outline=(70, 40, 18, 200), width=int(5 * SS / 2))
    d.ellipse(_circle_bbox(c, c, r - 6 * SS), outline=SAND + (110,), width=int(3 * SS / 2))

    return _finish(img, size)


def _icon_canvas(size=160):
    return _canvas(size), size


def _line(d, pts, width, fill=(255, 255, 255, 255)):
    d.line(pts, fill=fill, width=width, joint="curve")
    for p in (pts[0], pts[-1]):
        d.ellipse(_circle_bbox(p[0], p[1], width / 2), fill=fill)


def make_icon_jump(size=160):
    img, size = _icon_canvas(size)
    d = ImageDraw.Draw(img)
    u = size * SS / 160.0
    # Flèche vers le haut + socle.
    _line(d, [(80 * u, 128 * u), (80 * u, 44 * u)], int(16 * u))
    _line(d, [(40 * u, 82 * u), (80 * u, 40 * u), (120 * u, 82 * u)], int(16 * u))
    _line(d, [(46 * u, 142 * u), (114 * u, 142 * u)], int(12 * u))
    return _finish(img, size)


def make_icon_interact(size=160):
    img, size = _icon_canvas(size)
    d = ImageDraw.Draw(img)
    u = size * SS / 160.0
    c = 80 * u
    # Cible : point central, anneau, 4 repères.
    d.ellipse(_circle_bbox(c, c, 14 * u), fill=(255, 255, 255, 255))
    d.ellipse(_circle_bbox(c, c, 42 * u), outline=(255, 255, 255, 255), width=int(10 * u))
    for ang in (0, 90, 180, 270):
        a = math.radians(ang)
        p0 = (c + math.sin(a) * 56 * u, c - math.cos(a) * 56 * u)
        p1 = (c + math.sin(a) * 74 * u, c - math.cos(a) * 74 * u)
        _line(d, [p0, p1], int(10 * u))
    return _finish(img, size)


def make_icon_sprint(size=160):
    img, size = _icon_canvas(size)
    d = ImageDraw.Draw(img)
    u = size * SS / 160.0
    # Double chevron >> + traînées de vitesse.
    for ox in (-22, 22):
        _line(d, [((70 + ox) * u, 40 * u), ((104 + ox) * u, 80 * u), ((70 + ox) * u, 120 * u)], int(16 * u))
    _line(d, [(22 * u, 62 * u), (46 * u, 62 * u)], int(9 * u), (255, 255, 255, 190))
    _line(d, [(14 * u, 98 * u), (40 * u, 98 * u)], int(9 * u), (255, 255, 255, 190))
    return _finish(img, size)


def main():
    os.makedirs(os.path.join(ROOT, "icons"), exist_ok=True)
    outputs = {
        "joystick_base.png": make_base(),
        "joystick_knob.png": make_knob(),
        os.path.join("icons", "jump.png"): make_icon_jump(),
        os.path.join("icons", "interact.png"): make_icon_interact(),
        os.path.join("icons", "sprint.png"): make_icon_sprint(),
    }
    for name, image in outputs.items():
        path = os.path.join(ROOT, name)
        image.save(path)
        print("écrit", os.path.normpath(path), image.size)


if __name__ == "__main__":
    main()
