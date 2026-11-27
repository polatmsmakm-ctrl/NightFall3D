class_name GameMenu
extends CanvasLayer
## Menus: username, main, friends, lobby (map / role), character select with a live preview in front
## of the campfire, control layout, offline test. The 3D side of it lives in scripts/lobby.gd.

signal start_game(cfg: Dictionary)

const MAPS := {"forest": "The Forest", "village": "The Abandoned Village", "fareej": "The Fareej", "rubkhali": "The Empty Quarter",
	"garage": "The Car Park", "beach": "The Beach", "city": "City Life", "kuwait": "Kuwait City"}
const THEMES := {"normal": "Night", "fog": "Fog", "rain": "Rain", "snow": "Snow", "halloween": "Halloween", "sunset": "Late Afternoon"}
const THEME_ICON := {"normal": "moon", "fog": "fog", "rain": "rain", "snow": "star", "halloween": "skull", "sunset": "sun"}
const VERSION := "v1.4"
const CHARS := {"killer": "The Killer", "survivor1": "The Survivor", "survivor2": "The Nomad", "survivor3": "The Sheriff", "survivor4": "Crimson Valkyrie", "survivor5": "Battle-Scarred", "survivor6": "Night Sentinel", "survivor7": "The Researcher", "survivor8": "Night Rose", "survivor9": "Bloom", "survivor10": "Crimson Adventurer", "killer2": "The Beast"}
const SECRET := "survivor4" # hidden: only on phones Net.has_secret() is true for
const ERRORS := {"no_room": "No room with that code", "room_full": "The room is full", "in_game": "The game in this room has started",
	"killer_taken": "There's already a killer in the room", "offline": "Your friend is offline", "invite_later": "Your friend is offline — the invite reaches them when they come on (up to 20 minutes)", "bad_name": "Names must be 2 to 16 characters with no spaces",
	"name_taken": "That name is in use right now, pick another"}

var page := ""
var box: VBoxContainer
var toast := ""
var invite := {}
var typed := {} # LineEdit texts kept across rebuilds
var off_map := "forest"
var off_char := "killer"
var off_theme := "normal"
var prof_name := ""  # whose profile the «profile» page shows ("" = mine)
var off_gun := false # «وضع السلاح» in trial mode
var off_sniper := false # «وضع القنّاص» in trial mode (Kuwait City only: it takes the map with it)
var off_bot := true # trial mode as a survivor: a computer killer hunts you (NFBot)
var lobby: NFLobby       # the campfire scene, set by main.gd
var card: Control        # player card in the top corner
var char_pad: Control    # swipe area for the character carousel
var chars_from := "main" # which page the character select was opened from
var want_char := ""     # character I asked the server for, until the room list agrees
var _swipe_x := 0.0
var _swiping := false
var _editor: NFControlsEdit
var version: Label      # the small build number in the corner
var camp_pad: Control   # taps on the people at the fire (an online friend: invite him)
var poster: TextureRect # the opening shot, fading into the camp
var _logo_tex: Texture2D
var _invite_after := ""  # a friend tapped while I had no room: invite him once the room exists
var _tap_at := -9.0
const Paint := preload("res://scripts/paint.gd")
# the start screen's own pieces (the owner's mockup): built once, laid out by _layout_start
var ui: Control
var side: VBoxContainer
var modes_btn: Button
var map_panel: Control
var map_pic_holder: Control
var map_prev: Button
var map_next: Button
var play_btn: Button
var foot: HBoxContainer
var map_pic: Control
var _pic_map := ""
var _apply_modes := false
var _danced := false
const Social := preload("res://scripts/social.gd")
var social: Control # the Social Sidebar (friends, requests, invites), over everything on the start screen # the Dances page was open: my character goes back to standing when it closes # a room made with PLAY: send the modes picked before it existed

func _ready() -> void:
	layer = 10
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.28) # the campfire scene shows through
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var sc := ScrollContainer.new()
	sc.set_anchors_preset(Control.PRESET_FULL_RECT)
	sc.offset_top = 20; sc.offset_bottom = -20
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(sc)
	sc.offset_left = 36 + NFUI.safe_insets(get_viewport()).x
	var center := MarginContainer.new() # menu column sits on the left; the fire is on the right
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.add_child(center)
	box = VBoxContainer.new()
	box.custom_minimum_size.x = 540
	box.add_theme_constant_override("separation", 10)
	box.theme = NFUI.theme()
	center.add_child(box)
	char_pad = Control.new() # swipe left / right over the camp to change character
	char_pad.mouse_filter = Control.MOUSE_FILTER_STOP
	char_pad.visible = false
	char_pad.gui_input.connect(_on_swipe)
	add_child(char_pad)
	card = Control.new() # username / level / experience / escapes / kills
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.size = Vector2(340, 116)
	card.draw.connect(_draw_card)
	add_child(card)
	_build_start()
	social = Social.new()
	add_child(social)
	social.profile.connect(func(n: String) -> void:
		social.close()
		prof_name = n
		open("profile"))
	social.invite.connect(func(n: String) -> void:
		_invite(n)
		social.note = "Invite sent to %s" % Net.display_of(n)
		social.note_t = 3.0)
	social.more_page.connect(func() -> void:
		social.close()
		open("friends"))
	version = Label.new()
	version.text = VERSION
	version.add_theme_font_size_override("font_size", 15)
	version.add_theme_color_override("font_color", Color(0.55, 0.55, 0.58))
	version.mouse_filter = Control.MOUSE_FILTER_STOP
	version.gui_input.connect(_on_version_input)
	add_child(version)
	camp_pad = Control.new()
	camp_pad.mouse_filter = Control.MOUSE_FILTER_STOP
	camp_pad.visible = false
	camp_pad.gui_input.connect(_on_camp_tap)
	add_child(camp_pad)
	move_child(camp_pad, char_pad.get_index())
	if ResourceLoader.exists("res://assets/ui/logo.png"): _logo_tex = load("res://assets/ui/logo.png")
	if ResourceLoader.exists("res://assets/ui/poster.jpg"):
		poster = TextureRect.new()
		poster.texture = load("res://assets/ui/poster.jpg")
		poster.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		poster.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		poster.set_anchors_preset(Control.PRESET_FULL_RECT)
		poster.mouse_filter = Control.MOUSE_FILTER_IGNORE
		poster.visible = false
		add_child(poster)
	if CHARS.has(Net.last_char) and (Net.last_char != SECRET or Net.has_secret()): off_char = Net.last_char
	Net.changed.connect(_refresh)
	Net.message.connect(_on_msg)
	if Net.username == "": open("name")
	elif Net.in_room(): open("lobby")
	else: open("main")

func open(p: String) -> void:
	page = p
	_refresh()

func _on_msg(m: Dictionary) -> void:
	if not visible: return
	match str(m.t):
		"room":
			want_char = "" # the room list is the truth about my character again
			if str(m.get("code", "")) != "":
				if _invite_after != "": # the room I made for the friend I tapped at the fire
					Net.send({"t": "invite", "to": _invite_after})
					toast = "Invite sent to " + _invite_after
					_invite_after = ""
				if _apply_modes: # PLAY made this room: the weather and modes picked on the start screen come along
					_apply_modes = false
					Net.send({"t": "set", "theme": off_theme, "gun": off_gun, "sniper": off_sniper and off_map == "kuwait"})
				if not (page in ["friends", "chars", "controls", "dances", "modes"]): page = "lobby"
			elif page in ["lobby", "friends", "chars"]: page = "main"
		"started":
			start_game.emit({"map": m.map, "players": m.players, "me": Net.username, "offline": false,
				"seed": int(m.get("seed", 1)), "theme": str(m.get("theme", "normal")), "gun": bool(m.get("gun", false)), "sniper": bool(m.get("sniper", false))})
			return
		"welcome": # an older server does not know the newer maps and silently ignores them
			var known: Array = m.get("maps", [])
			for id in MAPS:
				if not known.has(id):
					toast = "The server is old and doesn't know every map — update the server"
					break
		"invite": invite = m
		"gift":
			toast = ("%s unlocked a secret character for you: Crimson Valkyrie" if bool(m.get("on", true)) else "%s locked the secret character") % str(m.get("from", ""))
		"emote": # someone at the fire waved / danced / clapped
			if lobby and is_instance_valid(lobby): lobby.emote(str(m.get("n", "")), int(m.get("k", 0)), str(m.get("d", "")))
			return
		"error":
			toast = ERRORS.get(str(m.code), str(m.code))
			if str(m.code) == "killer_taken": want_char = "" # someone else is the killer: back to what the room says
	_refresh()

