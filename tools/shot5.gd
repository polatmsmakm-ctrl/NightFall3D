extends Node
## Phase 1 screenshots: the vibration switch, the camera moves (hit, carried, hooked, escape)
## and the new character beats (limp, out of breath, startled, head turned).

var tree: SceneTree
var dir := ""
var m

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])
	print("shot ", name)

func phys(n: int) -> void:
	for i in n: await tree.physics_frame

func _ready() -> void:
	tree = get_tree()
	dir = OS.get_environment("NF_SHOTS")
	if dir == "": dir = "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	Gfx.fps_idx = 1; Gfx.preset = 0; Gfx.shadows = 0; Gfx.aa = 0; Gfx.scale_idx = 0; Gfx.effects = 0
	Gfx.apply()
	Net.username = "راشد"
	# ---------- the vibration switch ----------
	m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(22)
	m.menu.open("main")
	Gfx.open_settings()
	await frames(6)
	for ch in Gfx._panel.find_children("*", "Button", true, false):
		if ch.text == "تفصيل": ch.emit_signal("pressed")
	await frames(8)
	await shot("70_haptics_switch")
	Gfx._toggle()
	await frames(4)
	m.queue_free()
	await frames(8)
	# ---------- in a round ----------
	m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(10)
	m._start({"map": "village", "me": "راشد", "offline": true, "players": [
		{"name": "راشد", "role": "survivor", "char": "survivor2", "slot": 0},
		{"name": "فهد", "role": "killer", "char": "killer", "slot": 1},
		{"name": "بدر", "role": "survivor", "char": "survivor5", "slot": 2}]})
	for i in 500:
		await tree.process_frame
		if m.world.ready_done: break
	await frames(10)
	# limping while hurt
	m.tired = 0.0
	m.rules.s["راشد"].hp = "hurt"
	m.stick_vec = Vector2(0, -1)
	m.sprint = false
	await phys(70)
	await shot("72_limp")
	m.stick_vec = Vector2.ZERO
	# the killer steps into view: startle + head turn
	m.rules.s["راشد"].hp = "ok"
	var k = m.remotes["فهد"]
	k.pos = m.body.position + Vector3(2.0, 0, 5.5)
	k.node.position = k.pos
	k.yaw = PI
	m.yaw = PI + 0.35
	await phys(12)
	await shot("73_startled")
	# a hit: the camera kicks
	m._on_event({"k": "hurt", "n": "راشد", "s": "hurt"})
	await phys(3)
	await shot("74_hit_kick")
	await phys(60)
	# carried over his shoulder
	m.rules.s["راشد"].hp = "down"; m.rules.s["راشد"].t = Rules.BLEED_TIME
	await phys(4)
	m.rules.carrying = "راشد"; m.rules.s["راشد"].hp = "carried"
	await phys(50)
	await shot("75_carried_sway")
	# on the hook: the camera pulls back and looks up
	m.rules.carrying = ""
	m.rules.s["راشد"].hp = "hooked"; m.rules.s["راشد"].hook_i = 0
	m.rules.s["راشد"].t = 60.0; m.rules.s["راشد"].hooks = 1
	await phys(150)
	await shot("76_hooked_pullback")
	# and getting out: the slow zoom
	m.rules.s["راشد"].hp = "ok"
	await phys(10)
	m.rules.s["راشد"].hp = "escaped"
	await phys(20)
	await shot("77_escape_slowmo")
	m.queue_free()
	await frames(10)
	# ---------- the two new poses, seen properly at the campfire ----------
	m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(22)
	var lob = m.lobby_scene
	m.menu.off_char = "survivor5"
	m.menu.chars_from = "offline"
	m.menu.open("chars")
	await frames(12)
	for pose in [["tired", "71_out_of_breath"], ["startle", "73b_startled_pose"]]:
		lob.me_rig.current = ""
		lob.me_rig.play(str(pose[0]))
		lob.me_rig.player.advance(0.45)
		await frames(4)
		await shot(str(pose[1]))
	tree.quit()
