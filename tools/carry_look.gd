extends Node
## The carry as it is drawn in the round: the killer in `carry`, the survivor in `carried` at
## main._carry_spot (0.5 m ahead, turned 90°, lifted 0.12 m). Side, front and back views.
## NF_SHOTS=dir xvfb-run -a godot --rendering-driver opengl3 --path . res://tools/carry_look.tscn

func _ready() -> void:
	var dir := OS.get_environment("NF_SHOTS")
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
	var k := CharacterRig.new()
	vp.add_child(k)
	k.setup(OS.get_environment("NF_KILLER") if OS.get_environment("NF_KILLER") != "" else "killer", ["carry", "idle", "walk"], false, false)
	k.play("walk")
	var v := CharacterRig.new()
	vp.add_child(v)
	v.setup("survivor10", ["carried", "draped", "idle"], false, false)
	v.play("carried")
	if has_node("/root/Main"): pass
	var fn = load("res://scripts/carry_pose.gd")
	for i in 3: await get_tree().process_frame
	if fn: fn.place(k, v)
	else:
		v.position = Vector3(0, 0.12, 0.5)
		v.rotation.y = PI / 2.0
	var sun := DirectionalLight3D.new()
	vp.add_child(sun)
	sun.look_at_from_position(Vector3(2, 3, 3), Vector3(0, 1, 0))
	var cam := Camera3D.new()
	cam.fov = 40.0
	vp.add_child(cam)
	cam.current = true
	for view in [["side", Vector3(4.2, 1.3, 0.2)], ["front", Vector3(0.6, 1.4, 4.2)], ["back", Vector3(-0.6, 1.5, -4.2)], ["three_q", Vector3(3.0, 1.8, 3.0)]]:
		for f in [0.2, 0.6]:
			k.player.seek(k.player.current_animation_length * f, true)
			v.player.seek(v.player.current_animation_length * f, true)
			if fn: fn.place(k, v)
			cam.look_at_from_position(view[1], Vector3(0, 1.15, 0.1))
			for i in 3: await get_tree().process_frame
			await RenderingServer.frame_post_draw
			vp.get_texture().get_image().save_png("%s/carry_%s_%d.png" % [dir, view[0], int(f * 10)])
	get_tree().quit()
