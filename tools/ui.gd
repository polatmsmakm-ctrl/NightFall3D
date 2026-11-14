extends Node
## Headless checks for the new interface: button layout + editor file, quick signals,
## character select, the loading screen and the results stage.

var tree: SceneTree

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

func ids(list: Array) -> Array:
	var out := []
	for b in list: out.append(str(b[3]))
	out.sort()
	return out

func _ready() -> void:
	tree = get_tree()
	# ---------- button layout ----------
	DirAccess.remove_absolute(ProjectSettings.globalize_path(NFControls.PATH))
	NFControls.forget()
	var d := NFControls.layout("survivor")
	print("layout survivor: ", d.size(), " buttons, interact r=", d.interact.r, " fx=", snappedf(d.interact.fx, 0.001))
	var rect := Rect2(0, 0, 1280, 720)
	print("default interact centre on 1280x720 = ", NFControls.center_of(d.interact, rect), " (was 1028, 632)")
	d.interact.fx = 0.5; d.interact.fy = 0.5; d.interact.r = 70.0
	NFControls.save("survivor", d)
	NFControls.forget()
	var d2 := NFControls.layout("survivor")
	print("saved + reloaded: fx=", d2.interact.fx, " r=", d2.interact.r, " killer untouched=", NFControls.layout("killer").attack.r)
	var d3 := NFControls.reset("survivor")
	print("after reset: fx=", snappedf(d3.interact.fx, 0.001), " r=", d3.interact.r)
	# ---------- survivor HUD ----------
	var m = await boot("survivor", "survivor2", [["D", "survivor", "survivor4"], ["K", "killer", "killer"]])
	print("survivor buttons: ", ids(m._buttons()))
	var found := {}
	for b in m._buttons(): found[str(b[3])] = str(b[5])
	print("icons: ", found)
	m.body.position = m.world.gen_points[0] + Vector3(1.4, 0.3, 0.8)
	m.body.velocity = Vector3.ZERO
	for i in 8: await tree.physics_frame
	var ctxb := {}
	for b in m._buttons(): ctxb[str(b[3])] = [str(b[2]), str(b[5]), bool(b[4])]
	print("interact at a generator: ", ctxb.get("interact"))
	# quick signals
	print("panel closed: ", m._sig_buttons().size())
	m._press("sig", 3)
	var sb: Array = m._sig_buttons()
	print("panel open: ", sb.size(), " first rect=", sb[0][0] if sb.size() > 0 else "-")
	m._send_sig(1)
	print("sent: open=", m.sig_open, " live=", m.sigs.size(), " k=", m.sigs[0].k, " from=", m.sigs[0].n)
	m._add_sig("D", 0, Vector3(10, 0, 10))
	m._add_sig("D", 2, Vector3(12, 0, 10))
	print("one message per player: ", m.sigs.size(), " D now says k=", m.sigs[1].k)
	m.sigs[0].t = 0.05
	await frames(20)
	print("after it expires: ", m.sigs.size())
	# team bar data (what the portraits are drawn from), and the killer must never get positions
	m.rules.s["D"].hp = "hooked"; m.rules.s["D"].hook_i = 0; m.rules.s["D"].t = 21.0; m.rules.s["D"].hooks = 1
	await frames(4)
	print("team: ", m.rules.s.keys(), " D=", m.rules.hp("D"), " t=", int(m.rules.s["D"].t), " icon=", m.STATE_ICON.get("hooked"))
	# ---------- loading screen ----------
	var ld := NFLoading.new()
	ld.setup("fareej")
	tree.root.add_child.call_deferred(ld)
	await frames(2)
	ld.progress(0.4)
	await frames(3)
	print("loading: map=", ld.map_id, " tip len=", ld.tip.length(), " f=", ld.f, " busy=", ld.busy())
	ld.finish()
	await frames(40)
	print("loading freed: ", not is_instance_valid(ld))
	# ---------- results ----------
	var xp0: int = Net.xp
	var esc0: int = Net.escapes
	m.rules.score["P"] = 275.0
	m.rules.s["P"].hp = "escaped"
	m.rules.s["D"].hp = "dead"
	m.rules.over = true
	await frames(20)
	print("results up=", m.results_shown(), " rows=", m.results.rows.size(), " xp ", xp0, "->", Net.xp, " escapes ", esc0, "->", Net.escapes)
	var line := []
	for r in m.results.rows: line.append("%s:%s:%d" % [str(r.name), str(r.state), roundi(float(r.score))])
	print("row order (points first): ", line)
	print("xp bar animating: ", snappedf(m.results.xp_show, 1.0), " -> ", m.results.xp_to)
	await frames(120)
	print("xp bar arrived: ", snappedf(m.results.xp_show, 1.0))
	m.queue_free()
	await frames(10)
	# ---------- killer HUD ----------
	var k = await boot("killer", "killer", [["D", "survivor", "survivor4"]])
	print("killer buttons: ", ids(k._buttons()), " (no sig button for the killer)")
	k.rules.s["D"].hp = "down"
	k.rules.s["D"].t = Rules.BLEED_TIME # otherwise the bleed-out timer is 0 and they die at once
	k.body.position = k.remotes["D"].node.position + Vector3(0, 0.3, 1.4)
	k.body.velocity = Vector3.ZERO
	for i in 8: await tree.physics_frame
	var kb := {}
	for b in k._buttons(): kb[str(b[3])] = [str(b[2]), str(b[5])]
	print("killer interact over a downed survivor: ", kb.get("interact"))
	# ---------- character select ----------
	var mn = k.menu
	mn.visible = true
	mn.chars_from = "offline"
	mn.off_char = "survivor1"
	mn.open("chars")
	await frames(5)
	print("chars page list=", mn._char_list().size(), " (killer included in trial) current=", mn._my_char())
	mn._step(1)
	await frames(5)
	print("after one step: ", mn._my_char(), " card visible=", mn.card.visible, " swipe pad=", mn.char_pad.visible)
	mn._step(-1)
	await frames(5)
	print("back: ", mn._my_char())
	print("level progress: xp=", Net.xp, " level=", Net.level(), " bar=", snappedf(Net.level_progress(), 0.01))
	tree.quit()
