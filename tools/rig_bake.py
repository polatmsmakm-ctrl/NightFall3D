"""The second way through tools/rig_character.py (`--bake`): no pymeshlab.

Some sculpts cannot keep their own UV atlas. «البركة القرمزية» came with 3.1 M triangles cut into
3,937 UV islands, most of them hair: an atlas-preserving collapse cannot go under ~21k triangles
there (every island corner has to stay), and what it keeps is spent where the islands are, not
where the eye goes. So this path throws the atlas away instead:

  1. welds the sculpt and collapses it with tools/simplify.cpp (quadric edge collapse, a triangle
     budget per region like the pymeshlab path, plus an importance per vertex: face skin counts
     for more, dark hair for less);
  2. unwraps the small mesh into a new atlas (charts by facing direction, packed as bitmaps,
     more texels per metre on skin than on hair);
  3. bakes the sculpt onto it: for every texel, the closest point of the 3 M-triangle surface
     gives the colour, the metallic-roughness and the normal (the sculpt's own normal map
     *and* its geometry, rewritten in the small mesh's tangent space, which is exported as
     TANGENT so the engine shades with exactly the frame the bake used).

Needs numpy, scipy, opencv, pillow and a C++ compiler (g++ or clang++).
"""
import io, os, struct, subprocess, tempfile
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))


LOSSLESS = False   # set by rig_character.py --external: the maps come out as PNG
FACE_FACES = 0     # rig_character.py --face-faces: the front of the face gets its own triangle budget
FRINGE = False     # rig_character.py --fringe: hair hanging over the face is kept, not pinched
HAIR_DENSITY = 0.32  # texels per metre on hair, against the body (rig_character.py --hair-density)


def log(*a):
    print(*a, flush=True)


# ------------------------------------------------------------------ small mesh helpers
def weld(P):
    """Vertices that sit on the same point become one. Returns (first index of each, map old -> welded)."""
    _, first, inv = np.unique(P, axis=0, return_index=True, return_inverse=True)
    return first, inv.reshape(-1)


def face_normals(P, F):
    n = np.cross(P[F[:, 1]] - P[F[:, 0]], P[F[:, 2]] - P[F[:, 0]])
    l = np.linalg.norm(n, axis=1)
    return n / np.maximum(l, 1e-20)[:, None], l * 0.5


def vertex_normals(P, F):
    n = np.cross(P[F[:, 1]] - P[F[:, 0]], P[F[:, 2]] - P[F[:, 0]])
    N = np.zeros_like(P)
    for k in range(3):
        np.add.at(N, F[:, k], n)
    l = np.linalg.norm(N, axis=1)
    lost = l < 1e-12 * max(float(l.max()), 1e-30) + 1e-30    # faces that cancel out (a pinched strand)
    if lost.any():
        un = n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-30)
        for k in range(3):                                   # any one of its faces will do
            pick = lost[F[:, k]] & (np.linalg.norm(n, axis=1) > 0)
            N[F[pick, k]] = un[pick]
        l = np.linalg.norm(N, axis=1)
        N[l < 1e-12] = [0.0, 1.0, 0.0]
        l = np.linalg.norm(N, axis=1)
    return N / np.maximum(l, 1e-30)[:, None]


def face_adjacency(F, nv):
    """nb[f, k] = the face on the other side of edge (v_k, v_k+1), or -1."""
    nf = len(F)
    e = np.sort(np.stack([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]], 1), axis=2).reshape(-1, 2)
    key = e[:, 0].astype(np.int64) * nv + e[:, 1]
    order = np.argsort(key, kind='stable')
    ks = key[order]
    nb = -np.ones(nf * 3, np.int64)
    i = np.nonzero(ks[1:] == ks[:-1])[0]
    nb[order[i]] = order[i + 1] // 3
    nb[order[i + 1]] = order[i] // 3
    return nb.reshape(nf, 3)


