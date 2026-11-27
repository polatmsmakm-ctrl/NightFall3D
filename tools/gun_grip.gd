extends Node
## The pistol in a hand with fingers: lowered and raised, close up on the grip. NF_SHOTS=dir NF_CHARS="..."
func _ready() -> void:
	var dir := OS.get_environment("NF_SHOTS")
	for id in OS.get_environment("NF_CHARS").split(" ", false):
		for want in [0.0, 1.0]:
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
			rig.setup(id, ["idle", "attack"], false, false)
			rig.play("idle")
			var g := NFGun.new()
			vp.add_child(g)
			g.setup(rig)
			for i in 90:
				g.step(true, want, 0.0, 0.0, 1.0 / 60.0)
				await get_tree().process_frame
			var hand: Vector3 = rig.bone_at("mixamorig_RightHand")
			var cam := Camera3D.new()
			cam.fov = 32.0
			vp.add_child(cam)
			cam.current = true
			var key := DirectionalLight3D.new()
			vp.add_child(key)
			key.look_at_from_position(hand + Vector3(0.5, 1, 0.8), hand)
			cam.position = hand + Vector3(-0.45, 0.12, 0.25)
			cam.look_at(hand + Vector3(0, 0, 0.06))
			for i in 4: await get_tree().process_frame
			await RenderingServer.frame_post_draw
			vp.get_texture().get_image().save_png("%s/gun_%s_%d.png" % [dir, id, int(want)])
			vp.queue_free()
			await get_tree().process_frame
	get_tree().quit()
