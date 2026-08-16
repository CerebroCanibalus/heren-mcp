@tool
extends "res://addons/heren/handlers/heren_handler.gd"
# Heren MCP v4 - Scene handlers (Fase 1).
# Handles: health, project_info, get_edited_scene_root, get_open_scenes,
# create, save, open. All mutations go through the UndoRedo wrapper
# (EditorUndoRedoManager) so Ctrl+Z undoes them (ADR-002 advantage).
#
# ADR 2026-08-04 (escenas robustas): el guardado NUNCA pasa por el sistema de
# pestañas. create registra el árbol en HerenSceneRegistry (memoria, por path);
# save hace pack() directo del root registrado → ResourceSaver → disco.
# Así la escena "fantasma" (creada por MCP sin pestaña del editor) persiste.

const HerenSceneRegistryScript := preload("../scene_registry.gd")
const HerenCoordsScript := preload("coords.gd")

var _undo_redo: Node


func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin
	_undo_redo = plugin.get_undo_redo_wrapper()
	print("[HEREN] scene_handlers set_editor_plugin: ", _editor_plugin)


func handle_health(_args: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"status": "healthy",
		"editor_version": Engine.get_version_info().get("string", ""),
	}


func handle_project_info(_args: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"project_path": ProjectSettings.globalize_path("res://"),
		"project_name": ProjectSettings.get_setting("application/config/name", ""),
	}


func handle_get_edited_scene_root(_args: Dictionary) -> Dictionary:
	var ei := _editor_interface()
	if ei == null:
		return {"ok": false, "error": "editor interface unavailable"}
	var root := ei.get_edited_scene_root()
	if root == null:
		return {"ok": true, "has_scene": false}
	return {
		"ok": true,
		"has_scene": true,
		"scene_path": root.scene_file_path,
		"root_name": root.name,
	}


func handle_get_open_scenes(_args: Dictionary) -> Dictionary:
	var ei := _editor_interface()
	if ei == null:
		return {"ok": false, "error": "editor interface unavailable"}
	var scenes := ei.get_open_scenes()
	# Añadir escenas del registry que NO están en pestañas (creadas por MCP):
	# así el agente ve TODO lo que existe, no solo pestañas del editor.
	for scene_path in HerenSceneRegistryScript.all().keys():
		if scene_path not in scenes:
			scenes.append(scene_path)
	return {"ok": true, "open_scenes": scenes}


func handle_create(args: Dictionary) -> Dictionary:
	var ei := _editor_interface()
	if ei == null:
		return {"ok": false, "error": "editor interface unavailable"}

	var root_type: String = str(args.get("root_type", "Node2D"))
	var root_name: String = str(args.get("root_name", "NewNode"))
	var scene_path: String = _normalize_scene_path(str(args.get("scene_path", "")))

	# Instantiate the root node.
	var new_node: Node = ClassDB.instantiate(root_type)
	if new_node == null:
		return {"ok": false, "error": "unknown root_type: " + root_type}
	new_node.name = root_name

	# scene_path explícito → SIEMPRE crear archivo nuevo (independiente de la
	# pestaña activa). El path es el destino del archivo, no la escena activa.
	if scene_path != "":
		if ResourceLoader.exists(scene_path):
			new_node.free()
			return {"ok": false, "error": "scene_exists: " + scene_path}
		return _create_scene_file(ei, new_node, scene_path, root_type, root_name)

	# Sin scene_path: si hay escena abierta, inyectar el nodo (v3 behavior).
	var scene_root := ei.get_edited_scene_root()
	if scene_root != null:
		_undo_redo.begin_action("Heren Create Node: %s" % root_name)
		_undo_redo.add_do_method(scene_root, &"add_child", [new_node])
		_undo_redo.add_do_property(new_node, &"owner", scene_root)
		_undo_redo.add_undo_method(scene_root, &"remove_child", [new_node])
		_undo_redo.commit_action()
		return {
			"ok": true,
			"node_name": root_name,
			"node_type": root_type,
			"parent_path": ".",
		}

	# No scene open: create a brand-new scene file and open it in the editor.
	var packed := PackedScene.new()
	HerenCoordsScript.ensure_owner_recursive(new_node)
	packed.pack(new_node)
	scene_path = "res://%s.tscn" % root_name
	if ResourceLoader.exists(scene_path):
		new_node.free()
		return {"ok": false, "error": "scene_exists: " + scene_path}
	return _create_scene_file(ei, new_node, scene_path, root_type, root_name)


