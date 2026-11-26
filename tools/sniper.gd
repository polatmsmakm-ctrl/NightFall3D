extends Node
## «وضع القنّاص»: one gate, the tower and its stairs (she climbs them, survivors cannot), the rifle,
## the scope, the shot that drops whoever it hits, no moon; and the computer killer doing the same.
var tree: SceneTree
var bad := 0

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok: bad += 1

func round_of(me: String, role_me: String, bot := false) -> Node:
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(10)
	var players := [{"name": "P", "role": "survivor", "char": "survivor1", "slot": 0},
		{"name": "K", "role": "killer", "char": "killer", "slot": 1, "bot": bot}]
	m._start({"map": "kuwait", "me": me, "offline": true, "seed": 5150, "theme": "normal", "sniper": true, "players": players})
	for i in 1500:
		await tree.process_frame
		if m.world.ready_done: break
	await frames(30)
	return m

func _ready() -> void:
	tree = get_tree()
	# ---- as the killer
	var m = await round_of("K", "killer")
	var w = m.world
	m.rules.ev_at = 99999.0
	check(m.rules.sniper and w.sniper and w.find_child("SniperTower", true, false) != null, "the sniper mode builds the tower on Kuwait City")
	check(w.snipe_rifle != Vector3.INF and w.rifle_stand != null and w.rifle_stand.visible, "the rifle waits on its crate on the roof")
	var sp: Vector3 = w.spawn_point("killer", 1)
	check(sp.x > NightWorld.SN_STAIR_X0 - 6.0 and absf(sp.z - NightWorld.SN_FACE) < 10.0, "she starts at the foot of the stairs")
	for p in w.gen_points + w.hook_points.slice(0, w.road_hook0):
		if absf(p.x) < NightWorld.SN_HALF + 1.0 and p.z > NightWorld.SN_FACE - 4.0: check(false, "an objective inside the tower at %s" % p)
	check(m.ctx.get("interact", {}).get("kind", "") != "rifle", "(not at the rifle yet)")
	# climbing: from the foot, the stick forward along the flight (toward -x)
	var z: float = w._sn_z()
	m.body.global_position = Vector3(NightWorld.SN_STAIR_X0 + 1.2, 0.3, z)
	m.yaw = PI / 2.0
	m.pitch = 0.0
	await tree.physics_frame
	m.stick_vec = Vector2(0, -1)
	var climbed := false
	var saw_climb := false
	for i in 900:
		await tree.physics_frame
		if w.on_stairs(m.body.global_position) and m.rig.current == "climb": saw_climb = true
		if m.body.global_position.y > NightWorld.SN_H - 0.6:
			climbed = true
			break
	m.stick_vec = Vector2.ZERO
	check(saw_climb, "on the stairs she plays the climbing clip (made from the walk)")
	if not climbed:
		for ci in m.body.get_slide_collision_count():
			var col: KinematicCollision3D = m.body.get_slide_collision(ci)
			print("    stuck on ", col.get_collider(), " ", (col.get_collider() as Node).get_path() if col.get_collider() is Node else "", " normal ", col.get_normal(), " at ", col.get_position())
	check(climbed, "she climbs both flights to the roof (y %.1f, x %.1f)" % [m.body.global_position.y, m.body.global_position.x])
	check(m.rig.has("climb"), "every rig has «climb»")
	# the rifle
	m.body.global_position = w.snipe_rifle + Vector3(0.6, 0.3, 0.0)
	await frames(8)
	check(m.ctx.has("interact") and m.ctx.interact.kind == "rifle", "by the crate: «خذ القنّاصة»")
	m._snipe_start()
	await frames(20)
	check(m.sniping and not w.rifle_stand.visible and m.my_rifle != null and m.my_rifle.visible, "she lies down with the rifle in her hands")
	check(m.cam_pivot.position.y < 0.8, "her eye is down at the parapet (%.2f)" % m.cam_pivot.position.y)
	check(m.ctx.interact.kind == "rifle_off", "the interact button is «قوم»")
	m._press("power", -1)
	check(m.scope == 1 and absf(m.main_cam.fov - (80.0 + Gfx.fov_add) / 4.0) < 0.5, "«سكوب»: x4 (fov %.1f)" % m.main_cam.fov)
	await frames(3)
	m._press("power", -1)
	await frames(3)
	check(m.scope == 2 and absf(m.main_cam.fov - (80.0 + Gfx.fov_add) / 8.0) < 0.5, "again: x8 (fov %.1f)" % m.main_cam.fov)
	check(m._look_k() < 0.2, "through the scope the view turns slower")
	# crawling: slow, and never off the roof
	m.body.global_position = Vector3(0.0, NightWorld.SN_H + 0.3, NightWorld.SN_FACE + 3.0)
	m.yaw = 0.0
	m.stick_vec = Vector2(0, -1) # toward -z: the front edge
	for i in 240: await tree.physics_frame
	m.stick_vec = Vector2.ZERO
	var bp: Vector3 = m.body.global_position
	check(bp.y > NightWorld.SN_H - 0.5 and bp.z > NightWorld.SN_FACE - 0.6, "crawling to the edge, she stays on the roof (y %.1f, z %.1f)" % [bp.y, bp.z])
	check(m.rig.current == "crawl", "crawling: the crawl clip goes out to every phone")
	# the shot: the survivor stands in the open down the road; aim straight at her chest
	var r = m.remotes["P"]
	var target := Vector3(-8.0, 0.05, 50.0)
	r.pos = target
	r.node.position = target
	m.rules.s["P"].hp = "ok"
	await frames(4)
	var from: Vector3 = m.main_cam.global_position
	var to := target + Vector3(0, 1.2, 0)
	var d := (to - from).normalized()
	m.yaw = atan2(-d.x, -d.z)
	m.pitch = asin(d.y)
	await tree.physics_frame
	await frames(3)
	m.snipe_cd = 0.0
	m._snipe_fire()
	await frames(3)
	check(m.rules.s["P"].hp == "down", "one bullet and she is down (%s)" % m.rules.s["P"].hp)
	check(m.snipe_cd > 0.0, "the bolt: a beat before the next shot")
	m.rules.snipe_t = -99.0
	m.rules.s["P"].hp = "ok"
	m.snipe_cd = 0.0
	m.yaw += 0.3
	await tree.physics_frame
	await frames(2)
	m._snipe_fire()
	await frames(2)
	check(m.rules.s["P"].hp == "ok", "a miss is a miss")
	var many := 0
	for k in 5:
		m.rules.snipe_t = -99.0
		if not m.rules.handle({"k": "snipe", "n": "", "p": [0, 0, 0]}, "K").is_empty(): many += 1
	check(many == 5, "unlimited bullets")
	check(m.rules.handle({"k": "snipe", "n": "P"}, "P").is_empty(), "(only the killer can fire it)")
	m.rules.s["P"].shield = true
	m.rules.snipe_t = -99.0
	m.rules.handle({"k": "snipe", "n": "P"}, "K")
	check(m.rules.s["P"].hp == "down", "it drops even a survivor with «جلد قاسي»")
	m._snipe_stop()
	await frames(10)
	check(not m.sniping and w.rifle_stand.visible and m.cam_pivot.position.y > 1.2, "«قوم»: up again, the rifle back on its crate")
	# one gate, no moon
	for g in m.rules.gens: g.done = true
	for e in m.rules.tick(0.1): m._on_event(e)
	check(not m.rules.powered and m.rules.gate_t > 9.0 and not m.rules.gates[0].open, "the generators done: a countdown first (%.1f s), the gates still shut" % m.rules.gate_t)
	check(m.rules.snapshot().get("gt", -1.0) > 9.0, "the countdown goes out in the snapshot")
	for e in m.rules.tick(5.0): m._on_event(e)
	check(not m.rules.powered and absf(m.rules.gate_t - 4.9) < 0.05, "half way: %.1f s left" % m.rules.gate_t)
	for e in m.rules.tick(5.0): m._on_event(e)
	check(m.rules.powered and m.rules.gates[0].open and not m.rules.gates[1].open, "power: only the gate on the towers' side opens")
	check(m.rules.doom < 0.0, "and no moon comes down")
	m.rules.s["P"].hp = "ok"
	check(m.rules.handle({"k": "board", "i": 1}, "P").is_empty(), "nobody boards behind the shut gate")
	m.queue_free()
	await frames(5)
	# ---- as a survivor: the barrier at the stairs, and the computer killer
	var s = await round_of("P", "survivor", true)
	var w2 = s.world
	s.rules.ev_at = 99999.0
	var z2: float = w2._sn_z()
	s.body.global_position = Vector3(NightWorld.SN_STAIR_X0 + 2.0, 0.3, z2)
	s.yaw = PI / 2.0
	s.stick_vec = Vector2(0, -1)
	for i in 240: await tree.physics_frame
	s.stick_vec = Vector2.ZERO
	check(s.body.global_position.x > NightWorld.SN_STAIR_X0 and s.body.global_position.y < 1.0, "a survivor is stopped at the foot of the stairs (x %.1f)" % s.body.global_position.x)
	s.body.global_position = Vector3(-30.0, 0.3, -40.0)
	var bot = s.bot
	var up := false
	for i in 4800:
		await tree.physics_frame
		if bot.sn_state == "aim":
			up = true
			break
	if not up: print("    bot: ", bot.sn_state, " at ", bot.pos(), " way ", bot.sn_way.size(), " nav ", bot.nav_ok, " goal ", bot.goal)
	check(up, "the computer killer climbs to the rifle (y %.1f)" % bot.pos().y)
	check(bot.pos().y > NightWorld.SN_H - 0.8, "and lies on the roof")
	print("sniper: %d failed" % bad)
	tree.quit()
