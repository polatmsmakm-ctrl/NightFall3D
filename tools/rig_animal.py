#!/usr/bin/env python3
"""A four-legged animal: a baked static GLB (tools/prop_bake.py: metres, nose toward +z, standing on
y = 0) given a skeleton and skin weights, written back as a skinned GLB Godot animates in code
(scripts/animal.gd).

    python3 tools/rig_animal.py baked.glb joints.json out.glb

joints.json holds where the joints are, in metres in the baked model's space (read off the grid
pictures of `--sheet`): hips, spine1, spine2, chest, neck1, neck2, head, jaw, mouth (the lip corner the
jaw closes to), nose, tail1..tailN (from the root out), and for each leg fl / fr / bl / br the four
points from the body down: top, mid, low, paw (the toe tip is added below the paw).

    python3 tools/rig_animal.py baked.glb --sheet out.png    pictures with a 5 cm grid to read them

Every joint's rest rotation is the identity (its axes are the model's: +z forward, +y up, +x the
animal's left), so the game turns bones about plain axes. Weights: each vertex belongs to one region
(a leg, the tail, the head, the jaw, the body) decided from where it is, then takes the nearest bones
of that region by distance to their segments (inverse fourth power, four at most) and is smoothed
across the welded surface so seams do not open and joints bend softly.
"""
import json
import struct
import sys

import numpy as np
from scipy.spatial import cKDTree

LEGS = ['fl', 'fr', 'bl', 'br']


def read_glb(path):
    b = open(path, 'rb').read()
    n = struct.unpack('<I', b[12:16])[0]
    j = json.loads(b[20:20 + n])
    off = 20 + n
    bl = struct.unpack('<I', b[off:off + 4])[0]
    blob = bytearray(b[off + 8:off + 8 + bl])
    return j, blob


def acc(j, blob, i):
    a = j['accessors'][i]
    v = j['bufferViews'][a['bufferView']]
    ct = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}[a['componentType']]
    k = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}[a['type']]
    o = v.get('byteOffset', 0) + a.get('byteOffset', 0)
    return np.frombuffer(bytes(blob[o:o + a['count'] * k * np.dtype(ct).itemsize]), dtype=ct).reshape(a['count'], k)


def write_glb(path, j, blob):
    while len(blob) % 4: blob.append(0)
    j['buffers'] = [{'byteLength': len(blob)}]
    js = json.dumps(j, separators=(',', ':')).encode()
    while len(js) % 4: js += b' '
    out = struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob))
    out += struct.pack('<II', len(js), 0x4E4F534A) + js + struct.pack('<II', len(blob), 0x004E4942) + bytes(blob)
    open(path, 'wb').write(out)


def add_acc(j, blob, arr, ctype, typ, target=None, minmax=False):
    while len(blob) % 4: blob.append(0)
    raw = arr.tobytes()
    view = {'buffer': 0, 'byteOffset': len(blob), 'byteLength': len(raw)}
    if target: view['target'] = target
    blob.extend(raw)
    j['bufferViews'].append(view)
    a = {'bufferView': len(j['bufferViews']) - 1, 'componentType': ctype, 'count': int(arr.shape[0]), 'type': typ}
    if minmax:
        a['min'] = arr.min(0).tolist(); a['max'] = arr.max(0).tolist()
    j['accessors'].append(a)
    return len(j['accessors']) - 1


def mesh_of(j, blob):
    """The baked prop's meshes merged into one list of positions (world space of the GLB) per primitive."""
    def world(i, parent=np.eye(4)):
        nd = j['nodes'][i]
        M = np.eye(4)
        if 'translation' in nd: M[:3, 3] = nd['translation']
        if 'scale' in nd: M = M @ np.diag(list(nd['scale']) + [1])
        return parent @ M
    out = []
    def walk(i, parent):
        M = world(i, parent)
        nd = j['nodes'][i]
        if 'mesh' in nd: out.append((i, M))
        for c in nd.get('children', []): walk(c, M)
    for r in j['scenes'][j.get('scene', 0)]['nodes']: walk(r, np.eye(4))
    return out


