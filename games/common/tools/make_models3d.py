#!/usr/bin/env python3
# make_models3d.py - the 3D samples (CC0, made by code): games/common/
#   ship.glb    a low-poly ship: vertex colours, two nodes (the hull, a fin
#               turned and moved: the importer bakes node transforms)
#   crate.glb   a textured crate: a 32 x 32 PNG embedded in it (base colour texture)
#   crate.png   the same picture, for `mesh = { "cube", texture = "/assets/crate.png" }`
#   arm.glb     a skinned arm: two joints (upper at the origin, lower 1 m up), 2 m tall,
#               and a clip, "bend": the lower joint turns 90 degrees about z in 1 s
#   blob.glb    a cube with two morph targets, "puff" (its top 0.5 m up) and "squash"
#               (its sides 0.25 m out), and a clip, "breathe": puff 0 -> 1 -> 0 in 2 s
#   house.vox   MagicaVoxel: a house (16 x 12 x 15 voxels: walls, a door, windows, a roof)
#               and a tree beside it, turned 90 degrees (its own model, in the scene graph)
# glTF 2.0, binary (.glb), y up, meters. Run: python3 make_models3d.py (from anywhere).
import json, os, struct, zlib, math

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, ".."))

def png(w, h, px):                                 # px: rows of (r, g, b, a)
    raw = b"".join(b"\0" + bytes(c for p in row for c in p) for row in px)
    def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")

