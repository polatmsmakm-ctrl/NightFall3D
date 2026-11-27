extends Node3D
## The owner's gorilla («Shadowback Titan», his Meshy sculpt, rigged on the characters' Mixamo skeleton
## by tools/rig_character.py --bake, so it moves with their clips) and a horse, once a round, after the
## cat and the dog (scripts/catdog.gd), near the same generator, on every phone alike:
##
##   a horse wanders in and grazes; the gorilla comes out of the dark, hunched, twice a man's height;
##   the horse sees it and rears; it charges, knocks the horse down with one blow, crouches at its head,
##   grips the neck and the head and tears the head off (the neck pours); it stands, holds the head up
##   and roars, and throws it away; it crouches over the body and bites into it again and again; it
##   lifts what is left over its face and swallows it whole; it walks back into the dark. The head
##   stays where it fell.
##
## The horse is the Empty Quarter's horse (vinish.dev, CC BY 4.0) with its own clips (Graze, Rear…),
## loaded twice: the body, whose neck bone is folded away when the head comes off, and a second copy in
## which everything but the head is folded away, for the head in the gorilla's hand. No network message:
## it starts a few seconds after the dog has gone, from the same generator and the map's seed.
## No class_name (an in-game update can carry it).

const Probe := preload("res://scripts/pose_probe.gd")
const Crumbs := preload("res://scripts/crumbs.gd")
var horse_ps: PackedScene
const GS := 1.9              # the gorilla's size against the cast's 1.95 m: a titan
const HORSE := "res://assets/animals/arabian-horse.glb"
const DELAY := 6.0           # after the dog has gone
const HORSE_R := 12.0        # where the horse grazes, from the generator
const DEN_R := 30.0          # where the gorilla comes from, from the horse
const SEEN_AT := 14.0        # the horse rears when the gorilla is this near
const WALK := 1.3 * GS       # its walk and its charge, matching its legs at this size
const CHARGE := 3.7 * GS * 1.05
const TEAR := 2.6
const RIP_AT := 2.1
const ROAR := 2.0
const THROW := 0.55
const BITE := 6.0
const BITE_EVERY := 1.2
const SWALLOW := 6.0
const LEAVE := 10.0
const PIVOT_Y := 1.05        # the horse's middle, from its hooves

var world: NightWorld
var catdog: NFCatDog
var blood: NFBlood
var cam := Callable()
var skip: Array = []
var rng := RandomNumberGenerator.new()
var state := 0               # 0 waiting for the dog to go, 1 the pause, 2 the scene, 3 over
var wait := 0.0
var ph := 0                  # see _step
var ph_t := 0.0
var t := 0.0
var rig: CharacterRig
var horse: Node3D            # on the ground, turned (its yaw)
var pivot: Node3D            # the horse's middle: it falls and is lifted about this
var hmodel: Node3D
var hsk: Skeleton3D
var hap: AnimationPlayer
var head: Node3D             # the second copy: only the head
var head_sk: Skeleton3D
var head_v := Vector3.ZERO
var head_spin := Vector3.ZERO
var head_off := Transform3D()
var head_state := 0          # 0 on the horse, 1 in the hand, 2 flying, 3 on the ground
var spot := Vector3.ZERO     # where the horse grazes
var den := Vector3.ZERO
var gp := Vector3.ZERO
var fall_side := 1.0
var fall_t := -1.0
var bite_n := 0
var bite_t := 0.0
var lunge := 0.0
var spurt := 0.0
var swallow_from := Transform3D()
var stump: MeshInstance3D    # the torn end of the body's neck
var snd: AudioStreamPlayer3D
var chew: AudioStreamPlayer3D
var dark: AudioStreamPlayer3D
var hsnd: AudioStreamPlayer3D
var roar_s: AudioStream
var chew_s: AudioStream
var dark_s: AudioStream
var hit_s: Array = []
var feast_s: AudioStream     # the owner's own sound for this scene (assets/sfx/gorilla_feast.ogg, 30 s)
var rage: AudioStreamPlayer3D
var rage_fade := 0.0
var thud_s: Array = []
# for the tests
var rips := 0
var bites := 0
var splashes := 0
var swallowed := false
var phases := {}

