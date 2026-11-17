"""A Meshy prop (millions of triangles, one textured mesh) into a game-ready static GLB.

    python3 tools/prop_bake.py sculpt.glb assets/props/generator.glb --faces 9000 --width 2.0

Same machinery as `tools/rig_character.py --bake` (tools/rig_bake.py + tools/simplify.cpp), with no
skeleton: weld, quadric collapse to the budget, a new UV atlas, and colour, metallic-roughness and
normal baked from the full sculpt. On top of that:

  * size and placement in metres: turned by --yaw, scaled so the X extent is --width (or the
    height is --height), centred on X/Z and standing on y = 0;
  * a glow map (`--emit`): texels bright enough (and, with `--emit-red`, saturated red ones) give
    off their own colour, so lamps, flames and signs light up at night. Godot reads it as the
    material's emission texture;
  * `--split X,Y`: faces with |x| < X and y < Y become two extra meshes, `leaf_l` and `leaf_r`
    (x < 0 / x > 0), next to `frame`. The exit gate uses it: its two leaves slide apart.
  * `--wheels YF,ZF,YR,ZR,R,XIN`: a car's four wheels become their own meshes, `wheel_fl`,
    `wheel_fr`, `wheel_rl`, `wheel_rr` (front = +z, left = +x, the driver's side of a car facing
    +z), each with its node on the axle (y, z of the front/rear centre, x at the middle of the
    tyre) so the game can spin and steer it. A face is a wheel's when it lies further out than
    XIN and within R of that axle. The rest stays `frame`.

  * `--part NAME,CX,CY,CZ,R,AX,AY,AZ,T`: the faces within R of the centre and within T of the plane
    through it across the axis A become their own mesh NAME, its node on the centre (the cabin's
    steering wheel: the game turns it about A). Can be given more than once.

  * `--box NAME,X0,Y0,Z0,X1,Y1,Z1,HX,HY,HZ`: the faces inside the box become their own mesh NAME
    with its node at the hinge H (the car's driver door, which the game swings open).

Every bake writes its own command line into the GLB (asset.extras.bake), so it can be repeated.

Every mesh lands as its own node under one root, with one shared material.
Needs numpy, scipy, opencv, pillow and a C++ compiler.
"""
import argparse, io, json, os, struct, sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import rig_character as rc   # noqa: E402
import rig_bake as rb        # noqa: E402


def place(P, yaw_deg, width, height, depth=None, shift=(0.0, 0.0)):
    a = np.radians(yaw_deg)
    R = np.array([[np.cos(a), 0, np.sin(a)], [0, 1, 0], [-np.sin(a), 0, np.cos(a)]])
    P = P @ R.T
    if width:
        s = width / np.ptp(P[:, 0])
    else:
        s = height / np.ptp(P[:, 1])
    P = P * s
    P[:, 0] -= (P[:, 0].min() + P[:, 0].max()) / 2.0
    P[:, 2] -= (P[:, 2].min() + P[:, 2].max()) / 2.0
    P[:, 1] -= P[:, 1].min()
    if depth and np.ptp(P[:, 2]) > depth:   # flatten front to back (a wall seen from inside)
        P[:, 2] *= depth / np.ptp(P[:, 2])
    P[:, 0] += shift[0]
    P[:, 2] += shift[1]
    return P, s


def glow(col, v_lo, v_hi, red, white=None):
    """Emission map from the baked colour: bright texels, optionally saturated red ones, and
    optionally pale ones (`white`: a ramp on the darkest channel, so a lamp's glass lights up and
    the yellow paint next to it does not)."""
    c = col.astype(np.float32)
    v = c.max(axis=2)
    m = np.clip((v - v_lo) / max(v_hi - v_lo, 1.0), 0.0, 1.0)
    if white:
        lo, hi = white
        m = np.maximum(m, np.clip((c.min(axis=2) - lo) / max(hi - lo, 1.0), 0.0, 1.0) * (v > 175))
    if red:
        r, g, b = c[..., 0], c[..., 1], c[..., 2]
        m = np.maximum(m, np.clip((r - red) / 40.0, 0.0, 1.0) * (g < 0.45 * r) * (b < 0.5 * r))
    m = m * m * (3.0 - 2.0 * m)
    return np.clip(c * m[..., None], 0, 255).astype(np.uint8), float(m.mean())


