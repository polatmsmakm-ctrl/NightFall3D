class_name NFResults
extends Node3D
## End of the round: everyone lines up on a dark stage. Whoever got out is on their feet,
## whoever died is on the ground (assets/anims/dying, held on its last frame). Under each one:
## the name, the points counting up, and the owner's experience bar filling itself.

const STAGE_Y := 600.0 # the stage sits high above the map; the camera carries its own environment

var rows: Array = []    # [{name, char, role, state, score, mine}]
var title := ""
var stats := ""
var xp_from := 0
var xp_to := 0
var escapes := 0
var kills := 0
var on_back: Callable
var on_again: Callable
var again_text := ""

var cam: Camera3D
var pad: Control
var vic_stage: Node3D   # the escaped survivors in front of the gate
var row_stage: Node3D   # everyone, for the statistics
var vic: Array = []     # rows of whoever got out
var intro := 0.0        # seconds of the victory shot left
var home := Vector3.ZERO # where the statistics camera sits
var btns: Array = []     # the two buttons, hidden while the shot runs
var t := 0.0
var xp_show := 0.0

func _env() -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.015, 0.014, 0.02)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.16, 0.17, 0.26)
	e.ambient_light_energy = 1.1
	e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	e.fog_enabled = true
	e.fog_light_color = Color(0.03, 0.03, 0.05)
	e.fog_density = 0.035
	e.glow_enabled = true
	e.glow_intensity = 0.45
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	NFLook.apply(e, "stage")
	return e

func setup(d: Dictionary) -> void:
	rows = d.get("rows", [])
	title = str(d.get("title", ""))
	stats = str(d.get("stats", ""))
	xp_from = int(d.get("xp_from", 0))
	xp_to = int(d.get("xp_to", 0))
	escapes = int(d.get("escapes", 0))
	vic = d.get("victory", [])
	kills = int(d.get("kills", 0))
	on_back = d.get("on_back", Callable())
	on_again = d.get("on_again", Callable())
	again_text = str(d.get("again_text", ""))
	xp_show = float(xp_from)
	position = Vector3(0, STAGE_Y, 0)
	row_stage = Node3D.new()
	add_child(row_stage)
	# floor: a dull slab so the ones on the ground have something to lie on
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.07, 0.065, 0.07)
	fmat.roughness = 0.95
	pm.material = fmat
	floor_mi.mesh = pm
	row_stage.add_child(floor_mi)
	var n: int = maxi(rows.size(), 1)
	var dist: float = 3.2 + n * 1.05
	var gap := 1.5
	for i in rows.size():
		var r: Dictionary = rows[i]
		var dead: bool = str(r.get("state", "")) in ["dead", "down"]
		var rig := CharacterRig.new()
		row_stage.add_child(rig)
		rig.setup(str(r.get("char", "survivor1")), ["dying"] if dead else ["idle"])
		rig.position = Vector3((i - (n - 1) / 2.0) * gap, 0.0, 0.0)
		rig.rotation.y = 0.0 # the models face +z, which is where the camera is
		rig.play("dying" if dead else "idle")
		r["node"] = rig
		var key := OmniLight3D.new() # each one gets their own little light, colour-coded by fate
		key.position = rig.position + Vector3(0.0, 2.0, 1.5)
		key.light_energy = 1.5 if not dead else 0.8
		key.omni_range = 4.2
		key.light_color = Color(1.0, 0.85, 0.7) if not dead else Color(0.9, 0.3, 0.25)
		key.shadow_enabled = false
		row_stage.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.basis = Basis.looking_at(Vector3(-0.3, -0.5, -1.0).normalized())
	rim.light_color = Color(0.55, 0.62, 0.95)
	rim.light_energy = 0.7
	rim.shadow_enabled = false
	row_stage.add_child(rim)
	cam = Camera3D.new()
	cam.position = Vector3(0.0, 1.62, dist)
	home = cam.position
	cam.rotation = Vector3(-0.1, 0.0, 0.0)
	cam.fov = 58.0
	cam.near = 0.1
	cam.far = 60.0
	cam.environment = _env()
	add_child(cam)
	cam.current = true
	if not vic.is_empty(): # the ones who made it, at the gate, before the numbers
		_build_victory()
		intro = 5.0
		row_stage.visible = false
	var layer := CanvasLayer.new()
	layer.layer = 15
	add_child(layer)
	pad = Control.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_STOP
	pad.draw.connect(_draw_pad)
	layer.add_child(pad)
	var safe := NFUI.safe_insets(get_viewport())
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(170, 56)
	back.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	back.offset_left = -190.0 - safe.y; back.offset_right = -20.0 - safe.y
	back.offset_top = -76.0; back.offset_bottom = -20.0
	back.pressed.connect(func() -> void:
		if on_back.is_valid(): on_back.call())
	NFUI.dress(back, "exit")
	layer.add_child(back)
	btns.append(back)
	if on_again.is_valid() and again_text != "":
		var again := Button.new()
		again.text = again_text
		again.custom_minimum_size = Vector2(230, 56)
		again.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		again.offset_left = -440.0 - safe.y; again.offset_right = -200.0 - safe.y
		again.offset_top = -76.0; again.offset_bottom = -20.0
		again.pressed.connect(func() -> void:
			if on_again.is_valid(): on_again.call())
		NFUI.dress(again, "star")
		layer.add_child(again)
		btns.append(again)
	if intro > 0.0: # nothing to press while the camera circles them
		for b in btns: (b as Control).visible = false

