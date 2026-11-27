extends Control
## The Social Sidebar (the owner: "like PUBG and Call of Duty"): a dark glass panel that slides in from
## the right over the start screen. Two tabs, FRIENDS and REQUESTS. Every friend: their character's
## portrait (assets/ui/portraits) ringed in their status colour, display name, @username and level,
## and where they are (In Menu / In Lobby / In Match / Offline, last seen); online ones get INVITE.
## Requests: the ones I got (Accept / Decline) and the ones I sent (Pending, Cancel). Friends, requests
## and usernames live on the server (accounts), the phone keeps a copy. No class_name: preloaded by menu.

signal profile(name: String) # a friend's row was tapped: the menu opens their profile
signal invite(name: String)  # INVITE was tapped: the menu makes a room if needed and sends it
signal more_page             # the old friends page (the secret character's code and gifts)

const W := 460.0
const ACC := Color(0.92, 0.16, 0.13)
const ST_COL := {"menu": Color(0.3, 0.9, 0.45), "room": Color(0.35, 0.7, 1.0), "game": Color(1.0, 0.62, 0.2), "off": Color(0.45, 0.45, 0.48)}
const ST_TXT := {"menu": "Online · In Menu", "room": "Online · In Lobby", "game": "In Match", "off": "Offline"}

var tab := "friends"
var shown := 0.0     # 0 closed .. 1 open (slides)
var want := false
var panel: Control
var head: Control
var scroll: ScrollContainer
var list: VBoxContainer
var add_edit: LineEdit
var _tex := {}
var _dirty := true
var note := ""
var note_t := 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var dim := ColorRect.new() # tapping outside the panel closes it
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if (e is InputEventScreenTouch or e is InputEventMouseButton) and e.pressed: close())
	add_child(dim)
	panel = Control.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	var glass := ColorRect.new() # the blurred screen behind it, tinted dark (frosted glass)
	glass.set_anchors_preset(Control.PRESET_FULL_RECT)
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = Shader.new()
	sm.shader.code = """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, 3.2).rgb;
	COLOR = vec4(mix(c * 0.3, vec3(0.025, 0.025, 0.032), 0.94), 0.99);
}"""
	glass.material = sm
	panel.add_child(glass)
	head = Control.new() # the header, tabs and notes, drawn over the glass
	head.set_anchors_preset(Control.PRESET_FULL_RECT)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.draw.connect(_draw_panel)
	panel.add_child(head)
	# header: title, close, my own row
	var close_b := Button.new()
	close_b.text = "✕"
	close_b.flat = true
	close_b.position = Vector2(W - 170, 12) # left of the settings gear, which is always on screen
	close_b.size = Vector2(48, 44)
	close_b.add_theme_font_size_override("font_size", 26)
	close_b.pressed.connect(close)
	panel.add_child(close_b)
	for t in [["friends", "FRIENDS"], ["requests", "REQUESTS"]]:
		var b := Button.new()
		b.flat = true
		b.position = Vector2(18 + (0 if t[0] == "friends" else (W - 36) / 2.0), 140)
		b.size = Vector2((W - 36) / 2.0, 44)
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		var id: String = t[0]
		b.pressed.connect(func() -> void:
			NFUI.click()
			tab = id
			_dirty = true)
		panel.add_child(b)
	# add a friend by username
	add_edit = LineEdit.new()
	add_edit.placeholder_text = "Add friend by username"
	add_edit.position = Vector2(18, 198)
	add_edit.size = Vector2(W - 36 - 96, 46)
	add_edit.add_theme_font_size_override("font_size", 20)
	var es := StyleBoxFlat.new()
	es.bg_color = Color(1, 1, 1, 0.06)
	es.border_color = Color(1, 1, 1, 0.14)
	es.set_border_width_all(1)
	es.set_corner_radius_all(6)
	es.content_margin_left = 14
	for st in ["normal", "focus"]: add_edit.add_theme_stylebox_override(st, es)
	add_edit.text_submitted.connect(func(_t): _send_request())
	panel.add_child(add_edit)
	var add_b := _pill("SEND", ACC, _send_request)
	add_b.position = Vector2(W - 18 - 88, 198)
	add_b.size = Vector2(88, 46)
	panel.add_child(add_b)
	scroll = ScrollContainer.new()
	scroll.position = Vector2(0, 258)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	list = VBoxContainer.new()
	list.custom_minimum_size.x = W
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	if Net.font:
		for c in [close_b, add_edit]: c.add_theme_font_override("font", Net.font)
	Net.changed.connect(func() -> void: _dirty = true)
	Net.social_changed.connect(func() -> void:
		_dirty = true
		if Net.social_note != "":
			note = Net.social_note
			note_t = 4.0
			Net.social_note = "")

