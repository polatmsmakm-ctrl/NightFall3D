extends Node
## The owner's gorilla and «الوحش»'s meal on the hook:
##  - the gorilla model loads on the characters' skeleton, its clips play, its hands reach;
##  - with «الوحش» as the killer, a second hook cannot be lifted (both rules files say so), the body
##    goes stage by stage (15 bites), only the head is left, it is pulled up onto the hook and stays
##    there dead, with blood under the hook; with the other killer nothing of this happens;
##  - after the cat and the dog, the gorilla comes, the horse rears, falls, loses its head, is bitten,
##    swallowed, and the gorilla goes; the head stays on the ground.
var tree: SceneTree
var bad := 0

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok: bad += 1

func _ready() -> void:
	tree = get_tree()
	# ---- the model -----------------------------------------------------------------------------
	var r := CharacterRig.new()
	add_child(r)
	r.setup("gorilla", ["idle", "walk", "run", "attack", "repair"], false, false)
	check(r.skeleton != null and r.skeleton.find_bone("mixamorig_RightHand") >= 0, "gorilla: model on the Mixamo skeleton")
	var mi := r.model.find_children("*", "MeshInstance3D", true, false)
	var mat := (mi[0] as MeshInstance3D).get_active_material(0) as StandardMaterial3D if mi.size() > 0 else null
	check(mat != null and mat.albedo_texture != null and mat.normal_texture != null, "gorilla: colour and normal maps")
	check(r.has("run") and r.has("attack") and r.has("repair"), "gorilla: its clips")
	var top := r.bone_at("mixamorig_Head").y
	check(top > 1.3 and top < 2.1, "gorilla: head at %.2f m before scaling" % top)
	r.play("run")
	await frames(5)
	var a0 := r.bone_at("mixamorig_LeftFoot")
	await frames(12)
	check(r.bone_at("mixamorig_LeftFoot").distance_to(a0) > 0.05, "gorilla: the run moves its legs")
	var goal := r.bone_at("mixamorig_RightArm") + Vector3(0.1, 0.4, 0.45)
	r.reach(r.bone_at("mixamorig_LeftHand"), goal, Vector3(2, -1, 0), Vector3(-2, -1, 0))
	await frames(4)
	check(r.bone_at("mixamorig_RightHand").distance_to(goal) < 0.08, "gorilla: a hand reaches where it is sent (%.3f m)" % r.bone_at("mixamorig_RightHand").distance_to(goal))
	r.queue_free()
	# ---- the rules ------------------------------------------------------------------------------
	for kc in ["killer2", "killer"]:
		var ru := Rules.new()
		ru.setup(3, 2, 2, 1, [{"name": "K", "role": "killer", "char": kc}, {"name": "A", "role": "survivor", "char": "survivor1"},
			{"name": "B", "role": "survivor", "char": "survivor2"}], 5)
		ru.s.A.hp = "hooked"; ru.s.A.hooks = 2; ru.s.A.hook_i = 0; ru.s.A.t = 30.0
		ru.handle({"k": "rescue", "n": "A", "on": true}, "B")
		if kc == "killer2": check(ru.eaten("A") and not ru.rescuers.has("B"), "«الوحش»: his second hook cannot be lifted off")
		else: check(not ru.eaten("A") and ru.rescuers.has("B"), "the other killer: a second hook can be lifted as before")
	# ---- the meal on the hook --------------------------------------------------------------------
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(10)
	m._start({"map": "forest", "me": "P", "offline": true, "seed": 4242, "theme": "normal", "players": [
		{"name": "P", "role": "survivor", "char": "survivor1", "slot": 0},
		{"name": "D", "role": "survivor", "char": "survivor2", "slot": 1},
		{"name": "K", "role": "killer", "char": "killer2", "slot": 2}]})
	for i in 1500:
		await tree.process_frame
		if m.world.ready_done: break
	await frames(30)
	m.rules.ev_at = 99999.0
	check(m.rules.beast and m.feast != null and m.gorilla != null, "the round has the meal and the gorilla")
	if m.feast == null or m.gorilla == null:
		print("GORILLA FAIL %d" % (bad + 1))
		get_tree().quit(1)
		return
	var f = m.feast
	var w: NightWorld = m.world
	var D: Dictionary = m.rules.s["D"]
	D.hp = "hooked"; D.hooks = 2; D.hook_i = 1; D.t = Rules.HOOK_TIME[1]
	await frames(20)
	check(f.keeps("D") and f.e["D"].mats.size() > 0, "the second hook: the meal begins (%d surfaces on the shader)" % (f.e["D"].mats.size() if f.e.has("D") else 0))
	var rig: CharacterRig = m.remotes["D"].rig
	var cuts := []
	var heads := []
	var pools0: int = m.blood.count("pool")
	for k in 6: # the clock runs out in five steps; the cut climbs from under the feet to the neck
		D.t = Rules.HOOK_TIME[1] * (1.0 - k / 5.0) - (0.01 if k > 0 else 0.0)
		await frames(12)
		cuts.append(float(f.e["D"].mats[0].get_shader_parameter("cut_y")))
		heads.append(float(f.e["D"].mats[0].get_shader_parameter("head_r")))
	var feet := minf(rig.bone_at("mixamorig_LeftToeBase").y, rig.bone_at("mixamorig_RightToeBase").y)
	var rising := true
	for k in range(1, cuts.size()): if cuts[k] <= cuts[k - 1]: rising = false
	print("    cut: ", cuts.map(func(v): return snappedf(v, 0.01)), " feet ", snappedf(feet, 0.01))
	check(rising, "legs, thighs, stomach, chest, neck: the cut climbs each stage")
	check(heads[0] > 10.0 and heads[5] < 0.3, "the last stage leaves only a ball round the head")
	check(f.bites >= 5, "bites with every stage (%d)" % f.bites)
	m.rules.s["D"].hp = "dead"
	await frames(120)
	check(f.keeps("D") and m.remotes["D"].node.visible, "dead: what is left stays on the hook")
	var hd := rig.bone_at("mixamorig_Head")
	var tip: Vector3 = f.e["D"].tip
	check(absf(hd.y + 0.1 - (tip.y - 0.1)) < 0.25 and float(f.e["D"].lift) > 0.2, "the head pulled up onto the hook (%.2f m up, head %.2f, hook %.2f)" % [f.e["D"].lift, hd.y, tip.y])
	var hp: Vector3 = w.hook_points[1]
	check(Vector2(m.remotes["D"].node.position.x - hp.x, m.remotes["D"].node.position.z - (hp.z + 0.9)).length() < 0.3, "on the same hook")
	await frames(90)
	check(m.blood.count("pool") > pools0 and m.blood.landed > 10, "blood under the hook (%d pools, %d drops landed)" % [m.blood.count("pool"), m.blood.landed])
	check(m.esp_nodes.is_empty() or m.esp_nodes["D"].meshes.all(func(x): return x.material_overlay == null), "no see-through outline of the whole body")
	# the local player too
	var P: Dictionary = m.rules.s["P"]
	P.hp = "hooked"; P.hooks = 2; P.hook_i = 2; P.t = 3.0
	await frames(60)
	check(f.keeps("P") and m.ctx.get("interact", {}).get("kind", "") != "struggle", "me: eaten, no struggling off it")
	# ---- the gorilla and the horse -------------------------------------------------------------
	var cd: NFCatDog = m.catdog
	var go = m.gorilla
	check(go.state == 0 and go.rig == null, "the gorilla waits (not even loaded) until the dog has gone")
	cd._start_cat(0)
	cd._start_dog()
	cd.state = 3
	cd.ph = 6
	cd.dog.visible = false
	cd.cat.visible = false
	await frames(5)
	check(go.state == 1, "the dog gone: the gorilla's turn comes")
	go.wait = 0.05
	Engine.time_scale = 3.0
	await frames(10)
	check(go.state == 2 and go.rig != null and go.horse != null, "the scene starts: the gorilla and the horse")
	var h0: Vector3 = go.horse.global_position
	var big: float = go.rig.bone_at("mixamorig_Head").y - go.rig.global_position.y
	check(big > 3.0, "a titan: its head %.1f m up" % big)
	var g0: Vector3 = go.rig.global_position
	check(Vector2(g0.x - go.spot.x, g0.z - go.spot.z).length() > 14.0, "it comes from the dark (%.0f m)" % Vector2(g0.x - go.spot.x, g0.z - go.spot.z).length())
	var t0 := Time.get_ticks_msec()
	var in_hand := false
	var lifted := 0.0
	while go.state == 2 and Time.get_ticks_msec() - t0 < 90000:
		await tree.process_frame
		if go.head_state == 1: in_hand = in_hand or go.head.global_position.distance_to(go._hand(true).origin) < 1.2
		if go.ph == 8 and is_instance_valid(go.pivot): lifted = maxf(lifted, go.pivot.global_position.y - h0.y)
	Engine.time_scale = 1.0
	print("    phases ", go.phases.keys(), " rips ", go.rips, " bites ", go.bites, " splashes ", go.splashes)
	check(go.phases.has(2) and go.phases.has(3), "the horse rears and goes down")
	check(go.rips == 1 and in_hand, "the head torn off, in its hand")
	check(go.phases.has(5) and go.phases.has(6) and go.head_state == 3, "held up, thrown, and lying on the ground")
	if go.head:
		var hp2: Vector3 = go.head.global_position
		check(absf(hp2.y - w.height(hp2.x, hp2.z)) < 0.6, "the head rests on the ground (%.2f m off)" % (hp2.y - w.height(hp2.x, hp2.z)))
	check(go.bites >= 4, "bites into the body (%d)" % go.bites)
	check(go.swallowed and lifted > 2.0, "lifts it over its face (%.1f m) and swallows it" % lifted)
	check(go.splashes >= 8, "with blood (%d splashes)" % go.splashes)
	check(go.state == 3 and go.rig == null and go.head != null, "and goes; the head stays")
	print("GORILLA %s %d" % ["PASS" if bad == 0 else "FAIL", bad])
	get_tree().quit(1 if bad else 0)
