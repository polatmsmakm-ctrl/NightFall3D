"""His Blue Marble cut into the twelve pieces the defeat ending breaks it into: every triangle goes to
the piece whose seed direction is nearest its middle, nothing is dropped or changed (positions,
normals, UVs as they were), the maps stay the ones beside it.
python3 tools/earth_split.py assets/props/space/earth.glb assets/props/space/earth_pieces.glb"""
import sys, json, struct, numpy as np
sys.path.insert(0, 'tools')
from glb_cut import load, acc

# the same twelve directions as NFEnding.SEEDS (an icosahedron's corners, turned a little)
def seeds():
    t = (1 + 5 ** 0.5) / 2
    v = np.array([[-1, t, 0], [1, t, 0], [-1, -t, 0], [1, -t, 0], [0, -1, t], [0, 1, t], [0, -1, -t], [0, 1, -t],
                  [t, 0, -1], [t, 0, 1], [-t, 0, -1], [-t, 0, 1]], float)
    a, b = 0.37, 0.21 # a turn so no crack runs along the equator
    rx = np.array([[1, 0, 0], [0, np.cos(a), -np.sin(a)], [0, np.sin(a), np.cos(a)]])
    ry = np.array([[np.cos(b), 0, np.sin(b)], [0, 1, 0], [-np.sin(b), 0, np.cos(b)]])
    v = v @ rx.T @ ry.T
    return v / np.linalg.norm(v, axis=1, keepdims=True)

def main(src, dst):
    j, b = load(src)
    prim = j['meshes'][0]['primitives'][0]
    F = acc(j, b, prim['indices'])[:, 0].astype(np.int64).reshape(-1, 3)
    attrs = {k: acc(j, b, v) for k, v in prim['attributes'].items()}
    P = attrs['POSITION']
    c = P[F].mean(1)
    c = c - P.mean(0)
    c /= np.linalg.norm(c, axis=1, keepdims=True)
    S = seeds()
    which = np.argmax(c @ S.T, axis=1)
    out = b''; views = []; accs = []; meshes = []; nodes = []
    def add(arr, target, typ, comp):
        nonlocal out
        out += b'\0' * ((-len(out)) % 4)
        views.append({'buffer': 0, 'byteOffset': len(out), 'byteLength': arr.nbytes, 'target': target})
        out += arr.tobytes()
        a = {'bufferView': len(views) - 1, 'componentType': comp, 'count': arr.shape[0], 'type': typ}
        if typ == 'VEC3' and comp == 5126: a['min'] = arr.min(0).tolist(); a['max'] = arr.max(0).tolist()
        accs.append(a); return len(accs) - 1
    for k in range(12):
        Fk = F[which == k]
        used, inv = np.unique(Fk.ravel(), return_inverse=True)
        na = {}
        for an, v in attrs.items():
            arr = np.ascontiguousarray(v[used].astype(np.float32))
            na[an] = add(arr, 34962, {1: 'SCALAR', 2: 'VEC2', 3: 'VEC3', 4: 'VEC4'}[arr.shape[1]], 5126)
        idx = np.ascontiguousarray(inv.reshape(-1, 1).astype(np.uint32))
        ii = add(idx, 34963, 'SCALAR', 5125)
        meshes.append({'primitives': [{'attributes': na, 'indices': ii, 'material': 0}]})
        nodes.append({'name': 'piece%d' % k, 'mesh': k})
        print('piece %d: %d triangles' % (k, len(Fk)))
    g = {'asset': {'version': '2.0', 'generator': 'nightfall earth_split', 'extras': {'from': src.split('/')[-1]}},
         'scene': 0, 'scenes': [{'nodes': list(range(12))}], 'nodes': nodes, 'meshes': meshes,
         'accessors': accs, 'bufferViews': views, 'buffers': [{'byteLength': len(out) + (-len(out)) % 4}],
         'materials': j['materials'], 'textures': j.get('textures', []), 'images': j.get('images', [])}
    if j.get('samplers'): g['samplers'] = j['samplers']
    js = json.dumps(g, separators=(',', ':')).encode(); js += b' ' * ((-len(js)) % 4); out += b'\0' * ((-len(out)) % 4)
    with open(dst, 'wb') as f:
        f.write(struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(out)))
        f.write(struct.pack('<II', len(js), 0x4E4F534A)); f.write(js); f.write(struct.pack('<II', len(out), 0x004E4942)); f.write(out)
    print('%s: %d triangles in 12 pieces (of %d)' % (dst, sum(1 for _ in F), len(F)))
    print('seeds', np.round(S, 4).tolist())

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