# ---------- helpers ----------
func _label(text: String, size := 24, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(l)
	return l

func _button(text: String, cb: Callable, parent: Control = null, enabled := true, icon := "") -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 54
	b.disabled = not enabled
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	NFUI.dress(b, icon)
	(parent if parent else box).add_child(b)
	return b

## One map on the picker: a rendered preview of the map with its name under it. The images are
## real screenshots in assets/mapshots/<id>.png; a map without one still gets a working button.
func _map_card(id: String, chosen: bool, cb: Callable, parent: Control) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(150, 118)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	NFUI.dress(b, "")
	parent.add_child(b)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var path := "res://assets/mapshots/%s.png" % id
	var shot := TextureRect.new()
	shot.custom_minimum_size.y = 74
	shot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	shot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(path): shot.texture = load(path)
	shot.modulate = Color(1, 1, 1) if chosen else Color(0.72, 0.72, 0.75)
	v.add_child(shot)
	var nm := Label.new()
	nm.text = MAPS.get(id, id)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.add_theme_font_size_override("font_size", 19)
	nm.add_theme_color_override("font_color", Color(1, 0.8, 0.35) if chosen else Color(0.85, 0.85, 0.88))
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(nm)
	if chosen: b.modulate = Color(1, 0.88, 0.7)
	return b

func _edit(key: String, hint: String, parent: Control = null) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = hint
	e.text = typed.get(key, "")
	e.custom_minimum_size.y = 54
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.alignment = HORIZONTAL_ALIGNMENT_CENTER
	e.theme = NFUI.theme()
	e.text_changed.connect(func(t): typed[key] = t)
	(parent if parent else box).add_child(e)
	return e

func _row() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	box.add_child(h)
	return h

func _status() -> String:
	match Net.state:
		"online": return "Connected ✓  (%s)" % Net.username
		"connecting": return "Connecting to the server... (the first time can take a minute)"
		"name_taken": return "That name is in use right now, change it in the settings"
	return "Offline"

## The camp follows the weather the host picked, so the start screen shows the round's mood.
func _weather_changed() -> void:
	if lobby and is_instance_valid(lobby): lobby._time_of_day()

func _refresh() -> void:
	if not visible or box == null: return
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	if _logo_tex and page in ["main", "name"]: # the owner's wordmark
		var lg := TextureRect.new()
		lg.texture = _logo_tex
		lg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT if page == "main" else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		lg.custom_minimum_size = Vector2(540, 118 if page == "main" else 196)
		lg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(lg)
	else: _label("NightFall", 44, Color(0.85, 0.1, 0.12))
	if not invite.is_empty():
		_label("%s invites you to their room" % str(invite.from), 24, Color(1, 0.85, 0.4))
		var h := _row()
		_button("Accept", func():
			Net.send({"t": "join", "code": invite.code}); invite = {}; _refresh(), h, true, "out")
		_button("Decline", func(): invite = {}; _refresh(), h, true, "exit")
	if toast != "":
		_label(toast, 22, Color(1, 0.5, 0.4))
		toast = ""
	match page:
		"name": _page_name()
		"main": _page_main()
		"friends": _page_friends()
		"lobby": _page_lobby()
		"offline": _page_offline()
		"settings": _page_settings()
		"chars": _page_chars()
		"dev": _page_dev()
		"help": _page_help()
		"board": _page_board()
		"profile": _page_profile()
		"dances": _page_dances()
		"modes": _page_modes()
		"challenge": _page_challenge()
	_sync_lobby()

# ---------- the campfire scene follows the menu ----------
## True while we are choosing for the trial mode (where you may also pick the killer).
func _offline_flow() -> bool:
	if page == "chars": return chars_from != "lobby"
	return not Net.in_room()

func _my_char() -> String:
	if _offline_flow(): return off_char
	var me := _me()
	var cur := str(me.get("char", "")) if not me.is_empty() else ""
	if want_char != "" and want_char != cur: return want_char # waiting for the server to agree
	return cur if cur != "" else off_char

func _my_role() -> String:
	var me := _me()
	return str(me.get("role", "")) if not me.is_empty() else ""

func _char_list() -> Array:
	# every character, online too: picking one of the killers on the stand makes you the killer, picking
	# a survivor makes you a survivor (the owner could not find «الوحش» while he was a survivor in a room)
	var out := []
	for id in CHARS:
		if id == SECRET and not Net.has_secret(): continue
		out.append(id)
	return out

func _on_version_input(e: InputEvent) -> void:
	if not ((e is InputEventScreenTouch or e is InputEventMouseButton) and e.pressed): return
	if Dev.tap(): open("dev")

func _sync_lobby(dir := 0.0) -> void:
	var vs := get_viewport().get_visible_rect().size
	var safe := NFUI.safe_insets(get_viewport())
	version.size = Vector2(130, 42)
	version.position = Vector2(vs.x - 130.0 - 12.0 - safe.y, vs.y - 44.0)
	card.visible = page != "name"
	card.position = Vector2(vs.x - card.size.x - 16.0 - safe.y, 70.0) # clear of the settings gear above it
	card.queue_redraw()
	_layout_start()
	char_pad.visible = page == "chars"
	var px: float = maxf(596.0, vs.x * 0.44) # clear of the menu column on the left
	char_pad.position = Vector2(px, 0.0)
	char_pad.size = Vector2(maxf(vs.x - px, 10.0), vs.y)
	camp_pad.visible = page in ["main", "friends"] and not Net.in_room()
	camp_pad.position = char_pad.position
	camp_pad.size = Vector2(char_pad.size.x, maxf(vs.y - 60.0, 10.0)) # the version text stays reachable
	if lobby == null or not is_instance_valid(lobby): return
	if page == "name":
		lobby.hide_preview()
		lobby.set_cast([], Net.username)
		lobby.focus(false)
		return
	lobby.preview(_my_char(), str(CHARS.get(_my_char(), "")), dir)
	lobby.focus(page == "chars")
	lobby.set_cast(Net.room.get("players", []) if Net.in_room() else _friends_at_fire(), Net.username)
	var camp_map := "forest" # the camp wears the map the room, or the trial menu, has picked
	if Net.in_room(): camp_map = str(Net.room.get("map", "forest"))
	elif page == "offline" or (page == "chars" and chars_from == "offline"): camp_map = off_map
	lobby.set_map(camp_map)
	_weather_changed()

## Friends who are online right now sit at the fire, each as a survivor picked by his name
## (the server does not say which one he plays until he is in a room).
func _friends_at_fire() -> Array:
	var out := []
	var pool := ["survivor1", "survivor2", "survivor3", "survivor5", "survivor6", "survivor7", "survivor8", "survivor9", "survivor10"]
	for f in Net.friends:
		var n := str(f)
		if n == Net.username or not Net.is_online(n): continue
		out.append({"name": n, "role": "friend", "char": pool[absi(n.hash()) % pool.size()]})
	return out

## A tap on someone at the fire: an online friend gets a room and an invitation.
func _on_camp_tap(e: InputEvent) -> void:
	if not ((e is InputEventScreenTouch or e is InputEventMouseButton) and e.pressed): return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _tap_at < 0.6: return # a touch arrives twice, once as a mouse press
	_tap_at = now
	if lobby == null or not is_instance_valid(lobby) or Net.in_room() or _invite_after != "": return
	var n: String = lobby.pick(camp_pad.position + e.position)
	if n == "" or not Net.is_online(n): return
	_invite_after = n
	NFUI.click()
	Net.send({"t": "create", "map": "forest"})
	toast = "Making a room and inviting %s..." % n
	_refresh()

## The opening shot: the poster over everything, thinning out as the camera comes down.
func _process(_dt: float) -> void:
	if lobby == null or not is_instance_valid(lobby):
		if poster: poster.visible = false
		return
	var k: float = lobby.intro
	if poster:
		poster.visible = k < 0.55
		poster.modulate.a = clampf(1.0 - k / 0.5, 0.0, 1.0)
	var seen := clampf((k - 0.72) / 0.28, 0.0, 1.0)
	box.modulate.a = seen
	card.modulate.a = seen
	if ui: ui.modulate.a = seen

## The perk I play with: my character's own ("") or «المسعف» ("aid", the first-aid kit). Saved on the
## phone, and online the room hears it (`set {perk}`), so the rules give it to me when the round starts.
func _pick_perk(p: String) -> void:
	NFUI.click()
	Net.perk = p
	Net.save()
	if not _offline_flow(): Net.send({"t": "set", "perk": p})
	_refresh()

## One step along the carousel: the new character slides in, then the labels follow.
func _step(d: int) -> void:
	var list := _char_list()
	if list.is_empty(): return
	var i := list.find(_my_char())
	if i < 0: i = 0
	var id := str(list[(i + d + list.size()) % list.size()])
	NFUI.click()
	if _offline_flow(): off_char = id
	else:
		want_char = id # the room answers with a new player list; show it now so it feels instant
		var msg := {"t": "set", "char": id}
		var want_role := "killer" if id.begins_with("killer") else "survivor"
		if _my_role() != want_role: msg["role"] = want_role # the role comes with the character
		Net.send(msg)
	_sync_lobby(float(d))
	_refresh()

func _on_swipe(e: InputEvent) -> void:
	if (e is InputEventScreenTouch or e is InputEventMouseButton):
		if e.pressed:
			_swipe_x = e.position.x
			_swiping = true
		else: _swiping = false
	elif (e is InputEventScreenDrag or e is InputEventMouseMotion) and _swiping:
		var dx: float = e.position.x - _swipe_x
		if absf(dx) > 70.0:
			_swipe_x = e.position.x
			_step(1 if dx < 0.0 else -1) # drag left: next character

# ---------- player card ----------
func _draw_card() -> void:
	var s: Vector2 = card.size
	var f: Font = Net.font if Net.font else ThemeDB.fallback_font
	card.draw_rect(Rect2(Vector2.ZERO, s), Color(0.035, 0.03, 0.035, 0.82))
	card.draw_rect(Rect2(Vector2.ZERO, s), Color(0.55, 0.08, 0.09, 0.9), false, 2.0)
	NFUI.scratches(card, s, 7331, false)
	NFIcons.portrait(card, Vector2(s.x - 32.0, 36.0), 42.0, NFUI.char_col(_my_char()))
	card.draw_arc(Vector2(s.x - 32.0, 36.0), 24.0, 0, TAU, 28, Color(0.8, 0.2, 0.2, 0.9), 2.0)
	var nm := Net.username if Net.username != "" else "Player"
	card.draw_string(f, Vector2(12.0, 30.0), nm, HORIZONTAL_ALIGNMENT_RIGHT, s.x - 70.0, 24, Color(0.95, 0.93, 0.9))
	card.draw_string(f, Vector2(12.0, 54.0), "Level %d  •  %s" % [Net.level(), Net.title()], HORIZONTAL_ALIGNMENT_RIGHT, s.x - 70.0, 18, Color(1, 0.85, 0.45))
	var br := Rect2(Vector2(12.0, 64.0), Vector2(s.x - 70.0, 12.0))
	NFUI.bar(card, br, Net.level_progress(), Color(0.8, 0.12, 0.12), Color(1, 1, 1, 0.3))
	card.draw_string(f, Vector2(12.0, 90.0), "XP %d/%d" % [Net.xp, Net.level_xp(Net.level() + 1)],
		HORIZONTAL_ALIGNMENT_RIGHT, s.x - 70.0, 15, Color(0.7, 0.7, 0.72))
	NFIcons.draw(card, "out", Vector2(26.0, 104.0), 18.0, Color(0.5, 0.85, 1.0))
	card.draw_string(f, Vector2(38.0, 110.0), "%d" % Net.escapes, HORIZONTAL_ALIGNMENT_LEFT, 60.0, 17, Color(0.6, 0.9, 1.0))
	NFIcons.draw(card, "skull", Vector2(104.0, 104.0), 18.0, Color(1.0, 0.4, 0.35))
	card.draw_string(f, Vector2(116.0, 110.0), "%d" % Net.kills, HORIZONTAL_ALIGNMENT_LEFT, 60.0, 17, Color(1.0, 0.55, 0.5))
	var lr: Dictionary = Net.last_round # the last round, on the same line
	var res := str(lr.get("res", ""))
	if res != "":
		var line := "Last round: %s +%d" % [{"escaped": "escaped", "killer": "killer"}.get(res, "You didn't make it"), int(lr.get("score", 0))]
		var lc := Color(0.6, 0.9, 1.0) if res == "escaped" else (Color(1.0, 0.55, 0.5) if res == "killer" else Color(0.9, 0.5, 0.45))
		card.draw_string(f, Vector2(160.0, 110.0), line, HORIZONTAL_ALIGNMENT_RIGHT, s.x - 172.0, 15, lc)

# ---------- pages ----------
func _page_name() -> void:
	_label("Choose your username — friends add you with it")
	_edit("name", "English or Arabic, no spaces")
	_button("Continue", func():
		var n: String = typed.get("name", "").strip_edges()
		if n.length() < 2 or n.length() > 16 or n.contains(" "):
			toast = ERRORS.bad_name
			_refresh()
			return
		Net.configure(n, "")
		open("main"), null, true, "out")
	_button("Trial mode (offline)", func(): chars_from = "offline"; open("offline"), null, true, "star")

func _page_main() -> void:
	var crash: String = (load("res://scripts/crumbs.gd") as GDScript).launch()
	if crash != "" and Dev.unlocked: # the owner's phone: where the last session stopped
		var tail := Array(crash.split("\n")).slice(-8)
		_label("Last time the game closed while:\n" + "\n".join(tail), 15, Color(1, 0.45, 0.4))
	var cr := load("res://scripts/crumbs.gd") as GDScript
	var errs: PackedStringArray = cr.last_errs
	if Dev.unlocked and not errs.is_empty(): # the engine's own errors last session, crash or not
		_label("Engine errors last time:\n" + "\n".join(Array(errs).slice(-6)), 14, Color(1, 0.7, 0.35))
	_label(_status(), 16, Color(0.6, 0.9, 0.6) if Net.state == "online" else Color(0.75, 0.75, 0.78))
	var on := Net.state == "online"
	_mrow("Create Room", "claw", func() -> void: # red like his mockup even before the server answers
		if Net.state == "online": _create_room()
		else:
			toast = "Connecting to the server… try again in a moment"
			_refresh(), true, false, null, 48.0)
	_code_row(on)
	var waiting := Net.req_in.size()
	_mrow("Friends (%d)" % Net.friends.size() + ("   •  %d request%s" % [waiting, "" if waiting == 1 else "s"] if waiting > 0 else ""), "people",
		func(): social.open(), false, waiting > 0, null, 48.0)
	_mrow("Trial Mode", "skull", func(): chars_from = "offline"; open("offline"), false, true, null, 48.0)
	_mrow("Sound and Settings", "gear", func(): Gfx.open_settings(), false, false, null, 48.0)
	_mrow("How to Play", "book", func(): open("help"), false, false, null, 48.0)
	if Dev.unlocked: _mrow("Developer Tools", "wrench", func(): open("dev"), false, false, null, 48.0)
	_mrow("Name and Server", "globe", func():
		typed["name"] = Net.username; typed["url"] = Net.url; open("settings"), false, false, null, 48.0)

var help_tab := "survivor"
var board_by := "esc" # the friends' board: sorted by escapes, kills or level
const HELP := {
	"survivor": [
		["wrench", "Repair generators", "5 generators power the gates. Watch the skill check: a mistake blows the generator and the killer hears it."],
		["out", "Escape through a gate", "When the gates have power a green arrow points to the nearest one. Get out before the moon falls (two minutes)."],
		["car", "The escape car", "Behind each gate there's one car for everyone: the first one in drives and the rest ride along. The last gate is 600 m away and you have two minutes. If the killer rams you with her car or time runs out, you're down on the road and she hooks you."],
		["rescue", "Save your team", "Lift someone off the hook together: everyone who helps makes the rescue faster. Your team's names are over their heads and you can see them through walls."],
		["gun", "Gun mode", "If the host turns it on: you carry a stun pistol with 3 shots. Aim the camera at her within 22 m — a shot stuns her for 3 seconds and she drops whoever she's carrying."],
		["heart", "Watch your heartbeat", "A heartbeat and red edges mean the killer is close. The red arc shows where a hit came from."],
		["search", "Hide", "Lockers hide you, but the killer can search them and pull you out."],
		["plank", "Pallets and windows", "Drop a pallet on the killer when she's behind you to stun her, and vault through windows to get away."],
		["chat", "Signals", "The signal button only reaches your team: Come here, Killer here, I'm repairing."],
		["hand", "The hatch", "If you're the last one left, find the hatch and escape through it."],
		["star", "Your character's perk", "Every survivor has a perk: you see it under their name when you pick the character, and under the map while you play."],
		["nitro", "Nitro", "The escape car's driver has one nitro: the car flies for three and a half seconds. Use it when the killer is behind you."],
		["trap", "Traps", "The killer lays traps on the ground: stepping in one holds you for 4 seconds. If you see one (it glints a little), disarm it with the use button."],
	],
	"killer": [
		["attack", "Strike", "The first hit wounds, the second puts them down. After each hit you have to wait a moment."],
		["carry", "Carry and hook", "Pick up someone who's down and take them to the nearest hook. A pallet to the face makes you drop them."],
		["power", "Rush", "The power button speeds you up for a moment, then it needs time to come back."],
		["car", "The car", "Get in any parked car. Run survivors down, put the downed one in the seat next to you and take them to a hook. Three gears (up to 90 km/h) and a radio."],
		["out", "The long road", "If they get in the escape car, chase them in yours (second and third gear are faster than them) and ram them before the last gate. They fall on the road, and there are hooks all along it."],
		["search", "Search lockers", "Survivors hide in them: open them and pull them out."],
		["plank", "Break pallets", "A dropped pallet blocks the way: break it."],
		["door", "Doors", "Shut doors behind you. Anyone far away hears them."],
		["trap", "Traps", "The trap button lays a trap at your feet (4 at most, a fifth replaces the oldest). Whoever steps in it is held for 4 seconds and you get an arrow to them."],
		["spike", "Spikes", "On the escape road the same button lays spikes across half the road: if their car drives over them its tyres burst and it slows down."],
	],
}

func _page_help() -> void:
	_label("How to play", 30, Color(0.95, 0.25, 0.22))
	var tabs := _row()
	for t in [["survivor", "Survivors", "rescue"], ["killer", "The Killer", "attack"]]:
		var b := _button(str(t[1]), func(): help_tab = str(t[0]); _refresh(), tabs, true, str(t[2]))
		if help_tab == str(t[0]): b.modulate = Color(1, 0.75, 0.55)
	for it in HELP[help_tab]:
		_tip(str(it[0]), str(it[1]), str(it[2]))
	_label("Horses: \"Horses\" by vinish.dev — CC BY 4.0", 14, Color(0.6, 0.6, 0.62)) # their licence asks for the credit
	_button("Back", func(): open("main"), null, true, "exit")

func _tip(icon: String, title: String, text: String) -> void:
	var h := _row()
	h.add_theme_constant_override("separation", 14)
	var pic := Control.new()
	pic.custom_minimum_size = Vector2(56, 56)
	pic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	pic.draw.connect(func() -> void:
		pic.draw_circle(Vector2(28, 28), 27.0, Color(0.06, 0.05, 0.06, 0.85), true, -1.0, true)
		pic.draw_arc(Vector2(28, 28), 27.0, 0, TAU, 48, Color(0.72, 0.16, 0.16, 0.9), 2.0, true)
		NFIcons.draw(pic, icon, Vector2(28, 28), 34.0, Color(1, 0.93, 0.88)))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	var t := Label.new(); t.text = title
	t.add_theme_font_size_override("font_size", 22)
	t.add_theme_color_override("font_color", Color(1, 0.85, 0.5))
	var d := Label.new(); d.text = text
	d.add_theme_font_size_override("font_size", 17)
	d.add_theme_color_override("font_color", Color(0.9, 0.88, 0.86))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size.x = 380
	v.add_child(t); v.add_child(d)
	h.add_child(v) # Arabic reads right to left: the icon sits at the right end of the row
	h.add_child(pic)

func _page_settings() -> void:
	_label("Name")
	_edit("name", "Name")
	_label("Server address")
	_edit("url", "wss://...")
	_button("Save", func():
		Net.configure(typed.get("name", Net.username), typed.get("url", Net.url)); open("main"), null, true, "star")
	_button("Sound and graphics", func(): Gfx.open_settings(), null, true, "gear")
	_button("Button layout (position and size)", _open_editor, null, true, "gear")
	_button("Back", func(): open("main"), null, true, "exit")

func _open_editor() -> void:
	if _editor and is_instance_valid(_editor): return
	_editor = NFControlsEdit.new()
	_editor.role = "killer" if _my_char().begins_with("killer") else "survivor"
	_editor.closed.connect(func(): _editor = null)
	add_child(_editor)

func _page_friends() -> void:
	_label("Friends")
	var h := _row()
	_edit("friend", "Friend's username", h)
	_button("Add", func():
		Net.add_friend(typed.get("friend", "")); typed["friend"] = ""; _refresh(), h, true, "chat")
	if Net.friends.is_empty(): _label("You haven't added anyone yet", 20, Color(0.7, 0.7, 0.7))
	var top := _row()
	_button("My profile", func(): prof_name = ""; open("profile"), top, true, "star")
	_button("Rankings and my rounds", func(): open("board"), top, true, "star")
	# online first, then by name
	var sorted: Array = Net.friends.duplicate()
	sorted.sort_custom(func(a, b) -> bool:
		var oa := Net.is_online(str(a)); var ob := Net.is_online(str(b))
		if oa != ob: return oa
		return str(a).to_lower() < str(b).to_lower())
	for f in sorted:
		var name := str(f)
		var r := _row()
		var on := Net.is_online(name)
		var stt := Net.status_of(name)
		var sc: Color = {"menu": Color(0.5, 1, 0.5), "room": Color(1, 0.85, 0.4), "game": Color(1, 0.5, 0.4)}.get(stt, Color(0.6, 0.6, 0.6))
		var nb := _button(("● " if on else "○ ") + name + "  —  " + Net.status_text(name), func(): prof_name = name; open("profile"), r, true, "star")
		nb.add_theme_color_override("font_color", sc)
		nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if stt != "game": # in the menus, in a room or offline (the invite waits for him): ask him over
			var b := _button("Invite", func(): _invite(name), r, true, "chat")
			b.size_flags_horizontal = Control.SIZE_SHRINK_END
		if Dev.unlocked: # the owner's phone: open or shut the hidden character for this friend
			var has := Net.gifted.has(name.to_lower())
			var g := _button("Lock secret" if has else "Unlock secret", func():
				Net.gift(name, not has)
				toast = ("Locked for " + name) if has else ("%s's code: %s — they type it on their friends page" % [name, Net.secret_code(name)])
				_refresh(), r, true, "star")
			g.size_flags_horizontal = Control.SIZE_SHRINK_END
			if has: g.modulate = Color(1, 0.75, 0.3)
		var d := _button("Remove", func(): Net.remove_friend(name), r, true, "exit")
		d.size_flags_horizontal = Control.SIZE_SHRINK_END
	if not Net.has_secret(): # a friend with a code from the owner types it here
		var hc := _row()
		_edit("code", "Secret character code", hc)
		_button("Activate", func():
			toast = "Secret character unlocked: Crimson Valkyrie" if Net.redeem(typed.get("code", "")) else "Wrong code"
			typed["code"] = ""; _refresh(), hc, true, "star")
	_button("Back", func(): open("lobby" if Net.in_room() else "main"), null, true, "exit")

## Ask a friend over: to my room, or to a new one if I have none. An offline friend gets it when he
## comes online (the server keeps it for 20 minutes while the room is open).
func _invite(name: String) -> void:
	if Net.in_room():
		Net.send({"t": "invite", "to": name})
		toast = ("Invite sent to " + name) if Net.is_online(name) else ""
	else:
		_invite_after = name
		Net.send({"t": "create", "map": "forest"})
		toast = "Making a room and inviting %s..." % name
	_refresh()

## A player's profile: portrait in their character's colour, name, where they are now, level and
## title, their numbers and their line. Mine (prof_name == "") lets me write that line.
func _page_profile() -> void:
	var mine := prof_name == "" or prof_name.to_lower() == Net.username.to_lower()
	var who := Net.username if mine else prof_name
	var row: Dictionary = Net.my_stats() if mine else Net.fstats.get(prof_name.to_lower(), {})
	var ch := str(row.get("ch", ""))
	var col := NFUI.char_col(ch if ch != "" else "survivor1")
	var card := Control.new()
	card.custom_minimum_size = Vector2(0, 150)
	card.draw.connect(func() -> void:
		var cx := card.size.x / 2.0
		card.draw_circle(Vector2(cx, 70), 64, Color(0, 0, 0, 0.55))
		var pch := (Net.last_char if Net.last_char != "" else "survivor1") if mine else Net.char_of(who)
		var pp := "res://assets/ui/portraits/%s.png" % pch
		if ResourceLoader.exists(pp): card.draw_texture_rect(load(pp), Rect2(Vector2(cx - 60, 10), Vector2(120, 120)), false) # their character's face
		else: NFIcons.portrait(card, Vector2(cx, 70), 56.0, col)
		var stt := "menu" if mine else Net.status_of(who)
		var ring: Color = {"menu": Color(0.5, 1, 0.5), "room": Color(1, 0.85, 0.4), "game": Color(1, 0.5, 0.4)}.get(stt, Color(0.5, 0.5, 0.5))
		card.draw_arc(Vector2(cx, 70), 64, 0, TAU, 48, ring, 4.0, true))
	box.add_child(card)
	_label((Net.display if Net.display != "" else who) if mine else Net.display_of(who), 34, Color(1, 0.9, 0.7))
	_label("@" + who, 18, Color(0.65, 0.65, 0.7))
	_label("You" if mine else Net.status_text(who), 20, Color(0.7, 0.9, 0.7) if mine or Net.is_online(who) else Color(0.65, 0.65, 0.68))
	if row.is_empty() or (not mine and not row.has("lv")):
		_label("No numbers for them yet — they show after they play a round online", 18, Color(0.7, 0.7, 0.72))
	else:
		var lv := int(row.get("lv", 0))
		_label("Level %d%s" % [lv, ("  •  " + Net.title()) if mine else ""], 22, Color(1, 0.82, 0.45))
		if ch != "": _label("Character: %s" % CHARS.get(ch, ch), 20, col.lightened(0.3))
		_label("Escapes %d  •  Kills %d  •  Rounds %d" % [int(row.get("esc", 0)), int(row.get("kills", 0)), int(row.get("rounds", 0))], 22, Color(0.88, 0.9, 0.95))
		var b := str(row.get("bio", ""))
		if b != "" and not mine: _label("«%s»" % b, 20, Color(0.85, 0.85, 0.95))
	if mine:
		var hd := _row() # my display name: what friends see above my @username
		var ed := _edit("disp", "Display name (2-20 letters)", hd)
		if not typed.has("disp"): ed.text = Net.display if Net.display != "" else Net.username
		ed.max_length = 20
		_button("Save name", func():
			var d := str(typed.get("disp", Net.display)).strip_edges()
			if d.length() >= 2: Net.set_display(d)
			typed.erase("disp")
			toast = "Saved"
			_refresh(), hd, true, "star")
		var h := _row()
		var e := _edit("bio", "A line about you (your friends see it)", h)
		if not typed.has("bio"): e.text = Net.bio
		e.max_length = 60
		_button("Save", func():
			Net.set_bio(str(typed.get("bio", Net.bio)))
			typed.erase("bio")
			toast = "Saved"
			_refresh(), h, true, "star")
	else:
		var h2 := _row()
		var known := false
		for f in Net.friends: known = known or str(f).to_lower() == who.to_lower()
		if known:
			if Net.status_of(who) != "game": _button("Invite", func(): _invite(who), h2, true, "chat")
			_button("Remove friend", func(): Net.remove_friend(who); open("main"); social.open(), h2, true, "exit")
		else: _button("Send friend request", func(): Net.add_friend(who); _refresh(), h2, true, "chat")
	_button("Back", func():
		open("main" if not Net.in_room() else "lobby")
		if prof_name != "": social.open(), null, true, "exit")

## The friends' board (me and every friend the server has numbers for, best first) and my own
## last rounds. Numbers come from each phone; a friend who has not been online since the server
## started shows dashes until he is.
func _page_board() -> void:
	_label("Rankings among friends", 30, Color(1, 0.82, 0.45))
	var tabs := _row()
	for t in [["esc", "Escapes", "out"], ["kills", "Kills", "skull"], ["lv", "Level", "star"]]:
		var b := _button(str(t[1]), func(): board_by = str(t[0]); _refresh(), tabs, true, str(t[2]))
		if board_by == str(t[0]): b.modulate = Color(1, 0.75, 0.3)
	var rows := Net.board(board_by)
	var place := 0
	for row in rows:
		place += 1
		var me: bool = str(row.get("name", "")).to_lower() == Net.username.to_lower()
		var none: bool = row.get("none", false)
		var medal: String = ("★%d" % place) if place <= 3 and not none else "%d." % place
		var line := "%s  %s   —   Escapes %s  •  Kills %s  •  Level %s  •  Rounds %s" % [medal, str(row.get("name", "")),
			"-" if none else str(row.get("esc", 0)), "-" if none else str(row.get("kills", 0)),
			"-" if none else str(row.get("lv", 0)), "-" if none else str(row.get("rounds", 0))]
		_label(line, 20, Color(1, 0.85, 0.5) if me else (Color(0.55, 0.55, 0.58) if none else Color(0.88, 0.9, 0.95)))
	_label("My last rounds", 24, Color(0.95, 0.3, 0.25))
	if Net.history.is_empty(): _label("You haven't played a round yet", 18, Color(0.7, 0.7, 0.7))
	for hrow in Net.history.slice(0, 8):
		var res := str(hrow.get("res", ""))
		var what: String = str({"escaped": "escaped", "dead": "You died", "killer": "Killer — %d kills" % int(hrow.get("kills", 0))}.get(res, res))
		_label("%s   %s   %s   +%d" % [str(hrow.get("d", "")), str(MAPS.get(str(hrow.get("map", "")), hrow.get("map", ""))), what, int(hrow.get("score", 0))],
			18, Color(0.5, 1, 0.6) if res == "escaped" else (Color(1, 0.55, 0.5) if res == "dead" else Color(1, 0.8, 0.5)))
	_button("Back", func(): open("main" if not Net.in_room() else "lobby"), null, true, "exit")

## The three campfire emotes: played here at once, and relayed to the room if I am in one.
func _emote_row() -> void:
	var h := _row()
	for i in NFLobby.EMOTES.size():
		_button(NFLobby.EMOTE_TEXT[i], func():
			if lobby and is_instance_valid(lobby): lobby.emote(Net.username, i)
			if Net.in_room(): Net.send({"t": "emote", "k": i}), h, true, NFLobby.EMOTE_ICON[i])

func _me() -> Dictionary:
	for p in Net.room.get("players", []):
		if str(p.name) == Net.username: return p
	return {}

func _page_lobby() -> void:
	var r := Net.room
	if r.is_empty():
		open("main")
		return
	var host := str(r.host) == Net.username
	var code := str(r.code)
	_label("Room code", 20, Color(0.75, 0.75, 0.78))
	_label(code, 46, Color(1, 0.85, 0.4))
	_button("Copy the code and send it to your friends", func():
		DisplayServer.clipboard_set(code)
		toast = "Code %s copied" % code
		_refresh(), null, true, "chat")
	_label("Map: %s  •  %s%s" % [MAPS.get(str(r.map), str(r.map)), THEMES.get(str(r.get("theme", "normal")), "Night"),
		("  •  Gun mode" if r.get("gun", false) else "") + ("  •  Sniper mode" if r.get("sniper", false) else "")], 20)
	for p in r.players:
		var txt := "%s%s — %s" % ["★ " if str(p.name) == str(r.host) else "", str(p.name), CHARS.get(str(p.char), str(p.char))]
		_label(txt, 20, Color(1, 0.4, 0.4) if str(p.role) == "killer" else Color(0.7, 0.85, 1))
	var me := _me()
	var h2 := _row()
	var bk := _button("Play killer", func(): Net.send({"t": "set", "role": "killer"}), h2, true, "skull")
	var bs := _button("Play survivor", func(): Net.send({"t": "set", "role": "survivor"}), h2, true, "shoe")
	if str(me.get("role", "")) == "killer": bk.modulate = Color(1, 0.75, 0.3)
	else: bs.modulate = Color(1, 0.75, 0.3)
	if str(me.get("role", "")) == "survivor":
		_button("Choose character — %s" % CHARS.get(str(me.get("char", "")), ""), func():
			chars_from = "lobby"; open("chars"), null, true, "star")
	_emote_row()
	_button("Invite friends", func(): social.open(), null, true, "chat")
	if not host: _label("Waiting for the host to start...", 20, Color(0.7, 0.7, 0.7))
	_button("Leave the room", func(): Net.send({"t": "leave"}), null, true, "exit")

## Character select: the chosen one is standing in front of the fire; swipe the camp to change.
func _page_chars() -> void:
	var list := _char_list()
	var id := _my_char()
	var i := list.find(id)
	_label("Choose your character", 26, Color(1, 0.85, 0.45))
	_label(str(CHARS.get(id, id)), 40, NFUI.char_col(id))
	var pk: String = Rules.PERK.get(id, "")
	var survivor := not id.begins_with("killer")
	if survivor and Net.perk == "aid": pk = "aid" # «المسعف», picked instead of the character's own
	if pk != "": # what this character can do that the others cannot
		var info: Array = Rules.PERK_INFO[pk]
		_label("Perk: %s — %s" % [info[0], info[1]], 19, Color(1.0, 0.82, 0.45))
	if survivor: # pick a perk: the character's own, or «المسعف» with the first-aid kit in hand
		var own: String = Rules.PERK.get(id, "")
		var own_name: String = Rules.PERK_INFO[own][0] if Rules.PERK_INFO.has(own) else "None"
		var ph := _row()
		var b1 := _button("Character perk: %s" % own_name, func(): _pick_perk(""), ph, true, "star")
		var b2 := _button("Medic (first-aid kit)", func(): _pick_perk("aid"), ph, true, "heal")
		(b2 if Net.perk == "aid" else b1).modulate = Color(0.55, 1.0, 0.6)
	_label("%d/%d  •  swipe left or right" % [maxi(i, 0) + 1, list.size()], 18, Color(0.7, 0.7, 0.72))
	var h := _row()
	_button("‹ Previous", func(): _step(-1), h, true, "next")
	_button("Next ›", func(): _step(1), h, true, "next")
	_button("Done", func(): open(chars_from if chars_from != "main" else "main"), null, true, "star")

## Hidden developer tools. Only reachable on a phone that has unlocked them.
## Load each model the in-game updates brought, and say which load: on the owner's phone the
## gorilla's would not (the "second generator" crash). Failures also go in the crash trail with the
## engine's own reason ("ERR ...").
func _model_test() -> String:
	var out := []
	for p in ["res://assets/chars/gorilla.glb", "res://assets/chars/survivor10.glb", "res://assets/chars/survivor9.glb",
			"res://assets/animals/arabian-horse.glb", "res://assets/chars/gorilla_col.png"]:
		if not ResourceLoader.exists(p):
			out.append("—  %s (not in this build)" % p.get_file())
			continue
		var r = load(p)
		out.append(("OK  %s" if r != null else "FAILED  %s") % p.get_file())
		if r == null: (load("res://scripts/crumbs.gd") as GDScript).mark("model test failed: " + p)
	return "\n".join(out)

func _page_dev() -> void:
	if not Dev.unlocked: # fifteen taps got here: the passkey opens the tools
		_label("Developer tools", 30, Color(1, 0.85, 0.4))
		var hk := _row()
		var e := _edit("devkey", "Passkey", hk)
		e.secret = true
		e.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
		_button("Open", func():
			var ok := Dev.try_key(typed.get("devkey", ""))
			typed["devkey"] = ""
			if not ok: toast = "Wrong passkey"
			_refresh(), hk, true, "star")
		_button("Back", func(): typed["devkey"] = ""; open("main"), null, true, "exit")
		return
	_label("Developer tools", 30, Color(1, 0.85, 0.4))
	_label("Only shown on your phone", 18, Color(0.7, 0.7, 0.72))
	var van := _button("Vanish button in rounds: %s" % ("On" if Dev.vanish_tool else "Off"), func():
		Dev.set_vanish_tool(not Dev.vanish_tool); _refresh(), null, true, "ghost")
	if Dev.vanish_tool: van.modulate = Color(1, 0.75, 0.3)
	var esp := _button("See players: %s" % ("On" if Dev.esp else "Off"), func():
		Dev.set_esp(not Dev.esp); _refresh(), null, true, "next")
	if Dev.esp: esp.modulate = Color(1, 0.75, 0.3)
	_label("Move speed x%.2f" % Dev.speed, 20, Color(0.85, 0.9, 1))
	var sl := HSlider.new()
	sl.min_value = 1.0; sl.max_value = 2.0; sl.step = 0.05
	sl.custom_minimum_size = Vector2(0, 44)
	sl.theme = NFUI.theme()
	sl.set_value_no_signal(Dev.speed)
	sl.value_changed.connect(func(v: float): Dev.set_speed(v); _refresh())
	box.add_child(sl)
	_button("Test the update's models", func(): typed["models"] = _model_test(); _refresh(), null, true, "star")
	if typed.has("models"): _label(str(typed["models"]), 15, Color(0.8, 1, 0.8))
	_button("Lock the tools (needs the passkey again)", func(): Dev.lock(); open("main"), null, true, "skull")
	_button("Back", func(): open("main"), null, true, "exit")

func _page_offline() -> void:
	chars_from = "offline"
	_label("Trial Mode", 34, Color(0.95, 0.25, 0.22))
	_label("Pick the map on the right, the weather and rules in Game Modes, then PLAY", 18, Color(0.78, 0.78, 0.8))
	_button("Character — %s" % CHARS.get(off_char, off_char), func(): open("chars"), null, true, "star")
	if not off_char.begins_with("killer"):
		var bb := _button("Computer killer: %s" % ("On" if off_bot else "Off"), func(): off_bot = not off_bot; _refresh(), null, true, "skull")
		if off_bot: bb.modulate = Color(1, 0.6, 0.5)
	_button("Back", func(): chars_from = "main"; open("main" if Net.username != "" else "name"), null, true, "exit")

# ---------- the start screen, after the owner's mockup ----------
## His layout: the wordmark top left, a column of dark rows with an icon each (Create Room lit red),
## four square icons along the bottom, the player card top right, and on the right the Dances and
## Game Modes buttons, the MAP SELECT card with arrows and dots, and a big red PLAY. The camp behind
## all of it is his painting (NFLobby), the same whatever map, weather or mode is picked.
func _style(bg: Color, edge: Color, bw := 1, glow := Color(0, 0, 0, 0.5), glow_size := 4, left := 74) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = edge
	s.set_border_width_all(bw)
	s.set_corner_radius_all(3)
	s.shadow_color = glow
	s.shadow_size = glow_size
	s.content_margin_left = left
	s.content_margin_right = 44
	return s

## The drawings his mockup uses that the icon set does not have; everything else is NFIcons.
func _icon(ci: CanvasItem, name: String, c: Vector2, s: float, col: Color) -> void:
	var w := maxf(s * 0.07, 2.0)
	match name:
		"claw": # three slashes
			for k in 4:
				var x := c.x - s * 0.3 + k * s * 0.2
				ci.draw_line(Vector2(x + s * 0.08, c.y - s * 0.42), Vector2(x - s * 0.04, c.y + s * 0.42), col, w * 1.3, true)
		"people":
			for o in [[-0.2, 0.75], [0.18, 1.0]]:
				var cx := c.x + s * float(o[0])
				var k: float = o[1]
				ci.draw_circle(Vector2(cx, c.y - s * 0.16 * k), s * 0.14 * k, col, true, -1.0, true)
				ci.draw_rect(Rect2(cx - s * 0.2 * k, c.y + s * 0.04, s * 0.4 * k, s * 0.32 * k), col)
		"book":
			ci.draw_polyline(PackedVector2Array([c + Vector2(-s * 0.45, -s * 0.28), c + Vector2(0, -s * 0.18), c + Vector2(s * 0.45, -s * 0.28),
				c + Vector2(s * 0.45, s * 0.3), c + Vector2(0, s * 0.4), c + Vector2(-s * 0.45, s * 0.3), c + Vector2(-s * 0.45, -s * 0.28)]), col, w, true)
			ci.draw_line(c + Vector2(0, -s * 0.18), c + Vector2(0, s * 0.4), col, w, true)
		"globe":
			ci.draw_arc(c, s * 0.42, 0, TAU, 32, col, w, true)
			ci.draw_line(c + Vector2(-s * 0.42, 0), c + Vector2(s * 0.42, 0), col, w, true)
			ci.draw_line(c + Vector2(0, -s * 0.42), c + Vector2(0, s * 0.42), col, w, true)
			for k in [-1.0, 1.0]:
				ci.draw_arc(c + Vector2(k * s * 0.42, 0), s * 0.6, PI - 0.78 if k > 0 else -0.78, PI + 0.78 if k > 0 else 0.78, 12, col, w * 0.8, true)
		"quit": # the power symbol
			ci.draw_arc(c, s * 0.36, -PI / 2.0 + 0.62, PI * 1.5 - 0.62, 28, col, w * 1.2, true)
			ci.draw_line(c + Vector2(0, -s * 0.46), c + Vector2(0, -s * 0.06), col, w * 1.2, true)
		"bars":
			for k in 3:
				var h := s * (0.35 + 0.22 * k)
				ci.draw_rect(Rect2(c.x - s * 0.36 + k * s * 0.27, c.y + s * 0.38 - h, s * 0.18, h), col)
		"trophy":
			ci.draw_rect(Rect2(c.x - s * 0.24, c.y - s * 0.38, s * 0.48, s * 0.36), col)
			ci.draw_circle(c + Vector2(0, -s * 0.04), s * 0.24, col, true, -1.0, true)
			ci.draw_arc(c + Vector2(-s * 0.28, -s * 0.2), s * 0.13, 0, TAU, 12, col, w, true)
			ci.draw_arc(c + Vector2(s * 0.28, -s * 0.2), s * 0.13, 0, TAU, 12, col, w, true)
			ci.draw_rect(Rect2(c.x - s * 0.05, c.y + s * 0.18, s * 0.1, s * 0.14), col)
			ci.draw_rect(Rect2(c.x - s * 0.22, c.y + s * 0.3, s * 0.44, s * 0.1), col)
		"badge":
			for k in 8:
				var a := k * TAU / 8.0
				ci.draw_circle(c + Vector2(cos(a), sin(a)) * s * 0.33, s * 0.1, col, true, -1.0, true)
			ci.draw_circle(c, s * 0.3, col, true, -1.0, true)
			ci.draw_circle(c, s * 0.15, Color(0.05, 0.04, 0.05), true, -1.0, true)
		"dance":
			ci.draw_circle(c + Vector2(s * 0.08, -s * 0.36), s * 0.1, col, true, -1.0, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-s * 0.34, -s * 0.32), c + Vector2(-s * 0.05, -s * 0.12), c + Vector2(s * 0.3, -s * 0.28)]), col, w, true)
			ci.draw_line(c + Vector2(s * 0.04, -s * 0.22), c + Vector2(-s * 0.02, s * 0.1), col, w * 1.3, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-s * 0.3, s * 0.42), c + Vector2(-s * 0.02, s * 0.1), c + Vector2(s * 0.14, s * 0.24), c + Vector2(s * 0.34, s * 0.12)]), col, w, true)
		"modes":
			for k in 3:
				var y := c.y - s * 0.3 + k * s * 0.3
				ci.draw_line(Vector2(c.x - s * 0.42, y), Vector2(c.x + s * 0.42, y), col, w, true)
				ci.draw_circle(Vector2(c.x + s * (-0.2 + 0.2 * k), y), s * 0.09, col, true, -1.0, true)
		_: NFIcons.draw(ci, name, c, s, col)

