extends Node3D
## «Kiss» (the owner: shake the phone three times, a new interaction between characters; the one kissed
## is healed; faces very close, a natural hug). The rules decide it (`kiss` input, both rules files);
## every phone that gets the `kiss` event plays the same thing here:
##
##   0.0-0.9 s  the two step in to face each other (the middle between them, each turned to the other)
##   0.3-1.1 s  the arms come up and round: one holds the other's upper back, the other the waist
##   0.6-1.2 s  the backs lean in, the heads tip to opposite sides, the faces come together
##   1.2-3.7 s  the kiss (the distance between them is servoed every frame so the lips just meet,
##              whatever the two characters' builds); a slow sway, a breath
##   3.7-4.4 s  they ease apart
##
## The lean, the head's nod, tip and turn are `scripts/kiss_mod.gd` (after the animation, before the arms'
## IK); the hug is `NFReach` (the hands to points on the other's back). No class_name.

const KissMod := preload("res://scripts/kiss_mod.gd")
const TIME := 4.4
const SEP0 := 0.62      # where the servo starts: a little apart
const LIPS_UP := 0.075  # the lips, from the head bone (the base of the skull): up and forward
const LIPS_FWD := 0.105

var rig_of := Callable()   # name -> CharacterRig
var node_of := Callable()  # name -> the Node3D the character stands on (my body, a remote's node)
var now := {}              # "a|b" -> {a, b, t, mid, u, sep, y}
var mods := {}             # rig instance id -> the kiss modifier on it
var played := 0            # for the tests
var closest := 9.0         # for the tests: the nearest the lips came, last kiss
var snd_s: AudioStream
var snd: AudioStreamPlayer3D

var rules: Rules

func setup(rig_cb: Callable, node_cb: Callable, r: Rules = null) -> void:
	rules = r
	rig_of = rig_cb
	node_of = node_cb
	if ResourceLoader.exists("res://assets/sfx/kiss.ogg"): snd_s = load("res://assets/sfx/kiss.ogg")
	snd = AudioStreamPlayer3D.new()
	snd.bus = Aud.SFX
	snd.unit_size = 3.0
	snd.max_distance = 22.0
	add_child(snd)

## This survivor is in a kiss right now (main holds their input and their pose).
func busy(n: String) -> bool:
	for k in now:
		if now[k].a == n or now[k].b == n: return true
	return false

## Who `n` is kissing, or "".
func partner(n: String) -> String:
	for k in now:
		if now[k].a == n: return now[k].b
		if now[k].b == n: return now[k].a
	return ""

func start(a: String, b: String) -> void:
	var na = node_of.call(a) if node_of.is_valid() else null
	var nb = node_of.call(b) if node_of.is_valid() else null
	if na == null or nb == null: return
	var pa: Vector3 = (na as Node3D).global_position
	var pb: Vector3 = (nb as Node3D).global_position
	var u := Vector3(pb.x - pa.x, 0.0, pb.z - pa.z)
	if u.length() < 0.05: u = Vector3(0, 0, 1)
	u = u.normalized()
	now[a + "|" + b] = {"a": a, "b": b, "t": 0.0, "mid": (pa + pb) * 0.5, "u": u, "sep": SEP0,
		"pa": pa, "pb": pb, "y": (pa.y + pb.y) * 0.5}
	played += 1
	closest = 9.0
	if snd_s:
		snd.global_position = (pa + pb) * 0.5 + Vector3(0, 1.6, 0)
		snd.stream = snd_s
		get_tree().create_timer(0.55).timeout.connect(_kiss_sound)

func _kiss_sound() -> void:
	if is_instance_valid(snd): snd.play()

## Let go at once (one of them was struck, carried, went in a car...).
func stop(n: String) -> void:
	for k in now.keys():
		if now[k].a == n or now[k].b == n:
			_release(now[k])
			now.erase(k)

func _mod(r: CharacterRig):
	var id := r.get_instance_id()
	if mods.has(id) and is_instance_valid(mods[id]): return mods[id]
	var m = KissMod.new()
	m.name = "Kiss"
	r.skeleton.add_child(m)
	# after the hunch (if any), before the arms' IK
	var at := 0
	for i in r.skeleton.get_child_count():
		if r.skeleton.get_child(i) is NFHunch: at = i + 1
	r.skeleton.move_child(m, at)
	mods[id] = m
	return m

func _release(x: Dictionary) -> void:
	for n in [x.a, x.b]:
		var r = rig_of.call(n) if rig_of.is_valid() else null
		if r == null or not is_instance_valid(r): continue
		(r as CharacterRig).reach_clear()
		var m = mods.get((r as CharacterRig).get_instance_id())
		if m != null and is_instance_valid(m): m.amt = 0.0

func _lips(r: CharacterRig, fwd: Vector3) -> Vector3:
	return r.bone_at("mixamorig_Head") + Vector3(0, LIPS_UP, 0) + fwd * LIPS_FWD