func setup(w: NightWorld, cd: NFCatDog, b: NFBlood, cam_cb: Callable, skip_rids: Array) -> void:
	world = w
	catdog = cd
	blood = b
	cam = cam_cb
	skip = skip_rids
	if not ResourceLoader.exists("res://assets/chars/gorilla.glb") or not ResourceLoader.exists(HORSE) \
			or FileAccess.file_exists(Crumbs.NO_GORILLA): # (off on this phone after it crashed the game here once)
		state = 3
		return
	roar_s = _load("scream_beast.mp3")
	chew_s = _load("dog_eat.ogg")
	dark_s = _load("dog_eat_dark.ogg")
	feast_s = _load("gorilla_feast.ogg")
	for i in 4: hit_s.append(_load("knife%d.mp3" % (i + 1)))
	for i in 3: thud_s.append(_load("fall%d.ogg" % (i + 1)))
	# (no background loading: on the iPhone, loading these on a worker thread while the round draws crashed
	# the game when the scene began; they are read on the main thread when it starts, a short hitch)

func _load(f: String) -> AudioStream:
	var p := "res://assets/sfx/" + f
	return load(p) if ResourceLoader.exists(p) else null

## The models are only loaded when the scene starts: nothing to draw or skin before then.
func _build() -> bool:
	Crumbs.mark("gorilla: building")
	rig = CharacterRig.new()
	rig.name = "Titan"
	add_child(rig)
	rig.setup("gorilla", ["idle", "walk", "run", "attack", "repair"], false, false)
	Crumbs.mark("gorilla: model loaded")
	if rig.skeleton == null or rig.failed != "": return false
	rig.scale = Vector3.ONE * GS
	Crumbs.mark("gorilla: hunch")
	rig.hunch = NFHunch.new() # bent like an ape over every clip, as «الوحش» is
	rig.skeleton.add_child(rig.hunch)
	rig.skeleton.move_child(rig.hunch, 0)
	Probe.of(rig)
	Crumbs.mark("gorilla: probe")
	for gi in rig.find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).visibility_range_end = 120.0
	horse = Node3D.new()
	horse.name = "Horse"
	add_child(horse)
	pivot = Node3D.new()
	pivot.position.y = PIVOT_Y
	horse.add_child(pivot)
	Crumbs.mark("gorilla: loading the horse")
	horse_ps = load(HORSE) as PackedScene
	if horse_ps == null:
		Crumbs.mark("gorilla: the horse would not load")
		return false
	hmodel = horse_ps.instantiate() as Node3D
	hmodel.position.y = -PIVOT_Y
	pivot.add_child(hmodel)
	Crumbs.mark("gorilla: horse loaded")
	hsk = hmodel.find_children("*", "Skeleton3D", true, false)[0]
	var aps := hmodel.find_children("*", "AnimationPlayer", true, false)
	if aps.is_empty(): return false
	hap = aps[0]
	Crumbs.mark("gorilla: horse clips")
	for c in ["Walk", "Idle", "Graze", "Trot", "Gallop"]:
		if hap.has_animation(c): hap.get_animation(c).loop_mode = Animation.LOOP_LINEAR
	Crumbs.mark("gorilla: built")
	snd = _snd(rig, 14.0, 90.0)
	chew = _snd(rig, 9.0, 60.0)
	dark = _snd(rig, 12.0, 70.0)
	hsnd = _snd(pivot, 8.0, 60.0)
	rage = _snd(rig, 16.0, 110.0)
	return true

func _snd(n: Node3D, unit: float, reach: float) -> AudioStreamPlayer3D:
	var s := AudioStreamPlayer3D.new()
	s.bus = Aud.SFX
	s.unit_size = unit
	s.max_distance = reach
	n.add_child(s)
	return s

func _play(s: AudioStreamPlayer3D, st: AudioStream, pitch := 1.0, db := 0.0) -> void:
	if s == null or st == null: return
	s.stream = st
	s.pitch_scale = pitch
	s.volume_db = db
	s.play()

