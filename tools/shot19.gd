extends Node
## The driver's seat: the killer's gloves on the turned wheel, the speedometer is HUD (not here),
## a survivor slumped in the passenger seat. Forward+ through lavapipe in check.yml.
var tree: SceneTree
var dir := ""

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])
	print("shot ", name)

func _ready() -> void:
	tree = get_tree()
	dir = OS.get_environment("NF_SHOTS")
	if dir == "": dir = "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	Gfx.shadows = 2; Gfx.effects = 1; Gfx.aa = 1; Gfx.scale_idx = 2
	Gfx.apply()
	var w := NightWorld.new()
	w.configure("rubkhali", 4242, "normal") # daylight: the inside is lit and easy to read
	add_child(w)
	w.build()
	for i in 900:
		await tree.process_frame
		if w.ready_done: break
	var car: NFCar = w.drive_car
	car.driven = true
	car.show_inside(true)
	var vic := CharacterRig.new()
	add_child(vic)
	vic.setup("survivor1")
	vic.scale = Vector3.ONE * NFCar.VICTIM_SCALE
	vic.play("slump")
	var cam := Camera3D.new()
	cam.fov = 78.0
	cam.near = 0.05
	add_child(cam)
	cam.make_current()
	var views := [["19_drive_straight", 0.0, Vector3(0, -0.35, 1.0)], ["19_drive_turning", 0.6, Vector3(0, -0.35, 1.0)],
		["19_passenger", 0.3, Vector3(-1.0, -0.45, 0.55)]]
	for v in views:
		car.steer = v[1]
		for k in 8: car.park(0.05)
		car.steer = v[1]
		car._animate(0.016)
		vic.global_position = car.seat_spot()
		vic.rotation.y = car.rotation.y
		var e := car.eye()
		var look: Vector3 = car.global_basis * (v[2] as Vector3)
		cam.global_position = e
		cam.look_at(e + look, Vector3.UP)
		await frames(12)
		await shot(v[0])
	# outside: the passenger is inside the body, nothing pokes out
	cam.global_position = car.position + car.global_basis * Vector3(-4.5, 2.2, 1.0)
	cam.look_at(car.position + Vector3(0, 1.0, 0), Vector3.UP)
	await frames(8)
	await shot("19_outside")
	print("shots done")
	tree.quit()