def tangents(P, N, T, F):
    """Per-vertex tangent frame for a normal map with green pointing up the image (glTF):
    the tangent follows +u, the bitangent follows -v. Returns xyz + handedness."""
    e1, e2 = P[F[:, 1]] - P[F[:, 0]], P[F[:, 2]] - P[F[:, 0]]
    du1, du2 = T[F[:, 1], 0] - T[F[:, 0], 0], T[F[:, 2], 0] - T[F[:, 0], 0]
    dv1, dv2 = -(T[F[:, 1], 1] - T[F[:, 0], 1]), -(T[F[:, 2], 1] - T[F[:, 0], 1])
    det = du1 * dv2 - du2 * dv1
    r = np.where(np.abs(det) > 1e-20, 1.0 / np.where(np.abs(det) > 1e-20, det, 1.0), 0.0)
    ft = (e1 * dv2[:, None] - e2 * dv1[:, None]) * r[:, None]
    fb = (e2 * du1[:, None] - e1 * du2[:, None]) * r[:, None]
    area = np.linalg.norm(np.cross(e1, e2), axis=1)
    ft = ft / np.maximum(np.linalg.norm(ft, axis=1, keepdims=True), 1e-20) * area[:, None]
    fb = fb / np.maximum(np.linalg.norm(fb, axis=1, keepdims=True), 1e-20) * area[:, None]
    Tv, Bv = np.zeros_like(P), np.zeros_like(P)
    for k in range(3):
        np.add.at(Tv, F[:, k], ft)
        np.add.at(Bv, F[:, k], fb)
    Tv = Tv - N * (Tv * N).sum(1, keepdims=True)
    l = np.linalg.norm(Tv, axis=1, keepdims=True)
    lost = l[:, 0] < 1e-12                                  # no usable UVs here: any tangent will do
    alt = np.cross(N, np.array([0.0, 1.0, 0.0]))
    alt[np.linalg.norm(alt, axis=1) < 1e-6] = [1.0, 0.0, 0.0]
    Tv = np.where(lost[:, None], alt, Tv)
    Tv /= np.maximum(np.linalg.norm(Tv, axis=1, keepdims=True), 1e-20)
    w = np.where((np.cross(N, Tv) * Bv).sum(1) < 0.0, -1.0, 1.0)
    return np.column_stack([Tv, w])


# ------------------------------------------------------------------ 1. the collapse
def _simplifier():
    src = os.path.join(HERE, 'simplify.cpp')
    exe = os.path.join(tempfile.gettempdir(), 'nightfall_simplify')
    if not os.path.exists(exe) or os.path.getmtime(exe) < os.path.getmtime(src):
        for cc in ('g++', 'clang++', 'c++'):
            try:
                subprocess.run([cc, '-O2', '-o', exe, src], check=True)
                break
            except (OSError, subprocess.CalledProcessError):
                continue
        else:
            raise SystemExit('--bake needs a C++ compiler (g++ or clang++) to build tools/simplify.cpp')
    return exe


def simplify(P, F, region, targets, weight, soft, maxlen=0.06):
    exe = _simplifier()
    with tempfile.TemporaryDirectory() as d:
        fi, fo = os.path.join(d, 'in.bin'), os.path.join(d, 'out.bin')
        with open(fi, 'wb') as f:
            f.write(struct.pack('<3i', len(P), len(F), len(targets)))
            f.write(struct.pack('<d', maxlen))
            f.write(np.asarray(targets, '<i4').tobytes())
            f.write(np.ascontiguousarray(P, '<f8').tobytes())
            f.write(np.ascontiguousarray(F, '<i4').tobytes())
            f.write(np.ascontiguousarray(region, np.uint8).tobytes())
            f.write(np.ascontiguousarray(weight, '<f4').tobytes())
            f.write(np.ascontiguousarray(soft, np.uint8).tobytes())
        subprocess.run([exe, fi, fo], check=True)
        raw = open(fo, 'rb').read()
    nv, nf = struct.unpack_from('<2i', raw, 0)
    V = np.frombuffer(raw, '<f8', nv * 3, 8).reshape(nv, 3).copy()
    G = np.frombuffer(raw, '<i4', nf * 3, 8 + nv * 24).reshape(nf, 3).astype(np.int64)
    return V, G


# ------------------------------------------------------------------ 2. the new atlas
AXES = np.array([[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]], float)


