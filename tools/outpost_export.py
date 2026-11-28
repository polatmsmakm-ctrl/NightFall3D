import numpy as np, json, struct, os
src = '/home/claude/outpost/outpost_src.glb'
out = '/home/claude/nightfall3d/assets/props/outpost'
art = '/home/claude/nightfall3d/art/outpost'
os.makedirs(out, exist_ok=True); os.makedirs(art, exist_ok=True)
raw = open(src, 'rb').read(); l = struct.unpack('<I', raw[12:16])[0]; j = json.loads(raw[20:20 + l]); b0 = 20 + l + 8
names = ['outpost_col.jpg', 'outpost_mr.png', 'outpost_nrm.png']
for k, im in enumerate(j['images']): # his three maps, byte for byte
    bv = j['bufferViews'][im['bufferView']]; o = b0 + bv.get('byteOffset', 0)
    for dst in (out, art): open(os.path.join(dst, names[k]), 'wb').write(raw[o:o + bv['byteLength']])
mat = j['materials'][0]
d = np.load('/home/claude/outpost/raw.npz'); P = d['P'].astype(np.float32); N = d['N']; UV = d['UV']; F = d['F']
lab = np.load('/home/claude/outpost/labels.npy')
def write(path, faces, texdir_rel):
    used, inv = np.unique(faces.ravel(), return_inverse=True)
    idx = inv.reshape(-1, 3).astype(np.uint32)
    p, n, uv = P[used], N[used], UV[used]
    blobs = [p.tobytes(), n.tobytes(), uv.tobytes(), idx.tobytes()]
    views, off, bin_ = [], 0, b''
    for b, tgt in zip(blobs, [34962, 34962, 34962, 34963]):
        pad = (-len(bin_)) % 4; bin_ += b'\0' * pad
        views.append({'buffer': 0, 'byteOffset': len(bin_), 'byteLength': len(b), 'target': tgt}); bin_ += b
    g = {'asset': {'version': '2.0', 'generator': 'nightfall outpost split', 'extras': {'source': 'export_Meshy_AI_2026-11-28_b7b06b.glb', 'note': 'triangles, normals and UVs exactly as in the source; positions as placed in the outpost'}},
         'scene': 0, 'scenes': [{'nodes': [0]}], 'nodes': [{'mesh': 0, 'name': os.path.basename(path)[:-4]}],
         'meshes': [{'primitives': [{'attributes': {'POSITION': 0, 'NORMAL': 1, 'TEXCOORD_0': 2}, 'indices': 3, 'material': 0}]}],
         'accessors': [{'bufferView': 0, 'componentType': 5126, 'count': len(p), 'type': 'VEC3', 'min': p.min(0).tolist(), 'max': p.max(0).tolist()},
                       {'bufferView': 1, 'componentType': 5126, 'count': len(p), 'type': 'VEC3'},
                       {'bufferView': 2, 'componentType': 5126, 'count': len(p), 'type': 'VEC2'},
                       {'bufferView': 3, 'componentType': 5125, 'count': idx.size, 'type': 'SCALAR'}],
         'bufferViews': views, 'buffers': [{'byteLength': len(bin_)}],
         'materials': [mat], 'textures': [{'source': k} for k in range(3)],
         'images': [{'uri': texdir_rel + nm} for nm in names]}
    js = json.dumps(g, separators=(',', ':')).encode(); js += b' ' * ((-len(js)) % 4); bin_ += b'\0' * ((-len(bin_)) % 4)
    total = 12 + 8 + len(js) + 8 + len(bin_)
    with open(path, 'wb') as f:
        f.write(struct.pack('<III', 0x46546C67, 2, total)); f.write(struct.pack('<II', len(js), 0x4E4F534A)); f.write(js)
        f.write(struct.pack('<II', len(bin_), 0x004E4942)); f.write(bin_)
    print('%-34s %8d tris %6.1f MB  size %s' % (os.path.basename(path), len(faces), total / 1e6, np.round(p.max(0) - p.min(0), 3)))
for nm in sorted(set(lab)):
    write(os.path.join(out, nm + '.glb'), F[lab == nm], '')
write(os.path.join(art, 'outpost_full.glb'), F, '')
