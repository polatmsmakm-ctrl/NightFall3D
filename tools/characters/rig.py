"""Fit the Mixamo skeleton to a T-pose character, skin it, export GLB.
usage: python3 -I rig.py char.glb mixamo_rest.fbx test_anim.fbx outdir name"""
import bpy, sys, os, math
from mathutils import Vector, Matrix

src, restfbx, testfbx, outdir, name = sys.argv[-5:]
bpy.ops.wm.read_factory_settings(use_empty=True)

# ---------- character mesh ----------
bpy.ops.import_scene.gltf(filepath=src)
ch = [o for o in bpy.data.objects if o.type == 'MESH'][0]
mw = ch.matrix_world.copy(); ch.parent = None; ch.matrix_world = Matrix.Identity(4); ch.data.transform(mw)
for o in list(bpy.data.objects):
    if o is not ch: bpy.data.objects.remove(o)
import bmesh
bm = bmesh.new(); bm.from_mesh(ch.data)
n0 = len(bm.verts); bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
print(name, 'merged verts', n0, '->', len(bm.verts))
bm.to_mesh(ch.data); bm.free(); ch.data.update()
for poly in ch.data.polygons: poly.use_smooth = True
P = [v.co.copy() for v in ch.data.vertices]
H = max(p.z for p in P)

def bbox_c(pts):
    if not pts: return None
    xs = [p.x for p in pts]; ys = [p.y for p in pts]; zs = [p.z for p in pts]
    return Vector(((min(xs)+max(xs))/2, (min(ys)+max(ys))/2, (min(zs)+max(zs))/2))

# crotch / upper leg
crotch = None
z = 0.25 * H
while z < 0.7 * H:
    if any(abs(p.x) < 0.012 * H and z <= p.z < z + 0.01 * H for p in P):
        crotch = z; break
    z += 0.005 * H
upleg_z = min(max(crotch + 0.04 * H, 0.50 * H), 0.56 * H)
S = 0.975 / upleg_z                       # scale so hip height matches the Mixamo skeleton
ch.data.transform(Matrix.Scale(S, 4)); ch.data.update()
P = [v.co.copy() for v in ch.data.vertices]
H *= S; crotch *= S; upleg_z = 0.975

# arms
def zext(x):
    pts = [p for p in P if x <= abs(p.x) < x + 0.01 * H and p.z > 0.5 * H]
    return (max(p.z for p in pts) - min(p.z for p in pts)) if pts else 0
x = 0.04 * H
while zext(x) > 0.14 * H: x += 0.005 * H
xs1 = x - 0.01 * H
xt1 = (max(p.x for p in P) - min(p.x for p in P)) / 2
L1 = xt1 - xs1
def arm_c(side, x):
    return bbox_c([p for p in P if x - 0.015 * H <= side * p.x < x + 0.015 * H and p.z > 0.5 * H])
arm_line = {}
for side in (1, -1):
    a = arm_c(side, xs1 + 0.12 * L1); b = arm_c(side, xs1 + 0.70 * L1)
    arm_line[side] = (xs1 + 0.12 * L1, a, xs1 + 0.70 * L1, b)
def arm_axis(side, x):
    xa, a, xb, b = arm_line[side]
    t = (x - xa) / (xb - xa)
    return a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t
arm_z = (arm_axis(1, xs1)[1] + arm_axis(-1, xs1)[1]) / 2

# legs
def leg_c(side, z):
    return bbox_c([p for p in P if side * p.x > 0.004 * H and abs(p.x) < 0.25 * H and z - 0.012 * H <= p.z < z + 0.012 * H])
ankle_z = 0.050 * H
knee_z = ankle_z + (upleg_z - ankle_z) * 0.505
legs = {}
for side in (1, -1):
    hip = leg_c(side, crotch - 0.03 * H); knee = leg_c(side, knee_z); ank = leg_c(side, ankle_z + 0.02 * H)
    foot = [p for p in P if side * p.x > 0 and abs(p.x) < 0.25 * H and p.z < 0.06 * H]
    toe_y = min(p.y for p in foot); heel_y = max(p.y for p in foot)
    footx = bbox_c(foot).x
    ank_y = heel_y - (heel_y - toe_y) * 0.27
    legs[side] = dict(hip=Vector((hip.x, hip.y, upleg_z)), knee=Vector((knee.x, knee.y, knee_z)),
                      ank=Vector((ank.x, ank_y, ankle_z * 1.0 + 0.037 * H * 0)), toe_y=toe_y, footx=footx)
def torso_y(z):
    c = bbox_c([p for p in P if abs(p.x) < 0.07 * H and z - 0.015 * H <= p.z < z + 0.015 * H])
    return c.y if c else 0.0
print(name, 'H', round(H, 3), 'S', round(S, 3), 'crotch', round(crotch, 3), 'shoulder x', round(xs1, 3), 'tip', round(xt1, 3),
      'arm_z', round(arm_z, 3), 'knee', round(knee_z, 3), 'hipx', round(legs[1]['hip'].x, 3), round(legs[-1]['hip'].x, 3))

