class_name NFCatDog
extends Node3D
## The cat and the dog (the owner's scenario, his two Meshy models rigged by tools/rig_animal.py and
## posed in code by NFAnimal). Once a round, on every phone alike:
##
##   1. the first generator anyone starts repairing brings a cat in from the dark: it walks round the
##      people at it, sits, washes, crouches and pounces, bats the air, meows;
##   2. when that generator is done, the cat sits a little way off and a dog comes in slowly, low, from
##      the far side; it stops, barks and runs at it; the cat turns too late; the dog bites, shakes it
##      side to side (the owner's blood: drops, the wall, a pool), swallows it and runs off into the dark.
##
## No network message of its own: it starts from the generators in the round's state (the snapshot
## every phone gets), and every place and choice comes from the map's seed and the generator's number,
## so all the phones play the same thing within the snapshot's few hundred milliseconds.

const DOG_MOUTH := Vector3(0.0, 0.665, 0.63) # between the dog's teeth, in its model's rest space
const CAT_R := 2.3           # how far round the generator the cat walks
const SPOT_R := 2.8          # where it sits when the dog comes
const DEN_R := 15.0          # where the dog comes from
const STALK := 0.75          # the dog's slow approach (m/s)
const SPRINT := 7.5
const FREEZE_AT := 6.5       # how near the dog creeps before it stops
const SHAKE_TIME := 2.4
const SWALLOW_TIME := 3.2
const RUN_TIME := 5.0

var world: NightWorld
var rules: Rules
var blood: NFBlood
var cam := Callable()        # -> Vector3, the camera (blood near it is flown, far is laid)
var people := Callable()     # -> Array of Vector3, the survivors (the cat looks at the nearest)
var skip: Array = []         # RIDs the rays ignore (my own body)
var cat: NFAnimal
var dog: NFAnimal
var state := 0               # 0 waiting for a repair, 1 the cat, 2 the dog, 3 over
var gen := -1
var gp := Vector3.ZERO
var rng := RandomNumberGenerator.new()
var t := 0.0
# the cat's play
var act := ""
var act_t := 0.0
var act_len := 0.0
var ang := 0.0
var ang_to := 0.0
var rad := CAT_R
var rad_to := CAT_R
var meow_t := 2.5
var jaw_t := 0.0
var pounce_from := Vector3.ZERO
# the dog
var spot := Vector3.ZERO
var den := Vector3.ZERO
var ph := 0                  # 0 stalking, 1 frozen, 2 sprint, 3 shaking, 4 swallowing, 5 running, 6 gone
var ph_t := 0.0
var splash_t := 0.0
var away := Vector3.ZERO
var feared := false
var bark_stop := 0.0
var eat_stop := 0.0
# for the tests
var bites := 0
var splashes := 0
var meows := 0
var barks := 0
var acts := {}
var cat_snd: AudioStreamPlayer3D
var dog_snd: AudioStreamPlayer3D
var meow_s: Array = []
var bark_s: AudioStream
var eat_s: AudioStream

func setup(w: NightWorld, r: Rules, b: NFBlood, cam_cb: Callable, people_cb: Callable, skip_rids: Array) -> void:
	world = w
	rules = r
	blood = b
	cam = cam_cb
	people = people_cb
	skip = skip_rids
	cat = NFAnimal.new()
	cat.name = "Cat"
	add_child(cat)
	dog = NFAnimal.new()
	dog.name = "Dog"
	add_child(dog)
	if not cat.setup("cat") or not dog.setup("dog"):
		state = 3
		return
	cat.visible = false
	dog.visible = false
	cat_snd = _snd(cat, 5.0)
	dog_snd = _snd(dog, 9.0)
	for i in 6:
		var p := "res://assets/sfx/meow%d.ogg" % i
		if ResourceLoader.exists(p): meow_s.append(load(p))
	if ResourceLoader.exists("res://assets/sfx/dog_bark.ogg"): bark_s = load("res://assets/sfx/dog_bark.ogg")
	if ResourceLoader.exists("res://assets/sfx/dog_eat.ogg"): eat_s = load("res://assets/sfx/dog_eat.ogg")
	for g in rules.gens: # joined after the first generator was done: it has happened already
		if g.done: state = 3