## One row of his menu: icon on the left, the words, a chevron on the lit one, a red dot if asked.
func _mrow(text: String, icon: String, cb: Callable, primary := false, dot := false, parent: Control = null, h := 54.0) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, h)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 24 if h >= 50.0 else 20)
	if Net.font: b.add_theme_font_override("font", Net.font)
	var base := Color(0.025, 0.022, 0.026, 0.8)
	var edge := Color(0.42, 0.42, 0.46, 0.55)
	if primary:
		base = Color(0.38, 0.02, 0.03, 0.93)
		edge = Color(1.0, 0.18, 0.13, 0.95)
	var glow := Color(1.0, 0.05, 0.02, 0.5) if primary else Color(0, 0, 0, 0.55)
	b.add_theme_stylebox_override("normal", _style(base, edge, 2 if primary else 1, glow, 14 if primary else 4))
	b.add_theme_stylebox_override("hover", _style(base.lightened(0.07), edge.lightened(0.25), 2 if primary else 1, glow, 14 if primary else 4))
	b.add_theme_stylebox_override("pressed", _style(base.lightened(0.15), edge.lightened(0.35), 2, glow, 16))
	b.add_theme_stylebox_override("disabled", _style(Color(0.02, 0.02, 0.022, 0.62), Color(0.3, 0.3, 0.32, 0.4)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color(0.95, 0.93, 0.9))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.52))
	b.pressed.connect(func() -> void:
		NFUI.click()
		cb.call())
	var deco := Control.new()
	deco.set_anchors_preset(Control.PRESET_FULL_RECT)
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deco.draw.connect(func() -> void:
		var col := Color(0.95, 0.93, 0.9) if not b.disabled else Color(0.45, 0.45, 0.47)
		_icon(deco, icon, Vector2(38.0, deco.size.y / 2.0), minf(deco.size.y * 0.58, 34.0), col)
		if primary: # the chevron
			var x := deco.size.x - 26.0
			var y := deco.size.y / 2.0
			deco.draw_polyline(PackedVector2Array([Vector2(x - 6, y - 11), Vector2(x + 4, y), Vector2(x - 6, y + 11)]), col, 3.0, true)
		if dot: deco.draw_circle(Vector2(deco.size.x - 30.0, deco.size.y / 2.0), 6.0, Color(0.95, 0.08, 0.08), true, -1.0, true))
	b.add_child(deco)
	(parent if parent else box).add_child(b)
	return b

