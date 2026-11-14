class_name CharacterRig
extends Node3D
## Loads a rigged character GLB and attaches Mixamo animations (separate GLBs) to it.

const ANIMS := ["idle", "walk", "run", "crouchwalk", "hide", "attack", "injured", "dying", "vault", "carry", "carried", "hang", "crawl", "repair"]
const LOOPING := ["idle", "walk", "run", "sprint", "crouchwalk", "hide", "injured", "carry", "carried", "hang", "crawl", "repair", "campfire", "wave", "clap", "dance"]
## Campfire emotes. There is no Mixamo clip for these in assets/anims, so they are posed here on the
## same skeleton: drop wave.glb / clap.glb / dance.glb in and the real clip is used instead.
const EMOTES := {"wave": 2.0, "clap": 1.1, "dance": 1.8}
const EMOTE_BONES := ["mixamorig_Hips", "mixamorig_Spine", "mixamorig_Spine1", "mixamorig_Spine2",
	"mixamorig_Neck", "mixamorig_Head",
	"mixamorig_LeftShoulder", "mixamorig_LeftArm", "mixamorig_LeftForeArm", "mixamorig_LeftHand",
	"mixamorig_RightShoulder", "mixamorig_RightArm", "mixamorig_RightForeArm", "mixamorig_RightHand",
	"mixamorig_LeftUpLeg", "mixamorig_LeftLeg", "mixamorig_RightUpLeg", "mixamorig_RightLeg"]

var model: Node3D
var skeleton: Skeleton3D
var player := AnimationPlayer.new()
var current := ""

func setup(char_name: String, anims: Array = ANIMS) -> void:
	model = (load("res://assets/chars/%s.glb" % char_name) as PackedScene).instantiate()
	add_child(model)
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	player.name = "Anim"
	model.add_child(player)
	player.root_node = player.get_path_to(model)
	var lib := AnimationLibrary.new()
	var skel_path := str(model.get_path_to(skeleton))
	var char_rest := skeleton.get_bone_rest(skeleton.find_bone("mixamorig_Hips")).origin
	for a in anims:
		var path := "res://assets/anims/%s.glb" % a
		var res = load(path) if ResourceLoader.exists(path) else null
		if res == null:
			if EMOTES.has(a): lib.add_animation(a, _emote_anim(a, skel_path, char_rest)) # posed in code
			continue
		var inst: Node = (res as PackedScene).instantiate()
		var src_player: AnimationPlayer = inst.find_children("*", "AnimationPlayer", true, false)[0]
		var src: Animation = src_player.get_animation(src_player.get_animation_list()[0])
		var anim_hips := inst.find_child("mixamorig_Hips", true, false) as Node3D
		var ratio := 1.0
		var anim_rest := Vector3.ZERO
		if anim_hips and anim_hips.position.length() > 0.0001:
			anim_rest = anim_hips.position
			ratio = char_rest.length() / anim_rest.length()
		var out := Animation.new()
		out.length = src.length
		out.loop_mode = Animation.LOOP_LINEAR if a in LOOPING else Animation.LOOP_NONE
		for t in src.get_track_count():
			var p := str(src.track_get_path(t))
			var bone := p.get_slice("/", p.get_slice_count("/") - 1).get_slice(":", 0)
			if skeleton.find_bone(bone) < 0: continue
			var ty := src.track_get_type(t)
			var is_hips := bone == "mixamorig_Hips"
			if ty == Animation.TYPE_POSITION_3D and not is_hips: continue
			var nt := out.add_track(ty)
			out.track_set_path(nt, NodePath("%s:%s" % [skel_path, bone]))
			for k in src.track_get_key_count(t):
				var time := src.track_get_key_time(t, k)
				var v = src.track_get_key_value(t, k)
				if ty == Animation.TYPE_POSITION_3D:
					# hips local space: z is vertical. Keep only the vertical bob (in place, no root motion).
					v = char_rest + Vector3(0, 0, ((v as Vector3).z - anim_rest.z) * ratio)
				out.track_insert_key(nt, time, v)
		lib.add_animation(a, out)
		inst.queue_free()
	player.add_animation_library("", lib)
	play("idle")

# ---------------- hand-posed emotes ----------------
## The Mixamo rest pose these characters carry is a T-pose in a Z-down skeleton space:
## up is -Z, the character faces +Y, the right arm lies along -X. (tools/bones.tscn prints it.)
const UP := Vector3(0, 0, -1)
const FWD := Vector3(0, 1, 0)
const R_LIFT := Vector3(0, -1, 0)  # turning the RIGHT arm about this raises it
const L_LIFT := Vector3(0, 1, 0)   # and this one raises the LEFT arm
const R_AXIS := Vector3(-1, 0, 0)  # along the right arm: spinning it rolls the hand
const KNEE := Vector3(1, 0, 0)     # bends a knee backwards

static func _w(axis: Vector3, angle: float) -> Quaternion:
	return Quaternion(axis.normalized(), angle)

