#!/usr/bin/env python3
"""Turn a textured but *unrigged* sculpt into a playable NightFall character.

The models Rashid makes come out of Meshy with half a million triangles, real textures and no
skeleton at all, so the game cannot animate them. This script does the three jobs that stand
between the sculpt and the round:

  1. puts the mesh in the same space as the characters already in the game (feet on the floor,
     same height, same facing),
  2. decimates it to a face count a phone can draw, keeping the UVs so the sculpt's own colour,
     normal and roughness maps still line up,
  3. binds it to the skeleton of a character that is already rigged: every vertex is weighted to
     the bones nearest to it, so the Mixamo clips in assets/anims drive it with no extra work.

The donor's joints, their hierarchy and its inverse bind matrices are copied over untouched, so
the result sits in exactly the same bind pose as the rest of the cast.

    python3 tools/rig_character.py sculpt.glb assets/chars/survivor2.glb out.glb --faces 26000

A sculpt has to be in a T-pose for this to look right: the bind pose is the donor's.
"""
import argparse, io, json, struct, sys
import numpy as np

JSON_CHUNK, BIN_CHUNK = 0x4E4F534A, 0x004E4942
COMP = {5120: ('b', 1), 5121: ('B', 1), 5122: ('h', 2), 5123: ('H', 2), 5125: ('I', 4), 5126: ('f', 4)}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}


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


def read_acc(j, blob, ai):
    a = j['accessors'][ai]
    fmt, size = COMP[a['componentType']]
    n = NC[a['type']]
    bv = j['bufferViews'][a['bufferView']]
    start = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    stride = bv.get('byteStride') or size * n
    if stride == size * n:
        arr = np.frombuffer(blob, dtype=np.dtype('<' + fmt), count=a['count'] * n, offset=start)
        return arr.reshape(a['count'], n).astype(np.float64 if fmt == 'f' else np.int64)
    out = np.empty((a['count'], n), dtype=np.float64 if fmt == 'f' else np.int64)
    for i in range(a['count']):
        out[i] = struct.unpack_from('<' + fmt * n, blob, start + i * stride)
    return out


def mesh_of(j, blob):
    """Every primitive of every mesh, welded into one array set (positions, uvs, faces)."""
    P, T, F = [], [], []
    base = 0
    for m in j['meshes']:
        for pr in m['primitives']:
            pos = read_acc(j, blob, pr['attributes']['POSITION'])
            uv = (read_acc(j, blob, pr['attributes']['TEXCOORD_0'])
                  if 'TEXCOORD_0' in pr['attributes'] else np.zeros((len(pos), 2)))
            idx = read_acc(j, blob, pr['indices'])[:, 0].astype(np.int64)
            P.append(pos)
            T.append(uv)
            F.append(idx.reshape(-1, 3) + base)
            base += len(pos)
    return np.vstack(P), np.vstack(T), np.vstack(F)


def rot_between(a, b):
    """The rotation matrix that turns direction a into direction b."""
    a = a / max(np.linalg.norm(a), 1e-9)
    b = b / max(np.linalg.norm(b), 1e-9)
    v = np.cross(a, b)
    c = float(a @ b)
    if np.linalg.norm(v) < 1e-9:
        return np.eye(3) if c > 0 else -np.eye(3)
    vx = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + vx + vx @ vx * (1.0 / (1.0 + c))


def fit_arms(P, dP, names, world):
    """Lay the donor's arm bones along the sculpt's own arms.

    A sculpt is never in exactly the donor's T-pose — this one's arms hang a few degrees lower
    and are shorter — and binding a mesh to a skeleton that does not lie inside it is what makes
    shoulders pinch and forearms stretch when a clip plays. So the arm chain is rotated about the
    shoulder onto the direction the sculpt's own arm points, and stretched to reach its hand.
    Everything else (spine, legs, head) already matches once the heights are the same.
    """
    idx = {n: i for i, n in enumerate(names)}
    for side, sign in (("Left", 1.0), ("Right", -1.0)):
        chain = ["%sArm" % side, "%sForeArm" % side, "%sHand" % side]
        if not all(("mixamorig:" + c) in idx for c in chain):
            continue
        ids = [idx["mixamorig:" + c] for c in chain]
        shoulder = world[ids[0]][:3, 3]
        # the furthest vertex out on this side is the fingertip, in both meshes. Comparing the
        # sculpt's fingertip with the donor's fingertip (not with the donor's wrist *joint*) is
        # what makes the arm bones end up the right length inside this body.
        def far_tip(points):
            band = points[(np.abs(points[:, 1] - shoulder[1]) < 0.45) &
                          (points[:, 0] * sign > abs(shoulder[0]))]
            return None if len(band) < 20 else band[np.argmax(band[:, 0] * sign)]
        tip = far_tip(P)
        donor_tip = far_tip(dP)
        if tip is None or donor_tip is None:
            continue
        old_dir = world[ids[2]][:3, 3] - shoulder
        new_dir = tip - shoulder
        stretch = float(np.linalg.norm(new_dir) / max(np.linalg.norm(donor_tip - shoulder), 1e-6))
        R = rot_between(donor_tip - shoulder, new_dir)
        print("  %s arm: %.1f deg off, length x%.3f" % (
            side, np.degrees(np.arccos(np.clip(np.dot(old_dir / np.linalg.norm(old_dir),
                                                      new_dir / np.linalg.norm(new_dir)), -1, 1))), stretch))
        for ji in ids:
            w = world[ji].copy()
            w[:3, 3] = shoulder + R @ (w[:3, 3] - shoulder) * stretch
            w[:3, :3] = R @ w[:3, :3]
            world[ji] = w
    return world


