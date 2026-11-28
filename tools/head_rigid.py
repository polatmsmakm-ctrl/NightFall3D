#!/usr/bin/env python3
"""The face moves as one with the head (the owner: "faces and jaws move when dancing").

The rigs blended Head and Neck over a band ±2 cm round the head joint, which on these characters
runs right through the mouth: the chin was ~85% neck, the lips half and half, so every clip that
turns the head (the dances most of all) stretched the jaw and the lower face. This moves the whole
face, chin included, onto the Head bone and puts the head/neck blend under the chin, on the neck.
The back of the head keeps its blend at the skull's base (lower down there is hair and neck).

Only the skin weights change (JOINTS_0 / WEIGHTS_0, rewritten in place): every triangle, UV,
normal, material and texture stays exactly as it was. `asset.extras.head_rigid` marks a done file,
and the tool skips it.

  python3 tools/head_rigid.py assets/chars/*.glb
"""
import json, struct, sys
import numpy as np

def read(f):
    d = open(f, 'rb').read()
    l = struct.unpack('<I', d[12:16])[0]
    j = json.loads(d[20:20 + l])
    bo = 20 + l
    bl = struct.unpack('<I', d[bo:bo + 4])[0]
    return j, bytearray(d[bo + 8:bo + 8 + bl])

def write(f, j, b):
    js = json.dumps(j, separators=(',', ':')).encode()
    js += b' ' * ((4 - len(js) % 4) % 4)
    b = bytes(b) + b'\0' * ((4 - len(b) % 4) % 4)
    out = struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(b))
    out += struct.pack('<II', len(js), 0x4E4F534A) + js + struct.pack('<II', len(b), 0x004E4942) + b
    open(f, 'wb').write(out)

DT = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}

def view(j, b, i):
    """A writable numpy view onto the accessor's bytes (tightly packed only)."""
    a = j['accessors'][i]
    bv = j['bufferViews'][a['bufferView']]
    n = NC[a['type']]
    dt = np.dtype(DT[a['componentType']])
    st = bv.get('byteStride')
    if st and st != n * dt.itemsize:
        raise SystemExit('interleaved accessor: not handled')
    off = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    arr = np.frombuffer(memoryview(b)[off:off + a['count'] * n * dt.itemsize], dtype=dt).reshape(-1, n)
    return arr

def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)

def run(f):
    j, b = read(f)
    ex = j.setdefault('asset', {}).setdefault('extras', {})
    if ex.get('head_rigid'):
        print(f, 'already done'); return
    sk = j['skins'][0]
    names = [j['nodes'][k].get('name', '') for k in sk['joints']]
    try:
        hi = names.index('mixamorig:Head'); ni = names.index('mixamorig:Neck')
    except ValueError:
        print(f, 'no Head / Neck bone: skipped'); return
    ibm = np.array(view(j, b, sk['inverseBindMatrices']), dtype=np.float64).reshape(-1, 4, 4)
    hp = np.linalg.inv(ibm[hi].T)[:3, 3]
    npos = np.linalg.inv(ibm[ni].T)[:3, 3]
    prims = [p for m in j['meshes'] for p in m['primitives'] if 'JOINTS_0' in p['attributes']]
    V = np.vstack([np.array(view(j, b, p['attributes']['POSITION']), dtype=np.float64) for p in prims])
    # the face's profile down the middle: how far forward (+z) the surface comes at each height
    def front(y):
        s = (np.abs(V[:, 1] - y) < 0.006) & (np.abs(V[:, 0] - hp[0]) < 0.03) & (np.abs(V[:, 2] - hp[2]) < 0.25)
        return V[s, 2].max() if s.any() else None
    face = [front(hp[1] + d) for d in (0.02, 0.03, 0.04)]
    face = max([x for x in face if x is not None], default=None)
    neckf = [front(hp[1] + d) for d in np.arange(-0.13, -0.03, 0.01)]
    neckf = [x for x in neckf if x is not None]
    if face is None or not neckf:
        print(f, 'no face profile: skipped'); return
    nf = min(neckf)
    # the chin: the lowest height (below the mouth) where the surface still stands well out in front
    chin = None
    for d in np.arange(0.0, -0.12, -0.004):
        z = front(hp[1] + d)
        if z is None: continue
        if z >= nf + 0.6 * (face - nf): chin = hp[1] + d
        else: break
    if chin is None or not (hp[1] - 0.10 <= chin <= hp[1] + 0.015):
        print(f, 'chin not found (%s): skipped' % chin); return
    y_head = chin - 0.006    # full head from just under the chin
    y_neck = chin - 0.05     # full neck this far under it
    changed = 0
    for p in prims:
        P = np.array(view(j, b, p['attributes']['POSITION']), dtype=np.float64)
        J = view(j, b, p['attributes']['JOINTS_0'])
        W = view(j, b, p['attributes']['WEIGHTS_0'])
        if W.dtype != np.float32:
            raise SystemExit('weights not float: not handled')
        rel = P - hp
        r = np.hypot(rel[:, 0], rel[:, 2])
        # how much this point is the face (in front of the head joint) and not the back of the skull
        fr = smooth(-0.03, 0.03, rel[:, 2])
        # the target: on the face the blend sits under the chin; at the back it stays where it was
        tgt = smooth(y_neck, y_head, P[:, 1]) * fr
        near = (r < 0.17) & (P[:, 1] > y_neck - 0.01) & (P[:, 1] < hp[1] + 0.06)
        cur = (W * (J == hi)).sum(1)
        need = near & (tgt > cur + 0.01)
        for v in np.nonzero(need)[0]:
            w = W[v].astype(np.float64); jj = J[v].copy()
            if hi not in jj: # take the lightest slot for the head
                k = int(np.argmin(w)); jj[k] = hi; w[k] = 0.0
            k = int(np.nonzero(jj == hi)[0][0])
            others = w.sum() - w[k]
            want = float(tgt[v])
            if others > 1e-6:
                scale = (1.0 - want) / others
                w = w * scale
            w[k] = want
            w = w / w.sum()
            J[v] = jj; W[v] = w.astype(np.float32)
            changed += 1
    ex['head_rigid'] = 'tools/head_rigid.py (chin %.3f, %d vertices)' % (chin, changed)
    write(f, j, b)
    print(f, 'head joint %.3f chin %.3f (%+.3f): %d vertices onto the head' % (hp[1], chin, chin - hp[1], changed))

for f in sys.argv[1:]:
    run(f)
