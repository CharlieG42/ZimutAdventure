#!/usr/bin/env python3
"""Vendor, normalise et compose les props GLB de ZimutAdventure.

Usage (depuis la racine du projet) :
    python3 tools/make_glb_props.py all --kenney-root /chemin/vers/kenney
    python3 tools/make_glb_props.py vendor --kenney-root /chemin/vers/kenney
    python3 tools/make_glb_props.py compose
    python3 tools/make_glb_props.py inspect assets/props/kenney/nature/pine_a.glb

Sources : miroir GitHub CC0 des kits Kenney (https://github.com/shorepine/kenney,
miroir de kenney.nl, licence CC0 1.0 — voir assets/props/LICENSE-kenney.txt).

Produit dans assets/props/kenney/ :
  - nature/*.glb : arbres, rochers, buissons, herbes, fleurs, cactus
    (GLB autonomes Kenney, normalisés à une hauteur cible en mètres, origine au sol)
  - castle/ruin_a.glb, castle/ruin_b.glb : ruines composées à partir de pièces
    du Castle Kit, teintées façon grès ocre (baseColorFactor)
  - castle/Textures/colormap.png : texture référencée par les pièces castle

Le binaire GLB est un conteneur JSON + BIN : tout est fait ici en stdlib pur
(struct/json), sans dépendance externe ni Blender. Godot 4 importe les .glb
nativement.
"""
import argparse
import json
import math
import os
import shutil
import struct

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
PROPS_DIR = os.path.join(ROOT, "assets", "props", "kenney")

GLB_MAGIC = 0x46546C67
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942

# out name -> (kit, source GLB Kenney, hauteur cible en mètres)
NATURE_SPEC = [
    ("pine_default_a.glb", "tree_pineDefaultA.glb", 5.2),
    ("pine_default_b.glb", "tree_pineDefaultB.glb", 5.0),
    ("pine_tall_a.glb", "tree_pineTallA.glb", 6.5),
    ("pine_tall_b.glb", "tree_pineTallB.glb", 6.8),
    ("pine_round_a.glb", "tree_pineRoundA.glb", 4.6),
    ("pine_round_b.glb", "tree_pineRoundB.glb", 4.4),
    ("pine_round_c.glb", "tree_pineRoundC.glb", 4.8),
    ("pine_small_a.glb", "tree_pineSmallA.glb", 3.6),
    ("pine_small_b.glb", "tree_pineSmallB.glb", 3.4),
    ("boulder_a.glb", "rock_smallA.glb", 1.0),
    ("boulder_b.glb", "rock_smallB.glb", 1.1),
    ("boulder_c.glb", "rock_largeA.glb", 1.2),
    ("boulder_d.glb", "rock_largeB.glb", 1.3),
    ("boulder_e.glb", "rock_largeC.glb", 1.1),
    ("boulder_f.glb", "rock_largeD.glb", 1.4),
    ("boulder_g.glb", "rock_largeE.glb", 1.2),
    ("boulder_h.glb", "rock_largeF.glb", 1.3),
    ("boulder_flat_a.glb", "rock_smallFlatA.glb", 0.45),
    ("boulder_flat_b.glb", "rock_smallFlatB.glb", 0.5),
    ("shrub_a.glb", "plant_bush.glb", 0.7),
    ("shrub_b.glb", "plant_bushDetailed.glb", 0.8),
    ("shrub_c.glb", "plant_bushSmall.glb", 0.5),
    ("shrub_d.glb", "plant_bushLarge.glb", 1.0),
    ("grass_a.glb", "grass.glb", 0.35),
    ("grass_b.glb", "grass_large.glb", 0.5),
    ("grass_c.glb", "grass_leafs.glb", 0.4),
    ("flower_red_a.glb", "flower_redA.glb", 0.3),
    ("flower_red_b.glb", "flower_redB.glb", 0.32),
    ("flower_red_c.glb", "flower_redC.glb", 0.28),
    ("flower_purple_a.glb", "flower_purpleA.glb", 0.3),
    ("flower_purple_b.glb", "flower_purpleB.glb", 0.34),
    ("flower_purple_c.glb", "flower_purpleC.glb", 0.29),
    ("flower_yellow_a.glb", "flower_yellowA.glb", 0.3),
    ("flower_yellow_b.glb", "flower_yellowB.glb", 0.31),
    ("flower_yellow_c.glb", "flower_yellowC.glb", 0.27),
    ("cactus_short.glb", "cactus_short.glb", 1.5),
    ("cactus_tall.glb", "cactus_tall.glb", 2.8),
]