func _dir(a: float) -> Vector3:
	return Vector3(sin(a), 0.0, cos(a))

func _ray(a: Vector3, b: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1, skip)
	return get_world_3d().direct_space_state.intersect_ray(q)

func _ground(p: Vector3, fallback: float) -> float:
	var h := _ray(p + Vector3(0, 1.0, 0), p - Vector3(0, 3.0, 0))
	if h.is_empty(): h = _ray(p + Vector3(0, 4.0, 0), p - Vector3(0, 6.0, 0))
	return (h.position as Vector3).y if not h.is_empty() else fallback

func _clear(a: Vector3, b: Vector3, h := 0.6) -> bool:
	var up := Vector3(0, h, 0)
	return _ray(a + up, b + up).is_empty()

## The first open direction from `from` (a0, then either side of it), a body's width wide.
func _clear_spot(from: Vector3, a0: float, dist: float, short: float) -> Vector3:
	for k in 11:
		var a := a0 + 0.55 * ceilf(k / 2.0) * (1.0 if k % 2 == 1 else -1.0)
		var to := from + _dir(a) * dist
		var side := _dir(a + PI / 2.0) * 0.9
		if _clear(from + _dir(a) * 1.5, to) and _clear(from + _dir(a) * 1.5 + side, to + side) and _clear(from + _dir(a) * 1.5 - side, to - side):
			return to
	return from + _dir(a0) * short

func _cam() -> Vector3:
	return cam.call() if cam.is_valid() else Vector3.INF

func _hclip(c: String, speed := 1.0, blend := 0.4) -> void:
	if hap == null or not hap.has_animation(c): return
	if hap.current_animation != c: hap.play(c, blend)
	hap.speed_scale = speed

## Walk the gorilla toward a point, turning as it goes; its legs keep up with how fast it went.
func _go(to: Vector3, spd: float, dt: float, turn := 5.0) -> float:
	var d := Vector3(to.x - rig.position.x, 0.0, to.z - rig.position.z)
	var dist := d.length()
	var v := 0.0
	if dist > 0.05 and dt > 0.0:
		rig.rotation.y = lerp_angle(rig.rotation.y, atan2(d.x, d.z), 1.0 - exp(-turn * dt))
		var align := clampf(_dir(rig.rotation.y).dot(d / dist), 0.0, 1.0)
		v = minf(spd * (0.3 + 0.7 * align), dist / dt)
		rig.position += d / dist * v * dt
	rig.position.y = lerpf(rig.position.y, _ground(rig.position, rig.position.y), 1.0 - exp(-12.0 * dt))
	if v > 0.4:
		if spd > WALK * 1.3: rig.play("run", clampf(v / (3.7 * GS), 0.7, 1.6))
		else: rig.play("walk", clampf(v / WALK, 0.6, 1.5))
	return dist

func _turn_to(p: Vector3, dt: float, rate := 5.0) -> void:
	var d := p - rig.position
	rig.rotation.y = lerp_angle(rig.rotation.y, atan2(d.x, d.z), 1.0 - exp(-rate * dt))

## A horse bone in the world.
func _hb(sk: Skeleton3D, bone: String) -> Transform3D:
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone))

## Where its hand really is, after the hunch and the IK (pose_probe.gd).
func _hand(right: bool) -> Transform3D:
	return Probe.xf(rig, "mixamorig_RightHand" if right else "mixamorig_LeftHand")

func _mouth() -> Vector3:
	var fwd := _dir(rig.rotation.y)
	return Probe.xf(rig, "mixamorig_Head").origin + fwd * 0.14 * GS + Vector3(0, 0.03 * GS, 0)

func _process(dt: float) -> void:
	if state == 3 or catdog == null: return
	t += dt
	match state:
		0:
			if catdog.state == 3:
				if catdog.ph == 6: # the dog ran off: the gorilla's turn
					Crumbs.mark("gorilla: waiting")
					state = 1
					wait = DELAY
				else: state = 3 # the cat and dog never played here (a late join): nor does this
		1:
			wait -= dt
			if wait <= 0.0: _start()
		2:
			_step(dt)

