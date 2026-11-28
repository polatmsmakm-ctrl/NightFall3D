extends Node3D
## The three new killers with the scythe: idle and mid-attack, front and three-quarter.
var tree: SceneTree

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func _ready() -> void:
	tree = get_tree()
	var dir := OS.get_environment("NF_SHOTS")
	if dir == "": dir = "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.1, 0.1, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.ambient_light_energy = 1.2
	var we := WorldEnvironment.new(); we.environment = env; add_child(we)
	var sun := DirectionalLight3D.new(); sun.rotation = Vector3(-0.8, 0.6, 0); sun.light_energy = 1.6; add_child(sun)
	var rigs := []
	var x := -3.0
	for k in ["killer3", "killer4", "killer5"]:
		var holder := Node3D.new(); holder.position = Vector3(x, 0, 0); add_child(holder)
		var rig := CharacterRig.new(); holder.add_child(rig)
		rig.setup(k, CharacterRig.ANIMS, false, false)
		var sc := NFScythe.new(); holder.add_child(sc); sc.setup(rig)
		rigs.append(rig)
		x += 3.0
	var cam := Camera3D.new(); add_child(cam); cam.fov = 50.0; cam.current = true
	for pose in ["idle", "attack"]:
		for r in rigs: (r as CharacterRig).play(pose)
		await frames(pose == "attack" and 14 or 30)
		for view in [["front", Vector3(0, 1.4, 8.5)], ["side", Vector3(6.5, 1.6, 5.5)]]:
			cam.position = view[1]
			cam.look_at(Vector3(0, 1.2, 0))
			await frames(3)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/33_%s_%s.png" % [dir, pose, view[0]])
			print("shot ", pose, " ", view[0])
	tree.quit()