func _create_scene_file(ei: EditorInterface, new_node: Node, scene_path: String,
		root_type: String, root_name: String) -> Dictionary:
	# Asegurar directorio padre (misma carencia que shader/resource).
	_ensure_parent_dir(scene_path)
	var packed := PackedScene.new()
	HerenCoordsScript.ensure_owner_recursive(new_node)
	packed.pack(new_node)
	# 🚨 SIN FLAG_BUNDLE_RESOURCES: esa flag INCORPORA los recursos externos
	# (scripts .gd con resource_path) dentro del .tscn como sub_resource —
	# el bug "save embebe scripts". Los recursos inline sin path se guardan
	# vía resource_local_to_scene (ensure_resource_local_recursive).
	var err := ResourceSaver.save(packed, scene_path)
	if err != OK:
		new_node.free()
		return {"ok": false, "error": "save_failed: " + error_string(err)}

	var efs: EditorFileSystem = ei.get_resource_filesystem()
	if efs:
		efs.update_file(scene_path)

	# Registrar en memoria SIEMPRE (fuente de verdad del flujo MCP). Prioridad:
	# pestaña real del editor (si abre) → árbol en memoria vivo (fallback).
	var opened := ei.get_edited_scene_root()
	var got_tab := opened != null and opened.scene_file_path == scene_path
	if not got_tab:
		ei.open_scene_from_path(scene_path)
		opened = ei.get_edited_scene_root()
		got_tab = opened != null and opened.scene_file_path == scene_path
	if got_tab:
		new_node.free()
		HerenSceneRegistryScript.register(scene_path, opened)
	else:
		# open_scene_from_path falló (silencioso): mantener nuestro árbol VIVO
		# en el registry para que node/save operen contra él igualmente.
		new_node.scene_file_path = scene_path
		HerenSceneRegistryScript.register(scene_path, new_node)

	return {
		"ok": true,
		"created": scene_path,
		"root_name": root_name,
		"root_type": root_type,
		"registered": true,
	}


## Save SIEMPRE por pack directo del root objetivo → ResourceSaver. NUNCA
## ei.save_scene() (guarda la pestaña activa, no la escena pedida).
func handle_save(args: Dictionary) -> Dictionary:
	var ei := _editor_interface()
	if ei == null:
		return {"ok": false, "error": "editor interface unavailable"}

	var scene_path: String = str(args.get("scene_path", ""))
	if scene_path == "":
		scene_path = str(args.get("output_path", ""))
	var root: Node = null
	# Rediseño 2026-08-15: true si sync_from_disk recargó desde disco y
	# re-aplicó ops (en ese caso, los replay_skipped SÍ son reales).
	var synced_root_had_sync := false

	# 1) scene_path explícito → MISMA prioridad que resolve_root:
	#    PESTAÑA REAL primero (lo que el usuario ve y edita — incluidas las
	#    mutaciones de set_prop), luego registry, luego disco.
	#    🚨 Si diéramos prioridad al registry, handle_save guardaría la copia
	#    stale (ej: script embebido) en vez de la pestaña real con ext_resource.
	if scene_path != "":
		# Rediseño 2026-08-15: SYNC ANTES de guardar. Si el disco cambió
		# (hand-edit del usuario), recargamos desde disco y re-aplicamos las
		# ops pendientes del agente (replay) — NUNCA machacamos el disco con
		# una copia stale. sync_from_disk devuelve el root fresco si hubo sync.
		var synced := HerenSceneRegistryScript.sync_from_disk(ei, scene_path)
		if synced != null:
			root = synced
			synced_root_had_sync = true
		else:
			var active := ei.get_edited_scene_root()
			if active != null and active.scene_file_path == scene_path:
				root = active
			else:
				root = HerenSceneRegistryScript.get_root(scene_path)
				if root == null and ResourceLoader.exists(scene_path):
					ei.open_scene_from_path(scene_path)
					root = ei.get_edited_scene_root()

	# 2) Sin scene_path → pestaña activa (usa su propio scene_file_path).
	if root == null:
		root = ei.get_edited_scene_root()
		if root != null:
			scene_path = root.scene_file_path

	if root == null:
		return {"ok": false, "error": "no scene to save"}
	if scene_path == "":
		return {"ok": false, "error": "scene has no scene_file_path; pass scene_path"}

	# 3) Pack directo + owners garantizados + disco.
	#    🚨 SIN FLAG_BUNDLE_RESOURCES: esa flag INCORPORA los recursos externos
	#    (scripts .gd con resource_path) dentro del .tscn como sub_resource —
	#    el bug "save embebe scripts". Los recursos inline SIN path se guardan
	#    vía resource_local_to_scene (ensure_resource_local_recursive).
	_ensure_parent_dir(scene_path)
	HerenCoordsScript.ensure_owner_recursive(root)
	var packed := PackedScene.new()
	packed.pack(root)
	var err := ResourceSaver.save(packed, scene_path)
	if err != OK:
		return {"ok": false, "error": "save_failed: " + error_string(err)}

	var efs: EditorFileSystem = ei.get_resource_filesystem()
	if efs:
		efs.update_file(scene_path)
	# BUG 2 fix: actualizar mtime registrado después de guardar.
	HerenSceneRegistryScript.update_mtime(scene_path)
	# Rediseño 2026-08-15: tras guardar exitoso, limpiar ops pendientes.
	# SOLO reportamos replay_skipped si hubo sync real con el disco y alguna
	# op no se pudo re-aplicar. Si NO hubo divergencia (sync devolvió null),
	# el árbol guardado ya incluye las ops → limpiar silenciosamente.
	# 🚨 FIX 2026-08-15: sin esta guarda, un save normal reportaba
	# `replay_skipped` falso (la op sí estaba en el árbol guardado).
	var skipped: Array = []
	if synced_root_had_sync:
		skipped = HerenSceneRegistryScript.get_pending_ops(scene_path)
	HerenSceneRegistryScript.clear_ops(scene_path)
	var result := {"ok": true, "saved": true, "saved_to": scene_path}
	if skipped.size() > 0:
		result["replay_skipped"] = skipped
		result["note"] = "algunas ops del agente no se re-aplicaron tras sync con disco — re-hacerlas manualmente"
	return result


