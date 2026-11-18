extends Node
## The road chase: past each gate a 600 m road, one shared escape car, two minutes to the last
## gate. Board, drive, ride along, arrive; caught by her car or by the clock (thrown out, down,
## hooks along the road); the moon does not reach the cars; the server's layout carries it all.

var tree: SceneTree
var bad := 0

func frames(n: int) -> void:
	for i in n: await tree.physics_frame

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok: bad += 1

func boot(map: String, players: Array):
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	for i in 10: await tree.process_frame
	m._start({"map": map, "me": "P", "offline": true, "players": players})
	for i in 900:
		await tree.process_frame
		if m.world.ready_done and not m.world.esc_cars.is_empty(): break
	await frames(5)
	return m

func power(m) -> void:
	for g in 5:
		m.rules.gens[g].p = 0.999
		m.rules.gens[g].reps["D"] = true
	await frames(30)

func put(m, p: Vector3) -> void:
	m.body.position = p + Vector3(0, 0.3, 0)
	m.body.velocity = Vector3.ZERO
	await frames(4)

func events(m, out: Array) -> void:
	for e in out: m._on_event(e)

func _ready() -> void:
	tree = get_tree()
	var duo := [{"name": "P", "role": "survivor", "char": "survivor2", "slot": 0},
		{"name": "D", "role": "survivor", "char": "survivor5", "slot": 1, "dummy": true}]
	# ---------------- the road itself ----------------
	var m = await boot("forest", duo)
	var w: NightWorld = m.world
	check(w.hook_points.size() == w.road_hook0 + 2 * NightWorld.ROAD_HOOKS, "hooks: %d in the map + %d along the roads" % [w.road_hook0, w.hook_points.size() - w.road_hook0])
	check(w.esc_cars.size() == 2, "an escape car behind each gate")
	for i in 2:
		var ec: NFCar = w.esc_cars[i]
		var gp: Vector3 = w.gate_points[i][0]
		print("   car %d at %s, %.1f m past the gate, %.0f m to go, floor %.2f" % [i, ec.global_position.snappedf(0.1), w.road_d(i, ec.global_position), w.road_left(i, ec.global_position), ec.global_position.y - gp.y])
		check(absf(w.road_d(i, ec.global_position) - NightWorld.ESC_AT) < 1.0 and absf(ec.global_position.y - gp.y) < 0.6, "car %d waits on the road past its gate" % i)
		check(ec.forward().dot(w.road_end(i) - gp) > 0.0, "and points down the road")
		check(absf(w.road_end(i).distance_to(gp) - NightWorld.ROAD_LEN) < 0.5, "the last gate is %d m from the first" % roundi(NightWorld.ROAD_LEN))
		var hooks_on := 0
		for h in range(w.road_hook0, w.hook_points.size()):
			if w.road_at(w.hook_points[h]) == i: hooks_on += 1
		check(hooks_on == NightWorld.ROAD_HOOKS, "%d hooks stand on road %d" % [hooks_on, i])
	check(w.is_outside_gate(0, w.road_end(0)) and not w.is_outside_gate(0, w.esc_start(0)), "out only at the last gate")
	# board and drive
	check(m.ctx.get("interact", {}).get("kind", "") != "board", "no car to board before the gates have power")
	await power(m)
	check(m.rules.powered, "gates open")
	var ec1: NFCar = w.esc_cars[1]
	var side := Basis(Vector3.UP, float(w.gate_points[1][1])) * Vector3(1, 0, 0)
	await put(m, ec1.global_position + side * 2.2)
	check(m.ctx.get("interact", {}).get("kind", "") == "board", "next to it the button is «%s»" % m.ctx.get("interact", {}).get("label", ""))
	m._press("interact", 5)
	await frames(6)
	check(m.rules.car_of("P") == 1 and m.esc_i == 1 and m.rules.roads[1].drv == "P" and int(m.rules.roads[1].st) == 1, "first one in drives; the clock runs (%.1f s)" % float(m.rules.roads[1].t))
	check(m.rules.free_now("P") == false, "in the car you are not free to be hit or to repair")
	check(m.cshape.disabled and m.esc_vis, "my body rides in the seat")
	events(m, m.rules.handle({"k": "board", "i": 1}, "D"))
	await frames(4)
	check(m.rules.roads[1].who == ["P", "D"] and m.rules.car_of("D") == 1, "the second one rides with them")
	var dn: Node3D = m.remotes["D"].node
	check(dn.global_position.distance_to(ec1.seat_spot()) < 0.3, "D sits in the passenger seat (%.2f m)" % dn.global_position.distance_to(ec1.seat_spot()))
	var left0 := w.road_left(1, ec1.global_position)
	m.stick_vec = Vector2(0, -1)
	await frames(130) # the door, the key
	var left1 := w.road_left(1, ec1.global_position)
	check(absf(left1 - left0) < 1.0, "no gas until the key has turned (%.1f m)" % (left0 - left1))
	await frames(240)
	var left2 := w.road_left(1, ec1.global_position)
	print("   drove %.1f m in 4 s, %.1f km/h, %.0f m left" % [left1 - left2, absf(ec1.speed) * 3.6, left2])
	check(left1 - left2 > 25.0 and absf(ec1.speed) <= NightWorld.ESC_TOP + 0.2, "it drives down the road, capped at %d km/h" % roundi(NightWorld.ESC_TOP * 3.6))
	check(m._road_view() == 1, "the HUD shows this road")
	check(m.body.global_position.distance_to(ec1.global_position) < 0.1, "my position (what the others get) is the car's")
	m.big_map = true
	await frames(3)
	m.big_map = false
	# the last stretch
	var out: Vector3 = (w.road_end(1) - w.gate_points[1][0]).normalized()
	ec1.global_position = w.road_end(1) - out * 30.0 + Vector3(0, 0.1, 0)
	await frames(240)
	check(m.rules.hp("P") == "escaped" and m.rules.hp("D") == "escaped", "through the last gate: driver %s, rider %s" % [m.rules.hp("P"), m.rules.hp("D")])
	check(int(m.rules.roads[1].st) == 3 and m.esc_i == -1, "the car is done and I am out of it")
	m.stick_vec = Vector2.ZERO
	m.queue_free()
	await tree.process_frame
	# ---------------- caught: by her car, by the clock; the moon ----------------
	m = await boot("forest", duo)
	w = m.world
	await power(m)
	var ec0: NFCar = w.esc_cars[0]
	await put(m, ec0.global_position + Basis(Vector3.UP, float(w.gate_points[0][1])) * Vector3(2.2, 0, 0))
	m._press("interact", 5)
	await frames(6)
	events(m, m.rules.handle({"k": "board", "i": 1}, "D"))
	check(m.esc_i == 0 and m.rules.car_of("D") == 1, "one in each car")
	m.rules.doom = 0.05
	await frames(10)
	check(m.rules.hp("P") == "ok" and m.rules.hp("D") == "ok", "the moon lands; the cars are already out (P %s, D %s)" % [m.rules.hp("P"), m.rules.hp("D")])
	m.stick_vec = Vector2(0, -1)
	await frames(200)
	m.stick_vec = Vector2.ZERO
	events(m, m.rules.handle({"k": "ram", "i": 0}, m.rules.killer))
	await frames(10)
	check(m.rules.hp("P") == "down" and m.rules.car_of("P") == -1 and int(m.rules.roads[0].st) == 2, "rammed: thrown out, down")
	check(w.road_at(m.body.global_position) == 0 and m.body.global_position.distance_to(ec0.global_position) < 6.0, "beside the car, on the road (%.1f m)" % m.body.global_position.distance_to(ec0.global_position))
	check(absf(ec0.speed) < 0.1, "the car stopped dead")
	var near_hook := INF
	for h in range(w.road_hook0, w.hook_points.size()):
		near_hook = minf(near_hook, w.hook_points[h].distance_to(m.body.global_position))
	check(near_hook < 45.0, "a hook within %.0f m" % near_hook)
	m.rules.roads[1].t = 0.1
	await frames(20)
	check(m.rules.hp("D") == "down" and str(m.rules.roads[1].why) == "time", "out of time: the car stops, D is down")
	m.queue_free()
	await tree.process_frame
	# ---------------- the killer's car into theirs ----------------
	m = await boot("forest", [{"name": "P", "role": "killer", "char": "killer", "slot": 0},
		{"name": "D", "role": "survivor", "char": "survivor5", "slot": 1, "dummy": true}])
	w = m.world
	await power(m)
	ec0 = w.esc_cars[0]
	events(m, m.rules.handle({"k": "board", "i": 0}, "D"))
	await frames(4)
	check(m._road_view() == 0, "the killer sees the escape car's road on the HUD")
	m._enter_car()
	await frames(130)
	var car: NFCar = m.car
	car.global_position = ec0.global_position - ec0.forward() * 5.0 + Vector3(0, 0.1, 0)
	car.rotation.y = ec0.rotation.y
	m.stick_vec = Vector2(0, -1)
	await frames(90)
	m.stick_vec = Vector2.ZERO
	check(m.rules.hp("D") == "down" and int(m.rules.roads[0].st) == 2 and str(m.rules.roads[0].why) == "ram", "her car hits theirs: D %s" % m.rules.hp("D"))
	m.queue_free()
	await tree.process_frame
	# ---------------- the car park: the roof gate's road is up in the air ----------------
	m = await boot("garage", duo)
	w = m.world
	for i in 2:
		var ec: NFCar = w.esc_cars[i]
		await frames(30)
		check(absf(ec.global_position.y - (w.gate_points[i][0] as Vector3).y) < 0.6, "garage car %d sits on its road (y %.2f)" % [i, ec.global_position.y])
	m.queue_free()
	await tree.process_frame
	print("ROAD DONE bad=", bad)
	tree.quit()
