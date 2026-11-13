extends SceneTree
func _init():
	var m = load("res://scenes/main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	var sk: Skeleton3D = m.rig.skeleton
	var h := sk.find_bone("mixamorig_Hips")
	print("char hips rest ", sk.get_bone_rest(h).origin, " global rest ", sk.get_bone_global_rest(h).origin, " skel scale ", sk.global_transform.basis.get_scale(), " model scale ", m.rig.model.scale)
	var inst: Node = (load("res://assets/anims/walk.glb") as PackedScene).instantiate()
	var hn := inst.find_child("mixamorig_Hips", true, false) as Node3D
	print("anim hips node pos ", hn.position, " armature scale ", inst.get_node("Armature").scale)
	var ap: AnimationPlayer = inst.find_children("*", "AnimationPlayer", true, false)[0]
	var a := ap.get_animation("walk")
	for t in a.get_track_count():
		if str(a.track_get_path(t)).ends_with("Hips") and a.track_get_type(t) == Animation.TYPE_POSITION_3D:
			print("hips key0 ", a.track_get_key_value(t, 0), " key10 ", a.track_get_key_value(t, 10))
	quit()
