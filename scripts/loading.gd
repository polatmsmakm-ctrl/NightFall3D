class_name NFLoading
extends CanvasLayer
## Shown while NightWorld builds itself over several frames: map name, a dark painted preview
## of that map and a random tip. Everything is drawn, so it costs no textures.

const TIPS := [
	"القاتل يسمع المولد من 8 أمتار",
	"لا تركض كثير — الركض يخلّي أثر أحمر يشوفه القاتل",
	"اختبئ بالخزانة، بس خذ بالك… القاتل يفتّش الخزانات",
	"خمس مولدات وتنفتح البوابات",
	"اسقط الباب على القاتل ويتصعق وتهرب منه",
	"صاحبك على الخطاف؟ طير له قبل لا يخلص وقته",
	"أول مرة تنعلّق تقدر تفك نفسك إذا ضغطت بسرعة وبدون توقف",
	"الكشاف يبيّن من بعيد — شغّله بحذر",
	"إذا بقيت وحدك تنفتح لك فتحة هروب بمكان عشوائي",
	"لما تنفتح البوابات عندك دقيقتين قبل القمر ينزل على الخريطة",
	"دقات القلب معناها القاتل داخل ٢٤ متر منك",
	"الحقيبة تعالجك مرة واحدة بس — خلّها للوقت الصعب",
	"السوق يصير ظلام لما يدخله القاتل",
	"الانحناء يخفّي صوت خطواتك",
	"بعد البوابة امشِ للطريق لين آخره، هناك تطلع برّا",
	"تصليح المولد يبي ضغطات بالوقت الصح، وإلا ينفجر ويسمعه القاتل",
	"بالربع الخالي العجاج يغطي الرؤية — استغله واختفِ",
	"بيوت الشعر فيها خزانات تختبئ فيها",
	"الخيل والبعارين ما يأذونك، بس يشتتون نظر القاتل",
]
const NAMES := {"forest": "الغابة", "village": "القرية المهجورة", "fareej": "الفريج", "rubkhali": "الربع الخالي"}
const THEME_NAMES := {"snow": "ثلج", "halloween": "هالوين"}

var map_id := "forest"
var theme := "normal"
var tip := ""
var f := 0.0        # build progress 0..1
var shown := 0.0    # seconds on screen
var fade := 1.0
var _pad: Control

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
		"rubkhali": # dunes, a tent and a palm cluster in a dust haze
			var sand := Color(0.3, 0.24, 0.17, a)
			for depth in 3:
				var dy := base + depth * r.size.y * 0.1 - r.size.y * 0.12
				var pts := PackedVector2Array([Vector2(r.position.x, r.position.y + r.size.y)])
				for i in 15:
					var fx := i / 14.0
					pts.append(Vector2(r.position.x + r.size.x * fx,
						dy - sin(fx * PI * (1.4 + depth * 0.7) + depth * 2.1) * r.size.y * 0.1))
				pts.append(Vector2(r.position.x + r.size.x, r.position.y + r.size.y))
				_pad.draw_colored_polygon(pts, Color(sand.r + depth * 0.03, sand.g + depth * 0.02, sand.b + depth * 0.01, a))
			var tx := r.position.x + r.size.x * 0.33
			var th := r.size.y * 0.13
			_pad.draw_colored_polygon(PackedVector2Array([Vector2(tx - th * 1.9, base), Vector2(tx, base - th),
				Vector2(tx + th * 1.9, base), Vector2(tx + th * 1.5, base + 4.0), Vector2(tx - th * 1.5, base + 4.0)]), Color(0.1, 0.08, 0.07, a))
			for i in 3:
				var px2 := r.position.x + r.size.x * (0.62 + i * 0.09)
				var ph2 := r.size.y * rng.randf_range(0.2, 0.3)
				_pad.draw_line(Vector2(px2, base + 4.0), Vector2(px2 + ph2 * 0.08, base - ph2), Color(0.09, 0.08, 0.06, a), 3.0)
				for k in 6:
					var ang2: float = -PI * 0.9 + k * PI * 0.16
					_pad.draw_line(Vector2(px2 + ph2 * 0.08, base - ph2), Vector2(px2 + ph2 * 0.08, base - ph2) + Vector2(cos(ang2), sin(ang2)) * ph2 * 0.28,
						Color(0.09, 0.09, 0.07, a), 2.0)
			_pad.draw_rect(r, Color(0.5, 0.36, 0.18, 0.1 * a)) # dust haze
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
	var pr := Rect2(Vector2((s.x - pw) / 2.0, s.y * 0.2), Vector2(pw, ph))
	_draw_preview(pr)
	var title: String = str(NAMES.get(map_id, map_id))
	if THEME_NAMES.has(theme): title += "  •  " + str(THEME_NAMES[theme])
	_say(Vector2(s.x / 2.0, s.y * 0.1), title, 46, Color(0.88, 0.14, 0.15))
	_say(Vector2(s.x / 2.0, pr.position.y + ph + 24.0), tip, 24, Color(1.0, 0.86, 0.5), minf(s.x - 80.0, 1000.0))
	var bw: float = minf(pw, 560.0)
	var br := Rect2(Vector2((s.x - bw) / 2.0, pr.position.y + ph + 76.0), Vector2(bw, 16.0))
	NFUI.bar(_pad, br, f, Color(0.78, 0.1, 0.1, a), Color(1, 1, 1, 0.3 * a))
	var dots := ".".repeat(1 + int(shown * 2.0) % 3)
	_say(Vector2(s.x / 2.0, br.position.y + 40.0), ("جاري بناء الخريطة" + dots) if f < 1.0 else "جاهز!", 20, Color(0.7, 0.72, 0.75))