func open() -> void:
	want = true
	visible = true
	_dirty = true

func close() -> void:
	want = false

func _send_request() -> void:
	var n := add_edit.text.strip_edges()
	if n == "": return
	NFUI.click()
	Net.add_friend(n)
	add_edit.text = ""
	note = "Request sent to @%s" % n
	note_t = 3.0
	tab = "requests"
	_dirty = true

func _process(dt: float) -> void:
	shown = move_toward(shown, 1.0 if want else 0.0, dt * 5.0)
	if shown <= 0.0 and not want:
		visible = false
		return
	var vs := get_viewport().get_visible_rect().size
	var safe := NFUI.safe_insets(get_viewport())
	var e := 1.0 - pow(1.0 - shown, 3.0)
	panel.size = Vector2(W + safe.y, vs.y)
	panel.position = Vector2(vs.x - (W + safe.y) * e, 0)
	(get_node("Dim") as ColorRect).color.a = 0.4 * e
	scroll.size = Vector2(W, vs.y - 258 - 8)
	if note_t > 0.0:
		note_t -= dt
		head.queue_redraw()
	if _dirty:
		_dirty = false
		_build()
		head.queue_redraw()

func _portrait(ch: String) -> Texture2D:
	if not _tex.has(ch):
		var p := "res://assets/ui/portraits/%s.png" % ch
		_tex[ch] = load(p) if ResourceLoader.exists(p) else null
	return _tex[ch]

func _pill(text: String, col: Color, cb: Callable, filled := true) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 16)
	if Net.font: b.add_theme_font_override("font", Net.font)
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var s := StyleBoxFlat.new()
		s.bg_color = (col if filled else Color(0, 0, 0, 0)) * Color(1, 1, 1, 0.92 if st != "pressed" else 1.0)
		if st == "hover": s.bg_color = s.bg_color.lightened(0.1)
		s.border_color = col
		s.set_border_width_all(0 if filled else 2)
		s.set_corner_radius_all(6)
		s.content_margin_left = 12
		s.content_margin_right = 12
		b.add_theme_stylebox_override(st, s)
	b.add_theme_color_override("font_color", Color.WHITE if filled else col)
	b.pressed.connect(func() -> void:
		NFUI.click()
		cb.call())
	return b

func _section(text: String) -> void:
	var l := Label.new()
	l.text = "   " + text
	l.custom_minimum_size = Vector2(W, 34)
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(0.62, 0.62, 0.66))
	if Net.font: l.add_theme_font_override("font", Net.font)
	list.add_child(l)