# Ruines composées : (pièce castle, x, y, z, rotation Y en degrés, échelle).
# Le Castle Kit fait ~1 unité par bloc ; on scale à l'échelle du jeu (mètres).
RUIN_SPEC = [
    (
        "castle/ruin_a.glb",
        (0.96, 0.68, 0.45),
        [
            ("tower-square-base.glb", 0.0, 0.0, 0.0, 0.0, 4.0),
            ("tower-square-mid-open.glb", 0.0, 4.04, 0.0, 0.0, 4.0),
            ("wall.glb", 4.6, 0.0, 1.2, 90.0, 3.0),
            ("wall-half.glb", -4.4, 0.0, -1.5, -25.0, 3.0),
            ("wall-corner.glb", 0.5, 0.0, -4.6, 180.0, 3.0),
            ("siege-ram-demolished.glb", 2.6, 0.0, 4.0, 40.0, 2.2),
        ],
    ),
    (
        "castle/ruin_b.glb",
        (0.90, 0.60, 0.40),
        [
            ("tower-square-base.glb", 0.0, 0.0, 0.0, 0.0, 3.5),
            ("tower-square-mid-windows.glb", 0.0, 3.54, 0.0, 0.0, 3.5),
            ("wall-doorway.glb", 4.0, 0.0, -0.8, 90.0, 3.0),
            ("wall.glb", -3.8, 0.0, 2.0, 15.0, 3.0),
            ("siege-catapult-demolished.glb", 1.2, 0.0, 4.2, -60.0, 2.5),
            ("siege-tower-demolished.glb", -2.2, 0.0, -3.8, 10.0, 1.8),
        ],
    ),
]


def read_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, _version, _length = struct.unpack_from("<III", data, 0)
    if magic != GLB_MAGIC:
        raise ValueError("%s n'est pas un GLB" % path)
    clen, ctype = struct.unpack_from("<II", data, 12)
    if ctype != CHUNK_JSON:
        raise ValueError("%s : premier chunk pas JSON" % path)
    js = json.loads(data[20 : 20 + clen])
    off = 20 + clen
    blen, btype = struct.unpack_from("<II", data, off)
    bin_data = data[off + 8 : off + 8 + blen] if btype == CHUNK_BIN else b""
    return js, bin_data


def write_glb(path, js, bin_data):
    js_bytes = json.dumps(js, separators=(",", ":")).encode("utf-8")
    js_pad = (4 - len(js_bytes) % 4) % 4
    js_bytes += b" " * js_pad
    bin_pad = (4 - len(bin_data) % 4) % 4
    bin_data = bin_data + b"\x00" * bin_pad
    total = 12 + 8 + len(js_bytes) + 8 + len(bin_data)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", GLB_MAGIC, 2, total))
        f.write(struct.pack("<II", len(js_bytes), CHUNK_JSON))
        f.write(js_bytes)
        f.write(struct.pack("<II", len(bin_data), CHUNK_BIN))
        f.write(bin_data)


def position_accessor_indices(js):
    out = set()
    for mesh in js.get("meshes", []):
        for prim in mesh.get("primitives", []):
            pos = prim.get("attributes", {}).get("POSITION")
            if pos is not None:
                out.add(pos)
    return out


def transform_positions(js, bin_data, scale, translate):
    """Applique p' = p * scale + translate aux attributs POSITION, en place."""
    buf = bytearray(bin_data)
    for idx in position_accessor_indices(js):
        acc = js["accessors"][idx]
        bv = js["bufferViews"][acc["bufferView"]]
        base = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
        stride = bv.get("byteStride", 12)
        count = acc["count"]
        mins = [math.inf] * 3
        maxs = [-math.inf] * 3
        for i in range(count):
            off = base + i * stride
            x, y, z = struct.unpack_from("<fff", buf, off)
            x, y, z = x * scale + translate[0], y * scale + translate[1], z * scale + translate[2]
            struct.pack_into("<fff", buf, off, x, y, z)
            for k, v in enumerate((x, y, z)):
                mins[k] = min(mins[k], v)
                maxs[k] = max(maxs[k], v)
        acc["min"] = mins
        acc["max"] = maxs
    return bytes(buf)


