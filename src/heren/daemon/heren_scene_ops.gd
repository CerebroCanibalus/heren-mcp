class_name HerenSceneOps

var _daemon: SceneTree = null

# Cache de escenas cargadas (debe ser inyectado por el daemon principal)
var _scene_cache: Dictionary = {}

# Referencias a funciones utilitarias del daemon principal
# Estas deben ser asignadas por el daemon al inicializar esta clase
var _serialize_value_callback: Callable
var _deserialize_value_callback: Callable
var _dispatch_callback: Callable

func init(daemon: SceneTree) -> void:
	_daemon = daemon

func handle_load_scene(params: Dictionary) -> Dictionary:
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
				"node_count": count_nodes_recursive(cached_scene)
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
	_daemon.get_root().add_child(scene_instance)
	
	_scene_cache[scene_path] = scene_instance
	
	return {
		"success": true,
		"cached": false,
		"scene_path": scene_path,
		"root_type": scene_instance.get_class(),
		"node_count": count_nodes_recursive(scene_instance)
	}


func count_nodes_recursive(node: Node) -> int:
	var count = 1  # El nodo mismo
	for child in node.get_children():
		count += count_nodes_recursive(child)
	return count


func handle_unload_scene(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	if not _scene_cache.has(scene_path):
		return {"success": false, "error": "not_loaded", "scene_path": scene_path}
	
	var scene = _scene_cache[scene_path]
	if is_instance_valid(scene):
		scene.queue_free()
	
	_scene_cache.erase(scene_path)
	
	return {"success": true, "scene_path": scene_path}


func handle_get_loaded_scenes(params: Dictionary) -> Dictionary:
	var scenes = []
	for scene_path in _scene_cache.keys():
		var scene = _scene_cache[scene_path]
		scenes.append({
			"path": scene_path,
			"valid": is_instance_valid(scene),
			"type": scene.get_class() if is_instance_valid(scene) else "invalid",
			"node_count": count_nodes_recursive(scene) if is_instance_valid(scene) else 0
		})
	
	return {"success": true, "scenes": scenes, "count": scenes.size()}


func handle_get_scene_tree(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	if not scene_path:
		return {"success": false, "error": "missing_scene_path"}
	
	# Auto-cargar si no está en cache
	if not _scene_cache.has(scene_path):
		var load_result = handle_load_scene({"scene_path": scene_path})
		if not load_result.success:
			return load_result
	
	var root = _scene_cache[scene_path]
	var include_properties = params.get("include_properties", false)
	
	var nodes = []
	build_node_tree(root, nodes, "", include_properties)
	
	return {
		"success": true,
		"scene_path": scene_path,
		"node_count": nodes.size(),
		"nodes": nodes
	}


func build_node_tree(node: Node, output: Array, path: String, include_props: bool):
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
		node_info["properties"] = get_node_properties_dict(node)
	
	output.append(node_info)
	
	for child in node.get_children():
		var child_path = node_info["path"] + "/" + child.name
		build_node_tree(child, output, child_path, include_props)


func get_node_properties_dict(node: Node) -> Dictionary:
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
				props[prop_name] = _serialize_value_callback.call(value) if _serialize_value_callback else value
	
	return props


# ============================================================
# HANDLERS DE MODIFICACIÓN
# ============================================================

func handle_add_node(params: Dictionary) -> Dictionary:
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
		var load_result = handle_load_scene({"scene_path": scene_path})
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
		var deserialized = _deserialize_value_callback.call(properties[prop_name]) if _deserialize_value_callback else properties[prop_name]
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
		"node_count": count_nodes_recursive(root)
	}


func handle_remove_node(params: Dictionary) -> Dictionary:
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


func handle_set_property(params: Dictionary) -> Dictionary:
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
	
	var deserialized = _deserialize_value_callback.call(value) if _deserialize_value_callback else value
	
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


func handle_get_node_properties(params: Dictionary) -> Dictionary:
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
		"properties": get_node_properties_dict(node)
	}


func handle_array_append(params: Dictionary) -> Dictionary:
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


func handle_array_remove(params: Dictionary) -> Dictionary:
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


