extends Node3D
## NightFall game scene: menu -> world -> local player + online players, objectives, HUD.

const SPEED := { # walk, run, crouch (m/s)
	"killer": [1.7, 4.6, 1.7],
	"survivor": [1.5, 4.0, 1.1],
}
# ground speed each animation was authored for; playback is scaled to it so feet don't slide
const NATURAL := {"walk": 1.3, "run": 3.7, "crouchwalk": 1.0, "injured": 1.6}
const ACCEL := 20.0
const DECEL := 28.0
const REACH := 2.5

var menu: GameMenu
var world: NightWorld
var rules: Rules
var body: CharacterBody3D
var rig: CharacterRig
var cam_pivot: Node3D
var arm: SpringArm3D
var ui: Control
var minimap: Control
var results: PanelContainer
var started := false
var cfg := {}
var my_name := ""
var my_role := "killer"
var host_name := ""
var is_host := true
var remotes := {} # name -> {node, rig, pos, yaw, anim, role}

var yaw := 0.0
var pitch := -0.25
var stick_id := -1
var stick_origin := Vector2.ZERO
var stick_vec := Vector2.ZERO
var look_id := -1
var hold_id := -1
var key_hold := false
var crouch := false
var attack_t := 0.0
var attack_cd := 0.0
var hit_sent := false
var boost_t := 0.0
var send_t := 0.0
var snap_t := 0.0

var near_gen := -1
var near_gate := -1
var work_kind := "" # "", "gen", "gate"
var work_i := -1
var skill := {} # {t, zone}
var next_skill := 5.0
var boom_t := {} # generator index -> seconds left (alert)
var flash := "" # short message in the middle of the screen
var flash_t := 0.0
var my_state := "ok"
var dead_played := false

func _ready() -> void:
	menu = GameMenu.new()
	add_child(menu)
	menu.start_game.connect(_start)
	Net.message.connect(_on_net)

func _start(c: Dictionary) -> void:
	if started: return
	cfg = c
	my_name = str(c.me)
	host_name = my_name if c.get("offline", false) else str(Net.room.get("host", my_name))
	is_host = host_name == my_name
	menu.visible = false
	world = NightWorld.new()
	world.configure(str(c.map))
	add_child(world)
	world.build() # staged: terrain + buildings + objectives first, the rest over the next frames
	rules = Rules.new()
	rules.setup(world.gen_points.size(), world.gate_points.size(), c.players)
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
	arm.spring_length = 3.4
	arm.margin = 0.15
	arm.position.y = 0.3
	arm.add_excluded_object(body.get_rid())
	cam_pivot.add_child(arm)
	var cam := Camera3D.new()
	cam.far = 400.0
	cam.fov = 70.0
	arm.add_child(cam)
	# soft light that always comes from the camera side, so the character's details stay readable
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0.6, 0.9, 1.6)
	lamp.light_energy = 1.5; lamp.omni_range = 9.0
	lamp.light_color = Color(1.0, 0.93, 0.82)
	cam_pivot.add_child(lamp)

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
	var glow := OmniLight3D.new() # faint light so other players are not pitch black
	glow.position = Vector3(0, 2.0, 0)
	glow.light_energy = 0.5; glow.omni_range = 3.5
	node.add_child(glow)
	add_child(node)
	remotes[str(p.name)] = {"node": node, "rig": r, "pos": node.position, "yaw": 0.0, "anim": "idle", "role": str(p.role)}

# ---------------- networking ----------------
func _on_net(m: Dictionary) -> void:
	if not started: return
	match str(m.t):
		"st":
			var r = remotes.get(str(m.n))
			if r:
				r.pos = Vector3(m.p[0], m.p[1], m.p[2])
				r.yaw = float(m.p[3])
				r.anim = str(m.a)
		"ev":
			var d = m.get("d")
			if not (d is Dictionary): return
			if is_host:
				if str(d.get("k", "")) in ["rep", "skill", "gate", "escape", "hit"]: _host_handle(d, str(m.n))
			elif str(m.n) == host_name:
				if str(d.get("k", "")) == "gs": rules.apply(d)
				else: _on_event(d)
		"left":
			var r = remotes.get(str(m.name))
			if r:
				r.node.queue_free()
				remotes.erase(str(m.name))
			if is_host and rules.hp.has(str(m.name)) and rules.active(str(m.name)):
				rules.hp[str(m.name)] = "dead"
		"room":
			if not cfg.get("offline", false) and (str(m.get("code", "")) == "" or str(m.get("state", "")) == "lobby"):
				_to_menu()

