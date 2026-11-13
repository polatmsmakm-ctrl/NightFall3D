extends Node
func _ready():
	var tree := get_tree()
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	for i in 10: await tree.process_frame
	var online := OS.get_environment("NF_URL") != ""
	if not online:
		m._start({"map": "village", "me": "P", "offline": true, "players": [{"name": "P", "role": "survivor", "char": "survivor2", "slot": 0}]})
	else:
		Net.configure("Tester", "")
		for i in 200:
			await tree.process_frame
			if Net.state == "online": break
		Net.send({"t": "create", "map": "forest"})
		for i in 100:
			await tree.process_frame
			if Net.in_room(): break
		var f := FileAccess.open("/tmp/code.txt", FileAccess.WRITE); f.store_string(str(Net.room.code)); f.close()
		for i in 600:
			await tree.process_frame
			if Net.room.get("players", []).size() >= 2: break
		print("players=", Net.room.players.size())
		Net.send({"t": "start"})
	for i in 300:
		await tree.process_frame
		if m.started and m.world.ready_done: break
	var w = m.world
	print("started=", m.started, " role=", m.my_role, " host=", m.is_host, " gens=", w.gen_points.size(), " gates=", w.gate_points.size())
	m.stick_vec = Vector2(0, -1)
	var p0: Vector3 = m.body.position
	for i in 120: await tree.physics_frame
	print("moved ", snappedf(p0.distance_to(m.body.position), 0.01), " anim=", m.rig.current, " speed_scale=", snappedf(m.rig.player.speed_scale, 0.01))
	m.stick_vec = Vector2.ZERO
	if not online:
		for g in 5:
			m.body.position = w.gen_points[g] + Vector3(1.6, 0.3, 0.9)
			m.body.velocity = Vector3.ZERO
			for i in 5: await tree.physics_frame
			m._start_work()
			if g == 0:
				for i in 10: await tree.physics_frame
				print("working=", m.work_kind, " near=", m.near_gen, " anim=", m.rig.current, " stuck_in_gen=", m.body.position.distance_to(w.gen_points[g]))
				m.skill = {"t": 0.6, "zone": 0.5}; m._skill_tap()
				m.skill = {"t": 0.1, "zone": 0.5}; m._skill_tap()
				print("after skills p=", m.rules.gens[0].p, " boom=", m.boom_t)
			m.rules.gens[g].p = 0.995
			for i in 30: await tree.physics_frame
		print("done=", m.rules.done_count(), " powered=", m.rules.powered, " light0=", w.gen_nodes[0].light.light_energy)
		m.body.position = w.gate_points[0][0] + Vector3(0, 0.3, 2.8)
		for i in 5: await tree.physics_frame
		m._start_work()
		print("gate work=", m.work_kind)
		m.rules.gates[0].p = 0.99
		for i in 30: await tree.physics_frame
		print("gate open=", m.rules.gates[0].open, " door visible=", w.gate_nodes[0].door.visible)
		m.stick_vec = Vector2(0, -1); m.yaw = 0.0
		for i in 120: await tree.physics_frame
		for i in 5: await tree.process_frame
		print("state=", m.rules.hp, " over=", m.rules.over, " results=", m.results.visible)
	else:
		for i in 90: await tree.process_frame
		print("bot rep -> gen2 p=", m.rules.gens[2].p, " reps=", m.rules.gens[2].reps)
		var bot = m.remotes["Bot"]
		m.body.position = bot.node.position + Vector3(0, 0, -1.5)
		m.rig.rotation.y = 0.0
		for i in 3: await tree.physics_frame
		m._do_action("attack")
		for i in 60: await tree.physics_frame
		print("after hit hp=", m.rules.hp, " reps=", m.rules.gens[2].reps)
		for i in 150: await tree.physics_frame
		m._do_action("attack")
		for i in 60: await tree.physics_frame
		for i in 5: await tree.process_frame
		print("after 2nd hp=", m.rules.hp, " over=", m.rules.over, " results=", m.results.visible)
	tree.quit()
