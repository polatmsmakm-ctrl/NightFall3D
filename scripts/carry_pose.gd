extends RefCounted
## The killer carries a survivor over her right shoulder (the owner: "on its shoulder and catching
## its legs"): the survivor folded at the hips across the shoulder (`draped`, posed in code in
## character_rig.gd), head and arms hanging down her back, legs down her front, and her right arm
## wrapped over the backs of the thighs (NFReach) while the left swings with her walk.
## No class_name: `const Carry := preload("res://scripts/carry_pose.gd")`.

const TILT := 1.45      # how far the folded body is turned from standing, about its own side axis
const LIFT := 0.17      # the hips sit this far above her shoulder joint
const IN := 0.07        # and this far in toward her neck

## Put the survivor on the killer's shoulder and the killer's right hand on their legs. Every frame,
## after both have been animated (the shoulder moves with her walk).
static func place(k: CharacterRig, v: CharacterRig) -> void:
	if k == null or v == null or k.skeleton == null or v.skeleton == null: return
	var kb := k.global_transform.basis.orthonormalized()
	var up := Vector3.UP
	var fwd := (kb * Vector3(0, 0, 1)); fwd.y = 0.0; fwd = fwd.normalized()
	var right := up.cross(fwd).normalized() * -1.0 # her right hand side (she faces +z, +x is her left)
	var sh := k.bone_at("mixamorig_RightArm")
	var neck := k.bone_at("mixamorig_Neck")
	var target := sh + up * LIFT + (neck - sh) * Vector3(1, 0, 1) * IN / maxf((neck - sh).length(), 0.01)
	# the body across the shoulder, head behind her: turned to face her back, then folded over
	var yaw := atan2(fwd.x, fwd.z) + PI
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, TILT)
	v.global_transform = Transform3D(b, v.global_position)
	var hips := v.bone_at("mixamorig_Hips")
	v.global_position += target - hips
	# her right hand over the backs of their thighs, the elbow out to the side
	var thigh := (v.bone_at("mixamorig_LeftUpLeg").lerp(v.bone_at("mixamorig_LeftLeg"), 0.4) + v.bone_at("mixamorig_RightUpLeg").lerp(v.bone_at("mixamorig_RightLeg"), 0.4)) * 0.5
	var hand := thigh + fwd * 0.12 + right * 0.02
	var pole := sh + right * 0.5 - up * 0.25 + fwd * 0.25
	k.reach_arms(hand, hand, pole, pole, false, Vector3.ZERO, -right)
	k.grip(0.0, 0.7) # her fingers round the backs of their thighs

## Let go of the arm (she dropped them, hooked them, got stunned).
static func release(k: CharacterRig) -> void:
	if k: k.reach_clear()
