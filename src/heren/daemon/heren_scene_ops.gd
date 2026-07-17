class_name HerenSceneOps

var _daemon: SceneTree = null

# Cache de escenas cargadas (debe ser inyectado por el daemon principal)
var _scene_cache: Dictionary = {}

# Rastro de escenas modificadas desde el último guardado
var _dirty_scenes: Dictionary = {}

# Contenedor donde se montan las escenas cargadas (inyectado por el daemon)
var _scene_container: Node = null

# Wrapper por escena para evitar colisiones de nombres en el árbol del daemon
var _scene_wrappers: Dictionary = {}

# Referencias a funciones utilitarias del daemon principal
# Estas deben ser asignadas por el daemon al inicializar esta clase
var _serialize_value_callback: Callable
var _deserialize_value_callback: Callable
var _dispatch_callback: Callable

func init(daemon: SceneTree) -> void:
	_daemon = daemon

# ============================================================
# DIRTY TRACKING (modificaciones sin guardar)
# ============================================================
func _mark_dirty(scene_path: String) -> void:
	"""Marca una escena como modificada (necesita guardado)."""
	if scene_path:
		_dirty_scenes[scene_path] = true

func _clear_dirty(scene_path: String) -> void:
	"""Limpia el flag de sucio para una escena."""
	if _dirty_scenes.has(scene_path):
		_dirty_scenes.erase(scene_path)

func get_dirty_scenes() -> Array:
	"""Retorna lista de rutas de escenas sucias."""
	return _dirty_scenes.keys()

func is_dirty(scene_path: String) -> bool:
	"""Verifica si una escena tiene cambios sin guardar."""
	return _dirty_scenes.has(scene_path)

func handle_save_all_dirty(params: Dictionary) -> Dictionary:
	"""Guarda todas las escenas con cambios pendientes. Se llama en shutdown y auto-save."""
	var dirty = _dirty_scenes.keys()
	var results = []
	var errors = []
	
	for scene_path in dirty:
		var result = handle_save_scene({"scene_path": scene_path})
		results.append(result)
		if not result.get("success", false):
			errors.append({"scene_path": scene_path, "error": result.get("error", "unknown")})
	
	return {
		"success": errors.size() == 0,
		"total": dirty.size(),
		"saved": results.size() - errors.size(),
		"errors": errors,
		"results": results
	}

func _get_scene_wrapper(scene_path: String) -> Node:
	"""
	Crea o reutiliza un nodo wrapper único para esta escena.
	Evita que Godot renombre nodos raíz cuando hay varias escenas cargadas.
	"""
	if _scene_wrappers.has(scene_path):
		var existing = _scene_wrappers[scene_path]
		if is_instance_valid(existing):
			return existing
	
	var wrapper = Node.new()
	var hash_val = scene_path.hash()
	var suffix = str(hash_val) if hash_val >= 0 else "n" + str(-hash_val)
	wrapper.name = "HerenWrapper_" + suffix
	
	var container = _scene_container if is_instance_valid(_scene_container) else _daemon.get_root()
	container.add_child(wrapper)
	_scene_wrappers[scene_path] = wrapper
	return wrapper

