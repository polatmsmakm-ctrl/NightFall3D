extends Node
var tree: SceneTree
func frames(n: int) -> void:
	for i in n: await tree.physics_frame
func _ready():
	tree = get_tree()
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	for i in 10: await tree.process_frame
	Net.configure("Tester", "")
	for i in 200:
		await tree.process_frame
		if Net.state == "online": break
	Net.send({"t": "create", "map": "forest"})
	for i in 100:
		await tree.process_frame
		if Net.in_room(): break
	var probe := NightWorld.new(); probe.configure("forest")
	var gp: Vector3 = probe.gen_points[2]
	var f := FileAccess.open("/tmp/code.txt", FileAccess.WRITE); f.store_string("%s %f %f %f" % [str(Net.room.code), gp.x + 1.5, gp.y, gp.z + 1.0]); f.close()
	for i in 600:
		await tree.process_frame
		if Net.room.get("players", []).size() >= 2: break
	Net.send({"t": "start"})
	for i in 300:
		await tree.process_frame
		if m.started and m.world.ready_done: break
	var w = m.world
	print("O started role=", m.my_role, " offline=", m.offline)
	await frames(120)
	print("O server gens: p2=", m.rules.gens[2].p, " bot=", m.rules.hp("Bot"), " bot at ", m.remotes["Bot"].node.position.snapped(Vector3.ONE * 0.1))
	var d = m.remotes["Bot"]
	for hit in 2:
		m.body.position = d.node.position + Vector3(0, 0.2, 1.6); m.body.velocity = Vector3.ZERO; m.yaw = 0.0
		await frames(8)
		m._press("attack", 5); await frames(170)
		print("O hit ", hit + 1, " -> ", m.rules.hp("Bot"))
	m.body.position = d.node.position + Vector3(0, 0.2, 1.5); await frames(10)
	m._press("interact", 5); await frames(20)
	print("O carrying=", m.rules.carrying)
	m.body.position = w.hook_points[0] + Vector3(1.5, 0.3, 0); await frames(15)
	m._press("interact", 5); await frames(30)
	print("O hooked: ", m.rules.hp("Bot"), " t=", m.rules.s["Bot"].t)
	m._press("power", 5); await frames(20)
	print("O power cd=", m.rules.power_cd, " boost=", snappedf(m.boost_t, 0.1))
	tree.quit()
