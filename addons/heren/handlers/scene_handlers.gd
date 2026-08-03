@tool
extends Node

# Heren MCP v4 - Scene handlers (Fase 1).
# Handles: health, project_info, get_edited_scene_root, get_open_scenes,
# create, save, open. All mutations go through the UndoRedo wrapper
# (EditorUndoRedoManager) so Ctrl+Z undoes them (ADR-002 advantage).

var _editor_plugin: EditorPlugin
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
	return {"ok": true, "open_scenes": scenes}


func handle_create(args: Dictionary) -> Dictionary:
	var ei := _editor_interface()
	if ei == null:
		return {"ok": false, "error": "editor interface unavailable"}
	var scene_root := ei.get_edited_scene_root()
	if scene_root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var root_type: String = str(args.get("root_type", "Node2D"))
	var root_name: String = str(args.get("root_name", "NewNode"))

	# Instantiate the new node and register undo/redo.
	var new_node: Node = ClassDB.instantiate(root_type)
	if new_node == null:
		return {"ok": false, "error": "unknown root_type: " + root_type}
	new_node.name = root_name

	var parent_path: NodePath = NodePath(str(args.get("parent_path", "")))
	var parent: Node = scene_root
	if parent_path != NodePath("") and scene_root.has_node(parent_path):
		parent = scene_root.get_node(parent_path)

	_undo_redo.begin_action("Heren Create Node: %s" % root_name)
	_undo_redo.add_do_method(parent, "add_child", [new_node])
	_undo_redo.add_undo_method(parent, "remove_child", [new_node])
	_undo_redo.commit_action()

	return {
		"ok": true,
		"node_name": root_name,
		"node_type": root_type,
		"parent_path": str(parent.get_path()),
	}


func handle_save(args: Dictionary) -> Dictionary:
	var ei := _editor_interface()
	if ei == null:
		return {"ok": false, "error": "editor interface unavailable"}
	var root := ei.get_edited_scene_root()
	if root == null:
		return {"ok": false, "error": "no scene to save"}
	var err := ei.save_scene()
	if err != OK:
		return {"ok": false, "error": "save failed: %d" % err}
	return {"ok": true, "saved": true}


func handle_open(args: Dictionary) -> Dictionary:
	var ei := _editor_interface()
	if ei == null:
		return {"ok": false, "error": "editor interface unavailable"}
	var scene_path: String = str(args.get("scene_path", ""))
	if scene_path == "":
		return {"ok": false, "error": "scene_path required"}
	ei.open_scene_from_path(scene_path)
	return {"ok": true, "opened": scene_path}


func _editor_interface() -> EditorInterface:
	if _editor_plugin == null:
		print("[HEREN] _editor_plugin is NULL in handler")
		return null
	var ei: EditorInterface = _editor_plugin.get_editor_interface()
	if ei == null:
		print("[HEREN] get_editor_interface() returned NULL")
	return ei
