extends Node
func walk(m, from: Vector3, yaw: float, frames: int) -> Vector3:
	m.body.position = from; m.body.velocity = Vector3.ZERO; m.yaw = yaw
	m.stick_vec = Vector2(0, -1)
	for i in frames: await get_tree().physics_frame
	m.stick_vec = Vector2.ZERO
	return m.body.position
func _ready():
	var tree := get_tree()
	for map in ["forest", "village"]:
		var m = load("res://scenes/main.tscn").instantiate()
		tree.root.add_child.call_deferred(m)
		for i in 10: await tree.process_frame
		m._start({"map": map, "me": "P", "offline": true, "players": [{"name": "P", "role": "survivor", "char": "survivor2", "slot": 0}]})
		for i in 300:
			await tree.process_frame
			if m.world.ready_done: break
		var w = m.world
		var W: float = NightWorld.WALL
		var y := 1.0
		var p: Vector3 = await walk(m, Vector3(0, w.height(0, -W + 5) + 0.5, -W + 5), 0.0, 240)
		print(map, " closed door: z=", snappedf(p.z, 0.01), " (wall at ", -W, ") escaped=", m.rules.hp)
		p = await walk(m, Vector3(40, w.height(40, -W + 5) + 0.5, -W + 5), 0.0, 240)
		print(map, " north wall: z=", snappedf(p.z, 0.01))
		p = await walk(m, Vector3(W - 5, w.height(W - 5, 20) + 0.5, 20), -PI / 2.0, 240)
		print(map, " east wall: x=", snappedf(p.x, 0.01))
		p = await walk(m, Vector3(-30, w.height(-30, W - 5) + 0.5, W - 5), PI, 240)
		print(map, " south wall: z=", snappedf(p.z, 0.01))
		p = await walk(m, Vector3(-W + 5, w.height(-W + 5, -70) + 0.5, -70), PI / 2.0, 240)
		print(map, " west wall: x=", snappedf(p.x, 0.01))
		p = await walk(m, Vector3(W - 6, w.height(W - 6, W - 6) + 0.5, W - 6), -PI * 0.75, 240)
		print(map, " corner: ", snappedf(p.x, 0.01), ",", snappedf(p.z, 0.01))
		for g in 5: m.rules.gens[g].p = 0.999; m.rules.gens[g].reps["P"] = true
		for i in 240: await tree.physics_frame
		print(map, " powered=", m.rules.powered, " gates open=", m.rules.gates[0].open, m.rules.gates[1].open, " door x=", snappedf(w.gate_nodes[0].doors[0].position.x, 0.01))
		p = await walk(m, Vector3(0, w.height(0, W - 5) + 0.5, W - 5), PI, 240)
		for i in 5: await tree.process_frame
		print(map, " through south gate: z=", snappedf(p.z, 0.01), " hp=", m.rules.hp, " over=", m.rules.over, " results=", m.results.visible)
		m.queue_free()
		await tree.process_frame
	tree.quit()
