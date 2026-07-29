class_name HerenProjectOps

var _daemon: SceneTree = null

func init(daemon: SceneTree) -> void:
	_daemon = daemon


func _value_to_godot_config(value) -> String:
	"""Convierte un valor GDScript a su representación en project.godot."""
	if value == null:
		return "null"
	if value is bool:
		return "true" if value else "false"
	if value is int:
		return str(value)
	if value is float:
		return str(value)
	if value is String or value is StringName:
		return '"' + str(value).replace('"', '\\"') + '"'
	if value is Vector2:
		return "Vector2(" + str(value.x) + ", " + str(value.y) + ")"
	if value is Vector2i:
		return "Vector2i(" + str(value.x) + ", " + str(value.y) + ")"
	if value is Vector3:
		return "Vector3(" + str(value.x) + ", " + str(value.y) + ", " + str(value.z) + ")"
	if value is Vector3i:
		return "Vector3i(" + str(value.x) + ", " + str(value.y) + ", " + str(value.z) + ")"
	if value is Color:
		return "Color(" + str(value.r) + ", " + str(value.g) + ", " + str(value.b) + ", " + str(value.a) + ")"
	if value is Array or value is PackedStringArray:
		var items = []
		for item in value:
			items.append(_value_to_godot_config(item))
		return "PackedStringArray(" + ", ".join(items) + ")" if value is PackedStringArray else "[" + ", ".join(items) + "]"
	# Fallback
	return '"' + str(value).replace('"', '\\"') + '"'


# ============================================================
# PROJECT HANDLERS
# Extracted from heren_daemon.gd
# ============================================================

func handle_set_project_setting(params: Dictionary) -> Dictionary:
	var setting_name = params.get("setting_name", "")
	var value = params.get("value", null)
	
	if not setting_name:
		return {"success": false, "error": "missing_setting_name"}
	
	# Edición quirúrgica del project.godot sin sobrescribir todo
	var project_file = _daemon._project_path + "/project.godot"
	if not FileAccess.file_exists(project_file):
		return {"success": false, "error": "project_not_found", "path": project_file}
	
	# Leer archivo existente
	var file = FileAccess.open(project_file, FileAccess.READ)
	if not file:
		return {"success": false, "error": "cannot_read_project"}
	
	var content = file.get_as_text()
	file.close()
	
	# Parsear setting_name (formato: "section/key")
	var parts = setting_name.split("/")
	if parts.size() < 2:
		return {"success": false, "error": "invalid_setting_format", "expected": "section/key"}
	
	var section = parts[0]
	var key = parts[1]
	var deserialized = _daemon._core_utils.deserialize_value(value)
	var value_str = _value_to_godot_config(deserialized)
	
	# Verificar si la sección existe
	var section_pattern = "[" + section + "]"
	var section_pos = content.find(section_pattern)
	
	if section_pos == -1:
		# Sección no existe, añadir al final
		content += "\n" + section_pattern + "\n" + key + "=" + value_str + "\n"
	else:
		# Sección existe, buscar la key
		var next_section = content.find("[", section_pos + 1)
		var section_end = next_section if next_section != -1 else content.length()
		var section_content = content.substr(section_pos, section_end - section_pos)
		
		var key_pattern = key + "="
		var key_pos = section_content.find(key_pattern)
		
		if key_pos != -1:
			# Key existe, reemplazar
			var line_start = section_content.rfind("\n", key_pos) + 1
			var line_end = section_content.find("\n", key_pos)
			if line_end == -1:
				line_end = section_content.length()
			
			var before = content.substr(0, section_pos + line_start)
			var after = content.substr(section_pos + line_end)
			content = before + key + "=" + value_str + after
		else:
			# Key no existe, añadir al final de la sección
			var insert_pos = section_end
			content = content.substr(0, insert_pos) + key + "=" + value_str + "\n" + content.substr(insert_pos)
	
	# Guardar
	file = FileAccess.open(project_file, FileAccess.WRITE)
	if not file:
		return {"success": false, "error": "cannot_write_project"}
	file.store_string(content)
	file.close()
	
	# También actualizar en memoria para consistencia
	ProjectSettings.set_setting(setting_name, deserialized)
	
	return {
		"success": true,
		"setting": setting_name,
		"value": str(deserialized)
	}


