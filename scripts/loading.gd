class_name NFLoading
extends CanvasLayer
## Shown while NightWorld builds itself over several frames: map name, a dark painted preview
## of that map and a random tip. Everything is drawn, so it costs no textures.

const TIPS := [
	"The killer hears a generator from 8 metres away",
	"Don't run too much — running leaves red marks the killer can see",
	"Hide in a locker, but careful… the killer searches lockers",
	"Five generators and the gates open",
	"Drop a pallet on the killer to stun her and get away",
	"Friend on the hook? Get there before their time runs out",
	"On your first hook you can free yourself by tapping fast without stopping",
	"The torch can be seen from far away — use it carefully",
	"If you're the last one left, an escape hatch opens somewhere random",
	"Once the gates open you have two minutes before the moon falls",
	"A heartbeat means the killer is within 24 metres",
	"The bag heals you only once — save it for a hard moment",
	"The market goes dark when the killer walks in",
	"Crouching hides the sound of your steps",
	"After the gate, follow the road to its end — that's the way out",
	"Repairing a generator needs well-timed taps, or it blows and the killer hears it",
	"In the Empty Quarter the sandstorm hides you — use it",
	"The bedouin tents have lockers to hide in",
	"Horses and camels won't hurt you, but they distract the killer",
]
const NAMES := {"forest": "The Forest", "village": "The Abandoned Village", "fareej": "The Fareej", "rubkhali": "The Empty Quarter",
	"garage": "The Car Park", "beach": "The Beach", "city": "City Life", "kuwait": "Kuwait City"}
const THEME_NAMES := {"snow": "Snow", "halloween": "Halloween"}

var map_id := "forest"
var theme := "normal"
var tip := ""
var f := 0.0        # build progress 0..1
var shown := 0.0    # seconds on screen
var fade := 1.0
var _pad: Control
var _card: TextureRect # the owner's picture of this map (assets/ui/maps), the same for every weather and mode
const Paint := preload("res://scripts/paint.gd")

func setup(id: String, th := "normal") -> void:
	map_id = id
	theme = th
	tip = TIPS[randi() % TIPS.size()]

func _ready() -> void:
	layer = 25
	_pad = Control.new()
	_pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pad.mouse_filter = Control.MOUSE_FILTER_STOP # no stray taps into the match
	_pad.draw.connect(_draw_pad)
	add_child(_pad)
	_card = Paint.card(map_id)
	if _card:
		_card.stretch_mode = TextureRect.STRETCH_SCALE
		_pad.add_child(_card)

func progress(v: float) -> void:
	f = maxf(f, clampf(v, 0.0, 1.0))

func _process(dt: float) -> void:
	shown += dt
	if fade < 1.0:
		fade = maxf(fade - dt * 2.2, 0.0)
		if fade <= 0.0:
			queue_free()
			return
	_pad.queue_redraw()

## Called when the world is up: keeps the tip readable for a moment, then fades out.
func finish() -> void:
	if fade >= 1.0: fade = 0.999

func busy() -> bool:
	return fade >= 1.0 or fade > 0.0

func _font() -> Font:
	return Net.font if Net.font else ThemeDB.fallback_font

func _say(at: Vector2, t: String, size: int, col: Color, width := 900.0) -> void:
	var fo := _font()
	_pad.draw_string_outline(fo, at - Vector2(width / 2.0, 0), t, HORIZONTAL_ALIGNMENT_CENTER, width, size, 6, Color(0, 0, 0, 0.9 * fade))
	_pad.draw_string(fo, at - Vector2(width / 2.0, 0), t, HORIZONTAL_ALIGNMENT_CENTER, width, size, Color(col, col.a * fade))

