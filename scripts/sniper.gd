class_name NFSniper
extends RefCounted
## «وضع القنّاص»: the killer's rifle and its scope.
##  * `rifle()`: a bolt-action rifle built in code (stock, receiver, bolt handle, a long fluted barrel
##    with a muzzle brake, the scope on its rings, a bipod), 1.25 m long, muzzle toward +Z, the grip
##    at the origin. The same node lies on the crate on the roof, sits in her hands in first person,
##    and lies in front of her on every other phone.
##  * `draw_scope(ci, size, zoom)`: the view through the scope — black all round a round eyepiece,
##    a fine reticle with mil dots, the edge darkening, the magnification in the corner.

const ZOOMS := [1, 4, 8]   # no scope, then x4 and x8 in the same scope

static func _m(c: Color, rough := 0.5, metal := 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

static func _part(root: Node3D, mesh: Mesh, at: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mi

static func _box(size: Vector3, m: Material) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	b.material = m
	return b

static func _cyl(r: float, h: float, m: Material, r2 := -1.0) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r if r2 < 0.0 else r2
	c.height = h
	c.radial_segments = 14
	c.material = m
	return c

static func rifle() -> Node3D:
	var root := Node3D.new()
	root.name = "SniperRifle"
	var steel := _m(Color(0.07, 0.075, 0.08), 0.35, 0.85)
	var parkerized := _m(Color(0.14, 0.15, 0.14), 0.6, 0.6)
	var wood := _m(Color(0.26, 0.15, 0.08), 0.55, 0.0)
	var glass := _m(Color(0.1, 0.2, 0.3), 0.05, 0.2)
	glass.emission_enabled = true
	glass.emission = Color(0.15, 0.3, 0.45)
	glass.emission_energy_multiplier = 0.6
	var X := Vector3(PI / 2.0, 0, 0) # cylinders stand on y: lay them along z
	# the stock: butt, comb, the grip
	_part(root, _box(Vector3(0.05, 0.13, 0.32), wood), Vector3(0, -0.02, -0.3))
	_part(root, _box(Vector3(0.045, 0.05, 0.2), wood), Vector3(0, 0.055, -0.26))
	_part(root, _box(Vector3(0.055, 0.15, 0.03), _m(Color(0.05, 0.05, 0.05), 0.8, 0.0)), Vector3(0, -0.02, -0.465)) # the butt pad
	_part(root, _box(Vector3(0.045, 0.11, 0.05), wood), Vector3(0, -0.07, -0.06), Vector3(-0.35, 0, 0))
	# the fore-end under the barrel
	_part(root, _box(Vector3(0.055, 0.06, 0.42), wood), Vector3(0, -0.015, 0.22))
	# the receiver, the bolt and its handle, the magazine, the trigger guard
	_part(root, _cyl(0.024, 0.22, steel), Vector3(0, 0.03, 0.02), X)
	_part(root, _cyl(0.008, 0.07, steel), Vector3(0.045, 0.03, -0.04), Vector3(0, 0, PI / 2.0))
	_part(root, _cyl(0.014, 0.014, steel), Vector3(0.08, 0.03, -0.04), Vector3(0, 0, PI / 2.0))
	_part(root, _box(Vector3(0.035, 0.07, 0.08), steel), Vector3(0, -0.04, 0.05))
	_part(root, _box(Vector3(0.008, 0.03, 0.06), steel), Vector3(0, -0.06, -0.02))
	# the barrel: long, a little taper, a muzzle brake
	_part(root, _cyl(0.011, 0.68, steel, 0.015), Vector3(0, 0.03, 0.47), X)
	_part(root, _box(Vector3(0.032, 0.03, 0.06), steel), Vector3(0, 0.03, 0.83))
	# the scope on two rings: tube, the objective bell in front, the eyepiece behind, turrets
	var tube := _cyl(0.016, 0.3, parkerized)
	_part(root, tube, Vector3(0, 0.095, 0.03), X)
	_part(root, _cyl(0.027, 0.09, parkerized, 0.017), Vector3(0, 0.095, 0.22), X)
	_part(root, _cyl(0.021, 0.07, parkerized, 0.017), Vector3(0, 0.095, -0.15), X)
	_part(root, _cyl(0.024, 0.004, glass), Vector3(0, 0.095, 0.267), X)
	_part(root, _cyl(0.009, 0.03, parkerized), Vector3(0, 0.125, 0.03))
	_part(root, _cyl(0.009, 0.03, parkerized), Vector3(0.028, 0.095, 0.03), Vector3(0, 0, PI / 2.0))
	for rz in [-0.06, 0.12]:
		_part(root, _box(Vector3(0.04, 0.05, 0.018), steel), Vector3(0, 0.065, rz))
	# the bipod, folded down under the fore-end
	for sx in [-1.0, 1.0]:
		_part(root, _cyl(0.006, 0.24, steel), Vector3(sx * 0.03, -0.12, 0.36), Vector3(0.25, 0, sx * 0.25))
	return root

## The view through the scope: everything outside the round eyepiece is black.
static func draw_scope(ci: CanvasItem, size: Vector2, zoom: int, kick := 0.0) -> void:
	var c := size / 2.0 + Vector2(0.0, -kick * 40.0)
	var r := size.y * 0.46
	var black := Color(0, 0, 0, 1)
	# the two halves round the eyepiece (each a simple polygon: the screen's half with the circle cut out)
	for side in [-1.0, 1.0]:
		var pts := PackedVector2Array()
		pts.append(Vector2(c.x, -10.0))
		pts.append(Vector2(c.x + side * (size.x + 10.0), -10.0))
		pts.append(Vector2(c.x + side * (size.x + 10.0), size.y + 10.0))
		pts.append(Vector2(c.x, size.y + 10.0))
		var n := 40
		for i in n + 1: # up the arc on this side, from straight down round to straight up
			var t := PI * float(i) / float(n)
			pts.append(c + Vector2(side * sin(t), cos(t)) * r)
		ci.draw_colored_polygon(pts, black)
	# the edge of the glass darkening, and its rim
	for k in 6:
		ci.draw_arc(c, r - float(k) * 7.0, 0.0, TAU, 96, Color(0, 0, 0, 0.42 - float(k) * 0.065), 8.0, true)
	ci.draw_arc(c, r, 0.0, TAU, 96, Color(0.02, 0.02, 0.02, 1.0), 4.0, true)
	# the reticle: thick posts from the edge, a fine cross in the middle, mil dots, a red point
	var ink := Color(0.02, 0.02, 0.02, 0.95)
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		ci.draw_line(c + d * r, c + d * r * 0.32, ink, 5.0, true)
		ci.draw_line(c + d * r * 0.32, c + d * 6.0, ink, 1.5, true)
		for k in range(1, 6):
			var p: Vector2 = c + d * r * 0.055 * float(k)
			ci.draw_circle(p, 2.2, ink)
	ci.draw_circle(c, 2.4, Color(1.0, 0.12, 0.08, 0.95))
	# the magnification
	var f := ThemeDB.fallback_font
	ci.draw_string(f, Vector2(c.x + r * 0.62, c.y + r * 0.78), "×%d" % zoom, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.9, 0.85, 0.7, 0.9))