func handle_get_project_setting(params: Dictionary) -> Dictionary:
	var setting_name = params.get("setting_name", "")
	
	if not setting_name:
		return {"success": false, "error": "missing_setting_name"}
	
	if not ProjectSettings.has_setting(setting_name):
		return {"success": false, "error": "setting_not_found"}
	
	var value = ProjectSettings.get_setting(setting_name)
	
	return {
		"success": true,
		"setting": setting_name,
		"value": _daemon._core_utils.serialize_value(value),
		"has_setting": true
	}


func handle_add_autoload(params: Dictionary) -> Dictionary:
	var autoload_name = params.get("autoload_name", "")
	var script_path = params.get("script_path", "")
	
	if not autoload_name or not script_path:
		return {"success": false, "error": "missing_params"}
	
	var result = _daemon._edit_project_godot("autoload", autoload_name, "*" + script_path)
	if not result.success:
		return result
	
	ProjectSettings.set_setting("autoload/" + autoload_name, "*" + script_path)
	
	return {
		"success": true,
		"autoload": autoload_name,
		"path": script_path
	}


func handle_remove_autoload(params: Dictionary) -> Dictionary:
	var autoload_name = params.get("autoload_name", "")
	
	if not autoload_name:
		return {"success": false, "error": "missing_autoload_name"}
	
	var result = _daemon._edit_project_godot("autoload", autoload_name, "", true)
	if not result.success:
		return result
	
	ProjectSettings.set_setting("autoload/" + autoload_name, null)
	
	return {"success": true, "removed": autoload_name}


func handle_set_shader_global(params: Dictionary) -> Dictionary:
	var global_name = params.get("global_name", "")
	var value = params.get("value", null)
	
	if not global_name:
		return {"success": false, "error": "missing_global_name"}
	
	var deserialized = _daemon._core_utils.deserialize_value(value)
	RenderingServer.global_shader_parameter_add(global_name, RenderingServer.GLOBAL_VAR_TYPE_FLOAT, deserialized)
	
	return {
		"success": true,
		"global": global_name,
		"value": str(deserialized)
	}


# ============================================================
# TILEMAP HANDLERS
# Extracted from heren_daemon.gd
# ============================================================

func handle_inspect_tileset(params: Dictionary) -> Dictionary:
	var tileset_path = params.get("tileset_path", "")
	
	if not tileset_path:
		return {"success": false, "error": "missing_tileset_path"}
	
	if not ResourceLoader.exists(tileset_path):
		return {"success": false, "error": "tileset_not_found"}
	
	var tileset = load(tileset_path)
	if not tileset or not tileset is TileSet:
		return {"success": false, "error": "invalid_tileset"}
	
	var sources = []
	for i in range(tileset.get_source_count()):
		var source_id = tileset.get_source_id(i)
		var source = tileset.get_source(source_id)
		var source_info = {
			"id": source_id,
			"type": source.get_class(),
		}
		
		if source is TileSetAtlasSource:
			var atlas = source as TileSetAtlasSource
			source_info["texture"] = atlas.texture.resource_path if atlas.texture else ""
			source_info["margins"] = {"x": atlas.margins.x, "y": atlas.margins.y}
			source_info["separation"] = {"x": atlas.separation.x, "y": atlas.separation.y}
			source_info["texture_region_size"] = {"x": atlas.texture_region_size.x, "y": atlas.texture_region_size.y}
			
			if atlas.texture:
				var tex_size = atlas.texture.get_size()
				var cols = 0
				var rows = 0
				if atlas.texture_region_size.x > 0 and atlas.texture_region_size.y > 0:
					cols = int((tex_size.x - atlas.margins.x + atlas.separation.x) / (atlas.texture_region_size.x + atlas.separation.x))
					rows = int((tex_size.y - atlas.margins.y + atlas.separation.y) / (atlas.texture_region_size.y + atlas.separation.y))
				source_info["grid"] = {"cols": cols, "rows": rows}
		
		sources.append(source_info)
	
	return {
		"success": true,
		"tileset_path": tileset_path,
		"source_count": tileset.get_source_count(),
		"sources": sources
	}


