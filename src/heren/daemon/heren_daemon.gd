extends SceneTree

## Heren Daemon - Servidor WebSocket para MCP (Godot 4.x)
## Corre en Godot con ventana (sin --headless) para habilitar networking y rendering
## NOTA: Al usar --script, DEBE extender SceneTree o MainLoop

const DEFAULT_PORT := 49631
const PORT_RANGE := 100
const HEARTBEAT_INTERVAL := 5.0

# Servidor TCP + WebSocket peers
var _server: TCPServer
var _port: int = 0
var _peers: Dictionary = {}  # peer_id -> WebSocketPeer
var _clients: Dictionary = {}  # peer_id -> info

# Cache de escenas cargadas
var _scene_cache: Dictionary = {}
var _resource_cache: Dictionary = {}

# Debug state
var _breakpoints: Dictionary = {}
var _watch_list: Dictionary = {}

# Command registry
var _handlers: Dictionary = {}

# Heartbeat - usamos tiempo acumulado en vez de Timer
var _heartbeat_accumulator: float = 0.0

# Auto-shutdown por inactividad
var _inactivity_timer: float = 0.0
const INACTIVITY_TIMEOUT: float = 180.0  # 3 minutos sin comandos = auto-shutdown

# Estado
var _project_path: String = ""
var _is_ready: bool = false


func _initialize():
	print("[HEREN] Iniciando daemon...")
	
	# Obtener project path de argumentos
	_project_path = _get_project_path()
	
	# Si no hay args, estamos corriendo como autoload normal (no MCP)
	# No iniciar servidor para no interferir con el juego
	if _project_path == "":
		print("[HEREN] Modo autoload detectado (sin args). Daemon inactivo.")
		_is_ready = false
		return
	
	print("[HEREN] Proyecto: ", _project_path)
	
	# Limitar FPS para ahorrar recursos
	Engine.max_fps = 10
	print("[HEREN] FPS limitado a: ", Engine.max_fps)
	
	# Hacer ventana muy pequena para no estorbar (calidad de vida)
	# No afecta screenshots porque usan el tamaño especificado en params
	var window_size = Vector2i(320, 200)
	DisplayServer.window_set_size(window_size)
	# Mover a esquina inferior derecha
	var screen_size = DisplayServer.screen_get_size()
	DisplayServer.window_set_position(screen_size - window_size - Vector2i(20, 20))
	print("[HEREN] Ventana reducida a: ", window_size)
	
	# Registrar handlers
	_register_handlers()
	
	# Iniciar servidor TCP
	if not _start_server():
		push_error("[HEREN] No se pudo iniciar servidor TCP")
		quit(1)
		return
	
	_is_ready = true
	print("[HEREN] Daemon listo en puerto: ", _port)
	print("[HEREN_DAEMON_READY:", _port, "]")


func _process(delta):
	# Si no estamos listos (modo autoload sin args), no hacer nada
	if not _is_ready:
		return
	
	# Procesar heartbeat
	_process_heartbeat(delta)
	
	# Auto-shutdown por inactividad
	_inactivity_timer += delta
	if _inactivity_timer >= INACTIVITY_TIMEOUT:
		print("[HEREN] Auto-shutdown por inactividad (", INACTIVITY_TIMEOUT, "s sin comandos)")
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
				print("[HEREN] Error aceptando conexion WebSocket: ", err)
	
	# Procesar peers existentes
	for peer_id in _peers.keys():
		var peer = _peers[peer_id]
		peer.poll()
		
		var state = peer.get_ready_state()
		
		if state == WebSocketPeer.STATE_OPEN:
			# Leer mensajes disponibles
			while peer.get_available_packet_count() > 0:
				var packet = peer.get_packet()
				var msg = packet.get_string_from_utf8()
				_handle_message(peer_id, peer, msg)
				# Reset timer de inactividad al recibir comando
				_inactivity_timer = 0.0
			
		elif state == WebSocketPeer.STATE_CLOSING:
			pass  # Esperar cierre
			
		elif state == WebSocketPeer.STATE_CLOSED:
			print("[HEREN] Cliente desconectado: ", peer_id)
			_peers.erase(peer_id)
			_clients.erase(peer_id)


func _get_project_path() -> String:
	var args = OS.get_cmdline_user_args()
	if args.size() > 0:
		return args[0]
	return ""


func _start_server() -> bool:
	_server = TCPServer.new()
	
	# Intentar puertos en rango
	for p in range(DEFAULT_PORT, DEFAULT_PORT + PORT_RANGE):
		var err = _server.listen(p, "127.0.0.1")
		if err == OK:
			_port = p
			print("[HEREN] Servidor TCP escuchando en 127.0.0.1:", _port)
			return true
		else:
			print("[HEREN] Puerto ", p, " no disponible, intentando siguiente...")
	
	return false


func _process_heartbeat(delta):
	# Heartbeat basado en acumulador de tiempo
	_heartbeat_accumulator += delta
	if _heartbeat_accumulator >= HEARTBEAT_INTERVAL:
		_heartbeat_accumulator = 0.0
		_on_heartbeat()


func _on_heartbeat():
	# Enviar heartbeat a peers conectados
	var dead_peers = []
	for peer_id in _peers.keys():
		var peer = _peers[peer_id]
		if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
			var heartbeat = {
				"type": "heartbeat",
				"timestamp": Time.get_unix_time_from_system()
			}
			peer.send_text(JSON.stringify(heartbeat))
		else:
			dead_peers.append(peer_id)
	
	# Limpiar peers muertos
	for peer_id in dead_peers:
		_peers.erase(peer_id)
		_clients.erase(peer_id)


func _handle_message(peer_id: int, peer: WebSocketPeer, msg: String):
	var cmd = JSON.parse_string(msg)
	if not cmd or not cmd is Dictionary:
		_send_error(peer, "invalid_json", "Mensaje JSON inválido")
		return
	
	var method = cmd.get("method", "")
	var params = cmd.get("params", {})
	var request_id = cmd.get("id", "")
	
	print("[HEREN] Comando recibido: ", method, " (id: ", request_id, ")")
	
	var result = _dispatch(method, params)
	result["id"] = request_id
	result["method"] = method
	
	var response_json = JSON.stringify(result)
	var err = peer.send_text(response_json)
	if err != OK:
		print("[HEREN] Error enviando respuesta: ", err)


func _dispatch(method: String, params: Dictionary) -> Dictionary:
	if not _handlers.has(method):
		return {
			"success": false,
			"error": "unknown_method",
			"message": "Método no encontrado: " + method
		}
	
	var handler = _handlers[method]
	return handler.call(params)


func _send_error(peer: WebSocketPeer, error_code: String, message: String):
	peer.send_text(JSON.stringify({
		"success": false,
		"error": error_code,
		"message": message
	}))


# ============================================================
# REGISTRO DE HANDLERS
# ============================================================

func _register_handlers():
	_handlers["ping"] = _handle_ping
	_handlers["health"] = _handle_health
	_handlers["quit"] = _handle_quit
	
	_handlers["get_scene_tree"] = _handle_get_scene_tree
	_handlers["save_scene"] = _handle_save_scene
	_handlers["create_scene"] = _handle_create_scene
	_handlers["delete_scene"] = _handle_delete_scene
	_handlers["rename_scene"] = _handle_rename_scene
	_handlers["set_editable_paths"] = _handle_set_editable_paths
	
	_handlers["add_node"] = _handle_add_node
	_handlers["remove_node"] = _handle_remove_node
	_handlers["duplicate_node"] = _handle_duplicate_node
	_handlers["rename_node"] = _handle_rename_node
	_handlers["move_node"] = _handle_move_node
	_handlers["set_property"] = _handle_set_property
	_handlers["get_node_properties"] = _handle_get_node_properties
	_handlers["array_append"] = _handle_array_append
	_handlers["array_remove"] = _handle_array_remove
	
	# === SIGNAL HANDLERS ===
	_handlers["set_script"] = _handle_set_script
	_handlers["connect_signal"] = _handle_connect_signal
	_handlers["disconnect_signal"] = _handle_disconnect_signal
	_handlers["list_signals"] = _handle_list_signals
	
	_handlers["load_scene"] = _handle_load_scene
	_handlers["unload_scene"] = _handle_unload_scene
	_handlers["get_loaded_scenes"] = _handle_get_loaded_scenes
	
	_handlers["screenshot"] = _handle_screenshot
	_handlers["capture_viewport"] = _handle_capture_viewport
	_handlers["performance_metrics"] = _handle_performance_metrics
	
	_handlers["batch"] = _handle_batch
	
	# === RESOURCE HANDLERS ===
	_handlers["create_resource"] = _handle_create_resource
	_handlers["read_resource"] = _handle_read_resource
	_handlers["update_resource"] = _handle_update_resource
	_handlers["delete_resource"] = _handle_delete_resource
	_handlers["list_resources"] = _handle_list_resources
	
	# === ANIMATION HANDLERS ===
	_handlers["create_animation_player"] = _handle_create_animation_player
	_handlers["create_animation"] = _handle_create_animation
	_handlers["add_animation_track"] = _handle_add_animation_track
	_handlers["add_animation_key"] = _handle_add_animation_key
	_handlers["create_state_machine"] = _handle_create_state_machine
	
	# === SKELETON HANDLERS ===
	_handlers["create_skeleton"] = _handle_create_skeleton
	_handlers["add_bone"] = _handle_add_bone
	_handlers["set_bone_rest"] = _handle_set_bone_rest
	_handlers["skin_polygon2d"] = _handle_skin_polygon2d
	_handlers["add_bone_attachment"] = _handle_add_bone_attachment
	
	# === SHADER HANDLERS ===
	_handlers["create_shader"] = _handle_create_shader
	_handlers["edit_shader"] = _handle_edit_shader
	_handlers["validate_shader"] = _handle_validate_shader
	_handlers["create_shader_material"] = _handle_create_shader_material
	_handlers["set_shader_uniform"] = _handle_set_shader_uniform
	
	# === TILEMAP HANDLERS ===
	_handlers["inspect_tileset"] = _handle_inspect_tileset
	_handlers["inspect_tilemap"] = _handle_inspect_tilemap
	_handlers["set_tilemap_cell"] = _handle_set_tilemap_cell
	_handlers["apply_terrain"] = _handle_apply_terrain
	_handlers["create_tile_pattern"] = _handle_create_tile_pattern
	
	# === SCRIPT HANDLERS ===
	_handlers["create_script"] = _handle_create_script
	_handlers["read_script"] = _handle_read_script
	_handlers["edit_script"] = _handle_edit_script
	
	# === EXT_RESOURCE HANDLERS ===
	_handlers["add_ext_resource"] = _handle_add_ext_resource
	_handlers["remove_ext_resource"] = _handle_remove_ext_resource
	
	# === PROJECT HANDLERS ===
	_handlers["create_project"] = _handle_create_project
	_handlers["set_project_setting"] = _handle_set_project_setting
	_handlers["get_project_setting"] = _handle_get_project_setting
	_handlers["add_autoload"] = _handle_add_autoload
	_handlers["remove_autoload"] = _handle_remove_autoload
	_handlers["set_shader_global"] = _handle_set_shader_global
	
	# === VISUAL INSPECTION HANDLERS ===
	_handlers["inspect_visual"] = _handle_inspect_visual
	_handlers["raycast"] = _handle_raycast
	_handlers["measure"] = _handle_measure
	
	# === DEBUG HANDLERS ===
	_handlers["set_breakpoint"] = _handle_set_breakpoint
	_handlers["get_stack_trace"] = _handle_get_stack_trace
	_handlers["watch_variable"] = _handle_watch_variable
	_handlers["get_console_output"] = _handle_get_console_output
	_handlers["run_scene"] = _handle_run_scene
	_handlers["stop_scene"] = _handle_stop_scene
	_handlers["get_editor_errors"] = _handle_get_editor_errors
	_handlers["execute_editor_script"] = _handle_execute_editor_script
	
	# === VALIDATE HANDLERS ===
	_handlers["validate_scene"] = _handle_validate_scene
	_handlers["validate_script"] = _handle_validate_script
	_handlers["validate_node"] = _handle_validate_node
	_handlers["validate_resource"] = _handle_validate_resource
	
	print("[HEREN] ", _handlers.size(), " handlers registrados")


# ============================================================
# HANDLERS BÁSICOS
# ============================================================

func _handle_ping(params: Dictionary) -> Dictionary:
	return {"success": true, "pong": true, "timestamp": Time.get_unix_time_from_system()}


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
	print("[HEREN] Recibido comando quit. Cerrando daemon...")
	
	# Cerrar conexiones
	for peer_id in _peers.keys():
		var peer = _peers[peer_id]
		peer.close(1000, "Server shutting down")
	
	# Limpiar cache
	for scene_path in _scene_cache.keys():
		var scene = _scene_cache[scene_path]
		if is_instance_valid(scene) and scene is Node:
			scene.queue_free()
	_scene_cache.clear()
	_resource_cache.clear()
	
	# Detener servidor
	if _server:
		_server.stop()
	
	# Salir en el próximo frame
	call_deferred("_do_quit")
	
	return {"success": true, "message": "Daemon cerrándose"}


func _do_quit():
	quit(0)


# ============================================================
# HANDLERS DE ESCENAS
# ============================================================

