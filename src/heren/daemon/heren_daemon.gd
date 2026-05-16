extends SceneTree

## Heren Daemon - Orquestador Modular (Godot 4.x)
## Delega operaciones en módulos manteniendo infraestructura centralizada

const DEFAULT_PORT := 49631
const PORT_RANGE := 100
const HEARTBEAT_INTERVAL := 5.0

# ============================================================
# ESTADO COMPARTIDO (inyectado en módulos)
# ============================================================
var _server: TCPServer
var _port: int = 0
var _peers: Dictionary = {}
var _clients: Dictionary = {}
var _scene_cache: Dictionary = {}
var _resource_cache: Dictionary = {}
var _breakpoints: Dictionary = {}
var _watch_list: Dictionary = {}
var _handlers: Dictionary = {}
var _heartbeat_accumulator: float = 0.0
var _inactivity_timer: float = 0.0
const INACTIVITY_TIMEOUT: float = 600.0
var _project_path: String = ""
var _is_ready: bool = false
var _window_check_timer: float = 0.0

# ============================================================
# MÓDULOS
# ============================================================
var _window_mgr = null
var _core_utils = null
var _scene_ops = null
var _resource_ops = null
var _animation_ops = null
var _shader_ops = null
var _debug_ops = null
var _project_ops = null

func _initialize():
	print("[HEREN] === ORQUESTADOR MODULAR v2.0 ===")
	
	# Obtener project path de argumentos
	_project_path = _get_project_path()
	if _project_path == "":
		print("[HEREN] Modo autoload detectado. Daemon inactivo.")
		_is_ready = false
		return
	
	print("[HEREN] Proyecto: ", _project_path)
	
	# Limitar FPS
	Engine.max_fps = 10
	print("[HEREN] FPS limitado a: ", Engine.max_fps)
	
	# Configurar ventana no intrusiva
	_configure_window()
	
	# Inicializar módulos
	_init_modules()
	
	# Registrar handlers
	_register_handlers()
	
	# Iniciar servidor
	if not _start_server():
		push_error("[HEREN] No se pudo iniciar servidor TCP")
		quit(1)
		return
	
	_is_ready = true
	print("[HEREN] Daemon listo en puerto: ", _port)
	print("[HEREN_DAEMON_READY:", _port, "]")

func _configure_window():
	var window_size = Vector2i(240, 150)
	DisplayServer.window_set_size(window_size)
	var screen_size = DisplayServer.screen_get_size()
	DisplayServer.window_set_position(screen_size - window_size - Vector2i(10, 10))
	
	# Calidad de vida: ventana absolutamente no intrusiva
	if DisplayServer.has_feature(DisplayServer.FEATURE_WINDOW_TRANSPARENCY):
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_MOUSE_PASSTHROUGH, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, false)
	
	# FORZAR mouse libre: sobrescribir cualquier config del proyecto que capture mouse
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ProjectSettings.set_setting("display/mouse_cursor/custom_image", "")
	ProjectSettings.set_setting("input_devices/pointing/emulate_mouse_from_touch", false)
	
	print("[HEREN] Ventana configurada: ", window_size, " (no intrusiva)")
	print("[HEREN] Mouse mode: VISIBLE (forzado)")

func _get_project_path() -> String:
	var args = OS.get_cmdline_user_args()
	if args.size() > 0:
		return args[0]
	return ""

# ============================================================
# INICIALIZACIÓN DE MÓDULOS
# ============================================================
func _init_modules():
	print("[HEREN] Inicializando módulos...")
	
	# Core Utils (estático, no necesita instancia)
	_core_utils = preload("heren_core_utils.gd")
	
	# Window Manager
	_window_mgr = preload("heren_window_manager.gd").new()
	_window_mgr.init(self)
	
	# Scene Operations
	_scene_ops = preload("heren_scene_ops.gd").new()
	_scene_ops.init(self)
	_scene_ops._scene_cache = _scene_cache
	_scene_ops._serialize_value_callback = _core_utils.serialize_value
	_scene_ops._deserialize_value_callback = _core_utils.deserialize_value
	_scene_ops._dispatch_callback = _dispatch
	
	# Resource Operations
	_resource_ops = preload("heren_resource_ops.gd").new()
	_resource_ops.init(self)
	_resource_ops._scene_cache = _scene_cache
	_resource_ops._deserialize_value_callback = _core_utils.deserialize_value
	
	# Animation Operations
	_animation_ops = preload("heren_animation_ops.gd").new()
	_animation_ops.init(self)
	
	# Shader Operations
	_shader_ops = preload("heren_shader_ops.gd").new()
	_shader_ops.init(self)
	
	# Debug Operations
	_debug_ops = preload("heren_debug_ops.gd").new()
	_debug_ops.init(self)
	
	# Project Operations
	_project_ops = preload("heren_project_ops.gd").new()
	_project_ops.init(self)
	
	print("[HEREN] 7 módulos inicializados")

