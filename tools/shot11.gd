extends Node
## The map picker with its preview cards, the camp at night and in the fog, the roof of the
## car park, and the beach.

var tree: SceneTree
var dir := ""
var m

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])
	print("shot ", name)

func look(at: Vector3, target: Vector3, pitch := -0.05) -> void:
	m.body.position = at
	m.body.velocity = Vector3.ZERO
	m.yaw = atan2(at.x - target.x, at.z - target.z)
	m.pitch = pitch
	for i in 6: await tree.physics_frame
	await frames(4)

func boot(map: String, role := "survivor"):
	var g = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(g)
	await frames(10)
	g._start({"map": map, "me": "راشد", "offline": true, "seed": 1515, "players": [
		{"name": "راشد", "role": role, "char": "survivor2", "slot": 0},
		{"name": "فهد", "role": "killer", "char": "killer", "slot": 1},
		{"name": "بدر", "role": "survivor", "char": "survivor5", "slot": 2}]})
	for i in 900:
		await tree.process_frame
		if g.world.ready_done: break
	await frames(12)
	return g

func _ready() -> void:
	tree = get_tree()
	dir = OS.get_environment("NF_SHOTS")
	if dir == "": dir = "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	Gfx.fps_idx = 1; Gfx.preset = 0; Gfx.shadows = 1; Gfx.aa = 0; Gfx.scale_idx = 0; Gfx.effects = 1
	Gfx.apply()
	Net.username = "راشد"
	# the trial page: the map cards with their pictures, and the weather row
	m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(14)
	m.menu.open("offline")
	await frames(10)
	await shot("D0_map_picker")
	m.menu.off_theme = "fog"
	NFLobby.last_theme = "fog"
	m.menu._weather_changed()
	m.menu._refresh()
	await frames(20)
	await shot("D1_camp_fog")
	m.menu.off_theme = "normal"
	NFLobby.last_theme = "normal"
	m.menu._weather_changed()
	m.menu._refresh()
	await frames(20)
	await shot("D2_camp_night")
	m.queue_free()
	await frames(10)
	# the car park roof: the ramp, the gate up there and the last generator
	m = await boot("garage")
	var w = m.world
	var foot := Vector3((NightWorld.GAR_RAMP_X[0] + NightWorld.GAR_RAMP_X[1]) / 2.0, 0.3, NightWorld.GAR_RAMP_Z[0] - 10.0)
	await look(foot, foot + Vector3(0, 1.0, 20.0), 0.06)
	await shot("D3_ramp")
	var roof_gen: Vector3 = w.gen_points[6]
	await look(roof_gen + Vector3(7.0, 0.3, 7.0), roof_gen + Vector3(0, 1.0, 0), -0.06)
	await shot("D4_roof_generator")
	await look(Vector3(14.0, NightWorld.GAR_ROOF + 0.3, 60.0), Vector3(0, NightWorld.GAR_ROOF + 1.0, 112.0), 0.02)
	await shot("D5_roof_gate")
	m.queue_free()
	await frames(10)
	# the beach
	m = await boot("beach")
	await look(Vector3(-6, 0.3, 16.0), Vector3(6, 0.0, 50.0), 0.02)
	await shot("D6_beach")
	await look(Vector3(30, 0.3, -10.0), Vector3(-10, 1.0, 10.0), 0.0)
	await shot("D7_beach_huts")
	tree.quit()
