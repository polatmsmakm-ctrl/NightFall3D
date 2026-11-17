class_name CharacterRig
extends Node3D
## Loads a rigged character GLB and attaches Mixamo animations (separate GLBs) to it.

## The clips a player's rig asks for. Anything missing from assets/anims is simply skipped, so
## the list can name clips the owner has not supplied yet: drop sprint.glb / hit.glb / fall.glb /
## standup.glb / cheer.glb in and the game starts using them with no code change.
const ANIMS := ["idle", "walk", "run", "sprint", "crouchwalk", "hide", "attack", "injured", "dying",
	"vault", "carry", "carried", "hang", "crawl", "repair", "hit", "fall", "standup", "slump"]
const ONCE := ["hit", "fall", "attack", "vault"] # played through once, then back to the state pose
const LOOPING := ["idle", "walk", "run", "sprint", "crouchwalk", "hide", "injured", "carry", "carried", "hang", "crawl", "repair", "campfire", "wave", "clap", "dance", "cheer", "slump"]
## Campfire emotes. There is no Mixamo clip for these in assets/anims, so they are posed here on the
## same skeleton: drop wave.glb / clap.glb / dance.glb in and the real clip is used instead.
const EMOTES := {"wave": 2.4, "clap": 2.2, "dance": 4.0, "slump": 3.0}
const EMOTE_BONES := ["mixamorig_Hips", "mixamorig_Spine", "mixamorig_Spine1", "mixamorig_Spine2",
	"mixamorig_Neck", "mixamorig_Head",
	"mixamorig_LeftShoulder", "mixamorig_LeftArm", "mixamorig_LeftForeArm", "mixamorig_LeftHand",
	"mixamorig_RightShoulder", "mixamorig_RightArm", "mixamorig_RightForeArm", "mixamorig_RightHand",
	"mixamorig_LeftUpLeg", "mixamorig_LeftLeg", "mixamorig_RightUpLeg", "mixamorig_RightLeg"]

var model: Node3D
var skeleton: Skeleton3D
var player := AnimationPlayer.new()
var current := ""