# ============================================================
# REGISTRO DE HANDLERS
# ============================================================
func _register_handlers():
	# Handlers básicos (infraestructura)
	_handlers["ping"] = _handle_ping
	_handlers["health"] = _handle_health
	_handlers["quit"] = _handle_quit
	
	# Scene handlers
	_handlers["get_scene_tree"] = _scene_ops.handle_get_scene_tree
	_handlers["save_scene"] = _scene_ops.handle_save_scene
	_handlers["create_scene"] = _scene_ops.handle_create_scene
	_handlers["delete_scene"] = _scene_ops.handle_delete_scene
	_handlers["rename_scene"] = _scene_ops.handle_rename_scene
	_handlers["set_editable_paths"] = _scene_ops.handle_set_editable_paths
	_handlers["load_scene"] = _scene_ops.handle_load_scene
	_handlers["unload_scene"] = _scene_ops.handle_unload_scene
	_handlers["get_loaded_scenes"] = _scene_ops.handle_get_loaded_scenes
	
	# Node handlers
	_handlers["add_node"] = _scene_ops.handle_add_node
	_handlers["remove_node"] = _scene_ops.handle_remove_node
	_handlers["duplicate_node"] = _scene_ops.handle_duplicate_node
	_handlers["rename_node"] = _scene_ops.handle_rename_node
	_handlers["move_node"] = _scene_ops.handle_move_node
	_handlers["set_property"] = _scene_ops.handle_set_property
	_handlers["get_node_properties"] = _scene_ops.handle_get_node_properties
	_handlers["array_append"] = _scene_ops.handle_array_append
	_handlers["array_remove"] = _scene_ops.handle_array_remove
	
	# Signal handlers
	_handlers["set_script"] = _scene_ops.handle_set_script
	_handlers["connect_signal"] = _scene_ops.handle_connect_signal
	_handlers["disconnect_signal"] = _scene_ops.handle_disconnect_signal
	_handlers["list_signals"] = _scene_ops.handle_list_signals
	
	# Batch
	_handlers["batch"] = _scene_ops.handle_batch
	
	# Resource handlers
	_handlers["create_resource"] = _resource_ops.handle_create_resource
	_handlers["read_resource"] = _resource_ops.handle_read_resource
	_handlers["update_resource"] = _resource_ops.handle_update_resource
	_handlers["delete_resource"] = _resource_ops.handle_delete_resource
	_handlers["list_resources"] = _resource_ops.handle_list_resources
	_handlers["update_scene_subresource"] = _resource_ops.handle_update_scene_subresource
	_handlers["add_ext_resource"] = _resource_ops.handle_add_ext_resource
	_handlers["remove_ext_resource"] = _resource_ops.handle_remove_ext_resource
	
	# Script handlers
	_handlers["create_script"] = _resource_ops.handle_create_script
	_handlers["read_script"] = _resource_ops.handle_read_script
	_handlers["edit_script"] = _resource_ops.handle_edit_script
	
	# Animation handlers
	_handlers["create_animation_player"] = _animation_ops.handle_create_animation_player
	_handlers["create_animation"] = _animation_ops.handle_create_animation
	_handlers["add_animation_track"] = _animation_ops.handle_add_animation_track
	_handlers["add_animation_key"] = _animation_ops.handle_add_animation_key
	_handlers["create_state_machine"] = _animation_ops.handle_create_state_machine
	
	# Skeleton handlers
	_handlers["create_skeleton"] = _animation_ops.handle_create_skeleton
	_handlers["add_bone"] = _animation_ops.handle_add_bone
	_handlers["set_bone_rest"] = _animation_ops.handle_set_bone_rest
	_handlers["skin_polygon2d"] = _animation_ops.handle_skin_polygon2d
	_handlers["add_bone_attachment"] = _animation_ops.handle_add_bone_attachment
	
	# Shader handlers
	_handlers["create_shader"] = _shader_ops.handle_create_shader
	_handlers["edit_shader"] = _shader_ops.handle_edit_shader
	_handlers["validate_shader"] = _shader_ops.handle_validate_shader
	_handlers["create_shader_material"] = _shader_ops.handle_create_shader_material
	_handlers["set_shader_uniform"] = _shader_ops.handle_set_shader_uniform
	
	# Debug/Visual handlers
	_handlers["screenshot"] = _debug_ops.handle_screenshot
	_handlers["capture_viewport"] = _debug_ops.handle_capture_viewport
	_handlers["performance_metrics"] = _debug_ops.handle_performance_metrics
	_handlers["inspect_visual"] = _debug_ops.handle_inspect_visual
	_handlers["raycast"] = _debug_ops.handle_raycast
	_handlers["measure"] = _debug_ops.handle_measure
	_handlers["set_breakpoint"] = _debug_ops.handle_set_breakpoint
	_handlers["get_stack_trace"] = _debug_ops.handle_get_stack_trace
	_handlers["watch_variable"] = _debug_ops.handle_watch_variable
	_handlers["get_console_output"] = _debug_ops.handle_get_console_output
	_handlers["run_scene"] = _debug_ops.handle_run_scene
	_handlers["stop_scene"] = _debug_ops.handle_stop_scene
	_handlers["get_editor_errors"] = _debug_ops.handle_get_editor_errors
	_handlers["execute_editor_script"] = _debug_ops.handle_execute_editor_script
	
	# Validate handlers
	_handlers["validate_scene"] = _debug_ops.handle_validate_scene
	_handlers["validate_script"] = _debug_ops.handle_validate_script
	_handlers["validate_node"] = _debug_ops.handle_validate_node
	_handlers["validate_resource"] = _debug_ops.handle_validate_resource
	
	# Project handlers
	_handlers["create_project"] = _project_ops.handle_create_project
	_handlers["set_project_setting"] = _project_ops.handle_set_project_setting
	_handlers["get_project_setting"] = _project_ops.handle_get_project_setting
	_handlers["add_autoload"] = _project_ops.handle_add_autoload
	_handlers["remove_autoload"] = _project_ops.handle_remove_autoload
	_handlers["set_shader_global"] = _project_ops.handle_set_shader_global
	
	# Tilemap handlers
	_handlers["inspect_tileset"] = _project_ops.handle_inspect_tileset
	_handlers["inspect_tilemap"] = _project_ops.handle_inspect_tilemap
	_handlers["set_tilemap_cell"] = _project_ops.handle_set_tilemap_cell
	_handlers["apply_terrain"] = _project_ops.handle_apply_terrain
	_handlers["create_tile_pattern"] = _project_ops.handle_create_tile_pattern
	
	print("[HEREN] ", _handlers.size(), " handlers registrados")