def charts_of(V, F):
    """Cut the surface into pieces that each face one way, so a flat projection barely stretches."""
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import connected_components
    nf = len(F)
    fn, area = face_normals(V, F)
    nb = face_adjacency(F, len(V))
    score = fn @ AXES.T
    lab = score.argmax(1)
    rows = np.arange(nf)
    for _ in range(5):                                      # straighten the borders between directions
        votes = np.zeros((nf, 6))
        votes[rows, lab] += 1.2 * area
        for k in range(3):
            n = nb[:, k]
            ok = n >= 0
            np.add.at(votes, (rows[ok], lab[n[ok]]), area[n[ok]])
        votes[score < 0.3] = -1.0
        lab = np.where(votes.max(1) > 0, votes.argmax(1), lab)

    def components(lab):
        fi, fk = np.nonzero((nb >= 0) & (lab[np.maximum(nb, 0)] == lab[:, None]))
        g = coo_matrix((np.ones(len(fi), np.int8), (fi, nb[fi, fk])), shape=(nf, nf))
        return connected_components(g, directed=False)[1]

    chart = components(lab)
    for _ in range(3):                                      # crumbs join the neighbour they touch most
        size = np.bincount(chart)
        carea = np.bincount(chart, weights=area)
        small = np.nonzero((size < 10) | (carea < 4e-5))[0]
        if not len(small):
            break
        order = np.argsort(chart, kind='stable')
        start = np.searchsorted(chart[order], np.arange(len(size) + 1))
        moved = 0
        for c in small:
            fc = order[start[c]:start[c + 1]]
            if not len(fc) or chart[fc[0]] != c:
                continue
            n = nb[fc].reshape(-1)
            n = n[n >= 0]
            n = n[chart[n] != c]
            if not len(n):
                continue
            best, bl = -1, 0
            for d in np.unique(chart[n]):
                l = lab[n[chart[n] == d][0]]
                if (score[fc, l] > 0.12).all():
                    cnt = (chart[n] == d).sum()
                    if cnt > bl:
                        best, bl = d, cnt
            if best >= 0:
                lab[fc] = lab[n[chart[n] == best][0]]
                chart[fc] = best
                moved += 1
        if not moved:
            break
    chart = np.unique(components(lab), return_inverse=True)[1].reshape(-1)
    return chart, lab, fn, area