def write_glb(path, parts, pics, emissive):
    blob = bytearray()
    views, accs = [], []

    def put(data, count, comp, typ, target=None, mn=None, mx=None):
        while len(blob) % 4:
            blob.append(0)
        views.append({'buffer': 0, 'byteOffset': len(blob), 'byteLength': len(data)})
        if target:
            views[-1]['target'] = target
        blob.extend(data)
        a = {'bufferView': len(views) - 1, 'componentType': comp, 'count': count, 'type': typ}
        if mn is not None:
            a['min'], a['max'] = mn, mx
        accs.append(a)
        return len(accs) - 1

    meshes, nodes = [], []
    for part in parts:
        name, (V, N, TAN, T, F) = part[0], part[1]
        origin = part[2] if len(part) > 2 else None
        if origin is not None:
            V = V - np.asarray(origin)
        p = put(V.astype('<f4').tobytes(), len(V), 5126, 'VEC3', 34962, V.min(0).tolist(), V.max(0).tolist())
        n = put(N.astype('<f4').tobytes(), len(N), 5126, 'VEC3', 34962)
        t = put(TAN.astype('<f4').tobytes(), len(TAN), 5126, 'VEC4', 34962)
        u = put(T.astype('<f4').tobytes(), len(T), 5126, 'VEC2', 34962)
        i = put(F.astype('<u4').reshape(-1).tobytes(), F.size, 5125, 'SCALAR', 34963)
        meshes.append({'name': name, 'primitives': [{'attributes': {'POSITION': p, 'NORMAL': n, 'TANGENT': t, 'TEXCOORD_0': u},
                                                      'indices': i, 'material': 0}]})
        nodes.append({'name': name, 'mesh': len(meshes) - 1})
        if origin is not None:
            nodes[-1]['translation'] = [float(v) for v in origin]
    images = []
    for pic in pics:
        while len(blob) % 4:
            blob.append(0)
        views.append({'buffer': 0, 'byteOffset': len(blob), 'byteLength': len(pic)})
        blob.extend(pic)
        images.append({'bufferView': len(views) - 1, 'mimeType': 'image/jpeg'})
    mat = {'name': 'prop', 'pbrMetallicRoughness': {'baseColorTexture': {'index': 0}, 'metallicRoughnessTexture': {'index': 1},
                                                    'metallicFactor': 1.0, 'roughnessFactor': 1.0},
           'normalTexture': {'index': 2}}
    if emissive:
        mat['emissiveTexture'] = {'index': 3}
        mat['emissiveFactor'] = [1.0, 1.0, 1.0]
    nodes.append({'name': 'prop', 'children': list(range(len(parts)))})
    out = {'asset': {'version': '2.0', 'generator': 'NightFall tools/prop_bake.py',
                     'extras': {'bake': ' '.join(sys.argv[1:])}},
           'scene': 0, 'scenes': [{'nodes': [len(nodes) - 1]}], 'nodes': nodes, 'meshes': meshes,
           'materials': [mat], 'samplers': [{}], 'textures': [{'source': k, 'sampler': 0} for k in range(len(images))],
           'images': images, 'bufferViews': views, 'accessors': accs, 'buffers': [{'byteLength': len(blob)}]}
    while len(blob) % 4:
        blob.append(0)
    out['buffers'][0]['byteLength'] = len(blob)
    js = json.dumps(out, separators=(',', ':')).encode()
    while len(js) % 4:
        js += b' '
    body = struct.pack('<II', len(js), 0x4E4F534A) + js + struct.pack('<II', len(blob), 0x004E4942) + bytes(blob)
    open(path, 'wb').write(struct.pack('<III', 0x46546C67, 2, 12 + len(body)) + body)


