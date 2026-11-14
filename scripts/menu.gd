class_name GameMenu
extends CanvasLayer
## Menus: username, main, friends, lobby (map / role), character select with a live preview in front
## of the campfire, control layout, offline test. The 3D side of it lives in scripts/lobby.gd.

signal start_game(cfg: Dictionary)

const MAPS := {"forest": "الغابة", "village": "القرية المهجورة", "fareej": "الفريج", "rubkhali": "الربع الخالي"}
const THEMES := {"normal": "عادي", "snow": "ثلج", "halloween": "هالوين"}
const THEME_ICON := {"normal": "moon", "snow": "star", "halloween": "skull"}
const VERSION := "v1.4"
const CHARS := {"killer": "القاتل", "survivor1": "ناجي 1", "survivor2": "الحمراء", "survivor3": "ناجي 3", "survivor4": "ناجي 4", "survivor5": "المقاتلة", "survivor6": "الممرضة", "survivor7": "الطالبة"}
const ERRORS := {"no_room": "ما في غرفة بهالكود", "room_full": "الغرفة ممتلئة", "in_game": "اللعبة بدأت بالغرفة",
	"killer_taken": "في قاتل بالغرفة", "offline": "صديقك مو متصل", "bad_name": "الاسم لازم 2 إلى 16 حرف بدون مسافات",
	"name_taken": "الاسم مستخدم الحين، اختر غيره"}

var page := ""
var box: VBoxContainer
var toast := ""
var invite := {}
var typed := {} # LineEdit texts kept across rebuilds
var off_map := "forest"
var off_char := "killer"
var off_theme := "normal"
var lobby: NFLobby       # the campfire scene, set by main.gd
var card: Control        # player card in the top corner
var char_pad: Control    # swipe area for the character carousel
var chars_from := "main" # which page the character select was opened from
var want_char := ""     # character I asked the server for, until the room list agrees
var _swipe_x := 0.0
var _swiping := false
var _editor: NFControlsEdit
var version: Label      # the small build number in the corner

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
	card.size = Vector2(304, 116)
	card.draw.connect(_draw_card)
	add_child(card)
	version = Label.new()
	version.text = VERSION
	version.add_theme_font_size_override("font_size", 15)
	version.add_theme_color_override("font_color", Color(0.55, 0.55, 0.58))
	version.mouse_filter = Control.MOUSE_FILTER_STOP
	version.gui_input.connect(_on_version_input)
	add_child(version)
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
				if not (page in ["friends", "chars", "controls"]): page = "lobby"
			elif page in ["lobby", "friends", "chars"]: page = "main"
		"started":
			start_game.emit({"map": m.map, "players": m.players, "me": Net.username, "offline": false,
				"seed": int(m.get("seed", 1)), "theme": str(m.get("theme", "normal"))})
			return
		"invite": invite = m
		"emote": # someone at the fire waved / danced / clapped
			if lobby and is_instance_valid(lobby): lobby.emote(str(m.get("n", "")), int(m.get("k", 0)))
			return
		"error": toast = ERRORS.get(str(m.code), str(m.code))
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
		"online": return "متصل ✓  (%s)" % Net.username
		"connecting": return "جاري الاتصال بالسيرفر... (أول مرة ممكن تاخذ دقيقة)"
		"name_taken": return "الاسم مستخدم الحين، غيّره من الإعدادات"
	return "غير متصل"

func _refresh() -> void:
	if not visible or box == null: return
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	_label("NightFall", 44, Color(0.85, 0.1, 0.12))
	if not invite.is_empty():
		_label("%s يدعوك لغرفته" % str(invite.from), 24, Color(1, 0.85, 0.4))
		var h := _row()
		_button("قبول", func():
			Net.send({"t": "join", "code": invite.code}); invite = {}; _refresh(), h, true, "out")
		_button("رفض", func(): invite = {}; _refresh(), h, true, "exit")
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

