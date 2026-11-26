#!/usr/bin/env python3
"""Close-up of a character's face with no Godot: rasterises the head of a GLB (a rigged character in
its bind pose, or the raw sculpt) front on, textured and lit by its own geometry, so a rig's face
can be judged against the sculpt it was made from.

  python3 tools/face_shot.py OUT.png MODEL.glb [MODEL2.glb ...]   one column per model
      a model may be given as path@yaw (degrees about the vertical, for a sculpt that faces
      another way) — each column has three rows: colour, colour lit by the mesh, the bare mesh.
"""
import io
import json
import os
import struct
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pose_sheet as ps  # noqa: E402

PX = 640        # image size
HEAD = 0.34     # metres of the top of the body shown


def _tex(j, blob, path, prim):
    mat = j['materials'][prim['material']] if 'material' in prim else {}
    bc = mat.get('pbrMetallicRoughness', {}).get('baseColorTexture')
    if bc is None:
        return None
    im = j['images'][j['textures'][bc['index']]['source']]
    if 'bufferView' in im:
        v = j['bufferViews'][im['bufferView']]
        o = v.get('byteOffset', 0)
        return np.asarray(Image.open(io.BytesIO(blob[o:o + v['byteLength']])).convert('RGB'))
    return np.asarray(Image.open(os.path.join(os.path.dirname(path), im['uri'])).convert('RGB'))


def _world(j):
    parent = {}
    for i, n in enumerate(j['nodes']):
        for c in n.get('children', []):
            parent[c] = i
    memo = {}

    def g(i):
        if i not in memo:
            M = ps.trs(j['nodes'][i])
            memo[i] = (g(parent[i]) @ M) if i in parent else M
        return memo[i]
    return g


def load(path):
    """Every primitive as (positions in metres, y up, faces, uv, texture)."""
    j, blob = ps.load(path)
    g = _world(j)
    out = []
    for ni, n in enumerate(j['nodes']):
        if 'mesh' not in n:
            continue
        for prim in j['meshes'][n['mesh']]['primitives']:
            a = prim['attributes']
            P = ps.acc(j, blob, a['POSITION']).astype(np.float64)
            F = ps.acc(j, blob, prim['indices'])[:, 0].reshape(-1, 3) if 'indices' in prim else np.arange(len(P)).reshape(-1, 3)
            UV = ps.acc(j, blob, a['TEXCOORD_0']).astype(np.float64) if 'TEXCOORD_0' in a else np.zeros((len(P), 2))
            if 'skin' in n and 'JOINTS_0' in a:
                sk = j['skins'][n['skin']]
                ibm = ps.acc(j, blob, sk['inverseBindMatrices']).reshape(-1, 4, 4).transpose(0, 2, 1)
                J = ps.acc(j, blob, a['JOINTS_0']).astype(int)
                W = ps.acc(j, blob, a['WEIGHTS_0']).astype(np.float64)
                mats = np.array([g(jn) @ ibm[k] for k, jn in enumerate(sk['joints'])])
                Ph = np.hstack([P, np.ones((len(P), 1))])
                Q = np.zeros((len(P), 3))
                for c in range(4):
                    Q += W[:, c:c + 1] * np.einsum('nij,nj->ni', mats[J[:, c]], Ph)[:, :3]
                P = Q
            else:
                M = g(ni)
                P = (np.hstack([P, np.ones((len(P), 1))]) @ M.T)[:, :3]
            out.append((P, F, UV, _tex(j, blob, path, prim)))
    return out


