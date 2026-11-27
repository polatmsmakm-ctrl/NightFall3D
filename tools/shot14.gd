extends Node
## A character sheet for checking a rig: each character close up from the front in idle, then
## mid-stride in a run and crouched, so the hands, the feet and the joints can be judged.
## NF_CHARS=survivor1,survivor2 picks who; NF_HI=1 uses the close-up models.

var tree: SceneTree
var dir := ""

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func _ready() -> void:
	tree = get_tree()
	dir = OS.get_environment("NF_SHOTS")
	if dir == "": dir = "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	var who := OS.get_environment("NF_CHARS").split(",", false)
	if who.is_empty(): who = PackedStringArray(["survivor10"]) # the newest character
	var hi := OS.get_environment("NF_HI") == "1"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.1, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.65)
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.7, 0.6, 0)
	sun.light_energy = 1.3
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.2, 0.2, 0.22)
	pm.material = fm
	floor_mi.mesh = pm
	add_child(floor_mi)
	var cam := Camera3D.new()
	cam.fov = 34.0
	add_child(cam)
	cam.current = true
	for id in who:
		var poses := [["idle", 0.0, 0.0], ["run", 0.3, 0.6], ["crouchwalk", 0.4, -0.6], ["repair", 1.0, 2.6], ["attack", 0.9, 0.5]]
		var rigs := []
		for i in poses.size():
			var rig := CharacterRig.new()
			add_child(rig)
			rig.setup(id, CharacterRig.ANIMS, hi)
			rig.position = Vector3((i - 2) * 1.5, 0, 0)
			rig.rotation.y = poses[i][2]
			rig.player.play(str(poses[i][0]), 0.0)
			rig.player.seek(float(poses[i][1]), true)
			rig.player.speed_scale = 0.0
			rigs.append(rig)
		cam.position = Vector3(0, 1.05, 7.4)
		cam.look_at(Vector3(0, 0.95, 0), Vector3.UP)
		await frames(6)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/sheet_%s.png" % [dir, id])
		# hands and feet, close
		cam.position = Vector3(-3.0 + 0.9, 1.25, 1.9)
		cam.look_at(Vector3(-3.0 + 0.35, 1.2, 0), Vector3.UP)
		await frames(4)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/hand_%s.png" % [dir, id])
		cam.position = Vector3(-3.0 + 0.5, 0.45, 1.6)
		cam.look_at(Vector3(-3.0, 0.12, 0), Vector3.UP)
		await frames(4)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/feet_%s.png" % [dir, id])
		print("shot ", id)
		for r in rigs: r.queue_free()
		await frames(4)
	tree.quit()
