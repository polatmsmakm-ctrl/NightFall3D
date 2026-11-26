extends Node
## The interface pass on screen: the event feed, the hit arc and the gate arrow in a round, the
## controls sliders in the settings panel, and «طريقة اللعب». Forward+ through lavapipe in check.yml.
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
		{"name": "The Killer", "role": "killer", "char": "killer", "slot": 2}]})
	for i in 600:
		await tree.process_frame
		if m.world.ready_done: break
	await frames(30)
	# a moment in a round: gates open, a few things on the feed, just been hit
	m.rules.s["سارة"].hp = "down"
	await frames(2)
	m._on_event({"k": "hooked", "n": "سارة", "s": "hooked"})
	m._on_event({"k": "rescued", "n": "سارة", "by": "P", "hands": 1})
	for g in m.rules.gens: g.done = true
	m.rules.powered = true
	await frames(2)
	m.body.position = m.world.gate_points[0][0] + Vector3(25.0, 0.5, 30.0)
	m.yaw = 0.6
	await frames(20)
	m._on_event({"k": "hurt", "n": "P", "s": "hurt"})
	await frames(6)
	await shot("20_hud")
	Gfx.open_settings()
	await frames(4)
	await shot("20_settings")
	var sc: ScrollContainer = Gfx._panel.find_children("*", "ScrollContainer", true, false)[0]
	sc.scroll_vertical = 260
	await frames(4)
	await shot("20_settings_controls")
	Gfx._toggle()
	var mn = m.menu
	mn.visible = true
	mn.open("help")
	await frames(6)
	await shot("20_help_survivor")
	mn.help_tab = "killer"
	mn._refresh()
	await frames(6)
	await shot("20_help_killer")
	tree.quit()
