@tool
extends Node

# Heren MCP v4 - Project handlers (Fase 2).
# Configuración del proyecto vía ProjectSettings + InputMap (ADR-002):
# el editor vivo aplica y persiste los cambios en project.godot.
#
# Actions (heredadas de v3 project_tool.py, adaptadas a editor vivo):
#   setting      -> get/set ProjectSettings (persiste con ProjectSettings.save)
#   autoload     -> add (script_path) / list / remove_autoload
#   input_map    -> add/remove/list/set_event (InputEvent desde JSON)
#   shader_global-> RenderingServer.global_shader_parameter (runtime)
#
# NO portado de v3: create (crear proyecto desde 0), setup_daemon (obsoleto —
# v4 es EditorPlugin, no daemon; el plugin viaja con el proyecto).

const HerenCoordsScript := preload("coords.gd")

var _editor_plugin: EditorPlugin


func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin


func _editor_interface() -> EditorInterface:
	if _editor_plugin == null:
		return null
	return _editor_plugin.get_editor_interface()


## Accepts a Dictionary directly, or a JSON string.
func _args_dict(args: Dictionary, key: String) -> Dictionary:
	var raw: Variant = args.get(key, {})
	if raw is Dictionary:
		return raw
	if raw is String:
		var parsed: Variant = JSON.parse_string(raw)
		if parsed is Dictionary:
			return parsed
	return {}


func _serialize_setting(value: Variant) -> Variant:
	if value is Array:
		var out: Array = []
		for item in value:
			out.append(_serialize_setting(item))
		return out
	if value is Dictionary:
		var out := {}
		for k in value.keys():
			out[k] = _serialize_setting(value[k])
		return out
	return HerenCoordsScript.serialize_value(value)


# ---------------------------------------------------------------- handlers

func handle_setting(args: Dictionary) -> Dictionary:
	var setting_name: String = str(args.get("setting_name", ""))
	if setting_name == "":
		return {"ok": false, "error": "setting_name required"}

	if args.has("value"):
		var value: Variant = HerenCoordsScript.deserialize_value(args.get("value"))
		ProjectSettings.set_setting(setting_name, value)
		var err := ProjectSettings.save()
		if err != OK:
			return {"ok": false, "error": "save_failed: " + error_string(err)}
		return {"ok": true, "setting": setting_name, "value": _serialize_setting(ProjectSettings.get_setting(setting_name)), "op": "set"}

	if not ProjectSettings.has_setting(setting_name):
		return {"ok": false, "error": "setting_not_found: " + setting_name}
	return {
		"ok": true,
		"setting": setting_name,
		"value": _serialize_setting(ProjectSettings.get_setting(setting_name)),
		"op": "get",
	}


func handle_autoload(args: Dictionary) -> Dictionary:
	var autoload_name: String = str(args.get("autoload_name", ""))
	var script_path: String = str(args.get("script_path", ""))

	# No name -> list all autoloads (via property_list; get_autoload_list
	# is unreliable through the parser in some 4.x builds).
	if autoload_name == "":
		var out: Array = []
		for prop in ProjectSettings.get_property_list():
			var prop_name: StringName = prop.name
			if not str(prop_name).begins_with("autoload/"):
				continue
			var value: Variant = ProjectSettings.get_setting(prop_name)
			if value == null or str(value) == "":
				continue
			out.append({
				"name": str(prop_name).trim_prefix("autoload/"),
				"path": str(value),
			})
		return {"ok": true, "autoloads": out, "count": out.size()}

	if script_path == "":
		return {"ok": false, "error": "script_path required"}

	ProjectSettings.set_setting("autoload/" + autoload_name, "*" + script_path)
	var err := ProjectSettings.save()
	if err != OK:
		return {"ok": false, "error": "save_failed: " + error_string(err)}
	return {"ok": true, "autoload": autoload_name, "path": script_path}


