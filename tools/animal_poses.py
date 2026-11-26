#!/usr/bin/env python3
"""Pose test for a rigged animal (tools/rig_animal.py), with no Godot: bends the skeleton into a few
poses (rest, a walk's two extremes, sitting / stalking, the mouth open, the head turned, the tail
swung) and draws the skinned mesh from the side and the front, coloured from its texture.

    python3 tools/animal_poses.py animal.glb out.png [cat|dog]
"""
import io, json, sys
import numpy as np
from PIL import Image, ImageDraw
sys.path.insert(0, __import__('os').path.dirname(__file__))
import rig_animal as ra


def quat_mat(q):
    x, y, z, w = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def euler(e): # Godot's Quaternion.from_euler order (YXZ applied: rotate about Z, then X, then Y)
    x, y, z = e
    def rx(a): c, s = np.cos(a), np.sin(a); return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
    def ry(a): c, s = np.cos(a), np.sin(a); return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
    def rz(a): c, s = np.cos(a), np.sin(a); return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])
    return ry(y) @ rx(x) @ rz(z)


def main():
    path, out = sys.argv[1], sys.argv[2]
    kind = sys.argv[3] if len(sys.argv) > 3 else 'cat'
    j, blob = ra.read_glb(path)
    sk = j['skins'][0]
    joints = sk['joints']
    names = [j['nodes'][k]['name'] for k in joints]
    ibm = ra.acc(j, blob, sk['inverseBindMatrices']).reshape(-1, 4, 4).transpose(0, 2, 1)
    parent = {}
    for i, nd in enumerate(j['nodes']):
        for c in nd.get('children', []): parent[c] = i
    local = {}
    for k in joints:
        nd = j['nodes'][k]
        M = np.eye(4)
        if 'rotation' in nd: M[:3, :3] = quat_mat(nd['rotation'])
        M[:3, 3] = nd.get('translation', [0, 0, 0])
        local[k] = M
    P = []; UV = []; JJ = []; WW = []; tex = None
    for nd in j['nodes']:
        if 'mesh' not in nd or 'skin' not in nd: continue
        for p in j['meshes'][nd['mesh']]['primitives']:
            P.append(ra.acc(j, blob, p['attributes']['POSITION']).astype(float))
            UV.append(ra.acc(j, blob, p['attributes']['TEXCOORD_0']).astype(float))
            JJ.append(ra.acc(j, blob, p['attributes']['JOINTS_0']).astype(int))
            WW.append(ra.acc(j, blob, p['attributes']['WEIGHTS_0']).astype(float))
            if tex is None:
                mat = j['materials'][p['material']]
                ti = mat['pbrMetallicRoughness']['baseColorTexture']['index']
                im = j['images'][j['textures'][ti]['source']]
                v = j['bufferViews'][im['bufferView']]
                tex = np.asarray(Image.open(io.BytesIO(bytes(blob[v.get('byteOffset', 0):v.get('byteOffset', 0) + v['byteLength']]))).convert('RGB').resize((1024, 1024)))
    P = np.vstack(P); UV = np.vstack(UV); JJ = np.vstack(JJ); WW = np.vstack(WW)
    C = tex[np.clip((UV[:, 1] % 1 * 1023).astype(int), 0, 1023), np.clip((UV[:, 0] % 1 * 1023).astype(int), 0, 1023)]
    tails = [n for n in names if n.startswith('tail')]
    a = 0.45
    env = __import__('os').environ
    if 'SIT' in env: SIT_POSE = json.loads(env['SIT'])
    elif kind == 'cat': SIT_POSE = {'hips@': [0, -0.1, 0], 'hips': [-0.62, 0, 0], 'chest': [0.18, 0, 0], 'bl_top': [-0.5, 0, 0], 'br_top': [-0.5, 0, 0], 'bl_mid': [1.9, 0, 0], 'br_mid': [1.9, 0, 0], 'bl_low': [-1.5, 0, 0], 'br_low': [-1.5, 0, 0], 'fl_top': [0.44, 0, 0], 'fr_top': [0.44, 0, 0]}
    else: SIT_POSE = {'fl_top': [-0.35, 0, 0], 'fr_top': [-0.35, 0, 0], 'fl_mid': [0.85, 0, 0], 'fr_mid': [0.85, 0, 0], 'fl_low': [-0.55, 0, 0], 'fr_low': [-0.55, 0, 0],
                      'bl_top': [-0.5, 0, 0], 'br_top': [-0.5, 0, 0], 'bl_mid': [0.95, 0, 0], 'br_mid': [0.95, 0, 0], 'bl_low': [-0.6, 0, 0], 'br_low': [-0.6, 0, 0], 'neck1': [0.3, 0, 0], 'head': [0.2, 0, 0]}
    poses = {
        'rest': {},
        'walk A': {'fl_top': [-a, 0, 0], 'br_top': [-a, 0, 0], 'fr_top': [a, 0, 0], 'bl_top': [a, 0, 0], 'fr_mid': [0.5, 0, 0], 'fr_low': [-0.9, 0, 0], 'bl_mid': [-0.6, 0, 0], 'bl_low': [0.9, 0, 0]},
        'walk B': {'fr_top': [-a, 0, 0], 'bl_top': [-a, 0, 0], 'fl_top': [a, 0, 0], 'br_top': [a, 0, 0], 'fl_mid': [0.5, 0, 0], 'fl_low': [-0.9, 0, 0], 'br_mid': [-0.6, 0, 0], 'br_low': [0.9, 0, 0]},
        'mouth + look': {'jaw': [0.62, 0, 0], 'neck1': [-0.2, 0.3, 0], 'neck2': [-0.15, 0.3, 0], 'head': [-0.1, 0.25, 0]},
        ('sit' if kind == 'cat' else 'stalk'): SIT_POSE,
        'tail + shake': dict({t: [0.0, 0.5, 0.15] for t in tails}, **{'neck1': [0, 0.35, 0.15], 'neck2': [0, 0.45, 0.2], 'head': [0, 0.4, 0.3]}),
    }
    S = int(__import__('os').environ.get('POSE_PX', '420'))
    cols = []
    for title, pose in poses.items():
        glob = {}
        def g(k):
            if k in glob: return glob[k]
            L = local[k].copy()
            nm = j['nodes'][k]['name']
            if nm in pose: L[:3, :3] = L[:3, :3] @ euler(pose[nm])
            if nm + '@' in pose: L[:3, 3] = L[:3, 3] + np.array(pose[nm + '@'])
            G = (g(parent[k]) @ L) if parent.get(k) in local else L
            glob[k] = G
            return G
        mats = np.array([g(k) @ ibm[i] for i, k in enumerate(joints)])
        Ph = np.c_[P, np.ones(len(P))]
        Q = np.zeros((len(P), 3))
        for c in range(4):
            Q += WW[:, c:c + 1] * np.einsum('nij,nj->ni', mats[JJ[:, c]], Ph)[:, :3]
        lo = np.array([-0.4, 0, -0.45]) * (1 if kind == 'cat' else 2.6)
        span = 0.9 * (1 if kind == 'cat' else 2.6)
        panel = []
        for (ax, ay, ad, sgn) in [(2, 1, 0, 1), (0, 1, 2, 1)]:
            im = Image.new('RGB', (S, S), (24, 24, 28))
            px = im.load()
            x = ((Q[:, ax] - lo[ax]) / span * S).astype(int)
            y = (S - 10 - Q[:, ay] / span * S).astype(int)
            o = np.argsort(Q[:, ad] * sgn)
            for i in o:
                if 0 <= x[i] < S and 0 <= y[i] < S: px[x[i], y[i]] = tuple(C[i])
            ImageDraw.Draw(im).text((6, 6), title, fill=(255, 220, 0))
            panel.append(np.asarray(im))
        cols.append(np.vstack(panel))
    Image.fromarray(np.hstack(cols)).save(out)
    print(out)


if __name__ == '__main__':
    main()
