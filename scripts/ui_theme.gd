class_name NFUI
extends RefCounted
## The horror look of the interface: dark scratched panels, dry-blood accents, one shared Theme,
## plus the click sound hook. No sound is synthesized here: if the owner has not dropped a file in
## assets/sfx (ui_click.mp3 / click.mp3) the buttons stay silent.

const CLICK_FILES := ["res://assets/sfx/ui_click.mp3", "res://assets/sfx/click.mp3"]

const INK := Color(0.055, 0.047, 0.055)      # panel body
const INK2 := Color(0.105, 0.086, 0.094)     # raised body
const BLOOD := Color(0.52, 0.07, 0.08)       # accent / border
const BLOOD_HI := Color(0.85, 0.13, 0.14)    # hover accent
const BONE := Color(0.90, 0.88, 0.86)        # text
const DIM := Color(0.46, 0.44, 0.44)

## Signature colour of every character: team bar, player card, results, map markers.
const CHAR_COL := {
	"killer": Color(0.78, 0.13, 0.13),
	"survivor1": Color(0.38, 0.58, 0.92),
	"survivor2": Color(0.88, 0.26, 0.30),
	"survivor3": Color(0.46, 0.82, 0.56),
	"survivor4": Color(0.93, 0.72, 0.32),
	"survivor5": Color(0.70, 0.46, 0.92),
	"survivor6": Color(0.40, 0.86, 0.86),
	"survivor7": Color(0.95, 0.56, 0.76),
}

static var _theme: Theme
static var _dot: ImageTexture
static var _click: AudioStreamPlayer
static var _click_tried := false

## Round, soft-edged sprite shared by the particle systems (fire, breath, snow, dust).
static func soft_dot() -> ImageTexture:
	if _dot: return _dot
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5).length() / 31.5
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	_dot = ImageTexture.create_from_image(img)
	return _dot

static func char_col(id: String) -> Color:
	return CHAR_COL.get(id, Color(0.75, 0.75, 0.78))

