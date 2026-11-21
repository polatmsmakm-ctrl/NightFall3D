extends Node
## Online client (autoload "Net"): username, friends list (stored on the phone), rooms, relay.

signal message(m: Dictionary)
signal changed

const DEFAULT_URL := "wss://nightfall3d-server.onrender.com"
const PATH := "user://profile.cfg"

var url := DEFAULT_URL
var username := ""
var friends: Array = []
var online := {}
var state := "off" # off / connecting / online / name_taken
var room := {}
var font: FontFile
var xp := 0
var replay := {}   # trial-mode round to start again right after a scene reload
var escapes := 0   # how many rounds I got out of, all time
var kills := 0     # survivors I killed as the killer, all time
var secret := false # the hidden character is open on this phone (a gift from the owner)
var gifted: Array = [] # owner's phone only: the friends I opened it for
var last_char := ""    # the character I last started a round with: the one standing at the fire
var last_round := {}   # {res: escaped / dead / killer, score, gens, wipe}: the card and the camp read it
var day := ""          # today's date, for the daily challenge
var day_n: Array = [0, 0, 0] # today: rounds played, escapes, kills
var day_paid := false  # today's challenge already paid its experience
var rounds := 0        # rounds played, all time
var history: Array = [] # the last HISTORY rounds: {d, map, role, res, score, kills}, newest first
const HISTORY := 20
var fstats := {}       # friend (lowercase) -> {name, lv, xp, esc, kills, rounds}: the server passes them on

var _ws: WebSocketPeer
var _hello := false
var _retry := 0.0
var _ping := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = load("res://assets/fonts/cairo-ar.woff2")
	var lat: FontFile = load("res://assets/fonts/cairo-lat.woff2")
	if font and lat:
		font.fallbacks = [lat, ThemeDB.fallback_font]
		ThemeDB.get_default_theme().default_font = font
	var c := ConfigFile.new()
	if c.load(PATH) == OK:
		username = c.get_value("p", "name", "")
		friends = c.get_value("p", "friends", [])
		url = c.get_value("p", "url", DEFAULT_URL)
		xp = int(c.get_value("p", "xp", 0))
		escapes = int(c.get_value("p", "escapes", 0))
		kills = int(c.get_value("p", "kills", 0))
		secret = bool(c.get_value("p", "secret", false))
		gifted = c.get_value("p", "gifted", [])
		last_char = str(c.get_value("p", "last_char", ""))
		last_round = c.get_value("p", "last_round", {})
		day = str(c.get_value("p", "day", ""))
		day_n = c.get_value("p", "day_n", [0, 0, 0])
		day_paid = bool(c.get_value("p", "day_paid", false))
		rounds = int(c.get_value("p", "rounds", 0))
		history = c.get_value("p", "history", [])
		if day_n.size() != 3: day_n = [0, 0, 0]
	var env_url := OS.get_environment("NF_URL")
	if env_url != "": url = env_url

func save() -> void:
	var c := ConfigFile.new()
	c.set_value("p", "name", username)
	c.set_value("p", "friends", friends)
	c.set_value("p", "url", url)
	c.set_value("p", "xp", xp)
	c.set_value("p", "escapes", escapes)
	c.set_value("p", "kills", kills)
	c.set_value("p", "secret", secret)
	c.set_value("p", "gifted", gifted)
	c.set_value("p", "last_char", last_char)
	c.set_value("p", "last_round", last_round)
	c.set_value("p", "rounds", rounds)
	c.set_value("p", "history", history)
	c.set_value("p", "day", day)
	c.set_value("p", "day_n", day_n)
	c.set_value("p", "day_paid", day_paid)
	c.save(PATH)

## The hidden character («الفالكيري القرمزية») shows on the owner's phone (the one with the hidden
## tools unlocked) and on every phone he has opened it for.
func has_secret() -> bool:
	return secret or Dev.unlocked

## The six digits that open the hidden character for one username, with no server in between:
## the owner reads them off his phone, the friend types them in on the friends page.
func secret_code(who: String) -> String:
	return "%06d" % (abs(("nf-valk:" + who.strip_edges().to_lower()).hash()) % 1000000)

