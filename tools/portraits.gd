extends Node
## Renders a head-and-shoulders portrait of every character into assets/ui/portraits/<id>.png for the
## Social Sidebar and profiles. xvfb-run -a godot --rendering-driver opengl3 --path . res://tools/portraits.tscn

const IDS := ["killer", "killer2", "survivor1", "survivor2", "survivor3", "survivor4", "survivor5", "survivor6", "survivor7", "survivor8", "survivor9", "survivor10"]

func _ready() -> void:
	var out := ProjectSettings.globalize_path("res://assets/ui/portraits")
	DirAccess.make_dir_recursive_absolute(out)
	for id in IDS:
		var vp := SubViewport.new()
		vp.size = Vector2i(384, 384)
		vp.transparent_bg = false
		vp.own_world_3d = true
		vp.msaa_3d = Viewport.MSAA_4X
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.06, 0.05, 0.06)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.5, 0.52, 0.6)
		env.ambient_light_energy = 0.7
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		var we := WorldEnvironment.new()
		we.environment = env
		vp.add_child(we)
		var rig := CharacterRig.new()
		vp.add_child(rig)
		rig.setup(id, ["idle"], false, false)
		rig.play("idle")
		rig.player.seek(0.4, true)
		for i in 3: await get_tree().process_frame
		var head: Vector3 = rig.bone_at("mixamorig_Head")
		var neck: Vector3 = rig.bone_at("mixamorig_Neck")
		var look := head + (head - neck) * 0.6 - Vector3(0, 0.05, 0) # the middle of the face, a little of the shoulders
		var cam := Camera3D.new()
		cam.fov = 24.0
		vp.add_child(cam)
		cam.position = look + Vector3(0.1, 0.03, 0.9)
		cam.look_at(look)
		cam.current = true
		var key := DirectionalLight3D.new() # warm key from the front left, cool rim from behind right
		key.light_color = Color(1.0, 0.86, 0.72)
		key.light_energy = 1.5
		vp.add_child(key)
		key.look_at_from_position(look + Vector3(-0.8, 0.6, 1.0), look)
		var rim := DirectionalLight3D.new()
		rim.light_color = Color(0.9, 0.25, 0.2)
		rim.light_energy = 2.0
		vp.add_child(rim)
		rim.look_at_from_position(look + Vector3(0.9, 0.5, -1.0), look)
		for i in 6: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.save_png(out + "/" + id + ".png")
		print("portrait ", id, " head at ", head)
		vp.queue_free()
		await get_tree().process_frame
	get_tree().quit()
