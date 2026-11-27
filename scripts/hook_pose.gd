extends RefCounted
## Hanging on the gallows' hook (the owner: "the hook enters through the victim's back and emerges from
## their chest ... struggling to pull the hook out"). The gallows model (assets/props/hook.glb, at the
## hook point, facing +z) brings its hook down behind the victim, curves it through at about 2.45 m
## and lifts the point up in front of them; the survivor hangs on that curve: chest (Spine2) at
## CHEST, back toward the shank, the point out of the front, both hands round it. `impaled` (posed in
## code in character_rig.gd) hangs limp and sways; while they struggle (`impaled_kick`) the legs kick,
## the body twists and the hands pull at the point.
## No class_name: `const Impale := preload("res://scripts/hook_pose.gd")`.

const CHEST := 2.55           # the chest bone this far above the hook point: the hook's curve (2.42 m) runs through it
const TIP := Vector3(0.0, 2.64, 1.16) # where the point comes out in front of the chest (hook-point space)

## Put the hanging survivor on the hook at `at` (the hook point, world). `struggle` 0..1, `t` seconds.
static func place(r: CharacterRig, at: Vector3, struggle: float, t: float, dt: float) -> void:
	if r == null or r.skeleton == null: return
	r.play("impaled_kick" if struggle > 0.05 else "impaled")
	r.rotation = Vector3.ZERO
	var chest_h: float = r.bone_at("mixamorig_Spine2").y - r.global_position.y
	var par := r.get_parent() as Node3D
	var want: float = CHEST - chest_h + (at.y - par.global_position.y if par else 0.0)
	r.position.y = lerpf(r.position.y, want, 1.0 - exp(-10.0 * dt))
	# both hands round the point, pulling at it while they struggle
	var pull := struggle * sin(t * 13.0)
	var tip := at + TIP + Vector3(0, 0.05 * pull, 0.05 * maxf(pull, 0.0))
	var l := tip + Vector3(0.055, -0.05, 0.0)   # (she faces +z: her left hand is on +x)
	var rr := tip + Vector3(-0.055, 0.02, 0.0)
	r.reach_arms(l, rr, at + Vector3(0.55, 2.25, 0.95), at + Vector3(-0.55, 2.25, 0.95), true, Vector3.ZERO, Vector3.ZERO)
	r.grip(0.85, 0.85)
	r.set_meta("impaled", true)

## Off the hook (saved, free, dead): let go of the point.
static func release(r: CharacterRig) -> void:
	if r and r.has_meta("impaled"):
		r.remove_meta("impaled")
		r.reach_clear()
