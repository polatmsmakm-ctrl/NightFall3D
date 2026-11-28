extends Node
## «The Moon»: five generators, both gates in the south wall, the launch pad and the rocket, 3:30 to it.
var tree: SceneTree
var bad := 0

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok: bad += 1

func put(m, p: Vector3) -> void:
	m.body.position = p + Vector3(0, 0.4, 0)
	m.body.velocity = Vector3.ZERO
	await frames(6)

func _ready() -> void:
	tree = get_tree()
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(10)
	m._start({"map": "moon", "me": "P", "offline": true, "seed": 1969, "theme": "rain", "players": [
		{"name": "P", "role": "survivor", "char": "survivor1", "slot": 0},
		{"name": "D", "role": "survivor", "char": "survivor2", "slot": 1, "dummy": true},
		{"name": "K", "role": "killer", "char": "killer", "slot": 2}]})
	for i in 1500:
		await tree.process_frame
		if m.world.ready_done: break
	await frames(20)
	var w: NightWorld = m.world
	check(w.map_id == "moon" and w.ready_done, "the Moon is built")
	check(m.theme == "normal" and w.theme == "normal", "no rain on the Moon (asked for rain, got %s)" % m.theme)
	check(w.gen_points.size() == 5 and m.rules.gens.size() == 5, "five generators (%d)" % w.gen_points.size())
	check(w.gate_points.size() == 2 and absf(w.gate_points[0][0].z + NightWorld.WALL) < 0.1 and absf(w.gate_points[1][0].z + NightWorld.WALL) < 0.1,
		"both gates in the south wall, onto the launch pad")
	check(w.craters.size() >= 15, "craters in the ground (%d)" % w.craters.size())
	var c0: Array = w.craters[0]
	check(w.height(c0[0], c0[1]) < w.height(c0[0] + c0[2] * 1.0, c0[1]) - 0.5, "a crater is a bowl with a rim (floor %.1f, rim %.1f)" % [w.height(c0[0], c0[1]), w.height(c0[0] + c0[2], c0[1])])
	check(w.moon_props >= 25 and w.rocket != null, "his models on the Moon (%d) and the rocket on its pad" % w.moon_props)
	check(w.esc_cars.is_empty() and w.drive_car == null and w.road_hook0 == w.hook_points.size(), "no escape cars, no killer car, no road hooks")
	check(w.heli_spot == Vector3.INF and m.ravens == null and m.catdog == null, "no helicopter, no ravens, no cat and dog")
	check(float(w._sky_mat.get_shader_parameter("space")) == 1.0 and float(w._sky_mat.get_shader_parameter("has_moon_tex")) == 1.0, "black sky, his stars and the Earth")
	check(m.rules.doom_time == Rules.DOOM_MOON and Rules.DOOM_MOON == 210.0, "3:30 once the gates open")
	var gp: Vector3 = w.gate_points[0][0]
	check(not w.is_outside_gate(0, gp + Vector3(0, 0, -3)) and w.is_outside_gate(0, NightWorld.MOON_BOARD) and w.road_at(NightWorld.MOON_BOARD) == -1,
		"out only at the rocket's boarding ring")
	# the gates are shut: the arch is blocked
	await put(m, gp + Vector3(0, 0, 3.0))
	for i in 40:
		m.body.velocity = Vector3(0, m.body.velocity.y, -4.0)
		await tree.physics_frame
	check(m.body.position.z > -NightWorld.WALL + 0.2, "the shut gate stops you (z %.1f)" % m.body.position.z)
	# power
	m.rules.gate_delay = 0.0
	for g in 5:
		m.rules.gens[g].p = 0.999
		m.rules.gens[g].reps["D"] = true
	await frames(40)
	check(m.rules.powered and m.rules.doom > 200.0, "five done: the gates have power and the clock runs (%.0f s)" % m.rules.doom)
	await frames(30)
	# through the gate and onto the pad
	await put(m, gp + Vector3(0, 0, 3.0))
	for i in 90:
		m.body.velocity = Vector3(0, m.body.velocity.y, -5.0)
		await tree.physics_frame
	print("   through the gate: %s" % m.body.position.snappedf(0.1))
	check(m.body.position.z < -NightWorld.WALL - 12.0 and absf(m.body.position.y) < 0.6, "the open gate's vortex takes you through to the pad, and the pad holds you")
	check(m.warp_rect != null and w.portal_mats.size() == 2 and float(w.portal_mats[0].get_shader_parameter("power")) > 0.5, "a warp flash, and the vortex is racing")
	check(w.outpost_parts >= 10, "his outpost's buildings handed out over the map (%d)" % w.outpost_parts)
	check(w.moon2_parts >= 10, "his second batch on the Moon, the bone mountain beyond the wall (%d)" % w.moon2_parts)
	var eng := 0
	for gn in w.find_children("*", "Node3D", true, false):
		if gn.scene_file_path.ends_with("neon_engine.glb"): eng += 1
	check(eng == 5, "his Neon Steam Engine is every generator (%d)" % eng)
	check(float(w._sky_mat.get_shader_parameter("has_p2")) == 1.0, "Jupiter overhead")
	check(w.moon_rocks > 3000, "his rocks and pebbles all over the ground (%d)" % w.moon_rocks)
	check(m.rules.hp("P") == "ok", "not out yet on the pad")
	m.rules.doom = 100.0
	await frames(10)
	check(float(w._sky_mat.get_shader_parameter("meteor_near")) > 0.2, "the meteor grows in the sky (%.2f)" % float(w._sky_mat.get_shader_parameter("meteor_near")))
	await put(m, NightWorld.MOON_BOARD)
	await frames(10)
	check(m.rules.hp("P") == "escaped", "in the boarding ring: out (%s)" % m.rules.hp("P"))
	# the pad's walls
	m2_walls(m, w)
	await frames(2)
	print("MOON %s (%d failed)" % ["PASS" if bad == 0 else "FAIL", bad])
	tree.quit(1 if bad else 0)

func m2_walls(m, w: NightWorld) -> void:
	var space := w.get_world_3d().direct_space_state
	var hits := 0
	for dir in [Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)]:
		var o := Vector3(30.0, 1.5, -125.0)
		var q := PhysicsRayQueryParameters3D.create(o, o + dir * 120.0)
		q.exclude = [m.body.get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty(): hits += 1
	check(hits == 3, "the pad is walled in on its three sides (%d)" % hits)
