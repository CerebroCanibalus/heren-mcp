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
## compact=true omite "__type" en tipos que deserialize_value auto-detecta por
## keys (Vector2/3, Color, Quaternion, Plane, AABB, Transform2D/3D) → hasta
## -43% tokens en respuestas de lectura. Los ambiguos (Vector2i, Rect2,
## NodePath, StringName, Resource) SIEMPRE conservan __type.
static func serialize_value(value: Variant, compact: bool = false) -> Variant:
	if value is Vector2:
		return {"x": value.x, "y": value.y} if compact else {"x": value.x, "y": value.y, "__type": "Vector2"}
	elif value is Vector2i:
		return {"x": value.x, "y": value.y, "__type": "Vector2i"}
	elif value is Vector3:
		return {"x": value.x, "y": value.y, "z": value.z} if compact else {"x": value.x, "y": value.y, "z": value.z, "__type": "Vector3"}
	elif value is Vector3i:
		return {"x": value.x, "y": value.y, "z": value.z, "__type": "Vector3i"}
	elif value is Color:
		return {"r": value.r, "g": value.g, "b": value.b, "a": value.a} if compact else {"r": value.r, "g": value.g, "b": value.b, "a": value.a, "__type": "Color"}
	elif value is Rect2:
		return {"x": value.position.x, "y": value.position.y, "w": value.size.x, "h": value.size.y, "__type": "Rect2"}
	elif value is Rect2i:
		return {"x": value.position.x, "y": value.position.y, "w": value.size.x, "h": value.size.y, "__type": "Rect2i"}
	elif value is NodePath:
		return {"path": str(value), "__type": "NodePath"}
	elif value is StringName:
		return {"name": str(value), "__type": "StringName"}
	elif value is Quaternion:
		return {"x": value.x, "y": value.y, "z": value.z, "w": value.w} if compact else {"x": value.x, "y": value.y, "z": value.z, "w": value.w, "__type": "Quaternion"}
	elif value is Plane:
		return {"normal": serialize_value(value.normal, compact), "d": value.d} if compact else {"normal": serialize_value(value.normal, compact), "d": value.d, "__type": "Plane"}
	elif value is AABB:
		return {"position": serialize_value(value.position, compact), "size": serialize_value(value.size, compact)} if compact else {"position": serialize_value(value.position, compact), "size": serialize_value(value.size, compact), "__type": "AABB"}
	elif value is Transform2D:
		return {
			"origin": serialize_value(value.origin, compact),
			"x_axis": serialize_value(value.x, compact),
			"y_axis": serialize_value(value.y, compact),
			"__type": "Transform2D",
		} if compact else {
			"origin": serialize_value(value.origin, compact),
			"x_axis": serialize_value(value.x, compact),
			"y_axis": serialize_value(value.y, compact),
			"__type": "Transform2D",
		}
	elif value is Transform3D:
		return {
			"origin": serialize_value(value.origin, compact),
			"basis": {
				"x": serialize_value(value.basis.x, compact),
				"y": serialize_value(value.basis.y, compact),
				"z": serialize_value(value.basis.z, compact),
			},
			"__type": "Transform3D",
		} if compact else {
			"origin": serialize_value(value.origin, compact),
			"basis": {
				"x": serialize_value(value.basis.x, compact),
				"y": serialize_value(value.basis.y, compact),
				"z": serialize_value(value.basis.z, compact),
			},
			"__type": "Transform3D",
		}
	elif value is Object and value is Resource and value.resource_path:
		# Recurso con path: referencia por path (el agente puede load()).
		return {"resource_path": value.resource_path, "__type": "Resource"}
	elif value is Object and value is Resource:
		# Sub-recurso INLINE sin resource_path (StyleBoxFlat dentro de un
		# Theme .tres, Curve/Gradient en ParticleProcessMaterial, etc.).
		# Fix 2026-08-06: antes caía al `else` → devolvía el objeto Godot crudo
		# → JSON no representaba bg_color/border_color → se perdían (negro).
		# Ahora serializa la clase + props con el MISMO filtro STORAGE que
		# resource_handlers._serialize_resource_props (round-trip completo).
		var d := {"__type": "Resource", "resource_class": value.get_class(), "props": {}}
		for prop in value.get_property_list():
			var usage: int = int(prop.usage)
			if usage & PROPERTY_USAGE_STORAGE == 0:
				continue
			if usage & PROPERTY_USAGE_INTERNAL != 0:
				continue
			var pname: StringName = prop.name
			if pname in ["resource_path", "resource_local_to_scene", "resource_name"]:
				continue
			d["props"][pname] = serialize_value(value.get(pname), compact)
		return d
	else:
		return value


