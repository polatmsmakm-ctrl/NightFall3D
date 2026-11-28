import sys, json, struct, numpy as np
sys.path.insert(0, '/home/claude/nightfall3d/tools')
import pose_sheet as ps
j, blob = ps.load('/home/claude/outpost/outpost_src.glb')
p = j['meshes'][0]['primitives'][0]; a = p['attributes']
P = ps.acc(j, blob, a['POSITION']).astype(np.float64)
N = ps.acc(j, blob, a['NORMAL']).astype(np.float32)
UV = ps.acc(j, blob, a['TEXCOORD_0']).astype(np.float32)
F = ps.acc(j, blob, p['indices'])[:, 0].reshape(-1, 3).astype(np.int64)
np.savez('/home/claude/outpost/raw.npz', P=P, N=N, UV=UV, F=F)
print(P.shape, F.shape)
