class_name NFAnimal
extends Node3D
## The owner's cat and dog (assets/animals/cat.glb, dog.glb: his Meshy sculpts baked by
## tools/prop_bake.py and rigged by tools/rig_animal.py — root, hips, spine1-2, chest, neck1-2, head,
## jaw, a tail chain, four legs of top / mid / low / paw; every bone's rest is the model's own axes:
## +z forward, +y up, +x the animal's left). Animated in code every frame from what it is doing:
##
##   speed (m/s)        walk -> trot -> gallop, each leg on its own beat (a walk is one foot after
##                      another, a trot diagonal pairs, a gallop the hind pair then the front pair);
##                      the stride is sized from the speed so the paws do not skate
##   look               where the head turns (yaw, pitch), eased
##   sit, crouch        the cat sitting; the dog's low stalk (and the cat's crouch before a pounce)
##   pounce, swipe      the cat's play: a spring off the hind legs, a front paw batting
##   jaw                0 shut .. 1 wide (a meow, a bite)
##   shake              the dog's head and neck thrashing side to side
##   swallow            the throat working, the head tipped up
## plus breathing, the tail's own swing down its chain, and small idle looks.

var kind := "cat"
var skel: Skeleton3D
var bi := {}              # bone name -> index
var tails: Array = []     # tail bone indices, root first
var model: Node3D
var speed := 0.0
var look := Vector2.ZERO  # yaw, pitch for the head (radians)
var sit := 0.0
var crouch := 0.0
var pounce := 0.0
var swipe := 0.0
var jaw := 0.0
var shake := 0.0
var swallow := 0.0
var wag := 0.3            # how much the tail swings
var limp := 0.0           # hanging from a mouth: legs, head and tail let go (the cat in the dog's jaws)
var centre := Vector3.ZERO # the middle of the body in this node's space (the model is turned and moved so
                          # the body runs along +z through the origin)
var t := 0.0
var phase := 0.0
var _look := Vector2.ZERO
var _idle_look := Vector2.ZERO
var _idle_t := 0.0
var _gait := 0.0          # 0 walk, 1 trot, 2 gallop (eased)
var leg_len := 0.2        # top of a leg to the ground

func setup(which: String) -> bool:
	kind = which
	var path := "res://assets/animals/%s.glb" % which
	if not ResourceLoader.exists(path): return false
	var ps := load(path) as PackedScene
	if ps == null: return false
	model = ps.instantiate() as Node3D
	add_child(model)
	skel = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D if not model.find_children("*", "Skeleton3D", true, false).is_empty() else null
	if skel == null: return false
	for i in skel.get_bone_count():
		bi[skel.get_bone_name(i)] = i
	var k := 1
	while bi.has("tail%d" % k):
		tails.append(bi["tail%d" % k])
		k += 1
	if bi.has("fl_top"):
		leg_len = maxf(skel.get_bone_global_rest(bi["fl_top"]).origin.y, 0.05)
	if bi.has("hips") and bi.has("chest"): # the cat was sculpted standing at a slant: square it up
		var h := skel.get_bone_global_rest(bi["hips"]).origin
		var c := skel.get_bone_global_rest(bi["chest"]).origin
		var yaw := atan2(c.x - h.x, c.z - h.z)
		if absf(yaw) > 0.05: model.rotation.y = -yaw
		var mid: Vector3 = model.transform * ((h + c) * 0.5)
		model.position -= Vector3(mid.x, 0.0, mid.z)
		centre = Vector3(0.0, mid.y, 0.0)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.visibility_range_end = 75.0 # an animal is small: past this it is not worth drawing
		var mat := m.get_active_material(0) as StandardMaterial3D
		if mat: mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return true

## Where a point of the model (in its own rest space) is now, carried by a bone's pose: the dog's mouth.
func point_on(bone: String, rest_pt: Vector3) -> Vector3:
	if skel == null or not bi.has(bone): return global_position
	var b: int = bi[bone]
	return skel.global_transform * (skel.get_bone_global_pose(b) * (skel.get_bone_global_rest(b).affine_inverse() * rest_pt))

func bone_basis(bone: String) -> Basis:
	if skel == null or not bi.has(bone): return global_basis
	return (skel.global_transform * skel.get_bone_global_pose(bi[bone])).basis.orthonormalized()