func _process(dt: float) -> void:
	for k in now.keys():
		var x: Dictionary = now[k]
		x.t = float(x.t) + dt
		var ra = rig_of.call(x.a) if rig_of.is_valid() else null
		var rb = rig_of.call(x.b) if rig_of.is_valid() else null
		var na = node_of.call(x.a) if node_of.is_valid() else null
		var nb = node_of.call(x.b) if node_of.is_valid() else null
		var broke: bool = rules != null and not (rules.free_now(x.a) and rules.free_now(x.b)) # struck down, carried...
		if float(x.t) >= TIME or broke or ra == null or rb == null or na == null or nb == null:
			_release(x)
			now.erase(k)
			continue
		_pose(x, ra, rb, na, nb, dt)

func _pose(x: Dictionary, ra: CharacterRig, rb: CharacterRig, na: Node3D, nb: Node3D, dt: float) -> void:
	var t := float(x.t)
	var u: Vector3 = x.u
	var step := smoothstep(0.0, 0.9, t) * (1.0 - smoothstep(3.7, TIME, t) * 0.35)   # into place
	var arms := smoothstep(0.3, 1.1, t) * (1.0 - smoothstep(3.6, 4.25, t))           # the hug
	var lean := smoothstep(0.6, 1.25, t) * (1.0 - smoothstep(3.6, 4.2, t))            # the kiss
	# a slow sway together while they hold each other
	var sway := sin(t * 1.6) * 0.035 * arms
	var side := Vector3(-u.z, 0.0, u.x)
	var mid: Vector3 = Vector3(x.mid) + side * sway
	var sep: float = x.sep
	var want_a: Vector3 = mid - u * sep * 0.5
	var want_b: Vector3 = mid + u * sep * 0.5
	want_a.y = Vector3(x.pa).y
	want_b.y = Vector3(x.pb).y
	na.global_position = Vector3(x.pa).lerp(want_a, step)
	nb.global_position = Vector3(x.pb).lerp(want_b, step)
	var ya := atan2(u.x, u.z)
	var yb := atan2(-u.x, -u.z)
	ra.rotation = Vector3(0, lerp_angle(ra.rotation.y, ya, minf(1.0, dt * 9.0)) if step < 0.99 else ya, 0)
	rb.rotation = Vector3(0, lerp_angle(rb.rotation.y, yb, minf(1.0, dt * 9.0)) if step < 0.99 else yb, 0)
	ra.play("idle")
	rb.play("idle")
	# the lips: the gap along the line between them, closed by moving the two closer or further
	var la := _lips(ra, u)
	var lb := _lips(rb, -u)
	var gap := (lb - la).dot(u)
	if lean > 0.5: x.sep = clampf(sep + (gap - 0.012) * minf(1.0, dt * 6.0), 0.26, 0.8)
	elif t < 0.6: x.sep = lerpf(sep, 0.5, minf(1.0, dt * 3.0)) # close in while they step up
	if lean > 0.9: closest = minf(closest, la.distance_to(lb))
	# the heads: the taller one nods down, the shorter one lifts; both tip to their own right
	var dh := la.y - lb.y
	for pair in [[ra, u, dh, 1.0], [rb, -u, -dh, -1.0]]:
		var r: CharacterRig = pair[0]
		var f: Vector3 = pair[1]
		var m = _mod(r)
		m.amt = lean
		m.fwd = f
		m.left = Vector3(f.z, 0.0, -f.x) # the character's own left, facing f
		m.lean = 0.16
		m.pitch = clampf(atan2(float(pair[2]), 0.18) * 0.8, -0.35, 0.45) + 0.06
		m.roll = 0.32
		m.turn = 0.1
	# the hug: A's hands on B's upper back (over the shoulders), B's round A's waist
	if arms > 0.01:
		_hug(ra, rb, u, arms, true)
		_hug(rb, ra, -u, arms, false)
	else:
		ra.reach_clear()
		rb.reach_clear()

## `r` holds `o` (who faces -f): the wrists to two points either side of o's spine, on its back.
func _hug(r: CharacterRig, o: CharacterRig, f: Vector3, k: float, high: bool) -> void:
	var left := Vector3(f.z, 0.0, -f.x)
	var spine := o.bone_at("mixamorig_Spine2" if high else "mixamorig_Spine")
	var back := spine + f * (0.07 if high else 0.05) + Vector3(0, 0.06 if high else 0.02, 0)
	var spread := 0.11 if high else 0.13
	var lt := back + left * spread
	var rt := back - left * spread
	var sl := r.bone_at("mixamorig_LeftArm")
	var sr := r.bone_at("mixamorig_RightArm")
	# eased in from where the hands hang
	var rest_l := sl + Vector3(0, -0.55, 0) + left * 0.05
	var rest_r := sr + Vector3(0, -0.55, 0) - left * 0.05
	lt = rest_l.lerp(lt, k) if k < 0.999 else lt
	rt = rest_r.lerp(rt, k) if k < 0.999 else rt
	r.reach(lt, rt, sl + left * 0.55 - Vector3(0, 0.35, 0) - f * 0.15, sr - left * 0.55 - Vector3(0, 0.35, 0) - f * 0.15)
