extends Node
## Graphics settings (saved), FPS modes, and an adaptive performance governor.
## Autoload name: Gfx

signal changed

const PATH := "user://graphics.cfg"
const FPS_OPTS := [0, 30, 60, 120] # 0 = Auto
const SCALE_OPTS := [0.85, 0.9, 1.0]
const PRESETS := { # shadows, aa, scale index, effects
	0: [0, 0, 0, 0], # Medium
	1: [1, 1, 2, 1], # High
	2: [2, 2, 2, 2], # Ultra
}

var fps_idx := 0
var preset := 1
var shadows := 1
var aa := 1
var scale_idx := 2
var effects := 1

# runtime-only reductions made by the governor (not saved)
var dyn_scale := 1.0
var rt_shadows := 2
var rt_effects := 2
var rt_fps_cap := 0
var menu_open := false

var _t := 0.0
var _frames := 0
var _warm := 6.0
var _bad := 0
var _good := 0
var _hud: Label
var _panel: PanelContainer
var _opts := {}
var _editor: NFControlsEdit
var last_avg_ms := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()
	_build_ui()
	apply()

func eff_shadows() -> int: return mini(shadows, rt_shadows)
func eff_effects() -> int: return mini(effects, rt_effects)

func target_fps() -> int:
	var f: int = FPS_OPTS[fps_idx]
	if f == 0:
		var r := DisplayServer.screen_get_refresh_rate()
		f = int(clampf(roundf(r), 30.0, 120.0)) if (r > 1.0 and r < 1000.0) else 60
	if rt_fps_cap > 0: f = mini(f, rt_fps_cap)
	return f

func render_scale() -> float:
	return clampf(SCALE_OPTS[scale_idx] * dyn_scale, 0.85, 1.0)

func apply() -> void:
	var vp := get_viewport()
	Engine.max_fps = target_fps()
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][aa]
	vp.scaling_3d_scale = render_scale()
	var s := eff_shadows()
	RenderingServer.directional_shadow_atlas_set_size([1024, 2048, 4096][s], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
		[RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM][s])
	changed.emit()

func _reset_runtime() -> void:
	dyn_scale = 1.0; rt_shadows = 2; rt_effects = 2; rt_fps_cap = 0
	_bad = 0; _good = 0; _warm = 4.0

func _load() -> void:
	var c := ConfigFile.new()
	if c.load(PATH) != OK: return
	fps_idx = clampi(c.get_value("g", "fps", fps_idx), 0, 3)
	preset = clampi(c.get_value("g", "preset", preset), 0, 2)
	shadows = clampi(c.get_value("g", "shadows", shadows), 0, 2)
	aa = clampi(c.get_value("g", "aa", aa), 0, 2)
	scale_idx = clampi(c.get_value("g", "scale", scale_idx), 0, 2)
	effects = clampi(c.get_value("g", "effects", effects), 0, 2)

func _save() -> void:
	var c := ConfigFile.new()
	c.set_value("g", "fps", fps_idx); c.set_value("g", "preset", preset)
	c.set_value("g", "shadows", shadows); c.set_value("g", "aa", aa)
	c.set_value("g", "scale", scale_idx); c.set_value("g", "effects", effects)
	c.save(PATH)

# ---------- adaptive governor ----------
func _process(dt: float) -> void:
	_t += dt; _frames += 1
	if _warm > 0.0:
		_warm -= dt; _t = 0.0; _frames = 0
		return
	if _t < 2.0: return
	var avg := _t / float(_frames)
	_t = 0.0; _frames = 0
	last_avg_ms = avg * 1000.0
	_hud.text = "%d FPS  %.1f ms  target %d  scale %d%%" % [roundi(1.0 / avg), last_avg_ms, target_fps(), roundi(render_scale() * 100.0)]
	if menu_open: return
	var target := 1.0 / float(target_fps())
	if avg > target * 1.18: _bad += 1; _good = 0
	elif avg < target * 1.06: _good += 1; _bad = 0
	else: _bad = 0; _good = 0
	if _bad >= 2:
		_bad = 0; _step_down()
	elif _good >= 8:
		_good = 0; _step_up()

