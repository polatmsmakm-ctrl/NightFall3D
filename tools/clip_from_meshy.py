#!/usr/bin/env python3
"""Meshy motions -> the game's clips (assets/anims/<name>.glb), for every character.

Meshy's "Mixamo" skeleton has the Mixamo bone names, but its bones point another way (Y-up, no
Armature turn) from the Mixamo clips the game is built on (Z-down skeleton under an Armature turned
+90 degrees, centimetres). Copying its rotations across would twist every limb, so each frame is
retargeted through world space:

    D(bone, t)      = R_meshy(bone, t) * R_meshy_bind(bone)^-1      (how far the bone has turned)
    R_game(bone, t) = D(bone, t) * R_game_rest(bone)                (the same turn on the game's bone)
    local(bone, t)  = R_game(parent, t)^-1 * R_game(bone, t)

The hips' movement is carried across in metres, scaled by the two skeletons' hip heights (the game
keeps only the vertical part: in place, no root motion). The output copies the node tree of
assets/anims/idle.glb (a Mixamo "Without Skin" clip), so character_rig.gd loads it like any other.

    python3 tools/clip_from_meshy.py MESHY.glb Meshy_Anim_Name:clip [Name:clip ...] [--fps 30]
    python3 tools/clip_from_meshy.py MESHY.glb --list
"""
import argparse, json, os, struct, sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
TEMPLATE = os.path.join(ROOT, 'assets', 'anims', 'idle.glb')
COMP = {5120: 'b', 5121: 'B', 5122: 'h', 5123: 'H', 5125: 'I', 5126: 'f'}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}


def load(path):
    d = open(path, 'rb').read()
    off, j, blob = 12, None, b''
    while off < len(d):
        n, t = struct.unpack('<II', d[off:off + 8])
        if t == 0x4E4F534A:
            j = json.loads(d[off + 8:off + 8 + n])
        else:
            blob = d[off + 8:off + 8 + n]
        off += 8 + n
    return j, blob


def acc(j, blob, i):
    a = j['accessors'][i]
    bv = j['bufferViews'][a['bufferView']]
    n = NC[a['type']]
    fmt = COMP[a['componentType']]
    start = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    size = np.dtype(fmt).itemsize
    stride = bv.get('byteStride') or size * n
    if stride == size * n:
        out = np.frombuffer(blob, dtype='<' + fmt, count=a['count'] * n, offset=start).reshape(a['count'], n)
    else:
        out = np.array([np.frombuffer(blob, dtype='<' + fmt, count=n, offset=start + k * stride) for k in range(a['count'])])
    out = out.astype(np.float64)
    if a.get('normalized') and fmt in 'bBhH':
        out = out / {'b': 127.0, 'B': 255.0, 'h': 32767.0, 'H': 65535.0}[fmt]
    return out


# ---------------------------------------------------------------- quaternions (x, y, z, w)
def qmul(a, b):
    x1, y1, z1, w1 = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    x2, y2, z2, w2 = b[..., 0], b[..., 1], b[..., 2], b[..., 3]
    return np.stack([w1 * x2 + x1 * w2 + y1 * z2 - z1 * y2,
                     w1 * y2 - x1 * z2 + y1 * w2 + z1 * x2,
                     w1 * z2 + x1 * y2 - y1 * x2 + z1 * w2,
                     w1 * w2 - x1 * x2 - y1 * y2 - z1 * z2], -1)


def qinv(q):
    return q * np.array([-1.0, -1.0, -1.0, 1.0])


def qnorm(q):
    return q / np.linalg.norm(q, axis=-1, keepdims=True)


def qrot(q, v):
    p = np.concatenate([v, np.zeros(v.shape[:-1] + (1,))], -1)
    return qmul(qmul(q, p), qinv(q))[..., :3]


