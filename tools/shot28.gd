extends Node
## The owner's cat and dog in a round (forest): the cat round the generator, sitting, playing; the dog
## stalking, running in, the bite and the shake, the swallow. A soft light rides with the camera so
## the fur can be judged at night.
var tree: SceneTree
var dir := ""
var cam: Camera3D
var follow: Node3D
var off := Vector3(2.2, 1.0, 2.2)
var look_y := 0.25

func frames(n: int) -> void:
	for i in n:
		await tree.process_frame
		_aim()

func _aim() -> void:
	if follow and cam:
		var p := follow.global_position
		cam.global_position = cam.global_position.lerp(p + off, 0.35)
		cam.look_at(p + Vector3(0, look_y, 0))

func shot(name: String) -> void:
	_aim()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])
	print("shot ", name)

func wait_until(cd: NFCatDog, cond: Callable, limit := 900) -> void:
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
		{"name": "D", "role": "survivor", "char": "survivor2", "slot": 1},
		{"name": "K", "role": "killer", "char": "killer", "slot": 2}]})
	for i in 1500:
		await tree.process_frame
		if m.world.ready_done: break
	await frames(40)
	m.rules.ev_at = 99999.0
	var cd: NFCatDog = m.catdog
	cam = Camera3D.new()
	m.add_child(cam)
	cam.fov = 50.0
	cam.current = true
	var fill := OmniLight3D.new()
	fill.light_energy = 1.4
	fill.omni_range = 14.0
	fill.shadow_enabled = false
	cam.add_child(fill)
	var g := 2
	var gp: Vector3 = m.world.gen_points[g]
	m.body.global_position = gp + Vector3(1.0, 0.2, 0.0) # me, at the generator
	m.rules.gens[g].p = 0.05
	await frames(2)
	follow = cd.cat
	cam.global_position = cd.cat.global_position + off
	await frames(25)
	await shot("28_cat_comes")
	off = Vector3(-1.4, 0.55, 1.2)
	look_y = 0.2
	await wait_until(cd, func() -> bool: return cd.act == "circle", 600)
	await frames(12)
	await shot("28_cat_walk")
	off = Vector3(0.0, 0.5, 1.6)
	await wait_until(cd, func() -> bool: return cd.act == "sit" and cd.cat.sit > 0.9, 900)
	await shot("28_cat_sit")
	off = Vector3(1.6, 0.4, 0.2)
	await wait_until(cd, func() -> bool: return cd.act == "play" and cd.act_t > 1.05, 1200)
	await shot("28_cat_pounce")
	await wait_until(cd, func() -> bool: return cd.act == "play" and cd.cat.swipe > 0.8, 200)
	await shot("28_cat_swipe")
	# the generator done: the dog
	m.rules.gens[g].p = 1.0
	m.rules.gens[g].done = true
	await frames(3)
	follow = cd.dog
	off = Vector3(2.8, 1.3, 2.8)
	look_y = 0.5
	cam.global_position = cd.dog.global_position + off
	await frames(40)
	await shot("28_dog_stalk")
	off = Vector3(-2.0, 0.8, 1.0)
	await wait_until(cd, func() -> bool: return cd.ph == 1, 1500)
	await frames(6)
	await shot("28_dog_freeze")
	await wait_until(cd, func() -> bool: return cd.ph == 2 and cd.ph_t > 0.35, 400)
	await shot("28_dog_sprint")
	off = Vector3(2.0, 1.0, 1.4)
	await wait_until(cd, func() -> bool: return cd.ph == 3 and cd.ph_t > 0.5, 400)
	await shot("28_dog_bite")
	await wait_until(cd, func() -> bool: return cd.ph == 3 and cd.ph_t > 1.4, 400)
	await shot("28_dog_shake")
	off = Vector3(0.6, 0.7, 2.2)
	await wait_until(cd, func() -> bool: return cd.ph == 4 and cd.ph_t > 1.4, 600)
	await shot("28_dog_swallow")
	off = Vector3(3.0, 1.5, -1.0)
	await wait_until(cd, func() -> bool: return cd.ph == 5 and cd.ph_t > 0.8, 600)
	await shot("28_dog_runs")
	# the blood it left
	follow = null
	cam.global_position = cd.cat.global_position + Vector3(1.5, 1.6, 1.5)
	cam.look_at(cd.spot)
	await frames(10)
	await shot("28_blood")
	get_tree().quit()
