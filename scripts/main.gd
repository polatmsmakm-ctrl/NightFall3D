extends Node3D
## NightFall game scene: menu -> world -> local player (touch controls) + online players + minimap.

const SPEED := { # walk, run, crouch
	"killer": [2.6, 4.9, 2.6],
	"survivor": [2.3, 4.4, 1.3],
}
const ACCEL := 22.0
const DECEL := 30.0

var menu: GameMenu
var world: NightWorld
var body: CharacterBody3D
var rig: CharacterRig
var cam_pivot: Node3D
var arm: SpringArm3D
var ui: Control
var minimap: Control
var started := false
var cfg := {}
var my_name := ""
var my_role := "killer"
var remotes := {} # name -> {node, rig, pos, yaw, anim, role}

var yaw := 0.0
var pitch := -0.25
var stick_id := -1
var stick_origin := Vector2.ZERO
var stick_vec := Vector2.ZERO
var look_id := -1
var crouch := false
var attack_t := 0.0
var attack_cd := 0.0
var send_t := 0.0

func _ready() -> void:
	menu = GameMenu.new()
	add_child(menu)
	menu.start_game.connect(_start)
	Net.message.connect(_on_net)

func _start(c: Dictionary) -> void:
	if started: return
	cfg = c
	my_name = str(c.me)
	menu.visible = false
	world = NightWorld.new()
	world.configure(str(c.map))
	add_child(world)
	world.build() # staged: terrain first, the rest over the next frames
	for p in c.players:
		if str(p.name) == my_name:
			my_role = str(p.role)
			_build_player(str(p.char), world.spawn_point(my_role, int(p.slot)))
		else:
			_add_remote(p)
	_build_ui()
	started = true

func _build_player(char_name: String, at: Vector3) -> void:
	body = CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35; cap.height = 1.8
	cs.shape = cap; cs.position.y = 0.9
	body.add_child(cs)
	rig = CharacterRig.new()
	body.add_child(rig)
	rig.setup(char_name)
	body.position = at
	body.floor_snap_length = 0.5
	body.floor_max_angle = deg_to_rad(50.0)
	add_child(body)
	world.follow = body
	cam_pivot = Node3D.new()
	cam_pivot.position.y = 1.6
	body.add_child(cam_pivot)
	arm = SpringArm3D.new() # keeps the camera from going through trees and walls
	var probe := SphereShape3D.new()
	probe.radius = 0.25
	arm.shape = probe
	arm.spring_length = 3.6
	arm.margin = 0.15
	arm.position.y = 0.3
	arm.add_excluded_object(body.get_rid())
	cam_pivot.add_child(arm)
	var cam := Camera3D.new()
	cam.far = 400.0
	arm.add_child(cam)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 2.2, 0.5)
	lamp.light_energy = 1.2; lamp.omni_range = 9
	lamp.light_color = Color(1.0, 0.8, 0.55)
	body.add_child(lamp)

func _add_remote(p: Dictionary) -> void:
	var node := Node3D.new()
	var r := CharacterRig.new()
	node.add_child(r)
	r.setup(str(p.char))
	node.position = world.spawn_point(str(p.role), int(p.slot))
	var tag := Label3D.new()
	tag.text = str(p.name)
	tag.font = Net.font
	tag.font_size = 48
	tag.pixel_size = 0.004
	tag.position.y = 2.25
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = Color(1, 0.4, 0.4) if str(p.role) == "killer" else Color(0.75, 0.9, 1)
	node.add_child(tag)
	add_child(node)
	remotes[str(p.name)] = {"node": node, "rig": r, "pos": node.position, "yaw": 0.0, "anim": "idle", "role": str(p.role)}

func _on_net(m: Dictionary) -> void:
	if not started: return
	match str(m.t):
		"st":
			var r = remotes.get(str(m.n))
			if r:
				r.pos = Vector3(m.p[0], m.p[1], m.p[2])
				r.yaw = float(m.p[3])
				r.anim = str(m.a)
		"left":
			var r = remotes.get(str(m.name))
			if r:
				r.node.queue_free()
				remotes.erase(str(m.name))
		"room":
			if not cfg.get("offline", false) and (str(m.get("code", "")) == "" or str(m.get("state", "")) == "lobby"):
				_to_menu()

