extends Node
## Phase 2 screenshots: a door open and shut, the blackout, the heavy fog, the alarm arrow
## on the killer's screen, and a house light going out as he walks up to it.

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

func look_at_point(pos: Vector3, target: Vector3, pitch := -0.03) -> void:
	m.body.position = pos
	m.body.velocity = Vector3.ZERO
	m.yaw = atan2(pos.x - target.x, pos.z - target.z)
	m.pitch = pitch
	await phys(6)
	await frames(4)

func boot(map: String, role := "survivor"):
	var g = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(g)
	await frames(10)
	g._start({"map": map, "me": "راشد", "offline": true, "seed": 4242, "players": [
		{"name": "راشد", "role": role, "char": "survivor2", "slot": 0},
		{"name": "فهد", "role": "killer", "char": "killer", "slot": 1},
		{"name": "بدر", "role": "survivor", "char": "survivor5", "slot": 2}]})
	for i in 500:
		await tree.process_frame
		if g.world.ready_done: break
	await frames(10)
	return g

func _ready() -> void:
	tree = get_tree()
	dir = OS.get_environment("NF_SHOTS")
	if dir == "": dir = "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	Gfx.fps_idx = 1; Gfx.preset = 0; Gfx.shadows = 0; Gfx.aa = 0; Gfx.scale_idx = 0; Gfx.effects = 0
	Gfx.apply()
	Net.username = "راشد"
	# ---------- doors, on the fareej where the houses are ----------
	m = await boot("fareej")
	var w = m.world
	var di := 0
	for i in w.door_nodes.size():
		if w.door_nodes[i] != null:
			di = i
			break
	var dp: Array = w.door_points[di]
	var out := Basis(Vector3.UP, dp[1]) * Vector3(0, 0, 1)
	await look_at_point(dp[0] + out * 4.2 + Vector3(0, 1.3, 0), dp[0] + Vector3(0, 1.2, 0), 0.0)
	await shot("80_door_open")
	m.body.position = dp[0] + out * 1.4 + Vector3(0, 0.3, 0)
	await phys(10)
	m._press("interact", 5)
	await phys(50)
	await look_at_point(dp[0] + out * 4.2 + Vector3(0, 1.3, 0), dp[0] + Vector3(0, 1.2, 0), 0.0)
	await shot("81_door_shut")
	# ---------- blackout ----------
	var lamp: Vector3 = Vector3.ZERO
	for e in w.amb_lights:
		var l: OmniLight3D = e[0]
		if l.global_position.distance_to(Vector3(0, 0, 0)) > 20.0 and l.global_position.y < 6.0:
			lamp = l.global_position
			break
	await look_at_point(lamp + Vector3(7.0, 1.4, 7.0), lamp, 0.02)
	await shot("82_lights_on")
	m.rules.ev_kind = 0; m.rules.ev_t = 20.0; m.rules.ev_fired = true
	await frames(40)
	await shot("83_blackout")
	m.rules.ev_t = 0.0
	await frames(50)
	# ---------- heavy fog ----------
	m.ev_shown = -1
	m.rules.ev_kind = 1; m.rules.ev_t = 40.0
	await frames(30)
	await shot("84_heavy_fog")
	m.rules.ev_t = 0.0
	await frames(30)
	m.queue_free()
	await frames(10)
	# ---------- the alarm, from the killer's side ----------
	m = await boot("village", "killer")
	m.remotes["بدر"].pos = m.body.position + Vector3(26, 0, 14)
	m.remotes["بدر"].node.position = m.remotes["بدر"].pos
	m.ev_shown = -1
	m.rules.ev_kind = 2; m.rules.ev_t = 5.0; m.rules.ev_n = "بدر"; m.rules.ev_fired = true
	await frames(14)
	await shot("85_alarm_killer")
	m.rules.ev_t = 0.0
	# ---------- a house light goes out as he walks up ----------
	var house: Vector3 = Vector3.ZERO
	for e in m.world.amb_lights:
		if bool(e[2]):
			house = (e[0] as OmniLight3D).global_position
			break
	m.body.position = house + Vector3(30, 0.3, 30)
	await phys(10)
	await look_at_point(house + Vector3(14.0, 1.5, 14.0), house, -0.02)
	await shot("86_house_light_on")
	await look_at_point(house + Vector3(4.0, 1.5, 4.0), house, -0.05)
	await frames(40)
	await shot("87_house_light_out")
	tree.quit()