def donor_skeleton(j, blob):
    """The donor's joints: their position in mesh space and which joint each one hangs from."""
    sk = j['skins'][0]
    ibm = read_acc(j, blob, sk['inverseBindMatrices']).reshape(-1, 4, 4)
    world = np.array([np.linalg.inv(m.T) for m in ibm])
    pos = world[:, :3, 3]
    parent = {}
    for i, n in enumerate(j['nodes']):
        for c in n.get('children', []):
            parent[c] = i
    order = {node: k for k, node in enumerate(sk['joints'])}
    links = []                                   # (bone joint, tip position)
    for k, node in enumerate(sk['joints']):
        kids = [c for c in j['nodes'][node].get('children', []) if c in order]
        if kids:
            for c in kids:
                links.append((k, pos[order[c]]))
        else:                                    # a tip bone: carry on the way it was pointing
            p = parent.get(node)
            back = pos[order[p]] if p in order else pos[k] - np.array([0, 0.1, 0])
            links.append((k, pos[k] + (pos[k] - back) * 0.6))
    return pos, links, world, [j['nodes'][n].get('name', '') for n in sk['joints']]


def rebuild_links(j, world):
    """Bone segments again, now that the arms have been moved onto the sculpt."""
    sk = j['skins'][0]
    order = {node: k for k, node in enumerate(sk['joints'])}
    parent = {}
    for i, n in enumerate(j['nodes']):
        for c in n.get('children', []):
            parent[c] = i
    out = []
    for k, node in enumerate(sk['joints']):
        kids = [c for c in j['nodes'][node].get('children', []) if c in order]
        if kids:
            for c in kids:
                out.append((k, world[order[c]][:3, 3]))
        else:
            p = parent.get(node)
            back = world[order[p]][:3, 3] if p in order else world[k][:3, 3] - np.array([0, 0.1, 0])
            out.append((k, world[k][:3, 3] + (world[k][:3, 3] - back) * 0.6))
    return out


def seg_distance(points, a, b):
    ab = b - a
    t = np.clip(((points - a) @ ab) / max(float(ab @ ab), 1e-9), 0.0, 1.0)
    proj = a + t[:, None] * ab
    return np.linalg.norm(points - proj, axis=1)


def skin_weights(points, pos, links, influences=4):
    """Weight every vertex to the bones nearest to it (inverse square of the distance)."""
    d = np.stack([seg_distance(points, pos[j], tip) for j, tip in links], axis=1)
    joints = np.array([j for j, _ in links])
    order = np.argsort(d, axis=1)[:, :influences]
    near = np.take_along_axis(d, order, axis=1)
    w = 1.0 / np.maximum(near, 1e-4) ** 2
    w *= (near <= (near[:, :1] * 3.0 + 0.02))    # ignore bones much further than the closest one
    w /= w.sum(axis=1, keepdims=True)
    return joints[order].astype(np.uint16), w.astype(np.float32)


