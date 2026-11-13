extends Node3D
## NightFall game scene: menu -> world -> local player + other players, objectives, HUD, audio.
## Rules run on the server online (server/rules.js) and locally in trial mode (scripts/rules.gd).

const WALK := {"killer": 4.6, "survivor": 1.6}
const RUN := {"killer": 4.6, "survivor": 4.0}
const CROUCH_SPEED := 1.1
const CARRY_SPEED := 3.6
# ground speed each animation was authored for; playback is scaled to it so feet don't slide
const NATURAL := {"walk": 1.3, "run": 3.7, "crouchwalk": 1.0, "injured": 1.6}
const ACCEL := 20.0
const DECEL := 28.0
const SFX := ["step", "heartbeat", "gen_loop", "hit", "ding", "boom", "pallet", "gate", "wind_loop", "hurt"]

var menu: GameMenu
var world: NightWorld
var rules: Rules
var body: CharacterBody3D
var cshape: CollisionShape3D
var rig: CharacterRig
var cam_pivot: Node3D
var arm: SpringArm3D
var ui: Control
var minimap: Control
var results: PanelContainer
var started := false
var cfg := {}
var offline := false
var my_name := ""
var my_role := "killer"
var remotes := {} # name -> {node, rig, pos, yaw, anim, role, step}
var sounds := {}
var gen_audio: Array = []
var marks: Array = []
var mark_i := 0

var yaw := 0.0
var pitch := -0.25
var stick_id := -1
var stick_origin := Vector2.ZERO
var stick_vec := Vector2.ZERO
var look_id := -1
var sprint := false
var crouch := false
var attack_t := 0.0
var attack_cd := 0.0
var hit_sent := false
var boost_t := 0.0
var send_t := 0.0
var step_t := 0.0
var beat_t := 0.0
var mark_t := 0.0

var ctx := {} # button id -> what it would do right now
var hold := {} # running hold action: {btn, kind, touch, t, need, i, n}
var vault := {}
var skill := {}
var next_skill := 5.0
var boom_t := {}
var flash := ""
var flash_t := 0.0
var my_state := "ok"
var last_state := "ok"
var last_locker := -1
var was_powered := false
var danger := 0.0 # survivors: how close the killer is (0..1)
var noise := 0.0 # killer: loudest nearby survivor (0..1)
var noise_dir := 0.0

func _ready() -> void:
	menu = GameMenu.new()
	add_child(menu)
	menu.start_game.connect(_start)
	Net.message.connect(_on_net)

func _start(c: Dictionary) -> void:
	if started: return
	cfg = c
	offline = c.get("offline", false)
	my_name = str(c.me)
	menu.visible = false
	world = NightWorld.new()
	world.configure(str(c.map))
	add_child(world)
	world.build() # staged: terrain + buildings + objectives first, the rest over the next frames
	rules = Rules.new()
	rules.setup(world.gen_points.size(), world.gate_points.size(), world.pallet_points.size(), c.players)
	for p in c.players:
		if str(p.name) == my_name:
			my_role = str(p.role)
			_build_player(str(p.char), world.spawn_point(my_role, int(p.slot)))
	for p in c.players:
		if str(p.name) != my_name: _add_remote(p)
	_build_audio()
	_build_marks()
	_build_ui()
	if not offline:
		var xz := func(v: Vector3) -> Array: return [snappedf(v.x, 0.1), snappedf(v.z, 0.1)]
		var lay := {"g": [], "h": [], "p": []}
		for v in world.gen_points: lay.g.append(xz.call(v))
		for v in world.hook_points: lay.h.append(xz.call(v))
		for v in world.pallet_points: lay.p.append(xz.call(v[0]))
		Net.send({"t": "layout", "d": lay})
	started = true

func _build_player(char_name: String, at: Vector3) -> void:
	body = CharacterBody3D.new()
	cshape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35; cap.height = 1.8
	cshape.shape = cap; cshape.position.y = 0.9
	body.add_child(cshape)
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
	arm.margin = 0.15
	arm.add_excluded_object(body.get_rid())
	cam_pivot.add_child(arm)
	var cam := Camera3D.new()
	cam.far = 400.0
	arm.add_child(cam)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.93, 0.82)
	cam_pivot.add_child(lamp)
	if my_role == "killer": # first person
		arm.spring_length = 0.0
		arm.position.y = 0.2
		cam.fov = 80.0
		cam.near = 0.1
		rig.visible = false
		lamp.position = Vector3(0, 0.3, -0.5)
		lamp.light_energy = 1.0; lamp.omni_range = 11.0
	else: # third person
		arm.spring_length = 3.4
		arm.position.y = 0.3
		cam.fov = 70.0
		lamp.position = Vector3(0.6, 0.9, 1.6)
		lamp.light_energy = 1.5; lamp.omni_range = 9.0

