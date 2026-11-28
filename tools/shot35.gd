extends Node
## «The Moon», stage 3: the two endings, frame by frame (over tools/fly_mock.gd: no map).
## NF_ONLY=win or lose to shoot one of them.
var tree: SceneTree
var dir := ""

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func _ready() -> void:
	tree = get_tree()
	dir = OS.get_environment("NF_SHOTS")
	if dir == "": dir = "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	var only := OS.get_environment("NF_ONLY")
	var m = load("res://tools/fly_mock.gd").new()
	add_child(m)
	m.setup(4242)
	await frames(3)
	for won in [true, false]:
		if only == "win" and not won: continue
		if only == "lose" and won: continue
		var e := NFEnding.new()
		add_child(e)
		e.setup(m, won, ["Rashid", "Sara"])
		e.set_process(false)
		var times: Array = [1.5, 4.8, 8.6, 12.6] if won else [1.5, 3.9, 4.6, 6.0, 8.6, 11.6]
		for tt in times:
			e.t = 0.0
			e.played.clear()
			# run the film up to tt in steps so the camera has settled where it would be
			var k := 0.0
			while k < tt:
				k = minf(k + 0.1, tt)
				e.t = k
				e._step(0.1)
			await frames(3)
			await RenderingServer.frame_post_draw
			var nm := "%s/35_%s_%04.1f.png" % [dir, "win" if won else "lose", tt]
			get_viewport().get_texture().get_image().save_png(nm)
			print("shot ", nm)
		e.finish()
		await frames(2)
	tree.quit()
