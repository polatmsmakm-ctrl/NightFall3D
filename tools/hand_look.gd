extends Node
## Hands close up (the finger bones): each character's right hand from the back and from the side,
## in the idle, the run (a fist) and the attack. NF_SHOTS=dir NF_CHARS="survivor1 ..."

func _ready() -> void:
	var dir := OS.get_environment("NF_SHOTS")
	var ids := OS.get_environment("NF_CHARS").split(" ", false)
	for id in ids:
		var states := [["idle", 0.3], ["run", 0.25], ["run", 0.75], ["attack", 0.5]]
		if OS.get_environment("NF_QUICK") != "": states = [["idle", 0.3], ["attack", 0.5]]
		for st in states:
			var vp := SubViewport.new()
			vp.size = Vector2i(360, 360)
			vp.own_world_3d = true
			vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			add_child(vp)
			var env := Environment.new()
			env.background_mode = Environment.BG_COLOR
			env.background_color = Color(0.13, 0.13, 0.15)
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = Color(0.85, 0.85, 0.9)
			var we := WorldEnvironment.new()
			we.environment = env
			vp.add_child(we)
			var rig := CharacterRig.new()
			vp.add_child(rig)
			rig.setup(id, ["idle", "run", "attack"], false, false)
			rig.play(str(st[0]))
			rig.player.play(str(st[0]), 0.0) # no blend from the idle: the clip itself, at once
			rig.player.seek(rig.player.get_animation(str(st[0])).length * float(st[1]), true)
			rig.player.pause()
			for i in 3: await get_tree().process_frame
			var hand: Vector3 = rig.bone_at("mixamorig_RightHand")
			var fore: Vector3 = rig.bone_at("mixamorig_RightForeArm")
			var mid: Vector3 = rig.bone_at("mixamorig_RightHandMiddle2")
			if mid == rig.global_position: mid = hand + (hand - fore).normalized() * 0.09
			var look := hand.lerp(mid, 0.6)
			var along := (mid - hand).normalized()
			var side := along.cross(Vector3.UP).normalized()
			if side.length() < 0.1: side = Vector3.RIGHT
			var cam := Camera3D.new()
			cam.fov = 30.0
			vp.add_child(cam)
			cam.current = true
			var key := DirectionalLight3D.new()
			vp.add_child(key)
			key.look_at_from_position(look + Vector3(0.3, 1, 0.5), look)
			var hips: Vector3 = rig.bone_at("mixamorig_Hips")
			var out := Vector3(look.x - hips.x, 0, look.z - hips.z).normalized()
			var fwd := (rig.global_transform.basis * Vector3(0, 0, 1)).normalized()
			cam.position = look + out * (0.3 if id.find("killer2") < 0 else 0.9) + fwd * (0.34 if OS.get_environment("NF_PALM") == "" else -0.34) + Vector3(0, 0.06, 0)
			cam.look_at(look)
			for i in 4: await get_tree().process_frame
			await RenderingServer.frame_post_draw
			vp.get_texture().get_image().save_png("%s/%s_%s_%02d.png" % [dir, id, st[0], int(float(st[1]) * 100)])
			vp.queue_free()
			await get_tree().process_frame
	get_tree().quit()