func _char_list() -> Array:
	var out := []
	var trial := _offline_flow()
	for id in CHARS:
		if id == "killer" and not trial: continue # online the role button picks the killer
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
	card.position = Vector2(vs.x - card.size.x - 16.0 - safe.y, 78.0)
	card.queue_redraw()
	char_pad.visible = page == "chars"
	var px: float = maxf(596.0, vs.x * 0.44) # clear of the menu column on the left
	char_pad.position = Vector2(px, 0.0)
	char_pad.size = Vector2(maxf(vs.x - px, 10.0), vs.y)
	if lobby == null or not is_instance_valid(lobby): return
	if page == "name":
		lobby.hide_preview()
		lobby.set_cast([], Net.username)
		lobby.focus(false)
		return
	lobby.preview(_my_char(), str(CHARS.get(_my_char(), "")), dir)
	lobby.focus(page == "chars")
	lobby.set_cast(Net.room.get("players", []) if Net.in_room() else [], Net.username)

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
		Net.send({"t": "set", "char": id})
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
	var nm := Net.username if Net.username != "" else "لاعب"
	card.draw_string(f, Vector2(12.0, 30.0), nm, HORIZONTAL_ALIGNMENT_RIGHT, s.x - 70.0, 24, Color(0.95, 0.93, 0.9))
	card.draw_string(f, Vector2(12.0, 54.0), "المستوى %d" % Net.level(), HORIZONTAL_ALIGNMENT_RIGHT, s.x - 70.0, 18, Color(1, 0.85, 0.45))
	var br := Rect2(Vector2(12.0, 64.0), Vector2(s.x - 70.0, 12.0))
	NFUI.bar(card, br, Net.level_progress(), Color(0.8, 0.12, 0.12), Color(1, 1, 1, 0.3))
	card.draw_string(f, Vector2(12.0, 90.0), "خبرة %d/%d" % [Net.xp, Net.level_xp(Net.level() + 1)],
		HORIZONTAL_ALIGNMENT_RIGHT, s.x - 70.0, 15, Color(0.7, 0.7, 0.72))
	NFIcons.draw(card, "out", Vector2(26.0, 104.0), 18.0, Color(0.5, 0.85, 1.0))
	card.draw_string(f, Vector2(38.0, 110.0), "%d" % Net.escapes, HORIZONTAL_ALIGNMENT_LEFT, 60.0, 17, Color(0.6, 0.9, 1.0))
	NFIcons.draw(card, "skull", Vector2(104.0, 104.0), 18.0, Color(1.0, 0.4, 0.35))
	card.draw_string(f, Vector2(116.0, 110.0), "%d" % Net.kills, HORIZONTAL_ALIGNMENT_LEFT, 60.0, 17, Color(1.0, 0.55, 0.5))

# ---------- pages ----------
func _page_name() -> void:
	_label("اختر اسمك (يوزر) — أصدقاؤك يضيفونك فيه")
	_edit("name", "الاسم بالإنجليزي أو العربي بدون مسافات")
	_button("متابعة", func():
		var n: String = typed.get("name", "").strip_edges()
		if n.length() < 2 or n.length() > 16 or n.contains(" "):
			toast = ERRORS.bad_name
			_refresh()
			return
		Net.configure(n, "")
		open("main"), null, true, "out")
	_button("النمط التجريبي (بدون نت)", func(): chars_from = "offline"; open("offline"), null, true, "star")

func _page_main() -> void:
	_label(_status(), 20, Color(0.6, 0.9, 0.6) if Net.state == "online" else Color(0.8, 0.8, 0.8))
	var on := Net.state == "online"
	_button("إنشاء غرفة", func(): Net.send({"t": "create", "map": "forest"}), null, on, "star")
	var h := _row()
	_edit("code", "كود الغرفة", h)
	_button("دخول", func(): Net.send({"t": "join", "code": typed.get("code", "")}), h, on, "out")
	_button("الأصدقاء (%d)" % Net.friends.size(), func(): open("friends"), null, true, "chat")
	_button("النمط التجريبي (بدون نت)", func(): chars_from = "offline"; open("offline"), null, true, "star")
	_button("الصوت والإعدادات", func(): Gfx.open_settings(), null, true, "gear")
	_button("الاسم والسيرفر", func():
		typed["name"] = Net.username; typed["url"] = Net.url; open("settings"), null, true, "gear")
	_emote_row()

