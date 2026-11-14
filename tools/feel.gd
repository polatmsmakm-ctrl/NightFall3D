extends Node
## Phase 1 checks: the haptics switch and cooldowns, and every camera move.

var tree: SceneTree

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func boot(role := "survivor"):
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(10)
	m._start({"map": "forest", "me": "P", "offline": true, "players": [
		{"name": "P", "role": role, "char": "survivor2", "slot": 0},
		{"name": "K", "role": "killer", "char": "killer", "slot": 1},
		{"name": "D", "role": "survivor", "char": "survivor5", "slot": 2}]})
	for i in 400:
		await tree.process_frame
		if m.world.ready_done: break
	await frames(8)
	return m

func _ready() -> void:
	tree = get_tree()
	# ---------- haptics ----------
	Aud.set_haptics(true)
	print("haptics on=", Aud.haptics, " enabled()=", NFHaptics.enabled(), " kinds=", NFHaptics.KINDS.size())
	NFHaptics.pulse("hit")
	var fired := NFHaptics._next.has("hit")
	NFHaptics.pulse("hit") # the cooldown must swallow this one
	print("a pulse was sent=", fired, " cooldown kept=", NFHaptics._next.has("hit"))
	Aud.set_haptics(false)
	NFHaptics._next.clear()
	NFHaptics.pulse("hit")
	print("switched off: nothing sent=", not NFHaptics._next.has("hit"))
	Aud.set_haptics(true)
	var c := ConfigFile.new(); c.load(Aud.PATH)
	print("saved in user://: haptics=", c.get_value("a", "haptics"))
	# ---------- the camera ----------
	var m = await boot()
	print("camera at rest: arm=", snappedf(m.arm.spring_length, 0.01), " roll=", snappedf(m.cam_pivot.rotation.z, 0.001))
	m._shake(0.8)
	for i in 3: await tree.physics_frame
	var kicked: float = absf(m.cam_pivot.rotation.z) + absf(m.cam_pivot.rotation.x - m.pitch)
	for i in 90: await tree.physics_frame
	var settled: float = absf(m.cam_pivot.rotation.z) + absf(m.cam_pivot.rotation.x - m.pitch)
	print("hit kick: right after=", snappedf(kicked, 0.001), " a second later=", snappedf(settled, 0.001),
		" (springs back=", settled < kicked * 0.3, ")")
	# carried: sway, and the camera eases out
	m.rules.s["P"].hp = "down"; m.rules.s["P"].t = Rules.BLEED_TIME
	for i in 4: await tree.physics_frame
	m.rules.carrying = "P"; m.rules.s["P"].hp = "carried"
	for i in 40: await tree.physics_frame
	print("carried: arm=", snappedf(m.arm.spring_length, 0.01), " sway=", snappedf(absf(m.cam_pivot.rotation.z), 0.001))
	# hooked: it pulls right back and tips up
	m.rules.carrying = ""
	m.rules.s["P"].hp = "hooked"; m.rules.s["P"].hook_i = 0; m.rules.s["P"].t = 60.0; m.rules.s["P"].hooks = 1
	for i in 120: await tree.physics_frame
	print("hooked: arm=", snappedf(m.arm.spring_length, 0.01), " looking up by=", snappedf(m.cam_pivot.rotation.x - m.pitch, 0.01))
	# escape: slow motion for about a second, then back to normal
	m.rules.s["P"].hp = "ok"
	for i in 10: await tree.physics_frame
	m.rules.s["P"].hp = "escaped"
	for i in 6: await tree.physics_frame
	print("escaped: slowmo=", snappedf(m.slowmo, 0.01), " time scale=", snappedf(Engine.time_scale, 0.01),
		" fov=", snappedf(m.main_cam.fov, 0.1))
	for i in 200: await tree.physics_frame
	print("after it: time scale=", Engine.time_scale, " arm back=", snappedf(m.arm.spring_length, 0.01))
	tree.quit()
