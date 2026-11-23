extends Node
## The graphics pass: decals, campfire flames, the rain weather and its lightning, the colour
## grade per map, MetalFX only on Metal.
var tree: SceneTree
var bad := 0

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok: bad += 1

func boot(map: String, theme: String):
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(10)
	m._start({"map": map, "me": "P", "offline": true, "theme": theme, "players": [
		{"name": "P", "role": "survivor", "char": "survivor2", "slot": 0},
		{"name": "K", "role": "killer", "char": "killer", "slot": 1}]})
	for i in 900:
		await tree.process_frame
		if m.world.ready_done: break
	await frames(10)
	return m

func _ready() -> void:
	tree = get_tree()
	for t in ["blood", "drag", "oil", "dirt", "puddle", "puddle_orm", "soft", "streak"]:
		var tx := NFDecor.tex(t)
		check(tx != null and tx.get_width() == 128, "texture %s drawn" % t)
	for t in ["gun", "bag", "vault", "crouch", "torch", "sig", "heal", "hand", "sprint"]:
		check(load("res://assets/ui/btn/%s.png" % t) != null, "button picture %s" % t)
	for t in ["gen_on", "gen_off", "market", "hook", "gate_n", "gate_s", "hatch"]:
		check(load("res://assets/ui/map/%s.png" % t) != null, "map picture %s" % t)
	var m = await boot("forest", "normal")
	var w: NightWorld = m.world
	var ds := w.find_children("*", "Decal", true, false).size()
	print("forest: %d decals, %d fires" % [ds, w.fire_fx])
	check(ds >= w.hook_points.size() / 2 + 7 and ds == w.decals, "blood under the hooks, oil by the generators, stains about (%d)" % ds)
	check(w.fire_fx == w.campfires, "every campfire burns with real flames (%d of %d)" % [w.fire_fx, w.campfires])
	check(w.env.adjustment_color_correction == null, "no colour-correction curve (it burnt the colours on screen)")
	check(w.rain == null, "no rain on a dry night")
	check(not Gfx.metalfx_temporal() and get_viewport().scaling_3d_mode != Viewport.SCALING_3D_MODE_METALFX_TEMPORAL, "MetalFX stays off away from Metal")
	m.queue_free()
	await frames(20)
	m = await boot("beach", "rain")
	w = m.world
	check(w.rain != null and w.rain.emitting, "the rain falls")
	var puddles := 0
	for d in w.find_children("*", "Decal", true, false):
		if (d as Decal).texture_orm != null: puddles += 1
	check(puddles > 0, "puddles shine (%d)" % puddles)
	var below := 0
	for d in w.find_children("*", "Decal", true, false):
		if (d as Decal).global_position.z > NightWorld.BEACH_SHORE + 1.0 and (d as Decal).global_position.y < 0.5: below += 1
	check(below <= 6, "nothing laid in the lagoon (%d near the road/pier)" % below)
	var base: float = w.moon.light_energy
	w._bolt = 1.0
	await frames(2)
	check(w.moon.light_energy > base * 1.5, "the lightning lights the map (%.2f -> %.2f)" % [base, w.moon.light_energy])
	for i in 600:
		await tree.process_frame
		if w._bolt <= 0.0: break
	await frames(2)
	check(absf(w.moon.light_energy - w._moon_base) < 0.01, "and fades back")
	check(w.look_kind() == "rain", "the rain look")
	m.queue_free()
	await frames(20)
	m = await boot("rubkhali", "normal")
	w = m.world
	check(w.animal_models >= 6, "the owner's horses and camels (%d models)" % w.animal_models)
	var walking := 0
	for an in w.animals:
		if an.ap and (an.ap as AnimationPlayer).is_playing(): walking += 1
	check(walking >= 4, "the horses move on their own clips (%d)" % walking)
	check(w.scenery >= 10, "dunes on the horizon (%d)" % w.scenery)
	m.queue_free()
	await frames(20)
	m = await boot("forest", "fog")
	check(m.world.scenery >= 6, "forest floor patches (%d)" % m.world.scenery)
	var sky: ShaderMaterial = (m.world.env.sky.sky_material as ShaderMaterial)
	check(sky.get_shader_parameter("has_moon_tex") == 1.0 and sky.get_shader_parameter("moon_tex") != null, "the owner's moon in the sky")
	m.queue_free()
	await frames(20)
	m = await boot("garage", "rain")
	check(m.world.rain == null, "no rain under the car park's slab")
	m.queue_free()
	await frames(10)
	print("GFX DONE bad=%d" % bad)
	tree.quit()
