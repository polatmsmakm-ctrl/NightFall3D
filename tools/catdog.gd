extends Node
## The owner's cat and dog: rigged models loaded with their bones, the cat brought by the first repair
## (walking round the generator on the ground, meowing, acting), the dog when that generator is done
## (stalk, freeze, bark, sprint, bite, shake with blood, swallow, run off), and every phone agreeing.
var tree: SceneTree
var bad := 0

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok: bad += 1

func _ready() -> void:
	tree = get_tree()
	# the two models on their own
	for k in ["cat", "dog"]:
		var a := NFAnimal.new()
		add_child(a)
		var ok := a.setup(k)
		check(ok and a.skel != null and a.skel.get_bone_count() >= 28, "%s: model and skeleton load (%d bones)" % [k, a.skel.get_bone_count() if a.skel else 0])
		if not ok: continue
		var mi := a.model.find_children("*", "MeshInstance3D", true, false)
		check(mi.size() > 0 and (mi[0] as MeshInstance3D).skin != null, "%s: the mesh is skinned to it" % k)
		var mat := (mi[0] as MeshInstance3D).get_active_material(0) as StandardMaterial3D
		check(mat != null and mat.albedo_texture != null and mat.normal_texture != null, "%s: colour and normal maps" % k)
		check(a.tails.size() >= 4 and a.leg_len > 0.05, "%s: tail chain %d, legs %.2f m" % [k, a.tails.size(), a.leg_len])
		var rest := a.skel.get_bone_pose_rotation(a.bi["fl_top"])
		a.speed = 1.0 if k == "cat" else 2.5
		for i in 20: a.pose(0.05)
		check(not a.skel.get_bone_pose_rotation(a.bi["fl_top"]).is_equal_approx(rest), "%s: the legs move with the speed" % k)
		if k == "dog":
			var mo := a.point_on("head", NFCatDog.DOG_MOUTH)
			var hz := Vector2(mo.x, mo.z).length()
			check(hz > 0.45 and hz < 0.95 and mo.y > 0.45, "dog: the mouth is at the front of the head (%.2f m out, %.2f up)" % [hz, mo.y])
		a.queue_free()
	# in a round
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(10)
	m._start({"map": "forest", "me": "P", "offline": true, "seed": 4242, "theme": "normal", "players": [
		{"name": "P", "role": "survivor", "char": "survivor1", "slot": 0},
		{"name": "D", "role": "survivor", "char": "survivor2", "slot": 1},
		{"name": "K", "role": "killer", "char": "killer", "slot": 2}]})
	for i in 1500:
		await tree.process_frame
		if m.world.ready_done: break
	await frames(30)
	m.rules.ev_at = 99999.0
	var cd: NFCatDog = m.catdog
	check(cd != null and cd.state == 0, "the round has the cat and dog, waiting")
	if cd == null:
		print("CATDOG FAIL %d" % (bad + 1))
		get_tree().quit(1)
		return
	check(not cd.cat.visible and not cd.dog.visible, "nobody sees them before a repair starts")
	Engine.time_scale = 2.0
	var g := 2
	m.rules.gens[g].p = 0.05
	await frames(5)
	check(cd.state == 1 and cd.gen == g and cd.cat.visible, "the first repair brings the cat (state %d, gen %d)" % [cd.state, cd.gen])
	var gp: Vector3 = m.world.gen_points[g]
	var start: Vector3 = cd.cat.position
	check(start.distance_to(gp) > 3.0 and start.distance_to(gp) < 10.5, "it comes from a little way off (%.1f m)" % start.distance_to(gp))
	# every phone puts it in the same place
	var cd2 := NFCatDog.new()
	m.world.add_child(cd2)
	cd2.setup(m.world, m.rules, m.blood, Callable(), Callable(), [m.body.get_rid()])
	cd2.set_process(false)
	cd2._start_cat(g)
	check(cd2.cat.position.distance_to(start) < 0.6 and absf(wrapf(cd2.ang - cd.ang, -PI, PI)) < 0.01, "another phone starts it at the same spot (%.2f m: the first has walked a few frames)" % cd2.cat.position.distance_to(start))
	cd2.queue_free()
	var t0 := Time.get_ticks_msec()
	var near := 0
	var far_moved := 0.0
	var ground_bad := 0
	var samples := 0
	var last: Vector3 = cd.cat.position
	while Time.get_ticks_msec() - t0 < 14000:
		await frames(6)
		m.rules.gens[g].p = minf(m.rules.gens[g].p + 0.002, 0.95)
		var c: Vector3 = cd.cat.position
		far_moved += c.distance_to(last)
		last = c
		var hd := Vector2(c.x - gp.x, c.z - gp.z).length()
		if hd > 1.2 and hd < 3.6: near += 1
		var gy: float = m.world.height(c.x, c.z)
		if absf(c.y - gy) > 0.35: ground_bad += 1
		samples += 1
	check(near > samples / 2, "it stays round the people at the generator (%d of %d)" % [near, samples])
	check(far_moved > 2.0, "it walks about (%.1f m)" % far_moved)
	check(ground_bad <= samples / 10, "its paws stay on the ground (%d off of %d)" % [ground_bad, samples])
	check(cd.meows >= 1 and cd.acts.size() >= 1, "it meows (%d) and does things: %s" % [cd.meows, str(cd.acts)])
	# the generator is done: the dog
	m.rules.gens[g].p = 1.0
	m.rules.gens[g].done = true
	await frames(5)
	check(cd.state == 2 and cd.dog.visible, "the generator done: the dog comes")
	var dd: float = cd.dog.position.distance_to(cd.cat.position)
	check(dd > 6.0, "from the dark, well away (%.1f m)" % dd)
	var seen := {}
	var min_d := 99.0
	t0 = Time.get_ticks_msec()
	while cd.state == 2 and Time.get_ticks_msec() - t0 < 40000:
		await tree.process_frame
		seen[cd.ph] = true
		if cd.ph == 0: min_d = minf(min_d, cd.dog.speed)
		if cd.ph == 3:
			var mouth := cd.dog.point_on("head", NFCatDog.DOG_MOUTH)
			var cc := cd.cat.to_global(cd.cat.centre)
			seen["held"] = mouth.distance_to(cc) < 0.05
	check(seen.has(0) and seen.has(1) and seen.has(2), "stalks, stops, runs at it")
	check(cd.barks == 1, "barks once as it goes")
	check(cd.bites == 1 and seen.get("held", false), "bites and holds the cat in its mouth")
	check(seen.has(3) and seen.has(4), "shakes it, swallows it")
	check(cd.splashes >= 6 and m.blood._d_live + m.blood.landed > 10, "with blood (%d splashes, %d drops landed)" % [cd.splashes, m.blood.landed])
	check(cd.state == 3 and not cd.cat.visible and not cd.dog.visible, "and runs off: both gone, once a round")
	Engine.time_scale = 1.0
	print("CATDOG %s %d" % ["PASS" if bad == 0 else "FAIL", bad])
	get_tree().quit(1 if bad else 0)
