extends Node
## Headless checks for the Empty Quarter map, the snow / halloween themes, the campfire emotes,
## the pickup jumpscare and the "play again" path.

var tree: SceneTree

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func boot(map: String, theme: String, role := "survivor"):
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(10)
	m._start({"map": map, "me": "P", "offline": true, "theme": theme, "players": [
		{"name": "P", "role": role, "char": "survivor2", "slot": 0},
		{"name": "K", "role": "killer", "char": "killer", "slot": 1}]})
	for i in 500:
		await tree.process_frame
		if m.world.ready_done: break
	await frames(6)
	return m

func _ready() -> void:
	tree = get_tree()
	# ---------- the desert ----------
	var t0 := Time.get_ticks_msec()
	var m = await boot("rubkhali", "normal")
	var w = m.world
	print("rubkhali built in ms=", Time.get_ticks_msec() - t0, " ready=", w.ready_done)
	print("objectives: gens=", w.gen_points.size(), " hooks=", w.hook_points.size(), " lockers=", w.locker_points.size(),
		" pallets=", w.pallet_points.size(), " windows=", w.window_points.size(), " hatches=", w.hatch_points.size(),
		" gates=", w.gate_points.size())
	print("camps: buildings=", w.buildings.size(), " tents=", w.tents, " wrecks=", w.wrecks, " animals=", w.animals.size(),
		" palms=", w.tree_plan.size())
	var lo := 999.0
	var hi := -999.0
	for i in 60:
		for j in 60:
			var h: float = w.height(-110.0 + i * 3.7, -110.0 + j * 3.7)
			lo = minf(lo, h); hi = maxf(hi, h)
	print("dunes: lowest=", snappedf(lo, 0.1), " highest=", snappedf(hi, 0.1), " (wall top is 12)")
	print("ground=", w.surface_at(Vector3(40, 0, 40)), " fog=", snappedf(w.env.fog_density, 0.001),
		" storm grains=", m.world.dust.amount)
	# seeded the same for everyone, different each round
	var a := NightWorld.new(); a.configure("rubkhali", 7)
	var b := NightWorld.new(); b.configure("rubkhali", 7)
	var c2 := NightWorld.new(); c2.configure("rubkhali", 8)
	print("seeded: same seed same gens=", a.gen_points == b.gen_points, " other seed differs=", a.gen_points != c2.gen_points)
	# the animals move and never block a player
	var an: Dictionary = w.animals[0]
	for x in w.animals:
		if not x.stand:
			an = x
			break
	var before: Vector3 = an.node.position
	var cols := 0
	for x in w.animals:
		if x.node is CollisionObject3D: cols += 1
	await frames(90)
	print("animal walked=", snappedf(before.distance_to(an.node.position), 0.01), "m  with collision=", cols, " (must be 0)")
	# a tent: you can walk in, and there is a locker inside
	var tent: Array = w.buildings[0]
	var rot := Basis(Vector3.UP, tent[2])
	m.sprint = true
	m.body.position = Vector3(tent[0], w.height(tent[0], tent[1]) + 0.4, tent[1]) + rot * Vector3(0, 0, 9.0)
	m.yaw = tent[2]
	m.stick_vec = Vector2(0, -1)
	for i in 150: await tree.physics_frame
	m.stick_vec = Vector2.ZERO
	var loc: Vector3 = rot.inverse() * (m.body.position - Vector3(tent[0], 0, tent[1]))
	print("walked into the tent: local z=", snappedf(loc.z, 0.01), " (front edge is 3.5) surface=", w.surface_at(m.body.position))
	var lk: Array = w.locker_points[0]
	m.body.position = lk[0] + Basis(Vector3.UP, lk[1]) * Vector3(0, 0.3, 1.2)
	m.body.velocity = Vector3.ZERO
	for i in 10: await tree.physics_frame
	print("locker in the tent: ctx=", m.ctx.get("interact", {}).get("kind", "none"))
	# the escape road still works on this map
	var g: Array = w.gate_points[0]
	print("gate at ", g[0], " outside check at road end=", w.is_outside_gate(0, g[0] + Vector3(0, 0, -NightWorld.ROAD_LEN)))
	# ---------- jumpscare ----------
	m.rules.s["P"].hp = "down"; m.rules.s["P"].t = Rules.BLEED_TIME
	await frames(4)
	m.rules.carrying = "P"; m.rules.s["P"].hp = "carried"
	for i in 4: await tree.physics_frame
	print("picked up -> scare=", snappedf(m.scare_t, 0.01), " camera=", "killer close-up" if (m.scare_cam and m.scare_cam.current) else "mine")
	await frames(60)
	print("after the scare: scare=", snappedf(m.scare_t, 0.01), " camera back=", m.main_cam.current)
	m.queue_free()
	await frames(8)
	# ---------- themes ----------
	for th in ["snow", "halloween"]:
		var tt := Time.get_ticks_msec()
		var mt = await boot("forest", th)
		print("forest+", th, " built in ms=", Time.get_ticks_msec() - tt)
		var wt = mt.world
		print(th, ": fog=", snappedf(wt.env.fog_density, 0.001), " ambient=", wt.env.ambient_light_color,
			" moon=", wt.moon.light_color, " snow caps=", wt.snow_caps, " pumpkins=", wt.pumpkins, " webs=", wt.webs,
			" flakes/leaves=", wt.leaves.amount, " breath=", mt.breaths.size())
		mt.queue_free()
		await frames(8)
	# themes work on the new map too
	var mh = await boot("rubkhali", "halloween", "killer")
	print("rubkhali + halloween: pumpkins=", mh.world.pumpkins, " webs=", mh.world.webs, " wrecks=", mh.world.wrecks)
	mh.queue_free()
	await frames(8)
	# ---------- emotes in the lobby ----------
	var ml = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(ml)
	await frames(20)
	var lob = ml.lobby_scene
	ml.menu.off_char = "survivor1"
	ml.menu.open("main")
	await frames(10)
	print("emote clips on the preview: ", NFLobby.EMOTES, " available=", [
		lob.me_rig.player.has_animation("wave"), lob.me_rig.player.has_animation("dance"), lob.me_rig.player.has_animation("clap")])
	lob.emote("", 0)
	await frames(5)
	print("waving: anim=", lob.me_rig.current, " length=", snappedf(lob.me_rig.player.get_animation("wave").length, 0.01),
		" tracks=", lob.me_rig.player.get_animation("wave").get_track_count())
	lob.emote("", 1)
	await frames(5)
	print("dancing: anim=", lob.me_rig.current, " tracks=", lob.me_rig.player.get_animation("dance").get_track_count())
	# a friend at the fire emotes too
	lob.set_cast([{"name": "P", "role": "survivor", "char": "survivor2"}, {"name": "B", "role": "survivor", "char": "survivor5"}], "P")
	await frames(10)
	lob.emote("B", 2)
	await frames(5)
	print("friend clapping: anim=", lob.cast["B"].rig.current, " seated cast=", lob.cast.size())
	tree.quit()
