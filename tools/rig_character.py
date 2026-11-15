#!/usr/bin/env python3
"""Turn a textured but *unrigged* T-pose sculpt into a playable NightFall character.

Meshy sculpts arrive with half a million triangles, real textures and no skeleton. This script:

  1. puts the mesh in the cast's space (feet on the floor, 1.95 m, facing +Z - turned round by
     itself if the toes point the other way);
  2. **fits the skeleton to this body.** Every joint is placed by measuring the sculpt the same
     way the donor is measured (armpit, arm centre line, fingertip, leg centres at knee and
     ankle, torso depth) and carrying the donor's own offset across. The joints' *rest
     translations* are rewritten to match, so the bones are as long as this body's limbs. The
     first version of this script only changed the bind matrices and left the donor's bone
     lengths in the skeleton, which is why «وردة الليل» had stretched forearms and bad hands;
  3. decimates in regions: the head, the hands and the feet each keep their own triangle budget,
     so fingers and shoes are not the first thing the collapse eats;
  4. weights by body part, not by "nearest bone": arms along the arm, legs along the leg (split
     left/right with a soft seam so a skirt does not tear), torso by height. Everything past the
     wrist belongs to the hand and everything under the ankle to the foot and toes, so hands and
     feet move as solid pieces instead of smearing along the forearm or shin.

    python3 tools/rig_character.py sculpt.glb assets/chars/survivorN.glb --faces 30000
    python3 tools/rig_character.py sculpt.glb assets/chars/survivorN_hi.glb --faces 70000 --tex 2048

Needs `pip install pymeshlab numpy pillow` and the system's libopengl0. The donor rig is
tools/rig/donor_mixamo22.glb (the 22-joint Mixamo skeleton every character shares).
"""
import argparse, io, json, os, struct
import numpy as np

JSON_CHUNK, BIN_CHUNK = 0x4E4F534A, 0x004E4942
COMP = {5120: ('b', 1), 5121: ('B', 1), 5122: ('h', 2), 5123: ('H', 2), 5125: ('I', 4), 5126: ('f', 4)}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}
HERE = os.path.dirname(os.path.abspath(__file__))


# ------------------------------------------------------------------ glTF in
def load(path):
    d = open(path, 'rb').read()
    off, j, blob = 12, None, b''
    while off < len(d):
        clen, ctype = struct.unpack('<II', d[off:off + 8])
        if ctype == JSON_CHUNK:
            j = json.loads(d[off + 8:off + 8 + clen])
        else:
            blob = d[off + 8:off + 8 + clen]
        off += 8 + clen
    return j, blob


def read_acc(j, blob, ai):
    a = j['accessors'][ai]
    fmt, size = COMP[a['componentType']]
    n = NC[a['type']]
    bv = j['bufferViews'][a['bufferView']]
    start = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    stride = bv.get('byteStride') or size * n
    if stride == size * n:
        arr = np.frombuffer(blob, dtype=np.dtype('<' + fmt), count=a['count'] * n, offset=start)
        return arr.reshape(a['count'], n).astype(np.float64 if fmt == 'f' else np.int64)
    out = np.empty((a['count'], n), dtype=np.float64 if fmt == 'f' else np.int64)
    for i in range(a['count']):
        out[i] = struct.unpack_from('<' + fmt * n, blob, start + i * stride)
    return out


def mesh_of(j, blob):
    P, T, F, base = [], [], [], 0
    for m in j['meshes']:
        for pr in m['primitives']:
            pos = read_acc(j, blob, pr['attributes']['POSITION'])
            uv = (read_acc(j, blob, pr['attributes']['TEXCOORD_0'])
                  if 'TEXCOORD_0' in pr['attributes'] else np.zeros((len(pos), 2)))
            idx = read_acc(j, blob, pr['indices'])[:, 0].astype(np.int64)
            P.append(pos); T.append(uv); F.append(idx.reshape(-1, 3) + base)
            base += len(pos)
    return np.vstack(P), np.vstack(T), np.vstack(F)