def skeleton(J):
    """Bones as (name, parent, head position): the order the GLB writes them in."""
    bones = [('root', None, np.array([J['hips'][0], 0.0, J['hips'][2]]))]
    def add(n, p, at): bones.append((n, p, np.array(at, float)))
    add('hips', 'root', J['hips'])
    add('spine1', 'hips', J['spine1'])
    add('spine2', 'spine1', J['spine2'])
    add('chest', 'spine2', J['chest'])
    add('neck1', 'chest', J['neck1'])
    add('neck2', 'neck1', J['neck2'])
    add('head', 'neck2', J['head'])
    add('jaw', 'head', J['jaw'])
    tails = sorted([k for k in J if k.startswith('tail')], key=lambda k: int(k[4:]))
    prev = 'hips'
    for t in tails:
        add(t, prev, J[t]); prev = t
    for leg in LEGS:
        L = J[leg]
        par = 'chest' if leg[0] == 'f' else 'hips'
        add(leg + '_top', par, L['top'])
        add(leg + '_mid', leg + '_top', L['mid'])
        add(leg + '_low', leg + '_mid', L['low'])
        add(leg + '_paw', leg + '_low', L['paw'])
    return bones, tails


def rest_yaw(J):
    """The face's own direction (the head may be turned in the sculpt): the head and the jaw rest
    turned that way, so a nod and the mouth opening happen about the right axis."""
    d = np.array(J['nose'], float) - np.array(J['head'], float)
    head = float(np.arctan2(d[0], d[2]))
    m = np.array(J['mouth'], float) - np.array(J['jaw'], float)
    jaw = float(np.arctan2(m[0], m[2]))
    return {'head': head, 'jaw': jaw}


def quat_y(a):
    return [0.0, float(np.sin(a / 2)), 0.0, float(np.cos(a / 2))]


def seg_dist(P, a, b):
    ab = b - a
    t = np.clip(((P - a) @ ab) / max(ab @ ab, 1e-12), 0, 1)
    return np.linalg.norm(P - (a + t[:, None] * ab), axis=1)


