extends Node
## Renders one picture of every map into NF_SHOTS, to be copied into assets/mapshots/ and shown
## on the map picker. One scenic camera per map, no HUD.

var tree: SceneTree
var dir := ""

const VIEWS := {                       # map -> [camera position, what it looks at]
	"forest":   [Vector3(18, 6, 26), Vector3(-10, 2, -10)],
	"village":  [Vector3(26, 7, 34), Vector3(-6, 2, 0)],
	"fareej":   [Vector3(30, 9, 40), Vector3(0, 2, 6)],
	"rubkhali": [Vector3(24, 7, 30), Vector3(-16, 1, -18)],
	"garage":   [Vector3.ZERO, Vector3.ZERO], # worked out from the modules below
	"beach":    [Vector3(0, 10, 4), Vector3(0, 0, 60)],
}

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func _ready() -> void:
	tree = get_tree()
	dir = OS.get_environment("NF_SHOTS")
	if dir == "": dir = "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	Gfx.fps_idx = 1; Gfx.preset = 1; Gfx.shadows = 1; Gfx.aa = 0; Gfx.scale_idx = 2; Gfx.effects = 1
	Gfx.apply()
	Net.username = "راشد"
	var only := OS.get_environment("NF_ONLY").split(",", false) # one, a few, or all of them
	for id in VIEWS:
		if only.size() > 0 and not (id in only): continue
		var m = load("res://scenes/main.tscn").instantiate()
		tree.root.add_child.call_deferred(m)
		await frames(10)
		m._start({"map": id, "me": "راشد", "offline": true, "seed": 90210, "players": [
			{"name": "راشد", "role": "survivor", "char": "survivor2", "slot": 0},
			{"name": "فهد", "role": "killer", "char": "killer", "slot": 1}]})
		for i in 900:
			await tree.process_frame
			if m.world.ready_done: break
		await frames(14)
		if m.hud_layer: m.hud_layer.visible = false # a clean picture, no buttons
		if m.grade: m.grade.visible = false
		for l in Gfx.get_children(): # the settings gear lives on its own layer
			if l is CanvasLayer: (l as CanvasLayer).visible = false
		# a preview has to read on a small card, so a night map is lifted; the desert already
		# plays at noon and would blow straight out
		var lift: float = 1.0 if id == "rubkhali" else (1.22 if id == "fareej" else 1.5)
		var env: Environment = m.world.env
		env.ambient_light_energy *= 1.0 + (lift - 1.0) * 2.8
		env.adjustment_enabled = true
		env.adjustment_brightness = lift
		m.world.moon.light_energy *= 1.0 + (lift - 1.0) * 1.4
		var cam := Camera3D.new()
		cam.fov = 62.0
		cam.far = 400.0
		m.world.add_child(cam)
		var from: Vector3 = VIEWS[id][0]
		var to: Vector3 = VIEWS[id][1]
		if id == "garage": # down an aisle, with the strip lights leading away
			from = m.world._gar(1, 3, 6.0, -12.0) + Vector3(0, 1.9, 0)
			to = m.world._gar(4, 3, 26.0, -12.0) + Vector3(0, 1.2, 0)
		cam.position = from
		cam.look_at(to, Vector3.UP)
		cam.current = true
		await frames(10)
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.resize(512, 288, Image.INTERPOLATE_LANCZOS)
		img.save_png("%s/%s.png" % [dir, id])
		print("shot ", id)
		m.queue_free()
		await frames(10)
	tree.quit()