## The escaped survivors standing in the open gate, celebrating.
func _build_victory() -> void:
	vic_stage = Node3D.new()
	vic_stage.position = Vector3(0, 0, -40.0) # its own corner of the stage
	add_child(vic_stage)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(44, 44)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.09, 0.085, 0.08)
	fmat.roughness = 0.95
	pm.material = fmat
	floor_mi.mesh = pm
	vic_stage.add_child(floor_mi)
	# the gate: two towers, a lintel and the lit arch they ran through
	var wall := StandardMaterial3D.new()
	wall.albedo_color = Color(0.22, 0.21, 0.2)
	wall.roughness = 0.9
	var lit := StandardMaterial3D.new()
	lit.albedo_color = Color(0.45, 0.8, 0.6)
	lit.emission_enabled = true
	lit.emission = Color(0.45, 0.95, 0.65)
	lit.emission_energy_multiplier = 1.6
	for sx in [-1.0, 1.0]:
		var tower := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.8, 8.0, 2.0)
		bm.material = wall
		tower.mesh = bm
		tower.position = Vector3(sx * 4.4, 4.0, -3.0)
		vic_stage.add_child(tower)
		var post := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(0.4, 5.0, 0.3)
		pb.material = lit
		post.mesh = pb
		post.position = Vector3(sx * 3.3, 2.5, -3.0)
		vic_stage.add_child(post)
	var lintel := MeshInstance3D.new()
	var lb := BoxMesh.new()
	lb.size = Vector3(10.6, 1.6, 2.0)
	lb.material = wall
	lintel.mesh = lb
	lintel.position = Vector3(0, 8.8, -3.0)
	vic_stage.add_child(lintel)
	var bar := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(7.2, 0.5, 0.3)
	bb.material = lit
	bar.mesh = bb
	bar.position = Vector3(0, 5.2, -3.0)
	vic_stage.add_child(bar)
	var gl := OmniLight3D.new()
	gl.position = Vector3(0, 4.2, -1.2)
	gl.light_color = Color(0.65, 1.0, 0.8)
	gl.light_energy = 4.0
	gl.omni_range = 22.0
	vic_stage.add_child(gl)
	var fill := OmniLight3D.new() # so the gate towers are not flat black
	fill.position = Vector3(0.0, 3.6, 6.5)
	fill.light_color = Color(0.8, 0.86, 1.0)
	fill.light_energy = 1.3
	fill.omni_range = 20.0
	fill.shadow_enabled = false
	vic_stage.add_child(fill)
	var n: int = maxi(vic.size(), 1)
	for i in vic.size():
		var r: Dictionary = vic[i]
		var rig := CharacterRig.new()
		vic_stage.add_child(rig)
		rig.setup(str(r.get("char", "survivor1")), ["idle", "wave", "dance", "cheer"], true)
		rig.position = Vector3((i - (n - 1) / 2.0) * 1.7, 0.0, 0.6)
		# a real cheer clip if the owner has dropped one in; otherwise the emotes we have
		rig.play("cheer" if rig.has("cheer") else ("dance" if i == 0 else "wave"))
		rig.player.seek(float(i) * 0.4, true)
		var key := OmniLight3D.new()
		key.position = rig.position + Vector3(0.0, 2.2, 2.2)
		key.light_energy = 1.8
		key.omni_range = 5.0
		key.light_color = Color(1.0, 0.92, 0.82)
		key.shadow_enabled = false
		vic_stage.add_child(key)
		var tag := Label3D.new()
		tag.text = str(r.get("name", ""))
		tag.font = Net.font
		tag.font_size = 52
		tag.pixel_size = 0.0035
		tag.position = rig.position + Vector3(0, 2.6, 0) # clear of the raised arms in the dance
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.modulate = Color(0.75, 1.0, 0.85)
		tag.outline_size = 14
		tag.outline_modulate = Color(0, 0, 0, 0.85)
		vic_stage.add_child(tag)