func handle_duplicate_node(params: Dictionary) -> Dictionary:
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


func handle_rename_node(params: Dictionary) -> Dictionary:
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


func handle_move_node(params: Dictionary) -> Dictionary:
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
		"old_path": old_path,
		"new_path": str(target.get_path()),
		"new_parent": new_parent_path
	}


func handle_batch(params: Dictionary) -> Dictionary:
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
		
		var result = _dispatch_callback.call(method, op_params) if _dispatch_callback else {"success": false, "error": "dispatch_not_available"}
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
# SIGNAL & SCRIPT HANDLERS
# ============================================================

func handle_set_script(params: Dictionary) -> Dictionary:
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



func handle_connect_signal(params: Dictionary) -> Dictionary:
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
	
	# Verificar que la se├▒al existe
	if not source.has_signal(signal_name):
		return {"success": false, "error": "signal_not_found", "signal": signal_name}
	
	# Conectar la se├▒al
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



func handle_disconnect_signal(params: Dictionary) -> Dictionary:
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
	
	# Desconectar todas las conexiones de esta se├▒al si no se especifica target
	if to_node and method:
		var target = root.get_node_or_null(to_node)
		if target:
			source.disconnect(signal_name, Callable(target, method))
	else:
		# Desconectar todas las conexiones de esta se├▒al
		var connections = source.get_signal_connection_list(signal_name)
		for conn in connections:
			source.disconnect(signal_name, conn["callable"])
	
	return {
		"success": true,
		"scene_path": scene_path,
		"from_node": from_node,
		"signal": signal_name
	}



func handle_list_signals(params: Dictionary) -> Dictionary:
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
	
	# Obtener se├▒ales del nodo
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



