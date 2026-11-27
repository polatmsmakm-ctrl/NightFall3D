extends Node
## How far each character's finger bones bend in the idle, the run and the attack (degrees from rest,
## middle joint / first joint of the index finger, eight moments of each clip). NF_CHARS="..."
func _ready() -> void:
	for id in OS.get_environment("NF_CHARS").split(" ", false):
		var rig := CharacterRig.new()
		add_child(rig)
		rig.setup(id, ["idle", "run", "attack"], false, false)
		var sk := rig.skeleton
		var bi := sk.find_bone("mixamorig_RightHandIndex2")
		var b1 := sk.find_bone("mixamorig_RightHandIndex1")
		print(id, ": bones ", sk.get_bone_count(), " index2=", bi)
		if bi < 0: continue
		for a in ["idle", "run", "attack"]:
			rig.play(a)
			var L := rig.player.get_animation(a).length
			var s := ""
			for k in 8:
				rig.player.seek(L * k / 8.0, true)
				await get_tree().process_frame
				var q := sk.get_bone_pose_rotation(bi)
				var r := sk.get_bone_rest(bi).basis.get_rotation_quaternion()
				var q1 := sk.get_bone_pose_rotation(b1)
				var r1 := sk.get_bone_rest(b1).basis.get_rotation_quaternion()
				s += " %d/%d" % [int(rad_to_deg((r.inverse() * q).get_angle())), int(rad_to_deg((r1.inverse() * q1).get_angle()))]
			print("  ", a, s)
		rig.queue_free()
	get_tree().quit()
