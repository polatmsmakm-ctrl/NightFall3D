extends Node
## The car park after the cleanup: the big map with the ramp and everything on the roof marked,
## the brighter floor, and the minimap telling you you are on the roof.

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

func _ready() -> void:
	tree = get_tree()
	dir = OS.get_environment("NF_SHOTS")
	if dir == "": dir = "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	Gfx.fps_idx = 1; Gfx.preset = 0; Gfx.shadows = 1; Gfx.aa = 0; Gfx.scale_idx = 0; Gfx.effects = 1
	Gfx.apply()
	Net.username = "راشد"
	m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(10)
	m._start({"map": "garage", "me": "راشد", "offline": true, "seed": 1515, "players": [
		{"name": "راشد", "role": "survivor", "char": "survivor8", "slot": 0},
		{"name": "فهد", "role": "killer", "char": "killer", "slot": 1}]})
	for i in 900:
		await tree.process_frame
		if m.world.ready_done: break
	await frames(12)
	var w = m.world
	# the floor, down an aisle
	var a: Vector3 = w._gar(1, 3, 6.0, -12.0)
	await look(a + Vector3(0, 0.3, 0), w._gar(4, 3, 26.0, -12.0), -0.02)
	await shot("F0_floor")
	# the foot of the ramp, the only way up
	var foot := Vector3((NightWorld.GAR_RAMP_X[0] + NightWorld.GAR_RAMP_X[1]) / 2.0, 0.3, NightWorld.GAR_RAMP_Z[0] - 12.0)
	await look(foot, foot + Vector3(0, 1.0, 20.0), 0.04)
	await shot("F1_ramp")
	# the big map
	m.big_map = true
	await frames(6)
	await shot("F2_map")
	m.big_map = false
	# up on the roof: the minimap says so
	var g: Vector3 = w.gen_points[6]
	await look(g + Vector3(8.0, 0.3, 8.0), g + Vector3(0, 1.0, 0), -0.05)
	await frames(6)
	await shot("F3_on_roof")
	tree.quit()
