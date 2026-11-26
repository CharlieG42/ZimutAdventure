#!/usr/bin/env python3
"""Génère les icônes d'items et d'outils du HUD (assets/ui/icons/items/).

Usage (depuis la racine du projet) :
    python3 tools/generate_item_icons.py

Chaque icône est un glyphe blanc sur transparent (teintable par le thème du HUD),
dessiné en 4x puis réduit (anti-aliasing propre), avec un liseré sombre pour la
lisibilité sur fond clair comme sombre — même recette que generate_ui_assets.py.

Dépendances : Pillow (pip install pillow). Aucune image externe : tout est vectoriel
(Pillow), comme les icônes d'action existantes.
"""
import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SS = 4
SIZE = 256
WHITE = (255, 255, 255, 255)
OUTLINE = (24, 16, 10, 255)

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "ui", "icons", "items")


def _canvas():
    return Image.new("RGBA", (SIZE * SS, SIZE * SS), (0, 0, 0, 0))


def _finish(img):
    return img.resize((SIZE, SIZE), Image.LANCZOS)


def _u(d):
    return SIZE * SS / 256.0


def _line(d, pts, w, fill=WHITE):
    d.line(pts, fill=fill, width=int(w), joint="curve")
    for p in (pts[0], pts[-1]):
        r = w / 2
        d.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=fill)


def _poly(d, pts, fill=WHITE, outline=None, ow=0):
    if outline is not None and ow > 0:
        d.polygon(pts, fill=outline)
        grown = [((p[0] - 128 * _u(d)) * (1 + ow * 2 / 128) + 128 * _u(d), (p[1] - 128 * _u(d)) * (1 + ow * 2 / 128) + 128 * _u(d)) for p in pts]
        d.polygon(grown, fill=outline)
    d.polygon(pts, fill=fill)


def _ellipse(d, cx, cy, rx, ry, fill=WHITE):
    d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=fill)


def _arc(d, cx, cy, r, a0, a1, w, fill=WHITE):
    d.arc([cx - r, cy - r, cx + r, cy + r], a0, a1, fill=fill, width=int(w))


def _draw_body(fn):
    """fn(d, u) dessine le glyphe ; on dessine d'abord en liseré sombre décalé, puis blanc."""
    img = _canvas()
    d = ImageDraw.Draw(img)
    u = _u(d)
    fn(d, u, OUTLINE, 10)  # contour (épaisseur relative)
    fn(d, u, WHITE, 0)
    return _finish(img)


def _berry(d, u, fill, _):
    for (x, y, r) in [(96, 150, 34), (160, 150, 34), (128, 110, 34)]:
        _ellipse(d, x * u, y * u, r * u, r * u * 0.92, fill)
    _line(d, [(128 * u, 76 * u), (128 * u, 46 * u)], 10 * u, fill)
    leaf = [(128 * u, 52 * u), (158 * u, 38 * u), (168 * u, 62 * u)]
    d.polygon(leaf, fill=fill)


def _stone(d, u, fill, _):
    pts = [(70, 170), (95, 100), (150, 80), (205, 105), (215, 160), (170, 195), (105, 195)]
    _poly(d, [(x * u, y * u) for x, y in pts], fill)


def _wood(d, u, fill, _):
    # Bûche couchée : rectangle arrondi + extrémité circulaire.
    d.rounded_rectangle([52 * u, 108 * u, 204 * u, 164 * u], radius=26 * u, fill=fill)
    _ellipse(d, 204 * u, 136 * u, 18 * u, 28 * u, fill)
    _arc(d, 204 * u, 136 * u, 11 * u, 0, 360, 5 * u, (24, 16, 10, 255) if fill == WHITE else fill)


def _wheat(d, u, fill, _):
    _line(d, [(128 * u, 210 * u), (128 * u, 70 * u)], 10 * u, fill)
    for i in range(5):
        y = 78 * u + i * 24 * u
        for s in (-1, 1):
            d.polygon([(128 * u, y), ((128 + s * 26) * u, (y - 14 * u)), ((128 + s * 26) * u, (y + 10 * u))], fill=fill)
    d.polygon([(128 * u, 60 * u), (146 * u, 34 * u), (128 * u, 44 * u)], fill=fill)
    d.polygon([(128 * u, 60 * u), (110 * u, 34 * u), (128 * u, 44 * u)], fill=fill)