def mat_to_q(m):
    m = m[:3, :3] / np.linalg.norm(m[:3, :3], axis=0)
    t = np.trace(m)
    if t > 0:
        s = np.sqrt(t + 1.0) * 2
        q = [(m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s, 0.25 * s]
    elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = np.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
        q = [0.25 * s, (m[0, 1] + m[1, 0]) / s, (m[0, 2] + m[2, 0]) / s, (m[2, 1] - m[1, 2]) / s]
    elif m[1, 1] > m[2, 2]:
        s = np.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
        q = [(m[0, 1] + m[1, 0]) / s, 0.25 * s, (m[1, 2] + m[2, 1]) / s, (m[0, 2] - m[2, 0]) / s]
    else:
        s = np.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
        q = [(m[0, 2] + m[2, 0]) / s, (m[1, 2] + m[2, 1]) / s, 0.25 * s, (m[1, 0] - m[0, 1]) / s]
    return qnorm(np.array(q))


def slerp_track(times, values, t):
    """values (n, 4) at times (n,), sampled at t (m,)."""
    i = np.clip(np.searchsorted(times, t) - 1, 0, len(times) - 2) if len(times) > 1 else np.zeros(len(t), int)
    if len(times) == 1:
        return np.repeat(values[:1], len(t), 0)
    t0, t1 = times[i], times[i + 1]
    f = np.clip((t - t0) / np.maximum(t1 - t0, 1e-9), 0, 1)[:, None]
    a, b = values[i], values[i + 1]
    b = np.where((np.sum(a * b, -1) < 0)[:, None], -b, b)
    return qnorm(a * (1 - f) + b * f)  # nlerp: keys are 1/20 s apart


def lerp_track(times, values, t):
    if len(times) == 1:
        return np.repeat(values[:1], len(t), 0)
    i = np.clip(np.searchsorted(times, t) - 1, 0, len(times) - 2)
    f = np.clip((t - times[i]) / np.maximum(times[i + 1] - times[i], 1e-9), 0, 1)[:, None]
    return values[i] * (1 - f) + values[i + 1] * f


def short(name):
    return name.split(':')[-1].replace('mixamorig_', '')


# ---------------------------------------------------------------- the two skeletons
class Meshy:
    def __init__(self, path):
        self.j, self.blob = load(path)
        j = self.j
        sk = j['skins'][0]
        self.joints = sk['joints']
        ibm = acc(j, self.blob, sk['inverseBindMatrices']).reshape(-1, 4, 4)
        self.bind_q = {}
        self.bind_p = {}
        for k, n in enumerate(self.joints):
            w = np.linalg.inv(ibm[k].T)       # joint -> model space at bind
            self.bind_q[short(j['nodes'][n]['name'])] = mat_to_q(w)
            self.bind_p[short(j['nodes'][n]['name'])] = w[:3, 3]
        self.parent = {}
        for i, n in enumerate(j['nodes']):
            for c in n.get('children', []):
                self.parent[c] = i
        self.anims = {a.get('name', 'anim%d' % k): a for k, a in enumerate(j['animations'])}

    def chain(self, n):
        out = []
        while n is not None:
            out.append(n)
            n = self.parent.get(n)
        return out[::-1]

    def sample(self, name, fps):
        """World rotations and hips position of every joint, frame by frame."""
        j, a = self.j, self.anims[name]
        tracks = {}
        length = 0.0
        for c in a['channels']:
            s = a['samplers'][c['sampler']]
            t = acc(j, self.blob, s['input'])[:, 0]
            v = acc(j, self.blob, s['output'])
            tracks[(c['target']['node'], c['target']['path'])] = (t, v)
            length = max(length, t[-1])
        frames = max(2, int(round(length * fps)) + 1)
        ts = np.linspace(0.0, length, frames)
        local_q, local_p = {}, {}
        for i, n in enumerate(j['nodes']):
            r = tracks.get((i, 'rotation'))
            local_q[i] = slerp_track(*r, ts) if r else np.repeat([n.get('rotation', [0, 0, 0, 1])], frames, 0).astype(float)
            p = tracks.get((i, 'translation'))
            local_p[i] = lerp_track(*p, ts) if p else np.repeat([n.get('translation', [0, 0, 0])], frames, 0).astype(float)
        world_q, world_p = {}, {}
        for i in range(len(j['nodes'])):
            q = np.repeat([[0.0, 0, 0, 1]], frames, 0)
            p = np.zeros((frames, 3))
            for n in self.chain(i):          # (scale is 1 on every Meshy node)
                p = p + qrot(q, local_p[n])
                q = qmul(q, local_q[n])
            world_q[short(j['nodes'][i].get('name', ''))] = q
            world_p[short(j['nodes'][i].get('name', ''))] = p
        return ts, world_q, world_p, length


class Game:
    """The template clip's node tree: names, rest rotations, parents, and the Armature above the hips."""
    def __init__(self, path):
        self.j, self.blob = load(path)
        j = self.j
        self.parent = {}
        for i, n in enumerate(j['nodes']):
            for c in n.get('children', []):
                self.parent[c] = i
        self.byname = {n['name']: i for i, n in enumerate(j['nodes']) if 'name' in n}
        self.rest_q = {}
        self.rest_wq = {}
        self.scale = {}
        for i, n in enumerate(j['nodes']):
            self.rest_q[i] = np.array(n.get('rotation', [0, 0, 0, 1]), float)
        for i in range(len(j['nodes'])):
            q = np.array([0.0, 0, 0, 1])
            chain = []
            n = i
            while n is not None:
                chain.append(n)
                n = self.parent.get(n)
            for c in chain[::-1]:
                q = qmul(q, self.rest_q[c])
            self.rest_wq[i] = q
        self.hips = self.byname['mixamorig:Hips']
        self.arm = self.parent[self.hips]
        self.arm_q = self.rest_wq[self.arm]
        self.arm_s = float(j['nodes'][self.arm].get('scale', [1, 1, 1])[0])
        self.hips_rest = np.array(j['nodes'][self.hips]['translation'], float)
        # hip height in metres, in the world (the Armature turns and scales the hips' local position)
        self.hips_world = qrot(self.arm_q, self.hips_rest * self.arm_s)


def retarget(meshy, game, name, fps):
    ts, wq, wp, length = meshy.sample(name, fps)
    frames = len(ts)
    out = {}
    world = {}
    order = sorted(game.rest_wq, key=lambda i: len([1 for _ in iter(lambda: None, 0)]) if False else 0)
    # parents before children: walk the tree from the Armature
    stack, order = [game.arm], []
    while stack:
        n = stack.pop(0)
        order.append(n)
        stack.extend(game.j['nodes'][n].get('children', []))
    for i in order:
        nm = game.j['nodes'][i].get('name', '')
        if i == game.arm:
            world[i] = np.repeat([game.arm_q], frames, 0)
            continue
        b = short(nm)
        par = game.parent[i]
        if b in wq and b in meshy.bind_q:
            d = qmul(wq[b], qinv(np.repeat([meshy.bind_q[b]], frames, 0)))
            world[i] = qnorm(qmul(d, np.repeat([game.rest_wq[i]], frames, 0)))
            local = qnorm(qmul(qinv(world[par]), world[i]))
            # keep each key on the same side as the one before (no flips between frames)
            for k in range(1, frames):
                if np.dot(local[k], local[k - 1]) < 0:
                    local[k] = -local[k]
            out[i] = local
        else:                                   # fingers, ends: stay at rest, ride with the parent
            world[i] = qmul(world[par], np.repeat([game.rest_q[i]], frames, 0))
    # the hips: Meshy's movement from its bind, scaled to the game's hip height, back into the
    # Armature's local space (centimetres under a +90 degree turn)
    k = game.hips_world[1] / max(meshy.bind_p['Hips'][1], 1e-6)
    move = (wp['Hips'] - meshy.bind_p['Hips']) * k
    hips_local = game.hips_rest + qrot(np.repeat([qinv(game.arm_q)], frames, 0), move) / game.arm_s
    return ts, out, hips_local


def write(game, ts, rots, hips, out_path, clip):
    j = json.loads(json.dumps(game.j))
    for key in ('animations', 'accessors', 'bufferViews', 'buffers', 'meshes', 'skins', 'materials', 'textures', 'images', 'samplers'):
        j.pop(key, None)
    blob = bytearray()
    views, accs = [], []

    def put(arr, typ, mn=False):
        arr = np.ascontiguousarray(arr, dtype='<f4')
        while len(blob) % 4:
            blob.append(0)
        views.append({'buffer': 0, 'byteOffset': len(blob), 'byteLength': arr.nbytes})
        blob.extend(arr.tobytes())
        a = {'bufferView': len(views) - 1, 'componentType': 5126, 'count': len(arr), 'type': typ}
        if mn:
            a['min'] = [float(arr.min())]
            a['max'] = [float(arr.max())]
        accs.append(a)
        return len(accs) - 1

    t_acc = put(ts.reshape(-1, 1), 'SCALAR', True)
    samplers, channels = [], []
    for i, q in sorted(rots.items()):
        samplers.append({'input': t_acc, 'output': put(q, 'VEC4'), 'interpolation': 'LINEAR'})
        channels.append({'sampler': len(samplers) - 1, 'target': {'node': i, 'path': 'rotation'}})
    samplers.append({'input': t_acc, 'output': put(hips, 'VEC3'), 'interpolation': 'LINEAR'})
    channels.append({'sampler': len(samplers) - 1, 'target': {'node': game.hips, 'path': 'translation'}})
    j['animations'] = [{'name': clip, 'samplers': samplers, 'channels': channels}]
    j['accessors'] = accs
    j['bufferViews'] = views
    while len(blob) % 4:
        blob.append(0)
    j['buffers'] = [{'byteLength': len(blob)}]
    j.setdefault('asset', {})['generator'] = 'NightFall clip_from_meshy.py'
    js = json.dumps(j, separators=(',', ':')).encode()
    while len(js) % 4:
        js += b' '
    body = struct.pack('<II', len(js), 0x4E4F534A) + js + struct.pack('<II', len(blob), 0x004E4942) + bytes(blob)
    open(out_path, 'wb').write(struct.pack('<III', 0x46546C67, 2, 12 + len(body)) + body)


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('meshy')
    ap.add_argument('pairs', nargs='*', help='MeshyAnimName:clip_name')
    ap.add_argument('--fps', type=float, default=30.0)
    ap.add_argument('--out', default=os.path.join(ROOT, 'assets', 'anims'))
    ap.add_argument('--list', action='store_true')
    a = ap.parse_args()
    m = Meshy(a.meshy)
    if a.list:
        for n, an in m.anims.items():
            print(n)
        sys.exit(0)
    g = Game(TEMPLATE)
    for pair in a.pairs:
        src, clip = pair.split(':')
        ts, rots, hips = retarget(m, g, src, a.fps)
        path = os.path.join(a.out, clip + '.glb')
        write(g, ts, rots, hips, path, clip)
        print('%-28s -> %-16s %5.2f s  %d frames  %d bones  hips y %.2f..%.2f m' % (
            src, os.path.basename(path), ts[-1], len(ts), len(rots),
            -hips[:, 2].max() * g.arm_s, -hips[:, 2].min() * g.arm_s))