func _add_remote(p: Dictionary) -> void:
	var node := Node3D.new()
	var r := CharacterRig.new()
	node.add_child(r)
	r.setup(str(p.char))
	node.position = world.spawn_point(str(p.role), int(p.slot))
	if p.get("dummy", false): # trial-mode practice target
		var gp: Vector3 = world.gen_points[0]
		node.position = gp + Vector3(1.8, 0.0, 1.2) if my_role == "killer" else body.position + Vector3(2.5, 0, 0)
		rules.s[str(p.name)].hp = "ok" if my_role == "killer" else "hurt"
	var tag := Label3D.new()
	tag.text = str(p.name)
	tag.font = Net.font
	tag.font_size = 48
	tag.pixel_size = 0.004
	tag.position.y = 2.25
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = Color(1, 0.4, 0.4) if str(p.role) == "killer" else Color(0.75, 0.9, 1)
	tag.visible = str(p.role) == my_role # no name tags across teams
	node.add_child(tag)
	var glow := OmniLight3D.new() # faint light so other players are not pitch black
	glow.position = Vector3(0, 2.0, 0)
	glow.light_energy = 0.5; glow.omni_range = 3.5
	if str(p.role) == "killer": glow.light_color = Color(1, 0.25, 0.2)
	node.add_child(glow)
	add_child(node)
	remotes[str(p.name)] = {"node": node, "rig": r, "pos": node.position, "yaw": 0.0, "anim": "idle", "role": str(p.role), "step": 0.0}

# ---------------- audio ----------------
func _build_audio() -> void:
	for n in SFX: sounds[n] = load("res://assets/sfx/%s.wav" % n)
	for n in ["gen_loop", "wind_loop"]:
		var st: AudioStreamWAV = sounds[n]
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = int(st.get_length() * st.mix_rate)
	var wind := AudioStreamPlayer.new()
	wind.stream = sounds.wind_loop
	wind.volume_db = -16.0
	add_child(wind)
	wind.play()
	for gp in world.gen_points:
		var a := AudioStreamPlayer3D.new()
		a.stream = sounds.gen_loop
		a.position = gp + Vector3(0, 1, 0)
		a.unit_size = 5.0
		a.max_distance = 45.0
		add_child(a)
		gen_audio.append(a)

func _sfx(n: String, at = null, db := 0.0, pitch_scale := 1.0) -> void:
	var a: Node
	if at == null:
		a = AudioStreamPlayer.new()
	else:
		a = AudioStreamPlayer3D.new()
		a.position = at
		a.unit_size = 6.0
		a.max_distance = 60.0
	a.stream = sounds[n]
	a.volume_db = db
	a.pitch_scale = pitch_scale
	add_child(a)
	a.finished.connect(a.queue_free)
	a.play()

# scratch marks: glowing traces running survivors leave behind; only the killer sees them
func _build_marks() -> void:
	if my_role != "killer": return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.25, 0.08)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.12)
	q.material = mat
	for i in 60:
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		marks.append({"node": mi, "t": 0.0})

func _drop_mark(at: Vector3) -> void:
	var m: Dictionary = marks[mark_i]
	mark_i = (mark_i + 1) % marks.size()
	m.t = 7.0
	m.node.visible = true
	m.node.position = at + Vector3(randf_range(-0.4, 0.4), 0.06, randf_range(-0.4, 0.4))
	m.node.rotation = Vector3(-PI / 2.0, randf() * TAU, 0)
	m.node.scale = Vector3.ONE

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
			if d is Dictionary and str(m.get("n", "?")) == "": # only the server referees
				if str(d.get("k", "")) == "gs": rules.apply(d)
				else: _on_event(d)
		"left":
			var r = remotes.get(str(m.name))
			if r:
				r.node.queue_free()
				remotes.erase(str(m.name))
		"room":
			if not offline and (str(m.get("code", "")) == "" or str(m.get("state", "")) == "lobby"):
				_to_menu()

## Send one of my inputs to the referee (the server, or the local rules in trial mode).
func _ev(d: Dictionary) -> void:
	if offline:
		for e in rules.handle(d, my_name): _on_event(e)
	else:
		Net.send({"t": "ev", "d": d})

func _pos_of(n: String) -> Vector3:
	if n == my_name: return body.position
	var r = remotes.get(n)
	return r.node.position if r else Vector3.ZERO

func _on_event(e: Dictionary) -> void:
	match str(e.get("k", "")):
		"boom":
			boom_t[int(e.i)] = 4.0
			_sfx("boom", world.gen_points[int(e.i)], 4.0)
			if my_role == "killer": _flash("انفجار مولد! شوف الخريطة")
		"hurt":
			_sfx("hit", _pos_of(str(e.n)), 2.0)
			_sfx("hurt", _pos_of(str(e.n)), 0.0)
			if str(e.n) == my_name:
				boost_t = 2.0
				_flash("انضربت! اهرب" if str(e.s) == "hurt" else "طحت")
			elif my_role == "killer": _flash("أصبت %s" % str(e.n))
		"hooked":
			_sfx("hurt", _pos_of(str(e.n)), 3.0, 0.8)
			_flash("%s %s" % [str(e.n), "انعلّق على الخطاف" if str(e.s) == "hooked" else "مات"])
		"rescued": _flash("%s أنقذ %s" % [str(e.by), str(e.n)])
		"grabbed": _flash("القاتل طلّع %s من الخزانة" % str(e.n))
		"empty":
			if my_role == "killer": _flash("الخزانة فاضية")
		"pallet": _sfx("pallet", world.pallet_points[int(e.i)][0], 4.0)
		"broke": _sfx("pallet", world.pallet_points[int(e.i)][0], 2.0, 0.7)
		"stun":
			if my_role == "killer": _flash("انصعقت!")
		"power":
			if my_role == "killer":
				boost_t = 3.5
				_flash("اندفاع!")

func _flash(t: String) -> void:
	flash = t
	flash_t = 2.5

