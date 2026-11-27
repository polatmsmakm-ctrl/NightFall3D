extends Node
## A survivor on the gallows' hook (scripts/hook_pose.gd): hanging and struggling, from the side,
## the front and behind. NF_SHOTS=dir NF_CHAR=survivor10
const Impale := preload("res://scripts/hook_pose.gd")
func _ready() -> void:
	var dir := OS.get_environment("NF_SHOTS")
	var id := OS.get_environment("NF_CHAR") if OS.get_environment("NF_CHAR") != "" else "survivor10"
	var vp := SubViewport.new()
	vp.size = Vector2i(480, 480)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.15, 0.15, 0.17)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.8, 0.85)
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var hook: Node3D = (load("res://assets/props/hook.glb") as PackedScene).instantiate()
	vp.add_child(hook)
	var node := Node3D.new()
	node.position = Vector3(0, 0, 0.9)
	vp.add_child(node)
	var rig := CharacterRig.new()
	node.add_child(rig)
	rig.setup(id, ["idle", "attack", "impaled", "impaled_kick"], false, false)
	var sun := DirectionalLight3D.new()
	vp.add_child(sun)
	sun.look_at_from_position(Vector3(2, 4, 4), Vector3(0, 2, 0))
	var cam := Camera3D.new()
	cam.fov = 40.0
	vp.add_child(cam)
	cam.current = true
	var t := 0.0
	for st in [["hang", 0.0], ["struggle", 1.0]]:
		for i in 80:
			t += 1.0 / 30.0
			Impale.place(rig, Vector3.ZERO, float(st[1]), t, 1.0 / 30.0)
			await get_tree().process_frame
		print("rig y=", rig.position.y, " chest=", rig.bone_at("mixamorig_Spine2"), " hips=", rig.bone_at("mixamorig_Hips"), " anim=", rig.current)
		for view in [["side", Vector3(3.6, 2.5, 1.0)], ["front", Vector3(1.6, 2.6, 4.0)], ["back", Vector3(-1.4, 2.8, -2.4)], ["close", Vector3(1.3, 2.75, 2.0)]]:
			cam.look_at_from_position(view[1], Vector3(0, 2.0 if view[0] != "close" else 2.5, 0.9))
			for i in 3:
				t += 1.0 / 30.0
				Impale.place(rig, Vector3.ZERO, float(st[1]), t, 1.0 / 30.0)
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			vp.get_texture().get_image().save_png("%s/hook_%s_%s.png" % [dir, st[0], view[0]])
	get_tree().quit()
