#!/usr/bin/env python3
"""Split the car-park GLB into named pieces so the garage map can place them tile by tile.

The uploaded model (CC0, Innerscene Corp) is one 30 x 20 m car-park module whose walls,
columns and lift core all live in a single mesh. The garage map repeats the module in a
grid, and it needs to leave out a wall here and a core there so the bays join up, so each
connected lump of geometry becomes its own node:

  slab aisle paint detail doors lift core wall_s north_block cols

Vertices are not touched: every piece reuses the original POSITION/NORMAL/UV accessors and
only gets its own index list, so the file barely grows.

    python3 tools/split_glb.py in.glb assets/maps/carpark.glb
"""
import json, struct, sys

JSON_CHUNK, BIN_CHUNK = 0x4E4F534A, 0x004E4942
CT = {5120: ('b', 1), 5121: ('B', 1), 5122: ('h', 2), 5123: ('H', 2), 5125: ('I', 4), 5126: ('f', 4)}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}


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


def read(j, blob, ai):
    a = j['accessors'][ai]
    bv = j['bufferViews'][a['bufferView']]
    fmt, sz = CT[a['componentType']]
    n = NC[a['type']]
    start = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    stride = bv.get('byteStride') or sz * n
    return [struct.unpack_from('<' + fmt * n, blob, start + i * stride) for i in range(a['count'])]


def pieces_of(j, blob, mi):
    """Connected lumps of mesh `mi`, as lists of triangles (index triples)."""
    pr = j['meshes'][mi]['primitives'][0]
    pos = read(j, blob, pr['attributes']['POSITION'])
    idx = [x[0] for x in read(j, blob, pr['indices'])]
    par = list(range(len(pos)))

    def find(a):
        while par[a] != a:
            par[a] = par[par[a]]
            a = par[a]
        return a

    def join(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            par[ra] = rb

    seen = {}
    for i, v in enumerate(pos):          # weld split vertices first
        k = tuple(round(c, 4) for c in v)
        if k in seen:
            join(i, seen[k])
        else:
            seen[k] = i
    for t in range(0, len(idx), 3):
        join(idx[t], idx[t + 1])
        join(idx[t + 1], idx[t + 2])
    groups = {}
    for t in range(0, len(idx), 3):
        groups.setdefault(find(idx[t]), []).extend(idx[t:t + 3])
    out = []
    for tris in groups.values():
        lo = [min(pos[i][k] for i in tris) for k in range(3)]
        hi = [max(pos[i][k] for i in tris) for k in range(3)]
        out.append({'tris': tris, 'lo': lo, 'hi': hi})
    return out


def main(src, dst):
    j, blob = load(src)
    root = next((n for n in j['nodes'] if n.get('mesh') is None), {})
    shift = root.get('translation', [0, 0, 0])
    parts = {}     # name -> [(mesh index, [indices])]

    def add(name, mi, tris):
        parts.setdefault(name, []).append((mi, tris))

    for mi, m in enumerate(j['meshes']):
        label = m['name'].lower()
        if 'aisle' in label:
            name = 'aisle'
        elif 'bay lines' in label:
            name = 'paint'
        elif 'core doors' in label:
            name = 'doors'
        elif 'lift doors' in label:
            name = 'lift'
        elif 'wheel stops' in label:
            name = 'detail'
        else:
            name = None
        if name:                                   # whole mesh, one piece
            pr = j['meshes'][mi]['primitives'][0]
            add(name, mi, [x[0] for x in read(j, blob, pr['indices'])])
            continue
        for p in pieces_of(j, blob, mi):           # split by where the lump sits
            lo, hi = p['lo'], p['hi']
            w, h, d = hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2]
            if 'floor slab' in label:
                add('slab' if h < 1.0 else 'north_block', mi, p['tris'])
            elif w < 1.0 and d < 1.0:
                add('cols', mi, p['tris'])          # a column or a pilaster
            elif w < 10.0 and d > 10.0:
                add('core', mi, p['tris'])          # the stair / lift core, 5 x 20 m
            elif d < 1.0 and lo[2] < -19.0:
                add('wall_s', mi, p['tris'])        # the south retaining wall
            else:
                add('north_block', mi, p['tris'])   # the plant-room walls
    # rebuild the file: same vertices, new index lists, one node per piece.
    # The embedded textures are near-flat 2048 colour maps; a phone does not want seven of
    # those in memory for one repeated module, so they are re-encoded small on the way out.
    out = dict(j)
    out['meshes'] = []
    out['nodes'] = []
    small = {}
    for i, im in enumerate(out.get('images', [])):
        bv = j['bufferViews'][im['bufferView']]
        raw = blob[bv.get('byteOffset', 0):bv.get('byteOffset', 0) + bv['byteLength']]
        try:
            from PIL import Image
            from io import BytesIO
            pic = Image.open(BytesIO(raw))
            side = 512 if len(raw) > 200000 else 256
            if pic.width > side:
                pic = pic.resize((side, side), Image.LANCZOS)
                buf = BytesIO()
                pic.save(buf, format='PNG', optimize=True)
                small[im['bufferView']] = buf.getvalue()
        except Exception as e:
            print('image', i, 'left as it is:', e)
    extra = bytearray()
    views = []
    for vi, bv in enumerate(j['bufferViews']):          # repack, dropping the big images
        data = small.get(vi) or blob[bv.get('byteOffset', 0):bv.get('byteOffset', 0) + bv['byteLength']]
        nv = dict(bv)
        nv['byteOffset'] = len(extra)
        nv['byteLength'] = len(data)
        views.append(nv)
        extra += data
        while len(extra) % 4:
            extra.append(0)
    out['bufferViews'] = views
    for name, chunks in parts.items():
        merged = {}                                  # one primitive per source mesh: fewer draw calls
        for mi, tris in chunks:
            merged.setdefault(mi, []).extend(tris)
        prims = []
        for mi, tris in merged.items():
            src_pr = j['meshes'][mi]['primitives'][0]
            data = struct.pack('<%dI' % len(tris), *tris)
            bv = {'buffer': 0, 'byteOffset': len(extra), 'byteLength': len(data), 'target': 34963}
            extra += data
            while len(extra) % 4:
                extra.append(0)
            out['bufferViews'].append(bv)
            out['accessors'].append({'bufferView': len(out['bufferViews']) - 1, 'componentType': 5125,
                                     'count': len(tris), 'type': 'SCALAR'})
            prims.append({'attributes': src_pr['attributes'], 'indices': len(out['accessors']) - 1,
                          'material': src_pr['material']})
        out['meshes'].append({'name': name, 'primitives': prims})
        out['nodes'].append({'name': name, 'mesh': len(out['meshes']) - 1, 'translation': shift})
    out['scenes'] = [{'name': 'carpark', 'nodes': list(range(len(out['nodes'])))}]
    out['scene'] = 0
    out['buffers'] = [{'byteLength': len(extra)}]
    js = json.dumps(out, separators=(',', ':')).encode()
    while len(js) % 4:
        js += b' '
    body = (struct.pack('<II', len(js), JSON_CHUNK) + js +
            struct.pack('<II', len(extra), BIN_CHUNK) + bytes(extra))
    open(dst, 'wb').write(struct.pack('<III', 0x46546C67, 2, 12 + len(body)) + body)
    for name, chunks in parts.items():
        print('%-12s %d tris' % (name, sum(len(t) // 3 for _, t in chunks)))
    print('wrote', dst, len(body) + 12, 'bytes')


main(sys.argv[1], sys.argv[2])
