extends Node
## Phase 3 screenshots: the camp at four times of day (and a misty night), two survivors
## pulling one off the hook together, and the victory shot at the gate.

var tree: SceneTree
var dir := ""
var m

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func phys(n: int) -> void:
	for i in n: await tree.physics_frame

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
	var only := OS.get_environment("NF_ONLY") # "camp", "rescue", "win", or all of it
	# ---------- the camp follows the clock on the phone ----------
	if only in ["", "camp"]:
		NFLobby.force_mist = 0
		m = load("res://scenes/main.tscn").instantiate()
		tree.root.add_child.call_deferred(m)
		await frames(14)
		m.menu.open("main")
		await frames(8)
		var names := {6: "90_camp_dawn", 12: "91_camp_day", 18: "92_camp_dusk", 23: "93_camp_night"}
		for h in [6, 12, 18, 23]:
			NFLobby.force_hour = h
			m.lobby_scene._time_of_day()
			await frames(10)
			await shot(str(names[h]))
		NFLobby.force_mist = 1
		NFLobby.force_hour = 21
		m.lobby_scene._time_of_day()
		await frames(10)
		await shot("94_camp_misty")
		NFLobby.force_hour = -1
		NFLobby.force_mist = -1
		m.queue_free()
		await frames(8)
	if only == "camp": tree.quit()
	# ---------- two survivors on one hook ----------
	m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(10)
	m._start({"map": "forest", "me": "راشد", "offline": true, "seed": 909, "players": [
		{"name": "راشد", "role": "survivor", "char": "survivor2", "slot": 0},
		{"name": "فهد", "role": "killer", "char": "killer", "slot": 1},
		{"name": "بدر", "role": "survivor", "char": "survivor5", "slot": 2},
		{"name": "يوسف", "role": "survivor", "char": "survivor6", "slot": 3}]}) 
	for i in 500:
		await tree.process_frame
		if m.world.ready_done: break
	await frames(10)
	# hang يوسف on the nearest hook and put me and بدر next to him
	var hk: Vector3 = m.world.hook_points[0]
	m.rules.s["يوسف"].hp = "hooked"
	m.rules.s["يوسف"].hooks = 1
	m.rules.s["يوسف"].hook_i = 0
	m.rules.s["يوسف"].t = Rules.HOOK_TIME[0]
	m.remotes["يوسف"].pos = hk
	m.remotes["يوسف"].node.position = hk
	m.remotes["بدر"].pos = hk + Vector3(1.0, 0, 0.6)
	m.remotes["بدر"].node.position = hk + Vector3(1.0, 0, 0.6)
	m.body.position = hk + Vector3(-1.0, 0.3, 1.0)
	m.body.velocity = Vector3.ZERO
	m.yaw = atan2(m.body.position.x - hk.x, m.body.position.z - hk.z)
	m.pitch = -0.06
	await phys(10)
	m.rules.handle({"k": "rescue", "n": "يوسف", "on": true}, "بدر")
	m._press("interact", 90) # I hold it too
	await phys(8)
	await frames(4)
	if only != "win": await shot("95_rescue_together")
	if only == "rescue": tree.quit()
	# ---------- the victory shot, then the numbers ----------
	m.rules.score = {"راشد": 320.0, "بدر": 240.0, "يوسف": 110.0, "فهد": 180.0}
	m.rules.s["راشد"].hp = "escaped"
	m.rules.s["بدر"].hp = "escaped"
	m.rules.s["يوسف"].hp = "dead"
	m.rules.over = true
	await frames(20)
	await shot("96_victory_gate")
	await frames(60)
	await shot("97_victory_turn")
	for i in 900:
		await tree.process_frame
		if m.results.intro <= 0.0: break
	await frames(30)
	await shot("98_results_after")
	tree.quit()
