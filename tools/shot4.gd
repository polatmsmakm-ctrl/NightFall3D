extends Node
## Screenshots for phase 1: the volume settings, the version corner, the hidden tools and the
## see-through outlines (from behind a wall).

var tree: SceneTree
var dir := ""
var m

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])
	print("shot ", name)

func look_at_point(pos: Vector3, target: Vector3, pitch := -0.03) -> void:
	m.body.position = pos
	m.body.velocity = Vector3.ZERO
	m.yaw = atan2(pos.x - target.x, pos.z - target.z)
	m.pitch = pitch
	for i in 6: await tree.physics_frame
	await frames(4)

func _ready() -> void:
	tree = get_tree()
	dir = OS.get_environment("NF_SHOTS")
	if dir == "": dir = "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	Gfx.fps_idx = 1; Gfx.preset = 0; Gfx.shadows = 0; Gfx.aa = 0; Gfx.scale_idx = 0; Gfx.effects = 0
	Gfx.apply()
	Net.username = "راشد"
	Dev.unlocked = false
	# ---------- the menu, with the version text in the corner ----------
	m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(25)
	m.menu.open("main")
	await frames(8)
	await shot("60_menu_version")
	# the settings panel: master volume, then the split
	Gfx.open_settings()
	await frames(8)
	await shot("61_settings_volume")
	for ch in Gfx._panel.find_children("*", "Button", true, false):
		if ch.text == "تفصيل": ch.emit_signal("pressed")
	await frames(8)
	await shot("62_settings_volume_split")
	Gfx._toggle()
	await frames(6)
	# ---------- the hidden page, once this phone has unlocked it ----------
	for i in 15: Dev.tap()
	m.menu.open("dev")
	await frames(10)
	await shot("63_dev_page")
	m.menu.open("main")
	await frames(6)
	m.queue_free()
	await frames(8)
	# ---------- in a round: the dot, its panel, and the outlines through a wall ----------
	m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(10)
	m._start({"map": "forest", "me": "راشد", "offline": true, "players": [
		{"name": "راشد", "role": "survivor", "char": "survivor2", "slot": 0},
		{"name": "فهد", "role": "killer", "char": "killer", "slot": 1},
		{"name": "بدر", "role": "survivor", "char": "survivor5", "slot": 2}]})
	for i in 500:
		await tree.process_frame
		if m.world.ready_done: break
	await frames(10)
	var b: Array = m.world.buildings[0]
	var rot := Basis(Vector3.UP, b[2])
	var centre := Vector3(b[0], m.world.height(b[0], b[1]), b[1])
	# the killer waits inside the shack, a team-mate stands behind it
	var k = m.remotes["فهد"]
	k.pos = centre + rot * Vector3(0.0, 0.3, 0.0)
	k.node.position = k.pos
	var mate = m.remotes["بدر"]
	mate.pos = centre + rot * Vector3(6.0, 0.3, -9.0)
	mate.node.position = mate.pos
	await look_at_point(centre + rot * Vector3(0.5, 1.4, 11.0), centre + Vector3(0, 1.4, 0), -0.01)
	await shot("64_wall_before")
	m.dev_panel.visible = true
	await frames(6)
	await shot("65_dev_panel")
	Dev.set_esp(true)
	m.dev_panel.visible = false
	await frames(8)
	await shot("66_esp_through_wall")
	await look_at_point(centre + rot * Vector3(0.5, 1.4, 26.0), centre + Vector3(0, 6.0, 0), 0.06)
	await shot("67_esp_masts")
	tree.quit()
