#!/usr/bin/env python3
"""Shrink the textures inside a GLB without re-baking it (the UVs stay valid at any size).

    python3 tools/glb_texsize.py model.glb --max 2048 [--keep-color] [--out other.glb]

Every embedded image wider than --max is resized down to it (Lanczos) and re-encoded in its own
format (PNG stays PNG, JPEG stays JPEG). With --keep-color the base colour texture keeps its size:
it is what the eye reads; the normal, metal-rough and glow maps lose far less at half size.
Used to bring the IPA under 500 MB after the 4096 close-up bakes.
"""
import argparse, io, json, struct
from PIL import Image


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('src')
    ap.add_argument('--max', type=int, default=2048)
    ap.add_argument('--keep-color', action='store_true')
    ap.add_argument('--out')
    a = ap.parse_args()
    data = open(a.src, 'rb').read()
    L = struct.unpack('<I', data[12:16])[0]
    j = json.loads(data[20:20 + L])
    off = 20 + L
    blen = struct.unpack('<I', data[off:off + 4])[0]
    binc = data[off + 8:off + 8 + blen]
    color = set()
    for m in j.get('materials', []):
        t = m.get('pbrMetallicRoughness', {}).get('baseColorTexture')
        if t is not None: color.add(j['textures'][t['index']]['source'])
    views = j['bufferViews']
    repl = {}
    for i, im in enumerate(j.get('images', [])):
        if 'bufferView' not in im: continue
        bv = views[im['bufferView']]
        raw = binc[bv.get('byteOffset', 0):bv.get('byteOffset', 0) + bv['byteLength']]
        pic = Image.open(io.BytesIO(raw))
        if pic.width <= a.max or (a.keep_color and i in color): continue
        fmt = 'PNG' if raw[:8] == b'\x89PNG\r\n\x1a\n' else 'JPEG'
        small = pic.resize((a.max, a.max * pic.height // pic.width), Image.LANCZOS)
        out = io.BytesIO()
        if fmt == 'PNG': small.save(out, 'PNG', optimize=True)
        else: small.convert('RGB').save(out, 'JPEG', quality=92)
        repl[im['bufferView']] = out.getvalue()
        print('  image %d: %d -> %d px' % (i, pic.width, a.max))
    # rebuild the binary chunk with every view at a 4-byte aligned offset
    newbin = bytearray()
    for k, bv in enumerate(views):
        chunk = repl.get(k)
        if chunk is None: chunk = binc[bv.get('byteOffset', 0):bv.get('byteOffset', 0) + bv['byteLength']]
        while len(newbin) % 4: newbin.append(0)
        bv['byteOffset'] = len(newbin)
        bv['byteLength'] = len(chunk)
        newbin += chunk
    while len(newbin) % 4: newbin.append(0)
    j['buffers'][0]['byteLength'] = len(newbin)
    js = json.dumps(j, separators=(',', ':')).encode()
    while len(js) % 4: js += b' '
    total = 12 + 8 + len(js) + 8 + len(newbin)
    out = struct.pack('<III', 0x46546C67, 2, total) + struct.pack('<II', len(js), 0x4E4F534A) + js \
        + struct.pack('<II', len(newbin), 0x004E4942) + bytes(newbin)
    open(a.out or a.src, 'wb').write(out)
    print('%s: %.1f MB -> %.1f MB' % (a.src, len(data) / 1e6, len(out) / 1e6))


if __name__ == '__main__':
    main()