def weights(P, J, bones, tails, adj):
    names = [b[0] for b in bones]
    pos = {b[0]: b[2] for b in bones}
    child_end = {}
    for n, p, at in bones: # each bone's segment runs from its head to its (first) child's head
        if p is not None and p not in child_end: child_end[p] = at
    def end(n):
        if n in child_end: return child_end[n]
        if n == 'jaw': return np.array(J['mouth'], float)
        if n == 'head': return np.array(J['nose'], float)
        if n.endswith('_paw'): return pos[n] + np.array([0, -0.01, 0.04])
        if n.startswith('tail'): return pos[n] + (pos[n] - pos[names[names.index(n) - 1]]) * 0.8
        return pos[n]
    segs = {n: (pos[n], end(n)) for n in names if n != 'root'}
    N = len(P)
    D = {n: seg_dist(P, *segs[n]) for n in segs}
    # ---- regions ----
    hip_z, chest_z = J['hips'][2], J['chest'][2]
    region = np.full(N, 'body', dtype=object)
    # legs: under the body line between their top and the ground, nearest leg chain on that side
    leg_d = {}
    for leg in LEGS:
        ch = [leg + s for s in ['_top', '_mid', '_low', '_paw']]
        leg_d[leg] = np.min([D[c] for c in ch], axis=0)
    best_leg = np.array(LEGS)[np.argmin(np.stack([leg_d[l] for l in LEGS]), axis=0)]
    best_val = np.min(np.stack([leg_d[l] for l in LEGS]), axis=0)
    body_d = np.min([D[n] for n in ['hips', 'spine1', 'spine2', 'chest']], axis=0)
    # the body's centre line (it may stand a little diagonal): left / right is taken from it
    hz, hx = J['hips'][2], J['hips'][0]
    cz, cx = J['chest'][2], J['chest'][0]
    def centre_x(z): return hx + (cx - hx) * np.clip((z - hz) / (cz - hz), -0.5, 1.5)
    vside = np.sign(P[:, 0] - centre_x(P[:, 2]))
    # tail first: behind the hips and nearer the tail chain than the hips or any leg
    tail_d = np.min([D[t] for t in tails], axis=0) if tails else np.full(N, 9.0)
    if tails:
        m = (P[:, 2] < hip_z + 0.02) & (tail_d < np.minimum(body_d, best_val) * 0.85)
        region[m] = 'tail'
    for leg in LEGS:
        top_y = J[leg]['top'][1]
        pw = J[leg]['paw']
        side = np.sign(pw[0] - centre_x(np.array(pw[2])))
        m = (best_leg == leg) & (P[:, 1] < top_y - 0.02) & (best_val < body_d * 0.9) & (region == 'body')
        m &= (vside == side) | (np.abs(P[:, 0] - centre_x(P[:, 2])) < 0.008)
        m &= best_val < tail_d
        region[m] = leg
    # head and jaw: past the top of the neck, nearer the head than the neck
    head_d = np.minimum(D['head'], D['jaw'])
    neck_d = np.minimum(D['neck1'], D['neck2'])
    hc = np.array(J['head'], float)
    r_head = 1.5 * np.linalg.norm(np.array(J['nose'], float) - hc) # the skull, the ears, the cheeks
    m = (head_d < neck_d * 0.9) | ((np.linalg.norm(P - hc, axis=1) < r_head) & (P[:, 1] > J['neck2'][1] + 0.01))
    un = hc - np.array(J['neck1'], float)
    un /= np.linalg.norm(un)
    m &= (P - np.array(J['neck2'], float)) @ un > -0.02 * np.linalg.norm(un) # past the top of the neck, whichever way it points
    region[m & (region == 'body')] = 'head'
    # the lower jaw: under the line from the hinge to the mouth corner, in front of the hinge
    jw, mo = np.array(J['jaw'], float), np.array(J['mouth'], float)
    jd = mo - jw
    Ln = np.linalg.norm(jd)
    u = jd / Ln
    rel = P - jw
    along = rel @ u
    t = along / Ln
    perp = rel - along[:, None] * u
    lat = np.hypot(perp[:, 0], perp[:, 2])
    line_y = jw[1] + t * jd[1]
    m = (region == 'head') & (t > -0.15) & (t < 1.7) & (lat < 0.75 * Ln) & (P[:, 1] < line_y)
    region[m] = 'jaw'
    allowed = {
        'body': ['hips', 'spine1', 'spine2', 'chest', 'neck1', 'neck2'] + (tails[:1] if tails else []),
        'tail': ['hips'] + tails,
        'head': ['neck2', 'head'],
        'jaw': ['jaw', 'head'],
    }
    for leg in LEGS:
        allowed[leg] = [('chest' if leg[0] == 'f' else 'hips'), leg + '_top', leg + '_mid', leg + '_low', leg + '_paw']
    W = np.zeros((N, len(names)), np.float32)
    for reg, bl in allowed.items():
        m = region == reg
        if not m.any(): continue
        dd = np.stack([D[b][m] for b in bl], axis=1)
        w = 1.0 / np.maximum(dd, 0.004) ** 4
        # four at most
        cut = np.sort(w, axis=1)[:, -4][:, None] if w.shape[1] > 4 else 0
        w = np.where(w >= cut, w, 0)
        w /= w.sum(1, keepdims=True)
        idx = [names.index(b) for b in bl]
        W[np.ix_(np.where(m)[0], idx)] = w
    # smooth over the welded surface (a jaw or a leg edge softens instead of tearing)
    keep = (region == 'jaw') # the lips stay sharp: the mouth must open cleanly
    for it in range(4):
        S = np.zeros_like(W)
        cnt = np.zeros(N, np.float32)
        a, b = adj
        np.add.at(S, a, W[b]); np.add.at(cnt, a, 1)
        sm = (W + S) / (1 + cnt)[:, None]
        W = np.where(keep[:, None], W, 0.5 * W + 0.5 * sm)
    # four largest, normalised
    order = np.argsort(-W, axis=1)[:, :4]
    top = np.take_along_axis(W, order, 1)
    top /= np.maximum(top.sum(1, keepdims=True), 1e-9)
    return order.astype(np.uint8), top.astype(np.float32), region


