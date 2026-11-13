extends SceneTree
func _init():
	var m = load("res://scenes/main.tscn").instantiate()
	root.add_child(m)
	m.rig.play("walk")
	m.set_physics_process(false)
	m.yaw = 0.6
	for i in 20: await process_frame
	m.rig.player.seek(0.3, true)
	for i in 5: await process_frame
	root.get_texture().get_image().save_png("/tmp/shot.png")
	quit()