## `close_up` loads <char>_hi.glb when the owner has made one: the same sculpt at four or five
## times the detail, for the character select and the results stage where the camera is right in
## front of the character. The round itself always uses the small one.
func setup(char_name: String, anims: Array = ANIMS, close_up := false) -> void:
	var body_path := "res://assets/chars/%s%s.glb" % [char_name, "_hi" if close_up else ""]
	if not ResourceLoader.exists(body_path): body_path = "res://assets/chars/%s.glb" % char_name
	model = (load(body_path) as PackedScene).instantiate()
	add_child(model)
	NFLook.skin(model, body_path.get_file().get_basename()) # skin that lets light through, on Forward+
	# anisotropic filtering on the character's maps: Godot's glTF materials default to plain trilinear,
	# which smears the face, the fishnet and the buckles as soon as they are seen at an angle
	# (the level comes from Gfx: the viewport is set to 16x on «فائق», 4x below it)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		for s in (mesh.get_surface_count() if mesh else 0):
			var mat := (mi as MeshInstance3D).get_active_material(s) as BaseMaterial3D
			if mat: mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
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
	var side := Vector3(1, 0, 0) # lean forward / back, nod
	match a:
		"wave":
			# a big friendly wave: up on the toes, the whole arm swinging from the shoulder, the
			# body leaning into it, the other hand on the hip
			var swing := sin(ph * TAU * 3.0)
			var slow := sin(ph * TAU)
			match bone:
				"mixamorig_Hips": return _w(FWD, 0.05 * slow)
				"mixamorig_Spine": return _w(FWD, -0.06 - 0.03 * slow)
				"mixamorig_Spine1": return _w(UP, -0.1) * _w(FWD, -0.05)
				"mixamorig_Spine2": return _w(FWD, -0.04 * swing)
				"mixamorig_Neck": return _w(FWD, 0.06)
				"mixamorig_Head": return _w(FWD, 0.1 + 0.06 * swing) * _w(side, -0.06)
				"mixamorig_RightShoulder": return _w(R_LIFT, 0.1)
				"mixamorig_RightArm": return _w(UP, -0.1) * _w(R_LIFT, 1.25 + 0.08 * swing)    # elbow out at the shoulder
				"mixamorig_RightForeArm": return _w(R_LIFT, 0.55 + 0.5 * swing)               # the forearm swings side to side
				"mixamorig_RightHand": return _w(R_LIFT, 0.25 * swing)
				"mixamorig_LeftArm": return _w(L_LIFT, -0.85)                          # hand on the hip
				"mixamorig_LeftForeArm": return _w(L_LIFT, -1.45)
				"mixamorig_RightUpLeg": return _w(R_AXIS, 0.05 * maxf(slow, 0.0))
				"mixamorig_LeftUpLeg": return _w(R_AXIS, 0.05 * maxf(-slow, 0.0))
		"clap":
			# four claps to the loop, over the head on the last two, bouncing on the knees
			var beat := absf(sin(ph * TAU * 2.0))
			var open := 0.34 * (1.0 - beat)
			var high: float = clampf((ph - 0.42) * 6.0, 0.0, 1.0) * clampf((0.98 - ph) * 12.0, 0.0, 1.0)
			var turn := sin(ph * TAU)
			match bone:
				"mixamorig_Hips": return _w(UP, 0.12 * turn)
				"mixamorig_Spine": return _w(side, 0.05 * beat)
				"mixamorig_Spine1": return _w(UP, 0.1 * turn) * _w(side, 0.05 * beat - 0.1 * high)
				"mixamorig_Head": return _w(side, 0.1 * beat - 0.12 * high) * _w(FWD, 0.06 * turn)
				"mixamorig_RightArm": return _w(UP, 1.15 - open * 0.4) * _w(R_LIFT, -0.45 + 1.55 * high)
				"mixamorig_LeftArm": return _w(UP, -1.15 + open * 0.4) * _w(L_LIFT, -0.45 + 1.55 * high)
				"mixamorig_RightForeArm": return _w(UP, 1.5 - open - 0.55 * high)
				"mixamorig_LeftForeArm": return _w(UP, -1.5 + open + 0.55 * high)
				"mixamorig_RightUpLeg": return _w(KNEE, -0.12 * beat)
				"mixamorig_LeftUpLeg": return _w(KNEE, -0.12 * beat)
				"mixamorig_RightLeg": return _w(KNEE, 0.24 * beat)
				"mixamorig_LeftLeg": return _w(KNEE, 0.24 * beat)
		"dance":
			# two moves to the loop, blended: hands in the air with the hips swinging, then the
			# arms rolling in front of the chest while the feet step; the head keeps the beat
			var sway := sin(ph * TAU * 2.0)
			var beat2 := sin(ph * TAU * 4.0)
			var mix: float = 0.5 - 0.5 * cos(ph * TAU)      # 0 at the ends of the loop, 1 in the middle
			mix = mix * mix * (3.0 - 2.0 * mix)
			var step := sin(ph * TAU * 4.0)
			match bone:
				"mixamorig_Hips": return _w(UP, 0.3 * sway) * _w(FWD, 0.13 * sway)
				"mixamorig_Spine": return _w(FWD, -0.08 * sway)
				"mixamorig_Spine1": return _w(UP, -0.2 * sway) * _w(side, 0.06 * mix)
				"mixamorig_Spine2": return _w(FWD, -0.1 * sway) * _w(UP, -0.1 * sway)
				"mixamorig_Neck": return _w(side, 0.05 * beat2)
				"mixamorig_Head": return _w(FWD, 0.14 * sway) * _w(side, 0.1 * beat2)
				"mixamorig_RightShoulder": return _w(R_LIFT, 0.15 * (1.0 - mix))
				"mixamorig_LeftShoulder": return _w(L_LIFT, 0.15 * (1.0 - mix))
				"mixamorig_RightArm":
					return (_w(UP, 0.12) * _w(R_LIFT, 1.55 + 0.34 * sway)).slerp(_w(UP, 1.0 + 0.14 * beat2) * _w(R_LIFT, -0.2 + 0.26 * step), mix)
				"mixamorig_LeftArm":
					return (_w(UP, -0.12) * _w(L_LIFT, 1.55 - 0.34 * sway)).slerp(_w(UP, -1.0 + 0.14 * beat2) * _w(L_LIFT, -0.2 - 0.26 * step), mix)
				"mixamorig_RightForeArm":
					return _w(R_LIFT, 0.6 + 0.4 * beat2).slerp(_w(UP, 1.35 + 0.3 * step), mix)
				"mixamorig_LeftForeArm":
					return _w(L_LIFT, 0.6 - 0.4 * beat2).slerp(_w(UP, -1.35 + 0.3 * step), mix)
				"mixamorig_RightHand": return _w(R_AXIS, 0.3 * beat2)
				"mixamorig_LeftHand": return _w(R_AXIS, -0.3 * beat2)
				"mixamorig_RightUpLeg": return _w(KNEE, -0.34 * maxf(step, 0.0))
				"mixamorig_LeftUpLeg": return _w(KNEE, -0.34 * maxf(-step, 0.0))
				"mixamorig_RightLeg": return _w(KNEE, 0.62 * maxf(step, 0.0))
				"mixamorig_LeftLeg": return _w(KNEE, 0.62 * maxf(-step, 0.0))
		"slump":
			# knocked out in the car's passenger seat: reclined against the seat back, knees up in
			# the footwell, hands fallen in the lap, the head dropped onto one shoulder; only the
			# breath moves. (Checked offline on every character: with the 0.82 scale main gives it
			# in the car, head and feet stay between the floor and the roof.)
			var br := sin(ph * TAU)
			match bone:
				"mixamorig_Hips": return _w(side, -0.42)
				"mixamorig_Spine": return _w(side, -0.04 + 0.02 * br)
				"mixamorig_Spine1": return _w(side, 0.02)
				"mixamorig_Spine2": return _w(side, 0.06) * _w(FWD, 0.06)
				"mixamorig_Neck": return _w(side, 0.40) * _w(FWD, 0.18)
				"mixamorig_Head": return _w(side, 0.50) * _w(FWD, 0.50)
				"mixamorig_RightShoulder": return _w(R_LIFT, -0.10)
				"mixamorig_LeftShoulder": return _w(L_LIFT, -0.10)
				"mixamorig_RightArm": return _w(UP, 0.45) * _w(R_LIFT, -1.25)
				"mixamorig_LeftArm": return _w(UP, -0.45) * _w(L_LIFT, -1.25)
				"mixamorig_RightForeArm": return _w(UP, 0.80)
				"mixamorig_LeftForeArm": return _w(UP, -0.80)
				"mixamorig_RightUpLeg": return _w(KNEE, -1.30) * _w(FWD, -0.14)
				"mixamorig_LeftUpLeg": return _w(KNEE, -1.30) * _w(FWD, 0.14)
				"mixamorig_RightLeg": return _w(KNEE, 1.75)
				"mixamorig_LeftLeg": return _w(KNEE, 1.75)
	return Quaternion.IDENTITY

