class_name NFLookMod
extends SkeletonModifier3D
## Turns a character's head toward something after the animation has posed the skeleton.
## The rest pose of these rigs is Z-down (up is -Z, they face +Y), so the yaw is taken in the
## skeleton's own frame and folded into each bone with pose * (G⁻¹ · R · G).

const UP := Vector3(0, 0, -1)
const RIGHT := Vector3(-1, 0, 0)
const MAX_YAW := 1.15
const MAX_PITCH := 0.5
## how much of the turn each bone takes
const SHARE := {"mixamorig_Head": 0.65, "mixamorig_Neck": 0.35}

var target := Vector3.ZERO
var want := 0.0   # where the blend is going
var _w := 0.0     # where it is now

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null: return
	_w = move_toward(_w, want, 3.0 * maxf(get_process_delta_time(), 0.001))
	if _w <= 0.002: return
	var head := sk.find_bone("mixamorig_Head")
	if head < 0: return
	var local: Vector3 = sk.global_transform.affine_inverse() * target
	var from: Vector3 = sk.get_bone_global_pose(head).origin
	var dir := local - from
	if dir.length() < 0.001: return
	var yaw := clampf(atan2(dir.x, dir.y), -MAX_YAW, MAX_YAW)          # +Y is straight ahead
	var flat := Vector2(dir.x, dir.y).length()
	var pitch := clampf(atan2(-dir.z, maxf(flat, 0.001)), -MAX_PITCH, MAX_PITCH) # -Z is up
	for bone in SHARE:
		var i := sk.find_bone(bone)
		if i < 0: continue
		var share: float = SHARE[bone] * _w
		var r := Quaternion(UP, yaw * share) * Quaternion(RIGHT, pitch * share)
		var g := sk.get_bone_global_pose(i).basis.get_rotation_quaternion()
		sk.set_bone_pose_rotation(i, sk.get_bone_pose_rotation(i) * (g.inverse() * r * g))