## Deserialize a JSON-compatible value to a Godot type.
## Auto-detects types by keys when __type is missing (v3 legacy success).
static func deserialize_value(value: Variant) -> Variant:
	# BUG 3 fix: si el valor llega como string JSON (por serialización del server),
	# parsearlo primero para obtener el Dictionary/Array real.
	if value is String:
		var parsed = JSON.parse_string(value)
		if parsed != null:
			value = parsed
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
				# BUG 3 fix: forzar conversión a float para evitar problemas con strings.
				return Color(float(value.get("r", 0)), float(value.get("g", 0)), float(value.get("b", 0)), float(value.get("a", 1)))
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
				# Inline: {"resource_class": "StyleBoxFlat", "props": {...}}.
				# (fix 2026-08-06: sub-recursos sin path con props serializadas)
				if value.has("props") and value["props"] is Dictionary:
					return deserialize_resource(value)
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
	var resource_type: String = str(value.get("type", value.get("resource_type", value.get("resource_class", ""))))
	if resource_type == "":
		return null

	var resource: Variant = ClassDB.instantiate(resource_type)
	if resource == null or not resource is Resource:
		return null
	var res := resource as Resource

	# Inline serialization (fix 2026-08-06): {"resource_class", "props": {...}}
	# — los props del sub-recurso viven en "props" (ver serialize_value).
	if value.has("props") and value["props"] is Dictionary:
		for key in value["props"].keys():
			var k: String = str(key)
			if k in res:
				var prop_type: int = TYPE_NIL
				var prop_hint: String = ""
				for prop in res.get_property_list():
					if prop.name == k:
						prop_type = int(prop.type)
						prop_hint = str(prop.hint_string)
						break
				var prop_value: Variant = deserialize_typed(value["props"][key], prop_type, res.get(k))
				prop_value = _wrap_curve_gradient(prop_value, prop_hint)
				res.set(k, prop_value)
		return res

	for key in value.keys():
		if key in ["type", "resource_type", "__type", "resource_class"]:
			continue
		# Curve._data: formato INTERNO = 5 elementos por punto
		# [position(Vector2), left_tangent, right_tangent, left_mode, right_mode].
		# El usuario pasa solo posiciones [[x,y],...] → expandir. (curve.cpp set_data)
		if resource_type == "Curve" and key == "_data" and value[key] is Array:
			res.set(key, expand_curve_data(value[key]))
			continue
		var prop_type: int = TYPE_NIL
		var prop_hint: String = ""
		var found := false
		for prop in res.get_property_list():
			if prop.name == key:
				prop_type = int(prop.type)
				prop_hint = str(prop.hint_string)
				found = true
				break
		if not found:
			continue
		var prop_value: Variant = deserialize_typed(value[key], prop_type, res.get(key))
		# Godot 4: props *_curve (Texture2D) esperan CurveTexture/CurveXYZTexture
		# (NO Curve), color_ramp espera GradientTexture1D (NO Gradient) — el
		# usuario pasa Curve/Gradient naturalmente; wrap automático por hint.
		prop_value = _wrap_curve_gradient(prop_value, prop_hint)
		res.set(key, prop_value)

	return res


