"""Convertit un .gltf (tampon embarqué ou .bin voisin) en .glb compact, en ne gardant que
certaines animations et en reconstruisant le tampon binaire (données orphelines retirées)."""
import base64, json, os, struct, sys
import numpy as np

def load(path):
    j = json.load(open(path))
    bufs = []
    for b in j["buffers"]:
        uri = b.get("uri", "")
        if uri.startswith("data:"):
            bufs.append(base64.b64decode(uri.split(",", 1)[1]))
        else:
            bufs.append(open(os.path.join(os.path.dirname(path), uri), "rb").read())
    return j, bufs

def _read(j, bufs, i):
    a = j["accessors"][i]; v = j["bufferViews"][a["bufferView"]]
    n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
    assert a["componentType"] == 5126
    stride = v.get("byteStride", 4 * n)
    data = bufs[v.get("buffer", 0)]
    start = v.get("byteOffset", 0) + a.get("byteOffset", 0)
    raw = np.frombuffer(bytes(data), dtype=np.uint8)
    rows = [np.frombuffer(raw[start + k * stride: start + k * stride + 4 * n].tobytes(), dtype="<f4") for k in range(a["count"])]
    return np.array(rows, dtype=np.float32).reshape(a["count"], n)

def _simplify(t, v, eps, is_quat):
    """Garde les clés nécessaires pour que l'interpolation linéaire reste à moins de eps."""
    keep = [0]
    i = 0
    n = len(t)
    while i < n - 1:
        j = i + 2
        while j < n:
            seg_t = (t[i + 1:j] - t[i]) / max(t[j] - t[i], 1e-9)
            interp = v[i] + (v[j] - v[i]) * seg_t[:, None]
            if is_quat:
                interp /= np.linalg.norm(interp, axis=1, keepdims=True)
                err = 1.0 - np.abs(np.sum(interp * v[i + 1:j], axis=1))
            else:
                err = np.max(np.abs(interp - v[i + 1:j]), axis=1)
            if np.max(err) > eps:
                break
            j += 1
        i = j - 1
        keep.append(i)
    return sorted(set(keep))

def _reduce_keys(j, bufs):
    extra = bytearray()
    base = len(bufs[0])
    for a in j.get("animations", []):
        for ch, s in zip(a["channels"], [a["samplers"][c["sampler"]] for c in a["channels"]]):
            if s.get("interpolation", "LINEAR") != "LINEAR":
                continue
            t = _read(j, bufs, s["input"])[:, 0]
            v = _read(j, bufs, s["output"])
            if len(t) < 3:
                continue
            path = ch["target"]["path"]
            is_quat = path == "rotation"
            eps = 2e-6 if is_quat else 2e-4
            keep = _simplify(t, v, eps, is_quat)
            if len(keep) == len(t):
                continue
            for acc_i, arr in ((s["input"], t[keep].reshape(-1, 1)), (s["output"], v[keep])):
                old = j["accessors"][acc_i]
                while (base + len(extra)) % 4: extra.append(0)
                off = base + len(extra)
                extra += arr.astype("<f4").tobytes()
                j["bufferViews"].append({"buffer": 0, "byteOffset": off, "byteLength": arr.size * 4})
                new = dict(old); new["bufferView"] = len(j["bufferViews"]) - 1; new["byteOffset"] = 0; new["count"] = len(keep)
                if acc_i == s["input"]:
                    new["min"] = [float(arr.min())]; new["max"] = [float(arr.max())]
                j["accessors"].append(new)
                if acc_i == s["input"]:
                    s["input"] = len(j["accessors"]) - 1
                else:
                    s["output"] = len(j["accessors"]) - 1
    bufs[0] = bytes(bufs[0]) + bytes(extra)

def convert(src, dst, keep):
    j, bufs = load(src)
    if keep is not None:
        anims = []
        for a in j.get("animations", []):
            name = a.get("name", "")
            short = name.split("|")[-1]
            if short in keep:
                a["name"] = short
                anims.append(a)
        j["animations"] = anims
    _reduce_keys(j, bufs)
    used = set()
    def acc(i):
        if i is not None: used.add(i)
    for m in j["meshes"]:
        for p in m["primitives"]:
            for v in p["attributes"].values(): acc(v)
            acc(p.get("indices"))
            for t in p.get("targets", []):
                for v in t.values(): acc(v)
    for s in j.get("skins", []):
        acc(s.get("inverseBindMatrices"))
    for a in j.get("animations", []):
        for s in a["samplers"]:
            acc(s["input"]); acc(s["output"])
    # Nouveau tampon : une vue par accesseur utilisé, alignée sur 4 octets.
    out = bytearray(); views = []; remap = {}
    old_views = j["bufferViews"]
    for i in sorted(used):
        a = j["accessors"][i]
        v = old_views[a["bufferView"]]
        data = bufs[v.get("buffer", 0)]
        comp = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}[a["componentType"]]
        ncomp = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16}[a["type"]]
        elem = comp * ncomp
        stride = v.get("byteStride", elem)
        start = v.get("byteOffset", 0) + a.get("byteOffset", 0)
        chunk = bytearray()
        for k in range(a["count"]):
            chunk += data[start + k * stride: start + k * stride + elem]
        while len(out) % 4: out.append(0)
        nv = {"buffer": 0, "byteOffset": len(out), "byteLength": len(chunk)}
        if "target" in v: nv["target"] = v["target"]
        out += chunk
        remap[i] = len(views)
        views.append(nv)
        a["bufferView"] = remap[i]
        a["byteOffset"] = 0
    accessors = [j["accessors"][i] for i in sorted(used)]
    idx = {old: new for new, old in enumerate(sorted(used))}
    for m in j["meshes"]:
        for p in m["primitives"]:
            p["attributes"] = {k: idx[v] for k, v in p["attributes"].items()}
            if "indices" in p: p["indices"] = idx[p["indices"]]
            if "targets" in p: p["targets"] = [{k: idx[v] for k, v in t.items()} for t in p["targets"]]
    for s in j.get("skins", []):
        if "inverseBindMatrices" in s: s["inverseBindMatrices"] = idx[s["inverseBindMatrices"]]
    for a in j.get("animations", []):
        for s in a["samplers"]:
            s["input"] = idx[s["input"]]; s["output"] = idx[s["output"]]
    if j.get("images"):
        raise SystemExit("images non gérées : " + src)
    j["accessors"] = accessors
    j["bufferViews"] = views
    j["buffers"] = [{"byteLength": len(out)}]
    j.setdefault("asset", {})["copyright"] = "Quaternius (quaternius.com) - CC0 1.0"
    js = json.dumps(j, separators=(",", ":")).encode()
    while len(js) % 4: js += b" "
    while len(out) % 4: out.append(0)
    total = 12 + 8 + len(js) + 8 + len(out)
    with open(dst, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A)); f.write(js)
        f.write(struct.pack("<II", len(out), 0x004E4942)); f.write(out)

if __name__ == "__main__":
    src, dst = sys.argv[1], sys.argv[2]
    keep = set(sys.argv[3].split(",")) if len(sys.argv) > 3 else None
    convert(src, dst, keep)
    print(dst, os.path.getsize(dst))