# ------------------------------------------------------------------ the donor skeleton
class Donor:
    def __init__(self, path):
        self.j, self.blob = load(path)
        j = self.j
        sk = j['skins'][0]
        self.joints = sk['joints']
        self.names = [j['nodes'][n]['name'].split(':')[-1] for n in self.joints]
        self.idx = {n: i for i, n in enumerate(self.names)}
        ibm = read_acc(j, self.blob, sk['inverseBindMatrices']).reshape(-1, 4, 4)
        self.world = np.array([np.linalg.inv(m.T) for m in ibm])   # joint -> mesh space
        self.pos = self.world[:, :3, 3].copy()
        order = {node: k for k, node in enumerate(self.joints)}
        self.parent = [-1] * len(self.joints)
        self.root_node = None
        for i, n in enumerate(j['nodes']):
            for c in n.get('children', []):
                if c in order:
                    if i in order:
                        self.parent[order[c]] = order[i]
                    else:
                        self.root_node = i               # the Armature above the hips
        self.mesh, _, _ = mesh_of(j, self.blob)

    def root_world(self):
        n = self.j['nodes'][self.root_node]
        if 'matrix' in n:
            return np.array(n['matrix']).reshape(4, 4).T
        t = np.array(n.get('translation', [0, 0, 0]), float)
        x, y, z, w = n.get('rotation', [0, 0, 0, 1])
        s = np.array(n.get('scale', [1, 1, 1]), float)
        R = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                      [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                      [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
        M = np.eye(4)
        M[:3, :3] = R * s
        M[:3, 3] = t
        return M

    def local_translations(self, pos):
        """Rest translations that put every joint at `pos` while keeping the donor's rotations."""
        out = []
        rootL = self.root_world()
        for k in range(len(self.joints)):
            p = self.parent[k]
            if p < 0:
                out.append(np.linalg.inv(rootL[:3, :3]) @ (pos[k] - rootL[:3, 3]))
            else:
                out.append(np.linalg.inv(self.world[p][:3, :3]) @ (pos[k] - pos[p]))
        return out


# ------------------------------------------------------------------ measuring a body
def smooth(a, b, x):
    t = np.clip((x - a) / max(b - a, 1e-9), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def mid(v):
    return (v.min() + v.max()) / 2.0


def measure(P):
    """The landmarks both bodies are measured by. Left is +x, forward is +z, up is +y."""
    m = {}
    for side, s in (('Left', 1.0), ('Right', -1.0)):
        A = P[(P[:, 0] * s > 0.10) & (P[:, 1] > 1.15)]
        u = A[:, 0] * s
        tip = u.max()
        xs = np.arange(0.10, tip, 0.02)
        thick, cy, cz = [], [], []
        for x0 in xs:
            sl = A[(u >= x0 - 0.01) & (u < x0 + 0.03)]   # wide enough for a low-poly donor
            if len(sl) < 3:
                thick.append(0.0); cy.append(np.nan); cz.append(np.nan)   # nothing here: thin
            else:
                thick.append(sl[:, 1].max() - sl[:, 1].min()); cy.append(mid(sl[:, 1])); cz.append(mid(sl[:, 2]))
        thick = np.array(thick); cy = np.array(cy); cz = np.array(cz)
        armpit = xs[-1]
        for i in range(len(xs) - 4):                   # the arm starts where the body is thin
            if np.all(thick[i:i + 4] < 0.24):
                armpit = xs[i]
                break
        ok = (xs > armpit + 0.02) & (xs < armpit + 0.72 * (tip - armpit)) & ~np.isnan(cy)
        if ok.sum() >= 3:
            ky, by = np.polyfit(xs[ok], cy[ok], 1)
            kz, bz = np.polyfit(xs[ok], cz[ok], 1)
        else:
            ky, by, kz, bz = 0.0, 1.5, 0.0, 0.0
        m[side] = {'armpit': armpit, 'tip': tip, 'line': (ky, by, kz, bz)}
        legs = {}
        for name, y0 in (('thigh', 0.75), ('knee', 0.541), ('ankle', 0.156)):
            sl = P[(np.abs(P[:, 1] - y0) < 0.025)]
            mine = sl[sl[:, 0] * s > 0.02]
            gap = (np.abs(sl[:, 0]) < 0.02).sum() < 0.02 * max(len(sl), 1)
            legs[name] = (mid(mine[:, 0]), mid(mine[:, 2])) if (gap and len(mine) > 10) else None
        foot = P[(P[:, 1] < 0.10) & (P[:, 0] * s > 0.02)]
        legs['toe_tip'] = foot[:, 2].max() if len(foot) else 0.2
        legs['foot_x'] = mid(foot[:, 0]) if len(foot) else 0.2 * s
        m[side]['legs'] = legs
    def depth(y0):
        sl = P[(np.abs(P[:, 1] - y0) < 0.03) & (np.abs(P[:, 0]) < 0.12)]
        return mid(sl[:, 2]) if len(sl) > 10 else 0.0
    m['depth'] = depth
    return m


def fit_skeleton(P, donor):
    """Donor joints moved onto this body: same measurement on both, the donor's offset kept."""
    D = measure(donor.mesh)
    S = measure(P)
    pos = donor.pos.copy()
    ix = donor.idx
    for side, s in (('Left', 1.0), ('Right', -1.0)):
        d, b = D[side], S[side]
        def line(mm, x):
            ky, by, kz, bz = mm['line']
            return ky * x + by, kz * x + bz
        dj = {n: donor.pos[ix[side + n]] for n in ('Shoulder', 'Arm', 'ForeArm', 'Hand')}
        # along the arm, measured from the armpit as a fraction of armpit -> fingertip
        span_d, span_s = d['tip'] - d['armpit'], b['tip'] - b['armpit']
        for n in ('Arm', 'ForeArm', 'Hand'):
            ud = dj[n][0] * s
            us = b['armpit'] + (ud - d['armpit']) * (span_s / span_d)
            ly_d, lz_d = line(d, ud)
            ly_s, lz_s = line(b, us)
            pos[ix[side + n]] = [us * s, ly_s + (dj[n][1] - ly_d), lz_s + (dj[n][2] - lz_d)]
        arm_d, arm_s = dj['Arm'], pos[ix[side + 'Arm']]
        pos[ix[side + 'Shoulder']] = [dj['Shoulder'][0] * (arm_s[0] / arm_d[0]),
                                      dj['Shoulder'][1] + (arm_s[1] - arm_d[1]),
                                      dj['Shoulder'][2] + (arm_s[2] - arm_d[2])]
        # legs: the centre of the leg at the thigh, the knee and the ankle
        dl, bl = d['legs'], b['legs']
        for jn, key in (('UpLeg', 'thigh'), ('Leg', 'knee'), ('Foot', 'ankle')):
            k = ix[side + jn]
            if dl[key] is not None and bl[key] is not None:
                pos[k][0] = donor.pos[k][0] + (bl[key][0] - dl[key][0])
                pos[k][2] = donor.pos[k][2] + (bl[key][1] - dl[key][1])
        foot, toe = ix[side + 'Foot'], ix[side + 'ToeBase']
        len_d = dl['toe_tip'] - donor.pos[foot][2]
        len_s = bl['toe_tip'] - pos[foot][2]
        pos[toe][0] = pos[foot][0] + (donor.pos[toe][0] - donor.pos[foot][0])
        pos[toe][2] = pos[foot][2] + (donor.pos[toe][2] - donor.pos[foot][2]) * (len_s / max(len_d, 1e-3))
    lift = ((pos[ix['LeftArm']][1] - donor.pos[ix['LeftArm']][1]) +
            (pos[ix['RightArm']][1] - donor.pos[ix['RightArm']][1])) / 2.0
    for n, share in (('Hips', 0.0), ('Spine', 0.0), ('Spine1', 0.3), ('Spine2', 0.8), ('Neck', 1.0), ('Head', 0.5)):
        k = ix[n]
        y_d = donor.pos[k][1]
        pos[k][1] = y_d + lift * share
        pos[k][2] = donor.pos[k][2] + (S['depth'](pos[k][1]) - D['depth'](y_d))
        pos[k][0] = 0.0
    return pos


# ------------------------------------------------------------------ weights by body part
def chain(u, knots, blends):
    """Weights along a chain of bones: bone i owns knots[i]..knots[i+1], blending at each joint."""
    n = len(knots)
    s = [np.ones_like(u)] + [smooth(knots[i] - blends[i - 1], knots[i] + blends[i - 1], u) for i in range(1, n)]
    return [s[i] * (1.0 - s[i + 1]) if i + 1 < n else s[i] for i in range(n)]


def skin_weights(P, F, pos, ix):
    nJ = len(pos)
    W = np.zeros((len(P), nJ))
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    # torso, by height
    names = ['Hips', 'Spine', 'Spine1', 'Spine2', 'Neck', 'Head']
    ks = [pos[ix[n]][1] for n in names]
    ks[0] = -9.0
    torso = np.zeros((len(P), nJ))
    for n, w in zip(names, chain(y, ks, [0.05, 0.05, 0.05, 0.035, 0.03])):
        torso[:, ix[n]] = w
    # legs, by height, split left/right with a soft seam down the middle
    legs = np.zeros((len(P), nJ))
    for side, share in (('Left', smooth(-0.025, 0.025, x)), ('Right', 1.0 - smooth(-0.025, 0.025, x))):
        up, knee, ankle, toe = (pos[ix[side + n]] for n in ('UpLeg', 'Leg', 'Foot', 'ToeBase'))
        w_up, w_leg, w_foot = chain(-y, [-9.0, -knee[1], -ankle[1]], [0.06, 0.03])
        toes = smooth(toe[2] - 0.015, toe[2] + 0.03, z) * (1.0 - smooth(ankle[1] - 0.03, ankle[1] + 0.02, y))
        legs[:, ix[side + 'UpLeg']] = share * w_up
        legs[:, ix[side + 'Leg']] = share * w_leg
        legs[:, ix[side + 'Foot']] = share * w_foot * (1.0 - toes)
        legs[:, ix[side + 'ToeBase']] = share * w_foot * toes
    up_y = (pos[ix['LeftUpLeg']][1] + pos[ix['RightUpLeg']][1]) / 2.0
    leg_part = 1.0 - smooth(up_y - 0.13, up_y + 0.03, y)
    body = legs * leg_part[:, None] + torso * (1.0 - leg_part)[:, None]
    # arms, along the arm; everything past the wrist is the hand
    arm_part = np.zeros(len(P))
    arms = np.zeros((len(P), nJ))
    for side, s in (('Left', 1.0), ('Right', -1.0)):
        sh, arm, fore, hand = (pos[ix[side + n]] for n in ('Shoulder', 'Arm', 'ForeArm', 'Hand'))
        u = x * s
        part = smooth(arm[0] * s - 0.07, arm[0] * s + 0.03, u) * smooth(arm[1] - 0.45, arm[1] - 0.3, y)
        ws = chain(u, [-9.0, arm[0] * s, fore[0] * s, hand[0] * s], [0.05, 0.06, 0.025])
        for n, w in zip(('Shoulder', 'Arm', 'ForeArm', 'Hand'), ws):
            arms[:, ix[side + n]] += w * part
        arm_part += part
    arm_part = np.clip(arm_part, 0.0, 1.0)
    W = arms + body * (1.0 - arm_part)[:, None]
    # two passes of smoothing over the mesh, so no seam is a hard line
    # (on the welded surface: the two copies of a vertex on a UV seam must end up with exactly
    # the same weights, or the seam opens into a slit the moment the joint bends)
    _, weld = np.unique(np.round(P * 1e5).astype(np.int64), axis=0, return_inverse=True)
    weld = weld.reshape(-1)
    nW = weld.max() + 1
    Ww = np.zeros((nW, nJ))
    Ww[weld] = W
    Fw = weld[F]
    e = np.vstack([Fw[:, [0, 1]], Fw[:, [1, 2]], Fw[:, [2, 0]]])
    e = np.unique(np.vstack([e, e[:, ::-1]]), axis=0)
    deg = np.bincount(e[:, 0], minlength=nW).astype(float)
    for _ in range(2):
        acc = np.zeros_like(Ww)
        np.add.at(acc, e[:, 0], Ww[e[:, 1]])
        Ww = 0.5 * Ww + 0.5 * acc / np.maximum(deg, 1.0)[:, None]
    W = Ww[weld]
    order = np.argsort(-W, axis=1)[:, :4]
    w4 = np.take_along_axis(W, order, axis=1)
    w4 /= np.maximum(w4.sum(axis=1, keepdims=True), 1e-9)
    return order.astype(np.uint16), w4.astype(np.float32)


# ------------------------------------------------------------------ decimation by region
def decimate(P, T, F, faces, pos, ix):
    import pymeshlab
    ms = pymeshlab.MeshSet()
    ms.add_mesh(pymeshlab.Mesh(vertex_matrix=P, face_matrix=F, v_tex_coords_matrix=T))
    ms.compute_texcoord_transfer_vertex_to_wedge()
    # the sculpt comes with its vertices doubled along every UV seam. Left like that, each side
    # of a seam is collapsed on its own and the surface opens into black cracks, so the doubles
    # are welded first: the UVs now live on the wedges and survive the weld.
    ms.meshing_merge_close_vertices(threshold=pymeshlab.PercentageValue(0.0005))
    wrist = min(abs(pos[ix['LeftHand']][0]), abs(pos[ix['RightHand']][0])) - 0.03
    ankle = max(pos[ix['LeftFoot']][1], pos[ix['RightFoot']][1]) + 0.04
    neck = pos[ix['Neck']][1]
    hands = "(abs(x0) > %.4f)" % wrist
    feet = "(y0 < %.4f)" % ankle
    head = "(y0 > %.4f)" % neck
    # the head, the hands and the feet keep a budget of their own: they are small, they are
    # what you look at, and a single collapse over the whole body flattens them first
    inner = "(abs(x0) <= %.4f)" % wrist                    # muparser has no "not": spell it out
    plan = [("%s && (y0 >= %.4f) && (y0 <= %.4f)" % (inner, ankle, neck), 0.47),
            (head + " && " + inner, 0.27), (hands, 0.17), (feet + " && " + inner, 0.09)]
    for cond, share in plan:
        ms.compute_selection_by_condition_per_face(condselect=cond)
        have = ms.current_mesh().selected_face_number()
        want = int(faces * share)
        if have > want:
            ms.meshing_decimation_quadric_edge_collapse_with_texture(
                targetfacenum=want, preserveboundary=False, preservenormal=True,
                planarquadric=True, qualitythr=0.3, extratcoordw=1.0, selected=True)
        now = ms.current_mesh().selected_face_number()
        print('   %-52s %7d -> %6d faces' % (cond[:52], have, now))
    ms.set_selection_none()
    ms.compute_normal_per_vertex()
    m = ms.current_mesh()
    V, Fm, Nv = np.asarray(m.vertex_matrix()), np.asarray(m.face_matrix()), np.asarray(m.vertex_normal_matrix())
    # A vertex on a UV seam has one texture coordinate per side of the seam. Folding the wedges
    # back to one UV per vertex makes every triangle across a seam sample right across the atlas
    # (black cracks on the skin), so vertices are split wherever their wedges disagree.
    wuv = np.asarray(m.wedge_tex_coord_matrix()).reshape(-1, 2)
    corner = Fm.reshape(-1)
    key = np.column_stack([corner, np.round(wuv * 8192.0).astype(np.int64)])
    uniq, first, inverse = np.unique(key, axis=0, return_index=True, return_inverse=True)
    return V[uniq[:, 0]], wuv[first], inverse.reshape(-1, 3), Nv[uniq[:, 0]]


def shrink_images(j, blob, side, T, F):
    """The sculpt's maps at a size a phone can hold, with the colour of every UV island bled
    out into the empty atlas around it. A decimated triangle never follows an island's edge as
    closely as the original did; without the padding its rim samples the black background and
    the skin gets dark specks along every seam."""
    from PIL import Image, ImageDraw
    out = []
    mask_img = Image.new('L', (side, side), 0)
    draw = ImageDraw.Draw(mask_img)
    uv = (T % 1.0) * side if (T.max() > 1.001 or T.min() < -0.001) else T * side
    for tri in uv[F].reshape(-1, 6):
        draw.polygon(tri.tolist(), fill=255)
    covered0 = np.asarray(mask_img) > 0
    for im in j.get('images', []):
        bv = j['bufferViews'][im['bufferView']]
        raw = blob[bv.get('byteOffset', 0):bv.get('byteOffset', 0) + bv['byteLength']]
        pic = Image.open(io.BytesIO(raw)).convert('RGB')
        if pic.width != side:
            pic = pic.resize((side, side), Image.LANCZOS)
        px = np.asarray(pic).astype(np.float32)
        covered = covered0.copy()
        for _ in range(16):                              # grow the islands sixteen pixels
            acc = np.zeros_like(px)
            cnt = np.zeros(covered.shape, np.float32)
            for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
                acc += np.roll(px * covered[..., None], (dy, dx), (0, 1))
                cnt += np.roll(covered, (dy, dx), (0, 1))
            grow = (~covered) & (cnt > 0)
            px[grow] = acc[grow] / cnt[grow][:, None]
            covered = covered | grow
        pic = Image.fromarray(np.clip(px, 0, 255).astype(np.uint8))
        buf = io.BytesIO()
        pic.save(buf, format='JPEG', quality=88, optimize=True)
        out.append(buf.getvalue())
    return out


# ------------------------------------------------------------------ the whole job
def build(src, out_path, donor_path, faces, tex_side, facing='auto'):
    sj, sb = load(src)
    donor = Donor(donor_path)
    ix = donor.idx
    P, T, F = mesh_of(sj, sb)
    T0, F0 = T.copy(), F.copy()                            # the sculpt's own UV layout, for the atlas padding
    dP = donor.mesh
    # 1. the cast's space
    P = P * ((dP[:, 1].max() - dP[:, 1].min()) / (P[:, 1].max() - P[:, 1].min()))
    P[:, 1] -= P[:, 1].min()
    P[:, 0] -= mid(P[:, 0])
    P[:, 2] -= mid(P[:, 2])
    backwards = P[P[:, 1] < 0.06][:, 2].mean() < P[(P[:, 1] > 0.25) & (P[:, 1] < 0.45)][:, 2].mean()
    if facing == 'turn' or (facing == 'auto' and backwards):
        P[:, 0] *= -1.0                                    # toes pointed backwards: turn it round
        P[:, 2] *= -1.0
        print('turned to face +z')
    # 2. the skeleton, fitted to this body
    pos = fit_skeleton(P, donor)
    for side in ('Left', 'Right'):
        a, f, h = (pos[ix[side + n]] for n in ('Arm', 'ForeArm', 'Hand'))
        da, dh = donor.pos[ix[side + 'Arm']], donor.pos[ix[side + 'Hand']]
        print('  %-5s arm %.3f m (donor %.3f)  wrist at x=%.3f  ankle x=%.3f' % (
            side, np.linalg.norm(h - a), np.linalg.norm(dh - da), h[0], pos[ix[side + 'Foot']][0]))
    check = max(np.abs(np.array(t) - np.array(donor.j['nodes'][donor.joints[k]].get('translation', [0, 0, 0]))).max()
                for k, t in enumerate(donor.local_translations(donor.pos)))
    print('  rest-translation round trip on the donor: max error %.5f' % check)
    # 3. decimate by region, 4. weight by body part
    P, T, F, N = decimate(P, T, F, faces, pos, ix)
    print('mesh: %d faces, %d vertices' % (len(F), len(P)))
    JJ, WW = skin_weights(P, F, pos, ix)
    # ---- write the GLB ----
    out = {'asset': {'version': '2.0', 'generator': 'NightFall rig_character.py'}}
    blob = bytearray()
    views, accs = [], []

    def put(data, count, comp, typ, target=None, mn=None, mx=None):
        while len(blob) % 4:
            blob.append(0)
        v = {'buffer': 0, 'byteOffset': len(blob), 'byteLength': len(data)}
        if target:
            v['target'] = target
        views.append(v)
        blob.extend(data)
        a = {'bufferView': len(views) - 1, 'componentType': comp, 'count': count, 'type': typ}
        if mn is not None:
            a['min'], a['max'] = mn, mx
        accs.append(a)
        return len(accs) - 1

    pos_a = put(P.astype('<f4').tobytes(), len(P), 5126, 'VEC3', 34962, P.min(axis=0).tolist(), P.max(axis=0).tolist())
    nrm_a = put(N.astype('<f4').tobytes(), len(N), 5126, 'VEC3', 34962)
    uv_a = put(T.astype('<f4').tobytes(), len(T), 5126, 'VEC2', 34962)
    j_a = put(JJ.astype('<u2').tobytes(), len(JJ), 5123, 'VEC4', 34962)
    w_a = put(WW.astype('<f4').tobytes(), len(WW), 5126, 'VEC4', 34962)
    i_a = put(F.astype('<u4').reshape(-1).tobytes(), F.size, 5125, 'SCALAR', 34963)
    pics = shrink_images(sj, sb, tex_side, T0, F0)
    out['images'] = []
    for raw in pics:
        while len(blob) % 4:
            blob.append(0)
        views.append({'buffer': 0, 'byteOffset': len(blob), 'byteLength': len(raw)})
        blob.extend(raw)
        out['images'].append({'bufferView': len(views) - 1, 'mimeType': 'image/jpeg'})
    out['samplers'] = [{}]
    out['textures'] = [{'source': i, 'sampler': 0} for i in range(len(pics))]
    sm = sj['materials'][0] if sj.get('materials') else {}
    pbr = sm.get('pbrMetallicRoughness', {})
    mat = {'name': 'body', 'pbrMetallicRoughness': {'metallicFactor': 0.0, 'roughnessFactor': 0.85}}
    def tex(e):
        return e['index'] if e and e.get('index', 99) < len(pics) else None
    if tex(pbr.get('baseColorTexture')) is not None:
        mat['pbrMetallicRoughness']['baseColorTexture'] = {'index': tex(pbr.get('baseColorTexture'))}
    if tex(sm.get('normalTexture')) is not None:
        mat['normalTexture'] = {'index': tex(sm.get('normalTexture'))}
    if tex(pbr.get('metallicRoughnessTexture')) is not None:
        mat['pbrMetallicRoughness']['metallicRoughnessTexture'] = {'index': tex(pbr.get('metallicRoughnessTexture'))}
        mat['pbrMetallicRoughness'] = {k: v for k, v in mat['pbrMetallicRoughness'].items()
                                       if k not in ('metallicFactor', 'roughnessFactor')}
    out['materials'] = [mat]
    out['meshes'] = [{'name': 'body', 'primitives': [{'attributes': {
        'POSITION': pos_a, 'NORMAL': nrm_a, 'TEXCOORD_0': uv_a, 'JOINTS_0': j_a, 'WEIGHTS_0': w_a},
        'indices': i_a, 'material': 0}]}]
    # the donor's joints and rotations, with rest translations that fit this body
    dj = donor.j
    keep = sorted(set(donor.joints) | {donor.root_node})
    remap = {old: i for i, old in enumerate(keep)}
    trans = donor.local_translations(pos)
    nodes = []
    for old in keep:
        n = {k: v for k, v in dj['nodes'][old].items() if k not in ('mesh', 'skin', 'children')}
        kids = [remap[c] for c in dj['nodes'][old].get('children', []) if c in remap]
        if kids:
            n['children'] = kids
        if old in donor.joints:
            n['translation'] = [float(v) for v in trans[donor.joints.index(old)]]
        nodes.append(n)
    world = donor.world.copy()
    world[:, :3, 3] = pos
    ibm = np.array([np.linalg.inv(w).T for w in world], dtype='<f4')
    ibm_a = put(ibm.tobytes(), len(ibm), 5126, 'MAT4')
    out['skins'] = [{'inverseBindMatrices': ibm_a, 'joints': [remap[j] for j in donor.joints]}]
    nodes.append({'name': 'body', 'mesh': 0, 'skin': 0})
    nodes[remap[donor.root_node]].setdefault('children', []).append(len(nodes) - 1)
    out['nodes'] = nodes
    out['scenes'] = [{'nodes': [remap[donor.root_node]]}]
    out['scene'] = 0
    out['bufferViews'] = views
    out['accessors'] = accs
    while len(blob) % 4:
        blob.append(0)
    out['buffers'] = [{'byteLength': len(blob)}]
    js = json.dumps(out, separators=(',', ':')).encode()
    while len(js) % 4:
        js += b' '
    body = (struct.pack('<II', len(js), JSON_CHUNK) + js + struct.pack('<II', len(blob), BIN_CHUNK) + bytes(blob))
    open(out_path, 'wb').write(struct.pack('<III', 0x46546C67, 2, 12 + len(body)) + body)
    print('wrote %s: %.1f MB' % (out_path, (12 + len(body)) / 1e6))


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('src')
    ap.add_argument('out')
    ap.add_argument('--donor', default=os.path.join(HERE, 'rig', 'donor_mixamo22.glb'))
    ap.add_argument('--faces', type=int, default=30000)
    ap.add_argument('--tex', type=int, default=1024)
    ap.add_argument('--facing', choices=['auto', 'keep', 'turn'], default='auto',
                    help="auto looks at which way the toes point; high heels fool it, so say 'keep' or 'turn'")
    a = ap.parse_args()
    build(a.src, a.out, a.donor, a.faces, a.tex, a.facing)