## Deserializa `value` según el TIPO DECLARADO de la propiedad destino
## (`target_type` del property list, con fallback al tipo del valor actual).
## Sin esto, un Array anidado [x,y] se queda como Array y Godot lo convierte
## a PackedVector2Array produciendo Vector2(0,0) — el bug de Curve._data y
## Gradient.colors que quedaban negros/cero.
static func deserialize_typed(value: Variant, target_type: int, target_value: Variant = null) -> Variant:
	var t: int = target_type
	var vt: int = typeof(target_value) if target_value != null else TYPE_NIL
	# El tipo del VALOR actual es más fiable que el declarado para props
	# internas (ej: Curve._data reporta INT pero es PackedVector2Array).
	if vt == TYPE_PACKED_VECTOR2_ARRAY or vt == TYPE_PACKED_VECTOR3_ARRAY \
			or vt == TYPE_PACKED_COLOR_ARRAY or vt == TYPE_PACKED_FLOAT32_ARRAY \
			or vt == TYPE_PACKED_FLOAT64_ARRAY or vt == TYPE_PACKED_INT32_ARRAY \
			or vt == TYPE_PACKED_STRING_ARRAY or vt == TYPE_PACKED_BYTE_ARRAY:
		t = vt
	# Fallback por contenido: Array de arrays numéricos uniformes (2/3/4)
	# → packed del tamaño detectado. Cubre props internas sin tipo real.
	if t == TYPE_NIL or t == TYPE_OBJECT or t == TYPE_ARRAY or t == TYPE_INT:
		var dim := _packed_dim(value)
		if dim != 0:
			t = dim
	if not value is Array:
		return deserialize_value(value)
	match t:
		TYPE_PACKED_VECTOR2_ARRAY:
			var out := PackedVector2Array()
			for e in value:
				if e is Dictionary:
					out.append(deserialize_value(e))
				elif e is Array:
					out.append(Vector2(float(e[0]), float(e[1])))
				elif e is Vector2:
					out.append(e)
			return out
		TYPE_PACKED_VECTOR3_ARRAY:
			var out := PackedVector3Array()
			for e in value:
				if e is Dictionary:
					out.append(deserialize_value(e))
				elif e is Array:
					out.append(Vector3(float(e[0]), float(e[1]), float(e[2])))
				elif e is Vector3:
					out.append(e)
			return out
		TYPE_PACKED_COLOR_ARRAY:
			var out := PackedColorArray()
			for e in value:
				if e is Dictionary:
					out.append(deserialize_value(e))
				elif e is Array:
					out.append(Color(float(e[0]), float(e[1]), float(e[2]), float(e[3]) if e.size() > 3 else 1.0))
				elif e is Color:
					out.append(e)
			return out
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			var out := PackedFloat32Array()
			for e in value:
				out.append(float(e))
			return out
		TYPE_PACKED_INT32_ARRAY:
			var out := PackedInt32Array()
			for e in value:
				out.append(int(e))
			return out
		TYPE_PACKED_STRING_ARRAY:
			var out := PackedStringArray()
			for e in value:
				out.append(str(e))
			return out
		_:
			return deserialize_value(value)


## Detecta la dimensión packed de un Array de arrays numéricos uniformes:
## [[x,y],...] → 2 (Vector2), [[x,y,z],...] → 3 (Vector3), [[r,g,b,a],...] → 4 (Color).
## Devuelve 0 si no es un Array de arrays de números con tamaño uniforme.
static func _packed_dim(value: Variant) -> int:
	if not value is Array or value.size() == 0:
		return 0
	var first: Variant = value[0]
	if not first is Array:
		return 0
	var dim: int = first.size()
	if dim < 2 or dim > 4:
		return 0
	for e in value:
		if not e is Array or e.size() != dim:
			return 0
		for n in e:
			if not (n is float or n is int):
				return 0
	return TYPE_PACKED_VECTOR2_ARRAY if dim == 2 \
		else TYPE_PACKED_VECTOR3_ARRAY if dim == 3 \
		else TYPE_PACKED_COLOR_ARRAY


## Godot 4: ParticleProcessMaterial y similares exponen *_curve como Texture2D
## (CurveTexture/CurveXYZTexture) y color_ramp como GradientTexture1D. El
## usuario pasa Curve/Gradient naturalmente; si el hint lo pide, wrap automático.
static func _wrap_curve_gradient(v: Variant, hint: String) -> Variant:
	if hint == "" or not v is Resource:
		return v
	if v is Curve and hint.contains("CurveTexture"):
		var ct := CurveTexture.new()
		ct.curve = v
		return ct
	if v is Gradient and hint.contains("GradientTexture1D"):
		var gt := GradientTexture1D.new()
		gt.gradient = v
		return gt
	return v


