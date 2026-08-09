@tool
extends Node

# Heren MCP v4.5 - Debug handlers.
# Control del editor real (ADR-002) + depurador real (EditorDebuggerSession
# vía heren_debugger_plugin.gd, registrado con add_debugger_plugin()).
#
# Actions:
#   status              -> sesiones del depurador (active/breaked/debuggable),
#                          is_playing, breakpoints, profiler state
#   breakpoint          -> op=set|clear|list|clear_all (path, line, enabled)
#   control             -> op=pause|continue|step_over|step_into
#   stack               -> rastreo de pila cuando el juego está breaked
#   vars                -> variables del frame (coroutine: pide y espera)
#   profiler            -> op=start|stop|status|get|clear (CPU profiler)
#   run_scene           -> EditorInterface.play_main_scene / play_custom_scene
#   stop_scene          -> EditorInterface.stop_playing_scene
#   is_playing          -> EditorInterface.is_playing_scene
#   get_editor_errors   -> errores de runtime capturados del debugger (con stack)
#
# Limitación documentada (verificado contra source Godot 4.7, 2026-08-07):
#   - El stack/vars/errores del juego pausado NO son accesibles vía la API
#     pública de EditorDebuggerPlugin._capture (los mensajes sin ":" como
#     stack_dump/error los consume el ScriptEditorDebugger integrado primero;
#     sed.cpp _parse_message). Se resuelve conectando al signal `debug_data`
#     del ScriptEditorDebugger default (tab 0 del dock Debugger).
#   - La evaluación de expresiones (evaluate) devuelve evaluation_return al
#     integrado; no capturable → no expuesta.

var _editor_plugin: EditorPlugin
var _dbg_plugin: EditorDebuggerPlugin


func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin


func set_debugger_plugin(plugin: EditorDebuggerPlugin) -> void:
	_dbg_plugin = plugin
	if _dbg_plugin:
		_dbg_plugin.ensure_hooked()


func _editor_interface() -> EditorInterface:
	if _editor_plugin == null:
		return null
	return _editor_plugin.get_editor_interface()


# ---------------------------------------------------------------- handlers

func handle_status(args: Dictionary) -> Dictionary:
	var ei := _editor_interface()
	var sessions: Array = []
	if _dbg_plugin:
		_dbg_plugin.ensure_hooked()
		for i in _dbg_plugin.session_ids():
			var session := _dbg_plugin.get_session(i)
			if session == null:
				continue
			sessions.append({
				"id": i,
				"active": session.is_active(),
				"breaked": session.is_breaked(),
				"debuggable": session.is_debuggable(),
			})
	return {
		"ok": true,
		"is_playing": ei.is_playing_scene() if ei else false,
		"sessions": sessions,
		"breaked": _dbg_plugin.stack_breaked if _dbg_plugin else false,
		"stack_available": (_dbg_plugin.has_stack and _dbg_plugin.stack_breaked) if _dbg_plugin else false,
		"breakpoints": _dbg_plugin.list_breakpoints() if _dbg_plugin else [],
		"profiler_running": _dbg_plugin.profiler_running if _dbg_plugin else false,
		"profiler_frames": _dbg_plugin.profiler_frames.size() if _dbg_plugin else 0,
		"last_error_count": _dbg_plugin.last_errors.size() if _dbg_plugin else 0,
	}


func handle_breakpoint(args: Dictionary) -> Dictionary:
	if _dbg_plugin == null:
		return {"ok": false, "error": "debugger plugin not registered"}
	var op := str(args.get("op", "set"))
	match op:
		"set":
			var path := str(args.get("path", ""))
			var line := int(args.get("line", -1))
			if path == "" or line < 0:
				return {"ok": false, "error": "path and line required"}
			var enabled: bool = bool(args.get("enabled", true))
			return _dbg_plugin.set_breakpoint(path, line, enabled)
		"clear":
			var path := str(args.get("path", ""))
			var line := int(args.get("line", -1))
			if path == "" or line < 0:
				return {"ok": false, "error": "path and line required"}
			return _dbg_plugin.set_breakpoint(path, line, false)
		"list":
			return {"ok": true, "breakpoints": _dbg_plugin.list_breakpoints()}
		"clear_all":
			return _dbg_plugin.clear_all_breakpoints()
		_:
			return {"ok": false, "error": "unknown op: " + op}


func handle_control(args: Dictionary) -> Dictionary:
	if _dbg_plugin == null:
		return {"ok": false, "error": "debugger plugin not registered"}
	var op := str(args.get("op", ""))
	if op == "":
		return {"ok": false, "error": "op required (pause|continue|step_over|step_into)"}
	return _dbg_plugin.send_control(op)


func handle_stack(args: Dictionary) -> Dictionary:
	if _dbg_plugin == null:
		return {"ok": false, "error": "debugger plugin not registered"}
	_dbg_plugin.ensure_hooked()
	if not _dbg_plugin.stack_breaked:
		return {"ok": false, "error": "not breaked — run the scene, pause or hit a breakpoint first"}
	if not _dbg_plugin.has_stack:
		return {"ok": false, "error": "no stack dump captured"}
	return {"ok": true, "frames": _dbg_plugin.last_stack}