func _to_menu() -> void:
	started = false
	get_tree().reload_current_scene.call_deferred()

func _leave() -> void:
	if cfg.get("offline", false):
		_to_menu()
	elif Net.in_room() and str(Net.room.get("host", "")) == my_name:
		Net.send({"t": "lobby"}) # host ends the round for everyone
	else:
		Net.send({"t": "leave"})

# ---------------- UI: stick, action button, minimap ----------------
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	ui.draw.connect(_draw_ui)
	minimap = Control.new()
	minimap.position = Vector2(16, 44)
	minimap.size = Vector2(150, 150)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(minimap)
	minimap.draw.connect(_draw_minimap)
	var leave := Button.new()
	leave.text = "خروج" if cfg.get("offline", false) or str(Net.room.get("host", "")) != my_name else "إنهاء الجولة"
	leave.focus_mode = Control.FOCUS_NONE
	leave.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	leave.offset_left = -300; leave.offset_right = -152; leave.offset_top = 12; leave.offset_bottom = 64
	leave.pressed.connect(_leave)
	layer.add_child(leave)

func _action_button() -> Array: # center, radius, label, id
	var s := get_viewport().get_visible_rect().size
	if my_role == "killer": return [Vector2(s.x - 130, s.y - 140), 60.0, "ضرب", "attack"]
	return [Vector2(s.x - 130, s.y - 140), 60.0, "انحناء", "crouch"]

func _draw_ui() -> void:
	if stick_id >= 0:
		ui.draw_circle(stick_origin, 70, Color(1, 1, 1, 0.12))
		ui.draw_circle(stick_origin + stick_vec * 70, 32, Color(1, 1, 1, 0.35))
	var b := _action_button()
	var active: bool = (b[3] == "crouch" and crouch) or (b[3] == "attack" and attack_cd > 0.0)
	ui.draw_circle(b[0], b[1], Color(0.9, 0.2, 0.2, 0.45) if active else Color(1, 1, 1, 0.16))
	ui.draw_arc(b[0], b[1], 0, TAU, 40, Color(1, 1, 1, 0.5), 2.0)
	ui.draw_string(Net.font, b[0] + Vector2(-b[1], 9), b[2], HORIZONTAL_ALIGNMENT_CENTER, b[1] * 2.0, 24)

func _draw_minimap() -> void:
	var half := 75.0
	var k := 150.0 / NightWorld.SIZE
	var c := Vector2(half, half)
	minimap.draw_rect(Rect2(Vector2.ZERO, Vector2(150, 150)), Color(0, 0, 0, 0.45))
	minimap.draw_rect(Rect2(Vector2.ZERO, Vector2(150, 150)), Color(1, 1, 1, 0.35), false, 1.5)
	for b in world.buildings:
		minimap.draw_set_transform(c + Vector2(b[0], b[1]) * k, -b[2], Vector2.ONE)
		minimap.draw_rect(Rect2(-Vector2(b[3], b[4]) * k / 2.0, Vector2(b[3], b[4]) * k), Color(0.75, 0.7, 0.6, 0.9))
	minimap.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for n in remotes: # survivors see their team; the killer has to hunt
		var r = remotes[n]
		if my_role == "survivor" and r.role == "survivor":
			var p: Vector3 = r.node.position
			minimap.draw_circle(c + Vector2(p.x, p.z) * k, 3.5, Color(0.4, 0.8, 1))
	var me := c + Vector2(body.position.x, body.position.z) * k
	var f := Vector2(-sin(yaw), -cos(yaw))
	var side := Vector2(-f.y, f.x)
	minimap.draw_colored_polygon(PackedVector2Array([me + f * 8.0, me - f * 4.0 + side * 5.0, me - f * 4.0 - side * 5.0]),
		Color(1, 0.3, 0.3) if my_role == "killer" else Color(1, 1, 1))

func _do_action(id: String) -> void:
	if id == "crouch": crouch = not crouch
	elif id == "attack" and attack_cd <= 0.0:
		attack_t = 0.9
		attack_cd = 2.0
		rig.play("attack", 1.3)