func _start() -> void:
	if not _build():
		state = 3
		return
	state = 2
	Crumbs.mark("gorilla: placing")
	gp = catdog.gp
	rng.seed = world.layout_seed * 15485863 + catdog.gen * 211 + 3
	var away := atan2(catdog.den.x - gp.x, catdog.den.z - gp.z) + PI + rng.randf_range(-0.8, 0.8)
	spot = _clear_spot(gp, away, HORSE_R, 7.0)
	spot.y = _ground(spot, gp.y)
	var from := _clear_spot(spot, away + rng.randf_range(-1.2, 1.2), 9.0, 5.0) # the horse wanders in from here
	horse.position = Vector3(from.x, _ground(from, spot.y), from.z)
	horse.rotation.y = atan2(spot.x - from.x, spot.z - from.z)
	Crumbs.mark("gorilla: horse walks")
	_hclip("Walk", 1.0)
	den = _clear_spot(spot, away + rng.randf_range(-0.5, 0.5), DEN_R, 16.0)
	den.y = _ground(den, spot.y)
	rig.position = den
	rig.rotation.y = atan2(spot.x - den.x, spot.z - den.z)
	Crumbs.mark("gorilla: idle")
	rig.play("idle")
	rig.visible = false
	Crumbs.mark("gorilla: ready")
	ph = 0
	ph_t = 0.0

func _phase(n: int) -> void:
	Crumbs.mark("gorilla: phase %d" % n)
	ph = n
	ph_t = 0.0
	phases[n] = true

