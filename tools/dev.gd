extends Node
## Headless checks for the volume buses and the hidden developer tools.

var tree: SceneTree

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func _ready() -> void:
	tree = get_tree()
	# ---------- audio buses ----------
	var mi := AudioServer.get_bus_index(Aud.MUSIC)
	var si := AudioServer.get_bus_index(Aud.SFX)
	print("buses: music=", mi, " sfx=", si, " master sends=", AudioServer.get_bus_send(mi), "/", AudioServer.get_bus_send(si))
	Aud.set_vol("master", 1.0); Aud.set_vol("music", 0.5); Aud.set_vol("sfx", 0.25)
	print("volumes: master=", snappedf(AudioServer.get_bus_volume_db(0), 0.1), "dB music=",
		snappedf(AudioServer.get_bus_volume_db(mi), 0.1), "dB sfx=", snappedf(AudioServer.get_bus_volume_db(si), 0.1), "dB")
	Aud.set_vol("master", 0.0)
	print("master at 0: muted=", AudioServer.is_bus_mute(0))
	Aud.set_vol("master", 0.8)
	Aud.save()
	var c := ConfigFile.new()
	c.load(Aud.PATH)
	print("saved: master=", c.get_value("a", "master"), " music=", c.get_value("a", "music"), " sfx=", c.get_value("a", "sfx"))
	# ---------- every sound sits on a bus ----------
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(10)
	var lobby_buses := {}
	for a in m.lobby_scene.find_children("*", "AudioStreamPlayer", true, false): lobby_buses[a.bus] = true
	print("campfire screen buses: ", lobby_buses.keys())
	m._start({"map": "forest", "me": "P", "offline": true, "players": [
		{"name": "P", "role": "survivor", "char": "survivor2", "slot": 0},
		{"name": "K", "role": "killer", "char": "killer", "slot": 1},
		{"name": "D", "role": "survivor", "char": "survivor4", "slot": 2}]})
	for i in 400:
		await tree.process_frame
		if m.world.ready_done: break
	await frames(8)
	print("music: ambient=", m.amb.bus, " chase=", m.chase_music.bus, " doom=", m.doom_music.bus)
	print("game: heart=", m.heart.bus, " breath=", m.breath.bus, " steps=", m.my_steps.bus,
		" generator=", m.gen_audio[0].bus, " other player's steps=", m.remotes["K"].steps.bus)
	m._sfx("rope", Vector3(1, 1, 1), 0.0)
	await frames(2)
	var one_shot := ""
	for a in m.find_children("*", "AudioStreamPlayer3D", false, false):
		if a.stream == m.sounds.rope: one_shot = a.bus
	print("one-shot (rope) bus=", one_shot)
	# ---------- the tools stay locked ----------
	print("locked: dot=", m.dev_dot, " esp nodes=", m.esp_nodes.size())
	var walk_locked: float = m.WALK.survivor
	# 14 taps do nothing, the 15th opens it
	Dev.unlocked = false
	var opened := false
	for i in 14: opened = Dev.tap() or opened
	print("after 14 taps: unlocked=", Dev.unlocked, " opened=", opened)
	opened = Dev.tap()
	print("after the 15th: unlocked=", Dev.unlocked, " opens the page=", opened)
	var cfg := ConfigFile.new()
	cfg.load(Dev.PATH)
	print("remembered on this phone only: ", cfg.get_value("d", "on"))
	# slow taps never add up
	Dev.unlocked = false
	Dev._taps = 0
	for i in 20:
		Dev._last = -99.0 # pretend a long pause before each tap
		Dev.tap()
	print("slow taps: unlocked=", Dev.unlocked)
	Dev.unlocked = true
	# ---------- ESP ----------
	Dev.set_esp(true)
	await frames(6)
	var k: Dictionary = m.esp_nodes["K"]
	var mesh_count: int = k.meshes.size()
	var with_overlay := 0
	for mi2 in k.meshes:
		if mi2.material_overlay != null: with_overlay += 1
	print("esp on: players marked=", m.esp_nodes.size(), " meshes=", mesh_count, " overlaid=", with_overlay,
		" no depth test=", k.mat.no_depth_test, " mast visible=", k.mark.visible, " tag=", k.label.text)
	m.remotes["K"].node.position = m.body.position + Vector3(12, 0, 9)
	await frames(6)
	print("tag follows: ", k.label.text, " mast at=", k.mark.position.snapped(Vector3(1, 1, 1)))
	Dev.set_esp(false)
	await frames(6)
	with_overlay = 0
	for mi3 in k.meshes:
		if mi3.material_overlay != null: with_overlay += 1
	print("esp off: overlaid=", with_overlay, " mast visible=", k.mark.visible)
	# ---------- speed ----------
	Dev.set_speed(1.75)
	m.sprint = true
	m.stick_vec = Vector2(0, -1)
	for i in 70: await tree.physics_frame
	var fast: float = Vector2(m.body.velocity.x, m.body.velocity.z).length()
	Dev.set_speed(1.0)
	for i in 70: await tree.physics_frame
	var normal: float = Vector2(m.body.velocity.x, m.body.velocity.z).length()
	m.stick_vec = Vector2.ZERO
	print("run speed: normal=", snappedf(normal, 0.01), " boosted=", snappedf(fast, 0.01),
		" ratio=", snappedf(fast / maxf(normal, 0.01), 0.01))
	print("survivor walk=", walk_locked, " run=", m.RUN.survivor, " killer=", m.RUN.killer,
		" (killer still faster=", m.RUN.killer > m.RUN.survivor, ")")
	tree.quit()
