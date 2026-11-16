extends Node
## The maps before and after the lighter nights: one round per map, the same frame twice,
## first with the old light (no lift) and then as it ships.

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
	Gfx.fps_idx = 1; Gfx.preset = 0; Gfx.shadows = 0; Gfx.aa = 0; Gfx.scale_idx = 0; Gfx.effects = 0
	Gfx.apply()
	Net.username = "راشد"
	for map in ["forest", "fareej", "garage"]:
		var m = load("res://scenes/main.tscn").instantiate()
		tree.root.add_child(m)
		await frames(6)
		m._start({"map": map, "me": "راشد", "offline": true, "players": [
			{"name": "راشد", "role": "survivor", "char": "survivor5", "slot": 0},
			{"name": "فهد", "role": "killer", "char": "killer", "slot": 1}]})
		for i in 500:
			await tree.process_frame
			if m.world.ready_done: break
		await frames(20)
		var w: NightWorld = m.world
		var after := [w.env.ambient_light_energy, w.env.fog_density, w.env.tonemap_exposure, w.env.adjustment_brightness, w.moon.light_energy]
		w.env.ambient_light_energy = after[0] / 1.55; w.env.fog_density = after[1] / 0.72
		w.env.tonemap_exposure = 1.0; w.env.adjustment_brightness = 1.0; w.moon.light_energy = after[4] / 1.3
		await frames(4)
		await shot("10_%s_before" % map)
		w.env.ambient_light_energy = after[0]; w.env.fog_density = after[1]
		w.env.tonemap_exposure = after[2]; w.env.adjustment_brightness = after[3]; w.moon.light_energy = after[4]
		await frames(4)
		await shot("11_%s_after" % map)
		m.queue_free()
		await frames(4)
	print("shots done")
	tree.quit()
