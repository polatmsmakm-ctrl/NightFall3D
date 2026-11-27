#!/usr/bin/env python3
"""Give a rigged character finger bones (the owner: "make bones in their fingers ... in every character").

Our characters carry the 22-bone body of the Mixamo skeleton, no fingers; the clips in assets/anims
carry all 40 Mixamo finger bones. This adds the 20 bones of each hand (Thumb/Index/Middle/Ring/Pinky
1-4, Mixamo's own names) under the hands, placed on the character's own fingers, and moves the hand's
skin weight onto them past the knuckles. Nothing else changes: the same triangles, UVs, normals,
materials and textures (the GLB's images, embedded or beside it, are left exactly as they are).
Each new bone takes the clip skeleton's own rest rotation, so the clips' finger keys (copied onto
the character by bone name in character_rig.gd) bend the fingers as Mixamo meant.

  python3 tools/add_fingers.py IN.glb [OUT.glb] [--clip assets/anims/idle.glb] [--sheet out.png]
"""
import argparse, json, struct, sys
import numpy as np

FINGERS = ['Thumb', 'Index', 'Middle', 'Ring', 'Pinky']
SIDES = ['Left', 'Right']


# ---------------- glTF plumbing ----------------
def load(path):
    b = open(path, 'rb').read()
    assert b[:4] == b'glTF'
    jl = struct.unpack('<I', b[12:16])[0]
    j = json.loads(b[20:20 + jl])
    o = 20 + jl
    bl = struct.unpack('<I', b[o:o + 4])[0]
    blob = bytearray(b[o + 8:o + 8 + bl])
    return j, blob


def save(path, j, blob):
    while len(blob) % 4: blob.append(0)
    j['buffers'][0]['byteLength'] = len(blob)
    js = json.dumps(j, separators=(',', ':')).encode()
    js += b' ' * ((4 - len(js) % 4) % 4)
    out = b'glTF' + struct.pack('<II', 2, 12 + 8 + len(js) + 8 + len(blob))
    out += struct.pack('<I', len(js)) + b'JSON' + js
    out += struct.pack('<I', len(blob)) + b'BIN\x00' + bytes(blob)
    open(path, 'wb').write(out)


CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}


def acc_view(j, blob, ai):
    """(array view onto the blob, accessor) — writes go straight into the blob."""
    a = j['accessors'][ai]
    v = j['bufferViews'][a['bufferView']]
    dt = np.dtype(CT[a['componentType']])
    n = NC[a['type']]
    off = v.get('byteOffset', 0) + a.get('byteOffset', 0)
    stride = v.get('byteStride', 0) or dt.itemsize * n
    if stride == dt.itemsize * n:
        arr = np.frombuffer(blob, dtype=dt, count=a['count'] * n, offset=off).reshape(a['count'], n)
        return arr, a, None
    rows = np.ndarray((a['count'], n), dtype=dt, buffer=blob, offset=off, strides=(stride, dt.itemsize))
    return rows, a, stride


def add_accessor(j, blob, arr, comp, typ):
    while len(blob) % 4: blob.append(0)
    off = len(blob)
    data = np.ascontiguousarray(arr.astype(CT[comp])).tobytes()
    blob.extend(data)
    j['bufferViews'].append({'buffer': 0, 'byteOffset': off, 'byteLength': len(data)})
    a = {'bufferView': len(j['bufferViews']) - 1, 'componentType': comp, 'count': int(arr.shape[0]), 'type': typ}
    j['accessors'].append(a)
    return len(j['accessors']) - 1


def quat_m(q):
    x, y, z, w = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def trs(n):
    if 'matrix' in n: return np.array(n['matrix'], dtype=float).reshape(4, 4).T
    m = np.eye(4)
    s = np.array(n.get('scale', [1, 1, 1]), dtype=float)
    m[:3, :3] = quat_m(n.get('rotation', [0, 0, 0, 1])) * s
    m[:3, 3] = n.get('translation', [0, 0, 0])
    return m


def globals_of(j):
    parent = {}
    for i, n in enumerate(j['nodes']):
        for c in n.get('children', []): parent[c] = i
    G = {}
    def g(i):
        if i in G: return G[i]
        m = trs(j['nodes'][i])
        if i in parent: m = g(parent[i]) @ m
        G[i] = m
        return m
    for i in range(len(j['nodes'])): g(i)
    return G, parent


def node_by_name(j, name):
    for i, n in enumerate(j['nodes']):
        if n.get('name', '') in (name, name.replace(':', '_')): return i
    return -1