# ============================================================
# INFRAESTRUCTURA (WebSocket, Heartbeat, etc.)
# ============================================================
func _process(delta):
	if not _is_ready:
		return
	
	_process_heartbeat(delta)
	
	# Re-aplicar protección anti-mouse-lock cada 0.5 segundos
	_window_check_timer += delta
	if _window_check_timer >= 0.5:
		_window_check_timer = 0.0
		ensure_mouse_free()
	
	_inactivity_timer += delta
	if _inactivity_timer >= INACTIVITY_TIMEOUT:
		print("[HEREN] Auto-shutdown por inactividad")
		quit()
		return
	
	# Aceptar nuevas conexiones
	if _server and _server.is_connection_available():
		var conn = _server.take_connection()
		if conn:
			var peer = WebSocketPeer.new()
			var err = peer.accept_stream(conn)
			if err == OK:
				var peer_id = conn.get_instance_id()
				_peers[peer_id] = peer
				_clients[peer_id] = {"connected_at": Time.get_unix_time_from_system()}
				print("[HEREN] Cliente conectado: ", peer_id)
			else:
				print("[HEREN] Error aceptando conexion: ", err)
	
	# Procesar peers
	for peer_id in _peers.keys():
		var peer = _peers[peer_id]
		peer.poll()
		
		var state = peer.get_ready_state()
		
		if state == WebSocketPeer.STATE_OPEN:
			while peer.get_available_packet_count() > 0:
				var packet = peer.get_packet()
				var msg = packet.get_string_from_utf8()
				_handle_message(peer_id, peer, msg)
				_inactivity_timer = 0.0
				
		elif state == WebSocketPeer.STATE_CLOSED:
			print("[HEREN] Cliente desconectado: ", peer_id)
			_peers.erase(peer_id)
			_clients.erase(peer_id)

