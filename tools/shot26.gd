extends Node
## «وضع القنّاص»: the tower from down the road, her view lying on the roof, through the scope at x4
## and x8; and the car's headlights on a dark night (the power cut).
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
	Gfx.shadows = 1; Gfx.effects = 1; Gfx.scale_idx = 2; Gfx.aa = 1
	Gfx.apply()
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(10)
	m._start({"map": "kuwait", "me": "K", "offline": true, "seed": 5150, "theme": "normal", "sniper": true, "players": [
		{"name": "P", "role": "survivor", "char": "survivor9", "slot": 0},
		{"name": "K", "role": "killer", "char": "killer", "slot": 1}]})
	for i in 1500:
		await tree.process_frame
		if m.world.ready_done: break
	await frames(60)
	m.rules.ev_at = 99999.0
	var w = m.world
	var cam := Camera3D.new()
	m.add_child(cam)
	cam.fov = 62.0
	cam.global_position = Vector3(10, 5, 62)
	cam.look_at(Vector3(0, 7, 100))
	cam.current = true
	await frames(30)
	await shot("26_tower")
	cam.global_position = Vector3(18, 3, 86)
	cam.look_at(Vector3(4, 5, 95))
	await frames(20)
	await shot("26_stairs")
	cam.current = false
	m.main_cam.current = true
	# her view, lying on the roof with the rifle, the survivor down the road
	var r = m.remotes["P"]
	r.pos = Vector3(-8, 0.05, 30)
	r.node.position = r.pos
	m.body.global_position = Vector3(-2.0, NightWorld.SN_H + 0.3, NightWorld.SN_FACE + 0.9)
	m._snipe_start()
	var to: Vector3 = r.pos + Vector3(0, 1.2, 0)
	await frames(30)
	var d: Vector3 = (to - m.main_cam.global_position).normalized()
	m.yaw = atan2(-d.x, -d.z)
	m.pitch = asin(d.y)
	await frames(30)
	await shot("26_prone")
	m._press("power", -1)
	await frames(20)
	await shot("26_scope_x4")
	m._press("power", -1)
	await frames(20)
	await shot("26_scope_x8")
	m._press("power", -1)
	m._snipe_stop()
	# the car's headlights with the power cut
	for e in m.rules.handle({"k": "cut"}, "K"): m._on_event(e)
	m.body.global_position = m.car.global_position + Vector3(2.5, 0.3, 0)
	await frames(10)
	m._enter_car()
	m._car_view(false)
	await frames(150)
	await shot("26_car_lights")
	var c2 := Camera3D.new()
	m.add_child(c2)
	c2.fov = 60.0
	var cf: Vector3 = m.car.global_transform.basis.z
	c2.global_position = m.car.global_position + cf * 16.0 + Vector3(3, 2.2, 0)
	c2.look_at(m.car.global_position + Vector3(0, 1, 0))
	c2.current = true
	await frames(20)
	await shot("26_car_lights_front")
	print("shot26 done")
	tree.quit()