## His second row: the room code box with Join on its right.
func _code_row(on: bool) -> void:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(0, 48)
	p.add_theme_stylebox_override("panel", _style(Color(0.025, 0.022, 0.026, 0.8), Color(0.42, 0.42, 0.46, 0.55), 1, Color(0, 0, 0, 0.55), 4, 74))
	box.add_child(p)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	p.add_child(h)
	var e := LineEdit.new()
	e.placeholder_text = "Room Code"
	e.text = typed.get("code", "")
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.add_theme_font_size_override("font_size", 24)
	if Net.font: e.add_theme_font_override("font", Net.font)
	for st in ["normal", "focus", "read_only"]: e.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	e.add_theme_color_override("font_placeholder_color", Color(0.62, 0.62, 0.65))
	e.add_theme_color_override("font_color", Color(0.95, 0.93, 0.9))
	e.text_changed.connect(func(t): typed["code"] = t)
	h.add_child(e)
	var j := Button.new()
	j.text = "Join   "
	j.flat = true
	j.disabled = not on
	j.custom_minimum_size = Vector2(118, 0)
	j.add_theme_font_size_override("font_size", 24)
	if Net.font: j.add_theme_font_override("font", Net.font)
	j.add_theme_color_override("font_color", Color(0.95, 0.93, 0.9))
	j.pressed.connect(func() -> void:
		NFUI.click()
		Net.send({"t": "join", "code": typed.get("code", "")}))
	h.add_child(j)
	p.draw.connect(func() -> void:
		_icon(p, "people", Vector2(38.0, p.size.y / 2.0), 32.0, Color(0.95, 0.93, 0.9))
		NFIcons.draw(p, "out", Vector2(p.size.x - 30.0, p.size.y / 2.0), 24.0, Color(0.95, 0.93, 0.9)))

