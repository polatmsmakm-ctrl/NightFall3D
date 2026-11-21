extends Node
var tree: SceneTree

func _ready() -> void:
	tree = get_tree()
	for map in ["forest", "fareej", "garage", "beach", "rubkhali"]:
		var players := [{"name": "P", "role": "survivor", "char": "survivor2", "slot": 0}]
		for i in 5: players.append({"name": "D%d" % i, "role": "survivor", "char": "survivor%d" % (i + 3), "slot": i + 1, "dummy": true})
		players.append({"name": "K", "role": "killer", "char": "killer", "slot": 6, "bot": true})
		var m = load("res://scenes/main.tscn").instantiate()
		tree.root.add_child(m)
		for i in 5: await tree.process_frame
		var t0 := Time.get_ticks_msec()
		m._start({"map": map, "me": "P", "offline": true, "players": players})
		var t1 := Time.get_ticks_msec()
		var worst := 0
		var last := Time.get_ticks_usec()
		for i in 1200:
			await tree.process_frame
			var now := Time.get_ticks_usec()
			worst = maxi(worst, now - last); last = now
			if m.world.ready_done: break
		var t2 := Time.get_ticks_msec()
		print("%s: _start %d ms, build %d ms, worst build frame %d ms" % [map, t1 - t0, t2 - t1, worst / 1000])
		# play
		var pt := 0.0; var ph := 0.0; var n := 0
		worst = 0; last = Time.get_ticks_usec()
		var spikes := []
		for i in 400:
			await tree.process_frame
			var now := Time.get_ticks_usec()
			var d := now - last; last = now
			if i > 5 and d > 30000: spikes.append("%d:%dms" % [i, d / 1000])
			worst = maxi(worst, d)
			pt += Performance.get_monitor(Performance.TIME_PROCESS); ph += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS); n += 1
		print("  play: process %.2f ms, physics %.2f ms avg; worst frame %d ms; spikes %s" % [pt / n * 1000.0, ph / n * 1000.0, worst / 1000, str(spikes.slice(0, 12))])
		# pieces
		var parts := {}
		for k in 60:
			var a := Time.get_ticks_usec(); m._feed_watch(0.016); parts["feed"] = parts.get("feed", 0) + Time.get_ticks_usec() - a
			a = Time.get_ticks_usec(); m._tools(0.016); parts["tools"] = parts.get("tools", 0) + Time.get_ticks_usec() - a
			a = Time.get_ticks_usec(); m._esc_cars(0.016); parts["esc"] = parts.get("esc", 0) + Time.get_ticks_usec() - a
			a = Time.get_ticks_usec(); m.world._process(0.016); parts["world"] = parts.get("world", 0) + Time.get_ticks_usec() - a
			if m.bot:
				a = Time.get_ticks_usec(); m.bot.step(0.016); parts["bot"] = parts.get("bot", 0) + Time.get_ticks_usec() - a
		var s := ""
		for k in parts: s += "%s %.2f  " % [k, parts[k] / 60.0 / 1000.0]
		print("  parts (ms/frame): " + s)
		print("  nodes %d, lights %d" % [Performance.get_monitor(Performance.OBJECT_NODE_COUNT), m.world.find_children("*", "Light3D", true, false).size()])
		m.queue_free()
		for i in 5: await tree.process_frame
	print("PROF DONE")
	tree.quit()
