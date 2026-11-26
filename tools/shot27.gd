extends Node
## The owner's November batch on Kuwait City: the billboard from the road, the police lights, the sea
## and the boats, the bus stop, the parking, the rescue helicopter with someone on its ladder, the
## medic with the first-aid kit, his rifle in her hands, and the gate countdown on the HUD.
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
	Net.perk = "aid"
	m._start({"map": "kuwait", "me": "P", "offline": true, "seed": 4242, "theme": "normal", "players": [
		{"name": "P", "role": "survivor", "char": "survivor6", "perk": "aid", "slot": 0},
		{"name": "D", "role": "survivor", "char": "survivor9", "slot": 1},
		{"name": "K", "role": "killer", "char": "killer", "slot": 2}]})
	for i in 1500:
		await tree.process_frame
		if m.world.ready_done: break
	await frames(60)
	m.rules.ev_at = 99999.0
	var w = m.world
	var cam := Camera3D.new()
	m.add_child(cam)
	cam.fov = 62.0
	cam.current = true
	# the billboard, from the road and from the far walk
	cam.global_position = Vector3(6, 1.7, 10)
	cam.look_at(NightWorld.KW_BILL + Vector3(0, 7, 0))
	await frames(30)
	await shot("27_billboard_road")
	cam.global_position = Vector3(-8, 4.5, 60)
	cam.look_at(NightWorld.KW_BILL + Vector3(0, 6, 0))
	await frames(20)
	await shot("27_billboard_far")
	# the police at the south end, lights going
	cam.global_position = Vector3(4, 2.2, -62)
	cam.look_at(Vector3(5, 1, -80))
	await frames(25)
	await shot("27_police")
	# the sea and the boats from the corniche
	cam.global_position = Vector3(50, 3.5, -6)
	cam.look_at(Vector3(90, 0, -20))
	await frames(25)
	await shot("27_sea")
	cam.global_position = Vector3(58, 2.0, 40)
	cam.look_at(Vector3(100, 0, 40))
	await frames(25)
	await shot("27_sea2")
	# the car park, his new cars among the old
	cam.global_position = Vector3(34, 3.0, -20)
	cam.look_at(Vector3(34, 0, 10))
	await frames(20)
	await shot("27_parking")
	# the bus stop
	cam.global_position = Vector3(8, 1.8, -20)
	cam.look_at(NightWorld.KW_BUS + Vector3(0, 1.5, 0))
	await frames(20)
	await shot("27_busstop")
	# the medic with the kit, from his own camera
	cam.current = false
	m.main_cam.current = true
	m.body.global_position = Vector3(-10, 0.3, 20)
	m.yaw = 1.2
	await frames(40)
	await shot("27_medic")
	# the gate countdown
	for gg in m.rules.gens: gg.done = true
	await frames(20)
	await shot("27_gate_countdown")
	m.rules.gate_t = -1.0
	m.rules.powered = false
	for gg in m.rules.gens: gg.done = false
	# the helicopter: D is gone, P is the last; it flies in, hovers, P climbs
	m.rules.s["D"].hp = "dead"
	for e in m.rules.tick(0.1): m._on_event(e)
	await frames(5)
	m.rules.heli.t = Rules.HELI_COME * 0.35
	await frames(10)
	cam.current = true
	cam.global_position = w.heli_spot + Vector3(-20, 6, 18)
	cam.look_at(m.heli.body.global_position)
	await frames(5)
	await shot("27_heli_coming")
	m.rules.heli.t = 0.05
	await frames(120)
	cam.global_position = w.heli_spot + Vector3(-18, 4, 16)
	cam.look_at(w.heli_spot + Vector3(0, 9, 0))
	await frames(10)
	await shot("27_heli_hover")
	m.body.global_position = m.heli.ladder_foot() + Vector3(0.8, 0.3, 0)
	await frames(10)
	m._press("interact", 5)
	await frames(90)
	cam.global_position = m.body.global_position + Vector3(-6, 1.5, 5)
	cam.look_at(m.body.global_position + Vector3(0, 1.5, 0))
	await frames(5)
	await shot("27_heli_climb")
	cam.current = false
	m.main_cam.current = true
	await frames(10)
	await shot("27_heli_climb_hud")
	tree.quit()
