extends Node3D
## NightFall step 1: a character walking in a lit 3D scene (keyboard + touch).

const WALK := 2.4
const RUN := 4.6
var body: CharacterBody3D
var rig: CharacterRig
var cam_pivot: Node3D
var yaw := 0.0
var pitch := -0.25
var stick_id := -1
var stick_origin := Vector2.ZERO
var stick_vec := Vector2.ZERO
var look_id := -1
var ui_stick: Control

func _ready() -> void:
	_build_world()
	_build_player("killer")
	_build_ui()

func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.03, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.3, 0.45)
	env.ambient_light_energy = 0.6
	env.fog_enabled = true
	env.fog_light_color = Color(0.08, 0.1, 0.14)
	env.fog_density = 0.035
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new(); we.environment = env; add_child(we)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-50, 30, 0)
	moon.light_color = Color(0.55, 0.65, 0.95)
	moon.light_energy = 0.9
	moon.shadow_enabled = true
	add_child(moon)
	var ground := StaticBody3D.new()
	var gm := MeshInstance3D.new()
	var plane := PlaneMesh.new(); plane.size = Vector2(200, 200)
	var gmat := StandardMaterial3D.new(); gmat.albedo_color = Color(0.1, 0.12, 0.08); gmat.roughness = 1.0
	plane.material = gmat; gm.mesh = plane; ground.add_child(gm)
	var gc := CollisionShape3D.new(); var gs := WorldBoundaryShape3D.new(); gc.shape = gs; ground.add_child(gc)
	add_child(ground)
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	for i in 40: # placeholder obstacles so movement is testable
		var b := StaticBody3D.new()
		var m := MeshInstance3D.new(); var bm := BoxMesh.new()
		bm.size = Vector3(rng.randf_range(1, 4), rng.randf_range(1.5, 4), rng.randf_range(1, 4))
		var mat := StandardMaterial3D.new(); mat.albedo_color = Color(0.2, 0.18, 0.16); bm.material = mat
		m.mesh = bm; b.add_child(m)
		var c := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = bm.size; c.shape = bs; b.add_child(c)
		b.position = Vector3(rng.randf_range(-40, 40), bm.size.y / 2, rng.randf_range(-40, 40))
		if b.position.length() < 5: b.position.x += 8
		add_child(b)

func _build_player(char_name: String) -> void:
	body = CharacterBody3D.new()
	var cs := CollisionShape3D.new(); var cap := CapsuleShape3D.new(); cap.radius = 0.35; cap.height = 1.8
	cs.shape = cap; cs.position.y = 0.9; body.add_child(cs)
	rig = CharacterRig.new(); body.add_child(rig); rig.setup(char_name)
	add_child(body)
	cam_pivot = Node3D.new(); cam_pivot.position.y = 1.6; body.add_child(cam_pivot)
	var cam := Camera3D.new(); cam.position = Vector3(0, 0.3, 3.6); cam_pivot.add_child(cam)
	var lamp := OmniLight3D.new(); lamp.position = Vector3(0, 2.2, 0.5); lamp.light_energy = 1.2; lamp.omni_range = 9
	lamp.light_color = Color(1.0, 0.8, 0.55); body.add_child(lamp)

func _build_ui() -> void:
	var layer := CanvasLayer.new(); add_child(layer)
	ui_stick = Control.new(); ui_stick.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_stick.mouse_filter = Control.MOUSE_FILTER_IGNORE; layer.add_child(ui_stick)
	ui_stick.draw.connect(_draw_stick)

func _draw_stick() -> void:
	if stick_id < 0: return
	ui_stick.draw_circle(stick_origin, 70, Color(1, 1, 1, 0.12))
	ui_stick.draw_circle(stick_origin + stick_vec * 70, 32, Color(1, 1, 1, 0.35))

func _input(e: InputEvent) -> void:
	var half := get_viewport().get_visible_rect().size.x / 2.0
	if e is InputEventScreenTouch:
		if e.pressed:
			if e.position.x < half and stick_id < 0:
				stick_id = e.index; stick_origin = e.position; stick_vec = Vector2.ZERO
			elif e.position.x >= half and look_id < 0:
				look_id = e.index
		else:
			if e.index == stick_id: stick_id = -1; stick_vec = Vector2.ZERO
			if e.index == look_id: look_id = -1
		ui_stick.queue_redraw()
	elif e is InputEventScreenDrag:
		if e.index == stick_id:
			stick_vec = ((e.position - stick_origin) / 70.0).limit_length(1.0)
			ui_stick.queue_redraw()
		elif e.index == look_id:
			yaw -= e.relative.x * 0.006
			pitch = clampf(pitch - e.relative.y * 0.004, -0.9, 0.3)
	elif e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= e.relative.x * 0.003
		pitch = clampf(pitch - e.relative.y * 0.003, -0.9, 0.3)
	elif e is InputEventMouseButton and e.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	var move := stick_vec
	if move == Vector2.ZERO:
		move = Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
		move += Vector2(float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
			float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)))
		move = move.limit_length(1.0)
	cam_pivot.rotation = Vector3(pitch, yaw, 0)
	var basis_y := Basis(Vector3.UP, yaw)
	var dir := basis_y * Vector3(move.x, 0, move.y)
	var speed := RUN if move.length() > 0.7 or Input.is_key_pressed(KEY_SHIFT) else WALK
	var target := dir.normalized() * speed * move.length() if move.length() > 0.05 else Vector3.ZERO
	body.velocity.x = move_toward(body.velocity.x, target.x, 30.0 * delta)
	body.velocity.z = move_toward(body.velocity.z, target.z, 30.0 * delta)
	body.velocity.y = -2.0
	body.move_and_slide()
	var hv := Vector2(body.velocity.x, body.velocity.z)
	if hv.length() > 0.2:
		var want := atan2(hv.x, hv.y) + PI
		rig.rotation.y = lerp_angle(rig.rotation.y, want - 0.0 + PI, 12.0 * delta)
		rig.play("run" if hv.length() > 3.5 else "walk", clampf(hv.length() / (4.6 if hv.length() > 3.5 else 2.4), 0.6, 1.3))
	else:
		rig.play("idle")
