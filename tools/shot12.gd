extends Node
## The new character on the select stand (close-up model + three-point light), and in a round.

var tree: SceneTree
var dir := ""
var m

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
	Gfx.fps_idx = 1; Gfx.preset = 1; Gfx.shadows = 1; Gfx.aa = 0; Gfx.scale_idx = 2; Gfx.effects = 1
	Gfx.apply()
	Net.username = "راشد"
	m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(14)
	m.menu.chars_from = "offline"
	m.menu.off_char = "survivor8"
	m.menu.open("chars")
	await frames(60)
	await shot("E0_select_new")
	m.menu._step(1)
	await frames(50)
	await shot("E1_select_next")
	m.menu.off_char = "survivor8"
	m.menu.open("chars")
	await frames(50)
	m.lobby_scene.emote("", 0)
	await frames(30)
	await shot("E2_select_wave")
	m.queue_free()
	await frames(10)
	# and in the round, at the size you actually play at
	m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(10)
	m._start({"map": "fareej", "me": "راشد", "offline": true, "seed": 77, "players": [
		{"name": "راشد", "role": "survivor", "char": "survivor8", "slot": 0},
		{"name": "فهد", "role": "killer", "char": "killer", "slot": 1}]})
	for i in 900:
		await tree.process_frame
		if m.world.ready_done: break
	await frames(14)
	var b: Vector3 = m.body.position
	m.body.position = b
	m.yaw = 0.6
	m.pitch = -0.05
	for i in 8: await tree.physics_frame
	await frames(6)
	await shot("E3_in_game")
	tree.quit()