## Expande posiciones [[x,y],...] al formato INTERNO de Curve._data
## (5 elementos por punto: position, left_tangent, right_tangent, left_mode,
## right_mode). Si el valor ya viene en formato interno (lista plana con
## Vector2 + números), lo devuelve tal cual.
static func expand_curve_data(value: Variant) -> Variant:
	if not value is Array or value.size() == 0:
		return value
	var pts: Array = value
	if not (pts[0] is Array or pts[0] is Dictionary):
		return value  # ya formato interno
	var curve_data: Array = []
	for p in pts:
		var pos: Vector2 = deserialize_value(p) if p is Dictionary else Vector2(float(p[0]), float(p[1]))
		curve_data.append(pos)  # position
		curve_data.append(0.0)  # left_tangent
		curve_data.append(0.0)  # right_tangent
		curve_data.append(0)    # left_mode (TANGENT_FREE)
		curve_data.append(0)    # right_mode (TANGENT_FREE)
	return curve_data


## Marca `resource_local_to_scene` en el recurso y TODOS sus sub-recursos.
## Sin esto, Godot omite los sub-recursos sin resource_path al guardar la
## escena (la causa de "el Curve/Gradient se pierden al guardar").
static func ensure_resource_local_recursive(res: Resource) -> void:
	if res.resource_path != "":
		return  # recurso externo: no tocar
	if res.resource_local_to_scene:
		return  # ya marcado (también corta ciclos)
	res.resource_local_to_scene = true
	for prop in res.get_property_list():
		var usage: int = int(prop.usage)
		if usage & PROPERTY_USAGE_STORAGE == 0:
			continue
		if usage & PROPERTY_USAGE_INTERNAL != 0:
			continue
		var v: Variant = res.get(prop.name)
		if v is Resource:
			ensure_resource_local_recursive(v)
		elif v is Array:
			for e in v:
				if e is Resource:
					ensure_resource_local_recursive(e)


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


## ============================================================
## Sistema de coordenadas SMART (NIVEL 0+) — "deltas con significado".
## La investigación (SiT-Bench, Martorell 2025) muestra que los LLM razonan
## mejor con estructura cartesiana JSON + representaciones RELATIVAS que con
## números absolutos. Para animación: el agente necesita "qué cambió, en qué
## dirección, respecto a qué" — no 12 números por hueso.
## ============================================================

## Delta de rotación entre dos Transform3D/Transform2D, en GRADOS por eje
## (euler). Los LLM interpretan "+28° en X" mucho mejor que quaternions.
## Devuelve {"x": float, "y": float, "z": float} (grados) o {} si no puede.
static func rotation_delta_deg(from: Variant, to: Variant) -> Dictionary:
	var out := {}
	if from is Transform3D and to is Transform3D:
		# Rotación relativa: to * from⁻¹ (deshace el rest → el delta puro).
		var rel: Basis = (to as Transform3D).basis * (from as Transform3D).basis.inverse()
		var eul := rel.get_euler()
		out = {
			"x": round(eul.x * 180.0 / PI * 100.0) / 100.0,
			"y": round(eul.y * 180.0 / PI * 100.0) / 100.0,
			"z": round(eul.z * 180.0 / PI * 100.0) / 100.0,
		}
	elif from is Transform2D and to is Transform2D:
		var delta := (to as Transform2D).get_rotation() - (from as Transform2D).get_rotation()
		out = {
			"z": round(rad_to_deg(delta) * 100.0) / 100.0,
		}
	return out


## Delta de origen entre dos Transform3D (o posiciones), redondeado a 3 dec.
static func origin_delta(from: Variant, to: Variant) -> Dictionary:
	var out := {}
	if from is Transform3D and to is Transform3D:
		var d: Vector3 = (to as Transform3D).origin - (from as Transform3D).origin
		out = {
			"x": round(d.x * 1000.0) / 1000.0,
			"y": round(d.y * 1000.0) / 1000.0,
			"z": round(d.z * 1000.0) / 1000.0,
		}
	elif from is Transform2D and to is Transform2D:
		var d: Vector2 = (to as Transform2D).origin - (from as Transform2D).origin
		out = {
			"x": round(d.x * 1000.0) / 1000.0,
			"y": round(d.y * 1000.0) / 1000.0,
		}
	return out


## Asegura que root y TODOS sus descendientes tengan owner = root.
## CRÍTICO: PackedScene.pack() omite nodos sin owner → una escena construida
## por MCP (add_child por script NO setea owner) se guardaría vacía o incompleta.
## OJO con instancias externas: un nodo con scene_file_path != "" ES una
## instancia de .tscn → su raíz pertenece al árbol (owner = root) pero sus
## internos NO se tocan (se guardan por referencia en el .tscn externo).
static func ensure_owner_recursive(root: Node) -> void:
	if root == null:
		return
	# root.owner debe ser null (es el root de la escena, no puede ser owner de sí mismo)
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


