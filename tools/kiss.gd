extends Node
## «Kiss»: three shakes offer it, the button appears next to a teammate, the rules heal the one kissed
## (and refuse it again too soon, or for the killer), both step in face to face, hug (hands on each
## other's back), lean in with their heads tipped, the lips meet, and they let go.
var tree: SceneTree
var bad := 0

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok: bad += 1

func _ready() -> void:
	tree = get_tree()
	# the rules alone
	var ru := Rules.new()
	ru.setup(3, 2, 2, 1, [{"name": "K", "role": "killer", "char": "killer"}, {"name": "A", "role": "survivor", "char": "survivor1"},
		{"name": "B", "role": "survivor", "char": "survivor2"}], 5)
	ru.s.B.hp = "hurt"
	var ev := ru.handle({"k": "kiss", "n": "B"}, "A")
	check(ev.size() == 1 and ev[0].k == "kiss" and ru.s.B.hp == "ok", "a kiss heals the one kissed")
	ru.s.B.hp = "hurt"
	check(ru.handle({"k": "kiss", "n": "B"}, "A").is_empty() and ru.s.B.hp == "hurt", "not again straight away")
	ru.tick(Rules.KISS_CD + 0.5)
	check(not ru.handle({"k": "kiss", "n": "B"}, "A").is_empty(), "again after %d s" % int(Rules.KISS_CD))
	check(ru.handle({"k": "kiss", "n": "A"}, "K").is_empty(), "never the killer")
	ru.s.B.hp = "down"
	ru.tick(Rules.KISS_CD + 0.5)
	check(ru.handle({"k": "kiss", "n": "B"}, "A").is_empty(), "not someone on the ground")
	# in a round
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	await frames(10)
	m._start({"map": "forest", "me": "P", "offline": true, "seed": 4242, "theme": "normal", "bot": false, "players": [
		{"name": "P", "role": "survivor", "char": "survivor1", "slot": 0},
		{"name": "D", "role": "survivor", "char": "survivor2", "slot": 1},
		{"name": "K", "role": "killer", "char": "killer", "slot": 2}]})
	for i in 1500:
		await tree.process_frame
		if m.world.ready_done: break
	await frames(30)
	m.rules.ev_at = 99999.0
	check(m.kiss != null, "the round has the kiss")
	var d = m.remotes["D"]
	var here: Vector3 = m.body.global_position
	d.pos = here + Vector3(0.9, 0, 0.6)
	d.node.global_position = d.pos
	m.rules.s["D"].hp = "hurt"
	await frames(10)
	check(m.ctx.get("interact", {}).get("kind", "") != "kiss", "no Kiss button before the shakes")
	m._kiss_ready()
	await frames(4)
	check(m.ctx.get("interact", {}).get("kind", "") == "kiss" and m.ctx.interact.n == "D", "three shakes: «Kiss» next to her")
	m._press("interact", 0)
	await frames(3)
	check(m.rules.s["D"].hp == "ok", "she is healed")
	check(m.kiss.busy("P") and m.kiss.busy("D") and m.kiss_mode == 0.0, "the two of them are in the kiss")
	var me: CharacterRig = m.rig
	var her: CharacterRig = d.rig
	var mid_reach := 0.0
	var faced := 0.0
	var amt := 0.0
	var froze := true
	var t0 := Time.get_ticks_msec()
	while m.kiss.busy("P") and Time.get_ticks_msec() - t0 < 9000:
		await tree.process_frame
		var x: Dictionary = m.kiss.now.values()[0] if m.kiss.now.size() > 0 else {}
		if x.is_empty(): break
		if float(x.t) > 1.6 and float(x.t) < 3.4:
			amt = maxf(amt, float(m.kiss.mods[me.get_instance_id()].amt))
			# my hands on her back, hers on mine: how far the IK left the wrists from those points
			mid_reach = maxf(mid_reach, maxf(me.reach_mod.miss if me.reach_mod else 9.0, her.reach_mod.miss if her.reach_mod else 9.0))
			faced = maxf(faced, absf(wrapf(me.rotation.y - her.rotation.y - PI, -PI, PI)))
	print("    closest lips %.3f m, hands to her back %.2f m, lean %.2f" % [m.kiss.closest, mid_reach, amt])
	check(m.kiss.closest < 0.07, "their lips meet (%.3f m)" % m.kiss.closest)
	check(mid_reach < 0.12, "arms round each other (wrists within %.2f m of the other's back)" % mid_reach)
	check(amt > 0.95, "leaning in, heads tipped")
	check(faced < 0.2, "face to face")
	check(not m.kiss.busy("P") and m.kiss.now.is_empty(), "and they let go")
	check(m.ctx.get("interact", {}).get("kind", "") != "kiss", "the button is gone until the next shakes")
	print("KISS %s %d" % ["PASS" if bad == 0 else "FAIL", bad])
	get_tree().quit(1 if bad else 0)
