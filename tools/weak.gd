extends Node
## An older iPhone (NF_WEAK=1, as the iPhone 13 / 14 / 15 report themselves): its own start (the
## Mobile renderer from the next launch, nothing heavy meanwhile), the governor going further down
## (70% resolution, then a steady 30), thinner grass, sooner LOD, shorter light reach; and a round
## still plays. Cleans up after itself so the other runs keep Forward+.
var tree: SceneTree
var bad := 0

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok: bad += 1

func _ready() -> void:
	tree = get_tree()
	check(Gfx.weak and not Gfx.strong, "seen as an older phone")
	check(FileAccess.file_exists(Gfx.ENGINE_PATH) and not Gfx.engine_next_hd(), "the next launch runs the Mobile renderer")
	check(Gfx.fps_idx == 2 and Gfx.target_fps() == 60, "a locked 60 to start with (%d)" % Gfx.target_fps())
	check(Gfx.scale_idx == 0 and absf(Gfx.render_scale() - 0.85) < 0.01, "85%% resolution (%.2f)" % Gfx.render_scale())
	check(Gfx.shadows == 1 and Gfx.aa == 1 and Gfx.effects == 1, "moon shadows, MSAA 2x, light effects")
	var c := ConfigFile.new()
	c.load(Gfx.PATH)
	check(int(c.get_value("g", "weak", 0)) == Gfx.WEAK_TIER, "done once: saved, so the player's own choices stand afterwards")
	check(get_viewport().mesh_lod_threshold >= 2.0, "simpler model detail sooner (lod %.1f)" % get_viewport().mesh_lod_threshold)
	# the governor, all the way down
	Gfx.fps_idx = 2
	for i in 20: Gfx._step_down()
	print("   after 20 steps down: scale %.2f, shadows %d, effects %d, fps %d" % [Gfx.render_scale(), Gfx.eff_shadows(), Gfx.eff_effects(), Gfx.target_fps()])
	check(absf(Gfx.render_scale() - 0.7) < 0.01, "resolution down to 70%")
	check(Gfx.eff_shadows() == 0 and Gfx.eff_effects() == 0, "shadows and effects given away")
	check(Gfx.target_fps() == 30, "and a steady 30 as the last step")
	Gfx._reset_runtime()
	Gfx.apply()
	# a round on the forest
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	for i in 10: await tree.process_frame
	m._start({"map": "forest", "me": "P", "offline": true, "players": [
		{"name": "P", "role": "survivor", "char": "survivor2", "slot": 0},
		{"name": "D", "role": "survivor", "char": "survivor5", "slot": 1, "dummy": true}]})
	for i in 900:
		await tree.process_frame
		if m.world.ready_done: break
	for i in 30: await tree.physics_frame
	var w: NightWorld = m.world
	check(w.ready_done, "the forest builds")
	var faded := 0
	var lights := 0
	for l in w.find_children("*", "OmniLight3D", true, false):
		lights += 1
		if (l as OmniLight3D).distance_fade_enabled and (l as OmniLight3D).distance_fade_begin <= 32.0: faded += 1
	check(lights > 0 and faded == lights, "every lamp fades out at 32 m (%d of %d)" % [faded, lights])
	check(not m.hd_chars(), "the round uses the light character models")
	m.stick_vec = Vector2(0, -1)
	var p0: Vector3 = m.body.position
	for i in 90: await tree.physics_frame
	check(m.body.position.distance_to(p0) > 3.0, "and I can walk (%.1f m)" % m.body.position.distance_to(p0))
	m.queue_free()
	# leave the machine as it was for the other runs
	Gfx.set_engine(true)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Gfx.PATH))
	print("WEAK DONE bad=", bad)
	tree.quit()