func _remove_scene_wrapper(scene_path: String) -> void:
	if _scene_wrappers.has(scene_path):
		var wrapper = _scene_wrappers[scene_path]
		if is_instance_valid(wrapper):
			wrapper.queue_free()
		_scene_wrappers.erase(scene_path)

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
	
	# Agregar a wrapper dentro del contenedor. El wrapper aísla cada escena
	# para evitar colisiones de nombres en el árbol del daemon. El contenedor
	# se ubica fuera de pantalla, no oculto, para no alterar 'visible'.
	var wrapper = _get_scene_wrapper(scene_path)
	wrapper.add_child(scene_instance)
	
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
	
	_remove_scene_wrapper(scene_path)
	_scene_cache.erase(scene_path)
	_clear_dirty(scene_path)
	
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
	
	# B10 FIX: Normalizar nombre para evitar desambiguación con #
	# Godot añade # a nombres duplicados en el árbol runtime, pero el .tscn usa nombres originales
	var normalized_name = node.name
	if "#" in normalized_name:
		normalized_name = normalized_name.split("#")[0]
	
	var node_info = {
		"name": normalized_name,
		"type": node.get_class(),
		"path": path if not path.is_empty() else normalized_name
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
	
	# B6 FIX: Godot sanitiza caracteres especiales (@, #, !) en nombres
	# Obtener el nombre real que Godot usó después de la sanitización
	var actual_name = new_node.name
	
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
	
	# Verificar que el nodo fue añadido correctamente usando el nombre real
	var verify_node = parent.get_node_or_null(actual_name)
	if not verify_node:
		return {
			"success": false,
			"error": "add_failed",
			"message": "El nodo no se pudo verificar después de añadirlo"
		}
	
	# B6 FIX: Devolver información sobre la sanitización si ocurrió
	var name_was_sanitized = actual_name != node_name
	
	_mark_dirty(scene_path)
	
	return {
		"success": true,
		"scene_path": scene_path,
		"node_path": str(parent.get_path()) + "/" + actual_name,
		"node_type": node_type,
		"node_count": count_nodes_recursive(root),
		"node_name": actual_name,
		"name_sanitized": name_was_sanitized,
		"original_name": node_name if name_was_sanitized else null
	}


func handle_remove_node(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var node_path = params.get("node_path", "")
	var recursive = params.get("recursive", true)
	
	if not scene_path or not node_path:
		return {"success": false, "error": "missing_params", "message": "scene_path y node_path son requeridos"}
	
	# B12 FIX: Separar error de "escena no cargada" de "nodo no encontrado"
	if not _scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded", "message": "La escena no está cargada en memoria. Carga la escena primero con 'load_scene'."}
	
	var root = _scene_cache[scene_path]
	var normalized_path = _normalize_node_path(node_path, root)
	var target = root.get_node_or_null(normalized_path)
	
	if not target:
		return {"success": false, "error": "node_not_found", "node_path": node_path, "message": "El nodo '" + node_path + "' no existe en la escena '" + scene_path + "'"}
	
	if target == root:
		return {"success": false, "error": "cannot_remove_root"}
	
	if target.get_child_count() > 0 and not recursive:
		return {"success": false, "error": "node_has_children", "children": target.get_child_count()}
	
	var had_children = target.get_child_count() > 0
	target.queue_free()
	
	_mark_dirty(scene_path)
	
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
	
	# B4 FIX: Normalizar node_path para aceptar paths con o sin /root/ prefix
	var normalized_path = _normalize_node_path(node_path, root)
	var node = root.get_node_or_null(normalized_path)
	
	if not node:
		return {"success": false, "error": "node_not_found", "node_path": node_path}
	
	var deserialized = _deserialize_value_callback.call(value) if _deserialize_value_callback else value
	
	# Verificar si la propiedad existe
	if not property in node:
		return {"success": false, "error": "property_not_found", "property": property}
	
	var old_value = node.get(property)
	node.set(property, deserialized)
	
	_mark_dirty(scene_path)
	
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
	var normalized_path = _normalize_node_path(node_path, root)
	var node = root.get_node_or_null(normalized_path)
	
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
	var normalized_path = _normalize_node_path(node_path, root)
	var node = root.get_node_or_null(normalized_path)
	
	if not node:
		return {"success": false, "error": "node_not_found", "node_path": node_path}
	
	# Obtener el array actual (duplicate para evitar modificar por referencia)
	var current_array = node.get(property_name)
	var type_id = typeof(current_array)
	var is_array_type = current_array is Array or (type_id >= TYPE_PACKED_BYTE_ARRAY and type_id <= TYPE_PACKED_COLOR_ARRAY)
	if not is_array_type:
		return {"success": false, "error": "property_not_array", "property_name": property_name, "type": type_id}
	
	# Duplicar para asegurar que Godot detecte el cambio
	var new_array = current_array.duplicate()
	new_array.append(value)
	
	# Setear el array modificado
	node.set(property_name, new_array)
	
	_mark_dirty(scene_path)
	
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
	var normalized_path = _normalize_node_path(node_path, root)
	var node = root.get_node_or_null(normalized_path)
	
	if not node:
		return {"success": false, "error": "node_not_found", "node_path": node_path}
	
	# Obtener el array actual (duplicate para evitar modificar por referencia)
	var current_array = node.get(property_name)
	var type_id = typeof(current_array)
	var is_array_type = current_array is Array or (type_id >= TYPE_PACKED_BYTE_ARRAY and type_id <= TYPE_PACKED_COLOR_ARRAY)
	if not is_array_type:
		return {"success": false, "error": "property_not_array", "property_name": property_name, "type": type_id}
	
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
	
	_mark_dirty(scene_path)
	
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
	var normalized_path = _normalize_node_path(node_path, root)
	var target = root.get_node_or_null(normalized_path)
	
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
	
	_mark_dirty(scene_path)
	
	return {
		"success": true,
		"original": _get_node_path_relative(target),
		"duplicate": _get_node_path_relative(duplicate),
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
	var normalized_path = _normalize_node_path(node_path, root)
	var target = root.get_node_or_null(normalized_path)
	
	if not target:
		return {"success": false, "error": "node_not_found"}
	
	var old_name = target.name
	target.name = new_name
	
	_mark_dirty(scene_path)
	
	return {
		"success": true,
		"old_name": old_name,
		"new_name": new_name,
		"node_path": _get_node_path_relative(target)
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
	var normalized_path = _normalize_node_path(node_path, root)
	var normalized_parent = _normalize_node_path(new_parent_path, root)
	var target = root.get_node_or_null(normalized_path)
	var new_parent = root.get_node_or_null(normalized_parent)
	
	if not target:
		return {"success": false, "error": "node_not_found", "node_path": node_path}
	
	if not new_parent:
		return {"success": false, "error": "parent_not_found", "parent_path": new_parent_path}
	
	if target == root:
		return {"success": false, "error": "cannot_move_root"}
	
	var old_parent = target.get_parent()
	
	# Remove from old parent
	old_parent.remove_child(target)
	
	# Add to new parent
	new_parent.add_child(target)
	target.owner = root
	
	_mark_dirty(scene_path)
	
	return {
		"success": true,
		"old_path": _get_node_path_relative(target),
		"new_path": _get_node_path_relative(target),
		"new_parent": _get_node_path_relative(new_parent)
	}


func handle_batch(params: Dictionary) -> Dictionary:
	var operations = params.get("operations", [])
	if operations.is_empty():
		return {"success": false, "error": "empty_operations"}
	
	var results = []
	var all_success = true
	
	# B7 FIX: Auto-cargar escenas necesarias ANTES de ejecutar operaciones
	# Esto asegura que todas las operaciones trabajen sobre la misma instancia en memoria
	var scenes_to_load = {}
	for i in range(operations.size()):
		var op = operations[i]
		var method = op.get("method", "")
		var op_params = op.get("params", {})
		var scene_path = op_params.get("scene_path", "")
		
		# Solo para operaciones que requieren escena cargada
		if method in ["add_node", "remove_node", "set_property", "get_node_properties", 
					  "duplicate_node", "rename_node", "move_node", "save_scene", "get_scene_tree",
					  "array_append", "array_remove"]:
			if scene_path and not scenes_to_load.has(scene_path):
				scenes_to_load[scene_path] = true
	
	# Cargar todas las escenas necesarias
	for scene_path in scenes_to_load.keys():
		if not _scene_cache.has(scene_path):
			var load_result = handle_load_scene({"scene_path": scene_path})
			if not load_result.success:
				return {
					"success": false,
					"error": "batch_load_failed",
					"scene_path": scene_path,
					"message": "No se pudo cargar la escena requerida para batch: " + scene_path
				}
	
	# Ejecutar operaciones sobre la misma instancia de escena en caché
	for i in range(operations.size()):
		var op = operations[i]
		var method = op.get("method", "")
		var op_params = op.get("params", {})
		
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
	
	_mark_dirty(scene_path)
	
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
	
	# Conectar la se├▒al con CONNECT_PERSIST para que pack() la serialice
	var err = source.connect(signal_name, Callable(target, method), Object.CONNECT_PERSIST)
	if err != OK:
		return {"success": false, "error": "connect_failed", "code": err}
	
	_mark_dirty(scene_path)
	
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
	
	_mark_dirty(scene_path)
	
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
	
	# FIX: Limpiar propiedades inyectadas por wrappers anteriores en el root
	_pre_save_root_cleanup(root)
	
	# FIX CRITICO: Asegurar que todos los recursos de los nodos tengan paths validos
	# antes de hacer pack(). Esto fuerza a Godot a guardarlos como ext_resources.
	_pre_save_resource_fix(root)
	
	# Crear PackedScene
	var packed = PackedScene.new()
	var err = packed.pack(root)
	if err != OK:
		return {"success": false, "error": "pack_failed", "code": err}
	
	# Pipeline limpio: Godot maneja TODO nativamente.
	# pack() serializa nodos, propiedades, sub-recursos y señales (Godot 4.2+).
	# FLAG_BUNDLE_RESOURCES incrusta todos los recursos en el .tscn.
	# resource_local_to_scene=true (seteado en _pre_save_resource_fix) fuerza embedding.
	# No hay inyección de texto — eso causaba IDs duplicados y corrupción de referencias.
	var save_flags = ResourceSaver.FLAG_BUNDLE_RESOURCES
	err = ResourceSaver.save(packed, scene_path, save_flags)
	if err != OK:
		return {"success": false, "error": "save_failed", "code": err}
	
	# Verificar que el archivo se escribió correctamente
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
	
	# Limpiar flag de sucio: esta escena ya está en disco
	_clear_dirty(scene_path)
	
	# Liberar mouse después de operación de I/O
	if _daemon:
		_daemon.ensure_mouse_free()
	
	return {
		"success": true,
		"scene_path": scene_path,
		"node_count": saved_node_count,
		"verified": verify_count == saved_node_count
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
		_clear_dirty(scene_path)
	
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
		# Mover el flag de dirty a la nueva ruta
		if _dirty_scenes.has(scene_path):
			_dirty_scenes.erase(scene_path)
			_dirty_scenes[new_path] = true
	
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
	Ignora wrappers internos del daemon (HerenWrapper_*).
	"""
	if not node:
		return ""
	
	# Subir hasta encontrar el root de la escena (hijo directo de un wrapper o del contenedor)
	var scene_root = node
	var current = node.get_parent()
	while current and not current is Viewport:
		# Si el padre es un wrapper interno, el nodo acumulado es el root de la escena
		if current.name.begins_with("HerenWrapper_") or current.name == "HerenSceneContainer":
			break
		scene_root = current
		current = current.get_parent()
	
	if node == scene_root:
		return "."
	
	return scene_root.get_path_to(node)


func _pre_save_root_cleanup(root: Node) -> void:
	"""
	Limpia propiedades que wrappers anteriores pudieron haber inyectado en el root.
	Esto evita que escenas guardadas tengan visible=false o process_mode=4 en su raiz.
	"""
	if root is CanvasItem:
		root.visible = true
	root.process_mode = Node.PROCESS_MODE_INHERIT



# ============================================================
# PATH NORMALIZATION HELPER (B4 FIX)
# ============================================================

func _normalize_node_path(node_path: String, root: Node) -> String:
	"""
	Normaliza un path de nodo para aceptar tanto:
	- Paths con /root/ prefix: /root/TestRoot/Player
	- Paths sin prefix: TestRoot/Player o Player
	Retorna el path normalizado sin prefix.
	"""
	if node_path.is_empty():
		return ""
	
	# Si ya es vacío o solo el nombre del nodo, retornarlo
	if not node_path.contains("/"):
		return node_path
	
	# Quitar /root/ prefix si existe
	var normalized = node_path
	if normalized.begins_with("/root/"):
		normalized = normalized.substr(6)  # Quitar "/root/"
	
	# Quitar nombre del root si está al inicio (ej: "TestRoot/Player" -> "Player")
	var root_name = root.name
	if normalized.begins_with(root_name + "/"):
		normalized = normalized.substr(root_name.length() + 1)
	elif normalized == root_name:
		normalized = "."
	
	return normalized


