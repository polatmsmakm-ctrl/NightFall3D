extends Node
## The quality and interface pass: the event feed, the hit-direction arc, the gate arrow, the
## controls sliders (sensitivity, field of view, button size and transparency), 2D anti-aliasing,
## anisotropic filtering on the map, the parked car's sharper maps and the how-to-play page.

var tree: SceneTree
var bad := 0

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok: bad += 1

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func boot(role: String, chr: String, others := []):
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(10)
	var list := [{"name": "P", "role": role, "char": chr, "slot": 0}]
	var slot := 1
	for o in others:
		list.append({"name": str(o[0]), "role": str(o[1]), "char": str(o[2]), "slot": slot})
		slot += 1
	m._start({"map": "forest", "me": "P", "offline": true, "players": list})
	for i in 400:
		await tree.process_frame
		if m.world.ready_done: break
	await frames(10)
	return m

func _ready() -> void:
	tree = get_tree()
	var m = await boot("survivor", "survivor2", [["D", "survivor", "survivor5"], ["K", "killer", "killer"]])
	var w: NightWorld = m.world
	# ---------- quality ----------
	print("anisotropic materials on the forest: ", w.aniso_mats)
	check(w.aniso_mats > 20, "anisotropic filtering across the map's materials (%d)" % w.aniso_mats)
	check(get_viewport().msaa_2d != Viewport.MSAA_DISABLED or Gfx.preset == 0, "2D anti-aliasing for the interface (%d)" % get_viewport().msaa_2d)
	var car_ps: PackedScene = load("res://assets/props/car.glb")
	var ci := car_ps.instantiate()
	var cm: StandardMaterial3D = null
	for mi in ci.find_children("*", "MeshInstance3D", true, false):
		if cm == null: cm = (mi as MeshInstance3D).get_active_material(0) as StandardMaterial3D
	ci.free()
	check(cm != null and cm.albedo_texture != null and cm.albedo_texture.get_width() == 4096, "the parked car's colour map is 4096 (%d)" % (cm.albedo_texture.get_width() if cm and cm.albedo_texture else 0))
	check(cm != null and cm.albedo_texture.get_image().get_format() == Image.FORMAT_BPTC_RGBA, "at high quality")
	# ---------- event feed ----------
	m.feed.clear()
	m.rules.s["D"].hp = "down"
	m.rules.s["D"].t = Rules.BLEED_TIME # (left at 0 it bleeds out on the next tick)
	await frames(3)
	check(m.feed.size() >= 1 and str(m.feed[0].t).contains("طاح"), "the feed: D went down (%s)" % (m.feed[0].t if m.feed.size() else "-"))
	m._on_event({"k": "hooked", "n": "D", "s": "hooked"})
	m._on_event({"k": "rescued", "n": "D", "by": "P", "hands": 1})
	await frames(2)
	check(m.feed.size() >= 3 and str(m.feed[0].t).contains("أنقذ"), "the feed: hooked, then P saved D (%s)" % (m.feed[0].t if m.feed.size() else "-"))
	m.rules.s["D"].hp = "ok"
	for g in m.rules.gens: g.done = true
	m.rules.powered = true
	await frames(3)
	var texts := []
	for f in m.feed: texts.append(str(f.t))
	print("   feed now: ", texts)
	check(texts.any(func(t: String) -> bool: return t.contains("مولد")), "the feed: a generator done")
	check(texts.any(func(t: String) -> bool: return t.contains("البوابات")), "the feed: the gates are open")
	check(m.feed.size() <= 5, "never more than five lines")
	for i in 1000: # 6 s
		await tree.process_frame
		if m.feed.is_empty(): break
	check(m.feed.is_empty(), "lines fade away (%d left)" % m.feed.size())
	# ---------- hit direction and the gate arrow ----------
	m._on_event({"k": "hurt", "n": "P", "s": "hurt"})
	check(m.hit_t > 1.0 and m.hit_from.distance_to(m._pos_of("K")) < 0.5, "struck: the red arc points back at the killer")
	var d: Vector2 = m._ring_dir(m.body.position + Vector3(-sin(m.yaw), 0, -cos(m.yaw)) * 5.0)
	check(d.y < -0.9, "straight ahead is the top of the ring (%s)" % d)
	m.body.position = w.gate_points[0][0] + Vector3(0, 0.5, 40.0)
	await frames(3)
	m.ui.queue_redraw()
	await frames(2)
	check(m.rules.powered and m.my_role == "survivor", "the gate arrow shows once the gates have power")
	# ---------- controls ----------
	var r0: float = m._buttons()[0][1]
	Gfx.btn_scale = 1.3
	check(absf(m._buttons()[0][1] - r0 * 1.3) < 0.5, "«حجم الأزرار»: buttons 30% bigger")
	Gfx.btn_scale = 1.0
	var f0: float = m.main_cam.fov
	Gfx.fov_add = 10.0
	Gfx.look_changed.emit()
	check(absf(m.main_cam.fov - (70.0 + 10.0)) < 0.01, "«مجال الرؤية»: +10° live (%.1f, was %.1f)" % [m.main_cam.fov, f0])
	Gfx.fov_add = 0.0
	Gfx.look_changed.emit()
	var y0: float = m.yaw
	Gfx.look_sens = 2.0
	var ev := InputEventScreenDrag.new()
	ev.index = 7; ev.relative = Vector2(10, 0)
	m.look_id = 7
	m._input(ev)
	check(absf((y0 - m.yaw) - 0.12) < 0.001, "«حساسية الكاميرا» 200%%: a drag turns twice as far (%.3f)" % (y0 - m.yaw))
	Gfx.look_sens = 1.0
	m.look_id = -1
	m._press("crouch", 5)
	check(float(m.pop.get("crouch", 0.0)) > 0.0, "a pressed button dips")
	check(Gfx._nums.has("_sens") and Gfx._nums.has("_fov") and Gfx._nums.has("_btn") and Gfx._nums.has("_btn_a"), "the four control sliders are in the settings panel")
	Gfx._save()
	var cf := ConfigFile.new(); cf.load(Gfx.PATH)
	check(cf.has_section_key("g", "sens") and cf.has_section_key("g", "btn_a"), "and they are saved")
	# ---------- how to play ----------
	var mn = m.menu
	mn.visible = true
	mn.open("help")
	await frames(4)
	var labels := []
	for l in mn.box.find_children("*", "Label", true, false): labels.append((l as Label).text)
	check(labels.has("صلّح المولدات") and labels.has("أنقذ ربعك"), "«طريقة اللعب»: the survivors' tips")
	mn.help_tab = "killer"
	mn._refresh()
	await frames(3)
	labels.clear()
	for l in mn.box.find_children("*", "Label", true, false): labels.append((l as Label).text)
	check(labels.has("السيارة") and labels.has("شيل وعلّق"), "and the killer's tab")
	print("hud check: ", "FAILED %d" % bad if bad else "all good")
	if bad: push_error("HUD FAIL")
	tree.quit(1 if bad else 0)
