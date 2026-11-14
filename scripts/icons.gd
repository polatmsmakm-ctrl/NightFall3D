class_name NFIcons
extends RefCounted
## Vector icons drawn straight onto a CanvasItem — no image assets, no atlas, no texture memory.
## NFIcons.draw(canvas_item, "hand", center, 40.0, Color.WHITE) draws a hand about 40 px wide.
## Shapes are authored in a unit box (-1..1, y down) and scaled by `size`.

const CREST_OUT := 0.801 # crescent-moon arc limits (see _moon)
const CREST_IN := 1.066

static func _u(c: Vector2, s: float, x: float, y: float) -> Vector2:
	return c + Vector2(x, y) * s * 0.5

static func _pts(c: Vector2, s: float, a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in a: out.append(c + Vector2(p[0], p[1]) * s * 0.5)
	return out

static func _stroke(ci: CanvasItem, c: Vector2, s: float, a: Array, col: Color, w: float, closed := false) -> void:
	var p := _pts(c, s, a)
	if closed and p.size() > 2: p.append(p[0])
	ci.draw_polyline(p, col, w, true)

static func _fill(ci: CanvasItem, c: Vector2, s: float, a: Array, col: Color) -> void:
	ci.draw_colored_polygon(_pts(c, s, a), col)

static func _bar(ci: CanvasItem, c: Vector2, s: float, x0: float, y0: float, x1: float, y1: float, col: Color, w: float) -> void:
	ci.draw_line(_u(c, s, x0, y0), _u(c, s, x1, y1), col, w, true)

## The lit limb of a crescent moon, as one polygon.
static func _moon(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var r := s * 0.5
	var pts := PackedVector2Array()
	for i in 26:
		var a: float = lerpf(CREST_OUT, TAU - CREST_OUT, i / 25.0)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	var ic := c + Vector2(0.3 * r, 0.0)
	for i in 26:
		var a: float = lerpf(TAU - CREST_IN, CREST_IN, i / 25.0)
		pts.append(ic + Vector2(cos(a), sin(a)) * r * 0.82)
	ci.draw_colored_polygon(pts, col)

static func draw(ci: CanvasItem, name: String, c: Vector2, size: float, col: Color) -> void:
	var w: float = maxf(1.6, size * 0.085)
	match name:
		"hand": # interact
			_fill(ci, c, size, [[-0.5, 0.12], [0.5, 0.12], [0.5, 0.62], [0.26, 0.95], [-0.26, 0.95], [-0.5, 0.62]], col)
			for f in [[-0.36, -0.52], [-0.12, -0.78], [0.13, -0.72], [0.37, -0.42]]:
				_bar(ci, c, size, f[0], 0.16, f[0], f[1], col, w)
			_bar(ci, c, size, -0.5, 0.3, -0.92, -0.12, col, w)
		"shoe": # sprint
			_fill(ci, c, size, [[-0.88, 0.42], [-0.74, -0.22], [-0.44, -0.38], [-0.18, -0.12], [0.34, -0.06], [0.82, 0.14], [0.9, 0.42]], col)
			_bar(ci, c, size, -0.9, 0.52, 0.9, 0.52, col, w * 0.9)
			_bar(ci, c, size, -0.95, -0.3, -0.55, -0.3, Color(col, col.a * 0.5), w * 0.8)
			_bar(ci, c, size, -0.95, -0.05, -0.68, -0.05, Color(col, col.a * 0.5), w * 0.8)
		"crouch":
			ci.draw_circle(_u(c, size, -0.18, -0.58), size * 0.19, col)
			_stroke(ci, c, size, [[-0.18, -0.34], [0.3, -0.02], [-0.12, 0.34], [0.38, 0.72]], col, w)
			_bar(ci, c, size, -0.85, 0.9, 0.85, 0.9, Color(col, col.a * 0.55), w * 0.9)
		"jump": # vault
			ci.draw_arc(_u(c, size, 0.0, 0.42), size * 0.46, PI, TAU, 22, col, w, true)
			_fill(ci, c, size, [[-0.2, 0.52], [0.2, 0.52], [0.2, 0.92], [-0.2, 0.92]], col)
		"heal":
			_fill(ci, c, size, [[-0.22, -0.8], [0.22, -0.8], [0.22, -0.22], [0.8, -0.22], [0.8, 0.22], [0.22, 0.22], [0.22, 0.8], [-0.22, 0.8], [-0.22, 0.22], [-0.8, 0.22], [-0.8, -0.22], [-0.22, -0.22]], col)
		"item": # med kit
			_stroke(ci, c, size, [[-0.78, -0.3], [0.78, -0.3], [0.78, 0.74], [-0.78, 0.74]], col, w, true)
			_stroke(ci, c, size, [[-0.3, -0.3], [-0.3, -0.66], [0.3, -0.66], [0.3, -0.3]], col, w)
			_bar(ci, c, size, 0.0, 0.0, 0.0, 0.46, col, w)
			_bar(ci, c, size, -0.24, 0.23, 0.24, 0.23, col, w)
		"light": # flashlight
			_fill(ci, c, size, [[-0.25, -0.5], [0.3, -0.5], [0.3, 0.5], [-0.25, 0.5]], col)
			_fill(ci, c, size, [[-0.25, -0.34], [-0.9, -0.74], [-0.9, 0.74], [-0.25, 0.34]], Color(col, col.a * 0.45))
			_bar(ci, c, size, 0.5, 0.0, 0.92, 0.0, col, w)
		"attack": # claw swipe
			for k in 3:
				var off := -0.42 + k * 0.42
				ci.draw_arc(_u(c, size, 0.55, off), size * 0.52, PI * 0.78, PI * 1.32, 14, col, w * 1.1, true)
		"power": # lunge
			for k in 2:
				var x := -0.45 + k * 0.6
				_stroke(ci, c, size, [[x, -0.6], [x + 0.5, 0.0], [x, 0.6]], col, w * 1.15)
		"carry":
			ci.draw_circle(_u(c, size, -0.3, -0.5), size * 0.17, col)
			_stroke(ci, c, size, [[-0.3, -0.28], [-0.18, 0.2], [-0.5, 0.86]], col, w)
			_stroke(ci, c, size, [[-0.18, 0.2], [0.2, 0.84]], col, w)
			_bar(ci, c, size, -0.78, -0.42, 0.82, -0.68, col, w * 1.2)
		"hook":
			_bar(ci, c, size, 0.08, -0.9, 0.08, 0.12, col, w)
			ci.draw_arc(_u(c, size, -0.2, 0.2), size * 0.28, -0.35 * PI, 0.95 * PI, 20, col, w, true)
			_bar(ci, c, size, -0.6, -0.9, 0.5, -0.9, col, w)
		"wrench": # repair
			_stroke(ci, c, size, [[-0.7, 0.72], [0.22, -0.2]], col, w * 1.5)
			ci.draw_arc(_u(c, size, 0.44, -0.42), size * 0.3, 0.7 * PI, 2.1 * PI, 22, col, w * 1.4, true)
		"search":
			ci.draw_arc(_u(c, size, -0.14, -0.2), size * 0.38, 0, TAU, 26, col, w, true)
			_bar(ci, c, size, 0.22, 0.26, 0.74, 0.78, col, w * 1.3)
		"axe": # break
			_bar(ci, c, size, -0.5, 0.84, 0.34, -0.5, col, w * 1.2)
			_fill(ci, c, size, [[0.16, -0.78], [0.86, -0.5], [0.66, -0.02], [0.1, -0.34]], col)
		"door": # hide in a locker
			_stroke(ci, c, size, [[-0.62, -0.84], [0.62, -0.84], [0.62, 0.84], [-0.62, 0.84]], col, w, true)
			ci.draw_circle(_u(c, size, 0.3, 0.0), size * 0.07, col)
			_stroke(ci, c, size, [[-0.1, -0.3], [-0.46, 0.0], [-0.1, 0.3]], col, w * 0.9)
		"out": # step out / escaped
			_stroke(ci, c, size, [[0.1, -0.84], [-0.68, -0.84], [-0.68, 0.84], [0.1, 0.84]], col, w)
			_bar(ci, c, size, -0.1, 0.0, 0.8, 0.0, col, w)
			_stroke(ci, c, size, [[0.4, -0.34], [0.84, 0.0], [0.4, 0.34]], col, w)
		"plank": # pallet
			for k in 2:
				var y := -0.3 + k * 0.6
				_fill(ci, c, size, [[-0.86, y - 0.16], [0.86, y - 0.16], [0.86, y + 0.16], [-0.86, y + 0.16]], col)
			_fill(ci, c, size, [[-0.2, -0.86], [0.1, -0.86], [0.1, 0.86], [-0.2, 0.86]], Color(col, col.a * 0.55))
		"fist": # free yourself
			_fill(ci, c, size, [[-0.56, -0.34], [0.5, -0.46], [0.66, 0.2], [0.4, 0.72], [-0.46, 0.66]], col)
			for k in 3:
				_bar(ci, c, size, -0.3 + k * 0.3, -0.42, -0.3 + k * 0.3, -0.16, Color(0, 0, 0, 0.45), w * 0.8)
			_bar(ci, c, size, -0.56, -0.1, -0.92, 0.22, col, w)
		"rescue": # unhook someone
			_fill(ci, c, size, [[-0.46, 0.2], [0.46, 0.2], [0.46, 0.66], [0.2, 0.95], [-0.2, 0.95], [-0.46, 0.66]], col)
			for f in [-0.3, -0.05, 0.2, 0.42]:
				_bar(ci, c, size, f, 0.22, f, -0.12, col, w * 0.9)
			_stroke(ci, c, size, [[-0.34, -0.5], [0.04, -0.9], [0.42, -0.5]], col, w * 1.1)
			_bar(ci, c, size, 0.04, -0.86, 0.04, -0.3, col, w * 1.1)
		"chat": # quick signal
			_stroke(ci, c, size, [[-0.84, -0.68], [0.84, -0.68], [0.84, 0.3], [-0.2, 0.3], [-0.5, 0.82], [-0.5, 0.3], [-0.84, 0.3]], col, w, true)
			for k in 3:
				ci.draw_circle(_u(c, size, -0.42 + k * 0.42, -0.2), size * 0.065, col)
		"next": # spectate
			ci.draw_arc(_u(c, size, 0.0, 0.0), size * 0.42, 0, TAU, 26, col, w, true)
			ci.draw_circle(c, size * 0.14, col)
			_fill(ci, c, size, [[-0.95, 0.0], [-0.42, -0.3], [-0.42, 0.3]], col)
			_fill(ci, c, size, [[0.95, 0.0], [0.42, -0.3], [0.42, 0.3]], col)
		"moon": _moon(ci, c, size, col)
		"skull":
			ci.draw_circle(_u(c, size, 0.0, -0.22), size * 0.42, col)
			_fill(ci, c, size, [[-0.42, 0.06], [0.42, 0.06], [0.3, 0.76], [-0.3, 0.76]], col)
			ci.draw_circle(_u(c, size, -0.2, -0.28), size * 0.13, Color(0, 0, 0, 0.75))
			ci.draw_circle(_u(c, size, 0.2, -0.28), size * 0.13, Color(0, 0, 0, 0.75))
			_bar(ci, c, size, -0.16, 0.5, -0.16, 0.76, Color(0, 0, 0, 0.6), w * 0.8)
			_bar(ci, c, size, 0.16, 0.5, 0.16, 0.76, Color(0, 0, 0, 0.6), w * 0.8)
		"drop": # injured / bleeding
			var p := PackedVector2Array([_u(c, size, 0.0, -0.9)])
			for i in 22:
				var a: float = lerpf(-PI * 0.42, PI * 1.42, i / 21.0)
				p.append(_u(c, size, 0.0, 0.22) + Vector2(cos(a), sin(a)) * size * 0.34)
			ci.draw_colored_polygon(p, col)
		"down": # on the ground
			_stroke(ci, c, size, [[-0.5, -0.5], [0.0, 0.1], [0.5, -0.5]], col, w * 1.2)
			_bar(ci, c, size, 0.0, 0.1, 0.0, -0.8, col, w * 1.2)
			_bar(ci, c, size, -0.7, 0.7, 0.7, 0.7, col, w * 1.2)
		"heart":
			var p2 := PackedVector2Array()
			for i in 34:
				var t: float = i / 33.0 * TAU
				var x: float = 0.52 * pow(sin(t), 3.0)
				var y: float = -(0.42 * cos(t) - 0.16 * cos(2 * t) - 0.064 * cos(3 * t) - 0.032 * cos(4 * t)) * 1.05
				p2.append(_u(c, size, x * 1.7, y * 1.7))
			ci.draw_colored_polygon(p2, col)
		"gear":
			ci.draw_arc(c, size * 0.3, 0, TAU, 24, col, w, true)
			for k in 6:
				var a: float = k * TAU / 6.0
				var d := Vector2(cos(a), sin(a))
				ci.draw_line(c + d * size * 0.34, c + d * size * 0.5, col, w * 1.3, true)
		"star":
			var sp := PackedVector2Array()
			for i in 10:
				var a: float = -PI / 2.0 + i * PI / 5.0
				var r: float = size * (0.5 if i % 2 == 0 else 0.22)
				sp.append(c + Vector2(cos(a), sin(a)) * r)
			ci.draw_colored_polygon(sp, col)
		"pin": # "come here"
			var pp := PackedVector2Array([_u(c, size, 0.0, 0.92)])
			for i in 22:
				var a: float = lerpf(PI * 0.58, PI * 2.42, i / 21.0)
				pp.append(_u(c, size, 0.0, -0.22) + Vector2(cos(a), sin(a)) * size * 0.4)
			ci.draw_colored_polygon(pp, col)
			ci.draw_circle(_u(c, size, 0.0, -0.22), size * 0.13, Color(0, 0, 0, 0.6))
		"exit":
			_stroke(ci, c, size, [[0.2, -0.8], [-0.7, -0.8], [-0.7, 0.8], [0.2, 0.8]], col, w)
			_bar(ci, c, size, 0.0, 0.0, 0.85, 0.0, col, w)
			_stroke(ci, c, size, [[0.45, -0.32], [0.88, 0.0], [0.45, 0.32]], col, w)
		_:
			ci.draw_arc(c, size * 0.42, 0, TAU, 20, col, w, true)

## Head-and-shoulders avatar used by the team bar and the player card.
static func portrait(ci: CanvasItem, c: Vector2, size: float, col: Color) -> void:
	_fill(ci, c, size, [[-0.82, 1.0], [-0.66, 0.34], [-0.28, 0.1], [0.28, 0.1], [0.66, 0.34], [0.82, 1.0]], col)
	ci.draw_circle(_u(c, size, 0.0, -0.32), size * 0.27, col.lightened(0.12))
