extends Node
## «مدينة الكويت» against the owner's reference picture: from up high at the south-west corner looking
## up the Gulf Road (the Assembly on the left, the sea and the towers on the right), from the street,
## from the corniche, and the power box lit and cut. Forward+ through lavapipe.
var tree: SceneTree
var dir := ""

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])
	print("shot ", name)

func _ready() -> void:
	tree = get_tree()
	dir = OS.get_environment("NF_SHOTS")
	if dir == "": dir = "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	Gfx.shadows = 1; Gfx.effects = 1; Gfx.scale_idx = 2; Gfx.aa = 1
	Gfx.apply()
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(10)
	m._start({"map": "kuwait", "me": "P", "offline": true, "seed": 77, "theme": "normal", "players": [
		{"name": "P", "role": "survivor", "char": "survivor9", "slot": 0},
		{"name": "K", "role": "killer", "char": "killer", "slot": 1}]})
	for i in 1500:
		await tree.process_frame
		if m.world.ready_done: break
	await frames(60)
	var cam := Camera3D.new()
	m.add_child(cam)
	cam.fov = 62.0
	for v in [["24_kw_reference", Vector3(-46, 34, -118), Vector3(14, 0, 40)], ["24_kw_road", Vector3(0, 7, -100), Vector3(0, 3, 20)],
			["24_kw_towers", Vector3(48, 4, 10), Vector3(104, 30, 62)], ["24_kw_assembly", Vector3(-12, 5, -30), Vector3(-75, 10, 5)],
			["24_kw_park", Vector3(34, 9, -70), Vector3(40, 0, 0)]]:
		cam.global_position = v[1]
		cam.look_at(v[2])
		cam.current = true
		await frames(30)
		await shot(v[0])
	for e in m.rules.handle({"k": "cut"}, "K"): m._on_event(e)
	cam.global_position = Vector3(0, 7, -100)
	cam.look_at(Vector3(0, 3, 20))
	await frames(60)
	await shot("24_kw_power_cut")
	cam.current = false
	m.big_map = true
	await frames(10)
	await shot("24_kw_map")
	print("shot24 done")
	tree.quit()
