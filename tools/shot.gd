extends Node
## Screenshots of the interface, for checking the layout without a phone.
## xvfb-run godot --rendering-driver opengl3 --resolution 1564x720 --path . res://tools/shot.tscn
## Writes PNGs into the folder named by NF_SHOTS (default user://shots).

var tree: SceneTree
var dir := ""
var m

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [dir, name])
	print("shot ", name, " ", img.get_width(), "x", img.get_height())

func _ready() -> void:
	tree = get_tree()
	dir = OS.get_environment("NF_SHOTS")
	if dir == "": dir = "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	# cheapest settings: this runs on software GL, where every frame costs seconds
	Gfx.fps_idx = 1; Gfx.preset = 0; Gfx.shadows = 0; Gfx.aa = 0; Gfx.scale_idx = 0; Gfx.effects = 0
	Gfx.apply()
	Net.username = "راشد"
	Net.xp = 4200
	Net.escapes = 12
	Net.kills = 37
	m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(14)
	m.menu.open("main")
	await frames(6)
	await shot("01_menu_main")
	# character select, then one swipe to the next character
	m.menu.chars_from = "offline"
	m.menu.open("chars")
	await frames(10)
	await shot("02_menu_chars")
	m.menu._step(1)
	await frames(8)
	await shot("03_menu_chars_next")
	# a room with friends around the fire
	Net.room = {"code": "4821", "host": "راشد", "map": "fareej", "state": "lobby", "players": [
		{"name": "راشد", "role": "survivor", "char": "survivor2"},
		{"name": "بدر", "role": "survivor", "char": "survivor5"},
		{"name": "يوسف", "role": "survivor", "char": "survivor6"},
		{"name": "عبدالله", "role": "survivor", "char": "survivor7"},
		{"name": "فهد", "role": "killer", "char": "killer"}]}
	m.menu.chars_from = "lobby"
	m.menu.open("lobby")
	await frames(14)
	await shot("04_menu_lobby")
	# the controls editor
	m.menu._open_editor()
	await frames(6)
	await shot("05_controls")
	m.menu._editor.sel = "interact"
	m.menu._editor.pad.queue_redraw()
	await frames(4)
	await shot("06_controls_sel")
	m.menu._editor.queue_free()
	m.menu._editor = null
	await frames(5)
	# a round, as a survivor
	Net.room = {}
	m._start({"map": "forest", "me": "راشد", "offline": true, "players": [
		{"name": "راشد", "role": "survivor", "char": "survivor2", "slot": 0},
		{"name": "بدر", "role": "survivor", "char": "survivor5", "slot": 1},
		{"name": "يوسف", "role": "survivor", "char": "survivor6", "slot": 2},
		{"name": "عبدالله", "role": "survivor", "char": "survivor7", "slot": 3},
		{"name": "فهد", "role": "killer", "char": "killer", "slot": 4}]})
	await frames(6)
	await shot("07_loading")
	for i in 400:
		await tree.process_frame
		if m.world.ready_done: break
	await frames(10)
	# a mix of states in the team bar
	m.rules.s["بدر"].hp = "hurt"
	m.rules.s["يوسف"].hp = "hooked"; m.rules.s["يوسف"].hook_i = 0; m.rules.s["يوسف"].t = 38.0; m.rules.s["يوسف"].hooks = 1
	m.rules.s["عبدالله"].hp = "dead"
	m.rules.gens[0].done = true; m.rules.gens[1].done = true
	m.battery = 62.0
	m.light_on = true
	await frames(8)
	await shot("08_hud_survivor")
	# quick signals: the panel open and two live messages
	m.sig_open = true
	m.sig_close = 60.0
	m._add_sig("بدر", 0, m.body.position + Vector3(14, 0, -9))
	m._add_sig("يوسف", 1, m.body.position + Vector3(-18, 0, 6))
	await frames(4)
	await shot("09_hud_signals")
	# the moon falling
	m.rules.powered = true
	m.rules.doom = 24.0
	m.rules.gens[2].done = true; m.rules.gens[3].done = true; m.rules.gens[4].done = true
	await frames(8)
	await shot("10_hud_moon")
	# the killer's own HUD
	m.queue_free()
	await frames(10)
	m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(8)
	m._start({"map": "village", "me": "فهد", "offline": true, "players": [
		{"name": "فهد", "role": "killer", "char": "killer", "slot": 0},
		{"name": "راشد", "role": "survivor", "char": "survivor2", "slot": 1},
		{"name": "بدر", "role": "survivor", "char": "survivor5", "slot": 2}]})
	for i in 400:
		await tree.process_frame
		if m.world.ready_done: break
	await frames(12)
	m.rules.s["راشد"].hp = "down"
	await frames(5)
	await shot("11_hud_killer")
	# results
	m.rules.score["فهد"] = 410.0
	m.rules.score["راشد"] = 285.0
	m.rules.score["بدر"] = 150.0
	m.rules.s["راشد"].hp = "dead"
	m.rules.s["بدر"].hp = "escaped"
	m.rules.over = true
	await frames(4)
	await shot("12_results")
	await frames(14)
	await shot("13_results_xp")
	tree.quit()
