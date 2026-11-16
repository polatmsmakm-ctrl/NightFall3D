#!/usr/bin/env python3
"""Skin masks for the characters' subsurface scattering (NFLook.skin).

    python3 tools/skin_mask.py assets/chars/killer.glb [more.glb ...]

For every character GLB, reads its colour map (embedded, or the external file it points to) and
writes `<name>_skin.png` next to it: a 512 px grey mask, white where the colour is skin. Skin is a
warm or rosy, moderately saturated colour (red the strongest channel); strongly saturated reds (crimson cloth,
blood) and dark or grey things (hair, leather, metal) are left out. The mask is softened a little
so the effect fades in at the edges. Run it again whenever a character is re-baked: the atlas
changes with every bake.
Needs numpy, pillow and opencv.
"""
import io, json, os, struct, sys
import numpy as np
from PIL import Image
import cv2


def colour_map(path):
    data = open(path, 'rb').read()
    L = struct.unpack('<I', data[12:16])[0]
    j = json.loads(data[20:20 + L])
    binc = data[20 + L + 8:]
    mat = j['materials'][0]['pbrMetallicRoughness']
    tex = j['textures'][mat['baseColorTexture']['index']]
    im = j['images'][tex['source']]
    if 'bufferView' in im:
        bv = j['bufferViews'][im['bufferView']]
        raw = binc[bv.get('byteOffset', 0):bv.get('byteOffset', 0) + bv['byteLength']]
        return Image.open(io.BytesIO(raw)).convert('RGB')
    return Image.open(os.path.join(os.path.dirname(path), im['uri'])).convert('RGB')


def mask(img, size=512):
    a = np.asarray(img.resize((size, size), Image.LANCZOS)).astype(np.float32) / 255.0
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    hsv = cv2.cvtColor((a * 255).astype(np.uint8), cv2.COLOR_RGB2HSV).astype(np.float32)
    h, s, v = hsv[..., 0] * 2.0, hsv[..., 1] / 255.0, hsv[..., 2] / 255.0  # h in degrees
    warm = (h >= 4) & (h <= 38) & (g > b) & (s <= 0.62)          # tanned to fair skin
    pink = ((h >= 340) | (h < 4)) & (s <= 0.42) & (r - g > 0.06)  # porcelain, rosy skin
    m = ((warm | pink) & (s >= 0.11) & (v >= 0.28) & (r > g) & (r - b > 0.06)).astype(np.float32)
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))  # drop lone specks
    m = cv2.GaussianBlur(m, (0, 0), 1.5)
    return Image.fromarray((np.clip(m, 0, 1) * 255).astype(np.uint8), 'L')


if __name__ == '__main__':
    for p in sys.argv[1:]:
        out = os.path.splitext(p)[0] + '_skin.png'
        mk = mask(colour_map(p))
        mk.save(out, optimize=True)
        cover = np.asarray(mk).astype(np.float32).mean() / 255.0
        print('%s: %.1f%% of the atlas is skin -> %s' % (os.path.basename(p), cover * 100.0, out))
