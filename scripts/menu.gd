class_name GameMenu
extends CanvasLayer
## Menus: username, main, friends, lobby (map / role / character), offline test.

signal start_game(cfg: Dictionary)

const MAPS := {"forest": "الغابة", "village": "القرية المهجورة"}
const CHARS := {"killer": "القاتل", "survivor1": "ناجي 1", "survivor2": "ناجي 2", "survivor3": "ناجي 3", "survivor4": "ناجي 4"}
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

func _ready() -> void:
	layer = 10
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.035, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var sc := ScrollContainer.new()
	sc.set_anchors_preset(Control.PRESET_FULL_RECT)
	sc.offset_top = 20; sc.offset_bottom = -20
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(sc)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.add_child(center)
	box = VBoxContainer.new()
	box.custom_minimum_size.x = 600
	box.add_theme_constant_override("separation", 10)
	var th := Theme.new()
	th.default_font_size = 24
	box.theme = th
	center.add_child(box)
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
			if str(m.get("code", "")) != "":
				if page != "friends": page = "lobby"
			elif page == "lobby" or page == "friends": page = "main"
		"started":
			start_game.emit({"map": m.map, "players": m.players, "me": Net.username, "offline": false})
			return
		"invite": invite = m
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

func _button(text: String, cb: Callable, parent: Control = null, enabled := true) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 54
	b.disabled = not enabled
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	(parent if parent else box).add_child(b)
	return b

func _edit(key: String, hint: String, parent: Control = null) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = hint
	e.text = typed.get(key, "")
	e.custom_minimum_size.y = 54
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.alignment = HORIZONTAL_ALIGNMENT_CENTER
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
	var focus_key := ""
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	_label("NightFall", 44, Color(0.85, 0.1, 0.12))
	if not invite.is_empty():
		_label("%s يدعوك لغرفته" % str(invite.from), 24, Color(1, 0.85, 0.4))
		var h := _row()
		_button("قبول", func():
			Net.send({"t": "join", "code": invite.code}); invite = {}; _refresh(), h)
		_button("رفض", func(): invite = {}; _refresh(), h)
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
		open("main"))

func _page_main() -> void:
	_label(_status(), 20, Color(0.6, 0.9, 0.6) if Net.state == "online" else Color(0.8, 0.8, 0.8))
	var on := Net.state == "online"
	_button("إنشاء غرفة", func(): Net.send({"t": "create", "map": "forest"}), null, on)
	var h := _row()
	_edit("code", "كود الغرفة", h)
	_button("دخول", func(): Net.send({"t": "join", "code": typed.get("code", "")}), h, on)
	_button("الأصدقاء (%d)" % Net.friends.size(), func(): open("friends"))
	_button("تجربة بدون نت", func(): open("offline"))
	_button("الاسم والسيرفر", func():
		typed["name"] = Net.username; typed["url"] = Net.url; open("settings"))

func _page_settings() -> void:
	_label("الاسم")
	_edit("name", "الاسم")
	_label("رابط السيرفر")
	_edit("url", "wss://...")
	_button("حفظ", func():
		Net.configure(typed.get("name", Net.username), typed.get("url", Net.url)); open("main"))
	_button("رجوع", func(): open("main"))

func _page_friends() -> void:
	_label("الأصدقاء")
	var h := _row()
	_edit("friend", "يوزر صديقك", h)
	_button("إضافة", func():
		Net.add_friend(typed.get("friend", "")); typed["friend"] = ""; _refresh(), h)
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
			var b := _button("دعوة", func(): Net.send({"t": "invite", "to": name}); toast = "انرسلت الدعوة لـ" + name; _refresh(), r, on)
			b.size_flags_horizontal = Control.SIZE_SHRINK_END
		var d := _button("حذف", func(): Net.remove_friend(name), r)
		d.size_flags_horizontal = Control.SIZE_SHRINK_END
	_button("رجوع", func(): open("lobby" if Net.in_room() else "main"))

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
	_label("كود الغرفة: %s" % str(r.code), 30, Color(1, 0.85, 0.4))
	if host:
		var h := _row()
		for id in MAPS:
			var b := _button(MAPS[id], func(): Net.send({"t": "set", "map": id}), h)
			if str(r.map) == id: b.modulate = Color(1, 0.75, 0.3)
	else:
		_label("الخريطة: %s" % MAPS.get(str(r.map), str(r.map)), 22)
	for p in r.players:
		var txt := "%s%s — %s" % ["★ " if str(p.name) == str(r.host) else "", str(p.name), CHARS.get(str(p.char), str(p.char))]
		_label(txt, 22, Color(1, 0.4, 0.4) if str(p.role) == "killer" else Color(0.7, 0.85, 1))
	var me := _me()
	var h2 := _row()
	var bk := _button("ألعب قاتل", func(): Net.send({"t": "set", "role": "killer"}), h2)
	var bs := _button("ألعب ناجي", func(): Net.send({"t": "set", "role": "survivor"}), h2)
	if str(me.get("role", "")) == "killer": bk.modulate = Color(1, 0.75, 0.3)
	else: bs.modulate = Color(1, 0.75, 0.3)
	if str(me.get("role", "")) == "survivor":
		var h3 := _row()
		for id in ["survivor1", "survivor2", "survivor3", "survivor4"]:
			var b := _button(CHARS[id], func(): Net.send({"t": "set", "char": id}), h3)
			if str(me.get("char", "")) == id: b.modulate = Color(1, 0.75, 0.3)
	_button("دعوة الأصدقاء", func(): open("friends"))
	if host: _button("ابدأ اللعب", func(): Net.send({"t": "start"}))
	else: _label("بانتظار صاحب الغرفة يبدأ...", 20, Color(0.7, 0.7, 0.7))
	_button("خروج من الغرفة", func(): Net.send({"t": "leave"}))

func _page_offline() -> void:
	_label("تجربة بدون نت")
	var h := _row()
	for id in MAPS:
		var b := _button(MAPS[id], func(): off_map = id; _refresh(), h)
		if off_map == id: b.modulate = Color(1, 0.75, 0.3)
	var h2 := _row()
	for id in CHARS:
		var b := _button(CHARS[id], func(): off_char = id; _refresh(), h2)
		b.add_theme_font_size_override("font_size", 18)
		if off_char == id: b.modulate = Color(1, 0.75, 0.3)
	_button("ابدأ", func():
		var n := Net.username if Net.username != "" else "Player"
		start_game.emit({"map": off_map, "me": n, "offline": true,
			"players": [{"name": n, "role": "killer" if off_char == "killer" else "survivor", "char": off_char, "slot": 0}]}))
	_button("رجوع", func(): open("main" if Net.username != "" else "name"))
