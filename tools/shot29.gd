extends Node
## «الوحش»'s meal on the hook (legs gone, to the stomach, to the chest, only the head) and the gorilla
## with the horse (the charge, the tear, the head held up, the bites, the swallow), forest at night,
## a soft light riding with the camera.
var tree: SceneTree
var dir := ""
var cam: Camera3D
var follow: Node3D
var off := Vector3(0, 1.2, 4.0)
var look_y := 1.2

func frames(n: int) -> void:
	for i in n:
		await tree.process_frame
		_aim()

func _aim() -> void:
	if follow == null: return
	if follow and is_instance_valid(follow) and cam:
		var p := follow.global_position
		cam.global_position = cam.global_position.lerp(p + off, 0.35)
		cam.look_at(p + Vector3(0, look_y, 0))

func shot(name: String) -> void:
	_aim()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])
	print("shot ", name)

func until(cond: Callable, limit := 1200) -> void:
	for i in limit:
		if cond.call(): return
		await frames(1)

func _ready() -> void:
	tree = get_tree()
	dir = OS.get_environment("NF_SHOTS")
	if dir == "": dir = "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	Gfx.shadows = 1; Gfx.effects = 1; Gfx.scale_idx = 2; Gfx.aa = 1
	Gfx.apply()
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(10)
	m._start({"map": "forest", "me": "P", "offline": true, "seed": 4242, "theme": "normal", "players": [
		{"name": "P", "role": "survivor", "char": "survivor1", "slot": 0},
		{"name": "D", "role": "survivor", "char": "survivor8", "slot": 1},
		{"name": "K", "role": "killer", "char": "killer2", "slot": 2}]})
	for i in 1500:
		await tree.process_frame
		if m.world.ready_done: break
	await frames(40)
	m.rules.ev_at = 99999.0
	cam = Camera3D.new()
	m.add_child(cam)
	cam.fov = 50.0
	cam.current = true
	var fill := OmniLight3D.new()
	fill.light_energy = 1.6
	fill.omni_range = 16.0
	fill.shadow_enabled = false
	cam.add_child(fill)
	m.ui.visible = false
	# ---- the kiss and the hug
	var d = m.remotes["D"]
	var here: Vector3 = m.body.global_position
	d.pos = here + Vector3(0.9, 0, 0.6)
	d.node.global_position = d.pos
	m.rules.s["D"].hp = "hurt"
	await frames(10)
	m._kiss_ready()
	await frames(3)
	m._press("interact", 0)
	var mid: Vector3 = (here + d.pos) * 0.5
	var u: Vector3 = (d.pos - here).normalized()
	var side := Vector3(-u.z, 0, u.x)
	follow = null
	for k in [[0.5, "29_kiss_1_step_in", 2.6, 1.4], [1.9, "29_kiss_2_side", 2.1, 1.6], [2.6, "29_kiss_3_faces", 0.9, 1.65], [3.2, "29_kiss_4_over_shoulder", 1.6, 1.8]]:
		while m.kiss.now.size() > 0 and float(m.kiss.now.values()[0].t) < float(k[0]): await tree.process_frame
		var at: Vector3 = mid + Vector3(0, float(k[3]), 0)
		var from: Vector3 = at + side * float(k[2]) + Vector3(0, 0.05, 0)
		if str(k[1]) == "29_kiss_4_over_shoulder": from = at - u * 1.4 + side * 0.5 + Vector3(0, 0.2, 0)
		cam.global_position = from
		cam.look_at(at)
		await shot(str(k[1]))
	await frames(80)
	m.rules.s["D"].hp = "ok"
	# ---- the meal on the hook
	var D: Dictionary = m.rules.s["D"]
	D.hp = "hooked"; D.hooks = 2; D.hook_i = 1; D.t = Rules.HOOK_TIME[1]
	m.body.global_position = m.world.hook_points[1] + Vector3(4.0, 0.3, 4.0)
	follow = m.remotes["D"].node
	cam.global_position = follow.global_position + off
	await frames(40)
	var names := ["29_hook_0_whole", "29_hook_1_legs", "29_hook_2_thighs", "29_hook_3_stomach", "29_hook_4_chest"]
	for k in 5:
		D.t = Rules.HOOK_TIME[1] * (1.0 - (k + 0.95) / 5.0) if k > 0 else Rules.HOOK_TIME[1] * 0.99
		await frames(25)
		await shot(names[k])
	D.t = 0.05
	await frames(10)
	m.rules.s["D"].hp = "dead"
	await frames(200)
	off = Vector3(0.6, 0.0, 2.2)
	look_y = 2.4
	await frames(30)
	await shot("29_hook_5_head")
	off = Vector3(2.0, 0.6, 2.4)
	look_y = 0.0
	await frames(30)
	await shot("29_hook_6_blood_below")
	# ---- the gorilla and the horse
	var cd: NFCatDog = m.catdog
	var go = m.gorilla
	cd._start_cat(0)
	cd._start_dog()
	cd.state = 3
	cd.ph = 6
	cd.dog.visible = false
	cd.cat.visible = false
	await frames(3)
	go.wait = 0.05
	await frames(5)
	follow = go.horse
	off = Vector3(6.0, 2.5, 6.0)
	look_y = 1.0
	cam.global_position = follow.global_position + off
	await until(func() -> bool: return go.ph >= 1)
	await frames(20)
	await shot("29_gorilla_1_horse_grazing")
	await until(func() -> bool: return go.ph >= 2)
	follow = go.rig
	off = Vector3(5.0, 2.5, 7.0)
	look_y = 2.0
	await frames(30)
	await shot("29_gorilla_2_charge")
	await until(func() -> bool: return go.ph >= 3 and go.fall_t > 0.5)
	follow = go.horse
	off = Vector3(5.0, 3.0, 5.0)
	look_y = 1.2
	await frames(8)
	await shot("29_gorilla_3_blow")
	await until(func() -> bool: return go.ph == 4 and go.ph_t > 1.6)
	follow = go.rig
	off = Vector3(4.0, 2.8, 4.0)
	look_y = 1.2
	await frames(4)
	await shot("29_gorilla_4_tearing")
	await until(func() -> bool: return go.head_state >= 1)
	await frames(4)
	await shot("29_gorilla_5_torn")
	await until(func() -> bool: return go.ph == 5 and go.ph_t > 1.2)
	off = Vector3(0.0, 2.0, 7.0)
	off = go.rig.global_basis.z.normalized() * 7.0 + Vector3(0, 1.5, 0)
	look_y = 3.0
	await frames(12)
	await shot("29_gorilla_6_roar")
	await until(func() -> bool: return go.ph == 7 and go.bites >= 2)
	off = Vector3(4.0, 3.0, 3.0)
	look_y = 1.0
	await frames(10)
	await shot("29_gorilla_7_bite")
	await until(func() -> bool: return go.ph == 8 and go.ph_t > 1.7)
	off = go.rig.global_basis.z.normalized() * 8.0 + Vector3(0, 1.0, 0)
	look_y = 3.4
	await frames(10)
	await shot("29_gorilla_8_swallow")
	await until(func() -> bool: return go.head_state == 3)
	follow = go.head
	off = Vector3(1.5, 1.0, 1.5)
	look_y = 0.0
	await frames(30)
	await shot("29_gorilla_9_head")
	get_tree().quit()
