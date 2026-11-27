extends Node
## The owner's start screen (his mockup): the painted camp, the menu, Dances, Game Modes, MAP SELECT,
## trial mode, a room, and the loading screen with his map picture.
## NF_SHOTS=dir xvfb-run -a godot --rendering-driver opengl3 --resolution 1564x720 --path . res://tools/shot30.tscn

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
	Net.username = "Rashid"
	Net.xp = 4200; Net.escapes = 12; Net.kills = 37
	Net.friends = ["Bader", "Fahad"]
	Net.last_char = "survivor10"
	m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(3)
	var lob: NFLobby = m.lobby_scene
	print("painted camp: ", lob.painted)
	lob.intro = 1.0
	m.menu.open("main")
	await frames(8)
	await shot("01_main")
	for r in lob.stock: print("seat at screen ", lob.cam.unproject_position(r.global_position), " feet ", lob.cam.unproject_position(r.global_position + Vector3(0, 1.8, 0)))
	m.menu._map_step(1)
	await frames(4)
	await shot("02_main_village")
	m.menu.off_map = "kuwait"
	m.menu._refresh()
	await frames(30)
	await shot("03_main_kuwait")
	m.menu.open("dances")
	lob.dance_preview("dance_break")
	await frames(40)
	await shot("04_dances")
	m.menu.open("modes")
	await frames(4)
	await shot("05_modes")
	m.menu.off_theme = "snow"
	m.menu.open("main")
	await frames(6)
	await shot("06_main_snow_same_camp")
	m.menu.chars_from = "offline"
	m.menu.open("offline")
	await frames(4)
	await shot("07_trial")
	m.menu.open("chars")
	await frames(40)
	await shot("08_chars")
	Net.room = {"code": "4821", "host": "Rashid", "map": "beach", "theme": "fog", "players": [
		{"name": "Rashid", "role": "survivor", "char": "survivor10"}, {"name": "Bader", "role": "killer", "char": "killer2"},
		{"name": "Fahad", "role": "survivor", "char": "survivor9"}]}
	Net.state = "online"
	m.menu.open("lobby")
	await frames(2)
	await shot("09_room")
	for id in ["kuwait", "forest", "fareej"]:
		var ld := NFLoading.new()
		ld.setup(id, "normal")
		tree.root.add_child(ld)
		ld.progress(0.6)
		await frames(4)
		await shot("10_loading_" + id)
		ld.queue_free()
	tree.quit()
