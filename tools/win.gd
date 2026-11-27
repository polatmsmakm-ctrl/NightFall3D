extends Node
## Phase 3 checks: a rescue that goes faster with more hands, the camp light following the
## clock on the phone, and the victory shot at the gate before the statistics.

var tree: SceneTree

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func rules_with(n_survivors: int) -> Rules:
	var list := [{"name": "K", "role": "killer"}]
	for i in n_survivors: list.append({"name": char(65 + i), "role": "survivor"})
	var r := Rules.new()
	r.setup(7, 2, 9, 5, list, 777, 8)
	return r

func _ready() -> void:
	tree = get_tree()
	# ---------- a rescue with more than one pair of hands ----------
	for hands in [1, 2, 3]:
		var r := rules_with(4)
		r.s["C"].hp = "hooked"
		r.s["C"].hooks = 1
		r.s["C"].hook_i = 0
		r.s["C"].t = Rules.HOOK_TIME[0]
		var who := ["A", "B", "D"]
		for i in hands: r.handle({"k": "rescue", "n": "C", "on": true}, who[i])
		var took := 0.0
		var done := false
		while took < 6.0 and not done:
			for e in r.tick(0.1):
				if str(e.get("k", "")) == "rescued":
					done = true
					print(hands, " rescuing: took ", snappedf(took + 0.1, 0.1), "s  hands in the event=", e.get("hands", 0))
			took += 0.1
		if not done: print(hands, " rescuing: NEVER FINISHED")
	var r2 := rules_with(4)
	r2.s["C"].hp = "hooked"
	r2.s["C"].hooks = 1
	r2.s["C"].hook_i = 0
	r2.s["C"].t = Rules.HOOK_TIME[0]
	r2.handle({"k": "rescue", "n": "C", "on": true}, "A")
	r2.handle({"k": "rescue", "n": "C", "on": true}, "B")
	r2.tick(0.4)
	var snap := r2.snapshot()
	var row: Array = snap.s["C"]
	print("the snapshot tells everyone: progress=", snappedf(float(row[8]), 0.01), " hands=", row[9])
	r2.handle({"k": "rescue", "n": "C", "on": false}, "B")
	r2.tick(0.1)
	print("one lets go: hands=", r2.snapshot().s["C"][9])
	r2.handle({"k": "rescue", "n": "C", "on": false}, "A")
	r2.tick(0.6)
	print("both let go: progress back to ", snappedf(float(r2.snapshot().s["C"][8]), 0.01), " (nobody is rescued)")
	# ---------- the camp follows the clock ----------
	var menu = load("res://scripts/menu.gd").new()
	for h in [6, 12, 18, 23]:
		NFLobby.force_hour = h
		NFLobby.force_mist = 0
		var lb := NFLobby.new()
		tree.root.add_child.call_deferred(lb)
		await frames(6)
		if lb.painted: # the owner's painting: the same night at every hour, on purpose
			print("at %02d:00 the camp is the owner's painting (fixed)" % h)
			lb.queue_free()
			await frames(3)
			continue
		print("at %02d:00 the camp is " % h, lb.period,
			"  sky day=", snappedf(float(lb.sky_mat.get_shader_parameter("day")), 0.01),
			" warm=", snappedf(float(lb.sky_mat.get_shader_parameter("warm")), 0.01),
			" moonlight=", snappedf(lb.moon.light_energy, 0.01),
			" fog=", snappedf(lb.env.fog_density, 0.001),
			" fire=", snappedf(lb.fire_mul, 0.01))
		lb.queue_free()
		await frames(3)
	NFLobby.force_hour = 21
	NFLobby.force_mist = 1
	var lb2 := NFLobby.new()
	tree.root.add_child.call_deferred(lb2)
	await frames(6)
	if not lb2.painted: print("a misty night: misty=", lb2.misty, " fog=", snappedf(lb2.env.fog_density, 0.001))
	lb2.queue_free()
	NFLobby.force_hour = -1
	NFLobby.force_mist = -1
	menu.free()
	await frames(3)
	# ---------- the victory shot ----------
	var res := NFResults.new()
	tree.root.add_child.call_deferred(res)
	await frames(2)
	res.setup({"rows": [
			{"name": "راشد", "char": "survivor2", "role": "survivor", "state": "escaped", "score": 300.0, "mine": true},
			{"name": "بدر", "char": "survivor5", "role": "survivor", "state": "escaped", "score": 210.0},
			{"name": "يوسف", "char": "survivor6", "role": "survivor", "state": "dead", "score": 90.0},
			{"name": "فهد", "char": "killer", "role": "killer", "state": "killer", "score": 150.0}],
		"victory": [
			{"name": "راشد", "char": "survivor2", "role": "survivor", "state": "escaped", "score": 300.0, "mine": true},
			{"name": "بدر", "char": "survivor5", "role": "survivor", "state": "escaped", "score": 210.0}],
		"title": "You escaped!", "stats": "اختبار", "xp_from": 100, "xp_to": 400,
		"escapes": 3, "kills": 1})
	await frames(10)
	var at_gate := 0
	for c in res.vic_stage.get_children():
		if c is CharacterRig: at_gate += 1
	print("at the gate: ", at_gate, " of ", res.rows.size(), " players (only the ones who got out)")
	print("dead men are not in the shot: ", at_gate == res.vic.size())
	print("the numbers wait: statistics hidden=", not res.row_stage.visible,
		" buttons hidden=", not (res.btns[0] as Control).visible if res.btns.size() > 0 else "-")
	var seen := 0 # are they actually in shot?
	for c in res.vic_stage.get_children():
		if c is CharacterRig and not res.cam.is_position_behind((c as CharacterRig).global_position + Vector3(0, 1.2, 0)):
			var sp := res.cam.unproject_position((c as CharacterRig).global_position + Vector3(0, 1.2, 0))
			var vp: Vector2 = res.get_viewport().get_visible_rect().size
			if sp.x > 0.0 and sp.x < vp.x and sp.y > 0.0 and sp.y < vp.y: seen += 1
	print("in front of the camera: ", seen, " of ", res.vic.size())
	var first: Vector3 = res.cam.global_position
	await frames(40)
	print("the camera moves round them: ", snappedf(first.distance_to(res.cam.global_position), 0.01), " m")
	for i in 900:
		await tree.process_frame
		if res.intro <= 0.0: break
	await frames(4)
	print("then the statistics: visible=", res.row_stage.visible, " gate gone=", not res.vic_stage.visible,
		" buttons back=", (res.btns[0] as Control).visible, " camera home=", res.cam.position.snapped(Vector3(0.1, 0.1, 0.1)))
	await frames(120)
	print("xp bar runs after the shot: ", snappedf(res.xp_show, 1.0), " of ", res.xp_to)
	# a round the survivors lost goes straight to the numbers
	res.queue_free()
	await frames(5)
	var res2 := NFResults.new()
	tree.root.add_child.call_deferred(res2)
	await frames(2)
	res2.setup({"rows": [{"name": "راشد", "char": "survivor2", "role": "survivor", "state": "dead", "score": 60.0, "mine": true}],
		"victory": [], "title": "You didn't make it", "stats": "اختبار", "xp_from": 0, "xp_to": 60, "escapes": 0, "kills": 0})
	await frames(8)
	print("nobody escaped: shot skipped=", res2.intro <= 0.0, " statistics up=", res2.row_stage.visible)
	tree.quit()