def unwrap(V, F, side, density, pad=3, cell=4):
    """New UVs for the collapsed mesh. `density` is a per-face multiplier on texels per metre.
    Returns split vertices: (index into V for each new vertex, UV, faces)."""
    import cv2
    chart, lab, fn, area = charts_of(V, F)
    nc = chart.max() + 1
    order = np.argsort(chart, kind='stable')
    start = np.searchsorted(chart[order], np.arange(nc + 1))
    pieces = []
    for c in range(nc):
        fc = order[start[c]:start[c + 1]]
        m = (fn[fc] * area[fc, None]).sum(0)
        m /= max(np.linalg.norm(m), 1e-20)
        if (fn[fc] @ m).min() < 0.25:                        # too curled for its own average: use the axis
            m = AXES[lab[fc[0]]]
        a = np.array([0.0, 1.0, 0.0]) if abs(m[1]) < 0.9 else np.array([1.0, 0.0, 0.0])
        t1 = np.cross(a, m); t1 /= np.linalg.norm(t1)
        t2 = np.cross(m, t1)
        vid, loc = np.unique(F[fc].reshape(-1), return_inverse=True)
        xy = np.column_stack([V[vid] @ t1, V[vid] @ t2])
        (_, _), (rw, rh), ang = cv2.minAreaRect(xy.astype(np.float32))
        th = np.radians(ang if rw >= rh else ang + 90.0)     # long side along x
        R = np.array([[np.cos(th), np.sin(th)], [-np.sin(th), np.cos(th)]])
        xy = xy @ R.T
        xy -= xy.min(0)
        mul = float(np.average(density[fc], weights=np.maximum(area[fc], 1e-12)))
        pieces.append({'faces': fc, 'vid': vid, 'tri': loc.reshape(-1, 3), 'xy': xy * mul})
    G = side // cell

    def pack(s):
        occ = np.zeros((G, G), np.float32)
        where = []
        for p in sorted(pieces, key=lambda p: -max(p['xy'].max(0))):
            px = p['xy'] * s + pad + 1
            w, h = int(np.ceil(px[:, 0].max())) + pad + 2, int(np.ceil(px[:, 1].max())) + pad + 2
            wc, hc = -(-w // cell), -(-h // cell)
            if wc > G or hc > G:
                return None
            m = np.zeros((hc * cell, wc * cell), np.uint8)
            cv2.fillPoly(m, list(np.round(px[p['tri']] * 16).astype(np.int32)), 1, shift=4)
            cv2.polylines(m, list(np.round(px[p['tri']] * 16).astype(np.int32)), True, 1, 1, shift=4)
            m = cv2.dilate(m, np.ones((2 * pad + 1, 2 * pad + 1), np.uint8))
            cm = m.reshape(hc, cell, wc, cell).max(axis=(1, 3)).astype(np.float32)
            # how much of what is already placed this piece would land on, at every position
            hit = cv2.filter2D(occ, -1, cm, anchor=(0, 0), borderType=cv2.BORDER_CONSTANT)
            free = hit[:G - hc + 1, :G - wc + 1] < 0.5
            ys, xs = np.nonzero(free)
            if not len(ys):
                return None
            y, x = int(ys[0]), int(xs[0])
            occ[y:y + hc, x:x + wc] = np.maximum(occ[y:y + hc, x:x + wc], cm)
            where.append((p, x * cell, y * cell))
        return where, float(occ.mean())

    surface = sum(float((area[p['faces']] * density[p['faces']] ** 2).sum()) for p in pieces)
    hi = np.sqrt(side * side / surface)                      # an atlas with no gaps at all
    lo, best = hi * 0.2, None
    for _ in range(11):
        mid = (lo + hi) / 2.0
        got = pack(mid)
        if got is None:
            hi = mid
        else:
            lo, best = mid, (got, mid)
    (placed, fill), s = best
    log('   atlas: %d charts, %.0f texels per metre at %d px, %.0f%% of the cells used' % (nc, s, side, fill * 100))
    vmap, uv, F2 = [], [], np.zeros_like(F)
    base = 0
    for p, ox, oy in placed:
        px = p['xy'] * s + pad + 1 + np.array([ox, oy])
        vmap.append(p['vid'])
        uv.append(px / side)
        F2[p['faces']] = p['tri'] + base
        base += len(p['vid'])
    return np.concatenate(vmap), np.vstack(uv), F2


# ------------------------------------------------------------------ 3. the bake
def closest_on_triangles(p, A, B, C):
    """Closest point of each triangle (M, K) to its query point (M). Ericson's regions, vectorised.
    Returns the squared distance and the barycentric weights of the closest point."""
    q = p[:, None, :]
    ab, ac, ap = B - A, C - A, q - A
    d1, d2 = (ab * ap).sum(-1), (ac * ap).sum(-1)
    bp = q - B
    d3, d4 = (ab * bp).sum(-1), (ac * bp).sum(-1)
    cp = q - C
    d5, d6 = (ab * cp).sum(-1), (ac * cp).sum(-1)
    vc, vb, va = d1 * d4 - d3 * d2, d5 * d2 - d1 * d6, d3 * d6 - d5 * d4
    with np.errstate(divide='ignore', invalid='ignore'):
        den = va + vb + vc
        v, w = vb / den, vc / den
        m = (va <= 0) & ((d4 - d3) >= 0) & ((d5 - d6) >= 0)
        t = (d4 - d3) / ((d4 - d3) + (d5 - d6))
        v, w = np.where(m, 1 - t, v), np.where(m, t, w)
        m = (vb <= 0) & (d2 >= 0) & (d6 <= 0)
        t = d2 / (d2 - d6)
        v, w = np.where(m, 0.0, v), np.where(m, t, w)
        m = (vc <= 0) & (d1 >= 0) & (d3 <= 0)
        t = d1 / (d1 - d3)
        v, w = np.where(m, t, v), np.where(m, 0.0, w)
    m = (d6 >= 0) & (d5 <= d6)
    v, w = np.where(m, 0.0, v), np.where(m, 1.0, w)
    m = (d3 >= 0) & (d4 <= d3)
    v, w = np.where(m, 1.0, v), np.where(m, 0.0, w)
    m = (d1 <= 0) & (d2 <= 0)
    v, w = np.where(m, 0.0, v), np.where(m, 0.0, w)
    v, w = np.nan_to_num(v), np.nan_to_num(w)
    c = A + ab * v[..., None] + ac * w[..., None]
    return ((c - q) ** 2).sum(-1), np.stack([1 - v - w, v, w], -1)


def bilinear(img, u, v):
    """img (H, W, C) float32, u/v in [0, 1) with wrap."""
    H, W = img.shape[:2]
    x, y = u * W - 0.5, v * H - 0.5
    x0, y0 = np.floor(x).astype(np.int64), np.floor(y).astype(np.int64)
    fx, fy = (x - x0)[:, None], (y - y0)[:, None]
    x1, y1 = (x0 + 1) % W, (y0 + 1) % H
    x0, y0 = x0 % W, y0 % H
    return (img[y0, x0] * (1 - fx) * (1 - fy) + img[y0, x1] * fx * (1 - fy)
            + img[y1, x0] * (1 - fx) * fy + img[y1, x1] * fx * fy)


class Sculpt:
    """The full-resolution surface, ready to be asked "what is nearest to this point?"."""

    def __init__(self, P, T, F, images):
        from scipy.spatial import cKDTree
        self.P, self.T, self.F = P, T % 1.0 if (T.max() > 1.001 or T.min() < -0.001) else T, F
        self.first, self.weld = weld(P)
        self.Pw = P[self.first]
        self.Fw = self.weld[F]
        self.Nw = vertex_normals(self.Pw, self.Fw)
        self.N = self.Nw[self.weld]
        self.tan = tangents(P, self.N, self.T, F)
        self.tree = cKDTree(self.Pw)
        # faces around every welded vertex, padded to 8
        corner = self.Fw.reshape(-1)
        order = np.argsort(corner, kind='stable')
        cs = corner[order]
        start = np.searchsorted(cs, np.arange(len(self.Pw)))
        rank = np.arange(len(cs)) - start[cs]
        keep = rank < 8
        self.vf = -np.ones((len(self.Pw), 8), np.int64)
        self.vf[cs[keep], rank[keep]] = order[keep] // 3
        self.col, self.mr, self.nrm = images             # float32 arrays, 0..255 (mr / nrm may be None)
        self.dark = None                                   # hair per welded vertex, set by run() with --fringe
        self.neck = 1e9                                    # above this, hair wins a near tie (--fringe)

    def sample(self, p, n, want=None):
        """For points p with surface normals n: colour, metallic-roughness and world normal there.
        `want` (bool per point, with self.dark set, --fringe): look for hair on hair and skin on skin,
        so a strand lying a few millimetres over the forehead is not painted with the forehead."""
        M = len(p)
        _, near = self.tree.query(p, k=4, workers=-1)
        facing = (self.Nw[near] * n[:, None, :]).sum(-1) > 0.0
        key = np.arange(4)[None, :] + np.where(facing, 0, 10)      # the nearest that faces the same way
        pick = np.take_along_axis(near, np.argsort(key, axis=1)[:, :2], axis=1)
        if want is not None and self.dark is not None:
            # hair has its own index: its triangles are large and its vertices few, so by vertex
            # distance alone the dense skin of the forehead always wins, even under a strand
            if not hasattr(self, 'tree_dark'):
                from scipy.spatial import cKDTree
                self.dark_ix = np.nonzero(self.dark)[0]
                self.tree_dark = cKDTree(self.Pw[self.dark_ix])
            _, hn = self.tree_dark.query(p, k=2, workers=-1)
            pick = np.concatenate([pick, self.dark_ix[hn]], axis=1)
        cand = self.vf[pick].reshape(M, -1)
        ok = cand >= 0
        fc = np.maximum(cand, 0)
        tri = self.Pw[self.Fw[fc]]                                  # (M, C, 3, 3)
        d2, bary = closest_on_triangles(p, tri[:, :, 0], tri[:, :, 1], tri[:, :, 2])
        d2 = np.where(ok, d2, np.inf)
        if want is not None and self.dark is not None:
            hair_tri = self.dark[self.Fw[fc]].sum(-1) >= 2          # a triangle of hair
            d_any = np.sqrt(d2.min(1))
            d_hair = np.sqrt(np.where(hair_tri, d2, np.inf).min(1))
            # hair on hair only: a texel of a hair face takes the nearest hair, and on the head the
            # edge of a hair mass (some hair around it) does too when hair is within 8 mm of the
            # nearest surface. Skin is never forced: eyes, brows and buckles are dark details on skin.
            w = ((want > 0.5) & (d_hair <= d_any + 0.02)) | ((want > 0.15) & (p[:, 1] > self.neck) & (d_hair <= d_any + 0.008))
            w &= np.isfinite(d_hair)
            d2 = np.where(w[:, None] & ~hair_tri, d2 + 1.0, d2)
        k = d2.argmin(1)
        r = np.arange(M)
        f, b = fc[r, k], bary[r, k]
        vi = self.F[f]                                              # the sculpt's own (unwelded) corners
        uv = (self.T[vi] * b[..., None]).sum(1)
        # a face that straddles the 0/1 wrap would interpolate across the atlas: take its nearest corner
        span = np.ptp(self.T[vi], axis=1).max(1)
        nearest = self.T[vi[r, b.argmax(1)]]
        uv = np.where((span > 0.5)[:, None], nearest, uv)
        col = bilinear(self.col, uv[:, 0], uv[:, 1])
        mr = bilinear(self.mr, uv[:, 0], uv[:, 1]) if self.mr is not None else None
        N = (self.N[vi] * b[..., None]).sum(1)
        N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-20)
        if self.nrm is not None:
            tm = bilinear(self.nrm, uv[:, 0], uv[:, 1]) / 127.5 - 1.0
            Tn = (self.tan[vi, :3] * b[..., None]).sum(1)
            Tn = Tn - N * (Tn * N).sum(1, keepdims=True)
            Tn /= np.maximum(np.linalg.norm(Tn, axis=1, keepdims=True), 1e-20)
            Bn = np.cross(N, Tn) * self.tan[vi[:, 0], 3][:, None]
            W = Tn * tm[:, 0:1] + Bn * tm[:, 1:2] + N * np.maximum(tm[:, 2:3], 0.05)
            W /= np.maximum(np.linalg.norm(W, axis=1, keepdims=True), 1e-20)
        else:
            W = N
        return col, mr, W, np.sqrt(d2[r, k])