## The scene, phase by phase:
## 0 the horse walks to its spot · 1 it grazes, the gorilla comes · 2 the horse rears, the charge ·
## 3 the blow and the fall · 4 the tear · 5 the head held up, the roar · 6 the throw · 7 the bites ·
## 8 the swallow · 9 back into the dark
func _step(dt: float) -> void:
	ph_t += dt
	var c := _cam()
	var hpos: Vector3 = horse.global_position if is_instance_valid(horse) and not horse.is_queued_for_deletion() else rig.position
	var gdist := Vector2(rig.position.x - hpos.x, rig.position.z - hpos.z).length()
	match ph:
		0:
			var d := Vector3(spot.x - horse.position.x, 0.0, spot.z - horse.position.z)
			if d.length() > 0.15:
				horse.rotation.y = lerp_angle(horse.rotation.y, atan2(d.x, d.z), 1.0 - exp(-3.0 * dt))
				horse.position += d.normalized() * minf(1.3 * dt, d.length())
				horse.position.y = lerpf(horse.position.y, _ground(horse.position, horse.position.y), 1.0 - exp(-10.0 * dt))
			else:
				_hclip("Graze")
				rig.visible = true
				_phase(1)
		1:
			_go(hpos, WALK, dt, 3.0)
			if gdist < SEEN_AT or ph_t > 25.0:
				_hclip("Rear", 1.0, 0.25)
				var to := rig.position - hpos # it rears toward the thing coming at it
				horse.rotation.y = atan2(to.x, to.z)
				_play(snd, roar_s, 0.55, 6.0)
				_phase(2)
		2:
			var at := hpos + _dir(atan2(rig.position.x - hpos.x, rig.position.z - hpos.z)) * 2.6
			var left := _go(at, CHARGE, dt, 8.0)
			if hap.current_animation != "Rear" or not hap.is_playing(): _hclip("Idle")
			if left < 0.5 or ph_t > 6.0:
				rig.play("attack", 1.1)
				_phase(3)
		3:
			_turn_to(hpos, dt, 8.0)
			if ph_t > 0.38 and fall_t < 0.0: # the blow lands: it goes down sideways, away from the gorilla
				fall_t = 0.0
				hap.pause()
				hap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
				var local := horse.to_local(rig.global_position)
				fall_side = 1.0 if local.x > 0.0 else -1.0
				var hit := _hb(hsk, "Neck2").origin
				if blood:
					blood.splash(hit, (hit - rig.global_position).normalized(), c)
					splashes += 1
				if feast_s: _play(rage, feast_s, 1.0, 6.0) # his sound runs from the blow to the swallow
				else: _play(hsnd, hit_s[randi() % hit_s.size()], 0.55, 8.0)
			if fall_t >= 0.0:
				fall_t += dt
				var k := clampf(fall_t / 0.65, 0.0, 1.0)
				var drop := k * k # it topples, faster as it goes
				pivot.rotation.z = fall_side * 1.47 * drop
				pivot.position.y = lerpf(PIVOT_Y, 0.36, drop) + (0.06 * sin(clampf((fall_t - 0.65) / 0.3, 0.0, 1.0) * PI) if fall_t > 0.65 else 0.0)
				if fall_t - dt < 0.65 and fall_t >= 0.65:
					_play(hsnd, thud_s[randi() % thud_s.size()], 0.6, 10.0)
			if ph_t > 1.5:
				rig.play("repair", 0.5)
				_phase(4)
		4:
			_tear(dt)
		5: # stood up, the head held high, roaring
			rig.play("idle")
			_turn_to(rig.position + _dir(rig.rotation.y), dt)
			var sh := rig.bone_at("mixamorig_RightArm")
			var fwd := _dir(rig.rotation.y)
			var up := sh + Vector3(0, 0.85 * GS, 0) + fwd * 0.25 * GS
			rig.reach_arms(Vector3.ZERO, up, Vector3.ZERO, sh + fwd * 0.4 + Vector3(0, -0.3, 0) - rig.global_basis.x.normalized() * 0.6, false, Vector3.ZERO, Vector3.ZERO)
			if ph_t > ROAR: _phase(6)
		6: # the throw: forward and down, let go a little before the end
			var sh := rig.bone_at("mixamorig_RightArm")
			var fwd := _dir(rig.rotation.y)
			var k := clampf(ph_t / THROW, 0.0, 1.0)
			var to := sh + (Vector3(0, 0.85 * GS, 0) + fwd * 0.25 * GS).lerp(fwd * 0.9 * GS - Vector3(0, 0.1 * GS, 0), k * k)
			rig.reach_arms(Vector3.ZERO, to, Vector3.ZERO, sh - rig.global_basis.x.normalized() * 0.6 - Vector3(0, 0.4, 0), false, Vector3.ZERO, Vector3.ZERO)
			if head_state == 1 and k > 0.55:
				head_state = 2
				head_v = fwd * 9.0 + Vector3(0, 4.5, 0) + _dir(rig.rotation.y + PI / 2.0) * rng.randf_range(-2.0, 2.0)
				head_spin = Vector3(rng.randf_range(-6, 6), rng.randf_range(-3, 3), rng.randf_range(-6, 6))
			if ph_t > THROW + 0.35:
				rig.reach_clear()
				_phase(7)
				bite_t = 1.6
		7:
			_bites(dt)
		8:
			_swallow(dt)
		9:
			if rage_fade > 0.0: # his sound fades out as it walks away
				rage_fade -= dt
				rage.volume_db = 6.0 + linear_to_db(clampf(rage_fade / 2.5, 0.001, 1.0))
				if rage_fade <= 0.0: rage.stop()
			rig.reach_clear()
			lunge = 0.0
			rig.rotation.x = 0.0
			_go(den, WALK, dt, 3.0)
			if ph_t > LEAVE:
				rig.queue_free()
				rig = null
				state = 3
				chew.stop()
				return
	_head_step(dt)
	_neck_bleed(dt)
	if rig: rig.rotation.x = lerpf(rig.rotation.x, lunge, 1.0 - exp(-14.0 * dt))

