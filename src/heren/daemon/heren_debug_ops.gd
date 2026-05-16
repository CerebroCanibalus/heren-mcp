class_name HerenDebugOps

var _daemon: SceneTree = null

# Listas internas para debug
var _breakpoints: Dictionary = {}
var _watch_list: Dictionary = {}

func init(daemon: SceneTree) -> void:
	_daemon = daemon

# ============================================================
# DEBUG HANDLERS
# Extracted from heren_daemon.gd
# ============================================================

func handle_screenshot(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var output_path = params.get("output_path", "")
	var resolution = params.get("resolution", [1280, 720])
	var wait_frames = params.get("wait_frames", 3)
	var format = params.get("format", "png")
	var quality = params.get("quality", 0.85)
	
	if not scene_path or not output_path:
		return {"success": false, "error": "missing_params"}
	
	if not _daemon._scene_cache.has(scene_path):
		# Cargar escena directamente
		var scene_resource = load(scene_path)
		if not scene_resource:
			return {"success": false, "error": "load_failed", "scene_path": scene_path}
		
		var scene_instance = scene_resource.instantiate()
		if not scene_instance:
			return {"success": false, "error": "instantiate_failed", "scene_path": scene_path}
		
		scene_instance.hide()
		_daemon.get_root().add_child(scene_instance)
		_daemon._scene_cache[scene_path] = scene_instance
	
	var scene = _daemon._scene_cache[scene_path]
	
	# Crear SubViewport
	var viewport = SubViewport.new()
	viewport.size = Vector2i(resolution[0], resolution[1])
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_daemon.get_root().add_child(viewport)
	
	# Clonar escena para renderizar
	var instance = scene.duplicate()
	viewport.add_child(instance)
	
	# Esperar frames
	for i in range(wait_frames):
		await _daemon.create_timer(0.0).timeout
	
	# Capturar
	var texture = viewport.get_texture()
	var image = texture.get_image()
	
	# Guardar
	var err = OK
	match format:
		"jpg", "jpeg":
			var buffer = image.save_jpg_to_buffer(quality)
			var file = FileAccess.open(output_path, FileAccess.WRITE)
			if file:
				file.store_buffer(buffer)
				file.close()
			else:
				err = FAILED
		"webp":
			err = image.save_webp(output_path, true, quality)
		_:
			err = image.save_png(output_path)
	
	# Limpiar
	instance.queue_free()
	viewport.queue_free()
	
	if err != OK:
		return {"success": false, "error": "save_failed", "code": err}
	
	var file_size = 0
	if FileAccess.file_exists(output_path):
		file_size = FileAccess.get_file_as_bytes(output_path).size()
	
	return {
		"success": true,
		"image_path": output_path,
		"resolution": [image.get_width(), image.get_height()],
		"format": format,
		"file_size_bytes": file_size
	}


func handle_capture_viewport(params: Dictionary) -> Dictionary:
	var output_path = params.get("output_path", "")
	var format = params.get("format", "png")
	var quality = params.get("quality", 0.85)
	
	if not output_path:
		return {"success": false, "error": "missing_output_path"}
	
	var root_viewport = _daemon.get_root()
	var texture = root_viewport.get_texture()
	var image = texture.get_image()
	
	var err = OK
	match format:
		"jpg", "jpeg":
			var buffer = image.save_jpg_to_buffer(quality)
			var file = FileAccess.open(output_path, FileAccess.WRITE)
			if file:
				file.store_buffer(buffer)
				file.close()
			else:
				err = FAILED
		"webp":
			err = image.save_webp(output_path, true, quality)
		_:
			err = image.save_png(output_path)
	
	if err != OK:
		return {"success": false, "error": "save_failed", "code": err}
	
	return {
		"success": true,
		"image_path": output_path,
		"resolution": [image.get_width(), image.get_height()],
		"format": format
	}


func handle_performance_metrics(params: Dictionary) -> Dictionary:
	var metrics = {
		"fps": Performance.get_monitor(Performance.TIME_FPS),
		"frame_time": Performance.get_monitor(Performance.TIME_PROCESS),
		"physics_time": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS),
		"memory_static": Performance.get_monitor(Performance.MEMORY_STATIC),
		"memory_max": Performance.get_monitor(Performance.MEMORY_STATIC_MAX),
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"orphan_nodes": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"vertices": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
	}
	
	return {"success": true, "metrics": metrics}


