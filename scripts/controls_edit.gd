class_name NFControlsEdit
extends CanvasLayer
## Full-screen editor for the touch layout: drag a button anywhere, resize the selected one,
## reset to the shipped layout. Saves per role in user://controls.cfg.

signal closed

var role := "survivor"
var lay := {}
var sel := ""
var pad: Control
var slider: HSlider
var _drag := ""
var _grab := Vector2.ZERO
var _moved := false

func _ready() -> void:
	layer = 30
	lay = NFControls.layout(role).duplicate(true)
	pad = Control.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_STOP
	pad.gui_input.connect(_on_pad)
	pad.draw.connect(_draw_pad)
	add_child(pad)
	var safe := NFUI.safe_insets(get_viewport())
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	top.position = Vector2(safe.x + 18.0, 14.0)
	add_child(top)
	for r in [["survivor", "أزرار الناجي"], ["killer", "أزرار القاتل"]]:
		var b := Button.new()
		b.text = r[1]
		b.custom_minimum_size = Vector2(190, 48)
		b.pressed.connect(_switch.bind(str(r[0])))
		NFUI.dress(b, "gear")
		top.add_child(b)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	bottom.position = Vector2(safe.x + 18.0, 92.0)
	add_child(bottom)
	slider = HSlider.new()
	slider.custom_minimum_size = Vector2(300, 44)
	slider.min_value = NFControls.MIN_R
	slider.max_value = NFControls.MAX_R
	slider.step = 1.0
	slider.value = 48.0
	slider.theme = NFUI.theme()
	slider.value_changed.connect(_resize)
	bottom.add_child(slider)
	var rst := Button.new()
	rst.text = "إرجاع الأصلي"
	rst.custom_minimum_size = Vector2(190, 48)
	rst.pressed.connect(func() -> void:
		lay = NFControls.reset(role).duplicate(true)
		sel = ""
		pad.queue_redraw())
	NFUI.dress(rst, "exit")
	bottom.add_child(rst)
	var done := Button.new()
	done.text = "تم"
	done.custom_minimum_size = Vector2(130, 48)
	done.pressed.connect(func() -> void:
		NFControls.save(role, lay)
		closed.emit()
		queue_free())
	NFUI.dress(done, "star")
	bottom.add_child(done)

func _switch(r: String) -> void:
	NFControls.save(role, lay)
	role = r
	lay = NFControls.layout(role).duplicate(true)
	sel = ""
	pad.queue_redraw()

func _resize(v: float) -> void:
	if sel == "" or not lay.has(sel): return
	lay[sel].r = v
	NFControls.save(role, lay)
	pad.queue_redraw()

func _hit(p: Vector2) -> String:
	var rect := NFControls.area(get_viewport())
	var best := ""
	var bd := 1e9
	for id in lay:
		var c := NFControls.center_of(lay[id], rect)
		var d := p.distance_to(c)
		if d < float(lay[id].r) + 14.0 and d < bd:
			bd = d; best = id
	return best

func _on_pad(e: InputEvent) -> void:
	var rect := NFControls.area(get_viewport())
	if (e is InputEventScreenTouch or e is InputEventMouseButton) and e.pressed:
		var id := _hit(e.position)
		_drag = id
		_moved = false
		if id != "":
			sel = id
			_grab = e.position - NFControls.center_of(lay[id], rect)
			slider.set_value_no_signal(float(lay[id].r))
		pad.queue_redraw()
	elif (e is InputEventScreenTouch or e is InputEventMouseButton) and not e.pressed:
		if _drag != "" and _moved: NFControls.save(role, lay)
		_drag = ""
	elif (e is InputEventScreenDrag or e is InputEventMouseMotion) and _drag != "":
		var f := NFControls.fraction_of(e.position - _grab, rect)
		lay[_drag].fx = f.x
		lay[_drag].fy = f.y
		_moved = true
		pad.queue_redraw()

func _draw_pad() -> void:
	var s: Vector2 = pad.size
	var rect := NFControls.area(get_viewport())
	pad.draw_rect(Rect2(Vector2.ZERO, s), Color(0.02, 0.02, 0.028, 0.96))
	for i in 9: # faint grid so you can line the buttons up
		pad.draw_line(Vector2(rect.position.x + rect.size.x * i / 8.0, 0), Vector2(rect.position.x + rect.size.x * i / 8.0, s.y), Color(1, 1, 1, 0.045), 1.0)
		pad.draw_line(Vector2(0, s.y * i / 8.0), Vector2(s.x, s.y * i / 8.0), Color(1, 1, 1, 0.045), 1.0)
	var stick := Vector2(rect.position.x + rect.size.x * 0.2, s.y * 0.72)
	pad.draw_arc(stick, 70.0, 0, TAU, 40, Color(1, 1, 1, 0.1), 2.0)
	_say(Vector2(stick.x, stick.y + 92.0), "مكان عصا الحركة — ما ينتقل", 18, Color(1, 1, 1, 0.3))
	_say(Vector2(s.x / 2.0, 44.0), "اسحب أي زر لمكانه، واستخدم الشريط لتكبيره", 22, Color(1, 0.85, 0.55))
	for id in lay:
		var e: Dictionary = lay[id]
		var c := NFControls.center_of(e, rect)
		var r: float = e.r
		var on: bool = id == sel
		pad.draw_circle(c, r, Color(0.9, 0.2, 0.2, 0.22) if on else Color(1, 1, 1, 0.12))
		pad.draw_arc(c, r, 0, TAU, 44, Color(1, 0.3, 0.3, 0.95) if on else Color(1, 1, 1, 0.5), 2.5)
		NFIcons.draw(pad, NFControls.icon_of(id), c - Vector2(0, r * 0.16), r * 0.78, Color(1, 1, 1, 0.95))
		_say(c + Vector2(0, r * 0.52), NFControls.label_of(id), int(clampf(r * 0.33, 13.0, 20.0)), Color(1, 1, 1, 0.9))
		if on:
			pad.draw_arc(c, r + 7.0, 0, TAU, 44, Color(1, 0.85, 0.3, 0.8), 2.0)

func _say(at: Vector2, t: String, size: int, col: Color) -> void:
	var f: Font = Net.font if Net.font else ThemeDB.fallback_font
	pad.draw_string_outline(f, at - Vector2(300.0, 0), t, HORIZONTAL_ALIGNMENT_CENTER, 600.0, size, 5, Color(0, 0, 0, 0.85))
	pad.draw_string(f, at - Vector2(300.0, 0), t, HORIZONTAL_ALIGNMENT_CENTER, 600.0, size, col)