func _input(e: InputEvent) -> void:
	if not started: return
	if (e is InputEventScreenTouch or e is InputEventMouseButton) and e.pressed and Gfx.in_ui(e.position): return
	if Gfx.menu_open: return
	var half := get_viewport().get_visible_rect().size.x / 2.0
	if e is InputEventScreenTouch:
		if e.pressed:
			var b := _action_button()
			if e.position.distance_to(b[0]) < b[1] + 10.0:
				_do_action(b[3])
			elif e.position.x < half and stick_id < 0:
				stick_id = e.index; stick_origin = e.position; stick_vec = Vector2.ZERO
			elif e.position.x >= half and look_id < 0:
				look_id = e.index
		else:
			if e.index == stick_id: stick_id = -1; stick_vec = Vector2.ZERO
			if e.index == look_id: look_id = -1
	elif e is InputEventScreenDrag:
		if e.index == stick_id:
			stick_vec = ((e.position - stick_origin) / 70.0).limit_length(1.0)
			if stick_vec.length() < 0.12: stick_vec = Vector2.ZERO # dead zone
		elif e.index == look_id:
			yaw -= e.relative.x * 0.006
			pitch = clampf(pitch - e.relative.y * 0.004, -0.9, 0.3)
	elif e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= e.relative.x * 0.003
		pitch = clampf(pitch - e.relative.y * 0.003, -0.9, 0.3)
	elif e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_SPACE: _do_action("attack" if my_role == "killer" else "crouch")

func _process(dt: float) -> void:
	if not started: return
	ui.queue_redraw()
	minimap.queue_redraw()
	var w := 1.0 - exp(-12.0 * dt)
	for n in remotes:
		var r = remotes[n]
		r.node.position = r.node.position.lerp(r.pos, w)
		r.rig.rotation.y = lerp_angle(r.rig.rotation.y, r.yaw, w)
		r.rig.play(r.anim)

func _physics_process(delta: float) -> void:
	if not started: return
	attack_t = maxf(attack_t - delta, 0.0)
	attack_cd = maxf(attack_cd - delta, 0.0)
	var move := stick_vec
	if move == Vector2.ZERO:
		move = Vector2(float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
			float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))).limit_length(1.0)
	cam_pivot.rotation = Vector3(pitch, yaw, 0)
	var sp: Array = SPEED[my_role]
	var running := move.length() > 0.75 and not crouch
	var speed: float = sp[2] if crouch else (sp[1] if running else sp[0])
	var dir := Basis(Vector3.UP, yaw) * Vector3(move.x, 0, move.y)
	var target := dir.normalized() * speed if move.length() > 0.05 else Vector3.ZERO
	if attack_t > 0.55: # short lunge at the start of the swing
		target = Basis(Vector3.UP, rig.rotation.y) * Vector3(0, 0, 1) * 6.2
	elif attack_t > 0.0:
		target *= 0.35 # recovery slowdown after a swing
	var grounded := body.is_on_floor()
	var rate := (ACCEL if target != Vector3.ZERO else DECEL) * (1.0 if grounded else 0.3)
	var hv := Vector3(body.velocity.x, 0, body.velocity.z).move_toward(target, rate * delta)
	body.velocity.x = hv.x
	body.velocity.z = hv.z
	body.velocity.y = -2.0 if grounded else body.velocity.y - 22.0 * delta
	body.move_and_slide()
	var flat := Vector2(body.velocity.x, body.velocity.z)
	if flat.length() > 0.25 and attack_t <= 0.0:
		rig.rotation.y = lerp_angle(rig.rotation.y, atan2(flat.x, flat.y), 14.0 * delta)
	if attack_t > 0.0:
		pass # attack animation plays through
	elif crouch:
		rig.play("crouchwalk" if flat.length() > 0.25 else "hide", clampf(flat.length() / sp[2], 0.6, 1.3) if flat.length() > 0.25 else 1.0)
	elif flat.length() > 0.25:
		var is_run: bool = flat.length() > (sp[0] + sp[1]) * 0.5
		rig.play("run" if is_run else "walk", clampf(flat.length() / (sp[1] if is_run else sp[0]), 0.6, 1.3))
	else:
		rig.play("idle")
	if not cfg.get("offline", false):
		send_t -= delta
		if send_t <= 0.0:
			send_t = 1.0 / 12.0
			var p := body.position
			Net.send({"t": "st", "p": [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01), snappedf(rig.rotation.y, 0.01)], "a": rig.current})