# ---------------- style boxes ----------------
static func _sb(bg: Color, border: Color, bw := 2, left_accent := 0.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.border_width_left = bw # RTL: the thick accent sits on the right
	s.border_width_right = int(bw + left_accent)
	s.set_corner_radius_all(3)
	s.content_margin_left = 14; s.content_margin_right = 14
	s.content_margin_top = 8; s.content_margin_bottom = 8
	s.shadow_color = Color(0, 0, 0, 0.55)
	s.shadow_size = 4
	s.shadow_offset = Vector2(0, 2)
	return s

static func panel_style(strong := false) -> StyleBoxFlat:
	var s := _sb(Color(0.035, 0.03, 0.035, 0.88 if strong else 0.72), Color(BLOOD, 0.75), 2)
	s.content_margin_left = 16; s.content_margin_right = 16
	s.content_margin_top = 12; s.content_margin_bottom = 12
	return s

static func theme() -> Theme:
	if _theme: return _theme
	var t := Theme.new()
	t.default_font_size = 24
	# no default_font on purpose: Net installs the Arabic font on the project's default theme,
	# which this one falls back to. (Gfx builds its menu before Net has loaded the font.)
	var normal := _sb(INK2, Color(BLOOD, 0.8), 2, 3.0)
	var hover := _sb(Color(0.17, 0.09, 0.10), BLOOD_HI, 2, 4.0)
	var pressed := _sb(Color(0.30, 0.05, 0.06), BLOOD_HI, 2, 4.0)
	var disabled := _sb(Color(0.07, 0.07, 0.075, 0.75), Color(0.3, 0.3, 0.3, 0.6), 1)
	for cls in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", cls, normal)
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("pressed", cls, pressed)
		t.set_stylebox("disabled", cls, disabled)
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
		t.set_color("font_color", cls, BONE)
		t.set_color("font_hover_color", cls, Color(1, 0.95, 0.92))
		t.set_color("font_pressed_color", cls, Color(1, 0.88, 0.85))
		t.set_color("font_disabled_color", cls, DIM)
		t.set_constant("outline_size", cls, 0)
	t.set_stylebox("normal", "LineEdit", _sb(Color(0.03, 0.028, 0.032, 0.92), Color(0.42, 0.14, 0.14, 0.9), 2))
	t.set_stylebox("focus", "LineEdit", _sb(Color(0.05, 0.03, 0.035, 0.95), BLOOD_HI, 2))
	t.set_color("font_color", "LineEdit", BONE)
	t.set_color("font_placeholder_color", "LineEdit", Color(0.55, 0.5, 0.5))
	t.set_color("caret_color", "LineEdit", BLOOD_HI)
	t.set_stylebox("panel", "PanelContainer", panel_style(true))
	t.set_stylebox("panel", "Panel", panel_style(true))
	t.set_stylebox("panel", "PopupMenu", panel_style(true))
	t.set_color("font_color", "Label", BONE)
	t.set_color("font_color", "PopupMenu", BONE)
	t.set_stylebox("slider", "HSlider", _sb(Color(0.08, 0.07, 0.08), Color(0.3, 0.1, 0.1), 1))
	t.set_stylebox("grabber_area", "HSlider", _sb(BLOOD, Color(BLOOD_HI, 0.9), 1))
	t.set_stylebox("grabber_area_highlight", "HSlider", _sb(BLOOD_HI, BLOOD_HI, 1))
	_theme = t
	return t

# ---------------- click sound (only a file the owner supplied) ----------------
static func click_file() -> String:
	for f in CLICK_FILES:
		if ResourceLoader.exists(f): return f
	return ""

static func click() -> void:
	if not _click_tried:
		_click_tried = true
		var f := click_file()
		if f != "":
			var ml := Engine.get_main_loop()
			if ml is SceneTree and (ml as SceneTree).root:
				_click = AudioStreamPlayer.new()
				_click.bus = Aud.SFX
				_click.stream = load(f)
				_click.volume_db = -8.0
				_click.process_mode = Node.PROCESS_MODE_ALWAYS
				(ml as SceneTree).root.add_child(_click)
	if _click:
		_click.pitch_scale = randf_range(0.96, 1.05)
		_click.play()

# ---------------- drawing helpers ----------------
## A few dry scratches and a torn edge over a button, deterministic per button.
static func scratches(ci: CanvasItem, size: Vector2, seedv: int, hot: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seedv
	var col := Color(1, 1, 1, 0.07)
	for i in 4:
		var y := rng.randf_range(3.0, size.y - 3.0)
		var x := rng.randf_range(0.0, size.x * 0.55)
		var len := rng.randf_range(size.x * 0.14, size.x * 0.4)
		ci.draw_line(Vector2(x, y), Vector2(x + len, y + rng.randf_range(-3.0, 3.0)), col, rng.randf_range(0.8, 1.6), true)
	for i in 2: # dry-blood nicks on the accent edge
		var y2 := rng.randf_range(4.0, size.y - 8.0)
		ci.draw_line(Vector2(size.x - 2.0, y2), Vector2(size.x - rng.randf_range(8.0, 22.0), y2 + rng.randf_range(-2.0, 2.0)),
			Color(BLOOD_HI if hot else BLOOD, 0.5), 1.4, true)
	ci.draw_line(Vector2(0, size.y - 1.0), Vector2(size.x, size.y - 1.0), Color(0, 0, 0, 0.35), 2.0)

## Progress bar with a dark bed and a bright fill.
static func bar(ci: CanvasItem, r: Rect2, f: float, fill: Color, border := Color(1, 1, 1, 0.35)) -> void:
	ci.draw_rect(r, Color(0, 0, 0, 0.6))
	var k := clampf(f, 0.0, 1.0)
	if k > 0.0: ci.draw_rect(Rect2(r.position, Vector2(r.size.x * k, r.size.y)), fill)
	ci.draw_rect(r, border, false, 1.5)

## Apply the horror look to a Button: theme styles + scratches + an optional icon on the leading edge.
static func dress(b: Button, icon := "", click_sound := true) -> void:
	b.theme = theme()
	b.focus_mode = Control.FOCUS_NONE
	if click_sound: b.pressed.connect(NFUI.click)
	var ov := Control.new()
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(ov)
	var sd := int(absi(hash(b.text + icon)) % 100000)
	ov.draw.connect(func() -> void:
		var sz := ov.size
		scratches(ov, sz, sd, b.is_hovered())
		if icon != "":
			var col := Color(BLOOD_HI, 0.95) if not b.disabled else Color(DIM, 0.7)
			NFIcons.draw(ov, icon, Vector2(sz.x - 26.0, sz.y / 2.0), minf(26.0, sz.y * 0.55), col))
	b.resized.connect(ov.queue_redraw)
	b.mouse_entered.connect(ov.queue_redraw)
	b.mouse_exited.connect(ov.queue_redraw)

## Screen insets (left, right) to stay clear of the notch / Dynamic Island, in UI units.
static func safe_insets(vp: Viewport) -> Vector2:
	var win := Vector2(DisplayServer.window_get_size())
	var area := DisplayServer.get_display_safe_area()
	if win.x <= 0.0 or area.size.x <= 0 or vp == null: return Vector2.ZERO
	var k: float = vp.get_visible_rect().size.x / win.x
	return Vector2(maxf(area.position.x, 0.0) * k, maxf(win.x - float(area.position.x + area.size.x), 0.0) * k)