## Bake an emote into a looping Animation on this character's skeleton.
func _emote_anim(a: String, skel_path: String, char_rest: Vector3) -> Animation:
	var out := Animation.new()
	out.length = EMOTES[a]
	out.loop_mode = Animation.LOOP_LINEAR
	var steps := 48
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
	# the hop: in hips local space z is the vertical axis and -z is up
	var dip := {"dance": [3.0, 4.0], "clap": [0.0, 1.0], "wave": [1.2, 3.0], "slump": [0.0, 1.0]}
	if float(dip[a][0]) > 0.0:
		var tr := out.add_track(Animation.TYPE_POSITION_3D)
		out.track_set_path(tr, NodePath("%s:mixamorig_Hips" % skel_path))
		for k in steps + 1:
			var ph := float(k) / steps
			out.position_track_insert_key(tr, out.length * ph, char_rest + Vector3(0, 0, -float(dip[a][0]) * absf(sin(ph * PI * float(dip[a][1])))))
	return out

## Is this clip actually available on this character? (false until the GLB is dropped in)
func has(anim: String) -> bool:
	return player.has_animation(anim)

func play(anim: String, speed := 1.0) -> void:
	if current == anim and player.speed_scale == speed: return
	if not player.has_animation(anim): return
	current = anim
	player.speed_scale = speed
	player.play(anim, 0.2)
