extends Node
func _ready():
	var m = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(m)
	for i in 200: await get_tree().process_frame
	var names := ["a", "b", "c"]
	var yaws := [0.0, 2.2, 4.0]
	for k in 3:
		m.yaw = yaws[k]
		m.pitch = -0.05 if k == 0 else -0.2
		for i in 30: await get_tree().process_frame
		get_tree().root.get_texture().get_image().save_png("/tmp/shot_%s.png" % names[k])
	print("SHOTS DONE ready=", m.world.ready_done)
	get_tree().quit()
