extends Node
## The three new killers: they load, the scythe sits in the right hand, the Wraith floats and makes no steps.
var tree: SceneTree
var bad := 0

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok: bad += 1

func _ready() -> void:
	tree = get_tree()
	for k in ["killer3", "killer4", "killer5"]:
		var rig := CharacterRig.new()
		add_child(rig)
		rig.setup(k, CharacterRig.ANIMS, false, false)
		await frames(3)
		check(rig.skeleton != null and rig.has("attack"), "%s loads with the clips" % k)
		var sc := NFScythe.new()
		add_child(sc)
		sc.setup(rig)
		rig.play("run")
		await frames(20)
		var hand := rig.bone_at("mixamorig_RightHand")
		check(sc.model != null and sc.global_position.distance_to(hand) < 1.6, "%s holds the scythe by the hand (%.2f m)" % [k, sc.global_position.distance_to(hand)])
		var head := rig.bone_at("mixamorig_Head")
		check(head.y > 1.75, "%s stands tall (head %.2f m)" % [k, head.y])
		if k == "killer4":
			check(rig.flier and rig.current == "float", "the Wraith floats instead of running (%s)" % rig.current)
			check(rig.model.position.y > 0.3, "and hovers off the ground (%.2f m)" % rig.model.position.y)
			var lh := rig.bone_at("mixamorig_LeftHand"); var rh := rig.bone_at("mixamorig_RightHand")
			var hips := rig.bone_at("mixamorig_Hips")
			check(lh.z > hips.z + 0.3 and rh.z > hips.z + 0.3, "her hands reach out in front (%.2f, %.2f m ahead)" % [lh.z - hips.z, rh.z - hips.z])
		else:
			check(not rig.flier and rig.current == "run", "%s runs on its legs" % k)
		rig.queue_free(); sc.queue_free()
		await frames(2)
	print("KILLERS %s (%d failed)" % ["PASS" if bad == 0 else "FAIL", bad])
	tree.quit(1 if bad else 0)
