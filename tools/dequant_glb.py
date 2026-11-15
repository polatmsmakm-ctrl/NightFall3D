#!/usr/bin/env python3
"""Turn a KHR_mesh_quantization glTF into a plain one Godot 4.5 can import.

The beach model arrived with its vertex data packed into normalized shorts and the extension
listed as *required*, which this Godot build refuses to load. Nothing about the model changes
here: every quantized attribute is expanded to float32 exactly as the glTF spec says
(normalized SHORT -> max(c / 32767, -1), USHORT -> c / 65535, and so on), de-interleaved into
its own tightly packed buffer view, and the extension is dropped.

    python3 tools/dequant_glb.py in.glb out.glb
"""
import json, struct, sys

JSON_CHUNK, BIN_CHUNK = 0x4E4F534A, 0x004E4942
COMP = {5120: ('b', 1), 5121: ('B', 1), 5122: ('h', 2), 5123: ('H', 2), 5125: ('I', 4), 5126: ('f', 4)}
NCOMP = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}
DENOM = {5120: 127.0, 5121: 255.0, 5122: 32767.0, 5123: 65535.0}


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


def main(src, dst):
    j, blob = load(src)
    out = bytearray(blob)
    while len(out) % 4:
        out.append(0)
    touched = 0
    wanted = set()
    for m in j.get('meshes', []):
        for pr in m['primitives']:
            wanted.update(pr['attributes'].values())
            for tgt in pr.get('targets', []):
                wanted.update(tgt.values())
    for ai in sorted(wanted):
        a = j['accessors'][ai]
        ct = a['componentType']
        if ct == 5126:                      # already float: leave it alone
            continue
        fmt, size = COMP[ct]
        n = NCOMP[a['type']]
        bv = j['bufferViews'][a['bufferView']]
        start = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
        stride = bv.get('byteStride') or size * n
        vals = []
        for i in range(a['count']):
            raw = struct.unpack_from('<' + fmt * n, blob, start + i * stride)
            if a.get('normalized'):
                d = DENOM[ct]
                raw = tuple(max(c / d, -1.0) if ct in (5120, 5122) else c / d for c in raw)
            else:
                raw = tuple(float(c) for c in raw)
            vals.append(raw)
        data = b''.join(struct.pack('<' + 'f' * n, *v) for v in vals)
        j['bufferViews'].append({'buffer': 0, 'byteOffset': len(out), 'byteLength': len(data),
                                 'target': bv.get('target', 34962)})
        out += data
        while len(out) % 4:
            out.append(0)
        a['bufferView'] = len(j['bufferViews']) - 1
        a['byteOffset'] = 0
        a['componentType'] = 5126
        a.pop('normalized', None)
        a['min'] = [min(v[k] for v in vals) for k in range(n)]
        a['max'] = [max(v[k] for v in vals) for k in range(n)]
        touched += 1
    for key in ('extensionsRequired', 'extensionsUsed'):
        if key in j:
            j[key] = [e for e in j[key] if e != 'KHR_mesh_quantization']
            if not j[key]:
                del j[key]
    j['buffers'] = [{'byteLength': len(out)}]
    js = json.dumps(j, separators=(',', ':')).encode()
    while len(js) % 4:
        js += b' '
    body = (struct.pack('<II', len(js), JSON_CHUNK) + js +
            struct.pack('<II', len(out), BIN_CHUNK) + bytes(out))
    open(dst, 'wb').write(struct.pack('<III', 0x46546C67, 2, 12 + len(body)) + body)
    print('expanded %d attributes, wrote %s (%d bytes)' % (touched, dst, 12 + len(body)))


main(sys.argv[1], sys.argv[2])
