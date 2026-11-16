extends Node
## The high-end look (NFLook, Forward+) next to the old one. Run it twice through Vulkan:
##   NF_TAG=hd ... godot --rendering-driver vulkan ... res://tools/shot18.tscn
##   NF_TAG=lo ... godot --rendering-driver vulkan --rendering-method mobile ... res://tools/shot18.tscn
## Shoots the camp, the character stand, and per map a generator with a survivor beside it and
## the killer's car with its headlights on, all at the highest settings.

var tree: SceneTree
var dir := ""
var tag := ""

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [dir, tag, name])
	print("shot ", tag, "_", name, "  (", RenderingServer.get_current_rendering_method(), ")")

func look(cam: Camera3D, from: Vector3, at: Vector3) -> void:
	cam.position = from
	cam.look_at(at, Vector3.UP)

func _ready() -> void:
	tree = get_tree()
	dir = OS.get_environment("NF_SHOTS")
	if dir == "": dir = "user://shots"
	tag = OS.get_environment("NF_TAG")
	if tag == "": tag = "hd" if NFLook.hd() else "lo"
	DirAccess.make_dir_recursive_absolute(dir)
	Gfx.fps_idx = 1; Gfx.shadows = 2; Gfx.aa = 1; Gfx.scale_idx = 2; Gfx.effects = 2
	Gfx.apply()
	Net.username = "راشد"
	Net.last_char = "survivor5"
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(3)
	var lob: NFLobby = m.lobby_scene
	m.menu.open("main")
	lob.intro = 1.0
	await frames(40)
	await shot("00_camp")
	m.menu.chars_from = "offline"
	m.menu.off_char = "survivor5"
	m.menu.open("chars")
	await frames(40)
	m.menu.visible = false
	await frames(4)
	await shot("01_stand")
	m.queue_free()
	await frames(4)
	for map in ["forest", "fareej", "rubkhali", "garage", "beach", "village"]:
		var w := NightWorld.new()
		w.configure(map, 4242, "normal")
		add_child(w)
		w.build()
		for i in 900:
			await tree.process_frame
			if w.ready_done: break
		var cam := Camera3D.new()
		cam.fov = 70.0
		cam.far = 400.0
		add_child(cam)
		cam.make_current()
		var gen: Vector3 = w.gen_points[0]
		var rig := CharacterRig.new()
		add_child(rig)
		rig.setup("survivor1")
		var off := Vector3(1.3, 0.0, 1.3)
		for k in 8: # the side of the generator with open ground, so the shot is not into a wall
			var o := Vector3(1.8, 0.0, 0.0).rotated(Vector3.UP, k * TAU / 8.0)
			var q := PhysicsRayQueryParameters3D.create(gen + Vector3(0, 1.2, 0), gen + o * 3.2 + Vector3(0, 1.2, 0))
			if w.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				off = o
				break
		rig.position = gen + off
		rig.position.y = gen.y
		var fwd := off.normalized() # she stands beside it, facing away from it toward the camera
		rig.rotation.y = atan2(fwd.x, fwd.z) + 0.5
		rig.play("idle")
		look(cam, rig.position + fwd * 2.6 + fwd.cross(Vector3.UP) * 0.9 + Vector3(0, 1.55, 0), rig.position + Vector3(0, 1.15, 0) - fwd * 0.6)
		await frames(40)
		await shot("%s_1_gen" % map)
		var dc: NFCar = w.drive_car
		if dc:
			dc.driven = true
			for k in 6: dc.park(0.5)
			var f := dc.forward()
			look(cam, dc.position - f * 7.5 + dc.global_basis.x * 2.0 + Vector3(0, 3.0, 0), dc.position + f * 9.0)
			await frames(40)
			await shot("%s_2_car" % map)
		rig.queue_free()
		w.queue_free()
		cam.queue_free()
		await frames(4)
	print("shots done")
	tree.quit()
