extends Node
## Faces while walking: each character's head close up, standing (idle) and at two moments of the
## walk and the run, to see whether the face drops or stretches. NF_SHOTS=dir NF_CHARS="survivor1 ..."

func _ready() -> void:
	var dir := OS.get_environment("NF_SHOTS")
	var ids := OS.get_environment("NF_CHARS").split(" ", false)
	if ids.is_empty(): ids = ["survivor1", "survivor9", "survivor10", "killer"]
	for id in ids:
		for st in [["idle", 0.5], ["walk", 0.1], ["walk", 0.55], ["run", 0.3]]:
			var vp := SubViewport.new()
			vp.size = Vector2i(320, 320)
			vp.own_world_3d = true
			vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			add_child(vp)
			var env := Environment.new()
			env.background_mode = Environment.BG_COLOR
			env.background_color = Color(0.12, 0.12, 0.14)
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = Color(0.8, 0.8, 0.85)
			var we := WorldEnvironment.new()
			we.environment = env
			vp.add_child(we)
			var rig := CharacterRig.new()
			vp.add_child(rig)
			rig.setup(id, ["idle", "walk", "run"], false, false)
			rig.play(str(st[0]))
			var len := rig.player.get_animation(str(st[0])).length
			rig.player.seek(len * float(st[1]), true)
			rig.player.pause()
			for i in 3: await get_tree().process_frame
			var head: Vector3 = rig.bone_at("mixamorig_Head")
			var neck: Vector3 = rig.bone_at("mixamorig_Neck")
			var look := head + (head - neck) * 0.7
			var fwd := (rig.global_transform.basis * Vector3(0, 0, 1)).normalized()
			var cam := Camera3D.new()
			cam.fov = 22.0
			vp.add_child(cam)
			cam.position = look + fwd * 0.85 + Vector3(0, 0.02, 0)
			cam.look_at(look)
			cam.current = true
			var key := DirectionalLight3D.new()
			vp.add_child(key)
			key.look_at_from_position(look + fwd + Vector3(-0.5, 0.6, 0), look)
			for i in 4: await get_tree().process_frame
			await RenderingServer.frame_post_draw
			vp.get_texture().get_image().save_png("%s/%s_%s_%02d.png" % [dir, id, st[0], int(float(st[1]) * 100)])
			vp.queue_free()
			await get_tree().process_frame
	get_tree().quit()
