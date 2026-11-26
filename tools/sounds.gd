extends Node
## The owner's sound pack: every file loads, the loops loop, each map gets its own night, the
## footsteps follow who is walking (her, the beast, a limp), the heartbeat speeds up, the car has its door,
## brakes and radio static, and the music, the campfire and the radio's song are untouched.
var tree: SceneTree
var bad := 0

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok: bad += 1

func _ready() -> void:
	tree = get_tree()
	for f in ["ambient.mp3", "chase.mp3", "doom.mp3", "campfire.mp3", "radio.mp3", "adhan.mp3"]:
		check(ResourceLoader.exists("res://assets/sfx/" + f), "music kept: " + f)
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(10)
	m._start({"map": "beach", "me": "P", "offline": true, "seed": 77, "theme": "normal", "players": [
		{"name": "P", "role": "survivor", "char": "survivor1", "slot": 0},
		{"name": "D", "role": "survivor", "char": "survivor3", "slot": 1},
		{"name": "K", "role": "killer", "char": "killer2", "slot": 2}]})
	for i in 1500:
		await tree.process_frame
		if m.world.ready_done: break
	await frames(20)
	var missing := []
	for n in m.SFX:
		if m.sounds.get(n) == null: missing.append(n)
	check(missing.is_empty(), "every sound loads (%d; missing %s)" % [m.SFX.size(), str(missing)])
	var not_loop := []
	for n in m.SFX_LOOPS:
		if m.sounds.get(n) != null and not bool(m.sounds[n].get("loop")): not_loop.append(n)
	check(not_loop.is_empty(), "the loops loop (%s)" % str(not_loop))
	check(m.beds.has("amb_night") and m.beds.amb_night.playing, "the beach: the night around it")
	check(m.beds.has("amb_sea"), "and the sea")
	m.body.global_position = Vector3(0, 1, NightWorld.BEACH_SHORE - 5.0)
	for i in 60: m._step_beds(0.05, 0.0)
	check(m.beds.amb_sea.playing and m.beds.amb_sea.volume_db > -20.0, "loud by the water (%.1f dB)" % m.beds.amb_sea.volume_db)
	# footsteps by who walks
	var a := AudioStreamPlayer.new()
	m.add_child(a)
	m._steps(a, Vector3.ZERO, true, false, 0.0, "beast")
	check(a.stream == m.sounds.steps_beast, "the beast's tread")
	m._steps(a, Vector3.ZERO, true, false, 0.0, "killer")
	check(a.stream == m.sounds.steps_killer, "her heavy tread")
	m._steps(a, Vector3.ZERO, true, false, 0.0, "hurt")
	check(a.stream == m.sounds.steps_hurt, "a survivor limping: the slow, exhausted steps")
	m._steps(a, Vector3.ZERO, true, false, 0.0, "")
	check(a.stream == m.sounds.steps_out or a.stream == m.sounds.steps_in, "and the ordinary ones otherwise")
	# the heartbeat: slow far off, fast up close
	m.rules.ev_at = 99999.0
	var kp: Vector3 = m.body.global_position + Vector3(3, 0, 0)
	m.remotes["K"].pos = kp
	(m.remotes["K"].node as Node3D).global_position = kp
	await frames(30)
	check(m.danger > 0.6 and m.heart.stream == m.sounds.heart_fast, "she is right there: the fast heartbeat (danger %.2f)" % m.danger)
	# the car
	var car = m.world.find_children("*", "NFCar", true, false)
	var c = m.car if m.car else (car[0] if car.size() > 0 else null)
	check(c != null and c.extra.has("car_door") and c.extra.has("brake") and c.extra.has("radio_on"), "the car: door, brakes, the radio's static")
	print("SOUNDS %s %d" % ["PASS" if bad == 0 else "FAIL", bad])
	get_tree().quit(1 if bad else 0)
