extends Node
## The start screen, frame by frame: the camp, the menu over it, the friends page and the
## character stand. NF_SHOTS=dir xvfb-run godot --rendering-driver opengl3 ... res://tools/shot15.tscn

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
	Gfx.fps_idx = 1; Gfx.preset = 0; Gfx.shadows = 0; Gfx.aa = 0; Gfx.scale_idx = 0; Gfx.effects = 0
	Gfx.apply()
	Net.username = "راشد"
	Net.xp = 4200
	Net.escapes = 12
	Net.kills = 37
	Net.friends = ["بدر", "فهد"]
	m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(14)
	m.menu.open("main")
	await frames(8)
	await shot("01_main")
	m.menu.open("friends")
	await frames(6)
	await shot("02_friends")
	Dev.unlocked = true
	m.menu.open("friends")
	await frames(6)
	await shot("03_friends_owner")
	m.menu.chars_from = "offline"
	m.menu.off_char = "survivor5"
	m.menu.open("chars")
	await frames(40)
	await shot("04_chars")
	print("shots done")
	tree.quit()