## Where a bone should point during an emote, in skeleton space (identity = leave it at rest).
## Arms must always be posed: at rest they stick straight out in a T.
func _emote_world(a: String, bone: String, ph: float) -> Quaternion:
	match a:
		"wave":
			var swing := sin(ph * TAU * 2.0)
			match bone:
				"mixamorig_RightArm": return _w(UP, -0.05) * _w(R_LIFT, 1.9)      # up beside the head
				"mixamorig_RightForeArm": return _w(R_AXIS, 0.38 * swing) * _w(R_LIFT, 0.45)
				"mixamorig_RightHand": return _w(R_AXIS, 0.25 * swing)
				"mixamorig_LeftArm": return _w(UP, -0.12) * _w(L_LIFT, -1.3)      # the other arm rests
				"mixamorig_LeftForeArm": return _w(L_LIFT, 0.3)
				"mixamorig_Head": return _w(FWD, 0.07 * swing)
				"mixamorig_Spine1": return _w(UP, -0.08)
		"clap":
			var beat := absf(sin(ph * TAU))   # hands meet twice a loop
			var open := 0.3 * (1.0 - beat)
			match bone:
				"mixamorig_RightArm": return _w(UP, 1.15 - open * 0.4) * _w(R_LIFT, -0.45)
				"mixamorig_LeftArm": return _w(UP, -1.15 + open * 0.4) * _w(L_LIFT, -0.45)
				"mixamorig_RightForeArm": return _w(UP, 1.5 - open)
				"mixamorig_LeftForeArm": return _w(UP, -1.5 + open)
				"mixamorig_Spine1": return _w(Vector3(1, 0, 0), 0.06 * beat)
				"mixamorig_Head": return _w(Vector3(1, 0, 0), 0.05 * beat)
		"dance":
			var sway := sin(ph * TAU)
			var sway2 := sin(ph * TAU * 2.0)
			match bone:
				"mixamorig_Hips": return _w(UP, 0.25 * sway) * _w(FWD, 0.08 * sway)
				"mixamorig_Spine1": return _w(UP, -0.14 * sway)
				"mixamorig_Spine2": return _w(FWD, -0.1 * sway)
				"mixamorig_Head": return _w(FWD, 0.12 * sway) * _w(Vector3(1, 0, 0), 0.07 * sway2)
				"mixamorig_RightArm": return _w(UP, 0.12) * _w(R_LIFT, 1.5 + 0.32 * sway)
				"mixamorig_LeftArm": return _w(UP, -0.12) * _w(L_LIFT, 1.5 - 0.32 * sway)
				"mixamorig_RightForeArm": return _w(R_LIFT, 0.55 + 0.35 * sway2)
				"mixamorig_LeftForeArm": return _w(L_LIFT, 0.55 - 0.35 * sway2)
				"mixamorig_RightUpLeg": return _w(R_AXIS, 0.18 * maxf(sway2, 0.0))
				"mixamorig_LeftUpLeg": return _w(R_AXIS, 0.18 * maxf(-sway2, 0.0))
				"mixamorig_RightLeg": return _w(KNEE, 0.35 * maxf(sway2, 0.0))
				"mixamorig_LeftLeg": return _w(KNEE, 0.35 * maxf(-sway2, 0.0))
	return Quaternion.IDENTITY

## Bake an emote into a looping Animation on this character's skeleton.
func _emote_anim(a: String, skel_path: String, char_rest: Vector3) -> Animation:
	var out := Animation.new()
	out.length = EMOTES[a]
	out.loop_mode = Animation.LOOP_LINEAR
	var steps := 24
	for bone in EMOTE_BONES:
		var bi := skeleton.find_bone(bone)
		if bi < 0: continue
		var rest := skeleton.get_bone_rest(bi)
		var rest_q := rest.basis.get_rotation_quaternion()
		# a rotation written in model space becomes a local one by conjugating with the bone's global rest
		var gq := skeleton.get_bone_global_rest(bi).basis.get_rotation_quaternion()
		var gq_inv := gq.inverse()
		var keys := []
		var moves := false
		for k in steps + 1:
			var w := _emote_world(a, bone, float(k) / steps)
			if not w.is_equal_approx(Quaternion.IDENTITY): moves = true
			keys.append(rest_q * (gq_inv * w * gq))
		if not moves: continue
		var tr := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(tr, NodePath("%s:%s" % [skel_path, bone]))
		for k in steps + 1:
			out.rotation_track_insert_key(tr, out.length * float(k) / steps, keys[k])
	if a == "dance": # a little bounce; in hips local space z is the vertical axis
		var tr := out.add_track(Animation.TYPE_POSITION_3D)
		out.track_set_path(tr, NodePath("%s:mixamorig_Hips" % skel_path))
		for k in steps + 1:
			var ph := float(k) / steps
			out.position_track_insert_key(tr, out.length * ph, char_rest + Vector3(0, 0, -2.5 * absf(sin(ph * TAU))))
	return out

func play(anim: String, speed := 1.0) -> void:
	if current == anim and player.speed_scale == speed: return
	if not player.has_animation(anim): return
	current = anim
	player.speed_scale = speed
	player.play(anim, 0.2)