func _snd(n: Node3D, unit: float) -> AudioStreamPlayer3D:
	var s := AudioStreamPlayer3D.new()
	s.bus = Aud.SFX
	s.unit_size = unit
	s.max_distance = 70.0
	s.position = Vector3(0, 0.3, 0.3)
	n.add_child(s)
	return s

func _dir(a: float) -> Vector3:
	return Vector3(sin(a), 0.0, cos(a))

func _ray(a: Vector3, b: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1, skip)
	return get_world_3d().direct_space_state.intersect_ray(q)

## Nothing in the way, a hand's height above the ground.
func _clear(a: Vector3, b: Vector3) -> bool:
	var up := Vector3(0, 0.35, 0)
	return _ray(a + up, b + up).is_empty()

func _ground(p: Vector3, fallback: float) -> float:
	var h := _ray(p + Vector3(0, 0.6, 0), p - Vector3(0, 2.5, 0))
	if h.is_empty(): h = _ray(p + Vector3(0, 3.0, 0), p - Vector3(0, 5.0, 0))
	return (h.position as Vector3).y if not h.is_empty() else fallback

## Pick the first clear direction from `from`, trying `a0` and then either side of it.
func _clear_spot(from: Vector3, a0: float, dist: float, short: float) -> Vector3:
	for k in 9:
		var a := a0 + (0.7 * ceilf(k / 2.0) * (1.0 if k % 2 == 1 else -1.0))
		var to := from + _dir(a) * dist
		if _clear(from + _dir(a) * 1.4, to): return to
	return from + _dir(a0) * short

## Walk an animal toward a point: turning as it goes, its legs told the speed it really moved at.
func _go(a: NFAnimal, to: Vector3, spd: float, dt: float, turn := 6.0, lift := 0.0) -> float:
	var d := Vector3(to.x - a.position.x, 0.0, to.z - a.position.z)
	var dist := d.length()
	var v := 0.0
	if dist > 0.02 and dt > 0.0:
		a.rotation.y = lerp_angle(a.rotation.y, atan2(d.x, d.z), 1.0 - exp(-turn * dt))
		var fwd := _dir(a.rotation.y)
		var align := clampf(fwd.dot(d / dist), 0.0, 1.0)
		v = minf(spd * (0.25 + 0.75 * align), dist / dt)
		a.position += d / dist * v * dt
	a.speed = lerpf(a.speed, v, 1.0 - exp(-8.0 * dt))
	var gy := _ground(a.position, a.position.y)
	a.position.y = lerpf(a.position.y, gy + lift, 1.0 - exp(-14.0 * dt))
	return dist

func _turn_to(a: NFAnimal, p: Vector3, dt: float, rate := 4.0) -> void:
	var d := p - a.position
	a.rotation.y = lerp_angle(a.rotation.y, atan2(d.x, d.z), 1.0 - exp(-rate * dt))

func _look_at(a: NFAnimal, p: Vector3) -> void:
	var d := p - (a.position + Vector3(0, 0.3 if a.kind == "cat" else 0.75, 0))
	var yaw := wrapf(atan2(d.x, d.z) - a.rotation.y, -PI, PI)
	a.look = Vector2(clampf(yaw, -1.0, 1.0), clampf(atan2(d.y, Vector2(d.x, d.z).length()), -0.5, 0.6))

func _meow(pitch := 1.0) -> void:
	if meow_s.is_empty(): return
	cat_snd.stream = meow_s[randi() % meow_s.size()]
	cat_snd.pitch_scale = pitch * randf_range(0.94, 1.08)
	cat_snd.play()
	jaw_t = 0.5
	meows += 1

func _process(dt: float) -> void:
	if state == 3 or rules == null: return
	t += dt
	match state:
		0:
			for i in rules.gens.size():
				var g: Dictionary = rules.gens[i]
				if g.done: # nobody saw a repair start (a late join): let it be
					state = 3
					return
				if float(g.p) > 0.0:
					_start_cat(i)
					break
		1:
			if bool(rules.gens[gen].done): _start_dog()
			else: _cat_step(dt)
		2:
			_dog_step(dt)
	if state == 3: return
	var c: Vector3 = cam.call() if cam.is_valid() else Vector3.INF
	# the dog first: the cat may be hanging from its mouth
	if dog.visible and (c == Vector3.INF or c.distance_to(dog.global_position) < 70.0): dog.pose(dt)
	if ph >= 3 and ph <= 4 and state == 2: _hold_cat()
	if cat.visible and (c == Vector3.INF or c.distance_to(cat.global_position) < 60.0): cat.pose(dt)
	if bark_stop > 0.0:
		bark_stop -= dt
		if bark_stop <= 0.0: dog_snd.stop()
	if eat_stop > 0.0:
		eat_stop -= dt
		dog_snd.volume_db = linear_to_db(clampf(eat_stop / 0.6, 0.001, 1.0)) if eat_stop < 0.6 else 0.0
		if eat_stop <= 0.0:
			dog_snd.stop()
			dog_snd.volume_db = 0.0