def _egg(d, u, fill, _):
    d.ellipse([88 * u, 70 * u, 168 * u, 196 * u], fill=fill)


def _fish(d, u, fill, _):
    _ellipse(d, 120 * u, 128 * u, 62 * u, 34 * u, fill)
    d.polygon([(176 * u, 128 * u), (214 * u, 100 * u), (214 * u, 156 * u)], fill=fill)
    _ellipse(d, 92 * u, 118 * u, 6 * u, 6 * u, OUTLINE if fill == WHITE else fill)


def _fish_big(d, u, fill, _):
    _fish(d, u, fill, _)
    _arc(d, 120 * u, 128 * u, 44 * u, 200, 340, 8 * u, OUTLINE if fill == WHITE else fill)


def _seeds(d, u, fill, _):
    for (x, y) in [(100, 100), (156, 96), (128, 140), (92, 160), (164, 150), (128, 190), (112, 120), (146, 122)]:
        d.ellipse([(x - 11) * u, (y - 14) * u, (x + 11) * u, (y + 14) * u], fill=fill)


def _meat_raw(d, u, fill, _):
    d.rounded_rectangle([64 * u, 92 * u, 190 * u, 168 * u], radius=30 * u, fill=fill)
    _ellipse(d, 190 * u, 130 * u, 26 * u, 16 * u, fill)  # os
    _ellipse(d, 196 * u, 130 * u, 9 * u, 9 * u, OUTLINE if fill == WHITE else fill)


def _meat_cooked(d, u, fill, _):
    _meat_raw(d, u, fill, _)
    # Marques de grill : deux traits sombres.
    _line(d, [(96 * u, 108 * u), (150 * u, 156 * u)], 7 * u, OUTLINE if fill == WHITE else fill)
    _line(d, [(112 * u, 96 * u), (168 * u, 146 * u)], 7 * u, OUTLINE if fill == WHITE else fill)


def _bread(d, u, fill, _):
    d.rounded_rectangle([60 * u, 100 * u, 196 * u, 180 * u], radius=40 * u, fill=fill)
    for x in (100, 128, 156):
        _line(d, [(x * u, 112 * u), ((x + 10) * u, 168 * u)], 7 * u, OUTLINE if fill == WHITE else fill)


def _soup(d, u, fill, _):
    d.pieslice([70 * u, 90 * u, 186 * u, 190 * u], 180, 360, fill=fill)
    d.rectangle([70 * u, 140 * u, 186 * u, 190 * u], fill=fill)
    _ellipse(d, 128 * u, 140 * u, 58 * u, 12 * u, fill)
    _line(d, [(110 * u, 110 * u), (104 * u, 84 * u)], 6 * u, fill)
    _line(d, [(130 * u, 108 * u), (130 * u, 80 * u)], 6 * u, fill)
    _line(d, [(150 * u, 110 * u), (158 * u, 84 * u)], 6 * u, fill)


def _milk(d, u, fill, _):
    d.rectangle([92 * u, 96 * u, 164 * u, 196 * u], fill=fill)
    d.polygon([(92 * u, 96 * u), (128 * u, 66 * u), (164 * u, 96 * u)], fill=fill)
    d.rectangle([118 * u, 60 * u, 138 * u, 70 * u], fill=fill)


def _pelt(d, u, fill, _):
    d.rounded_rectangle([80 * u, 90 * u, 176 * u, 180 * u], radius=24 * u, fill=fill)
    for x in (96, 128, 160):
        _ellipse(d, x * u, 74 * u, 12 * u, 16 * u, fill)


def _relic(d, u, fill, _):
    d.polygon([(128 * u, 48 * u), (176 * u, 92 * u), (160 * u, 176 * u), (96 * u, 176 * u), (80 * u, 92 * u)], fill=fill)
    _ellipse(d, 128 * u, 118 * u, 18 * u, 18 * u, OUTLINE if fill == WHITE else fill)


