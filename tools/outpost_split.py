import numpy as np, scipy.sparse as sp
from scipy import ndimage as ndi
from scipy.sparse.csgraph import connected_components
d = np.load('/home/claude/outpost/raw.npz'); P = d['P']; F = d['F']
H = np.load('/home/claude/outpost/H.npy'); S = H.shape[0]; X0, Z0, W = -0.72, -0.96, 1.92
m = H > -0.09
m = ndi.binary_closing(m, iterations=3); m = ndi.binary_fill_holes(m)
yy, xx = np.mgrid[-9:10, -9:10]; disk = xx * xx + yy * yy <= 81
o = ndi.binary_opening(m, structure=disk)
lb, n = ndi.label(o)
seeds = {'dome_lab': (-0.08, -0.62), 'comms_tower': (0.48, -0.32), 'research_lab': (-0.55, -0.2), 'garage': (-0.1, 0.30),
         'dish_station': (0.48, 0.38), 'energy_storage': (-0.52, 0.52), 'medical': (0.1, 0.68)}
foot = {}
grow = ndi.binary_dilation(m, iterations=3)
for k, (x, z) in seeds.items():
    i, jx = int((z - Z0) / W * S), int((x - X0) / W * S)
    L = lb[i - 3:i + 4, jx - 3:jx + 4].ravel(); L = L[L > 0]
    if len(L) == 0: print('no blob for', k); continue
    blob = lb == np.bincount(L).argmax()
    foot[k] = ndi.binary_dilation(blob, iterations=34 if k == 'dish_station' else 12) & grow
    if k == 'dish_station': # its base sits low: take the whole pad round the dish
        zz, xg = np.mgrid[0:S, 0:S]
        foot[k] = foot[k] | ((((xg / S * W + X0) - 0.48) ** 2 + ((zz / S * W + Z0) - 0.385) ** 2) < 0.105 ** 2)
    print(k, blob.sum())
T = P[F]; cen = T.mean(1); cy = cen[:, 1]
DECK = -0.197
gi = ((cen[:, 2] - Z0) / W * S).astype(int).clip(0, S - 1); gj = ((cen[:, 0] - X0) / W * S).astype(int).clip(0, S - 1)
lab = np.full(len(F), '', dtype=object)
above = cy > DECK
for k, fp in foot.items():
    lab[(lab == '') & above & fp[gi, gj]] = k
ex = (cen[:, 0] - 0.008) / 0.714; ez = cen[:, 2] / 0.951; rr = np.sqrt(ex * ex + ez * ez)
lab[(lab == '') & ((~above) | (rr > 0.86))] = 'platform'
rest = np.where(lab == '')[0]
q = np.round(P / 1e-5).astype(np.int64); _, inv = np.unique(q, axis=0, return_inverse=True); inv = inv.ravel()
G = inv[F[rest]]; nv = inv.max() + 1
r = np.concatenate([G[:, 0], G[:, 1], G[:, 2]]); c = np.concatenate([G[:, 1], G[:, 2], G[:, 0]])
k2, vl = connected_components(sp.coo_matrix((np.ones(len(r)), (r, c)), shape=(nv, nv)), directed=False)
fl = vl[G[:, 0]]
order = np.argsort(fl); fls = fl[order]; cuts = np.flatnonzero(np.diff(fls)) + 1
for grp in np.split(order, cuts):
    idx = rest[grp]
    ext = cen[idx].max(0) - cen[idx].min(0)
    lab[idx] = 'corridors' if max(ext[0], ext[2]) > 0.12 else 'cargo'
names, counts = np.unique(lab, return_counts=True)
for a, b in zip(names, counts): print('%-16s %8d triangles' % (a, b))
np.save('/home/claude/outpost/labels.npy', lab.astype(str))