## Crouched at the head: one hand pins the neck, the other takes the head; the pull; the head comes off.
func _tear(dt: float) -> void:
	var head_p := _hb(hsk, "Head").origin
	var neck_p := _hb(hsk, "Neck2").origin
	var out := Vector3(head_p.x - neck_p.x, 0.0, head_p.z - neck_p.z).normalized()
	var stand := head_p + out * 1.35
	stand.y = _ground(stand, rig.position.y)
	var left := Vector3(stand.x - rig.position.x, 0.0, stand.z - rig.position.z).length()
	if left > 0.3 and ph_t < 1.2: # into place first
		_go(stand, WALK, dt, 6.0)
		if rig.current == "idle": rig.play("walk")
		ph_t = minf(ph_t, 0.4)
		return
	rig.play("repair", 0.5)
	rig.hunch.want = 0.4
	rig.position.y = lerpf(rig.position.y, _ground(rig.position, rig.position.y), 1.0 - exp(-12.0 * dt))
	_turn_to(head_p, dt, 6.0)
	var side := rig.global_basis.x.normalized()
	var k := clampf((ph_t - 0.8) / (RIP_AT - 0.8), 0.0, 1.0)
	var yank := sin(ph_t * 26.0) * 0.06 * k # tugging
	var r_to := head_p + Vector3(0, 0.12, 0) + (rig.position - head_p).normalized() * (0.55 * k * k) + Vector3(0, 0.25 * k + yank, 0)
	if head_state == 1: r_to = _hand(true).origin
	var l_to := neck_p + Vector3(0, 0.18, 0)
	var sh_l := rig.bone_at("mixamorig_LeftArm")
	var sh_r := rig.bone_at("mixamorig_RightArm")
	rig.reach(l_to, r_to, sh_l + side * 0.7 - Vector3(0, 0.6, 0), sh_r - side * 0.7 - Vector3(0, 0.6, 0))
	if head_state == 0 and k > 0.0: # the body jerks with every tug
		pivot.rotation.x = 0.05 * sin(ph_t * 26.0) * k
	if head_state == 0 and ph_t >= RIP_AT:
		_rip()
	if ph_t > TEAR:
		pivot.rotation.x = 0.0
		rig.reach_clear()
		_phase(5)
		_play(snd, roar_s, 0.5, 9.0)

## The head comes away: the body's neck is folded shut, and the copy with only a head takes its place
## in the gorilla's right hand.
func _rip() -> void:
	Crumbs.mark("gorilla: tearing the head")
	rips += 1
	var n3 := hsk.find_bone("Neck3")
	var neck_xf := _hb(hsk, "Neck3")
	neck_xf.basis = neck_xf.basis.orthonormalized()
	hsk.set_bone_pose_scale(n3, Vector3.ONE * 0.001)
	head = horse_ps.instantiate() as Node3D
	add_child(head)
	head_sk = head.find_children("*", "Skeleton3D", true, false)[0]
	for ap in head.find_children("*", "AnimationPlayer", true, false): (ap as AnimationPlayer).stop()
	var hips := head_sk.find_bone("Hips")
	head_sk.set_bone_pose_scale(hips, Vector3.ONE * 0.001)
	head_sk.set_bone_pose_scale(head_sk.find_bone("Neck3"), Vector3.ONE * 1000.0)
	for gi in head.find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).visibility_range_end = 70.0
	# put the copy's neck where the body's was
	var in_root := head.global_transform.affine_inverse() * head_sk.global_transform * head_sk.get_bone_global_pose(head_sk.find_bone("Neck3"))
	in_root.basis = in_root.basis.orthonormalized()
	head.global_transform = neck_xf * in_root.affine_inverse()
	# into the fist: the skull's middle (between its own Head bone and the muzzle) on the hand
	var hand := _hand(true)
	var grab := _hb(head_sk, "Head").origin
	head.global_position += hand.origin - grab
	head_off = hand.affine_inverse() * head.global_transform
	# both torn ends: raw and wet
	stump = _flesh(0.12)
	pivot.add_child(stump)
	stump.global_position = neck_xf.origin
	var cap := _flesh(0.1)
	head.add_child(cap)
	cap.position = in_root.origin
	cap.scale = Vector3(1.0, 0.6, 1.0)
	head_state = 1
	spurt = 9.0
	Crumbs.mark("gorilla: head in hand")
	var c := _cam()
	if blood:
		blood.splash(neck_xf.origin, (neck_xf.origin - _hb(hsk, "Chest").origin).normalized(), c)
		blood.splash(neck_xf.origin, Vector3(0, 1, 0), c)
		splashes += 2
	if not feast_s: _play(hsnd, hit_s[randi() % hit_s.size()], 0.45, 10.0)

