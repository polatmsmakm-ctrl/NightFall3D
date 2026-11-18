extends Node
## The road chase on screen: the escape car waiting past the gate, driving it with the road panel
## (metres to the last gate, the clock) and the speedometer, her car behind it, the last gate.
## Forward+ through lavapipe in check.yml.
var tree: SceneTree
var dir := ""

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])
	print("shot ", name)

func _ready() -> void:
	tree = get_tree()
	dir = OS.get_environment("NF_SHOTS")
	if dir == "": dir = "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(10)
	m._start({"map": "forest", "me": "P", "offline": true, "players": [
		{"name": "P", "role": "survivor", "char": "survivor6", "slot": 0},
		{"name": "سارة", "role": "survivor", "char": "survivor5", "slot": 1},
		{"name": "القاتلة", "role": "killer", "char": "killer", "slot": 2}]})
	for i in 900:
		await tree.process_frame
		if m.world.ready_done and not m.world.esc_cars.is_empty(): break
	await frames(30)
	var w: NightWorld = m.world
	for g in m.rules.gens: g.done = true
	await frames(30)
	var ec: NFCar = w.esc_cars[0]
	var b := Basis(Vector3.UP, float(w.gate_points[0][1]))
	m.body.position = ec.global_position + b * Vector3(2.6, 0.3, 4.0)
	m.yaw = float(w.gate_points[0][1]) + 0.5
	await frames(30)
	await shot("21_car_waits")
	m.body.position = ec.global_position + b * Vector3(2.2, 0.3, 0.0)
	await frames(8)
	print("ctx by the car: ", m.ctx.get("interact", {}).get("kind", "-"))
	m._press("interact", 5)
	await frames(4)
	for e in m.rules.handle({"k": "board", "i": 0}, "سارة"): m._on_event(e)
	m.stick_vec = Vector2(0, -1)
	await frames(200)
	# her car close behind, lights on
	var kr = m.remotes["القاتلة"] # as if her phone said she is at the wheel, just behind
	kr.anim = "drive"
	kr.pos = ec.global_position - ec.forward() * 9.0 + b * Vector3(1.5, 0, 0)
	kr.yaw = ec.rotation.y
	await frames(10)
	await shot("21_driving")
	m.stick_vec = Vector2.ZERO
	# the last stretch: the gate ahead
	var out: Vector3 = (w.road_end(0) - w.gate_points[0][0]).normalized()
	ec.global_position = w.road_end(0) - out * 45.0 + Vector3(0, 0.1, 0)
	ec.rotation.y = float(w.gate_points[0][1]) + PI
	m.yaw = ec.rotation.y + PI
	kr.anim = "idle"
	kr.pos = w.gate_points[1][0]
	await frames(30)
	await shot("21_last_gate")
	print("shots done")
	tree.quit()