def normalize(js, bin_data, target_height):
    """Échelle uniforme pour que la hauteur fasse target_height mètres,
    origine ramenée au sol (min.y = 0) et centrée en x/z."""
    mins = [math.inf] * 3
    maxs = [-math.inf] * 3
    for idx in position_accessor_indices(js):
        acc = js["accessors"][idx]
        for k in range(3):
            mins[k] = min(mins[k], acc["min"][k])
            maxs[k] = max(maxs[k], acc["max"][k])
    height = maxs[1] - mins[1]
    if height < 1e-9:
        raise ValueError("hauteur nulle, normalisation impossible")
    scale = target_height / height
    translate = [
        -(mins[0] + maxs[0]) * 0.5 * scale,
        -mins[1] * scale,
        -(mins[2] + maxs[2]) * 0.5 * scale,
    ]
    return transform_positions(js, bin_data, scale, translate)


def tint_materials(js, rgb):
    for mat in js.get("materials", []):
        pbr = mat.setdefault("pbrMetallicRoughness", {})
        bcf = pbr.get("baseColorFactor", [1.0, 1.0, 1.0, 1.0])
        pbr["baseColorFactor"] = [bcf[0] * rgb[0], bcf[1] * rgb[1], bcf[2] * rgb[2], bcf[3]]


def yaw_quat(deg):
    half = math.radians(deg) * 0.5
    return [0.0, math.sin(half), 0.0, math.cos(half)]


def compose_glb(out_path, parts, tint=None):
    """parts : liste de (chemin GLB source, (x,y,z), rotY_deg, échelle).
    Fusionne tous les GLB en un seul document glTF (un buffer, une scène),
    chaque pièce devenant un nœud enfant avec sa transformée."""
    out = {
        "asset": {"version": "2.0", "generator": "zimutadventure tools/make_glb_props.py"},
        "scene": 0,
        "scenes": [{"nodes": []}],
        "nodes": [],
        "meshes": [],
        "materials": [],
        "accessors": [],
        "bufferViews": [],
        "buffers": [{"byteLength": 0}],
    }
    out["images"] = []
    out["textures"] = []
    out["samplers"] = []
    bin_chunks = []
    bin_base = 0
    image_index_by_uri = {}

    for src, pos, rot_deg, scale in parts:
        js, bin_data = read_glb(src)
        pad = (4 - len(bin_data) % 4) % 4
        bin_chunks.append(bin_data + b"\x00" * pad)
        bv_off = len(out["bufferViews"])
        acc_off = len(out["accessors"])
        mesh_off = len(out["meshes"])
        mat_off = len(out["materials"])
        node_off = len(out["nodes"])
        samp_off = len(out["samplers"])

        for bv in js.get("bufferViews", []):
            bv["buffer"] = 0
            bv["byteOffset"] = bv.get("byteOffset", 0) + bin_base
            out["bufferViews"].append(bv)
        for acc in js.get("accessors", []):
            if "bufferView" in acc:
                acc["bufferView"] += bv_off
            out["accessors"].append(acc)
        for mesh in js.get("meshes", []):
            for prim in mesh.get("primitives", []):
                for attr, ai in list(prim.get("attributes", {}).items()):
                    prim["attributes"][attr] = ai + acc_off
                if "indices" in prim:
                    prim["indices"] += acc_off
                if "material" in prim:
                    prim["material"] += mat_off
            out["meshes"].append(mesh)
        # Images d'abord (dédup par URI), puis textures, puis matériaux.
        img_map = {}
        for local_i, img in enumerate(js.get("images", [])):
            uri = img.get("uri")
            if uri is not None and uri in image_index_by_uri:
                img_map[local_i] = image_index_by_uri[uri]
            else:
                img_map[local_i] = len(out["images"])
                out["images"].append(img)
                if uri is not None:
                    image_index_by_uri[uri] = img_map[local_i]
        tex_map = {}
        for local_t, tex in enumerate(js.get("textures", [])):
            tex_map[local_t] = len(out["textures"])
            if "sampler" in tex:
                tex["sampler"] += samp_off
            if "source" in tex:
                tex["source"] = img_map[tex["source"]]
            out["textures"].append(tex)
        for s in js.get("samplers", []):
            out["samplers"].append(s)
        for mat in js.get("materials", []):
            for key, ti in list(mat.items()):
                # glTF 2.0 : les matériaux référencent textures[] via "index".
                if key == "pbrMetallicRoughness":
                    bct = ti.get("baseColorTexture")
                    if bct is not None and "index" in bct:
                        bct["index"] = tex_map[bct["index"]]
                elif key.endswith("Texture") and isinstance(ti, dict) and "index" in ti:
                    ti["index"] = tex_map[ti["index"]]
            out["materials"].append(mat)
        for node in js.get("nodes", []):
            if "mesh" in node:
                node["mesh"] += mesh_off
            if "children" in node:
                node["children"] = [c + node_off for c in node["children"]]
            out["nodes"].append(node)

        scene_roots = js.get("scenes", [{}])[0].get("nodes", [])
        wrapper = {
            "name": os.path.basename(src),
            "translation": list(pos),
            "rotation": yaw_quat(rot_deg),
            "scale": [scale, scale, scale],
            "children": [r + node_off for r in scene_roots],
        }
        out["nodes"].append(wrapper)
        out["scenes"][0]["nodes"].append(len(out["nodes"]) - 1)
        bin_base += len(bin_data) + pad

    if tint is not None:
        tint_materials(out, tint)
    out["buffers"][0]["byteLength"] = bin_base
    write_glb(out_path, out, b"".join(bin_chunks))


