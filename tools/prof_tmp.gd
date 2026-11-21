extends Node
var tree: SceneTree

func avg(n: int) -> Array:
	var pt := 0.0; var ph := 0.0
	for i in n:
		await tree.process_frame
		pt += Performance.get_monitor(Performance.TIME_PROCESS); ph += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	return [pt / n * 1000.0, ph / n * 1000.0]

func _ready() -> void:
	tree = get_tree()
	for map in ["forest", "garage"]:
		var players := [{"name": "P", "role": "survivor", "char": "survivor2", "slot": 0}]
		for i in 5: players.append({"name": "D%d" % i, "role": "survivor", "char": "survivor%d" % (i + 3), "slot": i + 1, "dummy": true})
		players.append({"name": "K", "role": "killer", "char": "killer", "slot": 6, "bot": true})
		var m = load("res://scenes/main.tscn").instantiate()
		tree.root.add_child.call_deferred(m)
		for i in 10: await tree.process_frame
		m._start({"map": map, "me": "P", "offline": true, "players": players})
		for i in 1200:
			await tree.process_frame
			if m.world.ready_done: break
		for i in 200: await tree.process_frame
		var a = await avg(180)
		print("%s base: process %.2f physics %.2f" % [map, a[0], a[1]])
		# time main's own physics step directly
		var t := Time.get_ticks_usec()
		for i in 60: m._physics_process(1.0 / 60.0)
		print("  main._physics_process: %.2f ms" % ((Time.get_ticks_usec() - t) / 60000.0))
		t = Time.get_ticks_usec()
		for i in 60: m._process(1.0 / 60.0)
		print("  main._process: %.2f ms" % ((Time.get_ticks_usec() - t) / 60000.0))
		t = Time.get_ticks_usec()
		for i in 60: m._update_ctx()
		print("  _update_ctx: %.2f ms" % ((Time.get_ticks_usec() - t) / 60000.0))
		var cars: Array = m.world.esc_cars.duplicate()
		if m.world.drive_car: cars.append(m.world.drive_car)
		t = Time.get_ticks_usec()
		for i in 60:
			for c in cars: c._physics_process(1.0 / 60.0)
		print("  %d cars' physics: %.2f ms" % [cars.size(), (Time.get_ticks_usec() - t) / 60000.0])
		for c in cars: c.set_physics_process(false); c.set_process(false)
		a = await avg(120)
		print("  cars off: process %.2f physics %.2f" % [a[0], a[1]])
		m.set_physics_process(false)
		a = await avg(120)
		print("  + main physics off: process %.2f physics %.2f" % [a[0], a[1]])
		m.set_process(false)
		a = await avg(120)
		print("  + main process off: process %.2f physics %.2f" % [a[0], a[1]])
		m.world.set_process(false)
		for r in m.remotes.values(): r.rig.process_mode = Node.PROCESS_MODE_DISABLED
		m.rig.process_mode = Node.PROCESS_MODE_DISABLED
		a = await avg(120)
		print("  + world and rigs off: process %.2f physics %.2f" % [a[0], a[1]])
		print("  physics bodies: %d active, collision pairs %d, islands %d" % [Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS), Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS), Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT)])
		m.queue_free()
		for i in 10: await tree.process_frame
	print("PROF DONE")
	tree.quit()