## A square icon button (the row along the bottom of his mockup).
func _square(icon: String, cb: Callable, parent: Control) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(64, 64)
	var st := _style(Color(0.03, 0.027, 0.03, 0.82), Color(0.42, 0.42, 0.46, 0.6), 1, Color(0, 0, 0, 0.55), 4, 0)
	st.content_margin_right = 0
	b.add_theme_stylebox_override("normal", st)
	var hv := st.duplicate() as StyleBoxFlat
	hv.border_color = Color(1.0, 0.2, 0.15)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", hv)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(func() -> void:
		NFUI.click()
		cb.call())
	b.draw.connect(func() -> void: _icon(b, icon, b.size / 2.0, 34.0, Color(0.95, 0.93, 0.9)))
	parent.add_child(b)
	return b

func _build_start() -> void:
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui)
	side = VBoxContainer.new()
	side.add_theme_constant_override("separation", 10)
	ui.add_child(side)
	_mrow("Dances", "dance", func(): open("dances"), false, false, side, 52.0)
	modes_btn = _mrow("Game Modes", "modes", func(): open("modes"), false, false, side, 52.0)
	map_panel = Control.new()
	map_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	map_panel.draw.connect(_draw_map_panel)
	ui.add_child(map_panel)
	map_pic_holder = Control.new()
	map_pic_holder.clip_contents = true
	map_pic_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_panel.add_child(map_pic_holder)
	for k in [-1, 1]:
		var a := Button.new()
		a.flat = true
		a.text = "‹" if k < 0 else "›"
		a.add_theme_font_size_override("font_size", 54)
		a.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
		a.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		a.add_theme_constant_override("outline_size", 8)
		a.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		a.pressed.connect(func() -> void: _map_step(k))
		map_panel.add_child(a)
		if k < 0: map_prev = a
		else: map_next = a
	play_btn = Button.new()
	play_btn.text = "PLAY"
	play_btn.add_theme_font_size_override("font_size", 46)
	if Net.font: play_btn.add_theme_font_override("font", Net.font)
	var pn := _style(Color(0.62, 0.03, 0.04, 0.96), Color(1.0, 0.25, 0.2), 2, Color(1.0, 0.04, 0.02, 0.55), 18, 0)
	pn.content_margin_right = 0
	play_btn.add_theme_stylebox_override("normal", pn)
	var ph := pn.duplicate() as StyleBoxFlat
	ph.bg_color = Color(0.78, 0.06, 0.06)
	play_btn.add_theme_stylebox_override("hover", ph)
	play_btn.add_theme_stylebox_override("pressed", ph)
	play_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	play_btn.add_theme_color_override("font_color", Color(1, 0.97, 0.95))
	play_btn.pressed.connect(_play)
	play_btn.draw.connect(func() -> void:
		var x := play_btn.size.x - 34.0
		var y := play_btn.size.y / 2.0
		play_btn.draw_polyline(PackedVector2Array([Vector2(x - 9, y - 16), Vector2(x + 6, y), Vector2(x - 9, y + 16)]), Color(1, 0.97, 0.95), 4.0, true))
	ui.add_child(play_btn)
	foot = HBoxContainer.new()
	foot.add_theme_constant_override("separation", 30)
	ui.add_child(foot)
	_square("quit", func(): get_tree().quit(), foot)
	_square("bars", func(): open("board"), foot)
	_square("trophy", func(): open("challenge"), foot)
	_square("badge", func(): prof_name = ""; open("profile"), foot)
	get_viewport().size_changed.connect(func() -> void: _sync_lobby())

