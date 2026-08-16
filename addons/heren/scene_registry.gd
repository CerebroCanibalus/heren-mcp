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
##   1. Pestaña REAL del editor que coincide (lo que el usuario ve — si la
##      escena está abierta, operamos sobre ella, no sobre un árbol fantasma)
##   2. Registry (escena creada/editada por MCP en memoria, sin pestaña)
##      — INVALIDADO si el archivo en disco cambió (mtime check)
##   3. Archivo en disco → open_scene_from_path
##   4. null (error claro, nunca escena equivocada)


static var _scenes: Dictionary = {}  # scene_path → Node (root)
static var _mtimes: Dictionary = {}  # scene_path → int (mtime al registrar)


## Normaliza la key a la forma canónica (res://, forward slashes, sin
## trailing) para que coincida SIEMPRE con scene_file_path de las pestañas.
static func _norm(path: String) -> String:
	var s := path.strip_edges()
	if s == "":
		return ""
	s = s.replace("\\", "/")
	while s.ends_with("/"):
		s = s.substr(0, s.length() - 1)
	if not s.begins_with("res://"):
		return "res://" + s
	return s


## Obtiene el mtime de un archivo en disco (0 si no existe).
static func _get_file_mtime(path: String) -> int:
	if not ResourceLoader.exists(path):
		return 0
	var abs_path := ProjectSettings.globalize_path(path)
	var file := FileAccess.open(abs_path, FileAccess.READ)
	if file == null:
		return 0
	var mtime := file.get_modified_time(abs_path)
	file.close()
	return mtime


## Verifica si el archivo en disco cambió desde que se registró la escena.
static func _is_stale(path: String) -> bool:
	var p := _norm(path)
	if not _mtimes.has(p):
		return false  # No tenemos mtime registrado, asumir fresco
	var disk_mtime := _get_file_mtime(p)
	if disk_mtime == 0:
		return false  # Archivo no existe en disco, no puede estar stale
	return disk_mtime > _mtimes[p]


static func register(path: String, root: Node) -> void:
	var p := _norm(path)
	if p == "" or root == null:
		return
	_scenes[p] = root
	# Guardar mtime actual del archivo en disco (0 si no existe aún).
	_mtimes[p] = _get_file_mtime(p)


static func unregister(path: String) -> void:
	var p := _norm(path)
	_scenes.erase(p)
	_mtimes.erase(p)


static func get_root(path: String) -> Node:
	var p := _norm(path)
	# BUG 2 fix: verificar si el archivo en disco cambió (mtime).
	if _is_stale(p):
		# Invalidar cache — el usuario editó el .tscn manualmente.
		_scenes.erase(p)
		_mtimes.erase(p)
		return null
	var root: Variant = _scenes.get(p, null)
	if root is Node and is_instance_valid(root):
		return root
	# Referencia colgante (pestaña cerrada → nodo liberado): limpiar.
	_scenes.erase(p)
	_mtimes.erase(p)
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
	_mtimes.clear()


## Actualiza el mtime registrado para una escena (llamar después de save).
static func update_mtime(path: String) -> void:
	var p := _norm(path)
	if p == "":
		return
	_mtimes[p] = _get_file_mtime(p)


## Resuelve la escena objetivo de una operación.
## Prioridad (fix 2026-08-06, "rehace la escena"):
##   1. Pestaña REAL del editor que coincide (lo que el usuario ve — si la
##      escena está abierta, operamos sobre ella, no sobre un árbol fantasma)
##   2. Registry (escena creada/editada por MCP en memoria, sin pestaña)
##   3. Archivo en disco → open_scene_from_path
##   4. null (error claro, nunca escena equivocada)
static func resolve_root(ei: EditorInterface, scene_path: String) -> Node:
	if ei == null:
		return null
	if scene_path == "":
		return ei.get_edited_scene_root()
	var path := _norm(scene_path)
	# 1) Pestaña real: si el usuario abrió la escena, es la fuente de verdad.
	var active := ei.get_edited_scene_root()
	if active != null and active.scene_file_path == path:
		register(path, active)
		return active
	# 2) Registry (fantasma en memoria — escena creada por MCP sin pestaña).
	var registered := get_root(path)
	if registered != null:
		return registered
	# 3) Disco: abrir y registrar la pestaña.
	if ResourceLoader.exists(path):
		ei.open_scene_from_path(path)
		var opened := ei.get_edited_scene_root()
		if opened != null and opened.scene_file_path == path:
			register(path, opened)
			return opened
	return null
