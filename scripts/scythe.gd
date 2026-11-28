class_name NFScythe
extends Node3D
## The owner's Thorned Scythe (assets/props/scythe.glb, his model as he sent it, 10k triangles) in the
## right hand of the three new killers (`USERS`). Placed every frame from where the hand really is: the
## handle runs through the fist alongside the forearm (up the arm, the blade over her head), the blade's
## inner edge toward where she faces, so it follows the walk and sweeps with the attack clip. In first person the killer's own body is
## hidden, so `view()` makes a second scythe held in front of the camera that swings on the attack.
const USERS := ["killer3", "killer4", "killer5"]
const MODEL := "res://assets/props/scythe.glb"
# in the model: the pommel at (0.52, -0.93), the handle up and to the left, the blade curling over the top
const H_MODEL := Vector3(-0.55, 0.83, 0.0)  # along the handle, toward the blade
const B_MODEL := Vector3(0.83, 0.55, 0.0)   # the side the blade's inner edge faces
const GRIP := Vector3(0.36, -0.69, 0.0)     # where the fist closes on the handle
var rig: CharacterRig
var model: Node3D
var _m_inv: Basis

static func uses(char_name: String) -> bool:
	return char_name in USERS

static func _load() -> Node3D:
	if not ResourceLoader.exists(MODEL): return null
	return (load(MODEL) as PackedScene).instantiate() as Node3D

func setup(r: CharacterRig) -> void:
	rig = r
	model = _load()
	if model == null: return
	add_child(model)
	var h := H_MODEL.normalized()
	var b := (B_MODEL - h * B_MODEL.dot(h)).normalized()
	_m_inv = Basis(h, b, h.cross(b)).inverse()
	top_level = true

func _process(_dt: float) -> void:
	if rig == null or model == null or not is_instance_valid(rig): return
	visible = rig.is_visible_in_tree()
	if not visible: return
	var hand := rig.bone_at("mixamorig_RightHand")
	var elbow := rig.bone_at("mixamorig_RightForeArm")
	var a := elbow - hand # the handle runs through the fist alongside the forearm: up the arm, the blade overhead
	if a.length() < 0.01: a = Vector3.UP
	a = (a.normalized() + Vector3.UP * 0.8).normalized() # and a little toward the sky, so a reaching arm still holds it up
	var fwd := rig.global_transform.basis.z # the blade's inner edge faces where she is going
	var f := fwd - a * fwd.dot(a)
	if f.length() < 0.05: f = rig.global_transform.basis.x - a * rig.global_transform.basis.x.dot(a)
	f = f.normalized()
	var fingers := (hand - elbow).normalized() * 0.09
	var w := Basis(a, f, a.cross(f)) * _m_inv
	var grip_at := hand + fingers * 0.55
	global_transform = Transform3D(w, grip_at - w * GRIP)

## First person: the scythe low on the right of the view; `swing()` sweeps it across on the attack.
static func view(cam: Camera3D) -> Node3D:
	var m := _load()
	if m == null: return null
	var pivot := Node3D.new()
	pivot.name = "ScytheView"
	cam.add_child(pivot)
	pivot.position = Vector3(0.42, -0.5, -0.75)
	pivot.rotation = Vector3(0.25, -0.35, 0.55)
	m.scale = Vector3(0.55, 0.55, 0.55)
	m.position = -GRIP * 0.55
	pivot.add_child(m)
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.set_meta("rest", pivot.transform)
	return pivot

static func swing(pivot: Node3D) -> void:
	if pivot == null: return
	var rest: Transform3D = pivot.get_meta("rest")
	var tw := pivot.create_tween()
	tw.tween_property(pivot, "rotation", Vector3(0.5, -0.1, 1.2), 0.18).set_trans(Tween.TRANS_SINE) # wind up
	tw.tween_property(pivot, "rotation", Vector3(-0.3, 0.5, -0.9), 0.16).set_trans(Tween.TRANS_QUAD)  # the cut
	tw.tween_property(pivot, "transform", rest, 0.45).set_trans(Tween.TRANS_SINE)
