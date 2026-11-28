extends Node
## «The Moon», stage 2: the rocket chase on camera — cruising through the meteors, the boost, a big
## meteor alarm, a strike, the killer's ship behind, her own view. Run over tools/fly_mock.gd (no map).
var tree: SceneTree
var dir := ""
var ui: Control
var m

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func shot(name: String) -> void:
	ui.queue_redraw()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/34_%s.png" % [dir, name])
	print("shot ", name)

func _ready() -> void:
	tree = get_tree()
	dir = OS.get_environment("NF_SHOTS")
	if dir == "": dir = "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	m = load("res://tools/fly_mock.gd").new()
	add_child(m)
	m.setup(4242)
	var cl := CanvasLayer.new()
	add_child(cl)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.draw.connect(func(): m.flight.draw_hud(ui, ui.get_viewport_rect().size))
	cl.add_child(ui)
	var f: NFFlight = m.flight
	m.fly(6.0)
	if OS.get_environment("NF_CREW") != "0": m.crew()
	f.throttle = 1.0
	f.r_vel = Vector3(0, 0, 200.0)
	f.r_loc = Vector3(0, 0, 900.0)
	for i in 150: await tree.physics_frame
	await shot("cruise")
	# the cabin: eight seats, everyone in theirs, from my seat looking forward, to the side, back
	f.inside = true
	for i in 6: await tree.physics_frame
	await shot("cabin_front")
	f.look = Vector2(1.2, -0.1)
	for i in 3: await tree.physics_frame
	await shot("cabin_side")
	f.look = Vector2(2.6, -0.15)
	for i in 3: await tree.physics_frame
	await shot("cabin_back")
	f.inside = false
	# looking back from outside: the Moon they left
	f.look = Vector2(2.6, 0.1)
	f.look_idle = -100.0
	for i in 4: await tree.physics_frame
	await shot("moon_behind_near")
	f.r_loc.z = Rules.FLY_LEN * 0.6
	for i in 4: await tree.physics_frame
	await shot("moon_behind_far")
	f.look = Vector2.ZERO
	f.look_idle = 0.0
	f.r_loc.z = 900.0
	for i in 20: await tree.physics_frame
	m.rules.fl.b = true
	for i in 90: await tree.physics_frame
	await shot("boost")
	m.rules.fl.b = false
	var big := -1
	for i in f.met.size():
		var e: Array = f.met[i]
		if float(e[3]) >= NFFlight.BIG_R and int(e[4]) == 0 and float(e[0]) > f.r_loc.z + 2000.0: big = i; break
	if big >= 0:
		var mp: Array = f.meteor_at(big, f.clk)
		f.r_loc = Vector3(mp[0].x + 26.0, mp[0].y + 8.0, float(f.met[big][0]) - 700.0)
		for i in 20: await tree.physics_frame
		await shot("big_meteor")
	var tgt := -1
	for i in f.met.size():
		var e: Array = f.met[i]
		if int(e[4]) == 0 and float(e[0]) > f.r_loc.z + 200.0 and float(e[3]) < 6.0 and not f.gone.has(i): tgt = i; break
	var tp: Array = f.meteor_at(tgt, f.clk)
	f.r_loc = Vector3(tp[0].x, tp[0].y, float(f.met[tgt][0]) - 20.0)
	for i in 8: await tree.physics_frame
	await shot("strike")
	m.rules.fl.ks = true
	f.k_t = 5.0
	for i in 3: await tree.process_frame
	f.k_loc = f.r_loc + Vector3(13.0, 3.0, -70.0)
	f.k_vel = f.r_vel
	for i in 4: await tree.physics_frame
	await shot("killer_behind")
	m.rules.fl.ks = true
	m.my_role = "killer"; m.my_name = "K"
	for i in 3: await tree.physics_frame
	f.k_loc = f.r_loc + Vector3(-10.0, 2.0, -120.0)
	for i in 30: await tree.physics_frame
	await shot("killer_view")
	tree.quit()