## Coords estructurados de un Node — un solo punto de verdad para que el
## agente reciba position/rotation/scale en JSON tras open/save/orchestrate.
## Acepta Node3D/Node2D/Control; para otros tipos devuelve {}.
## - Node3D: position (Vector3), rotation_degrees (Vector3 en grados), scale (Vector3).
## - Node2D: position (Vector2), rotation_degrees (float), scale (Vector2).
## - Control: anchors_preset (int), anchors (4 floats), offsets (4 floats),
##             pivot_offset, size, rotation_degrees, scale.
## Única fuente de verdad del sistema de coordenadas del plugin (Fase A).
## Devuelve un dict discriminado por `kind` (clase real Godot) + `flags`
## (capacidades detectadas) para que el cliente sepa qué campos esperar SIN
## parsear. NO desperdicia datos: un nodo 2D jamás trae `quaternion`/`basis`/
## `cast_shadow`/`render_layers`; un nodo 3D jamás trae `z_index`/`y_sort`
## ni `anchors`.
##
## tier (int, default 1):
##   0 → kind + flags + parent_path + visible                    (~30 tok)
##   1 → + pos / scale / rotation (kind-specific) + bbox / aabb  (~80-150 tok)
##   2 → + modulate / material / collision / render layers /
##       Control: anchors, offsets, size, effective_rect         (~150-250 tok)
##   3 → + animation / light / audio (Fase C — no usado aún)     (~250-400 tok)
##
## `parent_path` es del PADRE inmediato ("" si el nodo es root). Quien llama
## lo precalcula con `_node_path_relative(node.get_parent(), root)` —
## desacoplar coords.gd del "root" mantiene la función pura y testeable.
static func coords_of_node(node: Node, parent_path: String = "", tier: int = 1) -> Dictionary:
	if node == null:
		return {"kind": "None", "flags": _empty_flags(), "parent_path": parent_path, "visible": true}

	var flags := _detect_flags(node)
	var out: Dictionary = {
		"kind": node.get_class(),
		"flags": flags,
		"parent_path": parent_path,
		"visible": node.is_visible_in_tree() if node.has_method("is_visible_in_tree") else true,
	}

	# === POSICIÓN + TRANSFORM por DIMENSIÓN (MUTUAMENTE EXCLUYENTE) ===
	# tier >= 1 → pos/scale/rotation/bbox; tier 0 → solo metadatos estructurales.
	if tier >= 1:
		if node is Node3D:
			_fill_3d(node, out, flags)
		elif node is CanvasItem:
			_fill_2d_canvas(node, out, flags)

	# === UI Control (descendiente de CanvasItem — siempre encima de _fill_2d) ===
	if node is Control:
		flags["is_control"] = true
		_fill_control(node, out, tier)

	# === TIER 2: modulate / material / collision / render layers / effective_rect ===
	if tier >= 2:
		_fill_tier2(node, out, flags)

	return out


## Backward-compat: tier=1 sin parent_path (legacy `coords_of`).
## Migrar los call sites a coords_of_node cuando se pueda.
static func coords_of(node: Node) -> Dictionary:
	return coords_of_node(node, "", 1)


static func _empty_flags() -> Dictionary:
	return {"is_2d": false, "is_3d": false, "is_control": false, "has_bbox": false, "has_aabb": false}


static func _detect_flags(node: Node) -> Dictionary:
	return {
		"is_2d": node is Node2D,
		"is_3d": node is Node3D,
		"is_control": node is Control,
		"has_bbox": false,
		"has_aabb": false,
	}


## Nodo 3D: pos global + scale + rotación Euler (deg) + quaternion (compact).
## NO trae z_index ni anchors (eso es CanvasItem/Control).
## Asume que node está inside_tree() — si no, global_position/rotation devuelven
## Transform() vacío (warning). Quien llama debe garantizar add_child previo.
static func _fill_3d(node: Node, out: Dictionary, flags: Dictionary) -> void:
	var n3: Node3D = node
	if n3.is_inside_tree():
		out["pos"] = serialize_value(n3.global_position)
	else:
		out["pos"] = serialize_value(n3.position)
	out["scale"] = serialize_value(n3.scale)
	out["rotation"] = {
		"euler_deg": {"x": n3.rotation_degrees.x, "y": n3.rotation_degrees.y, "z": n3.rotation_degrees.z},
		"quat": serialize_value(n3.quaternion, true),
	}
	# AABB solo si es MeshInstance3D con mesh asignado.
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		if mi.mesh != null:
			var aabb: AABB = mi.get_aabb()
			out["aabb"] = serialize_value(aabb, true)
			out["size_3d"] = serialize_value(aabb.size, true)
			flags["has_aabb"] = true


