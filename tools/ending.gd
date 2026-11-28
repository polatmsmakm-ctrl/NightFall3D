extends Node
## «The Moon», stage 3: the rocket rammed — HUMANITY HAS FALLEN, held exactly twelve seconds before
## the numbers; and the film's pieces (his Earth in twelve parts, the meteor, the fireball).
var tree: SceneTree
var bad := 0

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok: bad += 1

func _ready() -> void:
	tree = get_tree()
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(10)
	m._start({"map": "moon", "me": "P", "offline": true, "seed": 77, "theme": "normal", "players": [
		{"name": "P", "role": "survivor", "char": "survivor1", "slot": 0},
		{"name": "K", "role": "killer", "char": "killer", "slot": 2}]})
	for i in 1500:
		await tree.process_frame
		if m.world.ready_done: break
	await frames(30)
	m.rules.gate_delay = 0.0
	for g in 5: m.rules.gens[g].p = 1.0; m.rules.gens[g].done = true
	await frames(10)
	m.body.position = NightWorld.MOON_BOARD + Vector3(0, 0.3, 0)
	for i in 400:
		await tree.physics_frame
		if m.flight.me_mode() == "fly": break
	m.rules.fl.c = 20.0
	for e in m.rules.handle({"k": "kship"}, "K"): m._on_event(e)
	check(bool(m.rules.fl.ks), "the killer took off")
	var t0 := Time.get_ticks_msec()
	for e in m.rules.handle({"k": "rram"}, "K"): m._on_event(e)
	check(int(m.rules.fl.st) == 4 and m.rules.hp("P") == "dead", "rammed: lost, everyone aboard dead")
	await frames(2)
	var e2: NFEnding = m.ending
	check(e2 != null and not e2.won, "the defeat film plays")
	check(e2 != null and e2.pieces.size() == 12, "his Earth in twelve pieces (%d)" % (e2.pieces.size() if e2 else 0))
	var tris := 0
	if e2:
		for pc in e2.pieces:
			for mi in (pc[0] as Node3D).find_children("*", "MeshInstance3D", true, false):
				var mesh: Mesh = (mi as MeshInstance3D).mesh
				for si in mesh.get_surface_count(): tris += mesh.surface_get_array_index_len(si) / 3
	check(tris == 615480, "every one of his triangles is there (%d)" % tris)
	for i in 3000:
		await tree.process_frame
		if m.results != null: break
	var held := (Time.get_ticks_msec() - t0) / 1000.0
	check(m.results != null and held >= NFEnding.LOSE_LEN - 0.05 and held < NFEnding.LOSE_LEN + 1.5, "the numbers come up after %.2f s (12 asked)" % held)
	print("ENDING %s (%d failed)" % ["PASS" if bad == 0 else "FAIL", bad])
	tree.quit(1 if bad else 0)
