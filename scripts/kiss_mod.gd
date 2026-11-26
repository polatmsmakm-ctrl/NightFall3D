extends SkeletonModifier3D
## The kiss and the hug (scripts/kiss.gd), on one character, after the animation and before the arms'
## IK: the back leans in toward the other, the neck and head come forward and down (or up) to their
## face, and the head tips to the side so the two faces meet without the noses in the way.
## World-space settings, set every frame by NFKiss; `amt` eases everything in and out.

var amt := 0.0       # 0 none .. 1 the whole pose
var lean := 0.14     # radians the upper back bends forward
var pitch := 0.0     # radians the head nods down (+) toward the other face, or up (-)
var roll := 0.3      # radians the head tips sideways (the same sign on both: opposite sides in the world)
var turn := 0.08     # radians the head turns, with the tip
var fwd := Vector3.FORWARD
var left := Vector3.LEFT
var _ids := {}

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or amt <= 0.001: return
	if _ids.is_empty():
		for n in ["Spine", "Spine1", "Spine2", "Neck", "Head"]: _ids[n] = sk.find_bone("mixamorig_" + n)
	var inv := sk.global_basis.orthonormalized().inverse()
	var l := (inv * left).normalized()
	var f := (inv * fwd).normalized()
	var u := f.cross(l).normalized() # up, in the skeleton's space
	var bend := {"Spine": 0.2, "Spine1": 0.35, "Spine2": 0.45}
	for n in bend:
		var b: int = _ids[n]
		if b < 0: continue
		var gp := sk.get_bone_global_pose(b)
		gp.basis = Basis(l, lean * float(bend[n]) * amt) * gp.basis
		sk.set_bone_global_pose(b, gp)
	var nb: int = _ids["Neck"]
	if nb >= 0:
		var gp := sk.get_bone_global_pose(nb)
		gp.basis = Basis(l, pitch * 0.45 * amt) * Basis(f, roll * 0.35 * amt) * gp.basis
		sk.set_bone_global_pose(nb, gp)
	var hb: int = _ids["Head"]
	if hb >= 0:
		var gp := sk.get_bone_global_pose(hb)
		gp.basis = Basis(u, turn * amt) * Basis(l, pitch * 0.55 * amt) * Basis(f, roll * 0.65 * amt) * gp.basis
		sk.set_bone_global_pose(hb, gp)