## One person: portrait in a status ring, display name, @username · level, a status line, and buttons.
func _row(n: String, st: String, line: String, buttons: Array) -> void:
	var r := Control.new()
	r.custom_minimum_size = Vector2(W, 74)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	var tex := _portrait(Net.char_of(n))
	var lv := int(Net.fdisplay.get(n.to_lower(), {}).get("lv", Net.fstats.get(n.to_lower(), {}).get("lv", 0)))
	r.draw.connect(func() -> void:
		var f: Font = Net.font if Net.font else ThemeDB.fallback_font
		r.draw_rect(Rect2(Vector2(12, 3), Vector2(W - 24, 68)), Color(1, 1, 1, 0.045))
		var c := Vector2(48, 37)
		var col: Color = ST_COL.get(st, ST_COL.off)
		r.draw_circle(c, 27.0, col if st != "off" else Color(0.3, 0.3, 0.33), true, -1.0, true)
		if tex:
			r.draw_texture_rect(tex, Rect2(c - Vector2(24, 24), Vector2(48, 48)), false, Color(1, 1, 1, 1) if st != "off" else Color(0.5, 0.5, 0.53))
		r.draw_circle(c + Vector2(19, 19), 6.5, Color(0.05, 0.05, 0.06), true, -1.0, true)
		r.draw_circle(c + Vector2(19, 19), 4.8, col, true, -1.0, true)
		r.draw_string(f, Vector2(88, 30), Net.display_of(n), HORIZONTAL_ALIGNMENT_LEFT, 200, 21, Color(0.96, 0.95, 0.93))
		r.draw_string(f, Vector2(88, 49), "@%s%s" % [n, ("  ·  Lv %d" % lv) if lv > 0 else ""], HORIZONTAL_ALIGNMENT_LEFT, 200, 14, Color(0.6, 0.6, 0.64))
		r.draw_string(f, Vector2(88, 66), line, HORIZONTAL_ALIGNMENT_LEFT, 210, 14, col if st != "off" else Color(0.55, 0.55, 0.58)))
	r.gui_input.connect(func(e: InputEvent) -> void:
		if (e is InputEventScreenTouch or e is InputEventMouseButton) and e.pressed and tab == "friends": profile.emit(n))
	var x := W - 22.0
	for b in buttons:
		var bt: Button = b
		var bw: float = maxf(bt.get_combined_minimum_size().x, 76.0)
		x -= bw
		bt.position = Vector2(x, 19)
		bt.size = Vector2(bw, 36)
		x -= 8.0
		r.add_child(bt)
	list.add_child(r)

func _status_line(n: String) -> String:
	var st := Net.status_of(n)
	if st != "off": return ST_TXT[st]
	return Net.status_text(n) # "Offline", or how long ago
func _build() -> void:
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	if tab == "friends":
		var on: Array = []
		var off: Array = []
		for f in Net.friends: (on if Net.is_online(str(f)) else off).append(str(f))
		on.sort_custom(func(a, b): return Net.display_of(a).naturalnocasecmp_to(Net.display_of(b)) < 0)
		off.sort_custom(func(a, b): return Net.display_of(a).naturalnocasecmp_to(Net.display_of(b)) < 0)
		if Net.friends.is_empty():
			_section("No friends yet — add one by username above")
		_section("ONLINE — %d" % on.size())
		for n in on:
			var st := Net.status_of(n)
			var bs := []
			if st != "game":
				var nn: String = n
				bs.append(_pill("INVITE", ACC, func(): invite.emit(nn)))
			_row(n, st, _status_line(n), bs)
		_section("OFFLINE — %d" % off.size())
		for n in off:
			var nn: String = n
			_row(n, "off", _status_line(n), [_pill("INVITE", Color(0.55, 0.55, 0.6), func(): invite.emit(nn), false)])
		var more := _pill("Secret character code & gifts", Color(0.55, 0.55, 0.6), func(): more_page.emit(), false)
		more.custom_minimum_size = Vector2(0, 40)
		var mc := MarginContainer.new()
		mc.add_theme_constant_override("margin_left", 18)
		mc.add_theme_constant_override("margin_right", 18)
		mc.add_theme_constant_override("margin_top", 12)
		mc.add_child(more)
		list.add_child(mc)
	else:
		_section("RECEIVED — %d" % Net.req_in.size())
		if Net.req_in.is_empty(): _section("      Nothing waiting")
		for r in Net.req_in:
			var n := str(r.name)
			_row(n, "menu" if Net.is_online(n) else "off", "Wants to be your friend", [
				_pill("✕", Color(0.5, 0.5, 0.54), func(): Net.decline_friend(n), false),
				_pill("ACCEPT", Color(0.2, 0.72, 0.36), func(): Net.accept_friend(n))])
		_section("SENT — %d" % Net.req_out.size())
		for n in Net.req_out:
			var nn := str(n)
			_row(nn, "off", "Pending…", [_pill("CANCEL", Color(0.55, 0.55, 0.6), func(): Net.cancel_request(nn), false)])

