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

func boot(map: String, theme: String, gun := false):
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(10)
	m._start({"map": map, "me": "P", "offline": true, "theme": theme, "gun": gun, "players": [
		{"name": "P", "role": "survivor", "char": "survivor6", "slot": 0},
		{"name": "The Killer", "role": "killer", "char": "killer", "slot": 1}]})
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
	m = await boot("rubkhali", "normal")
	var an: Dictionary = m.world.animals[0]
	for x in m.world.animals:
		if x.kind == "horse" and not x.stand:
			an = x
			break
	await look_at_spot(m, an.node.position, 6.0)
	await shot("22_desert_horse")
	m.body.position = Vector3(0, m.world.height(0, 0) + 1.0, 0)
	m.pitch = 0.05
	await frames(20)
	await shot("22_desert_dunes")
	m.queue_free()
	await frames(20)
	m = await boot("forest", "normal")
	m.pitch = 0.35
	m.yaw = 0.0
	await frames(20)
	await shot("22_moon_a")
	m.yaw = PI
	await frames(20)
	await shot("22_moon_b")
	m.queue_free()
	await frames(20)
	m = await boot("garage", "normal")
	await look_at_spot(m, m.world.gen_points[0], 6.0)
	await shot("22_garage_grade")
	m.queue_free()
	await frames(10)
	# the pistol: lowered by the hip (seen from the side), then raised in both hands
	m = await boot("forest", "normal", true)
	await frames(30)
	m.rig.rotation.y = m.yaw - PI / 2.0 # her right side toward the camera
	await frames(6)
	await shot("22_gun_low")
	m.gun_aim = 999.0 # (lavapipe draws a frame a second: a 1.4 s hold would be over before the picture)
	await frames(30)
	await shot("22_gun_aim")
	m.pitch = 0.45
	await frames(15)
	await shot("22_gun_aim_up")
	m.yaw += PI * 0.6 # from the front and to the side, to see the hands and the gun
	await frames(20)
	await shot("22_gun_aim_front")
	m.queue_free()
	await frames(10)
	print("SHOT22 DONE")
	tree.quit()
