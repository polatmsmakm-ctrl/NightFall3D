extends Node
## Hidden developer tools (autoload "Dev").
## Locked by default: nothing of this exists on a phone that has not unlocked it, and the unlock
## is only ever kept locally in user://dev.cfg. Never relayed, never sent to the server.

signal changed

const PATH := "user://dev.cfg"
const TAPS := 15     # taps needed on the version text
const GAP := 1.0     # seconds: a slower tap restarts the count

const KEY := "4343" # the owner's passkey: fifteen taps open the door, this opens the tools
var unlocked := false
var vanish_tool := false # adds the «Vanish» button to the round (hidden on every other phone)
var esp := false      # see-through outlines of the other players
var speed := 1.0      # 1.0 .. 2.0 movement multiplier
var _taps := 0
var _last := -99.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var c := ConfigFile.new()
	if c.load(PATH) == OK: unlocked = bool(c.get_value("d", "on", false))

## One tap on the version text. Returns true on the tap that should open the tools' page: the
## fifteenth (which asks for the passkey) or any tap once this phone has them.
func tap() -> bool:
	if unlocked: return true
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last > GAP: _taps = 0
	_last = now
	_taps += 1
	if _taps < TAPS: return false
	_taps = 0
	return true

## The passkey. Only the right one unlocks (and it stays on this phone until locked again).
func try_key(code: String) -> bool:
	if code.strip_edges() != KEY: return false
	unlocked = true
	_save()
	changed.emit()
	return true

## Shut the tools again: the next time needs the fifteen taps and the passkey.
func lock() -> void:
	unlocked = false
	esp = false; speed = 1.0; vanish_tool = false
	_save()
	changed.emit()

func _save() -> void:
	var c := ConfigFile.new()
	c.set_value("d", "on", unlocked)
	c.save(PATH)

func set_vanish_tool(on: bool) -> void:
	vanish_tool = on
	changed.emit()

func set_esp(on: bool) -> void:
	esp = on
	changed.emit()

func set_speed(v: float) -> void:
	speed = clampf(v, 1.0, 2.0)
	changed.emit()