func _to_menu() -> void:
	started = false
	get_tree().reload_current_scene.call_deferred()

func _leave() -> void:
	if offline: _to_menu()
	elif str(Net.room.get("host", "")) == my_name: Net.send({"t": "lobby"}) # host ends the round for everyone
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
	leave.text = "إنهاء الجولة" if (not offline and str(Net.room.get("host", "")) == my_name) else "خروج"
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
	for n in rules.s:
		if rules.s[n].hp == "escaped": escaped += 1
	var title := Label.new()
	if my_role == "killer": title.text = "انتهت الجولة — هرب %d من %d" % [escaped, rules.s.size()]
	else: title.text = "هربت!" if rules.hp(my_name) == "escaped" else "ما نجوت"
	title.add_theme_font_size_override("font_size", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	for n in rules.s:
		var l := Label.new()
		var esc: bool = rules.s[n].hp == "escaped"
		l.text = "%s — %s" % [n, "هرب" if esc else "مات"]
		l.add_theme_font_size_override("font_size", 24)
		l.add_theme_color_override("font_color", Color(0.5, 1, 0.6) if esc else Color(1, 0.45, 0.4))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
	var b := Button.new()
	b.text = "رجوع"
	b.custom_minimum_size.y = 56
	b.add_theme_font_size_override("font_size", 24)
	b.pressed.connect(func():
		if not offline and str(Net.room.get("host", "")) == my_name: Net.send({"t": "lobby"})
		_to_menu())
	v.add_child(b)
	results.visible = true

## On-screen buttons. Each: center, radius, label, id, enabled.
func _buttons() -> Array:
	var s := get_viewport().get_visible_rect().size
	var out := []
	if my_role == "killer":
		out.append([Vector2(s.x - 115, s.y - 115), 62.0, "ضرب", "attack", attack_cd <= 0.0 and rules.carrying == ""])
		out.append([Vector2(s.x - 262, s.y - 92), 50.0, "اندفاع", "power", rules.power_cd <= 0.0 and rules.carrying == ""])
		var c = ctx.get("interact")
		out.append([Vector2(s.x - 215, s.y - 222), 48.0, c.label if c else "حمل", "interact", c != null])
	else:
		var c = ctx.get("interact")
		out.append([Vector2(s.x - 110, s.y - 110), 58.0, "ركض", "sprint", true])
		out.append([Vector2(s.x - 252, s.y - 88), 50.0, c.label if c else "تفاعل", "interact", c != null])
		out.append([Vector2(s.x - 88, s.y - 252), 44.0, "انحناء", "crouch", true])
		out.append([Vector2(s.x - 215, s.y - 215), 44.0, "قفز", "vault", ctx.has("vault")])
		out.append([Vector2(s.x - 375, s.y - 68), 40.0, "علاج", "heal", ctx.has("heal")])
		out.append([Vector2(s.x - 345, s.y - 170), 40.0, "حقيبة", "item", ctx.has("item")])
	return out

func _text(pos: Vector2, t: String, size: int, col := Color.WHITE, width := 700.0) -> void:
	ui.draw_string_outline(Net.font, pos - Vector2(width / 2.0, 0), t, HORIZONTAL_ALIGNMENT_CENTER, width, size, 6, Color(0, 0, 0, 0.8))
	ui.draw_string(Net.font, pos - Vector2(width / 2.0, 0), t, HORIZONTAL_ALIGNMENT_CENTER, width, size, col)

func _draw_ui() -> void:
	var s := get_viewport().get_visible_rect().size
	var mid := s / 2.0
	# survivors: red edges pulse when the killer is close
	if my_role == "survivor" and danger > 0.0:
		var a := danger * (0.25 + 0.2 * sin(Time.get_ticks_msec() / 1000.0 * lerpf(5.0, 12.0, danger)))
		ui.draw_rect(Rect2(Vector2.ZERO, s), Color(0.9, 0.05, 0.05, a), false, 46.0)
	if stick_id >= 0:
		ui.draw_circle(stick_origin, 70, Color(1, 1, 1, 0.12))
		ui.draw_circle(stick_origin + stick_vec * 70, 32, Color(1, 1, 1, 0.35))
	for b in _buttons():
		var id: String = b[3]
		var on: bool = (id == "crouch" and crouch) or (id == "sprint" and sprint) or (not hold.is_empty() and hold.btn == id)
		var col := Color(0.9, 0.2, 0.2, 0.5) if on else Color(1, 1, 1, 0.17 if b[4] else 0.06)
		ui.draw_circle(b[0], b[1], col)
		ui.draw_arc(b[0], b[1], 0, TAU, 40, Color(1, 1, 1, 0.55 if b[4] else 0.2), 2.0)
		ui.draw_string(Net.font, b[0] + Vector2(-b[1], 8), b[2], HORIZONTAL_ALIGNMENT_CENTER, b[1] * 2.0, 21, Color(1, 1, 1, 1.0 if b[4] else 0.4))
		if id == "power": # power indicator: ring refills during the cooldown
			var f := 1.0 - rules.power_cd / Rules.POWER_CD
			ui.draw_arc(b[0], b[1] + 5.0, -PI / 2.0, -PI / 2.0 + TAU * f, 40, Color(1, 0.5, 0.2) if f < 1.0 else Color(0.4, 1, 0.5), 5.0)
		if id == "attack" and attack_cd > 0.0:
			ui.draw_arc(b[0], b[1] + 5.0, -PI / 2.0, -PI / 2.0 + TAU * (1.0 - attack_cd / 2.4), 40, Color(1, 1, 1, 0.7), 4.0)
	# objective
	var top := Vector2(mid.x, 46)
	if not rules.powered: _text(top, "المولدات %d / %d" % [rules.done_count(), Rules.NEED], 26, Color(1, 0.9, 0.6))
	elif my_role == "killer": _text(top, "البوابات انفتحت — امنعهم من الهرب", 24, Color(1, 0.5, 0.4))
	else: _text(top, "البوابات انفتحت — اهرب من بوابة!", 26, Color(0.5, 1, 0.6))
	var sub := top + Vector2(0, 32)
	if my_role == "survivor":
		var me: Dictionary = rules.s.get(my_name, {})
		match my_state:
			"hurt": _text(sub, "مصاب", 22, Color(1, 0.5, 0.35))
			"down": _text(sub, "طايح — استنى أحد يعالجك (%d)" % int(me.t), 22, Color(1, 0.4, 0.35))
			"carried": _text(sub, "القاتل شايلك", 22, Color(1, 0.4, 0.35))
			"hooked": _text(sub, "معلّق على الخطاف — %d ث" % int(me.t), 22, Color(1, 0.4, 0.35))
			"dead": _text(sub, "انتهيت — تتفرج", 22, Color(1, 0.4, 0.35))
			"escaped": _text(sub, "هربت", 22, Color(0.5, 1, 0.6))
		if not me.is_empty() and me.locker >= 0: _text(sub + Vector2(0, 28), "مختبئ بالخزانة", 20, Color(0.7, 0.85, 1))
	else:
		# detection indicator: how loud the nearest running survivor is, and where
		var c := sub + Vector2(0, 8)
		ui.draw_circle(c, 20, Color(0, 0, 0, 0.5))
		ui.draw_arc(c, 20, 0, TAU, 32, Color(1, 1, 1, 0.4), 2.0)
		if noise > 0.02:
			ui.draw_circle(c, 6.0 + 12.0 * noise, Color(1, 0.3, 0.2, 0.4 + 0.5 * noise))
			var ang := -PI / 2.0 + noise_dir
			ui.draw_line(c + Vector2(cos(ang), sin(ang)) * 24.0, c + Vector2(cos(ang), sin(ang)) * 40.0, Color(1, 0.4, 0.3), 5.0)
			_text(c + Vector2(0, 52), "صوت ركض قريب", 18, Color(1, 0.6, 0.5))
		if rules.stun > 0.0: _text(mid + Vector2(0, -60), "مصعوق", 30, Color(1, 0.9, 0.3))
		if rules.carrying != "": _text(sub + Vector2(0, 84), "شايل %s — ودّه للخطاف" % rules.carrying, 20, Color(1, 0.7, 0.5))
		if attack_t > 0.55: # first person: show the swing
			ui.draw_arc(mid + Vector2(0, 120), 260, -PI * 0.75, -PI * 0.25, 24, Color(1, 1, 1, 0.35), 14.0)
	# team status
	var y := 216.0
	for n in rules.s:
		var p: Dictionary = rules.s[n]
		var mark: String = {"ok": "●", "hurt": "◐", "down": "▼", "carried": "▲", "hooked": "⚓", "dead": "✕", "escaped": "➜"}.get(p.hp, "?")
		var col: Color = {"ok": Color(0.7, 1, 0.7), "hurt": Color(1, 0.7, 0.3), "down": Color(1, 0.45, 0.3), "carried": Color(1, 0.45, 0.3),
			"hooked": Color(1, 0.3, 0.3), "dead": Color(0.6, 0.6, 0.6), "escaped": Color(0.5, 0.8, 1)}.get(p.hp, Color.WHITE)
		ui.draw_string(Net.font, Vector2(18, y), "%s %s%s" % [mark, n, "  " + "I".repeat(p.hooks) if p.hooks > 0 else ""], HORIZONTAL_ALIGNMENT_LEFT, 240, 18, col)
		y += 24.0
	# hold progress + skill check
	if not hold.is_empty():
		var p := 0.0
		match hold.kind:
			"rep": p = rules.gens[hold.i].p
			"heal": p = rules.s[hold.n].heal if rules.s.has(hold.n) else 0.0
			_: p = hold.t / hold.need
		var bar := Rect2(mid.x - 180, s.y - 90, 360, 18)
		ui.draw_rect(bar, Color(0, 0, 0, 0.6))
		ui.draw_rect(Rect2(bar.position, Vector2(360 * clampf(p, 0.0, 1.0), 18)), Color(1, 0.85, 0.3))
		ui.draw_rect(bar, Color(1, 1, 1, 0.6), false, 2.0)
	if not skill.is_empty():
		var z: float = skill.zone
		ui.draw_circle(mid, 78, Color(0, 0, 0, 0.55))
		ui.draw_arc(mid, 64, 0, TAU, 48, Color(1, 1, 1, 0.5), 4.0)
		ui.draw_arc(mid, 64, (z - 0.07) * TAU - PI / 2.0, (z + 0.07) * TAU - PI / 2.0, 12, Color(0.3, 1, 0.4), 10.0)
		var ang: float = skill.t / 1.2 * TAU - PI / 2.0
		ui.draw_line(mid, mid + Vector2(cos(ang), sin(ang)) * 72, Color(1, 0.3, 0.3), 4.0)
		_text(mid + Vector2(0, 118), "اضغط الشاشة لما المؤشر بالأخضر", 20)
	if flash_t > 0.0: _text(Vector2(mid.x, s.y * 0.3), flash, 30, Color(1, 0.85, 0.5))

func _draw_minimap() -> void:
	var k := 150.0 / NightWorld.SIZE
	var c := Vector2(75, 75)
	minimap.draw_rect(Rect2(Vector2.ZERO, Vector2(150, 150)), Color(0, 0, 0, 0.45))
	var wl := NightWorld.WALL * k
	minimap.draw_rect(Rect2(c - Vector2(wl, wl), Vector2(wl, wl) * 2.0), Color(1, 1, 1, 0.55), false, 2.0)
	for b in world.buildings:
		minimap.draw_set_transform(c + Vector2(b[0], b[1]) * k, -b[2], Vector2.ONE)
		minimap.draw_rect(Rect2(-Vector2(b[3], b[4]) * k / 2.0, Vector2(b[3], b[4]) * k), Color(0.55, 0.52, 0.45, 0.8))
	minimap.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for i in world.hook_points.size():
		var hp: Vector3 = world.hook_points[i]
		var used := rules.hook_user(i) != ""
		minimap.draw_circle(c + Vector2(hp.x, hp.z) * k, 4.5 if used else 2.5, Color(1, 0.2, 0.2) if used else Color(0.7, 0.25, 0.25))
	for i in world.gen_points.size():
		var gp: Vector3 = world.gen_points[i]
		var col := Color(0.4, 1, 0.5) if rules.gens[i].done else Color(1, 0.85, 0.2)
		var alert: bool = boom_t.get(i, 0.0) > 0.0 and my_role == "killer"
		if alert: col = Color(1, 0.2, 0.2)
		var sz := 9.0 if alert else 6.0
		minimap.draw_rect(Rect2(c + Vector2(gp.x, gp.z) * k - Vector2(sz, sz) / 2.0, Vector2(sz, sz)), col)
	for i in world.gate_points.size():
		var p: Vector3 = world.gate_points[i][0]
		minimap.draw_rect(Rect2(c + Vector2(p.x, p.z) * k - Vector2(7, 3), Vector2(14, 6)), Color(0.4, 1, 0.5) if rules.gates[i].open else Color(1, 0.3, 0.25))
	for n in remotes: # survivors see their team; the killer has to hunt
		var r = remotes[n]
		if my_role == "survivor" and r.role == "survivor" and r.node.visible:
			var p: Vector3 = r.node.position
			minimap.draw_circle(c + Vector2(p.x, p.z) * k, 3.5, Color(0.4, 0.8, 1))
	var me := c + Vector2(body.position.x, body.position.z) * k
	var f := Vector2(-sin(yaw), -cos(yaw))
	var side := Vector2(-f.y, f.x)
	minimap.draw_colored_polygon(PackedVector2Array([me + f * 8.0, me - f * 4.0 + side * 5.0, me - f * 4.0 - side * 5.0]),
		Color(1, 0.3, 0.3) if my_role == "killer" else Color(1, 1, 1))

# ---------------- context: what each button would do right now ----------------
func _near(a: Vector3, b: Vector3, r: float) -> bool:
	return Vector2(a.x - b.x, a.z - b.z).length() < r

func _update_ctx() -> void:
	ctx = {}
	if rules.over: return
	var pos := body.position
	if my_role == "survivor":
		var me: Dictionary = rules.s.get(my_name, {})
		if me.is_empty(): return
		if me.locker >= 0:
			ctx.interact = {"kind": "locker_out", "label": "اطلع", "i": me.locker}
			return
		if not (my_state in ["ok", "hurt"]): return
		for n in rules.s:
			var p: Dictionary = rules.s[n]
			if n == my_name: continue
			if p.hp == "hooked" and _near(pos, world.hook_points[p.hook_i], 2.9):
				ctx.interact = {"kind": "rescue", "label": "أنقذ", "n": n, "need": 1.5}
			if p.hp in ["hurt", "down"] and p.locker < 0 and _near(pos, _pos_of(n), 2.6):
				ctx.heal = {"kind": "heal", "n": n, "need": -1.0}
		if not ctx.has("interact"):
			for i in world.locker_points.size():
				if _near(pos, world.locker_points[i][0], 1.9) and rules.locker_user(i) == "":
					ctx.interact = {"kind": "locker_in", "label": "اختبئ", "i": i}
		if not ctx.has("interact"):
			for i in world.pallet_points.size():
				if rules.pallets[i] == 0 and _near(pos, world.pallet_points[i][0], 2.2):
					ctx.interact = {"kind": "pallet", "label": "اسقط", "i": i}
		if not ctx.has("interact") and not rules.powered:
			for i in world.gen_points.size():
				if not rules.gens[i].done and _near(pos, world.gen_points[i], 2.5):
					ctx.interact = {"kind": "rep", "label": "تصليح", "i": i, "need": -1.0}
		for w in world.window_points:
			if _near(pos, w[0], 1.7): ctx.vault = {"kind": "vault", "c": w[0], "n": w[1]}
		for i in world.pallet_points.size():
			var pp: Array = world.pallet_points[i]
			if rules.pallets[i] == 1 and _near(pos, pp[0], 1.7):
				ctx.vault = {"kind": "vault", "c": pp[0], "n": Basis(Vector3.UP, pp[1]) * Vector3(0, 0, 1)}
		if my_state == "hurt" and me.item: ctx.item = {"kind": "heal", "n": my_name, "need": -1.0}
		if rules.powered:
			for i in world.gate_points.size():
				if world.is_outside_gate(i, pos): _ev({"k": "escape"})
	elif rules.stun <= 0.0:
		if rules.carrying != "":
			for i in world.hook_points.size():
				if rules.hook_user(i) == "" and _near(pos, world.hook_points[i], 3.2):
					ctx.interact = {"kind": "hook", "label": "علّق", "i": i}
			return
		for n in rules.s:
			if rules.s[n].hp == "down" and _near(pos, _pos_of(n), 2.7): ctx.interact = {"kind": "pickup", "label": "احمل", "n": n}
		if not ctx.has("interact"):
			for i in world.locker_points.size():
				if _near(pos, world.locker_points[i][0], 2.1): ctx.interact = {"kind": "search", "label": "فتّش", "i": i}
		if not ctx.has("interact"):
			for i in world.pallet_points.size():
				if rules.pallets[i] == 1 and _near(pos, world.pallet_points[i][0], 2.4):
					ctx.interact = {"kind": "break", "label": "اكسر", "i": i, "need": 2.0}
		if not ctx.has("interact"):
			for w in world.window_points:
				if _near(pos, w[0], 1.7): ctx.interact = {"kind": "vault", "label": "اقفز", "c": w[0], "n": w[1]}

# ---------------- actions ----------------
func _press(id: String, touch: int) -> void:
	match id:
		"sprint":
			sprint = not sprint
			if sprint: crouch = false
		"crouch":
			crouch = not crouch
			if crouch: sprint = false
		"attack":
			if attack_cd <= 0.0 and rules.stun <= 0.0 and rules.carrying == "":
				attack_t = 1.1
				attack_cd = 2.4
				hit_sent = false
				rig.play("attack", 2.0)
		"power": _ev({"k": "power"})
		"vault":
			if ctx.has("vault"): _start_vault(ctx.vault)
		_:
			var c = ctx.get(id)
			if c == null or not hold.is_empty(): return
			match str(c.kind):
				"locker_in": _ev({"k": "locker", "i": c.i, "on": true})
				"locker_out": _ev({"k": "locker", "i": c.i, "on": false})
				"pallet": _ev({"k": "pallet", "i": c.i})
				"pickup": _ev({"k": "pickup", "n": c.n})
				"hook": _ev({"k": "hook", "i": c.i})
				"search": _ev({"k": "search", "i": c.i})
				"vault": _start_vault(c)
				_:
					hold = {"btn": id, "kind": c.kind, "touch": touch, "t": 0.0, "need": float(c.get("need", -1.0)), "i": int(c.get("i", -1)), "n": str(c.get("n", ""))}
					if c.kind == "rep":
						next_skill = randf_range(3.0, 6.0)
						_ev({"k": "rep", "i": c.i, "on": true})
					elif c.kind == "heal": _ev({"k": "heal", "n": c.n, "on": true})

func _end_hold() -> void:
	if hold.is_empty(): return
	if hold.kind == "rep": _ev({"k": "rep", "i": hold.i, "on": false})
	elif hold.kind == "heal": _ev({"k": "heal", "n": hold.n, "on": false})
	hold = {}
	skill = {}

func _update_hold(delta: float) -> void:
	if hold.is_empty(): return
	var c = ctx.get(hold.btn)
	if c == null or str(c.kind) != hold.kind or int(c.get("i", -1)) != hold.i or str(c.get("n", "")) != hold.n or stick_vec.length() > 0.3:
		_end_hold()
		return
	if hold.need > 0.0: # timed action: fires when the bar fills
		hold.t += delta
		if hold.t >= hold.need:
			if hold.kind == "rescue": _ev({"k": "rescue", "n": hold.n})
			elif hold.kind == "break": _ev({"k": "break", "i": hold.i})
			hold = {}
	elif hold.kind == "rep":
		if skill.is_empty():
			next_skill -= delta
			if next_skill <= 0.0: skill = {"t": 0.0, "zone": randf_range(0.4, 0.85)}
		else:
			skill.t += delta
			if skill.t > 1.2:
				_ev({"k": "skill", "i": hold.i, "ok": false})
				_flash("فاتك! انفجر المولد")
				skill = {}
				next_skill = randf_range(4.0, 8.0)

func _skill_tap() -> void:
	var ok: bool = absf(float(skill.t) / 1.2 - float(skill.zone)) <= 0.07
	_ev({"k": "skill", "i": hold.i, "ok": ok})
	if ok: _sfx("ding")
	_flash("ممتاز!" if ok else "غلط! انفجر المولد")
	skill = {}
	next_skill = randf_range(4.0, 8.0)

func _start_vault(c: Dictionary) -> void:
	if not vault.is_empty() or attack_t > 0.0: return
	var center: Vector3 = c.c
	var normal: Vector3 = c.n
	var side := 1.0 if (body.position - center).dot(normal) >= 0.0 else -1.0
	var to := center - normal * side * 1.25
	to.y = center.y + 0.05
	vault = {"from": body.position, "to": to, "t": 0.0, "dur": 1.7 if my_role == "killer" else (0.7 if sprint else 1.0)}

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
				if e.position.distance_to(b[0]) < b[1] + 8.0:
					_press(b[3], e.index)
					return
			if e.position.x < half and stick_id < 0:
				stick_id = e.index; stick_origin = e.position; stick_vec = Vector2.ZERO
			elif e.position.x >= half and look_id < 0:
				look_id = e.index
		else:
			if e.index == stick_id: stick_id = -1; stick_vec = Vector2.ZERO
			if e.index == look_id: look_id = -1
			if not hold.is_empty() and e.index == hold.touch: _end_hold()
	elif e is InputEventScreenDrag:
		if e.index == stick_id:
			stick_vec = ((e.position - stick_origin) / 70.0).limit_length(1.0)
			if stick_vec.length() < 0.12: stick_vec = Vector2.ZERO # dead zone
		elif e.index == look_id:
			yaw -= e.relative.x * 0.006
			pitch = clampf(pitch - e.relative.y * 0.004, -0.9, 0.5)
	elif e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= e.relative.x * 0.003
		pitch = clampf(pitch - e.relative.y * 0.003, -0.9, 0.5)

# ---------------- per-frame ----------------
func _process(dt: float) -> void:
	if not started: return
	flash_t = maxf(flash_t - dt, 0.0)
	for i in boom_t.keys(): boom_t[i] = maxf(boom_t[i] - dt, 0.0)
	ui.queue_redraw()
	minimap.queue_redraw()
	var kpos := _pos_of(rules.killer) if rules.killer != "" else Vector3.ZERO
	var w := 1.0 - exp(-12.0 * dt)
	noise = 0.0
	for n in remotes:
		var r = remotes[n]
		var st: String = rules.hp(n)
		var anim: String = r.anim
		var target: Vector3 = r.pos
		var lift := 0.0
		if st == "carried":
			target = kpos; lift = 1.0; anim = "dying"
		elif st == "hooked":
			target = world.hook_points[rules.s[n].hook_i] + Vector3(0, 0.6, 0.9); anim = "idle"
		elif st == "down" or st == "dead": anim = "dying"
		elif st == "hurt" and anim == "idle": anim = "injured"
		r.node.position = r.node.position.lerp(target, w)
		r.rig.position.y = lerpf(r.rig.position.y, lift, w)
		r.rig.rotation.y = lerp_angle(r.rig.rotation.y, r.yaw, w)
		r.rig.play(anim)
		r.node.visible = st != "escaped" and not (rules.s.has(n) and rules.s[n].locker >= 0)
		# footsteps of runners are audible in 3D; the killer also gets scratch marks and the detection indicator
		if anim == "run" and r.node.visible:
			r.step -= dt
			if r.step <= 0.0:
				r.step = 0.3
				_sfx("step", r.node.position, 6.0 if r.role == "killer" else 2.0, randf_range(0.9, 1.1))
				if my_role == "killer" and r.role == "survivor": _drop_mark(r.node.position)
			if my_role == "killer" and r.role == "survivor":
				var to: Vector3 = r.node.position - body.position
				var lvl := clampf(1.0 - to.length() / 26.0, 0.0, 1.0)
				if lvl > noise:
					noise = lvl
					noise_dir = wrapf(atan2(to.x, -to.z) + yaw, -PI, PI)
	for m in marks:
		if m.t > 0.0:
			m.t -= dt
			m.node.scale = Vector3.ONE * clampf(m.t / 2.0, 0.0, 1.0)
			if m.t <= 0.0: m.node.visible = false
	# world visuals + sounds follow the rules state
	for i in rules.gens.size():
		var g: Dictionary = rules.gens[i]
		if g.done: world.set_gen_done(i)
		var a: AudioStreamPlayer3D = gen_audio[i]
		var should: bool = g.p > 0.01
		if should and not a.playing: a.play()
		elif not should and a.playing: a.stop()
		a.pitch_scale = 0.75 + 0.45 * g.p
		a.volume_db = -8.0 + 8.0 * g.p
	for i in rules.gates.size(): world.set_gate_state(i, rules.gates[i].open)
	for i in rules.pallets.size(): world.set_pallet_state(i, rules.pallets[i])
	if rules.powered and not was_powered:
		was_powered = true
		for g in world.gate_points: _sfx("gate", g[0] + Vector3(0, 3, 0), 8.0)
		_sfx("gate", null, -10.0)
		_flash("اشتغلت الكهرباء — البوابات انفتحت!")
	# survivors: heartbeat gets faster and louder as the killer closes in
	danger = 0.0
	if my_role == "survivor" and rules.killer != "" and remotes.has(rules.killer) and my_state in ["ok", "hurt", "down"]:
		danger = clampf(1.0 - body.position.distance_to(kpos) / 32.0, 0.0, 1.0)
		if danger > 0.0:
			beat_t -= dt
			if beat_t <= 0.0:
				beat_t = lerpf(1.15, 0.42, danger)
				_sfx("heartbeat", null, lerpf(-14.0, 2.0, danger))
	if rules.over and not results.visible: _show_results()

func _physics_process(delta: float) -> void:
	if not started: return
	if offline:
		rules.tick(delta)
		if my_role == "survivor" and rules.hp(my_name) in ["escaped", "dead"]: rules.over = true # trial: the round is just me
	my_state = rules.hp(my_name) if my_role == "survivor" else "ok"
	var me: Dictionary = rules.s.get(my_name, {})
	var locker: int = me.locker if not me.is_empty() else -1
	_update_ctx()
	_update_hold(delta)
	attack_t = maxf(attack_t - delta, 0.0)
	attack_cd = maxf(attack_cd - delta, 0.0)
	boost_t = maxf(boost_t - delta, 0.0)
	cam_pivot.rotation = Vector3(pitch, yaw, 0)
	# states where I don't control my body
	var pinned := true
	if my_state == "carried":
		body.position = _pos_of(rules.killer)
		rig.position.y = 1.0
		rig.play("dying")
	elif my_state == "hooked":
		body.position = world.hook_points[me.hook_i] + Vector3(0, 0.6, 0.9)
		rig.play("idle")
	elif locker >= 0:
		body.position = world.locker_points[locker][0]
	elif not vault.is_empty():
		vault.t += delta
		var f: float = clampf(vault.t / vault.dur, 0.0, 1.0)
		var p: Vector3 = (vault.from as Vector3).lerp(vault.to, f)
		p.y += sin(f * PI) * 1.15
		body.position = p
		var dv: Vector3 = (vault.to as Vector3) - (vault.from as Vector3)
		rig.rotation.y = atan2(dv.x, dv.z)
		rig.play("run", 1.2)
		if f >= 1.0: vault = {}
	else:
		pinned = false
	if my_state != "carried": rig.position.y = 0.0
	if last_locker >= 0 and locker < 0 and my_state in ["ok", "hurt"]: # stepped out of a locker
		var lp: Array = world.locker_points[last_locker]
		body.position = lp[0] + Basis(Vector3.UP, lp[1]) * Vector3(0, 0, 1.1)
	last_locker = locker
	if my_role == "survivor": rig.visible = locker < 0 and my_state != "escaped"
	cshape.disabled = pinned or my_state in ["down", "dead", "escaped"]
	if pinned:
		body.velocity = Vector3.ZERO
	else:
		_move(delta)
	last_state = my_state
	if not offline:
		send_t -= delta
		if send_t <= 0.0:
			send_t = 1.0 / 15.0
			var p := body.position
			Net.send({"t": "st", "p": [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01), snappedf(rig.rotation.y, 0.01)], "a": rig.current})

