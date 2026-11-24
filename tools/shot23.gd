extends Node
## The November batch on screen: «City Life» from a street and from above, «الوحش» hunched in front
## of the camera, Bloom, the camp with the nun, the lantern tree and the ravens, the beach's galleon,
## the Empty Quarter's cactus, a pistol shot (flash, fire, smoke). Forward+ through lavapipe.
var tree: SceneTree
var dir := ""

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])
	print("shot ", name)

func boot(map: String, me_char: String, killer_char: String, gun := false):
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(10)
	m._start({"map": map, "me": "P", "offline": true, "theme": "normal", "gun": gun, "players": [
		{"name": "P", "role": "survivor", "char": me_char, "slot": 0},
		{"name": "K", "role": "killer", "char": killer_char, "slot": 1}]})
	for i in 1200:
		await tree.process_frame
		if m.world.ready_done: break
	await frames(40)
	return m

func _ready() -> void:
	tree = get_tree()
	dir = OS.get_environment("NF_SHOTS")
	if dir == "": dir = "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	Gfx.shadows = 1; Gfx.effects = 1; Gfx.scale_idx = 2; Gfx.aa = 1
	Gfx.apply()
	var m = await boot("city", "survivor9", "killer2", true)
	var w: NightWorld = m.world
	# down a street, toward the towers
	m.body.position = Vector3(-90.0, 0.4, 15.5)
	m.yaw = -PI / 2.0
	m.pitch = 0.05
	await frames(30)
	await shot("23_city_street")
	m.pitch = 0.45
	await frames(10)
	await shot("23_city_towers")
	# «الوحش» right in front of me
	var k = m.remotes["K"]
	m.body.position = Vector3(-90.0, 0.4, 15.5)
	m.yaw = 0.0
	m.pitch = -0.1
	k.node.position = m.body.position + Vector3(0, -0.4, -4.0)
	k.pos = k.node.position
	k.yaw = 0.0
	k.anim = "run"
	await frames(30)
	await shot("23_monster_run")
	k.anim = "idle"
	await frames(30)
	await shot("23_monster_idle")
	# a pistol shot
	m.gun_aim = 999.0
	await frames(20)
	m._beam(m.my_gun.muzzle() if m.my_gun and m.my_gun.visible else m.body.position + Vector3(0, 1.4, 0),
		m.body.position + Vector3(-sin(m.yaw), 0.8, -cos(m.yaw)) * 14.0, false, true)
	await frames(3)
	await shot("23_gun_flash")
	await frames(20)
	await shot("23_gun_smoke")
	m.queue_free()
	await frames(20)
	for mp in ["beach", "rubkhali", "forest"]:
		m = await boot(mp, "survivor9", "killer")
		w = m.world
		var props := w.find_children("*", "StaticBody3D", false, false)
		print("%s: %d of his props" % [mp, w.owner_props])
		# stand back from the last big prop he made, looking at it
		var target := Vector3.ZERO
		for st in w.sites: target = Vector3(st[0], st[2], st[1]) # the last site added is one of his
		m.body.position = target + Vector3(0, 1.0, 14.0)
		m.yaw = 0.0
		m.pitch = -0.12
		await frames(30)
		await shot("23_%s_props" % mp)
		m.queue_free()
		await frames(20)
	print("shot23 done")
	tree.quit()
