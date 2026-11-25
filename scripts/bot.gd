class_name NFBot
extends Node
## The killer in trial mode when nobody plays her: she patrols the generators being worked on,
## sees you within 30 m (in front of her, with nothing in between) or hears you within 10 m,
## chases, swings, picks up whoever is down and carries them to the nearest free hook. She breaks
## dropped pallets and opens shut doors that are in her way, searches a locker she saw you go into,
## and goes to a generator that blew up or a trap that shut. She is stunned by a pallet dropped on her.
## Her inputs go through the same Rules as a player's, so nothing in the round is faked.
##
## She walks a navigation mesh baked from the map's colliders when the round starts (on a thread);
## until it is ready, and out on the escape roads (beyond the map), she steers straight at her goal.

const RUN := 4.6        # a player killer's speed
const WALK := 3.3       # patrolling
const CARRY := 3.6
const SEE := 30.0
const HEAR := 10.0
const REACH := 2.1
const CONE := 0.34      # cos of half her field of view (~140 degrees)

var m                   # the game scene (scripts/main.gd)
var k := ""             # her name in the round
var body: CharacterBody3D
var nav_ok := false
var nav_map: RID
var path := PackedVector3Array()
var path_i := 0
var repath := 0.0
var state := "patrol"   # patrol, chase, fetch, carry
var target := ""
var goal := Vector3.INF
var last_seen := Vector3.INF
var lost := 0.0
var linger := 0.0
var think := 0.0
var swing := 0.0        # > 0: the swing is coming
var cd := 0.0           # after a swing
var slow := 0.0         # the wipe after a hit
var pause := 0.0        # breaking a pallet, opening a door
var sidestep := 0.0
var side_dir := Vector3.ZERO
var stuck := 0.0
var last_pos := Vector3.ZERO
var face := 0.0
var anim := "idle"
var hooks_done := 0     # for the tests
var hits := 0

func setup(main, name: String, at: Vector3) -> void:
	m = main
	k = name
	body = CharacterBody3D.new()
	body.name = "BotKiller"
	body.collision_layer = 1 << 9 # her own layer: players and rays do not bump into her
	body.collision_mask = 1 | NightWorld.SN_EDGE # (the sniper tower's roof edge)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	body.add_child(cs)
	body.floor_snap_length = 0.6
	body.floor_max_angle = deg_to_rad(48.0)
	add_child(body)
	body.global_position = at + Vector3(0, 0.3, 0)
	last_pos = body.global_position

## Bake the walkable area of the map once the world has built itself (call after build()).
func bake() -> void:
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.55
	nm.agent_max_slope = 42.0
	nm.cell_size = 0.4
	nm.cell_height = 0.25
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	var h := NightWorld.HALF + 2.0
	nm.filter_baking_aabb = AABB(Vector3(-h, -15.0, -h), Vector3(h * 2.0, 45.0, h * 2.0))
	nav_map = m.world.get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(nav_map, nm.cell_size)
	NavigationServer3D.map_set_cell_height(nav_map, nm.cell_height)
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, m.world)
	NavigationServer3D.bake_from_source_geometry_data_async(nm, src, func() -> void: _baked.call_deferred(nm))

func _baked(nm: NavigationMesh) -> void:
	if not is_inside_tree(): return
	var reg := NavigationRegion3D.new()
	reg.navigation_mesh = nm
	m.world.add_child(reg)
	await get_tree().physics_frame
	await get_tree().physics_frame
	nav_ok = nm.get_polygon_count() > 0

func pos() -> Vector3:
	return body.global_position

## Everything the rules say happened, so she can react to it (main calls this for every event).
func on_event(e: Dictionary) -> void:
	match str(e.get("k", "")):
		"boom": # a generator blew up: she heard it
			if state == "patrol" and int(e.i) < m.world.gen_points.size(): _go(m.world.gen_points[int(e.i)])
		"snap": # one of her traps
			if state != "carry": _go(m._pos_of(str(e.n)))
		"pallet": # dropped on her?
			var i := int(e.i)
			if i < m.world.pallet_points.size():
				var pp: Vector3 = m.world.pallet_points[i][0]
				if _flat(pp).distance_to(_flat(pos())) < 2.4 and m.rules.stun <= 0.0:
					m.rules.stun = Rules.STUN_TIME
					m._on_event({"k": "stun"})