func _start_server() -> bool:
	_server = TCPServer.new()
	for p in range(DEFAULT_PORT, DEFAULT_PORT + PORT_RANGE):
		var err = _server.listen(p, "127.0.0.1")
		if err == OK:
			_port = p
			print("[HEREN] Servidor TCP en 127.0.0.1:", _port)
			return true
		else:
			print("[HEREN] Puerto ", p, " no disponible...")
	return false

func _process_heartbeat(delta):
	_heartbeat_accumulator += delta
	if _heartbeat_accumulator >= HEARTBEAT_INTERVAL:
		_heartbeat_accumulator = 0.0
		_on_heartbeat()

func _on_heartbeat():
	var dead_peers = []
	for peer_id in _peers.keys():
		var peer = _peers[peer_id]
		if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
			peer.send_text(JSON.stringify({"type": "heartbeat", "timestamp": Time.get_unix_time_from_system()}))
		else:
			dead_peers.append(peer_id)
	for peer_id in dead_peers:
		_peers.erase(peer_id)
		_clients.erase(peer_id)

func _handle_message(peer_id: int, peer: WebSocketPeer, msg: String):
	_inactivity_timer = 0.0
	var cmd = JSON.parse_string(msg)
	if not cmd or not cmd is Dictionary:
		_send_error(peer, "invalid_json", "Mensaje JSON invalido")
		return
	
	var method = cmd.get("method", "")
	var params = cmd.get("params", {})
	var request_id = cmd.get("id", "")
	
	print("[HEREN] Comando: ", method, " (id: ", request_id, ")")
	
	var result = _dispatch(method, params)
	result["id"] = request_id
	result["method"] = method
	
	var err = peer.send_text(JSON.stringify(result))
	if err != OK:
		print("[HEREN] Error enviando respuesta: ", err)

func _dispatch(method: String, params: Dictionary) -> Dictionary:
	if not _handlers.has(method):
		return {"success": false, "error": "unknown_method", "message": "Metodo no encontrado: " + method}
	return _handlers[method].call(params)

func _send_error(peer: WebSocketPeer, error_code: String, message: String):
	peer.send_text(JSON.stringify({"success": false, "error": error_code, "message": message}))

# ============================================================
# HANDLERS BÁSICOS
# ============================================================
func _handle_ping(params: Dictionary) -> Dictionary:
	return {"success": true, "pong": true, "version": "2.0-modular", "timestamp": Time.get_unix_time_from_system()}

func _handle_health(params: Dictionary) -> Dictionary:
	var mem = Performance.get_monitor(Performance.MEMORY_STATIC)
	var mem_max = Performance.get_monitor(Performance.MEMORY_STATIC_MAX)
	return {
		"success": true,
		"status": "healthy",
		"project": _project_path,
		"scenes_cached": _scene_cache.size(),
		"resources_cached": _resource_cache.size(),
		"memory_mb": round(mem / 1024 / 1024 * 100) / 100,
		"memory_max_mb": round(mem_max / 1024 / 1024 * 100) / 100,
		"peers_connected": _peers.size(),
		"uptime_seconds": Time.get_ticks_msec() / 1000.0
	}

func _handle_quit(params: Dictionary) -> Dictionary:
	print("[HEREN] Recibido comando quit. Cerrando...")
	for peer_id in _peers.keys():
		_peers[peer_id].close(1000, "Server shutting down")
	for scene_path in _scene_cache.keys():
		var scene = _scene_cache[scene_path]
		if is_instance_valid(scene) and scene is Node:
			scene.queue_free()
	_scene_cache.clear()
	_resource_cache.clear()
	if _server:
		_server.stop()
	call_deferred("_do_quit")
	return {"success": true, "message": "Daemon cerrandose"}

func _do_quit():
	quit(0)

# ============================================================
# PROTECCIÓN ANTI-MOUSE-LOCK
# ============================================================
func ensure_mouse_free():
	"""Fuerza el mouse a estar libre y la ventana sin foco.
	Llama después de operaciones de I/O que puedan dar foco a la ventana."""
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_MOUSE_PASSTHROUGH, true)
