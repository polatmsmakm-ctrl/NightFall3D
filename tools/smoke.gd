extends Node
var tree: SceneTree
func frames(n: int) -> void:
	for i in n: await tree.physics_frame
func boot(role: String, chr: String):
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	for i in 10: await tree.process_frame
	m._start({"map": "forest", "me": "P", "offline": true, "players": [
		{"name": "P", "role": role, "char": chr, "slot": 0}, {"name": "D", "role": "survivor", "char": "survivor4", "slot": 1, "dummy": true}]})
	for i in 300:
		await tree.process_frame
		if m.world.ready_done: break
	return m
func put(m, p: Vector3) -> void:
	m.body.position = p + Vector3(0, 0.3, 0); m.body.velocity = Vector3.ZERO
	await frames(4)
func _ready():
	tree = get_tree()
	var m = await boot("survivor", "survivor2")
	var w = m.world
	print("S props: hooks=", w.hook_points.size(), " lockers=", w.locker_points.size(), " pallets=", w.pallet_points.size(), " windows=", w.window_points.size(), " dummy=", m.rules.hp("D"))
	# walk vs sprint
	m.stick_vec = Vector2(0, -1); await frames(60)
	var v1: float = Vector2(m.body.velocity.x, m.body.velocity.z).length()
	m._press("sprint", 9); await frames(60)
	print("S walk=", snappedf(v1, 0.01), " sprint=", snappedf(Vector2(m.body.velocity.x, m.body.velocity.z).length(), 0.01), " anim=", m.rig.current)
	m.stick_vec = Vector2.ZERO
	# heal the dummy
	await put(m, m.remotes["D"].node.position + Vector3(1.2, 0, 0))
	print("S ctx near dummy: ", m.ctx.keys())
	m._press("heal", 5); await frames(10)
	m.rules.s["D"].heal = 0.99; await frames(20)
	print("S healed dummy -> ", m.rules.hp("D"), " hold=", m.hold)
	# window vault
	var win: Array = w.window_points[0]
	await put(m, win[0] + win[1] * 1.2)
	m._press("vault", 5); await frames(80)
	print("S vault: side now=", snappedf((m.body.position - win[0]).dot(win[1]), 0.01), " (was +1.2) vaulting=", not m.vault.is_empty())
	# locker
	var lk: Array = w.locker_points[0]
	await put(m, lk[0] + Basis(Vector3.UP, lk[1]) * Vector3(0, 0, 1.2))
	m._press("interact", 5); await frames(10)
	print("S in locker=", m.rules.s["P"].locker, " visible=", m.rig.visible, " ctx=", m.ctx.get("interact", {}).get("kind", ""))
	m._press("interact", 5); await frames(10)
	print("S out locker=", m.rules.s["P"].locker, " dist=", snappedf(m.body.position.distance_to(lk[0]), 0.01))
	# pallet drop then vault over it
	var pp: Array = w.pallet_points[0]
	var pn: Vector3 = Basis(Vector3.UP, pp[1]) * Vector3(0, 0, 1)
	await put(m, pp[0] - pn * 1.2)
	print("S pallet ctx=", m.ctx.get("interact", {}).get("kind", ""))
	m._press("interact", 5); await frames(10)
	print("S pallet state=", m.rules.pallets[0], " node down visible=", w.pallet_nodes[0].down.visible, " vault ctx=", m.ctx.has("vault"))
	m.stick_vec = Vector2(0, -1); m.yaw = atan2(-pn.x, -pn.z) ; await frames(90); m.stick_vec = Vector2.ZERO
	print("S blocked by pallet: side=", snappedf((m.body.position - pp[0]).dot(pn), 0.01))
	m._press("vault", 5); await frames(80)
	print("S vaulted pallet: side=", snappedf((m.body.position - pp[0]).dot(pn), 0.01))
	# self heal with the item
	m.rules.s["P"].hp = "hurt"; await frames(5)
	m._press("item", 5); await frames(10)
	m.rules.s["P"].heal = 0.99; await frames(30)
	print("S self heal -> ", m.rules.hp("P"), " item left=", m.rules.s["P"].item)
	# repair + power + escape
	await put(m, w.gen_points[1] + Vector3(1.6, 0, 0.9))
	m._press("interact", 5); await frames(10)
	print("S repairing=", m.hold.get("kind", ""), " reps=", m.rules.gens[1].reps.keys())
	for g in 5: m.rules.gens[g].p = 0.999; m.rules.gens[g].reps["P"] = true
	await frames(60)
	print("S powered=", m.rules.powered, " hold cleared=", m.hold.is_empty())
	m.sprint = true
	var gz: float = NightWorld.WALL - 5.0
	await put(m, Vector3(0, w.height(0, gz), gz)); m.yaw = PI; m.stick_vec = Vector2(0, -1); await frames(120)
	print("S past gate, not out yet: ", m.rules.hp("P"), " z=", snappedf(m.body.position.z, 0.1), " floor=", m.body.is_on_floor())
	await frames(1000)
	print("S end of road z=", snappedf(m.body.position.z, 0.1), " banner=", snappedf(m.escape_banner, 0.1), " spectating=", m.spectating)
	await frames(300)
	for i in 5: await tree.process_frame
	print("S escaped=", m.rules.hp("P"), " over=", m.rules.over, " (dummy ", m.rules.hp("D"), ")")
	m.queue_free(); await tree.process_frame
	# ---------------- killer ----------------
	m = await boot("killer", "killer")
	w = m.world
	var d = m.remotes["D"]
	print("K first person: arm=", m.arm.spring_length, " rig visible=", m.rig.visible, " dummy=", m.rules.hp("D"))
	for hit in 2:
		await put(m, d.node.position + Vector3(0, 0, 1.6)); m.yaw = 0.0
		await frames(3)
		m._press("attack", 5); await frames(170)
		print("K hit ", hit + 1, " -> ", m.rules.hp("D"))
	await put(m, d.node.position + Vector3(0, 0, 1.5))
	print("K ctx=", m.ctx.get("interact", {}).get("kind", ""))
	m._press("interact", 5); await frames(10)
	print("K carrying=", m.rules.carrying, " dummy=", m.rules.hp("D"))
	await put(m, w.hook_points[0] + Vector3(1.5, 0, 0)); await frames(10)
	print("K at hook ctx=", m.ctx.get("interact", {}).get("kind", ""), " dummy follows dist=", snappedf(d.node.position.distance_to(m.body.position), 0.01))
	m._press("interact", 5); await frames(30)
	print("K hooked: ", m.rules.hp("D"), " hooks=", m.rules.s["D"].hooks, " t=", snappedf(m.rules.s["D"].t, 0.1), " at hook dist=", snappedf(d.node.position.distance_to(w.hook_points[0]), 0.01))
	m._press("power", 5); await frames(5)
	print("K power cd=", snappedf(m.rules.power_cd, 0.1), " boost=", snappedf(m.boost_t, 0.1))
	m.rules.pallets[2] = 1; await put(m, w.pallet_points[2][0] + Basis(Vector3.UP, w.pallet_points[2][1]) * Vector3(0, 0, 1.4))
	await frames(5)
	print("K pallet ctx=", m.ctx.get("interact", {}).get("kind", ""))
	m._press("interact", 5); await frames(140)
	print("K pallet after break=", m.rules.pallets[2])
	await put(m, w.locker_points[1][0] + Basis(Vector3.UP, w.locker_points[1][1]) * Vector3(0, 0, 1.3))
	print("K locker ctx=", m.ctx.get("interact", {}).get("kind", ""))
	m.rules.s["D"].t = 0.2; await frames(30)
	for i in 5: await tree.process_frame
	print("K hook timer out: ", m.rules.hp("D"), " over=", m.rules.over, " results=", m.results.visible)
	tree.quit()