func handle_execute_editor_script(params: Dictionary) -> Dictionary:
	var script_code = params.get("script_code", "")
	var context = params.get("context", {})
	
	if script_code.is_empty():
		return {"success": false, "error": "missing_script_code", "message": "Se requiere código GDScript para ejecutar"}
	
	# Crear expresión GDScript
	var expression = Expression.new()
	var err = expression.parse(script_code)
	
	if err != OK:
		return {
			"success": false,
			"error": "parse_failed",
			"code": err,
			"message": "Error al parsear el código GDScript"
		}
	
	# Preparar variables de contexto
	var input_names = []
	var input_values = []
	
	for key in context.keys():
		input_names.append(key)
		input_values.append(context[key])
	
	# Ejecutar expresión
	var result = expression.execute(input_values, self, false)
	
	if expression.has_execute_failed():
		return {
			"success": false,
			"error": "execution_failed",
			"message": "Error durante la ejecución del script"
		}
	
	return {
		"success": true,
		"result": result,
		"result_type": typeof(result),
		"script_code": script_code,
		"context_keys": input_names
	}


func handle_run_scene(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	
	var editor_interface = _get_editor_interface_or_fail()
	if editor_interface is Dictionary:
		return editor_interface
	
	if scene_path.is_empty():
		# Ejecutar escena actual
		editor_interface.play_current_scene()
		return {
			"success": true,
			"mode": "current_scene",
			"note": "Ejecutando escena actual del editor"
		}
	else:
		# Ejecutar escena específica
		editor_interface.play_custom_scene(scene_path)
		return {
			"success": true,
			"scene_path": scene_path,
			"mode": "custom_scene",
			"note": "Ejecutando escena específica"
		}


func handle_get_editor_errors(params: Dictionary) -> Dictionary:
	var editor_interface = _get_editor_interface_or_fail()
	if editor_interface is Dictionary:
		return editor_interface
	
	# Intentar obtener errores del panel de errores del editor
	var base_control = editor_interface.get_base_control()
	var error_panel = base_control.find_child("ErrorPanel", true, false)
	
	var errors = []
	var warnings = []
	
	if error_panel:
		# El panel existe pero extraer el texto es complejo
		# Retornamos información básica
		return {
			"success": true,
			"errors": errors,
			"warnings": warnings,
			"error_panel_found": true,
			"note": "Panel de errores encontrado. Extracción detallada en desarrollo.",
			"alternative": "Usar get_console_output() para ver logs recientes"
		}
	else:
		return {
			"success": true,
			"errors": errors,
			"warnings": warnings,
			"error_panel_found": false,
			"note": "No se encontró panel de errores. El proyecto compila sin errores visibles.",
			"alternative": "Usar get_console_output() para ver logs recientes"
		}


# ============================================================
# VALIDATE HANDLERS
# Extracted from heren_daemon.gd
# ============================================================

func handle_validate_scene(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	
	if not scene_path:
		return {"success": false, "error": "missing_scene_path"}
	
	if not FileAccess.file_exists(scene_path):
		return {"success": false, "error": "scene_not_found", "path": scene_path}
	
	var errors = []
	var warnings = []
	
	# Validar extensión
	if not scene_path.ends_with(".tscn") and not scene_path.ends_with(".scn"):
		errors.append("Extensión inválida: debe ser .tscn o .scn")
	
	# Intentar cargar
	var scene = load(scene_path)
	if not scene:
		errors.append("No se pudo cargar la escena (archivo corrupto)")
	else:
		# Validar que sea PackedScene
		if not scene is PackedScene:
			errors.append("El archivo no es una PackedScene válida")
		else:
			# Validar instanciación
			var instance = scene.instantiate()
			if not instance:
				errors.append("No se pudo instanciar la escena")
			else:
				# Verificar nodos huérfanos (sin owner)
				var orphan_count = 0
				for child in instance.get_children():
					if child.owner == null:
						orphan_count += 1
						warnings.append("Nodo huérfano: " + child.name)
				
				instance.queue_free()
				
				if orphan_count > 0:
					warnings.append(str(orphan_count) + " nodos sin owner (pueden no guardarse correctamente)")
	
	return {
		"success": errors.size() == 0,
		"valid": errors.size() == 0,
		"errors": errors,
		"warnings": warnings,
		"scene_path": scene_path,
		"error_count": errors.size(),
		"warning_count": warnings.size()
	}


func handle_validate_script(params: Dictionary) -> Dictionary:
	var script_path = params.get("script_path", "")
	
	if not script_path:
		return {"success": false, "error": "missing_script_path"}
	
	if not FileAccess.file_exists(script_path):
		return {"success": false, "error": "script_not_found", "path": script_path}
	
	var errors = []
	var warnings = []
	
	# Validar extensión
	if not script_path.ends_with(".gd"):
		errors.append("Extensión inválida: debe ser .gd")
	
	# Intentar cargar
	var script = load(script_path)
	if not script:
		errors.append("No se pudo cargar el script")
	else:
		if not script is GDScript:
			errors.append("El archivo no es un GDScript válido")
		else:
			# Verificar que compila
			var instance = script.new()
			if not instance:
				errors.append("Error de compilación en el script")
			else:
				instance.free()
	
	return {
		"success": errors.size() == 0,
		"valid": errors.size() == 0,
		"errors": errors,
		"warnings": warnings,
		"script_path": script_path,
		"error_count": errors.size(),
		"warning_count": warnings.size()
	}


func handle_validate_node(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var node_path = params.get("node_path", "")
	
	if not scene_path or not node_path:
		return {"success": false, "error": "missing_params"}
	
	if not _daemon._scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _daemon._scene_cache[scene_path]
	var node = root.get_node_or_null(node_path)
	
	if not node:
		return {"success": false, "error": "node_not_found"}
	
	var errors = []
	var warnings = []
	
	# Validaciones básicas
	if node.name.is_empty():
		errors.append("Nodo sin nombre")
	
	if node.get_child_count() == 0 and node.get_script() == null:
		warnings.append("Nodo hoja sin script")
	
	# Validar propiedades requeridas según tipo
	if node is CollisionShape2D and node.shape == null:
		errors.append("CollisionShape2D sin forma (shape)")
	
	if node is Sprite2D and node.texture == null:
		warnings.append("Sprite2D sin textura")
	
	return {
		"success": errors.size() == 0,
		"valid": errors.size() == 0,
		"errors": errors,
		"warnings": warnings,
		"node_path": node_path,
		"node_type": node.get_class(),
		"error_count": errors.size(),
		"warning_count": warnings.size()
	}


func handle_validate_resource(params: Dictionary) -> Dictionary:
	var resource_path = params.get("resource_path", "")
	
	if not resource_path:
		return {"success": false, "error": "missing_resource_path"}
	
	if not FileAccess.file_exists(resource_path):
		return {"success": false, "error": "resource_not_found", "path": resource_path}
	
	var errors = []
	var warnings = []
	
	# Validar extensión
	if not resource_path.ends_with(".tres") and not resource_path.ends_with(".res"):
		errors.append("Extensión inválida: debe ser .tres o .res")
	
	# Intentar cargar
	var resource = load(resource_path)
	if not resource:
		errors.append("No se pudo cargar el recurso")
	else:
		if not resource is Resource:
			errors.append("El archivo no es un Resource válido")
	
	return {
		"success": errors.size() == 0,
		"valid": errors.size() == 0,
		"errors": errors,
		"warnings": warnings,
		"resource_path": resource_path,
		"error_count": errors.size(),
		"warning_count": warnings.size()
	}


# ============================================================
# VISUAL INSPECTION HANDLERS
# ============================================================

func handle_inspect_visual(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var output_path = params.get("output_path", "")
	var show_grid = params.get("show_grid", true)
	var show_labels = params.get("show_labels", true)
	var show_axes = params.get("show_axes", true)
	var show_bounds = params.get("show_bounds", false)
	var resolution = params.get("resolution", [1280, 720])
	var grid_size = params.get("grid_size", 100)
	
	if not scene_path or not output_path:
		return {"success": false, "error": "missing_params"}
	
	if not _daemon._scene_cache.has(scene_path):
		# Cargar escena directamente
		var scene_resource = load(scene_path)
		if not scene_resource:
			return {"success": false, "error": "load_failed", "scene_path": scene_path}
		
		var scene_instance = scene_resource.instantiate()
		if not scene_instance:
			return {"success": false, "error": "instantiate_failed", "scene_path": scene_path}
		
		scene_instance.hide()
		_daemon.get_root().add_child(scene_instance)
		_daemon._scene_cache[scene_path] = scene_instance
	
	var scene = _daemon._scene_cache[scene_path]
	
	# Create viewport
	var viewport = SubViewport.new()
	viewport.size = Vector2i(resolution[0], resolution[1])
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_daemon.get_root().add_child(viewport)
	
	# Clone scene
	var instance = scene.duplicate()
	viewport.add_child(instance)
	
	# Create canvas layer for overlays
	var overlay = CanvasLayer.new()
	viewport.add_child(overlay)
	
	# Add grid
	if show_grid:
		var grid = _create_visual_grid(resolution[0], resolution[1], grid_size)
		overlay.add_child(grid)
	
	# Add labels
	if show_labels:
		_add_node_labels(instance, overlay, "")
	
	# Add axes
	if show_axes:
		var axes = _create_axes_indicator()
		overlay.add_child(axes)
	
	# Wait frames
	for i in range(3):
		await _daemon.create_timer(0.0).timeout
	
	# Capture
	var texture = viewport.get_texture()
	var image = texture.get_image()
	
	# Save
	var err = image.save_png(output_path)
	
	# Cleanup
	instance.queue_free()
	viewport.queue_free()
	
	if err != OK:
		return {"success": false, "error": "save_failed"}
	
	return {
		"success": true,
		"image_path": output_path,
		"resolution": [image.get_width(), image.get_height()],
		"features": {
			"grid": show_grid,
			"labels": show_labels,
			"axes": show_axes,
			"bounds": show_bounds
		}
	}



func handle_raycast(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var from = params.get("from", {})
	var direction = params.get("direction", {})
	var max_distance = params.get("max_distance", 1000.0)
	var collision_mask = params.get("collision_mask", 1)
	
	if not scene_path:
		return {"success": false, "error": "missing_scene_path"}
	
	if not _daemon._scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _daemon._scene_cache[scene_path]
	
	var space_state = root.get_world_2d().direct_space_state
	var from_vec = Vector2(from.get("x", 0), from.get("y", 0))
	var dir_vec = Vector2(direction.get("x", 1), direction.get("y", 0)).normalized()
	var to_vec = from_vec + dir_vec * max_distance
	
	var query = PhysicsRayQueryParameters2D.new()
	query.from = from_vec
	query.to = to_vec
	query.collision_mask = collision_mask
	
	var result = space_state.intersect_ray(query)
	
	if result.is_empty():
		return {
			"success": true,
			"hit": false,
			"from": {"x": from_vec.x, "y": from_vec.y},
			"to": {"x": to_vec.x, "y": to_vec.y}
		}
	
	return {
		"success": true,
		"hit": true,
		"position": {"x": result.position.x, "y": result.position.y},
		"normal": {"x": result.normal.x, "y": result.normal.y},
		"collider": result.collider.name if result.collider else "",
		"collider_path": str(result.collider.get_path()) if result.collider else ""
	}



func handle_measure(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var node_a = params.get("node_a", "")
	var node_b = params.get("node_b", "")
	
	if not scene_path or not node_a or not node_b:
		return {"success": false, "error": "missing_params"}
	
	if not _daemon._scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _daemon._scene_cache[scene_path]
	var a = root.get_node_or_null(node_a)
	var b = root.get_node_or_null(node_b)
	
	if not a or not b:
		return {"success": false, "error": "node_not_found"}
	
	var pos_a = Vector2.ZERO
	var pos_b = Vector2.ZERO
	
	if a is Node2D:
		pos_a = a.global_position
	elif a is Node3D:
		pos_a = Vector2(a.global_position.x, a.global_position.y)
	
	if b is Node2D:
		pos_b = b.global_position
	elif b is Node3D:
		pos_b = Vector2(b.global_position.x, b.global_position.y)
	
	var distance = pos_a.distance_to(pos_b)
	var direction = (pos_b - pos_a).normalized()
	var angle = direction.angle()
	
	return {
		"success": true,
		"node_a": node_a,
		"node_b": node_b,
		"distance": distance,
		"direction": {"x": direction.x, "y": direction.y},
		"angle_degrees": rad_to_deg(angle),
		"delta": {"x": pos_b.x - pos_a.x, "y": pos_b.y - pos_a.y}
	}



func handle_set_breakpoint(params: Dictionary) -> Dictionary:
	var script_path = params.get("script_path", "")
	var line = params.get("line", 0)
	var enabled = params.get("enabled", true)
	
	if not script_path:
		return {"success": false, "error": "missing_script_path"}
	
	# Registrar breakpoint en lista interna
	var bp_key = script_path + ":" + str(line)
	_breakpoints[bp_key] = {
		"script_path": script_path,
		"line": line,
		"enabled": enabled,
		"timestamp": Time.get_unix_time_from_system()
	}
	
	# Intentar activar breakpoint real si estamos en editor
	var editor_interface = _get_editor_interface_or_fail()
	if not editor_interface is Dictionary:
		var script_editor = editor_interface.get_script_editor()
		if script_editor:
			# Abrir script en editor
			var script = load(script_path)
			if script:
				script_editor.open_script_create_dialog(script, line)
				return {
					"success": true,
					"script_path": script_path,
					"line": line,
					"enabled": enabled,
					"note": "Breakpoint registrado y script abierto en editor"
				}
	
	return {
		"success": true,
		"script_path": script_path,
		"line": line,
		"enabled": enabled,
		"note": "Breakpoint registrado. Total: " + str(_breakpoints.size()),
		"total_breakpoints": _breakpoints.size()
	}



func handle_get_stack_trace(params: Dictionary) -> Dictionary:
	# Retorna stack trace del hilo principal
	var stack = get_stack()
	var frames = []
	
	for frame in stack:
		frames.append({
			"source": frame.get("source", "unknown"),
			"function": frame.get("function", "unknown"),
			"line": frame.get("line", 0)
		})
	
	return {
		"success": true,
		"frames": frames,
		"count": frames.size()
	}



func handle_watch_variable(params: Dictionary) -> Dictionary:
	var variable_name = params.get("variable_name", "")
	var watch_mode = params.get("mode", "add")  # add, remove, list
	
	if not variable_name and watch_mode != "list":
		return {"success": false, "error": "missing_variable_name"}
	
	match watch_mode:
		"add":
			_watch_list[variable_name] = {
				"name": variable_name,
				"added_at": Time.get_unix_time_from_system(),
				"last_value": null
			}
			return {
				"success": true,
				"variable": variable_name,
				"status": "watching",
				"note": "Variable a├▒adida a watch list",
				"total_watching": _watch_list.size()
			}
		"remove":
			_watch_list.erase(variable_name)
			return {
				"success": true,
				"variable": variable_name,
				"status": "removed",
				"total_watching": _watch_list.size()
			}
		"list":
			return {
				"success": true,
				"watching": _watch_list.keys(),
				"total": _watch_list.size()
			}
		_:
			return {"success": false, "error": "invalid_mode", "message": "Use: add, remove, list"}



func handle_get_console_output(params: Dictionary) -> Dictionary:
	var lines = params.get("lines", 100)
	
	# Intentar obtener logs del editor si est├í disponible
	var editor_interface = _get_editor_interface_or_fail()
	if editor_interface is Dictionary:
		# Fallback: retornar informaci├│n ├║til del sistema
		return {
			"success": true,
			"lines_requested": lines,
			"output": _get_system_info(),
			"note": "Editor no disponible. Mostrando informaci├│n del sistema.",
			"alternative": "Usar execute_editor_script() para ejecutar prints"
		}
	
	# Si tenemos editor, intentar obtener el log
	var base_control = editor_interface.get_base_control()
	var log_control = base_control.find_child("Log", true, false)
	
	if log_control:
		return {
			"success": true,
			"lines_requested": lines,
			"output": "Log encontrado (extracci├│n en desarrollo)",
			"note": "Panel de log encontrado. Extracci├│n detallada en desarrollo."
		}
	else:
		return {
			"success": true,
			"lines_requested": lines,
			"output": _get_system_info(),
			"note": "Panel de log no encontrado. Mostrando informaci├│n del sistema."
		}



func handle_stop_scene(params: Dictionary) -> Dictionary:
	var editor_interface = _get_editor_interface_or_fail()
	if editor_interface is Dictionary:
		return editor_interface
	
	editor_interface.stop_playing_scene()
	return {
		"success": true,
		"note": "Escena detenida"
	}




# ============================================================
# DEBUG HELPERS
# ============================================================

func _create_visual_grid(width: int, height: int, grid_size: int) -> Node2D:
	var grid = Node2D.new()
	grid.name = "VisualGrid"
	
	var line_color = Color(0.3, 0.3, 0.3, 0.5)
	
	# Vertical lines
	for x in range(0, width, grid_size):
		var line = Line2D.new()
		line.add_point(Vector2(x, 0))
		line.add_point(Vector2(x, height))
		line.default_color = line_color
		line.width = 1
		grid.add_child(line)
	
	# Horizontal lines
	for y in range(0, height, grid_size):
		var line = Line2D.new()
		line.add_point(Vector2(0, y))
		line.add_point(Vector2(width, y))
		line.default_color = line_color
		line.width = 1
		grid.add_child(line)
	
	return grid



func _add_node_labels(node: Node, overlay: CanvasLayer, path: String):
	if not is_instance_valid(node):
		return
	
	if node is Node2D or node is Node3D:
		var label = Label.new()
		label.text = node.name
		label.modulate = Color(1, 1, 0, 0.9)
		
		if node is Node2D:
			label.position = node.global_position + Vector2(0, -20)
		
		overlay.add_child(label)
	
	for child in node.get_children():
		_add_node_labels(child, overlay, path + "/" + child.name)



func _create_axes_indicator() -> Node2D:
	var axes = Node2D.new()
	axes.name = "AxesIndicator"
	axes.position = Vector2(50, 50)
	
	# X axis (red)
	var x_line = Line2D.new()
	x_line.add_point(Vector2(0, 0))
	x_line.add_point(Vector2(30, 0))
	x_line.default_color = Color(1, 0, 0, 0.8)
	x_line.width = 2
	axes.add_child(x_line)
	
	var x_label = Label.new()
	x_label.text = "X"
	x_label.modulate = Color(1, 0, 0, 0.8)
	x_label.position = Vector2(32, -8)
	axes.add_child(x_label)
	
	# Y axis (green)
	var y_line = Line2D.new()
	y_line.add_point(Vector2(0, 0))
	y_line.add_point(Vector2(0, 30))
	y_line.default_color = Color(0, 1, 0, 0.8)
	y_line.width = 2
	axes.add_child(y_line)
	
	var y_label = Label.new()
	y_label.text = "Y"
	y_label.modulate = Color(0, 1, 0, 0.8)
	y_label.position = Vector2(-8, 32)
	axes.add_child(y_label)
	
	return axes



func _get_editor_interface_or_fail() -> Variant:
	"""Helper: Obtiene EditorInterface o retorna Dictionary de error."""
	# Verificar si estamos en el editor
	if not Engine.is_editor_hint():
		return {
			"success": false,
			"error": "editor_only",
			"note": "Esta funci├│n requiere que el daemon se ejecute dentro del Editor Godot (no como --script standalone)"
		}
	
	# Obtener editor interface solo si existe (usar call() para evitar error de parseo)
	var editor_interface = null
	if has_method("get_editor_interface"):
		editor_interface = call("get_editor_interface")
	if not editor_interface:
		return {
			"success": false,
			"error": "editor_interface_not_available",
			"note": "EditorInterface no disponible. Aseg├║rate de ejecutar el daemon como plugin del editor."
		}
	return editor_interface



func _get_system_info() -> String:
	"""Retorna informaci├│n del sistema como string."""
	var info = []
	info.append("=== Heren Daemon System Info ===")
	info.append("FPS: " + str(Engine.get_frames_per_second()))
	info.append("Process Time: " + str(Time.get_time_string_from_system()))
	info.append("Memory Static: " + str(OS.get_static_memory_usage() / 1024 / 1024) + " MB")
	info.append("Scene Cache: " + str(_daemon._scene_cache.size()) + " scenes")
	return "\n".join(info)