func handle_remove_autoload(args: Dictionary) -> Dictionary:
	var autoload_name: String = str(args.get("autoload_name", ""))
	if autoload_name == "":
		return {"ok": false, "error": "autoload_name required"}

	ProjectSettings.set_setting("autoload/" + autoload_name, null)
	var err := ProjectSettings.save()
	if err != OK:
		return {"ok": false, "error": "save_failed: " + error_string(err)}
	return {"ok": true, "removed": autoload_name}


func handle_input_map(args: Dictionary) -> Dictionary:
	var action_type: String = str(args.get("type", "list"))
	var action_name: String = str(args.get("action_name", ""))

	match action_type:
		"add":
			if action_name == "":
				return {"ok": false, "error": "action_name required"}
			if InputMap.has_action(action_name):
				return {"ok": true, "action": action_name, "op": "exists"}
			InputMap.add_action(action_name)
			ProjectSettings.save()
			return {"ok": true, "action": action_name, "op": "added"}

		"remove":
			if action_name == "":
				return {"ok": false, "error": "action_name required"}
			if not InputMap.has_action(action_name):
				return {"ok": false, "error": "action_not_found: " + action_name}
			InputMap.erase_action(action_name)
			ProjectSettings.save()
			return {"ok": true, "action": action_name, "op": "removed"}

		"list":
			var out: Array = []
			for action in InputMap.get_actions():
				if action.begins_with("ui_"):
					continue
				var events: Array[InputEvent] = InputMap.action_get_events(action)
				var event_list: Array = []
				for ev in events:
					event_list.append({"type": ev.get_class(), "as_text": ev.as_text()})
				out.append({"name": action, "event_count": events.size(), "events": event_list})
			return {"ok": true, "actions": out, "count": out.size()}

		"set_event":
			if action_name == "":
				return {"ok": false, "error": "action_name required"}
			var event_data := _args_dict(args, "event")
			var ev: Variant = _create_input_event(event_data)
			if not ev is InputEvent:
				return {"ok": false, "error": "unsupported_input_event: " + str(event_data.get("type", ""))}
			if not InputMap.has_action(action_name):
				InputMap.add_action(action_name)
			InputMap.action_erase_events(action_name)
			InputMap.action_add_event(action_name, ev)
			ProjectSettings.save()
			return {"ok": true, "action": action_name, "event": (ev as InputEvent).as_text()}

	return {"ok": false, "error": "unknown_type: " + action_type}


func handle_shader_global(args: Dictionary) -> Dictionary:
	var global_name: String = str(args.get("global_name", ""))
	if global_name == "":
		return {"ok": false, "error": "global_name required"}

	var value: Variant = HerenCoordsScript.deserialize_value(args.get("value", 0.0))
	# Runtime only (RenderingServer); does not persist to project.godot.
	if RenderingServer.global_shader_parameter_get(global_name) == null:
		RenderingServer.global_shader_parameter_add(global_name, RenderingServer.GLOBAL_VAR_TYPE_FLOAT, value)
	else:
		RenderingServer.global_shader_parameter_set(global_name, value)

	return {"ok": true, "global": global_name, "value": HerenCoordsScript.serialize_value(value), "runtime_only": true}


func _create_input_event(data: Dictionary) -> Variant:
	var type_name: String = str(data.get("type", "InputEventKey"))
	match type_name:
		"InputEventKey":
			var ev := InputEventKey.new()
			ev.keycode = int(data.get("keycode", 0))
			ev.physical_keycode = int(data.get("physical_keycode", 0))
			ev.ctrl_pressed = bool(data.get("ctrl", false))
			ev.shift_pressed = bool(data.get("shift", false))
			ev.alt_pressed = bool(data.get("alt", false))
			return ev
		"InputEventMouseButton":
			var ev := InputEventMouseButton.new()
			ev.button_index = int(data.get("button_index", MOUSE_BUTTON_LEFT))
			ev.ctrl_pressed = bool(data.get("ctrl", false))
			ev.shift_pressed = bool(data.get("shift", false))
			return ev
		"InputEventJoypadButton":
			var ev := InputEventJoypadButton.new()
			ev.button_index = int(data.get("button_index", 0))
			ev.device = int(data.get("device", 0))
			return ev
	return null
