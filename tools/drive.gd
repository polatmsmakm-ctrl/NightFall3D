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
	if Gfx.strong:
		check(Gfx.preset == 2 and Gfx.maxed(), "a strong device starts on «فائق»")
		check(m.hd_chars() and m.rig.model.scene_file_path.ends_with("_hi.glb"), "and plays the round with the close-up model (%s)" % m.rig.model.scene_file_path.get_file())
	print("   forest car at ", car.position.snappedf(0.1), " yaw ", snappedf(car.rotation.y, 0.01))
	var home: Vector3 = car.position
	var home_yaw: float = car.rotation.y
	m.body.position = car.position + car.global_basis.x * 2.4 + Vector3(0, 0.3, 0)
	await frames(6)
	check(m.ctx.get("interact", {}).get("kind", "") == "car_in", "next to it the button says اركب")
	m._press("interact", 5)
	await frames(3)
	check(m.driving and m.car_inside and car.inside.visible and m.arm.spring_length < 0.1, "in the driver's seat, the cabin around him")
	await frames(2)
	check(m.main_cam.global_position.distance_to(car.eye()) < 0.35, "the camera is at the driver's eyes (%.2f m off)" % m.main_cam.global_position.distance_to(car.eye()))
	m._press("attack", 5)
	await frames(2)
	check(not m.car_inside and not car.inside.visible and m.arm.spring_length > 5.0, "the attack button switches to the camera behind the car")
	m._press("attack", 5)
	await frames(2)
	check(m.car_inside and car.inside.visible, "and back into the seat")
	check(m.rules.carrying == "" and m.attack_t <= 0.0, "no swing at the wheel")
	check(car.radio != null, "the car has the radio song")
	m._press("power", 5)
	await frames(3)
	check(car.radio_on and car._radio_started and not car.radio.stream_paused, "the power button turns the radio on")
	var lab := ""
	for bt in m._buttons():
		if bt[3] == "power": lab = bt[2]
	check(lab == "سكّر الراديو", "the button now says سكّر الراديو (%s)" % lab)
	m._press("power", 5)
	await frames(3)
	check(not car.radio_on and car.radio.stream_paused, "and off again (paused, not restarted)")
	m._press("power", 5)
	await frames(3)
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
	car.position = home # back to where it was parked: the lane in front of it is known to be clear
	car.rotation.y = home_yaw
	car.speed = 0.0
	car.velocity = Vector3.ZERO
	await frames(5)
	var start: Vector3 = car.position
	m.stick_vec = Vector2(0, -1)
	await frames(150)
	var sp: float = car.speed
	check(sp > 6.0 or flat(car.position, start) > 12.0, "gas: %.1f m/s, %.1f m" % [sp, flat(car.position, start)])
	check(absf(car.spin) > 0.01, "the wheels turn while it drives (%.2f rad)" % car.spin)
	check(car.steer_node != null and car.hands.size() == 2 and car.arms.size() == 2, "a steering wheel with two gloved hands on it")
	for i in car.get_slide_collision_count(): # what it is pushing against, if anything
		var col := car.get_slide_collision(i)
		print("   touching ", (col.get_collider() as Node).get_path() if col.get_collider() is Node else "?", " normal ", col.get_normal().snappedf(0.01))
	check(flat(m.body.position, car.position) < 0.2, "the killer rides with it (what the others are sent)")
	var y0: float = car.rotation.y
	m.stick_vec = Vector2(1, -1)
	await frames(60)
	check(absf(wrapf(car.rotation.y - y0, -PI, PI)) > 0.4, "steering turns it (%.2f rad)" % wrapf(car.rotation.y - y0, -PI, PI))
	if car.steer_node:
		var turned := car.steer_node.basis.get_rotation_quaternion().get_angle()
		check(turned > 1.0, "the steering wheel turns with it (%.2f rad)" % turned)
	check(m.speedo_kmh > 1.0, "the speedometer reads %.0f km/h" % m.speedo_kmh)
	m.stick_vec = Vector2(0, 1)
	await frames(120)
	check(car.speed < 0.5, "pulling back brakes, then reverses (%.1f)" % car.speed)
	m.stick_vec = Vector2.ZERO
	await frames(90)
	check(m.ctx.get("interact", {}).get("kind", "") == "car_out", "at the wheel the button says انزل")
	m._press("interact", 5)
	await frames(10)
	check(not m.driving and m.arm.spring_length < 0.5 and not car.inside.visible, "out, first person again, cabin hidden")
	check(car.radio_on and car.radio.stream_paused, "the radio stays switched on but goes quiet when he gets out")
	check(absf(m.cam_pivot.position.y - 1.6) < 0.01, "the camera is back at his own eyes")
	check(flat(m.body.position, car.position) > 1.4, "standing beside it, not inside it (%.1f m)" % flat(m.body.position, car.position))
	check(not m.cshape.disabled, "the killer's body is solid again")
	# the wheels roll and steer (car_drive.glb has them on their own axles)
	check(car.wheels.size() == 4, "the car has four wheels on axles (%d)" % car.wheels.size())
	# carry a downed survivor to the car, drive to a hook, hang them from the driver's seat
	m.rules.s["D"].hp = "down"
	d.pos = m.body.position + Vector3(1.0, 0, 0)
	d.node.position = d.pos
	await frames(4)
	m._ev({"k": "pickup", "n": "D"})
	await frames(4)
	check(m.rules.carrying == "D", "picked the survivor up")
	m.body.position = car.position + car.global_basis.x * 2.4 + Vector3(0, 0.3, 0)
	await frames(6)
	check(m.ctx.get("interact", {}).get("kind", "") == "car_in" and m.ctx.interact.label == "حطّه بالسيارة", "carrying, next to the car: «حطّه بالسيارة»")
	m._press("interact", 5)
	await frames(30)
	check(m.driving and m.rules.carrying == "D", "in the car with the survivor")
	var seat: Vector3 = car.seat_spot()
	check(d.node.position.distance_to(seat) < 0.5, "the survivor sits in the passenger seat (%.2f m off)" % d.node.position.distance_to(seat))
	check(d.rig.current == "slump" and absf(d.node.scale.x - NFCar.VICTIM_SCALE) < 0.01, "slumped, at %.2f of their size (%s)" % [d.node.scale.x, d.rig.current])
	check(d.rig.has("slump"), "the slump pose is built on the rig")
	var hk: Vector3 = m.world.hook_points[0]
	car.position = hk + Vector3(3.0, 0.3, 0)
	await frames(10)
	check(m.ctx.get("interact", {}).get("kind", "") == "car_hook", "pulled up at a hook: «انزل وعلّق» (%s)" % m.ctx.get("interact", {}).get("kind", ""))
	m._press("interact", 5)
	await frames(10)
	check(m.rules.hp("D") == "hooked" and not m.driving and m.rules.carrying == "", "hung on the hook straight from the car: %s" % m.rules.hp("D"))
	car.position = home
	car.rotation.y = home_yaw
	m.body.position = car.position + car.global_basis.x * 2.4 + Vector3(0, 0.3, 0)
	await frames(6)
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
	check(not car.radio_on, "radio off while his f is 0")
	k.lit = true
	for i in 10: await tree.process_frame
	check(car.radio_on and car._radio_started and not car.radio.stream_paused, "his radio plays on my phone, from the car")
	k.anim = "idle"
	k.pos = car.position + car.global_basis.x * 2.2
	for i in 40: await tree.process_frame
	check(not car.driven and k.node.visible, "he got out: lights off, he is back")
	check(car.radio.stream_paused, "and the radio stops with him out of the car")
	m.queue_free()
	await frames(5)
	print("drive check: ", "FAILED %d" % bad if bad else "all good")
	if bad: push_error("DRIVE FAIL")
	tree.quit(1 if bad else 0)