func _flesh(r: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 1.4
	s.radial_segments = 12
	s.rings = 6
	m.mesh = s
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.26, 0.015, 0.012)
	mat.roughness = 0.18
	mat.metallic_specular = 0.75
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m

## The head: in the hand, then flying, then where it lands, still bleeding a little.
func _head_step(dt: float) -> void:
	if head == null: return
	match head_state:
		1:
			if rig: head.global_transform = _hand(true) * head_off
			if blood and fmod(t, 0.12) < dt: blood.drip(head.global_position, Vector3(0, -0.3, 0), 0.05, true)
		2:
			head_v.y -= 9.8 * dt
			var from := head.global_position
			var to := from + head_v * dt
			var hit := _ray(from, to - Vector3(0, 0.25, 0))
			if hit.is_empty():
				head.global_position = to
				head.rotate_x(head_spin.x * dt)
				head.rotate_y(head_spin.y * dt)
				head.rotate_z(head_spin.z * dt)
				if blood and fmod(t, 0.05) < dt: blood.drip(from, head_v * 0.2, 0.05, true)
			else:
				head_state = 3
				head.global_position = (hit.position as Vector3) + Vector3(0, 0.05, 0)
				# lie on its side: keep only the heading, roll it over
				var yaw := head.global_basis.get_euler().y
				head.global_basis = Basis(Vector3.UP, yaw) * Basis(Vector3(0, 0, 1), PI / 2.0 * (1.0 if head_spin.z > 0.0 else -1.0))
				_rest_head()
				if blood:
					blood.splash(hit.position, Vector3(head_v.x, 0.0, head_v.z).normalized(), _cam())
					splashes += 1
				_play(hsnd, thud_s[randi() % thud_s.size()], 0.8, 4.0)
		3:
			if blood and fmod(t, 0.9) < dt: blood.drip(_hb(head_sk, "Neck3").origin + Vector3(0, 0.05, 0), Vector3.ZERO, 0.04, true)

## After it lands: lift it so the skull sits on the ground (its own bones tell where the neck is).
func _rest_head() -> void:
	var lo := _hb(head_sk, "Neck3").origin
	var hi := _hb(head_sk, "Head").origin
	var g := _ground(head.global_position, head.global_position.y)
	head.global_position.y += g + 0.13 - minf(lo.y, hi.y)

## The neck pours after the head comes off, less and less.
func _neck_bleed(dt: float) -> void:
	if spurt <= 0.0 or blood == null or hsk == null or not pivot.visible: return
	spurt -= dt
	if fmod(t, 0.07 if spurt > 6.0 else 0.18) < dt:
		var n := _hb(hsk, "Neck2")
		var out := (n.origin - _hb(hsk, "Chest").origin).normalized()
		blood.drip(n.origin + out * 0.25, out * (2.5 if spurt > 6.0 else 1.0) + Vector3(0, 0.6, 0), 0.06, true)

