class_name NFControls
extends RefCounted
## Where the touch buttons sit, and how big they are — saved per role in user://controls.cfg.
## Positions are kept as a fraction of the safe screen area so they survive a different aspect ratio;
## radii are in UI pixels of the 1280x720 design viewport.

const PATH := "user://controls.cfg"
const REF := Vector2(1280.0, 720.0)

## Defaults are the layout the game shipped with: [offset from the right edge, offset from the bottom, radius].
const DEF := {
	"killer": {
		"attack": [115.0, 115.0, 62.0],
		"power": [262.0, 92.0, 50.0],
		"interact": [215.0, 222.0, 48.0],
	},
	"survivor": {
		"sprint": [110.0, 110.0, 58.0],
		"interact": [252.0, 88.0, 50.0],
		"crouch": [88.0, 252.0, 44.0],
		"vault": [215.0, 215.0, 44.0],
		"heal": [375.0, 68.0, 40.0],
		"item": [345.0, 170.0, 40.0],
		"light": [88.0, 352.0, 40.0],
		"sig": [430.0, 92.0, 38.0],
	},
}

## Default face of every button (context buttons are overridden in main.gd).
const LABEL := {
	"attack": "ضرب", "power": "اندفاع", "interact": "تفاعل", "sprint": "ركض", "crouch": "انحناء",
	"vault": "قفز", "heal": "علاج", "item": "حقيبة", "light": "كشاف", "sig": "إشارة", "next": "التالي",
}
const ICON := {
	"attack": "attack", "power": "power", "interact": "hand", "sprint": "shoe", "crouch": "crouch",
	"vault": "jump", "heal": "heal", "item": "item", "light": "light", "sig": "chat", "next": "next",
}
## Icon for whatever the interact button is about to do right now.
const CTX_ICON := {
	"rep": "wrench", "rescue": "rescue", "locker_in": "door", "locker_out": "out", "pallet": "plank",
	"struggle": "fist", "hook": "hook", "pickup": "carry", "search": "search", "break": "axe",
	"vault": "jump", "heal": "heal",
}

const MIN_R := 26.0
const MAX_R := 86.0

static var _cache := {}

static func label_of(id: String) -> String:
	return LABEL.get(id, id)

static func icon_of(id: String) -> String:
	return ICON.get(id, "hand")

static func defaults(role: String) -> Dictionary:
	var out := {}
	for id in DEF.get(role, {}):
		var d: Array = DEF[role][id]
		out[id] = {"fx": (REF.x - d[0]) / REF.x, "fy": (REF.y - d[1]) / REF.y, "r": float(d[2])}
	return out

## Saved layout for a role, falling back to the shipped one for buttons the file does not mention.
static func layout(role: String) -> Dictionary:
	if _cache.has(role): return _cache[role]
	var out := defaults(role)
	var c := ConfigFile.new()
	if c.load(PATH) == OK:
		for id in out.keys():
			if not c.has_section_key(role, id): continue
			var v = c.get_value(role, id)
			if v is Array and v.size() >= 3:
				out[id] = {"fx": clampf(float(v[0]), 0.02, 0.98), "fy": clampf(float(v[1]), 0.02, 0.98),
					"r": clampf(float(v[2]), MIN_R, MAX_R)}
	_cache[role] = out
	return out

static func save(role: String, lay: Dictionary) -> void:
	_cache[role] = lay
	var c := ConfigFile.new()
	c.load(PATH)
	for id in lay:
		c.set_value(role, id, [snappedf(lay[id].fx, 0.0001), snappedf(lay[id].fy, 0.0001), snappedf(lay[id].r, 0.1)])
	c.save(PATH)

static func reset(role: String) -> Dictionary:
	var c := ConfigFile.new()
	c.load(PATH)
	if c.has_section(role): c.erase_section(role)
	c.save(PATH)
	_cache.erase(role)
	return layout(role)

static func forget() -> void:
	_cache.clear()

## The area buttons may live in: the viewport minus the notch insets.
static func area(vp: Viewport) -> Rect2:
	var s: Vector2 = vp.get_visible_rect().size
	var safe := NFUI.safe_insets(vp)
	return Rect2(safe.x, 0.0, maxf(s.x - safe.x - safe.y, 100.0), s.y)

static func center_of(e: Dictionary, rect: Rect2) -> Vector2:
	return rect.position + Vector2(float(e.fx) * rect.size.x, float(e.fy) * rect.size.y)

static func fraction_of(p: Vector2, rect: Rect2) -> Vector2:
	return Vector2(clampf((p.x - rect.position.x) / rect.size.x, 0.02, 0.98),
		clampf((p.y - rect.position.y) / rect.size.y, 0.02, 0.98))