# ---------------- the clip skeleton's finger rest rotations ----------------
def clip_fingers(path):
    j, _ = load(path)
    out = {}
    for side in SIDES:
        for f in FINGERS:
            for k in range(1, 5):
                nm = 'mixamorig:%sHand%s%d' % (side, f, k)
                i = node_by_name(j, nm)
                if i < 0: raise SystemExit('the clip has no ' + nm)
                n = j['nodes'][i]
                out[nm] = (np.array(n.get('rotation', [0, 0, 0, 1]), float), np.array(n.get('translation', [0, 0, 0]), float))
    return out


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


# ---------------- the hand ----------------
def fit_hand(P, hand_w, wrist, elbow, up):
    """Five fingers on this hand: for each, the four joint positions (bind space)."""
    sel = hand_w > 0.35
    H = P[sel]
    if len(H) < 60: return None
    dirv = wrist - elbow; dirv /= np.linalg.norm(dirv)
    lat = np.cross(up, dirv); lat /= np.linalg.norm(lat)
    nrm = np.cross(dirv, lat)
    d = (H - wrist) @ dirv
    s = (H - wrist) @ lat
    h = (H - wrist) @ nrm
    L = np.percentile(d, 99.5)
    if L <= 1e-6: return None
    # the knuckles: where the hand narrows into separate fingers — the width (lateral spread)
    # stops growing; Mixamo hands put them at ~0.44 of the hand's length from the wrist
    knk = 0.44 * L
    fing = d > knk
    # which lateral side is the thumb: in a T-pose the thumb hangs forward and down from the palm
    # (toward -nrm or +nrm depending on the hand); find it as the cluster closest to the wrist that
    # stands furthest out sideways
    sF = s[fing]; dF = d[fing]; hF = h[fing]
    # four fingers: split the lateral range of the finger region at its three widest gaps
    q = np.percentile(sF, [2, 98])
    lo, hi = q[0], q[1]
    # thumb candidates: in the base half of the hand, outside the fingers' lateral range
    base = (d > 0.08 * L) & (d < 0.75 * L)
    side_pos = base & (s > hi + 0.10 * (hi - lo))
    side_neg = base & (s < lo - 0.10 * (hi - lo))
    tside = 1.0 if side_pos.sum() >= side_neg.sum() else -1.0
    thumb = side_pos if tside > 0 else side_neg
    fingers = []
    # the four fingers: equal lateral bands across [lo, hi], index next to the thumb
    edges = np.linspace(lo, hi, 5)
    order = range(4) if tside < 0 else range(3, -1, -1)
    bands = []
    for b in range(4):
        m = fing & (s >= edges[b]) & (s <= edges[b + 1])
        bands.append(m)
    bands = [bands[i] for i in (range(3, -1, -1) if tside > 0 else range(4))]  # index .. pinky
    for m in bands:
        if m.sum() < 8:
            m = fing  # a mitten-like hand: share the whole finger block
        Hm = H[m]
        dm = d[m]
        tip_d = np.percentile(dm, 99)
        c_s = np.median(s[m]); c_h = np.median(h[m])
        b0 = wrist + dirv * knk + lat * c_s + nrm * c_h
        tip = wrist + dirv * tip_d + lat * c_s + nrm * np.median(h[m][dm > np.percentile(dm, 80)])
        fingers.append([b0 + (tip - b0) * f for f in (0.0, 0.45, 0.76, 1.0)])
    if thumb.sum() >= 8:
        T = H[thumb]
        dist = np.linalg.norm(T - wrist, axis=1)
        far = T[dist >= np.percentile(dist, 97)].mean(axis=0)
        root = wrist + dirv * (0.12 * L) + lat * (tside * 0.35 * (hi - lo) + (lo + hi) / 2) + nrm * np.median(h[thumb])
        th = [root + (far - root) * f for f in (0.0, 0.42, 0.72, 1.0)]
    else:  # no thumb to be found: a short stub beside the index finger
        root = wrist + dirv * 0.15 * L + lat * (tside * (hi - lo) * 0.6 + (lo + hi) / 2)
        tip = root + dirv * 0.3 * L + lat * tside * 0.15 * L
        th = [root + (tip - root) * f for f in (0.0, 0.42, 0.72, 1.0)]
    return {'Thumb': th, 'Index': fingers[0], 'Middle': fingers[1], 'Ring': fingers[2], 'Pinky': fingers[3],
            'L': L, 'knk': knk, 'dir': dirv}