## MAP SELECT: his frame, the title, the map's own painted card, a dot per map.
func _draw_map_panel() -> void:
	var s := map_panel.size
	var f: Font = Net.font if Net.font else ThemeDB.fallback_font
	map_panel.draw_rect(Rect2(Vector2.ZERO, s), Color(0.03, 0.025, 0.03, 0.88))
	map_panel.draw_rect(Rect2(Vector2.ZERO, s), Color(0.85, 0.08, 0.07, 0.95), false, 2.0)
	NFUI.scratches(map_panel, s, 4471, false)
	map_panel.draw_string(f, Vector2(0, 30), "MAP SELECT", HORIZONTAL_ALIGNMENT_CENTER, s.x, 22, Color(0.95, 0.93, 0.9))
	var ids := MAPS.keys()
	var n := ids.size()
	var i := ids.find(_cur_map())
	for k in n:
		var cx := s.x / 2.0 + (k - (n - 1) / 2.0) * 22.0
		map_panel.draw_circle(Vector2(cx, s.y - 14.0), 5.5, Color(0.95, 0.1, 0.08) if k == i else Color(0.55, 0.55, 0.58), true, -1.0, true)
	if Paint.card_path(_cur_map()).contains("/mapshots/"): # a map without his card: its name under the shot
		map_panel.draw_string(f, Vector2(0, s.y - 30.0), str(MAPS.get(_cur_map(), _cur_map())), HORIZONTAL_ALIGNMENT_CENTER, s.x, 20, Color(1, 0.9, 0.7))

