class_name CharacterRig
extends Node3D
## Loads a rigged character GLB and attaches Mixamo animations (separate GLBs) to it.

const ANIMS := ["idle", "walk", "run", "crouchwalk", "hide", "attack", "injured", "dying", "vault", "carry", "carried", "hang", "crawl", "repair"]
const LOOPING := ["idle", "walk", "run", "sprint", "crouchwalk", "hide", "injured", "carry", "carried", "hang", "crawl", "repair", "campfire"]

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
		var res = load("res://assets/anims/%s.glb" % a)
		if res == null: continue
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

func play(anim: String, speed := 1.0) -> void:
	if current == anim and player.speed_scale == speed: return
	if not player.has_animation(anim): return
	current = anim
	player.speed_scale = speed
	player.play(anim, 0.2)
