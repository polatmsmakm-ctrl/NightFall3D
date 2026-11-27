extends Node
## «Crimson Adventurer» (survivor10): the owner's model at full detail (every one of its 218,997
## triangles, its own 2048 maps), rigged on the cast's skeleton, and her perk «Light Feet».

var tree: SceneTree
var bad := 0

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok: bad += 1

func _ready() -> void:
	tree = get_tree()
	# --- the model as it is imported: nothing collapsed, his maps at their size
	var rig := CharacterRig.new()
	add_child(rig)
	rig.setup("survivor10")
	var tris := 0
	var tex_w := 0
	var nrm_w := 0
	for mi in rig.model.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			tris += (mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			var mat := (mi as MeshInstance3D).get_active_material(s) as StandardMaterial3D
			if mat and mat.albedo_texture: tex_w = mat.albedo_texture.get_width()
			if mat and mat.normal_texture: nrm_w = mat.normal_texture.get_width()
	check(tris == 218997, "every triangle of his model is there (%d of 218997)" % tris)
	check(tex_w == 2048 and nrm_w == 2048, "his colour and normal maps at 2048 (%d, %d)" % [tex_w, nrm_w])
	check(rig.skeleton != null and rig.skeleton.find_bone("mixamorig_Hips") >= 0, "on the cast's skeleton")
	for a in ["idle", "run", "crouchwalk", "repair", "vault", "hang", "crawl", "dying"]:
		rig.play(a)
		await frames(3)
		check(rig.player.current_animation == a, "plays %s" % a)
	check(ResourceLoader.exists("res://assets/chars/survivor10_skin.png"), "a skin mask for the stand")
	rig.queue_free()
	# --- in the menus and the rules
	check(GameMenu.CHARS.get("survivor10") == "Crimson Adventurer", "on the character stand")
	check(Rules.PERK.get("survivor10") == "nimble" and Rules.PERK_INFO.has("nimble"), "her perk: Light Feet")
	check(NFUI.CHAR_COL.has("survivor10"), "her colour on the team bar")
	# --- a round as her
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(10)
	m._start({"map": "forest", "me": "P", "offline": true, "seed": 4242, "theme": "normal", "players": [
		{"name": "P", "role": "survivor", "char": "survivor10", "slot": 0},
		{"name": "K", "role": "killer", "char": "killer", "slot": 1}]})
	for i in 1200:
		await tree.process_frame
		if m.world.ready_done: break
	await frames(20)
	check(m.chars.get("P") == "survivor10" and m.rig != null, "playable in a round")
	m.sprint = false
	m._start_vault({"c": m.body.position + Vector3(0.6, 0, 0), "n": Vector3(1, 0, 0)})
	check(not m.vault.is_empty() and absf(float(m.vault.dur) - 0.65) < 0.01, "Light Feet: a vault takes 0.65 s (%s)" % str(m.vault.get("dur", "-")))
	m.queue_free()
	await frames(5)
	print("adventurer: %d failed" % bad)
	tree.quit()
