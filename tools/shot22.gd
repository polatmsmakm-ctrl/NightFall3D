extends Node
## The graphics pass on screen: the rain night (streaks, wet ground, puddles, a lightning flash),
## blood under a hook, oil by a generator, a campfire's flames and smoke, each map's colour grade.
## Forward+ through lavapipe in check.yml.
var tree: SceneTree
var dir := ""

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])
	print("shot ", name)

func boot(map: String, theme: String):
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(10)
	m._start({"map": map, "me": "P", "offline": true, "theme": theme, "players": [
		{"name": "P", "role": "survivor", "char": "survivor6", "slot": 0},
		{"name": "القاتلة", "role": "killer", "char": "killer", "slot": 1}]})
	for i in 900:
		await tree.process_frame
		if m.world.ready_done: break
	await frames(40)
	return m

func look_at_spot(m, at: Vector3, back := 5.0) -> void:
	m.body.position = at + Vector3(0.0, 0.3, back)
	m.yaw = 0.0
	m.pitch = -0.32
	await frames(20)

func _ready() -> void:
	tree = get_tree()
	dir = OS.get_environment("NF_SHOTS")
	if dir == "": dir = "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	Gfx.shadows = 2; Gfx.effects = 2; Gfx.scale_idx = 2; Gfx.aa = 1
	Gfx.apply()
	var m = await boot("forest", "rain")
	var w: NightWorld = m.world
	print("rain: decals %d, rain node %s, fires %d" % [w.decals, w.rain != null, w.fire_fx])
	await look_at_spot(m, w.hook_points[0] + Vector3(0, 0, 0.9))
	await shot("22_rain_hook")
	w._bolt = 1.0
	await frames(2)
	await shot("22_rain_lightning")
	if not w.campfire_points.is_empty():
		await look_at_spot(m, w.campfire_points[0], 4.0)
		await shot("22_campfire")
	m.queue_free()
	await frames(20)
	m = await boot("fareej", "normal")
	await look_at_spot(m, m.world.gen_points[0], 5.0)
	await shot("22_fareej_grade_oil")
	m.queue_free()
	await frames(20)
	m = await boot("garage", "normal")
	await look_at_spot(m, m.world.gen_points[0], 6.0)
	await shot("22_garage_grade")
	m.queue_free()
	await frames(10)
	print("SHOT22 DONE")
	tree.quit()
