extends Node
## An online round against the real server (server/server.js) with a second phone played by
## tools/online_bot.js. NF_MODE picks what is tested:
##   forest        — I am the killer, the bot repairs generator 2: the server's generator progress
##                   reaches my phone, and my hits, pick-up and hook go through the server.
##   forest-surv   — I am a survivor, the bot is the killer: my repair is counted by the server and
##                   comes back to me, and the bot's blow (a server event) reaches my phone.
##   kuwait-sniper — I am the killer in «وضع القنّاص»: I climb the tower, take the rifle and the shot
##                   downs the bot on every phone; only the towers' gate is in play.
## Every check prints "O ok" or "O FAIL" (CI greps "^O ").
var tree: SceneTree
var bad := 0

func frames(n: int) -> void:
	for i in n: await tree.physics_frame

func check(ok: bool, what: String) -> void:
	print(("O ok   " if ok else "O FAIL ") + what)
	if not ok: bad += 1

func _ready():
	tree = get_tree()
	var mode := OS.get_environment("NF_MODE")
	if mode == "": mode = "forest"
	var map := "kuwait" if mode.begins_with("kuwait") else "forest"
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	for i in 10: await tree.process_frame
	Net.configure("Tester", "")
	for i in 300:
		await tree.process_frame
		if Net.state == "online": break
	check(Net.state == "online", "connected to the server")
	Net.send({"t": "create", "map": map})
	for i in 200:
		await tree.process_frame
		if Net.in_room(): break
	check(Net.in_room(), "room made (%s)" % str(Net.room.get("code", "")))
	if mode == "forest-surv": Net.send({"t": "set", "role": "survivor"})
	if mode == "kuwait-sniper": Net.send({"t": "set", "sniper": true})
	for i in 30: await tree.process_frame
	# where the bot should stand: by generator 2 (forest), down the Gulf Road in the rifle's view (sniper)
	var probe := NightWorld.new()
	probe.sniper = mode == "kuwait-sniper"
	probe.configure(map)
	var spot: Vector3 = probe.gen_points[2] + Vector3(1.5, 0, 1.0)
	if mode == "kuwait-sniper": spot = Vector3(-8.0, 0.05, 50.0)
	probe.free()
	var f := FileAccess.open("/tmp/code.txt", FileAccess.WRITE)
	f.store_string("%s %f %f %f %s" % [str(Net.room.code), spot.x, spot.y, spot.z, mode])
	f.close()
	for i in 900:
		await tree.process_frame
		if Net.room.get("players", []).size() >= 2: break
	check(Net.room.get("players", []).size() >= 2, "the second phone joined")
	Net.send({"t": "start"})
	for i in 2400:
		await tree.process_frame
		if m.started and m.world and m.world.ready_done: break
	check(m.started and not m.offline, "the round started online (role %s)" % m.my_role)
	if not m.started:
		print("O RESULT FAIL (no round)")
		tree.quit()
		return
	# the round's own seed (the server picks it): tell the bot where generator 2 really is
	if mode == "forest":
		spot = m.world.gen_points[2] + Vector3(1.5, 0, 1.0)
		var sf := FileAccess.open("/tmp/spot.txt", FileAccess.WRITE)
		sf.store_string("%f %f %f" % [spot.x, spot.y, spot.z])
		sf.close()
	await frames(90)
	check(m.remotes.has("Bot"), "the other phone is in my round")
	if not m.remotes.has("Bot"):
		print("O RESULT FAIL")
		tree.quit()
		return
	var d = m.remotes["Bot"]
	var said: Vector3 = d.pos # where its last message put it (the killer bot is already walking)
	check(d.node.position.distance_to(said) < 3.0 and (mode == "forest-surv" or said.distance_to(spot) < 3.0), "its position reaches me (%s)" % d.node.position.snapped(Vector3.ONE * 0.1))
	match mode:
		"forest": await _as_killer(m, d)
		"forest-surv": await _as_survivor(m, d)
		"kuwait-sniper": await _as_sniper(m, d)
	print("O RESULT ", "PASS" if bad == 0 else "FAIL (%d)" % bad)
	tree.quit()

