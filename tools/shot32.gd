extends Node
## «The Moon»: the Earth over the base, a gate, the launch pad and the rocket, the meteor coming down.
var tree: SceneTree
var dir := ""

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func shot(name: String) -> void:
	await frames(8)
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
	m._start({"map": "moon", "me": "P", "offline": true, "seed": 1969, "theme": "normal", "players": [
		{"name": "P", "role": "survivor", "char": "survivor9", "slot": 0},
		{"name": "K", "role": "killer", "char": "killer", "slot": 1}]})
	for i in 1500:
		await tree.process_frame
		if m.world.ready_done: break
	await frames(40)
	m.rules.ev_at = 99999.0
	var w: NightWorld = m.world
	var only := OS.get_environment("NF_ONLY")
	var cam := Camera3D.new()
	cam.fov = 62.0
	cam.far = 900.0
	w.add_child(cam)
	cam.current = true
	if m.hud_layer: m.hud_layer.visible = false
	var views := [
		["32_moon_earth", Vector3(8, 3.2, -44), Vector3(40, 11, 18)],
		["32_moon_base", w.market.pos + Vector3(-26, 4.0, -16), w.market.pos + Vector3(0, 2.5, 0)],
		["32_moon_gate", w.gate_points[0][0] + Vector3(10, 3.0, 22), w.gate_points[0][0] + Vector3(0, 3.5, 0)],
		["32_moon_pad", w.gate_points[1][0] + Vector3(-6, 2.5, -6), NightWorld.MOON_ROCKET + Vector3(0, 10, 0)],
		["32_moon_ground", Vector3(-20, 1.6, 30), Vector3(-34, 0.0, 52)],
	]
	for e in w.outpost_at.slice(0, 7):
		var at: Vector3 = e[1]
		var r: float = e[2]
		var dir := Vector3(at.x, 0, at.z).normalized() if Vector3(at.x, 0, at.z).length() > 1.0 else Vector3(0, 0, 1)
		views.append(["32_outpost_" + str(e[0]), at - dir * (r * 2.6) + Vector3(0, r * 0.55 + 2.0, 0), at + Vector3(0, r * 0.35, 0)])
	for v in views:
		var hit := only == ""
		for tok in only.split(",", false): if str(v[0]).begins_with(tok): hit = true
		if not hit: continue
		cam.global_position = v[1]
		cam.look_at(v[2])
		await shot(v[0])
	# a survivor at a generator, with the hud
	if m.hud_layer: m.hud_layer.visible = true
	cam.current = false
	m.main_cam.current = true
	var gp: Vector3 = w.gen_points[0]
	m.body.global_position = gp + Vector3(1.6, 0.4, 1.6)
	await frames(30)
	await shot("32_moon_play")
	# the gates open: the meteor in the sky over the rocket
	m.rules.gate_delay = 0.0
	for g in 5:
		m.rules.gens[g].p = 0.999
		m.rules.gens[g].reps["P"] = true
	await frames(60)
	if m.hud_layer: m.hud_layer.visible = false
	cam.current = true
	cam.global_position = w.gate_points[0][0] + Vector3(4, 2.4, 11)
	cam.look_at(w.gate_points[0][0] + Vector3(0, 3.4, 0))
	await frames(30)
	await shot("32_moon_portal")
	m.rules.doom = 60.0
	await frames(40)
	if m.hud_layer: m.hud_layer.visible = false
	cam.current = true
	cam.global_position = w.gate_points[1][0] + Vector3(-4, 2.0, -4)
	cam.look_at(cam.global_position + NightWorld.MOON_METEOR.normalized() * 10.0 + Vector3(0, -2.5, 0))
	await shot("32_moon_meteor")
	tree.quit()
