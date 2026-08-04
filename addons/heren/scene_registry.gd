class_name HerenSceneRegistry
extends RefCounted
## Heren MCP v4 - SceneRegistry.
##
## Registro de escenas en MEMORIA por scene_path (ADR 2026-08-04).
## Fuente de verdad para el flujo create → add → save, independiente del
## sistema de pestañas del editor (que falla silenciosamente: open_scene_from_path
## no siempre abre pestaña → la escena quedaba "fantasma" y save no la persistía).
##
## Resolución de escena (resolve_root), en orden:
##   1. Registry (escena creada/editada por MCP en memoria)
##   2. Pestaña activa que coincide con scene_path
##   3. Archivo en disco → open_scene_from_path
##   4. null (error claro, nunca escena equivocada)


static var _scenes: Dictionary = {}  # scene_path → Node (root)


static func register(path: String, root: Node) -> void:
	if path == "" or root == null:
		return
	_scenes[path] = root


static func unregister(path: String) -> void:
	_scenes.erase(path)


static func get_root(path: String) -> Node:
	var root: Variant = _scenes.get(path, null)
	if root is Node and is_instance_valid(root):
		return root
	# Referencia colgante (pestaña cerrada → nodo liberado): limpiar.
	_scenes.erase(path)
	return null


static func has(path: String) -> bool:
	return get_root(path) != null


static func all() -> Dictionary:
	var out := {}
	for path in _scenes.keys():
		var root := get_root(path)
		if root != null:
			out[path] = root
	return out


static func clear() -> void:
	_scenes.clear()


## Resuelve la escena objetivo de una operación: registry → pestaña → disco.
static func resolve_root(ei: EditorInterface, scene_path: String) -> Node:
	if ei == null:
		return null
	if scene_path == "":
		return ei.get_edited_scene_root()
	var registered := get_root(scene_path)
	if registered != null:
		return registered
	var active := ei.get_edited_scene_root()
	if active != null and active.scene_file_path == scene_path:
		register(scene_path, active)
		return active
	if ResourceLoader.exists(scene_path):
		ei.open_scene_from_path(scene_path)
		var opened := ei.get_edited_scene_root()
		if opened != null and opened.scene_file_path == scene_path:
			register(scene_path, opened)
			return opened
	return null
