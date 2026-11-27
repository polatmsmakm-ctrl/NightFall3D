#!/usr/bin/env python3
"""A pose sheet with no Godot: skins a rigged character GLB (assets/chars/*.glb) with frames of the
Mixamo clips in assets/anims the way character_rig.gd retargets them (rotations copied as they are,
only the hips' vertical bob kept) and splats it front and side, coloured by its texture.

    python3 tools/pose_sheet.py assets/chars/survivor9.glb /tmp/sheet.png [idle run crouchwalk ...]

Points, not triangles: it is for judging the rig (joints in the right place, nothing tearing or
dragging), not the look.
"""
import io
import json
import os
import struct
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def load(path):
    b = open(path, 'rb').read()
    n = struct.unpack('<I', b[12:16])[0]
    j = json.loads(b[20:20 + n])
    blob = b''
    if len(b) > 20 + n + 8:
        o = 20 + n
        bl = struct.unpack('<I', b[o:o + 4])[0]
        blob = b[o + 8:o + 8 + bl]
    return j, blob


def acc(j, blob, i):
    a = j['accessors'][i]
    v = j['bufferViews'][a['bufferView']]
    comp = {5126: np.float32, 5123: np.uint16, 5125: np.uint32, 5121: np.uint8}[a['componentType']]
    k = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}[a['type']]
    off = v.get('byteOffset', 0) + a.get('byteOffset', 0)
    sz = np.dtype(comp).itemsize
    st = v.get('byteStride', 0)
    if st and st != k * sz:
        raw = np.frombuffer(blob, np.uint8, a['count'] * st, off).reshape(-1, st)[:, :k * sz]
        out = raw.copy().view(comp).reshape(-1, k)
    else:
        out = np.frombuffer(blob, comp, a['count'] * k, off).reshape(-1, k)
    if a.get('normalized') and comp != np.float32:
        out = out.astype(np.float32) / np.iinfo(comp).max
    return out


def quat(q):
    x, y, z, w = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def trs(n):
    M = np.eye(4)
    if 'matrix' in n:
        return np.array(n['matrix']).reshape(4, 4).T
    M[:3, :3] = quat(n.get('rotation', [0, 0, 0, 1])) * np.array(n.get('scale', [1, 1, 1]))
    M[:3, 3] = n.get('translation', [0, 0, 0])
    return M


def bone(name):
    return name.split(':')[-1].replace('mixamorig_', '')


def clip(name, frac):
    """{bone: (rotation quat, translation or None)} at `frac` of the clip."""
    p = os.path.join(ROOT, 'assets', 'anims', name + '.glb')
    if not os.path.exists(p):
        return {}, None
    j, blob = load(p)
    out = {}
    hips_rest = None
    for n in j['nodes']:
        if bone(n.get('name', '')) == 'Hips':
            hips_rest = np.array(n.get('translation', [0, 0, 0]), float)
    an = j['animations'][0]
    for ch in an['channels']:
        s = an['samplers'][ch['sampler']]
        t = acc(j, blob, s['input'])[:, 0]
        v = acc(j, blob, s['output'])
        k = min(int(frac * (len(t) - 1)), len(t) - 1)
        b = bone(j['nodes'][ch['target']['node']].get('name', ''))
        r, tr = out.get(b, (None, None))
        if ch['target']['path'] == 'rotation':
            r = v[k]
        elif ch['target']['path'] == 'translation':
            tr = v[k]
        out[b] = (r, tr)
    return out, hips_rest