func _go(at: Vector3) -> void:
	goal = at
	linger = 0.0
	repath = 0.0

func _act(d: Dictionary) -> void:
	for e in m.rules.handle(d, k): m._on_event(e)

static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)

func step(dt: float) -> void:
	var r = m.remotes.get(k)
	if r == null or m.rules == null: return
	cd = maxf(cd - dt, 0.0)
	slow = maxf(slow - dt, 0.0)
	pause = maxf(pause - dt, 0.0)
	sidestep = maxf(sidestep - dt, 0.0)
	var vel := Vector3.ZERO
	if m.rules.sniper: # «وضع القنّاص»: up the stairs to the rifle, then down on the roof and shooting
		vel = _sniper(dt)
	elif m.rules.over or m.rules.stun > 0.0 or pause > 0.0:
		anim = "attack" if pause > 0.0 else "idle"
	else:
		think -= dt
		if think <= 0.0:
			think = 0.2
			_think()
		vel = _steer(dt)
		if swing > 0.0:
			swing -= dt
			anim = "attack"
			if swing <= 0.0: _land()
		elif vel.length() > 0.2:
			anim = "carry" if m.rules.carrying != "" else ("run" if vel.length() > 3.6 else "walk")
		else:
			anim = "carry" if m.rules.carrying != "" else "idle"
	body.velocity.x = vel.x
	body.velocity.z = vel.z
	body.velocity.y = -2.0 if body.is_on_floor() else body.velocity.y - 22.0 * dt
	body.move_and_slide()
	if Vector2(vel.x, vel.z).length() > 0.2:
		face = lerp_angle(face, atan2(vel.x, vel.z), 1.0 - exp(-10.0 * dt))
	_unstick(dt, vel)
	r.pos = pos()
	r.yaw = face
	r.anim = anim
	r.node.position = pos() # no easing: she is right here on this phone

## Pick what she is doing: carry to a hook, pick up, chase, fetch the fallen, or patrol.
func _think() -> void:
	var me := pos()
	var rules: Rules = m.rules
	if rules.carrying != "":
		state = "carry"
		var hi := _free_hook(me)
		if hi < 0: return
		goal = m.world.hook_points[hi]
		if _flat(goal).distance_to(_flat(me)) < 2.4 and absf(goal.y - me.y) < 2.5:
			_act({"k": "hook", "i": hi})
			hooks_done += 1
			cd = 1.2
			state = "patrol"
			goal = Vector3.INF
		return
	for n in rules.s: # someone down right at her feet: up they go
		if rules.hp(n) == "down" and m._pos_of(n).distance_to(me) < 1.9 and cd <= 0.0:
			_act({"k": "pickup", "n": n})
			if rules.carrying != "": return
	var seen := _look()
	if seen != "":
		target = seen
		last_seen = m._pos_of(seen)
		lost = 0.0
		state = "chase"
	elif state == "chase":
		lost += 0.2
		if not rules.s.has(target) or not (rules.hp(target) in ["ok", "hurt"]) or lost > 7.0: state = "patrol"
	if state == "chase":
		var lk: int = int(rules.s[target].locker) if rules.s.has(target) else -1
		if lk >= 0 and lk < m.world.locker_points.size(): # she saw them get in
			var lp: Vector3 = m.world.locker_points[lk][0]
			goal = lp
			if _flat(lp).distance_to(_flat(me)) < 2.2:
				_act({"k": "search", "i": lk})
				state = "patrol"
		else:
			goal = m._pos_of(target) if seen != "" else last_seen
			if seen == "" and _flat(goal).distance_to(_flat(me)) < 1.5: lost += 1.0 # nobody here
		return
	# the fallen, wherever she knows they are
	var best := INF
	for n in rules.s:
		if rules.hp(n) == "down":
			var d: float = (m._pos_of(n) as Vector3).distance_to(me)
			if d < best:
				best = d
				goal = m._pos_of(n)
				state = "fetch"
	if best < INF: return
	state = "patrol"
	if goal == Vector3.INF or _flat(goal).distance_to(_flat(me)) < 2.6:
		linger -= 0.2
		if linger <= 0.0:
			goal = _patrol_point(me)
			linger = 1.5