func handle_save_scene(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	
	if not scene_path:
		return {"success": false, "error": "missing_scene_path"}
	
	if not _scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	# FIX: Backup antes de guardar
	if FileAccess.file_exists(scene_path):
		var backup_path = scene_path + ".backup." + str(Time.get_unix_time_from_system())
		var dir = DirAccess.open(scene_path.get_base_dir())
		if dir:
			var copy_err = dir.copy(scene_path, backup_path)
			if copy_err == OK:
				print("[Save] Backup creado: ", backup_path)
	
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
	
	# Inyectar en el archivo .tscn (ahora con soporte para ext_resources)
	if not sub_resources.is_empty() or not connections.is_empty():
		_inject_into_tscn(scene_path, sub_resources, connections)
	
	# Verificar que el archivo se escribio correctamente
	var saved_node_count = count_nodes_recursive(root)
	
	# Intentar recargar para verificar integridad
	var verify_load = load(scene_path)
	var verify_count = 0
	if verify_load:
		var verify_instance = verify_load.instantiate()
		if verify_instance:
			verify_count = count_nodes_recursive(verify_instance)
			verify_instance.queue_free()
	
	if verify_count > 0 and verify_count != saved_node_count:
		return {
			"success": false,
			"error": "save_verification_failed",
			"message": "El archivo guardado tiene " + str(verify_count) + " nodos, pero se esperaban " + str(saved_node_count),
			"scene_path": scene_path
		}
	
	# Liberar mouse después de operación de I/O
	if _daemon:
		_daemon.ensure_mouse_free()
	
	return {
		"success": true,
		"scene_path": scene_path,
		"node_count": saved_node_count,
		"verified": verify_count == saved_node_count,
		"sub_resources_injected": sub_resources.size(),
		"connections_injected": connections.size()
	}



func handle_create_scene(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var root_type = params.get("root_type", "Node2D")
	var root_name = params.get("root_name", "Root")
	
	if not scene_path:
		return {"success": false, "error": "missing_scene_path"}
	
	if FileAccess.file_exists(scene_path):
		return {"success": false, "error": "scene_exists", "path": scene_path}
	
	# Crear nodo ra├¡z
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



func handle_delete_scene(params: Dictionary) -> Dictionary:
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



func handle_rename_scene(params: Dictionary) -> Dictionary:
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



func handle_set_editable_paths(params: Dictionary) -> Dictionary:
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
	
	# Modificar archivo .tscn para a├▒adir l├¡neas [editable]
	var file = FileAccess.open(scene_path, FileAccess.READ)
	if not file:
		return {"success": false, "error": "file_not_found", "scene_path": scene_path}
	
	var content = file.get_as_text()
	file.close()
	
	# A├▒adir l├¡neas [editable path="..."] antes del primer nodo
	var editable_lines = []
	for node_path in paths:
		if editable:
			editable_lines.append('[editable path="%s"]' % node_path)
		else:
			# Remover l├¡neas existentes
			content = content.replace('[editable path="%s"]\n' % node_path, "")
			content = content.replace('[editable path="%s"]' % node_path, "")
	
	if not editable_lines.is_empty():
		# Insertar antes de la primera l├¡nea [node ...]
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
# SAVE SCENE HELPERS
# ============================================================

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
				# FIX: Capturar incluso si tiene path (puede ser sub-resource anidado)
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



func _inject_into_tscn(scene_path: String, sub_resources: Array, connections: Array):
	"""
	Inyecta sub_resources, ext_resources y conexiones en un archivo .tscn existente.
	Modifica el archivo directamente agregando [ext_resource], [sub_resource] y [connection].
	Maneja recursos anidados (ej: ShaderMaterial.shader) y recursos externos.
	
	FIX: Los sub-resources deben insertarse ANTES de los nodos que los referencian.
	Godot requiere definicion antes de referencia.
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
	var has_connections_section = false
	
	# Procesar lineas existentes
	for line in lines:
		if line.begins_with("[connection"):
			has_connections_section = true
		result_lines.append(line)
	
	# Diccionario para ext_resources (recursos externos como .gdshader)
	var ext_resources_dict = {}
	
	# Preparar sub_resources a inyectar
	var sub_resources_to_inject = []
	if not sub_resources.is_empty():
		# Primero recolectar todos los sub-resources anidados
		var all_sub_resources = {}  # id -> {type, properties}
		
		for i in range(sub_resources.size()):
			var res_info = sub_resources[i]
			var res = res_info["resource"]
			var res_type = res_info["resource_type"]
			var res_id = res_type + "_heren_" + str(i)
			
			# Serializar propiedades, esto puede agregar sub-resources anidados y ext_resources
			var nested_dict = {}
			var res_properties = _serialize_resource_properties(res, nested_dict, ext_resources_dict)
			
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
		
		# Preparar lineas de sub-resources
		for res_id in all_sub_resources.keys():
			var res_data = all_sub_resources[res_id]
			sub_resources_to_inject.append("[sub_resource type=\"" + res_data["type"] + "\" id=\"" + res_id + "\"]")
			for prop_line in res_data["properties"]:
				sub_resources_to_inject.append(prop_line)
			sub_resources_to_inject.append("")
	
	# Encontrar posicion de insercion para ext_resources: despues del header [gd_scene]
	var ext_resources_to_inject = []
	if not ext_resources_dict.is_empty():
		for ext_id in ext_resources_dict.keys():
			var ext_data = ext_resources_dict[ext_id]
			ext_resources_to_inject.append("[ext_resource type=\"" + ext_data["type"] + "\" path=\"" + ext_data["path"] + "\" id=\"" + ext_id + "\"]")
		ext_resources_to_inject.append("")
	
	# Insertar ext_resources despues del header [gd_scene ...]
	var gd_scene_index = -1
	for i in range(result_lines.size()):
		if result_lines[i].begins_with("[gd_scene"):
			gd_scene_index = i
			break
	
	if gd_scene_index != -1 and not ext_resources_to_inject.is_empty():
		var ext_injection = ["", "; ExtResources injectados por Heren MCP"]
		ext_injection.append_array(ext_resources_to_inject)
		
		for i in range(ext_injection.size()):
			result_lines.insert(gd_scene_index + 1 + i, ext_injection[i])
	
	# Encontrar posicion de insercion para sub-resources: despues del ultimo [sub_resource] existente
	# pero antes del primer [node]
	var insert_index = -1
	var last_sub_resource_index = -1
	var first_node_index = -1
	
	for i in range(result_lines.size()):
		var line = result_lines[i]
		if line.begins_with("[sub_resource"):
			last_sub_resource_index = i
		if first_node_index == -1 and line.begins_with("[node"):
			first_node_index = i
	
	# Decidir donde insertar sub-resources
	if last_sub_resource_index != -1:
		# Insertar despues del ultimo sub-resource existente
		# Buscar el final de ese bloque (siguiente linea vacia o seccion nueva)
		insert_index = last_sub_resource_index + 1
		while insert_index < result_lines.size():
			var line = result_lines[insert_index].strip_edges()
			if line.is_empty() or line.begins_with("["):
				break
			insert_index += 1
	elif first_node_index != -1:
		# No hay sub-resources existentes, insertar antes del primer nodo
		insert_index = first_node_index
	else:
		# No hay nodos ni sub-resources, insertar al final
		insert_index = result_lines.size()
	
	# Insertar sub-resources en la posicion correcta
	if not sub_resources_to_inject.is_empty():
		var injection = ["", "; Sub-resources injectados por Heren MCP"]
		injection.append_array(sub_resources_to_inject)
		
		for i in range(injection.size()):
			result_lines.insert(insert_index + i, injection[i])
	
	# Agregar conexiones si no existen
	if not connections.is_empty() and not has_connections_section:
		result_lines.append("")
		result_lines.append("; Conexiones injectadas por Heren MCP")
		
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
		print("[Inject] Inyectados ", sub_resources.size(), " sub-resources, ", ext_resources_dict.size(), " ext-resources y ", connections.size(), " conexiones en ", scene_path)




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
		var prop_type = prop.get("type", 0)
		
		if prop_name in ["script", "resource_name", "resource_path"]:
			continue
		if prop_usage & PROPERTY_USAGE_STORAGE == 0:
			continue
		
		if prop_type == TYPE_OBJECT:
			var value = resource.get(prop_name)
			if value and value is Resource and not value is Script:
				var sub_res = value as Resource
				if not sub_res.resource_local_to_scene:
					sub_res.resource_local_to_scene = true
				_setup_resource_local_to_scene_recursive(sub_res)



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



func _serialize_resource_properties(resource: Resource, sub_resources_dict: Dictionary = {}, ext_resources_dict: Dictionary = {}) -> Array:
	"""
	Serializa las propiedades de un recurso a lineas de texto .tscn.
	Maneja recursos anidados creando sub-resources adicionales.
	Maneja recursos externos (con resource_path) creando ext_resources.
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
		
		# Si es un recurso anidado, crear sub-resource o ext-resource
		if value is Resource and not value is Script:
			var nested_res = value as Resource
			if not nested_res.resource_path.is_empty() and nested_res.resource_path.begins_with("res://"):
				# Recurso externo: crear ExtResource
				var ext_path = nested_res.resource_path
				var ext_id = ""
				
				# Reutilizar ID si ya existe
				for existing_id in ext_resources_dict.keys():
					if ext_resources_dict[existing_id]["path"] == ext_path:
						ext_id = existing_id
						break
				
				if ext_id.is_empty():
					ext_id = "ExtResource_heren_" + str(ext_resources_dict.size())
					var ext_type = nested_res.get_class()
					# Shaders son type="Shader", no "GDShader"
					if ext_path.ends_with(".gdshader"):
						ext_type = "Shader"
					ext_resources_dict[ext_id] = {
						"type": ext_type,
						"path": ext_path
					}
				
				lines.append(prop_name + " = ExtResource(\"" + ext_id + "\")")
				continue
			elif nested_res.resource_path.is_empty():
				# Recurso interno: crear sub-resource anidado
				var nested_type = nested_res.get_class()
				var nested_id = nested_type + "_nested_" + str(sub_resources_dict.size())
				sub_resources_dict[nested_id] = {
					"type": nested_type,
					"resource": nested_res,
					"properties": _serialize_resource_properties(nested_res, sub_resources_dict, ext_resources_dict)
				}
				lines.append(prop_name + " = SubResource(\"" + nested_id + "\")")
				continue
		
		# Serializar segun tipo
		var serialized = _serialize_value_tscn(value)
		if not serialized.is_empty():
			lines.append(prop_name + " = " + serialized)
	
	return lines



func _update_node_subresource_ref(lines: Array, node_path: String, prop_name: String, res_id: String):
	"""
	Actualiza la referencia de sub-resource en la linea del nodo correspondiente.
	Busca el nodo por path y agrega/modifica la propiedad para usar SubResource().
	Si la propiedad ya existe, la reemplaza (elimina duplicados).
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
	
	if target_node_line == -1:
		return
	
	# Buscar y eliminar propiedad existente dentro del bloque del nodo
	# Un bloque de nodo termina cuando encontramos otra linea [node, [sub_resource, [connection, o linea vac├¡a]
	var existing_prop_line = -1
	for i in range(target_node_line + 1, lines.size()):
		var line = lines[i]
		# Si encontramos inicio de otra secci├│n, salimos
		if line.begins_with("[node ") or line.begins_with("[sub_resource ") or line.begins_with("[connection "):
			break
		# Si encontramos la propiedad existente
		if line.strip_edges().begins_with(prop_name + " ="):
			existing_prop_line = i
			lines[i] = ""  # Eliminar linea existente
			break
	
	# Insertar nueva referencia despues de la linea del nodo
	var prop_line = target_indent + prop_name + " = SubResource(\"" + res_id + "\")"
	lines.insert(target_node_line + 1, prop_line)




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
		TYPE_VECTOR3I:
			var v = value as Vector3i
			return "Vector3i(" + str(v.x) + ", " + str(v.y) + ", " + str(v.z) + ")"
		TYPE_COLOR:
			var c = value as Color
			return "Color(" + str(c.r) + ", " + str(c.g) + ", " + str(c.b) + ", " + str(c.a) + ")"
		TYPE_RECT2:
			var r = value as Rect2
			return "Rect2(" + _serialize_value_tscn(r.position) + ", " + _serialize_value_tscn(r.size) + ")"
		TYPE_RECT2I:
			var r = value as Rect2i
			return "Rect2i(" + _serialize_value_tscn(r.position) + ", " + _serialize_value_tscn(r.size) + ")"
		TYPE_TRANSFORM2D:
			var t = value as Transform2D
			return "Transform2D(" + str(t.x.x) + ", " + str(t.x.y) + ", " + str(t.y.x) + ", " + str(t.y.y) + ", " + str(t.origin.x) + ", " + str(t.origin.y) + ")"
		TYPE_TRANSFORM3D:
			var t = value as Transform3D
			return "Transform3D(" + str(t.basis.x.x) + ", " + str(t.basis.x.y) + ", " + str(t.basis.x.z) + ", " + str(t.basis.y.x) + ", " + str(t.basis.y.y) + ", " + str(t.basis.y.z) + ", " + str(t.basis.z.x) + ", " + str(t.basis.z.y) + ", " + str(t.basis.z.z) + ", " + str(t.origin.x) + ", " + str(t.origin.y) + ", " + str(t.origin.z) + ")"
		TYPE_AABB:
			var a = value as AABB
			return "AABB(" + str(a.position.x) + ", " + str(a.position.y) + ", " + str(a.position.z) + ", " + str(a.size.x) + ", " + str(a.size.y) + ", " + str(a.size.z) + ")"
		TYPE_BASIS:
			var b = value as Basis
			return "Basis(" + str(b.x.x) + ", " + str(b.x.y) + ", " + str(b.x.z) + ", " + str(b.y.x) + ", " + str(b.y.y) + ", " + str(b.y.z) + ", " + str(b.z.x) + ", " + str(b.z.y) + ", " + str(b.z.z) + ")"
		TYPE_QUATERNION:
			var q = value as Quaternion
			return "Quaternion(" + str(q.x) + ", " + str(q.y) + ", " + str(q.z) + ", " + str(q.w) + ")"
		TYPE_PLANE:
			var p = value as Plane
			return "Plane(" + str(p.normal.x) + ", " + str(p.normal.y) + ", " + str(p.normal.z) + ", " + str(p.d) + ")"
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


