extends Node
func _ready():
	var tree := get_tree()
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	for i in 10: await tree.process_frame
	print("menu page=", m.menu.page, " rows=", m.menu.box.get_child_count())
	for pg in ["name", "main", "friends", "offline", "settings"]:
		m.menu.open(pg)
		await tree.process_frame
	if OS.get_environment("NF_URL") == "":
		m._start({"map": "village", "me": "P", "offline": true, "players": [{"name": "P", "role": "survivor", "char": "survivor2", "slot": 0}]})
	else:
		Net.configure("Tester", "")
		Net.add_friend("Bot")
		for i in 200:
			await tree.process_frame
			if Net.state == "online": break
		print("net=", Net.state)
		Net.send({"t": "create", "map": "forest"})
		for i in 100:
			await tree.process_frame
			if Net.in_room(): break
		print("room=", Net.room.get("code", "?"), " page=", m.menu.page)
		var f := FileAccess.open("/tmp/code.txt", FileAccess.WRITE); f.store_string(str(Net.room.code)); f.close()
		for i in 600:
			await tree.process_frame
			if Net.room.get("players", []).size() >= 2: break
		print("players=", Net.room.players.size(), " bot online=", Net.is_online("Bot"))
		m.menu.open("friends"); await tree.process_frame
		m.menu.open("lobby"); await tree.process_frame
		Net.send({"t": "start"})
	for i in 200:
		await tree.process_frame
		if m.started and m.world.ready_done: break
	var w = m.world
	print("started=", m.started, " role=", m.my_role, " map=", w.map_id, " buildings=", w.buildings.size(), " trees=", w.tree_plan.size(), " ready=", w.ready_done)
	for i in 60: await tree.physics_frame
	m.stick_vec = Vector2(0, -1)
	var p0: Vector3 = m.body.position
	for i in 120: await tree.physics_frame
	print("moved ", snappedf(p0.distance_to(m.body.position), 0.01), " anim=", m.rig.current, " floor=", m.body.is_on_floor())
	m.stick_vec = Vector2.ZERO
	m._do_action("attack" if m.my_role == "killer" else "crouch")
	for i in 10: await tree.physics_frame
	print("action anim=", m.rig.current)
	if m.remotes.has("Bot"):
		for i in 60: await tree.process_frame
		print("bot at ", m.remotes["Bot"].node.position, " anim=", m.remotes["Bot"].anim)
	tree.quit()
