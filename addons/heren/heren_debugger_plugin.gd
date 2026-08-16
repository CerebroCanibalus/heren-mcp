@tool
extends EditorDebuggerPlugin

# Heren MCP v4.5 - Plugin del depurador (EditorDebuggerPlugin).
# Registrado por editor_plugin.gd via add_debugger_plugin().
#
# Qué aporta (API pública + integración interna verificada contra Godot 4.7):
#   1. SESIONES: get_sessions()/get_session(id) (clase documentada) expone
#      estado del depurador: is_active()/is_breaked()/is_debuggable().
#   2. BREAKPOINTS: session.set_breakpoint(path, line, enabled) → mensaje
#      "breakpoint" al juego (mismo code path que el CodeEdit del editor).
#      Se re-sincronizan al conectar el juego (signal `started`).
#   3. CONTROL: session.send_message("break"/"continue"/"next"/"step").
#   4. PROFILER CPU: session.toggle_profiler("servers", ...) → el juego
#      devuelve `servers:profile_frame` + `servers:function_signature`.
#   5. CAPTURA CRUDA: localiza el ScriptEditorDebugger default (tab 0 del
#      dock "Debugger") por árbol y conecta su signal `debug_data`, que
#      emite TODOS los mensajes del protocolo: stack_dump, stack_frame_var(s),
#      error (con stack trace), output, servers:profile_frame...
#      (Los plugins NO reciben estos mensajes via `_capture`: el debugger
#      integrado los consume primero — sed.cpp _parse_message, 2026-08-07.)

var _editor_plugin: EditorPlugin
var _session_ids: Array[int] = []
var _hooked_debuggers: Array = []  # ScriptEditorDebugger ya conectados (multi-sesión)
var _hooked: bool = false
var _hook_retries: int = 0
var _hook_timer: SceneTreeTimer = null

# --- Breakpoints registrados por el agente (key "path:line") -------------
var breakpoints: Dictionary = {}

# --- Estado capturado del protocolo (JSON-friendly) -----------------------
var last_stack: Array = []
var has_stack: bool = false
var stack_breaked: bool = false
var last_vars: Array = []
var vars_pending: bool = false
var last_errors: Array = []
var last_output: Array = []
var last_output_errors: Array = []  # SOLO líneas de error (level==2) del output
var profiler_running: bool = false
var profiler_frames: Array = []
var _sig_map: Dictionary = {}  # sig_id -> "path::function"

const MAX_BUFFER := 200
const HOOK_MAX_RETRIES := 10  # 10s a 1s/retry: el dock se monta rápido; retries reducidos por D3