# ---------- Mixamo skeleton ----------
bpy.ops.import_scene.fbx(filepath=restfbx, automatic_bone_orientation=False)
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
arm.animation_data_clear()
for a in list(bpy.data.actions): bpy.data.actions.remove(a)
AW = arm.matrix_world.copy(); AWi = AW.inverted()

# X Bot reference landmarks (metres, Blender world)
XS0, XT0, AY0, AZ0 = 0.152, 0.905, 0.071, 1.441
ANK0, KNEE0, UP0, TOP0 = 0.087, 0.532, 0.975, 1.82
LEGX0, ANKY0, TOEY0 = 0.082, 0.043, -0.157

def lerp(a, b, t): return a + (b - a) * t
def warp(bname, p):
    n = bname.split(':')[-1]
    side = 1 if n.startswith('Left') else -1
    if any(k in n for k in ('Arm', 'Hand')):
        k = L1 / (XT0 - XS0)
        nx = xs1 + (abs(p.x) - XS0) * k
        ay, az = arm_axis(side, nx)
        return Vector((side * nx, ay + (p.y - AY0) * k, az + (p.z - AZ0) * k))
    if any(k in n for k in ('UpLeg', 'Leg', 'Foot', 'Toe')):
        lg = legs[side]
        if 'UpLeg' in n: return lg['hip'].copy()
        if n.endswith('Leg'): return lg['knee'].copy()
        ank = Vector((lg['ank'].x, lg['ank'].y, ankle_z + 0.03 * H))
        if n.endswith('Foot'): return ank
        t = (p.y - ANKY0) / (TOEY0 - ANKY0)           # 0 ankle .. 1 toe tip
        return Vector((lg['footx'], lerp(ank.y, lg['toe_y'], t), 0.012 * H))
    # spine / head / clavicles
    if p.z <= AZ0: nz = lerp(upleg_z, arm_z, (p.z - UP0) / (AZ0 - UP0))
    else:          nz = lerp(arm_z, H, (p.z - AZ0) / (TOP0 - AZ0))
    if 'Shoulder' in n:
        return Vector((side * xs1 * 0.32, torso_y(nz), nz))
    return Vector((0.0, torso_y(nz) if 'Head' not in n else torso_y(min(nz, H * 0.97)), nz))

bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='EDIT')
for eb in arm.data.edit_bones:
    eb.use_connect = False
for eb in arm.data.edit_bones:
    world = AW @ eb.head
    d = (AWi @ warp(eb.name, world)) - eb.head
    eb.head += d; eb.tail += d                       # translate only: rest orientation preserved
bpy.ops.object.mode_set(mode='OBJECT')
for b in arm.data.bones:
    n = b.name
    if any(k in n for k in ('Thumb', 'Index', 'Middle', 'Ring', 'Pinky', '_End')):
        b.use_deform = False

# ---------- skin ----------
bpy.ops.object.select_all(action='DESELECT')
ch.select_set(True); arm.select_set(True); bpy.context.view_layer.objects.active = arm
bpy.ops.object.parent_set(type='ARMATURE_AUTO')
vg = {g.index: g.name for g in ch.vertex_groups}
unw = sum(1 for v in ch.data.vertices if not v.groups)
print(name, 'vertex groups', len(vg), 'unweighted verts', unw)
arm.name = 'Armature'; ch.name = name

os.makedirs(outdir, exist_ok=True)
bpy.ops.export_scene.gltf(filepath=os.path.join(outdir, name + '.glb'), export_format='GLB', export_yup=True,
                          export_animations=False, export_def_bones=True, export_skins=True,
                          export_image_format='JPEG', export_jpeg_quality=88)

# ---------- test pose render ----------
if testfbx != '-':
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=testfbx, automatic_bone_orientation=False)
    new = [o for o in bpy.data.objects if o not in before]
    act = bpy.data.actions[0]
    for o in new: bpy.data.objects.remove(o)
    arm.animation_data_create(); arm.animation_data.action = act
    try: arm.animation_data.action_slot = act.slots[0]
    except Exception as e: print('slot', e)
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'; sc.cycles.samples = 10; sc.cycles.device = 'CPU'
    sc.render.resolution_x = 420; sc.render.resolution_y = 520
    w = bpy.data.worlds.new('w'); sc.world = w; w.use_nodes = True
    w.node_tree.nodes['Background'].inputs[0].default_value = (1, 1, 1, 1)
    cd = bpy.data.cameras.new('c'); cd.type = 'ORTHO'; cd.ortho_scale = 2.3
    cam = bpy.data.objects.new('c', cd); sc.collection.objects.link(cam); sc.camera = cam
    frames = [int(f) for f in os.environ.get('FRAMES', '8').split(',')]
    for f in frames:
        sc.frame_set(f)
        for vn, d in (('f', Vector((0.5, -1, 0.15))), ('s', Vector((1, 0.1, 0.1)))):
            d = d.normalized(); cam.location = Vector((0, 0, 0.95)) + d * 10
            cam.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
            sc.render.filepath = os.path.join(outdir, 'test', f'{name}_{f}_{vn}.png')
            bpy.ops.render.render(write_still=True)
