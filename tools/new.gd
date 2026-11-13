extends Node
func _ready():
	var tree := get_tree()
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	for i in 10: await tree.process_frame
	print("lobby scene=", m.lobby_scene != null, " rigs=", m.lobby_scene.find_children("*", "Skeleton3D", true, false).size())
	var t0 := Time.get_ticks_msec()
	m._start({"map": "fareej", "me": "P", "offline": true, "players": [
		{"name": "P", "role": "survivor", "char": "survivor2", "slot": 0}, {"name": "D", "role": "survivor", "char": "survivor4", "slot": 1, "dummy": true}, {"name": "K", "role": "killer", "char": "killer", "slot": 2}]})
	for i in 400:
		await tree.process_frame
		if m.world.ready_done: break
	var w = m.world
	print("fareej: start ms=", Time.get_ticks_msec() - t0, " houses=", w.buildings.size(), " trees=", w.tree_plan.size(), " gens=", w.gen_points.size(), " hooks=", w.hook_points.size(), " hatches=", w.hatch_points.size(), " lights=", w.find_children("*", "OmniLight3D", true, false).size(), " lobby freed=", m.lobby_scene == null)
	var w2 := NightWorld.new(); w2.configure("fareej", 5); var w3 := NightWorld.new(); w3.configure("fareej", 5); var w4 := NightWorld.new(); w4.configure("fareej", 6)
	print("seeded: same seed same gens=", w2.gen_points == w3.gen_points, " other seed differs=", w2.gen_points != w4.gen_points)
	# walk into a house through gate + door
	var b: Array = w.buildings[0]
	var rot := Basis(Vector3.UP, b[2])
	m.sprint = true
	m.body.position = Vector3(b[0], 0.4, b[1]) + rot * Vector3(0, 0, 10.0); m.yaw = b[2]; m.stick_vec = Vector2(0, -1)
	for i in 160: await tree.physics_frame
	m.stick_vec = Vector2.ZERO
	var loc: Vector3 = rot.inverse() * (m.body.position - Vector3(b[0], 0, b[1]))
	print("house entry: local z=", snappedf(loc.z, 0.01), " (door at 4.0, yard gate at 7.0) surface=", w.surface_at(m.body.position), " creak cooldowns=", m.door_cool.size())
	# flashlight
	m._press("light", 5)
	for i in 30: await tree.physics_frame
	print("flashlight on=", m.flash_light.visible, " battery=", snappedf(m.battery, 0.1))
	m.battery = 0.1
	for i in 30: await tree.physics_frame
	print("battery dead -> on=", m.light_on)
	# market blackout
	var k = m.remotes["K"]
	k.pos = w.market.pos + Vector3(0, 0.2, 0); k.node.position = k.pos
	for i in 120: await tree.process_frame
	print("killer in market: dark=", w.market_dark, " lamp energy=", w.market_lights[0][0].light_energy)
	k.pos = Vector3(-90, 0, -90); k.node.position = k.pos
	for i in 120: await tree.process_frame
	print("killer left: dark=", w.market_dark, " lamp energy=", w.market_lights[0][0].light_energy)
	# hatch: the dummy dies -> one survivor left
	m.rules.s["D"].hp = "dead"
	for i in 20: await tree.physics_frame
	print("hatch index=", m.rules.hatch, " node visible=", w.hatch_nodes[m.rules.hatch].visible if m.rules.hatch >= 0 else false)
	m.body.position = w.hatch_points[m.rules.hatch] + Vector3(0.5, 0.3, 0)
	for i in 20: await tree.physics_frame
	print("escaped, watching=", m.spectating, " over=", m.rules.over, " banner=", snappedf(m.escape_banner, 0.1))
	for i in 300: await tree.physics_frame
	for i in 5: await tree.process_frame
	print("after hatch: ", m.rules.hp("P"), " over=", m.rules.over, " score=", m.rules.score, " xp=", Net.xp, " level=", Net.level())
	tree.quit()
