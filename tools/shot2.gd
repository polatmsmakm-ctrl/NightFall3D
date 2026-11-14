extends Node
## Screenshots of the new content: the Empty Quarter, the snow and halloween themes,
## the campfire emotes and the pickup jumpscare.
## xvfb-run godot --rendering-driver opengl3 --resolution 1172x540 --path . res://tools/shot2.tscn

var tree: SceneTree
var dir := ""
var m

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [dir, name])
	print("shot ", name)

func boot(map: String, theme: String, role := "survivor"):
	var g = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(g)
	await frames(10)
	g._start({"map": map, "me": "راشد", "offline": true, "theme": theme, "players": [
		{"name": "راشد", "role": role, "char": "survivor2", "slot": 0},
		{"name": "بدر", "role": "survivor", "char": "survivor5", "slot": 1},
		{"name": "فهد", "role": "killer", "char": "killer", "slot": 2}]})
	for i in 500:
		await tree.process_frame
		if g.world.ready_done: break
	await frames(12)
	return g

## Stand at `pos` and aim the camera at `target` (the camera looks along -Z, behind the player).
func look_at_point(pos: Vector3, target: Vector3, pitch := -0.05) -> void:
	await look(pos, atan2(pos.x - target.x, pos.z - target.z), pitch)

## Put the player somewhere and point the camera.
func look(at: Vector3, yaw: float, pitch := -0.1) -> void:
	m.body.position = at
	m.body.velocity = Vector3.ZERO
	m.yaw = yaw
	m.pitch = pitch
	for i in 6: await tree.physics_frame
	await frames(4)

func _ready() -> void:
	tree = get_tree()
	dir = OS.get_environment("NF_SHOTS")
	if dir == "": dir = "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	Gfx.fps_idx = 1; Gfx.preset = 0; Gfx.shadows = 0; Gfx.aa = 0; Gfx.scale_idx = 0; Gfx.effects = 0
	Gfx.apply()
	Net.username = "راشد"
	# ---------- the Empty Quarter ----------
	m = await boot("rubkhali", "normal")
	var w = m.world
	var tent: Array = w.buildings[0]
	var rot := Basis(Vector3.UP, tent[2])
	var tent_at := Vector3(tent[0], w.height(tent[0], tent[1]), tent[1])
	await look_at_point(tent_at + rot * Vector3(2.0, 1.2, 14.0), tent_at + Vector3(0, 1.5, 0), -0.02)
	await shot("20_desert_tent")
	await look_at_point(tent_at + rot * Vector3(0.2, 0.5, 5.2), tent_at + rot * Vector3(0, 1.0, -1.5), 0.02)
	await shot("21_desert_tent_inside")
	# an animal, from a few metres away
	var an: Dictionary = w.animals[0]
	for x in w.animals:
		if not x.stand:
			an = x
			break
	var ap: Vector3 = an.node.position
	await look_at_point(ap + Vector3(4.5, 1.2, 6.5), ap + Vector3(0, 1.1, 0), -0.02)
	await shot("22_desert_animal")
	# a wreck and the open dunes
	var far := Vector3(0, 0, 0)
	for ch in w.get_children():
		if ch is StaticBody3D and ch.get_child_count() > 6 and ch.position.length() > 30.0 and ch.position.length() < 90.0:
			far = ch.position
	await look_at_point(far + Vector3(6.0, 1.3, 7.5), far + Vector3(0, 1.0, 0), -0.02)
	await shot("23_desert_wreck")
	# the gate from inside, so the way out is visible through the storm
	var g0: Array = w.gate_points[0]
	await look_at_point(Vector3(g0[0].x + 1.0, g0[0].y + 1.4, g0[0].z + 30.0), g0[0] + Vector3(0, 5.0, 0), 0.02)
	await shot("24_desert_gate")
	m.queue_free()
	await frames(10)
	# ---------- snow ----------
	m = await boot("forest", "snow")
	var b0: Array = m.world.buildings[0]
	var bp := Vector3(b0[0], m.world.height(b0[0], b0[1]), b0[1])
	await look_at_point(bp + Vector3(1.0, 1.3, 13.0), bp + Vector3(0, 2.0, 0), -0.01)
	await shot("25_snow_forest")
	var mate: Vector3 = m.remotes["بدر"].node.position
	await look_at_point(mate + Vector3(1.6, 1.3, 2.2), mate + Vector3(0, 1.6, 0), 0.0)
	await shot("26_snow_breath")
	m.queue_free()
	await frames(10)
	# ---------- halloween ----------
	m = await boot("fareej", "halloween")
	var h0: Array = m.world.buildings[0]
	var hp0 := Vector3(h0[0], 0.0, h0[1])
	await look_at_point(hp0 + Vector3(2.0, 1.4, 12.0), hp0 + Vector3(0, 1.8, 0), -0.01)
	await shot("27_halloween_house")
	var hk: Vector3 = m.world.hook_points[0]
	await look_at_point(hk + Vector3(2.6, 1.3, 3.4), hk + Vector3(0, 2.6, 0), 0.06)
	await shot("28_halloween_hook")
	m.queue_free()
	await frames(10)
	# ---------- the jumpscare ----------
	m = await boot("village", "normal")
	var k = m.remotes["فهد"]
	k.pos = m.body.position + Vector3(0, 0, 1.6)
	k.node.position = k.pos
	k.yaw = PI
	await frames(20)
	m.rules.s["راشد"].hp = "down"; m.rules.s["راشد"].t = Rules.BLEED_TIME
	for i in 4: await tree.physics_frame
	m.rules.carrying = "راشد"; m.rules.s["راشد"].hp = "carried"
	for i in 3: await tree.physics_frame
	await frames(2)
	await shot("29_jumpscare")
	m.queue_free()
	await frames(10)
	# ---------- emotes at the campfire ----------
	m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(25)
	var lob = m.lobby_scene
	m.menu.off_char = "survivor5"
	m.menu.chars_from = "offline"
	m.menu.open("chars") # the camera moves in on the character
	await frames(14)
	for i in NFLobby.EMOTES.size():
		lob.emote("", i)
		await frames(6)
		await shot("3%d_emote_%s" % [i, NFLobby.EMOTES[i]])
		await frames(4)
	tree.quit()
