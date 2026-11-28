extends Node
## «The Moon», stage 2: the rocket chase — boarding, lift-off, flying, the boost, a meteor strike, the
## computer killer taking off after it, reaching the Earth; and in the rules alone: the ram and the clock.
var tree: SceneTree
var bad := 0

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok: bad += 1

func _ready() -> void:
	tree = get_tree()
	_rules_only()
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(10)
	m._start({"map": "moon", "me": "P", "offline": true, "seed": 4242, "theme": "normal", "players": [
		{"name": "P", "role": "survivor", "char": "survivor1", "slot": 0},
		{"name": "K", "role": "killer", "char": "killer4", "slot": 2, "bot": true}]})
	for i in 1500:
		await tree.process_frame
		if m.world.ready_done: break
	await frames(30)
	var w: NightWorld = m.world
	check(m.flight != null and m.flight.meteor_count() > 400, "the flight and its meteor field are ready (%d meteors)" % (m.flight.meteor_count() if m.flight else 0))
	check(w.kship_node != null and w.kship_spot != Vector3.INF, "her spaceship waits on the pad")
	m.rules.gate_delay = 0.0
	for g in 5: m.rules.gens[g].p = 1.0; m.rules.gens[g].done = true
	await frames(20)
	check(m.rules.powered, "the gates have power")
	m.body.position = NightWorld.MOON_BOARD + Vector3(0, 0.3, 0)
	await frames(4)
	check(m.rules.in_rocket("P") and str(m.rules.fl.pil) == "P", "on the ring: into the rocket, at the controls")
	await frames(10)
	check(int(m.rules.fl.st) == 1 and float(m.rules.fl.t) <= Rules.COUNTDOWN, "nobody else to wait for: the five-second countdown (st %d, %.1f s)" % [int(m.rules.fl.st), float(m.rules.fl.t)])
	for i in 400:
		await tree.physics_frame
		if int(m.rules.fl.st) == 2: break
	check(int(m.rules.fl.st) == 2, "lift-off after the countdown")
	await frames(30)
	check(m.flight.me_mode() == "lift" and m.flight.cam.current and m.flight.r_vel.z == 0.0, "on the pad at zero speed until the throttle goes up (%s, %.1f m/s)" % [m.flight.me_mode(), m.flight.r_vel.z])
	check(m.flight.lever_on(), "the pilot has the throttle lever")
	# the lever by touch: press it at the top
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	var lr: Rect2 = m.flight.lever_rect(vs)
	var te := InputEventScreenTouch.new()
	te.index = 3; te.pressed = true; te.position = Vector2(lr.get_center().x, lr.position.y + 10.0)
	m._input(te)
	check(m.flight.throttle > 0.95, "a touch at the top of the lever: full throttle (%.2f)" % m.flight.throttle)
	te.pressed = false
	m._input(te)
	for i in 60: await tree.physics_frame
	check(m.flight.r_vel.z > 5.0 and m.flight.r_vel.z < 40.0, "it gathers speed slowly (%.1f m/s after 1 s)" % m.flight.r_vel.z)
	check(w.rocket.position.y > NightWorld.MOON_ROCKET.y + 2.0, "the rocket rises off its mount (%.1f m)" % (w.rocket.position.y - NightWorld.MOON_ROCKET.y))
	for i in 600:
		await tree.physics_frame
		if m.flight.me_mode() == "fly": break
	await frames(5)
	check(m.flight.me_mode() == "fly" and m.flight.shown and m.flight.cam.current, "in flight, the flight camera on")
	check(NFFlight.in_space(m.body.position), "my position is up in the flight (%s)" % m.body.position.snappedf(1))
	for i in 700: await tree.physics_frame
	var v0: float = m.flight.r_vel.z
	check(absf(v0 - NFFlight.CRUISE) < 15.0 or float(m.rules.fl.dm) > 0.0, "full throttle: cruising at %d m/s" % roundi(v0))
	m.flight.throttle = 0.5
	for i in 400: await tree.physics_frame
	check(absf(m.flight.r_vel.z - NFFlight.CRUISE * 0.5) < 10.0 or float(m.rules.fl.dm) > 0.0, "half throttle: %d m/s" % roundi(m.flight.r_vel.z))
	m.flight.throttle = 1.0
	# the cabin: eight seats inside the hull, me in the first
	check(m.flight.cabin != null and NFFlight.SEATS.size() == 8, "the cabin has eight seats")
	var inside_ok := true
	for sp in NFFlight.SEATS:
		var p3: Vector3 = sp
		# the seat's back and a rider's shoulders reach ~0.3 m out, the head ~0.75 m up, knees 0.5 m forward
		for q in [p3 + Vector3(0.32 * signf(p3.x), 0.0, 0.0), p3 + Vector3(0.25 * signf(p3.x), 0.8, 0.0), p3 + Vector3(0.0, -0.5, -0.55)]:
			if Vector2(q.x, q.y).length() > NFFlight.CAB_R - 0.05 or q.z < NFFlight.CAB_FRONT or q.z > NFFlight.CAB_BACK: inside_ok = false
	check(inside_ok and NFFlight.CAB_R < 1.8, "every seat and rider fits inside the cabin, and the cabin inside the hull (r %.2f)" % NFFlight.CAB_R)
	await frames(3)
	m.flight._seat_riders() # (main's physics step puts my body back each tick; on screen the seat wins, it runs last)
	var seat0: Vector3 = m.flight.seat_xf(0).origin
	check(m.rig.visible and m.rig.global_position.distance_to(seat0) < 0.05, "my character sits in seat 1 (%.2f m off)" % m.rig.global_position.distance_to(seat0))
	var btn: Array = m._buttons()
	var ids := btn.map(func(b): return b[3])
	check("fboost" in ids and "fview" in ids, "alone aboard: the pilot has the boost and the camera button (%s)" % str(ids))
	m._press("fview", 0)
	await frames(3)
	var cl: Vector3 = m.flight.rocket.global_transform.affine_inverse() * m.flight.cam.global_position
	check(m.flight.inside and Vector2(cl.x, cl.y).length() < NFFlight.CAB_R and cl.z > NFFlight.CAB_FRONT and cl.z < NFFlight.CAB_BACK and not m.rig.visible, "the inside view: the camera in the cabin at my seat (%s)" % cl.snappedf(0.01))
	m._press("fview", 0)
	await frames(2)
	check(not m.flight.inside, "and back outside")
	# her ship this near is a catch: 70 m from the hull
	var kl0: Vector3 = m.flight.k_loc
	m.flight.k_loc = m.flight.r_loc + Vector3(30.0, 0.0, -(NFFlight.ROCKET_HALF + 55.0))
	check(m.flight.catch_dist() < 70.0, "she is %.0f m off the hull: caught" % m.flight.catch_dist())
	m.flight.k_loc = m.flight.r_loc + Vector3(30.0, 0.0, -(NFFlight.ROCKET_HALF + 80.0))
	check(m.flight.catch_dist() > 70.0, "at %.0f m: not yet" % m.flight.catch_dist())
	m.flight.k_loc = kl0
	var vb: float = m.flight.r_vel.z
	m._press("fboost", 0)
	await frames(2)
	check(bool(m.rules.fl.b), "the boost is on")
	for i in 120: await tree.physics_frame
	check(m.flight.r_vel.z > vb + 40.0 or float(m.rules.fl.dm) > 0.0, "boosting: %d -> %d m/s" % [roundi(vb), roundi(m.flight.r_vel.z)])
	check(float(m.rules.fl.e) < 1.0, "the boost tank drains (%.2f)" % float(m.rules.fl.e))
	# fly into a meteor on purpose
	var tgt := -1
	for i in m.flight.met.size():
		var e: Array = m.flight.met[i]
		if int(e[4]) == 0 and float(e[0]) > m.flight.r_loc.z + 300.0 and not m.flight.gone.has(i) and not m.flight.sent.has(i) and absf(float(e[1])) < 55.0 and absf(float(e[2])) < 35.0:
			tgt = i; break
	var mp: Array = m.flight.meteor_at(tgt, m.flight.clk)
	m.flight.r_loc = Vector3(mp[0].x, mp[0].y, float(m.flight.met[tgt][0]) - 2.0)
	await tree.physics_frame
	await frames(3)
	check(m.flight.gone.has(tgt) and tgt in m.rules.fl.hits, "a meteor strike: it is gone, the rules have it")
	check(float(m.rules.fl.dm) > 0.0, "the engine is damaged (%.1f s)" % float(m.rules.fl.dm))
	for i in 30: await tree.physics_frame
	check(m.flight.r_vel.z < NFFlight.CRUISE, "and the rocket slows (%d m/s)" % roundi(m.flight.r_vel.z))
	# the computer killer takes her ship once she could have reached it
	for i in 1500:
		await tree.physics_frame
		if m.flight.k_on: break
	check(bool(m.rules.fl.ks) and m.flight.k_on, "the computer killer took off after the rocket (c %.1f)" % float(m.rules.fl.c))
	var kz0: float = m.flight.k_loc.z
	for i in 120: await tree.physics_frame
	check(m.flight.k_loc.z > kz0 + 100.0, "and flies down the line (%d -> %d m)" % [roundi(kz0), roundi(m.flight.k_loc.z)])
	check(m.remotes["K"].node.visible == false, "her body is not drawn on the Moon while she flies")
	check(m.flight.kship.visible and m.flight.rocket.visible, "both ships are drawn")
	# to the Earth
	m.flight.r_loc.z = Rules.FLY_LEN - 30.0
	m.flight.k_loc.z = 0.0
	for i in 30:
		await tree.physics_frame
		if int(m.rules.fl.st) == 3: break
	check(int(m.rules.fl.st) == 3 and m.rules.hp("P") == "escaped", "at the Earth: everyone aboard is out (%s)" % m.rules.hp("P"))
	await frames(10)
	check(m.ending != null and m.ending.won and m.ending.cam.current, "the ending film plays: HUMANITY SURVIVED")
	check(m.results == null, "the numbers wait for the film")
	for i in 1400:
		await tree.process_frame
		if m.results != null: break
	check(m.results != null and m.ending == null, "after the film, the results (%.1f s of film)" % NFEnding.WIN_LEN)
	print("FLIGHT %s (%d failed)" % ["PASS" if bad == 0 else "FAIL", bad])
	tree.quit(1 if bad else 0)

