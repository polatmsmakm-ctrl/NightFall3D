extends SceneTree
func dump(n: Node, d: int, maxd: int):
	if d > maxd: return
	print("  ".repeat(d), n.name, " [", n.get_class(), "]")
	for c in n.get_children(): dump(c, d+1, maxd)
func _init():
	for p in ["res://assets/chars/killer.glb", "res://assets/anims/walk.glb"]:
		var s: Node = load(p).instantiate()
		print("== ", p)
		dump(s, 0, 3)
		for ap in s.find_children("*", "AnimationPlayer", true, false):
			for a in ap.get_animation_list():
				var an: Animation = ap.get_animation(a)
				print("anim ", a, " len ", an.length, " tracks ", an.get_track_count())
				if an.get_track_count() > 0: print("  first: ", an.track_get_path(0))
		var sk = s.find_children("*", "Skeleton3D", true, false)
		for k in sk: print("skeleton ", k.get_path(), " bones ", k.get_bone_count(), " b0 ", k.get_bone_name(0))
	quit()