def grow(px, covered, steps):
    """Bleed every island's edge out into the empty atlas, so filtering never drags the background in."""
    px, covered = px.copy(), covered.copy()
    for _ in range(steps):
        acc = np.zeros_like(px)
        cnt = np.zeros(covered.shape, np.float32)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            acc += np.roll(px * covered[..., None], (dy, dx), (0, 1))
            cnt += np.roll(covered, (dy, dx), (0, 1))
        add = (~covered) & (cnt > 0)
        px[add] = acc[add] / cnt[add][:, None]
        covered |= add
    return px, covered


def bake(V, N, T, F, tan, sculpt, side, out_side, hair=None):
    """Rasterise the new atlas and fill it from the sculpt. Returns [colour, metal-rough, normal] as JPEG bytes."""
    import cv2
    from PIL import Image
    fid = np.zeros((side, side), np.int32)
    px = T * side
    tris = np.round(px[F] * 16).astype(np.int32)
    for f in range(len(F)):                                  # a one-pixel skirt first, the faces on top
        cv2.polylines(fid, [tris[f]], True, int(f + 1), 2, shift=4)
    for f in range(len(F)):
        cv2.fillConvexPoly(fid, tris[f], int(f + 1), shift=4)
    ys, xs = np.nonzero(fid)
    f = fid[ys, xs] - 1
    a, b, c = px[F[f, 0]], px[F[f, 1]], px[F[f, 2]]
    q = np.column_stack([xs + 0.5, ys + 0.5])
    v0, v1, v2 = b - a, c - a, q - a
    den = v0[:, 0] * v1[:, 1] - v1[:, 0] * v0[:, 1]
    den = np.where(np.abs(den) < 1e-12, 1e-12, den)
    wb = (v2[:, 0] * v1[:, 1] - v1[:, 0] * v2[:, 1]) / den
    wc = (v0[:, 0] * v2[:, 1] - v2[:, 0] * v0[:, 1]) / den
    bary = np.clip(np.column_stack([1 - wb - wc, wb, wc]), -0.25, 1.25)
    bary /= bary.sum(1, keepdims=True)
    col = np.zeros((side, side, 3), np.float32)
    mr = np.zeros((side, side, 3), np.float32)
    nm = np.zeros((side, side, 3), np.float32)
    far = []
    step = 60000
    for s in range(0, len(f), step):
        sl = slice(s, s + step)
        ff, bb = F[f[sl]], bary[sl][..., None]
        p = (V[ff] * bb).sum(1)
        n = (N[ff] * bb).sum(1)
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-20)
        want = None
        if hair is not None:
            want = (hair[ff] * bb[..., 0]).sum(1)          # how much hair is around this texel, 0..1
        c_, m_, w_, d_ = sculpt.sample(p, n, want)
        far.append(d_)
        # the sculpt's normal, written in the frame the engine will rebuild at this texel
        t = (tan[ff, :3] * bb).sum(1)
        t /= np.maximum(np.linalg.norm(t, axis=1, keepdims=True), 1e-20)
        bv = np.cross(N[ff], tan[ff, :3]) * tan[ff, 3:4]
        bv /= np.maximum(np.linalg.norm(bv, axis=2, keepdims=True), 1e-20)
        bt = (bv * bb).sum(1)
        bt /= np.maximum(np.linalg.norm(bt, axis=1, keepdims=True), 1e-20)
        Mx = np.stack([t, bt, n], axis=2)                    # columns T B N
        try:
            loc = np.linalg.solve(Mx, w_[..., None])[..., 0]
        except np.linalg.LinAlgError:
            loc = np.einsum('nij,nj->ni', np.linalg.pinv(Mx), w_)
        loc[:, 2] = np.maximum(loc[:, 2], 0.08)
        loc /= np.maximum(np.linalg.norm(loc, axis=1, keepdims=True), 1e-20)
        col[ys[sl], xs[sl]] = c_
        if m_ is not None:
            mr[ys[sl], xs[sl]] = m_
        nm[ys[sl], xs[sl]] = loc * 127.5 + 127.5
    far = np.concatenate(far)
    log('   bake: %d texels, sculpt within %.1f mm on average (%.1f mm at the 99th percentile)' % (
        len(f), far.mean() * 1000, np.percentile(far, 99) * 1000))
    covered = fid > 0
    out = []
    for img, is_normal in ((col, False), (mr, False), (nm, True)):
        if img is mr and sculpt.mr is None:
            continue
        g, _ = grow(img, covered, 24)
        if is_normal:
            g[~_] = [127.5, 127.5, 255.0]
        pic = Image.fromarray(np.clip(g + 0.5, 0, 255).astype(np.uint8))
        if out_side != side:
            pic = pic.resize((out_side, out_side), Image.LANCZOS)
            if is_normal:                                    # averaging shortens normals: stretch them back
                a = np.asarray(pic).astype(np.float32) / 127.5 - 1.0
                a /= np.maximum(np.linalg.norm(a, axis=2, keepdims=True), 1e-6)
                pic = Image.fromarray(np.clip(a * 127.5 + 127.5 + 0.5, 0, 255).astype(np.uint8))
        buf = io.BytesIO()
        if LOSSLESS: pic.save(buf, format='PNG', optimize=True)   # --external: no JPEG step at all
        else: pic.save(buf, format='JPEG', quality=90, optimize=True)
        out.append(buf.getvalue())
    return out