func handle_open(args: Dictionary) -> Dictionary:
	var ei := _editor_interface()
	if ei == null:
		return {"ok": false, "error": "editor interface unavailable"}
	var scene_path: String = str(args.get("scene_path", ""))
	if scene_path == "":
		return {"ok": false, "error": "scene_path required"}
	ei.open_scene_from_path(scene_path)
	# Re-registrar el árbol de la pestaña (puede diferir del guardado en disco).
	var opened := ei.get_edited_scene_root()
	if opened != null and opened.scene_file_path == scene_path:
		HerenSceneRegistryScript.register(scene_path, opened)
	return {"ok": true, "opened": scene_path}


## BUG 4 fix: unload cierra la escena del registry y del editor.
## Permite forzar recarga del disco tras ediciones manuales.
func handle_unload(args: Dictionary) -> Dictionary:
	var ei := _editor_interface()
	if ei == null:
		return {"ok": false, "error": "editor interface unavailable"}
	var scene_path: String = str(args.get("scene_path", ""))
	if scene_path == "":
		return {"ok": false, "error": "scene_path required"}
	# Quitar del registry.
	HerenSceneRegistryScript.unregister(scene_path)
	# Cerrar la pestaña del editor si está abierta.
	var open_scenes := ei.get_open_scenes()
	if scene_path in open_scenes:
		# Godot no tiene API pública para cerrar pestaña directamente.
		# El usuario puede cerrar manualmente o usar scene/open en otra escena.
		pass
	return {"ok": true, "unloaded": scene_path}


func _editor_interface() -> EditorInterface:
	if _editor_plugin == null:
		print("[HEREN] _editor_plugin is NULL in handler")
		return null
	var ei: EditorInterface = _editor_plugin.get_editor_interface()
	if ei == null:
		print("[HEREN] get_editor_interface() returned NULL")
	return ei


func _ensure_parent_dir(path: String) -> void:
	var dir_path := path.get_base_dir()
	if dir_path != "" and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir_path)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))


## Normaliza un scene_path a la forma canónica de Godot (res://, forward
## slashes, sin trailing). El server ya normaliza; esta es defensa en el
## plugin para que la key del SceneRegistry SIEMPRE coincida con el
## scene_file_path de la pestaña (fix 2026-08-06: paths crudos del agente
## rompían el match → escena fantasma divergente).
func _normalize_scene_path(path: String) -> String:
	var s := path.strip_edges()
	if s == "":
		return ""
	s = s.replace("\\", "/")
	while s.ends_with("/"):
		s = s.substr(0, s.length() - 1)
	if s.begins_with("res:/") and not s.begins_with("res://"):
		return "res://" + s.substr(5)
	if not s.begins_with("res://"):
		return "res://" + s
	return s