## Nodo 2D / CanvasItem: pos global + scale (si Node2D) + rotación Z (si Node2D)
## + z_index (CanvasItem) + bbox según tipo específico.
## NO trae quaternion ni basis (eso es Node3D).
static func _fill_2d_canvas(node: Node, out: Dictionary, flags: Dictionary) -> void:
	var ci: CanvasItem = node
	if ci.is_inside_tree():
		out["pos"] = serialize_value(ci.global_position)
	else:
		out["pos"] = serialize_value(Vector2.ZERO)
	if node is Node2D:
		var n2: Node2D = node
		out["scale"] = serialize_value(n2.scale)
		out["rotation"] = {"deg": roundf(rad_to_deg(n2.rotation) * 100.0) / 100.0, "rad": n2.rotation}
	out["z_index"] = ci.z_index

	var bbox := _bbox_of_2d(node)
	if not bbox.is_empty():
		out["bbox"] = bbox
		if bbox.has("w") and bbox.has("h"):
			out["size"] = {"w": bbox["w"], "h": bbox["h"]}
		flags["has_bbox"] = true


## Bbox 2D inferida por tipo. Cubre los tipos con geometría derivable;
## cualquier otro CanvasItem (Node, ColorRect, Container...) no tiene bbox
## natural y devuelve {}.
static func _bbox_of_2d(node: Node) -> Dictionary:
	if node is Sprite2D:
		var s: Sprite2D = node
		var tex: Texture2D = s.texture
		if tex != null:
			var w: float = tex.get_width() * s.scale.x
			var h: float = tex.get_height() * s.scale.y
			return {
				"x": s.global_position.x - w * 0.5,
				"y": s.global_position.y - h * 0.5,
				"w": w, "h": h,
			}
		return {}
	if node is AnimatedSprite2D:
		var as2: AnimatedSprite2D = node
		if as2.sprite_frames != null:
			var tex2: Texture2D = as2.sprite_frames.get_frame_texture(as2.animation, as2.frame)
			if tex2 != null:
				var w: float = tex2.get_width() * as2.scale.x
				var h: float = tex2.get_height() * as2.scale.y
				return {
					"x": as2.global_position.x - w * 0.5,
					"y": as2.global_position.y - h * 0.5,
					"w": w, "h": h,
				}
		return {}
	if node is CollisionShape2D:
		var cs: CollisionShape2D = node
		var shape: Shape2D = cs.shape
		if shape is RectangleShape2D:
			var rsize: Vector2 = (shape as RectangleShape2D).size
			return {
				"x": cs.global_position.x - rsize.x * 0.5,
				"y": cs.global_position.y - rsize.y * 0.5,
				"w": rsize.x, "h": rsize.y,
			}
		if shape is CircleShape2D:
			var radius: float = (shape as CircleShape2D).radius
			return {
				"x": cs.global_position.x - radius,
				"y": cs.global_position.y - radius,
				"w": radius * 2.0, "h": radius * 2.0,
			}
		return {}
	if node is Label:
		var lbl: Label = node
		var s2: Vector2 = lbl.get_minimum_size()
		return {
			"x": lbl.global_position.x, "y": lbl.global_position.y,
			"w": s2.x, "h": s2.y,
		}
	if node is Polygon2D:
		var pg: Polygon2D = node
		var pr: Rect2 = pg.get_rect()
		return {
			"x": pg.global_position.x + pr.position.x,
			"y": pg.global_position.y + pr.position.y,
			"w": pr.size.x, "h": pr.size.y,
		}
	if node is Line2D:
		var ln: Line2D = node
		var lr: Rect2 = ln.get_rect()
		return {
			"x": ln.global_position.x + lr.position.x,
			"y": ln.global_position.y + lr.position.y,
			"w": lr.size.x, "h": lr.size.y,
		}
	if node is TextureRect:
		var tr: TextureRect = node
		var ts: Vector2 = tr.size
		return {
			"x": tr.global_position.x, "y": tr.global_position.y,
			"w": ts.x, "h": ts.y,
		}
	if node is Control:
		var ctl2: Control = node
		var cs: Vector2 = ctl2.size
		return {
			"x": ctl2.global_position.x, "y": ctl2.global_position.y,
			"w": cs.x, "h": cs.y,
		}
	return {}