def _vegetables(d, u, fill, _):
    # Carotte : corps triangulaire + fanes.
    d.polygon([(96 * u, 200 * u), (120 * u, 110 * u), (144 * u, 200 * u)], fill=fill)
    _line(d, [(120 * u, 110 * u), (104 * u, 76 * u)], 8 * u, fill)
    _line(d, [(120 * u, 110 * u), (120 * u, 70 * u)], 8 * u, fill)
    _line(d, [(120 * u, 110 * u), (138 * u, 78 * u)], 8 * u, fill)


def _roast_vegetables(d, u, fill, _):
    _vegetables(d, u, fill, _)
    _ellipse(d, 176 * u, 170 * u, 22 * u, 22 * u, fill)  # champignon à côté
    _line(d, [(176 * u, 148 * u), (176 * u, 132 * u)], 10 * u, fill)


def _boiled_egg(d, u, fill, _):
    _egg(d, u, fill, _)
    _arc(d, 128 * u, 150 * u, 34 * u, 20, 160, 6 * u, OUTLINE if fill == WHITE else fill)


def _grilled_fish(d, u, fill, _):
    _fish(d, u, fill, _)
    _line(d, [(92 * u, 128 * u), (150 * u, 128 * u)], 6 * u, OUTLINE if fill == WHITE else fill)


def _grilled_fish_big(d, u, fill, _):
    _fish_big(d, u, fill, _)
    _line(d, [(92 * u, 128 * u), (150 * u, 128 * u)], 6 * u, OUTLINE if fill == WHITE else fill)


def _wool(d, u, fill, _):
    for (x, y, r) in [(104, 120, 30), (152, 120, 30), (128, 96, 30), (128, 148, 30), (88, 148, 22), (168, 148, 22)]:
        _ellipse(d, x * u, y * u, r * u, r * u * 0.8, fill)


def _tool_axe(d, u, fill, _):
    _line(d, [(88 * u, 196 * u), (168 * u, 76 * u)], 14 * u, fill)
    head = [(158 * u, 52 * u), (206 * u, 96 * u), (172 * u, 122 * u), (140 * u, 92 * u)]
    d.polygon(head, fill=fill)


def _tool_pickaxe(d, u, fill, _):
    d.line([(70 * u, 214 * u), (150 * u, 70 * u)], fill=fill, width=int(20 * u))
    _arc(d, 150 * u, 104 * u, 70 * u, 200, 340, 22 * u, fill)


def _tool_sickle(d, u, fill, _):
    _line(d, [(84 * u, 200 * u), (140 * u, 96 * u)], 12 * u, fill)
    _arc(d, 168 * u, 84 * u, 44 * u, 100, 320, 12 * u, fill)


def _tool_hoe(d, u, fill, _):
    _line(d, [(92 * u, 200 * u), (164 * u, 72 * u)], 12 * u, fill)
    blade = [(148 * u, 60 * u), (210 * u, 96 * u), (196 * u, 122 * u), (150 * u, 96 * u)]
    d.polygon(blade, fill=fill)


def _tool_watering_can(d, u, fill, _):
    d.rounded_rectangle([84 * u, 110 * u, 172 * u, 196 * u], radius=14 * u, fill=fill)
    _arc(d, 172 * u, 150 * u, 26 * u, 270, 90, 10 * u, fill)
    _line(d, [(84 * u, 130 * u), (52 * u, 96 * u)], 10 * u, fill)
    for (x, y) in [(48, 116), (42, 140), (54, 136)]:
        _ellipse(d, x * u, y * u, 4 * u, 4 * u, fill)


def _tool_bow(d, u, fill, _):
    _arc(d, 128 * u, 128 * u, 84 * u, 60, 300, 12 * u, fill)
    _line(d, [((128 + 84 * 0.5) * u, (128 - 84 * 0.866) * u), ((128 + 84 * 0.5) * u, (128 + 84 * 0.866) * u)], 4 * u, fill)
    _line(d, [(96 * u, 128 * u), (196 * u, 128 * u)], 6 * u, fill)