## A friend typing the code he was given. Arabic-Indic digits count too.
func redeem(code: String) -> bool:
	var c := code.strip_edges()
	for i in 10: c = c.replace(char(0x0660 + i), str(i)).replace(char(0x06F0 + i), str(i))
	if username == "" or c != secret_code(username): return false
	secret = true
	save()
	changed.emit()
	return true

## Owner only: open or shut the hidden character for a friend who is online right now.
func gift(friend: String, on: bool) -> void:
	send({"t": "gift", "to": friend, "on": on})
	var k := friend.to_lower()
	gifted.erase(k)
	if on: gifted.append(k)
	save()
	changed.emit()

## My numbers for the friends' board (the server keeps them only to pass them on).
func my_stats() -> Dictionary:
	return {"name": username, "lv": level(), "xp": xp, "esc": escapes, "kills": kills, "rounds": rounds}

func send_stats() -> void:
	if state == "online": send({"t": "stats", "s": my_stats()})

## Me and every friend the server has numbers for, best first by `by` (esc / kills / lv).
func board(by: String) -> Array:
	var rows := [my_stats()]
	for f in friends:
		var k := str(f).to_lower()
		if fstats.has(k): rows.append(fstats[k])
		else: rows.append({"name": str(f), "lv": 0, "xp": 0, "esc": 0, "kills": 0, "rounds": 0, "none": true})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var x := int(a.get(by, 0)); var y := int(b.get(by, 0))
		if x != y: return x > y
		return int(a.get("xp", 0)) > int(b.get("xp", 0)))
	return rows

func level() -> int:
	return 1 + int(sqrt(xp / 200.0))

## Experience needed for the start of a level (level 1 starts at 0).
func level_xp(lv: int) -> int:
	return int(200.0 * pow(float(maxi(lv, 1) - 1), 2.0))

## How far through the current level I am, 0..1 — for the bar on the player card.
func level_progress() -> float:
	var lv := level()
	var a := level_xp(lv)
	var b := level_xp(lv + 1)
	return clampf(float(xp - a) / maxf(float(b - a), 1.0), 0.0, 1.0)

## Keep the totals of a finished round next to the experience, on the phone.
func record_match(got_out: int, killed: int, map := "", role := "", res := "", score := 0) -> void:
	escapes += maxi(got_out, 0)
	kills += maxi(killed, 0)
	rounds += 1
	if map != "": # the round on my own list
		var t := Time.get_datetime_dict_from_system()
		history.push_front({"d": "%d/%d %02d:%02d" % [t.day, t.month, t.hour, t.minute], "map": map, "role": role,
			"res": res, "score": score, "kills": maxi(killed, 0)})
		if history.size() > HISTORY: history.resize(HISTORY)
	send_stats()
	_roll_day()
	day_n[0] = int(day_n[0]) + 1
	day_n[1] = int(day_n[1]) + maxi(got_out, 0)
	day_n[2] = int(day_n[2]) + maxi(killed, 0)
	if bool(daily().done) and not day_paid: # today's challenge pays once
		day_paid = true
		xp += DAILY_XP
	save()

## The challenge of the day: the same one for everybody on the same date, counted on the phone.
const DAILY := [["العب 3 جولات اليوم", 0, 3], ["اهرب مرة اليوم", 1, 1], ["اهرب مرتين اليوم", 1, 2],
	["اقتل 3 ناجين وأنت القاتل", 2, 3], ["العب جولتين اليوم", 0, 2], ["اقتل ناجي واحد وأنت القاتل", 2, 1]]
const DAILY_XP := 150
## A line that changes with the date, under the challenge.
const WHISPERS := ["المولد اللي يرمش أقرب للنهاية — كمّله أول", "لا تركض جنب القاتلة: الركض له صوت",
	"اثنين على الخطاف أسرع من واحد", "سكّر الباب وراك، بس تذكّر إن له صوت", "الخزانة تخبّيك، بس مو للأبد",
	"إذا انفتحت البوابات لا تتأخر: القمر ما ينتظر", "الكشاف يعميها لحظة — استغلها", "امشِ منحني جنب النوافذ",
	"القاتلة تسمع المولد من 8 متر بس", "لا تتركون واحد وراكم"]