def texel_positions(V, UV, F, side):
    """Where on the model every texel of the atlas lies (NaN where no face covers it)."""
    import cv2
    fid = np.zeros((side, side), np.int32)
    tris = np.round(UV[F] * side * 16).astype(np.int32)
    for f in range(len(F)):
        cv2.fillConvexPoly(fid, tris[f], int(f + 1), shift=4)
    out = np.full((side, side, 3), np.nan, np.float32)
    ys, xs = np.nonzero(fid)
    f = fid[ys, xs] - 1
    px = UV * side
    a, b, c = px[F[f, 0]], px[F[f, 1]], px[F[f, 2]]
    q = np.column_stack([xs + 0.5, ys + 0.5])
    v0, v1, v2 = b - a, c - a, q - a
    den = v0[:, 0] * v1[:, 1] - v1[:, 0] * v0[:, 1]
    den = np.where(np.abs(den) < 1e-12, 1e-12, den)
    wb = (v2[:, 0] * v1[:, 1] - v1[:, 0] * v2[:, 1]) / den
    wc = (v0[:, 0] * v2[:, 1] - v2[:, 0] * v0[:, 1]) / den
    bary = np.clip(np.column_stack([1 - wb - wc, wb, wc]), 0, 1)
    out[ys, xs] = (V[F[f]] * bary[..., None]).sum(1)
    return out


def box_glow(em, col, pos, box, bright=110.0):
    """Everything bright enough inside `box` (x0,y0,z0,x1,y1,z1 in metres) glows in its own colour."""
    lo, hi = np.array(box[:3]), np.array(box[3:])
    inside = np.all((pos >= lo) & (pos <= hi), axis=2)
    v = col.astype(np.float32).max(axis=2)
    m = inside * np.clip((v - bright) / 60.0, 0.0, 1.0)
    return np.maximum(em, (col.astype(np.float32) * m[..., None]).astype(np.uint8))