def _tool_fishing_rod(d, u, fill, _):
    _line(d, [(64 * u, 200 * u), (196 * u, 48 * u)], 9 * u, fill)
    # Fil + hameçon.
    _line(d, [(196 * u, 48 * u), (196 * u, 150 * u)], 3 * u, fill)
    _arc(d, 196 * u, 158 * u, 10 * u, 180, 360, 5 * u, fill)
    _ellipse(d, 64 * u, 200 * u, 10 * u, 10 * u, fill)


def _straw_hat(d, u, fill, _):
    _ellipse(d, 128 * u, 158 * u, 92 * u, 26 * u, fill)
    d.rounded_rectangle([82 * u, 88 * u, 174 * u, 162 * u], radius=30 * u, fill=fill)


def _fur_cloak(d, u, fill, _):
    d.polygon([(96 * u, 58 * u), (160 * u, 58 * u), (196 * u, 206 * u), (60 * u, 206 * u)], fill=fill)
    _ellipse(d, 128 * u, 62 * u, 44 * u, 18 * u, fill)
    for x in (76, 104, 132, 160, 186):
        _ellipse(d, x * u, 204 * u, 14 * u, 10 * u, fill)


def _boots(d, u, fill, _):
    for x0 in (62, 136):
        d.rectangle([x0 * u, 60 * u, (x0 + 34) * u, 176 * u], fill=fill)
        d.rounded_rectangle([x0 * u, 154 * u, (x0 + 62) * u, 196 * u], radius=14 * u, fill=fill)


def _backpack(d, u, fill, _):
    d.rounded_rectangle([74 * u, 70 * u, 182 * u, 206 * u], radius=26 * u, fill=fill)
    _arc(d, 128 * u, 74 * u, 30 * u, 180, 360, 12 * u, fill)
    d.rectangle([92 * u, 140 * u, 164 * u, 150 * u], fill=OUTLINE if fill == WHITE else fill)


def _shirt(d, u, fill, _):
    d.polygon([(92 * u, 56 * u), (164 * u, 56 * u), (214 * u, 96 * u), (190 * u, 128 * u), (172 * u, 116 * u),
               (172 * u, 206 * u), (84 * u, 206 * u), (84 * u, 116 * u), (66 * u, 128 * u), (42 * u, 96 * u)], fill=fill)
    d.polygon([(110 * u, 56 * u), (146 * u, 56 * u), (128 * u, 84 * u)], fill=OUTLINE if fill == WHITE else fill)


def _trousers(d, u, fill, _):
    d.polygon([(80 * u, 50 * u), (176 * u, 50 * u), (190 * u, 210 * u), (140 * u, 210 * u), (128 * u, 110 * u),
               (116 * u, 210 * u), (66 * u, 210 * u)], fill=fill)


def _gloves(d, u, fill, _):
    for dx, flip in ((-44, -1), (44, 1)):
        cx = 128 + dx
        d.rounded_rectangle([(cx - 26) * u, 96 * u, (cx + 26) * u, 186 * u], radius=16 * u, fill=fill)
        for i in range(3):
            fx = cx - 18 + i * 14
            d.rounded_rectangle([fx * u, 60 * u, (fx + 11) * u, 110 * u], radius=6 * u, fill=fill)
        tx = cx + 26 * flip
        d.rounded_rectangle([min(tx, tx + 22 * flip) * u, 110 * u, max(tx, tx + 22 * flip) * u, 140 * u], radius=8 * u, fill=fill)


def _iron_ore(d, u, fill, _):
    d.polygon([(54 * u, 170 * u), (82 * u, 86 * u), (150 * u, 62 * u), (204 * u, 112 * u), (190 * u, 188 * u), (110 * u, 204 * u)], fill=fill)
    spot = OUTLINE if fill == WHITE else fill
    for x, y, r in ((110, 120, 14), (150, 150, 11), (90, 165, 9), (160, 105, 8)):
        _ellipse(d, x * u, y * u, r * u, r * u, spot)


def _iron_ingot(d, u, fill, _):
    d.polygon([(40 * u, 176 * u), (78 * u, 104 * u), (208 * u, 104 * u), (226 * u, 176 * u)], fill=fill)
    d.polygon([(78 * u, 104 * u), (100 * u, 78 * u), (196 * u, 78 * u), (208 * u, 104 * u)], fill=fill)


