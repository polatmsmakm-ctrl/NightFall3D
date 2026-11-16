extends Node
## Headless check of the start screen: the camp dressed for every map, the stalking killer, online
## friends at the fire and a tap on one, the blood moon, the hook, the card and the daily line.

func frames(n: int) -> void:
	for i in n: await get_tree().process_frame

func _ready() -> void:
	Net.username = "راشد"
	Net.friends = ["بدر", "فهد"]
	Net.online = {"بدر": true}
	Net.last_round = {"res": "dead", "score": 120, "gens": 3, "wipe": true}
	Net.last_char = "survivor5"
	var m = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(m)
	await frames(12)
	var lob: NFLobby = m.lobby_scene
	Net.online = {"بدر": true} # Net clears it while it fails to reach a server here
	m.menu.open("main")
	await frames(4)
	print("stands at the fire: ", lob.me_char, " (last played survivor5)")
	print("friends at the fire: ", lob.cast.keys(), "  stock hidden=", not lob.stock[0].visible)
	print("blood moon=", lob.blood, " hook=", lob.hook_arm != null, " daily=", Net.daily())
	print("card title=", Net.title(), " logo=", m.menu._logo_tex != null, " poster=", m.menu.poster != null)
	for id in ["forest", "village", "fareej", "rubkhali", "garage", "beach"]:
		lob.set_map(id)
		await frames(2)
		print("camp as ", id, ": dressing nodes=", lob._dress.get_child_count(), " trees=", lob._trees[0].visible)
	lob.set_map("forest")
	var seen := 0
	var spots := {}
	for i in 400: # the stalker: gone, back, and never in the same place for long
		lob._tick_stalker(0.1)
		if lob.stalker.visible: seen += 1
		spots[lob._stalk_i] = true
	print("stalker visible ", seen, "/400 ticks, spots used=", spots.size())
	if not lob.cast.has("بدر"):
		push_error("CAMP FAIL: the online friend is not at the fire")
		get_tree().quit(1)
		return
	var at: Vector2 = lob.cam.unproject_position(lob.cast["بدر"].rig.global_position + Vector3(0, 1.0, 0))
	print("tap on بدر picks: ", lob.pick(at), "   tap on empty sky picks: '", lob.pick(Vector2(5, 5)), "'")
	for e in 3:
		lob.emote("", e)
		await frames(3)
		print("emote ", NFLobby.EMOTES[e], ": playing=", lob.me_rig.current, " length=", lob.me_rig.player.get_animation(NFLobby.EMOTES[e]).length)
	Net.room = {"code": "4821", "host": "راشد", "map": "beach", "state": "lobby", "players": [
		{"name": "راشد", "role": "survivor", "char": "survivor2"}, {"name": "فهد", "role": "killer", "char": "killer"}]}
	m.menu.open("lobby")
	await frames(4)
	lob._tick_stalker(1.0)
	print("in a room on the beach: camp=", lob.map_id, " stalker hidden (a player is the killer)=", not lob.stalker.visible)
	var e0: float = m.world.env.tonemap_exposure if m.world else 0.0
	Gfx.brightness = 1.4
	Gfx.look_changed.emit()
	print("brightness 140%: camp exposure=", lob.env.tonemap_exposure)
	Gfx.brightness = 1.0
	print("camp check done")
	get_tree().quit()
