class_name NFHunch extends SkeletonModifier3D
## «الوحش» moves like the creature he is: on top of whatever clip plays, his back bends forward, his
## head comes up to look ahead, his knees bend and his hips sink so the feet stay on the ground.
## The Mixamo clips are made for an upright person; without this he would run like one.
## `want` is 1 on foot and 0 in a seat or on a hook (CharacterRig.play sets it); `amount` eases to it.

var want := 1.0
var amount := 1.0
## Bend in radians about the body's left-right axis (+ tips forward).
const BEND := {"Spine": 0.24, "Spine1": 0.2, "Spine2": 0.16, "Neck": -0.28, "Head": -0.3,
	"LeftUpLeg": -0.5, "RightUpLeg": -0.5, "LeftLeg": 0.78, "RightLeg": 0.78, "LeftFoot": -0.28, "RightFoot": -0.28,
	"LeftArm": 0.18, "RightArm": 0.18}
const ORDER := ["Spine", "Spine1", "Spine2", "Neck", "Head", "LeftArm", "RightArm",
	"LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot"]
var _ids := {}
var _left := Vector3.RIGHT
var _up := Vector3.UP
var _drop := 0.0
var _hips := -1

func _setup(sk: Skeleton3D) -> void:
	for n in ORDER: _ids[n] = sk.find_bone("mixamorig_" + n)
	_hips = sk.find_bone("mixamorig_Hips")
	var g := func(n: String) -> Vector3: return sk.get_bone_global_rest(sk.find_bone("mixamorig_" + n)).origin
	_left = (g.call("LeftUpLeg") - g.call("RightUpLeg")).normalized()
	_up = (g.call("Neck") - g.call("Hips")).normalized()
	_left = (_left - _up * _left.dot(_up)).normalized()
	var l1: float = (g.call("LeftLeg") - g.call("LeftUpLeg")).length()
	var l2: float = (g.call("LeftFoot") - g.call("LeftLeg")).length()
	var thigh: float = absf(BEND.LeftUpLeg)
	var shin: float = absf(BEND.LeftUpLeg + BEND.LeftLeg)
	_drop = l1 * (1.0 - cos(thigh)) + l2 * (1.0 - cos(shin))

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null: return
	if _ids.is_empty(): _setup(sk)
	var dt := get_process_delta_time() if is_inside_tree() else 0.016
	amount = move_toward(amount, want, dt * 2.5)
	if amount <= 0.001: return
	if _hips >= 0:
		var hp := sk.get_bone_pose_position(_hips)
		# sink along "up", in the hips' parent space (the skeleton's own: the hips have no parent bone)
		sk.set_bone_pose_position(_hips, hp - _local_up(sk) * _drop * amount)
	for n in ORDER:
		var b: int = _ids[n]
		if b < 0: continue
		var gp := sk.get_bone_global_pose(b)
		gp.basis = Basis(_left, float(BEND[n]) * amount) * gp.basis
		sk.set_bone_global_pose(b, gp)

func _local_up(sk: Skeleton3D) -> Vector3:
	var par := sk.get_bone_parent(_hips)
	if par < 0: return _up
	return sk.get_bone_global_pose(par).basis.inverse() * _up
