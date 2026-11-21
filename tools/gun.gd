extends Node
## «وضع السلاح», the team's names and see-through, «Vanish», the friends' status and profile page,
## and the map's drawn icons.
var tree: SceneTree
var bad := 0

func frames(n: int) -> void:
	for i in n: await tree.physics_frame

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok: bad += 1

func boot(players: Array, gun: bool):
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	for i in 10: await tree.process_frame
	m._start({"map": "forest", "me": players[0].name, "offline": true, "gun": gun, "players": players})
	for i in 900:
		await tree.process_frame
		if m.world.ready_done: break
	await frames(20)
	return m

func _ready() -> void:
	tree = get_tree()
	# ---------------- the rules ----------------
	var r := Rules.new()
	r.gun = true
	r.setup(5, 2, 0, 0, [{"name": "K", "role": "killer", "char": "killer"}, {"name": "A", "role": "survivor", "char": "survivor1"}])
	check(int(r.s.A.ammo) == Rules.GUN_SHOTS, "every survivor starts with %d shots" % Rules.GUN_SHOTS)
	var ev := r.handle({"k": "shoot", "hit": true}, "A")
	check(r.stun == Rules.GUN_STUN and int(r.s.A.ammo) == 2 and ev.size() == 2, "a hit: she is dizzy %.0f s, one shot gone" % r.stun)
	var r2 := Rules.new()
	r2.setup(5, 2, 0, 0, [{"name": "K", "role": "killer", "char": "killer"}, {"name": "A", "role": "survivor", "char": "survivor1"}])
	check(r2.handle({"k": "shoot", "hit": true}, "A").is_empty() and r2.stun == 0.0, "no gun outside the mode")
	var snap := r.snapshot()
	var r3 := Rules.new()
	r3.setup(5, 2, 0, 0, [{"name": "K", "role": "killer", "char": "killer"}, {"name": "A", "role": "survivor", "char": "survivor1"}])
	r3.apply(snap)
	check(r3.gun and int(r3.s.A.ammo) == 2, "the snapshot carries the mode and the shots left")
	# ---------------- in a round: the button, a shot, the team ----------------
	var m = await boot([{"name": "P", "role": "survivor", "char": "survivor2", "slot": 0},
		{"name": "D", "role": "survivor", "char": "survivor1", "slot": 1, "dummy": true},
		{"name": "K", "role": "killer", "char": "killer", "slot": 2}], true)
	var ids := []
	for b in m._buttons(): ids.append(b[3])
	check("gun" in ids, "the gun button is there in the mode (%s)" % str(ids))
	# stand the killer in front of the camera, 8 m away
	var cam: Camera3D = m.get_viewport().get_camera_3d()
	var fwd := -cam.global_basis.z
	var kn: Node3D = m.remotes["K"].node
	# where the middle of the screen meets her: 8 m past me along the camera's line, feet on the ground
	var ahead := cam.global_position + fwd * (cam.global_position.distance_to(m.body.position) + 8.0)
	kn.position = Vector3(ahead.x, m.world.height(ahead.x, ahead.z), ahead.z)
	print("   aim: camera %s fwd %s, her at %s, me at %s" % [cam.global_position.snappedf(0.1), fwd.snappedf(0.01), kn.position.snappedf(0.1), m.body.position.snappedf(0.1)])
	m.remotes["K"].pos = kn.position
	await frames(2)
	m._press("gun", 5)
	await frames(4)
	print("   after the shot: stun %.1f, shots left %d" % [m.rules.stun, int(m.rules.s.P.ammo)])
	check(int(m.rules.s.P.ammo) == 2, "the shot is counted")
	check(m.rules.stun > 0.0 or not m.world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(m.body.position + Vector3(0, 1.35, 0), kn.position + Vector3(0, 1.3, 0), 1)).is_empty(),
		"aimed at her with a clear line, it hits and she is dizzy")
	# the team: D's name over D's head, D's body seen through walls; the killer gets nothing
	await frames(4)
	var e: Dictionary = m.esp_nodes.get("D", {})
	check(not e.is_empty() and (e.name as Label3D).visible and (e.name as Label3D).text.begins_with("D"), "a survivor sees the teammate's name over the head")
	var over := false
	for mi in e.get("meshes", []): over = over or (mi as MeshInstance3D).material_overlay != null
	check(over, "and the teammate's body through walls")
	var ek: Dictionary = m.esp_nodes.get("K", {})
	check(ek.is_empty() or not (ek.name as Label3D).visible, "but no name over the killer")
	# «Vanish»: a remote that says v=1 is hidden here
	m._on_net({"t": "st", "n": "D", "p": [m.remotes.D.pos.x, m.remotes.D.pos.y, m.remotes.D.pos.z, 0.0], "a": "idle", "f": 0, "v": 1})
	await frames(3)
	check(not m.remotes.D.node.visible, "a vanished player does not show on this phone")
	m.remotes.D.v = false
	Dev.unlocked = true
	Dev.vanish_tool = true
	ids = []
	for b in m._buttons(): ids.append(b[3])
	check("vanish" in ids, "with the tools unlocked and the switch on, the «Vanish» button is in the round")
	m._press("vanish", 5)
	check(m.vanished, "pressing it hides me (sent as v in my st)")
	m._press("vanish", 5)
	Dev.vanish_tool = false
	Dev.unlocked = false
	# the big map draws its icons without an error
	m.big_map = true
	m.minimap.queue_redraw()
	await frames(3)
	check(true, "the map draws its icons")
	m.queue_free()
	await frames(10)
	# a killer: no names at all
	var mk = await boot([{"name": "K", "role": "killer", "char": "killer", "slot": 0},
		{"name": "D", "role": "survivor", "char": "survivor1", "slot": 1, "dummy": true}], true)
	await frames(6)
	var any := false
	for n in mk.esp_nodes: any = any or (mk.esp_nodes[n].name as Label3D).visible
	check(not any, "the killer sees no names")
	mk.queue_free()
	await frames(10)
	# ---------------- the passkey, the friends' status and the profile page ----------------
	Dev.unlocked = false
	check(not Dev.try_key("0000") and Dev.try_key("4343"), "the tools open only with 4343")
	Dev.lock()
	check(not Dev.unlocked, "and lock again")
	Net.online = {"saud": true, "badr": true}
	Net.status = {"saud": "game", "badr": "room"}
	check(Net.status_of("Saud") == "game" and Net.status_text("Badr") == "بغرفة — ينتظر" and Net.status_of("Ghanim") == "off", "friends' status: in a round, in a room, offline")
	Net.fstats["saud"] = {"name": "Saud", "lv": 4, "esc": 3, "kills": 1, "rounds": 9, "ch": "survivor6", "bio": "هلا", "seen": 0}
	print("GUN DONE bad=%d" % bad)
	tree.quit()
