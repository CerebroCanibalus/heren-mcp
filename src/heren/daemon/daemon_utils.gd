## Daemon Utils - Funciones compartidas de serialización y utilidades
## Usado por heren_daemon.gd y daemon_handlers.gd

# Serializar valor de Godot a JSON
func serialize_value(value) -> Variant:
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


# Deserializar valor de JSON a Godot
func deserialize_value(value) -> Variant:
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


# Contar nodos recursivamente
func count_nodes_recursive(node: Node) -> int:
	var count = 1
	for child in node.get_children():
		count += count_nodes_recursive(child)
	return count


# Construir árbol de nodos para JSON
func build_node_tree(node: Node, output: Array, path: String, include_props: bool, utils):
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
		node_info["properties"] = get_node_properties_dict(node, utils)
	
	output.append(node_info)
	
	for child in node.get_children():
		var child_path = node_info["path"] + "/" + child.name
		build_node_tree(child, output, child_path, include_props, utils)


# Obtener propiedades de un nodo
func get_node_properties_dict(node: Node, utils) -> Dictionary:
	var props = {}
	var property_list = node.get_property_list()
	
	for prop in property_list:
		var prop_name = prop["name"]
		if prop_name.begins_with("_") or prop_name in ["script", "process_mode", "process_priority", "physics_interpolation_mode"]:
			continue
		
		var usage = prop.get("usage", 0)
		if usage & PROPERTY_USAGE_EDITOR or usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			if prop_name in node:
				var value = node.get(prop_name)
				props[prop_name] = utils.serialize_value(value)
	
	return props


# Obtener propiedades de un recurso
func get_resource_properties(resource: Resource, utils) -> Dictionary:
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
				props[prop_name] = utils.serialize_value(value)
	
	return props


# Escanear directorio recursivamente
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


# Crear grid visual para inspect_visual
func create_visual_grid(width: int, height: int, grid_size: int) -> Node2D:
	var grid = Node2D.new()
	grid.name = "VisualGrid"
	
	var line_color = Color(0.3, 0.3, 0.3, 0.5)
	
	for x in range(0, width, grid_size):
		var line = Line2D.new()
		line.add_point(Vector2(x, 0))
		line.add_point(Vector2(x, height))
		line.default_color = line_color
		line.width = 1
		grid.add_child(line)
	
	for y in range(0, height, grid_size):
		var line = Line2D.new()
		line.add_point(Vector2(0, y))
		line.add_point(Vector2(width, y))
		line.default_color = line_color
		line.width = 1
		grid.add_child(line)
	
	return grid


# Añadir labels de nodos
func add_node_labels(node: Node, overlay: CanvasLayer, path: String):
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
		add_node_labels(child, overlay, path + "/" + child.name)


# Crear indicador de ejes
func create_axes_indicator() -> Node2D:
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