func _move(delta: float) -> void:
	var frozen: bool = rules.over or my_state in ["down", "dead", "escaped"] or not hold.is_empty() or (my_role == "killer" and rules.stun > 0.0)
	var move := stick_vec
	if move == Vector2.ZERO:
		move = Vector2(float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
			float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))).limit_length(1.0)
	if frozen: move = Vector2.ZERO
	var speed: float = RUN[my_role] if (sprint or my_role == "killer") else WALK[my_role]
	if crouch: speed = CROUCH_SPEED
	if my_role == "killer" and rules.carrying != "": speed = CARRY_SPEED
	if boost_t > 0.0: speed *= 1.5
	var dir := Basis(Vector3.UP, yaw) * Vector3(move.x, 0, move.y)
	var target := dir.normalized() * speed * clampf(move.length() * 1.3, 0.0, 1.0) if move.length() > 0.05 else Vector3.ZERO
	if my_role == "killer": rig.rotation.y = yaw + PI # first person: the body faces where I look
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
	if my_role != "killer" and v > 0.25:
		rig.rotation.y = lerp_angle(rig.rotation.y, atan2(flat.x, flat.y), 12.0 * delta)
	# killer hit check during the swing
	if my_role == "killer" and attack_t > 0.45 and attack_t < 0.95 and not hit_sent:
		var fwd := Basis(Vector3.UP, rig.rotation.y) * Vector3(0, 0, 1)
		for n in remotes:
			var r = remotes[n]
			if r.role != "survivor" or not rules.free_now(n): continue
			var to: Vector3 = r.node.position - body.position
			to.y = 0.0
			if to.length() < 2.5 and (to.length() < 0.7 or fwd.dot(to.normalized()) > 0.45):
				hit_sent = true
				_ev({"k": "hit", "n": n})
				break
	# animation
	if my_state == "down" or my_state == "dead":
		rig.play("dying")
	elif attack_t > 0.0:
		pass # the swing plays through
	elif not hold.is_empty():
		var tp := body.position
		match hold.kind:
			"rep": tp = world.gen_points[hold.i]
			"heal":
				if hold.n != my_name: tp = _pos_of(hold.n)
			"rescue": tp = world.hook_points[rules.s[hold.n].hook_i] if rules.s[hold.n].hook_i >= 0 else tp
			"break": tp = world.pallet_points[hold.i][0]
		if tp != body.position and my_role != "killer":
			rig.rotation.y = lerp_angle(rig.rotation.y, atan2(tp.x - body.position.x, tp.z - body.position.z), 10.0 * delta)
		rig.play("hide")
	elif crouch:
		if v > 0.25: rig.play("crouchwalk", clampf(v / NATURAL.crouchwalk, 0.5, 1.6))
		else: rig.play("hide")
	elif v > 0.25:
		if v > 2.6:
			rig.play("run", clampf(v / NATURAL.run, 0.7, 1.7))
			step_t -= delta
			if step_t <= 0.0:
				step_t = 0.3
				_sfx("step", null, -9.0, randf_range(0.9, 1.1))
		elif my_state == "hurt": rig.play("injured", clampf(v / NATURAL.injured, 0.6, 1.6))
		else: rig.play("walk", clampf(v / NATURAL.walk, 0.6, 1.7))
	else:
		rig.play("idle")