## Over the body: both hands on it, the head down, a bite every second or so (a splash, the crunch,
## an open wound left behind).
func _bites(dt: float) -> void:
	var mid := pivot.global_position
	var from_side := Vector3(rig.position.x - mid.x, 0.0, rig.position.z - mid.z)
	var stand := mid + (from_side.normalized() if from_side.length() > 0.2 else _dir(0.0)) * 1.55
	stand.y = _ground(stand, rig.position.y)
	if Vector3(stand.x - rig.position.x, 0.0, stand.z - rig.position.z).length() > 0.35 and ph_t < 3.0:
		_go(stand, WALK, dt, 6.0)
		bite_t = maxf(bite_t, 0.6)
		return
	rig.play("repair", 0.5)
	rig.hunch.want = 0.6
	_turn_to(mid, dt, 6.0)
	var up_side := pivot.global_basis.y.normalized() # the horse's back, lying, points sideways
	var top := mid + Vector3(0, 0.3, 0)
	var side := rig.global_basis.x.normalized()
	rig.reach(top + side * 0.55 - up_side * 0.2, top - side * 0.55 + up_side * 0.2,
		rig.bone_at("mixamorig_LeftArm") + side * 0.8 - Vector3(0, 0.5, 0), rig.bone_at("mixamorig_RightArm") - side * 0.8 - Vector3(0, 0.5, 0))
	if not chew.playing and chew_s and not feast_s: _play(chew, chew_s, 0.55, 4.0)
	bite_t -= dt
	lunge = 0.42 if bite_t < 0.3 and bite_t > 0.0 else 0.12
	if bite_t <= 0.0:
		bite_t = BITE_EVERY
		bites += 1
		var at := _mouth() + Vector3(0, -0.35 * GS, 0)
		at.y = maxf(at.y, mid.y + 0.25)
		if blood:
			blood.splash(at, (at - rig.global_position).normalized() + Vector3(0, 0.3, 0), _cam())
			splashes += 1
		if not feast_s: _play(hsnd, hit_s[randi() % hit_s.size()], rng.randf_range(0.5, 0.62), 9.0)
		_wound(at)
	if ph_t > BITE:
		lunge = 0.0
		swallow_from = pivot.global_transform
		_phase(8)
		if not feast_s:
			_play(chew, chew_s, 0.5, 6.0)
			_play(dark, dark_s, 1.0, 4.0)

## A torn place on the body where a bite was: dark, wet flesh that stays on it.
func _wound(at: Vector3) -> void:
	var m := _flesh(0.2)
	pivot.add_child(m)
	m.global_position = pivot.global_position.lerp(at, 0.55) + Vector3(0, 0.12, 0)
	m.scale = Vector3(rng.randf_range(0.8, 1.4), 0.55, rng.randf_range(0.8, 1.4))

## Up over its face, turned so the torn neck goes in first, and down its throat.
func _swallow(dt: float) -> void:
	rig.play("idle")
	rig.hunch.want = 0.5
	var fwd := _dir(rig.rotation.y)
	var mouth := _mouth()
	var k := clampf(ph_t / 1.6, 0.0, 1.0)
	var e := smoothstep(0.0, 1.0, k)
	var g := smoothstep(0.0, 1.0, clampf((ph_t - 1.6) / (SWALLOW - 2.0), 0.0, 1.0)) # going down
	var down_b := Basis(fwd.cross(Vector3.DOWN).normalized(), fwd, Vector3.DOWN).orthonormalized()
	var over := mouth + Vector3(0, 0.45 * GS, 0)
	var pos := swallow_from.origin.lerp(over, e).lerp(mouth, g)
	var b := Basis(swallow_from.basis.get_rotation_quaternion().slerp(down_b.get_rotation_quaternion(), e))
	var s := maxf(1.0 - g * 0.98, 0.02)
	pivot.global_transform = Transform3D(b.scaled(Vector3.ONE * s), pos)
	var side := rig.global_basis.x.normalized()
	var hold := pivot.global_position + Vector3(0, -0.2, 0)
	if s > 0.35:
		rig.reach(hold + side * 0.45 * s, hold - side * 0.45 * s,
			rig.bone_at("mixamorig_LeftArm") + side - Vector3(0, 0.4, 0), rig.bone_at("mixamorig_RightArm") - side - Vector3(0, 0.4, 0))
	else: rig.reach_clear()
	if blood and fmod(t, 0.15) < dt and s > 0.1:
		blood.drip(pivot.global_position + Vector3(0, -0.3, 0), Vector3(rng.randf_range(-0.5, 0.5), -0.5, rng.randf_range(-0.5, 0.5)), 0.05, true)
	if ph_t > SWALLOW:
		swallowed = true
		pivot.visible = false
		spurt = 0.0
		rig.reach_clear()
		chew.stop()
		dark.stop()
		if blood:
			blood.splash(mouth, fwd, _cam())
			splashes += 1
		_play(snd, roar_s, 0.6, 7.0)
		rage_fade = 2.5
		horse.queue_free()
		hsk = null
		_phase(9)
