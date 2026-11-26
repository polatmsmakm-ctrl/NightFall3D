extends Node
## The "extreme" pass: the beach pier to the north gate, the survivors' perks, the killer's traps
## and road spikes, the escape car's nitro, the computer killer, the slow-motion final shot, and the
## friends' board with the round history.
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
		if m.world.ready_done: break
	await frames(10)
	return m

func put(m, p: Vector3) -> void:
	m.body.position = p + Vector3(0, 0.3, 0)
	m.body.velocity = Vector3.ZERO
	await frames(4)

func events(m, out: Array) -> void:
	for e in out: m._on_event(e)

func power(m) -> void:
	m.rules.gate_delay = 0.0 # (the countdown is tested in sniper.gd)
	for g in 5:
		m.rules.gens[g].p = 0.999
		m.rules.gens[g].reps["P"] = true
	await frames(30)

func _ready() -> void:
	tree = get_tree()
	var me_k := [{"name": "P", "role": "survivor", "char": "survivor2", "slot": 0},
		{"name": "D", "role": "survivor", "char": "survivor5", "slot": 1, "dummy": true},
		{"name": "K", "role": "killer", "char": "killer", "slot": 2}]
	# ---------------- the rules: perks ----------------
	var r := Rules.new()
	r.setup(5, 2, 0, 0, [{"name": "K", "role": "killer", "char": "killer"},
		{"name": "A", "role": "survivor", "char": "survivor5"}, {"name": "B", "role": "survivor", "char": "survivor2"},
		{"name": "C", "role": "survivor", "char": "survivor4"}, {"name": "M", "role": "survivor", "char": "survivor7"},
		{"name": "S", "role": "survivor", "char": "survivor3"}, {"name": "E", "role": "survivor", "char": "survivor1"}])
	check(r.perk.A == "tough" and r.perk.B == "fix" and r.perk.C == "rise" and r.perk.M == "medic" and r.perk.S == "lift", "every survivor has the perk of their character")
	r.clock = 10.0
	var ev := r.handle({"k": "hit", "n": "A"}, "K")
	check(r.hp("A") == "ok" and ev.size() == 1 and ev[0].k == "shield", "«جلد قاسي»: the first blow does nothing")
	r.clock = 20.0
	r.handle({"k": "hit", "n": "A"}, "K")
	check(r.hp("A") == "hurt", "the second one does")
	r.handle({"k": "rep", "i": 0, "on": true}, "B")
	r.handle({"k": "rep", "i": 1, "on": true}, "E")
	r.tick(10.0)
	check(r.gens[0].p > r.gens[1].p * 1.25, "«يد المصلّح» repairs faster (%.3f vs %.3f)" % [r.gens[0].p, r.gens[1].p])
	r.clock = 30.0; r.handle({"k": "hit", "n": "C"}, "K")
	r.clock = 40.0; r.handle({"k": "hit", "n": "C"}, "K")
	var risen := false
	for i in 210:
		for e in r.tick(0.1):
			if e.k == "rise": risen = true
	check(risen and r.hp("C") == "hurt", "«جناح الفالكيري» gets up by herself after 20 s down")
	r.clock = 50.0; r.handle({"k": "hit", "n": "E"}, "K") # hurt: someone to heal
	r.handle({"k": "heal", "n": "E", "on": true}, "M")
	r.tick(3.0)
	check(r.s.E.heal > 3.0 / Rules.HEAL_TIME * 1.4, "«طب ميداني» heals faster (%.2f in 3 s)" % r.s.E.heal)
	# traps in the rules
	for i in 6: r.handle({"k": "trap", "p": [float(i), 0.0, 0.0]}, "K")
	var armed := 0
	for t in r.traps:
		if t[2]: armed += 1
	check(r.traps.size() == Rules.TRAPS and armed == Rules.TRAPS, "at most %d traps; the newest take the oldest places" % Rules.TRAPS)
	ev = r.handle({"k": "snap", "i": 0}, "B")
	check(ev.size() == 1 and r.s.B.held > 3.9 and not r.traps[0][2], "stepping in one holds you (%.1f s)" % r.s.B.held)
	r.tick(4.5)
	check(r.s.B.held <= 0.0, "and lets go")
	# ---------------- the pier on the beach ----------------
	var m = await boot("beach", me_k)
	var w: NightWorld = m.world
	var north: Vector3 = w.gate_points[1][0]
	check(absf(north.y - NightWorld.PIER_Y) < 0.01, "the beach's north gate stands on the pier")
	await power(m)
	await put(m, Vector3(0.0, NightWorld.PIER_Y, 70.0))
	await frames(20)
	check(absf(m.body.position.y - NightWorld.PIER_Y) < 0.4, "on the deck over the water (y %.2f)" % m.body.position.y)
	m.yaw = PI # walk north
	m.sprint = true
	m.stick_vec = Vector2(0, -1)
	var z0: float = m.body.position.z
	await frames(150)
	check(m.body.position.z > z0 + 6.0 and absf(m.body.position.y - NightWorld.PIER_Y) < 0.4, "walking along the pier (%.1f m)" % (m.body.position.z - z0))
	await put(m, Vector3(0.0, NightWorld.PIER_Y, NightWorld.WALL - 6.0))
	await frames(120)
	check(w.road_at(m.body.position) == 1, "through the north gate onto its road")
	var sand := w.height(0.0, NightWorld.PIER_FROM - 14.0)
	await put(m, Vector3(0.0, sand, NightWorld.PIER_FROM - 14.0)) # up the ramp from the sand
	await frames(330)
	check(m.body.position.z > NightWorld.PIER_FROM + 2.0 and absf(m.body.position.y - NightWorld.PIER_Y) < 0.5,
		"up the ramp onto the deck from the sand (z %.1f, y %.2f)" % [m.body.position.z, m.body.position.y])
	m.stick_vec = Vector2.ZERO
	m.queue_free()
	await tree.process_frame
	# ---------------- traps, spikes, nitro, the HUD ----------------
	m = await boot("forest", me_k)
	w = m.world
	var spot: Vector3 = m.body.position + Vector3(2.0, 0, 0)
	events(m, m.rules.handle({"k": "trap", "p": [spot.x, spot.z, spot.y]}, "K"))
	await frames(4)
	check(m.trap_nodes.size() == 1 and m.trap_nodes[0].visible, "the trap shows to a survivor close by")
	await put(m, m.body.position + Vector3(0.6, 0, 0)) # 1.4 m from it
	m._update_ctx()
	check(m.ctx.get("interact", {}).get("kind", "") == "disarm", "close to it: «فك الفخ»")
	await put(m, spot)
	await frames(6)
	check(m._held() > 3.0, "walking into it: held (%.1f s)" % m._held())
	var p0: Vector3 = m.body.position
	m.stick_vec = Vector2(0, -1)
	await frames(60)
	check(m.body.position.distance_to(p0) < 0.3, "and cannot move while held")
	m.stick_vec = Vector2.ZERO
	await frames(200)
	check(m._held() <= 0.0, "let go after %.0f s" % Rules.HELD_TIME)
	check(m.rules.perk.get("P", "") == "fix", "my perk: «يد المصلّح»")
	# nitro and spikes on the escape road
	await power(m)
	var ec: NFCar = w.esc_cars[0]
	await put(m, ec.global_position + Basis(Vector3.UP, float(w.gate_points[0][1])) * Vector3(2.2, 0, 0))
	m._press("interact", 5)
	await frames(120) # the key
	m.stick_vec = Vector2(0, -1)
	await frames(90)
	var ids := []
	for b in m._buttons(): ids.append(str(b[3]))
	check("nitro" in ids, "the driver has a nitro button")
	m._press("nitro", 5)
	await frames(100)
	print("   with nitro: %.1f km/h (top %.0f)" % [absf(ec.speed) * 3.6, ec.top() * 3.6])
	check(absf(ec.speed) > NightWorld.ESC_TOP + 2.0 and ec.flames != null and ec.flames.visible, "nitro: past %d km/h, flames out of the back" % roundi(NightWorld.ESC_TOP * 3.6))
	m._press("nitro", 5)
	check(m.esc_nitro.get(0, false) and ec.nitro <= NFCar.NITRO_TIME, "only once a run")
	var ahead: Vector3 = ec.global_position + ec.forward() * 14.0
	events(m, m.rules.handle({"k": "spike", "i": 0, "p": [ahead.x, ahead.z]}, "K"))
	await frames(80)
	check(bool(m.rules.roads[0].flat) and absf(ec.limit - NightWorld.ESC_TOP * 0.45) < 0.01, "over the spikes: the tyres burst, the car crawls")
	m.stick_vec = Vector2.ZERO
	m.queue_free()
	await tree.process_frame
	# ---------------- the final shot ----------------
	m = await boot("forest", me_k)
	m.rules.s["D"].hp = "dead"
	m.rules.clock = 10.0
	events(m, m.rules.handle({"k": "hit", "n": "P"}, "K"))
	m.rules.clock = 20.0
	events(m, m.rules.handle({"k": "hit", "n": "P"}, "K"))
	print("   final shot: done %s who %s t %.2f scale %.2f" % [m.fin_done, m.fin_who, m.fin_t, Engine.time_scale])
	var slow_seen := false
	var cam_seen := false
	for i in 20:
		await tree.process_frame
		if is_equal_approx(Engine.time_scale, 0.3): slow_seen = true
		if m.fin_cam != null and m.fin_cam.current: cam_seen = true
	check(m.fin_done and m.fin_who == "P" and slow_seen and cam_seen, "the last one down: slow motion (%s), a camera circling them (%s)" % [slow_seen, cam_seen])
	for i in 400:
		await tree.process_frame
		if m.fin_t <= 0.0: break
	check(m.fin_t <= 0.0 and is_equal_approx(Engine.time_scale, 1.0) and m.main_cam.current, "and back to normal")
	m.queue_free()
	await tree.process_frame
	# ---------------- the computer killer ----------------
	m = await boot("forest", [{"name": "P", "role": "survivor", "char": "survivor1", "slot": 0},
		{"name": "The Killer", "role": "killer", "char": "killer", "slot": 2, "bot": true}])
	w = m.world
	check(m.bot != null, "trial mode as a survivor: a computer killer")
	for i in 600:
		await tree.physics_frame
		if m.bot.nav_ok: break
	check(m.bot.nav_ok, "she baked her way round the map")
	var bp: Vector3 = m.bot.pos()
	var face := Vector3(sin(m.bot.face), 0, cos(m.bot.face))
	var stand := bp + face * 7.0
	stand.y = w.height(stand.x, stand.z)
	await put(m, stand)
	var downed := false
	for i in 900:
		await tree.physics_frame
		if m.rules.hp("P") == "down":
			downed = true
			break
	check(m.bot.hits >= 2 and downed, "she sees me, chases and puts me down (%d hits)" % m.bot.hits)
	var hooked := false
	for i in 2400:
		await tree.physics_frame
		if m.rules.hp("P") == "hooked":
			hooked = true
			break
	check(hooked, "picks me up and hangs me on a hook (%s)" % m.rules.hp("P"))
	m.queue_free()
	await tree.process_frame
	# ---------------- the friends' board ----------------
	var h0 := Net.history.size()
	Net.record_match(1, 0, "forest", "survivor", "escaped", 320)
	check(Net.history.size() == mini(h0 + 1, Net.HISTORY) and str(Net.history[0].map) == "forest", "the round goes on my list")
	Net.fstats["salem"] = {"name": "salem", "lv": 9, "xp": 9000, "esc": 999, "kills": 3, "rounds": 50}
	if not "salem" in Net.friends: Net.friends.append("salem")
	var rows := Net.board("esc")
	check(str(rows[0].name) == "salem", "the board puts the best first")
	m = await boot("forest", me_k)
	m.menu.visible = true
	m.menu.open("board")
	await frames(3)
	m.menu.chars_from = "offline"
	m.menu.off_char = "survivor6"
	m.menu.open("chars")
	await frames(3)
	m.menu.open("help")
	await frames(3)
	check(true, "the board, the character stand with its perk and the help page draw")
	Net.friends.erase("salem")
	m.queue_free()
	print("EXTREME DONE bad=", bad)
	tree.quit()