func handle_inspect_tilemap(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var tilemap_path = params.get("tilemap_path", "")
	
	if not scene_path or not tilemap_path:
		return {"success": false, "error": "missing_params"}
	
	if not _daemon._scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _daemon._scene_cache[scene_path]
	var tilemap = root.get_node_or_null(tilemap_path)
	
	if not tilemap or not tilemap is TileMap:
		return {"success": false, "error": "tilemap_not_found"}
	
	var layers = []
	for i in range(tilemap.get_layers_count()):
		layers.append({
			"index": i,
			"name": tilemap.get_layer_name(i),
			"enabled": tilemap.is_layer_enabled(i),
			"modulate": {
				"r": tilemap.get_layer_modulate(i).r,
				"g": tilemap.get_layer_modulate(i).g,
				"b": tilemap.get_layer_modulate(i).b,
				"a": tilemap.get_layer_modulate(i).a
			}
		})
	
	# Get used cells from first layer
	var used_cells = []
	if tilemap.get_layers_count() > 0:
		var cells = tilemap.get_used_cells(0)
		for cell in cells:
			var atlas_coords = tilemap.get_cell_atlas_coords(0, cell)
			used_cells.append({
				"x": cell.x,
				"y": cell.y,
				"atlas_x": atlas_coords.x,
				"atlas_y": atlas_coords.y
			})
	
	return {
		"success": true,
		"tilemap_path": tilemap_path,
		"layers_count": tilemap.get_layers_count(),
		"layers": layers,
		"used_cells_count": used_cells.size(),
		"used_cells": used_cells
	}


func handle_set_tilemap_cell(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var tilemap_path = params.get("tilemap_path", "")
	var layer = params.get("layer", 0)
	var coords = params.get("coords", {})
	var atlas_coords = params.get("atlas_coords", {})
	var source_id = params.get("source_id", 0)
	var alternative_tile = params.get("alternative_tile", 0)
	
	if not scene_path or not tilemap_path:
		return {"success": false, "error": "missing_params"}
	
	if not _daemon._scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _daemon._scene_cache[scene_path]
	var tilemap = root.get_node_or_null(tilemap_path)
	
	if not tilemap or not tilemap is TileMap:
		return {"success": false, "error": "tilemap_not_found"}
	
	var pos = Vector2i(coords.get("x", 0), coords.get("y", 0))
	var atlas = Vector2i(atlas_coords.get("x", 0), atlas_coords.get("y", 0))
	
	tilemap.set_cell(layer, pos, source_id, atlas, alternative_tile)
	
	return {
		"success": true,
		"tilemap": tilemap_path,
		"position": {"x": pos.x, "y": pos.y},
		"atlas": {"x": atlas.x, "y": atlas.y}
	}


func handle_apply_terrain(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var tilemap_path = params.get("tilemap_path", "")
	var layer = params.get("layer", 0)
	var cells = params.get("cells", [])
	var terrain_set = params.get("terrain_set", 0)
	var terrain = params.get("terrain", 0)
	
	if not scene_path or not tilemap_path:
		return {"success": false, "error": "missing_params"}
	
	if not _daemon._scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _daemon._scene_cache[scene_path]
	var tilemap = root.get_node_or_null(tilemap_path)
	
	if not tilemap or not tilemap is TileMap:
		return {"success": false, "error": "tilemap_not_found"}
	
	var count = 0
	for cell_data in cells:
		var pos = Vector2i(cell_data.get("x", 0), cell_data.get("y", 0))
		tilemap.set_cells_terrain_connect(layer, [pos], terrain_set, terrain, true)
		count += 1
	
	return {
		"success": true,
		"applied": count,
		"terrain_set": terrain_set,
		"terrain": terrain
	}


func handle_create_tile_pattern(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var tilemap_path = params.get("tilemap_path", "")
	var layer = params.get("layer", 0)
	var region = params.get("region", {})
	var pattern_name = params.get("pattern_name", "Pattern")
	
	if not scene_path or not tilemap_path:
		return {"success": false, "error": "missing_params"}
	
	if not _daemon._scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _daemon._scene_cache[scene_path]
	var tilemap = root.get_node_or_null(tilemap_path)
	
	if not tilemap or not tilemap is TileMap:
		return {"success": false, "error": "tilemap_not_found"}
	
	var start = Vector2i(region.get("x", 0), region.get("y", 0))
	var size = Vector2i(region.get("w", 1), region.get("h", 1))
	var pattern = tilemap.get_pattern(layer, [start, start + size - Vector2i(1, 1)])
	
	if pattern:
		tilemap.tile_set.add_pattern(pattern, -1)
		return {
			"success": true,
			"pattern_id": tilemap.tile_set.get_patterns_count() - 1,
			"size": {"w": size.x, "h": size.y}
		}
	
	return {"success": false, "error": "pattern_creation_failed"}


# ============================================================
# INPUT MAP HANDLERS
# ============================================================

func handle_input_map(params: Dictionary) -> Dictionary:
	"""Gestiona el input map del proyecto via ProjectSettings API.
	type: add|remove|list|set_event
	"""
	var action_type = params.get("type", "list")
	var action_name = params.get("action_name", "")
	var event_data = params.get("event", {})
	
	match action_type:
		"add":
			if not action_name:
				return {"success": false, "error": "action_name es requerido"}
			if InputMap.has_action(action_name):
				return {"success": true, "warning": "La accion ya existe", "action": action_name}
			InputMap.add_action(action_name)
			ProjectSettings.save()
			return {"success": true, "action": action_name, "op": "added"}
		
		"remove":
			if not action_name:
				return {"success": false, "error": "action_name es requerido"}
			if not InputMap.has_action(action_name):
				return {"success": false, "error": "Accion no encontrada", "action": action_name}
			InputMap.erase_action(action_name)
			ProjectSettings.save()
			return {"success": true, "action": action_name, "op": "removed"}
		
		"list":
			var actions = []
			for action in InputMap.get_actions():
				if action.begins_with("ui_"):
					continue  # Saltar built-ins del editor
				var events = InputMap.action_get_events(action)
				var event_list = []
				for ev in events:
					event_list.append({
						"type": ev.get_class(),
						"device": ev.device if ev.has_method("get_device") else 0,
						"as_text": ev.as_text() if ev.has_method("as_text") else str(ev)
					})
				actions.append({
					"name": action,
					"event_count": events.size(),
					"events": event_list
				})
			return {"success": true, "actions": actions, "count": actions.size()}
		
		"set_event":
			if not action_name:
				return {"success": false, "error": "action_name es requerido"}
			if not InputMap.has_action(action_name):
				InputMap.add_action(action_name)
			# Crear InputEvent desde data
			var ev = _create_input_event_from_data(event_data)
			if ev is Dictionary:
				return ev  # Error
			InputMap.action_erase_events(action_name)
			InputMap.action_add_event(action_name, ev)
			ProjectSettings.save()
			return {"success": true, "action": action_name, "event": ev.as_text() if ev.has_method("as_text") else str(ev)}
	
	return {"success": false, "error": "Tipo desconocido: " + action_type}


func _create_input_event_from_data(data: Dictionary) -> Variant:
	"""Crea un InputEvent a partir de un dict Python/JSON.
	Soporta InputEventKey, InputEventMouseButton, InputEventJoypadButton.
	"""
	var type_name = data.get("type", "InputEventKey")
	var new_event = null
	
	match type_name:
		"InputEventKey":
			new_event = InputEventKey.new()
			new_event.keycode = data.get("keycode", 0)
			new_event.physical_keycode = data.get("physical_keycode", 0)
			new_event.ctrl_pressed = data.get("ctrl", false)
			new_event.shift_pressed = data.get("shift", false)
			new_event.alt_pressed = data.get("alt", false)
			new_event.meta_pressed = data.get("meta", false)
		
		"InputEventMouseButton":
			new_event = InputEventMouseButton.new()
			new_event.button_index = data.get("button_index", MOUSE_BUTTON_LEFT)
			new_event.ctrl_pressed = data.get("ctrl", false)
			new_event.shift_pressed = data.get("shift", false)
		
		"InputEventJoypadButton":
			new_event = InputEventJoypadButton.new()
			new_event.button_index = data.get("button_index", 0)
			new_event.device = data.get("device", 0)
	
	if not new_event:
		return {"success": false, "error": "Tipo de InputEvent no soportado: " + type_name}
	return new_event
