class_name HerenSceneRegistry
extends RefCounted
## Heren MCP v4 - SceneRegistry.
##
## Registro de escenas en MEMORIA por scene_path (ADR 2026-08-04).
## Fuente de verdad para el flujo create → add → save, independiente del
## sistema de pestañas del editor (que falla silenciosamente: open_scene_from_path
## no siempre abre pestaña → la escena quedaba "fantasma" y save no la persistía).
##
## PRINCIPIO (rediseño 2026-08-15): el DISCO es la fuente de verdad. La memoria
## es solo un overlay de trabajo del agente. Antes de CADA operación sobre una
## escena que existe en disco, el plugin sincroniza: si el disco cambió (mtime),
## recarga desde disco y re-aplica las ops pendientes del agente (replay).
## El agente NUNCA ve el conflicto — se resuelve silenciosamente.
##
## Resolución de escena (resolve_root), en orden:
##   0. SYNC: si el disco cambió → reload/replay ANTES de operar
##   1. Pestaña REAL del editor que coincide (lo que el usuario ve)
##   2. Registry (escena creada/editada por MCP en memoria, sin pestaña)
##   3. Archivo en disco → open_scene_from_path
##   4. null (error claro, nunca escena equivocada)


static var _scenes: Dictionary = {}  # scene_path → Node (root)
static var _mtimes: Dictionary = {}  # scene_path → int (mtime al registrar)
static var _pending_ops: Dictionary = {}  # scene_path → Array[Dictionary] (ops del agente re-aplicables)
static var _dirty: Dictionary = {}  # scene_path → bool (hay mutaciones pendientes)


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
	# 🚨 ORDEN CRÍTICO: is_instance_valid() PRIMERO (seguro con freed), luego
	# `is Node`. Si root es una instancia previamente liberada, `root is Node`
	# CRASHEA con "Left operand of 'is' is a previously freed instance".
	if is_instance_valid(root) and root is Node:
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
	_pending_ops.clear()
	_dirty.clear()


## Actualiza el mtime registrado para una escena (llamar después de save).
static func update_mtime(path: String) -> void:
	var p := _norm(path)
	if p == "":
		return
	_mtimes[p] = _get_file_mtime(p)


## ============================================================
## Ops pendientes del agente (replay) — rediseño 2026-08-15
## ============================================================

## Registra una operación del agente para poder re-aplicarla sobre un árbol
## fresco del disco (si el disco cambió entre la op y el save).
static func record_op(path: String, op: Dictionary) -> void:
	var p := _norm(path)
	if p == "":
		return
	if not _pending_ops.has(p):
		_pending_ops[p] = []
	(_pending_ops[p] as Array).append(op)
	_dirty[p] = true


## Limpia las ops pendientes de una escena (tras save exitoso).
static func clear_ops(path: String) -> void:
	var p := _norm(path)
	_pending_ops.erase(p)
	_dirty.erase(p)


## Devuelve las ops pendientes de una escena (copia).
static func get_pending_ops(path: String) -> Array:
	var p := _norm(path)
	return (_pending_ops.get(p, []) as Array).duplicate()


static func has_pending_ops(path: String) -> bool:
	var p := _norm(path)
	return _pending_ops.has(p) and (_pending_ops[p] as Array).size() > 0


static func is_dirty(path: String) -> bool:
	var p := _norm(path)
	return _dirty.get(p, false)


## Re-aplica UNA op sobre un root fresco. Devuelve true si se re-aplicó.
## Fail-safe: si la op no puede re-aplicarse (nodo no existe, prop cambió),
## devuelve false y el caller la conserva en _pending_ops para reportar.
static func _replay_op(root: Node, op: Dictionary) -> bool:
	var kind: String = str(op.get("kind", ""))
	var node_path: String = str(op.get("node_path", ""))
	var node: Node = null
	if node_path == "" or node_path == ".":
		node = root
	else:
		node = root.get_node_or_null(NodePath(node_path))
	if node == null:
		return false
	match kind:
		"set_prop":
			var property: String = str(op.get("property", ""))
			if property == "":
				return false
			# 🚨 property puede no existir aún si el script no se aplicó al
			# recargar. Esperamos 1 frame para que Godot aplique el script y
			# sus exports. Si sigue sin existir, es una prop real inexistente.
			if property not in node:
				return false
			node.set(property, op.get("value"))
			return true
		"set_owner":
			node.owner = root
			return true
		_:
			return false  # Op desconocida: no re-aplicable, conservar