func _step_down() -> void:
	if render_scale() > 0.851:
		dyn_scale = maxf(dyn_scale - 0.05, 0.85 / SCALE_OPTS[scale_idx])
	elif eff_shadows() > 0: rt_shadows = eff_shadows() - 1
	elif eff_effects() > 0: rt_effects = eff_effects() - 1
	elif target_fps() > 60: rt_fps_cap = 60
	else: return
	apply()

func _step_up() -> void:
	if dyn_scale < 1.0:
		dyn_scale = minf(dyn_scale + 0.05, 1.0)
		apply()

# ---------- UI ----------
func in_ui(pos: Vector2) -> bool:
	if menu_open: return true
	var w := get_viewport().get_visible_rect().size.x
	return pos.x > w - 150.0 and pos.y < 80.0

func _build_ui() -> void:
	var layer := CanvasLayer.new(); layer.layer = 20; add_child(layer)
	var theme := NFUI.theme()
	_hud = Label.new(); _hud.position = Vector2(16, 10); _hud.theme = theme
	_hud.add_theme_font_size_override("font_size", 16)
	_hud.modulate = Color(1, 1, 1, 0.7); _hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hud)
	var gear := Button.new(); gear.text = "الإعدادات"
	gear.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	gear.offset_left = -140; gear.offset_right = -12; gear.offset_top = 12; gear.offset_bottom = 64
	gear.pressed.connect(_toggle)
	NFUI.dress(gear, "gear")
	layer.add_child(gear)
	_panel = PanelContainer.new(); _panel.theme = theme; _panel.visible = false
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(520, 0)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH; _panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	layer.add_child(_panel)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: m.add_theme_constant_override("margin_" + side, 20)
	_panel.add_child(m)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 10); m.add_child(v)
	var title := Label.new(); title.text = "الإعدادات"; title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(title)
	_row(v, "fps", "الإطارات", ["تلقائي", "30", "60", "120"])
	_row(v, "preset", "الجرافيكس", ["متوسط", "عالي", "فائق"])
	_row(v, "shadows", "الظلال", ["منخفض", "متوسط", "عالي"])
	_row(v, "aa", "تنعيم الحواف", ["مغلق", "2x", "4x"])
	_row(v, "scale", "دقة الرسم", ["85%", "90%", "100%"])
	_row(v, "effects", "جودة المؤثرات", ["منخفض", "متوسط", "عالي"])
	var ctl := Button.new(); ctl.text = "أزرار التحكم (مكان وحجم)"; ctl.custom_minimum_size.y = 52
	ctl.pressed.connect(_edit_controls); NFUI.dress(ctl, "gear"); v.add_child(ctl)
	var close := Button.new(); close.text = "إغلاق"; close.custom_minimum_size.y = 52
	close.pressed.connect(_toggle); NFUI.dress(close, "exit"); v.add_child(close)
	_refresh()

## The touch-layout editor, reachable without leaving the round (the game ignores input while it is up).
func _edit_controls() -> void:
	if _editor and is_instance_valid(_editor): return
	_editor = NFControlsEdit.new()
	_panel.visible = false
	_editor.closed.connect(func() -> void:
		_editor = null
		_panel.visible = menu_open)
	add_child(_editor)

func _row(parent: Control, key: String, label: String, items: Array) -> void:
	var h := HBoxContainer.new(); parent.add_child(h)
	var l := Label.new(); l.text = label; l.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(l)
	var o := OptionButton.new(); o.custom_minimum_size = Vector2(200, 48)
	for it in items: o.add_item(it)
	o.item_selected.connect(_on_select.bind(key))
	h.add_child(o)
	_opts[key] = o

func _refresh() -> void:
	_opts["fps"].select(fps_idx); _opts["preset"].select(preset); _opts["shadows"].select(shadows)
	_opts["aa"].select(aa); _opts["scale"].select(scale_idx); _opts["effects"].select(effects)

func _on_select(i: int, key: String) -> void:
	match key:
		"fps": fps_idx = i
		"preset":
			preset = i
			var p: Array = PRESETS[i]
			shadows = p[0]; aa = p[1]; scale_idx = p[2]; effects = p[3]
		"shadows": shadows = i
		"aa": aa = i
		"scale": scale_idx = i
		"effects": effects = i
	_reset_runtime()
	_refresh(); _save(); apply()

func _toggle() -> void:
	menu_open = not menu_open
	_panel.visible = menu_open
	if not menu_open: _warm = 2.0