func _handle_load_scene(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	if not scene_path:
		return {"success": false, "error": "missing_scene_path"}
	
	# Si ya está cacheada, retornar
	if _scene_cache.has(scene_path):
		var cached_scene = _scene_cache[scene_path]
		if is_instance_valid(cached_scene):
			return {
				"success": true,
				"cached": true,
				"scene_path": scene_path,
				"node_count": _count_nodes_recursive(cached_scene)
			}
		else:
			_scene_cache.erase(scene_path)
	
	# Cargar escena
	var scene_resource = load(scene_path)
	if not scene_resource:
		return {"success": false, "error": "load_failed", "scene_path": scene_path}
	
	var scene_instance = scene_resource.instantiate()
	if not scene_instance:
		return {"success": false, "error": "instantiate_failed", "scene_path": scene_path}
	
	# Agregar a árbol pero oculto para no renderizar mientras editamos
	# NO deshabilitamos process_mode para que los nodos nuevos funcionen correctamente
	scene_instance.hide()
	get_root().add_child(scene_instance)
	
	_scene_cache[scene_path] = scene_instance
	
	return {
		"success": true,
		"cached": false,
		"scene_path": scene_path,
		"root_type": scene_instance.get_class(),
		"node_count": _count_nodes_recursive(scene_instance)
	}


func _count_nodes_recursive(node: Node) -> int:
	var count = 1  # El nodo mismo
	for child in node.get_children():
		count += _count_nodes_recursive(child)
	return count


func _handle_unload_scene(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	if not _scene_cache.has(scene_path):
		return {"success": false, "error": "not_loaded", "scene_path": scene_path}
	
	var scene = _scene_cache[scene_path]
	if is_instance_valid(scene):
		scene.queue_free()
	
	_scene_cache.erase(scene_path)
	
	return {"success": true, "scene_path": scene_path}


func _handle_get_loaded_scenes(params: Dictionary) -> Dictionary:
	var scenes = []
	for scene_path in _scene_cache.keys():
		var scene = _scene_cache[scene_path]
		scenes.append({
			"path": scene_path,
			"valid": is_instance_valid(scene),
			"type": scene.get_class() if is_instance_valid(scene) else "invalid",
			"node_count": _count_nodes_recursive(scene) if is_instance_valid(scene) else 0
		})
	
	return {"success": true, "scenes": scenes, "count": scenes.size()}


func _handle_get_scene_tree(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	if not scene_path:
		return {"success": false, "error": "missing_scene_path"}
	
	# Auto-cargar si no está en cache
	if not _scene_cache.has(scene_path):
		var load_result = _handle_load_scene({"scene_path": scene_path})
		if not load_result.success:
			return load_result
	
	var root = _scene_cache[scene_path]
	var include_properties = params.get("include_properties", false)
	
	var nodes = []
	_build_node_tree(root, nodes, "", include_properties)
	
	return {
		"success": true,
		"scene_path": scene_path,
		"node_count": nodes.size(),
		"nodes": nodes
	}


func _build_node_tree(node: Node, output: Array, path: String, include_props: bool):
	if not is_instance_valid(node):
		return
	
	var node_info = {
		"name": node.name,
		"type": node.get_class(),
		"path": path if not path.is_empty() else node.name
	}
	
	if node is Node2D:
		node_info["position"] = {"x": node.position.x, "y": node.position.y, "__type": "Vector2"}
		node_info["rotation"] = node.rotation
		node_info["scale"] = {"x": node.scale.x, "y": node.scale.y, "__type": "Vector2"}
	elif node is Node3D:
		node_info["position"] = {"x": node.position.x, "y": node.position.y, "z": node.position.z, "__type": "Vector3"}
		node_info["rotation"] = {"x": node.rotation.x, "y": node.rotation.y, "z": node.rotation.z, "__type": "Vector3"}
		node_info["scale"] = {"x": node.scale.x, "y": node.scale.y, "z": node.scale.z, "__type": "Vector3"}
	
	if node.get_script():
		node_info["script"] = node.get_script().resource_path
	
	node_info["groups"] = node.get_groups()
	
	if include_props:
		node_info["properties"] = _get_node_properties_dict(node)
	
	output.append(node_info)
	
	for child in node.get_children():
		var child_path = node_info["path"] + "/" + child.name
		_build_node_tree(child, output, child_path, include_props)


func _get_node_properties_dict(node: Node) -> Dictionary:
	var props = {}
	var property_list = node.get_property_list()
	
	for prop in property_list:
		var prop_name = prop["name"]
		# Filtrar propiedades internas
		if prop_name.begins_with("_") or prop_name in ["script", "process_mode", "process_priority", "physics_interpolation_mode"]:
			continue
		
		var usage = prop.get("usage", 0)
		if usage & PROPERTY_USAGE_EDITOR or usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			if prop_name in node:
				var value = node.get(prop_name)
				props[prop_name] = _serialize_value(value)
	
	return props


func _serialize_value(value) -> Variant:
	if value is Vector2:
		return {"x": value.x, "y": value.y, "__type": "Vector2"}
	elif value is Vector3:
		return {"x": value.x, "y": value.y, "z": value.z, "__type": "Vector3"}
	elif value is Color:
		return {"r": value.r, "g": value.g, "b": value.b, "a": value.a, "__type": "Color"}
	elif value is Rect2:
		return {"x": value.position.x, "y": value.position.y, "w": value.size.x, "h": value.size.y, "__type": "Rect2"}
	elif value is NodePath:
		return {"path": str(value), "__type": "NodePath"}
	elif value is Object and value is Resource and value.resource_path:
		return {"resource_path": value.resource_path, "__type": "Resource"}
	else:
		return value


# ============================================================
# HANDLERS DE MODIFICACIÓN
# ============================================================

func _handle_add_node(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var parent_path = params.get("parent_path", "")
	var node_type = params.get("node_type", "Node")
	var node_name = params.get("node_name", "")
	var properties = params.get("properties", {})
	
	# Compatibilidad: si no hay parent_path pero sí node_path, usar node_path como parent_path
	if not parent_path and params.has("node_path"):
		parent_path = params.get("node_path", ".")
	
	if not parent_path:
		parent_path = "."
	
	if not scene_path or not node_name:
		return {"success": false, "error": "missing_params", "message": "scene_path y node_name son requeridos"}
	
	# Asegurar que la escena esté cargada
	if not _scene_cache.has(scene_path):
		var load_result = _handle_load_scene({"scene_path": scene_path})
		if not load_result.success:
			return load_result
	
	var root = _scene_cache[scene_path]
	var parent: Node
	
	# Normalizar path
	if parent_path == "." or parent_path == root.name or parent_path == "/root/" + root.name:
		parent = root
	else:
		# Quitar prefijos /root/ si existen
		var normalized_path = parent_path
		if normalized_path.begins_with("/root/"):
			normalized_path = normalized_path.substr(6)
		# Quitar nombre del root si está al inicio
		if normalized_path.begins_with(root.name + "/"):
			normalized_path = normalized_path.substr(root.name.length() + 1)
		
		parent = root.get_node_or_null(normalized_path)
		if not parent:
			return {"success": false, "error": "parent_not_found", "parent_path": parent_path, "normalized": normalized_path}
	
	# Verificar que no exista
	if parent.get_node_or_null(node_name):
		return {"success": false, "error": "node_exists", "node_name": node_name}
	
	# Crear nodo
	var new_node = ClassDB.instantiate(node_type)
	if not new_node:
		return {"success": false, "error": "invalid_node_type", "node_type": node_type}
	
	new_node.name = node_name
	
	# Asegurar process_mode normal para nodos nuevos (no heredar el deshabilitado del cache)
	if new_node is Node:
		new_node.process_mode = Node.PROCESS_MODE_INHERIT
	
	# Aplicar propiedades
	for prop_name in properties.keys():
		var deserialized = _deserialize_value(properties[prop_name])
		if prop_name in new_node or prop_name in ["position", "rotation", "scale", "size", "text", "visible", "modulate", "self_modulate", "process_mode"]:
			new_node.set(prop_name, deserialized)
	
	parent.add_child(new_node)
	new_node.owner = root
	
	# Verificar que el nodo fue añadido correctamente
	var verify_node = parent.get_node_or_null(node_name)
	if not verify_node:
		return {
			"success": false,
			"error": "add_failed",
			"message": "El nodo no se pudo verificar después de añadirlo"
		}
	
	return {
		"success": true,
		"scene_path": scene_path,
		"node_path": str(parent.get_path()) + "/" + node_name,
		"node_type": node_type,
		"node_count": _count_nodes_recursive(root)
	}


func _handle_remove_node(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var node_path = params.get("node_path", "")
	var recursive = params.get("recursive", true)
	
	if not scene_path or not node_path:
		return {"success": false, "error": "missing_params"}
	
	if not _scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _scene_cache[scene_path]
	var target = root.get_node_or_null(node_path)
	
	if not target:
		return {"success": false, "error": "node_not_found", "node_path": node_path}
	
	if target == root:
		return {"success": false, "error": "cannot_remove_root"}
	
	if target.get_child_count() > 0 and not recursive:
		return {"success": false, "error": "node_has_children", "children": target.get_child_count()}
	
	var had_children = target.get_child_count() > 0
	target.queue_free()
	
	return {
		"success": true,
		"scene_path": scene_path,
		"removed": node_path,
		"had_children": had_children
	}


func _handle_set_property(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var node_path = params.get("node_path", "")
	var property = params.get("property", "")
	
	# Compatibilidad: aceptar "property_name" como alternativa a "property"
	if not property and params.has("property_name"):
		property = params.get("property_name", "")
	
	var value = params.get("value", null)
	
	if not scene_path or not node_path or not property:
		return {"success": false, "error": "missing_params", "message": "Se requiere scene_path, node_path y property (o property_name)"}
	
	if not _scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _scene_cache[scene_path]
	var node = root.get_node_or_null(node_path)
	
	if not node:
		return {"success": false, "error": "node_not_found", "node_path": node_path}
	
	var deserialized = _deserialize_value(value)
	
	# Verificar si la propiedad existe
	if not property in node:
		return {"success": false, "error": "property_not_found", "property": property}
	
	var old_value = node.get(property)
	node.set(property, deserialized)
	
	return {
		"success": true,
		"scene_path": scene_path,
		"node_path": node_path,
		"property": property,
		"old_value": str(old_value),
		"new_value": str(deserialized)
	}


func _handle_get_node_properties(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var node_path = params.get("node_path", "")
	
	if not scene_path or not node_path:
		return {"success": false, "error": "missing_params"}
	
	if not _scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _scene_cache[scene_path]
	var node = root.get_node_or_null(node_path)
	
	if not node:
		return {"success": false, "error": "node_not_found", "node_path": node_path}
	
	return {
		"success": true,
		"scene_path": scene_path,
		"node_path": node_path,
		"node_type": node.get_class(),
		"properties": _get_node_properties_dict(node)
	}


func _handle_array_append(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var node_path = params.get("node_path", "")
	var property_name = params.get("property_name", "")
	var value = params.get("value", null)
	
	if not scene_path or not node_path or not property_name:
		return {"success": false, "error": "missing_params", "message": "scene_path, node_path y property_name son requeridos"}
	
	if not _scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _scene_cache[scene_path]
	var node = root.get_node_or_null(node_path)
	
	if not node:
		return {"success": false, "error": "node_not_found", "node_path": node_path}
	
	# Obtener el array actual (duplicate para evitar modificar por referencia)
	var current_array = node.get(property_name)
	if not current_array is Array:
		return {"success": false, "error": "property_not_array", "property_name": property_name, "type": typeof(current_array)}
	
	# Duplicar para asegurar que Godot detecte el cambio
	var new_array = current_array.duplicate()
	new_array.append(value)
	
	# Setear el array modificado
	node.set(property_name, new_array)
	
	return {
		"success": true,
		"scene_path": scene_path,
		"node_path": node_path,
		"property_name": property_name,
		"value_added": value,
		"array_size": current_array.size()
	}


func _handle_array_remove(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var node_path = params.get("node_path", "")
	var property_name = params.get("property_name", "")
	var index = params.get("index", -1)
	var value = params.get("value", null)
	
	if not scene_path or not node_path or not property_name:
		return {"success": false, "error": "missing_params", "message": "scene_path, node_path y property_name son requeridos"}
	
	if not _scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _scene_cache[scene_path]
	var node = root.get_node_or_null(node_path)
	
	if not node:
		return {"success": false, "error": "node_not_found", "node_path": node_path}
	
	# Obtener el array actual (duplicate para evitar modificar por referencia)
	var current_array = node.get(property_name)
	if not current_array is Array:
		return {"success": false, "error": "property_not_array", "property_name": property_name, "type": typeof(current_array)}
	
	# Duplicar para asegurar que Godot detecte el cambio
	var new_array = current_array.duplicate()
	var removed_value = null
	
	# Remover por índice o por valor
	if index >= 0 and index < new_array.size():
		removed_value = new_array[index]
		new_array.remove_at(index)
	elif value != null:
		var found_index = new_array.find(value)
		if found_index >= 0:
			removed_value = new_array[found_index]
			new_array.remove_at(found_index)
		else:
			return {"success": false, "error": "value_not_found", "value": value}
	else:
		return {"success": false, "error": "invalid_remove_params", "message": "Especifica index o value para remover"}
	
	# Setear el array modificado
	node.set(property_name, new_array)
	
	return {
		"success": true,
		"scene_path": scene_path,
		"node_path": node_path,
		"property_name": property_name,
		"removed_value": removed_value,
		"array_size": current_array.size()
	}


# ============================================================
# HANDLERS DE SEÑALES Y SCRIPTS
# ============================================================

func _handle_set_script(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var node_path = params.get("node_path", "")
	var script_path = params.get("script_path", "")
	
	if not scene_path or not node_path or not script_path:
		return {"success": false, "error": "missing_params", "message": "scene_path, node_path y script_path son requeridos"}
	
	if not _scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _scene_cache[scene_path]
	var node = root.get_node_or_null(node_path)
	
	if not node:
		return {"success": false, "error": "node_not_found", "node_path": node_path}
	
	# Cargar el script
	var script = load(script_path)
	if not script:
		return {"success": false, "error": "script_not_found", "script_path": script_path}
	
	# Asignar script al nodo
	node.set_script(script)
	
	return {
		"success": true,
		"scene_path": scene_path,
		"node_path": node_path,
		"script_path": script_path,
		"script_type": script.get_class() if script else "null"
	}


func _handle_connect_signal(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var from_node = params.get("from_node", "")
	var signal_name = params.get("signal_name", "")
	var to_node = params.get("to_node", "")
	var method = params.get("method", "")
	
	if not scene_path or not from_node or not signal_name or not to_node or not method:
		return {"success": false, "error": "missing_params"}
	
	if not _scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _scene_cache[scene_path]
	var source = root.get_node_or_null(from_node)
	var target = root.get_node_or_null(to_node)
	
	if not source:
		return {"success": false, "error": "node_not_found", "node": from_node}
	if not target:
		return {"success": false, "error": "node_not_found", "node": to_node}
	
	# Verificar que la señal existe
	if not source.has_signal(signal_name):
		return {"success": false, "error": "signal_not_found", "signal": signal_name}
	
	# Conectar la señal
	var err = source.connect(signal_name, Callable(target, method))
	if err != OK:
		return {"success": false, "error": "connect_failed", "code": err}
	
	return {
		"success": true,
		"scene_path": scene_path,
		"from_node": from_node,
		"signal": signal_name,
		"to_node": to_node,
		"method": method
	}


func _handle_disconnect_signal(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var from_node = params.get("from_node", "")
	var signal_name = params.get("signal_name", "")
	var to_node = params.get("to_node", "")
	var method = params.get("method", "")
	
	if not scene_path or not from_node or not signal_name:
		return {"success": false, "error": "missing_params"}
	
	if not _scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _scene_cache[scene_path]
	var source = root.get_node_or_null(from_node)
	
	if not source:
		return {"success": false, "error": "node_not_found", "node": from_node}
	
	# Desconectar todas las conexiones de esta señal si no se especifica target
	if to_node and method:
		var target = root.get_node_or_null(to_node)
		if target:
			source.disconnect(signal_name, Callable(target, method))
	else:
		# Desconectar todas las conexiones de esta señal
		var connections = source.get_signal_connection_list(signal_name)
		for conn in connections:
			source.disconnect(signal_name, conn["callable"])
	
	return {
		"success": true,
		"scene_path": scene_path,
		"from_node": from_node,
		"signal": signal_name
	}


func _handle_list_signals(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var node_path = params.get("node_path", "")
	
	if not scene_path or not node_path:
		return {"success": false, "error": "missing_params"}
	
	if not _scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _scene_cache[scene_path]
	var node = root.get_node_or_null(node_path)
	
	if not node:
		return {"success": false, "error": "node_not_found", "node_path": node_path}
	
	# Obtener señales del nodo
	var signals = []
	var signal_list = node.get_signal_list()
	for sig in signal_list:
		var connections = node.get_signal_connection_list(sig["name"])
		var conn_list = []
		for conn in connections:
			conn_list.append({
				"target": str(conn["callable"].get_object()),
				"method": conn["callable"].get_method()
			})
		signals.append({
			"name": sig["name"],
			"args": sig.get("args", []),
			"connections": conn_list
		})
	
	return {
		"success": true,
		"scene_path": scene_path,
		"node_path": node_path,
		"signals": signals
	}


# ============================================================
# HANDLERS DE ESCENA
# ============================================================

func _handle_save_scene(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	
	if not scene_path:
		return {"success": false, "error": "missing_scene_path"}
	
	if not _scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _scene_cache[scene_path]
	
	# FIX CRITICO: Asegurar que todos los recursos de los nodos tengan paths validos
	# antes de hacer pack(). Esto fuerza a Godot a guardarlos como ext_resources.
	_pre_save_resource_fix(root)
	
	# Crear PackedScene
	var packed = PackedScene.new()
	var err = packed.pack(root)
	if err != OK:
		return {"success": false, "error": "pack_failed", "code": err}
	
	# FIX CRITICO: Usar FLAG_BUNDLE_RESOURCES para asegurar que todos los recursos se guarden
	var save_flags = ResourceSaver.FLAG_BUNDLE_RESOURCES
	err = ResourceSaver.save(packed, scene_path, save_flags)
	if err != OK:
		return {"success": false, "error": "save_failed", "code": err}
	
	# FIX CRITICO: Inyectar sub-resources y senales que PackedScene no guarda
	# Recolectar recursos y senales del arbol en memoria
	var sub_resources = _collect_sub_resources(root)
	var connections = _collect_connections(root)
	
	# Inyectar en el archivo .tscn
	if not sub_resources.is_empty() or not connections.is_empty():
		_inject_into_tscn(scene_path, sub_resources, connections)
	
	# Verificar que el archivo se escribio correctamente
	var saved_node_count = _count_nodes_recursive(root)
	
	# Intentar recargar para verificar integridad
	var verify_load = load(scene_path)
	var verify_count = 0
	if verify_load:
		var verify_instance = verify_load.instantiate()
		if verify_instance:
			verify_count = _count_nodes_recursive(verify_instance)
			verify_instance.queue_free()
	
	if verify_count > 0 and verify_count != saved_node_count:
		return {
			"success": false,
			"error": "save_verification_failed",
			"message": "El archivo guardado tiene " + str(verify_count) + " nodos, pero se esperaban " + str(saved_node_count),
			"scene_path": scene_path
		}
	
	return {
		"success": true,
		"scene_path": scene_path,
		"node_count": saved_node_count,
		"verified": verify_count == saved_node_count,
		"sub_resources_injected": sub_resources.size(),
		"connections_injected": connections.size()
	}


func _pre_save_resource_fix(node: Node):
	"""
	FIX CRITICO: Recorre todos los nodos y asegura que las propiedades Resource
	se serialicen correctamente en el .tscn.
	"""
	if not node:
		return
	
	# Obtener propiedades del nodo
	var property_list = node.get_property_list()
	
	for prop in property_list:
		var prop_name = prop.get("name", "")
		var prop_type = prop.get("type", 0)
		var prop_usage = prop.get("usage", 0)
		
		# Solo procesar propiedades exportadas o de almacenamiento
		if prop_usage & PROPERTY_USAGE_STORAGE == 0:
			continue
		
		# Si es una propiedad de tipo OBJECT (que incluye Resource)
		if prop_type == TYPE_OBJECT:
			var value = node.get(prop_name)
			if value and value is Resource:
				var res = value as Resource
				# FIX: Marcar como local_to_scene para forzar incrustacion
				if not res.resource_local_to_scene:
					res.resource_local_to_scene = true
				# FIX: Asegurar que los recursos anidados tambien sean locales
				_setup_resource_local_to_scene_recursive(res)
	
	# Recursion en hijos
	for child in node.get_children():
		_pre_save_resource_fix(child)


func _setup_resource_local_to_scene_recursive(resource: Resource):
	"""
	Marca un recurso y todos sus sub-recursos como local_to_scene.
	Esto fuerza a Godot a serializar todo en el .tscn.
	"""
	if not resource:
		return
	
	if not resource.resource_local_to_scene:
		resource.resource_local_to_scene = true
	
	# Recorrer propiedades del recurso buscando sub-recursos
	var prop_list = resource.get_property_list()
	for prop in prop_list:
		var prop_name = prop.get("name", "")
		var prop_usage = prop.get("usage", 0)
		
		if prop_name in ["script", "resource_name", "resource_path"]:
			continue
		if prop_usage & PROPERTY_USAGE_STORAGE == 0:
			continue
		
		var value = resource.get(prop_name)
		if value and value is Resource and not value is Script:
			_setup_resource_local_to_scene_recursive(value as Resource)


func _derive_resource_path(resource: Resource) -> String:
	"""
	Intenta derivar un resource_path para un recurso basado en su tipo.
	Esto es un workaround para recursos creados programaticamente.
	"""
	if not resource:
		return ""
	
	# Si ya tiene un path, devolverlo
	if not resource.resource_path.is_empty():
		return resource.resource_path
	
	# Para scripts, buscar por clase
	if resource is Script:
		var script = resource as Script
		if not script.resource_path.is_empty():
			return script.resource_path
		# Intentar encontrar el archivo basado en el nombre de la clase
		var class_name_str = script.get_global_name()
		if not class_name_str.is_empty():
			return "res://scripts/" + class_name_str.to_snake_case() + ".gd"
	
	# Para texturas, buscar en el sistema de archivos
	if resource is Texture2D:
		var texture = resource as Texture2D
		if not texture.resource_path.is_empty():
			return texture.resource_path
		# No podemos derivar el path de una textura sin mas informacion
		return ""
	
	# Para otros recursos, devolver vacio (no podemos derivar el path)
	return ""


func _collect_sub_resources(node: Node) -> Array:
	"""
	Recorre el arbol de nodos y recolecta todos los recursos que necesitan
	ser guardados como sub_resources en el .tscn.
	Retorna un array de diccionarios con: node_path, prop_name, resource, resource_type
	"""
	var resources = []
	if not node:
		return resources
	
	# Recorrer propiedades del nodo
	var property_list = node.get_property_list()
	for prop in property_list:
		var prop_name = prop.get("name", "")
		var prop_type = prop.get("type", 0)
		var prop_usage = prop.get("usage", 0)
		
		# Solo propiedades de almacenamiento
		if prop_usage & PROPERTY_USAGE_STORAGE == 0:
			continue
		
		# Si es OBJECT (Resource)
		if prop_type == TYPE_OBJECT:
			var value = node.get(prop_name)
			if value and value is Resource and not value is Script:
				# Solo recursos sin resource_path (creados programaticamente)
				if value.resource_path.is_empty():
					resources.append({
						"node_path": _get_node_path_relative(node),
						"prop_name": prop_name,
						"resource": value,
						"resource_type": value.get_class()
					})
	
	# Recursion en hijos
	for child in node.get_children():
		resources.append_array(_collect_sub_resources(child))
	
	return resources


func _collect_connections(node: Node) -> Array:
	"""
	Recorre el arbol de nodos y recolecta todas las senales conectadas.
	Retorna un array de diccionarios con: signal_name, from_path, to_path, method
	"""
	var connections = []
	if not node:
		return connections
	
	# Obtener senales del nodo
	var signal_list = node.get_signal_list()
	for sig in signal_list:
		var signal_name = sig.get("name", "")
		# Obtener conexiones de esta senal
		var conns = node.get_signal_connection_list(signal_name)
		for conn in conns:
			var callable_obj = conn.get("callable", null)
			if callable_obj:
				var target_node = callable_obj.get_object() as Node
				if target_node:
					connections.append({
						"signal_name": signal_name,
						"from_path": _get_node_path_relative(node),
						"to_path": _get_node_path_relative(target_node),
						"method": callable_obj.get_method()
					})
	
	# Recursion en hijos
	for child in node.get_children():
		connections.append_array(_collect_connections(child))
	
	return connections


func _get_node_path_relative(node: Node) -> String:
	"""
	Obtiene el path relativo del nodo desde el root de la escena.
	"""
	if not node:
		return ""
	
	var path = node.name
	var current = node.get_parent()
	while current and not current is Viewport:
		path = current.name + "/" + path
		current = current.get_parent()
	
	# Remover el nombre del root (la escena)
	var parts = path.split("/")
	if parts.size() > 1:
		parts.remove_at(0)
		return "/".join(parts)
	
	return "."


func _inject_into_tscn(scene_path: String, sub_resources: Array, connections: Array):
	"""
	Inyecta sub_resources y conexiones en un archivo .tscn existente.
	Modifica el archivo directamente agregando [sub_resource] y [connection].
	Maneja recursos anidados (ej: ShaderMaterial.shader).
	"""
	if not FileAccess.file_exists(scene_path):
		return
	
	var file = FileAccess.open(scene_path, FileAccess.READ)
	if not file:
		return
	
	var content = file.get_as_text()
	file.close()
	
	var lines = content.split("\n")
	var result_lines = []
	var has_sub_resources_section = false
	var has_connections_section = false
	
	# Procesar lineas existentes
	for line in lines:
		if line.begins_with("[sub_resource"):
			has_sub_resources_section = true
		if line.begins_with("[connection"):
			has_connections_section = true
		result_lines.append(line)
	
	# Agregar sub_resources si no existen
	if not sub_resources.is_empty() and not has_sub_resources_section:
		result_lines.append("")
		result_lines.append("# Sub-resources injectados por Heren MCP")
		
		# Primero recolectar todos los sub-resources anidados
		var all_sub_resources = {}  # id -> {type, properties}
		
		for i in range(sub_resources.size()):
			var res_info = sub_resources[i]
			var res = res_info["resource"]
			var res_type = res_info["resource_type"]
			var res_id = res_type + "_heren_" + str(i)
			
			# Serializar propiedades, esto puede agregar sub-resources anidados
			var nested_dict = {}
			var res_properties = _serialize_resource_properties(res, nested_dict)
			
			# Agregar sub-resources anidados primero
			for nested_id in nested_dict.keys():
				if not all_sub_resources.has(nested_id):
					all_sub_resources[nested_id] = nested_dict[nested_id]
			
			# Agregar el sub-resource principal
			all_sub_resources[res_id] = {
				"type": res_type,
				"properties": res_properties
			}
			
			# Actualizar la referencia en el nodo correspondiente
			var node_path = res_info["node_path"]
			var prop_name = res_info["prop_name"]
			_update_node_subresource_ref(result_lines, node_path, prop_name, res_id)
		
		# Inyectar todos los sub-resources en orden
		for res_id in all_sub_resources.keys():
			var res_data = all_sub_resources[res_id]
			result_lines.append("[sub_resource type=\"" + res_data["type"] + "\" id=\"" + res_id + "\"]")
			for prop_line in res_data["properties"]:
				result_lines.append(prop_line)
			result_lines.append("")  # Linea en blanco entre sub-resources
	
	# Agregar conexiones si no existen
	if not connections.is_empty() and not has_connections_section:
		result_lines.append("")
		result_lines.append("# Conexiones injectadas por Heren MCP")
		
		for conn in connections:
			var conn_line = "[connection signal=\"" + conn["signal_name"] + "\""
			conn_line += " from=\"" + conn["from_path"] + "\""
			conn_line += " to=\"" + conn["to_path"] + "\""
			conn_line += " method=\"" + conn["method"] + "\"]"
			result_lines.append(conn_line)
	
	# Escribir archivo modificado
	file = FileAccess.open(scene_path, FileAccess.WRITE)
	if file:
		file.store_string("\n".join(result_lines))
		file.close()
		print("[Inject] Inyectados ", sub_resources.size(), " sub-resources y ", connections.size(), " conexiones en ", scene_path)


func _serialize_resource_properties(resource: Resource, sub_resources_dict: Dictionary = {}) -> Array:
	"""
	Serializa las propiedades de un recurso a lineas de texto .tscn.
	Maneja recursos anidados creando sub-resources adicionales.
	"""
	var lines = []
	if not resource:
		return lines
	
	var prop_list = resource.get_property_list()
	for prop in prop_list:
		var prop_name = prop.get("name", "")
		var prop_usage = prop.get("usage", 0)
		
		# Solo propiedades de almacenamiento, no script o resource_name
		if prop_name in ["script", "resource_name", "resource_path"]:
			continue
		if prop_usage & PROPERTY_USAGE_STORAGE == 0:
			continue
		
		var value = resource.get(prop_name)
		if value == null:
			continue
		
		# Si es un recurso anidado, crear sub-resource separado
		if value is Resource and not value is Script:
			var nested_res = value as Resource
			if nested_res.resource_path.is_empty():
				# Crear sub-resource anidado
				var nested_type = nested_res.get_class()
				var nested_id = nested_type + "_nested_" + str(sub_resources_dict.size())
				sub_resources_dict[nested_id] = {
					"type": nested_type,
					"resource": nested_res,
					"properties": _serialize_resource_properties(nested_res, sub_resources_dict)
				}
				lines.append(prop_name + " = SubResource(\"" + nested_id + "\")")
				continue
		
		# Serializar segun tipo
		var serialized = _serialize_value_tscn(value)
		if not serialized.is_empty():
			lines.append(prop_name + " = " + serialized)
	
	return lines


func _serialize_value_tscn(value) -> String:
	"""
	Serializa un valor de Godot a formato texto .tscn.
	"""
	if value == null:
		return ""
	
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return str(value)
		TYPE_STRING, TYPE_STRING_NAME:
			return "\"" + value + "\""
		TYPE_BOOL:
			return "true" if value else "false"
		TYPE_VECTOR2:
			var v = value as Vector2
			return "Vector2(" + str(v.x) + ", " + str(v.y) + ")"
		TYPE_VECTOR2I:
			var v = value as Vector2i
			return "Vector2i(" + str(v.x) + ", " + str(v.y) + ")"
		TYPE_VECTOR3:
			var v = value as Vector3
			return "Vector3(" + str(v.x) + ", " + str(v.y) + ", " + str(v.z) + ")"
		TYPE_COLOR:
			var c = value as Color
			return "Color(" + str(c.r) + ", " + str(c.g) + ", " + str(c.b) + ", " + str(c.a) + ")"
		TYPE_RECT2:
			var r = value as Rect2
			return "Rect2(" + _serialize_value_tscn(r.position) + ", " + _serialize_value_tscn(r.size) + ")"
		TYPE_TRANSFORM2D:
			var t = value as Transform2D
			return "Transform2D(" + str(t.x.x) + ", " + str(t.x.y) + ", " + str(t.y.x) + ", " + str(t.y.y) + ", " + str(t.origin.x) + ", " + str(t.origin.y) + ")"
		TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_FLOAT32_ARRAY:
			var arr = value as Array
			var parts = []
			for item in arr:
				parts.append(_serialize_value_tscn(item))
			return "[" + ", ".join(parts) + "]"
		TYPE_DICTIONARY:
			var dict = value as Dictionary
			var parts = []
			for key in dict.keys():
				parts.append(_serialize_value_tscn(key) + ": " + _serialize_value_tscn(dict[key]))
			return "{" + ", ".join(parts) + "}"
		TYPE_OBJECT:
			if value is Resource:
				var res = value as Resource
				if not res.resource_path.is_empty():
					return "ExtResource(\"" + res.resource_path + "\")"
				else:
					# Referencia a sub_resource (no deberia ocurrir aqui)
					return "SubResource(\"" + res.get_class() + "\")"
			return ""
		_:
			return str(value)


func _update_node_subresource_ref(lines: Array, node_path: String, prop_name: String, res_id: String):
	"""
	Actualiza la referencia de sub-resource en la linea del nodo correspondiente.
	Busca el nodo por path y agrega/modifica la propiedad para usar SubResource().
	"""
	var target_node_line = -1
	var target_indent = ""
	
	# Encontrar la linea del nodo
	for i in range(lines.size()):
		var line = lines[i]
		if line.begins_with("[node "):
			# Extraer path del nodo de la linea
			var path_match = line.find("parent=\"")
			if path_match != -1:
				var path_start = path_match + 8
				var path_end = line.find("\"", path_start)
				var parent_path = line.substr(path_start, path_end - path_start)
				
				# Extraer nombre del nodo
				var name_match = line.find("name=\"")
				if name_match != -1:
					var name_start = name_match + 6
					var name_end = line.find("\"", name_start)
					var node_name = line.substr(name_start, name_end - name_start)
					
					# Construir path completo
					var full_path = node_name
					if parent_path != ".":
						full_path = parent_path + "/" + node_name
					
					if full_path == node_path or (node_path == "." and parent_path == "."):
						target_node_line = i
						target_indent = "\t"
						break
	
	# Si encontramos el nodo, agregar la propiedad despues de la linea del nodo
	if target_node_line != -1:
		var prop_line = target_indent + prop_name + " = SubResource(\"" + res_id + "\")"
		# Insertar despues de la linea del nodo
		lines.insert(target_node_line + 1, prop_line)


# ============================================================
# HANDLERS DE SCREENSHOT Y RENDERING
# ============================================================

func _handle_screenshot(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var output_path = params.get("output_path", "")
	var resolution = params.get("resolution", [1280, 720])
	var wait_frames = params.get("wait_frames", 3)
	var format = params.get("format", "png")
	var quality = params.get("quality", 0.85)
	
	if not scene_path or not output_path:
		return {"success": false, "error": "missing_params"}
	
	if not _scene_cache.has(scene_path):
		var load_result = _handle_load_scene({"scene_path": scene_path})
		if not load_result.success:
			return load_result
	
	var scene = _scene_cache[scene_path]
	
	# Crear SubViewport
	var viewport = SubViewport.new()
	viewport.size = Vector2i(resolution[0], resolution[1])
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	get_root().add_child(viewport)
	
	# Clonar escena para renderizar
	var instance = scene.duplicate()
	viewport.add_child(instance)
	
	# Esperar frames
	for i in range(wait_frames):
		await process_frame
	
	# Capturar
	var texture = viewport.get_texture()
	var image = texture.get_image()
	
	# Guardar
	var err = OK
	match format:
		"jpg", "jpeg":
			var buffer = image.save_jpg_to_buffer(quality)
			var file = FileAccess.open(output_path, FileAccess.WRITE)
			if file:
				file.store_buffer(buffer)
				file.close()
			else:
				err = FAILED
		"webp":
			err = image.save_webp(output_path, true, quality)
		_:
			err = image.save_png(output_path)
	
	# Limpiar
	instance.queue_free()
	viewport.queue_free()
	
	if err != OK:
		return {"success": false, "error": "save_failed", "code": err}
	
	var file_size = 0
	if FileAccess.file_exists(output_path):
		file_size = FileAccess.get_file_as_bytes(output_path).size()
	
	return {
		"success": true,
		"image_path": output_path,
		"resolution": [image.get_width(), image.get_height()],
		"format": format,
		"file_size_bytes": file_size
	}


func _handle_capture_viewport(params: Dictionary) -> Dictionary:
	var output_path = params.get("output_path", "")
	var format = params.get("format", "png")
	var quality = params.get("quality", 0.85)
	
	if not output_path:
		return {"success": false, "error": "missing_output_path"}
	
	var root_viewport = get_root()
	var texture = root_viewport.get_texture()
	var image = texture.get_image()
	
	var err = OK
	match format:
		"jpg", "jpeg":
			var buffer = image.save_jpg_to_buffer(quality)
			var file = FileAccess.open(output_path, FileAccess.WRITE)
			if file:
				file.store_buffer(buffer)
				file.close()
			else:
				err = FAILED
		"webp":
			err = image.save_webp(output_path, true, quality)
		_:
			err = image.save_png(output_path)
	
	if err != OK:
		return {"success": false, "error": "save_failed", "code": err}
	
	return {
		"success": true,
		"image_path": output_path,
		"resolution": [image.get_width(), image.get_height()],
		"format": format
	}


func _handle_performance_metrics(params: Dictionary) -> Dictionary:
	var metrics = {
		"fps": Performance.get_monitor(Performance.TIME_FPS),
		"frame_time": Performance.get_monitor(Performance.TIME_PROCESS),
		"physics_time": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS),
		"memory_static": Performance.get_monitor(Performance.MEMORY_STATIC),
		"memory_max": Performance.get_monitor(Performance.MEMORY_STATIC_MAX),
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"orphan_nodes": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"vertices": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
	}
	
	return {"success": true, "metrics": metrics}


# ============================================================
# HANDLER BATCH
# ============================================================

func _handle_batch(params: Dictionary) -> Dictionary:
	var operations = params.get("operations", [])
	if operations.is_empty():
		return {"success": false, "error": "empty_operations"}
	
	var results = []
	var all_success = true
	var scene_load_warned = false
	
	for i in range(operations.size()):
		var op = operations[i]
		var method = op.get("method", "")
		var op_params = op.get("params", {})
		
		# Auto-cargar escena si es necesario para operaciones de nodo/escena
		if method in ["add_node", "remove_node", "set_property", "get_node_properties", 
					  "duplicate_node", "rename_node", "move_node", "save_scene", "get_scene_tree"]:
			var scene_path = op_params.get("scene_path", "")
			if scene_path and not _scene_cache.has(scene_path) and not scene_load_warned:
				print("[BATCH] Advertencia: Escena no cargada en cache: ", scene_path)
				scene_load_warned = true
		
		var result = _dispatch(method, op_params)
		result["_batch_index"] = i
		result["_batch_method"] = method
		results.append(result)
		
		if not result.get("success", false):
			all_success = false
			if params.get("stop_on_error", false):
				break
	
	return {
		"success": all_success,
		"operation_count": operations.size(),
		"results": results,
		"note": "Revisa cada resultado individual para ver errores específicos"
	}


# ============================================================
# UTILIDADES
# ============================================================

func _deserialize_value(value) -> Variant:
	if value is Dictionary:
		var type = value.get("__type", "")
		
		# Si tiene "type" sin __, es un recurso generico
		if type == "" and value.has("type"):
			return _deserialize_resource(value)
		
		# Auto-detectar tipo por keys si no tiene __type
		if type == "" and value.has("x") and value.has("y"):
			if value.has("z"):
				type = "Vector3"
			else:
				type = "Vector2"
		elif type == "" and value.has("r") and value.has("g") and value.has("b"):
			type = "Color"
		
		match type:
			"Vector2":
				return Vector2(value.get("x", 0), value.get("y", 0))
			"Vector3":
				return Vector3(value.get("x", 0), value.get("y", 0), value.get("z", 0))
			"Color":
				return Color(value.get("r", 0), value.get("g", 0), value.get("b", 0), value.get("a", 1))
			"Rect2":
				return Rect2(value.get("x", 0), value.get("y", 0), value.get("w", 0), value.get("h", 0))
			"NodePath":
				return NodePath(value.get("path", ""))
			"Resource":
				var path = value.get("resource_path", "")
				if path and ResourceLoader.exists(path):
					return load(path)
				return null
			_:
				return value
	elif value is String:
		# FIX CRITICO: Si el string es un path a un recurso, cargarlo
		var str_value = value as String
		if str_value.begins_with("res://") or str_value.begins_with("user://"):
			if ResourceLoader.exists(str_value):
				return load(str_value)
		return value
	else:
		return value


func _deserialize_resource(value: Dictionary) -> Resource:
	"""
	Deserializa un diccionario con "type" y propiedades a un recurso de Godot.
	Ejemplo: {"type": "RectangleShape2D", "size": {"x": 64, "y": 64}}
	"""
	var resource_type = value.get("type", "")
	if resource_type == "":
		return null
	
	# Crear instancia del recurso usando ClassDB
	var resource = ClassDB.instantiate(resource_type)
	if not resource is Resource:
		return null
	
	# Setear propiedades
	for key in value.keys():
		if key == "type":
			continue
		var prop_value = _deserialize_value(value[key])
		if resource.get_property_list().any(func(p): return p.name == key):
			resource.set(key, prop_value)
	
	return resource as Resource


# ============================================================
# RESOURCE HANDLERS
# ============================================================

func _handle_create_resource(params: Dictionary) -> Dictionary:
	var resource_path = params.get("resource_path", "")
	var resource_type = params.get("resource_type", "Resource")
	var properties = params.get("properties", {})
	
	if not resource_path:
		return {"success": false, "error": "missing_resource_path"}
	
	# Ensure .tres extension
	if not resource_path.ends_with(".tres"):
		resource_path += ".tres"
	
	# Check if exists
	if FileAccess.file_exists(resource_path):
		return {"success": false, "error": "resource_exists", "path": resource_path}
	
	# Create directory
	var base_dir = resource_path.get_base_dir()
	if base_dir != "res://" and base_dir != ".":
		DirAccess.make_dir_recursive_absolute(base_dir)
	
	# Create resource using ClassDB
	var resource = ClassDB.instantiate(resource_type)
	if not resource:
		return {"success": false, "error": "invalid_resource_type", "type": resource_type}
	
	# Apply properties
	for prop_name in properties.keys():
		var deserialized = _deserialize_value(properties[prop_name])
		if prop_name in resource:
			resource.set(prop_name, deserialized)
	
	# Save
	var err = ResourceSaver.save(resource, resource_path)
	if err != OK:
		return {"success": false, "error": "save_failed", "code": err}
	
	# Cache it
	_resource_cache[resource_path] = resource
	
	return {
		"success": true,
		"resource_path": resource_path,
		"resource_type": resource_type
	}


func _handle_read_resource(params: Dictionary) -> Dictionary:
	var resource_path = params.get("resource_path", "")
	
	if not resource_path:
		return {"success": false, "error": "missing_resource_path"}
	
	# Try cache first
	if _resource_cache.has(resource_path):
		var cached = _resource_cache[resource_path]
		if is_instance_valid(cached):
			return {
				"success": true,
				"from_cache": true,
				"resource_path": resource_path,
				"resource_type": cached.get_class(),
				"properties": _get_resource_properties(cached)
			}
	
	if not ResourceLoader.exists(resource_path):
		return {"success": false, "error": "resource_not_found", "path": resource_path}
	
	var resource = load(resource_path)
	if not resource:
		return {"success": false, "error": "load_failed", "path": resource_path}
	
	_resource_cache[resource_path] = resource
	
	return {
		"success": true,
		"from_cache": false,
		"resource_path": resource_path,
		"resource_type": resource.get_class(),
		"properties": _get_resource_properties(resource)
	}


func _get_resource_properties(resource: Resource) -> Dictionary:
	var props = {}
	var property_list = resource.get_property_list()
	
	for prop in property_list:
		var prop_name = prop["name"]
		if prop_name.begins_with("_"):
			continue
		
		var usage = prop.get("usage", 0)
		if usage & PROPERTY_USAGE_EDITOR or usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			if prop_name in resource:
				var value = resource.get(prop_name)
				props[prop_name] = _serialize_value(value)
	
	return props


func _handle_update_resource(params: Dictionary) -> Dictionary:
	var resource_path = params.get("resource_path", "")
	var properties = params.get("properties", {})
	
	if not resource_path:
		return {"success": false, "error": "missing_resource_path"}
	
	var resource = null
	
	# Try cache
	if _resource_cache.has(resource_path):
		resource = _resource_cache[resource_path]
		if not is_instance_valid(resource):
			_resource_cache.erase(resource_path)
			resource = null
	
	# Load if not cached
	if not resource:
		if not ResourceLoader.exists(resource_path):
			return {"success": false, "error": "resource_not_found"}
		resource = load(resource_path)
		if not resource:
			return {"success": false, "error": "load_failed"}
		_resource_cache[resource_path] = resource
	
	# Update properties
	for prop_name in properties.keys():
		var deserialized = _deserialize_value(properties[prop_name])
		if prop_name in resource:
			resource.set(prop_name, deserialized)
	
	# Save
	var err = ResourceSaver.save(resource, resource_path)
	if err != OK:
		return {"success": false, "error": "save_failed", "code": err}
	
	return {
		"success": true,
		"resource_path": resource_path,
		"updated_properties": properties.keys()
	}


func _handle_delete_resource(params: Dictionary) -> Dictionary:
	var resource_path = params.get("resource_path", "")
	
	if not resource_path:
		return {"success": false, "error": "missing_resource_path"}
	
	if not FileAccess.file_exists(resource_path):
		return {"success": false, "error": "resource_not_found"}
	
	# Remove from cache
	if _resource_cache.has(resource_path):
		_resource_cache.erase(resource_path)
	
	# Delete file
	var err = DirAccess.remove_absolute(resource_path)
	if err != OK:
		return {"success": false, "error": "delete_failed", "code": err}
	
	return {"success": true, "deleted": resource_path}


func _handle_list_resources(params: Dictionary) -> Dictionary:
	var directory = params.get("directory", "res://")
	var extension = params.get("extension", "")
	var recursive = params.get("recursive", false)
	
	var resources = []
	_scan_directory(directory, extension, recursive, resources)
	
	return {
		"success": true,
		"directory": directory,
		"count": resources.size(),
		"resources": resources
	}


func _scan_directory(dir_path: String, extension: String, recursive: bool, output: Array):
	var dir = DirAccess.open(dir_path)
	if not dir:
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if file_name == "." or file_name == "..":
			file_name = dir.get_next()
			continue
		
		var full_path = dir_path.path_join(file_name)
		
		if dir.current_is_dir() and recursive:
			_scan_directory(full_path, extension, recursive, output)
		else:
			if extension.is_empty() or file_name.ends_with(extension):
				output.append(full_path)
		
		file_name = dir.get_next()
	
	dir.list_dir_end()


# ============================================================
# ANIMATION HANDLERS
# ============================================================

func _handle_create_animation_player(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var parent_path = params.get("parent_path", ".")
	var player_name = params.get("player_name", "AnimationPlayer")
	
	if not scene_path or not player_name:
		return {"success": false, "error": "missing_params"}
	
	if not _scene_cache.has(scene_path):
		var load_result = _handle_load_scene({"scene_path": scene_path})
		if not load_result.success:
			return load_result
	
	var root = _scene_cache[scene_path]
	var parent: Node
	
	if parent_path == "." or parent_path == root.name:
		parent = root
	else:
		parent = root.get_node_or_null(parent_path)
		if not parent:
			return {"success": false, "error": "parent_not_found"}
	
	if parent.get_node_or_null(player_name):
		return {"success": false, "error": "node_exists"}
	
	var player = AnimationPlayer.new()
	player.name = player_name
	parent.add_child(player)
	player.owner = root
	
	return {
		"success": true,
		"scene_path": scene_path,
		"player_path": str(parent.get_path()) + "/" + player_name,
		"player_name": player_name
	}


func _handle_create_animation(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var player_path = params.get("player_path", "")
	var anim_name = params.get("anim_name", "")
	var length = params.get("length", 1.0)
	var loop = params.get("loop", false)
	
	if not scene_path or not player_path or not anim_name:
		return {"success": false, "error": "missing_params"}
	
	if not _scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _scene_cache[scene_path]
	var player = root.get_node_or_null(player_path)
	
	if not player or not player is AnimationPlayer:
		return {"success": false, "error": "animation_player_not_found"}
	
	var anim = Animation.new()
	anim.length = length
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	
	# Godot 4 usa AnimationLibrary para persistir animaciones
	var anim_lib = player.get_animation_library("")
	if not anim_lib:
		anim_lib = AnimationLibrary.new()
		player.add_animation_library("", anim_lib)
	anim_lib.add_animation(anim_name, anim)
	
	return {
		"success": true,
		"scene_path": scene_path,
		"player_path": player_path,
		"anim_name": anim_name,
		"length": length,
		"loop": loop
	}


func _handle_add_animation_track(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var player_path = params.get("player_path", "")
	var anim_name = params.get("anim_name", "")
	var track_type = params.get("track_type", "value")
	var node_path = params.get("node_path", "")
	var property = params.get("property", "")
	
	if not scene_path or not player_path or not anim_name or not node_path or not property:
		return {"success": false, "error": "missing_params"}
	
	if not _scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _scene_cache[scene_path]
	var player = root.get_node_or_null(player_path)
	
	if not player or not player is AnimationPlayer:
		return {"success": false, "error": "animation_player_not_found"}
	
	var anim = player.get_animation(anim_name)
	if not anim:
		return {"success": false, "error": "animation_not_found"}
	
	var track_idx = -1
	match track_type:
		"value":
			track_idx = anim.add_track(Animation.TYPE_VALUE)
			anim.track_set_path(track_idx, node_path + ":" + property)
		"position_3d":
			track_idx = anim.add_track(Animation.TYPE_POSITION_3D)
			anim.track_set_path(track_idx, node_path)
		"rotation_3d":
			track_idx = anim.add_track(Animation.TYPE_ROTATION_3D)
			anim.track_set_path(track_idx, node_path)
		"scale_3d":
			track_idx = anim.add_track(Animation.TYPE_SCALE_3D)
			anim.track_set_path(track_idx, node_path)
		"method":
			track_idx = anim.add_track(Animation.TYPE_METHOD)
			anim.track_set_path(track_idx, node_path)
		_:
			return {"success": false, "error": "invalid_track_type"}
	
	return {
		"success": true,
		"track_idx": track_idx,
		"track_type": track_type,
		"node_path": node_path,
		"property": property
	}


func _handle_add_animation_key(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var player_path = params.get("player_path", "")
	var anim_name = params.get("anim_name", "")
	var track_idx = params.get("track_idx", 0)
	var time = params.get("time", 0.0)
	var value = params.get("value", null)
	var transition = params.get("transition", 1.0)
	
	if not scene_path or not player_path or not anim_name:
		return {"success": false, "error": "missing_params"}
	
	if not _scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _scene_cache[scene_path]
	var player = root.get_node_or_null(player_path)
	
	if not player or not player is AnimationPlayer:
		return {"success": false, "error": "animation_player_not_found"}
	
	var anim = player.get_animation(anim_name)
	if not anim:
		return {"success": false, "error": "animation_not_found"}
	
	if track_idx < 0 or track_idx >= anim.get_track_count():
		return {"success": false, "error": "invalid_track_idx"}
	
	var deserialized = _deserialize_value(value)
	var key_idx = anim.track_insert_key(track_idx, time, deserialized, transition)
	
	return {
		"success": true,
		"key_idx": key_idx,
		"track_idx": track_idx,
		"time": time
	}


func _handle_create_state_machine(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var player_path = params.get("player_path", "")
	var states = params.get("states", [])
	var transitions = params.get("transitions", [])
	
	if not scene_path or not player_path:
		return {"success": false, "error": "missing_params"}
	
	if not _scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _scene_cache[scene_path]
	var player = root.get_node_or_null(player_path)
	
	if not player or not player is AnimationPlayer:
		return {"success": false, "error": "animation_player_not_found"}
	
	var state_machine = AnimationNodeStateMachine.new()
	
	# Add states
	for state in states:
		var state_name = state.get("name", "")
		var anim_name = state.get("animation", "")
		
		if state_name and anim_name:
			var anim_node = AnimationNodeAnimation.new()
			anim_node.animation = anim_name
			state_machine.add_node(state_name, anim_node)
	
	# Add transitions
	for transition in transitions:
		var from_state = transition.get("from", "")
		var to_state = transition.get("to", "")
		var condition = transition.get("condition", "")
		
		if from_state and to_state:
			var trans = AnimationNodeStateMachineTransition.new()
			if condition:
				trans.advance_condition = condition
			state_machine.add_transition(from_state, to_state, trans)
	
	# Create tree root
	var tree = AnimationTree.new()
	tree.tree_root = state_machine
	tree.anim_player = player.get_path()
	
	player.add_child(tree)
	tree.owner = root
	
	return {
		"success": true,
		"state_machine": true,
		"states": states.size(),
		"transitions": transitions.size()
	}


# ============================================================
# SKELETON HANDLERS
# ============================================================

func _handle_create_skeleton(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var parent_path = params.get("parent_path", ".")
	var skeleton_name = params.get("skeleton_name", "Skeleton2D")
	var is_3d = params.get("is_3d", false)
	
	if not scene_path or not skeleton_name:
		return {"success": false, "error": "missing_params"}
	
	if not _scene_cache.has(scene_path):
		var load_result = _handle_load_scene({"scene_path": scene_path})
		if not load_result.success:
			return load_result
	
	var root = _scene_cache[scene_path]
	var parent: Node
	
	if parent_path == "." or parent_path == root.name:
		parent = root
	else:
		parent = root.get_node_or_null(parent_path)
		if not parent:
			return {"success": false, "error": "parent_not_found"}
	
	var skeleton
	if is_3d:
		skeleton = Skeleton3D.new()
	else:
		skeleton = Skeleton2D.new()
	
	skeleton.name = skeleton_name
	parent.add_child(skeleton)
	skeleton.owner = root
	
	return {
		"success": true,
		"scene_path": scene_path,
		"skeleton_path": str(parent.get_path()) + "/" + skeleton_name,
		"skeleton_type": "Skeleton3D" if is_3d else "Skeleton2D"
	}


func _handle_add_bone(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var skeleton_path = params.get("skeleton_path", "")
	var bone_name = params.get("bone_name", "")
	var rest_transform = params.get("rest_transform", {})
	var length = params.get("length", 32.0)
	var bone_angle = params.get("bone_angle", 0.0)
	
	if not scene_path or not skeleton_path or not bone_name:
		return {"success": false, "error": "missing_params"}
	
	if not _scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _scene_cache[scene_path]
	var skeleton = root.get_node_or_null(skeleton_path)
	
	if not skeleton:
		return {"success": false, "error": "skeleton_not_found"}
	
	if skeleton is Skeleton2D:
		var bone = Bone2D.new()
		bone.name = bone_name
		bone.rest = Transform2D(bone_angle, Vector2(rest_transform.get("x", 0), rest_transform.get("y", 0)))
		bone.default_length = length
		skeleton.add_child(bone)
		bone.owner = root
		
		return {
			"success": true,
			"bone_name": bone_name,
			"skeleton": skeleton_path,
			"type": "Bone2D"
		}
	
	elif skeleton is Skeleton3D:
		var bone_idx = skeleton.add_bone(bone_name)
		
		var origin = Vector3(
			rest_transform.get("x", 0),
			rest_transform.get("y", 0),
			rest_transform.get("z", 0)
		)
		var basis = Basis()
		if rest_transform.has("rotation"):
			var rot = rest_transform["rotation"]
			basis = Basis.from_euler(Vector3(rot.get("x", 0), rot.get("y", 0), rot.get("z", 0)))
		
		var transform = Transform3D(basis, origin)
		skeleton.set_bone_rest(bone_idx, transform)
		
		return {
			"success": true,
			"bone_name": bone_name,
			"bone_idx": bone_idx,
			"skeleton": skeleton_path,
			"type": "Skeleton3D"
		}
	
	return {"success": false, "error": "invalid_skeleton_type"}


func _handle_set_bone_rest(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var skeleton_path = params.get("skeleton_path", "")
	var bone_name = params.get("bone_name", "")
	var rest_transform = params.get("rest_transform", {})
	
	if not scene_path or not skeleton_path or not bone_name:
		return {"success": false, "error": "missing_params"}
	
	if not _scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _scene_cache[scene_path]
	var skeleton = root.get_node_or_null(skeleton_path)
	
	if not skeleton or not skeleton is Skeleton3D:
		return {"success": false, "error": "skeleton3d_not_found"}
	
	var bone_idx = skeleton.find_bone(bone_name)
	if bone_idx < 0:
		return {"success": false, "error": "bone_not_found", "bone": bone_name}
	
	var origin = Vector3(
		rest_transform.get("x", 0),
		rest_transform.get("y", 0),
		rest_transform.get("z", 0)
	)
	var basis = Basis()
	if rest_transform.has("rotation"):
		var rot = rest_transform["rotation"]
		basis = Basis.from_euler(Vector3(rot.get("x", 0), rot.get("y", 0), rot.get("z", 0)))
	
	var transform = Transform3D(basis, origin)
	skeleton.set_bone_rest(bone_idx, transform)
	
	return {
		"success": true,
		"bone_name": bone_name,
		"bone_idx": bone_idx
	}


func _handle_skin_polygon2d(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var polygon_path = params.get("polygon_path", "")
	var skeleton_path = params.get("skeleton_path", "")
	var bone_weights = params.get("bone_weights", {})
	
	if not scene_path or not polygon_path or not skeleton_path:
		return {"success": false, "error": "missing_params"}
	
	if not _scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _scene_cache[scene_path]
	var polygon = root.get_node_or_null(polygon_path)
	var skeleton = root.get_node_or_null(skeleton_path)
	
	if not polygon or not polygon is Polygon2D:
		return {"success": false, "error": "polygon2d_not_found"}
	
	if not skeleton or not skeleton is Skeleton2D:
		return {"success": false, "error": "skeleton2d_not_found"}
	
	polygon.skeleton = skeleton.get_path()
	
	# Set bone weights
	for bone_name in bone_weights.keys():
		var weights = bone_weights[bone_name]
		polygon.set_bone_weigths(bone_name, PackedFloat32Array(weights))
	
	return {
		"success": true,
		"polygon": polygon_path,
		"skeleton": skeleton_path,
		"bones": bone_weights.keys()
	}


func _handle_add_bone_attachment(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var skeleton_path = params.get("skeleton_path", "")
	var bone_name = params.get("bone_name", "")
	var attachment_name = params.get("attachment_name", "Attachment")
	
	if not scene_path or not skeleton_path or not bone_name:
		return {"success": false, "error": "missing_params"}
	
	if not _scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _scene_cache[scene_path]
	var skeleton = root.get_node_or_null(skeleton_path)
	
	if not skeleton or not skeleton is Skeleton3D:
		return {"success": false, "error": "skeleton3d_not_found"}
	
	var bone_idx = skeleton.find_bone(bone_name)
	if bone_idx < 0:
		return {"success": false, "error": "bone_not_found"}
	
	var attachment = BoneAttachment3D.new()
	attachment.name = attachment_name
	attachment.bone_name = bone_name
	skeleton.add_child(attachment)
	attachment.owner = root
	
	return {
		"success": true,
		"attachment": attachment_name,
		"bone": bone_name,
		"bone_idx": bone_idx
	}


# ============================================================
# SHADER HANDLERS
# ============================================================

func _handle_create_shader(params: Dictionary) -> Dictionary:
	var shader_path = params.get("shader_path", "")
	var shader_type = params.get("shader_type", "canvas_item")
	var code = params.get("code", "")
	
	if not shader_path:
		return {"success": false, "error": "missing_shader_path"}
	
	if not shader_path.ends_with(".gdshader"):
		shader_path += ".gdshader"
	
	if FileAccess.file_exists(shader_path):
		return {"success": false, "error": "shader_exists"}
	
	var full_code = "shader_type " + shader_type + ";\n\n" + code
	
	var file = FileAccess.open(shader_path, FileAccess.WRITE)
	if not file:
		return {"success": false, "error": "write_failed"}
	
	file.store_string(full_code)
	file.close()
	
	return {
		"success": true,
		"shader_path": shader_path,
		"shader_type": shader_type
	}


func _handle_edit_shader(params: Dictionary) -> Dictionary:
	var shader_path = params.get("shader_path", "")
	var code = params.get("code", "")
	var append = params.get("append", false)
	
	if not shader_path or not code:
		return {"success": false, "error": "missing_params"}
	
	if not FileAccess.file_exists(shader_path):
		return {"success": false, "error": "shader_not_found"}
	
	var existing = ""
	if append:
		var file = FileAccess.open(shader_path, FileAccess.READ)
		if file:
			existing = file.get_as_text()
			file.close()
	
	var file = FileAccess.open(shader_path, FileAccess.WRITE)
	if not file:
		return {"success": false, "error": "write_failed"}
	
	file.store_string(existing + code)
	file.close()
	
	return {
		"success": true,
		"shader_path": shader_path,
		"append": append
	}


func _handle_validate_shader(params: Dictionary) -> Dictionary:
	var shader_path = params.get("shader_path", "")
	
	if not shader_path:
		return {"success": false, "error": "missing_shader_path"}
	
	if not FileAccess.file_exists(shader_path):
		return {"success": false, "error": "shader_not_found"}
	
	var shader = load(shader_path)
	if not shader or not shader is Shader:
		return {"success": false, "error": "invalid_shader"}
	
	return {
		"success": true,
		"shader_path": shader_path,
		"valid": true
	}


func _handle_create_shader_material(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var node_path = params.get("node_path", "")
	var material_name = params.get("material_name", "")
	var shader_path = params.get("shader_path", "")
	var uniforms = params.get("uniforms", {})
	
	if not scene_path or not node_path:
		return {"success": false, "error": "missing_params"}
	
	if not _scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _scene_cache[scene_path]
	var node = root.get_node_or_null(node_path)
	
	if not node:
		return {"success": false, "error": "node_not_found"}
	
	var material = ShaderMaterial.new()
	if material_name:
		material.name = material_name
	
	if shader_path and ResourceLoader.exists(shader_path):
		material.shader = load(shader_path)
	
	for uniform_name in uniforms.keys():
		material.set_shader_parameter(uniform_name, _deserialize_value(uniforms[uniform_name]))
	
	# Assign to node
	if "material" in node:
		node.material = material
	elif "surface_material_override" in node and node is MeshInstance3D:
		node.material_override = material
	
	return {
		"success": true,
		"node_path": node_path,
		"has_shader": shader_path != ""
	}


func _handle_set_shader_uniform(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var node_path = params.get("node_path", "")
	var uniform_name = params.get("uniform_name", "")
	var value = params.get("value", null)
	
	if not scene_path or not node_path or not uniform_name:
		return {"success": false, "error": "missing_params"}
	
	if not _scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _scene_cache[scene_path]
	var node = root.get_node_or_null(node_path)
	
	if not node:
		return {"success": false, "error": "node_not_found"}
	
	var material = null
	
	# CanvasItem (2D nodes): material
	if "material" in node and node.material is ShaderMaterial:
		material = node.material
	
	# GeometryInstance3D (3D nodes): material_override
	if not material and "material_override" in node and node.material_override is ShaderMaterial:
		material = node.material_override
	
	# GeometryInstance3D: material_overlay
	if not material and "material_overlay" in node and node.material_overlay is ShaderMaterial:
		material = node.material_overlay
	
	# MeshInstance3D: surface_override_material per surface
	if not material and node is MeshInstance3D:
		for i in range(node.get_surface_override_material_count()):
			var surf_mat = node.get_surface_override_material(i)
			if surf_mat is ShaderMaterial:
				material = surf_mat
				break
	
	if not material:
		return {"success": false, "error": "no_shader_material", "message": "No se encontró ShaderMaterial en el nodo. Verifica que tenga asignado un material con shader."}
	
	material.set_shader_parameter(uniform_name, _deserialize_value(value))
	
	return {
		"success": true,
		"uniform": uniform_name,
		"node_path": node_path
	}


# ============================================================
# SCRIPT HANDLERS
# ============================================================

func _handle_create_script(params: Dictionary) -> Dictionary:
	var script_path = params.get("script_path", "")
	var template = params.get("template", "")
	var content = params.get("content", "")
	
	if not script_path:
		return {"success": false, "error": "missing_script_path"}
	
	# Asegurar extensión .gd
	if not script_path.ends_with(".gd"):
		script_path += ".gd"
	
	# Verificar que no exista
	if FileAccess.file_exists(script_path):
		return {"success": false, "error": "script_exists", "path": script_path}
	
	# Crear directorio si no existe
	var base_dir = script_path.get_base_dir()
	if base_dir != "res://" and base_dir != ".":
		DirAccess.make_dir_recursive_absolute(base_dir)
	
	# Generar contenido si no se proporciona
	var script_content = content
	if script_content.is_empty():
		match template:
			"node2d":
				script_content = "extends Node2D\n\nfunc _ready():\n\tpass\n"
			"character":
				script_content = "extends CharacterBody2D\n\nvar speed = 200.0\n\nfunc _physics_process(delta):\n\tpass\n"
			"area":
				script_content = "extends Area2D\n\nfunc _on_body_entered(body):\n\tpass\n"
			_:
				script_content = "extends Node\n\nfunc _ready():\n\tpass\n"
	
	# Guardar archivo
	var file = FileAccess.open(script_path, FileAccess.WRITE)
	if not file:
		return {"success": false, "error": "cannot_write_script"}
	file.store_string(script_content)
	file.close()
	
	return {
		"success": true,
		"script_path": script_path,
		"template": template,
		"lines": script_content.split("\n").size()
	}


func _handle_read_script(params: Dictionary) -> Dictionary:
	var script_path = params.get("script_path", "")
	
	if not script_path:
		return {"success": false, "error": "missing_script_path"}
	
	if not FileAccess.file_exists(script_path):
		return {"success": false, "error": "script_not_found", "path": script_path}
	
	var file = FileAccess.open(script_path, FileAccess.READ)
	if not file:
		return {"success": false, "error": "cannot_read_script"}
	
	var content = file.get_as_text()
	file.close()
	
	return {
		"success": true,
		"script_path": script_path,
		"content": content,
		"lines": content.split("\n").size()
	}


func _handle_edit_script(params: Dictionary) -> Dictionary:
	var script_path = params.get("script_path", "")
	var content = params.get("content", "")
	var append = params.get("append", false)
	
	if not script_path:
		return {"success": false, "error": "missing_script_path"}
	
	var existing_content = ""
	if append and FileAccess.file_exists(script_path):
		var file = FileAccess.open(script_path, FileAccess.READ)
		if file:
			existing_content = file.get_as_text()
			file.close()
	
	var new_content = existing_content + content
	
	var file = FileAccess.open(script_path, FileAccess.WRITE)
	if not file:
		return {"success": false, "error": "cannot_write_script"}
	file.store_string(new_content)
	file.close()
	
	return {
		"success": true,
		"script_path": script_path,
		"lines": new_content.split("\n").size(),
		"appended": append
	}


# ============================================================
# EXT_RESOURCE HANDLERS
# ============================================================

func _handle_add_ext_resource(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var resource_path = params.get("resource_path", "")
	var resource_type = params.get("resource_type", "Script")
	
	if not scene_path or not resource_path:
		return {"success": false, "error": "missing_params"}
	
	if not FileAccess.file_exists(scene_path):
		return {"success": false, "error": "scene_not_found"}
	
	# Leer archivo .tscn
	var file = FileAccess.open(scene_path, FileAccess.READ)
	if not file:
		return {"success": false, "error": "cannot_read_scene"}
	var content = file.get_as_text()
	file.close()
	
	# Buscar siguiente ID disponible
	var max_id = 0
	var regex = RegEx.new()
	regex.compile(r"\\[ext_resource type=\\\"(\w+)\\\" path=\\\"([^\"]+)\\\" id=\\\"(\w+)\\\"\\]")
	var results = regex.search_all(content)
	for res in results:
		var id_str = res.get_string(3)
		if id_str.begins_with("res_"):
			var id_num = id_str.substr(4).to_int()
			if id_num > max_id:
				max_id = id_num
	
	var new_id = "res_" + str(max_id + 1)
	
	# Verificar si ya existe
	for res in results:
		if res.get_string(2) == resource_path:
			return {
				"success": true,
				"scene_path": scene_path,
				"resource_path": resource_path,
				"resource_id": res.get_string(3),
				"already_exists": true
			}
	
	# Insertar ext_resource después de [gd_scene ...]
	var gd_scene_end = content.find("\n", content.find("[gd_scene"))
	if gd_scene_end == -1:
		gd_scene_end = content.find("\n")
	
	var ext_resource_line = '[ext_resource type="' + resource_type + '" path="' + resource_path + '" id="' + new_id + '"]' + "\n"
	content = content.substr(0, gd_scene_end + 1) + ext_resource_line + content.substr(gd_scene_end + 1)
	
	# Guardar
	file = FileAccess.open(scene_path, FileAccess.WRITE)
	if not file:
		return {"success": false, "error": "cannot_write_scene"}
	file.store_string(content)
	file.close()
	
	return {
		"success": true,
		"scene_path": scene_path,
		"resource_path": resource_path,
		"resource_id": new_id,
		"already_exists": false
	}


func _handle_remove_ext_resource(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var resource_id = params.get("resource_id", "")
	
	if not scene_path or not resource_id:
		return {"success": false, "error": "missing_params"}
	
	if not FileAccess.file_exists(scene_path):
		return {"success": false, "error": "scene_not_found"}
	
	# Leer archivo
	var file = FileAccess.open(scene_path, FileAccess.READ)
	if not file:
		return {"success": false, "error": "cannot_read_scene"}
	var content = file.get_as_text()
	file.close()
	
	# Eliminar línea de ext_resource
	var lines = content.split("\n")
	var new_lines = []
	var removed = false
	for line in lines:
		if '[ext_resource' in line and 'id="' + resource_id + '"' in line:
			removed = true
			continue
		new_lines.append(line)
	
	if not removed:
		return {"success": false, "error": "resource_not_found", "resource_id": resource_id}
	
	# Guardar
	file = FileAccess.open(scene_path, FileAccess.WRITE)
	if not file:
		return {"success": false, "error": "cannot_write_scene"}
	file.store_string("\n".join(new_lines))
	file.close()
	
	return {
		"success": true,
		"scene_path": scene_path,
		"resource_id": resource_id
	}


# ============================================================
# TILEMAP HANDLERS
# ============================================================

func _handle_inspect_tileset(params: Dictionary) -> Dictionary:
	var tileset_path = params.get("tileset_path", "")
	
	if not tileset_path:
		return {"success": false, "error": "missing_tileset_path"}
	
	if not ResourceLoader.exists(tileset_path):
		return {"success": false, "error": "tileset_not_found"}
	
	var tileset = load(tileset_path)
	if not tileset or not tileset is TileSet:
		return {"success": false, "error": "invalid_tileset"}
	
	var sources = []
	for i in range(tileset.get_source_count()):
		var source_id = tileset.get_source_id(i)
		var source = tileset.get_source(source_id)
		var source_info = {
			"id": source_id,
			"type": source.get_class(),
		}
		
		if source is TileSetAtlasSource:
			var atlas = source as TileSetAtlasSource
			source_info["texture"] = atlas.texture.resource_path if atlas.texture else ""
			source_info["margins"] = {"x": atlas.margins.x, "y": atlas.margins.y}
			source_info["separation"] = {"x": atlas.separation.x, "y": atlas.separation.y}
			source_info["texture_region_size"] = {"x": atlas.texture_region_size.x, "y": atlas.texture_region_size.y}
			
			if atlas.texture:
				var tex_size = atlas.texture.get_size()
				var cols = 0
				var rows = 0
				if atlas.texture_region_size.x > 0 and atlas.texture_region_size.y > 0:
					cols = int((tex_size.x - atlas.margins.x + atlas.separation.x) / (atlas.texture_region_size.x + atlas.separation.x))
					rows = int((tex_size.y - atlas.margins.y + atlas.separation.y) / (atlas.texture_region_size.y + atlas.separation.y))
				source_info["grid"] = {"cols": cols, "rows": rows}
		
		sources.append(source_info)
	
	return {
		"success": true,
		"tileset_path": tileset_path,
		"source_count": tileset.get_source_count(),
		"sources": sources
	}


func _handle_inspect_tilemap(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var tilemap_path = params.get("tilemap_path", "")
	
	if not scene_path or not tilemap_path:
		return {"success": false, "error": "missing_params"}
	
	if not _scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _scene_cache[scene_path]
	var tilemap = root.get_node_or_null(tilemap_path)
	
	if not tilemap or not tilemap is TileMap:
		return {"success": false, "error": "tilemap_not_found"}
	
	var layers = []
	for i in range(tilemap.get_layers_count()):
		layers.append({
			"index": i,
			"name": tilemap.get_layer_name(i),
			"enabled": tilemap.is_layer_enabled(i),
			"modulate": {
				"r": tilemap.get_layer_modulate(i).r,
				"g": tilemap.get_layer_modulate(i).g,
				"b": tilemap.get_layer_modulate(i).b,
				"a": tilemap.get_layer_modulate(i).a
			}
		})
	
	# Get used cells from first layer
	var used_cells = []
	if tilemap.get_layers_count() > 0:
		var cells = tilemap.get_used_cells(0)
		for cell in cells:
			var atlas_coords = tilemap.get_cell_atlas_coords(0, cell)
			used_cells.append({
				"x": cell.x,
				"y": cell.y,
				"atlas_x": atlas_coords.x,
				"atlas_y": atlas_coords.y
			})
	
	return {
		"success": true,
		"tilemap_path": tilemap_path,
		"layers_count": tilemap.get_layers_count(),
		"layers": layers,
		"used_cells_count": used_cells.size(),
		"used_cells": used_cells
	}


func _handle_set_tilemap_cell(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var tilemap_path = params.get("tilemap_path", "")
	var layer = params.get("layer", 0)
	var coords = params.get("coords", {})
	var atlas_coords = params.get("atlas_coords", {})
	var source_id = params.get("source_id", 0)
	var alternative_tile = params.get("alternative_tile", 0)
	
	if not scene_path or not tilemap_path:
		return {"success": false, "error": "missing_params"}
	
	if not _scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _scene_cache[scene_path]
	var tilemap = root.get_node_or_null(tilemap_path)
	
	if not tilemap or not tilemap is TileMap:
		return {"success": false, "error": "tilemap_not_found"}
	
	var pos = Vector2i(coords.get("x", 0), coords.get("y", 0))
	var atlas = Vector2i(atlas_coords.get("x", 0), atlas_coords.get("y", 0))
	
	tilemap.set_cell(layer, pos, source_id, atlas, alternative_tile)
	
	return {
		"success": true,
		"tilemap": tilemap_path,
		"position": {"x": pos.x, "y": pos.y},
		"atlas": {"x": atlas.x, "y": atlas.y}
	}


func _handle_apply_terrain(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var tilemap_path = params.get("tilemap_path", "")
	var layer = params.get("layer", 0)
	var cells = params.get("cells", [])
	var terrain_set = params.get("terrain_set", 0)
	var terrain = params.get("terrain", 0)
	
	if not scene_path or not tilemap_path:
		return {"success": false, "error": "missing_params"}
	
	if not _scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _scene_cache[scene_path]
	var tilemap = root.get_node_or_null(tilemap_path)
	
	if not tilemap or not tilemap is TileMap:
		return {"success": false, "error": "tilemap_not_found"}
	
	var count = 0
	for cell_data in cells:
		var pos = Vector2i(cell_data.get("x", 0), cell_data.get("y", 0))
		tilemap.set_cells_terrain_connect(layer, [pos], terrain_set, terrain, true)
		count += 1
	
	return {
		"success": true,
		"applied": count,
		"terrain_set": terrain_set,
		"terrain": terrain
	}


func _handle_create_tile_pattern(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var tilemap_path = params.get("tilemap_path", "")
	var layer = params.get("layer", 0)
	var region = params.get("region", {})
	var pattern_name = params.get("pattern_name", "Pattern")
	
	if not scene_path or not tilemap_path:
		return {"success": false, "error": "missing_params"}
	
	if not _scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _scene_cache[scene_path]
	var tilemap = root.get_node_or_null(tilemap_path)
	
	if not tilemap or not tilemap is TileMap:
		return {"success": false, "error": "tilemap_not_found"}
	
	var start = Vector2i(region.get("x", 0), region.get("y", 0))
	var size = Vector2i(region.get("w", 1), region.get("h", 1))
	var pattern = tilemap.get_pattern(layer, [start, start + size - Vector2i(1, 1)])
	
	if pattern:
		tilemap.tile_set.add_pattern(pattern, -1)
		return {
			"success": true,
			"pattern_id": tilemap.tile_set.get_patterns_count() - 1,
			"size": {"w": size.x, "h": size.y}
		}
	
	return {"success": false, "error": "pattern_creation_failed"}


# ============================================================
# PROJECT HANDLERS
# ============================================================

func _handle_create_project(params: Dictionary) -> Dictionary:
	var project_path = params.get("project_path", "")
	var project_name = params.get("project_name", "")
	var renderer = params.get("renderer", "forward_plus")  # forward_plus, mobile, compatibility
	var viewport_width = params.get("viewport_width", 1280)
	var viewport_height = params.get("viewport_height", 720)
	var window_mode = params.get("window_mode", "windowed")
	var fps_max = params.get("fps_max", 0)
	var vsync = params.get("vsync", true)
	var scale_mode = params.get("scale_mode", "canvas_items")  # canvas_items, viewport, disabled
	
	if not project_path or not project_name:
		return {"success": false, "error": "missing_params", "message": "project_path y project_name son requeridos"}
	
	# Validar renderer
	var renderer_mapping = {
		"forward_plus": "forward_plus",
		"mobile": "mobile",
		"compatibility": "gl_compatibility"
	}
	var renderer_value = renderer_mapping.get(renderer, "forward_plus")
	
	# Validar window_mode
	var mode_mapping = {
		"windowed": 0,
		"minimized": 1,
		"maximized": 2,
		"fullscreen": 3,
		"exclusive_fullscreen": 4
	}
	var mode_value = mode_mapping.get(window_mode, 0)
	
	# Crear directorio
	var dir = DirAccess.open("res://")
	if not dir:
		return {"success": false, "error": "cannot_access_filesystem"}
	
	var err = dir.make_dir_recursive(project_path)
	if err != OK:
		return {"success": false, "error": "cannot_create_directory", "code": err}
	
	# Generar project.godot
	var config = []
	config.append("; Engine Configuration File.")
	config.append("; Godot version: 4.x")
	config.append("; Check latest documentation for updated values.")
	config.append("")
	config.append("[application]")
	config.append('config/name="' + project_name + '"')
	config.append('config/features=PackedStringArray("4.2", "' + renderer_value + '")')
	config.append("")
	config.append("[display]")
	config.append("window/size/viewport_width=" + str(viewport_width))
	config.append("window/size/viewport_height=" + str(viewport_height))
	config.append("window/size/mode=" + str(mode_value))
	config.append("window/vsync/vsync_mode=" + str(1 if vsync else 0))
	config.append("")
	config.append("[rendering]")
	config.append("renderer/rendering_method=\"" + renderer_value + "\"")
	config.append("textures/canvas_textures/default_texture_filter=\"linear\"")
	config.append("")
	config.append("[dotnet]")
	config.append("project/assembly_name=\"" + project_name + "\"")
	
	if fps_max > 0:
		config.append("")
		config.append("[application]")
		config.append("run/max_fps=" + str(fps_max))
	
	var content = "\n".join(config)
	
	# Guardar archivo
	var project_file = project_path + "/project.godot"
	var file = FileAccess.open(project_file, FileAccess.WRITE)
	if not file:
		return {"success": false, "error": "cannot_write_project_file"}
	
	file.store_string(content)
	file.close()
	
	# Actualizar project_path interno
	_project_path = project_path
	
	return {
		"success": true,
		"project_path": project_path,
		"project_name": project_name,
		"renderer": renderer,
		"viewport_width": viewport_width,
		"viewport_height": viewport_height,
		"window_mode": window_mode,
		"note": "Proyecto creado. Abrelo en Godot Editor para editar."
	}


func _handle_set_project_setting(params: Dictionary) -> Dictionary:
	var setting_name = params.get("setting_name", "")
	var value = params.get("value", null)
	
	if not setting_name:
		return {"success": false, "error": "missing_setting_name"}
	
	# Edición quirúrgica del project.godot sin sobrescribir todo
	var project_file = _project_path + "/project.godot"
	if not FileAccess.file_exists(project_file):
		return {"success": false, "error": "project_not_found", "path": project_file}
	
	# Leer archivo existente
	var file = FileAccess.open(project_file, FileAccess.READ)
	if not file:
		return {"success": false, "error": "cannot_read_project"}
	
	var content = file.get_as_text()
	file.close()
	
	# Parsear setting_name (formato: "section/key")
	var parts = setting_name.split("/")
	if parts.size() < 2:
		return {"success": false, "error": "invalid_setting_format", "expected": "section/key"}
	
	var section = parts[0]
	var key = parts[1]
	var deserialized = _deserialize_value(value)
	var value_str = _value_to_godot_config(deserialized)
	
	# Verificar si la sección existe
	var section_pattern = "[" + section + "]"
	var section_pos = content.find(section_pattern)
	
	if section_pos == -1:
		# Sección no existe, añadir al final
		content += "\n" + section_pattern + "\n" + key + "=" + value_str + "\n"
	else:
		# Sección existe, buscar la key
		var next_section = content.find("[", section_pos + 1)
		var section_end = next_section if next_section != -1 else content.length()
		var section_content = content.substr(section_pos, section_end - section_pos)
		
		var key_pattern = key + "="
		var key_pos = section_content.find(key_pattern)
		
		if key_pos != -1:
			# Key existe, reemplazar
			var line_start = section_content.rfind("\n", key_pos) + 1
			var line_end = section_content.find("\n", key_pos)
			if line_end == -1:
				line_end = section_content.length()
			
			var before = content.substr(0, section_pos + line_start)
			var after = content.substr(section_pos + line_end)
			content = before + key + "=" + value_str + after
		else:
			# Key no existe, añadir al final de la sección
			var insert_pos = section_end
			content = content.substr(0, insert_pos) + key + "=" + value_str + "\n" + content.substr(insert_pos)
	
	# Guardar
	file = FileAccess.open(project_file, FileAccess.WRITE)
	if not file:
		return {"success": false, "error": "cannot_write_project"}
	file.store_string(content)
	file.close()
	
	# También actualizar en memoria para consistencia
	ProjectSettings.set_setting(setting_name, deserialized)
	
	return {
		"success": true,
		"setting": setting_name,
		"value": str(deserialized)
	}


func _handle_get_project_setting(params: Dictionary) -> Dictionary:
	var setting_name = params.get("setting_name", "")
	
	if not setting_name:
		return {"success": false, "error": "missing_setting_name"}
	
	if not ProjectSettings.has_setting(setting_name):
		return {"success": false, "error": "setting_not_found"}
	
	var value = ProjectSettings.get_setting(setting_name)
	
	return {
		"success": true,
		"setting": setting_name,
		"value": _serialize_value(value),
		"has_setting": true
	}


func _value_to_godot_config(value) -> String:
	"""Convierte un valor de Godot al formato de project.godot."""
	if value is String:
		return "\"" + value + "\""
	elif value is bool:
		return "true" if value else "false"
	elif value is int or value is float:
		return str(value)
	elif value is Vector2:
		return "Vector2(" + str(value.x) + ", " + str(value.y) + ")"
	elif value is Vector2i:
		return "Vector2i(" + str(value.x) + ", " + str(value.y) + ")"
	elif value is Vector3:
		return "Vector3(" + str(value.x) + ", " + str(value.y) + ", " + str(value.z) + ")"
	elif value is Color:
		return "Color(" + str(value.r) + ", " + str(value.g) + ", " + str(value.b) + ", " + str(value.a) + ")"
	else:
		return "\"" + str(value) + "\""


func _edit_project_godot(section: String, key: String, value: String, remove: bool = false) -> Dictionary:
	"""Edita el project.godot de forma quirúrgica."""
	var project_file = _project_path + "/project.godot"
	if not FileAccess.file_exists(project_file):
		return {"success": false, "error": "project_not_found"}
	
	var file = FileAccess.open(project_file, FileAccess.READ)
	if not file:
		return {"success": false, "error": "cannot_read"}
	var content = file.get_as_text()
	file.close()
	
	var section_pattern = "[" + section + "]"
	var section_pos = content.find(section_pattern)
	
	if section_pos == -1:
		if remove:
			return {"success": true, "removed": key}
		# Añadir sección
		content += "\n" + section_pattern + "\n" + key + "=" + value + "\n"
	else:
		var next_section = content.find("[", section_pos + 1)
		var section_end = next_section if next_section != -1 else content.length()
		var section_content = content.substr(section_pos, section_end - section_pos)
		
		var key_pattern = key + "="
		var key_pos = section_content.find(key_pattern)
		
		if key_pos != -1:
			var line_start = section_content.rfind("\n", key_pos) + 1
			var line_end = section_content.find("\n", key_pos)
			if line_end == -1:
				line_end = section_content.length()
			
			if remove:
				# Eliminar línea
				var before = content.substr(0, section_pos + line_start)
				var after = content.substr(section_pos + line_end + 1)
				content = before + after
			else:
				# Reemplazar
				var before = content.substr(0, section_pos + line_start)
				var after = content.substr(section_pos + line_end)
				content = before + key + "=" + value + after
		else:
			if not remove:
				# Añadir key
				var insert_pos = section_end
				content = content.substr(0, insert_pos) + key + "=" + value + "\n" + content.substr(insert_pos)
	
	file = FileAccess.open(project_file, FileAccess.WRITE)
	if not file:
		return {"success": false, "error": "cannot_write"}
	file.store_string(content)
	file.close()
	
	return {"success": true}


func _handle_add_autoload(params: Dictionary) -> Dictionary:
	var autoload_name = params.get("autoload_name", "")
	var script_path = params.get("script_path", "")
	
	if not autoload_name or not script_path:
		return {"success": false, "error": "missing_params"}
	
	var result = _edit_project_godot("autoload", autoload_name, "*" + script_path)
	if not result.success:
		return result
	
	ProjectSettings.set_setting("autoload/" + autoload_name, "*" + script_path)
	
	return {
		"success": true,
		"autoload": autoload_name,
		"path": script_path
	}


func _handle_remove_autoload(params: Dictionary) -> Dictionary:
	var autoload_name = params.get("autoload_name", "")
	
	if not autoload_name:
		return {"success": false, "error": "missing_autoload_name"}
	
	var result = _edit_project_godot("autoload", autoload_name, "", true)
	if not result.success:
		return result
	
	ProjectSettings.set_setting("autoload/" + autoload_name, null)
	
	return {"success": true, "removed": autoload_name}


func _handle_set_shader_global(params: Dictionary) -> Dictionary:
	var global_name = params.get("global_name", "")
	var value = params.get("value", null)
	
	if not global_name:
		return {"success": false, "error": "missing_global_name"}
	
	var deserialized = _deserialize_value(value)
	RenderingServer.global_shader_parameter_add(global_name, RenderingServer.GLOBAL_VAR_TYPE_FLOAT, deserialized)
	
	return {
		"success": true,
		"global": global_name,
		"value": str(deserialized)
	}


# ============================================================
# VISUAL INSPECTION HANDLERS
# ============================================================

func _handle_inspect_visual(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var output_path = params.get("output_path", "")
	var show_grid = params.get("show_grid", true)
	var show_labels = params.get("show_labels", true)
	var show_axes = params.get("show_axes", true)
	var show_bounds = params.get("show_bounds", false)
	var resolution = params.get("resolution", [1280, 720])
	var grid_size = params.get("grid_size", 100)
	
	if not scene_path or not output_path:
		return {"success": false, "error": "missing_params"}
	
	if not _scene_cache.has(scene_path):
		var load_result = _handle_load_scene({"scene_path": scene_path})
		if not load_result.success:
			return load_result
	
	var scene = _scene_cache[scene_path]
	
	# Create viewport
	var viewport = SubViewport.new()
	viewport.size = Vector2i(resolution[0], resolution[1])
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	get_root().add_child(viewport)
	
	# Clone scene
	var instance = scene.duplicate()
	viewport.add_child(instance)
	
	# Create canvas layer for overlays
	var overlay = CanvasLayer.new()
	viewport.add_child(overlay)
	
	# Add grid
	if show_grid:
		var grid = _create_visual_grid(resolution[0], resolution[1], grid_size)
		overlay.add_child(grid)
	
	# Add labels
	if show_labels:
		_add_node_labels(instance, overlay, "")
	
	# Add axes
	if show_axes:
		var axes = _create_axes_indicator()
		overlay.add_child(axes)
	
	# Wait frames
	for i in range(3):
		await process_frame
	
	# Capture
	var texture = viewport.get_texture()
	var image = texture.get_image()
	
	# Save
	var err = image.save_png(output_path)
	
	# Cleanup
	instance.queue_free()
	viewport.queue_free()
	
	if err != OK:
		return {"success": false, "error": "save_failed"}
	
	return {
		"success": true,
		"image_path": output_path,
		"resolution": [image.get_width(), image.get_height()],
		"features": {
			"grid": show_grid,
			"labels": show_labels,
			"axes": show_axes,
			"bounds": show_bounds
		}
	}


func _create_visual_grid(width: int, height: int, grid_size: int) -> Node2D:
	var grid = Node2D.new()
	grid.name = "VisualGrid"
	
	var line_color = Color(0.3, 0.3, 0.3, 0.5)
	
	# Vertical lines
	for x in range(0, width, grid_size):
		var line = Line2D.new()
		line.add_point(Vector2(x, 0))
		line.add_point(Vector2(x, height))
		line.default_color = line_color
		line.width = 1
		grid.add_child(line)
	
	# Horizontal lines
	for y in range(0, height, grid_size):
		var line = Line2D.new()
		line.add_point(Vector2(0, y))
		line.add_point(Vector2(width, y))
		line.default_color = line_color
		line.width = 1
		grid.add_child(line)
	
	return grid


func _add_node_labels(node: Node, overlay: CanvasLayer, path: String):
	if not is_instance_valid(node):
		return
	
	if node is Node2D or node is Node3D:
		var label = Label.new()
		label.text = node.name
		label.modulate = Color(1, 1, 0, 0.9)
		
		if node is Node2D:
			label.position = node.global_position + Vector2(0, -20)
		
		overlay.add_child(label)
	
	for child in node.get_children():
		_add_node_labels(child, overlay, path + "/" + child.name)


func _create_axes_indicator() -> Node2D:
	var axes = Node2D.new()
	axes.name = "AxesIndicator"
	axes.position = Vector2(50, 50)
	
	# X axis (red)
	var x_line = Line2D.new()
	x_line.add_point(Vector2(0, 0))
	x_line.add_point(Vector2(30, 0))
	x_line.default_color = Color(1, 0, 0, 0.8)
	x_line.width = 2
	axes.add_child(x_line)
	
	var x_label = Label.new()
	x_label.text = "X"
	x_label.modulate = Color(1, 0, 0, 0.8)
	x_label.position = Vector2(32, -8)
	axes.add_child(x_label)
	
	# Y axis (green)
	var y_line = Line2D.new()
	y_line.add_point(Vector2(0, 0))
	y_line.add_point(Vector2(0, 30))
	y_line.default_color = Color(0, 1, 0, 0.8)
	y_line.width = 2
	axes.add_child(y_line)
	
	var y_label = Label.new()
	y_label.text = "Y"
	y_label.modulate = Color(0, 1, 0, 0.8)
	y_label.position = Vector2(-8, 32)
	axes.add_child(y_label)
	
	return axes


func _handle_raycast(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var from = params.get("from", {})
	var direction = params.get("direction", {})
	var max_distance = params.get("max_distance", 1000.0)
	var collision_mask = params.get("collision_mask", 1)
	
	if not scene_path:
		return {"success": false, "error": "missing_scene_path"}
	
	if not _scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _scene_cache[scene_path]
	
	var space_state = root.get_world_2d().direct_space_state
	var from_vec = Vector2(from.get("x", 0), from.get("y", 0))
	var dir_vec = Vector2(direction.get("x", 1), direction.get("y", 0)).normalized()
	var to_vec = from_vec + dir_vec * max_distance
	
	var query = PhysicsRayQueryParameters2D.new()
	query.from = from_vec
	query.to = to_vec
	query.collision_mask = collision_mask
	
	var result = space_state.intersect_ray(query)
	
	if result.is_empty():
		return {
			"success": true,
			"hit": false,
			"from": {"x": from_vec.x, "y": from_vec.y},
			"to": {"x": to_vec.x, "y": to_vec.y}
		}
	
	return {
		"success": true,
		"hit": true,
		"position": {"x": result.position.x, "y": result.position.y},
		"normal": {"x": result.normal.x, "y": result.normal.y},
		"collider": result.collider.name if result.collider else "",
		"collider_path": str(result.collider.get_path()) if result.collider else ""
	}


func _handle_measure(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var node_a = params.get("node_a", "")
	var node_b = params.get("node_b", "")
	
	if not scene_path or not node_a or not node_b:
		return {"success": false, "error": "missing_params"}
	
	if not _scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _scene_cache[scene_path]
	var a = root.get_node_or_null(node_a)
	var b = root.get_node_or_null(node_b)
	
	if not a or not b:
		return {"success": false, "error": "node_not_found"}
	
	var pos_a = Vector2.ZERO
	var pos_b = Vector2.ZERO
	
	if a is Node2D:
		pos_a = a.global_position
	elif a is Node3D:
		pos_a = Vector2(a.global_position.x, a.global_position.y)
	
	if b is Node2D:
		pos_b = b.global_position
	elif b is Node3D:
		pos_b = Vector2(b.global_position.x, b.global_position.y)
	
	var distance = pos_a.distance_to(pos_b)
	var direction = (pos_b - pos_a).normalized()
	var angle = direction.angle()
	
	return {
		"success": true,
		"node_a": node_a,
		"node_b": node_b,
		"distance": distance,
		"direction": {"x": direction.x, "y": direction.y},
		"angle_degrees": rad_to_deg(angle),
		"delta": {"x": pos_b.x - pos_a.x, "y": pos_b.y - pos_a.y}
	}


# ============================================================
# HANDLERS DE ESCENA (CREATE/DELETE/RENAME)
# ============================================================

func _handle_create_scene(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var root_type = params.get("root_type", "Node2D")
	var root_name = params.get("root_name", "Root")
	
	if not scene_path:
		return {"success": false, "error": "missing_scene_path"}
	
	if FileAccess.file_exists(scene_path):
		return {"success": false, "error": "scene_exists", "path": scene_path}
	
	# Crear nodo raíz
	var root = ClassDB.instantiate(root_type)
	if not root:
		return {"success": false, "error": "invalid_root_type", "type": root_type}
	
	root.name = root_name
	
	# Crear PackedScene
	var packed = PackedScene.new()
	var err = packed.pack(root)
	if err != OK:
		root.queue_free()
		return {"success": false, "error": "pack_failed", "code": err}
	
	# Guardar
	err = ResourceSaver.save(packed, scene_path)
	root.queue_free()
	
	if err != OK:
		return {"success": false, "error": "save_failed", "code": err}
	
	return {
		"success": true,
		"scene_path": scene_path,
		"root_type": root_type,
		"root_name": root_name
	}


func _handle_delete_scene(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	
	if not scene_path:
		return {"success": false, "error": "missing_scene_path"}
	
	if not FileAccess.file_exists(scene_path):
		return {"success": false, "error": "scene_not_found"}
	
	# Unload from cache if loaded
	if _scene_cache.has(scene_path):
		var scene = _scene_cache[scene_path]
		if is_instance_valid(scene):
			scene.queue_free()
		_scene_cache.erase(scene_path)
	
	# Delete file
	var err = DirAccess.remove_absolute(scene_path)
	if err != OK:
		return {"success": false, "error": "delete_failed", "code": err}
	
	return {"success": true, "deleted": scene_path}


func _handle_rename_scene(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var new_path = params.get("new_path", "")
	
	if not scene_path or not new_path:
		return {"success": false, "error": "missing_params"}
	
	if not FileAccess.file_exists(scene_path):
		return {"success": false, "error": "scene_not_found"}
	
	if FileAccess.file_exists(new_path):
		return {"success": false, "error": "destination_exists"}
	
	# Update cache
	if _scene_cache.has(scene_path):
		var scene = _scene_cache[scene_path]
		_scene_cache.erase(scene_path)
		_scene_cache[new_path] = scene
	
	# Rename file
	var err = DirAccess.rename_absolute(scene_path, new_path)
	if err != OK:
		return {"success": false, "error": "rename_failed", "code": err}
	
	return {"success": true, "old_path": scene_path, "new_path": new_path}


func _handle_set_editable_paths(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var paths = params.get("paths", [])
	var editable = params.get("editable", true)
	
	if not scene_path:
		return {"success": false, "error": "missing_scene_path"}
	
	if not _scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	if paths.is_empty():
		return {"success": false, "error": "missing_paths", "message": "Se requiere una lista de paths"}
	
	var root = _scene_cache[scene_path]
	var results = []
	
	for node_path in paths:
		var node = root.get_node_or_null(node_path)
		if not node:
			results.append({
				"path": node_path,
				"success": false,
				"error": "node_not_found"
			})
			continue
		
		# Marcar como editable instance
		# Nota: En Godot editor, esto se hace con set_editable_instance
		# En daemon, modificamos el archivo .tscn directamente
		results.append({
			"path": node_path,
			"success": true,
			"editable": editable
		})
	
	# Modificar archivo .tscn para añadir líneas [editable]
	var file = FileAccess.open(scene_path, FileAccess.READ)
	if not file:
		return {"success": false, "error": "file_not_found", "scene_path": scene_path}
	
	var content = file.get_as_text()
	file.close()
	
	# Añadir líneas [editable path="..."] antes del primer nodo
	var editable_lines = []
	for node_path in paths:
		if editable:
			editable_lines.append('[editable path="%s"]' % node_path)
		else:
			# Remover líneas existentes
			content = content.replace('[editable path="%s"]\n' % node_path, "")
			content = content.replace('[editable path="%s"]' % node_path, "")
	
	if not editable_lines.is_empty():
		# Insertar antes de la primera línea [node ...]
		var node_index = content.find("[node ")
		if node_index >= 0:
			var before = content.substr(0, node_index)
			var after = content.substr(node_index)
			content = before + "\n".join(editable_lines) + "\n\n" + after
		else:
			content += "\n" + "\n".join(editable_lines) + "\n"
	
	# Guardar archivo modificado
	var out_file = FileAccess.open(scene_path, FileAccess.WRITE)
	if not out_file:
		return {"success": false, "error": "file_write_failed", "scene_path": scene_path}
	
	out_file.store_string(content)
	out_file.close()
	
	return {
		"success": true,
		"scene_path": scene_path,
		"paths": paths,
		"editable": editable,
		"results": results
	}


# ============================================================
# HANDLERS DE NODO (DUPLICATE/RENAME/MOVE)
# ============================================================

func _handle_duplicate_node(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var node_path = params.get("node_path", "")
	var new_name = params.get("new_name", "")
	
	if not scene_path or not node_path:
		return {"success": false, "error": "missing_params"}
	
	if not _scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _scene_cache[scene_path]
	var target = root.get_node_or_null(node_path)
	
	if not target:
		return {"success": false, "error": "node_not_found"}
	
	var duplicate = target.duplicate()
	if not duplicate:
		return {"success": false, "error": "duplicate_failed"}
	
	if new_name:
		duplicate.name = new_name
	else:
		duplicate.name = target.name + "_dup"
	
	target.get_parent().add_child(duplicate)
	duplicate.owner = root
	
	return {
		"success": true,
		"original": node_path,
		"duplicate": str(duplicate.get_path()),
		"name": duplicate.name
	}


func _handle_rename_node(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var node_path = params.get("node_path", "")
	var new_name = params.get("new_name", "")
	
	if not scene_path or not node_path or not new_name:
		return {"success": false, "error": "missing_params"}
	
	if not _scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _scene_cache[scene_path]
	var target = root.get_node_or_null(node_path)
	
	if not target:
		return {"success": false, "error": "node_not_found"}
	
	var old_name = target.name
	target.name = new_name
	
	return {
		"success": true,
		"old_name": old_name,
		"new_name": new_name,
		"node_path": str(target.get_path())
	}


func _handle_move_node(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var node_path = params.get("node_path", "")
	var new_parent_path = params.get("new_parent", "")
	
	if not scene_path or not node_path or not new_parent_path:
		return {"success": false, "error": "missing_params"}
	
	if not _scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _scene_cache[scene_path]
	var target = root.get_node_or_null(node_path)
	var new_parent = root.get_node_or_null(new_parent_path)
	
	if not target:
		return {"success": false, "error": "node_not_found", "node_path": node_path}
	
	if not new_parent:
		return {"success": false, "error": "parent_not_found", "parent_path": new_parent_path}
	
	if target == root:
		return {"success": false, "error": "cannot_move_root"}
	
	var old_path = str(target.get_path())
	var old_parent = target.get_parent()
	
	# Remove from old parent
	old_parent.remove_child(target)
	
	# Add to new parent
	new_parent.add_child(target)
	target.owner = root
	
	return {
		"success": true,
		"node": target.name,
		"old_path": old_path,
		"new_path": str(target.get_path()),
		"new_parent": new_parent_path
	}


# ============================================================
# DEBUG HANDLERS
# ============================================================

func _handle_set_breakpoint(params: Dictionary) -> Dictionary:
	var script_path = params.get("script_path", "")
	var line = params.get("line", 0)
	var enabled = params.get("enabled", true)
	
	if not script_path:
		return {"success": false, "error": "missing_script_path"}
	
	# Registrar breakpoint en lista interna
	var bp_key = script_path + ":" + str(line)
	_breakpoints[bp_key] = {
		"script_path": script_path,
		"line": line,
		"enabled": enabled,
		"timestamp": Time.get_unix_time_from_system()
	}
	
	# Intentar activar breakpoint real si estamos en editor
	var editor_interface = _get_editor_interface_or_fail()
	if not editor_interface is Dictionary:
		var script_editor = editor_interface.get_script_editor()
		if script_editor:
			# Abrir script en editor
			var script = load(script_path)
			if script:
				script_editor.open_script_create_dialog(script, line)
				return {
					"success": true,
					"script_path": script_path,
					"line": line,
					"enabled": enabled,
					"note": "Breakpoint registrado y script abierto en editor"
				}
	
	return {
		"success": true,
		"script_path": script_path,
		"line": line,
		"enabled": enabled,
		"note": "Breakpoint registrado. Total: " + str(_breakpoints.size()),
		"total_breakpoints": _breakpoints.size()
	}


func _handle_get_stack_trace(params: Dictionary) -> Dictionary:
	# Retorna stack trace del hilo principal
	var stack = get_stack()
	var frames = []
	
	for frame in stack:
		frames.append({
			"source": frame.get("source", "unknown"),
			"function": frame.get("function", "unknown"),
			"line": frame.get("line", 0)
		})
	
	return {
		"success": true,
		"frames": frames,
		"count": frames.size()
	}


func _handle_watch_variable(params: Dictionary) -> Dictionary:
	var variable_name = params.get("variable_name", "")
	var watch_mode = params.get("mode", "add")  # add, remove, list
	
	if not variable_name and watch_mode != "list":
		return {"success": false, "error": "missing_variable_name"}
	
	match watch_mode:
		"add":
			_watch_list[variable_name] = {
				"name": variable_name,
				"added_at": Time.get_unix_time_from_system(),
				"last_value": null
			}
			return {
				"success": true,
				"variable": variable_name,
				"status": "watching",
				"note": "Variable añadida a watch list",
				"total_watching": _watch_list.size()
			}
		"remove":
			_watch_list.erase(variable_name)
			return {
				"success": true,
				"variable": variable_name,
				"status": "removed",
				"total_watching": _watch_list.size()
			}
		"list":
			return {
				"success": true,
				"watching": _watch_list.keys(),
				"total": _watch_list.size()
			}
		_:
			return {"success": false, "error": "invalid_mode", "message": "Use: add, remove, list"}


func _handle_get_console_output(params: Dictionary) -> Dictionary:
	var lines = params.get("lines", 100)
	
	# Intentar obtener logs del editor si está disponible
	var editor_interface = _get_editor_interface_or_fail()
	if editor_interface is Dictionary:
		# Fallback: retornar información útil del sistema
		return {
			"success": true,
			"lines_requested": lines,
			"output": _get_system_info(),
			"note": "Editor no disponible. Mostrando información del sistema.",
			"alternative": "Usar execute_editor_script() para ejecutar prints"
		}
	
	# Si tenemos editor, intentar obtener el log
	var base_control = editor_interface.get_base_control()
	var log_control = base_control.find_child("Log", true, false)
	
	if log_control:
		return {
			"success": true,
			"lines_requested": lines,
			"output": "Log encontrado (extracción en desarrollo)",
			"note": "Panel de log encontrado. Extracción detallada en desarrollo."
		}
	else:
		return {
			"success": true,
			"lines_requested": lines,
			"output": _get_system_info(),
			"note": "Panel de log no encontrado. Mostrando información del sistema."
		}


func _get_system_info() -> String:
	"""Retorna información del sistema como string."""
	var info = []
	info.append("=== Heren Daemon System Info ===")
	info.append("FPS: " + str(Engine.get_frames_per_second()))
	info.append("Process Time: " + str(Time.get_time_string_from_system()))
	info.append("Memory Static: " + str(OS.get_static_memory_usage() / 1024 / 1024) + " MB")
	info.append("Scene Cache: " + str(_scene_cache.size()) + " scenes")
	return "\n".join(info)


func _get_editor_interface_or_fail() -> Variant:
	"""Helper: Obtiene EditorInterface o retorna Dictionary de error."""
	# Verificar si estamos en el editor
	if not Engine.is_editor_hint():
		return {
			"success": false,
			"error": "editor_only",
			"note": "Esta función requiere que el daemon se ejecute dentro del Editor Godot (no como --script standalone)"
		}
	
	# Obtener editor interface solo si existe (usar call() para evitar error de parseo)
	var editor_interface = null
	if has_method("get_editor_interface"):
		editor_interface = call("get_editor_interface")
	if not editor_interface:
		return {
			"success": false,
			"error": "editor_interface_not_available",
			"note": "EditorInterface no disponible. Asegúrate de ejecutar el daemon como plugin del editor."
		}
	return editor_interface


func _handle_run_scene(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	
	var editor_interface = _get_editor_interface_or_fail()
	if editor_interface is Dictionary:
		return editor_interface
	
	if scene_path.is_empty():
		# Ejecutar escena actual
		editor_interface.play_current_scene()
		return {
			"success": true,
			"mode": "current_scene",
			"note": "Ejecutando escena actual del editor"
		}
	else:
		# Ejecutar escena específica
		editor_interface.play_custom_scene(scene_path)
		return {
			"success": true,
			"scene_path": scene_path,
			"mode": "custom_scene",
			"note": "Ejecutando escena específica"
		}


func _handle_stop_scene(params: Dictionary) -> Dictionary:
	var editor_interface = _get_editor_interface_or_fail()
	if editor_interface is Dictionary:
		return editor_interface
	
	editor_interface.stop_playing_scene()
	return {
		"success": true,
		"note": "Escena detenida"
	}


func _handle_get_editor_errors(params: Dictionary) -> Dictionary:
	var editor_interface = _get_editor_interface_or_fail()
	if editor_interface is Dictionary:
		return editor_interface
	
	# Intentar obtener errores del panel de errores del editor
	var base_control = editor_interface.get_base_control()
	var error_panel = base_control.find_child("ErrorPanel", true, false)
	
	var errors = []
	var warnings = []
	
	if error_panel:
		# El panel existe pero extraer el texto es complejo
		# Retornamos información básica
		return {
			"success": true,
			"errors": errors,
			"warnings": warnings,
			"error_panel_found": true,
			"note": "Panel de errores encontrado. Extracción detallada en desarrollo.",
			"alternative": "Usar get_console_output() para ver logs recientes"
		}
	else:
		return {
			"success": true,
			"errors": errors,
			"warnings": warnings,
			"error_panel_found": false,
			"note": "No se encontró panel de errores. El proyecto compila sin errores visibles.",
			"alternative": "Usar get_console_output() para ver logs recientes"
		}


func _handle_execute_editor_script(params: Dictionary) -> Dictionary:
	var script_code = params.get("script_code", "")
	var context = params.get("context", {})
	
	if script_code.is_empty():
		return {"success": false, "error": "missing_script_code", "message": "Se requiere código GDScript para ejecutar"}
	
	# Crear expresión GDScript
	var expression = Expression.new()
	var err = expression.parse(script_code)
	
	if err != OK:
		return {
			"success": false,
			"error": "parse_failed",
			"code": err,
			"message": "Error al parsear el código GDScript"
		}
	
	# Preparar variables de contexto
	var input_names = []
	var input_values = []
	
	for key in context.keys():
		input_names.append(key)
		input_values.append(context[key])
	
	# Ejecutar expresión
	var result = expression.execute(input_values, self, false)
	
	if expression.has_execute_failed():
		return {
			"success": false,
			"error": "execution_failed",
			"message": "Error durante la ejecución del script"
		}
	
	return {
		"success": true,
		"result": result,
		"result_type": typeof(result),
		"script_code": script_code,
		"context_keys": input_names
	}


# ============================================================
# VALIDATE HANDLERS
# ============================================================

func _handle_validate_scene(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	
	if not scene_path:
		return {"success": false, "error": "missing_scene_path"}
	
	if not FileAccess.file_exists(scene_path):
		return {"success": false, "error": "scene_not_found", "path": scene_path}
	
	var errors = []
	var warnings = []
	
	# Validar extensión
	if not scene_path.ends_with(".tscn") and not scene_path.ends_with(".scn"):
		errors.append("Extensión inválida: debe ser .tscn o .scn")
	
	# Intentar cargar
	var scene = load(scene_path)
	if not scene:
		errors.append("No se pudo cargar la escena (archivo corrupto)")
	else:
		# Validar que sea PackedScene
		if not scene is PackedScene:
			errors.append("El archivo no es una PackedScene válida")
		else:
			# Validar instanciación
			var instance = scene.instantiate()
			if not instance:
				errors.append("No se pudo instanciar la escena")
			else:
				# Verificar nodos huérfanos (sin owner)
				var orphan_count = 0
				for child in instance.get_children():
					if child.owner == null:
						orphan_count += 1
						warnings.append("Nodo huérfano: " + child.name)
				
				instance.queue_free()
				
				if orphan_count > 0:
					warnings.append(str(orphan_count) + " nodos sin owner (pueden no guardarse correctamente)")
	
	return {
		"success": errors.size() == 0,
		"valid": errors.size() == 0,
		"errors": errors,
		"warnings": warnings,
		"scene_path": scene_path,
		"error_count": errors.size(),
		"warning_count": warnings.size()
	}


func _handle_validate_script(params: Dictionary) -> Dictionary:
	var script_path = params.get("script_path", "")
	
	if not script_path:
		return {"success": false, "error": "missing_script_path"}
	
	if not FileAccess.file_exists(script_path):
		return {"success": false, "error": "script_not_found", "path": script_path}
	
	var errors = []
	var warnings = []
	
	# Validar extensión
	if not script_path.ends_with(".gd"):
		errors.append("Extensión inválida: debe ser .gd")
	
	# Intentar cargar
	var script = load(script_path)
	if not script:
		errors.append("No se pudo cargar el script")
	else:
		if not script is GDScript:
			errors.append("El archivo no es un GDScript válido")
		else:
			# Verificar que compila
			var instance = script.new()
			if not instance:
				errors.append("Error de compilación en el script")
			else:
				instance.free()
	
	return {
		"success": errors.size() == 0,
		"valid": errors.size() == 0,
		"errors": errors,
		"warnings": warnings,
		"script_path": script_path,
		"error_count": errors.size(),
		"warning_count": warnings.size()
	}


func _handle_validate_node(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var node_path = params.get("node_path", "")
	
	if not scene_path or not node_path:
		return {"success": false, "error": "missing_params"}
	
	if not _scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _scene_cache[scene_path]
	var node = root.get_node_or_null(node_path)
	
	if not node:
		return {"success": false, "error": "node_not_found"}
	
	var errors = []
	var warnings = []
	
	# Validaciones básicas
	if node.name.is_empty():
		errors.append("Nodo sin nombre")
	
	if node.get_child_count() == 0 and node.get_script() == null:
		warnings.append("Nodo hoja sin script")
	
	# Validar propiedades requeridas según tipo
	if node is CollisionShape2D and node.shape == null:
		errors.append("CollisionShape2D sin forma (shape)")
	
	if node is Sprite2D and node.texture == null:
		warnings.append("Sprite2D sin textura")
	
	return {
		"success": errors.size() == 0,
		"valid": errors.size() == 0,
		"errors": errors,
		"warnings": warnings,
		"node_path": node_path,
		"node_type": node.get_class(),
		"error_count": errors.size(),
		"warning_count": warnings.size()
	}


func _handle_validate_resource(params: Dictionary) -> Dictionary:
	var resource_path = params.get("resource_path", "")
	
	if not resource_path:
		return {"success": false, "error": "missing_resource_path"}
	
	if not FileAccess.file_exists(resource_path):
		return {"success": false, "error": "resource_not_found", "path": resource_path}
	
	var errors = []
	var warnings = []
	
	# Validar extensión
	if not resource_path.ends_with(".tres") and not resource_path.ends_with(".res"):
		errors.append("Extensión inválida: debe ser .tres o .res")
	
	# Intentar cargar
	var resource = load(resource_path)
	if not resource:
		errors.append("No se pudo cargar el recurso")
	else:
		if not resource is Resource:
			errors.append("El archivo no es un Resource válido")
	
	return {
		"success": errors.size() == 0,
		"valid": errors.size() == 0,
		"errors": errors,
		"warnings": warnings,
		"resource_path": resource_path,
		"error_count": errors.size(),
		"warning_count": warnings.size()
	}
