extends Node
## Phase 2 checks: the one random event of the round (same on client and server), the call to
## prayer, doors that open and shut, and lights that react to the blackout and to the killer.

var tree: SceneTree

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func boot(map := "fareej", role := "survivor", seed := 123456789):
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(10)
	m._start({"map": map, "me": "P", "offline": true, "seed": seed, "players": [
		{"name": "P", "role": role, "char": "survivor2", "slot": 0},
		{"name": "K", "role": "killer", "char": "killer", "slot": 1},
		{"name": "D", "role": "survivor", "char": "survivor5", "slot": 2}]})
	for i in 500:
		await tree.process_frame
		if m.world.ready_done: break
	await frames(8)
	return m

func _ready() -> void:
	tree = get_tree()
	# ---------- the event is picked from the seed, and the snapshot carries it ----------
	for seed in [123456789, 7, 999999937]:
		var r := Rules.new()
		r.setup(7, 2, 9, 5, [{"name": "A", "role": "killer"}, {"name": "B", "role": "survivor"}], seed, 12)
		print("seed ", seed, ": event=", r.ev_kind, " at=", r.ev_at, "s adhan at=", r.adhan_at, "s doors=", r.doors.size())
	var a := Rules.new()
	a.setup(7, 2, 9, 5, [{"name": "A", "role": "killer"}, {"name": "B", "role": "survivor"}], 42424242, 12)
	var b := Rules.new()
	b.setup(7, 2, 9, 5, [{"name": "A", "role": "killer"}, {"name": "B", "role": "survivor"}], 42424242, 12)
	print("same seed, same plan=", a.ev_kind == b.ev_kind and a.ev_at == b.ev_at and a.adhan_at == b.adhan_at)
	# run the clock up to the event and watch it come and go
	a.clock = a.ev_at - 0.1
	a.tick(0.2)
	print("it fires: kind=", a.ev_kind, " left=", snappedf(a.ev_t, 0.1), "s target=", a.ev_n if a.ev_n != "" else "-")
	var snap := a.snapshot()
	print("snapshot: ek=", snap.ek, " et=", snap.et, " en=", snap.en, " ad=", snap.ad, " doors=", snap.dr.size())
	var c := Rules.new()
	c.setup(7, 2, 9, 5, [{"name": "A", "role": "killer"}, {"name": "B", "role": "survivor"}], 1, 12)
	c.apply(snap)
	print("another client applies it: kind=", c.ev_kind, " left=", snappedf(c.ev_t, 0.1), " target=", c.ev_n if c.ev_n != "" else "-")
	for i in int(Rules.EVENT_LEN[a.ev_kind] / 0.5) + 2: a.tick(0.5)
	print("after it runs out: left=", snappedf(a.ev_t, 0.1), " (fired once=", a.ev_fired, ")")
	a.clock = a.adhan_at + 0.1
	a.tick(0.1)
	print("call to prayer starts: ad=", a.adhan)
	a.clock = a.adhan_at + Rules.ADHAN_LEN + 1.0
	a.tick(0.1)
	print("and ends: ad=", a.adhan)
	# ---------- in the round ----------
	var m = await boot()
	var w = m.world
	var leaves := 0
	for d in w.door_nodes:
		if d != null: leaves += 1
	print("door leaves=", leaves, " of ", w.door_points.size(), " doorways (the rest hold pallets)",
		" lights registered=", w.amb_lights.size())
	# walk up to a door and swing it shut
	var di := 0
	for i in w.door_nodes.size():
		if w.door_nodes[i] != null:
			di = i
			break
	var dp: Array = w.door_points[di]
	m.body.position = dp[0] + Basis(Vector3.UP, dp[1]) * Vector3(0, 0.3, 1.4)
	m.body.velocity = Vector3.ZERO
	for i in 10: await tree.physics_frame
	print("at a door: ctx=", m.ctx.get("interact", {}).get("kind", "none"), " label=", m.ctx.get("interact", {}).get("label", ""))
	var before: float = w.door_nodes[di].hinge.rotation.y
	m._press("interact", 5)
	for i in 40: await tree.physics_frame
	print("shut it: rules=", m.rules.doors[di], " leaf moved=", snappedf(absf(w.door_nodes[di].hinge.rotation.y - before), 0.01), " rad")
	print("now the button says: ", m.ctx.get("interact", {}).get("label", ""))
	m._press("interact", 5)
	for i in 40: await tree.physics_frame
	print("opened again: rules=", m.rules.doors[di], " leaf back=", snappedf(absf(w.door_nodes[di].hinge.rotation.y - before), 0.01))
	# a door swinging far away is heard
	m.sigs.clear()
	var far_door := di
	for i in w.door_nodes.size(): # one across the map, so it counts as "heard"
		if w.door_nodes[i] != null and (w.door_points[i][0] as Vector3).distance_to(m.body.position) > 20.0:
			far_door = i
			break
	m._on_event({"k": "door", "i": far_door, "on": true, "by": "K"})
	await frames(3)
	print("heard a door: markers=", m.sigs.size(), " kind=", m.sigs[0].k if m.sigs.size() > 0 else -1,
		" text=", m.SIG_TEXT[int(m.sigs[0].k)] if m.sigs.size() > 0 else "-")
	# ---------- blackout ----------
	var lamp: OmniLight3D = w.amb_lights[0][0]
	var lit: float = lamp.light_energy
	m.rules.ev_kind = 0; m.rules.ev_t = 20.0; m.rules.ev_fired = true
	await frames(30)
	print("blackout: world=", w.blackout, " a lamp went from ", snappedf(lit, 0.01), " to ", snappedf(lamp.light_energy, 0.01))
	m.rules.ev_t = 0.0
	await frames(40)
	print("lights back: ", snappedf(lamp.light_energy, 0.01) > 0.1, " blackout=", w.blackout)
	# ---------- heavy fog ----------
	var clear: float = w.env.fog_density
	m.ev_shown = -1
	m.rules.ev_kind = 1; m.rules.ev_t = 40.0
	await frames(20)
	print("fog: ", snappedf(clear, 0.001), " -> ", snappedf(w.env.fog_density, 0.001))
	m.rules.ev_t = 0.0
	await frames(20)
	print("fog clears: ", snappedf(w.env.fog_density, 0.001))
	# ---------- the alarm gives one survivor away to the killer only ----------
	m.ev_shown = -1
	m.rules.ev_kind = 2; m.rules.ev_t = 5.0; m.rules.ev_n = "D"
	await frames(10)
	print("alarm: target=", m.rules.ev_n, " and the killer's map still has no players (drawn arrow only)")
	m.rules.ev_t = 0.0
	# ---------- a house light shies away from the killer ----------
	var house := -1
	for i in w.amb_lights.size():
		if bool(w.amb_lights[i][2]):
			house = i
			break
	var hl: OmniLight3D = w.amb_lights[house][0]
	var on: float = hl.light_energy
	m.remotes["K"].pos = hl.global_position
	m.remotes["K"].node.position = hl.global_position
	await frames(60)
	print("killer next to a house light: ", snappedf(on, 0.01), " -> ", snappedf(hl.light_energy, 0.01))
	m.remotes["K"].pos = Vector3(-200, 0, -200)
	m.remotes["K"].node.position = Vector3(-200, 0, -200)
	await frames(60)
	print("he leaves: ", snappedf(hl.light_energy, 0.01) > 0.1)
	# ---------- the call to prayer ----------
	print("mosque at ", w.adhan_point().snapped(Vector3(1, 1, 1)), " file ready=", ResourceLoader.exists("res://assets/sfx/adhan.mp3"))
	m.rules.adhan = 1
	await frames(6)
	print("playing: ", m.adhan_player != null and m.adhan_player.playing, " bus=", m.adhan_player.bus if m.adhan_player else "-",
		" quiet=", m.adhan_player.volume_db if m.adhan_player else 0)
	m.rules.adhan = 2
	await frames(6)
	print("fading out: handle cleared=", m.adhan_player == null)
	tree.quit()
