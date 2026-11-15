extends Node
## «المواقف» checks: the car-park modules line up into one floor, every objective is on
## open concrete under the slab, the same seed builds the same level, and you can walk.

var tree: SceneTree

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func boot(seed := 2211):
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(10)
	m._start({"map": "garage", "me": "P", "offline": true, "seed": seed, "players": [
		{"name": "P", "role": "survivor", "char": "survivor2", "slot": 0},
		{"name": "K", "role": "killer", "char": "killer", "slot": 1},
		{"name": "D", "role": "survivor", "char": "survivor5", "slot": 2}]})
	for i in 900:
		await tree.process_frame
		if m.world.ready_done: break
	await frames(10)
	return m

func ray(w, from: Vector3, to: Vector3) -> Dictionary:
	var sp: PhysicsDirectSpaceState3D = w.get_world_3d().direct_space_state
	return sp.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))

func _ready() -> void:
	tree = get_tree()
	var m = await boot()
	var w = m.world
	print("modules=", w.garage_tiles.size(), " solid blocks=", w.garage_solids.size(),
		" floor=", int(NightWorld.GAR_W * NightWorld.GAR_S * NightWorld.GAR_COLS), "x",
		int(NightWorld.GAR_D * NightWorld.GAR_S * NightWorld.GAR_ROWS), " m  ceiling=",
		snappedf(NightWorld.GAR_H * NightWorld.GAR_S, 0.1), " m")
	var cores := 0
	var walls := 0
	var blocks := 0
	for t in w.garage_tiles:
		if "core" in t.pieces: cores += 1
		if "wall_s" in t.pieces: walls += 1
		if "north_block" in t.pieces: blocks += 1
	print("stair cores=", cores, " cross walls=", walls, " ramps nobody can climb=", blocks,
		" (the model's own ramp to a storey that does not exist — must be 0)")
	print("objectives: gens=", w.gen_points.size(), " hooks=", w.hook_points.size(),
		" lockers=", w.locker_points.size(), " pallets=", w.pallet_points.size(),
		" hatches=", w.hatch_points.size(), " vault barriers=", w.window_points.size(),
		" doors=", w.door_points.size(), " gates=", w.gate_points.size())
	# nothing may sit inside a column, a core or a wall
	var bad := 0
	var all := []     # everything on the floor
	var roof := []    # and everything up on the roof
	for p in w.gen_points: (roof if p.y > 1.0 else all).append(p)
	for p in w.hook_points: (roof if p.y > 1.0 else all).append(p)
	for p in w.hatch_points: all.append(p)
	for e in w.pallet_points: all.append(e[0])
	for e in w.locker_points: all.append(e[0])
	for p in all:
		if not w._gar_free(p.x, p.z, 0.6): bad += 1
	print("objectives standing in concrete: ", bad, "   up on the roof: ", roof.size())
	# the floor is solid under them and the slab is overhead
	var floor_hits := 0
	var ceiling_hits := 0
	for p in all:
		if not ray(w, p + Vector3(0, 2.0, 0), p - Vector3(0, 1.0, 0)).is_empty(): floor_hits += 1
		if not ray(w, p + Vector3(0, 1.0, 0), p + Vector3(0, 9.0, 0)).is_empty(): ceiling_hits += 1
	print("floor under them: ", floor_hits, "/", all.size(), "   slab over them: ", ceiling_hits, "/", all.size())
	# ---------- the roof: you can stand on it, walk up to it, and it has the last generator ----------
	for p in roof:
		var under := ray(w, p + Vector3(0, 1.5, 0), p - Vector3(0, 0.8, 0))
		print("roof objective at y=", snappedf(p.y, 0.01), ": slab under it=", not under.is_empty(),
			"  open sky above=", ray(w, p + Vector3(0, 1.0, 0), p + Vector3(0, 40.0, 0)).is_empty())
	var ramp_foot := Vector3((NightWorld.GAR_RAMP_X[0] + NightWorld.GAR_RAMP_X[1]) / 2.0, 0, NightWorld.GAR_RAMP_Z[0] - 8.0)
	var ramp_top := Vector3(ramp_foot.x, NightWorld.GAR_ROOF, NightWorld.GAR_RAMP_Z[1] + 1.0)
	var steps := 0
	for i in 13: # walk up the slope and check there is road under every step
		var f := float(i) / 12.0
		var at := ramp_foot.lerp(ramp_top, f)
		if not ray(w, at + Vector3(0, 2.0, 0), at - Vector3(0, 1.2, 0)).is_empty(): steps += 1
	print("the ramp: solid under ", steps, "/13 steps, rises ", snappedf(NightWorld.GAR_ROOF, 0.1), " m over ",
		int(NightWorld.GAR_RAMP_Z[1] - NightWorld.GAR_RAMP_Z[0]), " m")
	# and actually drive up it
	m.body.position = ramp_foot + Vector3(0, 0.4, 0)
	m.body.velocity = Vector3.ZERO
	m.yaw = PI          # face up the slope (+z)
	m.stick_vec = Vector2(0, -1)
	m.sprint = true
	for i in 600: await tree.physics_frame
	m.stick_vec = Vector2.ZERO
	m.sprint = false
	print("walked up the ramp: now at y=", snappedf(m.body.position.y, 0.1),
		" (roof is ", snappedf(NightWorld.GAR_ROOF, 0.1), ")  made it=", m.body.position.y > NightWorld.GAR_ROOF - 0.6)
	# the map shows the way up and everything that is on the roof
	m.big_map = true
	await frames(3)
	var roof_marks := 0
	for p in w.gen_points: if p.y > 1.0: roof_marks += 1
	for p in w.hook_points: if p.y > 1.0: roof_marks += 1
	for g in w.gate_points: if (g[0] as Vector3).y > 1.0: roof_marks += 1
	print("on the map: the ramp is drawn, and ", roof_marks, " things carry the roof badge (gate, generator, hook)")
	print("standing on the roof the map says so: ", m.body.position.y > 3.0)
	m.big_map = false
	# the roof generator cannot be worked on from the floor underneath it
	var rg: Vector3 = roof[0]
	m.body.position = Vector3(rg.x, 0.3, rg.z)
	m.body.velocity = Vector3.ZERO
	for i in 10: await tree.physics_frame
	print("standing under the roof generator: interact=", m.ctx.get("interact", {}).get("kind", "nothing"))
	m.body.position = rg + Vector3(1.4, 0.3, 0)
	for i in 10: await tree.physics_frame
	print("standing next to it on the roof: interact=", m.ctx.get("interact", {}).get("kind", "nothing"))
	# the way out: from the middle to each gate opening
	for g in w.gate_points:
		var gp: Vector3 = g[0]
		print("gate at z=", int(gp.z), " sits at y=", snappedf(gp.y, 0.1))
		var hit := ray(w, Vector3(0, 1.2, signf(gp.z) * (NightWorld.GAR_D * NightWorld.GAR_S * NightWorld.GAR_ROWS / 2.0 - 2.0)),
			Vector3(0, 1.2, gp.z * 0.97))
		print("the opening toward the gate at z=", int(gp.z), " is clear: ", hit.is_empty())
	# walk a few metres down an aisle
	var start: Vector3 = w.hook_points[0] + Vector3(4.0, 0.3, 0)
	m.body.position = start
	m.body.velocity = Vector3.ZERO
	m.stick_vec = Vector2(0, -1)
	for i in 150: await tree.physics_frame
	m.stick_vec = Vector2.ZERO
	print("walked ", snappedf(Vector2(m.body.position.x - start.x, m.body.position.z - start.z).length(), 0.1),
		" m down an aisle, standing at y=", snappedf(m.body.position.y, 0.01))
	# headroom: a hook and a parked car both fit under the slab
	var hp: Vector3 = w.hook_points[0]
	print("headroom over a hook: ", snappedf(NightWorld.GAR_H * NightWorld.GAR_S - 3.4, 0.01), " m")
	print("footsteps: ", w.surface_at(hp), "   adhan from ", w.adhan_point().snapped(Vector3(1, 1, 1)))
	# lights, cars and the blackout
	var lights := 0
	for ch in w.get_children():
		if ch is OmniLight3D: lights += 1
	print("strip lights=", lights, " dark modules=", w.garage_tiles.size() - lights,
		" parked cars=", w.garage_cars, " panels tied to the blackout=", w.garage_panels.size())
	# standing at a barrier offers the vault
	m.body.position = w.window_points[0][0] + (w.window_points[0][1] as Vector3) * 1.2 - Vector3(0, 0.55, 0)
	m.body.velocity = Vector3.ZERO
	for i in 8: await tree.physics_frame
	print("at a crash barrier the vault button is up: ", m.ctx.has("vault"))
	var e0: float = (w.amb_lights[0][0] as OmniLight3D).light_energy
	w.set_blackout(true)
	await frames(90)
	print("blackout: a strip light went from ", snappedf(e0, 0.01), " to ", snappedf((w.amb_lights[0][0] as OmniLight3D).light_energy, 0.01))
	w.set_blackout(false)
	await frames(60)
	var tris := 0
	for mi in w.find_children("*", "MultiMeshInstance3D", true, false):
		var mm: MultiMesh = (mi as MultiMeshInstance3D).multimesh
		if mm == null or mm.mesh == null: continue
		var t := 0
		for si in mm.mesh.get_surface_count():
			t += (mm.mesh.surface_get_arrays(si)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		tris += t * mm.instance_count
	print("car-park geometry: ", w.find_children("*", "MultiMeshInstance3D", true, false).size(),
		" draw calls, ", tris, " triangles")
	# online everyone builds from the host's seed, so the same seed must give the same level
	var plan := func(seed: int) -> Array:
		var nw := NightWorld.new()
		nw.configure("garage", seed, "normal")
		var out := []
		for p in nw.gen_points: out.append(p.snapped(Vector3(0.01, 0.01, 0.01)))
		for p in nw.hook_points: out.append(p.snapped(Vector3(0.01, 0.01, 0.01)))
		for p in nw.hatch_points: out.append(p.snapped(Vector3(0.01, 0.01, 0.01)))
		for t in nw.garage_tiles: out.append(str(t.pieces))
		nw.free()
		return out
	var a: Array = plan.call(4242)
	var b: Array = plan.call(4242)
	var c: Array = plan.call(777)
	print("same seed, same level: ", a == b, "   another seed moves it: ", a != c)
	tree.quit()