## The rules alone: the countdown, who does what, the ram, the clock.
func _rules_only() -> void:
	var r := Rules.new()
	r.moon = true
	r.doom_time = Rules.DOOM_MOON
	r.setup(5, 2, 0, 0, [{"name": "A", "role": "survivor", "char": "survivor1"}, {"name": "B", "role": "survivor", "char": "survivor2"},
		{"name": "C", "role": "survivor", "char": "survivor3"}, {"name": "K", "role": "killer", "char": "killer"}], 1)
	r.gate_delay = 0.0
	for g in r.gens: g.p = 1.0; g.done = true
	r.tick(0.1); r.tick(0.1)
	check(r.powered, "rules: powered")
	r.handle({"k": "escape"}, "A")
	r.handle({"k": "escape"}, "B")
	check(r.in_rocket("A") and str(r.fl.pil) == "A" and str(r.fl.bst) == "B" and int(r.fl.st) == 1, "rules: first in steers, second boosts, the countdown runs")
	check(not r.free_now("A") and r.handle({"k": "hit", "n": "A"}, "K").is_empty() and r.hp("A") == "ok", "rules: nobody can touch them aboard")
	r.handle({"k": "kship"}, "K")
	check(not bool(r.fl.ks), "rules: her ship cannot leave before the rocket")
	for i in 60: r.tick(0.1)
	check(int(r.fl.st) == 1, "rules: still waiting for C after 6 s")
	for i in 100: r.tick(0.1)
	check(int(r.fl.st) == 2, "rules: lift-off when the wait ends (C stayed behind)")
	r.handle({"k": "boost", "on": true}, "A")
	check(not bool(r.fl.b), "rules: only the booster fires the boost")
	r.handle({"k": "boost", "on": true}, "B")
	check(bool(r.fl.b), "rules: the booster does")
	for i in 100: r.tick(0.1)
	check(float(r.fl.c) >= Rules.KSHIP_LOCK, "rules: the clock runs (%.1f)" % float(r.fl.c))
	r.handle({"k": "kship"}, "K")
	check(bool(r.fl.ks), "rules: she takes off")
	check(r.handle({"k": "hit", "n": "C"}, "K").is_empty() and r.hp("C") == "ok", "rules: in her ship she cannot hit anyone on the Moon")
	r.handle({"k": "mhit", "m": 12}, "A")
	r.handle({"k": "mhit", "m": 12}, "A")
	check(float(r.fl.dm) > 0.0 and (r.fl.hits as Array).count(12) == 1, "rules: a meteor strike damages the engine, once")
	var snap := r.snapshot()
	var r2 := Rules.new()
	r2.setup(5, 2, 0, 0, [{"name": "A", "role": "survivor", "char": "survivor1"}, {"name": "K", "role": "killer", "char": "killer"}], 1)
	r2.apply(JSON.parse_string(JSON.stringify(snap)))
	check(int(r2.fl.st) == 2 and str(r2.fl.pil) == "A" and 12 in (r2.fl.hits as Array), "rules: the flight goes through a snapshot")
	r.handle({"k": "rram"}, "K")
	check(int(r.fl.st) == 4 and r.hp("A") == "dead" and r.hp("B") == "dead" and r.hp("C") == "ok", "rules: rammed — everyone aboard is lost, the one left behind is not")
	# out of time
	var t := Rules.new()
	t.moon = true
	t.setup(5, 2, 0, 0, [{"name": "A", "role": "survivor", "char": "survivor1"}, {"name": "K", "role": "killer", "char": "killer"}], 1)
	t.gate_delay = 0.0
	for g in t.gens: g.p = 1.0; g.done = true
	t.tick(0.1); t.tick(0.1)
	t.handle({"k": "escape"}, "A")
	t.tick(0.1)
	check(int(t.fl.st) == 1 and float(t.fl.t) <= Rules.COUNTDOWN, "rules: everyone aboard — five seconds")
	for i in 52: t.tick(0.1)
	check(int(t.fl.st) == 2, "rules: and lift-off")
	for i in int(Rules.FLIGHT_TIME * 10.0) + 20: t.tick(0.1)
	var big := Rules.new()
	big.moon = true
	var eight := []
	for i in 9: eight.append({"name": "S%d" % i, "role": "survivor", "char": "survivor1"})
	eight.append({"name": "K", "role": "killer", "char": "killer"})
	big.setup(5, 2, 0, 0, eight, 1)
	big.gate_delay = 0.0
	for g in big.gens: g.p = 1.0; g.done = true
	big.tick(0.1); big.tick(0.1)
	for i in 9: big.handle({"k": "escape"}, "S%d" % i)
	check((big.fl.who as Array).size() == 8 and not big.in_rocket("S8"), "rules: the rocket seats eight, a ninth stays behind")
	check(int(t.fl.st) == 4 and str(t.fl.why) == "time" and t.hp("A") == "dead", "rules: the clock runs out — lost")
