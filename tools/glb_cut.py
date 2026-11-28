"""Cut one piece out of a single-mesh GLB by a test on each triangle's middle, every triangle and
attribute kept as it was, the textures embedded the same. Usage (in code): cut(src, dst, keep(cx, cy, cz) -> bool)
python3 tools/glb_cut.py rocket   -> assets/props/moon_rocket_ship.glb (the rocket without its tower and pad)"""
import sys, json, struct, numpy as np

def load(path):
    d = open(path, 'rb').read(); l = struct.unpack('<I', d[12:16])[0]
    j = json.loads(d[20:20 + l]); b = d[20 + l + 8:]
    return j, b

def acc(j, b, i):
    a = j['accessors'][i]; bv = j['bufferViews'][a['bufferView']]
    n = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[a['type']]
    dt = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}[a['componentType']]
    off = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    return np.frombuffer(b, dt, a['count'] * n, off).reshape(a['count'], n)

def cut(src, dst, keep, node_name='ship', maps=None):
    j, b = load(src)
    prim = j['meshes'][0]['primitives'][0]
    F = acc(j, b, prim['indices'])[:, 0].astype(np.int64).reshape(-1, 3)
    attrs = {k: acc(j, b, v) for k, v in prim['attributes'].items()}
    P = attrs['POSITION']; c = P[F].mean(1)
    m = np.array([keep(*x) for x in c]) if callable(keep) and not hasattr(keep, 'vector') else keep(c)
    Fk = F[m]
    used, inv = np.unique(Fk.ravel(), return_inverse=True)
    idx = inv.reshape(-1, 3).astype(np.uint32)
    out = b''; views = []; accs = []; newattr = {}
    def add(arr, target, typ, comp):
        nonlocal out
        out += b'\0' * ((-len(out)) % 4)
        views.append({'buffer': 0, 'byteOffset': len(out), 'byteLength': arr.nbytes, **({'target': target} if target else {})})
        out += arr.tobytes()
        a = {'bufferView': len(views) - 1, 'componentType': comp, 'count': arr.shape[0], 'type': typ}
        if typ == 'VEC3' and comp == 5126: a['min'] = arr.min(0).tolist(); a['max'] = arr.max(0).tolist()
        accs.append(a); return len(accs) - 1
    for k, v in attrs.items():
        arr = np.ascontiguousarray(v[used].astype(np.float32))
        newattr[k] = add(arr, 34962, {1: 'SCALAR', 2: 'VEC2', 3: 'VEC3', 4: 'VEC4'}[arr.shape[1]], 5126)
    ii = add(np.ascontiguousarray(idx.reshape(-1, 1)), 34963, 'SCALAR', 5125)
    accs[ii]['count'] = idx.size
    images = []
    import os
    for k, im in enumerate(j.get('images', [])):
        bv = j['bufferViews'][im['bufferView']]; o = bv.get('byteOffset', 0)
        data = b[o:o + bv['byteLength']]
        if maps: # the maps beside the GLB, byte for byte, shared by every piece cut from it
            name = '%s_%d.%s' % (maps, k, 'png' if 'png' in im['mimeType'] else 'jpg')
            open(os.path.join(os.path.dirname(dst), name), 'wb').write(data)
            images.append({'uri': name}); continue
        out += b'\0' * ((-len(out)) % 4)
        views.append({'buffer': 0, 'byteOffset': len(out), 'byteLength': len(data)}); out += data
        images.append({'bufferView': len(views) - 1, 'mimeType': im['mimeType']})
    g = {'asset': {'version': '2.0', 'generator': 'nightfall glb_cut', 'extras': {'from': src.split('/')[-1]}},
         'scene': 0, 'scenes': [{'nodes': [0]}], 'nodes': [{'name': node_name, 'mesh': 0}],
         'meshes': [{'primitives': [{'attributes': newattr, 'indices': ii, 'material': 0}]}],
         'accessors': accs, 'bufferViews': views, 'buffers': [{'byteLength': len(out) + (-len(out)) % 4}],
         'materials': j['materials'], 'textures': j.get('textures', []), 'samplers': j.get('samplers', []), 'images': images}
    if not g['samplers']: g.pop('samplers')
    js = json.dumps(g, separators=(',', ':')).encode(); js += b' ' * ((-len(js)) % 4); out += b'\0' * ((-len(out)) % 4)
    with open(dst, 'wb') as f:
        f.write(struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(out)))
        f.write(struct.pack('<II', len(js), 0x4E4F534A)); f.write(js); f.write(struct.pack('<II', len(out), 0x004E4942)); f.write(out)
    print('%s: %d of %d triangles' % (dst, len(Fk), len(F)))

if __name__ == '__main__' and sys.argv[1:] == ['rocket']:
    # his Escape Rocket without its launch tower and pad: everything within 4 m of the rocket's axis,
    # above the pad, and not on the tower's side of it
    def keep(c):
        r = np.hypot(c[:, 0] - 0.15, c[:, 2] + 0.5)
        core = np.hypot(c[:, 0] - 0.07, c[:, 2] + 0.55)
        low = (c[:, 1] <= 12.5) & (r < 4.0) & (c[:, 0] > -3.25)   # the boosters' height
        high = (c[:, 1] > 12.5) & (core < 2.45) & (c[:, 0] > -1.95)  # above them only the body
        return (c[:, 1] > 0.9) & (low | high)
    keep.vector = True
    cut('art/rocket/moon_rocket.glb', 'assets/props/moon_rocket_ship.glb', keep, 'ship', 'moon_rocket_map')
    rest = lambda c: ~keep(c)
    rest.vector = True
    cut('art/rocket/moon_rocket.glb', 'assets/props/moon_rocket_tower.glb', rest, 'tower', 'moon_rocket_map')  # what stays on the pad
