extends Node
## Checks the hand-posed emotes actually move the limbs where they should.
func _ready():
	var tree := get_tree()
	var r := CharacterRig.new()
	tree.root.add_child.call_deferred(r)
	for i in 5: await tree.process_frame
	r.setup("survivor5", ["idle", "wave", "clap", "dance"])
	for i in 5: await tree.process_frame
	var sk := r.skeleton
	var head := sk.get_bone_global_rest(sk.find_bone("mixamorig_Head")).origin
	var hips := sk.get_bone_global_rest(sk.find_bone("mixamorig_Hips")).origin
	print("up is -z: hips z=", snappedf(hips.z, 0.1), " head z=", snappedf(head.z, 0.1))
	for a in ["wave", "clap", "dance"]:
		r.current = ""
		r.play(a)
		r.player.advance(0.275)
		for i in 6: await tree.process_frame
		var rh := sk.get_bone_global_pose(sk.find_bone("mixamorig_RightHand")).origin
		var lh := sk.get_bone_global_pose(sk.find_bone("mixamorig_LeftHand")).origin
		print(a, ": right hand=", rh.snapped(Vector3(1, 1, 1)), " left hand=", lh.snapped(Vector3(1, 1, 1)),
			"  above head=", rh.z < head.z, "  hands apart=", snappedf(rh.distance_to(lh), 1.0), "cm")
	tree.quit()
