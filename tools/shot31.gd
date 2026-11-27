extends Node
## The Social Sidebar with sample friends: the Friends tab (online in menu / lobby / match, offline),
## the Requests tab (received and sent), and a friend's profile.
## NF_SHOTS=dir xvfb-run -a godot --rendering-driver opengl3 --resolution 1564x720 --path . res://tools/shot31.tscn

var tree: SceneTree
var dir := ""
var m

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])
	print("shot ", name)

func fake() -> void:
	Net.state = "online"
	Net.friends = ["Badr", "Fahad", "Saud", "Mubarak", "Yousef", "Ghanim"]
	Net.online = {"badr": true, "fahad": true, "saud": true}
	Net.status = {"badr": "game", "fahad": "room", "saud": "menu"}
	Net.fdisplay = {"badr": {"name": "Badr", "display": "Abu Nasser", "ch": "survivor3", "lv": 14},
		"fahad": {"name": "Fahad", "display": "Fahad", "ch": "killer2", "lv": 9}, "saud": {"name": "Saud", "display": "Saud", "ch": "survivor6", "lv": 22},
		"mubarak": {"name": "Mubarak", "display": "Mubarak", "ch": "survivor2", "lv": 5}, "yousef": {"name": "Yousef", "display": "Yousef", "ch": "survivor10", "lv": 3},
		"ghanim": {"name": "Ghanim", "display": "Ghanim", "ch": "killer", "lv": 31}, "nasser": {"name": "Nasser", "display": "Nasser", "ch": "survivor9", "lv": 7},
		"hamad": {"name": "Hamad", "display": "Hamad", "ch": "survivor1", "lv": 2}}
	Net.fstats = {"mubarak": {"name": "Mubarak", "seen": int(Time.get_unix_time_from_system() * 1000.0) - 3 * 3600000}}
	Net.req_in = [{"name": "Nasser", "display": "Nasser", "ch": "survivor9", "lv": 7}]
	Net.req_out = ["Hamad"]
	Net.display = "Abu Fahad"

func _ready() -> void:
	tree = get_tree()
	dir = OS.get_environment("NF_SHOTS")
	if dir == "": dir = "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	Gfx.fps_idx = 1; Gfx.preset = 0; Gfx.shadows = 0; Gfx.aa = 0; Gfx.scale_idx = 0; Gfx.effects = 0
	Gfx.apply()
	Net.username = "Rashid"
	Net.xp = 4200
	Net.last_char = "survivor10"
	m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(3)
	m.lobby_scene.intro = 1.0
	fake()
	m.menu.open("main")
	await frames(6)
	fake()
	m.menu._refresh()
	await frames(2)
	await shot("01_main_with_request")
	m.menu.social.open()
	for i in 10:
		fake()
		await frames(1)
	m.menu.social._dirty = true
	await frames(3)
	await shot("02_social_friends")
	m.menu.social.tab = "requests"
	m.menu.social._dirty = true
	fake()
	await frames(3)
	await shot("03_social_requests")
	m.menu.social.close()
	m.menu.prof_name = "Saud"
	fake()
	m.menu.open("profile")
	await frames(10)
	await shot("04_profile")
	tree.quit()
