extends Node
func _ready():
	var tree := get_tree()
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	for i in 10: await tree.process_frame
	m._start({"map": "village", "me": "P", "offline": true, "players": [{"name": "P", "role": "survivor", "char": "survivor2", "slot": 0}]})
	for i in 300:
		await tree.process_frame
		if m.world.ready_done: break
	var w = m.world
	var mk: Dictionary = w.market
	var rot := Basis(Vector3.UP, mk.yaw)
	m.sprint = true
	for lx in [0.0, 3.0, -9.0, 9.0]:
		m.body.position = mk.pos + rot * Vector3(lx, 0.4, 9.0); m.body.velocity = Vector3.ZERO; m.yaw = mk.yaw
		m.stick_vec = Vector2(0, -1)
		for i in 150: await tree.physics_frame
		m.stick_vec = Vector2.ZERO
		var loc: Vector3 = rot.inverse() * (m.body.position - mk.pos)
		print("market x=", lx, " -> local z=", snappedf(loc.z, 0.01), " y=", snappedf(loc.y, 0.01), " (front glass at 5.0)")
	print("children=", w.get_child_count(), " lights=", w.find_children("*", "OmniLight3D", true, false).size())
	var r: Rules = m.rules
	r.s["P"].hp = "hooked"; r.s["P"].hook_i = 0; r.s["P"].t = 60.0
	for i in 5: await tree.physics_frame
	print("hooked ctx=", m.ctx.get("interact", {}).get("kind", ""), " rig y=", snappedf(m.rig.position.y, 0.01), " anim=", m.rig.current)
	for k in 3:
		m._press("interact", 5)
		for i in 5: await tree.physics_frame
	print("after 3 tries: hp=", r.hp("P"), " tries=", r.s["P"].tries, " t=", snappedf(r.s["P"].t, 0.1), " ctx=", m.ctx.get("interact", {}).get("kind", "none"))
	tree.quit()
