class_name HerenShaderOps

var _daemon: SceneTree = null

func init(daemon: SceneTree) -> void:
	_daemon = daemon


# ============================================================
# SHADER HANDLERS
# Extracted from heren_daemon.gd
# ============================================================

func handle_create_shader(params: Dictionary) -> Dictionary:
	var shader_path = params.get("shader_path", "")
	var shader_type = params.get("shader_type", "canvas_item")
	var code = params.get("code", "")
	
	if not shader_path:
		return {"success": false, "error": "missing_shader_path"}
	
	if not shader_path.ends_with(".gdshader"):
		shader_path += ".gdshader"
	
	if FileAccess.file_exists(shader_path):
		return {"success": false, "error": "shader_exists"}
	
	# FIX: Detectar si el usuario ya incluyo shader_type
	var full_code = code
	if not code.strip_edges().begins_with("shader_type"):
		full_code = "shader_type " + shader_type + ";\n\n" + code
	
	var file = FileAccess.open(shader_path, FileAccess.WRITE)
	if not file:
		return {"success": false, "error": "write_failed"}
	
	file.store_string(full_code)
	file.close()
	
	return {
		"success": true,
		"shader_path": shader_path,
		"shader_type": shader_type
	}


func handle_edit_shader(params: Dictionary) -> Dictionary:
	var shader_path = params.get("shader_path", "")
	var code = params.get("code", "")
	var append = params.get("append", false)
	
	if not shader_path or not code:
		return {"success": false, "error": "missing_params"}
	
	if not FileAccess.file_exists(shader_path):
		return {"success": false, "error": "shader_not_found"}
	
	var existing = ""
	if append:
		var file = FileAccess.open(shader_path, FileAccess.READ)
		if file:
			existing = file.get_as_text()
			file.close()
	
	var file = FileAccess.open(shader_path, FileAccess.WRITE)
	if not file:
		return {"success": false, "error": "write_failed"}
	
	file.store_string(existing + code)
	file.close()
	
	return {
		"success": true,
		"shader_path": shader_path,
		"append": append
	}


func handle_validate_shader(params: Dictionary) -> Dictionary:
	var shader_path = params.get("shader_path", "")
	
	if not shader_path:
		return {"success": false, "error": "missing_shader_path"}
	
	if not FileAccess.file_exists(shader_path):
		return {"success": false, "error": "shader_not_found"}
	
	var shader = load(shader_path)
	if not shader or not shader is Shader:
		return {"success": false, "error": "invalid_shader"}
	
	return {
		"success": true,
		"shader_path": shader_path,
		"valid": true
	}


func handle_create_shader_material(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var node_path = params.get("node_path", "")
	var material_name = params.get("material_name", "")
	var shader_path = params.get("shader_path", "")
	var uniforms = params.get("uniforms", {})
	
	if not scene_path or not node_path:
		return {"success": false, "error": "missing_params"}
	
	if not _daemon._scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _daemon._scene_cache[scene_path]
	var node = root.get_node_or_null(node_path)
	
	if not node:
		return {"success": false, "error": "node_not_found"}
	
	var material = ShaderMaterial.new()
	if material_name:
		material.name = material_name
	
	if shader_path and ResourceLoader.exists(shader_path):
		material.shader = load(shader_path)
	
	for uniform_name in uniforms.keys():
		material.set_shader_parameter(uniform_name, _daemon._core_utils.deserialize_value(uniforms[uniform_name]))
	
	# B9 FIX: Asignar material correctamente a TODOS los tipos de nodos
	var material_assigned = false
	
	# CanvasItem (Node2D, Control, etc.): usar propiedad "material"
	if node.has_method("set_material"):
		node.set_material(material)
		material_assigned = true
	elif "material" in node:
		node.material = material
		material_assigned = true
	
	# MeshInstance3D: intentar surface_material_override_0
	if not material_assigned and node is MeshInstance3D:
		if node.get_surface_override_material_count() == 0:
			# Agregar primer surface material
			node.set_surface_override_material(0, material)
			material_assigned = true
		else:
			node.set_surface_override_material(0, material)
			material_assigned = true
	
	# GeometryInstance3D: material_override
	if not material_assigned and node.has_method("set_material_override"):
		node.set_material_override(material)
		material_assigned = true
	elif not material_assigned and "material_override" in node:
		node.material_override = material
		material_assigned = true
	
	# GeometryInstance3D: material_overlay
	if not material_assigned and node.has_method("set_material_overlay"):
		node.set_material_overlay(material)
		material_assigned = true
	elif not material_assigned and "material_overlay" in node:
		node.material_overlay = material
		material_assigned = true
	
	# Sprite2D, Sprite3D, etc: verificar texture que puede tener material
	if not material_assigned and "texture" in node:
		var texture = node.get("texture")
		if texture and texture is Texture2D:
			# No podemos asignar material a texture, pero el material se guarda en el nodo
			pass
	
	if not material_assigned:
		return {
			"success": false,
			"error": "material_assignment_failed",
			"message": "No se pudo asignar el material al nodo. Tipo de nodo: " + node.get_class()
		}
	
	return {
		"success": true,
		"node_path": node_path,
		"has_shader": shader_path != "",
		"material_assigned": material_assigned
	}


func handle_set_shader_uniform(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var node_path = params.get("node_path", "")
	var uniform_name = params.get("uniform_name", "")
	var value = params.get("value", null)
	
	if not scene_path or not node_path or not uniform_name:
		return {"success": false, "error": "missing_params"}
	
	if not _daemon._scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _daemon._scene_cache[scene_path]
	var node = root.get_node_or_null(node_path)
	
	if not node:
		return {"success": false, "error": "node_not_found"}
	
	var material = null
	
	# CanvasItem (2D nodes): material
	if "material" in node and node.material is ShaderMaterial:
		material = node.material
	
	# GeometryInstance3D (3D nodes): material_override
	if not material and "material_override" in node and node.material_override is ShaderMaterial:
		material = node.material_override
	
	# GeometryInstance3D: material_overlay
	if not material and "material_overlay" in node and node.material_overlay is ShaderMaterial:
		material = node.material_overlay
	
	# MeshInstance3D: surface_override_material per surface
	if not material and node is MeshInstance3D:
		for i in range(node.get_surface_override_material_count()):
			var surf_mat = node.get_surface_override_material(i)
			if surf_mat is ShaderMaterial:
				material = surf_mat
				break
	
	if not material:
		return {"success": false, "error": "no_shader_material", "message": "No se encontró ShaderMaterial en el nodo. Verifica que tenga asignado un material con shader."}
	
	material.set_shader_parameter(uniform_name, _daemon._core_utils.deserialize_value(value))
	
	return {
		"success": true,
		"uniform": uniform_name,
		"node_path": node_path
	}
