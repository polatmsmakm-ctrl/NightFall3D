extends Node
## «City Life», Bloom and «الوحش», the ravens, the rain, the owner's props on every map, the pistol's
## shot, and the optimisation pass (occluders, visibility ranges, animation throttling, the Low preset
## and the performance monitor).

var tree: SceneTree
var bad := 0

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok: bad += 1

func boot(map: String, me_char: String, killer_char: String, theme := "normal", gun := false):
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(10)
	m._start({"map": map, "me": "P", "offline": true, "seed": 4242, "theme": theme, "gun": gun, "players": [
		{"name": "P", "role": "survivor", "char": me_char, "slot": 0},
		{"name": "K", "role": "killer", "char": killer_char, "slot": 1}]})
	for i in 1200:
		await tree.process_frame
		if m.world.ready_done: break
	await frames(20)
	return m

func _ready() -> void:
	tree = get_tree()
	# --- City Life, as Bloom, hunted by «الوحش», in the rain
	var m = await boot("city", "survivor9", "killer2", "rain", true)
	var w = m.world
	check(w.map_id == "city" and w.buildings.size() == 24, "City Life: 24 blocks (%d)" % w.buildings.size())
	check(w.city_towers.size() == 24 and w.city_parts > 40, "towers, neon and street lamps (%d parts)" % w.city_parts)
	check(w.gen_points.size() == 7 and w.hook_points.size() >= 9 and w.gate_points.size() == 2 and w.locker_points.size() >= 10,
		"and the same bones as every map: 7 generators, hooks, 2 gates, lockers")
	check(w.on_street(0.0, 15.5) and not w.on_street(-56.0, -31.0), "the streets are streets, the blocks are not")
	check(w.surface_at(Vector3(10, 0, 10)) == "indoor", "footsteps on pavement")
	check(w.occluders > 40, "occluders: walls and towers hide what is behind them (%d)" % w.occluders)
	check(ProjectSettings.get_setting("rendering/occlusion_culling/use_occlusion_culling", false), "occlusion culling is on")
	check(w.ranged > 50, "visibility ranges on the small and middle-sized things (%d)" % w.ranged)
	check(w.owner_props >= 4, "his cars and lantern trees in the city (%d)" % w.owner_props)
	check(w.scenery >= (1 if ResourceLoader.exists("res://assets/props/city_skyline.glb") else 0), "his cyberpunk city round the outside (%d)" % w.scenery)
	# the characters
	check(m.chars.get("P") == "survivor9" and m.rig != null, "Bloom is playable")
	check(Rules.PERK.get("survivor9") == "mend", "Bloom's perk: «تفتّح»")
	m.rules.s["P"].hp = "hurt"
	m.rules.s["P"].rt = 0.0
	for i in 50: m.rules.tick(1.0)
	check(m.rules.s["P"].hp == "ok", "she mends herself after 45 s hurt and alone")
	# a blow: the knife, the blood, a hand on the wound, drops left behind while she walks
	var ammo0 = m.rules.s["P"].get("ammo", 0)
	m.rules.s["P"].ammo = 0 # the pistol away (it holds the arms while it is out)
	m.rules.s["P"].hp = "hurt"
	await frames(3)
	var bl: NFBlood = m.blood
	check(bl != null and bl.sets["pool"].mm.mesh != null and bl.drops_mm.mesh != null, "the blood system runs on his models (pool, smear, drop)")
	m._on_event({"k": "hurt", "n": "P", "s": "hurt"})
	check(bl.drops_live() >= 6, "the blow: a spray of drops in the air (%d)" % bl.drops_live())
	check(bl.count("pool") >= 1, "and a pool spreading under her")
	for i in 90: await tree.physics_frame
	check(bl.landed >= 6 and bl.drops_live() < 6, "the drops fall and land (%d landed)" % bl.landed)
	var pm: Dictionary = bl.sets["pool"]
	var on_ground := true
	for i in int(pm.n):
		var t: Transform3D = pm.xf[i]
		if absf(t.origin.y - m.body.global_position.y) > 0.6: on_ground = false
	check(on_ground, "every pool lies on the ground under her, not floating or sunk")
	var spread0: float = bl._spread(pm, 0)
	var marks0: int = bl.count("pool") + bl.count("smear")
	var landed0: int = bl.landed
	var start: Vector3 = m.body.global_position
	m.stick_vec = Vector2(0, -1)
	for i in 150: await tree.physics_frame
	m.stick_vec = Vector2.ZERO
	await frames(2)
	check(bl.landed > landed0 + 1, "hurt, she drips as she walks (%d more drops)" % (bl.landed - landed0))
	var near := 0
	for i in int(pm.n):
		var t: Transform3D = pm.xf[i]
		var o := t.origin
		var ab: Vector3 = m.body.global_position - start
		var tt := clampf((o - start).dot(ab) / maxf(ab.length_squared(), 0.01), 0.0, 1.0)
		if Vector2(o.x, o.z).distance_to(Vector2(start.x + ab.x * tt, start.z + ab.z * tt)) < 1.2: near += 1
	check(near >= 2, "and the drops lie along the way she went (%d)" % near)
	check(bl._spread(pm, 0) > spread0 or spread0 >= 0.99, "the first pool keeps spreading")
	check(m.rig.get_meta("clutch", false) and m.rig.reach_mod.use[0] and not m.rig.reach_mod.use[1], "and holds the wound with one hand")
	m.rules.s["P"].hp = "ok"
	await frames(3)
	check(not m.rig.get_meta("clutch", false), "healed, the hand comes away")
	check(not bl._st.has("P"), "and the bleeding stops")
	# drying and fading
	var keep := bl._clock
	bl._clock += NFBlood.MARK_LIFE * 0.7
	bl._tick = 0.0
	await frames(2)
	var c: Color = (bl.sets["pool"].mm as MultiMesh).get_instance_custom_data(0)
	check(c.g > 0.3, "an old pool has dried (%.2f)" % c.g)
	bl._clock = keep + NFBlood.MARK_LIFE + 1.0
	bl._tick = 0.0
	await frames(2)
	check(bl.count("pool") == 0 and bl.count("smear") == 0, "and is gone at the end of its life")
	# a wall behind her takes the splash
	var wall := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(4, 4, 0.3)
	cs.shape = bx
	wall.add_child(cs)
	m.add_child(wall)
	wall.global_position = m.body.global_position + Vector3(0, 1.5, 1.6)
	await tree.physics_frame
	await tree.physics_frame
	bl.splash(m.body.global_position + Vector3(0, 1.15, 0), Vector3(0, 0, 1))
	check(bl.count("wall") >= 1, "a wall behind her takes the splash (%d)" % bl.count("wall"))
	wall.queue_free()
	# down: a smear behind her as she crawls
	var sm0: int = bl.count("smear")
	for i in 60:
		bl.bleed("Q", Vector3(m.body.global_position.x + i * 0.05, m.body.global_position.y, m.body.global_position.z - 3.0), 2)
		await tree.physics_frame
	check(bl.count("smear") > sm0, "down, she drags a smear behind her (%d)" % (bl.count("smear") - sm0))
	m.rules.s["P"].ammo = ammo0
	var kr = m.remotes["K"].rig
	check(kr.hunch != null, "«الوحش» moves hunched (NFHunch on his skeleton)")
	kr.play("drive")
	check(kr.hunch.want == 0.0, "but sits straight at the wheel")
	kr.play("run")
	check(kr.hunch.want == 1.0, "and hunches again on foot")
	# the chase: he screams, the survivor's screen shakes a little
	m.remotes["K"].node.position = m.body.position + Vector3(0, 0, 6)
	m.remotes["K"].pos = m.remotes["K"].node.position
	await frames(30)
	check(m._cry_cd > 0.0, "he screams when the chase starts")
	# ravens and rain
	check(m.ravens != null and m.ravens.birds.size() >= 7, "the ravens fly (%d)" % (m.ravens.birds.size() if m.ravens else 0))
	check(m.rain_audio != null and m.rain_audio.playing, "the rain is heard in «مطر»")
	# the shot: his sound, flash, bullet, smoke, sparks, a case
	var before: int = m.get_child_count()
	m._beam(m.body.position + Vector3(0, 1.4, 0), m.body.position + Vector3(0, 1.4, 12), false, true)
	await frames(2)
	check(m.get_child_count() > before + 3, "a shot: flash, smoke, the bullet and the case (%d new)" % (m.get_child_count() - before))
	# animation throttling: a far remote is posed less often
	m.remotes["K"].node.position = m.body.position + Vector3(0, 0, 95)
	m.remotes["K"].pos = m.remotes["K"].node.position
	await frames(20)
	check(kr.anim_every > 1, "a far character's skeleton is posed less often (every %d frames)" % kr.anim_every)
	# the presets: Low and the monitor
	Gfx.preset = 3
	Gfx.apply()
	await frames(2)
	check(Gfx.low() and Gfx.view_dist() <= 80.0 and get_viewport().mesh_lod_threshold >= 3.0, "«منخفض»: shorter view, simpler models sooner")
	Gfx.perf_hud = true
	var txt: String = Gfx._perf_text(1.0 / 60.0)
	check(txt.contains("رسم") and txt.contains("مثلثات") and txt.contains("MB"), "«مراقب الأداء» shows draw calls, triangles and memory")
	Gfx.preset = 1; Gfx.perf_hud = false; Gfx.apply()
	m.queue_free()
	await frames(5)
	# --- his props on the other maps
	for mp in ["forest", "rubkhali", "beach"]:
		var m2 = await boot(mp, "survivor1", "killer")
		check(m2.world.owner_props > 0, "%s: his props are there (%d)" % [mp, m2.world.owner_props])
		check(m2.world.raven_perches().size() >= 9, "%s: ravens have somewhere to sit" % mp)
		m2.queue_free()
		await frames(5)
	print("city: %d failed" % bad)
	tree.quit()
