extends Node
func _ready():
	var root := get_tree().root
	var process_frame := get_tree().process_frame
	var physics_frame := get_tree().physics_frame
	var m = load("res://scenes/main.tscn").instantiate()
	root.add_child.call_deferred(m); await process_frame
	for i in 60: await process_frame
	var w: NightWorld = m.world
	print("world ready=", w.ready_done, " children=", w.get_child_count(), " grass chunks=", w.grass_nodes.size())
	for i in 120: await physics_frame
	print("player y=", m.body.position.y, " ground=", w.height(0,0), " on_floor=", m.body.is_on_floor())
	m.stick_vec = Vector2(0, -1)
	var p0: Vector3 = m.body.position
	for i in 120: await physics_frame
	print("moved ", p0.distance_to(m.body.position), " anim=", m.rig.current, " y=", m.body.position.y, " ground=", w.height(m.body.position.x, m.body.position.z))
	var g = Gfx
	g._on_select(2, "preset"); print("ultra: msaa=", root.msaa_3d, " scale=", root.scaling_3d_scale, " maxfps=", Engine.max_fps)
	g._on_select(3, "fps"); print("fps120 max=", Engine.max_fps)
	for k in 4: g._step_down()
	print("after stepdown scale=", g.render_scale(), " sh=", g.eff_shadows(), " fx=", g.eff_effects(), " target=", g.target_fps())
	for k in 6: g._step_down()
	print("after more: sh=", g.eff_shadows(), " fx=", g.eff_effects(), " target=", g.target_fps())
	g._on_select(1, "preset"); g._on_select(0, "fps")
	get_tree().quit()
