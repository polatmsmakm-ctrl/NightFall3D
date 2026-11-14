class_name NFHaptics
extends RefCounted
## The phone's vibration motor. Every buzz in the game goes through here so one switch
## ("الاهتزاز" in settings, kept by `Aud.haptics`) turns the lot off.
##
## Godot drives this with Input.vibrate_handheld(duration_ms, amplitude). On iOS that reaches
## Core Haptics, so duration and strength are honoured on an iPhone; on a desktop build it does
## nothing at all, which is why none of this can be checked without the device.

## kind -> [milliseconds, strength 0..1, how long before the same kind may fire again]
const KINDS := {
	"beat": [18, 0.25, 0.12],    # one heartbeat while the killer is near
	"hit": [240, 1.0, 0.25],     # you were struck
	"grab": [320, 1.0, 0.4],     # he picked you up
	"hook": [120, 0.7, 0.3],     # someone went on a hook
	"escape": [90, 0.5, 0.3],    # you got out
	"rumble": [90, 0.45, 0.25],  # the moon coming down
	"impact": [600, 1.0, 1.0],   # the moon landing
	"tick": [14, 0.2, 0.1],      # small confirmation
}

static var _next := {}

static func enabled() -> bool:
	return Aud != null and Aud.haptics

## Buzz, unless this kind just fired or the switch is off.
static func pulse(kind: String) -> void:
	if not enabled(): return
	var k: Array = KINDS.get(kind, KINDS.tick)
	var now := Time.get_ticks_msec() / 1000.0
	if now < float(_next.get(kind, -1.0)): return
	_next[kind] = now + float(k[2])
	Input.vibrate_handheld(int(k[0]), float(k[1]))

## A pulse whose strength follows a 0..1 value (the moon getting closer, the killer getting nearer).
static func pulse_scaled(kind: String, amount: float) -> void:
	if not enabled(): return
	var k: Array = KINDS.get(kind, KINDS.tick)
	var now := Time.get_ticks_msec() / 1000.0
	if now < float(_next.get(kind, -1.0)): return
	var f := clampf(amount, 0.0, 1.0)
	_next[kind] = now + float(k[2])
	Input.vibrate_handheld(int(k[0] * (0.5 + 0.5 * f)), float(k[1]) * (0.35 + 0.65 * f))