# ---- the cat -------------------------------------------------------------------------------------

func _start_cat(i: int) -> void:
	state = 1
	gen = i
	gp = world.gen_points[i]
	rng.seed = world.layout_seed * 7919 + i * 131 + 17
	ang = rng.randf() * TAU
	var from := _clear_spot(gp, ang, 9.0, 4.0)
	ang = atan2(from.x - gp.x, from.z - gp.z)
	cat.position = Vector3(from.x, _ground(Vector3(from.x, gp.y, from.z), gp.y), from.z)
	cat.rotation.y = atan2(gp.x - from.x, gp.z - from.z)
	cat.visible = true
	act = "come"
	act_t = 0.0
	rad = CAT_R
	rad_to = CAT_R
	meow_t = 1.5

func _next_act() -> void:
	act_t = 0.0
	var r := rng.randf()
	if r < 0.36:
		act = "circle"
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		ang_to = ang + side * rng.randf_range(0.9, 2.2)
		rad_to = rng.randf_range(1.6, 2.9)
		if not _clear(cat.position, gp + _dir((ang + ang_to) * 0.5) * rad_to):
			ang_to = ang - (ang_to - ang)
			if not _clear(cat.position, gp + _dir((ang + ang_to) * 0.5) * rad_to): act = "sit"
	elif r < 0.6: act = "sit"
	elif r < 0.82: act = "play"
	else: act = "groom"
	act_len = {"circle": 99.0, "sit": rng.randf_range(3.0, 6.0), "play": 3.4, "groom": rng.randf_range(3.0, 5.0)}[act]
	pounce_from = cat.position
	acts[act] = int(acts.get(act, 0)) + 1

func _nearest_person() -> Vector3:
	var best := gp + Vector3(0, 0.8, 0)
	var bd := 4.5
	if people.is_valid():
		for p in people.call():
			var d: float = (p as Vector3).distance_to(gp)
			if d < bd:
				bd = d
				best = (p as Vector3) + Vector3(0, 1.2, 0)
	return best

func _cat_step(dt: float) -> void:
	act_t += dt
	jaw_t = maxf(jaw_t - dt, 0.0)
	cat.jaw = sin(clampf(jaw_t / 0.5, 0.0, 1.0) * PI) * 0.8
	cat.look = Vector2.ZERO
	match act:
		"come":
			cat.wag = 0.35
			if _go(cat, gp + _dir(ang) * rad, 0.6, dt) < 0.15: _next_act()
		"circle":
			cat.wag = 0.35
			rad = move_toward(rad, rad_to, dt * 0.4)
			ang = move_toward(ang, ang_to, dt * 0.48 / rad)
			_go(cat, gp + _dir(ang) * rad, 0.5, dt)
			if absf(ang - ang_to) < 0.01: _next_act()
		"sit", "groom":
			cat.wag = 0.2
			_go(cat, cat.position, 0.0, dt)
			var up := act_t < act_len
			cat.sit = move_toward(cat.sit, 1.0 if up else 0.0, dt * 1.6)
			if act == "sit":
				_turn_to(cat, gp, dt, 1.5)
				_look_at(cat, _nearest_person())
			else: # washing: the head down to the chest, bobbing
				cat.look = Vector2(0.25 * sin(act_t * 1.3), -0.5 + 0.12 * sin(act_t * 9.0))
				cat.jaw = maxf(cat.jaw, 0.15 + 0.1 * sin(act_t * 9.0))
			if not up and cat.sit <= 0.0: _next_act()
		"play": # crouch, wiggle, spring forward, bat the air
			cat.wag = 0.8
			var a := act_t
			cat.crouch = clampf(a / 0.7, 0.0, 1.0) if a < 1.0 else maxf(1.0 - (a - 1.0) * 3.0, (0.25 if a < 3.0 else 0.0))
			cat.pounce = sin(clampf((a - 1.0) / 0.3, 0.0, 1.0) * PI)
			var hop := 0.12 * cat.pounce
			if a > 1.0 and a < 1.3:
				_go(cat, pounce_from + _dir(cat.rotation.y) * 0.6, 2.2, dt, 0.0, hop)
			else:
				_go(cat, cat.position, 0.0, dt)
				_look_at(cat, _nearest_person())
			cat.swipe = maxf(sin((a - 1.4) * 9.0), 0.0) if a > 1.4 and a < 3.0 else 0.0
			if a > act_len:
				cat.crouch = 0.0
				cat.pounce = 0.0
				cat.swipe = 0.0
				ang = atan2(cat.position.x - gp.x, cat.position.z - gp.z)
				rad = clampf(Vector2(cat.position.x - gp.x, cat.position.z - gp.z).length(), 1.4, 3.2)
				_next_act()
	meow_t -= dt
	if meow_t <= 0.0:
		_meow()
		meow_t = randf_range(2.5, 7.0) * (0.7 if act == "sit" else 1.0)

