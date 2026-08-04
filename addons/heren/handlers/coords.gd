@tool
class_name HerenCoords
extends RefCounted

# Heren MCP v4 - Unified coordinate serialization (ADR-005).
# Inherits the successful v3 serialize/deserialize (auto-detect by keys)
# and expands it: Vector2i/3i, Transform2D/3D, Quaternion, StringName,
# Plane/AABB. Lives in the plugin (Godot exact conversion); the generic
# JSON contract lives in FlojoMCP for reuse by other engines.
#
# No class_name collision with v3's HerenCoreUtils (still present in daemon/).


## Serialize a Godot value to JSON-compatible dict/primitive.
static func serialize_value(value: Variant) -> Variant:
	if value is Vector2:
		return {"x": value.x, "y": value.y, "__type": "Vector2"}
	elif value is Vector2i:
		return {"x": value.x, "y": value.y, "__type": "Vector2i"}
	elif value is Vector3:
		return {"x": value.x, "y": value.y, "z": value.z, "__type": "Vector3"}
	elif value is Vector3i:
		return {"x": value.x, "y": value.y, "z": value.z, "__type": "Vector3i"}
	elif value is Color:
		return {"r": value.r, "g": value.g, "b": value.b, "a": value.a, "__type": "Color"}
	elif value is Rect2:
		return {"x": value.position.x, "y": value.position.y, "w": value.size.x, "h": value.size.y, "__type": "Rect2"}
	elif value is Rect2i:
		return {"x": value.position.x, "y": value.position.y, "w": value.size.x, "h": value.size.y, "__type": "Rect2i"}
	elif value is NodePath:
		return {"path": str(value), "__type": "NodePath"}
	elif value is StringName:
		return {"name": str(value), "__type": "StringName"}
	elif value is Quaternion:
		return {"x": value.x, "y": value.y, "z": value.z, "w": value.w, "__type": "Quaternion"}
	elif value is Plane:
		return {"normal": serialize_value(value.normal), "d": value.d, "__type": "Plane"}
	elif value is AABB:
		return {"position": serialize_value(value.position), "size": serialize_value(value.size), "__type": "AABB"}
	elif value is Transform2D:
		return {
			"origin": serialize_value(value.origin),
			"x_axis": serialize_value(value.x),
			"y_axis": serialize_value(value.y),
			"__type": "Transform2D",
		}
	elif value is Transform3D:
		return {
			"origin": serialize_value(value.origin),
			"basis": {
				"x": serialize_value(value.basis.x),
				"y": serialize_value(value.basis.y),
				"z": serialize_value(value.basis.z),
			},
			"__type": "Transform3D",
		}
	elif value is Object and value is Resource and value.resource_path:
		return {"resource_path": value.resource_path, "__type": "Resource"}
	else:
		return value