## The map the card shows: the room's in a room (the host picks it), otherwise mine.
func _cur_map() -> String:
	return str(Net.room.get("map", "forest")) if Net.in_room() else off_map

func _host() -> bool:
	return Net.in_room() and str(Net.room.get("host", "")) == Net.username

func _map_step(d: int) -> void:
	var ids := MAPS.keys()
	var next := str(ids[(ids.find(_cur_map()) + d + ids.size()) % ids.size()])
	if Net.in_room():
		if not _host(): return
		NFUI.click()
		Net.send({"t": "set", "map": next})
		return
	NFUI.click()
	off_map = next
	if off_map != "kuwait": off_sniper = false
	_refresh()

## Put the picked map's card in the MAP SELECT frame (only when it changes).
func _show_map_pic() -> void:
	if _pic_map == _cur_map() and map_pic and is_instance_valid(map_pic): return
	_pic_map = _cur_map()
	if map_pic and is_instance_valid(map_pic): map_pic.queue_free()
	map_pic = Paint.card(_pic_map)
	if map_pic == null: return
	map_pic.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_pic_holder.add_child(map_pic)

## PLAY: with the server, a room on the picked map (with the picked modes; friends join with the code);
## without it, a trial round on that map at once.
func _play() -> void:
	if Net.in_room():
		if _host():
			NFUI.click()
			Net.send({"t": "start"})
		return
	NFUI.click()
	if page == "main" and Net.state == "online": _create_room()
	else: _start_trial()