## Send one of my inputs to the referee (myself when I am the host).
func _ev(d: Dictionary) -> void:
	if is_host: _host_handle(d, my_name)
	else: Net.send({"t": "ev", "d": d})

func _host_handle(d: Dictionary, from: String) -> void:
	for e in rules.handle(d, from):
		_on_event(e)
		if not cfg.get("offline", false): Net.send({"t": "ev", "d": e})
	snap_t = 0.0

func _on_event(e: Dictionary) -> void:
	match str(e.get("k", "")):
		"boom":
			boom_t[int(e.i)] = 4.0
			if my_role == "killer": _flash("انفجار مولد! شوف الخريطة")
		"hurt":
			if str(e.n) == my_name:
				boost_t = 2.0
				_flash("انضربت! اهرب" if str(e.s) == "hurt" else "طحت")
			elif my_role == "killer": _flash("أصبت %s" % str(e.n))

func _flash(t: String) -> void:
	flash = t
	flash_t = 2.5

func _to_menu() -> void:
	started = false
	get_tree().reload_current_scene.call_deferred()

func _leave() -> void:
	if cfg.get("offline", false): _to_menu()
	elif is_host: Net.send({"t": "lobby"}) # host ends the round for everyone
	else: Net.send({"t": "leave"})

# ---------------- UI ----------------
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
	leave.text = "إنهاء الجولة" if (is_host and not cfg.get("offline", false)) else "خروج"
	leave.focus_mode = Control.FOCUS_NONE
	leave.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	leave.offset_left = -300; leave.offset_right = -152; leave.offset_top = 12; leave.offset_bottom = 64
	leave.pressed.connect(_leave)
	layer.add_child(leave)
	results = PanelContainer.new()
	results.visible = false
	results.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	results.grow_horizontal = Control.GROW_DIRECTION_BOTH
	results.grow_vertical = Control.GROW_DIRECTION_BOTH
	results.custom_minimum_size = Vector2(520, 0)
	layer.add_child(results)

