extends Node
## The look pass: ground shading under everything, the finer materials, the clips and the
## models that get picked up automatically when the owner drops a file in.

var tree: SceneTree

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func boot(map := "forest", role := "survivor"):
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(10)
	m._start({"map": map, "me": "P", "offline": true, "seed": 31337, "players": [
		{"name": "P", "role": role, "char": "survivor2", "slot": 0},
		{"name": "K", "role": "killer", "char": "killer", "slot": 1},
		{"name": "D", "role": "survivor", "char": "survivor5", "slot": 2}]})
	for i in 900:
		await tree.process_frame
		if m.world.ready_done: break
	await frames(8)
	return m

## The darkest vertex colour of the terrain chunk that covers this spot.
func ground_shade(w, at: Vector3) -> float:
	var best := 1.0
	for body in w.find_children("Terrain", "StaticBody3D", true, false):
		for mi in body.get_children():
			if not (mi is MeshInstance3D): continue
			var mesh: Mesh = (mi as MeshInstance3D).mesh
			var arr := mesh.surface_get_arrays(0)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
			for i in verts.size():
				if Vector2(verts[i].x - at.x, verts[i].z - at.z).length() < 2.5:
					best = minf(best, cols[i].get_luminance())
	return best

func _ready() -> void:
	tree = get_tree()
	var m = await boot()
	var w = m.world
	# ---------- the ground is shaded under what stands on it ----------
	var house: Array = w.buildings[0]
	var at_house := Vector3(house[0], 0, house[1])
	var open := Vector3(-95, 0, 95)
	var a := ground_shade(w, at_house)
	var b := ground_shade(w, open)
	print("ground under a house=", snappedf(a, 0.001), "  out in the open=", snappedf(b, 0.001),
		"  darker=", a < b)
	# ---------- contact shadows ----------
	print("contact shadows: ", w.ao_blobs.size(), " of them in ", 1 if w.ao_mm else 0, " draw call",
		"  (one per generator, hook, locker, pallet, car, lamp, wreck)")
	var tris := 0
	if w.ao_mm:
		var mesh: Mesh = w.ao_mm.multimesh.mesh
		tris = (mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 * w.ao_mm.multimesh.instance_count
	print("they cost ", tris, " triangles in total")
	# ---------- the materials carry a fine detail layer now ----------
	var conc: StandardMaterial3D = w._mat.concrete
	print("concrete: detail layer=", conc.detail_enabled, " detail albedo=", conc.detail_albedo != null,
		" detail normal=", conc.detail_normal != null, " normal strength=", snappedf(conc.normal_scale, 0.01),
		" triplanar=", conc.uv1_triplanar)
	# ---------- clips: what is here, and what is waiting for a file ----------
	var want := ["idle", "walk", "run", "sprint", "crouchwalk", "hide", "attack", "injured", "dying",
		"vault", "carry", "carried", "hang", "crawl", "repair", "hit", "fall", "standup", "cheer"]
	var have := []
	var missing := []
	for c in want:
		if m.rig.has(c): have.append(c)
		else: missing.append(c)
	print("clips on the rig (", have.size(), "): ", have)
	print("waiting for a file (", missing.size(), "): ", missing, " -> drop <name>.glb in assets/anims")
	print("sprint is wired to the run state: ", m.rig.has("sprint"), " (NATURAL.sprint=", m.NATURAL.sprint, ")")
	# a flinch does nothing while there is no clip, and never touches movement
	m._hit_anim("P")
	print("flinch without a clip: timer=", m.hit_anim.size(), " (0 = nothing happened)")
	# ---------- models: the swap is armed, waiting for files ----------
	var names := ["car", "lamp", "generator", "hook", "locker"]
	var ready := []
	for n in names:
		if w._model(n) != null: ready.append(n)
	print("prop models in assets/props: ", ready, "  used this round=", w.models_used)
	print("waiting for: ", names, " -> drop <name>.glb in assets/props (collision never changes)")
	# ---------- the grade pass over the finished frame ----------
	print("grade pass up: ", m.grade != null, "  layer=", (m.grade.get_parent() as CanvasLayer).layer if m.grade else "-",
		"  ignores touches=", m.grade.mouse_filter == Control.MOUSE_FILTER_IGNORE if m.grade else "-")
	m.remotes["K"].pos = m.body.position + Vector3(3.0, 0, 0) # he is right behind you
	m.remotes["K"].node.position = m.remotes["K"].pos
	for i in 12: await tree.physics_frame
	var pulse: float = float((m.grade.material as ShaderMaterial).get_shader_parameter("pulse")) if m.grade else -1.0
	print("the killer three metres away: danger=", snappedf(m.danger, 0.01), " screen pulse=", snappedf(pulse, 0.01))
	m.remotes["K"].pos = Vector3(-200, 0, -200)
	m.remotes["K"].node.position = m.remotes["K"].pos
	for i in 12: await tree.physics_frame
	print("he leaves: danger=", snappedf(m.danger, 0.01))
	m.queue_free()
	await frames(6)
	# ---------- the garage gets the same treatment ----------
	var g = await boot("garage")
	print("garage: contact shadows=", g.world.ao_blobs.size(), " (cars and every column)")
	tree.quit()