func _create_room() -> void:
	_apply_modes = true
	Net.send({"t": "create", "map": off_map})

func _start_trial() -> void:
	var n := Net.username if Net.username != "" else "Player"
	var list := [{"name": n, "role": "killer" if off_char.begins_with("killer") else "survivor", "char": off_char, "perk": Net.perk, "slot": 0}]
	# a practice dummy: a target for the killer, or a wounded teammate to heal
	list.append({"name": "Dummy", "role": "survivor", "char": "survivor1" if off_char != "survivor1" else "survivor2", "slot": 1, "dummy": true})
	if not off_char.begins_with("killer") and off_bot: # a computer killer hunting you
		list.append({"name": "The Killer", "role": "killer", "char": "killer", "slot": 2, "bot": true})
	start_game.emit({"map": off_map, "me": n, "offline": true, "theme": off_theme, "gun": off_gun, "sniper": off_sniper and off_map == "kuwait", "players": list})

## Lay out his start screen for this screen size.
func _layout_start() -> void:
	if ui == null: return
	var vs := get_viewport().get_visible_rect().size
	var safe := NFUI.safe_insets(get_viewport())
	ui.visible = page in ["main", "lobby", "offline"]
	foot.visible = page == "main"
	play_btn.text = ("START" if _host() else "WAITING") if Net.in_room() else "PLAY"
	play_btn.disabled = Net.in_room() and not _host()
	map_prev.visible = not Net.in_room() or _host()
	map_next.visible = map_prev.visible
	var rw := 330.0
	var rx := vs.x - rw - 18.0 - safe.y
	play_btn.position = Vector2(rx, vs.y - 92.0)
	play_btn.size = Vector2(rw, 76.0)
	map_panel.position = Vector2(rx, vs.y - 92.0 - 16.0 - 156.0)
	map_panel.size = Vector2(rw, 156.0)
	map_pic_holder.position = Vector2(10.0, 40.0)
	map_pic_holder.size = Vector2(rw - 20.0, 92.0)
	map_prev.position = Vector2(4.0, 44.0)
	map_prev.size = Vector2(44.0, 84.0)
	map_next.position = Vector2(rw - 48.0, 44.0)
	map_next.size = Vector2(44.0, 84.0)
	side.position = Vector2(rx, map_panel.position.y - 12.0 - 114.0)
	side.size = Vector2(rw, 114.0)
	foot.position = Vector2(36.0 + safe.x, vs.y - 80.0)
	if page in ["main", "lobby", "offline"]: # the build number just left of PLAY, clear of the menu column
		version.position = Vector2(rx - 84.0, vs.y - 44.0)
	if _danced and page != "dances" and lobby and is_instance_valid(lobby):
		_danced = false
		lobby.dance_stop()
	if page == "dances": _danced = true
	modes_btn.text = "Game Modes  ·  %s" % THEMES.get(_mode_theme(), "Night")
	_show_map_pic()
	map_panel.queue_redraw()

func _mode_theme() -> String:
	return str(Net.room.get("theme", "normal")) if Net.in_room() else off_theme

# ---------- Dances ----------
func _page_dances() -> void:
	_label("Dances", 34, Color(0.95, 0.25, 0.22))
	_label("Pick the dance your character does at the fire — tap one to watch it", 18, Color(0.78, 0.78, 0.8))
	for d in NFLobby.DANCES:
		var did: String = d
		_mrow(str(NFLobby.DANCE_NAMES.get(did, did)) + ("     ✓ chosen" if Net.dance == did else ""), "dance", func() -> void:
			Net.dance = did
			Net.save()
			if lobby and is_instance_valid(lobby): lobby.dance_preview(did)
			_refresh(), Net.dance == did)
	# the song's own volume: down to nothing is off (also in Sound and Settings, «Dance music»)
	var vr := HBoxContainer.new()
	vr.add_theme_constant_override("separation", 12)
	box.add_child(vr)
	var vl := Label.new()
	vl.text = "Dance music  %d%%" % roundi(Aud.dance * 100.0) if Aud.dance > 0.005 else "Dance music  Off"
	vl.custom_minimum_size = Vector2(220, 0)
	vl.add_theme_font_size_override("font_size", 20)
	if Net.font: vl.add_theme_font_override("font", Net.font)
	vr.add_child(vl)
	var sl := HSlider.new()
	sl.min_value = 0.0; sl.max_value = 1.0; sl.step = 0.05
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.custom_minimum_size = Vector2(0, 44)
	sl.theme = NFUI.theme()
	sl.set_value_no_signal(Aud.dance)
	sl.value_changed.connect(func(v: float) -> void:
		Aud.set_vol("dance", v)
		vl.text = "Dance music  %d%%" % roundi(v * 100.0) if v > 0.005 else "Dance music  Off")
	vr.add_child(sl)
	var off := Button.new()
	off.text = "On" if Aud.dance <= 0.005 else "Off"
	off.custom_minimum_size = Vector2(118, 44)
	off.pressed.connect(func() -> void:
		Aud.set_vol("dance", 0.8 if Aud.dance <= 0.005 else 0.0)
		_refresh())
	NFUI.dress(off, "note")
	vr.add_child(off)
	_mrow("Dance now — everyone in the room sees it", "note", func() -> void:
		if lobby and is_instance_valid(lobby): lobby.emote(Net.username, 1, Net.dance)
		if Net.in_room(): Net.send({"t": "emote", "k": 1, "d": Net.dance}))
	_mrow("Back", "exit", func() -> void:
		if lobby and is_instance_valid(lobby): lobby.dance_stop()
		open("lobby" if Net.in_room() else "main"))

# ---------- Game Modes ----------
func _page_modes() -> void:
	var in_room := Net.in_room()
	var host := in_room and str(Net.room.get("host", "")) == Net.username
	var can := (not in_room) or host
	var r := Net.room
	_label("Game Modes", 34, Color(0.95, 0.25, 0.22))
	if in_room and not host: _label("Only the host can change these", 18, Color(1, 0.75, 0.45))
	_label("Weather", 22, Color(1, 0.82, 0.45))
	var cur := _mode_theme()
	var row: HBoxContainer = null
	var k := 0
	for id in THEMES:
		if k % 2 == 0: row = _row()
		k += 1
		var tid: String = id
		var b := _mrow(str(THEMES[tid]), str(THEME_ICON[tid]), func() -> void:
			if in_room: Net.send({"t": "set", "theme": tid})
			else:
				off_theme = tid
				NFLobby.last_theme = tid
			_refresh(), cur == tid, false, row, 50.0)
		b.disabled = not can
	_label("Rules", 22, Color(1, 0.82, 0.45))
	var gon: bool = r.get("gun", false) if in_room else off_gun
	var gb := _mrow("Gun mode: %s" % ("On — a stun pistol for survivors" if gon else "Off"), "gun", func() -> void:
		if in_room: Net.send({"t": "set", "gun": not gon})
		else: off_gun = not gon
		_refresh(), gon)
	gb.disabled = not can
	var son: bool = r.get("sniper", false) if in_room else off_sniper
	var sb := _mrow("Sniper mode: %s" % ("On — Kuwait City, one gate, the killer on the roof" if son else "Off"), "gun", func() -> void:
		if in_room: Net.send({"t": "set", "sniper": not son})
		else:
			off_sniper = not son
			if off_sniper: off_map = "kuwait"
		_refresh(), son)
	sb.disabled = not can
	if not in_room:
		var bb := _mrow("Computer killer (trial): %s" % ("On" if off_bot else "Off"), "skull", func() -> void:
			off_bot = not off_bot
			_refresh(), off_bot)
	_label("The start screen keeps the same picture whatever you pick", 16, Color(0.65, 0.65, 0.68))
	_mrow("Back", "exit", func(): open("lobby" if in_room else "main"))

# ---------- the trophy: today's challenge and my last round ----------
func _page_challenge() -> void:
	_label("Today", 34, Color(1, 0.82, 0.45))
	var dy: Dictionary = Net.daily()
	_label(("✓ Daily challenge: %s" if bool(dy.done) else "Daily challenge: %s") % str(dy.text) + "  (%d/%d)" % [int(dy.have), int(dy.need)],
		22, Color(0.55, 1.0, 0.6) if bool(dy.done) else Color(1, 0.85, 0.45))
	_label("«%s»" % str(dy.whisper), 18, Color(0.75, 0.75, 0.78))
	_label(_status(), 18, Color(0.6, 0.9, 0.6) if Net.state == "online" else Color(0.8, 0.8, 0.8))
	_mrow("Rankings and my rounds", "bars", func(): open("board"))
	_mrow("Back", "exit", func(): open("main"))
