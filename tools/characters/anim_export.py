import bpy, sys, os
src, out, clip = sys.argv[-3:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=src, automatic_bone_orientation=False)
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
arm.name = 'Armature'
act = bpy.data.actions[0]; act.name = clip
a, b = act.frame_range
bpy.context.scene.frame_start = int(a); bpy.context.scene.frame_end = int(b)
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_yup=True, export_animations=True,
                          export_animation_mode='ACTIONS', export_force_sampling=True, export_frame_range=True,
                          export_def_bones=False, export_skins=False, export_optimize_animation_size=True)
print('ANIM', clip, a, b)