def main():
    src = sys.argv[1]
    j, blob = read_glb(src)
    if sys.argv[2] == '--sheet':
        return sheet(j, blob, sys.argv[3])
    J = json.load(open(sys.argv[2]))
    out = sys.argv[3]
    bones, tails = skeleton(J)
    names = [b[0] for b in bones]
    meshes = mesh_of(j, blob)
    # positions of every vertex in the model's space, per primitive, and one weld over all of them
    prims = []
    allP = []
    for ni, M in meshes:
        for p in j['meshes'][j['nodes'][ni]['mesh']]['primitives']:
            P = acc(j, blob, p['attributes']['POSITION']).astype(np.float64)
            Pw = (np.c_[P, np.ones(len(P))] @ M.T)[:, :3]
            F = acc(j, blob, p['indices'])[:, 0].reshape(-1, 3)
            prims.append((ni, p, Pw, F))
            allP.append(Pw)
    Pall = np.vstack(allP)
    # weld: vertices at the same place are one for the smoothing
    tree = cKDTree(Pall)
    pairs = tree.query_pairs(1e-5, output_type='ndarray')
    rep = np.arange(len(Pall))
    for a, b in pairs: rep[b] = rep[a]
    edges = []
    base = 0
    for ni, p, Pw, F in prims:
        G = F + base
        for k in range(3):
            edges.append(np.c_[rep[G[:, k]], rep[G[:, (k + 1) % 3]]])
        base += len(Pw)
    E = np.vstack(edges)
    E = np.vstack([E, E[:, ::-1]])
    # the welded copies share their neighbours
    E = np.unique(E, axis=0)
    inv = rep # vertex -> representative
    # expand: every vertex uses its representative's edges (map both ends back to all members)
    a = E[:, 0]; b = E[:, 1]
    Jn, Wn, region = weights(Pall, J, bones, tails, (a, b))
    # the representatives carry the smoothed weights: copies take theirs
    Jn = Jn[inv]; Wn = Wn[inv]
    # ---- write: joints as nodes, the skin, the attributes ----
    first = len(j['nodes'])
    pos = {b[0]: b[2] for b in bones}
    ry = rest_yaw(J)
    gyaw = {} # each bone's world yaw at rest (only the head and the jaw turn)
    for n, par, at in bones:
        gyaw[n] = ry.get(n, gyaw.get(par, 0.0) if par else 0.0) if n in ('head', 'jaw') else (gyaw.get(par, 0.0) if par in ('head', 'jaw') else 0.0)
    for n, par, at in bones:
        rel = at - (pos[par] if par else np.zeros(3))
        py = gyaw.get(par, 0.0) if par else 0.0
        c, sn = np.cos(-py), np.sin(-py) # into the parent's (possibly turned) frame
        rel = np.array([c * rel[0] + sn * rel[2], rel[1], -sn * rel[0] + c * rel[2]])
        node = {'name': n, 'translation': [float(x) for x in rel]}
        ly = gyaw[n] - py
        if abs(ly) > 1e-6: node['rotation'] = quat_y(ly)
        j['nodes'].append(node)
    for i, (n, par, at) in enumerate(bones):
        if par:
            pi = first + names.index(par)
            j['nodes'][pi].setdefault('children', []).append(first + i)
    ibm = np.zeros((len(bones), 16), np.float32)
    for i, (n, par, at) in enumerate(bones):
        G = np.eye(4)
        c, sn = np.cos(gyaw[n]), np.sin(gyaw[n])
        G[:3, :3] = [[c, 0, sn], [0, 1, 0], [-sn, 0, c]]
        G[:3, 3] = at
        ibm[i] = np.linalg.inv(G).T.reshape(-1) # column major
    ibm_acc = add_acc(j, blob, ibm, 5126, 'MAT4')
    j.setdefault('skins', []).append({'joints': list(range(first, first + len(bones))), 'inverseBindMatrices': ibm_acc, 'skeleton': first, 'name': 'animal'})
    skin = len(j['skins']) - 1
    base = 0
    done_meshes = set()
    for ni, p, Pw, F in prims:
        n = len(Pw)
        jj = Jn[base:base + n].astype(np.uint8)
        ww = Wn[base:base + n].astype(np.float32)
        p['attributes']['JOINTS_0'] = add_acc(j, blob, np.ascontiguousarray(jj), 5121, 'VEC4', 34962)
        p['attributes']['WEIGHTS_0'] = add_acc(j, blob, np.ascontiguousarray(ww), 5126, 'VEC4', 34962)
        # skinned vertices are in the skeleton's space: bake the node's transform into them
        M = [m for (k, m) in meshes if k == ni][0]
        if not np.allclose(M, np.eye(4)):
            Pa = Pw.astype(np.float32)
            p['attributes']['POSITION'] = add_acc(j, blob, np.ascontiguousarray(Pa), 5126, 'VEC3', 34962, True)
        j['nodes'][ni]['skin'] = skin
        done_meshes.add(ni)
        base += n
    for ni in done_meshes: # a skinned mesh's own transform is ignored by the spec: keep it plain
        for k in ['translation', 'rotation', 'scale']: j['nodes'][ni].pop(k, None)
    j['scenes'][j.get('scene', 0)]['nodes'].append(first)
    j.setdefault('asset', {}).setdefault('extras', {})['rig'] = ' '.join(sys.argv[1:])
    write_glb(out, j, blob)
    counts = {r: int((region == r).sum()) for r in set(region.tolist())}
    print('bones', len(bones), 'regions', counts)
    print(out)


