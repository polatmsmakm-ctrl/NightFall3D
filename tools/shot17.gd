extends Node
## The owner's props in each map: the exit gate in the fortress wall, a generator, a hook, a
## campfire, and a corner of the wall. NF_SHOTS=dir xvfb-run godot ... res://tools/shot17.tscn

var tree: SceneTree
var dir := ""

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])
	print("shot ", name)

func look(cam: Camera3D, from: Vector3, at: Vector3) -> void:
	cam.position = from
	cam.look_at(at, Vector3.UP)

func _ready() -> void:
	tree = get_tree()
	dir = OS.get_environment("NF_SHOTS")
	if dir == "": dir = "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	Gfx.fps_idx = 1; Gfx.preset = 0; Gfx.shadows = 0; Gfx.aa = 0; Gfx.scale_idx = 0; Gfx.effects = 0
	Gfx.apply()
	var maps := OS.get_environment("NF_MAPS").split(",", false)
	if maps.is_empty(): maps = PackedStringArray(["forest", "fareej", "rubkhali", "garage", "beach", "village"])
	for map in maps:
		var w := NightWorld.new()
		w.configure(map, 4242, "normal")
		add_child(w)
		w.build()
		for i in 900:
			await tree.process_frame
			if w.ready_done: break
		var cam := Camera3D.new()
		cam.fov = 62.0
		cam.far = 400.0
		add_child(cam)
		cam.current = true
		var gp: Vector3 = w.gate_points[0][0]
		var inward := Basis(Vector3.UP, float(w.gate_points[0][1])) * Vector3(0, 0, 1)
		look(cam, gp + inward * 24.0 + Vector3(7, 4.5, 0), gp + Vector3(0, 4.0, 0))
		await frames(3)
		await shot("%s_1_gate" % map)
		var gen: Vector3 = w.gen_points[0]
		look(cam, gen + Vector3(3.2, 2.0, 4.2), gen + Vector3(0, 1.0, 0))
		await frames(3)
		await shot("%s_2_generator" % map)
		var hk: Vector3 = w.hook_points[0]
		look(cam, hk + Vector3(4.5, 2.4, 6.5), hk + Vector3(0, 2.3, -0.2))
		await frames(3)
		await shot("%s_3_hook" % map)
		if not w.campfire_points.is_empty():
			var cf: Vector3 = w.campfire_points[0]
			look(cam, cf + Vector3(2.2, 1.6, 2.6), cf + Vector3(0, 0.4, 0))
			await frames(3)
			await shot("%s_4_campfire" % map)
		if map == "rubkhali": # the crimson tents, front and side
			for k in 2:
				var tb: Array = w.buildings[k]
				var tp := Vector3(tb[0], w._raw_h(tb[0], tb[1]), tb[1])
				var fwd := Basis(Vector3.UP, float(tb[2])) * Vector3(0, 0, 1)
				var side := Basis(Vector3.UP, float(tb[2])) * Vector3(1, 0, 0)
				look(cam, tp + fwd * 13.0 + side * (4.0 if k == 0 else 9.0) + Vector3(0, 3.2, 0), tp + Vector3(0, 2.4, 0))
				await frames(3)
				await shot("%s_7_tent_%d" % [map, k])
		var c := Vector3(NightWorld.WALL, 0, NightWorld.WALL)
		look(cam, c + Vector3(-34, 6, -22), c + Vector3(-6, 3, -4))
		await frames(3)
		await shot("%s_5_wall" % map)
		w.set_gate_state(0, true)
		await tree.create_timer(5.0).timeout
		look(cam, gp + inward * 24.0 + Vector3(7, 4.5, 0), gp + Vector3(0, 4.0, 0))
		await frames(3)
		await shot("%s_6_gate_open" % map)
		w.queue_free()
		cam.queue_free()
		await frames(3)
	print("shots done")
	tree.quit()