func _draw_panel() -> void:
	var s := head.size
	var f: Font = Net.font if Net.font else ThemeDB.fallback_font
	head.draw_rect(Rect2(Vector2.ZERO, Vector2(3, s.y)), ACC) # the red edge
	head.draw_string(f, Vector2(22, 46), "SOCIAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(0.97, 0.96, 0.94))
	var on := 0
	for x in Net.friends: if Net.is_online(str(x)): on += 1
	head.draw_circle(Vector2(146, 37), 5.0, ST_COL.menu, true, -1.0, true)
	head.draw_string(f, Vector2(156, 44), "%d online" % on, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.7, 0.72, 0.74))
	# me
	var me_tex := _portrait(Net.last_char if Net.last_char != "" else "survivor1")
	var c := Vector2(48, 96)
	head.draw_circle(c, 25.0, ACC, true, -1.0, true)
	if me_tex: head.draw_texture_rect(me_tex, Rect2(c - Vector2(22, 22), Vector2(44, 44)), false)
	head.draw_arc(c, 24.0, 0, TAU, 40, ACC, 3.0, true)
	var dn := Net.display if Net.display != "" else Net.username
	head.draw_string(f, Vector2(86, 92), dn, HORIZONTAL_ALIGNMENT_LEFT, 260, 21, Color(0.97, 0.96, 0.94))
	head.draw_string(f, Vector2(86, 114), "@%s  ·  Lv %d  ·  %s" % [Net.username, Net.level(), "Online" if Net.state == "online" else "Offline"],
		HORIZONTAL_ALIGNMENT_LEFT, 340, 14, ST_COL.menu if Net.state == "online" else Color(0.6, 0.6, 0.62))
	# the tabs
	var tw := (W - 36) / 2.0
	for k in 2:
		var id := "friends" if k == 0 else "requests"
		var x := 18.0 + k * tw
		var sel := tab == id
		var label := "FRIENDS  %d" % Net.friends.size() if k == 0 else "REQUESTS"
		head.draw_string(f, Vector2(x, 170), label, HORIZONTAL_ALIGNMENT_CENTER, tw, 18, Color(0.97, 0.96, 0.94) if sel else Color(0.55, 0.55, 0.6))
		head.draw_rect(Rect2(Vector2(x + 8, 182), Vector2(tw - 16, 3)), ACC if sel else Color(1, 1, 1, 0.08))
		if k == 1 and Net.req_in.size() > 0: # a badge for requests waiting
			var bc := Vector2(x + tw / 2.0 + 62, 160)
			head.draw_circle(bc, 11.0, ACC, true, -1.0, true)
			head.draw_string(f, bc + Vector2(-11, 6), str(Net.req_in.size()), HORIZONTAL_ALIGNMENT_CENTER, 22, 15, Color.WHITE)
	if note_t > 0.0: # what just happened, for a few seconds
		var a := clampf(note_t, 0.0, 1.0)
		head.draw_rect(Rect2(Vector2(18, s.y - 54), Vector2(W - 36, 40)), Color(0.08, 0.08, 0.09, 0.95 * a))
		head.draw_rect(Rect2(Vector2(18, s.y - 54), Vector2(4, 40)), Color(ACC, a))
		head.draw_string(f, Vector2(32, s.y - 28), note, HORIZONTAL_ALIGNMENT_LEFT, W - 60, 16, Color(1, 1, 1, a))
