class_name HerenTscnSerializer



static func pre_save_resource_fix(node: Node):
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
				setup_resource_local_to_scene_recursive(res)
	
	# Recursion en hijos
	for child in node.get_children():
		pre_save_resource_fix(child)


static func setup_resource_local_to_scene_recursive(resource: Resource):
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
				setup_resource_local_to_scene_recursive(sub_res)


static func derive_resource_path(resource: Resource) -> String:
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


static func collect_sub_resources(node: Node) -> Array:
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
					"node_path": get_node_path_relative(node),
					"prop_name": prop_name,
					"resource": value,
					"resource_type": value.get_class()
				})
	
	# Recursion en hijos
	for child in node.get_children():
		resources.append_array(collect_sub_resources(child))
	
	return resources


static func collect_connections(node: Node) -> Array:
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
						"from_path": get_node_path_relative(node),
						"to_path": get_node_path_relative(target_node),
						"method": callable_obj.get_method()
					})
	
	# Recursion en hijos
	for child in node.get_children():
		connections.append_array(collect_connections(child))
	
	return connections


static func get_node_path_relative(node: Node) -> String:
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


static func inject_into_tscn(scene_path: String, sub_resources: Array, connections: Array):
	"""
	Inyecta sub_resources y conexiones en un archivo .tscn existente.
	Modifica el archivo directamente agregando [sub_resource] y [connection].
	Maneja recursos anidados (ej: ShaderMaterial.shader).
	
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
			
			# Serializar propiedades, esto puede agregar sub-resources anidados
			var nested_dict = {}
			var res_properties = serialize_resource_properties(res, nested_dict)
			
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
			update_node_subresource_ref(result_lines, node_path, prop_name, res_id)
		
		# Preparar lineas de sub-resources
		for res_id in all_sub_resources.keys():
			var res_data = all_sub_resources[res_id]
			sub_resources_to_inject.append("[sub_resource type=\"" + res_data["type"] + "\" id=\"" + res_id + "\"]")
			for prop_line in res_data["properties"]:
				sub_resources_to_inject.append(prop_line)
			sub_resources_to_inject.append("")
	
	# Encontrar posicion de insercion: despues del ultimo [sub_resource] existente
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
	
	# Decidir donde insertar
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
		print("[Inject] Inyectados ", sub_resources.size(), " sub-resources y ", connections.size(), " conexiones en ", scene_path)


static func serialize_resource_properties(resource: Resource, sub_resources_dict: Dictionary = {}) -> Array:
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
					"properties": serialize_resource_properties(nested_res, sub_resources_dict)
				}
				lines.append(prop_name + " = SubResource(\"" + nested_id + "\")")
				continue
		
		# Serializar segun tipo
		var serialized = serialize_value_tscn(value)
		if not serialized.is_empty():
			lines.append(prop_name + " = " + serialized)
	
	return lines


static func serialize_value_tscn(value) -> String:
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
			return "Rect2(" + serialize_value_tscn(r.position) + ", " + serialize_value_tscn(r.size) + ")"
		TYPE_RECT2I:
			var r = value as Rect2i
			return "Rect2i(" + serialize_value_tscn(r.position) + ", " + serialize_value_tscn(r.size) + ")"
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
				parts.append(serialize_value_tscn(item))
			return "[" + ", ".join(parts) + "]"
		TYPE_DICTIONARY:
			var dict = value as Dictionary
			var parts = []
			for key in dict.keys():
				parts.append(serialize_value_tscn(key) + ": " + serialize_value_tscn(dict[key]))
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


static func update_node_subresource_ref(lines: Array, node_path: String, prop_name: String, res_id: String):
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
	# Un bloque de nodo termina cuando encontramos otra linea [node, [sub_resource, [connection, o linea vacía]
	var existing_prop_line = -1
	for i in range(target_node_line + 1, lines.size()):
		var line = lines[i]
		# Si encontramos inicio de otra sección, salimos
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