## A painted night view of the map: sky bands, a moon, and silhouettes in two depths.
func _draw_preview(r: Rect2) -> void:
	var a := fade
	_pad.draw_rect(r, Color(0.03, 0.035, 0.055, 0.95 * a))
	for i in 8: # sky gradient
		var k := i / 7.0
		_pad.draw_rect(Rect2(r.position + Vector2(0, r.size.y * 0.52 * k), Vector2(r.size.x, r.size.y * 0.52 / 7.0 + 1.0)),
			Color(0.05 + 0.04 * k, 0.06 + 0.05 * k, 0.11 + 0.07 * k, a))
	NFIcons.draw(_pad, "moon", r.position + Vector2(r.size.x * 0.78, r.size.y * 0.2), r.size.y * 0.2, Color(0.88, 0.9, 0.98, 0.75 * a))
	_pad.draw_rect(Rect2(r.position + Vector2(0, r.size.y * 0.62), Vector2(r.size.x, r.size.y * 0.38)), Color(0.035, 0.045, 0.04, a))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(map_id)
	var base := r.position.y + r.size.y * 0.66
	match map_id:
		"forest":
			for depth in 2:
				var col := Color(0.03, 0.05, 0.05, a) if depth == 0 else Color(0.015, 0.025, 0.03, a)
				var y := base + depth * r.size.y * 0.1
				var n := 13 + depth * 5
				for i in n:
					var x := r.position.x + r.size.x * (i + rng.randf()) / float(n)
					var h := r.size.y * rng.randf_range(0.22, 0.42) * (1.0 - depth * 0.25)
					var wd := h * 0.3
					_pad.draw_colored_polygon(PackedVector2Array([Vector2(x, y - h), Vector2(x - wd, y + 4.0), Vector2(x + wd, y + 4.0)]), col)
		"village":
			for depth in 2:
				var col2 := Color(0.04, 0.04, 0.05, a) if depth == 0 else Color(0.02, 0.02, 0.028, a)
				var y2 := base + depth * r.size.y * 0.12
				var n2 := 4 + depth * 2
				for i in n2:
					var w2 := r.size.x / float(n2) * rng.randf_range(0.5, 0.8)
					var x2 := r.position.x + r.size.x * i / float(n2) + rng.randf_range(4.0, 14.0)
					var h2 := r.size.y * rng.randf_range(0.2, 0.34)
					_pad.draw_rect(Rect2(Vector2(x2, y2 - h2), Vector2(w2, h2 + 6.0)), col2)
					_pad.draw_colored_polygon(PackedVector2Array([Vector2(x2 - 5.0, y2 - h2), Vector2(x2 + w2 / 2.0, y2 - h2 - r.size.y * 0.1), Vector2(x2 + w2 + 5.0, y2 - h2)]), col2)
					if depth == 0 and rng.randf() < 0.6: # one lit window
						_pad.draw_rect(Rect2(Vector2(x2 + w2 * 0.3, y2 - h2 * 0.6), Vector2(w2 * 0.18, h2 * 0.2)), Color(1.0, 0.72, 0.35, 0.5 * a))
		"kuwait": # the Gulf Road at night: the Assembly, the lit road, the sea and the towers
			_pad.draw_rect(r, Color(0.03, 0.04, 0.09, a))
			var sea_y := base - r.size.y * 0.06
			_pad.draw_rect(Rect2(Vector2(r.position.x + r.size.x * 0.62, sea_y), Vector2(r.size.x * 0.38, r.position.y + r.size.y - sea_y)), Color(0.03, 0.08, 0.16, a))
			_pad.draw_rect(Rect2(Vector2(r.position.x + r.size.x * 0.05, base - r.size.y * 0.3), Vector2(r.size.x * 0.32, r.size.y * 0.3 + 6.0)), Color(0.75, 0.68, 0.56, a))
			for i in 9: # the Assembly's ribs
				var rx := r.position.x + r.size.x * (0.07 + i * 0.034)
				_pad.draw_line(Vector2(rx, base - r.size.y * 0.3), Vector2(rx + 4.0, base), Color(0.95, 0.85, 0.65, 0.8 * a), 2.0)
			var road_l := r.position.x + r.size.x * 0.42
			var road_r := r.position.x + r.size.x * 0.6
			_pad.draw_colored_polygon(PackedVector2Array([Vector2(road_l, r.position.y + r.size.y), Vector2(road_r, r.position.y + r.size.y),
				Vector2(road_r - r.size.x * 0.07, base - r.size.y * 0.12), Vector2(road_l + r.size.x * 0.07, base - r.size.y * 0.12)]), Color(0.12, 0.12, 0.14, a))
			for i in 8: # street lights down the road
				var f := i / 7.0
				var lx := lerpf(road_l - 6.0, road_l + r.size.x * 0.06, f)
				var lx2 := lerpf(road_r + 6.0, road_r - r.size.x * 0.06, f)
				var ly := lerpf(r.position.y + r.size.y - 10.0, base - r.size.y * 0.12, f)
				_pad.draw_circle(Vector2(lx, ly - 10.0 * (1.0 - f * 0.6)), 2.5 - f, Color(1.0, 0.8, 0.45, a))
				_pad.draw_circle(Vector2(lx2, ly - 10.0 * (1.0 - f * 0.6)), 2.5 - f, Color(1.0, 0.8, 0.45, a))
			var tx := r.position.x + r.size.x * 0.82
			for t in [[0.0, 0.62, 0.1], [14.0, 0.5, 0.08], [-11.0, 0.4, 0.0]]: # the towers
				var top := base - r.size.y * float(t[1])
				_pad.draw_line(Vector2(tx + float(t[0]), base), Vector2(tx + float(t[0]), top), Color(0.85, 0.85, 0.9, a), 3.0)
				if float(t[2]) > 0.0:
					_pad.draw_circle(Vector2(tx + float(t[0]), base - r.size.y * float(t[1]) * 0.55), r.size.y * float(t[2]) * 0.6, Color(0.25, 0.5, 1.0, a))
		"city": # City Life: towers with lit windows and neon against a purple sky
			_pad.draw_rect(r, Color(0.07, 0.04, 0.1, a))
			for depth in 2:
				var n4 := 7 + depth * 4
				for i in n4:
					var w4 := r.size.x / float(n4) * rng.randf_range(0.5, 0.85)
					var x4 := r.position.x + r.size.x * i / float(n4) + rng.randf_range(0.0, 8.0)
					var h4 := r.size.y * rng.randf_range(0.3, 0.75) * (1.0 - depth * 0.3)
					var c4 := Color(0.05, 0.045, 0.07, a) if depth == 0 else Color(0.03, 0.025, 0.045, a)
					_pad.draw_rect(Rect2(Vector2(x4, base - h4), Vector2(w4, h4 + 6.0)), c4)
					if depth == 0:
						for k in 10:
							if rng.randf() < 0.45: continue
							_pad.draw_rect(Rect2(Vector2(x4 + w4 * rng.randf_range(0.1, 0.8), base - h4 * rng.randf_range(0.1, 0.95)), Vector2(3.0, 2.0)),
								Color(1.0, 0.8, 0.5, 0.6 * a) if rng.randf() < 0.6 else Color(0.6, 0.85, 1.0, 0.6 * a))
						if rng.randf() < 0.5:
							var nc: Color = [Color(1.0, 0.2, 0.65), Color(0.2, 0.9, 1.0), Color(0.75, 0.35, 1.0)][i % 3]
							_pad.draw_rect(Rect2(Vector2(x4 + w4 * 0.15, base - h4 * 0.55), Vector2(w4 * 0.7, 4.0)), Color(nc.r, nc.g, nc.b, 0.9 * a))
		"garage": # a row of concrete columns under a low slab, with a car and two strip lights
			var slab := Color(0.05, 0.05, 0.055, a)
			var cy := r.position.y + r.size.y * 0.18
			_pad.draw_rect(Rect2(Vector2(r.position.x, cy), Vector2(r.size.x, r.size.y * 0.07)), slab)
			_pad.draw_rect(Rect2(Vector2(r.position.x, base), Vector2(r.size.x, r.size.y * 0.3)), Color(0.07, 0.07, 0.075, a))
			for i in 5:
				var cx := r.position.x + r.size.x * (0.1 + i * 0.2)
				var cw := r.size.x * 0.035 * (1.0 + i * 0.05)
				_pad.draw_rect(Rect2(Vector2(cx, cy), Vector2(cw, base - cy)), Color(0.11, 0.11, 0.115, a))
				_pad.draw_rect(Rect2(Vector2(cx, base - r.size.y * 0.12), Vector2(cw, r.size.y * 0.03)), Color(0.5, 0.42, 0.08, a))
			for i in 2: # the strip lights and the pools of light under them
				var lx := r.position.x + r.size.x * (0.3 + i * 0.4)
				_pad.draw_rect(Rect2(Vector2(lx, cy + r.size.y * 0.07), Vector2(r.size.x * 0.1, r.size.y * 0.016)), Color(0.8, 0.9, 1.0, 0.75 * a))
				_pad.draw_colored_polygon(PackedVector2Array([Vector2(lx, cy + r.size.y * 0.09),
					Vector2(lx + r.size.x * 0.1, cy + r.size.y * 0.09), Vector2(lx + r.size.x * 0.22, base),
					Vector2(lx - r.size.x * 0.12, base)]), Color(0.55, 0.65, 0.8, 0.07 * a))
			var carx := r.position.x + r.size.x * 0.52
			var carw := r.size.x * 0.17
			_pad.draw_rect(Rect2(Vector2(carx, base - r.size.y * 0.1), Vector2(carw, r.size.y * 0.07)), Color(0.14, 0.1, 0.1, a))
			_pad.draw_rect(Rect2(Vector2(carx + carw * 0.2, base - r.size.y * 0.15), Vector2(carw * 0.6, r.size.y * 0.05)), Color(0.1, 0.08, 0.08, a))
		"rubkhali": # daylight: pale dunes and a white sun behind the blowing sand
			_pad.draw_rect(r, Color(0.62, 0.5, 0.33, a))
			var sunc := r.position + Vector2(r.size.x * 0.72, r.size.y * 0.3)
			for ring in 4:
				_pad.draw_circle(sunc, r.size.y * (0.06 + ring * 0.07), Color(1.0, 0.93, 0.72, a * 0.1))
			_pad.draw_circle(sunc, r.size.y * 0.055, Color(1.0, 0.97, 0.85, a * 0.85))
			var sand := Color(0.52, 0.42, 0.28, a)
			for depth in 3:
				var dy := base + depth * r.size.y * 0.1 - r.size.y * 0.12
				var pts := PackedVector2Array([Vector2(r.position.x, r.position.y + r.size.y)])
				for i in 15:
					var fx := i / 14.0
					pts.append(Vector2(r.position.x + r.size.x * fx,
						dy - sin(fx * PI * (1.4 + depth * 0.7) + depth * 2.1) * r.size.y * 0.1))
				pts.append(Vector2(r.position.x + r.size.x, r.position.y + r.size.y))
				_pad.draw_colored_polygon(pts, Color(sand.r + depth * 0.08, sand.g + depth * 0.06, sand.b + depth * 0.04, a))
			var tx := r.position.x + r.size.x * 0.33
			var th := r.size.y * 0.13
			_pad.draw_colored_polygon(PackedVector2Array([Vector2(tx - th * 1.9, base), Vector2(tx, base - th),
				Vector2(tx + th * 1.9, base), Vector2(tx + th * 1.5, base + 4.0), Vector2(tx - th * 1.5, base + 4.0)]), Color(0.17, 0.13, 0.1, a))
			for i in 3:
				var px2 := r.position.x + r.size.x * (0.62 + i * 0.09)
				var ph2 := r.size.y * rng.randf_range(0.2, 0.3)
				_pad.draw_line(Vector2(px2, base + 4.0), Vector2(px2 + ph2 * 0.08, base - ph2), Color(0.16, 0.13, 0.08, a), 3.0)
				for k in 6:
					var ang2: float = -PI * 0.9 + k * PI * 0.16
					_pad.draw_line(Vector2(px2 + ph2 * 0.08, base - ph2), Vector2(px2 + ph2 * 0.08, base - ph2) + Vector2(cos(ang2), sin(ang2)) * ph2 * 0.28,
						Color(0.16, 0.15, 0.09, a), 2.0)
			_pad.draw_rect(r, Color(0.78, 0.62, 0.38, 0.3 * a)) # the storm washes it all out
		_: # fareej: flat roofs, parapets, palms
			for depth in 2:
				var col3 := Color(0.055, 0.05, 0.045, a) if depth == 0 else Color(0.03, 0.027, 0.024, a)
				var y3 := base + depth * r.size.y * 0.12
				var n3 := 4 + depth
				for i in n3:
					var w3 := r.size.x / float(n3) * rng.randf_range(0.55, 0.85)
					var x3 := r.position.x + r.size.x * i / float(n3) + rng.randf_range(2.0, 12.0)
					var h3 := r.size.y * rng.randf_range(0.18, 0.3)
					_pad.draw_rect(Rect2(Vector2(x3, y3 - h3), Vector2(w3, h3 + 6.0)), col3)
					_pad.draw_rect(Rect2(Vector2(x3 - 3.0, y3 - h3 - 6.0), Vector2(w3 + 6.0, 7.0)), col3)
					if depth == 0 and rng.randf() < 0.7:
						_pad.draw_rect(Rect2(Vector2(x3 + w3 * 0.45, y3 - h3 * 0.55), Vector2(w3 * 0.16, h3 * 0.22)), Color(1.0, 0.68, 0.3, 0.45 * a))
			for i in 3:
				var px := r.position.x + r.size.x * rng.randf_range(0.1, 0.9)
				var ph := r.size.y * rng.randf_range(0.26, 0.4)
				_pad.draw_line(Vector2(px, base + 6.0), Vector2(px + ph * 0.1, base - ph), Color(0.02, 0.02, 0.018, a), 3.0)
				for k in 7:
					var ang: float = -PI * 0.92 + k * PI * 0.14
					_pad.draw_line(Vector2(px + ph * 0.1, base - ph), Vector2(px + ph * 0.1, base - ph) + Vector2(cos(ang), sin(ang)) * ph * 0.3,
						Color(0.02, 0.025, 0.02, a), 2.0)
	if theme == "snow": _pad.draw_rect(r, Color(0.7, 0.8, 0.95, 0.12 * a))
	elif theme == "halloween": _pad.draw_rect(r, Color(0.9, 0.35, 0.05, 0.12 * a))
	_pad.draw_rect(r, Color(0.5, 0.08, 0.09, 0.8 * a), false, 2.0)