## Deserialize a JSON-compatible value to a Godot type.
## Auto-detects types by keys when __type is missing (v3 legacy success).
static func deserialize_value(value: Variant) -> Variant:
	if value is Dictionary:
		var type: String = str(value.get("__type", ""))

		# v3 legacy: {"type": ...} is a generic resource.
		if type == "" and value.has("type"):
			return deserialize_resource(value)

		# Auto-detect by keys (v3 success: positions just work).
		if type == "":
			if value.has("origin") and value.has("x_axis") and value.has("y_axis"):
				type = "Transform2D"
			elif value.has("origin") and value.has("basis"):
				type = "Transform3D"
			elif value.has("normal") and value.has("d"):
				type = "Plane"
			elif value.has("position") and value.has("size"):
				# Ambiguous: AABB (3D) vs Rect2 (2D) — Rect2 has x/y directly.
				if value["position"] is Dictionary and value["position"].has("z"):
					type = "AABB"
				else:
					type = "Rect2"
			elif value.has("x") and value.has("y") and value.has("z") and value.has("w"):
				type = "Quaternion"
			elif value.has("x") and value.has("y") and value.has("z"):
				type = "Vector3"
			elif value.has("x") and value.has("y"):
				# Distinguish Vector2 vs Vector2i vs Rect2 via __type only;
				# default to Vector2 for plain {x,y} (v3 behavior).
				type = "Vector2"
			elif value.has("r") and value.has("g") and value.has("b"):
				type = "Color"

		match type:
			"Vector2":
				return Vector2(value.get("x", 0), value.get("y", 0))
			"Vector2i":
				return Vector2i(int(value.get("x", 0)), int(value.get("y", 0)))
			"Vector3":
				return Vector3(value.get("x", 0), value.get("y", 0), value.get("z", 0))
			"Vector3i":
				return Vector3i(int(value.get("x", 0)), int(value.get("y", 0)), int(value.get("z", 0)))
			"Color":
				return Color(value.get("r", 0), value.get("g", 0), value.get("b", 0), value.get("a", 1))
			"Rect2":
				return Rect2(value.get("x", 0), value.get("y", 0), value.get("w", 0), value.get("h", 0))
			"Rect2i":
				return Rect2i(int(value.get("x", 0)), int(value.get("y", 0)), int(value.get("w", 0)), int(value.get("h", 0)))
			"NodePath":
				return NodePath(str(value.get("path", "")))
			"StringName":
				return StringName(str(value.get("name", "")))
			"Quaternion":
				return Quaternion(value.get("x", 0), value.get("y", 0), value.get("z", 0), value.get("w", 1))
			"Plane":
				return Plane(deserialize_value(value.get("normal", {})), value.get("d", 0))
			"AABB":
				return AABB(deserialize_value(value.get("position", {})), deserialize_value(value.get("size", {})))
			"Transform2D":
				return Transform2D(
					deserialize_value(value.get("x_axis", {})),
					deserialize_value(value.get("y_axis", {})),
					deserialize_value(value.get("origin", {}))
				)
			"Transform3D":
				var basis_dict: Dictionary = value.get("basis", {})
				var basis := Basis(
					deserialize_value(basis_dict.get("x", {})),
					deserialize_value(basis_dict.get("y", {})),
					deserialize_value(basis_dict.get("z", {}))
				)
				return Transform3D(basis, deserialize_value(value.get("origin", {})))
			"Resource":
				var path: String = str(value.get("resource_path", ""))
				if path != "" and ResourceLoader.exists(path):
					return load(path)
				# No path: try inline resource creation.
				if value.has("resource_type") or value.has("type"):
					return deserialize_resource(value)
				return null
			_:
				return value
	elif value is Array:
		# Recursively deserialize each element (arrays of Vector2/Color/
		# nested dicts, etc.). Godot converts Array[Vector2] to PackedVector2Array
		# when the target property is typed.
		var result: Array = []
		for element in value:
			result.append(deserialize_value(element))
		return result
	elif value is String:
		# v3: string that looks like a resource path gets loaded.
		var str_value := value as String
		if str_value.begins_with("res://") or str_value.begins_with("user://"):
			if ResourceLoader.exists(str_value):
				return load(str_value)
		return value
	else:
		return value


## Deserialize a dictionary with "type"/"resource_type" + props to a Resource.
## Example: {"type": "RectangleShape2D", "size": {"x": 64, "y": 64}}
static func deserialize_resource(value: Dictionary) -> Resource:
	var resource_type: String = str(value.get("type", value.get("resource_type", "")))
	if resource_type == "":
		return null

	var resource: Variant = ClassDB.instantiate(resource_type)
	if resource == null or not resource is Resource:
		return null
	var res := resource as Resource

	for key in value.keys():
		if key in ["type", "resource_type", "__type"]:
			continue
		var prop_value: Variant = deserialize_value(value[key])
		for prop in res.get_property_list():
			if prop.name == key:
				res.set(key, prop_value)
				break

	return res


## Normalize a node path to be resolvable from the scene root.
## Accepts: "Name", "/root/Root/Name", "Root/Name", "./Name", NodePath.
static func normalize_node_path(node_path: Variant, root: Node) -> String:
	if node_path == null:
		return ""
	var path_str := str(node_path)
	if path_str == "":
		return ""
	if path_str == ".":
		return "."
	# Strip leading "/root/" if present.
	if path_str.begins_with("/root/"):
		path_str = path_str.substr(6)
	# If the first segment is the root's own name, strip it.
	if path_str.begins_with(root.name + "/"):
		path_str = path_str.substr(root.name.length() + 1)
	elif path_str == root.name:
		path_str = "."
	# Normalize "./" prefix (child relative).
	if path_str.begins_with("./"):
		path_str = path_str.substr(2)
	if path_str == "":
		return "."
	return path_str


## Asegura que root y TODOS sus descendientes tengan owner = root.
## CRÍTICO: PackedScene.pack() omite nodos sin owner → una escena construida
## por MCP (add_child por script NO setea owner) se guardaría vacía o incompleta.
## OJO con instancias externas: un nodo con scene_file_path != "" ES una
## instancia de .tscn → su raíz pertenece al árbol (owner = root) pero sus
## internos NO se tocan (se guardan por referencia en el .tscn externo).
static func ensure_owner_recursive(root: Node) -> void:
	if root == null:
		return
	root.owner = root
	_ensure_owner_child(root, root)


static func _ensure_owner_child(node: Node, owner: Node) -> void:
	for child in node.get_children():
		if child.scene_file_path != "":
			# Instancia externa: solo la raíz pertenece a esta escena; sus
			# internos se serializan en el .tscn referenciado (ExtResource).
			child.owner = owner
			continue
		child.owner = owner
		_ensure_owner_child(child, owner)