def crate_pixels():
    px = []
    for y in range(32):
        row = []
        for x in range(32):
            edge = x < 3 or y < 3 or x > 28 or y > 28
            diag = abs(x - y) < 2 or abs(x - (31 - y)) < 2
            plank = (y // 8) % 2
            if edge or diag: c = (110, 70, 35)
            else: c = (190, 140, 80) if plank else (170, 122, 66)
            if (x * 7 + y * 13) % 11 == 0 and not edge: c = tuple(max(0, v - 18) for v in c)
            row.append(c + (255,))
        px.append(row)
    return px

class Glb:
    def __init__(self):
        self.bin = bytearray(); self.views = []; self.acc = []
    def view(self, data, target=None):
        while len(self.bin) % 4: self.bin += b"\0"
        off = len(self.bin); self.bin += data
        v = {"buffer": 0, "byteOffset": off, "byteLength": len(data)}
        if target: v["target"] = target
        self.views.append(v); return len(self.views) - 1
    def floats(self, vals, n, kind):
        data = struct.pack("<%df" % len(vals), *vals)
        a = {"bufferView": self.view(data, 34962), "componentType": 5126, "count": len(vals) // n, "type": kind}
        if kind == "VEC3":
            xs, ys, zs = vals[0::3], vals[1::3], vals[2::3]
            a["min"] = [min(xs), min(ys), min(zs)]; a["max"] = [max(xs), max(ys), max(zs)]
        self.acc.append(a); return len(self.acc) - 1
    def indices(self, idx):
        data = struct.pack("<%dH" % len(idx), *idx)
        self.acc.append({"bufferView": self.view(data, 34963), "componentType": 5123, "count": len(idx), "type": "SCALAR"})
        return len(self.acc) - 1
    def write(self, path, doc):
        doc["asset"] = {"version": "2.0", "generator": "Replay make_models3d.py (CC0)"}
        doc["buffers"] = [{"byteLength": len(self.bin)}]
        doc["bufferViews"] = self.views; doc["accessors"] = self.acc
        js = json.dumps(doc, separators=(",", ":")).encode()
        while len(js) % 4: js += b" "
        b = bytes(self.bin)
        while len(b) % 4: b += b"\0"
        out = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(b))
        out += struct.pack("<II", len(js), 0x4E4F534A) + js + struct.pack("<II", len(b), 0x004E4942) + b
        open(path, "wb").write(out)

def flat(tris, outward=True):                      # tris: ((p0, p1, p2), colour): per-face normals; outward: each one
    pos, nrm, col, idx = [], [], [], []           # turned counter-clockwise seen from outside (away from the middle)
    pts = [p for t, _ in tris for p in t]
    mid = [sum(p[i] for p in pts) / len(pts) for i in range(3)]
    for (a, b, c), rgb in tris:
        u = [b[i] - a[i] for i in range(3)]; v = [c[i] - a[i] for i in range(3)]
        n = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]]
        ctr = [(a[i] + b[i] + c[i]) / 3 - mid[i] for i in range(3)]
        if outward and sum(n[i] * ctr[i] for i in range(3)) < 0:
            b, c = c, b; n = [-x for x in n]
        l = math.sqrt(sum(x * x for x in n)) or 1
        n = [x / l for x in n]
        for p in (a, b, c):
            idx.append(len(pos) // 3); pos += p; nrm += n; col += [rgb[0] / 255, rgb[1] / 255, rgb[2] / 255, 1]
    return pos, nrm, col, idx

def ship():
    g = Glb()
    nose, tail_l, tail_r, top, bot = (0, 0, -1.2), (-0.7, 0, 0.6), (0.7, 0, 0.6), (0, 0.5, 0.15), (0, -0.2, 0.4)
    blue, dark, white = (70, 140, 230), (40, 60, 110), (230, 235, 245)
    hull = [((nose, tail_l, top), blue), ((nose, top, tail_r), (90, 160, 240)), ((tail_l, tail_r, top), white),
            ((nose, bot, tail_l), dark), ((nose, tail_r, bot), dark), ((tail_l, bot, tail_r), (60, 70, 90))]
    fin = [(((0, 0, 0.2), (0, 0.55, 0.45), (0, 0, 0.55)), (240, 120, 60)), (((0, 0, 0.2), (0, 0, 0.55), (0, 0.55, 0.45)), (240, 120, 60))]
    meshes, nodes = [], []
    for name, tris in (("hull", hull), ("fin", fin)):
        pos, nrm, col, idx = flat(tris, outward=(name == "hull"))   # (the fin: both sides given)
        meshes.append({"name": name, "primitives": [{"attributes": {"POSITION": g.floats(pos, 3, "VEC3"), "NORMAL": g.floats(nrm, 3, "VEC3"),
                       "COLOR_0": g.floats(col, 4, "VEC4")}, "indices": g.indices(idx), "material": 0}]})
    nodes.append({"name": "hull", "mesh": 0, "children": [1]})
    nodes.append({"name": "fin", "mesh": 1, "translation": [0, 0.15, 0.05], "rotation": [0, 0, 0, 1]})
    g.write(os.path.join(OUT, "ship.glb"), {"scene": 0, "scenes": [{"nodes": [0]}], "nodes": nodes, "meshes": meshes,
            "materials": [{"name": "paint", "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0}}]})

def crate():
    g = Glb()
    F = [((.5, -.5, .5), (.5, -.5, -.5), (.5, .5, -.5), (.5, .5, .5), (1, 0, 0)), ((-.5, -.5, -.5), (-.5, -.5, .5), (-.5, .5, .5), (-.5, .5, -.5), (-1, 0, 0)),
         ((-.5, .5, .5), (.5, .5, .5), (.5, .5, -.5), (-.5, .5, -.5), (0, 1, 0)), ((-.5, -.5, -.5), (.5, -.5, -.5), (.5, -.5, .5), (-.5, -.5, .5), (0, -1, 0)),
         ((-.5, -.5, .5), (.5, -.5, .5), (.5, .5, .5), (-.5, .5, .5), (0, 0, 1)), ((.5, -.5, -.5), (-.5, -.5, -.5), (-.5, .5, -.5), (.5, .5, -.5), (0, 0, -1))]
    pos, nrm, uv, idx = [], [], [], []
    for f in F:
        b = len(pos) // 3
        for k, p in enumerate(f[:4]):
            pos += p; nrm += f[4]; uv += [(0, 1), (1, 1), (1, 0), (0, 0)][k]
        idx += [b, b + 1, b + 2, b, b + 2, b + 3]
    pic = png(32, 32, crate_pixels())
    open(os.path.join(OUT, "crate.png"), "wb").write(pic)
    img_view = g.view(pic)
    mesh = {"name": "crate", "primitives": [{"attributes": {"POSITION": g.floats(pos, 3, "VEC3"), "NORMAL": g.floats(nrm, 3, "VEC3"),
            "TEXCOORD_0": g.floats(uv, 2, "VEC2")}, "indices": g.indices(idx), "material": 0}]}
    g.write(os.path.join(OUT, "crate.glb"), {"scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"name": "crate", "mesh": 0}], "meshes": [mesh],
            "materials": [{"name": "wood", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0}}],
            "textures": [{"source": 0, "sampler": 0}], "samplers": [{"magFilter": 9728, "minFilter": 9728}],
            "images": [{"bufferView": img_view, "mimeType": "image/png"}]})

def arm():
    g = Glb()
    h = 0.12                                       # a square post, 0.24 m across: rings at y = 0, 0.5, 1, 1.5, 2
    corners = [(-h, -h), (h, -h), (h, h), (-h, h)]   # (x, z), counter-clockwise from above
    ys = [0, 0.5, 1, 1.5, 2]
    pos, nrm, col, jnt, wgt, idx = [], [], [], [], [], []
    def wj(y):                                     # its joints: upper below 1 m, lower above, both at 1 m
        if y < 1: return (0, 1, 0, 0), (1, 0, 0, 0)
        if y > 1: return (1, 0, 0, 0), (1, 0, 0, 0)
        return (0, 1, 0, 0), (0.5, 0.5, 0, 0)
    for side in range(4):                          # the sides: flat normals, 2 vertices a ring each
        (ax, az), (bx, bz) = corners[side], corners[(side + 1) % 4]
        nx, nz = (ax + bx) / 2, (az + bz) / 2
        l = math.hypot(nx, nz); nx, nz = nx / l, nz / l
        base = len(pos) // 3
        for y in ys:
            for (x, z) in ((ax, az), (bx, bz)):
                pos += [x, y, z]; nrm += [nx, 0, nz]
                c = (230, 160, 60) if y <= 1 else (70, 150, 230)
                col += [c[0] / 255, c[1] / 255, c[2] / 255, 1]
                j, w = wj(y); jnt += j; wgt += w
        for r in range(len(ys) - 1):
            a, b, c, d = base + r * 2, base + r * 2 + 1, base + r * 2 + 3, base + r * 2 + 2
            idx += [a, c, b, a, d, c]              # (counter-clockwise from outside)
    for y, up in ((0, False), (2, True)):          # the caps
        base = len(pos) // 3
        for (x, z) in corners:
            pos += [x, y, z]; nrm += [0, 1 if up else -1, 0]
            c = (230, 160, 60) if not up else (70, 150, 230)
            col += [c[0] / 255, c[1] / 255, c[2] / 255, 1]
            j, w = wj(y); jnt += j; wgt += w
        idx += ([base, base + 3, base + 2, base, base + 2, base + 1] if up else [base, base + 1, base + 2, base, base + 2, base + 3])
    jdata = bytes(jnt)
    jv = g.view(jdata, 34962)
    g.acc.append({"bufferView": jv, "componentType": 5121, "count": len(jnt) // 4, "type": "VEC4"})
    jacc = len(g.acc) - 1
    wacc = g.floats(wgt, 4, "VEC4")
    ibm = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1] + [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, -1, 0, 1]
    iv = g.view(struct.pack("<32f", *ibm))
    g.acc.append({"bufferView": iv, "componentType": 5126, "count": 2, "type": "MAT4"})
    iacc = len(g.acc) - 1
    tv = g.view(struct.pack("<2f", 0, 1))
    g.acc.append({"bufferView": tv, "componentType": 5126, "count": 2, "type": "SCALAR", "min": [0], "max": [1]})
    tacc = len(g.acc) - 1
    s45 = math.sin(math.pi / 4)
    rv = g.view(struct.pack("<8f", 0, 0, 0, 1, 0, 0, s45, s45))
    g.acc.append({"bufferView": rv, "componentType": 5126, "count": 2, "type": "VEC4"})
    racc = len(g.acc) - 1
    mesh = {"name": "arm", "primitives": [{"attributes": {"POSITION": g.floats(pos, 3, "VEC3"), "NORMAL": g.floats(nrm, 3, "VEC3"),
            "COLOR_0": g.floats(col, 4, "VEC4"), "JOINTS_0": jacc, "WEIGHTS_0": wacc}, "indices": g.indices(idx), "material": 0}]}
    nodes = [{"name": "upper", "children": [1]}, {"name": "lower", "translation": [0, 1, 0]}, {"name": "arm", "mesh": 0, "skin": 0}]
    g.write(os.path.join(OUT, "arm.glb"), {"scene": 0, "scenes": [{"nodes": [0, 2]}], "nodes": nodes, "meshes": [mesh],
            "skins": [{"joints": [0, 1], "inverseBindMatrices": iacc, "skeleton": 0}],
            "animations": [{"name": "bend", "channels": [{"sampler": 0, "target": {"node": 1, "path": "rotation"}}],
                            "samplers": [{"input": tacc, "output": racc, "interpolation": "LINEAR"}]}],
            "materials": [{"name": "paint", "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0}}]})

def blob():
    g = Glb()
    F = [((.5, -.5, .5), (.5, -.5, -.5), (.5, .5, -.5), (.5, .5, .5), (1, 0, 0)), ((-.5, -.5, -.5), (-.5, -.5, .5), (-.5, .5, .5), (-.5, .5, -.5), (-1, 0, 0)),
         ((-.5, .5, .5), (.5, .5, .5), (.5, .5, -.5), (-.5, .5, -.5), (0, 1, 0)), ((-.5, -.5, -.5), (.5, -.5, -.5), (.5, -.5, .5), (-.5, -.5, .5), (0, -1, 0)),
         ((-.5, -.5, .5), (.5, -.5, .5), (.5, .5, .5), (-.5, .5, .5), (0, 0, 1)), ((.5, -.5, -.5), (-.5, -.5, -.5), (-.5, .5, -.5), (.5, .5, -.5), (0, 0, -1))]
    pos, nrm, idx, puff, squash = [], [], [], [], []
    for f in F:
        b = len(pos) // 3
        for p in f[:4]:
            pos += p; nrm += f[4]
            puff += [0, 0.5 if p[1] > 0 else 0, 0]
            squash += [0.25 if p[0] > 0 else -0.25, 0, 0.25 if p[2] > 0 else -0.25]
        idx += [b, b + 1, b + 2, b, b + 2, b + 3]
    tacc = g.floats([0, 1, 2], 1, "SCALAR")
    g.acc[tacc]["min"] = [0]; g.acc[tacc]["max"] = [2]
    wacc = g.floats([0, 0, 1, 0, 0, 0], 1, "SCALAR")   # (a key: puff, squash)
    prim = {"attributes": {"POSITION": g.floats(pos, 3, "VEC3"), "NORMAL": g.floats(nrm, 3, "VEC3")}, "indices": g.indices(idx), "material": 0,
            "targets": [{"POSITION": g.floats(puff, 3, "VEC3")}, {"POSITION": g.floats(squash, 3, "VEC3")}]}
    mesh = {"name": "blob", "primitives": [prim], "weights": [0, 0], "extras": {"targetNames": ["puff", "squash"]}}
    g.write(os.path.join(OUT, "blob.glb"), {"scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"name": "blob", "mesh": 0}], "meshes": [mesh],
            "animations": [{"name": "breathe", "channels": [{"sampler": 0, "target": {"node": 0, "path": "weights"}}],
                            "samplers": [{"input": tacc, "output": wacc, "interpolation": "LINEAR"}]}],
            "materials": [{"name": "jelly", "pbrMetallicRoughness": {"baseColorFactor": [0.5, 0.85, 0.4, 1], "metallicFactor": 0}}]})

def vox_chunk(cid, content, children=b""):
    return cid + struct.pack("<II", len(content), len(children)) + content + children
def vox_str(t): t = t.encode(); return struct.pack("<I", len(t)) + t
def vox_dict(d): return struct.pack("<I", len(d)) + b"".join(vox_str(k) + vox_str(v) for k, v in d.items())

def house():
    P = {1: (200, 190, 170), 2: (150, 60, 50), 3: (110, 75, 45), 4: (120, 170, 220), 5: (90, 140, 60), 6: (100, 70, 40), 7: (70, 120, 50)}
    sx, sy, sz = 16, 12, 15
    vox = {}
    for z in range(9):                             # the walls: one voxel thick, a door, windows
        for x in range(sx):
            for y in range(sy):
                if x in (0, sx - 1) or y in (0, sy - 1):
                    door = y == 0 and 6 <= x <= 8 and z < 6
                    win = (y == 0 and (2 <= x <= 3 or 12 <= x <= 13) and 3 <= z <= 5) or (x in (0, sx - 1) and 4 <= y <= 7 and 3 <= z <= 5)
                    if door: vox[(x, y, z)] = 3 if z < 5 and x != 7 else 3
                    elif win: vox[(x, y, z)] = 4
                    else: vox[(x, y, z)] = 1
    for z in range(9, sz):                         # the roof: a ridge along x
        k = z - 9
        for x in range(sx):
            for y in range(k, sy - k):
                if y in (k, sy - 1 - k) or z == sz - 1: vox[(x, y, z)] = 2
                elif x in (0, sx - 1): vox[(x, y, z)] = 1
    for (x, y, z) in [(7, 0, 0), (7, 0, 1), (7, 0, 2), (7, 0, 3), (7, 0, 4), (7, 0, 5)]: vox.pop((x, y, z), None); vox[(x, y, z)] = 3
    tx, ty, tz = 5, 5, 10                          # the tree: a trunk, a crown
    tree = {}
    for z in range(5): tree[(2, 2, z)] = 6
    for z in range(4, 10):
        for x in range(tx):
            for y in range(ty):
                if (x - 2) ** 2 + (y - 2) ** 2 + (z - 6.5) ** 2 / 2 < 5.5: tree[(x, y, z)] = 7 if (x + y + z) % 3 else 5
    def model(size, vx):
        xyzi = struct.pack("<I", len(vx)) + b"".join(struct.pack("<BBBB", x, y, z, c) for (x, y, z), c in sorted(vx.items()))
        return vox_chunk(b"SIZE", struct.pack("<III", *size)) + vox_chunk(b"XYZI", xyzi)
    rgba = b"".join(struct.pack("<BBBB", *(P.get(i + 1, (0, 0, 0)) + (255,))) for i in range(256))
    # the scene: 0 trn -> 1 grp -> (2 trn -> 3 shp: house), (4 trn: x 14, turned -> 5 shp: tree)
    nodes = vox_chunk(b"nTRN", struct.pack("<i", 0) + vox_dict({}) + struct.pack("<iiii", 1, -1, -1, 1) + vox_dict({}))
    nodes += vox_chunk(b"nGRP", struct.pack("<i", 1) + vox_dict({}) + struct.pack("<iii", 2, 2, 4))
    nodes += vox_chunk(b"nTRN", struct.pack("<i", 2) + vox_dict({}) + struct.pack("<iiii", 3, -1, 0, 1) + vox_dict({"_t": "0 0 7"}))
    nodes += vox_chunk(b"nSHP", struct.pack("<i", 3) + vox_dict({}) + struct.pack("<ii", 1, 0) + vox_dict({}))
    nodes += vox_chunk(b"nTRN", struct.pack("<i", 4) + vox_dict({}) + struct.pack("<iiii", 5, -1, 0, 1) + vox_dict({"_t": "14 -2 5", "_r": "17"}))
    nodes += vox_chunk(b"nSHP", struct.pack("<i", 5) + vox_dict({}) + struct.pack("<ii", 1, 1) + vox_dict({}))
    children = model((sx, sy, sz), vox) + model((tx, ty, tz), tree) + nodes + vox_chunk(b"RGBA", rgba)
    data = b"VOX " + struct.pack("<I", 150) + vox_chunk(b"MAIN", b"", children)
    open(os.path.join(OUT, "house.vox"), "wb").write(data)

ship(); crate(); arm(); blob(); house()
print("wrote", os.path.join(OUT, "ship.glb"), os.path.join(OUT, "crate.glb"), os.path.join(OUT, "crate.png"), os.path.join(OUT, "arm.glb"), os.path.join(OUT, "blob.glb"), os.path.join(OUT, "house.vox"))
