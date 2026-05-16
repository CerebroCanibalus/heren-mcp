class_name HerenCoreUtils

## Heren Core Utils - Utilidades compartidas para serialización y deserialización
## Usado por todos los módulos del daemon

static func serialize_value(value) -> Variant:
	"""
	Serializa un valor de Godot a formato JSON-compatible.
	"""
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


static func deserialize_value(value) -> Variant:
	"""
	Deserializa un valor desde formato JSON a tipo Godot.
	Auto-detecta tipos por keys si no tiene __type.
	"""
	if value is Dictionary:
		var type = value.get("__type", "")
		
		# Si tiene "type" sin __, es un recurso generico
		if type == "" and value.has("type"):
			return deserialize_resource(value)
		
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
				# Si no hay path, intentar crear recurso inline
				if value.has("resource_type") or value.has("type"):
					return deserialize_resource(value)
				return null
			_:
				return value
	elif value is String:
		# Si el string es un path a un recurso, cargarlo
		var str_value = value as String
		if str_value.begins_with("res://") or str_value.begins_with("user://"):
			if ResourceLoader.exists(str_value):
				return load(str_value)
		return value
	else:
		return value


static func deserialize_resource(value: Dictionary) -> Resource:
	"""
	Deserializa un diccionario con "type" y propiedades a un recurso de Godot.
	Ejemplo: {"type": "RectangleShape2D", "size": {"x": 64, "y": 64}}
	"""
	var resource_type = value.get("type", "")
	if resource_type == "":
		resource_type = value.get("resource_type", "")
	if resource_type == "":
		return null
	
	# Crear instancia del recurso usando ClassDB
	var resource = ClassDB.instantiate(resource_type)
	if not resource is Resource:
		return null
	
	# Setear propiedades
	for key in value.keys():
		if key in ["type", "resource_type", "__type"]:
			continue
		var prop_value = deserialize_value(value[key])
		# Verificar que la propiedad existe antes de setear
		var has_prop = false
		for prop in resource.get_property_list():
			if prop.name == key:
				has_prop = true
				break
		if has_prop:
			resource.set(key, prop_value)
	
	return resource as Resource
