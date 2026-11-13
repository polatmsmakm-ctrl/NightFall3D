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
	var env_url := OS.get_environment("NF_URL")
	if env_url != "": url = env_url

func save() -> void:
	var c := ConfigFile.new()
	c.set_value("p", "name", username)
	c.set_value("p", "friends", friends)
	c.set_value("p", "url", url)
	c.save(PATH)

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
				send({"t": "hello", "name": username, "friends": friends})
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
		"presence":
			if m.get("online", false): online[str(m.name).to_lower()] = true
			else: online.erase(str(m.name).to_lower())
		"room":
			room = m if str(m.get("code", "")) != "" else {}
		"error":
			if str(m.get("code", "")) == "name_taken":
				state = "name_taken"
				_ws.close()
	changed.emit()
	message.emit(m)