def reglow(a):
    """New glow map for a prop this tool already wrote: no re-bake."""
    from PIL import Image
    j, b = rc.load(a.out)
    pics = []
    for im in j['images']:
        bv = j['bufferViews'][im['bufferView']]
        pics.append(bytes(b[bv.get('byteOffset', 0):bv.get('byteOffset', 0) + bv['byteLength']]))
    pics = pics[:3]
    lo, hi = (float(v) for v in a.emit.split(',')) if a.emit else (999.0, 1000.0)
    col = np.asarray(Image.open(io.BytesIO(pics[0])).convert('RGB'))
    em, cover = glow(col, lo, hi, a.emit_red, tuple(float(v) for v in a.emit_white.split(',')) if a.emit_white else None)
    parts = []
    for n in j['nodes']:
        if 'mesh' not in n:
            continue
        pr = j['meshes'][n['mesh']]['primitives'][0]
        at = pr['attributes']
        parts.append((n['name'], (rc.read_acc(j, b, at['POSITION']), rc.read_acc(j, b, at['NORMAL']), rc.read_acc(j, b, at['TANGENT']),
                                  rc.read_acc(j, b, at['TEXCOORD_0']), rc.read_acc(j, b, pr['indices'])[:, 0].astype(np.int64).reshape(-1, 3))))
    if a.emit_box:
        Vs, Us, Fs, base = [], [], [], 0
        for _, (V, N, TAN, UV, F) in parts:
            Vs.append(V); Us.append(UV); Fs.append(F + base); base += len(V)
        pos = texel_positions(np.vstack(Vs), np.vstack(Us), np.vstack(Fs), col.shape[0])
        em = box_glow(em, col, pos, [float(v) for v in a.emit_box.split(',')])
        cover = float((em.max(axis=2) > 20).mean())
    buf = io.BytesIO()
    Image.fromarray(em).save(buf, format='JPEG', quality=90)
    pics.append(buf.getvalue())
    write_glb(a.out, parts, pics, True)
    print('reglow %s: glow covers %.2f%% of the atlas' % (a.out, cover * 100))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('src')
    ap.add_argument('out')
    ap.add_argument('--faces', type=int, default=8000)
    ap.add_argument('--tex', type=int, default=1024)
    ap.add_argument('--width', type=float, default=None, help='X extent in metres after --yaw')
    ap.add_argument('--height', type=float, default=None, help='height in metres (when --width is not given)')
    ap.add_argument('--yaw', type=float, default=0.0, help='degrees about +Y before measuring')
    ap.add_argument('--depth', type=float, default=None, help='squash the Z extent down to this many metres')
    ap.add_argument('--shift', default='0,0', metavar='X,Z', help='move the origin: metres added to x and z after centring')
    ap.add_argument('--emit', default=None, metavar='LO,HI', help='glow where the brightest channel goes from LO to HI (0-255)')
    ap.add_argument('--emit-red', type=float, default=0.0, metavar='R', help='also glow saturated red above R')
    ap.add_argument('--emit-white', default=None, metavar='LO,HI', help='also glow where the darkest channel goes from LO to HI')
    ap.add_argument('--emit-box', default=None, metavar='X0,Y0,Z0,X1,Y1,Z1', help='with --reglow: bright texels inside this box (metres) glow')
    ap.add_argument('--reglow', action='store_true', help='only recompute the glow map of an existing OUT (src is ignored)')
    ap.add_argument('--split', default=None, metavar='X,Y', help='gate leaves: |x| < X and y < Y, in metres')
    ap.add_argument('--box', action='append', default=[], metavar='NAME,X0,Y0,Z0,X1,Y1,Z1,HX,HY,HZ', help='cut a box-shaped piece out, its node on the hinge (repeat a NAME to add another box to it)')
    ap.add_argument('--box-faces', type=int, default=3500, help='at least this many faces for a --box piece (a door is a small part of a car\'s area, but it is seen up close)')
    ap.add_argument('--part', action='append', default=[], metavar='NAME,CX,CY,CZ,R,AX,AY,AZ,T', help='cut a disc-shaped piece out on its own node')
    ap.add_argument('--wheels', default=None, metavar='YF,ZF,YR,ZR,R,XIN', help='a car: cut the four wheels out, each on its own axle node')
    a = ap.parse_args()
    if a.reglow:
        return reglow(a)
    if not a.width and not a.height:
        raise SystemExit('give --width or --height')
    sj, sb = rc.load(a.src)
    P, T, F = rc.mesh_of(sj, sb)
    P, s = place(P, a.yaw, a.width, a.height, a.depth, tuple(float(v) for v in a.shift.split(',')))
    print('placed: %.2f x %.2f x %.2f m (scale %.3f), %d faces' % (np.ptp(P[:, 0]), np.ptp(P[:, 1]), np.ptp(P[:, 2]), s, len(F)), flush=True)
    sculpt = rb.Sculpt(P, T, F, rb.source_images(sj, sb))
    Pw, Fw = sculpt.Pw, sculpt.Fw
    c = Pw[Fw].mean(axis=1)
    part = np.zeros(len(Fw), np.int64)
    names = ['frame']
    if a.split:
        sx, sy = (float(v) for v in a.split.split(','))
        inner = (np.abs(c[:, 0]) < sx) & (c[:, 1] < sy)
        part[inner & (c[:, 0] < 0)] = 1
        part[inner & (c[:, 0] >= 0)] = 2
        names = ['frame', 'leaf_l', 'leaf_r']
    origins = {}
    if a.wheels:
        yf, zf, yr, zr, wr, xin = (float(v) for v in a.wheels.split(','))
        names = ['frame']
        for tag, (wy, wz) in (('f', (yf, zf)), ('r', (yr, zr))):
            for side, sg in (('l', 1.0), ('r', -1.0)):
                sel = (c[:, 0] * sg > xin) & (np.hypot(c[:, 1] - wy, c[:, 2] - wz) < wr) & (part == 0)
                names.append('wheel_%s%s' % (tag, side))
                part[sel] = len(names) - 1
                xs = c[sel, 0]
                origins[names[-1]] = [float((xs.min() + xs.max()) / 2.0) if len(xs) else sg * 0.8, wy, wz]
                print('   %s: %d faces, axle at x %.2f' % (names[-1], int(sel.sum()), origins[names[-1]][0]), flush=True)
    for spec in a.part:
        bits = spec.split(',')
        nm, v = bits[0], np.array([float(x) for x in bits[1:]])
        cen, rad, ax, th = v[0:3], v[3], v[4:7] / np.linalg.norm(v[4:7]), v[7]
        sel = (np.linalg.norm(c - cen, axis=1) < rad) & (np.abs((c - cen) @ ax) < th) & (part == 0)
        names.append(nm)
        part[sel] = len(names) - 1
        origins[nm] = [float(x) for x in cen]
        print('   %s: %d faces' % (nm, int(sel.sum())), flush=True)
    box_names = set()
    for spec in a.box:
        bits = spec.split(',')
        nm, v = bits[0], np.array([float(x) for x in bits[1:]])
        lo, hi, hinge = v[0:3], v[3:6], v[6:9]
        sel = np.all((c >= lo) & (c <= hi), axis=1) & (part == 0)
        box_names.add(nm)
        if nm not in names: names.append(nm)   # a second box with the same name adds to that piece
        part[sel] = names.index(nm)
        origins[nm] = [float(x) for x in hinge]
        print('   %s: %d faces' % (nm, int(sel.sum())), flush=True)
    area = np.linalg.norm(np.cross(Pw[Fw[:, 1]] - Pw[Fw[:, 0]], Pw[Fw[:, 2]] - Pw[Fw[:, 0]]), axis=1)
    share = np.array([area[part == k].sum() for k in range(len(names))])
    share = share / share.sum()
    Vs, Gs, ids = [], [], []
    base = 0
    for k, nm in enumerate(names):
        G0 = Fw[part == k]
        target = max(int(a.faces * share[k]), a.box_faces if nm in box_names else 200)
        V, G = rb.simplify(Pw, G0, np.zeros(len(G0), np.uint8), [target], np.ones(len(Pw), np.float32),
                           np.zeros(len(Pw), np.uint8), maxlen=1e9)
        print('   %s: %d -> %d faces' % (nm, len(G0), len(G)), flush=True)
        Vs.append(V)
        Gs.append(G + base)
        ids.append(np.full(len(G), k))
        base += len(V)
    V, G, fid = np.vstack(Vs), np.vstack(Gs), np.concatenate(ids)
    N = rb.vertex_normals(V, G)
    side = max(a.tex, 2048)
    vmap, UV, F2 = rb.unwrap(V, G, side, np.ones(len(G)), pad=2 * side // 1024, cell=2 * side // 1024)
    V2, N2 = V[vmap], N[vmap]
    TAN = rb.tangents(V2, N2, UV, F2)
    pics = rb.bake(V2, N2, UV, F2, TAN, sculpt, side, a.tex)
    from PIL import Image
    emissive = False
    if a.emit or a.emit_red or a.emit_white:
        lo, hi = (float(v) for v in a.emit.split(',')) if a.emit else (999.0, 1000.0)
        col = np.asarray(Image.open(io.BytesIO(pics[0])).convert('RGB'))
        em, cover = glow(col, lo, hi, a.emit_red, tuple(float(v) for v in a.emit_white.split(',')) if a.emit_white else None)
        buf = io.BytesIO()
        Image.fromarray(em).save(buf, format='JPEG', quality=90)
        pics.append(buf.getvalue())
        emissive = True
        print('   glow covers %.1f%% of the atlas' % (cover * 100), flush=True)
    if len(pics) < 3 + emissive:   # no metallic-roughness in the source: a plain rough one
        buf = io.BytesIO()
        Image.new('RGB', (8, 8), (0, 230, 0)).save(buf, format='JPEG')
        pics.insert(1, buf.getvalue())
    parts = []
    for k, nm in enumerate(names):
        fk = F2[fid == k]
        used, local = np.unique(fk.reshape(-1), return_inverse=True)
        parts.append((nm, (V2[used], N2[used], TAN[used], UV[used], local.reshape(-1, 3)), origins.get(nm)))
    write_glb(a.out, parts, pics, emissive)
    print('wrote %s: %.2f MB, %d faces' % (a.out, os.path.getsize(a.out) / 1e6, len(F2)), flush=True)


if __name__ == '__main__':
    main()