func _process(dt: float) -> void:
	if cam == null: return # setup() has not run yet
	t += dt
	if intro > 0.0: # circle them slowly, then hand over to the statistics
		intro = maxf(intro - dt, 0.0)
		var a := -0.5 + (5.0 - intro) * 0.19
		var centre: Vector3 = vic_stage.global_position + Vector3(0, 0, 0.6) # the stage sits 600 m up: work in world space
		cam.global_position = centre + Vector3(sin(a) * 7.5, 2.2 + 0.3 * sin(t * 0.5), cos(a) * 7.5)
		cam.look_at(centre + Vector3(0, 1.25, 0), Vector3.UP)
		pad.queue_redraw()
		if intro <= 0.0: # over to the numbers
			vic_stage.visible = false
			row_stage.visible = true
			cam.position = home
			cam.rotation = Vector3(-0.1, 0.0, 0.0)
			t = 0.0
			for b in btns: (b as Control).visible = true
		return
	cam.position.x = sin(t * 0.22) * 0.5 # a slow drift so the row is not a still photo
	xp_show = move_toward(xp_show, float(xp_to), maxf(float(xp_to - xp_from), 1.0) * dt / 1.6)
	pad.queue_redraw()

func _font() -> Font:
	return Net.font if Net.font else ThemeDB.fallback_font

func _say(at: Vector2, s: String, size: int, col: Color, width := 420.0) -> void:
	var f := _font()
	pad.draw_string_outline(f, at - Vector2(width / 2.0, 0), s, HORIZONTAL_ALIGNMENT_CENTER, width, size, 6, Color(0, 0, 0, 0.9))
	pad.draw_string(f, at - Vector2(width / 2.0, 0), s, HORIZONTAL_ALIGNMENT_CENTER, width, size, col)