func _as_killer(m, d) -> void:
	var w = m.world
	check(m.my_role == "killer", "I am the killer")
	var p0: float = m.rules.gens[2].p
	await frames(180)
	check(m.rules.gens[2].p > p0 and m.rules.gens[2].p > 0.0, "the bot's repair: generator 2 moves on my phone (%.3f -> %.3f)" % [p0, m.rules.gens[2].p])
	check(str(d.anim) == "repair", "I see it repairing (%s)" % d.anim)
	var want := ["hurt", "down"]
	for hit in 2:
		m.body.position = d.node.position + Vector3(0, 0.2, 1.6); m.body.velocity = Vector3.ZERO; m.yaw = 0.0
		await frames(8)
		m._press("attack", 5)
		await frames(170)
		check(m.rules.hp("Bot") == want[hit], "hit %d -> %s (server: %s)" % [hit + 1, want[hit], m.rules.hp("Bot")])
	m.body.position = d.node.position + Vector3(0, 0.2, 1.5); await frames(10)
	m._press("interact", 5); await frames(30)
	check(m.rules.carrying == "Bot", "picked up (carrying %s)" % m.rules.carrying)
	m.body.position = w.hook_points[0] + Vector3(1.5, 0.3, 0); await frames(15)
	m._press("interact", 5); await frames(40)
	check(m.rules.hp("Bot") == "hooked", "hooked (%s)" % m.rules.hp("Bot"))
	m._press("power", 5); await frames(20)
	check(m.rules.power_cd > 0.0, "the power went through the server (cd %.1f)" % m.rules.power_cd)

func _as_survivor(m, d) -> void:
	var w = m.world
	check(m.my_role == "survivor", "I am a survivor, the bot is the killer (%s)" % m.rules.killer)
	var g: Vector3 = w.gen_points[0]
	m.body.position = g + Vector3(1.4, 0.3, 0.6); m.body.velocity = Vector3.ZERO
	await frames(20)
	check(m.ctx.has("interact") and str(m.ctx.interact.get("kind", "")) == "rep", "by generator 0: «تصليح»")
	m._press("interact", 7)
	var p0: float = m.rules.gens[0].p
	await frames(240)
	check(m.rules.gens[0].p > p0, "my repair counted by the server and back on my phone (%.3f)" % m.rules.gens[0].p)
	# the bot (the killer) walks to me and swings: the blow comes from the server
	var hurt := false
	for i in 3000: # it may have to cross the whole map to me
		await tree.physics_frame
		if m.rules.hp(m.my_name) == "hurt" or m.rules.hp(m.my_name) == "down":
			hurt = true
			break
	check(hurt, "the killer's blow reaches me (%s)" % m.rules.hp(m.my_name))
	check(m.hold.is_empty(), "the blow stopped my repair")

func _as_sniper(m, d) -> void:
	var w = m.world
	check(m.rules.sniper and w.sniper, "«وضع القنّاص» on both sides (rules %s, map %s)" % [m.rules.sniper, w.sniper])
	check(m.my_role == "killer", "I am the killer")
	var z: float = w._sn_z()
	m.body.global_position = Vector3(NightWorld.SN_STAIR_X0 + 1.2, 0.3, z)
	m.yaw = PI / 2.0
	m.pitch = 0.0
	await tree.physics_frame
	m.stick_vec = Vector2(0, -1)
	var up := false
	for i in 900:
		await tree.physics_frame
		if m.body.global_position.y > NightWorld.SN_H - 0.6:
			up = true
			break
	m.stick_vec = Vector2.ZERO
	check(up, "I climb the tower (y %.1f)" % m.body.global_position.y)
	m.body.global_position = w.snipe_rifle + Vector3(0.6, 0.3, 0.0)
	await frames(8)
	m._snipe_start()
	await frames(20)
	check(m.sniping, "lying down with the rifle")
	m._press("power", -1)
	await frames(3)
	check(m.scope == 1, "scope x4")
	await frames(30)
	var target: Vector3 = d.node.position
	var from: Vector3 = m.main_cam.global_position
	var dir := (target + Vector3(0, 1.2, 0) - from).normalized()
	m.yaw = atan2(-dir.x, -dir.z)
	m.pitch = asin(dir.y)
	await tree.physics_frame
	await frames(3)
	m.snipe_cd = 0.0
	m._snipe_fire()
	var down := false
	for i in 120:
		await tree.physics_frame
		if m.rules.hp("Bot") == "down":
			down = true
			break
	check(down, "the shot downs the other phone, through the server (%s)" % m.rules.hp("Bot"))
	await frames(60)
	check(m.rules.s["Bot"].t > 0.0, "and it bleeds (%.0f s)" % m.rules.s["Bot"].t)
	check(m.rules.doom < 0.0, "no moon")
	m._snipe_stop()
	await frames(10)