def render(path, yaw=0.0):
    prims = load(path)
    allp = np.vstack([p[0] for p in prims])
    lo, hi = allp.min(0), allp.max(0)
    h = hi[1] - lo[1]
    s = 1.0
    if h > 3.0 or h < 1.0:  # a sculpt in its own units: bring it to 1.75 m
        s = 1.75 / h
    c = np.array([(lo[0] + hi[0]) / 2, lo[1], (lo[2] + hi[2]) / 2])
    cy, sy = np.cos(np.radians(yaw)), np.sin(np.radians(yaw))
    R = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    top = h * s
    col = np.full((PX, PX, 3), 24, np.float64)
    lit = col.copy()
    bare = col.copy()
    zb = np.full((PX, PX), -1e9)
    L = np.array([-0.35, 0.45, 0.82]); L /= np.linalg.norm(L)
    # the head: the top HEAD metres, centred on its own middle
    for P, F, UV, tex in prims:
        Q = ((P - c) * s) @ R.T
        keep = np.all(Q[F][:, :, 1] > top - HEAD, axis=1)
        if not keep.any():
            continue
        Fh = F[keep]
        allq = Q
        # centre x on the head
        hx = np.median(Q[np.unique(Fh), 0])
        scale = PX / HEAD
        X = (allq[:, 0] - hx) * scale + PX / 2
        Y = (top - allq[:, 1]) * scale
        Z = allq[:, 2]
        tri = np.stack([X[Fh], Y[Fh]], -1)
        e1 = Q[Fh[:, 1]] - Q[Fh[:, 0]]
        e2 = Q[Fh[:, 2]] - Q[Fh[:, 0]]
        nrm = np.cross(e1, e2)
        nrm /= np.linalg.norm(nrm, axis=1, keepdims=True) + 1e-12
        shade = 0.25 + 0.75 * np.clip(np.abs(nrm @ L), 0, 1)
        x0 = np.clip(np.floor(tri[:, :, 0].min(1)).astype(int), 0, PX - 1)
        x1 = np.clip(np.ceil(tri[:, :, 0].max(1)).astype(int), 0, PX - 1)
        y0 = np.clip(np.floor(tri[:, :, 1].min(1)).astype(int), 0, PX - 1)
        y1 = np.clip(np.ceil(tri[:, :, 1].max(1)).astype(int), 0, PX - 1)
        th, tw = (tex.shape[0], tex.shape[1]) if tex is not None else (1, 1)
        for k in range(len(Fh)):
            if x1[k] < x0[k] or y1[k] < y0[k]:
                continue
            a, b, d = tri[k]
            xs, ys = np.meshgrid(np.arange(x0[k], x1[k] + 1) + 0.5, np.arange(y0[k], y1[k] + 1) + 0.5)
            den = (b[1] - d[1]) * (a[0] - d[0]) + (d[0] - b[0]) * (a[1] - d[1])
            if abs(den) < 1e-9:
                xs = np.array([[(a[0] + b[0] + d[0]) / 3]]); ys = np.array([[(a[1] + b[1] + d[1]) / 3]])
                w0 = np.full((1, 1), 1 / 3); w1 = w0.copy()
            else:
                w0 = ((b[1] - d[1]) * (xs - d[0]) + (d[0] - b[0]) * (ys - d[1])) / den
                w1 = ((d[1] - a[1]) * (xs - d[0]) + (a[0] - d[0]) * (ys - d[1])) / den
            w2 = 1 - w0 - w1
            m = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
            if not m.any():
                # a triangle smaller than a pixel: its centre
                xs = np.array([[(a[0] + b[0] + d[0]) / 3]]); ys = np.array([[(a[1] + b[1] + d[1]) / 3]])
                w0 = np.full((1, 1), 1 / 3); w1 = w0.copy(); w2 = w0.copy(); m = np.ones((1, 1), bool)
            px = np.clip(xs[m].astype(int), 0, PX - 1); py = np.clip(ys[m].astype(int), 0, PX - 1)
            f = Fh[k]
            z = w0[m] * Z[f[0]] + w1[m] * Z[f[1]] + w2[m] * Z[f[2]]
            front = z > zb[py, px]
            if not front.any():
                continue
            px, py, z = px[front], py[front], z[front]
            zb[py, px] = z
            if tex is not None:
                u = w0[m][front] * UV[f[0], 0] + w1[m][front] * UV[f[1], 0] + w2[m][front] * UV[f[2], 0]
                v = w0[m][front] * UV[f[0], 1] + w1[m][front] * UV[f[1], 1] + w2[m][front] * UV[f[2], 1]
                cc = tex[np.clip((v % 1 * th).astype(int), 0, th - 1), np.clip((u % 1 * tw).astype(int), 0, tw - 1)]
            else:
                cc = np.full((len(px), 3), 190.0)
            col[py, px] = cc
            lit[py, px] = cc * shade[k]
            bare[py, px] = 200 * shade[k]
    tris = sum(len(p[1]) for p in prims)
    return np.vstack([col, lit, bare]).clip(0, 255).astype(np.uint8), tris


def main():
    out = sys.argv[1]
    cols = []
    for arg in sys.argv[2:]:
        path, _, yaw = arg.partition('@')
        im, tris = render(path, float(yaw or 0))
        im = Image.fromarray(im)
        ImageDraw.Draw(im).text((6, 6), '%s  %dk tris' % (os.path.basename(path), tris // 1000), fill=(255, 255, 0))
        cols.append(np.asarray(im))
        print(path, tris, flush=True)
    Image.fromarray(np.hstack(cols)).save(out)
    print(out)


if __name__ == '__main__':
    main()
