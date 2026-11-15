extends Node
## The look pass, side by side: the same frame with the contact shadows and the fine detail
## layer switched off, then on. (The ground shading is baked into the terrain's vertex colours
## while the map is built, so it cannot be toggled — it is in both frames.)

var tree: SceneTree
var dir := ""
var m

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])
	print("shot ", name)

func look(at: Vector3, target: Vector3, pitch := -0.05) -> void:
	m.body.position = at
	m.body.velocity = Vector3.ZERO
	m.yaw = atan2(at.x - target.x, at.z - target.z)
	m.pitch = pitch
	for i in 6: await tree.physics_frame
	await frames(4)

func boot(map: String):
	var g = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(g)
	await frames(10)
	g._start({"map": map, "me": "راشد", "offline": true, "seed": 2468, "players": [
		{"name": "راشد", "role": "survivor", "char": "survivor2", "slot": 0},
		{"name": "فهد", "role": "killer", "char": "killer", "slot": 1},
		{"name": "بدر", "role": "survivor", "char": "survivor5", "slot": 2}]})
	for i in 900:
		await tree.process_frame
		if g.world.ready_done: break
	await frames(12)
	return g

## Turn the new look off (as it was before) or on.
func detail(on: bool) -> void:
	var w = m.world
	if w.ao_mm: w.ao_mm.visible = on
	if m.grade: m.grade.visible = on
	for k in w._mat:
		var mat = w._mat[k]
		if mat is StandardMaterial3D: (mat as StandardMaterial3D).detail_enabled = on
	await frames(6)

func pair(tag: String, at: Vector3, target: Vector3, pitch := -0.05) -> void:
	await look(at, target, pitch)
	await detail(false)
	await shot("C%s_before" % tag)
	await detail(true)
	await shot("C%s_after" % tag)

func _ready() -> void:
	tree = get_tree()
	dir = OS.get_environment("NF_SHOTS")
	if dir == "": dir = "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	Gfx.fps_idx = 1; Gfx.preset = 0; Gfx.shadows = 1; Gfx.aa = 0; Gfx.scale_idx = 0; Gfx.effects = 1
	Gfx.apply()
	Net.username = "راشد"
	var only := OS.get_environment("NF_ONLY") # "forest", "garage", "fareej", or all of them
	# a generator beside a shack in the forest
	m = await boot("forest")
	var gen: Vector3 = m.world.gen_points[0]
	await pair("1_forest", gen + Vector3(7.0, 1.6, 7.0), gen + Vector3(0, 1.0, 0), -0.08)
	# and with the killer right behind you: the edges tighten and go red
	m.remotes["فهد"].pos = m.body.position + Vector3(3.0, 0, 0)
	m.remotes["فهد"].node.position = m.remotes["فهد"].pos
	for i in 20: await tree.physics_frame
	await frames(4)
	await shot("C4_killer_near")
	if only == "forest": tree.quit()
	m.queue_free()
	await frames(8)
	# the car park: columns, cars, contact shadows on concrete
	if only == "garage" or only == "": m = await boot("garage")
	else: tree.quit()
	var aisle: Vector3 = m.world._gar(1, 3, 6.0, -12.0)
	var far: Vector3 = m.world._gar(4, 3, 26.0, -12.0)
	await pair("2_garage", aisle + Vector3(0, 1.4, 0), far, -0.02)
	m.queue_free()
	await frames(8)
	# a street on the fareej
	m = await boot("fareej")
	var house: Array = m.world.buildings[2]
	var at := Vector3(house[0] + 9.0, 1.5, house[1] + 9.0)
	await pair("3_fareej", at, Vector3(house[0], 1.2, house[1]), -0.06)
	tree.quit()
