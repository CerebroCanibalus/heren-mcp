@tool
class_name HerenTemplateRegistry
extends RefCounted

# Heren MCP v4 - Sistema transversal de templates (Fase UI-1).
#
# Patron identico a coords.gd: RefCounted + funciones estaticas, cualquier
# handler lo usa sin registro en el EditorPlugin. NO esta acoplado a la tool
# `ui` — node/instantiate, resource, shader, etc. pueden consumirlo.
#
# Modelo hibrido (decision del General 2026-08-14):
#   templates .tscn con nodos CANONICOS + params por metadata.json.
#   El registry instancia el .tscn y setea `node.set(property, value)` en el
#   nodo target. NUNCA generar el arbol con codigo GDScript.
#
# metadata.json (addons/heren/templates/metadata.json):
#   {name, category, description, file, params: [
#     {name, target|targets, property, resource?, description}
#   ]}
#   target "." = root del template. targets = array (mismo valor a varios nodos).
#   resource:true = el valor es un path (res://...) que se carga con load().
#
# Los valores de los params viajan por el sistema de coordenadas
# (HerenCoords.deserialize_value): dict {x,y} -> Vector2, {r,g,b,a} -> Color.

const TEMPLATES_DIR := "res://addons/heren/templates/"
const METADATA_PATH := TEMPLATES_DIR + "metadata.json"

const CoordsScript := preload("handlers/coords.gd")

static var _metadata: Array = []          # cache RAM (primera lectura disco)
static var _metadata_loaded := false


## Lista todos los templates: Array[Dictionary] con name/category/description/params.
static func list_templates() -> Array:
	_load_metadata()
	return _metadata


## True si existe un template con ese nombre.
static func template_exists(template_name: String) -> bool:
	_load_metadata()
	return not _find(template_name).is_empty()


## Instancia un template aplicando params. Devuelve el Node raiz, o null si
## el template no existe o falla la carga/instanciacion.
static func instantiate(template_name: String, params: Dictionary = {}) -> Node:
	_load_metadata()
	var template: Dictionary = _find(template_name)
	if template.is_empty():
		return null

	var path: String = str(template.get("file", ""))
	if path == "":
		return null
	var packed: PackedScene = load(TEMPLATES_DIR + path)
	if packed == null:
		return null
	var instance: Node = packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	if instance == null:
		return null

	_apply_params(instance, template, params)
	return instance


# ---------------------------------------------------------------- internals

static func _load_metadata() -> void:
	if _metadata_loaded:
		return
	_metadata_loaded = true
	if not ResourceLoader.exists(METADATA_PATH):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(METADATA_PATH))
	if data is Dictionary:
		var templates: Variant = data.get("templates", [])
		if templates is Array:
			_metadata = templates


static func _find(template_name: String) -> Dictionary:
	for t in _metadata:
		if str(t.get("name", "")) == template_name:
			return t
	return {}


static func _apply_params(instance: Node, template: Dictionary, params: Dictionary) -> void:
	var param_defs: Array = template.get("params", [])
	for p in param_defs:
		var pname: String = str(p.get("name", ""))
		if pname == "" or not params.has(pname):
			continue
		var value: Variant = params[pname]
		var resource_flag: bool = bool(p.get("resource", false))

		var targets: Array = []
		if p.has("targets") and p.get("targets") is Array:
			targets = p.get("targets")
		elif p.has("target"):
			targets = [p.get("target")]
		for target in targets:
			var node: Node = instance if str(target) == "." else instance.get_node_or_null(NodePath(target))
			if node == null:
				continue
			var prop: StringName = StringName(str(p.get("property", "")))
			if prop == "" or prop not in node:
				continue
			# Params resource: cargar el recurso por path (res://...) y setearlo.
			var final_value: Variant = value
			if resource_flag and value is String:
				var loaded: Resource = load(value)
				if loaded != null:
					final_value = loaded
			else:
				final_value = CoordsScript.deserialize_value(value)
			node.set(prop, final_value)
