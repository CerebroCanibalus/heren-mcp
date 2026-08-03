@tool
extends Node

# Heren MCP v4 - Debug handlers (Fase 2).
# Control del editor real (ADR-002): play/stop de escenas con la API del
# EditorInterface, en vez de subprocess godot --headless de v3.
#
# Actions (heredadas de v3 debug_tool.py, adaptadas a editor vivo):
#   run_scene        -> EditorInterface.play_main_scene / play_custom_scene
#   stop_scene       -> EditorInterface.stop_playing_scene
#   is_playing       -> EditorInterface.is_playing_scene
#   get_editor_errors-> parsear output del editor (logueado por el plugin)
#
# NO portado de v3: breakpoint/stack_trace/watch/console (dependían del
# debugger subprocess de v3; con editor real el breakpoint se pone en el
# editor manualmente), execute_editor_script/check_script_syntax (obsoletos,
# el plugin ES el editor).

var _editor_plugin: EditorPlugin


func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin


func _editor_interface() -> EditorInterface:
	if _editor_plugin == null:
		return null
	return _editor_plugin.get_editor_interface()


# ---------------------------------------------------------------- handlers

func handle_run_scene(args: Dictionary) -> Dictionary:
	var ei := _editor_interface()
	if ei == null:
		return {"ok": false, "error": "no editor interface"}

	var scene_path: String = str(args.get("scene_path", ""))
	if scene_path != "":
		if not ResourceLoader.exists(scene_path):
			return {"ok": false, "error": "scene_not_found: " + scene_path}
		ei.play_custom_scene(scene_path)
		return {"ok": true, "running": scene_path, "custom": true}

	ei.play_main_scene()
	return {"ok": true, "running": "main_scene", "custom": false}


func handle_stop_scene(args: Dictionary) -> Dictionary:
	var ei := _editor_interface()
	if ei == null:
		return {"ok": false, "error": "no editor interface"}
	if not ei.is_playing_scene():
		return {"ok": true, "was_playing": false}
	ei.stop_playing_scene()
	return {"ok": true, "was_playing": true}


func handle_is_playing(args: Dictionary) -> Dictionary:
	var ei := _editor_interface()
	if ei == null:
		return {"ok": false, "error": "no editor interface"}
	return {"ok": true, "is_playing": ei.is_playing_scene()}


func handle_get_editor_errors(args: Dictionary) -> Dictionary:
	# El editor no expone un buffer de errores estable via API pública en 4.x;
	# el plugin loguea sus propios errores y los reporta aquí. Los errores del
	# editor real se ven en el panel Output (no accesible por script).
	return {
		"ok": true,
		"note": "editor errors not exposed via public API; see Output panel",
		"plugin_errors": [],
	}