func handle_vars(args: Dictionary) -> Dictionary:
	# Coroutine: pide las variables del frame al juego y espera la respuesta.
	if _dbg_plugin == null:
		return {"ok": false, "error": "debugger plugin not registered"}
	if not _dbg_plugin.stack_breaked:
		return {"ok": false, "error": "not breaked — pause or hit a breakpoint first"}
	var frame := int(args.get("frame", 0))
	_dbg_plugin.request_frame_vars(frame)
	await get_tree().create_timer(0.3).timeout
	return {"ok": true, "frame": frame, "vars": _dbg_plugin.last_vars}


func handle_profiler(args: Dictionary) -> Dictionary:
	if _dbg_plugin == null:
		return {"ok": false, "error": "debugger plugin not registered"}
	var op := str(args.get("op", "status"))
	match op:
		"start":
			var max_funcs := int(args.get("max_functions", 128))
			var include_native: bool = bool(args.get("include_native", true))
			return _dbg_plugin.profiler_start(max_funcs, include_native)
		"stop":
			return _dbg_plugin.profiler_stop()
		"status":
			return {
				"ok": true,
				"profiler_running": _dbg_plugin.profiler_running,
				"frames_collected": _dbg_plugin.profiler_frames.size(),
			}
		"get":
			var limit := int(args.get("limit", 0))
			var frames: Array = _dbg_plugin.profiler_frames
			if limit > 0 and frames.size() > limit:
				frames = frames.slice(frames.size() - limit)
			return {"ok": true, "profiler_running": _dbg_plugin.profiler_running, "frames": frames}
		"clear":
			_dbg_plugin.profiler_frames.clear()
			return {"ok": true, "frames_collected": 0}
		_:
			return {"ok": false, "error": "unknown op: " + op}


func handle_run_scene(args: Dictionary) -> Dictionary:
	var ei := _editor_interface()
	if ei == null:
		return {"ok": false, "error": "no editor interface"}

	var scene_path: String = str(args.get("scene_path", ""))
	if scene_path != "":
		if not ResourceLoader.exists(scene_path):
			return {"ok": false, "error": "scene_not_found: " + scene_path}
		ei.play_custom_scene(scene_path)
		return {"ok": true, "running": scene_path, "custom": true}

	ei.play_main_scene()
	return {"ok": true, "running": "main_scene", "custom": false}


func handle_stop_scene(args: Dictionary) -> Dictionary:
	var ei := _editor_interface()
	if ei == null:
		return {"ok": false, "error": "no editor interface"}
	if not ei.is_playing_scene():
		return {"ok": true, "was_playing": false}
	ei.stop_playing_scene()
	return {"ok": true, "was_playing": true}


func handle_is_playing(args: Dictionary) -> Dictionary:
	var ei := _editor_interface()
	if ei == null:
		return {"ok": false, "error": "no editor interface"}
	return {"ok": true, "is_playing": ei.is_playing_scene()}


func handle_get_editor_errors(args: Dictionary) -> Dictionary:
	# v4.5: errores de RUNTIME capturados del debugger (mensaje `error` con
	# stack trace + `output` con el texto formateado del panel Output).
	# Los errores del editor en reposo (sin juego) no son accesibles por API
	# pública — ver nota en get_editor_errors de v4.
	if _dbg_plugin == null:
		return {
			"ok": true,
			"note": "editor errors not exposed via public API; see Output panel",
			"errors": [],
			"count": 0,
		}
	_dbg_plugin.ensure_hooked()
	var limit := int(args.get("limit", 50))
	var errors: Array = _dbg_plugin.last_errors
	if errors.size() > limit:
		errors = errors.slice(errors.size() - limit)
	# output_errors: texto formateado `E hh:mm:ss:mmm file:line @ func(): msg`
	# + stack — EXACTAMENTE lo que muestra el panel Output del editor.
	var output_errors: Array = _dbg_plugin.last_output_errors
	if output_errors.size() > limit:
		output_errors = output_errors.slice(output_errors.size() - limit)
	return {
		"ok": true,
		"errors": errors,
		"count": _dbg_plugin.last_errors.size(),
		"output_errors": output_errors,
		"output_count": _dbg_plugin.last_output_errors.size(),
		"hook_ok": _dbg_plugin._hooked,
		"note": "errores de runtime del depurador: errors = estructurados (mensaje error), output_errors = texto del panel Output (mensaje output, level=2). Los del editor en reposo no son accesibles por API pública.",
	}


func handle_output(args: Dictionary) -> Dictionary:
	# v4.5: salida del panel Output del juego en ejecución (print + errores
	# formateados `E hh:mm:ss:mmm`). filter: all|error (default error).
	if _dbg_plugin == null:
		return {"ok": false, "error": "debugger plugin not registered"}
	_dbg_plugin.ensure_hooked()
	var filter := str(args.get("filter", "error"))
	var limit := int(args.get("limit", 100))
	var lines: Array = []
	if filter == "all":
		lines = _dbg_plugin.last_output
	else:
		lines = _dbg_plugin.last_output_errors
	if lines.size() > limit:
		lines = lines.slice(lines.size() - limit)
	return {
		"ok": true,
		"filter": filter,
		"lines": lines,
		"count": lines.size(),
		"hook_ok": _dbg_plugin._hooked,
	}
