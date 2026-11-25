extends Node
## The blood (the owner's three models), «بين العصر والمغرب» from the afternoon to the dark and the
## lights coming on, and Halloween lit and switched off. Forward+ through lavapipe.
var tree: SceneTree
var dir := ""

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])
	print("shot ", name)

func round_of(map: String, theme: String, seed: int) -> Node:
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(10)
	m._start({"map": map, "me": "P", "offline": true, "seed": seed, "theme": theme, "players": [
		{"name": "P", "role": "survivor", "char": "survivor9", "slot": 0},
		{"name": "K", "role": "killer", "char": "killer", "slot": 1}]})
	for i in 1500:
		await tree.process_frame
		if m.world.ready_done: break
	await frames(40)
	return m

func _ready() -> void:
	tree = get_tree()
	dir = OS.get_environment("NF_SHOTS")
	if dir == "": dir = "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	Gfx.shadows = 1; Gfx.effects = 1; Gfx.scale_idx = 2; Gfx.aa = 1
	Gfx.apply()
	# --- the blood: a blow, then walking hurt, then a close look at the ground
	var m = await round_of("village", "normal", 5)
	m.rules.s["P"].ammo = 0
	m.rules.s["P"].hp = "hurt"
	m._on_event({"k": "hurt", "n": "P", "s": "hurt"})
	await frames(4)
	var cam := Camera3D.new()
	m.add_child(cam)
	cam.fov = 55.0
	var p: Vector3 = m.body.global_position
	cam.global_position = p + Vector3(2.4, 1.5, -2.2)
	cam.look_at(p + Vector3(0, 0.9, 0))
	cam.current = true
	await shot("25_blood_hit")
	await frames(90)
	m.stick_vec = Vector2(0, -1)
	for i in 220: await tree.physics_frame
	m.stick_vec = Vector2.ZERO
	await frames(10)
	var q: Vector3 = m.body.global_position
	cam.global_position = (p + q) / 2.0 + Vector3(2.2, 2.6, 0.0)
	cam.look_at((p + q) / 2.0)
	await frames(20)
	await shot("25_blood_trail")
	cam.global_position = p + Vector3(0.9, 0.8, 0.9)
	cam.look_at(p)
	await frames(10)
	await shot("25_blood_pool")
	m.queue_free()
	await frames(5)
	# --- «بين العصر والمغرب»
	var g = await round_of("village", "sunset", 9)
	var gc := Camera3D.new()
	g.add_child(gc)
	gc.fov = 62.0
	gc.global_position = Vector3(-24, 12, 70) # looking toward where the sun goes down
	gc.look_at(Vector3(6, 7, -30))
	gc.current = true
	for v in [["25_sunset_1_afternoon", 20.0], ["25_sunset_2_golden", 205.0], ["25_sunset_3_red", 262.0], ["25_sunset_4_dusk", 288.0], ["25_sunset_5_dark", 310.0]]:
		g.rules.clock = v[1]
		await frames(60)
		await shot(v[0])
	g.rules.grid = true
	await frames(90)
	await shot("25_sunset_6_lights_on")
	g.queue_free()
	await frames(5)
	# --- Halloween: lit, then switched off
	var h = await round_of("forest", "halloween", 7)
	var hc := Camera3D.new()
	h.add_child(hc)
	hc.fov = 62.0
	hc.global_position = h.world.power_box + Vector3(-10, 6, -10)
	hc.look_at(h.world.power_box + Vector3(10, 0, 10))
	hc.current = true
	await frames(30)
	await shot("25_halloween_lit")
	for e in h.rules.handle({"k": "off"}, "P"): h._on_event(e)
	await frames(90)
	await shot("25_halloween_off")
	print("shot25 done")
	tree.quit()