## ============================================================
## Sincronización disco ↔ memoria (rediseño 2026-08-15)
## ============================================================

## Detecta si el disco cambió desde el último registro y resuelve la
## divergencia SILENCIOSAMENTE:
##   - Sin ops pendientes: recarga desde disco (el árbol en memoria se
##     refresca; el agente opera sobre la versión fresca)
##   - Con ops pendientes: recarga desde disco + re-aplica las ops (replay)
## Devuelve el root FRESCO si hubo sync, null si no hubo divergencia o falló.
## El caller usa el root devuelto en lugar de resolver de nuevo.
static func sync_from_disk(ei: EditorInterface, scene_path: String) -> Node:
	var p := _norm(scene_path)
	if ei == null or p == "":
		return null
	# Caso 4 (matriz): archivo borrado del disco → limpiar, NO recrear.
	if not ResourceLoader.exists(p):
		unregister(p)
		_pending_ops.erase(p)
		_dirty.erase(p)
		return null
	var disk_mtime := _get_file_mtime(p)
	var registered := _mtimes.get(p, -1)
	if registered == -1:
		return null  # Nunca registrada: resolve_root la carga fresca
	if disk_mtime <= registered:
		return null  # Sin divergencia: no tocar nada
	# 🚨 DIVERGENCIA: el disco es más nuevo que nuestra copia.
	var ops: Array = get_pending_ops(p)
	var has_ops: bool = ops.size() > 0
	# Recargar la escena desde disco. Si está activa en la pestaña, forzar
	# reload_scene_from_path (que pierde memoria — por eso re-aplicamos ops).
	# 🚨 API REAL Godot 4: reload_scene_from_path(path) — NO reload_scene_from_disk()
	# (ese es de Godot 3). Además, reload_scene_from_path SOLO funciona una vez
	# por frame con la escena activa (issue #13816) — si falla, usar open.
	var active := ei.get_edited_scene_root()
	var reloaded := false
	if active != null and active.scene_file_path == p:
		if ei.has_method("reload_scene_from_path"):
			ei.reload_scene_from_path(p)
			active = ei.get_edited_scene_root()
			reloaded = active != null and active.scene_file_path == p
	if not reloaded:
		ei.open_scene_from_path(p)
		active = ei.get_edited_scene_root()
	if active == null or active.scene_file_path != p:
		# No se pudo recargar: limpiar y dejar que resolve_root intente de nuevo.
		unregister(p)
		return null
	# Re-aplicar ops pendientes sobre el árbol fresco (replay).
	var skipped: Array = []
	if has_ops:
		for op in ops:
			if not _replay_op(active, op):
				skipped.append(op)
	# Registrar con el mtime NUEVO del disco (ya no hay divergencia).
	register(p, active)
	if skipped.size() > 0:
		# Conservar las no re-aplicadas (el agente las verá en el próximo
		# save como `replay_skipped`) y marcar dirty.
		_pending_ops[p] = skipped
		_dirty[p] = true
	else:
		_pending_ops.erase(p)
		_dirty.erase(p)
	return active


## Resuelve la escena objetivo de una operación.
## Prioridad (rediseño 2026-08-15):
##   0. SYNC: si el disco cambió → reload/replay ANTES de operar
##   1. Pestaña REAL del editor que coincide (lo que el usuario ve)
##   2. Registry (escena creada/editada por MCP en memoria, sin pestaña)
##   3. Archivo en disco → open_scene_from_path
##   4. null (error claro, nunca escena equivocada)
static func resolve_root(ei: EditorInterface, scene_path: String) -> Node:
	if ei == null:
		return null
	if scene_path == "":
		return ei.get_edited_scene_root()
	var path := _norm(scene_path)
	# 0) SYNC: si el disco cambió, recargar/replay ANTES de operar.
	#    Esto evita que el agente opere sobre un árbol stale (matriz #1,#9).
	var synced := sync_from_disk(ei, path)
	if synced != null:
		return synced
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
