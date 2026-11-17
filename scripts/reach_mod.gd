extends SkeletonModifier3D
class_name NFReach
## Two-bone IK for both arms, run after the animation has posed the skeleton: the killer's own hands
## on the steering wheel. Every frame the car hands in the two grip points on the rim (they turn with
## the wheel) and a pole for each elbow (down and out). It also hides the head (scaled to nothing)
## for the driver's own view from the seat, where the camera sits inside it.

var active := false
var targets := [Vector3.ZERO, Vector3.ZERO]  # world: left hand, right hand (the wrist joint)
var poles := [Vector3.ZERO, Vector3.ZERO]    # world: where each elbow should point
var hide_head := false
var _bones := []                             # [[arm, forearm, hand] left, [..] right], head

func _bones_of(sk: Skeleton3D) -> void:
	_bones = []
	for side in ["Left", "Right"]:
		_bones.append([sk.find_bone("mixamorig_%sArm" % side), sk.find_bone("mixamorig_%sForeArm" % side),
			sk.find_bone("mixamorig_%sHand" % side)])
	_bones.append(sk.find_bone("mixamorig_Head"))

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or not active: return
	if _bones.is_empty(): _bones_of(sk)
	var inv := sk.global_transform.affine_inverse()
	for i in 2:
		var ch: Array = _bones[i]
		if ch[0] < 0 or ch[1] < 0 or ch[2] < 0: continue
		_two_bone(sk, ch[0], ch[1], ch[2], inv * (targets[i] as Vector3), inv * (poles[i] as Vector3))
	var head: int = _bones[2]
	if hide_head and head >= 0:
		var hp := sk.get_bone_global_pose(head)
		sk.set_bone_global_pose(head, Transform3D(hp.basis.scaled(Vector3.ONE * 0.001), hp.origin))

## Shoulder a, elbow b, wrist c; t and pole in skeleton space.
func _two_bone(sk: Skeleton3D, a: int, b: int, c: int, t: Vector3, pole: Vector3) -> void:
	var A := sk.get_bone_global_pose(a)
	var pa := A.origin
	var pb := sk.get_bone_global_pose(b).origin
	var pc := sk.get_bone_global_pose(c).origin
	var l1 := pa.distance_to(pb)
	var l2 := pb.distance_to(pc)
	if l1 < 1e-5 or l2 < 1e-5: return
	var to := t - pa
	var d := clampf(to.length(), absf(l1 - l2) + 1e-4, l1 + l2 - 1e-4)
	var dir := to.normalized()
	var side := pole - pa
	side = side - dir * side.dot(dir)
	if side.length() < 1e-5: side = Vector3.UP.cross(dir)
	side = side.normalized()
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var elbow := pa + dir * (l1 * cos_a) + side * (l1 * sqrt(maxf(0.0, 1.0 - cos_a * cos_a)))
	var hand := pa + dir * d
	# upper arm: turn it so the elbow lands on its new spot
	var q1 := Quaternion((pb - pa).normalized(), (elbow - pa).normalized())
	sk.set_bone_global_pose(a, Transform3D(Basis(q1) * A.basis, pa))
	# forearm: turn it so the wrist lands on the target
	var B := sk.get_bone_global_pose(b)
	var pc2 := sk.get_bone_global_pose(c).origin
	var q2 := Quaternion((pc2 - B.origin).normalized(), (hand - B.origin).normalized())
	sk.set_bone_global_pose(b, Transform3D(Basis(q2) * B.basis, B.origin))
