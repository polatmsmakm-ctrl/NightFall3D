extends Node
## The killer's car: get in, drive, steer, run a survivor down, get out; down the garage ramp
## from the roof; and on a survivor's phone, the car following what the killer reports.

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
		if m.world.ready_done and m.car != null: break
	await frames(5)
	return m

func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _ready() -> void:
	tree = get_tree()
	var players := [{"name": "P", "role": "killer", "char": "killer", "slot": 0},
		{"name": "D", "role": "survivor", "char": "survivor5", "slot": 1, "dummy": true}]
	# ---------------- forest: the whole loop ----------------
	var m = await boot("forest", players)
	var car: NFCar = m.car
	check(car != null, "the car is there")
	m.body.position = car.position + car.global_basis.x * 2.4 + Vector3(0, 0.3, 0)
	await frames(6)
	check(m.ctx.get("interact", {}).get("kind", "") == "car_in", "next to it the button says اركب")
	m._press("interact", 5)
	await frames(3)
	check(m.driving and m.arm.spring_length > 5.0, "in the seat, camera behind the car")
	check(m.cshape.disabled, "the killer's own body is out of the way")
	# run the dummy down: put it 7 m in front, on the ground, and floor it
	var d = m.remotes["D"]
	m.rules.s["D"].hp = "ok"
	var ahead: Vector3 = car.position + car.forward() * 7.0
	ahead.y = m.world.height(ahead.x, ahead.z)
	d.pos = ahead
	d.node.position = ahead
	m.stick_vec = Vector2(0, -1)
	for i in 160:
		await frames(1)
		d.node.position = ahead
		if m.rules.hp("D") != "ok": break
	check(m.rules.hp("D") == "hurt", "the car hit the survivor: %s" % m.rules.hp("D"))
	m.stick_vec = Vector2.ZERO
	await frames(60)
	var start: Vector3 = car.position
	m.stick_vec = Vector2(0, -1)
	await frames(150)
	var sp: float = car.speed
	check(sp > 6.0 or flat(car.position, start) > 12.0, "gas: %.1f m/s, %.1f m" % [sp, flat(car.position, start)])
	check(flat(m.body.position, car.position) < 0.2, "the killer rides with it (what the others are sent)")
	var y0: float = car.rotation.y
	m.stick_vec = Vector2(1, -1)
	await frames(60)
	check(absf(wrapf(car.rotation.y - y0, -PI, PI)) > 0.4, "steering turns it (%.2f rad)" % wrapf(car.rotation.y - y0, -PI, PI))
	m.stick_vec = Vector2(0, 1)
	await frames(120)
	check(car.speed < 0.5, "pulling back brakes, then reverses (%.1f)" % car.speed)
	m.stick_vec = Vector2.ZERO
	await frames(90)
	check(m.ctx.get("interact", {}).get("kind", "") == "car_out", "at the wheel the button says انزل")
	m._press("interact", 5)
	await frames(10)
	check(not m.driving and m.arm.spring_length < 0.5, "out, first person again")
	check(flat(m.body.position, car.position) > 1.4, "standing beside it, not inside it (%.1f m)" % flat(m.body.position, car.position))
	check(not m.cshape.disabled, "the killer's body is solid again")
	var parked: Vector3 = car.position
	m.stick_vec = Vector2(0, -1)
	await frames(60)
	m.stick_vec = Vector2.ZERO
	check(car.position.distance_to(parked) < 0.2, "the car stays put once he is out")
	m.queue_free()
	await frames(5)
	# ---------------- the garage: from the roof down the ramp ----------------
	m = await boot("garage", players)
	car = m.car
	check(car.position.y > NightWorld.GAR_ROOF - 0.5, "garage: the car is on the roof (y %.1f)" % car.position.y)
	m.body.position = car.position + car.global_basis.x * 2.4 + Vector3(0, 0.3, 0)
	await frames(6)
	m._press("interact", 5)
	await frames(3)
	m.stick_vec = Vector2(0, -0.8)
	var low := 99.0
	for i in 600:
		await frames(1)
		low = minf(low, car.position.y)
		if car.position.y < 0.8: break
	print("   garage: car at ", car.position.snappedf(0.1))
	check(low < 1.0, "drove down the ramp to the floor (lowest y %.1f)" % low)
	m.stick_vec = Vector2.ZERO
	m.queue_free()
	await frames(5)
	# ---------------- a survivor's phone: the car follows the killer's reports ----------------
	m = await boot("forest", [{"name": "P", "role": "survivor", "char": "survivor5", "slot": 0},
		{"name": "K", "role": "killer", "char": "killer", "slot": 0}])
	car = m.car
	var k = m.remotes["K"]
	var to: Vector3 = car.position + car.forward() * 6.0
	k.anim = "drive"
	k.pos = to
	k.yaw = car.rotation.y + 0.5
	await frames(60)
	for i in 30: await tree.process_frame
	check(car.driven and car.position.distance_to(to) < 0.6, "the car follows the killer's position")
	check(not k.node.visible, "the killer is out of sight while he drives")
	check(car.lights.light_energy > 2.0, "headlights on while someone drives")
	k.anim = "idle"
	k.pos = car.position + car.global_basis.x * 2.2
	for i in 40: await tree.process_frame
	check(not car.driven and k.node.visible, "he got out: lights off, he is back")
	m.queue_free()
	await frames(5)
	print("drive check: ", "FAILED %d" % bad if bad else "all good")
	if bad: push_error("DRIVE FAIL")
	tree.quit(1 if bad else 0)
