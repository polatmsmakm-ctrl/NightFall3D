extends Node
## «الشاطئ»: the sand, the lagoon, the palms from the model, and the same bones as every map.

var tree: SceneTree

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func _ready() -> void:
	tree = get_tree()
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(10)
	m._start({"map": "beach", "me": "P", "offline": true, "seed": 4242, "players": [
		{"name": "P", "role": "survivor", "char": "survivor2", "slot": 0},
		{"name": "K", "role": "killer", "char": "killer", "slot": 1}]})
	for i in 900:
		await tree.process_frame
		if m.world.ready_done: break
	await frames(10)
	var w = m.world
	print("built: huts=", w.buildings.size(), " palms=", w.beach_palms, " wet sand + shells=", w.beach_props)
	print("objectives: gens=", w.gen_points.size(), " hooks=", w.hook_points.size(), " lockers=",
		w.locker_points.size(), " pallets=", w.pallet_points.size(), " hatches=", w.hatch_points.size(),
		" doors=", w.door_points.size(), " gates=", w.gate_points.size())
	# the sand slopes into the water on the north side
	var dry: float = w.height(0, -60)
	var shore: float = w.height(0, NightWorld.BEACH_SHORE)
	var out: float = w.height(0, NightWorld.BEACH_SHORE + 30.0)
	print("the ground: dry sand y=", snappedf(dry, 0.1), "  at the shore y=", snappedf(shore, 0.1),
		"  out in the lagoon y=", snappedf(out, 0.1), "  water sits at ", NightWorld.BEACH_WATER)
	print("footsteps=", w.surface_at(Vector3(0, 0, -40)))
	# everything the round needs is on the dry side, not under water
	var wet := 0
	var all := []
	for p in w.gen_points: all.append(p)
	for p in w.hook_points: all.append(p)
	for p in w.hatch_points: all.append(p)
	for e in w.pallet_points: all.append(e[0])
	for p in all: # in the water means north of the shore *and* under the surface
		if p.z > NightWorld.BEACH_SHORE - 8.0 and w.height(p.x, p.z) < NightWorld.BEACH_WATER: wet += 1
	print("objectives standing in the lagoon: ", wet, " of ", all.size())
	# the killer used to start at (-52, 52): in the water, past the wading wall, stuck for the round
	var ks: Vector3 = w.spawn_point("killer", 1)
	var dry_ok: bool = ks.z < NightWorld.BEACH_SHORE - 4.0 and w.height(ks.x, ks.z) > NightWorld.BEACH_WATER + 0.3
	print(("  ok   " if dry_ok else "  FAIL ") + "the killer starts on the dry sand, this side of the wading wall (%.1f, %.1f)" % [ks.x, ks.z])
	var kn: Node3D = m.remotes["K"].node
	print(("  ok   " if kn.position.z < NightWorld.BEACH_SHORE else "  FAIL ") + "and so does her body in the round (z %.1f)" % kn.position.z)
	# you can wade in, you cannot swim out
	var sp = w.get_world_3d().direct_space_state
	var hit: Dictionary = sp.intersect_ray(PhysicsRayQueryParameters3D.create(
		Vector3(0, 1.0, NightWorld.BEACH_SHORE + 2.0), Vector3(0, 1.0, NightWorld.BEACH_SHORE + 30.0)))
	print("the lagoon is closed off further out: ", not hit.is_empty())
	# walk down the sand toward the water
	m.body.position = Vector3(0, w.height(0, 28.0) + 0.4, 28.0)
	m.body.velocity = Vector3.ZERO
	m.yaw = PI
	m.stick_vec = Vector2(0, -1)
	m.sprint = true
	for i in 420: await tree.physics_frame
	m.stick_vec = Vector2.ZERO
	m.sprint = false
	print("walked toward the sea: z=", snappedf(m.body.position.z, 0.1), " y=", snappedf(m.body.position.y, 0.1),
		" (wading=", m.body.position.y < 0.0, ")")
	var draws := 0 # the model's pieces only: the grass has its own chunks
	for mi in w.get_children():
		if mi is MultiMeshInstance3D and str(mi.name).begins_with("Beach_"): draws += 1
	print("model scatter draw calls=", draws)
	# the same seed builds the same beach
	var a := NightWorld.new(); a.configure("beach", 7)
	var b := NightWorld.new(); b.configure("beach", 7)
	print("same seed, same beach: ", a.gen_points == b.gen_points)
	a.free(); b.free()
	tree.quit()