# ---- the dog -------------------------------------------------------------------------------------

func _start_dog() -> void:
	state = 2
	ph = 0
	ph_t = 0.0
	rng.seed = world.layout_seed * 104729 + gen * 37 + 5
	cat.crouch = 0.0
	cat.pounce = 0.0
	cat.swipe = 0.0
	if not cat.visible: # done before the cat ever came: it comes now, straight to its place
		_start_cat(gen)
		state = 2
	var a := atan2(cat.position.x - gp.x, cat.position.z - gp.z)
	spot = _clear_spot(gp, a, SPOT_R, 1.8)
	spot.y = _ground(Vector3(spot.x, gp.y, spot.z), gp.y)
	var out := atan2(spot.x - gp.x, spot.z - gp.z) + rng.randf_range(-0.6, 0.6)
	den = _clear_spot(spot, out, DEN_R, 8.0)
	dog.position = Vector3(den.x, _ground(Vector3(den.x, spot.y, den.z), spot.y), den.z)
	dog.rotation.y = atan2(spot.x - den.x, spot.z - den.z)
	dog.visible = true
	dog.wag = 0.08
	feared = false

func _dog_step(dt: float) -> void:
	ph_t += dt
	jaw_t = maxf(jaw_t - dt, 0.0)
	var dist := Vector2(dog.position.x - cat.position.x, dog.position.z - cat.position.z).length()
	# the cat: to its place, washing, until the dog is near; then low, facing it, tail lashing
	if ph <= 1:
		if not feared and dist < 10.0:
			feared = true
			_meow(1.25)
		if not feared:
			cat.jaw = sin(clampf(jaw_t / 0.5, 0.0, 1.0) * PI) * 0.8
			if _go(cat, spot, 0.7, dt) < 0.1:
				_turn_to(cat, gp, dt, 2.0)
				cat.sit = move_toward(cat.sit, 1.0, dt * 1.6)
				cat.look = Vector2(0.2 * sin(t * 1.3), -0.5 + 0.12 * sin(t * 9.0))
		else:
			_go(cat, cat.position, 0.0, dt)
			cat.sit = move_toward(cat.sit, 0.0, dt * 3.0)
			cat.crouch = move_toward(cat.crouch, 0.7, dt * 2.0)
			cat.wag = 1.0
			_turn_to(cat, dog.position, dt, 3.0)
			_look_at(cat, dog.position + Vector3(0, 0.6, 0))
			cat.jaw = 0.5 + 0.2 * sin(t * 20.0) # hissing
	match ph:
		0: # low and slow, eyes on it
			dog.crouch = move_toward(dog.crouch, 0.55, dt)
			_go(dog, cat.position, STALK, dt, 3.0)
			_look_at(dog, cat.position + Vector3(0, 0.2, 0))
			if dist <= FREEZE_AT or ph_t > 25.0:
				ph = 1
				ph_t = 0.0
		1: # stops dead, lower still
			_go(dog, dog.position, 0.0, dt)
			dog.crouch = move_toward(dog.crouch, 0.85, dt * 2.0)
			_turn_to(dog, cat.position, dt, 4.0)
			_look_at(dog, cat.position + Vector3(0, 0.2, 0))
			if ph_t > 1.4:
				ph = 2
				ph_t = 0.0
				if bark_s:
					dog_snd.stream = bark_s
					dog_snd.play()
					bark_stop = 1.3
					barks += 1
				away = (cat.position - dog.position).normalized()
		2: # the run; the cat turns a moment too late
			dog.crouch = move_toward(dog.crouch, 0.0, dt * 4.0)
			dog.wag = 0.0
			_go(dog, cat.position, SPRINT, dt, 12.0)
			_look_at(dog, cat.position)
			var mouth := dog.point_on("head", DOG_MOUTH)
			var cc := cat.to_global(cat.centre)
			var md := Vector2(mouth.x - cc.x, mouth.z - cc.z).length()
			dog.jaw = clampf(1.6 - md * 0.6, 0.0, 1.0)
			if ph_t > 0.3:
				cat.crouch = move_toward(cat.crouch, 0.0, dt * 4.0)
				_go(cat, cat.position + away * 3.0, 3.0, dt, 9.0)
			if md < 0.45 or ph_t > 3.0:
				ph = 3
				ph_t = 0.0
				bites += 1
				_meow(1.5)
				cat.limp = 1.0
				cat.crouch = 0.0
				cat.sit = 0.0
				cat.speed = 0.0
				if blood: blood.splash(cc, away, cam.call() if cam.is_valid() else Vector3.INF)
				splashes += 1
				splash_t = 0.25
		3: # it shakes it
			_go(dog, dog.position, 0.0, dt)
			dog.crouch = move_toward(dog.crouch, 0.25, dt * 3.0)
			dog.jaw = 0.42
			dog.look = Vector2(0.0, -0.15)
			dog.shake = clampf(ph_t / 0.2, 0.0, 1.0) * clampf((SHAKE_TIME - ph_t) / 0.3, 0.0, 1.0)
			cat.shake = dog.shake
			splash_t -= dt
			if splash_t <= 0.0 and blood:
				splash_t = 0.32
				var side := dog.global_basis.x * (1.0 if sin(dog.t * TAU * 4.6) > 0.0 else -1.0)
				blood.splash(cat.to_global(cat.centre), side, cam.call() if cam.is_valid() else Vector3.INF)
				splashes += 1
			if ph_t > SHAKE_TIME:
				ph = 4
				ph_t = 0.0
				dog.shake = 0.0
				cat.shake = 0.0
				if eat_s:
					dog_snd.stream = eat_s
					dog_snd.play()
					eat_stop = SWALLOW_TIME + 0.2
		4: # and swallows it: head up, the throat working
			dog.swallow = 1.0
			dog.jaw = 0.25
			dog.look = Vector2(0.0, 0.35)
			if ph_t > SWALLOW_TIME:
				ph = 5
				ph_t = 0.0
				cat.visible = false
				dog.swallow = 0.0
				dog.look = Vector2.ZERO
				if blood:
					blood.splash(dog.point_on("head", DOG_MOUTH), _dir(dog.rotation.y), cam.call() if cam.is_valid() else Vector3.INF)
					splashes += 1
				var back := Vector3(den.x - dog.position.x, 0.0, den.z - dog.position.z)
				away = back.normalized() if back.length() > 0.5 else -_dir(dog.rotation.y)
		5: # off into the dark
			dog.wag = 0.4
			dog.jaw = 0.3
			_go(dog, dog.position + away * 10.0, 6.5, dt, 5.0)
			if ph_t > RUN_TIME:
				ph = 6
				dog.visible = false
				state = 3

## The cat across the dog's mouth: its middle between the teeth, its length along the jaw, rolled so
## it hangs; while it is swallowed it shrinks into the mouth.
func _hold_cat() -> void:
	var mouth := dog.point_on("head", DOG_MOUTH)
	var b := dog.bone_basis("head") * Basis(Vector3.UP, PI * 0.5) * Basis(Vector3(0, 0, 1), 0.45)
	var s := 1.0
	if ph == 4:
		var k := smoothstep(0.0, 1.0, ph_t / (SWALLOW_TIME * 0.9))
		s = maxf(1.0 - k, 0.02)
		mouth = mouth.lerp(dog.point_on("head", DOG_MOUTH - Vector3(0, 0, 0.12)), k)
	b = b.scaled(Vector3.ONE * s)
	cat.global_transform = Transform3D(b, mouth - b * cat.centre)
