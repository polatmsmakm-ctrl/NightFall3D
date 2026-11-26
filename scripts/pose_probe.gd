extends SkeletonModifier3D
## Where a few bones really are once every modifier has run (the hunch, the kiss, the arms' IK).
## Since Godot 4.3 a skeleton puts its bones back as the animation left them after the modifiers have
## been drawn, so reading a bone from outside (CharacterRig.bone_at) gives the pose *before* the IK —
## a hand by the hip while the IK has it over the head. This one sits last on the skeleton and writes
## down the finished transforms every update (one frame old when read). No class_name.

var bones := ["mixamorig_Head", "mixamorig_LeftHand", "mixamorig_RightHand"]
var at := {}    # bone name -> world Transform3D
var _ids := {}

## The probe on this rig (made the first time), kept last among the skeleton's modifiers.
static func of(r: CharacterRig) -> Node:
	if r == null or r.skeleton == null: return null
	var sk := r.skeleton
	var p: Node = null
	for c in sk.get_children():
		if c.has_meta("pose_probe"): p = c
	if p == null:
		p = (load("res://scripts/pose_probe.gd") as GDScript).new()
		p.name = "Probe"
		p.set_meta("pose_probe", true)
		sk.add_child(p)
	if p.get_index() != sk.get_child_count() - 1: sk.move_child(p, -1)
	return p

## A bone's finished world transform, or the plain pose until the first update.
static func xf(r: CharacterRig, bone: String) -> Transform3D:
	var p = of(r)
	if p != null and p.at.has(bone): return p.at[bone]
	var b := r.skeleton.find_bone(bone)
	return r.skeleton.global_transform * r.skeleton.get_bone_global_pose(b)

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null: return
	for b in bones:
		if not _ids.has(b): _ids[b] = sk.find_bone(b)
		var i: int = _ids[b]
		if i >= 0: at[b] = sk.global_transform * sk.get_bone_global_pose(i)