func setup(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin


# ------------------------------------------------------------- API pública

func session_ids() -> Array[int]:
	return _session_ids


func first_session() -> EditorDebuggerSession:
	var arr := get_sessions()
	if arr.is_empty():
		return null
	return arr[0]


func ensure_hooked() -> void:
	if not _hooked:
		_hook_default_debugger()


func set_breakpoint(path: String, line: int, enabled: bool) -> Dictionary:
	var key := "%s:%d" % [path, line]
	if enabled:
		breakpoints[key] = {"path": path, "line": line, "enabled": true}
	else:
		breakpoints.erase(key)
	var session := first_session()
	if session != null:
		session.set_breakpoint(path, line, enabled)
	return {
		"ok": true,
		"path": path,
		"line": line,
		"enabled": enabled,
		"synced_to_running": session != null,
	}


func list_breakpoints() -> Array:
	var out: Array = []
	for key in breakpoints:
		out.append(breakpoints[key])
	out.sort_custom(func(a, b): return str(a.path) + ":" + str(a.line) < str(b.path) + ":" + str(b.line))
	return out


func clear_all_breakpoints() -> Dictionary:
	var session := first_session()
	for key in breakpoints:
		var bp: Dictionary = breakpoints[key]
		if session != null:
			session.set_breakpoint(bp.path, bp.line, false)
	var count := breakpoints.size()
	breakpoints.clear()
	return {"ok": true, "cleared": count}


func send_control(op: String) -> Dictionary:
	var session := first_session()
	if session == null:
		return {"ok": false, "error": "no debugger session"}
	if not session.is_active():
		return {"ok": false, "error": "no active debug session (run a scene first)"}
	match op:
		"pause":
			if session.is_breaked():
				return {"ok": false, "error": "already breaked"}
			session.send_message("break", [])
		"continue":
			if not session.is_breaked():
				return {"ok": false, "error": "not breaked"}
			session.send_message("continue", [])
		"step_over":
			if not session.is_breaked():
				return {"ok": false, "error": "not breaked"}
			session.send_message("next", [])
		"step_into":
			if not session.is_breaked():
				return {"ok": false, "error": "not breaked"}
			session.send_message("step", [])
		_:
			return {"ok": false, "error": "unknown control op: " + op}
	return {"ok": true, "op": op, "breaked": session.is_breaked()}


func profiler_start(max_funcs: int, include_native: bool) -> Dictionary:
	var session := first_session()
	if session == null:
		return {"ok": false, "error": "no debugger session"}
	_sig_map.clear()
	profiler_frames.clear()
	profiler_running = true
	session.toggle_profiler("servers", true, [max_funcs, include_native])
	return {"ok": true, "profiler": "servers(cpu)", "max_functions": max_funcs, "include_native": include_native}


func profiler_stop() -> Dictionary:
	var session := first_session()
	if session == null:
		return {"ok": false, "error": "no debugger session"}
	profiler_running = false
	session.toggle_profiler("servers", false, [])
	return {"ok": true, "frames_collected": profiler_frames.size()}


func request_frame_vars(frame: int) -> void:
	var session := first_session()
	if session == null:
		return
	last_vars.clear()
	vars_pending = true
	# El juego responde con stack_frame_vars + N× stack_frame_var (protocolo
	# del debugger; el inspector integrado hace lo mismo al seleccionar frame).
	session.send_message("get_stack_frame_vars", [frame])


# ----------------------------------------------------------- señal de sesión

func _setup_session(session_id: int) -> void:
	if session_id in _session_ids:
		return
	_session_ids.append(session_id)
	var session := get_session(session_id)
	if session == null:
		return
	session.started.connect(_on_session_started.bind(session_id))
	session.breaked.connect(_on_session_breaked.bind(session_id))
	session.continued.connect(_on_session_continued.bind(session_id))
	session.stopped.connect(_on_session_stopped.bind(session_id))
	_hook_default_debugger()


func _on_session_started(session_id: int) -> void:
	# El juego acaba de conectar (recibió su PID). Re-enviar breakpoints
	# registrados: `set_breakpoint` enviado antes de correr NO queda en el map
	# del EditorDebuggerNode (solo el CodeEdit lo actualiza) — este re-push
	# garantiza que lleguen al proceso vivo.
	var session := get_session(session_id)
	if session == null:
		return
	for key in breakpoints:
		var bp: Dictionary = breakpoints[key]
		session.set_breakpoint(bp.path, bp.line, bp.enabled)


func _on_session_breaked(_can_debug: bool, _session_id: int) -> void:
	stack_breaked = true


func _on_session_continued(_session_id: int) -> void:
	stack_breaked = false


func _on_session_stopped(_session_id: int) -> void:
	stack_breaked = false
	has_stack = false
	last_vars.clear()


# ---------------------------------------------------- captura ScriptEditorDebugger

func _hook_default_debugger() -> void:
	# Conecta a TODOS los ScriptEditorDebugger del TabContainer del dock
	# "Debugger" (multi-sesión, no solo tab 0). Si el dock aún no está
	# montado, programa reintentos (HOOK_MAX_RETRIES × 1s) — el dock se
	# monta al primer play o al abrir el panel inferior.
	var dbg := _find_default_debugger()
	if dbg == null:
		if _hook_retries < HOOK_MAX_RETRIES:
			_hook_retries += 1
			if _hook_timer == null:
				_hook_timer = _editor_plugin.get_tree().create_timer(1.0)
				_hook_timer.timeout.connect(_on_hook_retry)
		return
	_hooked = true
	for child in dbg.get_children():
		if child.is_class("ScriptEditorDebugger"):
			_hook_one(child)


func _on_hook_retry() -> void:
	_hook_timer = null
	_hook_default_debugger()


func _hook_one(dbg: Node) -> void:
	if dbg in _hooked_debuggers:
		return
	_hooked_debuggers.append(dbg)
	if not dbg.is_connected("debug_data", _on_debug_data):
		dbg.connect("debug_data", _on_debug_data)


func _find_default_debugger() -> Node:
	# El run local usa la primera sesión inactiva del dock "Debugger"
	# (EditorDebuggerNode, tab 0 = get_default_debugger()). Localizarla por
	# árbol: dock class EditorDebuggerNode → TabContainer → hijo.
	if _editor_plugin == null:
		return null
	var root := _editor_plugin.get_editor_interface().get_base_control()
	if root == null:
		return null
	var dock := _find_class(root, "EditorDebuggerNode")
	if dock == null:
		return null
	var tabs: Node = null
	for child in dock.get_children():
		if child.is_class("TabContainer"):
			tabs = child
			break
	if tabs == null or tabs.get_child_count() == 0:
		return null
	return tabs


func _find_class(node: Node, cls: String) -> Node:
	if node.is_class(cls):
		return node
	for child in node.get_children():
		var found := _find_class(child, cls)
		if found:
			return found
	return null


func _find_editor_log_dock(root: Node) -> Node:
	# Buscar el dock "Output" o "Log" en el árbol de nodos del editor.
	# En Godot 4.7 el dock de output suele tener class "EditorOutput" o estar
	# dentro del dock principal "Debugger". Usamos _find_class con nombres
	# probables y fallback a búsqueda por nombre de nodo.
	var probable_classes := ["EditorOutput", "EditorLog", "Output", "Log"]
	for cls in probable_classes:
		var dock := _find_class(root, cls)
		if dock != null:
			return dock
	# Fallback: buscar por nombre de nodo conteniendo "output" o "log"
	for child in root.get_children():
		var name := str(child.get("name", "")).to_lower()
		if name.contains("output") or name.contains("log"):
			return child
	return null


# ----------------------------------------------------------- mensajes crudos

func _on_debug_data(msg: String, data: Array) -> void:
	match msg:
		"stack_dump":
			_store_stack_dump(data)
		"stack_frame_vars":
			vars_pending = true
			last_vars.clear()
		"stack_frame_var":
			_append_frame_var(data)
		"servers:profile_frame":
			_store_profile_frame(data)
		"servers:function_signature":
			_store_signature(data)
		"error":
			_store_error(data)
		"output":
			_store_output(data)


func _store_stack_dump(data: Array) -> void:
	last_stack.clear()
	has_stack = false
	if data.is_empty():
		return
	var total: int = int(data[0])
	if total <= 0:
		return
	var count: int = total / 3
	for i in count:
		last_stack.append({
			"frame": i,
			"file": data[1 + i * 3],
			"function": data[3 + i * 3],
			"line": int(data[2 + i * 3]),
		})
	has_stack = not last_stack.is_empty()


func _append_frame_var(data: Array) -> void:
	# ScriptStackVariable: [name, type(0=locals,1=members), var_type, value, type_hint]
	if data.size() < 5:
		return
	var scope := "locals"
	if int(data[1]) == 1:
		scope = "members"
	last_vars.append({
		"name": str(data[0]),
		"scope": scope,
		"type": int(data[2]),
		"value": _jsonable(data[3]),
		"type_hint": str(data[4]) if data[4] != null else "",
	})


func _store_signature(data: Array) -> void:
	# ScriptFunctionSignature: [name, id]
	if data.size() < 2:
		return
	_sig_map[int(data[1])] = data[0]


func _store_profile_frame(data: Array) -> void:
	# ServersProfilerFrame: [frame_number, frame_time, process_time, physics_time,
	#   physics_frame_time, script_time, servers_size, (name, sub*2, ...)*,
	#   script_functions*5 (sig_id, call_count, self, total, internal)]
	if data.size() < 7:
		return
	var frame := {
		"frame_number": int(data[0]),
		"frame_time": float(data[1]),
		"process_time": float(data[2]),
		"physics_time": float(data[3]),
		"physics_frame_time": float(data[4]),
		"script_time": float(data[5]),
	}
	var idx := 7
	var servers_size: int = int(data[6])
	var server_count := 0
	for _s in servers_size:
		server_count += 1
		idx += 1  # name
		if idx >= data.size():
			break
		var sub_size: int = int(data[idx])
		idx += 1 + sub_size  # sub entries (name, time) pairs
	frame["servers"] = server_count
	if idx >= data.size():
		profiler_frames.append(frame)
		return
	var funcs_total: int = int(data[idx])
	idx += 1
	var funcs: Array = []
	var func_count: int = funcs_total / 5
	for _f in func_count:
		if idx + 4 >= data.size():
			break
		var sig_id := int(data[idx])
		funcs.append({
			"signature": str(_sig_map.get(sig_id, "sig_" + str(sig_id))),
			"calls": int(data[idx + 1]),
			"self": float(data[idx + 2]),
			"total": float(data[idx + 3]),
			"internal": float(data[idx + 4]),
		})
		idx += 5
	frame["funcs"] = funcs
	profiler_frames.append(frame)
	if profiler_frames.size() > MAX_BUFFER:
		profiler_frames = profiler_frames.slice(profiler_frames.size() - MAX_BUFFER)


func _store_error(data: Array) -> void:
	# OutputError: [hr,min,sec,msec, source_file, source_func, source_line,
	#   error, error_descr, warning, stack_size*3, (file,func,line)*]
	if data.size() < 11:
		return
	var stack: Array = []
	var total: int = int(data[10])
	var count: int = total / 3
	for i in count:
		stack.append({
			"file": str(data[11 + i * 3]),
			"function": str(data[12 + i * 3]),
			"line": int(data[13 + i * 3]),
		})
	last_errors.append({
		"time": "%02d:%02d:%02d" % [int(data[0]), int(data[1]), int(data[2])],
		"file": str(data[4]),
		"function": str(data[5]),
		"line": int(data[6]),
		"error": str(data[7]),
		"descr": str(data[8]),
		"warning": bool(data[9]),
		"stack": stack,
	})
	if last_errors.size() > MAX_BUFFER:
		last_errors.pop_front()


func _store_output(data: Array) -> void:
	if data.size() < 2:
		return
	var msgs = data[0]
	var types = data[1]
	if not (msgs is PackedStringArray) or not (types is PackedInt32Array):
		return
	for i in msgs.size():
		var text: String = msgs[i]
		var level: int = int(types[i])
		# El formato `E hh:mm:ss:mmm ...` del panel Output del editor viene del
		# RemoteDebugger con MESSAGE_TYPE_ERROR (2) — son los errores de runtime
		# del juego con stack completo. MESSAGE_TYPE_LOG=0, LOG_RICH=1, ERROR=2.
		var entry := {"text": text, "level": level}
		last_output.append(entry)
		if level == 2:
			last_output_errors.append(entry)
	if last_output.size() > MAX_BUFFER:
		last_output = last_output.slice(last_output.size() - MAX_BUFFER)
	if last_output_errors.size() > MAX_BUFFER:
		last_output_errors = last_output_errors.slice(last_output_errors.size() - MAX_BUFFER)


func _jsonable(v) -> Variant:
	if v is Array:
		var out: Array = []
		for item in v:
			out.append(_jsonable(item))
		return out
	if v is Dictionary:
		var out: Dictionary = {}
		for k in v:
			out[k] = _jsonable(v[k])
		return out
	if v is EncodedObjectAsID:
		return {"__object_id": (v as EncodedObjectAsID).object_id}
	if v is Object:
		return {"__object": v.get_class(), "id": v.get_instance_id()}
	if v is StringName or v is NodePath:
		return str(v)
	if v is Vector2 or v is Vector3 or v is Vector2i or v is Vector3i or v is Color \
			or v is Rect2 or v is Rect2i or v is Transform2D or v is Transform3D or v is Plane \
			or v is Quaternion or v is AABB:
		return str(v)
	return v
