extends Node
## «الربع الخالي» in daylight: the sun behind the storm, a camp, a surge of sand, and the
## sun coming down once the gates have power.

var tree: SceneTree
var dir := ""
var m

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])
	print("shot ", name)

func look(at: Vector3, yaw: float, pitch := -0.05) -> void:
	m.body.position = at
	m.body.velocity = Vector3.ZERO
	m.yaw = yaw
	m.pitch = pitch
	for i in 6: await tree.physics_frame
	await frames(4)

func boot(role := "survivor"):
	var g = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(g)
	await frames(10)
	g._start({"map": "rubkhali", "me": "راشد", "offline": true, "seed": 5150, "players": [
		{"name": "راشد", "role": role, "char": "survivor2", "slot": 0},
		{"name": "بدر", "role": "survivor", "char": "survivor5", "slot": 1},
		{"name": "فهد", "role": "killer", "char": "killer", "slot": 2}]})
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
	Gfx.fps_idx = 1; Gfx.preset = 0; Gfx.shadows = 1; Gfx.aa = 0; Gfx.scale_idx = 0; Gfx.effects = 1
	Gfx.apply()
	Net.username = "راشد"
	# the loading screen's painted preview, now in daylight
	var ld := NFLoading.new()
	ld.setup("rubkhali", "normal")
	tree.root.add_child.call_deferred(ld)
	await frames(4)
	ld.progress(0.6)
	await frames(4)
	await shot("B0_loading")
	ld.finish()
	await frames(20)
	m = await boot()
	var w = m.world
	# facing into the sun, across the dunes
	var sun_yaw: float = atan2(-w.moon_dir.x, -w.moon_dir.z)
	await look(Vector3(0, w.height(0, 0) + 0.3, 0), sun_yaw, 0.3)
	await shot("B1_sun")
	# a bedouin camp in the storm
	var camp: Vector3 = Vector3(w.buildings[0][0], 0, w.buildings[0][1])
	camp.y = w.height(camp.x, camp.z)
	await look(camp + Vector3(11.0, 0.3, 11.0), atan2(11.0, 11.0), -0.04)
	await shot("B2_camp")
	# a generator, so the daylight on the props reads
	var gen: Vector3 = w.gen_points[0]
	await look(gen + Vector3(5.0, 0.3, 5.0), atan2(5.0, 5.0), -0.08)
	await shot("B3_generator")
	# the round's event out here is a surge of sand
	m.rules.ev_kind = 0; m.rules.ev_t = 20.0; m.rules.ev_fired = true
	await frames(80)
	await look(Vector3(0, w.height(0, 0) + 0.3, 0), sun_yaw, 0.16)
	await shot("B4_sandsurge")
	m.rules.ev_t = 0.0
	await frames(70)
	# gates powered: the storm goes red and the sun comes down
	m.rules.powered = true
	m.rules.doom = Rules.DOOM_TIME * 0.45
	w.set_blood_moon(true)
	await frames(150)
	w.set_moon_near(0.55)
	await frames(10)
	await look(Vector3(0, w.height(0, 0) + 0.3, 0), sun_yaw, 0.34)
	await shot("B5_sun_falling")
	tree.quit()
