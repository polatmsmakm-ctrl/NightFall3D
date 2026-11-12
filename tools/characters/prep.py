"""Clean foot shadow skirts, normalise orientation/scale, export GLB + FBX.
usage: python3 -I prep.py src.glb outdir name height_m clean(0/1)"""
import bpy, sys, os, math
from mathutils import Matrix

src, outdir, name, height, clean = sys.argv[-5:]
height = float(height); clean = clean == '1'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
o = [o for o in bpy.data.objects if o.type == 'MESH'][0]
bpy.context.view_layer.objects.active = o
o.select_set(True)
# bake world transform, drop parents
mw = o.matrix_world.copy()
o.parent = None
o.matrix_world = Matrix.Identity(4)
o.data.transform(mw)
for other in list(bpy.data.objects):
    if other is not o:
        bpy.data.objects.remove(other)
me = o.data
vs = me.vertices
zmin = min(v.co.z for v in vs); zmax = max(v.co.z for v in vs); H = zmax - zmin

if clean:
    moved = 0
    for sel in (lambda v: v.co.x < 0, lambda v: v.co.x >= 0):
        foot = [v for v in vs if sel(v) and abs(v.co.x) < 0.22 and v.co.z < zmin + H * 0.12]
        ref = [v for v in foot if zmin + H * 0.035 <= v.co.z < zmin + H * 0.055]
        x0 = min(v.co.x for v in ref); x1 = max(v.co.x for v in ref)
        y0 = min(v.co.y for v in ref); y1 = max(v.co.y for v in ref)
        top = zmin + H * 0.035
        for v in foot:
            if v.co.z < top:
                t = (top - v.co.z) / (top - zmin)          # 0 at top of skirt .. 1 at ground
                inset = 0.004 * t                           # slight taper like a real sole
                nx = min(max(v.co.x, x0 + inset), x1 - inset)
                ny = min(max(v.co.y, y0 + inset), y1 - inset)
                if nx != v.co.x or ny != v.co.y:
                    moved += 1
                v.co.x = nx; v.co.y = ny
    print(name, 'clamped skirt verts', moved)

# face -Y in Blender (= +Z in glTF = Mixamo / three.js forward), feet on ground, scaled
xs = [v.co.x for v in vs]
cx = (min(xs) + max(xs)) / 2
ys = [v.co.y for v in vs if v.co.z > zmin + H * 0.4 and v.co.z < zmin + H * 0.7 and abs(v.co.x - cx) < 0.1]
cy = (min(ys) + max(ys)) / 2
s = height / H
M = Matrix.Scale(s, 4) @ Matrix.Rotation(math.pi, 4, 'Z') @ Matrix.Translation((-cx, -cy, -zmin))
me.transform(M)
me.update()
o.name = name; me.name = name
for m in me.materials:
    m.name = name + '_mat'

os.makedirs(outdir, exist_ok=True)
bpy.ops.export_scene.gltf(filepath=os.path.join(outdir, name + '.glb'), export_format='GLB', export_yup=True)
# FBX with embedded textures for Mixamo
bpy.ops.file.pack_all()
bpy.ops.file.unpack_all(method='WRITE_LOCAL')
bpy.ops.export_scene.fbx(filepath=os.path.join(outdir, name + '.fbx'), use_selection=False,
                         path_mode='COPY', embed_textures=True, axis_forward='-Z', axis_up='Y',
                         apply_scale_options='FBX_SCALE_ALL', mesh_smooth_type='FACE',
                         add_leaf_bones=False, bake_anim=False, object_types={'MESH'})
print(name, 'done H', round(H * s, 3))