def copy_textures(kenney_root, kit, js):
    """Copie les textures externes référencées par un GLB à côté du GLB vendu."""
    for img in js.get("images", []):
        uri = img.get("uri")
        if not uri:
            continue
        src = os.path.join(kenney_root, "3d", kit, uri)
        dst = os.path.join(PROPS_DIR, kit, uri)
        if os.path.exists(src):
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copyfile(src, dst)
            print("  texture copiée", os.path.normpath(dst))


def cmd_vendor(kenney_root):
    for out_name, src_name, height in NATURE_SPEC:
        src = os.path.join(kenney_root, "3d", "nature", src_name)
        js, bin_data = read_glb(src)
        bin_data = normalize(js, bin_data, height)
        dst = os.path.join(PROPS_DIR, "nature", out_name)
        write_glb(dst, js, bin_data)
        copy_textures(kenney_root, "nature", js)
        print("vendored nature/%s <- %s (h=%.2f m)" % (out_name, src_name, height))


def cmd_compose(kenney_root):
    for out_name, tint, parts in RUIN_SPEC:
        src_parts = [
            (os.path.join(kenney_root, "3d", "castle", p[0]), tuple(p[1:4]), p[4], p[5])
            for p in parts
        ]
        dst = os.path.join(PROPS_DIR, out_name)
        compose_glb(dst, src_parts, tint=tint)
        js, _ = read_glb(src_parts[0][0])
        copy_textures(kenney_root, "castle", js)
        print("composed %s (%d pièces)" % (os.path.normpath(dst), len(parts)))


def cmd_inspect(path):
    js, bin_data = read_glb(path)
    mins = [math.inf] * 3
    maxs = [-math.inf] * 3
    verts = 0
    for idx in position_accessor_indices(js):
        acc = js["accessors"][idx]
        verts += acc["count"]
        for k in range(3):
            mins[k] = min(mins[k], acc["min"][k])
            maxs[k] = max(maxs[k], acc["max"][k])
    print("%s : %d octets bin, %d sommets, %d maillages, %d nœuds" % (
        path, len(bin_data), verts, len(js.get("meshes", [])), len(js.get("nodes", []))))
    print("  AABB min [%.2f %.2f %.2f] max [%.2f %.2f %.2f]" % (*mins, *maxs))
    print("  images:", [i.get("uri", "embedded") for i in js.get("images", [])])


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("vendor", "compose", "all"):
        p = sub.add_parser(name)
        p.add_argument("--kenney-root", default="/tmp/kenney",
                       help="racine d'un checkout du miroir https://github.com/shorepine/kenney")
    p = sub.add_parser("inspect")
    p.add_argument("glb")
    args = ap.parse_args()

    if args.cmd == "inspect":
        cmd_inspect(args.glb)
        return
    kenney_root = args.kenney_root
    if not os.path.isdir(os.path.join(kenney_root, "3d")):
        raise SystemExit(
            "kenney-root invalide (%s) : cloner d'abord "
            "git clone --depth 1 --filter=blob:none --sparse https://github.com/shorepine/kenney" % kenney_root
        )
    if args.cmd in ("vendor", "all"):
        cmd_vendor(kenney_root)
    if args.cmd in ("compose", "all"):
        cmd_compose(kenney_root)


if __name__ == "__main__":
    main()
