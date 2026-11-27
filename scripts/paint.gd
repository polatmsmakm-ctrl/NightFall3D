extends RefCounted
## The owner's paintings on screen: the camp (the start screen's fixed background) and one card per
## map (the map picker and the loading screen). They never change with the map, the weather or the
## mode. Only what he asked to move moves, through shaders/painted.gdshader: the camp's fire and moon,
## the moons on the forest / beach / Kuwait City cards, and Kuwait City's palms and trees (and the
## beach's palms). Coordinates are in each picture's own pixels.
## No class_name (an in-game update can carry it): `const Paint := preload("res://scripts/paint.gd")`.

const CAMP := "res://assets/ui/camp_bg.png"
const CAMP_SIZE := Vector2(1672.0, 941.0)
## Where things are in the camp painting (pixels of camp_bg.png).
const CAMP_FIRE := Vector2(655.0, 660.0)     # the middle of the fire, on the ground
const CAMP_HORIZON := 545.0                  # the eye line of the painting
const CAMP_FOCAL := 1009.0                   # its lens, in pixels (about 50 degrees across its height)
const CAMP_EYE := 0.88                       # how high the painter's eye was, in metres

## Each map card: its moving parts. moon = [x, y, r]; sway = regions [x0, y0, x1, y1]; lamp = [x, y, r].
const CARDS := {
	"forest": {"moon": [556.0, 30.0, 13.0], "lamp": [583.0, 129.0, 8.0]},
	"village": {"lamp": [592.0, 85.0, 6.0]},
	"rubkhali": {},
	"garage": {},
	"beach": {"moon": [569.0, 27.0, 12.0], "sway": [[0.0, 2.0, 215.0, 126.0]]},
	"city": {},
	"kuwait": {"moon": [670.0, 37.0, 10.0], "sway": [[0.0, 14.0, 152.0, 152.0], [652.0, 74.0, 734.0, 152.0], [152.0, 118.0, 652.0, 150.0]]},
}

static var _noise: Texture2D
static var _shader: Shader

static func noise() -> Texture2D:
	if _noise == null:
		var n := FastNoiseLite.new()
		n.frequency = 0.02
		n.fractal_octaves = 3
		var t := NoiseTexture2D.new()
		t.width = 256
		t.height = 256
		t.seamless = true
		t.noise = n
		_noise = t
	return _noise

static func shader() -> Shader:
	if _shader == null: _shader = load("res://shaders/painted.gdshader")
	return _shader

static func has_camp() -> bool:
	return ResourceLoader.exists(CAMP)

static func card_path(id: String) -> String:
	var p := "res://assets/ui/maps/%s.png" % id
	if ResourceLoader.exists(p): return p
	p = "res://assets/mapshots/%s.png" % id # a map he has no card for (the Fareej): its rendered shot
	return p if ResourceLoader.exists(p) else ""

static func _rect(tex: Texture2D) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

## The camp, filling its parent, with the fire and the moon alive.
static func camp() -> TextureRect:
	if not has_camp(): return null
	var r := _rect(load(CAMP))
	var m := ShaderMaterial.new()
	m.shader = shader()
	m.set_shader_parameter("noise_tex", noise())
	m.set_shader_parameter("img_size", CAMP_SIZE)
	m.set_shader_parameter("fire_on", 1.0)
	m.set_shader_parameter("moon_on", 1.0)
	m.set_shader_parameter("lamp", Vector2(293.0, 437.0))
	m.set_shader_parameter("lamp_r", 12.0)
	r.material = m
	return r

## One map's card (his picture with its painted name), moving where he asked.
static func card(id: String) -> TextureRect:
	var path := card_path(id)
	if path == "": return null
	var tex: Texture2D = load(path)
	var r := _rect(tex)
	var spec: Dictionary = CARDS.get(id, {})
	if spec.is_empty(): return r
	var m := ShaderMaterial.new()
	m.shader = shader()
	m.set_shader_parameter("noise_tex", noise())
	m.set_shader_parameter("img_size", Vector2(tex.get_width(), tex.get_height()))
	if spec.has("moon"):
		var mo: Array = spec.moon
		m.set_shader_parameter("moon_on", 1.0)
		m.set_shader_parameter("moon_c", Vector2(mo[0], mo[1]))
		m.set_shader_parameter("moon_r", mo[2])
	var sw: Array = spec.get("sway", [])
	for i in mini(sw.size(), 4):
		var s: Array = sw[i]
		m.set_shader_parameter("sway%d" % i, Vector4(s[0], s[1], s[2], s[3]))
	m.set_shader_parameter("sway_amp", 1.6)
	if spec.has("lamp"):
		var lp: Array = spec.lamp
		m.set_shader_parameter("lamp", Vector2(lp[0], lp[1]))
		m.set_shader_parameter("lamp_r", lp[2])
	r.material = m
	return r

## Where a point of the camp painting is on a screen of `size` (the picture covers the screen,
## centred: the sides or the top and bottom are cut, never squashed).
static func camp_to_screen(px: Vector2, size: Vector2) -> Vector2:
	var s: float = maxf(size.x / CAMP_SIZE.x, size.y / CAMP_SIZE.y)
	return (px - CAMP_SIZE / 2.0) * s + size / 2.0
