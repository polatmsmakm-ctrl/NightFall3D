extends Node
## The owner's props in every map: the gate model with its leaves on the sliding doors (and
## gone from the opening once powered), the fortress along the perimeter, the generator, the
## gallows and the campfires. Fails loudly, so the check workflow stops on it.

var tree: SceneTree
var bad := 0

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok: bad += 1

func _ready() -> void:
	tree = get_tree()
	for map in ["forest", "village", "fareej", "rubkhali", "garage", "beach"]:
		var w := NightWorld.new()
		w.configure(map, 4242, "normal")
		add_child(w)
		w.build()
		for i in 900:
			await tree.process_frame
			if w.ready_done: break
		print("== ", map, ": models ", w.models_used, ", fortress sections ", w.fortress_parts, ", campfires ", w.campfires)
		check(w.fortress_parts >= 30, "fortress around the map")
		check(w.hook_hang_y < 0.5, "the gallows sets how high a survivor hangs")
		var g: Dictionary = w.gate_nodes[0]
		var leaves := 0
		for d in g.doors:
			for ch in (d as Node).get_children():
				if str(ch.name).begins_with("leaf_"): leaves += 1
		check(leaves == 2, "both gate leaves ride the sliding doors")
		check((g.mat as StandardMaterial3D).get_texture(BaseMaterial3D.TEXTURE_EMISSION) != null, "the gate's sign is its own glow map")
		check((w.gen_nodes[0].mat as StandardMaterial3D).get_texture(BaseMaterial3D.TEXTURE_EMISSION) != null, "the generator's lamp is its own glow map")
		if map != "garage": check(w.campfires > 0, "burning barrels became campfires")
		check(w.car_models > 0, "cars are the Land Cruiser (%d)" % w.car_models)
		var dc: NFCar = w.drive_car
		check(dc != null, "the killer's car is parked")
		if dc:
			print("   killer car at ", dc.position.snappedf(0.1), " yaw ", snappedf(dc.rotation.y, 0.01))
			if map == "garage": check(dc.position.y > NightWorld.GAR_ROOF - 0.5, "on the garage it waits on the roof")
			else: check(Vector2(dc.position.x, dc.position.z).distance_to(Vector2(w.spawn_point("killer", 0).x, w.spawn_point("killer", 0).z)) < 40.0, "near where the killer starts")
			if map == "beach": check(dc.position.z < NightWorld.BEACH_SHORE, "not in the lagoon")
			var rq := PhysicsRayQueryParameters3D.create(dc.position + Vector3(0, 1.0, 0), dc.position + Vector3(0, -1.5, 0))
			rq.exclude = [dc.get_rid()]
			var g := w.get_world_3d().direct_space_state.intersect_ray(rq)
			check(not g.is_empty() and absf(g.position.y - dc.position.y) < 0.4, "its wheels are on the ground")
		if map == "rubkhali": check(w.tent_models == w.tents and w.tents > 0, "every tent is the crimson tent (%d of %d)" % [w.tent_models, w.tents])
		var leaf: Node3D = null
		for ch in (g.doors[0] as Node).get_children():
			if str(ch.name) == "leaf_l": leaf = ch
		var x0 := leaf.global_position.x
		w.set_gate_state(0, true)
		await tree.create_timer(5.0).timeout
		check(absf(leaf.global_position.x - x0) > 3.0, "the left leaf slid %.1f m when the gate opened" % absf(leaf.global_position.x - x0))
		w.queue_free()
		await frames(3)
	print("props check: ", "FAILED %d" % bad if bad else "all good")
	if bad: push_error("PROPS FAIL")
	tree.quit(1 if bad else 0)