func _roll_day() -> void:
	var today := Time.get_date_string_from_system()
	if day == today: return
	day = today
	day_n = [0, 0, 0]
	day_paid = false

func daily() -> Dictionary:
	_roll_day()
	var d: Array = DAILY[absi(day.hash()) % DAILY.size()]
	var have: int = mini(int(day_n[int(d[1])]), int(d[2]))
	return {"text": str(d[0]), "have": have, "need": int(d[2]), "done": have >= int(d[2]),
		"whisper": str(WHISPERS[absi((day + "w").hash()) % WHISPERS.size()])}

## A name for the level, on the player card.
func title() -> String:
	var lv := level()
	if lv >= 20: return "أسطورة الليل"
	if lv >= 12: return "صيّاد الظلام"
	if lv >= 7: return "ناجي متمرّس"
	if lv >= 3: return "ناجي"
	return "مبتدئ"

func configure(new_name: String, new_url: String) -> void:
	username = new_name.strip_edges()
	if new_url.strip_edges() != "": url = new_url.strip_edges()
	save()
	if _ws: _ws.close()
	_ws = null
	state = "off"; room = {}; online = {}
	_retry = 0.0
	changed.emit()

func send(d: Dictionary) -> void:
	if _ws and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(d))

func is_online(n: String) -> bool:
	return online.has(n.to_lower())

func in_room() -> bool:
	return room.has("code") and str(room.code) != ""

func add_friend(n: String) -> void:
	n = n.strip_edges()
	if n == "" or n.to_lower() == username.to_lower(): return
	for f in friends:
		if str(f).to_lower() == n.to_lower(): return
	friends.append(n)
	save()
	send({"t": "friends", "friends": friends})
	changed.emit()

func remove_friend(n: String) -> void:
	friends.erase(n)
	online.erase(n.to_lower())
	save()
	send({"t": "friends", "friends": friends})
	changed.emit()

func _process(dt: float) -> void:
	if _ws == null:
		if username == "" or state == "name_taken": return
		_retry -= dt
		if _retry <= 0.0:
			_ws = WebSocketPeer.new()
			_hello = false
			if _ws.connect_to_url(url) != OK:
				_ws = null; _retry = 4.0
				return
			state = "connecting"
			changed.emit()
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _hello:
				_hello = true
				send({"t": "hello", "name": username, "friends": friends, "stats": my_stats()})
			while _ws.get_available_packet_count() > 0:
				var m = JSON.parse_string(_ws.get_packet().get_string_from_utf8())
				if m is Dictionary and m.has("t"): _handle(m)
			_ping += dt
			if _ping > 20.0:
				_ping = 0.0
				send({"t": "ping"})
		WebSocketPeer.STATE_CLOSED:
			_ws = null
			_retry = 4.0
			var was_in_room := in_room()
			room = {}; online = {}
			if state != "name_taken": state = "off"
			changed.emit()
			if was_in_room: message.emit({"t": "room", "code": ""})

func _handle(m: Dictionary) -> void:
	match str(m.t):
		"welcome": state = "online"
		"friends":
			online = {}
			for n in m.get("online", []): online[str(n).to_lower()] = true
			for row in m.get("stats", []):
				if row is Dictionary: fstats[str(row.get("name", "")).to_lower()] = row
		"fstats": # a friend finished a round
			if m.get("s") is Dictionary: fstats[str(m.s.get("name", "")).to_lower()] = m.s
		"presence":
			if m.get("online", false): online[str(m.name).to_lower()] = true
			else: online.erase(str(m.name).to_lower())
		"room":
			room = m if str(m.get("code", "")) != "" else {}
		"gift": # the owner opened (or shut) the hidden character for me
			secret = bool(m.get("on", true))
			save()
		"error":
			if str(m.get("code", "")) == "name_taken":
				state = "name_taken"
				_ws.close()
	changed.emit()
	message.emit(m)