func _draw_pad() -> void:
	var s: Vector2 = pad.size
	if intro > 0.0:
		var names := PackedStringArray()
		for r in vic: names.append(str(r.get("name", "")))
		var fade: float = clampf(intro / 0.6, 0.0, 1.0) * clampf((5.0 - intro) / 0.4, 0.0, 1.0)
		_say(Vector2(s.x / 2.0, s.y * 0.16), "They escaped!", 56, Color(0.6, 1.0, 0.75, fade), s.x - 40.0)
		_say(Vector2(s.x / 2.0, s.y * 0.24), ", ".join(names), 26, Color(0.85, 1.0, 0.9, fade), s.x - 60.0)
		return
	var safe := NFUI.safe_insets(get_viewport())
	pad.draw_rect(Rect2(Vector2.ZERO, Vector2(s.x, 100.0)), Color(0.02, 0.02, 0.03, 0.72))
	pad.draw_rect(Rect2(Vector2(0.0, s.y - 122.0), Vector2(s.x, 122.0)), Color(0.02, 0.02, 0.03, 0.72))
	pad.draw_line(Vector2(0.0, 100.0), Vector2(s.x, 100.0), Color(0.5, 0.07, 0.08, 0.8), 2.0)
	pad.draw_line(Vector2(0.0, s.y - 122.0), Vector2(s.x, s.y - 122.0), Color(0.5, 0.07, 0.08, 0.8), 2.0)
	_say(Vector2(s.x / 2.0, 52.0), title, 40, Color(0.9, 0.17, 0.17), s.x - 40.0)
	_say(Vector2(s.x / 2.0, 84.0), stats, 21, Color(0.8, 0.8, 0.82), s.x - 40.0)
	# name + points under each character
	var grow: float = clampf(t / 1.2, 0.0, 1.0)
	for r in rows:
		var rig: CharacterRig = r.get("node")
		if rig == null: continue
		var head: Vector3 = rig.global_position
		if not cam.is_position_behind(head):
			var p := cam.unproject_position(head)
			var mine: bool = bool(r.get("mine", false))
			var st := str(r.get("state", ""))
			var col: Color = Color(1, 0.86, 0.35) if mine else (Color(0.55, 0.9, 1.0) if st == "escaped" else (Color(1, 0.45, 0.4) if st == "dead" else Color(0.85, 0.85, 0.9)))
			var y: float = clampf(p.y + 28.0, 134.0, s.y - 200.0)
			_say(Vector2(p.x, y), str(r.get("name", "")), 24, col, 300.0)
			_say(Vector2(p.x, y + 28.0), "%d points" % roundi(float(r.get("score", 0)) * grow), 20, Color(1, 0.9, 0.6), 300.0)
			var fate: String = {"escaped": "Escaped", "dead": "died", "killer": "The Killer"}.get("killer" if str(r.get("role", "")) == "killer" else st, "inside")
			_say(Vector2(p.x, y + 52.0), fate, 18, Color(col, 0.75), 300.0)
			NFIcons.draw(pad, "out" if st == "escaped" else ("skull" if st == "dead" else "star"),
				Vector2(p.x, y - 16.0), 26.0, Color(col, 0.9))
	# the owner's experience bar, filling while you watch
	var lvl := 1 + int(sqrt(xp_show / 200.0))
	var base := 200.0 * pow(float(lvl - 1), 2.0)
	var next := 200.0 * pow(float(lvl), 2.0)
	var f: float = clampf((xp_show - base) / maxf(next - base, 1.0), 0.0, 1.0)
	var bw: float = minf(s.x - 120.0 - safe.x - safe.y, 520.0)
	var br := Rect2(Vector2((s.x - bw) / 2.0, s.y - 56.0), Vector2(bw, 14.0))
	var up := lvl > 1 + int(sqrt(float(xp_from) / 200.0))
	_say(Vector2(s.x / 2.0, s.y - 96.0), "Escapes %d   •   Kills %d" % [escapes, kills], 19, Color(0.75, 0.78, 0.8), s.x - 40.0)
	_say(Vector2(s.x / 2.0, s.y - 66.0), "Level %d%s   •   XP %d  (+%d)" % [lvl, "  Level up!" if up else "", roundi(xp_show), xp_to - xp_from],
		22, Color(0.6, 1.0, 0.7) if up else Color(1, 0.9, 0.6), s.x - 40.0)
	NFUI.bar(pad, br, f, Color(0.8, 0.12, 0.12), Color(1, 1, 1, 0.35))
