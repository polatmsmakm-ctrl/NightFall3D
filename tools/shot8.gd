extends Node
## «المواقف» screenshots: the car park from a survivor's eyes and the killer's, the loading
## screen, the map on the phone, a bay of parked cars, and the level with the lights out.

var tree: SceneTree
var dir := ""
var m

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func phys(n: int) -> void:
	for i in n: await tree.physics_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])
	print("shot ", name)

func look(pos: Vector3, target: Vector3, pitch := -0.03) -> void:
	m.body.position = pos
	m.body.velocity = Vector3.ZERO
	m.yaw = atan2(pos.x - target.x, pos.z - target.z)
	m.pitch = pitch
	await phys(6)
	await frames(4)

func boot(role := "survivor"):
	var g = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(g)
	await frames(10)
	g._start({"map": "garage", "me": "راشد", "offline": true, "seed": 1807, "players": [
		{"name": "راشد", "role": role, "char": "survivor2", "slot": 0},
		{"name": "فهد", "role": "killer" if role == "survivor" else "survivor", "char": "killer" if role == "survivor" else "survivor5", "slot": 1},
		{"name": "بدر", "role": "survivor", "char": "survivor5", "slot": 2}]})
	for i in 900:
		await tree.process_frame
		if g.world.ready_done: break
	await frames(12)
	return g

func _ready() -> void:
	tree = get_tree()
	dir = OS.get_environment("NF_SHOTS")
	if dir == "": dir = "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	Gfx.fps_idx = 1; Gfx.preset = 0; Gfx.shadows = 0; Gfx.aa = 0; Gfx.scale_idx = 0; Gfx.effects = 1
	Gfx.apply()
	Net.username = "راشد"
	# the loading screen first, with the painted preview of the map
	var ld := NFLoading.new()
	ld.setup("garage", "normal")
	tree.root.add_child.call_deferred(ld)
	await frames(4)
	ld.progress(0.55)
	await frames(4)
	await shot("A0_loading")
	ld.finish()
	await frames(20)
	m = await boot()
	var w = m.world
	# down an aisle between the columns (a spot clear of the columns and the parked cars)
	var aisle: Vector3 = w._gar(1, 3, 6.0, -12.0)
	var far: Vector3 = w._gar(4, 3, 26.0, -12.0)
	await look(aisle + Vector3(0, 1.4, 0), far, -0.01)
	await shot("A1_aisle")
	# a generator under the slab
	var gen: Vector3 = w.gen_points[0]
	await look(gen + Vector3(4.5, 1.5, 4.5), gen + Vector3(0, 1.0, 0), -0.06)
	await shot("A2_generator")
	# the parked cars in the bays
	var bay: Vector3 = w._gar(2, 3, 15.0, -12.0)
	await look(bay + Vector3(0, 1.5, 6.0), bay + Vector3(0, 1.0, -8.0), 0.0)
	await shot("A3_cars")
	# a stair core and a crash barrier
	var bar: Vector3 = w.window_points[0][0]
	await look(bar + Vector3(3.0, 1.4, 3.0), bar, -0.08)
	await shot("A4_barrier")
	# the phone map
	m.big_map = true
	await frames(6)
	await shot("A5_map")
	m.big_map = false
	await frames(4)
	# the lights out
	m.rules.ev_kind = 0; m.rules.ev_t = 20.0; m.rules.ev_fired = true
	await frames(60)
	await look(aisle + Vector3(0, 1.4, 0), far, -0.01)
	await shot("A6_blackout")
	m.rules.ev_t = 0.0
	await frames(60)
	m.queue_free()
	await frames(10)
	# the killer's first-person view of his floor
	m = await boot("killer")
	var k: Vector3 = m.world._gar(3, 2, 26.0, -12.0)
	await look(m.world._gar(1, 2, 8.0, -12.0) + Vector3(0, 0.0, 0), k, -0.01)
	await shot("A7_killer")
	tree.quit()