def decimate(P, T, F, faces):
    import pymeshlab
    ms = pymeshlab.MeshSet()
    ms.add_mesh(pymeshlab.Mesh(vertex_matrix=P, face_matrix=F, v_tex_coords_matrix=T))
    if len(F) > faces: # the texture-aware collapse keeps the UVs lined up with the sculpt's maps
        ms.compute_texcoord_transfer_vertex_to_wedge() # the filter wants them per wedge
        # UV seams are boundaries, and a sculpt is mostly seams: preserving them stops the
        # collapse dead, so they are allowed to move and the texture weight carries the UVs
        for attempt in range(3):
            if ms.current_mesh().face_number() <= faces * 1.08: break
            ms.meshing_decimation_quadric_edge_collapse_with_texture(
                targetfacenum=int(faces), preserveboundary=False, preservenormal=True,
                planarquadric=True, qualitythr=0.3, extratcoordw=0.6 + attempt * 0.4)
        ms.compute_texcoord_transfer_wedge_to_vertex()
    ms.compute_normal_per_vertex()
    m = ms.current_mesh()
    return (np.asarray(m.vertex_matrix()), np.asarray(m.vertex_tex_coord_matrix()),
            np.asarray(m.face_matrix()), np.asarray(m.vertex_normal_matrix()))


def shrink_images(j, blob, side):
    """Re-encode the sculpt's maps so a phone can hold them."""
    from PIL import Image
    out = []
    for im in j.get('images', []):
        bv = j['bufferViews'][im['bufferView']]
        raw = blob[bv.get('byteOffset', 0):bv.get('byteOffset', 0) + bv['byteLength']]
        pic = Image.open(io.BytesIO(raw)).convert('RGB')
        if pic.width > side:
            pic = pic.resize((side, side), Image.LANCZOS)
        buf = io.BytesIO()
        pic.save(buf, format='JPEG', quality=88, optimize=True)
        out.append(buf.getvalue())
    return out