def seg_param(P, chain):
    """Distance from each point to a 4-joint chain, and where along it (0..3: which segment, fraction)."""
    best_d = np.full(len(P), np.inf); best_u = np.zeros(len(P))
    for k in range(3):
        a, b = chain[k], chain[k + 1]
        ab = b - a
        t = np.clip(((P - a) @ ab) / max(ab @ ab, 1e-12), 0.0, 1.0)
        q = a + t[:, None] * ab
        dd = np.linalg.norm(P - q, axis=1)
        better = dd < best_d
        best_d[better] = dd[better]; best_u[better] = k + t[better]
    return best_d, best_u


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('src'); ap.add_argument('dst', nargs='?')
    ap.add_argument('--clip', default='assets/anims/idle.glb')
    args = ap.parse_args()
    dst = args.dst or args.src
    j, blob = load(args.src)
    if node_by_name(j, 'mixamorig:LeftHandIndex1') >= 0:
        print('already has fingers:', args.src); return
    clip = clip_fingers(args.clip)
    skin = j['skins'][0]
    joints = list(skin['joints'])
    ibm, _, _ = acc_view(j, blob, skin['inverseBindMatrices'])
    IBM = [ibm[i].reshape(4, 4).T.astype(float) for i in range(len(joints))]
    G, parent = globals_of(j)
    jix = {j['nodes'][n].get('name', ''): k for k, n in enumerate(joints)}
    def J(name):
        k = jix.get('mixamorig:' + name, jix.get('mixamorig_' + name, -1))
        if k < 0: raise SystemExit('no bone ' + name)
        return k
    bindG = [np.linalg.inv(m) for m in IBM]                      # each joint in bind space
    hand_k = {sd: J(sd + 'Hand') for sd in SIDES}
    bind_to_node = G[joints[hand_k['Left']]] @ IBM[hand_k['Left']]  # bind space -> node world
    up = bindG[J('Head')][:3, 3] - bindG[J('Hips')][:3, 3]; up /= np.linalg.norm(up)
    # every skinned primitive's positions and weights
    prims = []
    for mesh in j['meshes']:
        for pr in mesh['primitives']:
            at = pr['attributes']
            if 'JOINTS_0' not in at: continue
            P, _, _ = acc_view(j, blob, at['POSITION'])
            JJ, ja, _ = acc_view(j, blob, at['JOINTS_0'])
            WW, wa, _ = acc_view(j, blob, at['WEIGHTS_0'])
            prims.append((P.astype(float), JJ, WW, wa))
    allP = np.concatenate([p[0] for p in prims])
    def wof(k):
        return np.concatenate([np.where(p[1] == k, p[2].astype(float) / (255.0 if p[2].dtype == np.uint8 else (65535.0 if p[2].dtype == np.uint16 else 1.0)), 0.0).sum(axis=1) for p in prims])
    new_nodes = {}
    fit = {}
    for sd in SIDES:
        hk = hand_k[sd]
        wrist = bindG[hk][:3, 3]
        elbow = bindG[J(sd + 'ForeArm')][:3, 3]
        f = fit_hand(allP, wof(hk), wrist, elbow, up)
        if f is None: raise SystemExit('no hand found: ' + sd)
        fit[sd] = f
        # the bones: clip rest rotation, translation to fit this hand (node space)
        for fn in FINGERS:
            par_node = joints[hk]
            par_G = G[par_node]
            for k in range(4):
                nm = 'mixamorig:%sHand%s%d' % (sd, fn, k + 1)
                q, _ = clip[nm]
                pos_world = (bind_to_node @ np.append(f[fn][k], 1.0))[:3]
                t_local = (np.linalg.inv(par_G) @ np.append(pos_world, 1.0))[:3]
                node = {'name': nm, 'rotation': [float(x) for x in q], 'translation': [float(x) for x in t_local]}
                j['nodes'].append(node)
                ni = len(j['nodes']) - 1
                j['nodes'][par_node].setdefault('children', []).append(ni)
                Gn = par_G @ trs(node)
                G[ni] = Gn
                new_nodes[nm] = ni
                joints.append(ni)
                IBM.append(np.linalg.inv(np.linalg.inv(bind_to_node) @ Gn))
                par_node = ni; par_G = Gn
    skin['joints'] = joints
    jk = {nm: joints.index(ni) for nm, ni in new_nodes.items()}
    if len(joints) > 255:
        print('warning: more than 255 joints')
    # weights: past the knuckles the hand's share goes to the nearest finger, bone by bone
    moved = 0
    for P, JJ, WW, wa in prims:
        scale = 255.0 if WW.dtype == np.uint8 else (65535.0 if WW.dtype == np.uint16 else 1.0)
        W = WW.astype(float) / scale
        for sd in SIDES:
            f = fit[sd]; hk = hand_k[sd]
            wrist = bindG[hk][:3, 3]
            hw = np.where(JJ == hk, W, 0.0).sum(axis=1)
            cand = np.nonzero(hw > 1e-4)[0]
            if len(cand) == 0: continue
            Pc = P[cand]
            dist = np.full(len(cand), np.inf); u = np.zeros(len(cand)); which = np.zeros(len(cand), int)
            for fi, fn in enumerate(FINGERS):
                dd, uu = seg_param(Pc, f[fn])
                b = dd < dist
                dist[b] = dd[b]; u[b] = uu[b]; which[b] = fi
            dalong = (Pc - wrist) @ f['dir']
            # how much of the hand's weight moves: none at the palm, all past the knuckles (the thumb
            # from its own base); a short blend so the knuckle bends smoothly
            share = smoothstep(f['knk'] - 0.08 * f['L'], f['knk'] + 0.03 * f['L'], dalong)
            th = which == 0
            share[th] = smoothstep(0.02, 0.35, u[th] / 3.0 + 0.1)
            # a point far from every finger (the palm's back, a cuff) stays on the hand
            share *= smoothstep(0.30 * f['L'], 0.16 * f['L'], dist)
            for ci, vi in enumerate(cand):
                s = share[ci]
                if s <= 1e-3: continue
                take = hw[vi] * s
                fn = FINGERS[which[ci]]
                uu = u[ci]  # 0..3 along the finger
                # bone k owns segment k; blend across each joint
                k0 = int(min(np.floor(uu), 2)); fr = uu - k0
                parts = {}
                b1 = smoothstep(0.75, 1.0, fr) if k0 < 2 else 0.0
                parts[jk['mixamorig:%sHand%s%d' % (sd, fn, k0 + 1)]] = take * (1 - b1)
                if b1 > 0: parts[jk['mixamorig:%sHand%s%d' % (sd, fn, k0 + 2)]] = take * b1
                b0 = smoothstep(0.25, 0.0, fr) if k0 > 0 else 0.0
                if b0 > 0:
                    a = jk['mixamorig:%sHand%s%d' % (sd, fn, k0 + 1)]
                    parts[a] -= take * (1 - b1) * b0 * 0.5
                    pk = jk['mixamorig:%sHand%s%d' % (sd, fn, k0)]
                    parts[pk] = parts.get(pk, 0) + take * (1 - b1) * b0 * 0.5
                infl = {}
                for slot in range(4):
                    if W[vi, slot] > 0: infl[int(JJ[vi, slot])] = infl.get(int(JJ[vi, slot]), 0) + W[vi, slot]
                infl[hk] = infl.get(hk, 0) - take
                for a, w in parts.items(): infl[a] = infl.get(a, 0) + w
                top = sorted([(w, a) for a, w in infl.items() if w > 1e-5], reverse=True)[:4]
                tot = sum(w for w, _ in top) or 1.0
                for slot in range(4):
                    if slot < len(top):
                        JJ[vi, slot] = top[slot][1]; W[vi, slot] = top[slot][0] / tot
                    else:
                        JJ[vi, slot] = 0; W[vi, slot] = 0.0
                moved += 1
        if scale == 1.0: WW[:] = W.astype(WW.dtype)
        else:
            q = np.round(W * scale)
            q[:, 0] += scale - q.sum(axis=1)  # integer weights must still add up exactly
            WW[:] = np.clip(q, 0, scale).astype(WW.dtype)
        if JJ.dtype == np.uint8 and len(joints) > 255: raise SystemExit('too many joints for byte indices')
    # the bigger bind-matrix table goes at the end of the buffer (no views onto it may be open then)
    del prims, ibm, JJ, WW, P
    skin['inverseBindMatrices'] = add_accessor(j, blob, np.array([m.T.reshape(16) for m in IBM]), 5126, 'MAT4')
    j.setdefault('asset', {}).setdefault('extras', {})['fingers'] = 'tools/add_fingers.py (%d finger bones, %d vertices)' % (len(new_nodes), moved)
    save(dst, j, blob)
    print('%s: +%d finger bones, %d vertices weighted to fingers' % (dst, len(new_nodes), moved))


if __name__ == '__main__':
    main()