func _rot(name: String, e: Vector3) -> void:
	if not bi.has(name): return
	skel.set_bone_pose_rotation(bi[name], Quaternion.from_euler(e))

func _pos(name: String, off: Vector3) -> void:
	if not bi.has(name): return
	var i: int = bi[name]
	skel.set_bone_pose_position(i, skel.get_bone_rest(i).origin + off)

## One frame of the pose.
func pose(dt: float) -> void:
	if skel == null: return
	t += dt
	# the gait from the speed (walk / trot / gallop), and how often a stride comes round
	var walk_top := 0.5 if kind == "cat" else 1.3
	var trot_top := 1.6 if kind == "cat" else 3.2
	var g := 0.0 if speed < walk_top else (1.0 if speed < trot_top else 2.0)
	_gait = move_toward(_gait, g, dt * 2.5)
	var hz := 0.0
	if speed > 0.03:
		var base := 1.7 if kind == "cat" else 1.3
		hz = base + speed * (1.3 if kind == "cat" else 0.42)
		hz = minf(hz, 4.2 if kind == "cat" else 3.4)
	phase = fmod(phase + dt * hz, 1.0)
	var moving := clampf(speed / (0.15 if kind == "cat" else 0.3), 0.0, 1.0)
	# stride: the paw travels speed / hz each cycle, over about 60% of it on the ground
	var amp := 0.0
	if hz > 0.0: amp = clampf((speed / hz) / (2.0 * leg_len * 1.5), 0.0, 0.62)
	# each leg's offset in the cycle (walk: lateral sequence; trot: diagonals; gallop: rotary)
	var off_walk := {"bl": 0.0, "fl": 0.25, "br": 0.5, "fr": 0.75}
	var off_trot := {"fl": 0.0, "br": 0.0, "fr": 0.5, "bl": 0.5}
	var off_gal := {"bl": 0.0, "br": 0.12, "fl": 0.52, "fr": 0.62}
	var body_bob := 0.0
	for leg in ["fl", "fr", "bl", "br"]:
		var o: float = off_walk[leg]
		if _gait > 1.0: o = lerpf(off_trot[leg], off_gal[leg], _gait - 1.0)
		else: o = lerpf(off_walk[leg], off_trot[leg], _gait)
		var p := fmod(phase + o, 1.0)
		# swing forward over the last 40% of the cycle, the stance pushes back over the first 60%
		var sw: float
		var lift := 0.0
		if p < 0.6: sw = lerpf(1.0, -1.0, p / 0.6) # planted: the leg sweeps back under the body
		else:
			var q := (p - 0.6) / 0.4
			sw = lerpf(-1.0, 1.0, smoothstep(0.0, 1.0, q))
			lift = sin(q * PI)
		var front: bool = leg[0] == "f"
		var a := -sw * amp * moving # negative pitch takes the paw forward
		var bend := lift * moving * (0.9 + 0.25 * _gait)
		var top := a
		var mid := 0.0
		var low := 0.0
		if front: # the elbow folds back, the wrist curls the paw up and back
			mid = bend * 0.55
			low = -bend * 1.1
		else: # the stifle comes forward, the hock folds
			mid = -bend * 0.75
			low = bend * 1.05
		# the cat sitting: hind legs folded under, front legs straight up the chest
		if not front and sit > 0.0: # (tried offline with tools/animal_poses.py)
			top += -0.5 * sit; mid += 1.9 * sit; low += -1.5 * sit
		if front and sit > 0.0:
			top += 0.44 * sit
		# low to the ground: every joint bends a little more
		var cr := crouch
		if cr > 0.0:
			if front: top += -0.35 * cr; mid += 0.85 * cr; low += -0.55 * cr
			else: top += -0.5 * cr; mid += 0.95 * cr; low += -0.6 * cr
		# the cat's play: crouched hind legs then springing straight; a front paw batting the air
		if pounce > 0.0:
			if front: top += -0.9 * pounce; low += 0.4 * pounce
			else: top += 0.6 * pounce; mid += -0.3 * pounce
		if swipe > 0.0 and leg == "fr":
			top += -1.2 * swipe; mid += 0.7 * swipe; low += -0.6 * swipe
		if limp > 0.0: # let go: the legs hang a little back and swing with the jolts
			var swing := sin(t * TAU * 4.6 + float(leg.unicode_at(0) + leg.unicode_at(1)) * 0.7) * 0.45 * shake
			top = lerpf(top, 0.35 + swing, limp)
			mid = lerpf(mid, (0.35 if front else -0.35) + swing * 0.6, limp)
			low = lerpf(low, (-0.3 if front else 0.3), limp)
		_rot(leg + "_top", Vector3(top, 0, 0))
		_rot(leg + "_mid", Vector3(mid, 0, 0))
		_rot(leg + "_low", Vector3(low, 0, 0))
		_rot(leg + "_paw", Vector3(-low * 0.4, 0, 0))
		body_bob += lift * moving
	# the body: rising and falling with the strides, rolling a touch, the spine flexing in a gallop
	var bob := sin(phase * TAU * 2.0) * 0.012 * moving * (1.0 + _gait)
	var breath := sin(t * (2.2 if kind == "cat" else 1.6)) * 0.012
	var flex := sin(phase * TAU) * 0.12 * clampf(_gait - 1.0, 0.0, 1.0)
	_pos("hips", Vector3(0, bob - crouch * leg_len * 0.38 - sit * leg_len * 0.46, 0))
	_rot("hips", Vector3(-0.62 * sit + flex * 0.5, sin(phase * TAU) * 0.05 * moving, sin(phase * TAU) * 0.04 * moving))
	_rot("spine1", Vector3(breath + flex, 0, 0))
	_rot("spine2", Vector3(-breath * 0.5 + flex, 0, 0))
	_rot("chest", Vector3(0.18 * sit - 0.1 * crouch - pounce * 0.25 - flex, -sin(phase * TAU) * 0.04 * moving, 0))
	# the head: where it is told to look, plus little looks of its own when idle; it counters the bob
	_idle_t -= dt
	if _idle_t <= 0.0:
		_idle_t = randf_range(1.5, 4.0)
		_idle_look = Vector2(randf_range(-0.6, 0.6), randf_range(-0.15, 0.25)) * (1.0 - moving)
	var want := look + _idle_look * (1.0 - clampf(shake + swallow + limp, 0.0, 1.0))
	want = want.lerp(Vector2(0.0, -0.75), limp)
	_look = _look.lerp(want, 1.0 - exp(-4.0 * dt))
	var thrash := sin(t * TAU * 4.6) * shake
	var thrash2 := sin(t * TAU * 4.6 + 0.9) * shake
	var gulp := swallow * (0.35 + 0.12 * sin(t * TAU * 2.4))
	_rot("neck1", Vector3(-_look.y * 0.4 + crouch * 0.3 - gulp * 0.6, _look.x * 0.35 + thrash * 0.35, thrash2 * 0.15))
	_rot("neck2", Vector3(-_look.y * 0.3 - gulp * 0.5 - bob * 2.0, _look.x * 0.35 + thrash * 0.45, thrash * 0.2))
	_rot("head", Vector3(-_look.y * 0.3 + crouch * 0.2 - gulp * 0.3, _look.x * 0.3 + thrash * 0.4, thrash2 * 0.3))
	if bi.has("neck2"): # the throat working while it swallows
		skel.set_bone_pose_scale(bi["neck2"], Vector3.ONE * (1.0 + swallow * 0.07 * maxf(sin(t * TAU * 2.4), 0.0)))
	_rot("jaw", Vector3(0.62 * clampf(maxf(jaw, 0.45 * limp), 0.0, 1.0) + swallow * 0.12 * maxf(sin(t * TAU * 2.4 + 1.0), 0.0), 0, 0))
	# the tail: a wave running down it, lazier at rest, low in the stalk, straight out in a gallop
	var n := tails.size()
	for k in n:
		var f := float(k + 1) / float(n)
		var sway := sin(t * (1.6 if moving < 0.5 else hz * TAU / TAU * 1.0) * TAU / 2.0 - k * 0.55) * wag * (0.25 + 0.6 * f)
		var lift_t := 0.0
		if kind == "cat": lift_t = -0.25 * (1.0 - moving) + 0.15 * sit # a cat carries it up, curls it sitting
		else: lift_t = 0.12 + crouch * 0.35 + _gait * -0.08 # a dog lets it hang, low when it stalks
		lift_t = lerpf(lift_t, -0.45, limp)
		skel.set_bone_pose_rotation(tails[k], Quaternion.from_euler(Vector3(lift_t * (0.6 + f) - pounce * 0.3, sway, sway * 0.3)))