def _furnace(d, u, fill, _):
    d.pieslice([56 * u, 50 * u, 200 * u, 220 * u], 180, 360, fill=fill)
    d.rectangle([56 * u, 134 * u, 200 * u, 206 * u], fill=fill)
    d.rectangle([150 * u, 30 * u, 176 * u, 90 * u], fill=fill)
    d.rounded_rectangle([100 * u, 140 * u, 156 * u, 196 * u], radius=16 * u, fill=OUTLINE if fill == WHITE else fill)


def _rifle(d, u, fill, _):
    # Carabine à levier : crosse, boîtier, canon, levier.
    d.polygon([(28 * u, 150 * u), (92 * u, 122 * u), (104 * u, 146 * u), (36 * u, 176 * u)], fill=fill)
    d.rectangle([92 * u, 116 * u, 136 * u, 144 * u], fill=fill)
    d.rectangle([132 * u, 118 * u, 236 * u, 128 * u], fill=fill)
    d.rectangle([132 * u, 130 * u, 204 * u, 138 * u], fill=fill)
    _arc(d, 112 * u, 156 * u, 14 * u, 0, 180, 6 * u, fill)


def _cartridge(d, u, fill, _):
    for i, x in enumerate((80, 128, 176)):
        d.rounded_rectangle([(x - 14) * u, 96 * u, (x + 14) * u, 206 * u], radius=4 * u, fill=fill)
        d.pieslice([(x - 14) * u, 64 * u, (x + 14) * u, 124 * u], 180, 360, fill=fill)
        d.rectangle([(x - 16) * u, 196 * u, (x + 16) * u, 206 * u], fill=OUTLINE if fill == WHITE else fill)


def _iron_arrows(d, u, fill, _):
    for dx in (-26, 0, 26):
        d.line([((70 + dx) * u, 210 * u), ((170 + dx) * u, 60 * u)], fill=fill, width=int(9 * u))
        tip = ((176 + dx) * u, 50 * u)
        d.polygon([tip, ((150 + dx) * u, 70 * u), ((172 + dx) * u, 84 * u)], fill=fill)


ICONS = {
    "item_berries": _berry,
    "item_stone": _stone,
    "item_wood": _wood,
    "item_wheat": _wheat,
    "item_egg": _egg,
    "item_boiled_egg": _boiled_egg,
    "item_fish": _fish,
    "item_fish_big": _fish_big,
    "item_grilled_fish": _grilled_fish,
    "item_grilled_fish_big": _grilled_fish_big,
    "item_seeds": _seeds,
    "item_grain_seeds": _seeds,
    "item_raw_meat": _meat_raw,
    "item_cooked_meat": _meat_cooked,
    "item_bread": _bread,
    "item_soup": _soup,
    "item_milk": _milk,
    "item_pelt": _pelt,
    "item_relic": _relic,
    "item_vegetables": _vegetables,
    "item_roast_vegetables": _roast_vegetables,
    "item_wool": _wool,
    "tool_stone_axe": _tool_axe,
    "tool_sickle": _tool_sickle,
    "tool_pickaxe": _tool_pickaxe,
    "tool_hoe": _tool_hoe,
    "tool_watering_can": _tool_watering_can,
    "tool_hunting_bow": _tool_bow,
    "tool_fishing_rod": _tool_fishing_rod,
    "item_iron_ore": _iron_ore,
    "tool_rifle": _rifle,
    "item_cartridge": _cartridge,
    "arrow_iron": _iron_arrows,
    "item_iron_ingot": _iron_ingot,
    "building_furnace": _furnace,
    "gear_straw_hat": _straw_hat,
    "armor_fur_cloak": _fur_cloak,
    "gear_hide_boots": _boots,
    "gear_backpack": _backpack,
    "gear_wool_shirt": _shirt,
    "gear_wool_trousers": _trousers,
    "gear_leather_gloves": _gloves,
}


def main():
    os.makedirs(ROOT, exist_ok=True)
    for name, fn in ICONS.items():
        img = _draw_body(fn)
        path = os.path.join(ROOT, name + ".png")
        img.save(path)
        print("écrit", os.path.normpath(path), img.size)


if __name__ == "__main__":
    main()
