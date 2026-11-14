extends Node
## Phase 1 checks: haptics switch, the camera moves, the limp / out-of-breath poses
## and the head turns.

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
	m.queue_free()
	await frames(8)
	# ---------- limp, tired, startle ----------
	m = await boot()
	print("posed clips: tired=", m.rig.player.has_animation("tired"), " startle=", m.rig.player.has_animation("startle"),
		" tracks=", m.rig.player.get_animation("tired").get_track_count(), "/", m.rig.player.get_animation("startle").get_track_count(),
		" startle loops=", m.rig.player.get_animation("startle").loop_mode != Animation.LOOP_NONE)
	m.sprint = true
	m.stick_vec = Vector2(0, -1)
	for i in 80: await tree.physics_frame
	var healthy: float = Vector2(m.body.velocity.x, m.body.velocity.z).length()
	m.rules.s["P"].hp = "hurt"
	for i in 80: await tree.physics_frame
	var hurt: float = Vector2(m.body.velocity.x, m.body.velocity.z).length()
	print("limp: healthy run=", snappedf(healthy, 0.01), " hurt run=", snappedf(hurt, 0.01),
		" anim=", m.rig.current, " roll=", snappedf(m.rig.rotation.z, 0.001))
	m.rules.s["P"].hp = "ok"
	# a long sprint, then a stop
	m.run_time = 0.0
	for i in 420: await tree.physics_frame
	print("sprinted for ", snappedf(m.run_time, 0.1), "s")
	m.stick_vec = Vector2.ZERO
	for i in 120: await tree.physics_frame
	print("stopped: tired=", snappedf(m.tired, 0.1), " anim=", m.rig.current)
	for i in 200: await tree.physics_frame
	print("recovered: tired=", snappedf(m.tired, 0.1), " anim=", m.rig.current)
	# the killer walks into view for the first time
	var k = m.remotes["K"]
	k.pos = m.body.position + Vector3(0, 0, 6.0)
	k.node.position = k.pos
	m.yaw = PI
	for i in 60: await tree.physics_frame
	print("first sight: saw killer=", m.saw_killer, " startle=", snappedf(m.startle, 0.01),
		" looking at something=", m.look_at.has("P"), " head turned=", m.rig._look != null and m.rig._look.want > 0.0)
	# a scream turns every survivor's head
	m.look_at.clear()
	m._on_event({"k": "hurt", "n": "D", "s": "hurt"})
	await frames(4)
	print("scream: heads turning=", m.look_at.size(), " (me and the other survivor)")
	tree.quit()
