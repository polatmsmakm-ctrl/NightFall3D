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
	Net.online = {"بدر": true, "فهد": true}
	Net.last_char = "survivor5"
	Net.last_round = {"res": "escaped", "score": 340, "gens": 5, "wipe": false}
	var only := OS.get_environment("NF_ONLY")
	m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(3)
	var lob: NFLobby = m.lobby_scene
	m.menu.open("main")
	# the opening shot, three moments of it
	for st in [[0.05, "00_intro_a"], [0.45, "00_intro_b"], [0.8, "00_intro_c"]]:
		lob.intro = st[0]
		lob.set_process(false)
		m.menu._process(0.0)
		lob._process(0.0001)
		await frames(2)
		await shot(st[1])
	lob.intro = 1.0
	lob.set_process(true)
	await frames(6)
	await shot("01_main")
	for i in 3: # she moves between the trees
		lob._stalk_t = 0.0; lob._stalk_seen = false; lob._tick_stalker(0.01)
		await frames(3)
		await shot("02_stalker_%d" % i)
	m.menu.open("friends")
	await frames(4)
	await shot("03_friends")
	m.menu.chars_from = "offline"
	m.menu.off_char = "survivor5"
	m.menu.open("chars")
	await frames(30)
	await shot("04_chars")
	for e in 3: # the emotes, four moments each
		lob.emote("", e)
		await frames(2)
		var an: Animation = lob.me_rig.player.get_animation(NFLobby.EMOTES[e])
		for q in 4:
			lob.me_rig.player.seek(an.length * (0.06 + 0.25 * q), true)
			lob.me_rig.player.pause()
			await frames(2)
			await shot("05_%s_%d" % [NFLobby.EMOTES[e], q])
		lob.me_rig.player.play()
	m.menu.open("offline")
	for id in ["village", "fareej", "rubkhali", "garage", "beach"]:
		m.menu.off_map = id
		m.menu._refresh()
		await frames(4)
		await shot("06_camp_%s" % id)
	m.menu.off_map = "forest"
	Net.last_round = {"res": "dead", "score": 90, "gens": 2, "wipe": true}
	lob._time_of_day()
	m.menu.open("main")
	await frames(4)
	await shot("07_blood_moon")
	print("shots done")
	tree.quit()
