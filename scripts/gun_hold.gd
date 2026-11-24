class_name NFGun
extends Node3D
## «وضع السلاح»: the pistol in a survivor's hand and the arms that hold it.
##  * lowered (`raise` 0): right hand at the hip, the muzzle toward the ground ahead, the left arm free
##    (it keeps swinging with the walk);
##  * aimed (`raise` 1): both hands out in front at shoulder height, the left one cupping the right,
##    the gun along the aim — and the aim follows the camera up and down (`pitch`);
##  * `kick` (0..1): the recoil of a shot, the muzzle jumping up and the hands back a little.
## The arms come from NFReach (two-bone IK after the animation), so the legs keep walking, running
## and crouching underneath. The pistol is the owner's `assets/props/gun.glb` when it is there
## (grip at the origin, barrel toward +Z, in metres), otherwise one built here.

var rig: CharacterRig
var model: Node3D
var raise := 0.0       # eased toward the wanted pose
var kick := 0.0
var muzzle_local := Vector3(0, 0.038, 0.155)

static var _mesh_cache: Array = []

func setup(r: CharacterRig) -> void:
	rig = r
	model = Node3D.new()
	add_child(model)
	if ResourceLoader.exists("res://assets/props/gun.glb"):
		model.add_child((load("res://assets/props/gun.glb") as PackedScene).instantiate())
	else:
		_build(model)
	for gi in model.find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false

## A compact pistol: slide with cocking serrations and sights, polymer frame, raked grip with its
## texture, trigger and guard, the barrel's mouth. 19 cm long, like a real one.
static func _build(into: Node3D) -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.13, 0.135, 0.14)
	steel.metallic = 0.85
	steel.roughness = 0.32
	var poly := StandardMaterial3D.new()
	poly.albedo_color = Color(0.05, 0.05, 0.055)
	poly.roughness = 0.62
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.01, 0.01, 0.01)
	dark.roughness = 0.9
	var parts := [
		# [size, position, rotation x (degrees), material]
		[Vector3(0.03, 0.03, 0.19), Vector3(0, 0.038, 0.06), 0.0, steel],      # slide
		[Vector3(0.026, 0.02, 0.155), Vector3(0, 0.014, 0.045), 0.0, poly],     # frame / dust cover
		[Vector3(0.027, 0.108, 0.046), Vector3(0, -0.046, -0.008), -16.0, poly], # grip, raked back
		[Vector3(0.029, 0.09, 0.008), Vector3(0, -0.044, -0.03), -16.0, dark],   # backstrap texture
		[Vector3(0.006, 0.026, 0.006), Vector3(0, -0.004, 0.034), 8.0, steel],   # trigger
		[Vector3(0.012, 0.004, 0.05), Vector3(0, -0.019, 0.04), 0.0, poly],      # trigger guard, bottom
		[Vector3(0.012, 0.022, 0.005), Vector3(0, -0.009, 0.064), 0.0, poly],    # trigger guard, front
		[Vector3(0.008, 0.006, 0.008), Vector3(0, 0.056, 0.145), 0.0, steel],    # front sight
		[Vector3(0.022, 0.007, 0.008), Vector3(0, 0.056, -0.025), 0.0, steel],   # rear sight
		[Vector3(0.028, 0.02, 0.012), Vector3(0, -0.098, -0.022), -16.0, poly],  # magazine base
	]
	for pp in parts:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = pp[0]
		bm.material = pp[3]
		mi.mesh = bm
		mi.position = pp[1]
		mi.rotation_degrees.x = pp[2]
		into.add_child(mi)
	for k in 6: # cocking serrations at the back of the slide
		var sr := MeshInstance3D.new()
		var bm2 := BoxMesh.new()
		bm2.size = Vector3(0.032, 0.022, 0.003)
		bm2.material = dark
		sr.mesh = bm2
		sr.position = Vector3(0, 0.04, -0.02 + k * 0.007)
		into.add_child(sr)
	var mouth := MeshInstance3D.new() # the barrel's mouth
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0055; cm.bottom_radius = 0.0055; cm.height = 0.004
	cm.material = dark
	mouth.mesh = cm
	mouth.rotation_degrees.x = 90.0
	mouth.position = Vector3(0, 0.038, 0.1555)
	into.add_child(mouth)

## Each frame. `show`: the gun is out at all; `want`: 0 lowered, 1 aimed; `pitch`: the aim up (+)
## or down (-) in radians; `yaw`: which way the aim faces.
func step(show: bool, want: float, pitch: float, yaw: float, dt: float) -> void:
	if rig == null: return
	if not show:
		if visible:
			visible = false
			rig.reach_clear()
		raise = 0.0
		return
	visible = true
	raise = move_toward(raise, want, dt * (7.0 if want > raise else 3.5))
	kick = maxf(kick - dt * 6.5, 0.0)
	var r := clampf(raise, 0.0, 1.0)
	var e := r * r * (3.0 - 2.0 * r) # smooth in and out
	var up := Vector3.UP
	var flat := Vector3(sin(yaw), 0, cos(yaw))
	var side := flat.cross(up).normalized() # the character's right (forward x up)
	var rs := rig.bone_at("mixamorig_RightArm")
	var ls := rig.bone_at("mixamorig_LeftArm")
	var mid := (rs + ls) * 0.5
	# aimed: out in front along the aim, a little right of the middle and under the eyes
	var p := clampf(pitch + kick * 0.35, -1.0, 1.0)
	var aim := (flat * cos(p) + up * sin(p)).normalized()
	var r_aim := mid + aim * (0.46 - kick * 0.05) + side * 0.045 - up * 0.07
	# lowered: by the right hip, the forearm forward, the muzzle down at the ground ahead
	var r_low := rs - up * 0.43 + flat * 0.2 + side * 0.03
	var low_dir := (flat * 0.55 - up * 0.83).normalized()
	var rw := r_low.lerp(r_aim, e)
	var gdir := low_dir.slerp(aim, e).normalized()
	var lw := rw - aim * 0.035 - side * 0.065 - up * 0.035 # the left hand cups the right
	var r_pole := rs + side * 0.35 - up * 0.45 - flat * 0.1
	var l_pole := ls - side * 0.35 - up * 0.45 - flat * 0.1
	rig.reach_arms(lw, rw, l_pole, r_pole, e > 0.35, (gdir + side * 0.15).normalized(), gdir)
	# the pistol sits in the palm of the REAL hand (where the arm actually got to, not where it was
	# asked to go), its barrel straight on from the forearm like a held gun, the grip under the hand
	var hand := rig.bone_at("mixamorig_RightHand")
	var elbow := rig.bone_at("mixamorig_RightForeArm")
	var fore := hand - elbow
	var barrel := gdir
	if fore.length() > 0.05: barrel = fore.normalized().slerp(gdir, 0.35).normalized()
	var grip_up := (up - barrel * barrel.dot(up))
	if grip_up.length() < 0.05: grip_up = flat
	grip_up = grip_up.normalized()
	var basis := Basis(grip_up.cross(barrel).normalized(), grip_up, barrel).orthonormalized() # a true rotation: x = up x forward
	var at := hand + barrel * 0.065 - grip_up * 0.012 if fore.length() > 0.05 else rw + gdir * 0.075
	model.global_transform = Transform3D(basis.scaled(Vector3.ONE * 1.12), at)

func shot() -> void:
	kick = 1.0

## Where the beam of a shot starts.
func muzzle() -> Vector3:
	return model.global_transform * muzzle_local
