extends Node
## Quick render of just the three campfire emotes (the full set is tools/shot2.tscn).
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
	if OS.get_environment("NF_PART") == "hall": # just the halloween lighting check
		var g = load("res://scenes/main.tscn").instantiate()
		tree.root.add_child.call_deferred(g)
		await frames(10)
		g._start({"map": "fareej", "me": "راشد", "offline": true, "theme": "halloween", "players": [
			{"name": "راشد", "role": "survivor", "char": "survivor2", "slot": 0}]})
		for i in 500:
			await tree.process_frame
			if g.world.ready_done: break
		await frames(12)
		var h0: Array = g.world.buildings[0]
		var hp0 := Vector3(h0[0], 0.0, h0[1])
		var pos := hp0 + Vector3(2.0, 1.4, 12.0)
		g.body.position = pos
		g.yaw = atan2(pos.x - hp0.x, pos.z - hp0.z)
		g.pitch = -0.01
		for i in 8: await tree.physics_frame
		await frames(6)
		await shot("50_halloween_tuned")
		tree.quit()
		return
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(25)
	var lob = m.lobby_scene
	m.menu.off_char = "survivor5"
	m.menu.chars_from = "offline"
	m.menu.open("chars")
	await frames(12)
	for i in NFLobby.EMOTES.size():
		for k in 3: # three moments through the loop
			lob.emote("", i)
			lob.me_rig.player.advance(0.3 + k * 0.45)
			await frames(3)
			await shot("4%d%d_emote_%s" % [i, k, NFLobby.EMOTES[i]])
	tree.quit()