def sheet(j, blob, out):
    """Side, top and front pictures of the baked model with a 5 cm grid, to read the joints off."""
    from PIL import Image, ImageDraw
    P = []; C = []
    for ni, M in mesh_of(j, blob):
        for p in j['meshes'][j['nodes'][ni]['mesh']]['primitives']:
            X = acc(j, blob, p['attributes']['POSITION']).astype(np.float64)
            X = (np.c_[X, np.ones(len(X))] @ M.T)[:, :3]
            P.append(X)
            C.append(np.full((len(X), 3), 200))
    P = np.vstack(P); C = np.vstack(C)
    lo, hi = P.min(0) - 0.05, P.max(0) + 0.05
    S = 900
    span = max(hi - lo)
    sc = (S - 40) / span
    def view(a, b, d, flip_d):
        im = Image.new('RGB', (S, S), (22, 22, 26)); dr = ImageDraw.Draw(im)
        x = 20 + (P[:, a] - lo[a]) * sc; y = S - 20 - (P[:, b] - lo[b]) * sc
        dd = P[:, d] * flip_d
        o = np.argsort(dd)
        shade = (60 + 195 * (dd[o] - dd.min()) / max(np.ptp(dd), 1e-9)).astype(int)
        px = im.load()
        for xi, yi, s in zip(x[o].astype(int), y[o].astype(int), shade):
            if 0 <= xi < S and 0 <= yi < S: px[xi, yi] = (s, s, s)
        g = 0.05
        v = np.floor(lo[a] / g) * g
        while v <= hi[a]:
            X = 20 + (v - lo[a]) * sc
            dr.line([(X, 0), (X, S)], fill=(70, 40, 40) if abs(v) > 1e-6 else (200, 60, 60))
            if abs(round(v / 0.1) * 0.1 - v) < 1e-6: dr.text((X + 2, 4), '%.1f' % v, fill=(255, 120, 120))
            v += g
        v = np.floor(lo[b] / g) * g
        while v <= hi[b]:
            Y = S - 20 - (v - lo[b]) * sc
            dr.line([(0, Y), (S, Y)], fill=(40, 70, 40) if abs(v) > 1e-6 else (60, 200, 60))
            if abs(round(v / 0.1) * 0.1 - v) < 1e-6: dr.text((4, Y - 12), '%.1f' % v, fill=(120, 255, 120))
            v += g
        return im
    side = view(2, 1, 0, 1)    # z across, y up, seen from +x (the animal's left)
    top = view(2, 0, 1, 1)     # z across, x up, from above
    front = view(0, 1, 2, 1)   # x across, y up, from the front
    im = Image.new('RGB', (S * 3, S))
    im.paste(side, (0, 0)); im.paste(top, (S, 0)); im.paste(front, (2 * S, 0))
    im.save(out)
    print(out, 'lo', lo.round(3), 'hi', hi.round(3))


if __name__ == '__main__':
    main()