## The nearest survivor she can see or hear, "" for none.
func _look() -> String:
	var me := pos()
	var fwd := Vector3(sin(face), 0, cos(face))
	var best := ""
	var bd := INF
	for n in m.rules.s:
		if not m.rules.free_now(n): continue
		if n == m.my_name and m.vanished: continue # «Vanish»: she cannot see me either
		var p: Vector3 = m._pos_of(n)
		var to := p - me
		var d := to.length()
		if d > SEE or d >= bd: continue
		var ok := d < HEAR and absf(to.y) < 3.0
		if not ok and fwd.dot(Vector3(to.x, 0, to.z).normalized()) > CONE: ok = _clear(me + Vector3(0, 1.6, 0), p + Vector3(0, 1.2, 0))
		if ok:
			best = n
			bd = d
	return best

func _clear(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	q.exclude = [body.get_rid(), m.body.get_rid()]
	return body.get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _free_hook(me: Vector3) -> int:
	var best := -1
	var bd := INF
	var on_road: bool = m.world.road_at(me) >= 0
	for i in m.world.hook_points.size():
		if m.rules.hook_user(i) != "": continue
		if not on_road and i >= m.world.road_hook0: continue # the road hooks only when she is out there
		var d: float = (m.world.hook_points[i] as Vector3).distance_to(me)
		if d < bd:
			bd = d
			best = i
	return best

## Where to look next: a generator someone is working on, one with progress, any one; once the
## gates have power, the gates.
func _patrol_point(me: Vector3) -> Vector3:
	var w = m.world
	var rules: Rules = m.rules
	if rules.powered:
		var g: Array = w.gate_points[randi() % w.gate_points.size()]
		return (g[0] as Vector3) + Basis(Vector3.UP, float(g[1])) * Vector3(0, 0, 6.0)
	var busy := []
	var started := []
	for i in rules.gens.size():
		if rules.gens[i].done: continue
		if not rules.gens[i].reps.is_empty(): busy.append(i)
		elif rules.gens[i].p > 0.0: started.append(i)
	var pick := -1
	if not busy.is_empty(): pick = busy[randi() % busy.size()]
	elif not started.is_empty() and randf() < 0.6: pick = started[randi() % started.size()]
	else: pick = randi() % w.gen_points.size()
	var gp: Vector3 = w.gen_points[pick]
	return gp + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))

## The velocity she wants this step: along the baked path, or straight at a close target.
func _steer(dt: float) -> Vector3:
	if goal == Vector3.INF: return Vector3.ZERO
	var me := pos()
	var speed := RUN if state in ["chase", "fetch"] else (CARRY if state == "carry" else WALK)
	if slow > 0.0: speed *= 0.4
	var dir := Vector3.ZERO
	var tp: Vector3 = m._pos_of(target) if (state == "chase" and target != "") else goal
	var close: bool = state == "chase" and lost <= 0.0 and _flat(tp).distance_to(_flat(me)) < 5.0
	if state == "chase" and lost <= 0.0 and target != "" and m.rules.free_now(target):
		var d := _flat(tp).distance_to(_flat(me))
		if d < REACH and cd <= 0.0 and swing <= 0.0:
			swing = 0.35 # wind up
	if sidestep > 0.0:
		dir = side_dir
	elif close or not nav_ok or not _inside(me) or not _inside(goal):
		dir = tp - me
	else:
		repath -= dt
		if repath <= 0.0 or path_i >= path.size():
			path = NavigationServer3D.map_get_path(nav_map, me, goal, true)
			path_i = 0
			repath = 0.35 if state == "chase" else 1.4
		while path_i < path.size() and _flat(path[path_i]).distance_to(_flat(me)) < 0.7: path_i += 1
		dir = (path[path_i] - me) if path_i < path.size() else (goal - me)
	dir.y = 0.0
	if dir.length() < 0.15: return Vector3.ZERO
	if swing > 0.0: speed *= 0.6
	return dir.normalized() * speed

func _inside(p: Vector3) -> bool:
	return absf(p.x) < NightWorld.HALF and absf(p.z) < NightWorld.HALF

## The swing lands: a hit if they are still in reach.
func _land() -> void:
	if target == "" or not m.rules.free_now(target):
		cd = 1.0
		return
	var tp: Vector3 = m._pos_of(target)
	if _flat(tp).distance_to(_flat(pos())) < REACH + 0.6 and absf(tp.y - pos().y) < 1.8:
		_act({"k": "hit", "n": target})
		hits += 1
		cd = 2.2
		slow = 1.5
	else: cd = 1.0