func _page_settings() -> void:
	_label("الاسم")
	_edit("name", "الاسم")
	_label("رابط السيرفر")
	_edit("url", "wss://...")
	_button("حفظ", func():
		Net.configure(typed.get("name", Net.username), typed.get("url", Net.url)); open("main"), null, true, "star")
	_button("الصوت والجرافيكس", func(): Gfx.open_settings(), null, true, "gear")
	_button("أزرار التحكم (مكان وحجم)", _open_editor, null, true, "gear")
	_button("رجوع", func(): open("main"), null, true, "exit")

func _open_editor() -> void:
	if _editor and is_instance_valid(_editor): return
	_editor = NFControlsEdit.new()
	_editor.role = "killer" if _my_char() == "killer" else "survivor"
	_editor.closed.connect(func(): _editor = null)
	add_child(_editor)

func _page_friends() -> void:
	_label("الأصدقاء")
	var h := _row()
	_edit("friend", "يوزر صديقك", h)
	_button("إضافة", func():
		Net.add_friend(typed.get("friend", "")); typed["friend"] = ""; _refresh(), h, true, "chat")
	if Net.friends.is_empty(): _label("ما أضفت أحد للحين", 20, Color(0.7, 0.7, 0.7))
	for f in Net.friends:
		var name := str(f)
		var r := _row()
		var l := Label.new()
		var on := Net.is_online(name)
		l.text = ("● " if on else "○ ") + name
		l.add_theme_color_override("font_color", Color(0.5, 1, 0.5) if on else Color(0.6, 0.6, 0.6))
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(l)
		if Net.in_room():
			var b := _button("دعوة", func(): Net.send({"t": "invite", "to": name}); toast = "انرسلت الدعوة لـ" + name; _refresh(), r, on, "chat")
			b.size_flags_horizontal = Control.SIZE_SHRINK_END
		var d := _button("حذف", func(): Net.remove_friend(name), r, true, "exit")
		d.size_flags_horizontal = Control.SIZE_SHRINK_END
	_button("رجوع", func(): open("lobby" if Net.in_room() else "main"), null, true, "exit")

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
	_label("كود الغرفة", 20, Color(0.75, 0.75, 0.78))
	_label(code, 46, Color(1, 0.85, 0.4))
	_button("انسخ الكود وأرسله لربعك", func():
		DisplayServer.clipboard_set(code)
		toast = "انتسخ الكود %s" % code
		_refresh(), null, true, "chat")
	if host:
		var h := _row()
		var hk := 0
		for id in MAPS:
			if hk == 2: h = _row() # four maps: two rows
			hk += 1
			var b := _button(MAPS[id], func(): Net.send({"t": "set", "map": id}), h)
			b.add_theme_font_size_override("font_size", 20)
			if str(r.map) == id: b.modulate = Color(1, 0.75, 0.3)
		var ht := _row()
		for id in THEMES:
			var b2 := _button(THEMES[id], func(): Net.send({"t": "set", "theme": id}), ht, true, THEME_ICON[id])
			b2.add_theme_font_size_override("font_size", 20)
			if str(r.get("theme", "normal")) == id: b2.modulate = Color(1, 0.75, 0.3)
	else:
		_label("الخريطة: %s  •  الجو: %s" % [MAPS.get(str(r.map), str(r.map)), THEMES.get(str(r.get("theme", "normal")), "عادي")], 22)
	for p in r.players:
		var txt := "%s%s — %s" % ["★ " if str(p.name) == str(r.host) else "", str(p.name), CHARS.get(str(p.char), str(p.char))]
		_label(txt, 20, Color(1, 0.4, 0.4) if str(p.role) == "killer" else Color(0.7, 0.85, 1))
	var me := _me()
	var h2 := _row()
	var bk := _button("ألعب قاتل", func(): Net.send({"t": "set", "role": "killer"}), h2, true, "skull")
	var bs := _button("ألعب ناجي", func(): Net.send({"t": "set", "role": "survivor"}), h2, true, "shoe")
	if str(me.get("role", "")) == "killer": bk.modulate = Color(1, 0.75, 0.3)
	else: bs.modulate = Color(1, 0.75, 0.3)
	if str(me.get("role", "")) == "survivor":
		_button("اختر الشخصية — %s" % CHARS.get(str(me.get("char", "")), ""), func():
			chars_from = "lobby"; open("chars"), null, true, "star")
	_emote_row()
	_button("دعوة الأصدقاء", func(): open("friends"), null, true, "chat")
	if host: _button("ابدأ اللعب", func(): Net.send({"t": "start"}), null, true, "out")
	else: _label("بانتظار صاحب الغرفة يبدأ...", 20, Color(0.7, 0.7, 0.7))
	_button("خروج من الغرفة", func(): Net.send({"t": "leave"}), null, true, "exit")

