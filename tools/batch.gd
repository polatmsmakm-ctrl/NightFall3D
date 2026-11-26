extends Node
## The owner's November batch: the four-minute sunset, no proximity music while vanished, the gate
## countdown, the sea, his billboard (picture always, video only from the developer tools), the
## police (lights on, sirens when the gates open), the bus stop, drains, boats, varied parking, his
## rifle, «المسعف» with the first-aid kit, and the rescue helicopter for the last survivor.
var tree: SceneTree
var bad := 0

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok: bad += 1

func _ready() -> void:
	tree = get_tree()
	check(is_equal_approx(NightWorld.SUNSET_TIME, 240.0), "«بين العصر والمغرب»: the sun sets over four minutes")
	# ---- the rules on their own: «المسعف», the gate countdown, the helicopter ----
	var r := Rules.new()
	r.setup(7, 2, 9, 5, [{"name": "K", "role": "killer", "char": "killer"},
		{"name": "A", "role": "survivor", "char": "survivor1", "perk": "aid"},
		{"name": "B", "role": "survivor", "char": "survivor2"},
		{"name": "C", "role": "survivor", "char": "survivor7"}], 7, 4)
	check(r.perk["A"] == "aid" and r.perk["B"] == "fix" and r.perk["C"] == "medic", "«المسعف» replaces the character's own perk, only for whoever picked it")
	r.s["B"].hp = "hurt"; r.s["C"].hp = "hurt"
	r.handle({"k": "heal", "n": "B", "on": true}, "A")
	for i in 42: r.tick(0.1) # 4 s: with the kit that is the whole heal (8 s for anyone else)
	check(r.s["B"].hp == "ok", "the medic heals another in 4 s (%s)" % r.s["B"].hp)
	r.s["A"].hp = "hurt"
	r.handle({"k": "heal", "n": "A", "on": true}, "A")
	for i in 82: r.tick(0.1)
	check(r.s["A"].hp == "ok" and r.s["A"].item, "and himself in 8 s, and the kit is still there (%s, item %s)" % [r.s["A"].hp, r.s["A"].item])
	# helicopter
	r.heli_ok = true
	r.s["B"].hp = "dead"; r.s["C"].hp = "dead"; r.s["A"].hp = "ok"
	var evs := r.tick(0.1)
	check(int(r.heli.st) == 1 and str(r.heli.who) == "A", "one survivor left: the helicopter comes for A")
	var got := false
	for e in evs: got = got or (str(e.k) == "heli" and int(e.st) == 1)
	check(got, "everyone hears it (event heli 1)")
	for i in int(Rules.HELI_COME * 10) + 2: r.tick(0.1)
	check(int(r.heli.st) == 2, "it arrives and lets the ladder down")
	check(r.snapshot().get("hl", [])[0] == 2, "it is in the snapshot")
	r.handle({"k": "ladder"}, "A")
	check(int(r.heli.st) == 3, "A takes the ladder")
	for i in 20: r.tick(0.1)
	r.handle({"k": "hit", "n": "A"}, "K")
	check(r.s["A"].hp == "ok", "half way up, the killer cannot reach her")
	for i in int(Rules.CLIMB_TIME * 10) + 2: r.tick(0.1)
	check(int(r.heli.st) == 4 and r.s["A"].hp == "escaped" and r.over, "at the top: out, and the round is over")
	# caught before the ladder: it leaves
	var q := Rules.new()
	q.setup(7, 2, 9, 5, [{"name": "K", "role": "killer", "char": "killer"},
		{"name": "A", "role": "survivor", "char": "survivor1"}, {"name": "B", "role": "survivor", "char": "survivor2"}], 9, 4)
	q.heli_ok = true
	q.s["B"].hp = "dead"; q.s["A"].hp = "hurt"
	q.tick(0.1)
	q.handle({"k": "hit", "n": "A"}, "K")
	q.tick(0.1)
	check(int(q.heli.st) == 5 and q.s["A"].hp == "down", "caught before the ladder: the helicopter leaves at once")
	# gate countdown in the snapshot / apply round trip
	var g := Rules.new()
	g.setup(7, 2, 9, 5, [{"name": "K", "role": "killer", "char": "killer"}, {"name": "A", "role": "survivor", "char": "survivor1"}], 3, 4)
	for gg in g.gens: gg.done = true
	g.tick(0.1)
	var g2 := Rules.new()
	g2.setup(7, 2, 9, 5, [{"name": "K", "role": "killer", "char": "killer"}, {"name": "A", "role": "survivor", "char": "survivor1"}], 3, 4)
	g2.apply(g.snapshot())
	check(not g2.powered and g2.gate_t > 9.0, "another phone sees the countdown (%.1f s)" % g2.gate_t)
	# ---- Kuwait City in a round ----
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(10)
	Net.perk = "aid"
	m._start({"map": "kuwait", "me": "P", "offline": true, "seed": 4242, "theme": "normal", "players": [
		{"name": "P", "role": "survivor", "char": "survivor1", "perk": "aid", "slot": 0},
		{"name": "D", "role": "survivor", "char": "survivor2", "slot": 1},
		{"name": "K", "role": "killer", "char": "killer", "slot": 2}]})
	for i in 1500:
		await tree.process_frame
		if m.world.ready_done: break
	await frames(30)
	var w = m.world
	check(w.ad_mat != null and w.ad_mat.albedo_texture != null, "the billboard shows his picture from the start")
	var scr: Node3D = w.find_child("AdScreen", true, false)
	check(scr != null and scr.global_position.distance_to(NightWorld.KW_BILL) < 9.0 and scr.global_position.y > 6.0, "high up on the main street")
	# nothing between the road and the screen
	var space: PhysicsDirectSpaceState3D = w.get_world_3d().direct_space_state
	var clear := 0
	for z in [20.0, 34.0, 48.0]:
		var q2 := PhysicsRayQueryParameters3D.create(Vector3(0, 7.0, z), scr.global_position)
		var hit := space.intersect_ray(q2)
		if hit.is_empty() or (hit.position as Vector3).distance_to(scr.global_position) < 2.5: clear += 1
	check(clear == 3, "seen from the road, nothing stands in front of it (%d/3)" % clear)
	var before = w.ad_mat.albedo_texture
	w.play_ad(true)
	await frames(10)
	check(w.ad_video != null and w.ad_mat.albedo_texture != before, "the developer tools' button: the video takes the screen")
	w.play_ad(false)
	check(w.ad_mat.albedo_texture == w.ad_img, "and stops back to his picture")
	check(w.police.size() == 4, "four police cars (%d)" % w.police.size())
	await frames(20)
	var flashing := 0
	for p in w.police: if (p[1] as OmniLight3D).light_energy > 0.0 or (p[2] as StandardMaterial3D).emission_energy_multiplier > 1.0 or (p[3] as StandardMaterial3D).emission_energy_multiplier > 1.0: flashing += 1
	check(flashing >= 1, "their lights go round from the start (%d flashing now)" % flashing)
	var silent := true
	for p in w.police: if p[4] and (p[4] as AudioStreamPlayer3D).playing: silent = false
	check(silent and not w.sirens_on, "and the sirens are silent")
	m.rules.gate_delay = 0.0
	for gg in m.rules.gens: gg.done = true
	await frames(30)
	check(m.rules.powered and w.sirens_on, "the gates open: the sirens start")
	check(w.boats.size() == 3, "boats on the water (%d)" % w.boats.size())
	var b0: Node3D = (w.boats[0][0] as Node3D).get_parent() if (w.boats[0][0] as Node3D).get_parent() != w else w.boats[0][0]
	var y0 := b0.position.y
	await frames(40)
	check(absf(b0.position.y - y0) > 0.002, "and they ride the swell (%.3f m)" % absf(b0.position.y - y0))
	var sea_ok := false
	for mi in w.find_children("*", "MeshInstance3D", true, false):
		var mm := mi as MeshInstance3D
		if mm.mesh is PlaneMesh and (mm.mesh as PlaneMesh).material is ShaderMaterial:
			sea_ok = sea_ok or ((mm.mesh as PlaneMesh).material as ShaderMaterial).shader.resource_path.ends_with("ocean.gdshader")
	check(sea_ok, "the sea is the wave shader")
	check(absf(w.wave_y(10.0, 5.0, 1.0) - w.wave_y(10.0, 5.0, 2.0)) > 0.001, "the waves move")
	check(m.kits.has("P") and (m.kits["P"] as Node3D).visible, "«المسعف» carries the first-aid kit")
	var kit_hand: float = (m.kits["P"] as Node3D).global_position.distance_to(m.rig.bone_at("LeftHand"))
	check(kit_hand < 0.4, "in his hand (%.2f m)" % kit_hand)
	check(not m.kits.has("D"), "nobody else does")
	var r2 := NFSniper.rifle()
	check(r2.get_child_count() == 1 and r2.get_child(0).name != "", "the sniper rifle is his model now")
	r2.free()
	check(w.heli_spot != Vector3.INF, "a spot for the rescue helicopter")
	# the helicopter in the round: D is gone, P is the last
	m.rules.s["D"].hp = "dead"
	for e in m.rules.tick(0.1): m._on_event(e)
	await frames(5)
	check(int(m.rules.heli.st) == 1 and m.heli != null and m.heli.visible, "the helicopter flies in")
	m.rules.heli.t = 0.05
	await frames(150)
	check(int(m.rules.heli.st) == 2 and m.heli.ladder.visible, "it hovers, the ladder down")
	var foot: Vector3 = m.heli.ladder_foot()
	check(absf(foot.y - w.heli_spot.y) < 2.0, "the ladder reaches the ground (%.1f m off)" % absf(foot.y - w.heli_spot.y))
	m.body.global_position = foot + Vector3(0.8, 0.3, 0)
	await frames(10)
	check(m.ctx.has("interact") and str(m.ctx.interact.kind) == "ladder", "next to it: «امسك السلم واطلع»")
	m._press("interact", 5)
	await frames(30)
	check(int(m.rules.heli.st) == 3 and m.body.global_position.y > foot.y + 0.2, "climbing (%.1f m up)" % (m.body.global_position.y - foot.y))
	for i in 420:
		await tree.physics_frame
		if int(m.rules.heli.st) == 4: break
	check(int(m.rules.heli.st) == 4 and m.rules.hp("P") == "escaped", "at the top: rescued")
	print("BATCH ", "PASS" if bad == 0 else "FAIL (%d)" % bad)
	tree.quit()
