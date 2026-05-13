extends SceneTree

# 🐉 Heren Bridge GDScript
# Este script corre dentro de Godot headless y actúa como servidor JSON-RPC.
# Recibe comandos por stdin, ejecuta operaciones nativas, devuelve JSON por stdout.
# Filosofía: Poder. Eficiencia. Rapidez.

const CMD_FILE = "D:/Mis Juegos/GodotMCP/heren-mcp/.temp/heren_cmd.json"
const RESP_FILE = "D:/Mis Juegos/GodotMCP/heren-mcp/.temp/heren_resp.json"

func _init():
	print("HEREN_BRIDGE_READY")
	flush_stdout()
	
	# Bucle principal de comandos - lee archivo temporal
	while true:
		# Leer comando desde archivo
		if FileAccess.file_exists(CMD_FILE):
			var file = FileAccess.open(CMD_FILE, FileAccess.READ)
			if file:
				var line = file.get_line()
				file.close()
				
				# Borrar archivo de comando
				DirAccess.remove_absolute(CMD_FILE)
				
				if not line.is_empty():
					var result = process_command(line.strip_edges())
					
					# Escribir respuesta
					var resp_file = FileAccess.open(RESP_FILE, FileAccess.WRITE)
					if resp_file:
						resp_file.store_line(JSON.stringify(result))
						resp_file.close()
					
					print(JSON.stringify(result))
					flush_stdout()
					
					# Verificar si es shutdown
					if result.get("action") == "shutdown":
						break
		
		OS.delay_msec(50)

func flush_stdout():
	# Forzar flush del stdout
	OS.delay_usec(1000)

func process_command(line: String) -> Dictionary:
	var json = JSON.new()
	var parse_result = json.parse(line)
	
	if parse_result != OK:
		return {
			"success": false,
			"error": "JSON inválido: " + json.get_error_message()
		}
	
	var cmd = json.data
	var action = cmd.get("action", "")
	var params = cmd.get("params", {})
	
	match action:
		"shutdown":
			return {"success": true, "message": "Shutting down"}
		"get_scene_tree":
			return cmd_get_scene_tree(params)
		"save_scene":
			return cmd_save_scene(params)
		"add_node":
			return cmd_add_node(params)
		"remove_node":
			return cmd_remove_node(params)
		"set_property":
			return cmd_set_property(params)
		"get_project_info":
			return cmd_get_project_info(params)
		"get_node_properties":
			return cmd_get_node_properties(params)
		_:
			return {
				"success": false,
				"error": "Acción desconocida: " + action
			}