# ------------------------------------------------------------------ the whole second path
def source_images(j, blob):
    """The sculpt's colour, metallic-roughness and normal maps as float arrays (None when absent)."""
    from PIL import Image
    mat = j['materials'][0] if j.get('materials') else {}
    pbr = mat.get('pbrMetallicRoughness', {})

    def get(entry):
        if not entry:
            return None
        im = j['images'][j['textures'][entry['index']]['source']]
        bv = j['bufferViews'][im['bufferView']]
        raw = blob[bv.get('byteOffset', 0):bv.get('byteOffset', 0) + bv['byteLength']]
        return np.asarray(Image.open(io.BytesIO(raw)).convert('RGB')).astype(np.float32)
    return get(pbr.get('baseColorTexture')), get(pbr.get('metallicRoughnessTexture')), get(mat.get('normalTexture'))


def run(P, T, F, images, faces, tex_side, pos, ix, hair_lum=70.0):
    """P is the sculpt already in the cast's space. Returns the game mesh and its maps:
    V, UV, F, normals, tangents, [colour, (metal-rough), normal] JPEGs, hair (0..1 per vertex)."""
    log('bake path: welding %d vertices' % len(P))
    sculpt = Sculpt(P, T, F, images)
    Pw, Fw = sculpt.Pw, sculpt.Fw
    # how dark the sculpt is around every welded vertex: on these characters that is the hair
    lum = bilinear(sculpt.col, sculpt.T[sculpt.first, 0], sculpt.T[sculpt.first, 1]).max(1)
    hip = (pos[ix['LeftUpLeg']][1] + pos[ix['RightUpLeg']][1]) / 2.0
    reach = max(abs(pos[ix['LeftArm']][0]), abs(pos[ix['RightArm']][0])) + 0.10
    # (above the hips and no further out than the shoulders: dark boots and the shadows between
    #  the fingers are not hair)
    dark = (lum < hair_lum) & (Pw[:, 1] > hip) & (np.abs(Pw[:, 0]) < reach)
    # ...and nothing on the arm itself: a dark armband or sleeve past the shoulder joint, at arm
    # height, belongs to the arm (it tore off «المحاربة الجريحة» when it was taken for hair)
    arm_y = (pos[ix['LeftArm']][1] + pos[ix['RightArm']][1]) / 2.0
    dark &= ~((np.abs(Pw[:, 0]) > reach - 0.07) & (np.abs(Pw[:, 1] - arm_y) < 0.09))
    # hair proper: the big dark masses. Brows, lashes and irises are small dark islands on the skin.
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import connected_components
    e = np.concatenate([Fw[:, [0, 1]], Fw[:, [1, 2]], Fw[:, [2, 0]]])
    e = e[dark[e[:, 0]] & dark[e[:, 1]]]
    g = coo_matrix((np.ones(len(e)), (e[:, 0], e[:, 1])), shape=(len(Pw), len(Pw)))
    _, lab = connected_components(g, directed=False)
    size = np.bincount(lab, weights=dark.astype(float))
    hair_only = dark & (size[lab] > 0.02 * max(dark.sum(), 1))
    # regions, as in the pymeshlab path: the head, the hands and the feet keep their own budget
    wrist = min(abs(pos[ix['LeftHand']][0]), abs(pos[ix['RightHand']][0])) - 0.03
    ankle = max(pos[ix['LeftFoot']][1], pos[ix['RightFoot']][1]) + 0.04
    neck = pos[ix['Neck']][1]
    x0, y0 = np.abs(Pw[Fw[:, 0], 0]), Pw[Fw[:, 0], 1]
    region = np.zeros(len(Fw), np.uint8)
    region[(y0 > neck) & (x0 <= wrist)] = 1
    region[x0 > wrist] = 2
    region[(y0 < ankle) & (x0 <= wrist)] = 3
    targets = [int(faces * s) for s in (0.47, 0.27, 0.17, 0.09)]
    if FACE_FACES > 0:
        # the front of the face on its own budget: brows, eyelids and lips keep their shape (out of
        # the head's budget the hair took almost everything, and the face came out at a tenth of
        # the sculpt's triangles, softer and with a different expression in the game's light)
        head_z = pos[ix['Head']][2]
        zf = Pw[Fw[:, 0], 2]
        # everything on the front of the face but the hair: skin, and the brows, lashes and eyes
        face = (y0 > neck) & (x0 < 0.10) & (zf > head_z - 0.01) & ~hair_only[Fw[:, 0]]
        region[face] = 4
        targets.append(int(FACE_FACES))
        log('   face: %d sculpt faces, kept to %d' % (int(face.sum()), int(FACE_FACES)))
    weight = np.ones(len(Pw), np.float32)
    weight[dark] = 0.25                  # hair: a soft mass, not the place for triangles
    weight[(lum >= hair_lum) & (Pw[:, 1] > neck) & (np.abs(Pw[:, 0]) < reach)] = 7.0  # the face
    soft = dark
    if FRINGE:
        # strands over the forehead and the cheeks: pinched shut, the texels on them land on the skin
        # behind and the fringe comes out as white streaks. Keep them as real geometry instead.
        head = pos[ix['Head']]
        fringe = dark & (Pw[:, 1] > neck) & (np.abs(Pw[:, 0]) < 0.12) & (Pw[:, 2] > head[2] + 0.03)
        weight[fringe] = 4.0
        soft = dark & ~fringe
        log('   fringe: %d sculpt vertices of hair over the face kept as strands' % int(fringe.sum()))
    log('   collapsing %d faces to %d (body %d, head %d, hands %d, feet %d%s)' % ((len(Fw), faces) + tuple(targets[:4]) + (
        (', face %d' % targets[4]) if len(targets) > 4 else '',)))
    V, G = simplify(Pw, Fw, region, targets, weight, soft)
    log('   mesh: %d faces, %d vertices' % (len(G), len(V)))
    # hair and skin on the small mesh, from the sculpt around each vertex
    _, near = sculpt.tree.query(V, k=12, workers=-1)
    hair_v = dark[near].mean(1)
    Nv = vertex_normals(V, G)
    fh = hair_v[G].mean(1)
    fy = V[G][:, :, 1].mean(1)
    fx = np.abs(V[G][:, :, 0]).mean(1)
    density = np.ones(len(G))
    density[fh > 0.6] = HAIR_DENSITY         # hair is mostly one dark colour: it needs fewer texels
    density[(fh < 0.4) & (fy > neck) & (fx < reach)] = 2.1  # the face gets the most
    side = max(tex_side, 2048)                               # bake large, shrink after: free supersampling
    vmap, UV, F2 = unwrap(V, G, side, density, pad=2 * side // 1024, cell=2 * side // 1024)
    V2, N2 = V[vmap], Nv[vmap]
    tan = tangents(V2, N2, UV, F2)
    if FRINGE:
        # for the fringe rule only hair proper counts: letting the brows "win" made them thick and brown
        log('   fringe: %d of %d dark sculpt vertices are hair (the rest: brows, lashes, eyes)' % (int(hair_only.sum()), int(dark.sum())))
        sculpt.dark = hair_only
        sculpt.neck = neck
    pics = bake(V2, N2, UV, F2, tan, sculpt, side, tex_side, hair_v[vmap] if FRINGE else None)
    return V2, UV, F2, N2, tan, pics, hair_v[vmap]