def build(src, donor, out_path, faces, tex_side, flip, scale_fix):
    sj, sb = load(src)
    dj, db = load(donor)
    P, T, F = mesh_of(sj, sb)
    dP, _, _ = mesh_of(dj, db)
    dP_fitted = dP
    # ---- 1. the same space as the cast: feet on the floor, same height, same way round ----
    if flip:
        P[:, 0] *= -1.0
        P[:, 2] *= -1.0
        F = F[:, ::-1]
    s = (dP[:, 1].max() - dP[:, 1].min()) / (P[:, 1].max() - P[:, 1].min()) * scale_fix
    P = P * s
    P[:, 0] -= (P[:, 0].max() + P[:, 0].min()) / 2.0 - (dP[:, 0].max() + dP[:, 0].min()) / 2.0
    P[:, 2] -= (P[:, 2].max() + P[:, 2].min()) / 2.0 - (dP[:, 2].max() + dP[:, 2].min()) / 2.0
    P[:, 1] -= P[:, 1].min() - dP[:, 1].min()
    print('scaled by %.4f -> height %.3f m, span %.3f m' % (s, P[:, 1].max() - P[:, 1].min(),
                                                            P[:, 0].max() - P[:, 0].min()))
    # ---- 2. down to a face count a phone can draw ----
    P, T, F, N = decimate(P, T, F, faces)
    print('mesh: %d faces, %d vertices' % (len(F), len(P)))
    # ---- 3. bind it to the donor's skeleton, fitted to this sculpt's own arms ----
    jpos, links, world, jnames = donor_skeleton(dj, db)
    world = fit_arms(P, dP_fitted, jnames, world)
    jpos = world[:, :3, 3]
    links = [(k, (world[kk][:3, 3] if isinstance(kk, (int, np.integer)) else kk)) for k, kk in
             [(k, t) for k, t in links]]
    links = rebuild_links(dj, world)
    JJ, WW = skin_weights(P, jpos, links)
    # ---- write it out ----
    out = {'asset': {'version': '2.0', 'generator': 'NightFall rig_character.py'}}
    blob = bytearray()
    views, accs = [], []

    def put(data, arr, comp, typ, target=None, mn=None, mx=None):
        while len(blob) % 4:
            blob.append(0)
        views.append({'buffer': 0, 'byteOffset': len(blob), 'byteLength': len(data)}
                     | ({'target': target} if target else {}))
        blob.extend(data)
        a = {'bufferView': len(views) - 1, 'componentType': comp, 'count': len(arr), 'type': typ}
        if mn is not None:
            a['min'] = mn
            a['max'] = mx
        accs.append(a)
        return len(accs) - 1

    pos_a = put(P.astype('<f4').tobytes(), P, 5126, 'VEC3', 34962,
                P.min(axis=0).tolist(), P.max(axis=0).tolist())
    nrm_a = put(N.astype('<f4').tobytes(), N, 5126, 'VEC3', 34962)
    uv_a = put(T.astype('<f4').tobytes(), T, 5126, 'VEC2', 34962)
    j_a = put(JJ.astype('<u2').tobytes(), JJ, 5123, 'VEC4', 34962)
    w_a = put(WW.astype('<f4').tobytes(), WW, 5126, 'VEC4', 34962)
    idx = F.astype('<u4').reshape(-1)
    i_a = put(idx.tobytes(), idx, 5125, 'SCALAR', 34963)
    pics = shrink_images(sj, sb, tex_side)
    out['images'] = []
    for raw in pics:
        while len(blob) % 4:
            blob.append(0)
        views.append({'buffer': 0, 'byteOffset': len(blob), 'byteLength': len(raw)})
        blob.extend(raw)
        out['images'].append({'bufferView': len(views) - 1, 'mimeType': 'image/jpeg'})
    out['samplers'] = [{}]
    out['textures'] = [{'source': i, 'sampler': 0} for i in range(len(pics))]
    src_mat = sj['materials'][0] if sj.get('materials') else {}
    pbr = src_mat.get('pbrMetallicRoughness', {})
    mat = {'name': 'body', 'pbrMetallicRoughness': {'metallicFactor': 0.0, 'roughnessFactor': 0.85}}
    def tex_of(entry):
        return entry['index'] if entry and entry.get('index', -1) < len(pics) else None
    base = tex_of(pbr.get('baseColorTexture'))
    if base is not None:
        mat['pbrMetallicRoughness']['baseColorTexture'] = {'index': base}
    nrm = tex_of(src_mat.get('normalTexture'))
    if nrm is not None:
        mat['normalTexture'] = {'index': nrm}
    mr = tex_of(pbr.get('metallicRoughnessTexture'))
    if mr is not None:
        mat['pbrMetallicRoughness']['metallicRoughnessTexture'] = {'index': mr}
        mat['pbrMetallicRoughness'].pop('roughnessFactor', None)
    out['materials'] = [mat]
    out['meshes'] = [{'name': 'body', 'primitives': [{'attributes': {
        'POSITION': pos_a, 'NORMAL': nrm_a, 'TEXCOORD_0': uv_a, 'JOINTS_0': j_a, 'WEIGHTS_0': w_a},
        'indices': i_a, 'material': 0}]}]
    # the donor's joints, hierarchy and bind matrices, copied across unchanged
    sk = dj['skins'][0]
    keep = sorted(set(sk['joints']) | {n for n in range(len(dj['nodes']))
                                       if dj['nodes'][n].get('mesh') is None and
                                       any(c in sk['joints'] for c in dj['nodes'][n].get('children', []))})
    remap = {old: i for i, old in enumerate(keep)}
    nodes = []
    for old in keep:
        n = dict(dj['nodes'][old])
        n.pop('mesh', None)
        n.pop('skin', None)
        n['children'] = [remap[c] for c in n.get('children', []) if c in remap]
        if not n['children']:
            n.pop('children')
        nodes.append(n)
    ibm = np.array([np.linalg.inv(w).T for w in world], dtype='<f4') # bind pose = this sculpt
    ibm_a = put(ibm.astype('<f4').tobytes(), ibm.reshape(len(world), 16), 5126, 'MAT4')
    out['skins'] = [{'inverseBindMatrices': ibm_a, 'joints': [remap[j] for j in sk['joints']]}]
    mesh_node = len(nodes)
    nodes.append({'name': 'body', 'mesh': 0, 'skin': 0})
    roots = [i for i, old in enumerate(keep) if old not in
             {c for n in dj['nodes'] for c in n.get('children', [])}]
    for r in roots:
        nodes[r].setdefault('children', []).append(mesh_node)
    out['nodes'] = nodes
    out['scenes'] = [{'nodes': roots if roots else [mesh_node]}]
    out['scene'] = 0
    out['bufferViews'] = views
    out['accessors'] = accs
    out['buffers'] = [{'byteLength': len(blob)}]
    js = json.dumps(out, separators=(',', ':')).encode()
    while len(js) % 4:
        js += b' '
    while len(blob) % 4:
        blob.append(0)
    body = (struct.pack('<II', len(js), JSON_CHUNK) + js +
            struct.pack('<II', len(blob), BIN_CHUNK) + bytes(blob))
    open(out_path, 'wb').write(struct.pack('<III', 0x46546C67, 2, 12 + len(body)) + body)
    print('wrote %s: %.1f MB' % (out_path, (12 + len(body)) / 1e6))


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('src')
    ap.add_argument('donor')
    ap.add_argument('out')
    ap.add_argument('--faces', type=int, default=26000)
    ap.add_argument('--tex', type=int, default=2048)
    ap.add_argument('--flip', action='store_true', help='the sculpt faces the other way')
    ap.add_argument('--scale', type=float, default=1.0, help='fine height adjustment')
    a = ap.parse_args()
    build(a.src, a.donor, a.out, a.faces, a.tex, a.flip, a.scale)