func cmd_get_scene_tree(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	
	if scene_path.is_empty():
		return {"success": false, "error": "scene_path requerido"}
	
	var packed_scene = load(scene_path)
	if packed_scene == null:
		return {"success": false, "error": "No se pudo cargar la escena: " + scene_path}
	
	var scene = packed_scene.instantiate()
	if scene == null:
		return {"success": false, "error": "No se pudo instanciar la escena"}
	
	var tree_data = node_to_dict(scene, true)
	scene.free()
	
	return {
		"success": true,
		"scene_path": scene_path,
		"tree": tree_data
	}

func node_to_dict(node: Node, is_root: bool = false) -> Dictionary:
	var result = {
		"name": node.name,
		"type": node.get_class(),
		"path": node.get_path().get_concatenated_names(),
	}
	
	# Propiedades básicas según tipo
	if node is Node2D:
		result["position"] = var_to_dict(node.position)
		result["rotation"] = node.rotation
		result["scale"] = var_to_dict(node.scale)
	elif node is Node3D:
		result["position"] = var_to_dict(node.position)
		result["rotation"] = var_to_dict(node.rotation)
		result["scale"] = var_to_dict(node.scale)
	
	# Script adjunto
	if node.get_script() != null:
		result["script"] = node.get_script().resource_path
	
	# Groups
	result["groups"] = node.get_groups()
	
	# Children
	var children = []
	for child in node.get_children():
		children.append(node_to_dict(child))
	result["children"] = children
	
	return result

func var_to_dict(val) -> Variant:
	# Convierte tipos Godot a representación serializable
	if val is Vector2:
		return {"__type": "Vector2", "x": val.x, "y": val.y}
	elif val is Vector3:
		return {"__type": "Vector3", "x": val.x, "y": val.y, "z": val.z}
	elif val is Color:
		return {"__type": "Color", "r": val.r, "g": val.g, "b": val.b, "a": val.a}
	elif val is Transform2D:
		return {"__type": "Transform2D", "origin": var_to_dict(val.origin)}
	elif val is Rect2:
		return {"__type": "Rect2", "x": val.position.x, "y": val.position.y, "w": val.size.x, "h": val.size.y}
	return val

func cmd_save_scene(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	
	if scene_path.is_empty():
		return {"success": false, "error": "scene_path requerido"}
	
	var result = ResourceSaver.save(load(scene_path), scene_path)
	
	if result == OK:
		return {"success": true, "scene_path": scene_path}
	else:
		return {"success": false, "error": "Error guardando escena: " + str(result)}

func cmd_add_node(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var parent_path = params.get("parent_path", "")
	var node_type = params.get("node_type", "Node")
	var node_name = params.get("node_name", "")
	var properties = params.get("properties", {})
	
	if scene_path.is_empty() or parent_path.is_empty() or node_name.is_empty():
		return {"success": false, "error": "scene_path, parent_path, node_name requeridos"}
	
	var packed_scene = load(scene_path)
	if packed_scene == null:
		return {"success": false, "error": "No se pudo cargar la escena"}
	
	var scene = packed_scene.instantiate()
	var parent = scene.get_node_or_null(parent_path)
	
	if parent == null:
		scene.free()
		return {"success": false, "error": "Nodo padre no encontrado: " + parent_path}
	
	# Crear nodo usando ClassDB
	var new_node = ClassDB.instantiate(node_type)
	if new_node == null:
		scene.free()
		return {"success": false, "error": "No se pudo crear nodo de tipo: " + node_type}
	
	new_node.name = node_name
	parent.add_child(new_node)
	new_node.owner = scene
	
	# Setear propiedades
	for prop_name in properties.keys():
		var value = dict_to_var(properties[prop_name])
		if new_node.get(prop_name) != null or new_node.get_property_list().any(func(p): return p.name == prop_name):
			new_node.set(prop_name, value)
	
	# Guardar
	var save_result = ResourceSaver.save(scene, scene_path)
	scene.free()
	
	if save_result == OK:
		return {
			"success": true,
			"scene_path": scene_path,
			"node_path": parent_path + "/" + node_name
		}
	else:
		return {"success": false, "error": "Error guardando: " + str(save_result)}

func dict_to_var(val) -> Variant:
	# Convierte representación serializada a tipo Godot
	if val is Dictionary and val.has("__type"):
		match val["__type"]:
			"Vector2":
				return Vector2(val.get("x", 0), val.get("y", 0))
			"Vector3":
				return Vector3(val.get("x", 0), val.get("y", 0), val.get("z", 0))
			"Color":
				return Color(val.get("r", 0), val.get("g", 0), val.get("b", 0), val.get("a", 1))
	return val

func cmd_remove_node(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var node_path = params.get("node_path", "")
	
	if scene_path.is_empty() or node_path.is_empty():
		return {"success": false, "error": "scene_path y node_path requeridos"}
	
	var packed_scene = load(scene_path)
	if packed_scene == null:
		return {"success": false, "error": "No se pudo cargar la escena"}
	
	var scene = packed_scene.instantiate()
	var node = scene.get_node_or_null(node_path)
	
	if node == null:
		scene.free()
		return {"success": false, "error": "Nodo no encontrado: " + node_path}
	
	node.queue_free()
	
	var save_result = ResourceSaver.save(scene, scene_path)
	scene.free()
	
	if save_result == OK:
		return {"success": true, "removed_path": node_path}
	else:
		return {"success": false, "error": "Error guardando: " + str(save_result)}

func cmd_set_property(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var node_path = params.get("node_path", "")
	var property = params.get("property", "")
	var value = params.get("value", null)
	
	if scene_path.is_empty() or node_path.is_empty() or property.is_empty():
		return {"success": false, "error": "scene_path, node_path, property requeridos"}
	
	var packed_scene = load(scene_path)
	if packed_scene == null:
		return {"success": false, "error": "No se pudo cargar la escena"}
	
	var scene = packed_scene.instantiate()
	var node = scene.get_node_or_null(node_path)
	
	if node == null:
		scene.free()
		return {"success": false, "error": "Nodo no encontrado: " + node_path}
	
	var godot_value = dict_to_var(value)
	node.set(property, godot_value)
	
	var save_result = ResourceSaver.save(scene, scene_path)
	scene.free()
	
	if save_result == OK:
		return {
			"success": true,
			"node_path": node_path,
			"property": property,
			"value": value
		}
	else:
		return {"success": false, "error": "Error guardando: " + str(save_result)}

func cmd_get_project_info(params: Dictionary) -> Dictionary:
	var project_path = params.get("project_path", "")
	
	var config = ConfigFile.new()
	var err = config.load(project_path.path_join("project.godot"))
	
	if err != OK:
		return {"success": false, "error": "No se pudo leer project.godot"}
	
	return {
		"success": true,
		"project_name": config.get_value("application", "config/name", "Unknown"),
		"main_scene": config.get_value("application", "run/main_scene", ""),
		"version": config.get_value("application", "config/features", []),
	}

func cmd_get_node_properties(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var node_path = params.get("node_path", "")
	
	if scene_path.is_empty() or node_path.is_empty():
		return {"success": false, "error": "scene_path y node_path requeridos"}
	
	var packed_scene = load(scene_path)
	if packed_scene == null:
		return {"success": false, "error": "No se pudo cargar la escena"}
	
	var scene = packed_scene.instantiate()
	var node = scene.get_node_or_null(node_path)
	
	if node == null:
		scene.free()
		return {"success": false, "error": "Nodo no encontrado: " + node_path}
	
	var properties = {}
	for prop in node.get_property_list():
		if prop.usage & PROPERTY_USAGE_EDITOR != 0 or prop.usage & PROPERTY_USAGE_STORAGE != 0:
			properties[prop.name] = var_to_dict(node.get(prop.name))
	
	scene.free()
	
	return {
		"success": true,
		"node_path": node_path,
		"properties": properties
	}
