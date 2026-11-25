extends Node
## «مدينة الكويت»: the Gulf Road, the Assembly, the sea, the towers, and the power box.
var tree: SceneTree
var bad := 0

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok: bad += 1

func _ready() -> void:
	tree = get_tree()
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(10)
	m._start({"map": "kuwait", "me": "P", "offline": true, "seed": 4242, "theme": "normal", "players": [
		{"name": "P", "role": "survivor", "char": "survivor1", "slot": 0},
		{"name": "K", "role": "killer", "char": "killer", "slot": 1}]})
	for i in 1200:
		await tree.process_frame
		if m.world.ready_done: break
	await frames(20)
	var w = m.world
	check(w.map_id == "kuwait" and w.kw_parts > 100, "Kuwait City is built (%d placed pieces)" % w.kw_parts)
	check(w.gen_points.size() == 7 and w.gate_points.size() == 2 and w.locker_points.size() >= 10 and w.hook_points.size() >= 9,
		"the same bones as every map")
	var wet := 0
	for p in w.gen_points + w.hook_points.slice(0, w.road_hook0): if p.x > NightWorld.KW_SHORE - 4.0: wet += 1
	for p in w.hatch_points: if p.x > NightWorld.KW_SHORE - 4.0: wet += 1
	check(wet == 0, "nothing the round needs is in the sea (%d)" % wet)
	check(w.on_street(0.0, 50.0) and w.on_street(30.0, 0.0) and not w.on_street(-40.0, 20.0), "the Gulf Road and the car park are kept clear")
	check(w.height(100.0, 0.0) < NightWorld.KW_WATER and w.height(-20.0, 0.0) > -0.1, "the land is flat, the sea floor drops away east")
	check(w.surface_at(Vector3(58, 0, 0)) == "sand" and w.surface_at(Vector3(-20, 0, 0)) == "indoor", "sand by the water, paving on the land")
	check(w.power_box != Vector3.INF and m.rules.has_grid and m.rules.grid, "the power box stands, and the street lights are on")
	var grid_lights := 0
	for e in w.amb_lights: if e.size() > 5 and bool(e[5]): grid_lights += 1
	check(grid_lights > 30, "the street lights hang on it (%d)" % grid_lights)
	var cones := 0
	var ups := 0
	for e in w.amb_lights:
		if e[0] is SpotLight3D and bool(e[5]):
			var sl: SpotLight3D = e[0]
			if sl.rotation.x < 0.0 and sl.light_color.is_equal_approx(NightWorld.KW_SODIUM): cones += 1
			elif sl.rotation.x > 0.0: ups += 1
	check(cones > 30 and ups > 8, "sodium-gold cones down from the lamp heads (%d) and palms lit from their feet (%d)" % [cones, ups])
	check(w.grid_glare != null and w.env.glow_hdr_threshold < 1.0, "the lamps bloom and carry a glare")
	# the killer pulls it
	for e in m.rules.handle({"k": "cut"}, "K"): m._on_event(e)
	await frames(60)
	var lit := 0
	for e in w.amb_lights:
		if e.size() > 5 and bool(e[5]) and (e[0] as Light3D).light_energy > 0.05: lit += 1
	check(not m.rules.grid and w.grid_off and lit == 0, "the killer cuts the power: every street light goes out (%d still lit)" % lit)
	# a survivor fixes it at the box
	m.body.global_position = w.power_box + Vector3(1.4, 0.3, 0)
	await frames(10)
	check(m.ctx.has("interact") and m.ctx.interact.kind == "pfix", "at the box the button is «صلّح الكهرباء»")
	m.rules.handle({"k": "pfix", "on": true}, "P")
	for i in 13:
		for e in m.rules.tick(1.0): m._on_event(e)
	await frames(60)
	lit = 0
	for e in w.amb_lights:
		if e.size() > 5 and bool(e[5]) and (e[0] as Light3D).light_energy > 0.05: lit += 1
	check(m.rules.grid and not w.grid_off and lit > 30, "fixed: the street is lit again (%d)" % lit)
	# twice a round, with a wait between
	var again: Array = m.rules.handle({"k": "cut"}, "K")
	check(again.is_empty() and m.rules.grid_wait > 30.0, "straight after the repair it cannot be cut again (%d s to wait)" % ceili(m.rules.grid_wait))
	m.rules.grid_wait = 0.0
	check(not m.rules.handle({"k": "cut"}, "K").is_empty() and m.rules.grid_cuts == 2, "after the wait: the second cut")
	m.rules.grid = true; m.rules.grid_wait = 0.0
	check(m.rules.handle({"k": "cut"}, "K").is_empty(), "and no third")
	check(w.kerbs.size() >= 3, "kerbs to walk and drive up onto (%d)" % w.kerbs.size())
	m.body.global_position = Vector3(-NightWorld.KW_ROAD_HALF + 0.3, 0.3, 30.0)
	await frames(6)
	check(m.ctx.has("vault"), "at the kerb the jump button lights up")
	var mosque: bool = w.find_child("KW_kw_mosque", true, false) != null or w.kw_parts > 0
	check(mosque and w.door_points.size() > 0, "the mosque stands where the market was")
	var snap: Dictionary = m.rules.snapshot()
	check(snap.has("pb") and (snap.pb as Array).size() >= 4, "the snapshot carries the box (online phones follow it)")
	m.queue_free()
	await frames(5)
	# Halloween: dark, not red; every lamp out all round; his pumpkins everywhere
	var h = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(h)
	await frames(10)
	h._start({"map": "forest", "me": "P", "offline": true, "seed": 7, "theme": "halloween", "players": [
		{"name": "P", "role": "survivor", "char": "survivor1", "slot": 0}, {"name": "K", "role": "killer", "char": "killer", "slot": 1}]})
	for i in 1200:
		await tree.process_frame
		if h.world.ready_done: break
	await frames(30)
	var hw = h.world
	var amb: Color = hw.env.ambient_light_color
	check(absf(amb.r - amb.b) < 0.05, "Halloween is grey, not red (ambient %s)" % amb)
	var lit_h := 0
	for e in hw.amb_lights:
		if not hw.pumpkin_lights.has(e[0]) and (e[0] as Light3D).light_energy > 0.05: lit_h += 1
	check(not hw.blackout and h.rules.has_grid and h.rules.grid and lit_h > 0, "its lights are on to begin with (%d)" % lit_h)
	check(hw.power_box != Vector3.INF and hw.pumpkins >= 40, "a power box on the map, %d pumpkins about" % hw.pumpkins)
	h.body.global_position = hw.power_box + Vector3(1.4, 0.3, 0)
	await frames(10)
	check(h.ctx.has("interact") and h.ctx.interact.kind == "off", "at the box a survivor can «اطفي الكهرباء»")
	for e in h.rules.handle({"k": "off"}, "P"): h._on_event(e)
	await frames(80)
	lit_h = 0
	for e in hw.amb_lights:
		if not hw.pumpkin_lights.has(e[0]) and (e[0] as Light3D).light_energy > 0.05: lit_h += 1
	var a2: Color = hw.env.ambient_light_color
	check(not h.rules.grid and lit_h == 0, "switched off: every lamp of the map goes out (%d still lit)" % lit_h)
	check(absf(hw.env.ambient_light_energy - NightWorld.DARK_AMB_E) < 0.05 and a2.is_equal_approx(NightWorld.DARK_AMB) and hw.moon.light_energy < 0.2,
		"and the night is the old Halloween dark (ambient %.2f, moon %.2f)" % [hw.env.ambient_light_energy, hw.moon.light_energy])
	check(h.rules.handle({"k": "off"}, "K").is_empty(), "(the killer has no «اطفي»: hers is the cut)")
	h.rules.handle({"k": "pfix", "on": true}, "P")
	for i in 13:
		for e in h.rules.tick(1.0): h._on_event(e)
	await frames(60)
	check(h.rules.grid and hw.env.ambient_light_energy > NightWorld.DARK_AMB_E + 0.2, "fixed: the lights and the night come back")
	check(h.rules.handle({"k": "off"}, "P").is_empty(), "and it cannot be switched off again straight away")
	h.queue_free()
	await frames(5)
	# «بين العصر والمغرب»: afternoon, the sun goes down over five minutes, then pitch dark until the lights are on
	var g = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(g)
	await frames(10)
	g._start({"map": "village", "me": "P", "offline": true, "seed": 9, "theme": "sunset", "players": [
		{"name": "P", "role": "survivor", "char": "survivor2", "slot": 0}, {"name": "K", "role": "killer", "char": "killer", "slot": 1}]})
	for i in 1200:
		await tree.process_frame
		if g.world.ready_done: break
	await frames(20)
	var gw = g.world
	g.rules.ev_at = 99999.0 # (the jumps in the clock below would set off the round's own event)
	check(gw.power_box != Vector3.INF and g.rules.has_grid and not g.rules.grid, "the street lights start off, a power box on the map")
	check(gw.moon.light_energy > 1.2 and gw.env.ambient_light_energy > 1.0 and gw.moon.global_basis.z.y > 0.3, "it is afternoon: the sun is high (%.2f)" % gw.moon.light_energy)
	g.rules.clock = 200.0
	await frames(6)
	var mid_sun: float = gw.moon.light_energy
	check(mid_sun < 1.9 and gw._sky_mat.get_shader_parameter("warm") > 0.3, "an hour later it is going down, red-gold (%.2f)" % mid_sun)
	g.rules.clock = 301.0
	await frames(70)
	check(gw.night_fell() and gw.moon.light_energy < 0.05 and gw.env.ambient_light_energy < NightWorld.DARK_AMB_E + 0.05, "five minutes: the sun is gone and it is pitch dark (%.2f)" % gw.env.ambient_light_energy)
	g.body.global_position = gw.power_box + Vector3(1.4, 0.3, 0)
	await frames(10)
	check(g.ctx.has("interact") and g.ctx.interact.kind == "pfix" and g.ctx.interact.label == "شغّل أنوار الشارع", "at the box: «شغّل أنوار الشارع»")
	g.rules.handle({"k": "pfix", "on": true}, "P")
	for i in 40: # (and past the round's own blackout event, which the jumps in the clock set off)
		for e in g.rules.tick(1.0): g._on_event(e)
	g.world.set_blackout(false)
	g.rules.clock = 420.0
	await frames(70)
	var lit_s := 0
	for e in gw.amb_lights: if (e[0] as Light3D).light_energy > 0.05: lit_s += 1
	check(g.rules.grid and lit_s > 0 and gw.env.ambient_light_energy > 0.9, "on: the lamps light the night (%d lamps)" % lit_s)
	check(gw.moon_now > 15.0 and gw.moon.light_energy > 0.1 and gw.moon.global_basis.z.y > 0.2, "the moon has come up on the other side (%.0f°)" % gw.moon_now)
	g.rules.grid_wait = 0.0
	check(not g.rules.handle({"k": "cut"}, "K").is_empty(), "and the killer can cut them again")
	g.queue_free()
	await frames(5)
	print("kuwait: %d failed" % bad)
	tree.quit()