## Control UI: anchors, offsets, size. Tier≥1 ya dio size (si had_bbox); aqui
## siempre expone los anchors/offsets aunque el Control no tenga geometría
## propia. tier=1 → solo anchors/offsets (barato). tier≥2 → + effective_rect
## (post-container-layout) + size_flags.
static func _fill_control(ctl: Control, out: Dictionary, tier: int) -> void:
	out["anchors"] = {
		"left": ctl.anchor_left, "top": ctl.anchor_top,
		"right": ctl.anchor_right, "bottom": ctl.anchor_bottom,
	}
	out["offsets"] = {
		"left": ctl.offset_left, "top": ctl.offset_top,
		"right": ctl.offset_right, "bottom": ctl.offset_bottom,
	}
	if tier >= 2:
		# effective_rect = Rect2 global post-anchors y post-container-layout.
		# Más fiel al "lo que el usuario ve" que size/anchors separados.
		var eff: Rect2 = ctl.get_global_rect()
		out["effective_rect"] = serialize_value(eff, true)
		out["size_flags"] = {
			"horizontal": ctl.size_flags_horizontal,
			"vertical": ctl.size_flags_vertical,
			"stretch_ratio": ctl.size_flags_stretch_ratio,
		}
		out["parent_is_container"] = ctl.get_parent() is Container


## Tier 2: visibility, modulate, material, collision/render layers.
## Accesos defensivos con `"prop" in node` para tolerar builds de Godot donde
## la propiedad no exista (ej: `visibility_mode` añadido en 4.5+;
## `render_layers` vive en GeometryInstance3D, no Node3D puro).
static func _fill_tier2(node: Node, out: Dictionary, flags: Dictionary) -> void:
	# --- CanvasItem: modulate / visibility / material (común 2D y 3D CanvasItem) ---
	if node is CanvasItem:
		var ci: CanvasItem = node
		out["modulate"] = serialize_value(ci.modulate, true)
		out["self_modulate"] = serialize_value(ci.self_modulate, true)
		if "visibility_mode" in ci:
			out["visibility_mode"] = _visibility_mode_str(int(ci.visibility_mode))
		out["top_level"] = ci.top_level
		if "clip_children" in ci:
			out["clip_children"] = int(ci.clip_children)
		if ci.material != null:
			out["material_path"] = ci.material.resource_path if ci.material.resource_path != "" else "(inline)"

	# --- Collision: 2D o 3D ---
	if node is CollisionObject2D:
		var co2: CollisionObject2D = node
		out["collision_layer"] = co2.collision_layer
		out["collision_mask"] = co2.collision_mask
		out["collision_priority"] = co2.collision_priority
	elif node is CollisionObject3D:
		var co3: CollisionObject3D = node
		out["collision_layer"] = co3.collision_layer
		out["collision_mask"] = co3.collision_mask
		out["collision_priority"] = co3.collision_priority

	# --- Render: GeometryInstance3D (no Node3D puro) ---
	# En Godot 4.5 las props viven en GeometryInstance3D: cast_shadow, gi_mode.
	# NO existe `render_layers` ni `visibility_layer` — fue eliminado.
	if "cast_shadow" in node:
		out["cast_shadow"] = int(node.cast_shadow)
	if "gi_mode" in node:
		out["gi_mode"] = int(node.gi_mode)
	if "material_override" in node and node.material_override != null:
		out["material_override_path"] = node.material_override.resource_path if node.material_override.resource_path != "" else "(inline)"
	if "material_overlay" in node and node.material_overlay != null:
		out["material_overlay_path"] = node.material_overlay.resource_path if node.material_overlay.resource_path != "" else "(inline)"


static func _visibility_mode_str(mode: int) -> String:
	# CanvasItem en Godot 4: VISIBILITY_INHERIT=0, VISIBILITY_VISIBLE=1, VISIBILITY_INVISIBLE=2.
	match mode:
		1:
			return "visible"
		2:
			return "invisible"
		_:
			return "inherit"