## Character select: the chosen one is standing in front of the fire; swipe the camp to change.
func _page_chars() -> void:
	var list := _char_list()
	var id := _my_char()
	var i := list.find(id)
	_label("اختر شخصيتك", 26, Color(1, 0.85, 0.45))
	_label(str(CHARS.get(id, id)), 40, NFUI.char_col(id))
	_label("%d/%d  •  اسحب الشاشة يمين أو يسار" % [maxi(i, 0) + 1, list.size()], 18, Color(0.7, 0.7, 0.72))
	var h := _row()
	_button("‹ السابق", func(): _step(-1), h, true, "next")
	_button("التالي ›", func(): _step(1), h, true, "next")
	_button("تم", func(): open(chars_from if chars_from != "main" else "main"), null, true, "star")

## Hidden developer tools. Only reachable on a phone that has unlocked them.
func _page_dev() -> void:
	if not Dev.unlocked:
		open("main")
		return
	_label("أدوات المطوّر", 30, Color(1, 0.85, 0.4))
	_label("تظهر على جهازك فقط", 18, Color(0.7, 0.7, 0.72))
	var esp := _button("رؤية اللاعبين: %s" % ("شغّال" if Dev.esp else "مطفي"), func():
		Dev.set_esp(not Dev.esp); _refresh(), null, true, "next")
	if Dev.esp: esp.modulate = Color(1, 0.75, 0.3)
	_label("سرعة الحركة ×%.2f" % Dev.speed, 20, Color(0.85, 0.9, 1))
	var sl := HSlider.new()
	sl.min_value = 1.0; sl.max_value = 2.0; sl.step = 0.05
	sl.custom_minimum_size = Vector2(0, 44)
	sl.theme = NFUI.theme()
	sl.set_value_no_signal(Dev.speed)
	sl.value_changed.connect(func(v: float): Dev.set_speed(v); _refresh())
	box.add_child(sl)
	_button("رجوع", func(): open("main"), null, true, "exit")

func _page_offline() -> void:
	chars_from = "offline"
	_label("النمط التجريبي — اختر الخريطة والجو والشخصية")
	var h := _row()
	var k := 0
	for id in MAPS:
		if k == 2: h = _row()
		k += 1
		var b := _button(MAPS[id], func(): off_map = id; _refresh(), h)
		b.add_theme_font_size_override("font_size", 20)
		if off_map == id: b.modulate = Color(1, 0.75, 0.3)
	var ht := _row()
	for id in THEMES:
		var b2 := _button(THEMES[id], func(): off_theme = id; _refresh(), ht, true, THEME_ICON[id])
		b2.add_theme_font_size_override("font_size", 20)
		if off_theme == id: b2.modulate = Color(1, 0.75, 0.3)
	_button("الشخصية — %s" % CHARS.get(off_char, off_char), func(): open("chars"), null, true, "star")
	_button("ابدأ", func():
		var n := Net.username if Net.username != "" else "Player"
		var list := [{"name": n, "role": "killer" if off_char == "killer" else "survivor", "char": off_char, "slot": 0}]
		# a practice dummy: a target for the killer, or a wounded teammate to heal
		list.append({"name": "دمية", "role": "survivor", "char": "survivor4" if off_char != "survivor4" else "survivor1", "slot": 1, "dummy": true})
		start_game.emit({"map": off_map, "me": n, "offline": true, "theme": off_theme, "players": list}), null, true, "out")
	_button("رجوع", func(): chars_from = "main"; open("main" if Net.username != "" else "name"), null, true, "exit")
