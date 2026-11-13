extends SceneTree
func _init():
	var m = load("res://scenes/main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	m.set_physics_process(false)
	var r: CharacterRig = m.rig
	var sk := r.skeleton
	var b := sk.find_bone("mixamorig_LeftUpLeg")
	var rest := sk.get_bone_pose_rotation(b)
	r.player.play("walk", 0.0)
	r.player.seek(0.3, true)
	var p := sk.get_bone_pose_rotation(b)
	print("rest ", rest, " walk@0.3 ", p, " changed=", not rest.is_equal_approx(p))
	print("hips pos ", sk.get_bone_pose_position(sk.find_bone("mixamorig_Hips")))
	quit()
