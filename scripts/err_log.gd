extends Logger
## The engine's own error lines, written into the crash trail (scripts/crumbs.gd) as "ERR ...", so a
## model that will not load on the phone says why (the "second generator" crash: on the owner's iPhone
## load("res://assets/chars/gorilla.glb") came back empty, and nothing on the phone said why).
## Installed by the Patch autoload (Godot 4.5's OS.add_logger). No class_name (an update can carry it).
## Called from any thread: Crumbs.err() queues what other threads send and writes it on the main thread.

const Crumbs := preload("res://scripts/crumbs.gd")

func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == ERROR_TYPE_WARNING or error_type == ERROR_TYPE_SHADER: return
	var t := rationale if rationale != "" else code
	Crumbs.err("%s (%s)" % [t.strip_edges(), function])

func _log_message(message: String, error: bool) -> void:
	if error: Crumbs.err(message.strip_edges())
