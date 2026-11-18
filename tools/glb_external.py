#!/usr/bin/env python3
"""Move a GLB's embedded maps out beside it, byte for byte, so Godot imports them with our settings.

    python3 tools/glb_external.py assets/chars/killer.glb [more.glb ...]

Embedded glTF images are imported with Godot's defaults: VRAM compression at normal quality, which
is ETC2 on the iPhone (blocky on normal maps and soft gradients on skin). Moved out as files
(`<stem>_col.jpg`, `<stem>_mr.jpg`, `<stem>_nrm.jpg`, ...; the original bytes, nothing re-encoded,
so the repository does not grow) with the GLB pointing at them by `uri`, each file carries a
committed `.import`: colour and normal at `compress/high_quality=true` (ASTC 4x4 on the iPhone,
BC7 on desktop), the normal map flagged as one, the metallic-roughness map at normal quality
(it shows little and is the biggest saving), mipmaps on, never shrunk. A GLB already pointing at
files is left alone.
"""
import json
import os
import struct
import sys


def write_import(path, normal=False, high=True):
    with open(path + '.import', 'w') as fh:
        fh.write('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\n'
                 'compress/mode=2\ncompress/high_quality=%s\ncompress/lossy_quality=1.0\n'
                 'compress/hdr_compression=1\ncompress/normal_map=%d\ncompress/channel_pack=0\n'
                 'mipmaps/generate=true\nmipmaps/limit=-1\nroughness/mode=0\nroughness/src_normal=""\n'
                 'process/fix_alpha_border=true\nprocess/premult_alpha=false\n'
                 'process/normal_map_invert_y=false\nprocess/hdr_as_srgb=false\n'
                 'process/hdr_clamp_exposure=false\nprocess/size_limit=0\ndetect_3d/compress_to=0\n'
                 % ('true' if high else 'false', 1 if normal else 2))


def roles(j):
    """image index -> 'col' / 'mr' / 'nrm' / 'occ' / 'emit' from how the materials use it."""
    tex_img = {i: t.get('source') for i, t in enumerate(j.get('textures', []))}
    out = {}
    for m in j.get('materials', []):
        pbr = m.get('pbrMetallicRoughness', {})
        for key, role in [(pbr.get('baseColorTexture'), 'col'), (pbr.get('metallicRoughnessTexture'), 'mr'),
                          (m.get('normalTexture'), 'nrm'), (m.get('occlusionTexture'), 'occ'),
                          (m.get('emissiveTexture'), 'emit')]:
            if key is not None and tex_img.get(key.get('index')) is not None:
                out.setdefault(tex_img[key['index']], role)
    return out


def externalise(path):
    d = open(path, 'rb').read()
    jl = struct.unpack('<I', d[12:16])[0]
    j = json.loads(d[20:20 + jl])
    rest = d[20 + jl:]
    bl = struct.unpack('<I', rest[0:4])[0]
    blob = rest[8:8 + bl]
    imgs = j.get('images', [])
    if not imgs or all('uri' in im for im in imgs):
        print('%s: nothing embedded' % path)
        return
    rl = roles(j)
    stem = os.path.splitext(os.path.basename(path))[0]
    folder = os.path.dirname(os.path.abspath(path))
    moved = set()
    used = {}
    for i, im in enumerate(imgs):
        if 'uri' in im:
            continue
        bv = j['bufferViews'][im['bufferView']]
        o = bv.get('byteOffset', 0)
        raw = blob[o:o + bv['byteLength']]
        ext = '.png' if im.get('mimeType') == 'image/png' or raw[:4] == b'\x89PNG' else '.jpg'
        role = rl.get(i, str(i))
        used[role] = used.get(role, 0) + 1
        name = '%s_%s%s%s' % (stem, role, '' if used[role] == 1 else str(used[role]), ext)
        with open(os.path.join(folder, name), 'wb') as fh:
            fh.write(raw)
        write_import(os.path.join(folder, name), normal=(role == 'nrm'), high=(role != 'mr'))
        moved.add(im['bufferView'])
        imgs[i] = {'uri': name}
        print('   %s -> %s (%d KB)' % (path, name, len(raw) // 1024))
    # rebuild the binary chunk without the image bytes, and renumber the buffer views
    keep = [k for k in range(len(j['bufferViews'])) if k not in moved]
    remap = {old: new for new, old in enumerate(keep)}
    nb = bytearray()
    views = []
    for k in keep:
        bv = dict(j['bufferViews'][k])
        o = bv.get('byteOffset', 0)
        while len(nb) % 4:
            nb.append(0)
        bv['byteOffset'] = len(nb)
        nb.extend(blob[o:o + bv['byteLength']])
        views.append(bv)
    j['bufferViews'] = views
    for a in j.get('accessors', []):
        if 'bufferView' in a:
            a['bufferView'] = remap[a['bufferView']]
    for im in imgs:
        if 'bufferView' in im:
            im['bufferView'] = remap[im['bufferView']]
    while len(nb) % 4:
        nb.append(0)
    j['buffers'] = [{'byteLength': len(nb)}]
    js = json.dumps(j, separators=(',', ':')).encode()
    while len(js) % 4:
        js += b' '
    out = bytearray(b'glTF') + struct.pack('<II', 2, 12 + 8 + len(js) + 8 + len(nb))
    out += struct.pack('<I', len(js)) + b'JSON' + js
    out += struct.pack('<I', len(nb)) + b'BIN\x00' + nb
    with open(path, 'wb') as fh:
        fh.write(out)
    print('%s: %d maps moved out, GLB now %d KB' % (path, len(moved), len(out) // 1024))


if __name__ == '__main__':
    for p in sys.argv[1:]:
        externalise(p)
