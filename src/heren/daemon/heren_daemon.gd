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

# Command registry
var _handlers: Dictionary = {}

# Heartbeat - usamos tiempo acumulado en vez de Timer
var _heartbeat_accumulator: float = 0.0

# Estado
var _project_path: String = ""
var _is_ready: bool = false


func _initialize():
	print("[HEREN] Iniciando daemon...")
	
	# Limitar FPS para ahorrar recursos
	Engine.max_fps = 10
	print("[HEREN] FPS limitado a: ", Engine.max_fps)
	
	# Obtener project path de argumentos
	_project_path = _get_project_path()
	print("[HEREN] Proyecto: ", _project_path)
	
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
	# Procesar heartbeat
	_process_heartbeat(delta)
	
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
				print("[HEREN] Error aceptando conexión WebSocket: ", err)
	
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
	_handlers["add_node"] = _handle_add_node
	_handlers["remove_node"] = _handle_remove_node
	_handlers["set_property"] = _handle_set_property
	_handlers["get_node_properties"] = _handle_get_node_properties
	
	_handlers["load_scene"] = _handle_load_scene
	_handlers["unload_scene"] = _handle_unload_scene
	_handlers["get_loaded_scenes"] = _handle_get_loaded_scenes
	
	_handlers["screenshot"] = _handle_screenshot
	_handlers["capture_viewport"] = _handle_capture_viewport
	_handlers["performance_metrics"] = _handle_performance_metrics
	
	_handlers["batch"] = _handle_batch
	
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
	
	# Agregar a árbol pero oculto y deshabilitado
	scene_instance.process_mode = Node.PROCESS_MODE_DISABLED
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
	var parent_path = params.get("parent_path", ".")
	var node_type = params.get("node_type", "Node")
	var node_name = params.get("node_name", "")
	var properties = params.get("properties", {})
	
	if not scene_path or not node_name:
		return {"success": false, "error": "missing_params", "message": "scene_path y node_name son requeridos"}
	
	# Asegurar que la escena esté cargada
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
			return {"success": false, "error": "parent_not_found", "parent_path": parent_path}
	
	# Verificar que no exista
	if parent.get_node_or_null(node_name):
		return {"success": false, "error": "node_exists", "node_name": node_name}
	
	# Crear nodo
	var new_node = ClassDB.instantiate(node_type)
	if not new_node:
		return {"success": false, "error": "invalid_node_type", "node_type": node_type}
	
	new_node.name = node_name
	
	# Aplicar propiedades
	for prop_name in properties.keys():
		var deserialized = _deserialize_value(properties[prop_name])
		if prop_name in new_node or prop_name in ["position", "rotation", "scale", "size", "text", "visible", "modulate", "self_modulate"]:
			new_node.set(prop_name, deserialized)
	
	parent.add_child(new_node)
	new_node.owner = root
	
	return {
		"success": true,
		"scene_path": scene_path,
		"node_path": str(parent.get_path()) + "/" + node_name,
		"node_type": node_type
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
	var value = params.get("value", null)
	
	if not scene_path or not node_path or not property:
		return {"success": false, "error": "missing_params"}
	
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


func _handle_save_scene(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	
	if not scene_path:
		return {"success": false, "error": "missing_scene_path"}
	
	if not _scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _scene_cache[scene_path]
	
	# Crear PackedScene
	var packed = PackedScene.new()
	var err = packed.pack(root)
	if err != OK:
		return {"success": false, "error": "pack_failed", "code": err}
	
	# Guardar
	err = ResourceSaver.save(packed, scene_path)
	if err != OK:
		return {"success": false, "error": "save_failed", "code": err}
	
	return {
		"success": true,
		"scene_path": scene_path,
		"node_count": _count_nodes_recursive(root)
	}


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
	
	for op in operations:
		var method = op.get("method", "")
		var op_params = op.get("params", {})
		
		var result = _dispatch(method, op_params)
		results.append(result)
		
		if not result.get("success", false):
			all_success = false
			if params.get("stop_on_error", false):
				break
	
	return {
		"success": all_success,
		"operation_count": operations.size(),
		"results": results
	}


# ============================================================
# UTILIDADES
# ============================================================

func _deserialize_value(value) -> Variant:
	if value is Dictionary:
		var type = value.get("__type", "")
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
	else:
		return value