## Not getting anywhere: a dropped pallet in the way gets broken, a shut door opened, otherwise
## a step to one side and a fresh path.
func _unstick(dt: float, vel: Vector3) -> void:
	if vel.length() < 0.5 or pause > 0.0:
		stuck = 0.0
		last_pos = pos()
		return
	stuck += dt
	if stuck < 0.9: return
	var moved := _flat(pos()).distance_to(_flat(last_pos))
	stuck = 0.0
	last_pos = pos()
	if moved > 0.6: return
	var me := pos()
	var rules: Rules = m.rules
	for i in rules.pallets.size():
		if rules.pallets[i] == 1 and _flat(m.world.pallet_points[i][0]).distance_to(_flat(me)) < 3.2:
			_act({"k": "break", "i": i})
			pause = 2.0
			return
	for i in rules.doors.size():
		if rules.doors[i] and _flat(m.world.door_points[i][0]).distance_to(_flat(me)) < 3.2:
			_act({"k": "door", "i": i, "on": false})
			pause = 0.6
			return
	side_dir = Vector3(-vel.z, 0, vel.x).normalized() * (1.0 if randf() < 0.5 else -1.0)
	sidestep = 0.6
	repath = 0.0


# ---------------- «وضع القنّاص» ----------------
## She walks to the stairs (the navigation mesh runs up both flights), climbs to the roof, takes the
## rifle and lies down along the front of the roof, crawling slowly from one side to the other.
## Every few seconds she picks the nearest survivor she has a clear line to and fires: the further
## away, the likelier she misses (a miss lands near them, and they hear it).
var sn_state := "go"
var sn_t := 0.0
var sn_cd := 3.0
var shots := 0          # (tests)

func _sniper(dt: float) -> Vector3:
	var w = m.world
	var me := pos()
	if m.rules.over:
		anim = "crawl" if sn_state == "aim" else "idle"
		return Vector3.ZERO
	if sn_state == "go":
		goal = w.snipe_rifle
		state = "patrol"
		if _flat(me).distance_to(_flat(w.snipe_rifle)) < 1.8 and me.y > NightWorld.SN_H - 1.0:
			sn_state = "aim"
			return Vector3.ZERO
		var vel := _steer(dt)
		if w.on_stairs(me): vel = vel.limit_length(2.2)
		anim = "climb" if (w.on_stairs(me) and vel.length() > 0.2) else ("walk" if vel.length() > 0.2 else "idle")
		return vel
	# lying on the roof with the rifle
	sn_t += dt
	var want := Vector3(sin(sn_t * 0.07) * 11.0, me.y, NightWorld.SN_FACE + 1.3)
	var d := want - me
	d.y = 0.0
	var vel2 := d.limit_length(0.8) if d.length() > 0.3 else Vector3.ZERO
	anim = "crawl" # (lying still: other phones freeze the crawl when she does not move)
	var tgt := ""
	var td := INF
	var muzzle := me + Vector3(0, 0.5, 0)
	for n in m.rules.s:
		if not m.rules.free_now(n): continue
		if n == m.my_name and m.vanished: continue
		var p: Vector3 = m._pos_of(n) + Vector3(0, 1.1, 0)
		var dd := p.distance_to(muzzle)
		if dd < td and dd < 230.0 and _clear(muzzle, p):
			tgt = n
			td = dd
	if tgt != "":
		var tp: Vector3 = m._pos_of(tgt)
		face = lerp_angle(face, atan2(tp.x - me.x, tp.z - me.z), 1.0 - exp(-4.0 * dt))
	sn_cd -= dt
	if sn_cd <= 0.0 and tgt != "":
		sn_cd = randf_range(2.6, 4.8)
		shots += 1
		var chest: Vector3 = m._pos_of(tgt) + Vector3(0, 1.15, 0)
		var hit := randf() < clampf(0.6 - td / 450.0, 0.15, 0.6)
		var at := chest if hit else chest + Vector3(randf_range(-1.6, 1.6), randf_range(-1.0, 0.4), randf_range(-1.6, 1.6))
		_act({"k": "snipe", "n": tgt if hit else "", "p": [at.x, at.y, at.z]})
	return vel2