func _show_results() -> void:
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: m.add_theme_constant_override("margin_" + side, 24)
	results.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	m.add_child(v)
	var escaped := 0
	for n in rules.hp:
		if rules.hp[n] == "escaped": escaped += 1
	var title := Label.new()
	if my_role == "killer": title.text = "انتهت الجولة — هرب %d من %d" % [escaped, rules.hp.size()]
	else: title.text = "هربت! 🎉" if rules.hp.get(my_name, "") == "escaped" else "ما نجوت"
	title.add_theme_font_size_override("font_size", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	for n in rules.hp:
		var l := Label.new()
		l.text = "%s — %s" % [n, "هرب" if rules.hp[n] == "escaped" else "مات"]
		l.add_theme_font_size_override("font_size", 24)
		l.add_theme_color_override("font_color", Color(0.5, 1, 0.6) if rules.hp[n] == "escaped" else Color(1, 0.45, 0.4))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
	var b := Button.new()
	b.text = "رجوع"
	b.custom_minimum_size.y = 56
	b.add_theme_font_size_override("font_size", 24)
	b.pressed.connect(func():
		if is_host and not cfg.get("offline", false): Net.send({"t": "lobby"})
		_to_menu())
	v.add_child(b)
	results.visible = true

func _buttons() -> Array: # each: center, radius, label, id
	var s := get_viewport().get_visible_rect().size
	var out := []
	if my_role == "killer":
		out.append([Vector2(s.x - 130, s.y - 140), 60.0, "ضرب", "attack"])
	elif my_state in ["ok", "hurt"]:
		out.append([Vector2(s.x - 130, s.y - 140), 60.0, "انحناء", "crouch"])
		if near_gen >= 0: out.append([Vector2(s.x - 290, s.y - 110), 64.0, "تصليح", "hold"])
		elif near_gate >= 0: out.append([Vector2(s.x - 290, s.y - 110), 64.0, "افتح", "hold"])
	return out

func _text(pos: Vector2, t: String, size: int, col := Color.WHITE, width := 600.0) -> void:
	ui.draw_string_outline(Net.font, pos - Vector2(width / 2.0, 0), t, HORIZONTAL_ALIGNMENT_CENTER, width, size, 6, Color(0, 0, 0, 0.8))
	ui.draw_string(Net.font, pos - Vector2(width / 2.0, 0), t, HORIZONTAL_ALIGNMENT_CENTER, width, size, col)

func _draw_ui() -> void:
	var s := get_viewport().get_visible_rect().size
	if stick_id >= 0:
		ui.draw_circle(stick_origin, 70, Color(1, 1, 1, 0.12))
		ui.draw_circle(stick_origin + stick_vec * 70, 32, Color(1, 1, 1, 0.35))
	for b in _buttons():
		var active: bool = (b[3] == "crouch" and crouch) or (b[3] == "attack" and attack_cd > 0.0) or (b[3] == "hold" and work_kind != "")
		ui.draw_circle(b[0], b[1], Color(0.9, 0.2, 0.2, 0.45) if active else Color(1, 1, 1, 0.16))
		ui.draw_arc(b[0], b[1], 0, TAU, 40, Color(1, 1, 1, 0.5), 2.0)
		ui.draw_string(Net.font, b[0] + Vector2(-b[1], 9), b[2], HORIZONTAL_ALIGNMENT_CENTER, b[1] * 2.0, 24)
	# objective
	var top := Vector2(s.x / 2.0, 46)
	if not rules.powered:
		_text(top, "المولدات %d / %d" % [rules.done_count(), Rules.NEED], 26, Color(1, 0.9, 0.6))
	else:
		var open := false
		for g in rules.gates:
			if g.open: open = true
		if my_role == "killer": _text(top, "البوابات اشتغلت — امنعهم من الهرب", 24, Color(1, 0.5, 0.4))
		elif open: _text(top, "البوابة مفتوحة — اهرب!", 26, Color(0.5, 1, 0.6))
		else: _text(top, "اشتغلت الكهرباء — افتح بوابة الخروج", 24, Color(1, 0.9, 0.6))
	if my_role == "survivor":
		if my_state == "hurt": _text(top + Vector2(0, 32), "مصاب", 22, Color(1, 0.4, 0.35))
		elif my_state == "dead": _text(top + Vector2(0, 32), "انتهيت — تتفرج", 22, Color(1, 0.4, 0.35))
		elif my_state == "escaped": _text(top + Vector2(0, 32), "هربت", 22, Color(0.5, 1, 0.6))
	# team status
	var y := 216.0
	for n in rules.hp:
		var st: String = rules.hp[n]
		var mark: String = {"ok": "●", "hurt": "◐", "dead": "✕", "escaped": "➜"}.get(st, "?")
		var col: Color = {"ok": Color(0.7, 1, 0.7), "hurt": Color(1, 0.7, 0.3), "dead": Color(1, 0.35, 0.3), "escaped": Color(0.5, 0.8, 1)}.get(st, Color.WHITE)
		ui.draw_string(Net.font, Vector2(18, y), "%s %s" % [mark, n], HORIZONTAL_ALIGNMENT_LEFT, 200, 18, col)
		y += 24.0
	# work progress + skill check
	if work_kind != "":
		var p: float = rules.gens[work_i].p if work_kind == "gen" else rules.gates[work_i].p
		var bar := Rect2(s.x / 2.0 - 180, s.y - 90, 360, 18)
		ui.draw_rect(bar, Color(0, 0, 0, 0.6))
		ui.draw_rect(Rect2(bar.position, Vector2(360 * p, 18)), Color(1, 0.85, 0.3))
		ui.draw_rect(bar, Color(1, 1, 1, 0.6), false, 2.0)
	if not skill.is_empty():
		var c := s / 2.0
		var z: float = skill.zone
		ui.draw_circle(c, 78, Color(0, 0, 0, 0.55))
		ui.draw_arc(c, 64, 0, TAU, 48, Color(1, 1, 1, 0.5), 4.0)
		ui.draw_arc(c, 64, (z - 0.07) * TAU - PI / 2.0, (z + 0.07) * TAU - PI / 2.0, 12, Color(0.3, 1, 0.4), 10.0)
		var ang: float = skill.t / 1.2 * TAU - PI / 2.0
		ui.draw_line(c, c + Vector2(cos(ang), sin(ang)) * 72, Color(1, 0.3, 0.3), 4.0)
		_text(c + Vector2(0, 118), "اضغط الشاشة لما المؤشر بالأخضر", 20)
	if flash_t > 0.0: _text(Vector2(s.x / 2.0, s.y * 0.3), flash, 30, Color(1, 0.85, 0.5))

func _draw_minimap() -> void:
	var k := 150.0 / NightWorld.SIZE
	var c := Vector2(75, 75)
	minimap.draw_rect(Rect2(Vector2.ZERO, Vector2(150, 150)), Color(0, 0, 0, 0.45))
	minimap.draw_rect(Rect2(Vector2.ZERO, Vector2(150, 150)), Color(1, 1, 1, 0.35), false, 1.5)
	for b in world.buildings:
		minimap.draw_set_transform(c + Vector2(b[0], b[1]) * k, -b[2], Vector2.ONE)
		minimap.draw_rect(Rect2(-Vector2(b[3], b[4]) * k / 2.0, Vector2(b[3], b[4]) * k), Color(0.55, 0.52, 0.45, 0.8))
	minimap.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for i in world.gen_points.size():
		var gp: Vector3 = world.gen_points[i]
		var col := Color(0.4, 1, 0.5) if rules.gens[i].done else Color(1, 0.85, 0.2)
		if boom_t.get(i, 0.0) > 0.0 and my_role == "killer": col = Color(1, 0.2, 0.2)
		var sz := 9.0 if col.g < 0.5 else 6.0
		minimap.draw_rect(Rect2(c + Vector2(gp.x, gp.z) * k - Vector2(sz, sz) / 2.0, Vector2(sz, sz)), col)
	if rules.powered:
		for i in world.gate_points.size():
			var p: Vector3 = world.gate_points[i][0]
			minimap.draw_rect(Rect2(c + Vector2(p.x, p.z) * k - Vector2(7, 3), Vector2(14, 6)), Color(0.4, 1, 0.5) if rules.gates[i].open else Color.WHITE)
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

# ---------------- actions ----------------
func _do_action(id: String) -> void:
	if id == "crouch": crouch = not crouch
	elif id == "attack" and attack_cd <= 0.0:
		attack_t = 1.1
		attack_cd = 2.4
		hit_sent = false
		rig.play("attack", 2.0)

func _start_work() -> void:
	if work_kind != "" or not (my_state in ["ok", "hurt"]): return
	if near_gen >= 0:
		work_kind = "gen"; work_i = near_gen
		next_skill = randf_range(3.0, 6.0)
		_ev({"k": "rep", "i": work_i, "on": true})
	elif near_gate >= 0:
		work_kind = "gate"; work_i = near_gate
		_ev({"k": "gate", "i": work_i, "on": true})

func _stop_work() -> void:
	if work_kind == "": return
	_ev({"k": "rep" if work_kind == "gen" else "gate", "i": work_i, "on": false})
	work_kind = ""; work_i = -1; skill = {}

func _skill_tap() -> void:
	var frac: float = skill.t / 1.2
	var ok: bool = absf(frac - float(skill.zone)) <= 0.07
	_ev({"k": "skill", "i": work_i, "ok": ok})
	_flash("ممتاز!" if ok else "غلط! انفجر المولد")
	skill = {}
	next_skill = randf_range(4.0, 8.0)

func _input(e: InputEvent) -> void:
	if not started or rules.over: return
	if (e is InputEventScreenTouch or e is InputEventMouseButton) and e.pressed and Gfx.in_ui(e.position): return
	if Gfx.menu_open: return
	var half := get_viewport().get_visible_rect().size.x / 2.0
	if e is InputEventScreenTouch:
		if e.pressed:
			if not skill.is_empty() and e.index != stick_id:
				_skill_tap()
				return
			for b in _buttons():
				if e.position.distance_to(b[0]) < b[1] + 10.0:
					if b[3] == "hold":
						hold_id = e.index
						_start_work()
					else: _do_action(b[3])
					return
			if e.position.x < half and stick_id < 0:
				stick_id = e.index; stick_origin = e.position; stick_vec = Vector2.ZERO
			elif e.position.x >= half and look_id < 0:
				look_id = e.index
		else:
			if e.index == stick_id: stick_id = -1; stick_vec = Vector2.ZERO
			if e.index == look_id: look_id = -1
			if e.index == hold_id:
				hold_id = -1
				_stop_work()
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
	elif e is InputEventKey and not e.echo:
		if e.keycode == KEY_SPACE and e.pressed:
			if not skill.is_empty(): _skill_tap()
			else: _do_action("attack" if my_role == "killer" else "crouch")
		elif e.keycode == KEY_E:
			key_hold = e.pressed
			if e.pressed: _start_work()
			else: _stop_work()

func _process(dt: float) -> void:
	if not started: return
	flash_t = maxf(flash_t - dt, 0.0)
	for i in boom_t.keys(): boom_t[i] = maxf(boom_t[i] - dt, 0.0)
	ui.queue_redraw()
	minimap.queue_redraw()
	var w := 1.0 - exp(-12.0 * dt)
	for n in remotes:
		var r = remotes[n]
		r.node.position = r.node.position.lerp(r.pos, w)
		r.rig.rotation.y = lerp_angle(r.rig.rotation.y, r.yaw, w)
		r.rig.play(r.anim)
		r.node.visible = rules.hp.get(n, "") != "escaped"
	# world visuals follow the rules state
	for i in rules.gens.size():
		if rules.gens[i].done: world.set_gen_done(i)
	for i in rules.gates.size():
		world.set_gate_state(i, 2 if rules.gates[i].open else (1 if rules.powered else 0))
	if rules.over and not results.visible: _show_results()

func _update_interactions(delta: float) -> void:
	my_state = rules.hp.get(my_name, "ok") if my_role == "survivor" else "ok"
	near_gen = -1; near_gate = -1
	if my_role != "survivor" or not (my_state in ["ok", "hurt"]):
		if work_kind != "": _stop_work()
		return
	if not rules.powered:
		for i in world.gen_points.size():
			if not rules.gens[i].done and body.position.distance_to(world.gen_points[i]) < REACH: near_gen = i
	else:
		for i in world.gate_points.size():
			var gp: Vector3 = world.gate_points[i][0]
			var d := body.position.distance_to(gp)
			if rules.gates[i].open:
				if d < 2.2: _ev({"k": "escape"})
			elif d < REACH + 0.8: near_gate = i
	if work_kind != "":
		var still: bool = (work_kind == "gen" and near_gen == work_i) or (work_kind == "gate" and near_gate == work_i)
		if not still or stick_vec.length() > 0.3:
			_stop_work()
		elif work_kind == "gen":
			if skill.is_empty():
				next_skill -= delta
				if next_skill <= 0.0: skill = {"t": 0.0, "zone": randf_range(0.4, 0.85)}
			else:
				skill.t += delta
				if skill.t > 1.2:
					_ev({"k": "skill", "i": work_i, "ok": false})
					_flash("فاتك! انفجر المولد")
					skill = {}
					next_skill = randf_range(4.0, 8.0)

func _physics_process(delta: float) -> void:
	if not started: return
	if is_host:
		rules.tick(delta)
		snap_t -= delta
		if snap_t <= 0.0 and not cfg.get("offline", false):
			snap_t = 0.25
			Net.send({"t": "ev", "d": rules.snapshot()})
	_update_interactions(delta)
	attack_t = maxf(attack_t - delta, 0.0)
	attack_cd = maxf(attack_cd - delta, 0.0)
	boost_t = maxf(boost_t - delta, 0.0)
	var frozen: bool = rules.over or my_state in ["dead", "escaped"] or work_kind != ""
	var move := stick_vec
	if move == Vector2.ZERO:
		move = Vector2(float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
			float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))).limit_length(1.0)
	if frozen: move = Vector2.ZERO
	cam_pivot.rotation = Vector3(pitch, yaw, 0)
	var sp: Array = SPEED[my_role]
	var running := move.length() > 0.55 and not crouch
	var speed: float = sp[2] if crouch else (sp[1] if running else sp[0])
	if boost_t > 0.0: speed *= 1.5
	var dir := Basis(Vector3.UP, yaw) * Vector3(move.x, 0, move.y)
	var target := dir.normalized() * speed if move.length() > 0.05 else Vector3.ZERO
	if attack_t > 0.75: # short lunge at the start of the swing
		target = Basis(Vector3.UP, rig.rotation.y) * Vector3(0, 0, 1) * 6.4
	elif attack_t > 0.0:
		target *= 0.3 # recovery slowdown after a swing
	var grounded := body.is_on_floor()
	var rate := (ACCEL if target != Vector3.ZERO else DECEL) * (1.0 if grounded else 0.3)
	var hv := Vector3(body.velocity.x, 0, body.velocity.z).move_toward(target, rate * delta)
	body.velocity.x = hv.x
	body.velocity.z = hv.z
	body.velocity.y = -2.0 if grounded else body.velocity.y - 22.0 * delta
	body.move_and_slide()
	var flat := Vector2(body.velocity.x, body.velocity.z)
	var v := flat.length()
	if v > 0.25 and attack_t <= 0.0:
		rig.rotation.y = lerp_angle(rig.rotation.y, atan2(flat.x, flat.y), 12.0 * delta)
	# killer hit check during the swing
	if my_role == "killer" and attack_t > 0.45 and attack_t < 0.95 and not hit_sent:
		var fwd := Basis(Vector3.UP, rig.rotation.y) * Vector3(0, 0, 1)
		for n in remotes:
			var r = remotes[n]
			if r.role != "survivor" or not rules.active(n): continue
			var to: Vector3 = r.node.position - body.position
			to.y = 0.0
			if to.length() < 2.4 and (to.length() < 0.6 or fwd.dot(to.normalized()) > 0.45):
				hit_sent = true
				_ev({"k": "hit", "n": n})
				break
	# animation
	if my_state == "dead":
		if not dead_played:
			dead_played = true
			rig.play("dying")
	elif attack_t > 0.0:
		pass # the swing plays through
	elif work_kind != "":
		var tp: Vector3 = world.gen_points[work_i] if work_kind == "gen" else world.gate_points[work_i][0]
		rig.rotation.y = lerp_angle(rig.rotation.y, atan2(tp.x - body.position.x, tp.z - body.position.z), 10.0 * delta)
		rig.play("hide")
	elif crouch:
		if v > 0.25: rig.play("crouchwalk", clampf(v / NATURAL.crouchwalk, 0.5, 1.6))
		else: rig.play("hide")
	elif v > 0.25:
		if v > 2.6: rig.play("run", clampf(v / NATURAL.run, 0.7, 1.7))
		elif my_state == "hurt": rig.play("injured", clampf(v / NATURAL.injured, 0.6, 1.6))
		else: rig.play("walk", clampf(v / NATURAL.walk, 0.6, 1.7))
	else:
		rig.play("idle")
	if not cfg.get("offline", false):
		send_t -= delta
		if send_t <= 0.0:
			send_t = 1.0 / 15.0
			var p := body.position
			Net.send({"t": "st", "p": [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01), snappedf(rig.rotation.y, 0.01)], "a": rig.current})
