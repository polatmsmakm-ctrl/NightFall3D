extends Node
func _ready():
	var tree := get_tree()
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	for i in 10: await tree.process_frame
	m._start({"map": "forest", "me": "P", "offline": true, "players": [
		{"name": "P", "role": "survivor", "char": "survivor2", "slot": 0}, {"name": "K", "role": "killer", "char": "killer", "slot": 1}]})
	for i in 300:
		await tree.process_frame
		if m.world.ready_done: break
	var w = m.world
	var k = m.remotes["K"]
	print("size=", NightWorld.SIZE, " trees=", w.tree_plan.size(), " buildings=", w.buildings.size(), " ambient playing=", m.amb.playing)
	var b: Array = w.buildings[0]
	print("surface: inside building=", w.surface_at(Vector3(b[0], 0, b[1])), " yard=", w.surface_at(Vector3(b[0] + 5.5, 0, b[1] + 5.5)), " market=", w.surface_at(w.market.pos), " forest=", w.surface_at(Vector3(-20, 0, -70)))
	for d in [40.0, 20.0, 12.0, 5.0]:
		k.pos = m.body.position + Vector3(d, 0, 0); k.node.position = k.pos
		for i in 90: await tree.process_frame
		print("killer at ", d, "m: danger=", snappedf(m.danger, 0.01), " heart=", m.heart.playing, " ", snappedf(m.heart.volume_db, 0.1), "dB breath=", m.breath.playing, " chase=", m.chase_music.playing, " amb=", snappedf(m.amb.volume_db, 0.1))
	m.sprint = true; m.stick_vec = Vector2(0, -1)
	for i in 40: await tree.physics_frame
	print("my steps playing=", m.my_steps.playing, " stream=", m.my_steps.stream.resource_path.get_file(), " pitch=", m.my_steps.pitch_scale)
	m.stick_vec = Vector2.ZERO
	m.rules.gens[3].p = 0.9
	for i in 20: await tree.process_frame
	print("gen 3 at 90%: run sound=", m.gen_audio[3].run.playing, " hum=", m.gen_audio[3].hum.playing, " blink=", w.gen_nodes[3].blink)
	tree.quit()