def skin(path, anim, frac):
    j, blob = load(path)
    prim = j['meshes'][0]['primitives'][0]
    P = acc(j, blob, prim['attributes']['POSITION']).astype(np.float64)
    UV = acc(j, blob, prim['attributes']['TEXCOORD_0'])
    J = acc(j, blob, prim['attributes']['JOINTS_0']).astype(int)
    W = acc(j, blob, prim['attributes']['WEIGHTS_0']).astype(np.float64)
    sk = j['skins'][0]
    ibm = acc(j, blob, sk['inverseBindMatrices']).reshape(-1, 4, 4).transpose(0, 2, 1)
    pose, hips_anim = clip(anim, frac) if anim else ({}, None)
    parent = {}
    for i, n in enumerate(j['nodes']):
        for c in n.get('children', []):
            parent[c] = i
    glob = {}

    def g(i):
        if i in glob:
            return glob[i]
        n = j['nodes'][i]
        M = trs(n)
        b = bone(n.get('name', ''))
        if b in pose:
            r, tr = pose[b]
            if r is not None:
                M[:3, :3] = quat(r) * np.array(n.get('scale', [1, 1, 1]))
            if b == 'Hips' and tr is not None and hips_anim is not None and np.linalg.norm(hips_anim) > 1e-4:
                rest = np.array(n.get('translation', [0, 0, 0]), float)
                ratio = np.linalg.norm(rest) / np.linalg.norm(hips_anim)
                M[:3, 3] = rest + np.array([0, 0, (tr[2] - hips_anim[2]) * ratio])
        glob[i] = (g(parent[i]) @ M) if i in parent else M
        return glob[i]

    mats = np.array([g(jn) @ ibm[k] for k, jn in enumerate(sk['joints'])])
    Ph = np.hstack([P, np.ones((len(P), 1))])
    out = np.zeros((len(P), 3))
    for c in range(4):
        out += W[:, c:c + 1] * np.einsum('nij,nj->ni', mats[J[:, c]], Ph)[:, :3]
    # the mesh node's own place (the armature root carries the cast's turn and scale)
    body = next(i for i, n in enumerate(j['nodes']) if 'mesh' in n)
    root = body
    while root in parent:
        root = parent[root]
    # skinned meshes ignore their node transform; the joints already carry the armature's
    tex = None
    mat = j['materials'][prim['material']] if 'material' in prim else {}
    bc = mat.get('pbrMetallicRoughness', {}).get('baseColorTexture')
    if bc is not None:
        im = j['images'][j['textures'][bc['index']]['source']]
        if 'bufferView' in im:
            v = j['bufferViews'][im['bufferView']]
            o = v.get('byteOffset', 0)
            tex = np.asarray(Image.open(io.BytesIO(blob[o:o + v['byteLength']])).convert('RGB'))
        else:
            tex = np.asarray(Image.open(os.path.join(os.path.dirname(path), im['uri'])).convert('RGB'))
    if tex is not None:
        u = (UV[:, 0] % 1 * (tex.shape[1] - 1)).astype(int)
        w = (UV[:, 1] % 1 * (tex.shape[0] - 1)).astype(int)
        C = tex[w, u]
    else:
        C = np.full((len(P), 3), 200, np.uint8)
    # densify: points on the triangles too, or a 30k mesh is a cloud of dots
    F = acc(j, blob, prim['indices'])[:, 0].reshape(-1, 3)
    pts, cols = [out], [C]
    rng = np.random.default_rng(1)
    for _ in range(6):
        b = rng.dirichlet([1, 1, 1], len(F))
        pts.append(np.einsum('nk,nkd->nd', b, out[F]))
        cols.append(C[F[:, 0]])
    return np.vstack(pts), np.vstack(cols)


def splat(P, C, h, d, flip, W=300, H=2.4):
    S = W / 1.6
    img = np.full((int(H * S), W, 3), 28, np.uint8)
    x = (W / 2 + P[:, h] * flip * S).astype(int)
    y = (img.shape[0] - 1 - P[:, 1] * S).astype(int)
    ok = (x >= 0) & (x < W) & (y >= 0) & (y < img.shape[0])
    o = np.argsort(P[ok, d] * (1 if h == 0 else -flip))
    img[y[ok][o], x[ok][o]] = C[ok][o]
    return img


def main():
    src, dst = sys.argv[1], sys.argv[2]
    anims = sys.argv[3:] or ['', 'idle', 'run', 'crouchwalk', 'attack', 'carry', 'drive']
    cols = []
    for a in anims:
        frac = 0.35
        if '@' in a:                       # name@0.8: that fraction of the clip
            a, frac = a.split('@')[0], float(a.split('@')[1])
        P, C = skin(src, a, frac)
        P = P - np.array([np.median(P[:, 0]), 0, np.median(P[:, 2])])
        P[:, 1] -= P[:, 1].min()
        im = np.vstack([splat(P, C, 0, 2, 1), splat(P, C, 2, 0, -1)])
        im = Image.fromarray(im)
        ImageDraw.Draw(im).text((4, 4), (a or 'bind') + ('' if abs(frac - 0.35) < 1e-6 else ' @%.2f' % frac), fill=(255, 255, 0))
        cols.append(np.asarray(im))
    Image.fromarray(np.hstack(cols)).save(dst)
    print(dst)


if __name__ == '__main__':
    main()