func _draw_pad() -> void:
	var s: Vector2 = _pad.size
	var a := fade
	_pad.draw_rect(Rect2(Vector2.ZERO, s), Color(0.012, 0.012, 0.017, a))
	var safe := NFUI.safe_insets(get_viewport())
	var pw: float = minf(s.x - safe.x - safe.y - 120.0, 720.0)
	var ph: float = minf(s.y * 0.46, pw * 0.42)
	if _card and _card.texture: # his picture, whole, at its own shape
		var asp: float = float(_card.texture.get_width()) / float(_card.texture.get_height())
		ph = minf(s.y * 0.46, pw / asp)
		pw = ph * asp
	var pr := Rect2(Vector2((s.x - pw) / 2.0, s.y * 0.2), Vector2(pw, ph))
	if _card:
		_card.position = pr.position
		_card.size = pr.size
		_card.modulate.a = a
		_pad.draw_rect(pr.grow(3.0), Color(0.5, 0.08, 0.09, 0.8 * a), false, 2.0)
	else: _draw_preview(pr)
	var title: String = str(NAMES.get(map_id, map_id))
	if THEME_NAMES.has(theme): title += "  •  " + str(THEME_NAMES[theme])
	_say(Vector2(s.x / 2.0, s.y * 0.1), title, 46, Color(0.88, 0.14, 0.15))
	_say(Vector2(s.x / 2.0, pr.position.y + ph + 40.0), tip, 24, Color(1.0, 0.86, 0.5), minf(s.x - 80.0, 1000.0))
	var bw: float = minf(pw, 560.0)
	var br := Rect2(Vector2((s.x - bw) / 2.0, pr.position.y + ph + 92.0), Vector2(bw, 16.0))
	NFUI.bar(_pad, br, f, Color(0.78, 0.1, 0.1, a), Color(1, 1, 1, 0.3 * a))
	var dots := ".".repeat(1 + int(shown * 2.0) % 3)
	_say(Vector2(s.x / 2.0, br.position.y + 40.0), ("Building the map" + dots) if f < 1.0 else "Ready!", 20, Color(0.7, 0.72, 0.75))
