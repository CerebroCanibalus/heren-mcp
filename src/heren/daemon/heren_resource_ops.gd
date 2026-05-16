class_name HerenResourceOps

var _daemon: SceneTree = null

# Cache de recursos cargados (debe ser inyectado por el daemon principal)
var _resource_cache: Dictionary = {}
var _scene_cache: Dictionary = {}

# Referencias a funciones utilitarias del daemon principal
var _serialize_value_tscn_callback: Callable
var _deserialize_value_callback: Callable

func init(daemon: SceneTree) -> void:
	_daemon = daemon

func handle_create_resource(params: Dictionary) -> Dictionary:
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
		var deserialized = _deserialize_value_callback.call(properties[prop_name]) if _deserialize_value_callback else properties[prop_name]
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


func handle_update_scene_subresource(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var subresource_type = params.get("subresource_type", "")
	var subresource_index = params.get("subresource_index", 0)
	var property_name = params.get("property_name", "")
	var value = params.get("value", null)
	
	if not scene_path or not subresource_type or not property_name:
		return {"success": false, "error": "missing_params"}
	
	if not FileAccess.file_exists(scene_path):
		return {"success": false, "error": "scene_not_found"}
	
	var file = FileAccess.open(scene_path, FileAccess.READ)
	if not file:
		return {"success": false, "error": "read_failed"}
	
	var content = file.get_as_text()
	file.close()
	
	var lines = content.split("\n")
	var result_lines = []
	var current_subresource_idx = -1
	var in_target_subresource = false
	var property_updated = false
	
	for line in lines:
		if line.begins_with("[sub_resource type=\"" + subresource_type + "\"]"):
			current_subresource_idx += 1
			if current_subresource_idx == subresource_index:
				in_target_subresource = true
			else:
				in_target_subresource = false
		elif line.begins_with("[") and not line.begins_with("[sub_resource"):
			in_target_subresource = false
		
		if in_target_subresource and not property_updated:
			# Verificar si la linea es la propiedad a actualizar
			var prop_prefix = property_name + " = "
			if line.begins_with(prop_prefix) or line.strip_edges() == property_name:
				# Reemplazar valor
				var deserialized = _deserialize_value_callback.call(value) if _deserialize_value_callback else value
				var serialized = _serialize_value_tscn_callback.call(deserialized) if _serialize_value_tscn_callback else str(deserialized)
				if not serialized.is_empty():
					result_lines.append(property_name + " = " + serialized)
					property_updated = true
					continue
		
		result_lines.append(line)
	
	if not property_updated:
		return {"success": false, "error": "property_not_found", "subresource_index": subresource_index}
	
	# Guardar
	file = FileAccess.open(scene_path, FileAccess.WRITE)
	if not file:
		return {"success": false, "error": "write_failed"}
	
	file.store_string("\n".join(result_lines))
	file.close()
	
	return {
		"success": true,
		"scene_path": scene_path,
		"subresource_type": subresource_type,
		"subresource_index": subresource_index,
		"property_name": property_name,
		"property_updated": true
	}


func handle_read_resource(params: Dictionary) -> Dictionary:
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
				"properties": get_resource_properties(cached)
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
		"properties": get_resource_properties(resource)
	}


func get_resource_properties(resource: Resource) -> Dictionary:
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
				props[prop_name] = value
	
	return props


func handle_update_resource(params: Dictionary) -> Dictionary:
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
		var deserialized = _deserialize_value_callback.call(properties[prop_name]) if _deserialize_value_callback else properties[prop_name]
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


func handle_delete_resource(params: Dictionary) -> Dictionary:
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


func handle_list_resources(params: Dictionary) -> Dictionary:
	var directory = params.get("directory", "res://")
	var extension = params.get("extension", "")
	var recursive = params.get("recursive", false)
	
	var resources = []
	scan_directory(directory, extension, recursive, resources)
	
	return {
		"success": true,
		"directory": directory,
		"count": resources.size(),
		"resources": resources
	}


func scan_directory(dir_path: String, extension: String, recursive: bool, output: Array):
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
			scan_directory(full_path, extension, recursive, output)
		else:
			if extension.is_empty() or file_name.ends_with(extension):
				output.append(full_path)
		
		file_name = dir.get_next()
	
	dir.list_dir_end()


# ============================================================
# SCRIPT HANDLERS
# ============================================================

func handle_create_script(params: Dictionary) -> Dictionary:
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


func handle_read_script(params: Dictionary) -> Dictionary:
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


func handle_edit_script(params: Dictionary) -> Dictionary:
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

func handle_add_ext_resource(params: Dictionary) -> Dictionary:
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


func handle_remove_ext_resource(params: Dictionary) -> Dictionary:
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
