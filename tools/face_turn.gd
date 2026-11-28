extends Node
## The face through a dance (the owner: the jaw moved): a character close up, front on, at a few
## moments of a dance where the head turns most. NF_CHARS picks the characters (default survivor1).
var tree: SceneTree

func _ready() -> void:
	tree = get_tree()
	var dir := OS.get_environment("NF_SHOTS")
	if dir == "": dir = "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.12, 0.13, 0.16)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.5, 0.4, 0)
	add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 30.0
	add_child(cam)
	cam.make_current()
	var chars := OS.get_environment("NF_CHARS").split(",", false)
	if chars.is_empty(): chars = PackedStringArray(["survivor1"])
	for c in chars:
		var rig := CharacterRig.new()
		add_child(rig)
		rig.setup(c, CharacterRig.ANIMS + ["dance_pop", "dance_funny"], false, false)
		rig.play("dance_funny")
		for k in 6:
			for i in 24: await tree.process_frame
			var head := rig.bone_at("mixamorig_Head")
			cam.look_at_from_position(head + Vector3(0, 0.05, 0.85), head + Vector3(0, 0.03, 0), Vector3.UP)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/face_%s_%d.png" % [dir, c, k])
			print("shot face ", c, " ", k)
		rig.queue_free()
	tree.quit()
